echo "Repair gnome-keyring plaintext keyring files that gnome-keyring 50 rejects"

# gnome-keyring writes textual secrets with g_key_file_set_value(), which does
# not escape newlines (GLib docs: set_value is for values with no escapable
# characters; set_string must be used otherwise). A secret containing a raw
# newline (JSON with embedded PEM blocks, multi-line tokens) produces a
# keyring file the daemon cannot parse again. On the next start it logs
#   keyring was in an invalid or unrecognized format
# and silently drops the collection, creating a fresh empty default. Browsers
# lose Safe Storage and every saved login appears wiped.
#
# The reader (GKeyFile) does unescape standard sequences, so affected files can
# be repaired in place by escaping the multi-line value. Repaired files are
# backed up first.
#
# Why the repair below is unambiguous (ground truth, not heuristics):
# gkm-secret-textual.c writes each item group with generate_item() in a fixed
# call order: item-type, display-name, secret (or binary-secret), mtime,
# ctime; mtime/ctime are unconditional. g_key_file_to_data() serializes keys
# in insertion order (glib/gkeyfile.c iterates the prepend-built key list in
# reverse), so the file order IS the writer call order. Crucially, secret is
# the ONLY field written with the unescaped g_key_file_set_value(); every
# other field uses g_key_file_set_string/_integer/_boolean, which cannot emit
# raw newlines (binary-secret is hex: single line by construction).
#
# Therefore, in a writer-produced file, an item group's last two key=value
# lines are always the genuine mtime and ctime, and every line between the
# first "secret=" line and those two lines is secret content -- even lines
# shaped like "mtime=...", "display-name=...", or "secret=...". No guesswork:
# a content line can never be mistaken for a field boundary.
#
# Fail-closed rule: anything that does not match this writer invariant is left
# byte-identical and reported, never "repaired":
#   - a corrupt group that is not an item group (the writer cannot produce
#     multi-line values there),
#   - an item group whose last two key=value lines are not mtime=/ctime=,
#   - an item group with no "secret=" line, or a genuine binary-secret field,
#   - any other corruption the writer could not have produced.
# Automatic migration is therefore safe: it only ever rewrites files whose
# repair is uniquely determined, byte-exact after parse. Files it cannot
# prove safe are named in the output for explicit, human-supervised recovery.

keyrings_dir="$HOME/.local/share/keyrings"

[[ -d $keyrings_dir ]] || exit 0
command -v python3 >/dev/null || exit 0

python3 - "$keyrings_dir" <<'PY'
import re
import shutil
import sys
import time
from pathlib import Path

SECTION = re.compile(rb"^\[[^\]]+\]$")
KV = re.compile(rb"^[A-Za-z0-9_-]+=")
ITEM_SECTION = re.compile(rb"^\[\d+\]$")


def is_item_section(header):
    return bool(ITEM_SECTION.match(header))


def group_is_corrupt(lines):
    return any(line != b"" and not KV.match(line) for line in lines)


def escape(value):
    out = value.replace(b"\\", b"\\\\")
    out = out.replace(b"\r", b"\\r")
    out = out.replace(b"\n", b"\\n")
    out = out.replace(b"\t", b"\\t")
    return out


def repair_item_group(lines):
    """Repair one corrupt [N] item group, or return None to fail closed.

    Writer invariant (gkm-secret-textual.c generate_item + GKeyFile insertion
    order): the group's last two key=value lines are the genuine mtime and
    ctime; the first "secret=" line opens the only field that may span lines.
    Everything between is secret content, whatever shape it has.
    """
    kv_idx = [i for i, line in enumerate(lines) if KV.match(line)]
    secret_at = [i for i in kv_idx if lines[i].startswith(b"secret=")]
    if not secret_at or len(kv_idx) < 3:
        return None
    s = secret_at[0]
    mtime_i, ctime_i = kv_idx[-2], kv_idx[-1]
    if not lines[mtime_i].startswith(b"mtime="):
        return None
    if not lines[ctime_i].startswith(b"ctime="):
        return None
    if mtime_i < s:
        return None
    for i in kv_idx:
        # A genuine binary-secret field means the secret was hex (single
        # line); a multi-line secret alongside it is not writer-produced.
        # binary-secret= lines inside the secret span are just content.
        if i < s and lines[i].startswith(b"binary-secret="):
            return None
    # The prefix (writer-emitted single-line fields) must be intact: the
    # writer cannot produce a broken line before the secret.
    for line in lines[:s]:
        if line != b"" and not KV.match(line):
            return None
    # Nothing but blank lines may follow the genuine ctime.
    for line in lines[ctime_i + 1:]:
        if line != b"":
            return None
    content = [lines[s].split(b"=", 1)[1]] + lines[s + 1:mtime_i]
    return (lines[:s] + [b"secret=" + escape(b"\n".join(content))]
            + lines[mtime_i:])


def split_groups(raw):
    groups = []
    header, glines = None, []
    for line in raw.split(b"\n"):
        if SECTION.match(line):
            if header is not None:
                groups.append((header, glines))
            header, glines = line, []
        elif header is None:
            if line != b"":
                return None
        else:
            glines.append(line)
    if header is not None:
        groups.append((header, glines))
    return groups


def repair(raw):
    groups = split_groups(raw)
    if groups is None:
        return None

    changed = False
    fixed_groups = []
    for header, glines in groups:
        if not group_is_corrupt(glines):
            fixed_groups.append((header, glines))
            continue
        # Only item groups can hold a writer-produced multi-line value.
        # Anything else corrupt is failed closed: guessing the split could
        # silently change bytes the writer could never have produced.
        if not is_item_section(header):
            return None
        fixed = repair_item_group(glines)
        if fixed is None:
            return None
        changed = True
        fixed_groups.append((header, fixed))

    if not changed:
        return None
    out = []
    for header, glines in fixed_groups:
        out.append(header)
        out.extend(glines)
    fixed = b"\n".join(out)
    # The repaired file must parse clean; otherwise fail closed.
    for line in fixed.split(b"\n"):
        if SECTION.match(line) or line == b"" or KV.match(line):
            continue
        return None
    return fixed


keyrings = Path(sys.argv[1])
backups = keyrings / f"backup-{time.strftime('%Y%m%d-%H%M%S')}"
checked = repaired = failed = 0

for path in sorted(keyrings.glob("*.keyring")):
    raw = path.read_bytes()
    if not raw.startswith(b"[keyring]"):
        continue
    groups = split_groups(raw)
    if groups is None:
        continue
    if not any(group_is_corrupt(gl) for _, gl in groups):
        continue
    checked += 1
    fixed = repair(raw)
    if fixed is None:
        print(f"  could not repair {path.name}; left untouched")
        failed += 1
        continue
    backups.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, backups / path.name)
    path.write_bytes(fixed)
    print(f"  repaired {path.name} (backup in {backups.name}/)")
    repaired += 1

if checked == 0:
    print("  no affected keyring files found")
print(f"  summary: corrupt={checked} repaired={repaired} failed={failed}")
if failed:
    print("  ambiguous files were left byte-identical; recover them explicitly")
    print("  (inspect the file, split the secret by hand, then re-run)")
sys.exit(0)
PY

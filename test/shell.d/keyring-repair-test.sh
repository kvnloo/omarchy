#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command python3

migration="$ROOT/migrations/1790383800.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
keyrings="$home/.local/share/keyrings"
mkdir -p "$keyrings"

run_migration() {
  HOME="$home" bash -euo pipefail "$migration"
}

export FIXDIR="$test_dir/fixtures"
mkdir -p "$FIXDIR"
cat >"$test_dir/gen.py" <<'PYEOF'
import base64, sys
from pathlib import Path

fixdir = Path(sys.argv[1])
kind = sys.argv[2]

ITEM_TOKENS = [b"item-type", b"display-name", b"secret", b"binary-secret",
               b"mtime", b"ctime"]

def write(name, text):
    (fixdir / name).write_bytes(text)

def item_group(secret_lines, extra_prefix=(), extra_suffix=()):
    lines = [b"[1]", b"item-type=0", b"display-name=login"]
    lines += list(extra_prefix)
    lines.append(b"secret=" + secret_lines[0])
    lines += secret_lines[1:]
    lines += [b"mtime=1700000001", b"ctime=1700000001"]
    lines += list(extra_suffix)
    return lines

def keyring_group():
    return [b"[keyring]", b"display-name=default", b"ctime=1700000000",
            b"mtime=1700000000"]

def build(name, groups):
    lines = []
    for g in groups:
        lines += g
    write(name, b"\n".join(lines) + b"\n")

if kind == "plain":
    secret = (b'{"token":"abc",\n"pem":"-----BEGIN RSA PRIVATE KEY-----\n'
              b'MIIB\n-----END RSA PRIVATE KEY-----"}')
    build("plain.keyring", [keyring_group(),
                            item_group(secret.split(b"\n"))])
    print(base64.b64encode(secret).decode())
elif kind == "adv-item":
    # Secret content lines begin with EVERY valid key token of the item
    # group, including hostile mtime=/ctime= lines planted immediately
    # before the genuine trailing mtime/ctime. The writer-invariant repair
    # (genuine mtime/ctime are positionally last) must still recover the
    # secret byte-for-byte instead of mistaking content for fields.
    secret = [b"head"]
    secret += [t + b"=injected-" + t for t in ITEM_TOKENS]
    secret += [b"mtime=evil-tail", b"ctime=evil-tail", b"tail"]
    raw_secret = b"\n".join(secret)
    build("adv-item.keyring", [keyring_group(), item_group(secret)])
    print(base64.b64encode(raw_secret).decode())
elif kind == "unknownkey":
    secret = b"line1\nx-custom=1\nfoo=bar\nline2"
    build("unknownkey.keyring", [keyring_group(),
                                 item_group(secret.split(b"\n"))])
    print(base64.b64encode(secret).decode())
elif kind == "two-items":
    secret = b"multi\nline\nsecret"
    build("two-items.keyring", [keyring_group(),
                                item_group(secret.split(b"\n")),
                                [b"[2]", b"item-type=0", b"display-name=other",
                                 b"secret=safe", b"mtime=3", b"ctime=3"]])
    print(base64.b64encode(secret).decode())
elif kind == "fail-truncated":
    # Item group does not end with the writer's mtime/ctime pair: not
    # writer-produced, must fail closed.
    secret = b"aaa\nbbb"
    lines = [b"[1]", b"item-type=0", b"secret=" + secret.replace(b"\n", b"\n")]
    build("fail-truncated.keyring", [keyring_group(), lines])
    print("")
elif kind == "fail-binary":
    # Genuine binary-secret field plus a broken line: the writer hex-encodes
    # binary secrets (single line), so this is not writer-produced.
    lines = [b"[1]", b"item-type=0", b"binary-secret=deadbeef",
             b"broken line", b"mtime=1", b"ctime=1"]
    build("fail-binary.keyring", [keyring_group(), lines])
    print("")
elif kind == "fail-display":
    # Corruption before the secret field: the writer cannot produce a broken
    # line in its single-line prefix fields.
    lines = [b"[1]", b"item-type=0", b"display-name=foo", b"broken line",
             b"secret=abc", b"mtime=1", b"ctime=1"]
    build("fail-display.keyring", [keyring_group(), lines])
    print("")
elif kind == "fail-keyring":
    # Corrupt [keyring] group: the writer escapes every field there, so a
    # multi-line value is not writer-produced.
    lines = [b"[keyring]", b"display-name=one", b"two", b"ctime=1", b"mtime=1",
             b"[1]", b"item-type=0", b"secret=ok", b"mtime=2", b"ctime=2"]
    build("fail-keyring.keyring", [lines])
    print("")
elif kind == "valid":
    build("valid.keyring", [keyring_group(),
                            [b"[1]", b"item-type=0", b"display-name=x",
                             b"secret=plain", b"mtime=2", b"ctime=2"]])
    print("")
PYEOF

# Strict GKeyFile-style value reader for repaired files: single-line
# key=value pairs, standard unescape, returned raw for byte comparison.
read_secret() {
  python3 - "$1" "$2" "$3" <<'PYEOF'
import sys
path, section, key = sys.argv[1], sys.argv[2].encode(), sys.argv[3].encode()
cur = None
for line in open(path, "rb").read().split(b"\n"):
    if line.startswith(b"[") and line.endswith(b"]"):
        cur = line[1:-1]
        continue
    if cur == section and line.startswith(key + b"="):
        v = line[len(key) + 1:]
        v = v.replace(b"\\\\", b"\x00").replace(b"\\n", b"\n").replace(b"\\r", b"\r").replace(b"\\t", b"\t").replace(b"\x00", b"\\")
        sys.stdout.buffer.write(v)
        sys.exit(0)
sys.exit("value not found")
PYEOF
}

gen() {
  python3 "$test_dir/gen.py" "$FIXDIR" "$1"
}

check_repaired_byte_exact() { # <name> <orig_b64> <section>
  local name="$1" orig_b64="$2" section="$3"
  local out
  out=$(run_migration)
  echo "$out" | grep -q "repaired $name" || { fail "$name is repaired" "$out"; }
  local recovered_b64
  recovered_b64=$(read_secret "$keyrings/$name" "$section" secret | base64 -w0)
  [[ "$recovered_b64" == "$orig_b64" ]] || \
    fail "$name secret is byte-identical after parse" "orig=$orig_b64 got=$recovered_b64"
  pass "$name is repaired byte-for-byte"
}

check_fail_closed() { # <name>
  local name="$1"
  local before out
  before=$(sha256sum "$keyrings/$name" | cut -d' ' -f1)
  out=$(run_migration)
  echo "$out" | grep -q "could not repair $name; left untouched" || \
    fail "$name fails closed" "$out"
  [[ $(sha256sum "$keyrings/$name" | cut -d' ' -f1) == "$before" ]] || \
    fail "$name left byte-identical" ""
  [[ ! -d "$keyrings"/backup-* ]] || fail "$name writes no backup on failure" ""
  echo "$out" | grep -q "failed=1" || fail "$name counted as failed" "$out"
  pass "$name fails closed: untouched, no backup, reported"
}

reset_keyrings() {
  rm -rf "$keyrings"
  mkdir -p "$keyrings"
}

# --- plain multiline secret: repaired byte-for-byte, backed up, then no-op ---
reset_keyrings
orig_b64=$(gen plain)
cp "$FIXDIR/plain.keyring" "$keyrings/"
before=$(sha256sum "$keyrings/plain.keyring" | cut -d' ' -f1)
check_repaired_byte_exact plain.keyring "$orig_b64" 1
backup=$(ls -d "$keyrings"/backup-*)
[[ -f "$backup/plain.keyring" ]] || fail "backup written before repair" ""
[[ $(sha256sum "$backup/plain.keyring" | cut -d' ' -f1) == "$before" ]] || \
  fail "backup holds original bytes" ""
pass "backup-before-write preserves original bytes"
out=$(run_migration)
echo "$out" | grep -q "no affected keyring files found" || fail "second run is a no-op" "$out"
[[ $(ls -d "$keyrings"/backup-* | wc -l) == 1 ]] || fail "second run writes no new backup" ""
pass "second run is a no-op"

# --- adversarial content: every item key token inside the secret ---
reset_keyrings
orig_b64=$(gen adv-item)
cp "$FIXDIR/adv-item.keyring" "$keyrings/"
check_repaired_byte_exact adv-item.keyring "$orig_b64" 1

# --- unknown key tokens in secret are content (writer never emits them) ---
reset_keyrings
orig_b64=$(gen unknownkey)
cp "$FIXDIR/unknownkey.keyring" "$keyrings/"
check_repaired_byte_exact unknownkey.keyring "$orig_b64" 1

# --- two items: only the corrupt one is touched ---
reset_keyrings
orig_b64=$(gen two-items)
cp "$FIXDIR/two-items.keyring" "$keyrings/"
check_repaired_byte_exact two-items.keyring "$orig_b64" 1
[[ $(read_secret "$keyrings/two-items.keyring" 2 secret) == "safe" ]] || \
  fail "valid sibling item untouched" ""
pass "valid sibling item untouched"

# --- not-writer-produced files fail closed ---
for kind in fail-truncated fail-binary fail-display fail-keyring; do
  reset_keyrings
  gen "$kind" >/dev/null
  cp "$FIXDIR/$kind.keyring" "$keyrings/"
  check_fail_closed "$kind.keyring"
done

# --- valid file is a no-op ---
reset_keyrings
gen valid >/dev/null
cp "$FIXDIR/valid.keyring" "$keyrings/"
out=$(run_migration)
echo "$out" | grep -q "no affected keyring files found" || fail "valid file is a no-op" "$out"
[[ ! -d "$keyrings"/backup-* ]] || fail "valid file writes no backup" ""
pass "valid file is a no-op"

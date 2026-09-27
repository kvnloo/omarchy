#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command python3
require_command curl
require_command file

# An icon URL is saved as <name>.png and referenced from the .desktop file by
# that name, so only an actual image may land there: without -f curl exits 0
# on an HTTP error and saves the error page, and without a content check an
# HTML page lands as a broken icon with no error at all.

TMPDIR=$(mktemp -d)
trap 'kill "$SERVER_PID" 2>/dev/null; rm -rf "$TMPDIR"' EXIT

STUB_DIR="$TMPDIR/stub"
mkdir -p "$STUB_DIR"
printf '#!/bin/bash\nexit 0\n' >"$STUB_DIR/gtk-update-icon-cache"
chmod +x "$STUB_DIR/gtk-update-icon-cache"

# Fixtures: a real 1x1 PNG and a minimal JPEG.
python3 - <<'PY' "$TMPDIR"
import os, struct, sys, zlib
d = os.path.join(sys.argv[1], "serve")
os.makedirs(d, exist_ok=True)
def chunk(t, data):
    c = t + data
    return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(b"\x00\x00\x00\x00")) + chunk(b"IEND", b"")
open(os.path.join(d, "real.png"), "wb").write(png)
open(os.path.join(d, "photo.jpg"), "wb").write(
    bytes.fromhex("ffd8ffe000104a46494600010100000100010000ffdb004300") + b"\x08" * 64 +
    bytes.fromhex("ffc2000b080001000101011100ffc40014000100000000000000000000000000000000"
                  "ffc40014100100000000000000000000000000000000ffda0008010100003f00d2cf20ffd9"))
PY

PORT=18931
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$TMPDIR/serve" >/dev/null 2>&1 &
SERVER_PID=$!
sleep 1

install() {
  local name="$1" url="$2"
  HOME="$TMPDIR/home-$name" PATH="$STUB_DIR:$PATH" \
    "$ROOT/bin/omarchy-tui-install" "$name" "true" "tile" "$url" >/dev/null 2>&1
  echo $?
}

icon_path() {
  printf '%s' "$TMPDIR/home-$1/.local/share/icons/hicolor/256x256/apps/$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^[:alnum:]]\+/-/g; s/^-//; s/-$//').png"
}

# A real PNG installs as before.
status=$(install "Png App" "http://127.0.0.1:$PORT/real.png")
[[ $status == 0 ]] || fail "a real PNG icon URL installs successfully (exit $status)"
icon=$(icon_path "Png App")
[[ -f $icon ]] || fail "a real PNG icon URL leaves the icon file behind"
[[ $(file -b --mime-type "$icon") == "image/png" ]] || fail "a real PNG icon URL is stored as PNG"
pass "a real PNG icon URL installs as a PNG"

# A JPEG is an image too: any image/* installs, since icon lookup resolves by
# name rather than extension. Only non-images are refused.
status=$(install "Jpg App" "http://127.0.0.1:$PORT/photo.jpg")
[[ $status == 0 ]] || fail "a JPEG icon URL installs successfully (exit $status)"
icon=$(icon_path "Jpg App")
[[ -f $icon ]] || fail "a JPEG icon URL leaves the icon file behind"
[[ $(file -b --mime-type "$icon") == image/* ]] || fail "a JPEG icon URL is stored as an image"
pass "a JPEG served as an icon URL installs as an image"

# A 200 response with HTML content is not an icon either.
printf '<html><body>not an icon</body></html>\n' >"$TMPDIR/serve/not-an-icon"
status=$(install "Html App" "http://127.0.0.1:$PORT/not-an-icon")
[[ $status != 0 ]] || fail "an HTML icon URL is refused (exit $status)"
[[ ! -e $(icon_path "Html App") ]] || fail "a refused HTML icon URL leaves no icon file behind"
pass "an HTML page served as an icon URL is refused without a broken icon file"

# An HTTP error must not be saved as the icon either.
output=$(HOME="$TMPDIR/home-MissingApp" PATH="$STUB_DIR:$PATH" \
  "$ROOT/bin/omarchy-tui-install" "Missing App" "true" "tile" "http://127.0.0.1:$PORT/does-not-exist" 2>&1)
status=$?
[[ $status != 0 ]] || fail "a 404 icon URL is refused (exit $status)"
[[ $output == *"does-not-exist"* ]] || fail "a 404 icon URL names the failing URL" "$output"
[[ ! -e $(icon_path "Missing App") ]] || fail "a 404 icon URL leaves no icon file behind"
pass "an HTTP error icon URL fails loudly instead of saving the error page"

# Local file icons keep working: the URL branch is the only one that changed.
cp "$TMPDIR/serve/real.png" "$TMPDIR/local-icon.png"
status=$(HOME="$TMPDIR/home-Local App" PATH="$STUB_DIR:$PATH" \
  "$ROOT/bin/omarchy-tui-install" "Local App" "true" "tile" "$TMPDIR/local-icon.png" >/dev/null 2>&1; echo $?)
[[ $status == 0 ]] || fail "a local icon file still installs (exit $status)"
[[ -f $(icon_path "Local App") ]] || fail "a local icon file still leaves the icon behind"
pass "a local icon file still installs unchanged"

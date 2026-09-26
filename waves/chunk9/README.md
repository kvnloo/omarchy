# [muse] chunk 9 — router metadata cache

`bin/omarchy`: `load_commands()` now caches the serialized registration state
(`declare -p` of the 19 registration arrays) at
`${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/router-metadata-v1.sh` and sources it
on a hit instead of re-scanning 458 binaries.

## Measured

- `commands --check` end-to-end: median ~3450ms -> ~800ms (6 interleaved runs
  vs pristine base on a loaded box; steady-state hit ~350ms). `load_commands`
  alone: 3835ms -> ~350ms in-harness.
- Hot path (`omarchy <cmd>`) never calls `load_commands`, so it is unaffected.
- `commands --json --all` on a cache hit is byte-identical (md5) to pristine.
- `commands --check` passes: "Command metadata check passed (458 commands)".

## Invalidation contract (all verified)

- `find "$OMARCHY_BIN_DIR" -newer "$cache_file"`: add, remove, chmod, and
  content edits each trigger MISS + rescan; steady state hits.
- The cache records `OMARCHY_ROUTER_CACHE_BIN_DIR`; a different install dir
  sharing one XDG cache rescans once, then hits.
- Corrupt/malformed cache -> fall through to rescan (source failure is fenced
  by the bindir-stamp check and the non-empty `COMMAND_KEYS` guard).
- Atomic write via tmp-file + rename; cache write failures are silent no-ops
  (best-effort: a failed cache never breaks registration).

## Design tradeoffs (maintainer decisions)

- **Cache location** (`$XDG_CACHE_HOME/omarchy/router-metadata-v1.sh`) and the
  `router-metadata-v1` stamp format are baked in; bumping
  `ROUTER_METADATA_CACHE_VERSION` invalidates all caches.
- **`find -newer` is strict-greater-than** at ns granularity: a file modified in
  the exact timestamp as the cache write would slip. Negligible in practice.
- **First run after any bin/ change pays the full scan**; cache file is ~350KB.
- **Trust boundary**: the cache is per-user under the user's own XDG cache dir
  and is sourced; a cache written by another user is not trusted by design.
- Three prototype bugs were found and fixed during development (noted here so
  they don't regress): (1) bindir-stamp compared before assignment -> perpetual
  miss; (2) `declare -g-a` errors when read from a file on bash 5.2 ->
  use `-ga`/`-gA`; (3) failed-source + rescan compounded `COMMAND_KEYS`
  458 -> 1832 -> scan path now resets all 19 arrays first, which also makes
  `load_commands` idempotent (pristine router is not).

## Scope note

Best-effort cache only. No behavior change when the cache is absent, stale, or
corrupt. `write_router_metadata_cache` never fails the registration path.

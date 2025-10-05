#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${FRONTIER_ZIG_CI_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)}"

if [[ ! -f "$ROOT_DIR/justfile" ]]; then
  printf 'Unable to locate project root (missing justfile in %s)\n' "$ROOT_DIR" >&2
  exit 1
fi

cd "$ROOT_DIR"

run_step() {
  local description="$1"
  shift
  printf '\n=== %s ===\n' "$description"
  "$@"
}

tmp_prefix="${FRONTIER_ZIG_CI_PREFIX:-"$(mktemp -d "${TMPDIR:-/tmp}/frontier-zig-prefix.XXXXXX")"}"
export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-${TMPDIR:-/tmp}/zig-global-cache}"
export ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-${TMPDIR:-/tmp}/zig-local-cache}"

run_step "Checking formatting" zig fmt --check zig
run_step "Building project" zig build --build-file zig/build.zig --prefix "$tmp_prefix"
run_step "Running tests" zig build test --build-file zig/build.zig

printf '\nCI pipeline completed successfully.\n'

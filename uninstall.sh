#!/usr/bin/env sh
# =============================================================================
#  Pretense CLI: Uninstaller
#  Usage: curl -fsSL https://www.pretense.ai/uninstall.sh | sh
#
#  Runs the CLI's own uninstall order, nothing else:
#    1. pretense start --uninstall               (stops and removes the always-on proxy)
#    2. pretense start --shell-setup --remove    (removes the shell lines Pretense added)
#    3. npm rm -g @pretense/cli                  (removes the npm package)
#
#  It prints each step, deletes no user files beyond what steps 1 and 2 do, and
#  exits non-zero if any step fails. It is safe to run twice.
#
#  TRUNCATION GUARD: every statement lives in a function and the only top-level
#  call is `main "$@"` on the last line, so a dropped `curl | sh` transfer
#  defines functions and exits without running anything. Keep it POSIX (sh -n).
# =============================================================================
set -u

FAILED=0

say()  { printf '%s\n' "$1"; }
fail() { printf 'FAILED: %s\n' "$1" >&2; FAILED=1; }

run_step() {
  # run_step <n> <label> <command...>
  _n="$1"; _label="$2"; shift 2
  say "Step ${_n} of 3: ${_label}"
  say "  \$ $*"
  if "$@"; then
    say "  done"
  else
    fail "step ${_n} (${_label}) exited non-zero"
  fi
}

skip_step() {
  say "Step $1 of 3: $2"
  say "  skipped: $3"
}

main() {
  say "Pretense uninstall"

  _bin="${PRETENSE_INSTALL_DIR:-$HOME/.local/bin}/pretense"
  _cli=$(command -v pretense 2>/dev/null || true)
  if [ -z "$_cli" ] && [ -x "$_bin" ]; then _cli="$_bin"; fi

  if [ -z "$_cli" ]; then
    skip_step 1 "stop and remove the always-on proxy" "pretense is not installed, nothing to stop"
    skip_step 2 "remove the shell setup lines" "pretense is not installed, nothing to remove"
  elif "$_cli" start --help 2>/dev/null | grep -q -e '--uninstall'; then
    run_step 1 "stop and remove the always-on proxy" "$_cli" start --uninstall
    run_step 2 "remove the shell setup lines" "$_cli" start --shell-setup --remove
  else
    skip_step 1 "stop and remove the always-on proxy" "this pretense version has no always-on service (added in 0.6.88)"
    skip_step 2 "remove the shell setup lines" "this pretense version writes no shell setup lines"
  fi

  if command -v npm >/dev/null 2>&1; then
    run_step 3 "remove the npm package" npm rm -g @pretense/cli
  else
    skip_step 3 "remove the npm package" "npm is not on your PATH"
  fi

  if [ "$FAILED" -ne 0 ]; then
    say "Pretense uninstall finished with errors. See the FAILED lines above."
    return 1
  fi
  if [ -e "$_bin" ]; then
    say "The proxy service and the npm package are removed. The curl installer's binary stays at ${_bin}."
    say "  Remove it with: rm ${_bin}"
    return 0
  fi
  say "Pretense is uninstalled. Open a new terminal to refresh your PATH."
  return 0
}

main "$@"

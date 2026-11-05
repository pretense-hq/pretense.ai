#!/usr/bin/env sh
set -e
# NOTE: `set -e` only. `set -euo pipefail` is a BASHISM — /bin/sh is dash on
# Ubuntu and `set -o pipefail` aborts there, which would break every Debian and
# Ubuntu CI runner. Keep this script strictly POSIX; verify with `sh -n`.

# =============================================================================
#  Pretense CLI — Installer
#  Usage: curl -fsSL https://www.pretense.ai/install.sh | sh
#
#  Copy that command EXACTLY:
#    -f  refuse HTTP errors instead of piping an error page into your shell
#    -L  follow redirects instead of piping the redirect body into your shell
#    -S  still show the error when -s silences progress
#    https://www.  the canonical host — zero redirect hops
#
# -----------------------------------------------------------------------------
#  INCIDENT: "Redirecting...: command not found"  (2026-07-21)
# -----------------------------------------------------------------------------
#  The site shipped `curl -s pretense.ai/install | sh` on its homepage. That  [install-lint-ok: incident quote]
#  URL takes TWO redirect hops (http->https 308, apex->www 307) before it
#  reaches this file. Without -L, curl does not follow them: it prints the
#  redirect's 15-byte body, the literal text "Redirecting...", and the pipe
#  fed that straight to sh:
#
#      sh: line 1: Redirecting...: command not found     (exit 127)
#
#  Harmless noise that day. But piping an unfollowed, unverified HTTP body into
#  a shell is precisely the curl|sh supply-chain shape: had any host in that
#  chain returned attacker-controlled bytes, sh would have run them.
#
#  TRUNCATION GUARD — DO NOT "SIMPLIFY" THIS AWAY.
#  Every executable statement in this file lives inside a function, and the
#  ONLY top-level invocation is `main "$@"` on the VERY LAST LINE. That is
#  deliberate. `curl | sh` streams (install-lint-ok: prose, not a command):
#  sh executes each complete top-level command
#  as it arrives, so a connection dropped mid-transfer in a flat script runs
#  half an installer — downloading a binary, or chmod+mv-ing a partial file,
#  and then dying. With this layout a truncated download can only ever define
#  some functions and reach EOF: sh exits without installing anything.
#
#  Consequently:
#    * Do NOT move logic out of a function to "make it readable".
#    * Do NOT add any top-level statement after `main "$@"`.
#    * `main "$@"` MUST remain the final line of this file.
#  Regression coverage: pretense-dashboard/scripts/test-install-truncation.sh
# =============================================================================

# --- Configuration -----------------------------------------------------------
BASE_URL="https://www.pretense.ai"
# Release binaries stay off the public Pages repo; they are served by the app origin.
RELEASES_URL="https://app.pretense.ai"
# Must match the published artifact filenames exactly or every download 404s.
# As of v0.6.1 the release workflow emits `pretense-*`; older 0.4.x artifacts
# were named `pretest-*` and have been removed.
REMOTE_BINARY_NAME="pretense"
# The installed command is `pretense` — this is what docs and npm both use.
BINARY_NAME="pretense"
INSTALL_DIR="${PRETENSE_INSTALL_DIR:-$HOME/.local/bin}"

# --- Helpers -----------------------------------------------------------------
BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

info()    { printf "${CYAN}  →${RESET}  %s\n" "$1"; }
success() { printf "${GREEN}  ✓${RESET}  %s\n" "$1"; }
warn()    { printf "${YELLOW}  ⚠${RESET}  %s\n" "$1"; }
# error() renders with %b, not %s, ON PURPOSE. Every fail-closed message below
# is multi-line — "…(likely a soft-404 or an error page).\nRefusing to install."
# — and %s prints those escapes LITERALLY, so the refusal and the remedy landed
# on one run-on line with a visible "\n" in the middle of the sentence that is
# supposed to stop someone from installing a tampered binary. %b expands the
# escapes in the ARGUMENT (POSIX; dash-safe). The message text is unchanged:
# this fixes how it prints, not what it says.
error()   { printf "${RED}  ✗${RESET}  %b\n" "$1" >&2; exit 1; }
banner()  { printf "\n${BOLD}  Pretense CLI Installer${RESET}\n  AI firewall for dev teams — pretense.ai\n\n"; }

# --- Detect OS ---------------------------------------------------------------
detect_os() {
  case "$(uname -s)" in
    Linux*)  echo "linux" ;;
    Darwin*) echo "darwin" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) error "Unsupported OS: $(uname -s). Install manually: npm install -g @pretense/cli" ;;
  esac
}

# --- Detect Architecture -----------------------------------------------------
detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) error "Unsupported architecture: $(uname -m). Install manually: npm install -g @pretense/cli" ;;
  esac
}

# --- Check for required tools ------------------------------------------------
#
# THIS FAILS CLOSED ON A MISSING HASH TOOL. It used to warn() and set
# SKIP_CHECKSUM=1 by itself, which silently turned "this machine cannot verify
# anything" into "verification was skipped, carry on" — the exact fail-open
# shape the checksum block in main() exists to eliminate, reached without the
# operator ever asking for it. Demonstrated, not theorised: run with sha256sum
# and shasum removed from PATH, against a server whose binary does NOT match its
# SHA256SUMS, the tampered binary was installed and the script exited 0 — the
# manifest was never even fetched.
#
# The two states are not the same and must never be collapsed:
#   * SKIP_CHECKSUM=1 exported by the operator — a deliberate, informed
#     override. Unchanged: it still installs, still warns loudly.
#   * no hash tool on the machine — nobody chose anything. Hard error naming
#     the missing dependency and the verified alternative.
# Regression coverage: pretense-dashboard/scripts/test-install-checksum.mjs
check_deps() {
  if ! command -v curl >/dev/null 2>&1; then
    error "curl is required but not installed."
  fi
  if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    if [ "${SKIP_CHECKSUM:-0}" = "1" ]; then
      warn "No sha256sum/shasum found, and SKIP_CHECKSUM=1 is set."
      warn "Nothing about this download will be verified."
    else
      error "Cannot verify this download: neither sha256sum nor shasum is installed.\nRefusing to install an unverified binary. Install one of them (coreutils or perl), or install manually: npm install -g @pretense/cli"
    fi
  fi
}

# --- Verify SHA256 checksum --------------------------------------------------
verify_checksum() {
  file="$1"
  expected="$2"

  if [ "${SKIP_CHECKSUM:-0}" = "1" ]; then
    return 0
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$file" | awk '{print $1}')
  else
    actual=$(shasum -a 256 "$file" | awk '{print $1}')
  fi

  if [ "$actual" != "$expected" ]; then
    error "Checksum mismatch.\n  Expected: $expected\n  Got:      $actual\n  Delete $file and try again."
  fi
}

# --- Ensure install dir is on PATH -------------------------------------------
ensure_on_path() {
  dir="$1"
  case ":$PATH:" in
    *":$dir:"*) return 0 ;;
  esac

  warn "$dir is not in your PATH."

  shell_rc=""
  if [ -n "$ZSH_VERSION" ] || [ "$(basename "${SHELL:-}")" = "zsh" ]; then
    shell_rc="$HOME/.zshrc"
  elif [ -n "$BASH_VERSION" ] || [ "$(basename "${SHELL:-}")" = "bash" ]; then
    shell_rc="$HOME/.bashrc"
    [ -f "$HOME/.bash_profile" ] && shell_rc="$HOME/.bash_profile"
  fi

  if [ -n "$shell_rc" ]; then
    printf '\nexport PATH="%s:$PATH"\n' "$dir" >> "$shell_rc"
    info "Added $dir to PATH in $shell_rc"
    info "Run: source $shell_rc  (or open a new terminal)"
  else
    warn "Add this to your shell config manually:"
    printf '    export PATH="%s:$PATH"\n\n' "$dir"
  fi
}

# --- Prefer npm when available -----------------------------------------------
# The npm package tracks the `latest` dist-tag, so `npm i -g @pretense/cli`
# always installs the newest release with ZERO version-drift between channels
# (this is why the curl-installer used to lag npm by several versions). The
# standalone binary below stays as the fallback for machines without Node.
# Escape hatch: set PRETENSE_INSTALL_METHOD=binary to force the binary path.
try_npm_install() {
  [ "${PRETENSE_INSTALL_METHOD:-}" = "binary" ] && return 1
  command -v npm >/dev/null 2>&1 || return 1
  command -v node >/dev/null 2>&1 || return 1
  info "Node + npm detected — installing the always-latest npm package..."
  if npm install -g @pretense/cli >/dev/null 2>&1; then
    installed=$(pretense --version 2>/dev/null || echo "")
    if [ -n "$installed" ]; then
      success "Installed @pretense/cli ${installed} via npm"
      printf "\n${BOLD}  Quick start:${RESET}\n    ${BINARY_NAME} run claude\n\n"
      return 0
    fi
  fi
  warn "npm install did not complete; falling back to the standalone binary."
  return 1
}

# --- Downgrade guard ---------------------------------------------------------
#
# WHY THIS EXISTS. The binary fallback below ends in an unconditional
# `mv "$TMP_BIN" "${INSTALL_DIR}/${BINARY_NAME}"`. It never looked at what was
# already there, so it would happily write an OLDER pretense over a NEWER one.
#
# That is not hypothetical. On 2026-08-13 npm's `latest` dist-tag was 0.6.52
# while ${BASE_URL}/releases/latest/version.txt still said 0.6.40, because the
# release workflow's publish-cdn job was failing and had been for days. The two
# channels drift independently, so "the CDN is older than what you have" is the
# NORMAL state during a CDN outage, not an edge case.
#
# And the older build does not merely sit alongside the newer one. The default
# INSTALL_DIR ($HOME/.local/bin) precedes nvm's shim directory on a typical
# PATH, so the CDN binary SHADOWS an npm install: `pretense --version` silently
# starts answering with the older number and nothing announces the move.
#
# The consequence is a security regression, not a cosmetic one. 0.6.40 predates
# egress-detector fixes that later releases carry — its shipped engine misses
# GitHub `ghu_`/`gho_`/`ghr_` tokens and both engines miss Slack `xoxe-` and
# `xapp-` tokens. Secrets the current release MUTATES at egress travel
# UN-MUTATED on that build. Moving a user backwards onto it without a word is
# the worst thing this installer can do, so it now refuses.
#
# Escape hatch: PRETENSE_ALLOW_DOWNGRADE=1, for deliberate, informed pinning.
# Note the guard deliberately does NOT gate the npm path above: npm installs the
# `latest` dist-tag, which cannot be a downgrade.

# Print the semver a pretense binary reports, or nothing at all.
# NEVER fails the script: a binary that will not run simply does not get a vote
# in the comparison. Refusing to install because we could not interrogate some
# unrelated file on the PATH would be its own kind of fail-closed bug.
probe_version() {
  _pv_bin="$1"
  [ -n "$_pv_bin" ] || return 0
  _pv_out=$("$_pv_bin" --version 2>/dev/null) || return 0
  # First x.y.z on the first line. Tolerates a leading `v` and any suffix, so
  # "pretense 0.6.52 (darwin-arm64)" and "v0.6.52" both reduce to 0.6.52.
  printf '%s\n' "$_pv_out" | head -n 1 |
    sed -n 's/^[^0-9]*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*$/\1/p'
}

# True when $1 is a strictly newer semver than $2.
#
# Compares each field NUMERICALLY. A string comparison would be actively
# dangerous here: `[ "0.6.9" \> "0.6.40" ]` is true lexically, so a lexical
# guard would rank 0.6.9 above 0.6.40 and wave real downgrades straight
# through — the guard would look present and do nothing.
version_gt() {
  _a="$1"
  _b="$2"
  [ -n "$_a" ] && [ -n "$_b" ] || return 1
  for _i in 1 2 3; do
    _x=$(printf '%s' "$_a" | cut -d. -f"$_i")
    _y=$(printf '%s' "$_b" | cut -d. -f"$_i")
    # Drop any pre-release/build suffix so `9.9.9-test` compares as 9.9.9.
    _x=${_x%%[!0-9]*}
    _y=${_y%%[!0-9]*}
    [ -n "$_x" ] || _x=0
    [ -n "$_y" ] || _y=0
    if [ "$_x" -gt "$_y" ]; then return 0; fi
    if [ "$_x" -lt "$_y" ]; then return 1; fi
  done
  # Equal is NOT newer. Reinstalling the version you already have is allowed;
  # it is a repair, not a downgrade.
  return 1
}

# Refuse to overwrite a newer pretense with an older one.
check_downgrade() {
  _offered="$1"
  [ "${PRETENSE_ALLOW_DOWNGRADE:-0}" = "1" ] && return 0

  # Consider BOTH the pretense the user actually runs (PATH order decides that,
  # and INSTALL_DIR commonly outranks nvm) and the exact file we are about to
  # clobber. Either one can be the newer build that would be lost, and they are
  # frequently not the same file.
  _current=""
  _cur_path=""
  for _cand in "$(command -v "$BINARY_NAME" 2>/dev/null || true)" "${INSTALL_DIR}/${BINARY_NAME}"; do
    [ -n "$_cand" ] || continue
    [ -x "$_cand" ] || continue
    _got=$(probe_version "$_cand")
    [ -n "$_got" ] || continue
    if [ -z "$_current" ] || version_gt "$_got" "$_current"; then
      _current="$_got"
      _cur_path="$_cand"
    fi
  done

  # Nothing installed, or nothing that would answer --version: fresh install.
  [ -n "$_current" ] || return 0

  if version_gt "$_current" "$_offered"; then
    error "Refusing to downgrade ${BINARY_NAME}.\n  Installed: ${_current}  (${_cur_path})\n  Offered:   ${_offered}  (${BASE_URL}/releases/latest/version.txt)\n\n  The release CDN is serving an OLDER build than the one you already have.\n  Installing it would overwrite ${_cur_path}, and because ${INSTALL_DIR}\n  usually precedes npm/nvm on your PATH it would silently become the\n  ${BINARY_NAME} you run — on a build with weaker egress detectors.\n\n  Keeping ${_current}. For the newest release:  npm install -g @pretense/cli\n  To install ${_offered} anyway:                PRETENSE_ALLOW_DOWNGRADE=1"
  fi
}

# =============================================================================
#  Main
# =============================================================================
# ─── API key persistence (ported from the pretense-repo installer) ────────────
#
# WHY THIS LIVES HERE NOW: the two install.sh copies had diverged in OPPOSITE
# directions. This one (served live, tested by scripts/test-install-checksum.mjs)
# carries the fail-closed checksum verification. The pretense-repo copy carried
# PRETENSE_API_KEY handling and no checksum verification at all. Syncing either
# way would have destroyed something: deploying the repo copy removes checksum
# verification (a supply-chain regression), while "syncing forward" to this one
# deletes key support. So the key handling is ported IN, and this file is the
# single source of truth.
#
# PREFIXES CORRECTED. The old copy validated `ptns_org_` / `ptns_live_` /
# `ptns_test_`, but the dashboard issues `prtns_live_` / `prtns_test_` — note
# `prtns`, not `ptns`. Every legitimate key therefore tripped the "does not match
# expected prefix" warning. Prefixes here match cli/src/commands/auth.ts exactly.
#
# The key is persisted, never transmitted by this script. @pretense/cli's
# postinstall reads it and asks the backend for a signed licence; entitlement is
# decided server-side and enforced by signature verification in the proxy. A key
# written here grants nothing on its own.
save_api_key() {
  KEY="${PRETENSE_API_KEY:-${PRETENSE_ORG_TOKEN:-${PRETENSE_LICENSE_KEY:-}}}"
  [ -z "$KEY" ] && return 0

  case "$KEY" in
    prtns_live_*|prtns_test_*|pt-free-*|pt-pro-*|pt-ent-*) ;;
    *) warn "API key does not match a known prefix. Saving anyway." ;;
  esac

  CONFIG_DIR="${HOME}/.pretense"
  mkdir -p "$CONFIG_DIR" || { warn "Could not create ${CONFIG_DIR}; skipping key save."; return 0; }
  # 0600 before writing, so the key is never briefly world-readable.
  ( umask 077; printf '{\n  "api_key": "%s",\n  "authenticated_at": "%s"\n}\n' \
      "$KEY" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${CONFIG_DIR}/credentials.json" ) 2>/dev/null \
    || { warn "Could not write credentials; run 'pretense auth login' later."; return 0; }
  chmod 600 "${CONFIG_DIR}/credentials.json" 2>/dev/null || true
  success "API key saved to ${CONFIG_DIR}/credentials.json"
}

main() {
  banner

  # Persist the key BEFORE either install path, because the npm branch exits 0
  # immediately on success and would otherwise skip this entirely.
  save_api_key

  # Channel-unification: npm first (always latest), binary as fallback.
  if try_npm_install; then
    exit 0
  fi

  check_deps

  OS=$(detect_os)
  ARCH=$(detect_arch)

  # Windows: recommend npm instead
  if [ "$OS" = "windows" ]; then
    info "Windows detected. Install via npm:"
    printf "\n    npm install -g @pretense/cli\n\n"
    exit 0
  fi

  info "Detected: ${OS}/${ARCH}"

  # Fetch latest version
  info "Fetching latest version..."
  VERSION=$(curl -fsSL "${BASE_URL}/releases/latest/version.txt" 2>/dev/null | tr -d '[:space:]')
  if [ -z "$VERSION" ]; then
    error "Could not fetch latest version from ${BASE_URL}/releases/latest/version.txt"
  fi
  info "Latest version: ${VERSION}"

  # Stop BEFORE downloading anything if the CDN is offering us a step backwards.
  # Placed here, not next to the `mv`, so a refused downgrade costs no bandwidth
  # and cannot leave a half-installed state behind.
  check_downgrade "$VERSION"

  # Build download URLs
  #
  # ── ONE MAPPING, MIRRORING scripts/build-binaries.sh TARGETS (TASK-737) ──────
  # This read `${REMOTE_BINARY_NAME}-${OS}-${ARCH}`, which yields
  # "pretense-windows-x64" on git-bash/MSYS/Cygwin. The published Windows asset
  # is "pretense-win-x64.exe" — a different stem AND an extension — so every
  # Windows `curl | sh` install 404'd on the download step. Verified against the
  # CDN: pretense-windows-x64.exe -> 404, pretense-win-x64.exe -> 200.
  #
  # The comment at the top of this file already said "must match the published
  # artifact filenames exactly or every download 404s". It was right; the code
  # did not honour it. Windows is the ONLY platform whose published name differs
  # from ${OS}-${ARCH}, so it is the only special case here.
  case "$OS" in
    windows) BINARY_FILE="${REMOTE_BINARY_NAME}-win-${ARCH}.exe" ;;
    *)       BINARY_FILE="${REMOTE_BINARY_NAME}-${OS}-${ARCH}" ;;
  esac
  DOWNLOAD_URL="${RELEASES_URL}/releases/${VERSION}/${BINARY_FILE}"
  CHECKSUM_URL="${BASE_URL}/releases/${VERSION}/SHA256SUMS"

  # Download binary
  TMP_DIR=$(mktemp -d)
  TMP_BIN="${TMP_DIR}/${BINARY_FILE}"
  TMP_SUMS="${TMP_DIR}/SHA256SUMS"

  info "Downloading ${BINARY_FILE} ${VERSION}..."
  if ! curl -fsSL --progress-bar -o "$TMP_BIN" "$DOWNLOAD_URL"; then
    error "Download failed: ${DOWNLOAD_URL}\nCheck that version ${VERSION} has a release for ${OS}/${ARCH}."
  fi

  # Download and verify checksum.
  #
  # THIS BLOCK FAILS CLOSED. It used to fail OPEN, and that was a live
  # supply-chain vulnerability: every branch that could not produce a checksum
  # merely warn()ed and fell through to `chmod +x` + `mv`. Demonstrated by
  # serving an HTML page as SHA256SUMS with status 200 — a 39-byte HTML file
  # was installed as the `pretense` executable and the script exited 0.
  #
  # A soft-404 is the realistic attack and the realistic accident: this domain
  # has already served the login page with status 200 for missing assets, so
  # `curl -f` succeeding proves nothing about WHAT came back. Anyone able to
  # interpose on the checksum response could therefore ship an arbitrary
  # binary. For a security product whose entire pitch is that secrets never
  # leave the machine, silently installing unverified bytes is the worst
  # possible default.
  #
  # Rule: no verified checksum, no install. The only way past this is an
  # explicit, deliberate SKIP_CHECKSUM=1 from the operator.
  if [ "${SKIP_CHECKSUM:-0}" = "1" ]; then
    warn "SKIP_CHECKSUM=1 — installing WITHOUT verifying the download."
    warn "You are trusting the network. Do not use this on a shared machine."
  else
    if ! curl -fsSL -o "$TMP_SUMS" "$CHECKSUM_URL" 2>/dev/null; then
      rm -rf "$TMP_DIR"
      error "Could not fetch SHA256SUMS from ${CHECKSUM_URL}\nRefusing to install an unverified binary. Retry, or set SKIP_CHECKSUM=1 to override."
    fi

    # Reject a soft-404 before parsing. A checksum manifest is lines of
    # "<64 hex>  <filename>"; an HTML error page is not, and grepping it for a
    # filename yields an empty EXPECTED that used to be treated as "no entry,
    # carry on".
    if ! grep -Eq '^[0-9a-fA-F]{64}[[:space:]]' "$TMP_SUMS"; then
      rm -rf "$TMP_DIR"
      error "SHA256SUMS at ${CHECKSUM_URL} is not a checksum manifest (likely a soft-404 or an error page).\nRefusing to install."
    fi

    # Anchor the filename match. An unanchored grep for "pretense-linux-x64"
    # also matches "pretense-linux-x64.exe" and any longer name, so the wrong
    # line's hash could be selected.
    EXPECTED=$(awk -v f="$BINARY_FILE" '$2 == f || $2 == "*" f { print $1; exit }' "$TMP_SUMS")
    if [ -z "$EXPECTED" ]; then
      rm -rf "$TMP_DIR"
      error "No checksum entry for ${BINARY_FILE} in SHA256SUMS.\nThis release may be incomplete. Refusing to install an unverified binary."
    fi

    info "Verifying checksum..."
    verify_checksum "$TMP_BIN" "$EXPECTED"
    success "Checksum verified"
  fi

  # Install binary
  mkdir -p "$INSTALL_DIR"
  chmod +x "$TMP_BIN"
  mv "$TMP_BIN" "${INSTALL_DIR}/${BINARY_NAME}"
  rm -rf "$TMP_DIR"

  success "Installed ${BINARY_NAME} ${VERSION} → ${INSTALL_DIR}/${BINARY_NAME}"

  # PATH check
  ensure_on_path "$INSTALL_DIR"

  # Verify THE BINARY WE JUST INSTALLED, by absolute path.
  #
  # This used to run `command -v "$BINARY_NAME"`, which resolves against $PATH
  # — so a DIFFERENT, pre-existing pretense earlier on the PATH would answer,
  # and the script would print "Installation complete (v0.6.9)" over an install
  # that had in fact just written a corrupt file somewhere else. A success
  # banner sourced from a different binary than the one installed is exactly
  # the class of green-that-means-nothing this project keeps getting bitten by.
  #
  # Also: the CLI exposes `--version`, NOT a `version` subcommand, so the old
  # call always failed and the banner always said "unknown" — the version in
  # the success line was never real.
  INSTALLED_BIN="${INSTALL_DIR}/${BINARY_NAME}"
  if [ -x "$INSTALLED_BIN" ] && INSTALLED_VERSION=$("$INSTALLED_BIN" --version 2>/dev/null); then
    success "Installation complete  (${INSTALLED_VERSION})"
  else
    rm -f "$INSTALLED_BIN"
    error "Installed binary at ${INSTALLED_BIN} did not run.\nIt has been removed rather than left in place. Please report this with your OS and architecture."
  fi

  if ! command -v "$BINARY_NAME" >/dev/null 2>&1; then
    info "Restart your terminal or run: export PATH=\"${INSTALL_DIR}:\$PATH\""
  fi

  printf "\n${BOLD}  Quick start:${RESET}\n"
  printf "    export ANTHROPIC_BASE_URL=http://localhost:9339\n"
  printf "    ${BINARY_NAME} start --verbose\n\n"
}

# -----------------------------------------------------------------------------
# TRUNCATION GUARD: this is the one and only top-level invocation, and it must
# stay the LAST LINE of the file. See the incident note at the top before
# touching it. A partially downloaded copy of this script reaches EOF without
# ever getting here, and therefore installs nothing.
# -----------------------------------------------------------------------------
main "$@"
# =============================================================================
#  Pretense CLI Installer for Windows
#  Usage: irm https://www.pretense.ai/install.ps1 | iex
#
#  Use the canonical https://www. host: it is zero redirect hops. The apex
#  (pretense.ai) redirects to www at the edge, and the POSIX twin of this
#  script shipped an install line that piped that redirect's body -- the
#  literal text "Redirecting..." -- straight into a shell. See the incident
#  note in install.sh (2026-07-21).
#
#  TRUNCATION GUARD -- DO NOT "SIMPLIFY" THIS AWAY.
#  Every executable statement lives inside Invoke-PretenseInstall, and the ONLY
#  top-level invocation is the call on the VERY LAST LINE. `irm | iex` on a
#  connection that drops mid-transfer yields a partial script; if that script
#  were flat, PowerShell would happily execute whatever complete statements
#  arrived -- fetching a version, downloading a binary, or copying a partial
#  file onto PATH -- and then stop. With this layout a truncated download can
#  only ever define a function that is never called, so it installs nothing.
#
#  Consequently:
#    * Do NOT move logic out of the function to "make it readable".
#    * Do NOT add any top-level statement after the final call.
#    * The Invoke-PretenseInstall call MUST remain the last line of this file.
#  Regression coverage: pretense-dashboard/scripts/test-install-truncation.sh
# =============================================================================

$ErrorActionPreference = "Stop"

# NOTE ON THE TRUNCATION GUARD: the helpers below are function DEFINITIONS, not
# executable statements, so they preserve the invariant described above — a
# partial download can still only ever define functions and reach EOF. The sole
# top-level invocation remains the final line of the file.

# --- Prefer npm when available -----------------------------------------------
#
# WHY THIS WAS ADDED. This script had NO npm path at all: it went straight to
# ${BaseUrl}/releases/latest/version.txt and installed whatever the CDN was
# serving. Its POSIX twin has preferred npm since "fix(install): prefer npm
# (always-latest) with binary fallback", so Windows was the only platform with
# no route to the current release — and on 2026-08-13 that meant
# `irm https://www.pretense.ai/install.ps1 | iex` installed 0.6.40 while npm's
# `latest` was 0.6.52, because the release workflow's publish-cdn job was
# failing. Windows users could not escape the stale CDN by any documented route.
#
# The npm package tracks the `latest` dist-tag, so it cannot lag. The standalone
# binary below stays as the fallback for machines without Node.
# Escape hatch: PRETENSE_INSTALL_METHOD=binary forces the binary path.
function Install-PretenseViaNpm {
  if ($env:PRETENSE_INSTALL_METHOD -eq "binary") { return $false }

  # -CommandType Application on purpose: we want a real npm/node executable,
  # never a same-named alias or function from the user's profile.
  $Npm  = Get-Command npm  -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  $Node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $Npm -or -not $Node) { return $false }

  Write-Host "  -> Node + npm detected, installing the always-latest npm package..."

  # '@pretense/cli' MUST stay quoted. A bare @pretense/cli is PowerShell's
  # splat operator applied to $pretense, not a string, so the package name
  # would silently become something else entirely.
  #
  # stdout stays quiet; stderr is kept and SHOWN when npm fails. It used to be
  # piped to Out-Null with stdout, so a failed install printed no reason at all.
  # ErrorActionPreference is relaxed for this call only: under "Stop", Windows
  # PowerShell 5.1 turns the first native stderr line into a terminating error.
  $script:PretenseNpmFailed = $true
  $NpmOut = $null
  $NpmExit = 1
  $PrevEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $NpmOut = & $Npm.Source install -g '@pretense/cli' 2>&1
    $NpmExit = $LASTEXITCODE
  } catch {
    $NpmOut = @($_)
    $NpmExit = 1
  } finally {
    $ErrorActionPreference = $PrevEap
  }
  if ($NpmExit -ne 0) {
    Write-Host "  WARN  npm install -g @pretense/cli failed. npm said:"
    foreach ($Line in @($NpmOut)) {
      if ($Line -is [System.Management.Automation.ErrorRecord]) {
        [Console]::Error.WriteLine("    " + $Line.ToString())
      }
    }
    Write-Host "  WARN  npm install did not complete; falling back to the standalone binary."
    return $false
  }

  # Confirm the package actually produced a runnable command before claiming
  # success — mirrors the POSIX twin, which treats an unverifiable npm install
  # as a failure and falls through to the binary.
  $Cmd = Get-Command pretense -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  $Installed = $null
  if ($Cmd) {
    try { $Installed = (& $Cmd.Source --version 2>$null | Select-Object -First 1) } catch { $Installed = $null }
  }
  if (-not $Installed) {
    Write-Host "  WARN  npm did not produce a runnable CLI; falling back to the standalone binary."
    return $false
  }

  $script:PretenseNpmFailed = $false
  Write-Host "  OK  Installed @pretense/cli $Installed via npm"
  Write-PretenseQuickStart
  return $true
}

# --- Next steps ----------------------------------------------------------------
# The three commands a new user runs next, printed as the LAST lines of every
# successful install (npm and binary paths alike). Mirrors install.sh.
# `start --install` first shipped in 0.6.89; a binary below the floor does not
# have it, so that install prints plain `start`.
function Write-PretenseQuickStart {
  param([bool]$OldBinary = $false)
  Write-Host ""
  if ($OldBinary) {
    Write-Host "  For the always-on version (start --install), run: npm i -g @pretense/cli"
    Write-Host ""
  }
  Write-Host "  Quick start:"
  Write-Host "    pretense login"
  if ($OldBinary) {
    Write-Host "    pretense start"
  } else {
    Write-Host "    pretense start --install"
  }
  Write-Host "    pretense status"
  Write-Host ""
}

# --- Downgrade guard ---------------------------------------------------------
#
# WHY THIS EXISTS. The install below is an unconditional `Copy-Item -Force` over
# whatever pretense.exe already exists, and it never looked at the version it
# was replacing. Combined with a CDN that can lag npm by a dozen releases (see
# above), that is a silent-downgrade path onto a build with weaker egress
# detectors: 0.6.40 misses Slack `xoxe-`/`xapp-` tokens and, in the engine the
# standalone binary ships, GitHub `ghu_`/`gho_`/`ghr_` tokens. Secrets the
# current release MUTATES at egress travel UN-MUTATED there.
#
# Escape hatch: PRETENSE_ALLOW_DOWNGRADE=1, for deliberate, informed pinning.

# The semver a pretense binary reports, or $null. Never throws: a binary that
# will not run simply does not get a vote in the comparison.
function Get-PretenseVersion {
  param([string]$Exe)
  if (-not $Exe) { return $null }
  $Out = $null
  try { $Out = & $Exe --version 2>$null | Select-Object -First 1 } catch { return $null }
  if (-not $Out) { return $null }
  # Tolerates "0.6.52", "v0.6.52" and "pretense 0.6.52 (win-x64)".
  $M = [regex]::Match([string]$Out, '(\d+)\.(\d+)\.(\d+)')
  if (-not $M.Success) { return $null }
  return $M.Value
}

# True when $A is a strictly newer semver than $B.
#
# Field-by-field NUMERIC comparison. A [string] compare would rank "0.6.9" above
# "0.6.40" and wave real downgrades through; a [version] cast would throw on a
# pre-release tag like "9.9.9-test". Equal is NOT newer, so reinstalling the
# version you already have stays allowed.
function Test-PretenseVersionNewer {
  param([string]$A, [string]$B)
  if (-not $A -or -not $B) { return $false }
  $MA = [regex]::Match($A, '(\d+)\.(\d+)\.(\d+)')
  $MB = [regex]::Match($B, '(\d+)\.(\d+)\.(\d+)')
  if (-not $MA.Success -or -not $MB.Success) { return $false }
  for ($i = 1; $i -le 3; $i++) {
    $X = [int]$MA.Groups[$i].Value
    $Y = [int]$MB.Groups[$i].Value
    if ($X -gt $Y) { return $true }
    if ($X -lt $Y) { return $false }
  }
  return $false
}

# Refuse to overwrite a newer pretense with an older one.
function Assert-PretenseNoDowngrade {
  param([string]$Offered, [string]$InstallDir, [string]$BinaryName, [string]$BaseUrl)
  if ($env:PRETENSE_ALLOW_DOWNGRADE -eq "1") { return }

  # Consider BOTH the pretense the user actually runs (PATH order decides that)
  # and the exact file we are about to overwrite. They are frequently different
  # files, and either can be the newer build that would be lost.
  $Candidates = @()
  $OnPath = Get-Command $BinaryName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($OnPath) { $Candidates += $OnPath.Source }
  $Dest = Join-Path $InstallDir $BinaryName
  if (Test-Path $Dest) { $Candidates += $Dest }

  $Current = $null
  $CurrentPath = $null
  foreach ($Cand in $Candidates) {
    $Got = Get-PretenseVersion $Cand
    if (-not $Got) { continue }
    if ((-not $Current) -or (Test-PretenseVersionNewer $Got $Current)) {
      $Current = $Got
      $CurrentPath = $Cand
    }
  }

  # Nothing installed, or nothing that answers --version: fresh install.
  if (-not $Current) { return }

  if (Test-PretenseVersionNewer $Current $Offered) {
    throw (
      "Refusing to downgrade $BinaryName.`n" +
      "  Installed: $Current  ($CurrentPath)`n" +
      "  Offered:   $Offered  ($BaseUrl/releases/latest/version.txt)`n`n" +
      "  The release CDN is serving an OLDER build than the one you already have.`n" +
      "  Installing it would overwrite $CurrentPath on a build with weaker egress`n" +
      "  detectors.`n`n" +
      "  Keeping $Current. For the newest release:  npm install -g @pretense/cli`n" +
      "  To install $Offered anyway:                set PRETENSE_ALLOW_DOWNGRADE=1"
    )
  }
}

# --- Binary channel floor --------------------------------------------------------
# The standalone binary is published separately from npm and can lag it: on
# 2026-11-13 releases/latest/version.txt said 0.6.79 while npm latest was
# 0.6.89. Below this floor the binary is never installed silently:
#   * Node present and not forced to binary: refuse the binary and point at npm.
#   * No Node (or PRETENSE_INSTALL_METHOD=binary): say plainly that the binary
#     is older and how to get Node, then continue.
# The downgrade guard and checksum verification still apply either way.
# Returns $true when the offered binary is below the floor (and was allowed).
function Test-PretenseBinaryFloor {
  param([string]$Offered, [string]$MinVersion)
  if (-not (Test-PretenseVersionNewer $MinVersion $Offered)) { return $false }
  $Node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($env:PRETENSE_INSTALL_METHOD -ne "binary" -and $Node) {
    $Why = if ($script:PretenseNpmFailed) { "npm install failed (see npm's output above)." } else { "npm was not found next to node." }
    throw (
      "The standalone binary ($Offered) is older than $MinVersion, and $Why`n" +
      "  Node is installed, so install the current release with npm:`n" +
      "    npm install -g @pretense/cli`n" +
      "  To install the older $Offered binary anyway:  set PRETENSE_INSTALL_METHOD=binary"
    )
  }
  Write-Host "  WARN  The standalone binary is $Offered, older than $MinVersion (the current release is on npm)."
  Write-Host "  WARN  For the current release, install Node.js 18+ (https://nodejs.org/en/download),"
  Write-Host "  WARN  then run:  npm install -g @pretense/cli"
  Write-Host "  WARN  Continuing with the $Offered binary."
  return $true
}

function Invoke-PretenseInstall {
  $BaseUrl    = "https://www.pretense.ai"
  $ReleasesUrl = "https://app.pretense.ai"  # binaries are served by the app origin, not the public Pages repo
  # Must match the published artifact filename exactly or the download 404s.
  # As of v0.6.1 the release workflow emits pretense-*; older 0.4.x artifacts
  # were named pretest-* and have been removed.
  $RemoteBinaryName = "pretense-win-x64.exe"
  # The installed command is `pretense` — matches the docs and the npm package
  # (@pretense/cli, scoped; the unscoped `pretense` on npm is not ours).
  $BinaryName = "pretense.exe"
  $InstallDir = if ($env:PRETENSE_INSTALL_DIR) { $env:PRETENSE_INSTALL_DIR } else { "$env:USERPROFILE\.local\bin" }

  Write-Host ""
  Write-Host "  Pretense CLI Installer"
  Write-Host "  AI firewall for dev teams -- pretense.ai"
  Write-Host ""

  # Channel-unification: npm first (always latest), binary as fallback.
  if (Install-PretenseViaNpm) { return }

  # Fetch latest version
  Write-Host "  -> Fetching latest version..."
  $Version = (Invoke-RestMethod "$BaseUrl/releases/latest/version.txt").Trim()
  if (-not $Version) { throw "Could not fetch latest version" }
  Write-Host "  -> Latest version: $Version"

  # Stop BEFORE downloading anything if the CDN is offering a step backwards.
  # Checked here, not next to the Copy-Item, so a refused downgrade costs no
  # bandwidth and cannot leave a half-installed state behind.
  Assert-PretenseNoDowngrade $Version $InstallDir $BinaryName $BaseUrl

  # Never install a binary below the floor without saying so.
  $MinBinaryVersion = "0.6.89"
  $OldBinary = Test-PretenseBinaryFloor $Version $MinBinaryVersion

  # Download binary
  $FileName   = $RemoteBinaryName
  $DownloadUrl = "$ReleasesUrl/releases/$Version/$FileName"
  $TmpFile    = [System.IO.Path]::GetTempFileName() + ".exe"

  Write-Host "  -> Downloading $FileName $Version..."
  Invoke-WebRequest -Uri $DownloadUrl -OutFile $TmpFile -UseBasicParsing

  # Verify SHA256.
  #
  # THIS BLOCK FAILS CLOSED. It used to fail OPEN: both the "no entry" and the
  # "could not fetch" branches merely printed WARN and fell through to the
  # install, so any response that did not yield a hash resulted in an unverified
  # executable being written to disk. Demonstrated on the POSIX twin by serving
  # an HTML page as SHA256SUMS with status 200 — the HTML was installed as the
  # binary and the script exited successfully.
  #
  # Two further bugs are fixed here:
  #   1. `$_ -match $FileName` is an UNANCHORED REGEX. The dot in
  #      "pretense-win-x64.exe" is a wildcard, and the match is a substring, so
  #      the wrong manifest line could supply the hash.
  #   2. `catch [System.Net.WebException]` does not catch the PowerShell 6+
  #      HttpResponseException, so on modern PowerShell a fetch failure escaped
  #      as an unhandled error rather than the intended path.
  # Both are replaced with an exact, whole-field comparison and a total catch.
  Write-Host "  -> Verifying checksum..."
  if ($env:SKIP_CHECKSUM -eq "1") {
    Write-Host "  WARN  SKIP_CHECKSUM=1 -- installing WITHOUT verifying the download."
  } else {
    $SumsText = $null
    try {
      $SumsUrl  = "$BaseUrl/releases/$Version/SHA256SUMS"
      $SumsText = (Invoke-RestMethod $SumsUrl)
    } catch {
      Remove-Item $TmpFile -Force -ErrorAction SilentlyContinue
      throw "Could not fetch SHA256SUMS from $BaseUrl/releases/$Version/SHA256SUMS. Refusing to install an unverified binary. Set SKIP_CHECKSUM=1 to override."
    }

    # Reject a soft-404 before parsing: a manifest is lines of "<64 hex> <name>".
    if ($SumsText -notmatch '(?m)^[0-9a-fA-F]{64}\s') {
      Remove-Item $TmpFile -Force -ErrorAction SilentlyContinue
      throw "SHA256SUMS is not a checksum manifest (likely a soft-404 or an error page). Refusing to install."
    }

    # Exact whole-field filename match, not a regex substring.
    $Expected = $null
    foreach ($Line in ($SumsText -split "`r?`n")) {
      $Fields = $Line.Trim() -split "\s+"
      if ($Fields.Count -ge 2 -and ($Fields[1] -eq $FileName -or $Fields[1] -eq "*$FileName")) {
        $Expected = $Fields[0].ToLower()
        break
      }
    }
    if (-not $Expected) {
      Remove-Item $TmpFile -Force -ErrorAction SilentlyContinue
      throw "No checksum entry for $FileName in SHA256SUMS. This release may be incomplete. Refusing to install an unverified binary."
    }

    $Actual = (Get-FileHash $TmpFile -Algorithm SHA256).Hash.ToLower()
    if ($Actual -ne $Expected) {
      Remove-Item $TmpFile -Force -ErrorAction SilentlyContinue
      throw "Checksum mismatch. Expected: $Expected  Got: $Actual"
    }
    Write-Host "  OK  Checksum verified"
  }

  # Install
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  $Dest = Join-Path $InstallDir $BinaryName
  Copy-Item $TmpFile $Dest -Force
  Remove-Item $TmpFile -Force

  Write-Host "  OK  Installed pretense $Version -> $Dest"

  # Add to PATH if needed
  $UserPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
  if ($UserPath -notlike "*$InstallDir*") {
    [System.Environment]::SetEnvironmentVariable("PATH", "$InstallDir;$UserPath", "User")
    Write-Host "  OK  Added $InstallDir to PATH (restart your terminal)"
  }

  # Verify THE BINARY WE JUST INSTALLED, by absolute path.
  # The CLI exposes `--version`, NOT a `version` subcommand — the old call used
  # `version`, so it always failed and the banner printed an empty version over
  # an install nobody had actually checked. Mirrors the POSIX twin: if the
  # installed file does not run, remove it rather than leave it on PATH.
  $env:PATH = "$InstallDir;$env:PATH"
  $InstalledVersion = $null
  try {
    $InstalledVersion = & "$Dest" --version 2>$null
  } catch {
    $InstalledVersion = $null
  }
  if (-not $InstalledVersion) {
    Remove-Item $Dest -Force -ErrorAction SilentlyContinue
    throw "Installed binary at $Dest did not run. It has been removed rather than left in place. Please report this with your Windows version and architecture."
  }
  Write-Host ""
  Write-Host "  Installation complete ($InstalledVersion)"

  if ($OldBinary) {
    Write-Host "  WARN  Installed $Version, older than $MinBinaryVersion. Install Node.js, then: npm install -g @pretense/cli"
  }

  Write-PretenseQuickStart -OldBinary $OldBinary
}

# -----------------------------------------------------------------------------
# TRUNCATION GUARD: this is the one and only top-level invocation, and it must
# stay the LAST LINE of the file. See the note at the top before touching it.
# A partially downloaded copy of this script reaches EOF without ever getting
# here, and therefore installs nothing.
# -----------------------------------------------------------------------------
Invoke-PretenseInstall

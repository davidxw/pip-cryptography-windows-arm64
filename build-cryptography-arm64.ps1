#Requires -Version 5.1
<#
.SYNOPSIS
    Builds and installs the Python cryptography package natively for Windows ARM64.

.DESCRIPTION
    This script automates the process of building the Python cryptography pip package
    from source so that it runs natively on Windows ARM64 hardware. It checks all
    prerequisites, installs and configures Rust with the ARM64 target, sets up the
    Visual Studio build environment, and builds/installs the package.

.PARAMETER PythonExe
    Path to the Python executable to use. Defaults to "python" (uses PATH).

.PARAMETER CryptographyVersion
    Specific version of the cryptography package to install (e.g. "42.0.8").
    Defaults to the latest version.

.PARAMETER SkipArchCheck
    Skip the check that verifies Python is running as ARM64. Use with caution.

.EXAMPLE
    .\build-cryptography-arm64.ps1

.EXAMPLE
    .\build-cryptography-arm64.ps1 -PythonExe "C:\Python312\python.exe"

.EXAMPLE
    .\build-cryptography-arm64.ps1 -CryptographyVersion "42.0.8"
#>

param(
    [string]$PythonExe     = "python",
    [string]$CryptographyVersion = "",
    [switch]$SkipArchCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
function Write-Banner {
    param([string]$Text)
    $width = 72
    $line  = "=" * $width
    Write-Host ""
    Write-Host $line                    -ForegroundColor Cyan
    Write-Host ("  " + $Text)          -ForegroundColor Cyan
    Write-Host $line                    -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host ">>> $Text" -ForegroundColor Yellow
}

function Write-OK {
    param([string]$Text)
    Write-Host "  [OK] $Text" -ForegroundColor Green
}

function Write-Info {
    param([string]$Text)
    Write-Host "  [>>] $Text" -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Text)
    Write-Host "  [!!] $Text" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Text)
    Write-Host "  [XX] $Text" -ForegroundColor Red
}

function Invoke-OrFail {
    param(
        [scriptblock]$ScriptBlock,
        [string]$ErrorMessage
    )
    try {
        & $ScriptBlock
        if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
            throw "Exit code $LASTEXITCODE"
        }
    }
    catch {
        Write-Fail $ErrorMessage
        Write-Host "  Detail: $_" -ForegroundColor Red
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
Write-Banner "Python cryptography – Windows ARM64 builder"
Write-Host "  This script builds and installs the 'cryptography' Python package" -ForegroundColor White
Write-Host "  from source so that it runs natively on Windows ARM64." -ForegroundColor White
Write-Host ""
Write-Host "  See README.md for prerequisites before running this script." -ForegroundColor DarkGray
Write-Host ""

# ---------------------------------------------------------------------------
# Step 1 – Verify we are on Windows ARM64
# ---------------------------------------------------------------------------
Write-Step "Step 1/6  Checking system architecture"

if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
    Write-OK "Running on Windows ARM64 (native)"
}
elseif ($env:PROCESSOR_ARCHITEW6432 -eq "ARM64") {
    Write-Warn "Running a 32/64-bit process on an ARM64 host (WOW64)."
    Write-Warn "Consider using an ARM64-native shell for best results."
}
elseif (-not $SkipArchCheck) {
    Write-Fail "This machine does not appear to be Windows ARM64."
    Write-Host "  PROCESSOR_ARCHITECTURE = $env:PROCESSOR_ARCHITECTURE" -ForegroundColor Red
    Write-Host "  Use -SkipArchCheck to bypass this check." -ForegroundColor DarkGray
    exit 1
}
else {
    Write-Warn "Architecture check skipped (-SkipArchCheck was specified)."
}

# ---------------------------------------------------------------------------
# Step 2 – Verify Python is ARM64
# ---------------------------------------------------------------------------
Write-Step "Step 2/6  Checking Python installation"

# Resolve the full path so we can report it clearly
try {
    $resolvedPython = (Get-Command $PythonExe -ErrorAction Stop).Source
}
catch {
    Write-Fail "Cannot find Python executable: '$PythonExe'"
    Write-Host "  Make sure Python is installed and on your PATH, or supply -PythonExe." -ForegroundColor DarkGray
    exit 1
}

$pyVersion = & $resolvedPython --version 2>&1
Write-OK "Python found  : $resolvedPython"
Write-OK "Version       : $pyVersion"

# Check the architecture of the Python interpreter
$pyArch = & $resolvedPython -c "import platform; print(platform.machine())" 2>&1
Write-Info "Architecture  : $pyArch"

if ($pyArch -notmatch "ARM64|aarch64" -and -not $SkipArchCheck) {
    Write-Fail "Python is NOT running as ARM64 ($pyArch)."
    Write-Host ""
    Write-Host "  You need an ARM64-native Python build. Download it from:" -ForegroundColor Yellow
    Write-Host "  https://www.python.org/downloads/windows/" -ForegroundColor Cyan
    Write-Host "  Choose the 'ARM64 installer' for your Python version." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Use -SkipArchCheck to bypass this check." -ForegroundColor DarkGray
    exit 1
}
elseif ($pyArch -notmatch "ARM64|aarch64") {
    Write-Warn "Python architecture check skipped."
}
else {
    Write-OK "Python is ARM64-native – good."
}

# ---------------------------------------------------------------------------
# Step 3 – Verify / install Rust
# ---------------------------------------------------------------------------
Write-Step "Step 3/6  Checking Rust toolchain"

$rustupExe = Join-Path $env:USERPROFILE ".cargo\bin\rustup.exe"

$rustupOnPath = Get-Command "rustup" -ErrorAction SilentlyContinue
if ($rustupOnPath) {
    $rustupExe = $rustupOnPath.Source
    Write-OK "rustup found  : $rustupExe"
}
elseif (Test-Path $rustupExe) {
    # Not on PATH but exists in default location – add to session
    $env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
    Write-OK "rustup found  : $rustupExe (added to session PATH)"
}
else {
    Write-Warn "Rust / rustup not found. Downloading and installing rustup..."
    Write-Host ""

    $rustupUrl      = "https://win.rustup.rs/aarch64"
    $rustupInstaller = Join-Path $env:TEMP "rustup-init-arm64.exe"

    Write-Info "Downloading rustup from $rustupUrl ..."
    try {
        Invoke-WebRequest -Uri $rustupUrl -OutFile $rustupInstaller -UseBasicParsing
    }
    catch {
        Write-Fail "Failed to download rustup installer."
        Write-Host "  Please install Rust manually from https://rustup.rs/ then re-run this script." -ForegroundColor DarkGray
        exit 1
    }

    Write-Info "Running rustup installer (this may take a few minutes)..."
    # -y  = accept defaults, --default-toolchain stable, --profile minimal
    $rustupArgs = @("-y", "--default-toolchain", "stable", "--profile", "minimal")
    Start-Process -FilePath $rustupInstaller -ArgumentList $rustupArgs -Wait -NoNewWindow
    Remove-Item $rustupInstaller -Force -ErrorAction SilentlyContinue

    # Reload PATH to pick up cargo/rustup
    $env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"

    if (-not (Get-Command "rustup" -ErrorAction SilentlyContinue)) {
        Write-Fail "Rust installation appears to have failed."
        Write-Host "  Please install Rust manually from https://rustup.rs/" -ForegroundColor DarkGray
        exit 1
    }
    Write-OK "Rust installed successfully."
}

# Ensure the stable toolchain is active
Write-Info "Ensuring stable toolchain is set as default..."
& rustup default stable | Out-Null

$rustVersion = & rustc --version 2>&1
Write-OK "Rust version  : $rustVersion"

# ---------------------------------------------------------------------------
# Step 4 – Ensure the ARM64 Rust target is installed
# ---------------------------------------------------------------------------
Write-Step "Step 4/6  Configuring Rust ARM64 target"

$arm64Target = "aarch64-pc-windows-msvc"

$installedTargets = & rustup target list --installed 2>&1
if ($installedTargets -match [regex]::Escape($arm64Target)) {
    Write-OK "Target '$arm64Target' already installed."
}
else {
    Write-Info "Adding target '$arm64Target' ..."
    Invoke-OrFail {
        & rustup target add $arm64Target
    } "Failed to add Rust target '$arm64Target'."
    Write-OK "Target added."
}

# ---------------------------------------------------------------------------
# Step 5 – Set up the Visual Studio ARM64 build environment
# ---------------------------------------------------------------------------
Write-Step "Step 5/6  Setting up Visual Studio ARM64 build environment"

# Locate vswhere – the canonical tool for finding VS installations
$vswherePath = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswherePath)) {
    $vswherePath = "${env:ProgramFiles}\Microsoft Visual Studio\Installer\vswhere.exe"
}

if (-not (Test-Path $vswherePath)) {
    Write-Fail "vswhere.exe not found. Visual Studio does not appear to be installed."
    Write-Host ""
    Write-Host "  Please install Visual Studio 2022 (Community or above) with:" -ForegroundColor Yellow
    Write-Host "    - Workload: 'Desktop development with C++'" -ForegroundColor Yellow
    Write-Host "    - Component: 'MSVC v143 – VS 2022 C++ ARM64/ARM64EC build tools'" -ForegroundColor Yellow
    Write-Host "    - Component: 'Windows 11 SDK (10.0.22000 or later)'" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Download from: https://visualstudio.microsoft.com/downloads/" -ForegroundColor Cyan
    exit 1
}

$vsInstallPath = & $vswherePath -latest -requires "Microsoft.VisualCpp.Tools.HostX64.TargetARM64" -property installationPath 2>$null
if (-not $vsInstallPath) {
    # Try without the component requirement – VS is installed but maybe missing arm64 component
    $vsInstallPath = & $vswherePath -latest -property installationPath 2>$null
    if ($vsInstallPath) {
        Write-Warn "Visual Studio found but the ARM64 build tools component may be missing."
        Write-Warn "Path: $vsInstallPath"
        Write-Host ""
        Write-Host "  Open Visual Studio Installer and add the following component:" -ForegroundColor Yellow
        Write-Host "    'MSVC v143 – VS 2022 C++ ARM64/ARM64EC build tools'" -ForegroundColor Yellow
        Write-Host ""
        $continue = Read-Host "  Continue anyway? The build may fail. [y/N]"
        if ($continue -notmatch "^[yY]") {
            exit 1
        }
    }
    else {
        Write-Fail "Could not locate a Visual Studio installation."
        Write-Host "  Install Visual Studio 2022 from: https://visualstudio.microsoft.com/downloads/" -ForegroundColor DarkGray
        exit 1
    }
}

Write-OK "Visual Studio : $vsInstallPath"

$vcvarsall = Join-Path $vsInstallPath "VC\Auxiliary\Build\vcvarsall.bat"
if (-not (Test-Path $vcvarsall)) {
    Write-Fail "vcvarsall.bat not found at expected location: $vcvarsall"
    exit 1
}

Write-Info "Loading ARM64 build environment from vcvarsall.bat ..."

# Capture the environment variables set by vcvarsall.bat arm64
$vcEnvOutput = cmd /c "`"$vcvarsall`" arm64 > nul 2>&1 && set" 2>&1
if ($LASTEXITCODE -ne 0 -or -not $vcEnvOutput) {
    Write-Fail "vcvarsall.bat arm64 failed. ARM64 build tools may not be installed."
    exit 1
}

$envVarsApplied = 0
foreach ($line in $vcEnvOutput) {
    if ($line -match "^([^=]+)=(.*)$") {
        $varName  = $Matches[1]
        $varValue = $Matches[2]
        [System.Environment]::SetEnvironmentVariable($varName, $varValue, "Process")
        $envVarsApplied++
    }
}
Write-OK "VS build environment loaded ($envVarsApplied variables)."

# Tell Cargo/Rust to compile for ARM64
$env:CARGO_BUILD_TARGET = $arm64Target
Write-OK "CARGO_BUILD_TARGET = $arm64Target"

# ---------------------------------------------------------------------------
# Step 6 – Build and install cryptography
# ---------------------------------------------------------------------------
Write-Step "Step 6/6  Building and installing the cryptography package"

$pipTarget = if ($CryptographyVersion) { "cryptography==$CryptographyVersion" } else { "cryptography" }
Write-Info "Target package  : $pipTarget"
Write-Info "Python          : $resolvedPython"
Write-Host ""
Write-Host "  Building from source – this may take 5-10 minutes the first time." -ForegroundColor DarkGray
Write-Host ""

# --no-binary :all: forces pip to build from source (no pre-built wheel)
# --no-cache-dir avoids stale cached wheels from previous failed attempts
$pipArgs = @(
    "-m", "pip", "install",
    "--no-binary", ":all:",
    "--no-cache-dir",
    $pipTarget
)

try {
    & $resolvedPython @pipArgs
    if ($LASTEXITCODE -ne 0) {
        throw "pip exited with code $LASTEXITCODE"
    }
}
catch {
    Write-Host ""
    Write-Fail "Build failed: $_"
    Write-Host ""
    Write-Host "  Troubleshooting tips:" -ForegroundColor Yellow
    Write-Host "    1. Ensure the MSVC ARM64 build tools are installed in Visual Studio." -ForegroundColor Yellow
    Write-Host "       Open 'Visual Studio Installer', click Modify, and under" -ForegroundColor Yellow
    Write-Host "       'Individual Components' add:" -ForegroundColor Yellow
    Write-Host "         MSVC v143 – VS 2022 C++ ARM64/ARM64EC build tools (Latest)" -ForegroundColor Yellow
    Write-Host "    2. Try running this script from a 'Developer PowerShell for VS 2022'" -ForegroundColor Yellow
    Write-Host "       prompt configured for ARM64." -ForegroundColor Yellow
    Write-Host "    3. Check that Rust's stable-aarch64-pc-windows-msvc toolchain is OK:" -ForegroundColor Yellow
    Write-Host "         rustup show" -ForegroundColor Cyan
    exit 1
}

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------
Write-Host ""
Write-Banner "Verifying installation"

$verifyScript = @"
import platform, sys
try:
    import cryptography
    from cryptography.fernet import Fernet
    key = Fernet.generate_key()
    f   = Fernet(key)
    tok = f.encrypt(b'arm64 test')
    assert f.decrypt(tok) == b'arm64 test'
    print(f"cryptography {cryptography.__version__} installed OK")
    print(f"Python arch : {platform.machine()}")
    print(f"Python path : {sys.executable}")
    print("Smoke test  : PASSED")
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
"@

$result = & $resolvedPython -c $verifyScript 2>&1
$exitCode = $LASTEXITCODE

foreach ($line in $result) {
    if ($line -match "^ERROR") {
        Write-Fail $line
    }
    elseif ($line -match "PASSED") {
        Write-OK $line
    }
    else {
        Write-Info $line
    }
}

if ($exitCode -ne 0) {
    Write-Host ""
    Write-Fail "Verification failed. The package may not have installed correctly."
    exit 1
}

Write-Host ""
Write-Host ("=" * 72) -ForegroundColor Green
Write-Host "  SUCCESS – cryptography is installed and working on Windows ARM64!" -ForegroundColor Green
Write-Host ("=" * 72) -ForegroundColor Green
Write-Host ""
Write-Host "  You can now use packages that depend on cryptography, such as:" -ForegroundColor White
Write-Host "    pip install azure-identity azure-keyvault-secrets" -ForegroundColor Cyan
Write-Host ""

# pip Cryptography on Windows ARM64

A PowerShell script that automates building and installing the Python [`cryptography`](https://pypi.org/project/cryptography/) package natively on **Windows ARM64**.

## The Problem

The `cryptography` Python package is a core dependency of many popular libraries – most notably the **Azure SDK** (e.g. `azure-identity`, `azure-keyvault-secrets`). Since version 3.4, `cryptography` is partially written in Rust and distributed as pre-compiled binary wheels on PyPI.

PyPI currently does **not** publish a pre-built `win_arm64` wheel for `cryptography`. This means that on a Windows ARM64 machine (e.g. a Snapdragon X Elite / X Plus laptop, or an ARM64 Azure VM), running `pip install cryptography` (or any package that depends on it) **fails** with an error such as:

```
ERROR: Could not find a version that satisfies the requirement cryptography
```

The solution is to **build the package from source** on the ARM64 machine. The `build-cryptography-arm64.ps1` script in this repository automates that process.

## Prerequisites

The following must be installed **manually** before running the script. These steps cannot be fully automated because they involve large installers and licence agreements.

### 1 – Windows 11 ARM64

You must be running a 64-bit ARM edition of Windows 11 on native ARM64 hardware (e.g. Snapdragon X, Ampere Altra, etc.). Windows 11 ARM64 can run x64 applications via emulation, but for the best results Python and all build tools should be ARM64-native.

### 2 – Python (ARM64)

You need an **ARM64-native** build of Python 3.9 or later. Verify your existing install:

```powershell
python -c "import platform; print(platform.machine())"
# Expected output: ARM64
```

If the output shows `AMD64` instead, or Python is not installed, install the ARM64 build via **winget**:

```powershell
winget install Python.Python.3.12
```

Winget automatically selects the ARM64 package on ARM64 hardware.

### 3 – C++ ARM64 Build Tools

You need the MSVC ARM64 compiler and linker. The lightest way to get them is via the **Visual Studio 2022 Build Tools** (no full IDE required):

1. Downloand and run the Visual Studio 2022 Build Tools installer:

```powershell
winget install --id=Microsoft.VisualStudio.2022.BuildTools
```
2. In the installer, select the **Desktop development with C++** workload.
3. In the **Individual Components** tab, ensure the following are checked:

| Component | Why it's needed |
|-----------|----------------|
| **MSVC v143 – VS 2022 C++ ARM64/ARM64EC build tools (Latest)** | ARM64 compiler & linker |
| **Windows 11 SDK (10.0.22000.0 or later)** | Windows headers & libraries |

> [!NOTE] 
If you already have **Visual Studio 2022** (Community / Professional / Enterprise) installed, you can add the same components via **Visual Studio Installer → Modify → Individual Components** instead of installing the standalone Build Tools.

> [!TIP] 
Search for "ARM64" in the Individual Components tab to quickly find the required component.

## Installation Steps

Once the prerequisites are in place, open a **PowerShell** terminal (does **not** need to be a Developer prompt – the script sets up the environment itself) and run:

```powershell
# 1. Clone or download this repository
git clone https://github.com/davidxw/pip-cryptography-windows-arm64.git
cd pip-cryptography-windows-arm64

# 2. Allow the script to run (one-time, or use RemoteSigned policy)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# 3. Run the script
.\build-cryptography-arm64.ps1
```

### Optional parameters

| Parameter | Description |
|-----------|-------------|
| `-PythonExe <path>` | Full path to the Python executable to use. Defaults to `python` (first match on `PATH`). |
| `-CryptographyVersion <ver>` | Pin a specific version, e.g. `42.0.8`. Defaults to the latest available. |
| `-SkipArchCheck` | Skip the check that verifies the machine / Python are ARM64. |

**Examples:**

```powershell
# Use a specific Python installation
.\build-cryptography-arm64.ps1 -PythonExe "C:\Python312\python.exe"

# Pin a specific cryptography version
.\build-cryptography-arm64.ps1 -CryptographyVersion "42.0.8"
```

### What the script does

1. Verifies the machine is Windows ARM64.
2. Verifies the Python interpreter is an ARM64-native build.
3. Installs **Rust** via `rustup` if it is not already present (downloads the ARM64 `rustup-init.exe` automatically).
4. Adds the `aarch64-pc-windows-msvc` Rust compilation target.
5. Locates Visual Studio / Build Tools and loads the ARM64 build environment (`vcvarsall.bat arm64`).
6. Installs **OpenSSL ARM64 development libraries** via `winget` if not already present, and sets the `OPENSSL_DIR`, `OPENSSL_LIB_DIR`, and `OPENSSL_INCLUDE_DIR` environment variables.
7. Configures the OpenSSL DLL path to avoid runtime conflicts with system DLLs.
8. Runs `pip install --no-binary :all: cryptography` to build and install the package from source.
9. Runs a smoke test to confirm the installation works.

## Follow-up Steps and Implications

### Installing Azure SDK packages

Once `cryptography` is installed natively, you can install the Azure SDK packages as normal:

```powershell
pip install azure-identity azure-keyvault-secrets azure-storage-blob
# … and any other azure-* packages you need
```

### Using multiple virtual environments

The built ARM64 wheel is **cached by pip** automatically. Once the script has built `cryptography` successfully, any subsequent `pip install cryptography` (or a package that depends on it) in **any** virtual environment will use the cached wheel — no rebuild or environment variables required.

You can verify the wheel is cached:

```powershell
pip cache list cryptography
```

If you need to force a rebuild (e.g. after upgrading OpenSSL), re-run the script.

### Keeping cryptography up to date

To upgrade to a new version, re-run the script — it will build and cache the new version:

```powershell
.\build-cryptography-arm64.ps1 -CryptographyVersion "<new-version>"
```

After that, `pip install --upgrade cryptography` in any venv will use the newly cached wheel.

### Rust remains installed

The script installs Rust permanently in `%USERPROFILE%\.cargo`. This is intentional – you will need Rust if you ever rebuild `cryptography` or other Rust-based Python packages. If you want to remove Rust later, run `rustup self uninstall`.

### Performance

A natively-compiled ARM64 `cryptography` wheel performs significantly better than the x64 emulated version. Benchmarks show 2–4× throughput improvements for cryptographic operations on Snapdragon X hardware.

## Testing

After the script finishes successfully it runs a built-in smoke test. You can also verify the installation manually:

```powershell
# 1. Check the installed version and architecture
python -c "import cryptography, platform; print(cryptography.__version__, platform.machine())"
# Expected: <version>  ARM64

# 2. Run a Fernet encrypt/decrypt cycle
python -c "
from cryptography.fernet import Fernet
key = Fernet.generate_key()
f   = Fernet(key)
tok = f.encrypt(b'hello arm64')
print('Decrypt OK:', f.decrypt(tok))
"
# Expected: Decrypt OK: b'hello arm64'

# 3. Verify azure-identity works (if installed)
python -c "from azure.identity import DefaultAzureCredential; print('azure-identity OK')"
```

## Acknowledgements

The OpenSSL build steps in this project were informed by the excellent guide [*The Complete Guide to Setting Up Python and Azure SDK on Windows ARM64*](https://zenn.dev/pcmin/articles/windows-arm64-python-cryptography-azure-sdk) by [@pcmin](https://zenn.dev/pcmin).


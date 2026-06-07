<#
.SYNOPSIS
    Build Gifsicle for Windows (x64 by default) with the installed MSVC compiler.

.DESCRIPTION
    Locates an existing Visual Studio / Build Tools installation with vswhere,
    loads the matching MSVC developer environment in-process (Enter-VsDevShell),
    then drives src\Makefile.w32 with nmake to produce gifsicle.exe and
    gifdiff.exe. The compiler-detection approach mirrors UE5CEDumper\build.ps1.

    No compiler is downloaded or installed -- only what is already on the
    machine is used.

.PARAMETER Arch
    Target architecture: x64 (default) or x86.

.PARAMETER Clean
    Remove build artifacts (obj/exe and generated config.h) before building.

.PARAMETER Ungif
    Build with unpatented run-length compression (ungifwrt.c) instead of
    LZW compression (gifwrite.c).

.PARAMETER LogFile
    Optional path to a transcript log file.

.EXAMPLE
    .\build.ps1
    Build the x64 release.

.EXAMPLE
    .\build.ps1 -Arch x86 -Clean
    Clean, then build the 32-bit release.
#>
[CmdletBinding()]
param(
    [ValidateSet('x64', 'x86')]
    [string]$Arch = 'x64',
    [switch]$Clean,
    [switch]$Ungif,
    [string]$LogFile
)

$ErrorActionPreference = 'Stop'
$ROOT_DIR = $PSScriptRoot
$SRC_DIR  = Join-Path $ROOT_DIR 'src'
$DIST_DIR = Join-Path $ROOT_DIR 'dist'

if ($LogFile) {
    try { Start-Transcript -Path $LogFile -Force | Out-Null } catch { }
}

# ------------------------------------------------------------
# Output helpers
# ------------------------------------------------------------
function Write-Banner([string]$Text) {
    Write-Host ''
    Write-Host ('=' * 60) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ('=' * 60) -ForegroundColor Cyan
}
function Write-Step([string]$Text) { Write-Host ''; Write-Host ">> $Text" -ForegroundColor White }
function Write-Ok([string]$Text)   { Write-Host "   [OK] $Text"   -ForegroundColor Green }
function Write-Fail([string]$Text) { Write-Host "   [FAIL] $Text" -ForegroundColor Red }
function Write-Info([string]$Text) { Write-Host "   $Text"        -ForegroundColor Gray }

# ------------------------------------------------------------
# Locate vswhere.exe -- search multiple known locations
# (same strategy as UE5CEDumper\build.ps1)
# ------------------------------------------------------------
function Find-VsWhere {
    $candidates = [System.Collections.Generic.List[string]]::new()

    $inPath = Get-Command vswhere -ErrorAction SilentlyContinue
    if ($inPath) { $candidates.Add($inPath.Source) }

    $pf86 = ${env:ProgramFiles(x86)}
    if ($pf86) { $candidates.Add((Join-Path $pf86 'Microsoft Visual Studio\Installer\vswhere.exe')) }

    if ($env:ProgramFiles) { $candidates.Add((Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe')) }
    if ($env:ChocolateyInstall) { $candidates.Add((Join-Path $env:ChocolateyInstall 'bin\vswhere.exe')) }
    if ($env:LOCALAPPDATA) { $candidates.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\VisualStudio\Installer\vswhere.exe')) }

    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c -ErrorAction SilentlyContinue)) { return $c }
    }

    Write-Fail 'vswhere.exe not found. Searched:'
    foreach ($c in $candidates) { if ($c) { Write-Info "  - $c" } }
    Write-Info 'Install Visual Studio (C++ Desktop workload) or run: winget install Microsoft.VisualStudio.Locator'
    return $null
}

# ------------------------------------------------------------
# Find a VS install that has the C++ x64/x86 build tools
# ------------------------------------------------------------
function Find-VsInstall([string]$vswhere) {
    $vsPath = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath 2>$null
    if (-not $vsPath) {
        # Fall back to any latest install (e.g. Build Tools without the exact component id)
        $vsPath = & $vswhere -latest -products * -property installationPath 2>$null
    }
    if ($vsPath) { return $vsPath.Trim() }
    return $null
}

# ------------------------------------------------------------
# Load the MSVC developer environment in-process
# ------------------------------------------------------------
function Enter-VsDevEnvironment([string]$vsPath, [string]$Arch) {
    $devShellDll = Join-Path $vsPath 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll'
    if (-not (Test-Path $devShellDll)) {
        Write-Fail "Microsoft.VisualStudio.DevShell.dll not found: $devShellDll"
        return $false
    }
    Import-Module $devShellDll -ErrorAction Stop
    # host_arch=x64: use the 64-bit toolchain to build either target.
    Enter-VsDevShell -VsInstallPath $vsPath -SkipAutomaticLocation `
        -DevCmdArguments "-arch=$Arch -host_arch=x64" | Out-Null
    return $true
}

# ============================================================
# Main
# ============================================================
$exitCode = 0
try {
    Write-Banner "Gifsicle Windows Build  |  Arch: $Arch  |  Ungif: $($Ungif.IsPresent)"
    Write-Info "Root: $ROOT_DIR"

    Write-Step 'Locating compiler...'
    $vswhere = Find-VsWhere
    if (-not $vswhere) { exit 1 }
    Write-Info "vswhere: $vswhere"

    $vsPath = Find-VsInstall $vswhere
    if (-not $vsPath) {
        Write-Fail 'No Visual Studio installation with the C++ build tools was found.'
        Write-Info 'Install the "Desktop development with C++" workload.'
        exit 1
    }
    Write-Ok "Visual Studio: $vsPath"

    Write-Step "Loading MSVC environment ($Arch)..."
    if (-not (Enter-VsDevEnvironment $vsPath $Arch)) { exit 1 }
    $cl = Get-Command cl -ErrorAction SilentlyContinue
    if (-not $cl) { Write-Fail 'cl.exe not on PATH after loading the dev environment.'; exit 1 }
    Write-Ok "cl.exe: $($cl.Source)"

    Set-Location $SRC_DIR

    if ($Clean) {
        Write-Step 'Cleaning...'
        Remove-Item (Join-Path $SRC_DIR '*.obj') -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $SRC_DIR '*.exe') -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $SRC_DIR '*.pdb') -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $ROOT_DIR 'config.h') -ErrorAction SilentlyContinue
        Write-Ok 'Clean done'
    }

    Write-Step 'Building (nmake -f Makefile.w32)...'
    $gifwrite = if ($Ungif) { 'ungifwrt.obj' } else { 'gifwrite.obj' }
    & nmake /NOLOGO -f Makefile.w32 "GIFWRITE_OBJ=$gifwrite" gifsicle.exe gifdiff.exe
    if ($LASTEXITCODE -ne 0) { Write-Fail "nmake failed (exit $LASTEXITCODE)"; exit $LASTEXITCODE }

    $gifsicleExe = Join-Path $SRC_DIR 'gifsicle.exe'
    $gifdiffExe  = Join-Path $SRC_DIR 'gifdiff.exe'
    if (-not (Test-Path $gifsicleExe) -or -not (Test-Path $gifdiffExe)) {
        Write-Fail 'Build reported success but the executables are missing.'
        exit 1
    }

    Write-Step 'Collecting output...'
    $outDir = Join-Path $DIST_DIR $Arch
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    Copy-Item $gifsicleExe, $gifdiffExe -Destination $outDir -Force
    Write-Ok "Copied to $outDir"

    Write-Step 'Verifying...'
    & $gifsicleExe --version | Select-Object -First 1 | ForEach-Object { Write-Info $_ }
    & $gifdiffExe  --version | Select-Object -First 1 | ForEach-Object { Write-Info $_ }

    Write-Banner 'BUILD SUCCEEDED'
    Write-Host "  gifsicle.exe -> $outDir" -ForegroundColor Green
    Write-Host "  gifdiff.exe  -> $outDir" -ForegroundColor Green
}
catch {
    Write-Fail "Build error: $_"
    $exitCode = 1
}
finally {
    Set-Location $ROOT_DIR
    if ($LogFile) { try { Stop-Transcript | Out-Null } catch { } }
}

exit $exitCode

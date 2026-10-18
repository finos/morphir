# Minimal bootstrap before the portable MoonBit core setup script can run.
# Operates only inside mise's installation, never the user's shared .moon.
param([string]$ToolchainHome = $env:MISE_TOOL_INSTALL_PATH)
$ErrorActionPreference = 'Stop'
if (-not $ToolchainHome) { throw 'An explicit mise toolchain directory is required' }
$Pin = Get-Content (Join-Path $PSScriptRoot 'moonbit-core-pin.json') -Raw | ConvertFrom-Json
$Moon = Join-Path $ToolchainHome 'bin/moon.exe'
if (-not (Test-Path $Moon -PathType Leaf)) { throw 'Install the pinned compiler archive first' }
$Compiler = Join-Path $ToolchainHome 'bin/moonc.exe'
if ((& $Compiler -v) -notlike "v$($Pin.compilerVersion) *") { throw 'The pinned compiler is required before core bootstrap' }
$Core = Join-Path $ToolchainHome 'lib/core'
if (-not (Test-Path (Join-Path $Core 'moon.mod') -PathType Leaf)) {
    $Archive = Join-Path $ToolchainHome 'bootstrap-core.zip'
    try {
        $Version = $Pin.compilerVersion -replace '\+', '%2B'
        Invoke-WebRequest "https://cli.moonbitlang.com/cores/core-$Version.zip" -OutFile $Archive
        if ((Get-FileHash $Archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Pin.bootstrapWindowsCoreSha256) { throw 'Bootstrap core checksum differs' }
        Expand-Archive $Archive -DestinationPath (Join-Path $ToolchainHome 'lib')
    } finally { Remove-Item $Archive -ErrorAction SilentlyContinue }
}
$Moonx = Join-Path $ToolchainHome 'bin/moonx.exe'
if (-not (Test-Path $Moonx -PathType Leaf)) { Copy-Item $Moon $Moonx }
$Previous = $env:MOON_CORE_OVERRIDE
try {
    $env:MOON_CORE_OVERRIDE = $Core
    & $Moon -C $Core bundle --warn-list -a --all
    if ($LASTEXITCODE -ne 0) { throw 'Bootstrap core bundling failed' }
} finally { $env:MOON_CORE_OVERRIDE = $Previous }

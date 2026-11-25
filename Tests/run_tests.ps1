param(
    [ValidateSet('Debug', 'Release')]
    [string] $Config = 'Release',
    [switch] $Warp,
    [string] $PluginPath = (Join-Path $env:ProgramData 'aviutl2\Plugin\SYNC_PaperBreak\SYNC_PaperBreak.auf2')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$compiler = (Get-Command dcc64).Source
$out = Join-Path $root 'Win64\Verification'
New-Item -ItemType Directory -Force $out, (Join-Path $out 'DCU') | Out-Null

if (-not (Test-Path -LiteralPath $PluginPath -PathType Leaf)) {
    throw "Build $PluginPath first."
}
$plugin = (Get-Item -LiteralPath $PluginPath).FullName

Push-Location $PSScriptRoot
try {
    & $compiler '-B' '-Q' '-NSSystem;Winapi;Vcl' "-E$out" "-NU$out\DCU" 'PaperBreak_RenderTests.dpr'
    if ($LASTEXITCODE -ne 0) { throw 'Test compilation failed.' }

    $driver = if ($Warp) { 'warp' } else { 'hardware' }
    & (Join-Path $out 'PaperBreak_RenderTests.exe') $plugin (Join-Path $out "$Config-$driver.png") $driver
    if ($LASTEXITCODE -ne 0) { throw 'Render test failed.' }
} finally {
    Pop-Location
}

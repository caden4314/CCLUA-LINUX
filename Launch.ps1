$ErrorActionPreference = 'Stop'
$root = 'C:\Dev\CCLUA-LINUX'
& (Join-Path $root 'Build.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$craft = Join-Path $root 'tools\CraftOS-PC\CraftOS-PC_console.exe'
$computers = Join-Path $root 'runtime\computer'
& $craft -C $computers -i 2710 --gui

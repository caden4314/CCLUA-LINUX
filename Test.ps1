$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$computerId = 2799
$runtime = Join-Path $root ("runtime\computer\" + $computerId)
$state = Join-Path $runtime '.cclua'
$smoke = Join-Path $state 'smoke'
$result = Join-Path $state 'smoke-result.txt'
$craft = Join-Path $root 'tools\CraftOS-PC\CraftOS-PC_console.exe'

& (Join-Path $root 'Build.ps1')
if ($LASTEXITCODE -ne 0) { throw "Build failed with exit code $LASTEXITCODE" }

if (Test-Path $runtime) { Remove-Item -Recurse -Force $runtime }
python (Join-Path $root 'tools\prepare_runtime.py') --id $computerId
if ($LASTEXITCODE -ne 0) { throw "Runtime preparation failed with exit code $LASTEXITCODE" }

New-Item -ItemType Directory -Force -Path $state | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue $result
New-Item -ItemType File -Force -Path $smoke | Out-Null

try {
    & $craft -C (Join-Path $root 'runtime\computer') -i $computerId --headless | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "CraftOS-PC exited with code $LASTEXITCODE" }
}
finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $smoke
}
if (-not (Test-Path $result)) { throw 'Smoke result was not produced.' }
$lines = @(Get-Content $result)
$required = @(
    'CCLUA_LINUX_SMOKE_PASS',
    'scheduler.probe=pass',
    'scheduler.crashes=0',
    'package.lua-ssh=pass',
    'package.guard=pass',
    'service.netd=running',
    'service.diagnosticsd=running',
    'service.updated=running',
    'service.pkgd=running',
    'service.sshd=running',
    'service.sshclientd=running'
)
foreach ($entry in $required) {
    if ($lines -notcontains $entry) { throw "Smoke assertion failed: $entry" }
}

$isoLine = $lines | Where-Object { $_ -like 'iso_files=*' } | Select-Object -First 1
if (-not $isoLine) { throw 'Smoke result did not report iso_files.' }
$isoFiles = [int]($isoLine -replace '^iso_files=', '')
if ($isoFiles -lt 1) { throw "Invalid ISO file count: $isoFiles" }

Write-Host "CCLUA-LINUX smoke PASS ($isoFiles ISO files)" -ForegroundColor Green
$lines | ForEach-Object { Write-Host $_ }

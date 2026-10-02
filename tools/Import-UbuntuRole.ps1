param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("desktop","server")]
    [string]$Role,

    [string]$RepoRoot = "C:\Dev\CCLUA-LINUX"
)

$ErrorActionPreference = "Stop"
Set-Location $RepoRoot

$release = "ubuntu-22.04.5"
$rootfs = Join-Path $RepoRoot "extracted\$release\$Role\rootfs"
$gen = Join-Path $RepoRoot "generated\$release\$Role"

Write-Host "=== Extract $Role ==="
& "$RepoRoot\tools\Extract-Ubuntu.ps1" -Role $Role -RepoRoot $RepoRoot

Write-Host "=== Basic filesystem inventory ==="
python "$RepoRoot\tools\classify_rootfs.py" $rootfs --image "$release-$Role" --output "$gen\filesystem-inventory.json"
if ($LASTEXITCODE -ne 0) { throw "classify_rootfs failed" }

Write-Host "=== Semantic rootfs analysis ==="
python "$RepoRoot\tools\analyze_rootfs.py" $rootfs --role $Role --output-dir "$gen\analysis"
if ($LASTEXITCODE -ne 0) { throw "analyze_rootfs failed" }

Write-Host "=== Import dpkg package database ==="
python "$RepoRoot\tools\import_dpkg_db.py" $rootfs --output "$gen\dpkg-database.json"
if ($LASTEXITCODE -ne 0) { throw "import_dpkg_db failed" }

Write-Host "=== Parse systemd ==="
python "$RepoRoot\tools\parse_systemd.py" $rootfs --output "$gen\systemd.json"
if ($LASTEXITCODE -ne 0) { throw "parse_systemd failed" }

Write-Host "=== Build conversion plan ==="
python "$RepoRoot\tools\generate_conversion_plan.py" --analysis "$gen\analysis" --registry "$RepoRoot\spec\replacement-registry.json" --output "$gen\conversion-plan.json"
if ($LASTEXITCODE -ne 0) { throw "generate_conversion_plan failed" }

Write-Host ""
Write-Host "IMPORT COMPLETE"
Write-Host "RootFS: $rootfs"
Write-Host "Generated: $gen"

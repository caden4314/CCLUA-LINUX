param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("desktop","server")]
    [string]$Role,

    [string]$RepoRoot = "C:\Dev\CCLUA-LINUX"
)

$ErrorActionPreference = "Stop"
$SevenZip = "C:\Program Files\7-Zip\7z.exe"
if (-not (Test-Path $SevenZip)) { throw "7-Zip not found at $SevenZip" }

$cache = Join-Path $RepoRoot ".cache\ubuntu"
$isoName = if ($Role -eq "desktop") {
    "ubuntu-22.04.5-desktop-amd64.iso"
} else {
    "ubuntu-22.04.5-live-server-amd64.iso"
}

$iso = Join-Path $cache $isoName
if (-not (Test-Path $iso)) { throw "ISO not found: $iso" }

$work = Join-Path $RepoRoot "extracted\ubuntu-22.04.5\$Role"
$isoTree = Join-Path $work "iso"
$rootfs = Join-Path $work "rootfs"
$squash = Join-Path $isoTree "casper\filesystem.squashfs"

New-Item -ItemType Directory -Path $isoTree -Force | Out-Null
New-Item -ItemType Directory -Path $rootfs -Force | Out-Null

Write-Host "Extracting ISO payload for $Role..."
& $SevenZip x $iso "-o$isoTree" "casper/filesystem.squashfs" "casper/filesystem.manifest" "casper/filesystem.size" -y
if ($LASTEXITCODE -ne 0) { throw "ISO extraction failed with exit code $LASTEXITCODE" }
if (-not (Test-Path $squash)) { throw "filesystem.squashfs not found after ISO extraction" }

Write-Host "Extracting SquashFS root filesystem..."
& $SevenZip x $squash "-o$rootfs" -y
if ($LASTEXITCODE -ne 0) { throw "SquashFS extraction failed with exit code $LASTEXITCODE" }

Write-Host "Root filesystem ready: $rootfs"
Get-ChildItem $rootfs | Select-Object Name,Mode | Format-Table -AutoSize

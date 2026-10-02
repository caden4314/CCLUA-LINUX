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

if (Test-Path $rootfs) { Remove-Item $rootfs -Recurse -Force }
New-Item -ItemType Directory -Path $isoTree -Force | Out-Null
New-Item -ItemType Directory -Path $rootfs -Force | Out-Null

if ($Role -eq "desktop") {
    $members = @(
        "casper/filesystem.squashfs",
        "casper/filesystem.manifest",
        "casper/filesystem.size"
    )
    $layers = @("filesystem.squashfs")
} else {
    $members = @(
        "casper/install-sources.yaml",
        "casper/filesystem.manifest",
        "casper/filesystem.size",
        "casper/ubuntu-server-minimal.squashfs",
        "casper/ubuntu-server-minimal.manifest",
        "casper/ubuntu-server-minimal.size",
        "casper/ubuntu-server-minimal.ubuntu-server.squashfs",
        "casper/ubuntu-server-minimal.ubuntu-server.manifest",
        "casper/ubuntu-server-minimal.ubuntu-server.size"
    )
    # Ubuntu's install-sources.yaml marks ubuntu-server as the default
    # fsimage-layered source. Apply the minimized base first, then the
    # normal Ubuntu Server layer.
    $layers = @(
        "ubuntu-server-minimal.squashfs",
        "ubuntu-server-minimal.ubuntu-server.squashfs"
    )
}

Write-Host "Extracting ISO payload for $Role..."
$args = @("x", $iso, "-o$isoTree", "-y") + $members
& $SevenZip @args
if ($LASTEXITCODE -gt 1) { throw "ISO extraction failed with exit code $LASTEXITCODE" }
if ($LASTEXITCODE -eq 1) { Write-Warning "ISO extraction completed with warnings" }

foreach ($layer in $layers) {
    $squash = Join-Path $isoTree "casper\$layer"
    if (-not (Test-Path $squash)) { throw "SquashFS layer not found: $squash" }

    Write-Host "Cataloging SquashFS layer: $layer"
    $catalog = Join-Path $isoTree "casper\$layer.slt.txt"
    & $SevenZip l -slt $squash | Set-Content -Path $catalog -Encoding UTF8

    Write-Host "Extracting SquashFS layer: $layer"
    $oldErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $SevenZip x $squash "-o$rootfs" -aoa -y
    $extractCode = $LASTEXITCODE
    $ErrorActionPreference = $oldErrorPreference

    if ($extractCode -gt 1) { throw "SquashFS extraction failed for $layer with exit code $extractCode" }
    if ($extractCode -eq 1) {
        Write-Warning "SquashFS layer $layer extracted with link/metadata warnings; catalog preserved at $catalog"
    }
}

Write-Host "Root filesystem ready: $rootfs"
Get-ChildItem $rootfs | Select-Object Name,Mode | Format-Table -AutoSize

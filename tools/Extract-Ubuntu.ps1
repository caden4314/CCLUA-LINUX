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
$isoName = if ($Role -eq "desktop") { "ubuntu-22.04.5-desktop-amd64.iso" } else { "ubuntu-22.04.5-live-server-amd64.iso" }
$iso = Join-Path $cache $isoName
if (-not (Test-Path $iso)) { throw "ISO not found: $iso" }

$work = Join-Path $RepoRoot "extracted\ubuntu-22.04.5\$Role"
$isoTree = Join-Path $work "iso"
$rootfs = Join-Path $work "rootfs"
$layerRoot = Join-Path $work "layers"

if (Test-Path $rootfs) { Remove-Item $rootfs -Recurse -Force }
if (Test-Path $layerRoot) { Remove-Item $layerRoot -Recurse -Force }
New-Item -ItemType Directory -Path $isoTree -Force | Out-Null
New-Item -ItemType Directory -Path $rootfs -Force | Out-Null
New-Item -ItemType Directory -Path $layerRoot -Force | Out-Null

if ($Role -eq "desktop") {
    $members = @("casper/filesystem.squashfs","casper/filesystem.manifest","casper/filesystem.size")
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
}

Write-Host "Extracting ISO payload for $Role..."
$isoArgs = @("x", $iso, "-o$isoTree", "-y") + $members
& $SevenZip @isoArgs
if ($LASTEXITCODE -gt 1) { throw "ISO extraction failed with exit code $LASTEXITCODE" }
if ($LASTEXITCODE -eq 1) { Write-Warning "ISO extraction completed with warnings" }

function Extract-SquashLayer {
    param(
        [Parameter(Mandatory=$true)][string]$Layer,
        [Parameter(Mandatory=$true)][string]$Destination
    )

    $squash = Join-Path $isoTree "casper\$Layer"
    if (-not (Test-Path $squash)) { throw "SquashFS layer not found: $squash" }

    Write-Host "Cataloging SquashFS layer: $Layer"
    $catalog = Join-Path $isoTree "casper\$Layer.slt.txt"
    & $SevenZip l -slt $squash | Set-Content -Path $catalog -Encoding UTF8

    if (Test-Path $Destination) { Remove-Item $Destination -Recurse -Force }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    Write-Host "Extracting SquashFS layer: $Layer"
    $safeLayer = $Layer -replace "[^A-Za-z0-9._-]","_"
    $stdoutLog = Join-Path $isoTree "casper\$safeLayer.extract.stdout.log"
    $stderrLog = Join-Path $isoTree "casper\$safeLayer.extract.stderr.log"
    $arguments = @("x", $squash, "-o$Destination", "-aoa", "-y")
    $proc = Start-Process -FilePath $SevenZip -ArgumentList $arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
    $extractCode = $proc.ExitCode

    if ($extractCode -ne 0) {
        $errorLines = @(Get-Content $stderrLog -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne "" })
        $unexpected = @($errorLines | Where-Object {
            $_ -notmatch "^ERROR: Cannot create symbolic link" -and
            $_ -notmatch "^ERROR: Dangerous link path was ignored" -and
            $_ -notmatch "^ERROR: Temporary link file is not empty" -and
            $_ -notmatch "^ERROR: Cannot create .* special file" -and
            $_ -notmatch "^ERROR: Cannot create .* device"
        })
        if ($unexpected.Count -gt 0) {
            $sample = ($unexpected | Select-Object -First 5) -join " | "
            throw "SquashFS extraction failed for $Layer; unexpected 7-Zip errors: $sample"
        }
        Write-Warning "SquashFS layer $Layer extracted with $($errorLines.Count) expected Windows/Linux metadata warnings; catalog preserved at $catalog"
    }
    return $catalog
}

if ($Role -eq "desktop") {
    Extract-SquashLayer -Layer "filesystem.squashfs" -Destination $rootfs | Out-Null
} else {
    Extract-SquashLayer -Layer "ubuntu-server-minimal.squashfs" -Destination $rootfs | Out-Null

    $overlay = Join-Path $layerRoot "ubuntu-server"
    $overlayCatalog = Extract-SquashLayer -Layer "ubuntu-server-minimal.ubuntu-server.squashfs" -Destination $overlay

    Write-Host "Applying Ubuntu Server overlay semantics..."
    $mergeOutput = Join-Path $work "server-layer-merge.json"
    python "$RepoRoot\tools\merge_squashfs_layer.py" --base-root $rootfs --overlay-root $overlay --catalog $overlayCatalog --output $mergeOutput
    if ($LASTEXITCODE -ne 0) { throw "Server SquashFS layer merge failed" }
}

$requiredPaths = @(
    (Join-Path $rootfs "usr"),
    (Join-Path $rootfs "usr\lib\os-release"),
    (Join-Path $rootfs "var\lib\dpkg\status")
)
foreach ($required in $requiredPaths) {
    if (-not (Test-Path $required)) { throw "Extracted rootfs validation failed; missing $required" }
}

Write-Host "Root filesystem ready: $rootfs"
Get-Content (Join-Path $rootfs "usr\lib\os-release") | Select-Object -First 6

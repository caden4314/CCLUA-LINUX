$ErrorActionPreference = 'Stop'
$root = 'C:\Dev\CCLUA-LINUX'
& (Join-Path $root 'Build.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$craft = Join-Path $root 'tools\CraftOS-PC\CraftOS-PC_console.exe'
$computers = Join-Path $root 'runtime\computer'
$scaleFile = Join-Path $root 'runtime\computer\2710\.cclua\data\apps\settings\ui-scale'
$scale = '0.5'
if (Test-Path $scaleFile) {
    $candidate = (Get-Content -LiteralPath $scaleFile -Raw).Trim()
    if ($candidate -in @('1.0','0.5')) { $scale = $candidate }
}

$configPath = Join-Path $env:APPDATA 'CraftOS-PC\config\global.json'
$originalConfig = $null
if (Test-Path $configPath) {
    $originalConfig = Get-Content -LiteralPath $configPath -Raw
    $config = $originalConfig | ConvertFrom-Json
    if ($scale -eq '0.5') {
        $config.customCharScale = 1
        $config.defaultWidth = 102
        $config.defaultHeight = 38
    } else {
        $config.customCharScale = 2
        $config.defaultWidth = 51
        $config.defaultHeight = 19
    }
    $config | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $configPath -Encoding UTF8
}

Write-Host "CCLUA-LINUX UI scale: $scale"
try {
    & $craft -C $computers -i 2710 --gui
}
finally {
    if ($null -ne $originalConfig) {
        [System.IO.File]::WriteAllText($configPath, $originalConfig, [System.Text.UTF8Encoding]::new($false))
    }
}

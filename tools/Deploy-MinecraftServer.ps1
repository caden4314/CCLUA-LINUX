param(
    [string]$RepoRoot = "C:\Dev\CCLUA-LINUX",
    [string]$WorldPath = "$env:APPDATA\PrismLauncher\instances\CCLUA-Dev-1.20.1\minecraft\saves\COMPUTERS"
)

$ErrorActionPreference = "Stop"

$ComputerRoot = Join-Path $WorldPath "computercraft\computer"
New-Item -ItemType Directory -Path $ComputerRoot -Force | Out-Null

$Machines = @(
    @{
        Id = 0
        Label = "SERVER_CYAN"
        Hostname = "server-cyan"
        Role = "server"
        Address = "10.27.0.11"
        Manager = "10.27.0.1"
    },
    @{
        Id = 1
        Label = "SERVER_ORANGE"
        Hostname = "server-orange"
        Role = "server"
        Address = "10.27.0.12"
        Manager = "10.27.0.1"
    },
    @{
        Id = 2
        Label = "SERVER_RED"
        Hostname = "manager"
        Role = "manager"
        Address = "10.27.0.1"
        Manager = "10.27.0.1"
    }
)

function Copy-Tree {
    param([string]$Source,[string]$Destination)
    if (-not (Test-Path $Source)) { return }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item (Join-Path $Source "*") $Destination -Recurse -Force
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-Utf8NoBom {
    param([string]$Path,[string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

foreach ($Machine in $Machines) {
    $Disk = Join-Path $ComputerRoot ([string]$Machine.Id)
    New-Item -ItemType Directory -Path $Disk -Force | Out-Null

    # Shared image/runtime.
    Copy-Tree (Join-Path $RepoRoot "src\kernel") (Join-Path $Disk "System\kernel")
    Copy-Tree (Join-Path $RepoRoot "src\init")   (Join-Path $Disk "System\init")
    Copy-Tree (Join-Path $RepoRoot "src\usr")    (Join-Path $Disk "usr")
    Copy-Tree (Join-Path $RepoRoot "src\lib")    (Join-Path $Disk "lib")
    Copy-Tree (Join-Path $RepoRoot "src\etc")    (Join-Path $Disk "etc")

    # Required writable state.
    New-Item -ItemType Directory -Path (Join-Path $Disk "root") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Disk "home\caden") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Disk "var\log") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Disk "var\lib\cclua") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Disk "etc\cclua") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Disk "tmp") -Force | Out-Null

    # Machine-specific identity.
    Write-Utf8NoBom -Path (Join-Path $Disk "etc\hostname") -Content ($Machine.Hostname + [Environment]::NewLine)

    $Config = [ordered]@{
        schema = 1
        computer_id = $Machine.Id
        label = $Machine.Label
        hostname = $Machine.Hostname
        role = $Machine.Role
        address = $Machine.Address
        netmask = "255.255.255.0"
        manager = $Machine.Manager
        network = "10.27.0.0/24"
        image = "ubuntu-22.04-server"
        ubuntu_reference = "22.04.5"
        channel = "development"
    }
    $ConfigJson = $Config | ConvertTo-Json -Depth 5
    Write-Utf8NoBom -Path (Join-Path $Disk "etc\cclua\machine.json") -Content ($ConfigJson + [Environment]::NewLine)

    # Startup is intentionally tiny: establish identity, then hand off to PID 1.
    $Startup = @"
local expectedId = $($Machine.Id)
local expectedLabel = "$($Machine.Label)"

if os.getComputerID() ~= expectedId then
    error(("CCLUA disk identity mismatch: expected ID %d, running on ID %d"):format(expectedId, os.getComputerID()))
end

if os.getComputerLabel() ~= expectedLabel then
    os.setComputerLabel(expectedLabel)
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1,1)

local ok, err = pcall(dofile, "/System/init/init.lua")
if not ok then
    term.setTextColor(colors.red)
    print("")
    print("CCLUA BOOT FAILED")
    term.setTextColor(colors.white)
    print(tostring(err))
    while true do
        os.pullEvent()
    end
end
"@
    Write-Utf8NoBom -Path (Join-Path $Disk "startup.lua") -Content $Startup

    Write-Host ("DEPLOYED ID {0} | {1} | {2} | {3}" -f $Machine.Id,$Machine.Label,$Machine.Role,$Machine.Address)
}

Write-Host ""
Write-Host "Deployment complete."

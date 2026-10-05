$ErrorActionPreference = "Stop"

$Root = "E:\Minecraft\CCLUA-Server"
$Java = "C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot\bin\java.exe"
$Jar = Join-Path $Root "fabric-server-launch.jar"
$Control = Join-Path $Root "control"
$Logs = Join-Path $Root "logs"
$Backups = Join-Path $Root "backups"
$SupervisorLog = Join-Path $Logs "supervisor.log"

New-Item -ItemType Directory -Force -Path $Control,$Logs,$Backups | Out-Null

function Write-SupervisorLog {
    param([string]$Message)
    $line = "$(Get-Date -Format o) $Message"
    Add-Content -Path $SupervisorLog -Value $line
}

function Backup-World {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $dest = Join-Path $Backups "world-$stamp.zip"
    Write-SupervisorLog "Creating clean stopped-world backup $dest"
    Compress-Archive -Path (Join-Path $Root "world\*") -DestinationPath $dest -CompressionLevel Fastest
    Get-ChildItem $Backups -Filter "world-*.zip" -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip 10 |
        Remove-Item -Force
    Write-SupervisorLog "Backup complete $dest"
}

function Port-In-Use {
    return [bool](Get-NetTCPConnection -LocalAddress "100.76.188.26" -LocalPort 25565 -State Listen -ErrorAction SilentlyContinue)
}

if (Port-In-Use) {
    Write-SupervisorLog "Port 100.76.188.26:25565 already has a listener; supervisor will not start a duplicate."
    exit 0
}

$crashes = @()
while ($true) {
    $consoleLog = Join-Path $Logs ("server-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
    Write-SupervisorLog "Starting Fabric dedicated server"

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Java
    $psi.WorkingDirectory = $Root
    $psi.Arguments = '-Xms4G -Xmx10G -XX:+UseG1GC -jar "fabric-server-launch.jar" nogui'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    [void]$proc.Start()

    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    $requestedStop = $false
    $backupRestart = $false

    while (-not $proc.HasExited) {
        if (Test-Path (Join-Path $Control "backup-restart")) {
            Remove-Item (Join-Path $Control "backup-restart") -Force
            $backupRestart = $true
            Write-SupervisorLog "Backup-restart requested; issuing clean Minecraft stop"
            $proc.StandardInput.WriteLine("save-all flush")
            Start-Sleep -Seconds 2
            $proc.StandardInput.WriteLine("stop")
        } elseif (Test-Path (Join-Path $Control "stop")) {
            Remove-Item (Join-Path $Control "stop") -Force
            $requestedStop = $true
            Write-SupervisorLog "Clean stop requested"
            $proc.StandardInput.WriteLine("stop")
        }
        Start-Sleep -Milliseconds 750
    }

    $proc.WaitForExit()
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    Set-Content -Path $consoleLog -Value $stdout -Encoding utf8
    if ($stderr) { Add-Content -Path $consoleLog -Value $stderr -Encoding utf8 }

    Write-SupervisorLog "Minecraft exited with code $($proc.ExitCode)"

    if ($backupRestart) {
        Backup-World
        Start-Sleep -Seconds 2
        continue
    }
    if ($requestedStop -or $proc.ExitCode -eq 0) {
        Write-SupervisorLog "Normal shutdown; supervisor exiting"
        break
    }

    $now = Get-Date
    $crashes = @($crashes | Where-Object { ($now - $_).TotalMinutes -lt 10 })
    $crashes += $now
    if ($crashes.Count -gt 3) {
        Write-SupervisorLog "Crash loop protection tripped (>3 crashes/10m); not restarting"
        break
    }

    Write-SupervisorLog "Unexpected exit; restarting in 10 seconds"
    Start-Sleep -Seconds 10
}

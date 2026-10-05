param()

$ErrorActionPreference = "Stop"
$health = "http://127.0.0.1:8765/v1/health"
$pythonw = "C:\Users\Jeff482\AppData\Local\Programs\Python\Python312\pythonw.exe"
$bridge = "E:\Minecraft\CCLUA-LINUX\tools\harmoni_cc_bridge.py"

try {
    $r = Invoke-WebRequest -UseBasicParsing -Uri $health -TimeoutSec 2
    if ($r.StatusCode -eq 200) { exit 0 }
} catch {
    # Not running yet.
}

if (!(Test-Path $pythonw)) { throw "pythonw.exe not found: $pythonw" }
if (!(Test-Path $bridge)) { throw "Harmoni bridge not found: $bridge" }

Start-Process -FilePath $pythonw -ArgumentList @($bridge) -WindowStyle Hidden
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 250
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Uri $health -TimeoutSec 1
        if ($r.StatusCode -eq 200) { exit 0 }
    } catch {}
}

throw "Harmoni bridge did not become healthy on port 8765."

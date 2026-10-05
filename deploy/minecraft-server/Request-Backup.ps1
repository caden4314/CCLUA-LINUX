$Control = "E:\Minecraft\CCLUA-Server\control"
New-Item -ItemType Directory -Force -Path $Control | Out-Null
Set-Content -Path (Join-Path $Control "backup-restart") -Value (Get-Date -Format o) -Encoding ascii

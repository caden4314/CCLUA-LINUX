$ErrorActionPreference = 'Stop'
$root = 'C:\Dev\CCLUA-LINUX'
$src = Join-Path $root 'src'
$dist = Join-Path $root 'dist'
$iso = Join-Path $dist 'CCLUA-LINUX.luaiso'
$bundled = Join-Path $src 'system\packages'
New-Item -ItemType Directory -Force -Path $bundled | Out-Null

python (Join-Path $root 'tools\build_pkg.py') (Join-Path $root 'packages\lua-ssh') (Join-Path $bundled 'lua-ssh.luapkg')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

python (Join-Path $root 'tools\build_iso.py') --src $src --out $iso --version '0.1.0' --channel 'dev'
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

python (Join-Path $root 'tools\prepare_runtime.py') --id 2710
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Get-Item $iso | Select-Object FullName,Length,LastWriteTime

$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $root 'Build.ps1')
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}

$craft=Join-Path $root 'tools\CraftOS-PC\CraftOS-PC_console.exe'
$computers=Join-Path $root 'runtime\computer'
$cases=@(
  @{Id=2798;Scale='0.5';Expected='display=102x34'},
  @{Id=2797;Scale='0.25';Expected='display=153x57'}
)

foreach($case in $cases){
  $id=$case.Id
  $dir=Join-Path $computers ([string]$id)
  if(Test-Path $dir){Remove-Item -Recurse -Force $dir}
  python (Join-Path $root 'tools\prepare_runtime.py') --id $id | Out-Null
  if($LASTEXITCODE -ne 0){throw "prepare_runtime failed for $id"}
  $settings=Join-Path $dir '.cclua\data\apps\settings'
  New-Item -ItemType Directory -Force -Path $settings | Out-Null
  Set-Content -LiteralPath (Join-Path $settings 'ui-scale') -Value $case.Scale -NoNewline -Encoding ascii
  New-Item -ItemType File -Force -Path (Join-Path $dir '.cclua\smoke') | Out-Null

  & $craft -C $computers -i $id --gui
  if($LASTEXITCODE -ne 0){throw "CraftOS-PC pixel smoke failed for scale $($case.Scale)"}

  $result=Join-Path $dir '.cclua\smoke-result.txt'
  if(-not (Test-Path $result)){throw "No smoke result for scale $($case.Scale)"}
  $lines=@(Get-Content $result)
  foreach($required in @('CCLUA_LINUX_SMOKE_PASS','display.endpoint=pixel16',$case.Expected,'ui.files=pass','vfs.linux=pass')){
    if($lines -notcontains $required){throw "Scale $($case.Scale) missing: $required"}
  }
  Write-Host "Pixel smoke PASS scale=$($case.Scale) $($case.Expected)"
}

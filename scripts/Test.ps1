param([string]$LuaPath='lua',[string]$ZigPath='zig',[switch]$SkipNative)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$lua=(Get-Command $LuaPath -ErrorAction Stop).Source
Push-Location $root
try{
 $guardBin=Join-Path $root ('analysis/guard-tests/'+[guid]::NewGuid().ToString('N'))
 $null=New-Item -ItemType Directory -Path $guardBin -Force
 Get-ChildItem mods/ClanTools/bin -Filter '*.dll' -File|Copy-Item -Destination $guardBin
 $suites=@(Get-ChildItem mods/ClanTools/tests,mods/ClanLoader/tests -File -Filter '*.test.lua'|Sort-Object FullName)
 foreach($test in $suites){& $lua $test.FullName ($guardBin.Replace('\','/')+'/');if($LASTEXITCODE -ne 0){throw "Failed: $($test.Name)"}}
 foreach($test in @('mods/ClanLoader/tests/launcher-policy.test.ps1','mods/ClanLoader/tests/manager.test.ps1','mods/ClanTools/tests/package.test.ps1','mods/ClanTools/tests/release-inputs.test.ps1')){
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $test
  if($LASTEXITCODE -ne 0){throw "Failed: $test"}
 }
 $nativeCount=0
 if(!$SkipNative){
  $zig=(Get-Command $ZigPath -ErrorAction Stop).Source
  $out=Join-Path $root 'analysis/native-tests';$null=New-Item -ItemType Directory -Path $out -Force
  foreach($test in Get-ChildItem mods/ClanTools/tests -File -Filter '*.test.c'){
   $exe=Join-Path $out ($test.BaseName+'.exe')
   & $zig cc -O2 -Wall -Wextra $test.FullName -o $exe
   if($LASTEXITCODE -ne 0){throw "Native harness build failed: $($test.Name)"}
   & $exe
   if($LASTEXITCODE -ne 0){throw "Native harness failed: $($test.Name)"}
   $nativeCount++
  }
 }
 Write-Output "PASS: $($suites.Count) Lua suites, 4 PowerShell suites, $nativeCount native harnesses. Live gameplay is a separate check."
}finally{Pop-Location}

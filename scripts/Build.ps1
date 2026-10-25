param([string]$ZigPath='zig',[string]$NodePath='node')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$zig=(Get-Command $ZigPath -ErrorAction Stop).Source
$node=(Get-Command $NodePath -ErrorAction Stop).Source
$bin=Join-Path $root 'mods/ClanTools/bin'
$null=New-Item -ItemType Directory -Path $bin -Force
$sources=[ordered]@{
 'clanparty.dll'='mods/ClanParty/native/bridge.c'
 'clanappearance-skins-v8.dll'='mods/ClanTools/native/appearance_bridge.c'
 'item-feedback-v5.dll'='mods/ClanTools/native/item_feedback.c'
 'crafting-v4.dll'='mods/ClanTools/native/crafting.c'
 'admin-heal.dll'='mods/ClanTools/native/admin_heal.c'
 'admin-progression-v2.dll'='mods/ClanTools/native/admin_progression.c'
 'admin-quests-v5.dll'='mods/ClanTools/native/admin_quests.c'
 'admin-sandbox.dll'='mods/ClanTools/native/admin_sandbox.c'
 'admin-inventory.dll'='mods/ClanTools/native/admin_inventory.c'
 'enemy-cleanup.dll'='mods/ClanTools/native/enemy_cleanup.c'
 'follower-appearance-v4.dll'='mods/ClanTools/native/follower_appearance.c'
 'settings-bridge-v2.dll'='mods/ClanTools/native/settings_bridge.c'
 'settings-remap-v3.dll'='mods/ClanTools/native/settings_remap.c'
 'workshop.dll'='mods/ClanTools/native/workshop.c'
}
Push-Location $root
$oldZig=$env:CLANTOOLS_ZIG
try{
 foreach($name in $sources.Keys){
  # Keep the original linker module names for these renamed release DLLs.
  $outputName=switch($name){'clanparty.dll'{'clanparty-next.dll'} 'admin-heal.dll'{'admin-heal-next.dll'} default{$name}}
  $args=@('cc','-shared','-O2','-Wall','-Wextra',(Join-Path $root $sources[$name]),'-o',(Join-Path $bin $outputName))
  if($name -eq 'clanparty.dll'){$args+='-lshell32'}
  & $zig @args
  if($LASTEXITCODE -ne 0){throw "Native build failed: $name"}
  if($outputName -cne $name){Copy-Item -LiteralPath (Join-Path $bin $outputName) -Destination (Join-Path $bin $name) -Force}
 }
 $env:CLANTOOLS_ZIG=$zig
 & $node scripts/CommunityNativeCompare.mjs
 if($LASTEXITCODE -ne 0){throw 'Independent native section audit failed'}
 $selection=Get-Content mods/ClanTools/release/native-selection.community.json -Raw|ConvertFrom-Json
 $selection.preparedUtc=[DateTime]::UtcNow.ToString('o')
 foreach($entry in $selection.files){
  $entry.sha256=(Get-FileHash (Join-Path $bin $entry.source)).Hash
  $entry.acceptance='Fresh local build and independent executable-section audit. Live gameplay validation must be recorded separately.'
  if($entry.destination -cne $entry.source){Copy-Item -LiteralPath (Join-Path $bin $entry.source) -Destination (Join-Path $bin $entry.destination) -Force}
 }
 $selection|ConvertTo-Json -Depth 8|Set-Content analysis/community/native-verify/native-selection.built.json -Encoding UTF8
 $theme=Join-Path $root 'mods/ClanLoader/manager/theme-tools'
 & $zig c++ -O2 '-msse4.1' -DWIN32 -D_WIN64 -include sys/stat.h -Wno-writable-strings -Wno-format (Join-Path $theme 'source/kraken.cpp') (Join-Path $theme 'source/lzna.cpp') (Join-Path $theme 'source/bitknit.cpp') -o (Join-Path $theme 'ooz.exe')
 if($LASTEXITCODE -ne 0){throw 'ooz helper build failed'}
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File mods/ClanLoader/manager/Build-Launcher.ps1
 if($LASTEXITCODE -ne 0){throw 'Manager build failed'}
 Write-Output 'Built native bridges, decoder, manager and icons. No game files changed.'
}finally{$env:CLANTOOLS_ZIG=$oldZig;Pop-Location}

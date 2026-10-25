$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'release/Package.Core.ps1')
$workspace=Split-Path (Split-Path $root -Parent) -Parent
$fixture=Join-Path $workspace ('analysis/release-tests/'+[guid]::NewGuid().ToString('N'))
$package=Join-Path $fixture 'package';$game=Join-Path $fixture 'game';$backups=Join-Path $fixture 'backups';$saves=Join-Path $fixture 'saves'
$win=Join-Path $game 'Wrc/Binaries/Win64';$mod=Join-Path $win 'ue4ss/Mods/ClanTools';$list=Join-Path $win 'ue4ss/Mods/mods.txt'
foreach($dir in @($package,$mod,$saves,(Join-Path $mod 'Scripts'),(Join-Path $package 'payload/ClanTools/Scripts'),(Join-Path $package 'payload/ClanTools/bin'),(Join-Path $package 'payload/ClanTools/data'))){$null=New-Item -ItemType Directory -Path $dir -Force}
function Assert($Value,$Message){if(!$Value){throw "ASSERT: $Message"}}
function Fails([scriptblock]$Action,[string]$Message){$failed=$false;try{&$Action}catch{$failed=$true};Assert $failed $Message}
Assert-LuaReleaseDependencies 'main.lua' 'local m=dofile(folder..''helper.lua''); package.loadlib(dir..''bridge-v4.dll'',''run'')' @('main.lua','helper.lua') @('bridge-v4.dll')
Fails {Assert-LuaReleaseDependencies 'main.lua' 'dofile(folder..''missing.lua'')' @('main.lua') @('bridge.dll')} 'missing Lua dependency rejected'
Fails {Assert-LuaReleaseDependencies 'main.lua' 'require(''missing'')' @('main.lua') @('bridge.dll')} 'extensionless require rejected'
Fails {Assert-LuaReleaseDependencies 'main.lua' 'package.loadlib(dir..''bridge-v5.dll'',''run'')' @('main.lua') @('bridge-v4.dll')} 'new unselected native dependency rejected'
Assert-NativeReleaseDependencies 'bridge.c' '#include "guards.h"' @('bridge.c','guards.h')
Fails {Assert-NativeReleaseDependencies 'bridge.c' '#include "missing.h"' @('bridge.c')} 'missing native source include rejected'
Assert-LuaReleaseDependencies 'inventory.lua' 'read(root..''data/admin-inventory.json'')' @('inventory.lua') @() @('admin-inventory.json')
Fails {Assert-LuaReleaseDependencies 'inventory.lua' 'read(root..''data/admin-inventory.json'')' @('inventory.lua') @() @('catalog.json')} 'missing static inventory catalog rejected'
Write-Output 'PASS missing Lua and native dependencies fail before staging'
$script:running=$false
function Get-Process {param($Name,$ErrorAction)if($script:running){[pscustomobject]@{ProcessName='Wrc-Win64-ShippingDRM'}}}
Write-Utf8 (Join-Path $win 'Wrc-Win64-ShippingDRM.exe') 'fake executable; never executed'
Write-Utf8 (Join-Path $saves 'WrcGame.sav') 'private fixture save'
Write-Utf8 (Join-Path $mod 'settings.json') '{"theme":"light"}'
$userPaths=@('settings.json','settings-extensions.json','keybinds.json','crafting-settings.json','appearance-presets.json','appearance-presets.json.previous.txt','admin-waypoints.json','admin-waypoints.json.previous.txt','photo-settings.json','photo-settings.json.previous.txt','den-layouts.json','den-layouts.json.previous.txt','state/followers.json','state/favorites.json','state/cat-names-player.json','state/party-presets-player.json','state/party-player.json','state/player_0_Chapter00.original.txt','backups/private/WrcGame.json','bin/admin-inventory-request.txt','bin/admin-inventory-status.txt','bin/admin-sandbox-status.txt')
$userPaths+=@('admin-waypoints.json.previous','admin-waypoints.json.tmp','settings-extensions.json.previous','settings-extensions.json.tmp','keybinds.json.previous','keybinds.json.tmp','den-extra-personal.json')
$userHashes=@{}
foreach($relative in $userPaths){$full=Get-ContainedPath $mod $relative;$null=New-Item -ItemType Directory -Path (Split-Path $full -Parent) -Force;if($relative -ne 'settings.json'){Write-Utf8 $full ('private fixture '+$relative)};$userHashes[$relative]=(Get-FileHash -LiteralPath $full).Hash}
function Assert-UserState([string]$Step){foreach($relative in $userPaths){$full=Get-ContainedPath $mod $relative;Assert ((Test-Path -LiteralPath $full) -and (Get-FileHash -LiteralPath $full).Hash -eq $userHashes[$relative]) ($Step+' preserves '+$relative)}}
Write-Utf8 (Join-Path $mod 'Scripts/main.lua') 'old main'
Write-Utf8 $list "; keep comment`r`nOtherMod : 1`r`nClanTools : 0`r`nThirdMod : 0`r`n"
Write-Utf8 (Join-Path $package 'payload/ClanTools/Scripts/main.lua') 'new main'
Write-Utf8 (Join-Path $package 'payload/ClanTools/Scripts/runtime_valid.lua') 'new helper'
Write-Utf8 (Join-Path $package 'payload/ClanTools/bin/mock.dll') 'fake dll; never executed'
foreach($name in @('catalog.json','admin-moves.json','admin-inventory.json')){Write-Utf8 (Join-Path $package ('payload/ClanTools/data/'+$name)) '{"fixture":true}'}
$manifest=[ordered]@{schema=1;name='ClanTools';version='fixture';gameSha256=(Get-FileHash (Join-Path $win 'Wrc-Win64-ShippingDRM.exe')).Hash;files=@()}
foreach($relative in @('Scripts/main.lua','Scripts/runtime_valid.lua','bin/mock.dll','data/catalog.json','data/admin-moves.json','data/admin-inventory.json')){$p='payload/ClanTools/'+$relative;$manifest.files+=@{area='mod';path=$p;sha256=(Get-FileHash (Join-Path $package $p)).Hash}}
Write-Utf8 (Join-Path $package 'manifest.json') ($manifest|ConvertTo-Json -Depth 5)
foreach($private in @('settings.json','crafting-settings.json','profilekeybinds.json','WrcGame.sav','bin/crafting-watch.txt','bin/item-status.txt','command.lua','data/preferences.json')+$userPaths){
 $privatePath='payload/ClanTools/'+$private;$full=Join-Path $package $privatePath
 $null=New-Item -ItemType Directory -Path (Split-Path $full -Parent) -Force
 Write-Utf8 $full 'private fixture must not ship'
 $bad=[ordered]@{schema=1;name='ClanTools';files=@($manifest.files)+@(@{area='mod';path=$privatePath;sha256=(Get-FileHash $full).Hash})}
 Write-Utf8 (Join-Path $package 'manifest.json') ($bad|ConvertTo-Json -Depth 5)
 Fails {Read-PackageManifest $package} ('private payload excluded: '+$private)
}
Write-Utf8 (Join-Path $package 'manifest.json') ($manifest|ConvertTo-Json -Depth 5)
Write-Output 'PASS saves, preferences, mailboxes and runtime commands are refused as mod payloads'
Fails {Get-ContainedPath $fixture '../outside'} 'reject traversal'
Fails {Get-ContainedPath $fixture 'C:\outside'} 'reject absolute paths'
Write-Output 'PASS containment refuses traversal and absolute paths'
$script:running=$true;Fails {Install-ClanToolsPackage $package $game $backups $saves} 'running game rejected';$script:running=$false
Install-ClanToolsPackage $package $game $backups $saves -ValidateOnly
Assert (!(Test-Path $backups)) 'validation creates no backups';Assert ((Get-Content (Join-Path $mod 'Scripts/main.lua') -Raw) -eq 'old main') 'validation keeps old code'
Write-Output 'PASS running-game refusal and validation-only leave installation unchanged'
Write-Utf8 (Join-Path $package 'payload/ClanTools/Scripts/main.lua') 'tampered'
Fails {Install-ClanToolsPackage $package $game $backups $saves} 'tampered payload rejected'
Write-Utf8 (Join-Path $package 'payload/ClanTools/Scripts/main.lua') 'new main'
Install-ClanToolsPackage $package $game $backups $saves
Assert-UserState 'Install'
Assert ((Get-Content (Join-Path $mod 'settings.json') -Raw) -eq '{"theme":"light"}') 'settings preserved'
Assert ((Get-Content $list -Raw) -eq "; keep comment`r`nOtherMod : 1`r`nThirdMod : 0`r`nClanTools : 1`r`n") 'other mods unchanged'
$receipt=Get-Content (Join-Path $mod '.clantools-install.json') -Raw|ConvertFrom-Json
Assert ((Get-Content (Join-Path $receipt.backup 'SaveGames/WrcGame.sav') -Raw) -eq 'private fixture save') 'save backup correct'
Assert ((Get-Content (Join-Path $receipt.backup 'ClanTools/Scripts/main.lua') -Raw) -eq 'old main') 'old mod backup correct'
Write-Output 'PASS verified install preserves other mods/settings and backs up old code/saves'
Write-Utf8 (Join-Path $mod 'Scripts/obsolete.lua') 'old owned code'
$receipt.files+=@{path='Scripts/obsolete.lua';sha256=(Get-FileHash (Join-Path $mod 'Scripts/obsolete.lua')).Hash}
Write-Utf8 (Join-Path $mod '.clantools-install.json') ($receipt|ConvertTo-Json -Depth 5)
Install-ClanToolsPackage $package $game $backups $saves
Assert-UserState 'Upgrade'
foreach($name in @('catalog.json','admin-moves.json','admin-inventory.json')){Assert (Test-Path -LiteralPath (Join-Path $mod ('data/'+$name))) ('Static metadata installed: '+$name)}
Assert (!(Test-Path (Join-Path $mod 'Scripts/obsolete.lua'))) 'obsolete owned code retired'
Assert (Test-Path (Join-Path $mod 'settings.json')) 'upgrade retains settings'
Write-Output 'PASS upgrade retires only unchanged previously owned files'
$goodReceipt=[IO.File]::ReadAllText((Join-Path $mod '.clantools-install.json'))
$badReceipt=$goodReceipt|ConvertFrom-Json;$badReceipt.files+=@{path='state/favorites.json';sha256=$userHashes['state/favorites.json']}
Write-Utf8 (Join-Path $mod '.clantools-install.json') ($badReceipt|ConvertTo-Json -Depth 5)
Fails {Install-ClanToolsPackage $package $game $backups $saves} 'private sidecar cannot become prior owned file'
Fails {Uninstall-ClanToolsPackage $game $backups $saves} 'private sidecar cannot be removed through receipt'
Assert-UserState 'Rejected private ownership'
Write-Utf8 (Join-Path $mod '.clantools-install.json') $goodReceipt
Write-Output 'PASS ownership receipts cannot claim preferences, aliases, presets or saved layouts'
Write-Utf8 (Join-Path $mod 'Scripts/main.lua') 'previous working revision'
$script:failCopy=$true
function Copy-Item {param($LiteralPath,$Destination,[switch]$Recurse,[switch]$Force)
 if($script:failCopy -and $Destination -eq (Join-Path $mod 'Scripts/runtime_valid.lua')){$script:failCopy=$false;throw 'injected write failure'}
 Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Recurse:$Recurse -Force:$Force
}
Fails {Install-ClanToolsPackage $package $game $backups $saves} 'injected write failure'
Assert-UserState 'Rollback'
Assert ((Get-Content (Join-Path $mod 'Scripts/main.lua') -Raw) -eq 'previous working revision') 'rollback restores previous main'
Assert ((Get-Content $list -Raw).Contains('OtherMod : 1')) 'rollback preserves mod list'
Write-Output 'PASS partial write failure restores prior owned files and enable list'
Write-Utf8 (Join-Path $mod 'Scripts/main.lua') 'user modification'
Write-Utf8 (Join-Path $mod 'enabled.txt') ''
Uninstall-ClanToolsPackage $game $backups $saves
Assert-UserState 'Uninstall'
foreach($name in @('catalog.json','admin-moves.json','admin-inventory.json')){Assert (!(Test-Path -LiteralPath (Join-Path $mod ('data/'+$name)))) ('Unchanged shipped metadata removed: '+$name)}
Assert (!(Test-Path (Join-Path $mod 'bin/mock.dll'))) 'owned dll removed'
Assert ((Get-Content (Join-Path $mod 'Scripts/main.lua') -Raw) -eq 'user modification') 'modified source preserved'
Assert (Test-Path (Join-Path $mod 'settings.json')) 'user settings retained'
Assert (!(Test-Path (Join-Path $mod 'enabled.txt'))) 'enabled marker removed'
Assert ((Get-Content $list -Raw) -eq "; keep comment`r`nOtherMod : 1`r`nThirdMod : 0`r`n") 'only ClanTools line removed'
Write-Output 'PASS uninstall removes owned unchanged files and own enablement only'
$loaderPayload=Join-Path $package 'loader/ue4ss';$null=New-Item -ItemType Directory -Path $loaderPayload -Force
Write-Utf8 (Join-Path $loaderPayload 'UE4SS.dll') 'approved fixture loader'
Write-Utf8 (Join-Path $loaderPayload 'UE4SS-settings.ini') 'default fixture settings'
foreach($relative in @('UE4SS.dll','UE4SS-settings.ini')){$manifest.files+=@{area='loader';path=('loader/ue4ss/'+$relative);sha256=(Get-FileHash (Join-Path $loaderPayload $relative)).Hash}}
Write-Utf8 (Join-Path $package 'manifest.json') ($manifest|ConvertTo-Json -Depth 5)
Write-Utf8 (Join-Path $win 'ue4ss/UE4SS.dll') 'different existing loader'
Fails {Install-ClanToolsPackage $package $game $backups $saves} 'existing different loader refused'
Assert ((Get-Content (Join-Path $win 'ue4ss/UE4SS.dll') -Raw) -eq 'different existing loader') 'different loader untouched'
Write-Utf8 (Join-Path $win 'ue4ss/UE4SS.dll') 'approved fixture loader'
Write-Utf8 (Join-Path $win 'ue4ss/UE4SS-settings.ini') 'custom existing settings'
Install-ClanToolsPackage $package $game $backups $saves
Assert-UserState 'Reinstall'
Assert ((Get-Content (Join-Path $win 'ue4ss/UE4SS-settings.ini') -Raw) -eq 'custom existing settings') 'loader settings preserved'
Write-Output 'PASS different loader refused; identical loader reused without replacing its settings'
Uninstall-ClanToolsPackage $game $backups $saves -DisableOnly
Assert-UserState 'Disable'
Assert (Test-Path -LiteralPath (Join-Path $mod 'data/admin-inventory.json')) 'Disable retains installed metadata'
Write-Output "PASS all$($userPaths.Count) personal sidecars and nested state/backups survive install, upgrade, rollback, uninstall, reinstall and disable"
Write-Output "Synthetic fixture retained at: $fixture"

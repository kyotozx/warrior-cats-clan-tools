$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../manager/Manager.Core.ps1')
function Assert-GameClosed {} # Filesystem fixture; never targets an installation.
function Check($Value,[string]$Message){if(!$Value){throw $Message};$script:checks++}
function Reject([scriptblock]$Fn){$failed=$false;try{& $Fn|Out-Null}catch{$failed=$true};Check $failed 'Expected rejection'}
$script:checks=0
$fixture=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../analysis/community'))) ('manager-test-'+[guid]::NewGuid().ToString('N'))
$mods=Join-Path $fixture 'Mods';$pkg=Join-Path $fixture 'package';$null=New-Item -ItemType Directory -Path $mods,(Join-Path $pkg 'payload/TestMod/Scripts') -Force
Write-Utf8 (Join-Path $mods 'mods.txt') "OtherMod : 1`r`n"
Write-Utf8 (Join-Path $pkg 'payload/TestMod/Scripts/main.lua') "print('Example')"
$m=[ordered]@{schema=1;loaderApi=1;gameBuild='24847281';id='TestMod';name='Test mod';version='1.0.0';description='Fixture';dependencies=@();files=@(@{path='Scripts/main.lua';sha256=(Get-FileHash (Join-Path $pkg 'payload/TestMod/Scripts/main.lua')).Hash})}
Write-Utf8 (Join-Path $pkg 'mod.json') ($m|ConvertTo-Json -Depth 8)
$null=Install-CommunityPackage $pkg $mods
Check (Test-Path (Join-Path $mods 'TestMod/Scripts/main.lua')) 'Install failed'
Check ((Get-ModStates ([IO.File]::ReadAllText((Join-Path $mods 'mods.txt')))).OtherMod) 'Other mod changed'
Write-Utf8 (Join-Path $mods 'TestMod/skins.json') 'personal'
Set-ManagedModEnabled $mods TestMod $false
$m.version='1.1.0';Write-Utf8 (Join-Path $pkg 'mod.json') ($m|ConvertTo-Json -Depth 8)
$null=Install-CommunityPackage $pkg $mods
Check (!((Get-ModStates ([IO.File]::ReadAllText((Join-Path $mods 'mods.txt')))).TestMod)) 'Update enabled a disabled mod'
Check ([IO.File]::ReadAllText((Join-Path $mods 'TestMod/skins.json')) -eq 'personal') 'Update replaced personal data'
Set-ManagedModEnabled $mods TestMod $true
$r=Read-ModRegistry $mods;$r.mods+=@([pscustomobject]@{id='Dependent';name='Dependent';version='1';description='';dependencies=@('TestMod');files=@()});Save-ModRegistry $mods $r
Write-Utf8 (Join-Path $mods 'mods.txt') (Set-ModStateText ([IO.File]::ReadAllText((Join-Path $mods 'mods.txt'))) Dependent $true)
Reject {Set-ManagedModEnabled $mods TestMod $false}
Set-ManagedModEnabled $mods Dependent $false
$null=Remove-ManagedMod $mods TestMod
Check (!(Test-Path (Join-Path $mods 'TestMod/Scripts/main.lua'))) 'Uninstall kept unchanged owned file'
Check (Test-Path (Join-Path $mods 'TestMod/skins.json')) 'Uninstall deleted personal data'
Reject {Get-ContainedPath $mods '../escape'}
Reject {Set-ModStateText '' 'Bad/Id' $true}
Reject {Get-ModStates "TestMod : 1`nTestMod : 0"}
$m.files[0].path='../../save.sav';Write-Utf8 (Join-Path $pkg 'mod.json') ($m|ConvertTo-Json -Depth 8);Reject {Read-CommunityPackage $pkg}
$m.files[0].path='Scripts/main.lua';$m.files[0].sha256='0'*64;Write-Utf8 (Join-Path $pkg 'mod.json') ($m|ConvertTo-Json -Depth 8);Reject {Read-CommunityPackage $pkg}
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Bad-Zip([string]$Name){$p=Join-Path $fixture ([guid]::NewGuid().ToString('N')+'.zip');$a=[IO.Compression.ZipFile]::Open($p,'Create');try{$e=$a.CreateEntry($Name);$w=[IO.StreamWriter]::new($e.Open());$w.Write('bad');$w.Dispose()}finally{$a.Dispose()};return $p}
foreach($name in @('../escape.lua','C:/escape.lua','payload/TestMod/Scripts/../../save.sav','payload/TestMod/skins.json')){Reject {Expand-CommunityZip (Bad-Zip $name) (Join-Path $fixture ([guid]::NewGuid().ToString('N')))}}
# Upgrade retires unchanged old code while preserving local edits and state.
$m.files[0].sha256=(Get-FileHash (Join-Path $pkg 'payload/TestMod/Scripts/main.lua')).Hash
$extra=Join-Path $pkg 'payload/TestMod/Scripts/retired.lua';Write-Utf8 $extra "return 'old'"
$m.files+=@(@{path='Scripts/retired.lua';sha256=(Get-FileHash $extra).Hash})
Write-Utf8 (Join-Path $pkg 'mod.json') ($m|ConvertTo-Json -Depth 8)
$null=Install-CommunityPackage $pkg $mods
$m.files=@($m.files|Where-Object {$_.path -ne 'Scripts/retired.lua'})
Write-Utf8 (Join-Path $pkg 'mod.json') ($m|ConvertTo-Json -Depth 8)
$null=Install-CommunityPackage $pkg $mods
Check (!(Test-Path (Join-Path $mods 'TestMod/Scripts/retired.lua'))) 'Upgrade retained retired code'
$r=Read-ModRegistry $mods;$r.mods+=@([pscustomobject]@{id='ClanLoader';name='Manager';version='1';description='';dependencies=@();files=@()});Save-ModRegistry $mods $r
Write-Utf8 (Join-Path $mods 'mods.txt') (Set-ModStateText ([IO.File]::ReadAllText((Join-Path $mods 'mods.txt'))) ClanLoader $true)
Set-ManagedModEnabled $mods ClanLoader $false
Check (!((Get-ModStates ([IO.File]::ReadAllText((Join-Path $mods 'mods.txt')))).ClanLoader)) 'External recovery could not disable manager'
$null=Remove-ManagedMod $mods ClanLoader
Check (@((Read-ModRegistry $mods).mods|Where-Object {$_.id -eq 'ClanLoader'}).Count -eq 0) 'Manager uninstall kept registry entry'
Write-Output "PASS $script:checks manager lifecycle, dependency and package-boundary checks. Fixture: $fixture"

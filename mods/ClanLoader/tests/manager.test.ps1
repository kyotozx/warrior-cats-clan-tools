$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../manager/Manager.Core.ps1')
function Assert-GameClosed {} # Filesystem fixture; never targets an installation.
function Check($Value,[string]$Message){if(!$Value){throw $Message};$script:checks++}
function Reject([scriptblock]$Fn){$failed=$false;try{& $Fn|Out-Null}catch{$failed=$true};Check $failed 'Expected rejection'}
$script:checks=0
$fixture=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../analysis/community'))) ('manager-test-'+[guid]::NewGuid().ToString('N'))
$env:LOCALAPPDATA=Join-Path $fixture 'LocalAppData'
$mods=Join-Path $fixture 'Mods';$pkg=Join-Path $fixture 'package';$null=New-Item -ItemType Directory -Path $mods,(Join-Path $pkg 'payload/TestMod/Scripts') -Force
Write-Utf8 (Join-Path $mods 'mods.txt') "OtherMod : 1`r`n"
Write-Utf8 (Join-Path $pkg 'payload/TestMod/Scripts/main.lua') "print('Example')"
$m=[ordered]@{schema=1;loaderApi=1;gameBuild='26184573';id='TestMod';name='Test mod';version='1.0.0';description='Fixture';dependencies=@();files=@(@{path='Scripts/main.lua';sha256=(Get-FileHash (Join-Path $pkg 'payload/TestMod/Scripts/main.lua')).Hash})}
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

# Existing UE4SS marker activation must be visible and actually disabled.
$list=Join-Path $mods 'mods.txt';$marker=Join-Path $mods 'TestMod/enabled.txt';$entry=Join-Path $mods 'TestMod/Scripts/main.lua'
Write-Utf8 $list (Set-ModStateText ([IO.File]::ReadAllText($list)) TestMod $false)
Write-Utf8 $marker 'marker bytes'
Check (Test-ManagedModEnabled $mods (Get-ModStates ([IO.File]::ReadAllText($list))) TestMod) 'Marker activation was not detected'
Set-ManagedModEnabled $mods TestMod $false
Check (!(Test-Path -LiteralPath $marker)) 'Disable retained enabled.txt'
Check (!(Test-ManagedModEnabled $mods (Get-ModStates ([IO.File]::ReadAllText($list))) TestMod)) 'Disable left effective activation'
Write-Utf8 $marker 'marker bytes'
$null=Install-CommunityPackage $pkg $mods
Check ((Get-ModStates ([IO.File]::ReadAllText($list))).TestMod) 'Upgrade did not preserve marker activation'
Check (!(Test-Path -LiteralPath $marker)) 'Upgrade did not migrate marker activation'

# Marker-only dependents must block disabling their dependency, including casing.
$dependentMarker=Join-Path $mods 'Dependent/enabled.txt';$null=New-Item -ItemType Directory -Path (Split-Path $dependentMarker) -Force
$r=Read-ModRegistry $mods;($r.mods|Where-Object {$_.id -eq 'Dependent'}).dependencies=@('testmod');Save-ModRegistry $mods $r
Write-Utf8 $dependentMarker ''
Reject {Set-ManagedModEnabled $mods TestMod $false}
Set-ManagedModEnabled $mods Dependent $false
Check (!(Test-Path -LiteralPath $dependentMarker)) 'Dependent marker survived disable'

# Reject package identity changes before touching payload, registry or mod order.
$oldList=[IO.File]::ReadAllText($list);$oldRegistry=[IO.File]::ReadAllText((Join-Path $mods 'ClanLoader/registry.json'));$oldHash=(Get-FileHash $entry).Hash
$m.id='testmod';Write-Utf8 (Join-Path $pkg 'mod.json') ($m|ConvertTo-Json -Depth 8)
Reject {Install-CommunityPackage $pkg $mods}
Check ([IO.File]::ReadAllText($list) -ceq $oldList) 'Case-only ID changed load order'
Check ([IO.File]::ReadAllText((Join-Path $mods 'ClanLoader/registry.json')) -ceq $oldRegistry) 'Case-only ID changed registry'
Check ((Get-FileHash $entry).Hash -eq $oldHash) 'Case-only ID changed payload'
$m.id='TestMod';$m.dependencies=@('testmod');Write-Utf8 (Join-Path $pkg 'mod.json') ($m|ConvertTo-Json -Depth 8);Reject {Read-CommunityPackage $pkg}
$m.dependencies=@();Write-Utf8 (Join-Path $pkg 'mod.json') ($m|ConvertTo-Json -Depth 8)
$normalized=Set-ModStateText "testmod : 0`nOther : 1`n" TestMod $true
Check ((Get-ModStates $normalized).TestMod -and (Get-ModStates $normalized).Other) 'Case-insensitive replacement lost entries'
Check ($normalized -cnotmatch 'testmod :') 'Replacement retained wrong-cased duplicate'
Check (!(Test-ManagedModEnabled $mods (Get-ModStates "testmod : 1`n") TestMod)) 'Wrong-cased entry was shown enabled despite UE4SS rejecting it'
Check (Test-ManagedModEnabled $mods (Get-ModStates "TestMod : 1`n") testmod) 'Dependency spelling did not resolve the actual folder name'
Check (!(Test-ManagedModEnabled (Join-Path $fixture 'not-installed') @{} ClanLoader)) 'Fresh setup must not require an existing Mods directory'
$beforeCaseRepair=[IO.File]::ReadAllText($list)
Write-Utf8 $list (Set-ModStateText $beforeCaseRepair testmod $true)
Set-ManagedModEnabled $mods TestMod $true
Check ([IO.File]::ReadAllText($list) -cmatch 'TestMod : 1') 'Enabling did not repair the folder spelling'
Check ([IO.File]::ReadAllText($list) -cnotmatch 'testmod :') 'Enabling retained the wrong-cased entry'
Write-Utf8 $list $beforeCaseRepair

# Fault after truncating mods.txt: restore exact previous bytes and marker.
Write-Utf8 $marker 'marker bytes';$oldList=[IO.File]::ReadAllText($list)
$script:realWrite=${function:Write-Utf8};$script:failList=$list;$script:failWrite=$true
function Write-Utf8([string]$Path,[string]$Text){if($script:failWrite -and $Path -eq $script:failList){$script:failWrite=$false;[IO.File]::WriteAllText($Path,'partial');throw 'Injected write failure'};& $script:realWrite $Path $Text}
try{Reject {Set-ManagedModEnabled $mods TestMod $false}}finally{Set-Item Function:Write-Utf8 $script:realWrite}
Check ([IO.File]::ReadAllText($list) -ceq $oldList) 'Toggle write failure did not restore mods.txt'
Check ([IO.File]::ReadAllText($marker) -ceq 'marker bytes') 'Toggle write failure lost marker'

# Fault after deleting marker: restore both activation sources.
$script:realRemove=${function:Remove-ModEnableMarker}
function Remove-ModEnableMarker([string]$Mods,[string]$Id){& $script:realRemove $Mods $Id;throw 'Injected marker removal failure'}
try{Reject {Set-ManagedModEnabled $mods TestMod $false}}finally{Set-Item Function:Remove-ModEnableMarker $script:realRemove}
Check ([IO.File]::ReadAllText($list) -ceq $oldList) 'Marker failure did not restore mods.txt'
Check ([IO.File]::ReadAllText($marker) -ceq 'marker bytes') 'Marker failure did not restore enabled.txt'

# Uninstall must restore files, registry and activation if its final write fails.
$oldRegistry=[IO.File]::ReadAllText((Join-Path $mods 'ClanLoader/registry.json'));$oldBody=[IO.File]::ReadAllText($entry)
$script:realSave=${function:Save-ModRegistry}
function Save-ModRegistry([string]$Mods,$Registry){Write-Utf8 (Join-Path $Mods 'ClanLoader/registry.json') 'partial';throw 'Injected registry failure'}
try{Reject {Remove-ManagedMod $mods TestMod}}finally{Set-Item Function:Save-ModRegistry $script:realSave}
Check ([IO.File]::ReadAllText($entry) -ceq $oldBody) 'Failed uninstall did not restore owned code'
Check ([IO.File]::ReadAllText($marker) -ceq 'marker bytes') 'Failed uninstall did not restore marker'
Check ([IO.File]::ReadAllText($list) -ceq $oldList) 'Failed uninstall did not restore load order'
Check ([IO.File]::ReadAllText((Join-Path $mods 'ClanLoader/registry.json')) -ceq $oldRegistry) 'Failed uninstall did not restore registry'

# Upgrade rollback must also restore marker after payload and registry changes.
Write-Utf8 (Join-Path $pkg 'payload/TestMod/Scripts/main.lua') "print('updated')"
$m.version='2.0.0';$m.files[0].sha256=(Get-FileHash (Join-Path $pkg 'payload/TestMod/Scripts/main.lua')).Hash
Write-Utf8 (Join-Path $pkg 'mod.json') ($m|ConvertTo-Json -Depth 8)
function Remove-ModEnableMarker([string]$Mods,[string]$Id){& $script:realRemove $Mods $Id;throw 'Injected marker removal failure'}
try{Reject {Install-CommunityPackage $pkg $mods}}finally{Set-Item Function:Remove-ModEnableMarker $script:realRemove}
Check ([IO.File]::ReadAllText($entry) -ceq $oldBody) 'Failed update did not restore owned code'
Check ([IO.File]::ReadAllText($marker) -ceq 'marker bytes') 'Failed update did not restore marker'
Check ([IO.File]::ReadAllText($list) -ceq $oldList) 'Failed update did not restore load order'
Check ([IO.File]::ReadAllText((Join-Path $mods 'ClanLoader/registry.json')) -ceq $oldRegistry) 'Failed update did not restore registry'

# Preserve a user's modified entry point without leaving it enabled after removal.
Write-Utf8 $entry "print('personal edit')";$null=Remove-ManagedMod $mods TestMod
Check (Test-Path -LiteralPath $entry) 'Uninstall deleted a modified entry point'
Check (!(Test-Path -LiteralPath $marker)) 'Uninstall left preserved code enabled'
Check (!(Get-ModStates ([IO.File]::ReadAllText($list))).TestMod) 'Uninstall left load order enabled'
Check (@((Read-ModRegistry $mods).mods|Where-Object {$_.id -eq 'TestMod'}).Count -eq 0) 'Uninstall kept registry entry'
# An unregistered directory must not be adopted with a differently cased ID.
Copy-Item -LiteralPath (Join-Path $pkg 'payload/TestMod/Scripts/main.lua') -Destination $entry -Force
$m.id='testmod';Write-Utf8 (Join-Path $pkg 'mod.json') ($m|ConvertTo-Json -Depth 8)
$beforeAdoption=[IO.File]::ReadAllText($list)
Reject {Install-CommunityPackage $pkg $mods}
Check ([IO.File]::ReadAllText($list) -ceq $beforeAdoption) 'Rejected folder casing changed activation'
Check (@((Read-ModRegistry $mods).mods|Where-Object {$_.id -ieq 'TestMod'}).Count -eq 0) 'Wrong-cased folder was registered'
Write-Output "PASS $script:checks manager lifecycle, dependency and package-boundary checks. Fixture: $fixture"

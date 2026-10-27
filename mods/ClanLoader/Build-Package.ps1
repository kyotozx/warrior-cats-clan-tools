param([string]$Version='0.3.0-rc7',[Parameter(Mandatory=$true)][string]$ClanToolsPackage,[string]$OutputRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'manager/Manager.Core.ps1')
$workspace=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if(!$OutputRoot){$OutputRoot=Join-Path $workspace 'dist/final'}
if($Version -notmatch '^[0-9][A-Za-z0-9._-]{0,50}$'){throw 'Invalid version.'}
$stage=Get-ContainedPath $OutputRoot ('ClanLoader-'+$Version)
if(Test-Path -LiteralPath $stage){throw 'Release already exists.'}
$ct=Read-PackageManifest $ClanToolsPackage
$null=New-Item -ItemType Directory -Path $stage -Force
foreach($name in @('ClanLoader.exe','Manager.ps1','Updates.ps1','Updates.Core.ps1','Manager.Core.ps1','Package.Core.ps1','Manager.xaml','Theme.ps1','ThemeAssets.dll','theme-assets.json')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('manager/'+$name)) -Destination $stage}
$iconNames=@('loader','clan-tools','package','party','appearance','item-feedback','offline-admin','den-workshop','keybinds','fps','performance','player-skins','sky')
$supportFiles=@('icons/loader.ico','icons/catalog.json','theme-tools/ooz.exe','theme-tools/COPYING.txt','theme-tools/NOTICE.txt')
foreach($icon in $iconNames){$supportFiles+=@(('icons/'+$icon+'.svg'),('icons/'+$icon+'.png'))}
foreach($name in @('kraken.cpp','lzna.cpp','bitknit.cpp','stdafx.h','targetver.h','README.md')){$supportFiles+=('theme-tools/source/'+$name)}
foreach($name in $supportFiles){$dest=Get-ContainedPath $stage $name;$null=New-Item -ItemType Directory -Path (Split-Path $dest) -Force;Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('manager/'+$name)) -Destination $dest}
foreach($name in @('LICENSE','THIRD-PARTY-NOTICES.md')){Copy-Item -LiteralPath (Join-Path $workspace $name) -Destination $stage}
foreach($name in @('README.txt','DEVELOPERS.txt')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $stage}
$null=New-Item -ItemType Directory -Path (Join-Path $stage 'ClanTools') -Force
foreach($f in @($ct.files)+@([pscustomobject]@{path='manifest.json'})){
 $dest=Get-ContainedPath $stage ('ClanTools/'+$f.path);$null=New-Item -ItemType Directory -Path (Split-Path $dest) -Force
 Copy-Item -LiteralPath (Get-ContainedPath $ClanToolsPackage $f.path) -Destination $dest
}
function New-ModPackage([string]$Id,[string]$Name,[string]$Description,[string[]]$Dependencies,$Sources,[string]$PackageVersion=$Version){
 $root=Get-ContainedPath $stage ('packages/'+$Id);$files=@()
 foreach($s in $Sources){$dest=Get-ContainedPath $root ('payload/'+$Id+'/'+$s.path);$null=New-Item -ItemType Directory -Path (Split-Path $dest) -Force;Copy-Item -LiteralPath $s.source -Destination $dest;$files+=@{path=$s.path;sha256=(Get-FileHash -LiteralPath $dest).Hash}}
 $m=[ordered]@{schema=1;loaderApi=1;gameBuild='26184573';id=$Id;name=$Name;version=$PackageVersion;description=$Description;dependencies=@($Dependencies);files=$files}
 Write-Utf8 (Join-Path $root 'mod.json') ($m|ConvertTo-Json -Depth 8)
 $null=Read-CommunityPackage $root
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 [IO.Compression.ZipFile]::CreateFromDirectory($root,(Join-Path $stage ('packages/'+$Id+'-'+$PackageVersion+'.zip')))
}
$loaderScripts=@('menu_icons.lua','main.lua','registry.lua','native_panel.lua','native_skin.lua','runtime_valid.lua','json.lua')
$loaderSources=@($loaderScripts|ForEach-Object {@{path='Scripts/'+$_;source=(Join-Path $PSScriptRoot ('Scripts/'+$_))}})
$loaderSources+=@{path='assets/icons/loader.png';source=(Join-Path $PSScriptRoot 'assets/icons/loader.png')}
New-ModPackage 'ClanLoader' 'Clan Loader' 'Manage community mods from the original game menu. Changes apply on the next launch.' @() $loaderSources
$toolSources=@($ct.files|Where-Object {$_.area -eq 'mod'}|ForEach-Object {@{path=$_.path.Substring(18);source=(Get-ContainedPath $ClanToolsPackage $_.path)}})
New-ModPackage 'ClanTools' 'Clan Tools' 'Party, player skins, clan appearances, offline admin and den workshop.' @('ClanLoader') $toolSources $ct.version
# Explicit original source files, never personal state or extracted game assets.
foreach($name in @('Launcher.cs','Build-Launcher.ps1','Build-Icons.ps1','Manager.ps1','Updates.ps1','Updates.Core.ps1','Manager.Core.ps1','Package.Core.ps1','Manager.xaml','Theme.ps1','ThemeAssets.cs','theme-assets.json')){
 $dest=Join-Path $stage ('source/manager/'+$name);$null=New-Item -ItemType Directory -Path (Split-Path $dest) -Force;Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('manager/'+$name)) -Destination $dest
}
$example=Join-Path $stage 'example';$null=New-Item -ItemType Directory -Path (Join-Path $example 'payload/HelloClan/Scripts') -Force
Write-Utf8 (Join-Path $example 'payload/HelloClan/Scripts/main.lua') "print('[HelloClan] Example community mod loaded.\n')`n"
$em=[ordered]@{schema=1;loaderApi=1;gameBuild='26184573';id='HelloClan';name='Hello Clan';version='1.0.0';description='Minimal Lua package example. Writes one startup message to UE4SS.log.';dependencies=@('ClanLoader');files=@(@{path='Scripts/main.lua';sha256=(Get-FileHash (Join-Path $example 'payload/HelloClan/Scripts/main.lua')).Hash})}
Write-Utf8 (Join-Path $example 'mod.json') ($em|ConvertTo-Json -Depth 8)
$null=Read-CommunityPackage $example
$hashes=@(Get-ChildItem -LiteralPath $stage -File -Recurse|Sort-Object FullName|ForEach-Object {@{path=$_.FullName.Substring($stage.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
Write-Utf8 (Join-Path $stage 'bundle-manifest.json') (@{version=$Version;files=$hashes}|ConvertTo-Json -Depth 5)
Compress-Archive -LiteralPath $stage -DestinationPath ($stage+'.zip') -CompressionLevel Optimal
Get-FileHash -LiteralPath ($stage+'.zip')

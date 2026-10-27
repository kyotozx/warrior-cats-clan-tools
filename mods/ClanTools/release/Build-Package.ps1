param([Parameter(Mandatory=$true)][string]$Version,[Parameter(Mandatory=$true)][string]$NativeSelection,[string]$OutputRoot,[string]$NativeAudit,[switch]$ValidateOnly,[string]$UE4SSDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Package.Core.ps1')
if($Version -notmatch '^[0-9][A-Za-z0-9._-]{0,50}$'){throw 'Invalid release version.'}
$modRoot=Split-Path $PSScriptRoot -Parent;$workspace=Split-Path (Split-Path $modRoot -Parent) -Parent
if(!$OutputRoot){$OutputRoot=Join-Path $workspace 'dist'}
$stage=Get-ContainedPath $OutputRoot ('ClanTools-'+$Version);$zip=$stage+'.zip'
if((Test-Path -LiteralPath $stage) -or(Test-Path -LiteralPath $zip)){throw 'Release destination already exists; use a new version. Existing releases are never overwritten.'}
$allow=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'files.json') -Raw|ConvertFrom-Json
$native=Get-Content -LiteralPath $NativeSelection -Raw|ConvertFrom-Json
if((!$ValidateOnly -and $native.finalized -ne $true) -or @($native.files).Count -lt 1){throw 'Final native DLL selection and SHA256 values are required before staging.'}
if(!$NativeAudit){$NativeAudit=Join-Path $workspace 'analysis/release-verify/source-binary-audit.json'}
$audit=Get-Content -LiteralPath $NativeAudit -Raw|ConvertFrom-Json
foreach($row in $audit.results){
 if($row.productionSectionsMatch -ne $true){throw "Native source/binary audit failed: $($row.name)"}
 if((Get-FileHash -LiteralPath (Get-ContainedPath $workspace $row.source)).Hash -ne $row.sourceSha256){throw "Native source changed after recompilation audit: $($row.source)"}
}
foreach($header in $audit.headers){if((Get-FileHash -LiteralPath (Get-ContainedPath $workspace $header.path)).Hash -ne $header.sha256){throw "Native header changed after recompilation audit: $($header.path)"}}
foreach($entry in $native.files){
 $row=@($audit.results|Where-Object {$_.name -eq $entry.source})
 if($row.Count -ne 1 -or $row[0].original.sha256 -ne $entry.sha256){throw "Selected native binary is absent from source audit: $($entry.source)"}
}
$inputs=@();$destinations=@{}
function Add-Input([string]$Source,[string]$Destination,[string]$Area){
 if($destinations.ContainsKey($Destination.ToLowerInvariant())){throw "Duplicate output: $Destination"};$destinations[$Destination.ToLowerInvariant()]=$true
 if(!(Test-Path -LiteralPath $Source -PathType Leaf)){throw "Missing release input: $Source"};Assert-TreeNoLinks $Source
 $script:inputs+=@{source=$Source;path=$Destination;area=$Area;sha256=(Get-FileHash -LiteralPath $Source).Hash}
}
foreach($name in $allow.scripts){
 if($name -notmatch '^[A-Za-z0-9_]+\.lua$'){throw "Invalid script allowlist entry: $name"}
 Add-Input (Get-ContainedPath $modRoot ('Scripts/'+$name)) ('payload/ClanTools/Scripts/'+$name) 'mod'
}
foreach($name in $allow.icons){
 if($name -cnotmatch '^[a-z][a-z-]*\.png$'){throw "Invalid icon: $name"}
 Add-Input (Get-ContainedPath $modRoot ('assets/icons/'+$name)) ('payload/ClanTools/assets/icons/'+$name) 'mod'
}
foreach($name in $allow.data){
 if(!(Test-ClanToolsProgramPath ('data/'+$name))){throw "Invalid static data allowlist entry: $name"}
 $source=Get-ContainedPath $modRoot ('data/'+$name)
 $null=Get-Content -LiteralPath $source -Raw|ConvertFrom-Json
 Add-Input $source ('payload/ClanTools/data/'+$name) 'mod'
}
foreach($f in $native.files){
 if($f.source -notmatch '^[A-Za-z0-9_-]+\.dll$' -or $f.destination -notmatch '^[A-Za-z0-9_-]+\.dll$' -or $f.sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid finalized native selection.'}
 $source=Get-ContainedPath $modRoot ('bin/'+$f.source);if((Get-FileHash -LiteralPath $source).Hash -ne $f.sha256){throw "Native DLL changed after validation: $($f.source)"}
 Add-Input $source ('payload/ClanTools/bin/'+$f.destination) 'mod'
}
# Keep the explicit allowlist honest when root changes a module or DLL filename.
foreach($name in $allow.scripts){
 $lua=[IO.File]::ReadAllText((Get-ContainedPath $modRoot ('Scripts/'+$name)))
 Assert-LuaReleaseDependencies $name $lua @($allow.scripts) @($native.files|ForEach-Object {$_.destination}) @($allow.data)
}
foreach($name in $allow.nativeSources){
 if($name -notmatch '^[A-Za-z0-9_]+\.(c|h)$'){throw "Invalid native source allowlist entry: $name"}
 $source=Get-ContainedPath $modRoot ('native/'+$name)
 Assert-NativeReleaseDependencies $name ([IO.File]::ReadAllText($source)) @($allow.nativeSources)
 Add-Input $source ('source/native/'+$name) 'source'
}
Add-Input (Get-ContainedPath $workspace 'mods/ClanParty/native/bridge.c') 'source/native/clanparty_bridge.c' 'source'
foreach($name in $allow.documentation){Add-Input (Get-ContainedPath $PSScriptRoot $name) $name 'documentation'}
$loader=if($UE4SSDirectory){[IO.Path]::GetFullPath($UE4SSDirectory)}else{Get-ContainedPath $workspace 'tools/ue4ss/extracted'}
foreach($pair in @(@('dwmapi.dll','93B9431A5A4F32C675D269C5DA1C9B3EC6F88552EC20C282AB435F411E9271FB'),@('ue4ss/UE4SS.dll','CE5E3C46A920CC00B2817AC61E438C9162830290379D0B5B9C4DFC2B29459290'))){if((Get-FileHash -LiteralPath (Get-ContainedPath $loader $pair[0])).Hash -ne $pair[1]){throw 'UE4SS distribution differs from the approved prerequisite.'}}
foreach($name in @('dwmapi.dll','ue4ss/UE4SS.dll','ue4ss/LICENSE','ue4ss/UE4SS-settings.ini')){Add-Input (Get-ContainedPath $loader $name) ('loader/'+$name) 'loader'}
# Every payload is selected above. No directory-wide runtime/bin/settings copies.
if($ValidateOnly){Write-Output "Validated $($inputs.Count) allowlisted package inputs, source/binary audit, and dependency closure. No files staged; pending runtime acceptance is unchanged.";return}
$null=New-Item -ItemType Directory -Path $stage -Force
foreach($f in $inputs){$dest=Get-ContainedPath $stage $f.path;$null=New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force;Copy-Item -LiteralPath $f.source -Destination $dest}
$manifest=[ordered]@{schema=1;name='ClanTools';version=$Version;gameBuild='26184573';steamApp='3960600';gameSha256='CD8AAFB4D2A423BD8D4A4CCD3325590EDE61C97702D595C944D18F5B3984A995';loaderRelease='UE4SS_v3.0.1-1181-g83330635';createdUtc=[DateTime]::UtcNow.ToString('o');files=@($inputs|ForEach-Object {[ordered]@{path=$_.path;area=$_.area;sha256=$_.sha256}})}
Write-Utf8 (Join-Path $stage 'manifest.json') ($manifest|ConvertTo-Json -Depth 6)
$null=Read-PackageManifest $stage
Compress-Archive -LiteralPath $stage -DestinationPath $zip -CompressionLevel Optimal
Get-FileHash -LiteralPath $zip
Write-Output "Prepared only; not installed or published: $zip"

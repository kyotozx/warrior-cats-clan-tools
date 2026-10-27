Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Package.Core.ps1')
$script:SupportedGameHash='F50EB374F8611E4EB6796A33218E4A11DD83B408B3D4687F23C9E80EDB6EBFB2'
function Get-ModsRoot([string]$Game,[switch]$RequireSupportedBuild){
 if([string]::IsNullOrWhiteSpace($Game)){throw 'Choose the game installation folder first.'}
 $win=Get-ContainedPath $Game 'Wrc/Binaries/Win64'
 if(!(Test-Path -LiteralPath (Join-Path $win 'Wrc-Win64-ShippingDRM.exe'))){throw 'The selected folder does not contain Warrior Cats.'}
 if($RequireSupportedBuild){$null=Assert-GameTarget $Game $script:SupportedGameHash}
 return Join-Path $win 'ue4ss/Mods'
}
function Test-ModId([string]$Id){$Id -cmatch '^[A-Za-z][A-Za-z0-9_]{0,63}$'}
function Set-ModStateText([string]$Text,[string]$Id,[bool]$Enabled){
 if(!(Test-ModId $Id)){throw 'Invalid mod ID.'}
 $out=[regex]::Replace($Text,('(?im)^[\t ]*'+[regex]::Escape($Id)+'[\t ]*:[^\r\n]*(?:\r?\n|$)'), '')
 return $out.TrimEnd("`r","`n")+"`r`n"+$Id+' : '+[int]$Enabled+"`r`n"
}
function Get-ModStates([string]$Text){
 $states=@{};foreach($m in [regex]::Matches($Text,'(?m)^[\t ]*([A-Za-z][A-Za-z0-9_]*)[\t ]*:[\t ]*([01])[\t ]*\r?$')){
  $id=$m.Groups[1].Value;if($states.ContainsKey($id)){throw "Duplicate mod entry: $id"};$states[$id]=$m.Groups[2].Value -eq '1'
 };return $states
}
function Read-ModRegistry([string]$Mods){
 $p=Get-ContainedPath $Mods 'ClanLoader/registry.json'
 if(!(Test-Path -LiteralPath $p)){return [pscustomobject]@{schema=1;mods=@()}}
 $r=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json
 if($r.schema -ne 1){throw 'Unsupported mod registry.'};return $r
}
function Test-ManagedModEnabled([string]$Mods,$States,[string]$Id){
 if(!(Test-ModId $Id)){throw 'Invalid mod ID.'}
 # UE4SS processes enabled.txt after mods.txt, even when the list says disabled.
 return ($States.ContainsKey($Id) -and $States[$Id]) -or (Test-Path -LiteralPath (Get-ContainedPath $Mods ($Id+'/enabled.txt')))
}
function Remove-ModEnableMarker([string]$Mods,[string]$Id){
 $marker=Get-ContainedPath $Mods ($Id+'/enabled.txt')
 if(Test-Path -LiteralPath $marker){
  if(!(Test-Path -LiteralPath $marker -PathType Leaf)){throw 'The mod enable marker is not a regular file.'}
  Remove-Item -LiteralPath $marker -Force
 }
}
function Assert-ModStateChange([string]$Mods,$Registry,$States,[string]$Id,[bool]$Enabled){
 if(!(Test-ModId $Id)){throw 'Invalid mod ID.'}
 $entry=@($Registry.mods|Where-Object {$_.id -ceq $Id});if($entry.Count -ne 1){throw 'Unknown mod.'}
 if($Enabled){foreach($dep in $entry[0].dependencies){if(!(Test-ManagedModEnabled $Mods $States $dep)){throw "Enable $dep first."}}}
 else{foreach($m in $Registry.mods){if((Test-ManagedModEnabled $Mods $States $m.id) -and $Id -iin $m.dependencies){throw "Disable $($m.name) first."}}}
}
function Save-ModRegistry([string]$Mods,$Registry){
 $p=Get-ContainedPath $Mods 'ClanLoader/registry.json';$null=New-Item -ItemType Directory -Path (Split-Path $p) -Force
 Write-Utf8 $p ($Registry|ConvertTo-Json -Depth 12)
}
function Read-CommunityPackage([string]$Root){
 $m=Get-Content -LiteralPath (Get-ContainedPath $Root 'mod.json') -Raw|ConvertFrom-Json
 if($m.schema -ne 1 -or $m.loaderApi -ne 1 -or $m.gameBuild -cne '26184573' -or !(Test-ModId $m.id) -or $m.name.Length -gt 80 -or $m.description.Length -gt 200 -or $m.version -notmatch '^[0-9][A-Za-z0-9._-]{0,50}$'){throw 'Incompatible or invalid mod manifest. Use a mod package updated for game patch 1.1.'}
 if(@($m.files).Count -lt 1 -or @($m.files).Count -gt 1000){throw 'Invalid package file count.'}
 foreach($dep in $m.dependencies){if(!(Test-ModId $dep) -or $dep -ieq $m.id){throw 'Invalid mod dependency.'}}
 $seen=@{};foreach($f in $m.files){
  # A package owns program files only. User saves, settings and personal skins
  # can never be claimed by an update or removed during uninstall.
  if($f.path -cnotmatch '^(Scripts/[A-Za-z0-9_]+\.lua|assets/icons/[a-z][a-z-]*\.png|bin/[A-Za-z0-9_-]+\.dll|data/[A-Za-z0-9_-]+\.json)$' -or $f.sha256 -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Invalid program file path or hash.'}
  if($seen.ContainsKey($f.path)){throw 'Duplicate program file.'};$seen[$f.path]=$true
  $p=Get-ContainedPath $Root ('payload/'+$m.id+'/'+$f.path)
  if(!(Test-Path -LiteralPath $p -PathType Leaf) -or (Get-FileHash -LiteralPath $p).Hash -ne $f.sha256){throw "Damaged package file: $($f.path)"}
 }
 if(!$seen.ContainsKey('Scripts/main.lua')){throw 'A Lua entry point is required.'};return $m
}
function Expand-CommunityZip([string]$Zip,[string]$Destination){
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 if(Test-Path -LiteralPath $Destination){throw 'Extraction destination must be new.'}
 $archive=[IO.Compression.ZipFile]::OpenRead($Zip)
 try{
  if($archive.Entries.Count -gt 1100){throw 'Too many ZIP entries.'};$total=0L;$seen=@{};$entries=@()
  foreach($e in $archive.Entries){
   $name=$e.FullName
   if($name.EndsWith('/')){continue}
   if($name -cnotmatch '^(mod\.json|README\.txt|LICENSE\.txt|payload/[A-Za-z][A-Za-z0-9_]{0,63}/(Scripts/[A-Za-z0-9_]+\.lua|assets/icons/[a-z][a-z-]*\.png|bin/[A-Za-z0-9_-]+\.dll|data/[A-Za-z0-9_-]+\.json))$'){throw "Unsupported ZIP path: $name"}
   if((($e.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000){throw 'ZIP links are not supported.'}
   if($seen.ContainsKey($name)){throw 'Duplicate ZIP entry.'};$seen[$name]=$true
   $total+=$e.Length;if($e.Length -gt 32MB -or $total -gt 128MB){throw 'Package exceeds size limits.'}
   $entries+=@{entry=$e;path=(Get-ContainedPath $Destination $name)}
  }
  if(!$seen.ContainsKey('mod.json')){throw 'Select a ClanLoader package containing mod.json at the ZIP root.'}
  $null=New-Item -ItemType Directory -Path $Destination
  foreach($item in $entries){$null=New-Item -ItemType Directory -Path (Split-Path $item.path) -Force;[IO.Compression.ZipFileExtensions]::ExtractToFile($item.entry,$item.path,$false)}
  $m=Read-CommunityPackage $Destination
  foreach($item in $entries){if($item.entry.FullName.StartsWith('payload/')){
   $expected=@($m.files|ForEach-Object {'payload/'+$m.id+'/'+$_.path});if($item.entry.FullName -cnotin $expected){throw 'ZIP contains undeclared payload files.'}
  }}
  return $m
 }finally{$archive.Dispose()}
}
function Backup-ManagedMod([string]$Mods,[string]$Id){
 $backup=Join-Path $env:LOCALAPPDATA ('ClanTools/Backups/manager-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N'))
 $mod=Get-ContainedPath $Mods $Id;Assert-TreeNoLinks $mod
 $null=New-Item -ItemType Directory -Path $backup -Force
 if(Test-Path -LiteralPath $mod){Copy-Item -LiteralPath $mod -Destination (Join-Path $backup 'mod') -Recurse}
 foreach($pair in @(@('mods.txt','mods.txt'),@('ClanLoader/registry.json','registry.json'))){$p=Get-ContainedPath $Mods $pair[0];if(Test-Path -LiteralPath $p){Copy-Item -LiteralPath $p -Destination (Join-Path $backup $pair[1])}}
 return $backup
}
function Install-CommunityPackage([string]$Root,[string]$Mods){
 Assert-GameClosed;$m=Read-CommunityPackage $Root;$r=Read-ModRegistry $Mods
 $list=Get-ContainedPath $Mods 'mods.txt';$text=if(Test-Path -LiteralPath $list){[IO.File]::ReadAllText($list)}else{''};$states=Get-ModStates $text
 foreach($dep in $m.dependencies){if(!(Test-ManagedModEnabled $Mods $states $dep)){throw "Install and enable dependency first: $dep"}}
 $old=@($r.mods|Where-Object {$_.id -ieq $m.id});if($old.Count -gt 1){throw 'Duplicate registered mod.'}
 if($old.Count -eq 1 -and $old[0].id -cne $m.id){throw "Package ID casing must remain $($old[0].id)."}
 $target=Get-ContainedPath $Mods $m.id
 # Windows resolves both spellings to the same directory, but UE4SS mod names
 # come from the directory and are case-sensitive when reading mods.txt.
 if(Test-Path -LiteralPath $target){
  $folder=@(Get-ChildItem -LiteralPath $Mods -Directory -Force|Where-Object {$_.Name -ieq $m.id})
  if($folder.Count -ne 1 -or $folder[0].Name -cne $m.id){throw 'Package ID casing must match the existing mod folder.'}
 }
 $newFiles=@();foreach($f in $m.files){$dest=Get-ContainedPath $target $f.path
  if(Test-Path -LiteralPath $dest){
   $owned=$old.Count -eq 1 -and $f.path -cin @($old[0].files|ForEach-Object {$_.path})
   if(!$owned -and (Get-FileHash -LiteralPath $dest).Hash -ne $f.sha256){throw "An unmanaged file already exists: $($f.path)"}
  }else{$newFiles+=$dest}
 }
 $backup=Backup-ManagedMod $Mods $m.id
 try{
  foreach($f in $m.files){$dest=Get-ContainedPath $target $f.path;$null=New-Item -ItemType Directory -Path (Split-Path $dest) -Force;Copy-Item -LiteralPath (Get-ContainedPath $Root ('payload/'+$m.id+'/'+$f.path)) -Destination $dest;if((Get-FileHash -LiteralPath $dest).Hash -ne $f.sha256){throw 'Installed file hash mismatch.'}}
  if($old.Count -eq 1){foreach($f in $old[0].files){if($f.path -cnotin @($m.files|ForEach-Object {$_.path})){
   $obsolete=Get-ContainedPath $target $f.path
   if((Test-Path -LiteralPath $obsolete) -and (Get-FileHash -LiteralPath $obsolete).Hash -eq $f.sha256){Remove-Item -LiteralPath $obsolete}
  }}}
  $r.mods=@($r.mods|Where-Object {$_.id -ine $m.id})+@($m)
  Save-ModRegistry $Mods $r
  $enable=if($states.ContainsKey($m.id)){Test-ManagedModEnabled $Mods $states $m.id}else{$true}
  Write-Utf8 $list (Set-ModStateText $text $m.id $enable)
  Remove-ModEnableMarker $Mods $m.id
 }catch{
  foreach($p in $newFiles){if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p -Force}}
  if(Test-Path -LiteralPath (Join-Path $backup 'mod')){$null=New-Item -ItemType Directory -Path $target -Force;Get-ChildItem -LiteralPath (Join-Path $backup 'mod') -Force|Copy-Item -Destination $target -Recurse -Force}
  foreach($pair in @(@('mods.txt','mods.txt'),@('registry.json','ClanLoader/registry.json'))){$saved=Join-Path $backup $pair[0];$dest=Get-ContainedPath $Mods $pair[1];if(Test-Path -LiteralPath $saved){Copy-Item -LiteralPath $saved -Destination $dest -Force}elseif(Test-Path -LiteralPath $dest){Remove-Item -LiteralPath $dest -Force}}
  throw
 }
 return "Installed $($m.name) $($m.version). Backup: $backup"
}
function Set-ManagedModEnabled([string]$Mods,[string]$Id,[bool]$Enabled){
 Assert-GameClosed;$r=Read-ModRegistry $Mods
 $list=Get-ContainedPath $Mods 'mods.txt';$text=[IO.File]::ReadAllText($list);$states=Get-ModStates $text
 Assert-ModStateChange $Mods $r $states $Id $Enabled
 $backup=Backup-ManagedMod $Mods $Id
 try{Write-Utf8 $list (Set-ModStateText $text $Id $Enabled);Remove-ModEnableMarker $Mods $Id}
 catch{
  $failure=$_;Copy-Item -LiteralPath (Join-Path $backup 'mods.txt') -Destination $list -Force
  $saved=Join-Path $backup 'mod/enabled.txt';if(Test-Path -LiteralPath $saved -PathType Leaf){Copy-Item -LiteralPath $saved -Destination (Get-ContainedPath $Mods ($Id+'/enabled.txt')) -Force}
  throw $failure
 }
}
function Remove-ManagedMod([string]$Mods,[string]$Id){
 Assert-GameClosed;$r=Read-ModRegistry $Mods
 $list=Get-ContainedPath $Mods 'mods.txt';$text=[IO.File]::ReadAllText($list);$states=Get-ModStates $text
 Assert-ModStateChange $Mods $r $states $Id $false;$m=@($r.mods|Where-Object {$_.id -ceq $Id})[0]
 $backup=Backup-ManagedMod $Mods $Id;$target=Get-ContainedPath $Mods $Id
 try{
  Write-Utf8 $list (Set-ModStateText $text $Id $false);Remove-ModEnableMarker $Mods $Id
  foreach($f in $m.files){$p=Get-ContainedPath $target $f.path;if((Test-Path -LiteralPath $p) -and (Get-FileHash -LiteralPath $p).Hash -eq $f.sha256){Remove-Item -LiteralPath $p}}
  $r.mods=@($r.mods|Where-Object {$_.id -cne $Id});Save-ModRegistry $Mods $r
 }catch{
  $failure=$_
  if(Test-Path -LiteralPath (Join-Path $backup 'mod')){Get-ChildItem -LiteralPath (Join-Path $backup 'mod') -Force|Copy-Item -Destination $target -Recurse -Force}
  Copy-Item -LiteralPath (Join-Path $backup 'mods.txt') -Destination $list -Force
  Copy-Item -LiteralPath (Join-Path $backup 'registry.json') -Destination (Get-ContainedPath $Mods 'ClanLoader/registry.json') -Force
  throw $failure
 }
 return "Removed program files. Personal data and modified files were preserved. Backup: $backup"
}
function Import-PlayerSkin([string]$Path,[string]$Mods){
 $bytes=[IO.File]::ReadAllBytes($Path);if($bytes.Length -gt 8192){throw 'Skin file exceeds size limit.'}
 $text=[Text.Encoding]::UTF8.GetString($bytes);$s=$text|ConvertFrom-Json
 if($s.format -cne 'ClanTools.Skin' -or $s.schema -ne 1 -or $s.gameBuild -cnotin @('24847281','26184573') -or $s.label.Length -lt 1 -or $s.label.Length -gt 40){throw 'Invalid skin format.'}
 foreach($prop in $s.PSObject.Properties.Name){if($prop -notin @('format','schema','gameBuild','label','values')){throw 'Unexpected skin data.'}}
 $values=@($s.values -split '\s+'|Where-Object {$_ -ne ''});if($values.Count -ne 24){throw 'Invalid appearance fields.'}
 foreach($v in $values){if($v -notmatch '^\d{1,3}$' -or [int]$v -gt 255){throw 'Invalid appearance value.'}}
 if([int]$values[22] -gt 1 -or [int]$values[23] -gt 16){throw 'Invalid appearance flags.'}
 $dest=Get-ContainedPath $Mods 'ClanTools/skin-import.json';if(Test-Path -LiteralPath $dest){Copy-Item -LiteralPath $dest -Destination ($dest+'.previous.txt') -Force};Write-Utf8 $dest $text
 return 'Skin prepared. In the game, open Your cat / Skins and choose Import skin.'
}

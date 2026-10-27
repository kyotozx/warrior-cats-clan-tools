Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Get-ContainedPath([string]$Root,[string]$Relative){
 if([IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)|:'){throw "Unsafe relative path: $Relative"}
 $base=[IO.Path]::GetFullPath($Root).TrimEnd('\','/');$full=[IO.Path]::GetFullPath((Join-Path $base $Relative))
 if(!$full.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)){throw "Path leaves its directory: $Relative"}
 $cursor=$full
 while($cursor.Length -ge $base.Length){
  if(Test-Path -LiteralPath $cursor){if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Linked paths are not supported: $cursor"}}
  if($cursor -eq $base){break};$cursor=Split-Path $cursor -Parent
 }
 return $full
}
function Assert-GameClosed {
 if(Get-Process -Name 'Wrc-Win64-ShippingDRM','Wrc-Win64-Shipping','Wrc' -ErrorAction SilentlyContinue){throw 'Save and close Warrior Cats before changing its installation.'}
}
function Find-GameDirectory([string]$Requested){
 if($Requested){return [IO.Path]::GetFullPath($Requested)}
 $libraries=@();$steamInfo=Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue;$steam=if($steamInfo){$steamInfo.SteamPath}else{''}
 if($steam){$libraries+=$steam;$vdf=Join-Path $steam 'steamapps/libraryfolders.vdf';if(Test-Path -LiteralPath $vdf){foreach($m in [regex]::Matches([IO.File]::ReadAllText($vdf),'"path"\s+"([^"\r\n]+)"')){$libraries+=$m.Groups[1].Value.Replace('\\','\')}}}
 $libraries+=Join-Path ${env:ProgramFiles(x86)} 'Steam'
 $found=@($libraries|ForEach-Object {[IO.Path]::GetFullPath($_)}|Sort-Object -Unique|ForEach-Object {$candidate=Join-Path $_ 'steamapps/common/Warrior Cats Clans of the Forest';if(Test-Path -LiteralPath (Join-Path $candidate 'Wrc/Binaries/Win64/Wrc-Win64-ShippingDRM.exe')){$candidate}})
 if($found.Count -eq 1){return $found[0]}
 throw 'Game folder not found uniquely. Run Install.cmd "D:\SteamLibrary\steamapps\common\Warrior Cats Clans of the Forest" (or pass -GameDirectory to the PowerShell script).'
}
function Assert-GameTarget([string]$Game,[string]$ExpectedHash){
 $exe=Get-ContainedPath $Game 'Wrc/Binaries/Win64/Wrc-Win64-ShippingDRM.exe'
 if(!(Test-Path -LiteralPath $exe -PathType Leaf)){throw "Game executable not found: $exe"}
 if((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne $ExpectedHash){throw 'This game executable is not the supported build. No installation changes were made.'}
 return Split-Path $exe -Parent
}
function Write-Utf8([string]$Path,[string]$Text){[IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))}
function Test-ClanToolsProgramPath([string]$Path){
 # Only immutable shipped catalogs are program data. Preferences, aliases,
 # presets, layouts, backups and native mailboxes must never become owned files.
 return $Path -cmatch '^(Scripts/[A-Za-z0-9_]+\.lua|assets/icons/[a-z][a-z-]*\.png|data/(catalog|admin-moves|admin-inventory|workshop)\.json|bin/[A-Za-z0-9_-]+\.dll)$'
}
function Assert-LuaReleaseDependencies([string]$Name,[string]$Lua,[string[]]$Scripts,[string[]]$Dlls,[string[]]$DataFiles=@()){
 foreach($match in [regex]::Matches($Lua,'[A-Za-z0-9_-]+\.dll')){
  if($match.Value -notin $Dlls){throw "Lua $Name references an unselected DLL: $($match.Value)"}
 }
 foreach($match in [regex]::Matches($Lua,'[''"]([A-Za-z0-9_]+\.lua)[''"]')){
  if($match.Groups[1].Value -notin $Scripts){throw "Lua $Name dependency is absent from explicit allowlist: $($match.Groups[1].Value)"}
 }
 foreach($match in [regex]::Matches($Lua,'\brequire\s*\(?\s*[''"]([A-Za-z0-9_]+)[''"]')){
  if(($match.Groups[1].Value+'.lua') -notin $Scripts){throw "Lua $Name require dependency is absent from explicit allowlist: $($match.Groups[1].Value)"}
 }
 foreach($match in [regex]::Matches($Lua,'data/([A-Za-z0-9_-]+\.json)')){
  if($match.Groups[1].Value -notin $DataFiles){throw "Lua $Name static data is absent from explicit allowlist: $($match.Groups[1].Value)"}
 }
}
function Assert-NativeReleaseDependencies([string]$Name,[string]$Source,[string[]]$Sources){
 foreach($match in [regex]::Matches($Source,'(?m)^\s*#\s*include\s*"([^"\r\n]+)"')){
  if($match.Groups[1].Value -notin $Sources){throw "Native $Name include is absent from explicit source allowlist: $($match.Groups[1].Value)"}
 }
}
function Update-ModList([string]$Text,[bool]$Enable){
 $newline=if($Text.Contains("`r`n")){"`r`n"}else{"`n"}
 $out=[regex]::Replace($Text,'(?m)^[\t ]*ClanTools[\t ]*:[^\r\n]*(?:\r?\n|$)','')
 if($Enable){if($out.Length -and !$out.EndsWith("`n")){$out+=$newline};$out+='ClanTools : 1'+$newline}
 return $out
}
function Read-PackageManifest([string]$Root){
 $path=Get-ContainedPath $Root 'manifest.json';$m=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
 if($m.schema -ne 1 -or $m.name -ne 'ClanTools' -or @($m.files).Count -lt 1){throw 'Invalid Clan Tools package manifest.'}
 $seen=@{}
 foreach($f in $m.files){
  if($f.area -notin @('mod','loader','source','documentation') -or $f.sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid package file record.'}
  $full=Get-ContainedPath $Root $f.path;$key=$f.path.ToLowerInvariant();if($seen.ContainsKey($key)){throw "Duplicate package path: $key"};$seen[$key]=$true
  if(!(Test-Path -LiteralPath $full -PathType Leaf) -or (Get-FileHash -LiteralPath $full).Hash -ne $f.sha256){throw "Package file is missing or damaged: $($f.path)"}
  if($f.area -eq 'mod' -and (!$f.path.StartsWith('payload/ClanTools/',[StringComparison]::Ordinal) -or !(Test-ClanToolsProgramPath $f.path.Substring(18)))){throw 'Unexpected mod payload path.'}
  if($f.area -eq 'loader' -and $f.path -notin @('loader/dwmapi.dll','loader/ue4ss/UE4SS.dll','loader/ue4ss/LICENSE','loader/ue4ss/UE4SS-settings.ini')){throw 'Unexpected loader payload path.'}
 }
 return $m
}
function Assert-TreeNoLinks([string]$Path){
 if(!(Test-Path -LiteralPath $Path)){return}
 $item=Get-Item -LiteralPath $Path -Force;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Backup refuses linked path: $Path"}
 if($item.PSIsContainer){foreach($child in Get-ChildItem -LiteralPath $Path -Force){Assert-TreeNoLinks $child.FullName}}
}
function New-Backup([string]$BackupRoot,[string]$Mod,[string]$List,[string]$Saves){
 Assert-TreeNoLinks $Mod;if($Saves){Assert-TreeNoLinks $Saves}
 $backup=Get-ContainedPath $BackupRoot ((Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
 $null=New-Item -ItemType Directory -Path $backup -Force
 if(Test-Path -LiteralPath $Mod){Copy-Item -LiteralPath $Mod -Destination (Join-Path $backup 'ClanTools') -Recurse}
 if(Test-Path -LiteralPath $List){Copy-Item -LiteralPath $List -Destination (Join-Path $backup 'mods.txt')}
 if($Saves -and(Test-Path -LiteralPath $Saves)){Copy-Item -LiteralPath $Saves -Destination (Join-Path $backup 'SaveGames') -Recurse}
 return $backup
}
function Install-ClanToolsPackage([string]$PackageRoot,[string]$Game,[string]$BackupRoot,[string]$Saves,[switch]$ValidateOnly){
 Assert-GameClosed;$m=Read-PackageManifest $PackageRoot;$win=Assert-GameTarget $Game $m.gameSha256
 $loader=Get-ContainedPath $win 'ue4ss';$mods=Get-ContainedPath $win 'ue4ss/Mods';$mod=Get-ContainedPath $mods 'ClanTools';$list=Get-ContainedPath $mods 'mods.txt'
 $newLoader=@();$targets=@()
 foreach($f in $m.files){
  if($f.area -eq 'loader'){
   $dest=Get-ContainedPath $win $f.path.Substring(7)
   if(Test-Path -LiteralPath $dest){
    if($f.path -match '\.dll$' -and (Get-FileHash -LiteralPath $dest).Hash -ne $f.sha256){throw "A different loader already exists; it was preserved: $dest"}
   }else{$newLoader+=@{source=(Get-ContainedPath $PackageRoot $f.path);dest=$dest}}
  }elseif($f.area -eq 'mod'){$relative=$f.path.Substring(18);$targets+=@{source=(Get-ContainedPath $PackageRoot $f.path);dest=(Get-ContainedPath $mod $relative);relative=$relative;sha256=$f.sha256}}
 }
 $receipt=Get-ContainedPath $mod '.clantools-install.json';$oldReceipt=Test-Path -LiteralPath $receipt;$retired=@()
 if($oldReceipt){
  $prior=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json
  if($prior.schema -ne 1 -or $prior.name -ne 'ClanTools'){throw 'Existing install receipt is invalid; preserve this folder before upgrading.'}
  foreach($f in $prior.files){
   if(!(Test-ClanToolsProgramPath $f.path) -or $f.sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid prior owned-file record.'}
   $dest=Get-ContainedPath $mod $f.path
   if($f.path -notin @($targets|ForEach-Object {$_.relative}) -and (Test-Path -LiteralPath $dest) -and (Get-FileHash -LiteralPath $dest).Hash -eq $f.sha256){$retired+=@{relative=$f.path;dest=$dest}}
  }
 }
 if($ValidateOnly){Write-Output "Validated $($m.version) for $Game. No files changed.";return}
 Assert-GameClosed
 $backup=New-Backup $BackupRoot $mod $list $Saves
 $changed=@();$loaderCreated=@();$listExisted=Test-Path -LiteralPath $list
 try {
  foreach($dir in @($loader,$mods,$mod,(Get-ContainedPath $mod 'state'),(Get-ContainedPath $mod 'backups'))){$null=New-Item -ItemType Directory -Force -Path $dir}
  foreach($f in $newLoader){$null=New-Item -ItemType Directory -Force -Path (Split-Path $f.dest -Parent);$loaderCreated+=$f.dest;Copy-Item -LiteralPath $f.source -Destination $f.dest}
  foreach($f in $targets){$null=New-Item -ItemType Directory -Force -Path (Split-Path $f.dest -Parent);$changed+=$f;Copy-Item -LiteralPath $f.source -Destination $f.dest -Force}
  foreach($f in $retired){$changed+=$f;Remove-Item -LiteralPath $f.dest -Force}
  $previous=if($listExisted){[IO.File]::ReadAllText($list)}else{''};Write-Utf8 $list (Update-ModList $previous $true)
  $r=[ordered]@{schema=1;name='ClanTools';version=$m.version;backup=$backup;installedUtc=[DateTime]::UtcNow.ToString('o');files=@($targets|ForEach-Object {@{path=$_.relative;sha256=$_.sha256}})}
  Write-Utf8 $receipt ($r|ConvertTo-Json -Depth 6)
 }catch{
  $failure=$_
  foreach($f in $changed){$old=Get-ContainedPath (Join-Path $backup 'ClanTools') $f.relative;if(Test-Path -LiteralPath $old){Copy-Item -LiteralPath $old -Destination $f.dest -Force}elseif(Test-Path -LiteralPath $f.dest){Remove-Item -LiteralPath $f.dest -Force}}
  foreach($path in $loaderCreated){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}}
  if($listExisted){Copy-Item -LiteralPath (Join-Path $backup 'mods.txt') -Destination $list -Force}elseif(Test-Path -LiteralPath $list){Remove-Item -LiteralPath $list -Force}
  if($oldReceipt){Copy-Item -LiteralPath (Join-Path $backup 'ClanTools/.clantools-install.json') -Destination $receipt -Force}elseif(Test-Path -LiteralPath $receipt){Remove-Item -LiteralPath $receipt -Force}
  throw "Installation failed and previous files were restored. Backup: $backup. $failure"
 }
 Write-Output "Clan Tools $($m.version) installed. User settings and other mods were preserved. Backup: $backup"
}
function Uninstall-ClanToolsPackage([string]$Game,[string]$BackupRoot,[string]$Saves,[switch]$DisableOnly){
 Assert-GameClosed
 $win=Get-ContainedPath $Game 'Wrc/Binaries/Win64';$mods=Get-ContainedPath $win 'ue4ss/Mods';$mod=Get-ContainedPath $mods 'ClanTools';$list=Get-ContainedPath $mods 'mods.txt';$receipt=Get-ContainedPath $mod '.clantools-install.json'
 # Removal works after a game update; exact install ownership replaces build checks.
 if(!(Test-Path -LiteralPath $mod)){Write-Output 'Clan Tools is not installed in this folder.';return}
 if(!$DisableOnly -and !(Test-Path -LiteralPath $receipt)){throw 'No installer ownership receipt exists. Use Disable.cmd; preserve this manually installed folder.'}
 $owned=@();if(!$DisableOnly){$r=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json;if($r.schema -ne 1 -or $r.name -ne 'ClanTools'){throw 'Invalid installation receipt.'};foreach($f in $r.files){if(!(Test-ClanToolsProgramPath $f.path) -or $f.sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid owned-file record.'};$owned+=@{dest=(Get-ContainedPath $mod $f.path);sha256=$f.sha256}}}
 $backup=New-Backup $BackupRoot $mod $list $Saves
 if(Test-Path -LiteralPath $list){Write-Utf8 $list (Update-ModList ([IO.File]::ReadAllText($list)) $false)}
 $enabled=Get-ContainedPath $mod 'enabled.txt';if(Test-Path -LiteralPath $enabled){Remove-Item -LiteralPath $enabled -Force}
 if(!$DisableOnly){foreach($f in $owned){if(Test-Path -LiteralPath $f.dest){if((Get-FileHash -LiteralPath $f.dest).Hash -eq $f.sha256){Remove-Item -LiteralPath $f.dest -Force}else{Write-Warning "Preserved modified file: $($f.dest)"}}};Remove-Item -LiteralPath $receipt -Force}
 Write-Output "Clan Tools disabled$(if(!$DisableOnly){' and owned program files removed'}). Settings, backups, saves, loader and other mods were preserved. Backup: $backup"
}

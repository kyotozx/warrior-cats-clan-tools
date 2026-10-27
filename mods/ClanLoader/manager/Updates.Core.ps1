$script:ReleaseRepositories=@{
 ClanLoader='kyotozx/warrior-cats-clan-tools'
 ClanTools='kyotozx/warrior-cats-clan-tools'
 ClanPerformance='kyotozx/warrior-cats-performance'
}
function ConvertTo-ReleaseVersion([string]$Text){
 if($Text -cnotmatch '^v?(\d+)\.(\d+)\.(\d+)(?:-([a-zA-Z]+)(\d*)(?:[.-](\d+))?)?$'){return $null}
 $kind=[string]$Matches[4];$number=$Matches[5];if(!$number){$number=$Matches[6]}
 $rank=switch($kind){''{4};'rc'{3};'beta'{2};'alpha'{1};'preview'{0};default{return $null}}
 return ,@([long]$Matches[1],[long]$Matches[2],[long]$Matches[3],[long]$rank,[long]$number)
}
function Compare-ReleaseVersion([string]$Left,[string]$Right){
 $a=ConvertTo-ReleaseVersion $Left;$b=ConvertTo-ReleaseVersion $Right
 if($null -eq $a -or $null -eq $b){return $null}
 for($i=0;$i -lt $a.Count;$i++){if($a[$i] -gt $b[$i]){return 1};if($a[$i] -lt $b[$i]){return -1}}
 return 0
}
function Select-PublishedRelease($Releases,[string]$Repository){
 $best=$null
 foreach($release in $Releases){
  if($release.draft -or $null -eq (ConvertTo-ReleaseVersion $release.tag_name)){continue}
  # Only downloadable product packages count, not source-only or diagnostic releases.
  $pattern=if($Repository -eq 'kyotozx/warrior-cats-performance'){'^Performance-[0-9][A-Za-z0-9._-]*\.zip$'}else{'^ClanLoader-[0-9][A-Za-z0-9._-]*\.zip$'}
  if(!@($release.assets|Where-Object {$_.name -cmatch $pattern}).Count){continue}
  if(!$best -or (Compare-ReleaseVersion $release.tag_name $best.tag_name) -gt 0){$best=$release}
 }
 if($best){return [pscustomobject]@{version=$best.tag_name.TrimStart('v');url=('https://github.com/'+$Repository+'/releases/tag/'+[Uri]::EscapeDataString($best.tag_name))}}
}
function Get-CommunityReleases{
 $result=@{};$failed=@()
 [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
 foreach($repo in @($script:ReleaseRepositories.Values|Sort-Object -Unique)){
  try{
   $releases=Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$repo+'/releases?per_page=30') -Headers @{'User-Agent'='ClanLoader-UpdateCheck';Accept='application/vnd.github+json'} -TimeoutSec 8
   $release=Select-PublishedRelease $releases $repo
   if($release){$result[$repo]=$release}else{$failed+=$repo}
  }catch{$failed+=$repo}
 }
 return [pscustomobject]@{releases=$result;failed=$failed}
}
function Get-AvailableModUpdates($Mods,$Releases){
 foreach($mod in $Mods){
  $repo=$script:ReleaseRepositories[$mod.id]
  if(!$repo -or !$Releases.ContainsKey($repo)){continue}
  $latest=$Releases[$repo]
  if((Compare-ReleaseVersion $latest.version $mod.version) -eq 1){
   [pscustomobject]@{id=$mod.id;name=$mod.name;installed=$mod.version;version=$latest.version;url=$latest.url}
  }
 }
}

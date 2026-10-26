param([string]$GameDirectory)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/Modules/Microsoft.PowerShell.Utility') -Force
. (Join-Path $PSScriptRoot 'Manager.Core.ps1')
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms
[xml]$xaml=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Manager.xaml'))
$window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$window.Icon=[Windows.Media.Imaging.BitmapFrame]::Create([Uri]::new((Join-Path $PSScriptRoot 'icons/loader.ico')))
$window.FindName('AppMark').Source=[Windows.Media.Imaging.BitmapImage]::new([Uri]::new((Join-Path $PSScriptRoot 'icons/loader.png')))
$window.FindName('SkinMark').Source=[Windows.Media.Imaging.BitmapImage]::new([Uri]::new((Join-Path $PSScriptRoot 'icons/player-skins.png')))
$pathBox=$window.FindName('GamePath');$list=$window.FindName('Mods');$status=$window.FindName('Status')
try{$pathBox.Text=Find-GameDirectory $GameDirectory}catch{$status.Text=$_.Exception.Message}
$script:rows=@();$script:busy=$false
function Show-Result([scriptblock]$Action){
 if($script:busy){return};$script:busy=$true;$window.Cursor=[Windows.Input.Cursors]::Wait
 try{$result=& $Action;$status.Text=($result|Out-String).Trim();Refresh-List}catch{$status.Text=$_.Exception.Message}finally{$script:busy=$false;$window.Cursor=$null}
}
function Current-Mods{Get-ModsRoot $pathBox.Text}
function Refresh-List{
 $selectedId=if($list.SelectedIndex -ge 0 -and $list.SelectedIndex -lt $script:rows.Count){$script:rows[$list.SelectedIndex].id}else{$null}
 $root=Current-Mods;$r=Read-ModRegistry $root;$script:rows=@($r.mods);$list.Items.Clear();$states=@{};$p=Get-ContainedPath $root 'mods.txt'
 if(Test-Path -LiteralPath $p){$states=Get-ModStates ([IO.File]::ReadAllText($p))}
 foreach($m in $script:rows){
  $enabled=$states.ContainsKey($m.id) -and $states[$m.id]
  $label=if($enabled){'Enabled'}else{'Disabled'};$color=if($enabled){'#8CD5AA'}else{'#9BA7A1'}
  $iconName=if($m.id -eq 'ClanLoader'){'loader'}elseif($m.id -eq 'ClanTools'){'clan-tools'}elseif($m.id -eq 'ClanPerformance'){'performance'}else{'package'}
  $icon=[Windows.Media.Imaging.BitmapImage]::new([Uri]::new((Join-Path $PSScriptRoot ('icons/'+$iconName+'.png'))));$icon.Freeze()
  $null=$list.Items.Add([pscustomobject]@{DisplayName=$m.name;StateLabel=$label;StateBrush=$color;VersionLabel=$m.version;Enabled=$enabled;IconSource=$icon})
 }
 $window.FindName('ModCount').Text=('{0} INSTALLED' -f $script:rows.Count)
 if($script:rows.Count){$index=0;for($i=0;$i -lt $script:rows.Count;$i++){if($script:rows[$i].id -eq $selectedId){$index=$i}};$list.SelectedIndex=$index}
 Update-Details
}
function Update-Details{
 $selected=$list.SelectedIndex -ge 0 -and $list.SelectedIndex -lt $script:rows.Count
 $window.FindName('Toggle').IsEnabled=$selected;$window.FindName('Remove').IsEnabled=$selected
 if($selected){
  $m=$script:rows[$list.SelectedIndex];$item=$list.SelectedItem
  $window.FindName('DetailName').Text=$m.name
  $window.FindName('DetailVersion').Text=('VERSION '+$m.version+'   /   '+$item.StateLabel.ToUpperInvariant())
  $window.FindName('DetailDescription').Text=$m.description
  $window.FindName('Toggle').Content=if($item.Enabled){'DISABLE MOD'}else{'ENABLE MOD'}
 }else{$window.FindName('DetailName').Text='Clan Loader';$window.FindName('DetailVersion').Text='Install the suite or add a mod package.';$window.FindName('DetailDescription').Text='Your installed mods will appear here.'}
}
$list.Add_SelectionChanged({Update-Details})
. (Join-Path $PSScriptRoot 'Theme.ps1')
function Selected-Mod{if($list.SelectedIndex -lt 0){throw 'Select a mod first.'};return $script:rows[$list.SelectedIndex]}
function Select-File([string]$Filter){$d=[Microsoft.Win32.OpenFileDialog]::new();$d.Filter=$Filter;if($d.ShowDialog($window)){return $d.FileName}}
$window.FindName('Browse').Add_Click({$d=[Windows.Forms.FolderBrowserDialog]::new();$d.Description='Choose the Warrior Cats Steam folder';if($d.ShowDialog() -eq 'OK'){$pathBox.Text=$d.SelectedPath;Show-Result {Refresh-List;Start-GameTheme;'Game folder selected.'}};$d.Dispose()})
$window.FindName('Refresh').Add_Click({Show-Result {'Mod list refreshed.'}})
$window.FindName('Setup').Add_Click({Show-Result {
 $root=Current-Mods;Assert-GameClosed;$suite=Join-Path $PSScriptRoot 'ClanTools'
 if(!(Test-Path -LiteralPath (Join-Path $suite 'Install.ps1'))){throw 'This source copy is not a release bundle. Use the packaged manager.'}
 $null=Read-CommunityPackage (Join-Path $PSScriptRoot 'packages/ClanLoader')
 $null=Read-CommunityPackage (Join-Path $PSScriptRoot 'packages/ClanTools')
 $listPath=Join-Path $root 'mods.txt';$priorStates=@{}
 if(Test-Path -LiteralPath $listPath){$priorStates=Get-ModStates ([IO.File]::ReadAllText($listPath))}
 try{
  & (Join-Path $suite 'Install.ps1') -GameDirectory $pathBox.Text
  Install-CommunityPackage (Join-Path $PSScriptRoot 'packages/ClanLoader') $root
  Write-Utf8 $listPath (Set-ModStateText ([IO.File]::ReadAllText($listPath)) 'ClanLoader' $true)
  Install-CommunityPackage (Join-Path $PSScriptRoot 'packages/ClanTools') $root
 }finally{
  if(Test-Path -LiteralPath $listPath){$finalText=[IO.File]::ReadAllText($listPath);foreach($id in @('ClanTools','ClanLoader')){if($priorStates.ContainsKey($id)){$finalText=Set-ModStateText $finalText $id $priorStates[$id]}};Write-Utf8 $listPath $finalText}
 }
 'Suite installed. Start the game and choose Mods from the original menu.'
}})
$window.FindName('ImportMod').Add_Click({$file=Select-File 'ClanLoader mod package (*.zip)|*.zip';if($file){Show-Result {
 $root=Get-ModsRoot $pathBox.Text -RequireSupportedBuild;Assert-GameClosed;$temp=Join-Path $env:LOCALAPPDATA ('ClanTools/PackageCache/'+[guid]::NewGuid().ToString('N'))
 $null=Expand-CommunityZip $file $temp;Install-CommunityPackage $temp $root
}}})
$window.FindName('Toggle').Add_Click({Show-Result {$m=Selected-Mod;$root=Current-Mods;$states=Get-ModStates ([IO.File]::ReadAllText((Join-Path $root 'mods.txt')));$enabled=$states.ContainsKey($m.id) -and $states[$m.id];Set-ManagedModEnabled $root $m.id (!$enabled);'Mod preference saved for the next launch.'}})
$window.FindName('Remove').Add_Click({try{$m=Selected-Mod;if([Windows.MessageBox]::Show($window,"Uninstall $($m.name)? Personal data will be kept.",'Uninstall mod','YesNo','Question') -eq 'Yes'){Show-Result {Remove-ManagedMod (Current-Mods) $m.id}}}catch{$status.Text=$_.Exception.Message}})
$window.FindName('ImportSkin').Add_Click({$file=Select-File 'Player skin (*.json)|*.json';if($file){Show-Result {Import-PlayerSkin $file (Current-Mods)}}})
$window.FindName('ExportSkin').Add_Click({Show-Result {
 $source=Get-ContainedPath (Current-Mods) 'ClanTools/skin-export.json';if(!(Test-Path -LiteralPath $source)){throw 'In the game, select a skin and choose Export skin first.'}
 $d=[Microsoft.Win32.SaveFileDialog]::new();$d.Filter='Player skin (*.json)|*.json';$d.FileName='My-cat-skin.json';if($d.ShowDialog($window)){Copy-Item -LiteralPath $source -Destination $d.FileName -Force;'Skin exported.'}
}})
$window.FindName('Launch').Add_Click({Start-Process 'steam://rungameid/3960600'})
$window.FindName('OpenMods').Add_Click({Show-Result {$root=Current-Mods;if(Test-Path -LiteralPath $root){Invoke-Item -LiteralPath $root};'Mods folder opened.'}})
$window.FindName('Backups').Add_Click({$p=Join-Path $env:LOCALAPPDATA 'ClanTools/Backups';if(Test-Path -LiteralPath $p){Invoke-Item -LiteralPath $p}})
$window.Add_Loaded({if($pathBox.Text){try{Refresh-List;Start-GameTheme;$status.Text=""}catch{$status.Text=$_.Exception.Message}}})
$null=$window.ShowDialog()

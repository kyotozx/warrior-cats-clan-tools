. (Join-Path $PSScriptRoot 'Updates.Core.ps1')
$script:releaseData=@{};$script:availableUpdates=@();$script:updateWorker=$null;$script:updateHandle=$null;$script:lastUpdateCheck=[DateTime]::MinValue
function Refresh-UpdateNotice{
 $mods=@($script:rows)
 # Check the application bundle too, even before the user installs its suite.
 $bundle=Join-Path $PSScriptRoot 'bundle-manifest.json'
 if(Test-Path -LiteralPath $bundle){
  try{$version=(Get-Content -LiteralPath $bundle -Raw|ConvertFrom-Json).version
   $mods+= [pscustomobject]@{id='ClanLoader';name='Clan Loader';version=$version}
  }catch{}
 }
 $script:availableUpdates=@(Get-AvailableModUpdates $mods $script:releaseData|Sort-Object id -Unique)
 $notice=$window.FindName('UpdateNotice');$open=$window.FindName('OpenUpdate')
 $open.Visibility=if($script:availableUpdates.Count){'Visible'}else{'Collapsed'}
 if($script:availableUpdates.Count){
  $notice.Text='Updates available: '+(($script:availableUpdates|ForEach-Object {$_.name+' '+$_.version}) -join ', ')
  $notice.ToolTip=$notice.Text
 }
}
function Start-UpdateCheck{
 if($script:updateWorker -or ([DateTime]::UtcNow-$script:lastUpdateCheck).TotalSeconds -lt 60){return}
 $script:lastUpdateCheck=[DateTime]::UtcNow
 $window.FindName('CheckUpdates').IsEnabled=$false;$window.FindName('UpdateNotice').Text='Checking for updates...'
 $session=[Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
 $session.ExecutionPolicy=[Microsoft.PowerShell.ExecutionPolicy]::Bypass
 $script:updateRunspace=[Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($session)
 $script:updateRunspace.Open()
 $script:updateWorker=[PowerShell]::Create();$script:updateWorker.Runspace=$script:updateRunspace
 $null=$script:updateWorker.AddScript('param($core) . $core; Get-CommunityReleases').AddArgument((Join-Path $PSScriptRoot 'Updates.Core.ps1'))
 $script:updateHandle=$script:updateWorker.BeginInvoke();$script:updateTimer.Start()
}
$script:updateTimer=[Windows.Threading.DispatcherTimer]::new();$script:updateTimer.Interval=[TimeSpan]::FromMilliseconds(500)
$script:updateTimer.Add_Tick({
 if(!$script:updateHandle -or !$script:updateHandle.IsCompleted){return}
 $script:updateTimer.Stop()
 try{
  $result=@($script:updateWorker.EndInvoke($script:updateHandle))[-1]
  foreach($key in $result.releases.Keys){$script:releaseData[$key]=$result.releases[$key]}
  $window.FindName('UpdateNotice').Text=if($result.failed.Count){'Some updates could not be checked. Try again later.'}else{'No newer releases found.'}
  Refresh-UpdateNotice
 }catch{$window.FindName('UpdateNotice').Text='Could not check for updates. Try again later.'}
 finally{$script:updateWorker.Dispose();$script:updateRunspace.Dispose();$script:updateWorker=$null;$script:updateHandle=$null;$window.FindName('CheckUpdates').IsEnabled=$true}
})
$window.FindName('CheckUpdates').Add_Click({Start-UpdateCheck})
$window.FindName('OpenUpdate').Add_Click({
 # Open only the selected product, or the first available update. No downloads or installs.
 $chosen=@($script:availableUpdates|Where-Object {$list.SelectedIndex -ge 0 -and $_.id -eq $script:rows[$list.SelectedIndex].id})|Select-Object -First 1
 if(!$chosen){$chosen=$script:availableUpdates|Select-Object -First 1}
 if($chosen){Start-Process $chosen.url}
})
$window.Add_ContentRendered({Start-UpdateCheck})
$window.Add_Closed({$script:updateTimer.Stop();if($script:updateWorker){$null=$script:updateWorker.BeginStop($null,$null)}})

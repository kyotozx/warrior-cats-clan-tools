Add-Type -AssemblyName System.Web.Extensions
Add-Type -Path (Join-Path $PSScriptRoot 'ThemeAssets.dll')
$script:themeRoot=$PSScriptRoot
$script:themeTask=$null
$script:themeCache=$null
function Get-ThemeImage([string]$Name){
 $image=[Windows.Media.Imaging.BitmapImage]::new();$image.BeginInit();$image.CacheOption=[Windows.Media.Imaging.BitmapCacheOption]::OnLoad;$image.UriSource=[Uri]::new((Join-Path $script:themeCache ($Name+'.png')));$image.EndInit();$image.Freeze();return $image
}
function Apply-GameTheme([string]$Cache){
 $script:themeCache=$Cache
 foreach($pair in @(@('button','ButtonMask'),@('noise','NoiseMask'),@('base','BaseMask'),@('line','LineMask'))){$brush=[Windows.Media.ImageBrush]::new((Get-ThemeImage $pair[0]));$brush.Stretch='Fill';$brush.Freeze();$window.Resources[$pair[1]]=$brush}
 $window.FindName('EdgeGlow').OpacityMask=[Windows.Media.ImageBrush]::new((Get-ThemeImage 'glow'))
 $uri=[Uri]::new($Cache.TrimEnd('/','\')+[IO.Path]::DirectorySeparatorChar)
 $window.Resources['HeadingFont']=[Windows.Media.FontFamily]::new($uri,'./#Amarante')
 $window.Resources['BodyFont']=[Windows.Media.FontFamily]::new($uri,'./#Catamaran')
 $pulse=[Windows.Media.Animation.DoubleAnimation]::new(0.23,0.38,[Windows.Duration]::new([TimeSpan]::FromSeconds(6)))
 $pulse.AutoReverse=$true;$pulse.RepeatBehavior=[Windows.Media.Animation.RepeatBehavior]::Forever
 $window.FindName('EdgeGlow').BeginAnimation([Windows.UIElement]::OpacityProperty,$pulse)
 $veil=[Windows.Media.Animation.DoubleAnimation]::new(0.025,0.065,[Windows.Duration]::new([TimeSpan]::FromSeconds(9)))
 $veil.AutoReverse=$true;$veil.RepeatBehavior=[Windows.Media.Animation.RepeatBehavior]::Forever
 $window.FindName('CloudVeil').BeginAnimation([Windows.UIElement]::OpacityProperty,$veil)
}
function Start-GameTheme{
 $script:themeTask=[ClanThemeAssets]::Begin($pathBox.Text,$script:themeRoot)
 $script:themeTimer.Start()
}
$script:themeTimer=[Windows.Threading.DispatcherTimer]::new();$script:themeTimer.Interval=[TimeSpan]::FromMilliseconds(200)
$script:themeTimer.Add_Tick({
 if(!$script:themeTask){return}
 if(!$script:themeTask.IsCompleted){if(!$script:busy){$status.Text=[ClanThemeAssets]::Progress};return}
 $script:themeTimer.Stop()
 if($script:themeTask.IsFaulted){$status.Text='Original artwork unavailable: '+$script:themeTask.Exception.GetBaseException().Message;return}
 try{Apply-GameTheme $script:themeTask.Result;if(!$script:busy){$status.Text='Changes apply on the next game launch.'}}catch{$status.Text='Could not display game artwork: '+$_.Exception.Message}
})
$window.Add_Closed({$script:themeTimer.Stop()})

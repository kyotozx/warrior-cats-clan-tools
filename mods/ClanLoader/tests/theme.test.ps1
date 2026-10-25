param([string]$GameDirectory='C:/Program Files (x86)/Steam/steamapps/common/Warrior Cats Clans of the Forest')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Web.Extensions
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../manager'))
Add-Type -Path (Join-Path $root 'ThemeAssets.dll')
$recipe=Get-Content (Join-Path $root 'theme-assets.json') -Raw|ConvertFrom-Json
$cache=[ClanThemeAssets]::Prepare($GameDirectory,$root)
if([ClanThemeAssets]::Prepare($GameDirectory,$root) -cne $cache){throw 'Warm cache differs'}
foreach($a in $recipe.assets){
 if($a.font){continue}
 $image=[Windows.Media.Imaging.BitmapImage]::new([Uri]::new((Join-Path $cache ($a.name+'.png'))))
 if($image.PixelWidth -ne $a.width -or $image.PixelHeight -ne $a.height){throw 'Texture dimensions differ'}
}
$fonts=@([Windows.Media.Fonts]::GetFontFamilies($cache.TrimEnd('/','\')+'/')|ForEach-Object {$_.FamilyNames.Values})
if('Amarante' -notin $fonts -or 'Catamaran' -notin $fonts){throw 'Original fonts unavailable'}
$window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new([xml](Get-Content (Join-Path $root 'Manager.xaml') -Raw)))
if(!$window.FindName('AppMark') -or !$window.FindName('SkinMark')){throw 'Icon targets missing'}
$window.Close()
$fixture=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../analysis/loader-theme'))) ('reject-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $fixture
$recipe.assets[0].blocks[0].sha256=('0'*64)
$recipe|ConvertTo-Json -Depth 12|Set-Content (Join-Path $fixture 'theme-assets.json') -Encoding UTF8
$rejected=$false
try{$null=[ClanThemeAssets]::Prepare($GameDirectory,$fixture)}catch{if($_.Exception.GetBaseException().Message -like '*differs from supported build*'){$rejected=$true}else{throw}}
if(!$rejected){throw 'Changed game block was accepted'}
Write-Output ('PASS: '+$recipe.assets.Count+' verified assets, warm cache, texture dimensions, original fonts, XAML and incorrect-source refusal.')

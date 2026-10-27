$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$fixture=Join-Path $repo ('analysis/launcher-policy-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $fixture
$scriptPath=Join-Path $fixture 'Manager.ps1'
$helperPath=Join-Path $fixture 'Helper.ps1'
[IO.File]::WriteAllText($scriptPath, '. (Join-Path $PSScriptRoot "Helper.ps1"); Get-FixtureValue')
[IO.File]::WriteAllText($helperPath, 'function Get-FixtureValue { "helper-loaded" }')
foreach($path in @($scriptPath,$helperPath)){
    Set-Content -LiteralPath $path -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding ASCII
}
$themeScript=Join-Path $fixture 'ManagerTheme.ps1'
$themeDll=Join-Path $fixture 'ThemeAssets.dll'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../manager/ThemeAssets.dll') -Destination $themeDll
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../manager/Theme.ps1') -Destination $fixture
$unrelated=Join-Path $fixture 'Unrelated.dll'
[IO.File]::WriteAllText($unrelated,'Unrelated download must stay marked')
$themeProbe=@'
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$window=[Windows.Window]::new()
. (Join-Path $PSScriptRoot 'Theme.ps1')
if(![ClanThemeAssets].GetMethod('Begin')){throw 'Theme helper unavailable'}
$window.Close()
'theme-loaded'
'@
[IO.File]::WriteAllText($themeScript,$themeProbe)
foreach($path in @($themeDll,$themeScript,(Join-Path $fixture 'Theme.ps1'),$unrelated)){
 Set-Content -LiteralPath $path -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding ASCII
}
$dllHash=(Get-FileHash -LiteralPath $themeDll).Hash
$compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$automation=Join-Path $env:WINDIR 'Microsoft.NET/assembly/GAC_MSIL/System.Management.Automation/v4.0_3.0.0.0__31bf3856ad364e35/System.Management.Automation.dll'
$exe=Join-Path $fixture 'LauncherPolicyTest.exe'
& $compiler /nologo /target:exe /platform:x64 /main:LauncherPolicyTest ('/reference:'+$automation) /reference:System.Windows.Forms.dll ('/out:'+$exe) (Join-Path $PSScriptRoot '../manager/Launcher.cs') (Join-Path $PSScriptRoot 'LauncherPolicyTest.cs')
if($LASTEXITCODE -ne 0){throw 'Launcher policy fixture compilation failed.'}
# The fixture changes only its own process policy, never this PowerShell host.
$before=$env:PSExecutionPolicyPreference
& $exe $scriptPath $themeScript
if($LASTEXITCODE -ne 0){throw 'Launcher execution policy regression.'}
if($env:PSExecutionPolicyPreference -ne $before){throw 'Parent process policy changed.'}
Write-Output 'PASS parent process policy unchanged'
if(Get-Item -LiteralPath $themeDll -Stream Zone.Identifier -ErrorAction SilentlyContinue){throw 'Bundled DLL is still marked as downloaded'}
if((Get-FileHash -LiteralPath $themeDll).Hash -ne $dllHash){throw 'Theme DLL content changed'}
foreach($path in @($unrelated,$scriptPath,$themeScript)){
 if(!(Get-Item -LiteralPath $path -Stream Zone.Identifier -ErrorAction SilentlyContinue)){throw 'Unrelated download marker was removed'}
}
Write-Output 'PASS only bundled theme DLL unblocked; binary contents and unrelated download markers preserved'

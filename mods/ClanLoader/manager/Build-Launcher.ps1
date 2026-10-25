$ErrorActionPreference='Stop'
$compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$automation=Join-Path $env:WINDIR 'Microsoft.NET/assembly/GAC_MSIL/System.Management.Automation/v4.0_3.0.0.0__31bf3856ad364e35/System.Management.Automation.dll'
& (Join-Path $PSScriptRoot 'Build-Icons.ps1')
& $compiler /nologo /target:winexe /platform:x64 /optimize+ ('/reference:'+$automation) /reference:System.Windows.Forms.dll ('/win32icon:'+(Join-Path $PSScriptRoot 'icons/loader.ico')) ('/out:'+(Join-Path $PSScriptRoot 'ClanLoader.exe')) (Join-Path $PSScriptRoot 'Launcher.cs')
if($LASTEXITCODE -ne 0){throw 'GUI launcher compilation failed.'}
Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'ClanLoader.exe')

$framework=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'
& $compiler /nologo /target:library /optimize+ /reference:System.Xaml.dll /reference:System.Web.Extensions.dll ('/reference:'+$framework+'/WPF/PresentationCore.dll') ('/reference:'+$framework+'/WPF/WindowsBase.dll') ('/out:'+(Join-Path $PSScriptRoot 'ThemeAssets.dll')) (Join-Path $PSScriptRoot 'ThemeAssets.cs')
if($LASTEXITCODE -ne 0){throw 'Theme decoder compilation failed.'}

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
$compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$automation=Join-Path $env:WINDIR 'Microsoft.NET/assembly/GAC_MSIL/System.Management.Automation/v4.0_3.0.0.0__31bf3856ad364e35/System.Management.Automation.dll'
$exe=Join-Path $fixture 'LauncherPolicyTest.exe'
& $compiler /nologo /target:exe /platform:x64 /main:LauncherPolicyTest ('/reference:'+$automation) /reference:System.Windows.Forms.dll ('/out:'+$exe) (Join-Path $PSScriptRoot '../manager/Launcher.cs') (Join-Path $PSScriptRoot 'LauncherPolicyTest.cs')
if($LASTEXITCODE -ne 0){throw 'Launcher policy fixture compilation failed.'}
# The fixture changes only its own process policy, never this PowerShell host.
$before=$env:PSExecutionPolicyPreference
& $exe $scriptPath
if($LASTEXITCODE -ne 0){throw 'Launcher execution policy regression.'}
if($env:PSExecutionPolicyPreference -ne $before){throw 'Parent process policy changed.'}
Write-Output 'PASS parent process policy unchanged'

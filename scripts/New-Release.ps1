param([Parameter(Mandatory=$true)][string]$Version,[Parameter(Mandatory=$true)][string]$UE4SSDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$runtime=(Resolve-Path -LiteralPath $UE4SSDirectory).Path
Push-Location $root
try{
 $output=Join-Path $root 'dist'
 & ./mods/ClanTools/release/Build-Package.ps1 -Version $Version -NativeSelection analysis/community/native-verify/native-selection.built.json -NativeAudit analysis/community/native-verify/source-binary-audit.json -OutputRoot $output -UE4SSDirectory $runtime
 & ./mods/ClanLoader/Build-Package.ps1 -Version $Version -ClanToolsPackage (Join-Path $output ('ClanTools-'+$Version)) -OutputRoot $output
 Write-Output 'Release staged locally. Run live acceptance before publishing a rebuilt release.'
}finally{Pop-Location}

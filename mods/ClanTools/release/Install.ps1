param([string]$GameDirectory,[switch]$ValidateOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Package.Core.ps1')
$game=Find-GameDirectory $GameDirectory
Install-ClanToolsPackage $PSScriptRoot $game (Join-Path $env:LOCALAPPDATA 'ClanTools/Backups') (Join-Path $env:LOCALAPPDATA 'Wrc/Saved/SaveGames') -ValidateOnly:$ValidateOnly

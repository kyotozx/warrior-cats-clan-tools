param([string]$GameDirectory,[switch]$DisableOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Package.Core.ps1')
$game=Find-GameDirectory $GameDirectory
Uninstall-ClanToolsPackage $game (Join-Path $env:LOCALAPPDATA 'ClanTools/Backups') (Join-Path $env:LOCALAPPDATA 'Wrc/Saved/SaveGames') -DisableOnly:$DisableOnly

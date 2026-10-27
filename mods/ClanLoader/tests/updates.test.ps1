$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../manager/Updates.Core.ps1')
function Check($Value,[string]$Message){if(!$Value){throw $Message}}
Check ((Compare-ReleaseVersion 'v0.3.0-rc10' '0.3.0-rc6') -eq 1) 'RC numbers must compare numerically.'
Check ((Compare-ReleaseVersion '0.3.0' '0.3.0-rc10') -eq 1) 'Stable follows its release candidates.'
Check ((Compare-ReleaseVersion '0.3.1-preview.1' '0.3.0') -eq 1) 'Preview version parsing failed.'
Check ((Compare-ReleaseVersion '0.3.0-rc6' 'v0.3.0-rc6') -eq 0) 'Equivalent versions differ.'
Check ($null -eq (Compare-ReleaseVersion 'not-a-version' '0.3.0')) 'Invalid version should not offer an update.'
$releases=@(
 @{tag_name='v0.3.0-rc7';draft=$false;assets=@(@{name='ClanLoader-0.3.0-rc7.zip'});html_url='https://untrusted.invalid'},
 @{tag_name='v99.0.0';draft=$true;assets=@(@{name='ClanLoader-99.0.0.zip'})},
 @{tag_name='v1.0.0';draft=$false;assets=@(@{name='diagnostic.zip'})}
)
$release=Select-PublishedRelease $releases 'kyotozx/warrior-cats-clan-tools'
Check ($release.version -eq '0.3.0-rc7') 'Drafts and diagnostic archives must be ignored.'
Check ($release.url -eq 'https://github.com/kyotozx/warrior-cats-clan-tools/releases/tag/v0.3.0-rc7') 'Release URL must stay on the known repository.'
$found=@(Get-AvailableModUpdates @(@{id='ClanTools';name='Clan Tools';version='0.3.0-rc6'},@{id='Other';name='Other';version='0.0.1'}) @{'kyotozx/warrior-cats-clan-tools'=$release})
Check ($found.Count -eq 1 -and $found[0].id -eq 'ClanTools') 'Only known installed mods should be matched.'
Check (@(Get-AvailableModUpdates @(@{id='ClanTools';name='Clan Tools';version='0.3.0-rc8'}) @{'kyotozx/warrior-cats-clan-tools'=$release}).Count -eq 0) 'Never suggest downgrading.'
Write-Output 'PASS: update versions, published package filtering, trusted links and installed-mod matching.'

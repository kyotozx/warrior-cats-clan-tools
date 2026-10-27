$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'release/Package.Core.ps1')
$allow=Get-Content -LiteralPath (Join-Path $root 'release/files.json') -Raw|ConvertFrom-Json
$dlls=@(Get-ChildItem -LiteralPath (Join-Path $root 'bin') -File -Filter '*.dll'|ForEach-Object Name)
foreach($name in $allow.scripts){
 $source=Get-ContainedPath $root ('Scripts/'+$name)
 if(!(Test-Path -LiteralPath $source -PathType Leaf)){throw "Missing script: $name"}
 Assert-LuaReleaseDependencies $name ([IO.File]::ReadAllText($source)) @($allow.scripts) $dlls @($allow.data)
}
foreach($source in Get-ChildItem -LiteralPath (Join-Path $root 'Scripts') -File -Filter '*.lua'){
 if($source.Name -notin $allow.scripts){throw "Production Lua omitted from explicit source list: $($source.Name)"}
}
foreach($name in $allow.nativeSources){
 $source=Get-ContainedPath $root ('native/'+$name)
 Assert-NativeReleaseDependencies $name ([IO.File]::ReadAllText($source)) @($allow.nativeSources)
}
foreach($name in $allow.data){
 if(!(Test-ClanToolsProgramPath ('data/'+$name))){throw "Unsupported metadata: $name"}
 $null=Get-Content -LiteralPath (Get-ContainedPath $root ('data/'+$name)) -Raw|ConvertFrom-Json
}
foreach($name in $allow.icons){
 if(!(Test-ClanToolsProgramPath ('assets/icons/'+$name))){throw "Unsupported icon: $name"}
 $bytes=[IO.File]::ReadAllBytes((Get-ContainedPath $root ('assets/icons/'+$name)))
 if($bytes.Length -lt 24 -or [BitConverter]::ToString($bytes,0,8) -ne '89-50-4E-47-0D-0A-1A-0A'){throw "Invalid PNG: $name"}
}
foreach($name in $allow.documentation){if(!(Test-Path -LiteralPath (Get-ContainedPath (Join-Path $root 'release') $name) -PathType Leaf)){throw "Missing release documentation: $name"}}
foreach($name in @('Build-Package.ps1','Package.Core.ps1','Install.ps1','Uninstall.ps1')){
 $parseErrors=$null;$tokens=$null
 $null=[Management.Automation.Language.Parser]::ParseFile((Get-ContainedPath (Join-Path $root 'release') $name),[ref]$tokens,[ref]$parseErrors)
 if($parseErrors.Count){throw "Release PowerShell syntax error: $name : $parseErrors"}
}
Write-Output "PASS explicit $($allow.scripts.Count) Lua modules, $($allow.nativeSources.Count) native sources, $($allow.data.Count) static catalogs and release documentation closure."
Write-Output 'Existing workspace DLL filenames checked only. Native source/binary/hash audit, runtime acceptance and final selection remain pending. No package staged.'

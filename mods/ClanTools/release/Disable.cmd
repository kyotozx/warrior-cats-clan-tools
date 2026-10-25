@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1" -DisableOnly %*
if errorlevel 1 echo Disable failed. Read the message above.
pause

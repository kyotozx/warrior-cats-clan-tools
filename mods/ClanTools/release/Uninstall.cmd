@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1" %*
if errorlevel 1 echo Uninstall failed. Read the message above.
pause

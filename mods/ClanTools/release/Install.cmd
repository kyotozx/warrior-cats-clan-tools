@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %*
if errorlevel 1 echo Installation failed. Read the message above; no global execution policy was changed.
pause

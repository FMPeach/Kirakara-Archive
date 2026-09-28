@echo off
setlocal
where pwsh.exe >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
  echo Kirakara flutterw requires PowerShell 7 ^(pwsh.exe^) on PATH. 1>&2
  exit /b 1
)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0flutterw.ps1" %*
exit /b %ERRORLEVEL%

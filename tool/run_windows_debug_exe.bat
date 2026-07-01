@echo off
setlocal
set "PROJECT_DIR=D:\Kirakara-App-ascii"
set "FLUTTER_BIN=D:\Program Files\Flutter\bin"
set "PATH=%FLUTTER_BIN%;%PATH%"
set "EXE=%PROJECT_DIR%\build\windows\x64\runner\Debug\kirakara_app.exe"

cd /d "%PROJECT_DIR%"
if not exist "%EXE%" (
  echo Debug exe does not exist yet. Building it first...
  call "%PROJECT_DIR%\tool\build_windows_debug_exe.bat"
  if errorlevel 1 exit /b 1
)

echo Starting:
echo %EXE%
start "" "%EXE%"

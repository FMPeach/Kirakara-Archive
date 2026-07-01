@echo off
setlocal
set "PROJECT_DIR=D:\Kirakara-App-ascii"
set "FLUTTER_BIN=D:\Program Files\Flutter\bin"
set "PATH=%FLUTTER_BIN%;%PATH%"

cd /d "%PROJECT_DIR%"
echo Starting Kirakara-App with Flutter debug runner...
echo.
flutter run -d windows

echo.
echo Debug runner exited.
pause

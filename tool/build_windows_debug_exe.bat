@echo off
setlocal
set "PROJECT_DIR=D:\Kirakara-App-ascii"
set "FLUTTER_BIN=D:\Program Files\Flutter\bin"
set "PATH=%FLUTTER_BIN%;%PATH%"

cd /d "%PROJECT_DIR%"
echo Building Kirakara-App Debug exe...
echo.
flutter pub get
if errorlevel 1 goto failed

flutter build windows --debug
if errorlevel 1 goto failed

echo.
echo Debug exe built:
echo %PROJECT_DIR%\build\windows\x64\runner\Debug\kirakara_app.exe
explorer.exe /select,"%PROJECT_DIR%\build\windows\x64\runner\Debug\kirakara_app.exe"
pause
exit /b 0

:failed
echo.
echo Build failed. The console output above has the useful error.
pause
exit /b 1

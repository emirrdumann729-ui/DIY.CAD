@echo off
rem Builds the DIY.CAD Windows package: build\DIY.CAD.exe (+ occ, macros, plugins) and, if available, an Inno Setup installer.
rem Required: Godot 4.7.1 export templates (Godot editor: Editor > Manage Export Templates > Download).
rem Optional: Inno Setup 6 (https://jrsoftware.org/isdl.php) -> build\installer\DIY.CAD-<version>-setup.exe
cd /d "%~dp0"
set G=..\Godot\Godot_v4.7.1-stable_win64_console.exe
set T=%APPDATA%\Godot\export_templates\4.7.1.stable\windows_release_x86_64.exe
if not exist "%T%" (
  echo Export templates not found: %T%
  echo In the Godot editor: Editor ^> Manage Export Templates ^> Download and Install
  pause
  exit /b 1
)
if not exist icon.ico "%G%" --headless --path . --script res://tools/make_icon.gd
if not exist build mkdir build
type nul > build\.gdignore
"%G%" --headless --path . --export-release "Windows" build\DIY.CAD.exe
if errorlevel 1 (
  echo Export failed.
  pause
  exit /b 1
)
xcopy /y /i /q occ\*.py build\occ\ >nul
xcopy /y /i /q macros\*.gd build\macros\ >nul
xcopy /y /i /q plugins\*.gd build\plugins\ >nul
copy /y OCC_Kur.bat build\ >nul
copy /y README.md build\ >nul
copy /y CHANGELOG.md build\ >nul
copy /y LICENSE build\ >nul
echo Portable build ready: build\DIY.CAD.exe  (for OpenCASCADE run build\OCC_Kur.bat)
set ISCC=
if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe
if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe
if exist "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" set ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe
if "%ISCC%"=="" (
  echo Inno Setup 6 not found: installer skipped.
) else (
  "%ISCC%" installer\DIYCAD.iss
  echo Installer: build\installer\
)
pause

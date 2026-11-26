@echo off
rem DIY.CAD Windows paketini hazirlar: build\DIY.CAD.exe (+ occ, macros, plugins) ve varsa Inno Setup ile kurulum dosyasi.
rem Gereken: Godot 4.7.1 disa aktarma sablonlari (Godot editoru: Editor > Manage Export Templates > Download).
rem Istege bagli: Inno Setup 6 (https://jrsoftware.org/isdl.php) -> build\installer\DIY.CAD-<surum>-kurulum.exe
cd /d "%~dp0"
set G=..\Godot\Godot_v4.7.1-stable_win64_console.exe
set T=%APPDATA%\Godot\export_templates\4.7.1.stable\windows_release_x86_64.exe
if not exist "%T%" (
  echo Disa aktarma sablonlari bulunamadi: %T%
  echo Godot editorunde: Editor ^> Manage Export Templates ^> Download and Install
  pause
  exit /b 1
)
if not exist icon.ico "%G%" --headless --path . --script res://tools/make_icon.gd
if not exist build mkdir build
type nul > build\.gdignore
"%G%" --headless --path . --export-release "Windows" build\DIY.CAD.exe
if errorlevel 1 (
  echo Disa aktarma basarisiz.
  pause
  exit /b 1
)
xcopy /y /i /q occ\*.py build\occ\ >nul
xcopy /y /i /q macros\*.gd build\macros\ >nul
xcopy /y /i /q plugins\*.gd build\plugins\ >nul
copy /y OCC_Kur.bat build\ >nul
copy /y README.md build\ >nul
copy /y CHANGELOG.md build\ >nul
echo Tasinabilir surum hazir: build\DIY.CAD.exe  (OpenCASCADE icin build\OCC_Kur.bat)
set ISCC=
if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe
if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe
if exist "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" set ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe
if "%ISCC%"=="" (
  echo Inno Setup 6 bulunamadi: kurulum dosyasi atlandi.
) else (
  "%ISCC%" installer\DIYCAD.iss
  echo Kurulum dosyasi: build\installer\
)
pause

@echo off
rem DIY.CAD programini baslatir
cd /d "%~dp0"
if not exist "..\Godot\Godot_v4.7.1-stable_win64.exe" (
  echo Godot bulunamadi: %~dp0..\Godot\Godot_v4.7.1-stable_win64.exe
  pause
  exit /b 1
)
start "" "..\Godot\Godot_v4.7.1-stable_win64.exe" --path .

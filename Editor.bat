@echo off
rem Opens the DIY.CAD project in the Godot editor
cd /d "%~dp0"
if not exist "..\Godot\Godot_v4.7.1-stable_win64.exe" (
  echo Godot not found: %~dp0..\Godot\Godot_v4.7.1-stable_win64.exe
  pause
  exit /b 1
)
start "" "..\Godot\Godot_v4.7.1-stable_win64.exe" -e --path .

@echo off
rem Runs the automated tests
cd /d "%~dp0"
set G=..\Godot\Godot_v4.7.1-stable_win64_console.exe
"%G%" --headless --path . --script res://tests/selftest.gd
"%G%" --headless --path . --script res://tests/solver_test.gd
"%G%" --headless --path . --script res://tests/ops_test.gd
"%G%" --headless --path . --script res://tests/drawing_test.gd
"%G%" --headless --path . --script res://tests/assembly_test.gd
"%G%" --headless --path . --script res://tests/special_test.gd
"%G%" --headless --path . --script res://tests/pro_test.gd
"%G%" --headless --path . -- --uitest --kernel=csg
if exist occ_env\Scripts\python.exe (
  "%G%" --headless --path . --script res://tests/occ_test.gd -- --kernel=occ
  "%G%" --headless --path . -- --uitest --kernel=occ
)
pause

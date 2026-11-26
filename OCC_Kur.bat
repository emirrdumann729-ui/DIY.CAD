@echo off
rem OpenCASCADE (B-rep) cekirdegini kurar: projeye ozel Python ortami + cadquery-ocp-novtk (~180 MB)
cd /d "%~dp0"
where python >nul 2>nul || (echo Python 3.11-3.13 bulunamadi. https://www.python.org adresinden kurun. & pause & exit /b 1)
if not exist occ_env\Scripts\python.exe python -m venv occ_env
type nul > occ_env\.gdignore
occ_env\Scripts\python.exe -m pip install --upgrade pip
occ_env\Scripts\python.exe -m pip install --no-deps "cadquery-ocp-novtk>=8.0,<8.1"
rem Statik analiz (FEA) icin seyrek cozucu: numpy + scipy (~60 MB)
occ_env\Scripts\python.exe -m pip install numpy scipy
occ_env\Scripts\python.exe -c "import OCP, numpy, scipy; print('OpenCASCADE hazir, OCP', OCP.__version__, '/ numpy', numpy.__version__, '/ scipy', scipy.__version__)"
pause

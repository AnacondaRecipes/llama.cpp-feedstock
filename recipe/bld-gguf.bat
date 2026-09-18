@echo off
setlocal EnableDelayedExpansion

cd gguf-py
if errorlevel 1 exit 1

:: Relax upstream's `numpy (>=2.2.6)` in pyproject.toml to match the conda run:
:: pin (`numpy >=2.2.5`). pkgs/main lacks numpy 2.2.6+ for py3.10; without this
:: the wheel metadata forces `pip check` to fail on py3.10. See build-gguf.sh
:: for the full rationale. python -c avoids cmd.exe's `\"` escape trap where
:: powershell would receive literal backslash-quote and silently no-op.
python -c "import pathlib; f=pathlib.Path('pyproject.toml'); f.write_text(f.read_text().replace('numpy (>=2.2.6)', 'numpy (>=2.2.5)'))"
if errorlevel 1 exit 1

:: Install the package using pip
pip install . -vv --no-deps --no-build-isolation
if errorlevel 1 exit 1

:: Exit with success code
exit /b 0
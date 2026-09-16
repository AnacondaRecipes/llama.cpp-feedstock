@echo off
setlocal EnableDelayedExpansion

cd gguf-py
if errorlevel 1 exit 1

:: Relax upstream's `numpy (>=2.2.6)` in pyproject.toml to match the conda run:
:: pin (`numpy >=2.2.5`). pkgs/main lacks numpy 2.2.6+ for py3.10; without this
:: the wheel metadata forces `pip check` to fail on py3.10. See build-gguf.sh
:: for the full rationale.
powershell -Command "(Get-Content pyproject.toml) -replace \"'numpy \(>=2\.2\.6\)'\", \"'numpy (>=2.2.5)'\" | Set-Content pyproject.toml"
if errorlevel 1 exit 1

:: Install the package using pip
pip install . -vv --no-deps --no-build-isolation
if errorlevel 1 exit 1

:: Exit with success code
exit /b 0
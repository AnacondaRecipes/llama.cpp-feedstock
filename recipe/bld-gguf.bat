@echo off
setlocal EnableDelayedExpansion

cd gguf-py
if errorlevel 1 exit 1

:: Install the package using pip
pip install . -vv --no-deps --no-build-isolation
if errorlevel 1 exit 1

:: Exit with success code
exit /b 0
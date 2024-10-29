@echo off

:: Create our package directory
if not exist %SP_DIR%\llama_cpp_tools mkdir %SP_DIR%\llama_cpp_tools
if errorlevel 1 exit 1

copy convert_hf_to_gguf.py %SP_DIR%\llama_cpp_tools\
if errorlevel 1 exit 1

copy convert_llama_ggml_to_gguf.py %SP_DIR%\llama_cpp_tools\
if errorlevel 1 exit 1

:: Install the llava scripts from the examples directory
if not exist %SP_DIR%\llama_cpp_tools\examples\llava mkdir %SP_DIR%\llama_cpp_tools\examples\llava
if errorlevel 1 exit 1

xcopy .\examples\llava\*.py %SP_DIR%\llama_cpp_tools\examples\llava\ /E /I /Y
if errorlevel 1 exit 1

:: Create an __init__.py file to make it a proper Python package
type nul > %SP_DIR%\llama_cpp_tools\__init__.py
if errorlevel 1 exit 1

type nul > %SP_DIR%\llama_cpp_tools\examples\__init__.py
if errorlevel 1 exit 1

type nul > %SP_DIR%\llama_cpp_tools\examples\llava\__init__.py
if errorlevel 1 exit 1

:: Exit with success code
exit /b 0
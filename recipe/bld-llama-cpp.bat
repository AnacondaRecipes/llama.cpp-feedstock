@echo off
setlocal EnableDelayedExpansion

REM GGML build options
set GGML_ARGS=-DGGML_NATIVE=OFF -DGGML_CPU_ALL_VARIANTS=ON -DGGML_BACKEND_DL=ON
set GGML_OPENMP_FLAGS=

if "%gpu_variant:~0,5%"=="cuda-" (
    REM Let llama.cpp's CMakeLists.txt handle architecture selection
    REM It automatically uses 120a-real for CUDA 12.8+ (fixes MXFP4 compilation)
    REM See: https://github.com/ggml-org/llama.cpp/pull/18672
    set GGML_ARGS=!GGML_ARGS! -DGGML_CUDA=ON
) else (
    set GGML_ARGS=!GGML_ARGS! -DGGML_CUDA=OFF
)

if "%blas_impl%"=="mkl" (
    set GGML_ARGS=!GGML_ARGS! -DGGML_BLAS=ON
    set GGML_ARGS=!GGML_ARGS! -DGGML_ACCELERATE=OFF
    set GGML_ARGS=!GGML_ARGS! -DGGML_BLAS_VENDOR=Intel10_64_dyn
    set GGML_OPENMP_FLAGS=-DOpenMP_C_FLAGS=/openmp:llvm -DOpenMP_CXX_FLAGS=/openmp:llvm -DOpenMP_C_LIB_NAMES=libiomp5md -DOpenMP_CXX_LIB_NAMES=libiomp5md -DOpenMP_libiomp5md_LIBRARY=%LIBRARY_LIB%\libiomp5md.lib
) else if "%blas_impl%"=="openblas" (
    set GGML_ARGS=!GGML_ARGS! -DGGML_BLAS=ON
    set GGML_ARGS=!GGML_ARGS! -DGGML_ACCELERATE=OFF
    set GGML_ARGS=!GGML_ARGS! -DGGML_BLAS_VENDOR=OpenBLAS
    REM openblas-devel on Windows installs headers under Library/include/openblas/.
    set GGML_ARGS=!GGML_ARGS! -DGGML_OPENBLAS_INCLUDE_DIR=%LIBRARY_PREFIX%/include/openblas
) else (
    REM Note: LLAMA_CUDA=ON enables cublas.
    REM Tests fail when both mkl and cublas are used.
    REM This has also been reported here: https://github.com/ggerganov/llama.cpp/issues/4626
    set GGML_ARGS=!GGML_ARGS! -DGGML_BLAS=OFF
)

REM win-arm64 uses clang; FindOpenMP otherwise picks VS libomp140.aarch64.dll from the
REM host toolset, which is not in the conda env and makes ctest fail with 0xc0000135.
if /i "%target_platform%"=="win-arm64" (
    if not "%blas_impl%"=="mkl" (
        set GGML_OPENMP_FLAGS=-DOpenMP_C_FLAGS=-fopenmp=libomp -DOpenMP_CXX_FLAGS=-fopenmp=libomp -DOpenMP_C_LIB_NAMES=libomp -DOpenMP_CXX_LIB_NAMES=libomp -DOpenMP_libomp_LIBRARY=%LIBRARY_LIB%\libomp.lib
    )
)

REM LLAMA build options
set LLAMA_ARGS=-DLLAMA_BUILD_NUMBER=%LLAMA_BUILD_NUMBER% -DLLAMA_BUILD_COMMIT=%LLAMA_BUILD_COMMIT%
set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_OPENSSL=ON
REM Disable the unified `llama` router app: it #includes common/build-info.h but
REM the upstream app/CMakeLists.txt does not wire up its include path, so the
REM build fails with "fatal error: build-info.h: No such file or directory".
REM Upstream workaround documented in ggml-org/llama.cpp#23628.
set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_APP=OFF
if "%PKG_NAME%" == "libllama" (
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_SERVER=OFF
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_TOOLS=OFF
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_TESTS=OFF
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_EXAMPLES=OFF
) else if "%PKG_NAME%" == "llama.cpp" (
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_SERVER=ON
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_TOOLS=ON
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_TESTS=OFF
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_EXAMPLES=OFF
) else if "%PKG_NAME%" == "llama.cpp-tests" (
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_SERVER=OFF
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_TOOLS=OFF
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_TESTS=ON
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_EXAMPLES=OFF
) else (
    echo "Invalid package name: %PKG_NAME%"
    exit 1
)
REM TODO add LLAMA_LLGUIDANCE?
REM TODO set LLAMA_USE_SYSTEM_GGML once ggml gets its own feedstock

cmake -S . -B build ^
    -G Ninja ^
    !CMAKE_ARGS! ^
    -DCMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX% ^
    -DCMAKE_PREFIX_PATH=%LIBRARY_PREFIX% ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DBUILD_SHARED_LIBS=ON  ^
    !GGML_ARGS! ^
    !GGML_OPENMP_FLAGS! ^
    !LLAMA_ARGS!
if errorlevel 1 exit 1

cmake --build build --config Release --verbose
if errorlevel 1 exit 1

cmake --install build
if errorlevel 1 exit 1

if "%PKG_NAME%" == "llama.cpp-tests" (
    pushd build
    REM With GGML_BACKEND_DL=ON, tests load backend DLLs from build/bin and need
    REM openblas.dll and libomp.dll beside the test exes (or on PATH). 0xc0000135 otherwise.
    REM Use !CD! not %%CD%%: inside parenthesized blocks %%CD%% is expanded before pushd.
    set "PATH=!CD!\bin;%LIBRARY_PREFIX%\bin;%BUILD_PREFIX%\Library\bin;%PATH%"
    if /i "%target_platform%"=="win-arm64" (
        if exist "%LIBRARY_BIN%\libomp.dll" copy /Y "%LIBRARY_BIN%\libomp.dll" "bin\" >nul
        if exist "%LIBRARY_BIN%\openblas.dll" copy /Y "%LIBRARY_BIN%\openblas.dll" "bin\" >nul
    )
    REM test-tokenizers-ggml-vocabs requires git-lfs to download the model files
    ctest -L main -C Release --output-on-failure -j%CPU_COUNT% --timeout 900 -E "test-tokenizers-ggml-vocabs"
    if errorlevel 1 exit 1
    popd
)

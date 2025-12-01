@echo off
setlocal EnableDelayedExpansion

REM GGML build options
set GGML_ARGS=-DGGML_NATIVE=OFF -DGGML_CPU_ALL_VARIANTS=ON -DGGML_BACKEND_DL=ON

if "%gpu_variant:~0,5%"=="cuda-" (
    set CMAKE_ARGS=!CMAKE_ARGS! -DCMAKE_CUDA_ARCHITECTURES=all-major
    set GGML_ARGS=!GGML_ARGS! -DGGML_CUDA=ON
) else (
    set GGML_ARGS=!GGML_ARGS! -DGGML_CUDA=OFF
)

if "%blas_impl%"=="mkl" (
    set GGML_ARGS=!GGML_ARGS! -DGGML_BLAS=ON
    set GGML_ARGS=!GGML_ARGS! -DGGML_ACCELERATE=OFF
    set GGML_ARGS=!GGML_ARGS! -DGGML_BLAS_VENDOR=Intel10_64_dyn
) else if "%blas_impl%"=="openblas" (
    set GGML_ARGS=!GGML_ARGS! -DGGML_BLAS=ON
    set GGML_ARGS=!GGML_ARGS! -DGGML_ACCELERATE=OFF
    set GGML_ARGS=!GGML_ARGS! -DGGML_BLAS_VENDOR=OpenBLAS
) else (
    REM Note: LLAMA_CUDA=ON enables cublas.
    REM Tests fail when both mkl and cublas are used.
    REM This has also been reported here: https://github.com/ggerganov/llama.cpp/issues/4626
    set GGML_ARGS=!GGML_ARGS! -DGGML_BLAS=OFF
)

REM LLAMA build options
set LLAMA_ARGS=-DLLAMA_BUILD_NUMBER=%LLAMA_BUILD_NUMBER% -DLLAMA_BUILD_COMMIT=%LLAMA_BUILD_COMMIT%
set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_CURL=ON
set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_SERVER=ON
set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_TOOLS=ON
set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_TESTS=ON
set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_EXAMPLES=OFF
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
    !LLAMA_ARGS!
if errorlevel 1 exit 1

cmake --build build --config Release --verbose
if errorlevel 1 exit 1

cmake --install build
if errorlevel 1 exit 1

pushd build
REM test-tokenizers-ggml-vocabs requires git-lfs to download the model files
REM Skip test-backend-ops on CUDA (has test failures in b6188)
if "%gpu_variant:~0,5%"=="cuda-" (
    ctest -L main -C Release --output-on-failure -j%CPU_COUNT% --timeout 900 -E "test-tokenizers-ggml-vocabs|test-backend-ops"
) else (
    ctest -L main -C Release --output-on-failure -j%CPU_COUNT% --timeout 900 -E "test-tokenizers-ggml-vocabs"
)
if errorlevel 1 exit 1
popd

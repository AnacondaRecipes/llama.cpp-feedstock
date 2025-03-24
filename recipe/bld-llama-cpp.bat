@echo off
setlocal EnableDelayedExpansion

if "%gpu_variant:~0,5%"=="cuda-" (
    set CMAKE_ARGS=!CMAKE_ARGS! -DCMAKE_CUDA_ARCHITECTURES=all-major
    set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_CUDA=ON
) else (
    set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_CUDA=OFF
)

if "%blas_impl%"=="mkl" (
    set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_BLAS=ON
    set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_ACCELERATE=OFF
    set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_BLAS_VENDOR=Intel10_64_dyn
) else if "%blas_impl%"=="openblas" (
    set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_BLAS=ON
    set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_ACCELERATE=OFF
    set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_BLAS_VENDOR=OpenBLAS
) else (
    REM Note: LLAMA_CUDA=ON enables cublas.
    REM Tests fail when both mkl and cublas are used.
    REM This has also been reported here: https://github.com/ggerganov/llama.cpp/issues/4626
    set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_BLAS=OFF
)

if "%x86_64_opt%"=="v3" (
    set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_AVX2=ON
) else if "%x86_64_opt%"=="v2" (
    set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_AVX=ON
) else (
    set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_AVX=OFF
    set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_AVX2=OFF
    set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_FMA=OFF
)

cmake -S . -B build ^
    -G Ninja ^
    !CMAKE_ARGS! ^
    !LLAMA_ARGS! ^
    -DCMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX% ^
    -DCMAKE_PREFIX_PATH=%LIBRARY_PREFIX% ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DLLAMA_BUILD_TESTS=ON  ^
    -DBUILD_SHARED_LIBS=ON  ^
    -DLLAMA_BUILD_SERVER=ON ^
    -DGGML_NATIVE=OFF ^
    -DGGML_AVX512=OFF ^
    -DGGML_AVX512_VBMI=OFF ^
    -DGGML_AVX512_VNNI=OFF ^
    -DGGML_AVX512_BF16=OFF ^
    -DLLAMA_CURL=ON

if errorlevel 1 exit 1

cmake --build build --config Release --verbose
if errorlevel 1 exit 1

cmake --install build
if errorlevel 1 exit 1

pushd build
ctest -L main -C Release --output-on-failure -j%CPU_COUNT% --timeout 900
if errorlevel 1 exit 1
popd

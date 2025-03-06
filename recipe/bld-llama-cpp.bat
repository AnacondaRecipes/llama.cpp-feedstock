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

REM Configure CPU optimization flags based on the x86_64_opt variable
if "%x86_64_opt%"=="v4" (
    set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_AVX512=ON
    set ARCH_FLAG=/arch:AVX512
) else if "%x86_64_opt%"=="v3" (
    set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_AVX=ON -DGGML_AVX2=ON
    set ARCH_FLAG=/arch:AVX2
) else if "%x86_64_opt%"=="v2" (
    set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_AVX=OFF -DGGML_AVX2=OFF
    set ARCH_FLAG=/arch:SSE2
)

set CXXFLAGS=!CXXFLAGS! !ARCH_FLAG!
set CFLAGS=!CFLAGS! !ARCH_FLAG!

REM Set defaults for instruction sets if not already set
if not "!LLAMA_ARGS!"==*"-DGGML_AVX="* set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_AVX=OFF
if not "!LLAMA_ARGS!"==*"-DGGML_AVX2="* set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_AVX2=OFF
if not "!LLAMA_ARGS!"==*"-DGGML_AVX512="* set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_AVX512=OFF
if not "!LLAMA_ARGS!"==*"-DGGML_AVX512_VBMI="* set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_AVX512_VBMI=OFF
if not "!LLAMA_ARGS!"==*"-DGGML_AVX512_VNNI="* set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_AVX512_VNNI=OFF
if not "!LLAMA_ARGS!"==*"-DGGML_AVX512_BF16="* set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_AVX512_BF16=OFF
if not "!LLAMA_ARGS!"==*"-DGGML_AVX_VNNI="* set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_AVX_VNNI=OFF
if not "!LLAMA_ARGS!"==*"-DGGML_AMX_TILE="* set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_AMX_TILE=OFF
if not "!LLAMA_ARGS!"==*"-DGGML_AMX_INT8="* set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_AMX_INT8=OFF
if not "!LLAMA_ARGS!"==*"-DGGML_AMX_BF16="* set LLAMA_ARGS=!LLAMA_ARGS! -DGGML_AMX_BF16=OFF

cmake -S . -B build ^
    -G Ninja ^
    !CMAKE_ARGS! ^
    !LLAMA_ARGS! ^
    -DCMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX% ^
    -DCMAKE_PREFIX_PATH=%LIBRARY_PREFIX% ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DLLAMA_BUILD_TESTS=ON  ^
    -DBUILD_SHARED_LIBS=ON  ^
    -DGGML_NATIVE=OFF ^
    -DLLAMA_CURL=ON

if errorlevel 1 exit 1

cmake --build build --config Release --verbose
if errorlevel 1 exit 1

cmake --install build
if errorlevel 1 exit 1

pushd build
ctest -L main --output-on-failure -j%CPU_COUNT%
if errorlevel 1 exit 1
popd
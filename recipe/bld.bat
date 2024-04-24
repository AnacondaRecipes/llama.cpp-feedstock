@echo off
setlocal EnableDelayedExpansion

if "%gpu_variant%"=="cuda-12" or "%gpu_variant%"=="cuda-11" (
    set CMAKE_ARGS=!CMAKE_ARGS! -DCMAKE_CUDA_ARCHITECTURES=all
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_CUDA=ON
)

if "%blas_impl%"=="mkl" (
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BLAS=ON
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_ACCELERATE=OFF
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BLAS_VENDOR=Intel10_64_dyn
) else if "%blas_impl%"=="openblas" (
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BLAS=ON
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_ACCELERATE=OFF
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BLAS_VENDOR=OpenBLAS
) else (
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BLAS=OFF
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
    -DLLAMA_NATIVE=OFF ^
    -DLLAMA_AVX=OFF ^
    -DLLAMA_AVX2=OFF ^
    -DLLAMA_AVX512=OFF ^
    -DLLAMA_AVX512_VBMI=OFF ^
    -DLLAMA_AVX512_VNNI=OFF ^
    -DLLAMA_FMA=OFF
if errorlevel 1 exit 1

cmake --build build --config Release --verbose
if errorlevel 1 exit 1

cmake --install build
if errorlevel 1 exit 1

pushd build\tests
ctest --output-on-failure build -j%CPU_COUNT%
if errorlevel 1 exit 1
popd
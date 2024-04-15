@echo off
setlocal EnableDelayedExpansion

if "%gpu_variant%"=="cuda-12" or "%gpu_variant%"=="cuda-11" (
    set CMAKE_ARGS=!CMAKE_ARGS! -DCMAKE_CUDA_ARCHITECTURES=all
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_CUBLAS=ON
)

if "%blas_impl%"=="mkl" (
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BLAS=ON
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_ACCELERATE=OFF
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BLAS_VENDOR=Intel10_64_dyn
) else if "%blas_impl%"=="openblas" (
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BLAS=ON
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_ACCELERATE=OFF
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BLAS_VENDOR=OpenBLAS
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
    -DLLAMA_FMA=OFF ^
    -DLLAMA_F16C=OFF

cmake --build build --config Release --verbose
cmake --install build
pushd build\tests
ctest --output-on-failure build -j%CPU_COUNT%
popd
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

rem TODO: set LLAMA_BUILD_TESTS=ON, i.e. run the upstream tests
cmake -S . -B build ^
    -G Ninja ^
    !CMAKE_ARGS! ^
    !LLAMA_ARGS! ^
    -DLLAMA_BUILD_TESTS=OFF  ^
    -DBUILD_SHARED_LIBS=ON  ^
    -DLLAMA_NATIVE=OFF ^
    -DLLAMA_AVX=OFF ^
    -DLLAMA_AVX2=OFF ^
    -DLLAMA_AVX512=OFF ^
    -DLLAMA_AVX512_VBMI=OFF ^
    -DLLAMA_AVX512_VNNI=OFF ^
    -DLLAMA_FMA=OFF ^
    -DLLAMA_F16C=OFF

cmake --build build --verbose
cmake --install build
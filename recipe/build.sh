#!/bin/bash
set -ex

if [[ ${gpu_variant:-} = "cuda-12" ]]; then
    CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_CUDA_ARCHITECTURES=all"
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_CUBLAS=ON"
    export LDFLAGS="$LDFLAGS -Wl,-rpath-link,/usr/lib64"
elif [[ ${gpu_variant:-} = "cuda-11" ]]; then
    CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_CUDA_ARCHITECTURES=all"
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_CUBLAS=ON"
    export CUDACXX=/usr/local/cuda/bin/nvcc
    export CUDAHOSTCXX="${CXX}"
fi

# LLAMA_METAL is on by default on osx, but it requires macOS v12.3,
# so to support earlier macOS versions we provide the non-metal variant
if [[ "$OSTYPE" == "darwin"* ]] && [[ ${gpu_variant:-} = "none" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_METAL=OFF"
fi

# TODO: implement test that detects whether the correct BLAS is actually used
if [[ ${blas_impl:-} = "accelerate" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BLAS=OFF"
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_ACCELERATE=ON"
elif [[ ${blas_impl:-} = "mkl" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BLAS=ON"
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_ACCELERATE=OFF"
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BLAS_VENDOR=Intel10_64_dyn"
elif [[ ${blas_impl:-} = "openblas" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BLAS=ON"
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_ACCELERATE=OFF"
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BLAS_VENDOR=OpenBLAS"
fi

cmake -S . -B build \
    -G Ninja \
    ${CMAKE_ARGS} \
    ${LLAMA_ARGS} \
    -DCMAKE_INSTALL_PREFIX=${PREFIX} \
    -DCMAKE_PREFIX_PATH=${PREFIX} \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLAMA_BUILD_TESTS=ON  \
    -DBUILD_SHARED_LIBS=ON  \
    -DLLAMA_NATIVE=OFF \
    -DLLAMA_AVX=OFF \
    -DLLAMA_AVX2=OFF \
    -DLLAMA_AVX512=OFF \
    -DLLAMA_AVX512_VBMI=OFF \
    -DLLAMA_AVX512_VNNI=OFF \
    -DLLAMA_FMA=OFF \
    -DLLAMA_F16C=OFF

cmake --build build --config Release --verbose
cmake --install build
pushd build/tests
if [[ "$OSTYPE" == "darwin"* ]] && [[ ${gpu_variant:-} != "none" ]]; then
    export GGML_METAL_PATH_RESOURCES=$PREFIX/bin
fi
ctest --output-on-failure build -j${CPU_COUNT} || true
popd
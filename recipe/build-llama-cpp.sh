#!/bin/bash
set -ex

ARCH=$(uname -m)

if [[ ${gpu_variant:0:5} = "cuda-" ]]; then
    CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_CUDA_ARCHITECTURES=all-major"
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_CUDA=ON"
    # cuda-compat provided libcuda.so.1
    LDFLAGS="$LDFLAGS -Wl,-rpath-link,${PREFIX}/cuda-compat/"
elif [[ ${gpu_variant:-} = "none" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_CUDA=OFF"
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
    if [[ ${gpu_variant:-} = "none" ]]; then
        # GGML_METAL is on by default on osx, but it requires macOS v12.3,
        # so to support earlier macOS versions we provide the non-metal variant
        LLAMA_ARGS="${LLAMA_ARGS} -DGGML_METAL=OFF"
    elif [[ ${gpu_variant:-} = "metal" ]]; then
        # GGML_METAL as a shared library requires xcode 
        # to run metal and metallib commands to compile Metal kernels
        LLAMA_ARGS="${LLAMA_ARGS} -DGGML_METAL=ON"
        LLAMA_ARGS="${LLAMA_ARGS} -DGGML_METAL_EMBED_LIBRARY=ON"
    fi
else
    if [[ ${ARCH} == "x86_64" ]]; then
        # For x86_64 Linux, we enable GGML_CPU_ALL_VARIANTS which will use the optimized backend for the local 
        # architecture. See: https://github.com/ggml-org/llama.cpp/blob/master/ggml/src/CMakeLists.txt#L307
        #
        # This creates multiple CPU backend variants with different instruction sets (AVX, AVX2, AVX512, etc.)
        # The appropriate variant will be selected at runtime based on the CPU capabilities.
        LLAMA_ARGS="${LLAMA_ARGS} -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON"
    fi
fi

# TODO: implement test that detects whether the correct BLAS is actually used
if [[ ${blas_impl:-} = "accelerate" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_BLAS=ON"
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_ACCELERATE=ON"
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_BLAS_VENDOR=Apple"
elif [[ ${blas_impl:-} = "mkl" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_BLAS=ON"
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_ACCELERATE=OFF"
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_BLAS_VENDOR=Intel10_64_dyn"
elif [[ ${blas_impl:-} = "openblas" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_BLAS=ON"
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_ACCELERATE=OFF"
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_BLAS_VENDOR=OpenBLAS"
else
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_BLAS=OFF"
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
    -DGGML_NATIVE=OFF \
    -DGGML_STATIC=OFF \
    -DGGML_CUDA_F16=OFF \
    -DGGML_CUDA_DMMV_F16=OFF \
    -DLLAMA_CURL=ON

cmake --build build --config Release --verbose
cmake --install build
 
# Tests like test_chat use relative paths to load the model template files that break when run from a different 
# parent directory. Tests (per upstream CI workflows) should be run from the build directory.
# See: https://github.com/ggerganov/llama.cpp/blob/master/.github/workflows/build.yml

pushd build
ctest --output-on-failure -L main -j${CPU_COUNT}
popd

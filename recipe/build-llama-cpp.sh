#!/bin/bash
set -ex

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
        # TODO look into GGML_METAL_MACOSX_VERSION_MIN and GGML_METAL_STD
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
    -DBUILD_SHARED_LIBS=ON  \
    -DLLAMA_BUILD_TESTS=ON  \
    -DLLAMA_BUILD_SERVER=ON \
    -DLLAMA_BUILD_NUMBER=${LLAMA_BUILD_NUMBER} \
    -DLLAMA_BUILD_COMMIT=${LLAMA_BUILD_COMMIT} \
    -DGGML_NATIVE=OFF \
    -DGGML_CPU_ALL_VARIANTS=ON \
    -DGGML_BACKEND_DL=ON \
    -DLLAMA_CURL=ON
    # TODO add LLAMA_LLGUIDANCE?
    # TODO add LLAMA_USE_SYSTEM_GGML?

cmake --build build --config Release --verbose
cmake --install build
 
# Tests like test_chat use relative paths to load the model template files that break when run from a different 
# parent directory. Tests (per upstream CI workflows) should be run from the build directory.
# See: https://github.com/ggerganov/llama.cpp/blob/master/.github/workflows/build.yml

pushd build
# test-tokenizers-ggml-vocabs requires git-lfs to download the model files
ctest -L main -C Release --output-on-failure -j${CPU_COUNT} --timeout 900 -E "test-tokenizers-ggml-vocabs"
popd

#!/bin/bash
set -ex

# GGML build options
GGML_ARGS="-DGGML_NATIVE=OFF -DGGML_CPU_ALL_VARIANTS=ON -DGGML_BACKEND_DL=ON"

if [[ ${gpu_variant:0:5} = "cuda-" ]]; then
    CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_CUDA_ARCHITECTURES=all-major"
    GGML_ARGS="${GGML_ARGS} -DGGML_CUDA=ON"
    # cuda-compat provided libcuda.so.1
    LDFLAGS="$LDFLAGS -Wl,-rpath-link,${PREFIX}/cuda-compat/"
elif [[ ${gpu_variant:-} = "none" ]]; then
    GGML_ARGS="${GGML_ARGS} -DGGML_CUDA=OFF"
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
    if [[ ${gpu_variant:-} = "none" ]]; then
        # GGML_METAL is on by default on osx, but it requires macOS v12.3,
        # so to support earlier macOS versions we provide the non-metal variant
        GGML_ARGS="${GGML_ARGS} -DGGML_METAL=OFF"
    elif [[ ${gpu_variant:-} = "metal" ]]; then
        # GGML_METAL as a shared library requires xcode 
        # to run metal and metallib commands to compile Metal kernels
        GGML_ARGS="${GGML_ARGS} -DGGML_METAL=ON"
        GGML_ARGS="${GGML_ARGS} -DGGML_METAL_EMBED_LIBRARY=ON"
        # TODO look into GGML_METAL_MACOSX_VERSION_MIN and GGML_METAL_STD
    fi
fi

# TODO: implement test that detects whether the correct BLAS is actually used
if [[ ${blas_impl:-} = "accelerate" ]]; then
    GGML_ARGS="${GGML_ARGS} -DGGML_BLAS=ON"
    GGML_ARGS="${GGML_ARGS} -DGGML_ACCELERATE=ON"
    GGML_ARGS="${GGML_ARGS} -DGGML_BLAS_VENDOR=Apple"
elif [[ ${blas_impl:-} = "mkl" ]]; then
    GGML_ARGS="${GGML_ARGS} -DGGML_BLAS=ON"
    GGML_ARGS="${GGML_ARGS} -DGGML_ACCELERATE=OFF"
    GGML_ARGS="${GGML_ARGS} -DGGML_BLAS_VENDOR=Intel10_64_dyn"
elif [[ ${blas_impl:-} = "openblas" ]]; then
    GGML_ARGS="${GGML_ARGS} -DGGML_BLAS=ON"
    GGML_ARGS="${GGML_ARGS} -DGGML_ACCELERATE=OFF"
    GGML_ARGS="${GGML_ARGS} -DGGML_BLAS_VENDOR=OpenBLAS"
else
    GGML_ARGS="${GGML_ARGS} -DGGML_BLAS=OFF"
fi

# LLAMA build options
LLAMA_ARGS="-DLLAMA_BUILD_NUMBER=${LLAMA_BUILD_NUMBER} -DLLAMA_BUILD_COMMIT=${LLAMA_BUILD_COMMIT}"
LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_CURL=ON"
LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BUILD_SERVER=ON"
LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BUILD_TOOLS=ON"
LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BUILD_TESTS=ON"
LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BUILD_EXAMPLES=OFF"
# TODO add LLAMA_LLGUIDANCE? 
# TODO set LLAMA_USE_SYSTEM_GGML once ggml gets its own feedstock

cmake -S . -B build \
    -G Ninja \
    ${CMAKE_ARGS} \
    -DCMAKE_INSTALL_PREFIX=${PREFIX} \
    -DCMAKE_PREFIX_PATH=${PREFIX} \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON  \
    ${GGML_ARGS} \
    ${LLAMA_ARGS}

cmake --build build --config Release --verbose
cmake --install build
 
# Tests like test_chat use relative paths to load the model template files that break when run from a different 
# parent directory. Tests (per upstream CI workflows) should be run from the build directory.
# See: https://github.com/ggerganov/llama.cpp/blob/master/.github/workflows/build.yml

pushd build
# test-tokenizers-ggml-vocabs requires git-lfs to download the model files
# Skip test-backend-ops on Metal and CUDA (has test failures in b6188)
if [[ "${gpu_variant}" == "metal" ]] || [[ "${gpu_variant}" == "cuda-12" ]]; then
    ctest -L main -C Release --output-on-failure -j${CPU_COUNT} --timeout 900 -E "(test-tokenizers-ggml-vocabs|test-backend-ops)"
else
    ctest -L main -C Release --output-on-failure -j${CPU_COUNT} --timeout 900 -E "(test-tokenizers-ggml-vocabs)"
fi
popd

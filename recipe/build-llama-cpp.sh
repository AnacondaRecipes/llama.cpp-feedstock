#!/bin/bash
set -ex

# workaround to get PBP to see that OSX_SDK_DIR is used
# and thus get it forwarded to the build
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo $OSX_SDK_DIR
fi

# GGML build options
GGML_ARGS="-DGGML_NATIVE=OFF -DGGML_CPU_ALL_VARIANTS=ON -DGGML_BACKEND_DL=ON"

if [[ ${gpu_variant:0:5} = "cuda-" ]]; then
    # Exclude Blackwell (sm_120) - MXFP4 instructions require CUDA 13.0+
    # Support: Maxwell(50), Pascal(60), Volta(70), Turing(75), Ampere(80,86), Ada(89), Hopper(90)
    CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_CUDA_ARCHITECTURES=50;60;70;75;80;86;89;90"
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
if [[ "$PKG_NAME" == "libllama" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BUILD_SERVER=OFF"
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BUILD_TOOLS=OFF"
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BUILD_TESTS=OFF"
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BUILD_EXAMPLES=OFF"
elif [[ "$PKG_NAME" == "llama.cpp" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BUILD_SERVER=ON"
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BUILD_TOOLS=ON"
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BUILD_TESTS=OFF"
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BUILD_EXAMPLES=OFF"
elif [[ "$PKG_NAME" == "llama.cpp-tests" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BUILD_SERVER=OFF"
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BUILD_TOOLS=OFF"
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BUILD_TESTS=ON"
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BUILD_EXAMPLES=OFF"
else
    echo "Invalid package name: $PKG_NAME"
    exit 1
fi
# TODO add LLAMA_LLGUIDANCE? 
# TODO set LLAMA_USE_SYSTEM_GGML once ggml gets its own feedstock

cmake -S . -B build_${gpu_variant} \
    -G Ninja \
    ${CMAKE_ARGS} \
    -DCMAKE_INSTALL_PREFIX=${PREFIX} \
    -DCMAKE_PREFIX_PATH=${PREFIX} \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON  \
    ${GGML_ARGS} \
    ${LLAMA_ARGS}

cmake --build build_${gpu_variant} --config Release --verbose
cmake --install build_${gpu_variant}
 
if [[ "$PKG_NAME" == "llama.cpp-tests" ]]; then
    # Tests like test_chat use relative paths to load the model template files that break when run from a different 
    # parent directory. Tests (per upstream CI workflows) should be run from the build directory.
    # See: https://github.com/ggerganov/llama.cpp/blob/master/.github/workflows/build.yml

    pushd build_${gpu_variant}
    # test-tokenizers-ggml-vocabs requires git-lfs to download the model files

    if [[ ${gpu_variant:-} = "metal" ]]; then
        # Skip Metal-specific failing tests:
        # test-tokenizers-ggml-vocabs: Known test data issue (#10290)
        # test-thread-safety: crashes with "Subprocess aborted" (investigating)
        ctest -L main -C Release --output-on-failure -j${CPU_COUNT} --timeout 900 -E "(test-tokenizers-ggml-vocabs|test-thread-safety)"
    elif [[ ${gpu_variant:0:5} = "cuda-" ]]; then
        # Check GPU compute capability - skip test-backend-ops on older GPUs (<=7.5)
        # T4 (SM 7.5) has limited shared memory causing Flash Attention crashes
        COMPUTE_CAP=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '.')
        if [[ -n "$COMPUTE_CAP" ]] && [[ "$COMPUTE_CAP" -le 75 ]]; then
            echo "GPU compute capability <= 7.5 detected, skipping test-backend-ops (shared memory limits)"
            ctest -L main -C Release --output-on-failure -j${CPU_COUNT} --timeout 900 -E "(test-tokenizers-ggml-vocabs|test-backend-ops)"
        else
            ctest -L main -C Release --output-on-failure -j${CPU_COUNT} --timeout 900 -E "(test-tokenizers-ggml-vocabs)"
        fi
    else
        # Skip test-tokenizers-ggml-vocabs on all platforms: Requires git-lfs to download model files
        ctest -L main -C Release --output-on-failure -j${CPU_COUNT} --timeout 900 -E "(test-tokenizers-ggml-vocabs)"
    fi
    popd
fi

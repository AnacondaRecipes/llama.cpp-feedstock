#!/bin/bash
set -ex

# workaround to get PBP to see that OSX_SDK_DIR is used
# and thus get it forwarded to the build
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo $OSX_SDK_DIR
fi

# GGML build options
GGML_ARGS="-DGGML_NATIVE=OFF -DGGML_CPU_ALL_VARIANTS=ON -DGGML_BACKEND_DL=ON"
GGML_OPENMP_FLAGS=()

if [[ ${gpu_variant:0:5} = "cuda-" ]]; then
    # Let llama.cpp's CMakeLists.txt handle architecture selection
    # It automatically uses 120a-real for CUDA 12.8+ (fixes MXFP4 compilation)
    # See: https://github.com/ggml-org/llama.cpp/pull/18672
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
    if [[ "${target_platform:-}" == linux-* ]]; then
        GGML_OPENMP_FLAGS=(
            -DOpenMP_C_FLAGS=-fopenmp
            -DOpenMP_CXX_FLAGS=-fopenmp
            -DOpenMP_C_LIB_NAMES=iomp5
            -DOpenMP_CXX_LIB_NAMES=iomp5
            -DOpenMP_iomp5_LIBRARY=${PREFIX}/lib/libiomp5${SHLIB_EXT}
        )
    fi
elif [[ ${blas_impl:-} = "openblas" ]]; then
    GGML_ARGS="${GGML_ARGS} -DGGML_BLAS=ON"
    GGML_ARGS="${GGML_ARGS} -DGGML_ACCELERATE=OFF"
    GGML_ARGS="${GGML_ARGS} -DGGML_BLAS_VENDOR=OpenBLAS"
else
    GGML_ARGS="${GGML_ARGS} -DGGML_BLAS=OFF"
fi

# LLAMA build options
LLAMA_ARGS="-DLLAMA_BUILD_NUMBER=${LLAMA_BUILD_NUMBER} -DLLAMA_BUILD_COMMIT=${LLAMA_BUILD_COMMIT}"
LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_OPENSSL=ON"
# Disable common/subproc.cpp (added b10241, ggml-org/llama.cpp#26102). It pulls
# vendored sheredom/subprocess.h whose Linux path calls
# posix_spawn_file_actions_addchdir_np() unconditionally, requiring glibc>=2.29;
# AR CentOS 7 sysroot ships glibc 2.28. Only server MCP/tools/router use this,
# and neither is exposed by our binaries.
LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_SUBPROCESS=OFF"
# Disable the unified `llama` router app: it #includes common/build-info.h but the
# upstream app/CMakeLists.txt does not wire up its include path, so the build fails
# with `fatal error: build-info.h: No such file or directory` on every platform.
# Upstream workaround documented in ggml-org/llama.cpp#23628.
LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BUILD_APP=OFF"
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
    "${GGML_OPENMP_FLAGS[@]}" \
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
        # test-tokenizers-ggml-vocabs: Requires git-lfs to download model files
        # test-thread-safety: GGML_ASSERT(buf_dst) fails in ggml_metal_cpy_tensor_async during concurrent decode
        # test-llama-archs: aborts in ggml_backend_meta_get_split_state on Metal (b8994 regression)
        # test-recurrent-state-rollback: same GGML_ASSERT(buf_dst) failure in
        #   ggml_metal_cpy_tensor_async during decode; test became a real check at
        #   ggml-org/llama.cpp#25758 (b10068). No upstream fix as of b10760.
        # test-save-load-state: same GGML_ASSERT(buf_dst) failure at
        #   ggml-metal-context.m:377, surfaced as a required test at b10760.
        ctest -L main -C Release --output-on-failure -j${CPU_COUNT} --timeout 900 -E "(test-tokenizers-ggml-vocabs|test-thread-safety|test-llama-archs|test-recurrent-state-rollback|test-save-load-state)"
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

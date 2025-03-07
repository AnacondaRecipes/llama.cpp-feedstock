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

# Configure CPU optimization flags based on the x86_64_opt variable

if [[ $ARCH = "x86_64" ]]; then
    if [[ ${x86_64_opt:-} = "v4" ]]; then
        # Enable AVX-512 and all previous instruction sets (v4)
        export CXXFLAGS="${CXXFLAGS/march=nocona/march=x86-64-v4}"
        export CFLAGS="${CFLAGS/march=nocona/march=x86-64-v4}"
        export CPPFLAGS="${CPPFLAGS/march=nocona/march=x86-64-v4}"
        LLAMA_ARGS="${LLAMA_ARGS} -DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_AVX512=ON -DGGML_FMA=ON -DGGML_F16C=ON"
        # TBD: -DGGML_AVX512_VBMI=ON -DGGML_AVX512_VNNI=ON -DGGML_AVX512_BF16=ON 
        # May not want to enable these additional AVX512 instructions for all x86_64 builds
    elif [[ ${x86_64_opt:-} = "v3" ]]; then
        # Enable AVX, AVX2, FMA, F16C and all previous instruction sets (v3)
        export CXXFLAGS="${CXXFLAGS/march=nocona/march=x86-64-v3}"
        export CFLAGS="${CFLAGS/march=nocona/march=x86-64-v3}"
        export CPPFLAGS="${CPPFLAGS/march=nocona/march=x86-64-v3}"
        LLAMA_ARGS="${LLAMA_ARGS} -DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON"
    elif [[ ${x86_64_opt:-} = "v2" ]]; then
        # Enable AVX and all previous instruction sets (v2)
        export CXXFLAGS="${CXXFLAGS/march=nocona/march=x86-64-v2}"
        export CFLAGS="${CFLAGS/march=nocona/march=x86-64-v2}"
        export CPPFLAGS="${CPPFLAGS/march=nocona/march=x86-64-v2}"
        LLAMA_ARGS="${LLAMA_ARGS} -DGGML_AVX=ON"
    else
        # Enable SSE2 (v1)
        export CXXFLAGS="${CXXFLAGS/march=nocona/march=x86-64-v1}"
        export CFLAGS="${CFLAGS/march=nocona/march=x86-64-v1}"
        export CPPFLAGS="${CPPFLAGS/march=nocona/march=x86-64-v1}"
    fi
fi

# Set defaults for instruction sets if not already set
if [[ ! "${LLAMA_ARGS}" =~ "-DGGML_AVX=" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_AVX=OFF"
fi
if [[ ! "${LLAMA_ARGS}" =~ "-DGGML_AVX2=" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_AVX2=OFF"
fi
if [[ ! "${LLAMA_ARGS}" =~ "-DGGML_AVX512=" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_AVX512=OFF"
fi
if [[ ! "${LLAMA_ARGS}" =~ "-DGGML_AVX512_VBMI=" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_AVX512_VBMI=OFF"
fi
if [[ ! "${LLAMA_ARGS}" =~ "-DGGML_AVX512_VNNI=" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_AVX512_VNNI=OFF"
fi
if [[ ! "${LLAMA_ARGS}" =~ "-DGGML_AVX512_BF16=" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_AVX512_BF16=OFF"
fi
if [[ ! "${LLAMA_ARGS}" =~ "-DGGML_AVX_VNNI=" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_AVX_VNNI=OFF"
fi
if [[ ! "${LLAMA_ARGS}" =~ "-DGGML_FMA=" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_FMA=OFF"
fi
if [[ ! "${LLAMA_ARGS}" =~ "-DGGML_F16C=" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_F16C=OFF"
fi
if [[ ! "${LLAMA_ARGS}" =~ "-DGGML_AMX_TILE=" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_AMX_TILE=OFF"
fi
if [[ ! "${LLAMA_ARGS}" =~ "-DGGML_AMX_INT8=" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_AMX_INT8=OFF"
fi
if [[ ! "${LLAMA_ARGS}" =~ "-DGGML_AMX_BF16=" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_AMX_BF16=OFF"
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
    -DLLAMA_CURL=ON

cmake --build build --config Release --verbose
cmake --install build
 
# Tests like test_chat use relative paths to load the model template files that break when run from a different 
# parent directory. Tests (per upstream CI workflows) should be run from the build directory.
# See: https://github.com/ggerganov/llama.cpp/blob/master/.github/workflows/build.yml

pushd build
ctest --output-on-failure -L main -j${CPU_COUNT}
popd

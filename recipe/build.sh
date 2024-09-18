#!/bin/bash
set -ex

if [[ ${gpu_variant:0:5} = "cuda-" ]]; then
    CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_CUDA_ARCHITECTURES=all"
    LLAMA_ARGS="${LLAMA_ARGS} -DGGML_CUDA=ON"
    if [[ ${gpu_variant:-} = "cuda-11" ]]; then
        export CUDACXX=/usr/local/cuda/bin/nvcc
        export CUDAHOSTCXX="${CXX}"
    else
        # cuda-compat provided libcuda.so.1
        LDFLAGS="$LDFLAGS -Wl,-rpath-link,${PREFIX}/cuda-compat/"
    fi
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

if [[ ${x86_64_opt:-} = "v3" ]]; then
    export CXXFLAGS="${CXXFLAGS/march=nocona/march=x86-64-v3}"
    export CFLAGS="${CFLAGS/march=nocona/march=x86-64-v3}"
    export CPPFLAGS="${CPPFLAGS/march=nocona/march=x86-64-v3}"
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
    -DGGML_AVX=OFF \
    -DGGML_AVX2=OFF \
    -DGGML_AVX512=OFF \
    -DGGML_AVX512_VBMI=OFF \
    -DGGML_AVX512_VNNI=OFF \
    -DGGML_FMA=OFF \
    -DGGML_F16C=OFF

cmake --build build --config Release --verbose
cmake --install build
pushd build/tests
if [[ ${gpu_variant:0:5} = "cuda-" ]]; then
    # Tests failures around batch matrix multiplication (ggml_mul_mat) due to our hardware (Maxwell) not supporting 
    # f16 CUDA intrinsics (available from 60 - Pascal), and us compiling with CUDA architectures all.
    # See https://github.com/ggerganov/llama.cpp/blob/b2781/CMakeLists.txt#L439-L451
    # LLAMA_CUDA_F16 is optional, but the corresponding tests are not skipped by default.
    #   MUL_MAT(type_a=f16,type_b=f16,m=16,n=1,k=256,bs=[10,1],nr=[1,1]): [MUL_MAT] NMSE = 0.993871958 > 0.000500000 FAIL
    #   MUL_MAT(type_a=f16,type_b=f16,m=16,n=1,k=256,bs=[10,1],nr=[2,1]): [MUL_MAT] NMSE = 1.002262239 > 0.000500000 FAIL
    #   MUL_MAT(type_a=f16,type_b=f16,m=16,n=1,k=256,bs=[10,10],nr=[1,1]): [MUL_MAT] inf mismatch: CUDA0=-inf CPU=9.985199 FAIL
    #   MUL_MAT(type_a=f16,type_b=f16,m=16,n=1,k=256,bs=[10,10],nr=[2,1]): [MUL_MAT] inf mismatch: CUDA0=-inf CPU=-4.107816 FAIL
    #   MUL_MAT(type_a=f16,type_b=f16,m=16,n=16,k=256,bs=[10,1],nr=[1,1]): [MUL_MAT] NMSE = 1.002217055 > 0.000500000 FAIL
    #   MUL_MAT(type_a=f16,type_b=f16,m=16,n=16,k=256,bs=[10,1],nr=[2,1]): [MUL_MAT] NMSE = 1.001445591 > 0.000500000 FAIL
    #   MUL_MAT(type_a=f16,type_b=f16,m=16,n=16,k=256,bs=[10,10],nr=[1,1]): [MUL_MAT] NMSE = 1.000128216 > 0.000500000 FAIL
    #   MUL_MAT(type_a=f16,type_b=f16,m=16,n=16,k=256,bs=[10,10],nr=[2,1]): [MUL_MAT] NMSE = 1.000069965 > 0.000500000 FAIL
    ctest --output-on-failure build -j${CPU_COUNT} || true
else
    ctest --output-on-failure build -j${CPU_COUNT}
fi
popd
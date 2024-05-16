#!/bin/bash
set -ex

if [[ ${gpu_variant:0:5} = "cuda-" ]]; then
    CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_CUDA_ARCHITECTURES=all"
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_CUDA=ON"
    if [[ ${gpu_variant:-} = "cuda-11" ]]; then
        export CUDACXX=/usr/local/cuda/bin/nvcc
        export CUDAHOSTCXX="${CXX}"
    fi
elif [[ ${gpu_variant:-} = "none" ]]; then
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_CUDA=OFF"
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
    if [[ ${gpu_variant:-} = "none" ]]; then
        # LLAMA_METAL is on by default on osx, but it requires macOS v12.3,
        # so to support earlier macOS versions we provide the non-metal variant
        LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_METAL=OFF"
    elif [[ ${gpu_variant:-} = "metal" ]]; then
        # LLAMA_METAL as a shared library requires xcode 
        # to run metal and metallib commands to compile Metal kernels
        LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_METAL=ON"
        LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_METAL_EMBED_LIBRARY=ON"
    fi
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
else
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_BLAS=OFF"
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
if [[ ${gpu_variant:0:5} = "cuda-" ]]; then
    # Tests failures around batch matrix multiplication (ggml_mul_mat) due to our hardware (Maxwell) not supporting 
    # f16 CUDA intrinsics (available from 60 - Pascal), and us compiling with CUDA architectures all.
    # See https://github.com/ggerganov/llama.cpp/blob/b2781/CMakeLists.txt#L439-L451
    # LLAMA_CUDA_F16 is optional, but the corresponding tests are not skipped by default.
    #   MUL_MAT(type_a=f16,type_b=f16,m=16,n=1,k=256,bs=[10,1],nr=[1,1]): [MUL_MAT] NMSE = 0.995356906 > 0.0005000
    # 00 FAIL
    #   MUL_MAT(type_a=f16,type_b=f16,m=16,n=1,k=256,bs=[10,1],nr=[2,1]): [MUL_MAT] NMSE = 0.999567945 > 0.0005000
    # 00 FAIL
    #   MUL_MAT(type_a=f16,type_b=f16,m=16,n=1,k=256,bs=[10,10],nr=[1,1]): [MUL_MAT] inf mismatch: CUDA0=-inf CPU=
    # 3.371366 FAIL
    #   MUL_MAT(type_a=f16,type_b=f16,m=16,n=1,k=256,bs=[10,10],nr=[2,1]): [MUL_MAT] inf mismatch: CUDA0=-inf CPU=
    # 6.707091 FAIL
    #   MUL_MAT(type_a=f16,type_b=f16,m=16,n=1,k=256,bs=[10,10],nr=[1,2]): not supported [CUDA0]
    #   MUL_MAT(type_a=f16,type_b=f16,m=16,n=1,k=256,bs=[10,10],nr=[2,2]): not supported [CUDA0]
    #   MUL_MAT(type_a=f16,type_b=f16,m=16,n=16,k=256,bs=[1,1],nr=[1,1]): OK
    #   MUL_MAT(type_a=f16,type_b=f16,m=16,n=16,k=256,bs=[10,1],nr=[1,1]): [MUL_MAT] NMSE = 1.002334163 > 0.000500
    # 000 FAIL
    #   MUL_MAT(type_a=f16,type_b=f16,m=16,n=16,k=256,bs=[10,1],nr=[2,1]): [MUL_MAT] NMSE = 1.000352589 > 0.000500
    # 000 FAIL
    #   MUL_MAT(type_a=f16,type_b=f16,m=16,n=16,k=256,bs=[10,10],nr=[1,1]): [MUL_MAT] NMSE = 1.000091733 > 0.00050
    # 0000 FAIL
    #   MUL_MAT(type_a=f16,type_b=f16,m=16,n=16,k=256,bs=[10,10],nr=[2,1]): [MUL_MAT] NMSE = 1.000184368 > 0.00050
    # 0000 FAIL
    ctest --output-on-failure build -j${CPU_COUNT} || true
else
    ctest --output-on-failure build -j${CPU_COUNT}
fi
popd
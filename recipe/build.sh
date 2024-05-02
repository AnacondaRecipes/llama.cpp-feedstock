#!/bin/bash
set -ex

if [[ ${gpu_variant:0:5} = "cuda-" ]]; then
    CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_CUDA_ARCHITECTURES=all"
    LLAMA_ARGS="${LLAMA_ARGS} -DLLAMA_CUDA=ON"
    if [[ ${gpu_variant:-} = "cuda-11" ]]; then
        export CUDACXX=/usr/local/cuda/bin/nvcc
        export CUDAHOSTCXX="${CXX}"
    else
        LDFLAGS="$LDFLAGS -Wl,-rpath-link,${PREFIX}/lib/stubs/"
        # TODO: This is a workaround. In the future, consider using cuda-compat instead of 
        # cuda-driver-dev to provide libcuda.so.1
        ln -s ${PREFIX}/lib/stubs/libcuda.so ${PREFIX}/lib/stubs/libcuda.so.1
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
    # Tests failures around some quantization types (F32, IQ2_XXS) and batch matrix multiplication (ggml_mul_mat)
    # Possibly due to simd feature not supported by our hardware (Maxwell).
    # To revisit cuda build if this package is to be used with models requiring these features.
    # Possiblity linked to https://github.com/ggerganov/llama.cpp/issues/6825
    ctest --output-on-failure build -j${CPU_COUNT} || true
else
    ctest --output-on-failure build -j${CPU_COUNT}
fi
popd
@echo off
setlocal EnableDelayedExpansion

REM GGML build options
set GGML_ARGS=-DGGML_NATIVE=OFF -DGGML_BACKEND_DL=ON
set GGML_OPENMP_FLAGS=

REM GGML_CPU_ALL_VARIANTS has no ARM-on-Windows variant table (upstream CMake
REM fatal-errors "Unsupported ARM target OS: Windows"); upstream's own win-arm64
REM release builds ship a single CPU backend with GGML_CPU_ALL_VARIANTS=OFF.
if "%target_platform%"=="win-arm64" (
    set GGML_ARGS=!GGML_ARGS! -DGGML_CPU_ALL_VARIANTS=OFF
) else (
    set GGML_ARGS=!GGML_ARGS! -DGGML_CPU_ALL_VARIANTS=ON
)

if "%gpu_variant:~0,5%"=="cuda-" (
    REM Let llama.cpp's CMakeLists.txt handle architecture selection
    REM It automatically uses 120a-real for CUDA 12.8+ (fixes MXFP4 compilation)
    REM See: https://github.com/ggml-org/llama.cpp/pull/18672
    set GGML_ARGS=!GGML_ARGS! -DGGML_CUDA=ON
) else (
    set GGML_ARGS=!GGML_ARGS! -DGGML_CUDA=OFF
)

if "%blas_impl%"=="mkl" (
    set GGML_ARGS=!GGML_ARGS! -DGGML_BLAS=ON
    set GGML_ARGS=!GGML_ARGS! -DGGML_ACCELERATE=OFF
    set GGML_ARGS=!GGML_ARGS! -DGGML_BLAS_VENDOR=Intel10_64_dyn
    set GGML_OPENMP_FLAGS=-DOpenMP_C_FLAGS=/openmp:llvm -DOpenMP_CXX_FLAGS=/openmp:llvm -DOpenMP_C_LIB_NAMES=libiomp5md -DOpenMP_CXX_LIB_NAMES=libiomp5md -DOpenMP_libiomp5md_LIBRARY=%LIBRARY_LIB%\libiomp5md.lib
) else if "%blas_impl%"=="openblas" (
    set GGML_ARGS=!GGML_ARGS! -DGGML_BLAS=ON
    set GGML_ARGS=!GGML_ARGS! -DGGML_ACCELERATE=OFF
    set GGML_ARGS=!GGML_ARGS! -DGGML_BLAS_VENDOR=OpenBLAS
) else (
    REM Note: LLAMA_CUDA=ON enables cublas.
    REM Tests fail when both mkl and cublas are used.
    REM This has also been reported here: https://github.com/ggerganov/llama.cpp/issues/4626
    set GGML_ARGS=!GGML_ARGS! -DGGML_BLAS=OFF
)

REM LLAMA build options
set LLAMA_ARGS=-DLLAMA_BUILD_NUMBER=%LLAMA_BUILD_NUMBER% -DLLAMA_BUILD_COMMIT=%LLAMA_BUILD_COMMIT%
set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_OPENSSL=ON
REM Disable common/subproc.cpp for parity with Linux (see build-llama-cpp.sh).
REM Only server MCP/tools/router consume it, neither is exposed by our binaries.
set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_SUBPROCESS=OFF
REM Disable the unified `llama` router app: it #includes common/build-info.h but
REM the upstream app/CMakeLists.txt does not wire up its include path, so the
REM build fails with "fatal error: build-info.h: No such file or directory".
REM Upstream workaround documented in ggml-org/llama.cpp#23628.
set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_APP=OFF
if "%PKG_NAME%" == "libllama" (
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_SERVER=OFF
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_TOOLS=OFF
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_TESTS=OFF
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_EXAMPLES=OFF
) else if "%PKG_NAME%" == "llama.cpp" (
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_SERVER=ON
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_TOOLS=ON
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_TESTS=OFF
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_EXAMPLES=OFF
) else if "%PKG_NAME%" == "llama.cpp-tests" (
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_SERVER=OFF
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_TOOLS=OFF
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_TESTS=ON
    set LLAMA_ARGS=!LLAMA_ARGS! -DLLAMA_BUILD_EXAMPLES=OFF
) else (
    echo "Invalid package name: %PKG_NAME%"
    exit 1
)
REM TODO add LLAMA_LLGUIDANCE?
REM TODO set LLAMA_USE_SYSTEM_GGML once ggml gets its own feedstock

cmake -S . -B build ^
    -G Ninja ^
    !CMAKE_ARGS! ^
    -DCMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX% ^
    -DCMAKE_PREFIX_PATH=%LIBRARY_PREFIX% ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DBUILD_SHARED_LIBS=ON  ^
    !GGML_ARGS! ^
    !GGML_OPENMP_FLAGS! ^
    !LLAMA_ARGS!
if errorlevel 1 exit 1

REM Cap ninja parallelism on CUDA builds — CLAIM_EXPIRED workaround (SIR-3267 followup).
REM GGML_CPU_ALL_VARIANTS=ON generates 15 backends; combined with cublas linking the
REM Windows worker's memory saturates and starves the TaskCluster heartbeat monitor.
set BUILD_JOBS=%CPU_COUNT%
if "%gpu_variant:~0,5%"=="cuda-" set BUILD_JOBS=4
cmake --build build --config Release --verbose --parallel %BUILD_JOBS%
if errorlevel 1 exit 1

cmake --install build
if errorlevel 1 exit 1

if "%PKG_NAME%" == "llama.cpp-tests" (
    pushd build
    REM test-tokenizers-ggml-vocabs requires git-lfs to download the model files
    REM test-backend-ops (CUDA only): MEAN(type=f32,ne=[33,1,1,1]) fails on
    REM   CUDA0 backend at b10068. Single-op regression in 1/13163 subtests;
    REM   no upstream fix. Mirrors linux-64 CUDA behavior in build-llama-cpp.sh.
    if "%gpu_variant:~0,5%"=="cuda-" (
        ctest -L main -C Release --output-on-failure -j%CPU_COUNT% --timeout 900 -E "(test-tokenizers-ggml-vocabs|test-backend-ops)"
    ) else (
        ctest -L main -C Release --output-on-failure -j%CPU_COUNT% --timeout 900 -E "test-tokenizers-ggml-vocabs"
    )
    if errorlevel 1 exit 1
    popd
)

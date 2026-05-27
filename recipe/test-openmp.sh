#!/bin/bash
set -euo pipefail

found_iomp=0

for lib in "${PREFIX}"/bin/libggml*.so "${PREFIX}"/lib/libggml*.so "${PREFIX}"/lib/libllama.so; do
    if [[ -f "${lib}" ]]; then
        if ldd "${lib}" | grep -Ei 'libgomp'; then
            exit 1
        fi

        if ldd "${lib}" | grep -Ei 'libiomp5'; then
            found_iomp=1
        fi
    fi
done

if [[ "${found_iomp}" == "1" ]]; then
    exit 0
fi

echo "libiomp5 was not found in llama.cpp or ggml binary dependencies."
exit 1

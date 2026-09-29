/* Library callers must find ggml's dynamic backends from any executable
 * location / cwd, not only from $PREFIX/bin (ggml's default search). */
#include <stdio.h>
#include <ggml-backend.h>

int main(void) {
    ggml_backend_load_all();
    size_t n = ggml_backend_dev_count();
    printf("ggml devices: %zu\n", n);
    for (size_t i = 0; i < n; i++) {
        printf("  %s\n", ggml_backend_dev_name(ggml_backend_dev_get(i)));
    }
    return n > 0 ? 0 : 1;
}

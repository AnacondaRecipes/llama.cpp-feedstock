/* Library callers must find ggml's dynamic backends from any executable
 * location / cwd, not only from $PREFIX/bin (ggml's default search).
 * Optional argv[1]: a device-name prefix (e.g. CUDA) that must be among them. */
#include <stdio.h>
#include <string.h>
#include <ggml-backend.h>

int main(int argc, char ** argv) {
    const char * required = argc > 1 ? argv[1] : NULL;
    int found = 0;
    ggml_backend_load_all();
    size_t n = ggml_backend_dev_count();
    printf("ggml devices: %zu\n", n);
    for (size_t i = 0; i < n; i++) {
        const char * name = ggml_backend_dev_name(ggml_backend_dev_get(i));
        printf("  %s\n", name);
        if (required && strncmp(name, required, strlen(required)) == 0) {
            found = 1;
        }
    }
    if (required && !found) {
        fprintf(stderr, "no %s device found\n", required);
        return 1;
    }
    return n > 0 ? 0 : 1;
}

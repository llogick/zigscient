#include <assert.h>

// TODO we would like to #include "mathtest.h" here but this feature has been disabled in
// the stage1 compiler. Users will have to wait until self-hosted is available for
// the "generate .h file" feature.

#include <stdint.h>
int32_t add(int32_t a, int32_t b);

#if _WIN32
#define IMPORT __declspec(dllimport)
#else
#define IMPORT
#endif

extern IMPORT int32_t exported_var;

int main(int argc, char **argv) {
    assert(add(42, 1337) == 1379);
    assert(exported_var == 9999);
    return 0;
}

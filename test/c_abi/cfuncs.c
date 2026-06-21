#include <complex.h>
#include <inttypes.h>
#include <stdalign.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

void zig_panic(void);

static void assert_or_panic(bool ok) {
    if (!ok) {
        zig_panic();
    }
}

#if defined(__mips64__)
#  define ZIG_MIPS64
#elif defined(__mips__)
#  define ZIG_MIPS32
#endif

#if defined(_ARCH_PPC64)
#  define ZIG_PPC64
#elif defined(__powerpc__)
#  define ZIG_PPC32
#endif

#ifdef __riscv
#  ifdef _ILP32
#    define ZIG_RISCV32
#  else
#    define ZIG_RISCV64
#  endif
#endif

#ifdef __i386__
#  define ZIG_NO_I128
#endif

#ifdef __arm__
#  define ZIG_NO_I128
#endif

#ifdef __hexagon__
#  define ZIG_NO_I128
#endif

#ifdef __mips__
#  define ZIG_NO_I128
#endif

#ifdef ZIG_PPC32
#  define ZIG_NO_I128
#endif

#ifdef ZIG_RISCV32
#  define ZIG_NO_I128
#endif

#ifdef __i386__
#  define ZIG_NO_COMPLEX
#endif

#ifdef __mips__
#  define ZIG_NO_COMPLEX
#endif

#ifdef __arm__
#  define ZIG_NO_COMPLEX
#endif

#ifdef __hexagon__
#  define ZIG_NO_COMPLEX
#endif

#if defined(__loongarch__) && defined(__loongarch_soft_float)
#  define ZIG_NO_COMPLEX
#endif

#ifdef ZIG_PPC32
#  define ZIG_NO_COMPLEX
#endif

#ifdef __riscv
#  define ZIG_NO_COMPLEX
#endif

#ifdef __s390x__
#  define ZIG_NO_COMPLEX
#endif

#ifdef __x86_64__
#define ZIG_NO_RAW_F16
#endif

#ifdef __i386__
#define ZIG_NO_RAW_F16
#endif

#ifdef __hexagon__
#define ZIG_NO_RAW_F16
#endif

#ifdef __loongarch__
#define ZIG_NO_RAW_F16
#endif

#ifdef __mips__
#define ZIG_NO_RAW_F16
#endif

#ifdef __riscv
#define ZIG_NO_RAW_F16
#endif

#ifdef __s390x__
#define ZIG_NO_RAW_F16
#endif

#ifdef __wasm__
#define ZIG_NO_RAW_F16
#endif

#ifdef __powerpc__
#define ZIG_NO_RAW_F16
#endif

#ifdef __aarch64__
#define ZIG_NO_F128
#endif

#ifdef __arm__
#define ZIG_NO_F128
#endif

#ifdef __hexagon__
#define ZIG_NO_F128
#endif

#ifdef __loongarch__
#define ZIG_NO_F128
#endif

#ifdef __mips__
#define ZIG_NO_F128
#endif

#ifdef __riscv
#define ZIG_NO_F128
#endif

#ifdef __powerpc__
#define ZIG_NO_F128
#endif

#ifdef __s390x__
#define ZIG_NO_F128
#endif

#ifdef __APPLE__
#define ZIG_NO_F128
#endif

#ifdef _MSC_VER
#define ZIG_NO_F128
#endif

#ifndef ZIG_NO_I128
struct i128 {
    __int128 value;
};

struct u128 {
    unsigned __int128 value;
};
#endif

void zig_u8(uint8_t);
void zig_u16(uint16_t);
void zig_u32(uint32_t);
void zig_u64(uint64_t);
#ifndef ZIG_NO_I128
void zig_struct_u128(struct u128);
#endif
void zig_i8(int8_t);
void zig_i16(int16_t);
void zig_i32(int32_t);
void zig_i64(int64_t);
#ifndef ZIG_NO_I128
void zig_struct_i128(struct i128);
#endif
void zig_five_integers(int32_t, int32_t, int32_t, int32_t, int32_t);

void zig_f32(float);
void zig_f64(double);
void zig_longdouble(long double);
void zig_five_floats(float, float, float, float, float);

bool zig_ret_bool();
uint8_t zig_ret_u8();
uint16_t zig_ret_u16();
uint32_t zig_ret_u32();
uint64_t zig_ret_u64();
int8_t zig_ret_i8();
int16_t zig_ret_i16();
int32_t zig_ret_i32();
int64_t zig_ret_i64();

void zig_ptr(void *);

void zig_bool(bool);

#ifndef ZIG_NO_COMPLEX
// Note: These two functions match the signature of __mulsc3 and __muldc3 in compiler-rt (and libgcc)
float complex zig_cmultf_comp(float a_r, float a_i, float b_r, float b_i);
double complex zig_cmultd_comp(double a_r, double a_i, double b_r, double b_i);

float complex zig_cmultf(float complex a, float complex b);
double complex zig_cmultd(double complex a, double complex b);
#endif

#if defined(ZIG_BACKEND_STAGE2_X86_64) || defined(ZIG_PPC32) || defined(__wasm__)

typedef bool Vector_2_bool __attribute__((ext_vector_type(2)));

Vector_2_bool zig_ret_vector_2_bool(void);
void zig_vector_2_bool(Vector_2_bool vec);

Vector_2_bool c_ret_vector_2_bool(void) {
    return (Vector_2_bool){
        true,
        false,
    };
}
void c_vector_2_bool(Vector_2_bool vec) {
    assert_or_panic(vec[0] == true);
    assert_or_panic(vec[1] == true);
}
void c_test_vector_2_bool(void) {
    Vector_2_bool vec = zig_ret_vector_2_bool();
    assert_or_panic(vec[0] == false);
    assert_or_panic(vec[1] == false);
    zig_vector_2_bool((Vector_2_bool){
        false,
        true,
    });
}

typedef bool Vector_4_bool __attribute__((ext_vector_type(4)));

Vector_4_bool zig_ret_vector_4_bool(void);
void zig_vector_4_bool(Vector_4_bool vec);

Vector_4_bool c_ret_vector_4_bool(void) {
    return (Vector_4_bool){
        true,
        false,
        true,
        false,
    };
}
void c_vector_4_bool(Vector_4_bool vec) {
    assert_or_panic(vec[0] == true);
    assert_or_panic(vec[1] == true);
    assert_or_panic(vec[2] == false);
    assert_or_panic(vec[3] == true);
}
void c_test_vector_4_bool(void) {
    Vector_4_bool vec = zig_ret_vector_4_bool();
    assert_or_panic(vec[0] == false);
    assert_or_panic(vec[1] == true);
    assert_or_panic(vec[2] == true);
    assert_or_panic(vec[3] == true);
    zig_vector_4_bool((Vector_4_bool){
        false,
        false,
        false,
        false,
    });
}

typedef bool Vector_8_bool __attribute__((ext_vector_type(8)));

Vector_8_bool zig_ret_vector_8_bool(void);
void zig_vector_8_bool(Vector_8_bool vec);

Vector_8_bool c_ret_vector_8_bool(void) {
    return (Vector_8_bool){
        false,
        true,
        false,
        false,
        true,
        false,
        false,
        true,
    };
}
void c_vector_8_bool(Vector_8_bool vec) {
    assert_or_panic(vec[0] == true);
    assert_or_panic(vec[1] == false);
    assert_or_panic(vec[2] == true);
    assert_or_panic(vec[3] == true);
    assert_or_panic(vec[4] == true);
    assert_or_panic(vec[5] == true);
    assert_or_panic(vec[6] == false);
    assert_or_panic(vec[7] == true);
}
void c_test_vector_8_bool(void) {
    Vector_8_bool vec = zig_ret_vector_8_bool();
    assert_or_panic(vec[0] == false);
    assert_or_panic(vec[1] == false);
    assert_or_panic(vec[2] == false);
    assert_or_panic(vec[3] == false);
    assert_or_panic(vec[4] == true);
    assert_or_panic(vec[5] == false);
    assert_or_panic(vec[6] == false);
    assert_or_panic(vec[7] == false);
    zig_vector_8_bool((Vector_8_bool){
        true,
        true,
        false,
        true,
        false,
        true,
        true,
        false,
    });
}

typedef bool Vector_16_bool __attribute__((ext_vector_type(16)));

Vector_16_bool zig_ret_vector_16_bool(void);
void zig_vector_16_bool(Vector_16_bool vec);

Vector_16_bool c_ret_vector_16_bool(void) {
    return (Vector_16_bool){
        true,
        true,
        false,
        false,
        false,
        false,
        true,
        false,
        true,
        false,
        false,
        true,
        true,
        false,
        true,
        true,
    };
}
void c_vector_16_bool(Vector_16_bool vec) {
    assert_or_panic(vec[0] == true);
    assert_or_panic(vec[1] == false);
    assert_or_panic(vec[2] == false);
    assert_or_panic(vec[3] == false);
    assert_or_panic(vec[4] == true);
    assert_or_panic(vec[5] == false);
    assert_or_panic(vec[6] == true);
    assert_or_panic(vec[7] == true);
    assert_or_panic(vec[8] == true);
    assert_or_panic(vec[9] == true);
    assert_or_panic(vec[10] == true);
    assert_or_panic(vec[11] == true);
    assert_or_panic(vec[12] == false);
    assert_or_panic(vec[13] == false);
    assert_or_panic(vec[14] == false);
    assert_or_panic(vec[15] == false);
}
void c_test_vector_16_bool(void) {
    Vector_16_bool vec = zig_ret_vector_16_bool();
    assert_or_panic(vec[0] == false);
    assert_or_panic(vec[1] == true);
    assert_or_panic(vec[2] == false);
    assert_or_panic(vec[3] == false);
    assert_or_panic(vec[4] == false);
    assert_or_panic(vec[5] == true);
    assert_or_panic(vec[6] == false);
    assert_or_panic(vec[7] == false);
    assert_or_panic(vec[8] == true);
    assert_or_panic(vec[9] == false);
    assert_or_panic(vec[10] == false);
    assert_or_panic(vec[11] == false);
    assert_or_panic(vec[12] == false);
    assert_or_panic(vec[13] == true);
    assert_or_panic(vec[14] == false);
    assert_or_panic(vec[15] == false);
    zig_vector_16_bool((Vector_16_bool){
        true,
        false,
        true,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        true,
    });
}

typedef bool Vector_32_bool __attribute__((ext_vector_type(32)));

Vector_32_bool zig_ret_vector_32_bool(void);
void zig_vector_32_bool(Vector_32_bool vec);

Vector_32_bool c_ret_vector_32_bool(void) {
    return (Vector_32_bool){
        true,
        false,
        true,
        true,
        true,
        false,
        true,
        false,
        true,
        true,
        true,
        false,
        true,
        true,
        false,
        false,
        true,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        false,
        true,
        false,
        false,
        true,
        false,
        false,
        false,
    };
}
void c_vector_32_bool(Vector_32_bool vec) {
    assert_or_panic(vec[0] == true);
    assert_or_panic(vec[1] == false);
    assert_or_panic(vec[2] == true);
    assert_or_panic(vec[3] == true);
    assert_or_panic(vec[4] == false);
    assert_or_panic(vec[5] == false);
    assert_or_panic(vec[6] == true);
    assert_or_panic(vec[7] == false);
    assert_or_panic(vec[8] == true);
    assert_or_panic(vec[9] == false);
    assert_or_panic(vec[10] == true);
    assert_or_panic(vec[11] == true);
    assert_or_panic(vec[12] == true);
    assert_or_panic(vec[13] == false);
    assert_or_panic(vec[14] == false);
    assert_or_panic(vec[15] == true);
    assert_or_panic(vec[16] == false);
    assert_or_panic(vec[17] == true);
    assert_or_panic(vec[18] == false);
    assert_or_panic(vec[19] == true);
    assert_or_panic(vec[20] == true);
    assert_or_panic(vec[21] == true);
    assert_or_panic(vec[22] == true);
    assert_or_panic(vec[23] == true);
    assert_or_panic(vec[24] == false);
    assert_or_panic(vec[25] == true);
    assert_or_panic(vec[26] == true);
    assert_or_panic(vec[27] == true);
    assert_or_panic(vec[28] == false);
    assert_or_panic(vec[29] == true);
    assert_or_panic(vec[30] == true);
    assert_or_panic(vec[31] == false);
}
void c_test_vector_32_bool(void) {
    Vector_32_bool vec = zig_ret_vector_32_bool();
    assert_or_panic(vec[0] == false);
    assert_or_panic(vec[1] == true);
    assert_or_panic(vec[2] == false);
    assert_or_panic(vec[3] == false);
    assert_or_panic(vec[4] == true);
    assert_or_panic(vec[5] == false);
    assert_or_panic(vec[6] == true);
    assert_or_panic(vec[7] == true);
    assert_or_panic(vec[8] == true);
    assert_or_panic(vec[9] == true);
    assert_or_panic(vec[10] == true);
    assert_or_panic(vec[11] == true);
    assert_or_panic(vec[12] == false);
    assert_or_panic(vec[13] == false);
    assert_or_panic(vec[14] == false);
    assert_or_panic(vec[15] == false);
    assert_or_panic(vec[16] == false);
    assert_or_panic(vec[17] == false);
    assert_or_panic(vec[18] == true);
    assert_or_panic(vec[19] == true);
    assert_or_panic(vec[20] == true);
    assert_or_panic(vec[21] == false);
    assert_or_panic(vec[22] == true);
    assert_or_panic(vec[23] == false);
    assert_or_panic(vec[24] == true);
    assert_or_panic(vec[25] == false);
    assert_or_panic(vec[26] == false);
    assert_or_panic(vec[27] == true);
    assert_or_panic(vec[28] == false);
    assert_or_panic(vec[29] == false);
    assert_or_panic(vec[30] == true);
    assert_or_panic(vec[31] == true);
    zig_vector_32_bool((Vector_32_bool){
        false,
        false,
        false,
        true,
        true,
        false,
        false,
        true,
        false,
        true,
        true,
        true,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        false,
        true,
        true,
        true,
        false,
        false,
        true,
        true,
        false,
        true,
        true,
        false,
        true,
    });
}

typedef bool Vector_64_bool __attribute__((ext_vector_type(64)));

Vector_64_bool zig_ret_vector_64_bool(void);
void zig_vector_64_bool(Vector_64_bool vec);

Vector_64_bool c_ret_vector_64_bool(void) {
    return (Vector_64_bool){
        false,
        true,
        false,
        true,
        true,
        true,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
        false,
        true,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        false,
        false,
        true,
        false,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
    };
}
void c_vector_64_bool(Vector_64_bool vec) {
    assert_or_panic(vec[0] == true);
    assert_or_panic(vec[1] == true);
    assert_or_panic(vec[2] == true);
    assert_or_panic(vec[3] == false);
    assert_or_panic(vec[4] == true);
    assert_or_panic(vec[5] == false);
    assert_or_panic(vec[6] == false);
    assert_or_panic(vec[7] == false);
    assert_or_panic(vec[8] == true);
    assert_or_panic(vec[9] == false);
    assert_or_panic(vec[10] == false);
    assert_or_panic(vec[11] == false);
    assert_or_panic(vec[12] == false);
    assert_or_panic(vec[13] == true);
    assert_or_panic(vec[14] == true);
    assert_or_panic(vec[15] == true);
    assert_or_panic(vec[16] == true);
    assert_or_panic(vec[17] == false);
    assert_or_panic(vec[18] == false);
    assert_or_panic(vec[19] == true);
    assert_or_panic(vec[20] == false);
    assert_or_panic(vec[21] == true);
    assert_or_panic(vec[22] == false);
    assert_or_panic(vec[23] == true);
    assert_or_panic(vec[24] == true);
    assert_or_panic(vec[25] == true);
    assert_or_panic(vec[26] == true);
    assert_or_panic(vec[27] == true);
    assert_or_panic(vec[28] == true);
    assert_or_panic(vec[29] == true);
    assert_or_panic(vec[30] == false);
    assert_or_panic(vec[31] == false);
    assert_or_panic(vec[32] == true);
    assert_or_panic(vec[33] == true);
    assert_or_panic(vec[34] == false);
    assert_or_panic(vec[35] == true);
    assert_or_panic(vec[36] == false);
    assert_or_panic(vec[37] == false);
    assert_or_panic(vec[38] == true);
    assert_or_panic(vec[39] == true);
    assert_or_panic(vec[40] == true);
    assert_or_panic(vec[41] == false);
    assert_or_panic(vec[42] == false);
    assert_or_panic(vec[43] == true);
    assert_or_panic(vec[44] == true);
    assert_or_panic(vec[45] == false);
    assert_or_panic(vec[46] == true);
    assert_or_panic(vec[47] == false);
    assert_or_panic(vec[48] == true);
    assert_or_panic(vec[49] == false);
    assert_or_panic(vec[50] == false);
    assert_or_panic(vec[51] == true);
    assert_or_panic(vec[52] == false);
    assert_or_panic(vec[53] == true);
    assert_or_panic(vec[54] == true);
    assert_or_panic(vec[55] == true);
    assert_or_panic(vec[56] == true);
    assert_or_panic(vec[57] == true);
    assert_or_panic(vec[58] == false);
    assert_or_panic(vec[59] == false);
    assert_or_panic(vec[60] == true);
    assert_or_panic(vec[61] == false);
    assert_or_panic(vec[62] == true);
    assert_or_panic(vec[63] == false);
}
void c_test_vector_64_bool(void) {
    Vector_64_bool vec = zig_ret_vector_64_bool();
    assert_or_panic(vec[0] == true);
    assert_or_panic(vec[1] == false);
    assert_or_panic(vec[2] == true);
    assert_or_panic(vec[3] == false);
    assert_or_panic(vec[4] == false);
    assert_or_panic(vec[5] == true);
    assert_or_panic(vec[6] == false);
    assert_or_panic(vec[7] == true);
    assert_or_panic(vec[8] == true);
    assert_or_panic(vec[9] == false);
    assert_or_panic(vec[10] == true);
    assert_or_panic(vec[11] == false);
    assert_or_panic(vec[12] == true);
    assert_or_panic(vec[13] == false);
    assert_or_panic(vec[14] == false);
    assert_or_panic(vec[15] == true);
    assert_or_panic(vec[16] == false);
    assert_or_panic(vec[17] == false);
    assert_or_panic(vec[18] == true);
    assert_or_panic(vec[19] == true);
    assert_or_panic(vec[20] == false);
    assert_or_panic(vec[21] == false);
    assert_or_panic(vec[22] == true);
    assert_or_panic(vec[23] == false);
    assert_or_panic(vec[24] == false);
    assert_or_panic(vec[25] == true);
    assert_or_panic(vec[26] == true);
    assert_or_panic(vec[27] == true);
    assert_or_panic(vec[28] == true);
    assert_or_panic(vec[29] == true);
    assert_or_panic(vec[30] == false);
    assert_or_panic(vec[31] == false);
    assert_or_panic(vec[32] == true);
    assert_or_panic(vec[33] == true);
    assert_or_panic(vec[34] == true);
    assert_or_panic(vec[35] == true);
    assert_or_panic(vec[36] == false);
    assert_or_panic(vec[37] == true);
    assert_or_panic(vec[38] == false);
    assert_or_panic(vec[39] == true);
    assert_or_panic(vec[40] == true);
    assert_or_panic(vec[41] == true);
    assert_or_panic(vec[42] == true);
    assert_or_panic(vec[43] == true);
    assert_or_panic(vec[44] == false);
    assert_or_panic(vec[45] == false);
    assert_or_panic(vec[46] == false);
    assert_or_panic(vec[47] == true);
    assert_or_panic(vec[48] == true);
    assert_or_panic(vec[49] == true);
    assert_or_panic(vec[50] == false);
    assert_or_panic(vec[51] == true);
    assert_or_panic(vec[52] == true);
    assert_or_panic(vec[53] == true);
    assert_or_panic(vec[54] == false);
    assert_or_panic(vec[55] == false);
    assert_or_panic(vec[56] == false);
    assert_or_panic(vec[57] == true);
    assert_or_panic(vec[58] == false);
    assert_or_panic(vec[59] == false);
    assert_or_panic(vec[60] == true);
    assert_or_panic(vec[61] == false);
    assert_or_panic(vec[62] == true);
    assert_or_panic(vec[63] == false);
    zig_vector_64_bool((Vector_64_bool){
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        false,
        false,
        true,
        true,
        false,
        true,
        true,
        true,
        true,
        false,
        false,
        true,
        false,
        false,
        true,
        false,
        true,
        false,
        true,
        true,
        false,
        true,
        true,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        false,
        true,
        false,
        false,
        false,
        false,
        false,
        true,
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
    });
}

typedef bool Vector_128_bool __attribute__((ext_vector_type(128)));

Vector_128_bool zig_ret_vector_128_bool(void);
void zig_vector_128_bool(Vector_128_bool vec);

Vector_128_bool c_ret_vector_128_bool(void) {
    return (Vector_128_bool){
        false,
        true,
        true,
        false,
        true,
        false,
        false,
        true,
        true,
        false,
        true,
        false,
        false,
        false,
        true,
        false,
        true,
        false,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        false,
        true,
        true,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        false,
        false,
        false,
        false,
        true,
        false,
        false,
        true,
        false,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        false,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        true,
        true,
        true,
        false,
        false,
        true,
        false,
        false,
        true,
        true,
        true,
        true,
        false,
        true,
        true,
        true,
        false,
        false,
        true,
        false,
        false,
        true,
        true,
        false,
        true,
        false,
        true,
        true,
        true,
        true,
        true,
        false,
        false,
        true,
        false,
        true,
    };
}
void c_vector_128_bool(Vector_128_bool vec) {
    assert_or_panic(vec[0] == false);
    assert_or_panic(vec[1] == false);
    assert_or_panic(vec[2] == false);
    assert_or_panic(vec[3] == false);
    assert_or_panic(vec[4] == false);
    assert_or_panic(vec[5] == true);
    assert_or_panic(vec[6] == true);
    assert_or_panic(vec[7] == false);
    assert_or_panic(vec[8] == true);
    assert_or_panic(vec[9] == true);
    assert_or_panic(vec[10] == false);
    assert_or_panic(vec[11] == true);
    assert_or_panic(vec[12] == true);
    assert_or_panic(vec[13] == false);
    assert_or_panic(vec[14] == true);
    assert_or_panic(vec[15] == true);
    assert_or_panic(vec[16] == true);
    assert_or_panic(vec[17] == false);
    assert_or_panic(vec[18] == false);
    assert_or_panic(vec[19] == false);
    assert_or_panic(vec[20] == false);
    assert_or_panic(vec[21] == true);
    assert_or_panic(vec[22] == true);
    assert_or_panic(vec[23] == false);
    assert_or_panic(vec[24] == false);
    assert_or_panic(vec[25] == false);
    assert_or_panic(vec[26] == true);
    assert_or_panic(vec[27] == true);
    assert_or_panic(vec[28] == false);
    assert_or_panic(vec[29] == true);
    assert_or_panic(vec[30] == false);
    assert_or_panic(vec[31] == false);
    assert_or_panic(vec[32] == true);
    assert_or_panic(vec[33] == false);
    assert_or_panic(vec[34] == false);
    assert_or_panic(vec[35] == true);
    assert_or_panic(vec[36] == true);
    assert_or_panic(vec[37] == true);
    assert_or_panic(vec[38] == true);
    assert_or_panic(vec[39] == true);
    assert_or_panic(vec[40] == false);
    assert_or_panic(vec[41] == true);
    assert_or_panic(vec[42] == true);
    assert_or_panic(vec[43] == true);
    assert_or_panic(vec[44] == false);
    assert_or_panic(vec[45] == false);
    assert_or_panic(vec[46] == false);
    assert_or_panic(vec[47] == false);
    assert_or_panic(vec[48] == true);
    assert_or_panic(vec[49] == true);
    assert_or_panic(vec[50] == false);
    assert_or_panic(vec[51] == true);
    assert_or_panic(vec[52] == true);
    assert_or_panic(vec[53] == true);
    assert_or_panic(vec[54] == true);
    assert_or_panic(vec[55] == true);
    assert_or_panic(vec[56] == false);
    assert_or_panic(vec[57] == true);
    assert_or_panic(vec[58] == true);
    assert_or_panic(vec[59] == false);
    assert_or_panic(vec[60] == true);
    assert_or_panic(vec[61] == false);
    assert_or_panic(vec[62] == false);
    assert_or_panic(vec[63] == true);
    assert_or_panic(vec[64] == true);
    assert_or_panic(vec[65] == false);
    assert_or_panic(vec[66] == true);
    assert_or_panic(vec[67] == true);
    assert_or_panic(vec[68] == false);
    assert_or_panic(vec[69] == true);
    assert_or_panic(vec[70] == false);
    assert_or_panic(vec[71] == false);
    assert_or_panic(vec[72] == true);
    assert_or_panic(vec[73] == true);
    assert_or_panic(vec[74] == false);
    assert_or_panic(vec[75] == true);
    assert_or_panic(vec[76] == true);
    assert_or_panic(vec[77] == true);
    assert_or_panic(vec[78] == false);
    assert_or_panic(vec[79] == true);
    assert_or_panic(vec[80] == false);
    assert_or_panic(vec[81] == false);
    assert_or_panic(vec[82] == false);
    assert_or_panic(vec[83] == false);
    assert_or_panic(vec[84] == true);
    assert_or_panic(vec[85] == false);
    assert_or_panic(vec[86] == false);
    assert_or_panic(vec[87] == false);
    assert_or_panic(vec[88] == true);
    assert_or_panic(vec[89] == true);
    assert_or_panic(vec[90] == false);
    assert_or_panic(vec[91] == false);
    assert_or_panic(vec[92] == true);
    assert_or_panic(vec[93] == true);
    assert_or_panic(vec[94] == true);
    assert_or_panic(vec[95] == true);
    assert_or_panic(vec[96] == false);
    assert_or_panic(vec[97] == false);
    assert_or_panic(vec[98] == false);
    assert_or_panic(vec[99] == false);
    assert_or_panic(vec[100] == false);
    assert_or_panic(vec[101] == true);
    assert_or_panic(vec[102] == false);
    assert_or_panic(vec[103] == false);
    assert_or_panic(vec[104] == false);
    assert_or_panic(vec[105] == false);
    assert_or_panic(vec[106] == true);
    assert_or_panic(vec[107] == true);
    assert_or_panic(vec[108] == true);
    assert_or_panic(vec[109] == true);
    assert_or_panic(vec[110] == true);
    assert_or_panic(vec[111] == false);
    assert_or_panic(vec[112] == false);
    assert_or_panic(vec[113] == true);
    assert_or_panic(vec[114] == false);
    assert_or_panic(vec[115] == true);
    assert_or_panic(vec[116] == false);
    assert_or_panic(vec[117] == false);
    assert_or_panic(vec[118] == true);
    assert_or_panic(vec[119] == false);
    assert_or_panic(vec[120] == true);
    assert_or_panic(vec[121] == false);
    assert_or_panic(vec[122] == true);
    assert_or_panic(vec[123] == true);
    assert_or_panic(vec[124] == true);
    assert_or_panic(vec[125] == true);
    assert_or_panic(vec[126] == true);
    assert_or_panic(vec[127] == true);
}
void c_test_vector_128_bool(void) {
    Vector_128_bool vec = zig_ret_vector_128_bool();
    assert_or_panic(vec[0] == true);
    assert_or_panic(vec[1] == true);
    assert_or_panic(vec[2] == false);
    assert_or_panic(vec[3] == false);
    assert_or_panic(vec[4] == false);
    assert_or_panic(vec[5] == true);
    assert_or_panic(vec[6] == true);
    assert_or_panic(vec[7] == false);
    assert_or_panic(vec[8] == false);
    assert_or_panic(vec[9] == true);
    assert_or_panic(vec[10] == false);
    assert_or_panic(vec[11] == false);
    assert_or_panic(vec[12] == false);
    assert_or_panic(vec[13] == true);
    assert_or_panic(vec[14] == false);
    assert_or_panic(vec[15] == true);
    assert_or_panic(vec[16] == true);
    assert_or_panic(vec[17] == false);
    assert_or_panic(vec[18] == false);
    assert_or_panic(vec[19] == true);
    assert_or_panic(vec[20] == true);
    assert_or_panic(vec[21] == true);
    assert_or_panic(vec[22] == true);
    assert_or_panic(vec[23] == true);
    assert_or_panic(vec[24] == false);
    assert_or_panic(vec[25] == false);
    assert_or_panic(vec[26] == true);
    assert_or_panic(vec[27] == true);
    assert_or_panic(vec[28] == true);
    assert_or_panic(vec[29] == false);
    assert_or_panic(vec[30] == false);
    assert_or_panic(vec[31] == true);
    assert_or_panic(vec[32] == true);
    assert_or_panic(vec[33] == false);
    assert_or_panic(vec[34] == true);
    assert_or_panic(vec[35] == true);
    assert_or_panic(vec[36] == true);
    assert_or_panic(vec[37] == false);
    assert_or_panic(vec[38] == true);
    assert_or_panic(vec[39] == true);
    assert_or_panic(vec[40] == true);
    assert_or_panic(vec[41] == false);
    assert_or_panic(vec[42] == true);
    assert_or_panic(vec[43] == true);
    assert_or_panic(vec[44] == false);
    assert_or_panic(vec[45] == false);
    assert_or_panic(vec[46] == false);
    assert_or_panic(vec[47] == true);
    assert_or_panic(vec[48] == false);
    assert_or_panic(vec[49] == false);
    assert_or_panic(vec[50] == false);
    assert_or_panic(vec[51] == false);
    assert_or_panic(vec[52] == true);
    assert_or_panic(vec[53] == false);
    assert_or_panic(vec[54] == true);
    assert_or_panic(vec[55] == false);
    assert_or_panic(vec[56] == true);
    assert_or_panic(vec[57] == false);
    assert_or_panic(vec[58] == false);
    assert_or_panic(vec[59] == true);
    assert_or_panic(vec[60] == true);
    assert_or_panic(vec[61] == true);
    assert_or_panic(vec[62] == true);
    assert_or_panic(vec[63] == true);
    assert_or_panic(vec[64] == false);
    assert_or_panic(vec[65] == false);
    assert_or_panic(vec[66] == false);
    assert_or_panic(vec[67] == true);
    assert_or_panic(vec[68] == true);
    assert_or_panic(vec[69] == false);
    assert_or_panic(vec[70] == true);
    assert_or_panic(vec[71] == true);
    assert_or_panic(vec[72] == false);
    assert_or_panic(vec[73] == true);
    assert_or_panic(vec[74] == true);
    assert_or_panic(vec[75] == false);
    assert_or_panic(vec[76] == false);
    assert_or_panic(vec[77] == true);
    assert_or_panic(vec[78] == false);
    assert_or_panic(vec[79] == true);
    assert_or_panic(vec[80] == false);
    assert_or_panic(vec[81] == false);
    assert_or_panic(vec[82] == true);
    assert_or_panic(vec[83] == true);
    assert_or_panic(vec[84] == false);
    assert_or_panic(vec[85] == true);
    assert_or_panic(vec[86] == false);
    assert_or_panic(vec[87] == false);
    assert_or_panic(vec[88] == true);
    assert_or_panic(vec[89] == true);
    assert_or_panic(vec[90] == true);
    assert_or_panic(vec[91] == true);
    assert_or_panic(vec[92] == true);
    assert_or_panic(vec[93] == false);
    assert_or_panic(vec[94] == false);
    assert_or_panic(vec[95] == true);
    assert_or_panic(vec[96] == false);
    assert_or_panic(vec[97] == false);
    assert_or_panic(vec[98] == true);
    assert_or_panic(vec[99] == true);
    assert_or_panic(vec[100] == true);
    assert_or_panic(vec[101] == true);
    assert_or_panic(vec[102] == true);
    assert_or_panic(vec[103] == true);
    assert_or_panic(vec[104] == true);
    assert_or_panic(vec[105] == false);
    assert_or_panic(vec[106] == false);
    assert_or_panic(vec[107] == true);
    assert_or_panic(vec[108] == false);
    assert_or_panic(vec[109] == false);
    assert_or_panic(vec[110] == true);
    assert_or_panic(vec[111] == false);
    assert_or_panic(vec[112] == false);
    assert_or_panic(vec[113] == true);
    assert_or_panic(vec[114] == false);
    assert_or_panic(vec[115] == false);
    assert_or_panic(vec[116] == false);
    assert_or_panic(vec[117] == false);
    assert_or_panic(vec[118] == false);
    assert_or_panic(vec[119] == false);
    assert_or_panic(vec[120] == true);
    assert_or_panic(vec[121] == true);
    assert_or_panic(vec[122] == true);
    assert_or_panic(vec[123] == false);
    assert_or_panic(vec[124] == true);
    assert_or_panic(vec[125] == false);
    assert_or_panic(vec[126] == false);
    assert_or_panic(vec[127] == true);
    zig_vector_128_bool((Vector_128_bool){
        true,
        true,
        false,
        true,
        true,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        true,
        false,
        true,
        false,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
        true,
        false,
        true,
        true,
        false,
        true,
        false,
        true,
        true,
        false,
        false,
        false,
        false,
        true,
        true,
        false,
        true,
        false,
        false,
        true,
        false,
        false,
        true,
        true,
        false,
        false,
        true,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        false,
        false,
        true,
        false,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        false,
        true,
        true,
        true,
        true,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        false,
        true,
        true,
        false,
        true,
        false,
    });
}

typedef bool Vector_256_bool __attribute__((ext_vector_type(256)));

Vector_256_bool zig_ret_vector_256_bool(void);
void zig_vector_256_bool(Vector_256_bool vec);

Vector_256_bool c_ret_vector_256_bool(void) {
    return (Vector_256_bool){
        true,
        false,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        true,
        true,
        true,
        false,
        false,
        false,
        true,
        false,
        true,
        false,
        false,
        true,
        true,
        true,
        false,
        false,
        true,
        true,
        true,
        false,
        true,
        true,
        true,
        false,
        true,
        false,
        true,
        true,
        false,
        true,
        false,
        true,
        true,
        false,
        false,
        true,
        true,
        false,
        false,
        true,
        false,
        true,
        true,
        true,
        false,
        true,
        true,
        false,
        true,
        true,
        false,
        true,
        false,
        true,
        true,
        true,
        false,
        true,
        true,
        false,
        true,
        true,
        true,
        true,
        false,
        true,
        false,
        true,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        false,
        false,
        false,
        true,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        true,
        true,
        false,
        true,
        false,
        false,
        false,
        false,
        true,
        false,
        false,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        false,
        true,
        false,
        true,
        true,
        true,
        false,
        true,
        true,
        false,
        true,
        true,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        true,
        false,
        false,
        true,
        false,
        true,
        true,
        true,
        false,
        false,
        true,
        true,
        true,
        true,
        false,
        true,
        true,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        false,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        true,
        false,
        true,
        true,
        false,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
    };
}
// WASM: The following vector functions define too many Wasm locals for wasmtime in debug mode and are therefore disabled for the wasm target.
#ifndef __wasm__
void c_vector_256_bool(Vector_256_bool vec) {
    assert_or_panic(vec[0] == false);
    assert_or_panic(vec[1] == true);
    assert_or_panic(vec[2] == true);
    assert_or_panic(vec[3] == false);
    assert_or_panic(vec[4] == false);
    assert_or_panic(vec[5] == true);
    assert_or_panic(vec[6] == true);
    assert_or_panic(vec[7] == true);
    assert_or_panic(vec[8] == false);
    assert_or_panic(vec[9] == true);
    assert_or_panic(vec[10] == true);
    assert_or_panic(vec[11] == true);
    assert_or_panic(vec[12] == false);
    assert_or_panic(vec[13] == true);
    assert_or_panic(vec[14] == false);
    assert_or_panic(vec[15] == true);
    assert_or_panic(vec[16] == false);
    assert_or_panic(vec[17] == false);
    assert_or_panic(vec[18] == true);
    assert_or_panic(vec[19] == true);
    assert_or_panic(vec[20] == false);
    assert_or_panic(vec[21] == true);
    assert_or_panic(vec[22] == false);
    assert_or_panic(vec[23] == false);
    assert_or_panic(vec[24] == false);
    assert_or_panic(vec[25] == true);
    assert_or_panic(vec[26] == true);
    assert_or_panic(vec[27] == false);
    assert_or_panic(vec[28] == false);
    assert_or_panic(vec[29] == true);
    assert_or_panic(vec[30] == true);
    assert_or_panic(vec[31] == false);
    assert_or_panic(vec[32] == true);
    assert_or_panic(vec[33] == false);
    assert_or_panic(vec[34] == false);
    assert_or_panic(vec[35] == true);
    assert_or_panic(vec[36] == false);
    assert_or_panic(vec[37] == true);
    assert_or_panic(vec[38] == false);
    assert_or_panic(vec[39] == true);
    assert_or_panic(vec[40] == true);
    assert_or_panic(vec[41] == true);
    assert_or_panic(vec[42] == true);
    assert_or_panic(vec[43] == false);
    assert_or_panic(vec[44] == false);
    assert_or_panic(vec[45] == true);
    assert_or_panic(vec[46] == false);
    assert_or_panic(vec[47] == false);
    assert_or_panic(vec[48] == false);
    assert_or_panic(vec[49] == false);
    assert_or_panic(vec[50] == false);
    assert_or_panic(vec[51] == false);
    assert_or_panic(vec[52] == true);
    assert_or_panic(vec[53] == true);
    assert_or_panic(vec[54] == true);
    assert_or_panic(vec[55] == true);
    assert_or_panic(vec[56] == true);
    assert_or_panic(vec[57] == true);
    assert_or_panic(vec[58] == false);
    assert_or_panic(vec[59] == true);
    assert_or_panic(vec[60] == true);
    assert_or_panic(vec[61] == false);
    assert_or_panic(vec[62] == false);
    assert_or_panic(vec[63] == true);
    assert_or_panic(vec[64] == false);
    assert_or_panic(vec[65] == false);
    assert_or_panic(vec[66] == false);
    assert_or_panic(vec[67] == false);
    assert_or_panic(vec[68] == false);
    assert_or_panic(vec[69] == false);
    assert_or_panic(vec[70] == true);
    assert_or_panic(vec[71] == true);
    assert_or_panic(vec[72] == true);
    assert_or_panic(vec[73] == false);
    assert_or_panic(vec[74] == false);
    assert_or_panic(vec[75] == false);
    assert_or_panic(vec[76] == true);
    assert_or_panic(vec[77] == false);
    assert_or_panic(vec[78] == true);
    assert_or_panic(vec[79] == true);
    assert_or_panic(vec[80] == false);
    assert_or_panic(vec[81] == false);
    assert_or_panic(vec[82] == true);
    assert_or_panic(vec[83] == true);
    assert_or_panic(vec[84] == false);
    assert_or_panic(vec[85] == true);
    assert_or_panic(vec[86] == true);
    assert_or_panic(vec[87] == true);
    assert_or_panic(vec[88] == true);
    assert_or_panic(vec[89] == true);
    assert_or_panic(vec[90] == true);
    assert_or_panic(vec[91] == true);
    assert_or_panic(vec[92] == false);
    assert_or_panic(vec[93] == true);
    assert_or_panic(vec[94] == true);
    assert_or_panic(vec[95] == false);
    assert_or_panic(vec[96] == false);
    assert_or_panic(vec[97] == true);
    assert_or_panic(vec[98] == true);
    assert_or_panic(vec[99] == false);
    assert_or_panic(vec[100] == true);
    assert_or_panic(vec[101] == false);
    assert_or_panic(vec[102] == false);
    assert_or_panic(vec[103] == true);
    assert_or_panic(vec[104] == false);
    assert_or_panic(vec[105] == true);
    assert_or_panic(vec[106] == true);
    assert_or_panic(vec[107] == true);
    assert_or_panic(vec[108] == true);
    assert_or_panic(vec[109] == true);
    assert_or_panic(vec[110] == false);
    assert_or_panic(vec[111] == false);
    assert_or_panic(vec[112] == false);
    assert_or_panic(vec[113] == false);
    assert_or_panic(vec[114] == true);
    assert_or_panic(vec[115] == true);
    assert_or_panic(vec[116] == false);
    assert_or_panic(vec[117] == true);
    assert_or_panic(vec[118] == false);
    assert_or_panic(vec[119] == false);
    assert_or_panic(vec[120] == true);
    assert_or_panic(vec[121] == false);
    assert_or_panic(vec[122] == false);
    assert_or_panic(vec[123] == true);
    assert_or_panic(vec[124] == false);
    assert_or_panic(vec[125] == true);
    assert_or_panic(vec[126] == true);
    assert_or_panic(vec[127] == true);
    assert_or_panic(vec[128] == true);
    assert_or_panic(vec[129] == false);
    assert_or_panic(vec[130] == true);
    assert_or_panic(vec[131] == true);
    assert_or_panic(vec[132] == false);
    assert_or_panic(vec[133] == false);
    assert_or_panic(vec[134] == true);
    assert_or_panic(vec[135] == false);
    assert_or_panic(vec[136] == false);
    assert_or_panic(vec[137] == true);
    assert_or_panic(vec[138] == false);
    assert_or_panic(vec[139] == true);
    assert_or_panic(vec[140] == false);
    assert_or_panic(vec[141] == true);
    assert_or_panic(vec[142] == true);
    assert_or_panic(vec[143] == true);
    assert_or_panic(vec[144] == true);
    assert_or_panic(vec[145] == false);
    assert_or_panic(vec[146] == true);
    assert_or_panic(vec[147] == false);
    assert_or_panic(vec[148] == false);
    assert_or_panic(vec[149] == false);
    assert_or_panic(vec[150] == true);
    assert_or_panic(vec[151] == true);
    assert_or_panic(vec[152] == true);
    assert_or_panic(vec[153] == true);
    assert_or_panic(vec[154] == true);
    assert_or_panic(vec[155] == false);
    assert_or_panic(vec[156] == true);
    assert_or_panic(vec[157] == false);
    assert_or_panic(vec[158] == false);
    assert_or_panic(vec[159] == false);
    assert_or_panic(vec[160] == true);
    assert_or_panic(vec[161] == true);
    assert_or_panic(vec[162] == false);
    assert_or_panic(vec[163] == true);
    assert_or_panic(vec[164] == true);
    assert_or_panic(vec[165] == false);
    assert_or_panic(vec[166] == false);
    assert_or_panic(vec[167] == false);
    assert_or_panic(vec[168] == false);
    assert_or_panic(vec[169] == true);
    assert_or_panic(vec[170] == false);
    assert_or_panic(vec[171] == true);
    assert_or_panic(vec[172] == false);
    assert_or_panic(vec[173] == false);
    assert_or_panic(vec[174] == false);
    assert_or_panic(vec[175] == false);
    assert_or_panic(vec[176] == true);
    assert_or_panic(vec[177] == true);
    assert_or_panic(vec[178] == true);
    assert_or_panic(vec[179] == false);
    assert_or_panic(vec[180] == true);
    assert_or_panic(vec[181] == false);
    assert_or_panic(vec[182] == true);
    assert_or_panic(vec[183] == true);
    assert_or_panic(vec[184] == false);
    assert_or_panic(vec[185] == false);
    assert_or_panic(vec[186] == true);
    assert_or_panic(vec[187] == false);
    assert_or_panic(vec[188] == false);
    assert_or_panic(vec[189] == false);
    assert_or_panic(vec[190] == false);
    assert_or_panic(vec[191] == true);
    assert_or_panic(vec[192] == true);
    assert_or_panic(vec[193] == true);
    assert_or_panic(vec[194] == true);
    assert_or_panic(vec[195] == true);
    assert_or_panic(vec[196] == true);
    assert_or_panic(vec[197] == true);
    assert_or_panic(vec[198] == false);
    assert_or_panic(vec[199] == true);
    assert_or_panic(vec[200] == false);
    assert_or_panic(vec[201] == false);
    assert_or_panic(vec[202] == true);
    assert_or_panic(vec[203] == false);
    assert_or_panic(vec[204] == true);
    assert_or_panic(vec[205] == true);
    assert_or_panic(vec[206] == true);
    assert_or_panic(vec[207] == false);
    assert_or_panic(vec[208] == false);
    assert_or_panic(vec[209] == true);
    assert_or_panic(vec[210] == true);
    assert_or_panic(vec[211] == true);
    assert_or_panic(vec[212] == false);
    assert_or_panic(vec[213] == true);
    assert_or_panic(vec[214] == true);
    assert_or_panic(vec[215] == true);
    assert_or_panic(vec[216] == true);
    assert_or_panic(vec[217] == true);
    assert_or_panic(vec[218] == false);
    assert_or_panic(vec[219] == false);
    assert_or_panic(vec[220] == false);
    assert_or_panic(vec[221] == false);
    assert_or_panic(vec[222] == false);
    assert_or_panic(vec[223] == true);
    assert_or_panic(vec[224] == true);
    assert_or_panic(vec[225] == false);
    assert_or_panic(vec[226] == true);
    assert_or_panic(vec[227] == false);
    assert_or_panic(vec[228] == false);
    assert_or_panic(vec[229] == true);
    assert_or_panic(vec[230] == false);
    assert_or_panic(vec[231] == true);
    assert_or_panic(vec[232] == false);
    assert_or_panic(vec[233] == false);
    assert_or_panic(vec[234] == false);
    assert_or_panic(vec[235] == true);
    assert_or_panic(vec[236] == false);
    assert_or_panic(vec[237] == false);
    assert_or_panic(vec[238] == false);
    assert_or_panic(vec[239] == true);
    assert_or_panic(vec[240] == true);
    assert_or_panic(vec[241] == true);
    assert_or_panic(vec[242] == true);
    assert_or_panic(vec[243] == true);
    assert_or_panic(vec[244] == true);
    assert_or_panic(vec[245] == false);
    assert_or_panic(vec[246] == false);
    assert_or_panic(vec[247] == true);
    assert_or_panic(vec[248] == false);
    assert_or_panic(vec[249] == true);
    assert_or_panic(vec[250] == true);
    assert_or_panic(vec[251] == false);
    assert_or_panic(vec[252] == true);
    assert_or_panic(vec[253] == true);
    assert_or_panic(vec[254] == true);
    assert_or_panic(vec[255] == false);
}
#endif
void c_test_vector_256_bool(void) {
    Vector_256_bool vec = zig_ret_vector_256_bool();
    assert_or_panic(vec[0] == true);
    assert_or_panic(vec[1] == true);
    assert_or_panic(vec[2] == true);
    assert_or_panic(vec[3] == false);
    assert_or_panic(vec[4] == true);
    assert_or_panic(vec[5] == false);
    assert_or_panic(vec[6] == false);
    assert_or_panic(vec[7] == true);
    assert_or_panic(vec[8] == false);
    assert_or_panic(vec[9] == false);
    assert_or_panic(vec[10] == false);
    assert_or_panic(vec[11] == false);
    assert_or_panic(vec[12] == false);
    assert_or_panic(vec[13] == false);
    assert_or_panic(vec[14] == false);
    assert_or_panic(vec[15] == false);
    assert_or_panic(vec[16] == true);
    assert_or_panic(vec[17] == false);
    assert_or_panic(vec[18] == true);
    assert_or_panic(vec[19] == false);
    assert_or_panic(vec[20] == false);
    assert_or_panic(vec[21] == true);
    assert_or_panic(vec[22] == true);
    assert_or_panic(vec[23] == false);
    assert_or_panic(vec[24] == false);
    assert_or_panic(vec[25] == true);
    assert_or_panic(vec[26] == true);
    assert_or_panic(vec[27] == false);
    assert_or_panic(vec[28] == true);
    assert_or_panic(vec[29] == true);
    assert_or_panic(vec[30] == true);
    assert_or_panic(vec[31] == false);
    assert_or_panic(vec[32] == true);
    assert_or_panic(vec[33] == false);
    assert_or_panic(vec[34] == true);
    assert_or_panic(vec[35] == false);
    assert_or_panic(vec[36] == true);
    assert_or_panic(vec[37] == false);
    assert_or_panic(vec[38] == true);
    assert_or_panic(vec[39] == false);
    assert_or_panic(vec[40] == false);
    assert_or_panic(vec[41] == false);
    assert_or_panic(vec[42] == true);
    assert_or_panic(vec[43] == true);
    assert_or_panic(vec[44] == true);
    assert_or_panic(vec[45] == false);
    assert_or_panic(vec[46] == false);
    assert_or_panic(vec[47] == false);
    assert_or_panic(vec[48] == true);
    assert_or_panic(vec[49] == false);
    assert_or_panic(vec[50] == true);
    assert_or_panic(vec[51] == false);
    assert_or_panic(vec[52] == true);
    assert_or_panic(vec[53] == false);
    assert_or_panic(vec[54] == true);
    assert_or_panic(vec[55] == true);
    assert_or_panic(vec[56] == false);
    assert_or_panic(vec[57] == false);
    assert_or_panic(vec[58] == false);
    assert_or_panic(vec[59] == true);
    assert_or_panic(vec[60] == true);
    assert_or_panic(vec[61] == true);
    assert_or_panic(vec[62] == false);
    assert_or_panic(vec[63] == true);
    assert_or_panic(vec[64] == false);
    assert_or_panic(vec[65] == true);
    assert_or_panic(vec[66] == false);
    assert_or_panic(vec[67] == true);
    assert_or_panic(vec[68] == true);
    assert_or_panic(vec[69] == false);
    assert_or_panic(vec[70] == true);
    assert_or_panic(vec[71] == false);
    assert_or_panic(vec[72] == true);
    assert_or_panic(vec[73] == true);
    assert_or_panic(vec[74] == false);
    assert_or_panic(vec[75] == false);
    assert_or_panic(vec[76] == false);
    assert_or_panic(vec[77] == false);
    assert_or_panic(vec[78] == false);
    assert_or_panic(vec[79] == false);
    assert_or_panic(vec[80] == false);
    assert_or_panic(vec[81] == false);
    assert_or_panic(vec[82] == false);
    assert_or_panic(vec[83] == true);
    assert_or_panic(vec[84] == false);
    assert_or_panic(vec[85] == false);
    assert_or_panic(vec[86] == false);
    assert_or_panic(vec[87] == true);
    assert_or_panic(vec[88] == false);
    assert_or_panic(vec[89] == true);
    assert_or_panic(vec[90] == true);
    assert_or_panic(vec[91] == false);
    assert_or_panic(vec[92] == false);
    assert_or_panic(vec[93] == true);
    assert_or_panic(vec[94] == true);
    assert_or_panic(vec[95] == false);
    assert_or_panic(vec[96] == false);
    assert_or_panic(vec[97] == true);
    assert_or_panic(vec[98] == false);
    assert_or_panic(vec[99] == false);
    assert_or_panic(vec[100] == false);
    assert_or_panic(vec[101] == false);
    assert_or_panic(vec[102] == false);
    assert_or_panic(vec[103] == false);
    assert_or_panic(vec[104] == false);
    assert_or_panic(vec[105] == true);
    assert_or_panic(vec[106] == true);
    assert_or_panic(vec[107] == false);
    assert_or_panic(vec[108] == true);
    assert_or_panic(vec[109] == false);
    assert_or_panic(vec[110] == true);
    assert_or_panic(vec[111] == true);
    assert_or_panic(vec[112] == false);
    assert_or_panic(vec[113] == false);
    assert_or_panic(vec[114] == false);
    assert_or_panic(vec[115] == false);
    assert_or_panic(vec[116] == false);
    assert_or_panic(vec[117] == false);
    assert_or_panic(vec[118] == false);
    assert_or_panic(vec[119] == true);
    assert_or_panic(vec[120] == true);
    assert_or_panic(vec[121] == true);
    assert_or_panic(vec[122] == false);
    assert_or_panic(vec[123] == true);
    assert_or_panic(vec[124] == true);
    assert_or_panic(vec[125] == false);
    assert_or_panic(vec[126] == false);
    assert_or_panic(vec[127] == true);
    assert_or_panic(vec[128] == true);
    assert_or_panic(vec[129] == true);
    assert_or_panic(vec[130] == true);
    assert_or_panic(vec[131] == true);
    assert_or_panic(vec[132] == false);
    assert_or_panic(vec[133] == true);
    assert_or_panic(vec[134] == true);
    assert_or_panic(vec[135] == false);
    assert_or_panic(vec[136] == false);
    assert_or_panic(vec[137] == true);
    assert_or_panic(vec[138] == true);
    assert_or_panic(vec[139] == false);
    assert_or_panic(vec[140] == true);
    assert_or_panic(vec[141] == false);
    assert_or_panic(vec[142] == true);
    assert_or_panic(vec[143] == false);
    assert_or_panic(vec[144] == true);
    assert_or_panic(vec[145] == true);
    assert_or_panic(vec[146] == true);
    assert_or_panic(vec[147] == true);
    assert_or_panic(vec[148] == false);
    assert_or_panic(vec[149] == false);
    assert_or_panic(vec[150] == false);
    assert_or_panic(vec[151] == true);
    assert_or_panic(vec[152] == false);
    assert_or_panic(vec[153] == true);
    assert_or_panic(vec[154] == false);
    assert_or_panic(vec[155] == true);
    assert_or_panic(vec[156] == true);
    assert_or_panic(vec[157] == false);
    assert_or_panic(vec[158] == true);
    assert_or_panic(vec[159] == true);
    assert_or_panic(vec[160] == true);
    assert_or_panic(vec[161] == true);
    assert_or_panic(vec[162] == true);
    assert_or_panic(vec[163] == false);
    assert_or_panic(vec[164] == false);
    assert_or_panic(vec[165] == true);
    assert_or_panic(vec[166] == false);
    assert_or_panic(vec[167] == true);
    assert_or_panic(vec[168] == true);
    assert_or_panic(vec[169] == true);
    assert_or_panic(vec[170] == true);
    assert_or_panic(vec[171] == false);
    assert_or_panic(vec[172] == true);
    assert_or_panic(vec[173] == true);
    assert_or_panic(vec[174] == true);
    assert_or_panic(vec[175] == true);
    assert_or_panic(vec[176] == true);
    assert_or_panic(vec[177] == true);
    assert_or_panic(vec[178] == true);
    assert_or_panic(vec[179] == false);
    assert_or_panic(vec[180] == true);
    assert_or_panic(vec[181] == false);
    assert_or_panic(vec[182] == false);
    assert_or_panic(vec[183] == false);
    assert_or_panic(vec[184] == true);
    assert_or_panic(vec[185] == false);
    assert_or_panic(vec[186] == true);
    assert_or_panic(vec[187] == true);
    assert_or_panic(vec[188] == false);
    assert_or_panic(vec[189] == true);
    assert_or_panic(vec[190] == false);
    assert_or_panic(vec[191] == true);
    assert_or_panic(vec[192] == false);
    assert_or_panic(vec[193] == true);
    assert_or_panic(vec[194] == false);
    assert_or_panic(vec[195] == false);
    assert_or_panic(vec[196] == true);
    assert_or_panic(vec[197] == true);
    assert_or_panic(vec[198] == true);
    assert_or_panic(vec[199] == true);
    assert_or_panic(vec[200] == true);
    assert_or_panic(vec[201] == true);
    assert_or_panic(vec[202] == true);
    assert_or_panic(vec[203] == false);
    assert_or_panic(vec[204] == true);
    assert_or_panic(vec[205] == false);
    assert_or_panic(vec[206] == false);
    assert_or_panic(vec[207] == true);
    assert_or_panic(vec[208] == true);
    assert_or_panic(vec[209] == false);
    assert_or_panic(vec[210] == false);
    assert_or_panic(vec[211] == false);
    assert_or_panic(vec[212] == true);
    assert_or_panic(vec[213] == true);
    assert_or_panic(vec[214] == true);
    assert_or_panic(vec[215] == false);
    assert_or_panic(vec[216] == false);
    assert_or_panic(vec[217] == true);
    assert_or_panic(vec[218] == true);
    assert_or_panic(vec[219] == true);
    assert_or_panic(vec[220] == true);
    assert_or_panic(vec[221] == false);
    assert_or_panic(vec[222] == true);
    assert_or_panic(vec[223] == false);
    assert_or_panic(vec[224] == true);
    assert_or_panic(vec[225] == true);
    assert_or_panic(vec[226] == true);
    assert_or_panic(vec[227] == false);
    assert_or_panic(vec[228] == false);
    assert_or_panic(vec[229] == false);
    assert_or_panic(vec[230] == false);
    assert_or_panic(vec[231] == false);
    assert_or_panic(vec[232] == true);
    assert_or_panic(vec[233] == true);
    assert_or_panic(vec[234] == false);
    assert_or_panic(vec[235] == false);
    assert_or_panic(vec[236] == false);
    assert_or_panic(vec[237] == true);
    assert_or_panic(vec[238] == true);
    assert_or_panic(vec[239] == false);
    assert_or_panic(vec[240] == true);
    assert_or_panic(vec[241] == true);
    assert_or_panic(vec[242] == true);
    assert_or_panic(vec[243] == false);
    assert_or_panic(vec[244] == true);
    assert_or_panic(vec[245] == true);
    assert_or_panic(vec[246] == false);
    assert_or_panic(vec[247] == true);
    assert_or_panic(vec[248] == false);
    assert_or_panic(vec[249] == false);
    assert_or_panic(vec[250] == true);
    assert_or_panic(vec[251] == true);
    assert_or_panic(vec[252] == false);
    assert_or_panic(vec[253] == true);
    assert_or_panic(vec[254] == false);
    assert_or_panic(vec[255] == true);
    zig_vector_256_bool((Vector_256_bool){
        false,
        false,
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        false,
        true,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        false,
        true,
        true,
        false,
        true,
        false,
        false,
        true,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
        true,
        false,
        false,
        true,
        true,
        false,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        true,
        true,
        false,
        false,
        true,
        true,
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        true,
        false,
        false,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        true,
        true,
        true,
        false,
        true,
        false,
        true,
        true,
        false,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        false,
        true,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        false,
        true,
        false,
        false,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
        false,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        false,
        false,
        true,
        false,
        false,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        true,
        false,
        true,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        true,
        false,
        true,
        true,
        true,
        false,
        false,
        true,
        false,
        false,
        false,
        true,
        false,
        false,
        true,
        true,
        true,
        true,
    });
}

typedef bool Vector_512_bool __attribute__((ext_vector_type(512)));

Vector_512_bool zig_ret_vector_512_bool(void);
void zig_vector_512_bool(Vector_512_bool vec);

Vector_512_bool c_ret_vector_512_bool(void) {
    return (Vector_512_bool){
        false,
        true,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        false,
        true,
        true,
        false,
        true,
        false,
        true,
        true,
        true,
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        true,
        false,
        true,
        true,
        false,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        true,
        false,
        true,
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        true,
        false,
        true,
        true,
        true,
        false,
        true,
        false,
        false,
        true,
        true,
        false,
        true,
        true,
        false,
        true,
        false,
        true,
        true,
        false,
        true,
        true,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        true,
        false,
        true,
        false,
        true,
        true,
        true,
        false,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        false,
        true,
        false,
        true,
        true,
        false,
        true,
        false,
        false,
        true,
        false,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        true,
        false,
        true,
        true,
        true,
        false,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        false,
        true,
        false,
        false,
        false,
        false,
        false,
        true,
        true,
        false,
        false,
        true,
        false,
        false,
        false,
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        true,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        false,
        true,
        false,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        false,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        false,
        true,
        false,
        true,
        true,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        false,
        true,
        true,
        true,
        true,
        false,
        true,
        false,
        false,
        true,
        false,
        true,
        false,
        false,
        true,
        true,
        false,
        true,
        false,
        false,
        true,
        false,
        false,
        true,
        true,
        true,
        false,
        false,
        true,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        false,
        true,
        false,
        true,
        true,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        false,
        true,
        true,
        true,
        true,
        true,
        false,
        true,
        true,
        true,
        false,
        true,
        false,
        true,
        true,
        true,
        false,
        false,
        true,
        true,
        true,
        false,
        false,
        true,
        true,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        false,
        true,
        false,
        true,
        true,
        false,
        true,
        false,
        false,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        false,
        true,
        true,
        false,
        false,
        true,
        false,
        false,
        true,
        false,
        false,
        true,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        false,
        true,
        true,
        false,
        false,
        false,
        true,
        false,
        true,
        true,
        false,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        false,
        true,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        false,
        false,
        true,
        true,
        true,
        false,
        true,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        true,
        true,
        true,
        false,
        true,
        true,
        false,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        true,
        false,
        true,
        false,
    };
}
// WASM: The following vector functions define too many Wasm locals for wasmtime in debug mode and are therefore disabled for the wasm target.
#ifndef __wasm__
void c_vector_512_bool(Vector_512_bool vec) {
    assert_or_panic(vec[0] == true);
    assert_or_panic(vec[1] == true);
    assert_or_panic(vec[2] == true);
    assert_or_panic(vec[3] == true);
    assert_or_panic(vec[4] == true);
    assert_or_panic(vec[5] == false);
    assert_or_panic(vec[6] == false);
    assert_or_panic(vec[7] == true);
    assert_or_panic(vec[8] == true);
    assert_or_panic(vec[9] == true);
    assert_or_panic(vec[10] == true);
    assert_or_panic(vec[11] == false);
    assert_or_panic(vec[12] == true);
    assert_or_panic(vec[13] == true);
    assert_or_panic(vec[14] == false);
    assert_or_panic(vec[15] == false);
    assert_or_panic(vec[16] == false);
    assert_or_panic(vec[17] == true);
    assert_or_panic(vec[18] == true);
    assert_or_panic(vec[19] == true);
    assert_or_panic(vec[20] == true);
    assert_or_panic(vec[21] == true);
    assert_or_panic(vec[22] == false);
    assert_or_panic(vec[23] == false);
    assert_or_panic(vec[24] == true);
    assert_or_panic(vec[25] == true);
    assert_or_panic(vec[26] == false);
    assert_or_panic(vec[27] == false);
    assert_or_panic(vec[28] == false);
    assert_or_panic(vec[29] == false);
    assert_or_panic(vec[30] == false);
    assert_or_panic(vec[31] == true);
    assert_or_panic(vec[32] == true);
    assert_or_panic(vec[33] == false);
    assert_or_panic(vec[34] == true);
    assert_or_panic(vec[35] == true);
    assert_or_panic(vec[36] == true);
    assert_or_panic(vec[37] == true);
    assert_or_panic(vec[38] == true);
    assert_or_panic(vec[39] == true);
    assert_or_panic(vec[40] == false);
    assert_or_panic(vec[41] == true);
    assert_or_panic(vec[42] == true);
    assert_or_panic(vec[43] == false);
    assert_or_panic(vec[44] == false);
    assert_or_panic(vec[45] == false);
    assert_or_panic(vec[46] == true);
    assert_or_panic(vec[47] == true);
    assert_or_panic(vec[48] == false);
    assert_or_panic(vec[49] == true);
    assert_or_panic(vec[50] == false);
    assert_or_panic(vec[51] == true);
    assert_or_panic(vec[52] == true);
    assert_or_panic(vec[53] == false);
    assert_or_panic(vec[54] == true);
    assert_or_panic(vec[55] == false);
    assert_or_panic(vec[56] == false);
    assert_or_panic(vec[57] == true);
    assert_or_panic(vec[58] == true);
    assert_or_panic(vec[59] == false);
    assert_or_panic(vec[60] == true);
    assert_or_panic(vec[61] == true);
    assert_or_panic(vec[62] == false);
    assert_or_panic(vec[63] == true);
    assert_or_panic(vec[64] == false);
    assert_or_panic(vec[65] == true);
    assert_or_panic(vec[66] == true);
    assert_or_panic(vec[67] == true);
    assert_or_panic(vec[68] == true);
    assert_or_panic(vec[69] == true);
    assert_or_panic(vec[70] == true);
    assert_or_panic(vec[71] == true);
    assert_or_panic(vec[72] == true);
    assert_or_panic(vec[73] == true);
    assert_or_panic(vec[74] == false);
    assert_or_panic(vec[75] == true);
    assert_or_panic(vec[76] == false);
    assert_or_panic(vec[77] == true);
    assert_or_panic(vec[78] == false);
    assert_or_panic(vec[79] == false);
    assert_or_panic(vec[80] == false);
    assert_or_panic(vec[81] == true);
    assert_or_panic(vec[82] == false);
    assert_or_panic(vec[83] == true);
    assert_or_panic(vec[84] == true);
    assert_or_panic(vec[85] == false);
    assert_or_panic(vec[86] == true);
    assert_or_panic(vec[87] == true);
    assert_or_panic(vec[88] == true);
    assert_or_panic(vec[89] == false);
    assert_or_panic(vec[90] == true);
    assert_or_panic(vec[91] == true);
    assert_or_panic(vec[92] == false);
    assert_or_panic(vec[93] == true);
    assert_or_panic(vec[94] == false);
    assert_or_panic(vec[95] == true);
    assert_or_panic(vec[96] == true);
    assert_or_panic(vec[97] == false);
    assert_or_panic(vec[98] == false);
    assert_or_panic(vec[99] == false);
    assert_or_panic(vec[100] == true);
    assert_or_panic(vec[101] == true);
    assert_or_panic(vec[102] == false);
    assert_or_panic(vec[103] == true);
    assert_or_panic(vec[104] == false);
    assert_or_panic(vec[105] == false);
    assert_or_panic(vec[106] == true);
    assert_or_panic(vec[107] == false);
    assert_or_panic(vec[108] == false);
    assert_or_panic(vec[109] == true);
    assert_or_panic(vec[110] == false);
    assert_or_panic(vec[111] == false);
    assert_or_panic(vec[112] == false);
    assert_or_panic(vec[113] == false);
    assert_or_panic(vec[114] == false);
    assert_or_panic(vec[115] == true);
    assert_or_panic(vec[116] == true);
    assert_or_panic(vec[117] == false);
    assert_or_panic(vec[118] == false);
    assert_or_panic(vec[119] == false);
    assert_or_panic(vec[120] == false);
    assert_or_panic(vec[121] == true);
    assert_or_panic(vec[122] == false);
    assert_or_panic(vec[123] == false);
    assert_or_panic(vec[124] == true);
    assert_or_panic(vec[125] == true);
    assert_or_panic(vec[126] == false);
    assert_or_panic(vec[127] == true);
    assert_or_panic(vec[128] == false);
    assert_or_panic(vec[129] == true);
    assert_or_panic(vec[130] == true);
    assert_or_panic(vec[131] == false);
    assert_or_panic(vec[132] == true);
    assert_or_panic(vec[133] == false);
    assert_or_panic(vec[134] == false);
    assert_or_panic(vec[135] == false);
    assert_or_panic(vec[136] == false);
    assert_or_panic(vec[137] == true);
    assert_or_panic(vec[138] == true);
    assert_or_panic(vec[139] == false);
    assert_or_panic(vec[140] == false);
    assert_or_panic(vec[141] == false);
    assert_or_panic(vec[142] == true);
    assert_or_panic(vec[143] == true);
    assert_or_panic(vec[144] == false);
    assert_or_panic(vec[145] == false);
    assert_or_panic(vec[146] == true);
    assert_or_panic(vec[147] == true);
    assert_or_panic(vec[148] == true);
    assert_or_panic(vec[149] == true);
    assert_or_panic(vec[150] == true);
    assert_or_panic(vec[151] == true);
    assert_or_panic(vec[152] == true);
    assert_or_panic(vec[153] == false);
    assert_or_panic(vec[154] == true);
    assert_or_panic(vec[155] == false);
    assert_or_panic(vec[156] == false);
    assert_or_panic(vec[157] == true);
    assert_or_panic(vec[158] == false);
    assert_or_panic(vec[159] == true);
    assert_or_panic(vec[160] == false);
    assert_or_panic(vec[161] == true);
    assert_or_panic(vec[162] == true);
    assert_or_panic(vec[163] == true);
    assert_or_panic(vec[164] == true);
    assert_or_panic(vec[165] == true);
    assert_or_panic(vec[166] == true);
    assert_or_panic(vec[167] == true);
    assert_or_panic(vec[168] == true);
    assert_or_panic(vec[169] == false);
    assert_or_panic(vec[170] == true);
    assert_or_panic(vec[171] == true);
    assert_or_panic(vec[172] == false);
    assert_or_panic(vec[173] == true);
    assert_or_panic(vec[174] == true);
    assert_or_panic(vec[175] == false);
    assert_or_panic(vec[176] == false);
    assert_or_panic(vec[177] == false);
    assert_or_panic(vec[178] == true);
    assert_or_panic(vec[179] == false);
    assert_or_panic(vec[180] == false);
    assert_or_panic(vec[181] == true);
    assert_or_panic(vec[182] == true);
    assert_or_panic(vec[183] == true);
    assert_or_panic(vec[184] == true);
    assert_or_panic(vec[185] == true);
    assert_or_panic(vec[186] == true);
    assert_or_panic(vec[187] == true);
    assert_or_panic(vec[188] == true);
    assert_or_panic(vec[189] == true);
    assert_or_panic(vec[190] == false);
    assert_or_panic(vec[191] == true);
    assert_or_panic(vec[192] == true);
    assert_or_panic(vec[193] == false);
    assert_or_panic(vec[194] == false);
    assert_or_panic(vec[195] == true);
    assert_or_panic(vec[196] == true);
    assert_or_panic(vec[197] == false);
    assert_or_panic(vec[198] == true);
    assert_or_panic(vec[199] == true);
    assert_or_panic(vec[200] == false);
    assert_or_panic(vec[201] == true);
    assert_or_panic(vec[202] == true);
    assert_or_panic(vec[203] == false);
    assert_or_panic(vec[204] == true);
    assert_or_panic(vec[205] == true);
    assert_or_panic(vec[206] == true);
    assert_or_panic(vec[207] == true);
    assert_or_panic(vec[208] == false);
    assert_or_panic(vec[209] == true);
    assert_or_panic(vec[210] == false);
    assert_or_panic(vec[211] == true);
    assert_or_panic(vec[212] == true);
    assert_or_panic(vec[213] == false);
    assert_or_panic(vec[214] == true);
    assert_or_panic(vec[215] == false);
    assert_or_panic(vec[216] == true);
    assert_or_panic(vec[217] == false);
    assert_or_panic(vec[218] == true);
    assert_or_panic(vec[219] == false);
    assert_or_panic(vec[220] == false);
    assert_or_panic(vec[221] == true);
    assert_or_panic(vec[222] == false);
    assert_or_panic(vec[223] == false);
    assert_or_panic(vec[224] == false);
    assert_or_panic(vec[225] == true);
    assert_or_panic(vec[226] == true);
    assert_or_panic(vec[227] == false);
    assert_or_panic(vec[228] == false);
    assert_or_panic(vec[229] == false);
    assert_or_panic(vec[230] == true);
    assert_or_panic(vec[231] == false);
    assert_or_panic(vec[232] == true);
    assert_or_panic(vec[233] == false);
    assert_or_panic(vec[234] == false);
    assert_or_panic(vec[235] == false);
    assert_or_panic(vec[236] == true);
    assert_or_panic(vec[237] == true);
    assert_or_panic(vec[238] == false);
    assert_or_panic(vec[239] == false);
    assert_or_panic(vec[240] == false);
    assert_or_panic(vec[241] == false);
    assert_or_panic(vec[242] == false);
    assert_or_panic(vec[243] == true);
    assert_or_panic(vec[244] == true);
    assert_or_panic(vec[245] == false);
    assert_or_panic(vec[246] == true);
    assert_or_panic(vec[247] == false);
    assert_or_panic(vec[248] == false);
    assert_or_panic(vec[249] == true);
    assert_or_panic(vec[250] == false);
    assert_or_panic(vec[251] == false);
    assert_or_panic(vec[252] == false);
    assert_or_panic(vec[253] == true);
    assert_or_panic(vec[254] == false);
    assert_or_panic(vec[255] == false);
    assert_or_panic(vec[256] == false);
    assert_or_panic(vec[257] == false);
    assert_or_panic(vec[258] == true);
    assert_or_panic(vec[259] == true);
    assert_or_panic(vec[260] == true);
    assert_or_panic(vec[261] == true);
    assert_or_panic(vec[262] == false);
    assert_or_panic(vec[263] == true);
    assert_or_panic(vec[264] == false);
    assert_or_panic(vec[265] == false);
    assert_or_panic(vec[266] == false);
    assert_or_panic(vec[267] == true);
    assert_or_panic(vec[268] == false);
    assert_or_panic(vec[269] == false);
    assert_or_panic(vec[270] == true);
    assert_or_panic(vec[271] == true);
    assert_or_panic(vec[272] == false);
    assert_or_panic(vec[273] == false);
    assert_or_panic(vec[274] == false);
    assert_or_panic(vec[275] == false);
    assert_or_panic(vec[276] == false);
    assert_or_panic(vec[277] == true);
    assert_or_panic(vec[278] == false);
    assert_or_panic(vec[279] == true);
    assert_or_panic(vec[280] == true);
    assert_or_panic(vec[281] == true);
    assert_or_panic(vec[282] == true);
    assert_or_panic(vec[283] == true);
    assert_or_panic(vec[284] == false);
    assert_or_panic(vec[285] == false);
    assert_or_panic(vec[286] == false);
    assert_or_panic(vec[287] == false);
    assert_or_panic(vec[288] == false);
    assert_or_panic(vec[289] == false);
    assert_or_panic(vec[290] == false);
    assert_or_panic(vec[291] == false);
    assert_or_panic(vec[292] == false);
    assert_or_panic(vec[293] == true);
    assert_or_panic(vec[294] == true);
    assert_or_panic(vec[295] == true);
    assert_or_panic(vec[296] == true);
    assert_or_panic(vec[297] == true);
    assert_or_panic(vec[298] == true);
    assert_or_panic(vec[299] == false);
    assert_or_panic(vec[300] == true);
    assert_or_panic(vec[301] == false);
    assert_or_panic(vec[302] == true);
    assert_or_panic(vec[303] == true);
    assert_or_panic(vec[304] == true);
    assert_or_panic(vec[305] == false);
    assert_or_panic(vec[306] == false);
    assert_or_panic(vec[307] == true);
    assert_or_panic(vec[308] == true);
    assert_or_panic(vec[309] == true);
    assert_or_panic(vec[310] == false);
    assert_or_panic(vec[311] == true);
    assert_or_panic(vec[312] == true);
    assert_or_panic(vec[313] == true);
    assert_or_panic(vec[314] == false);
    assert_or_panic(vec[315] == true);
    assert_or_panic(vec[316] == true);
    assert_or_panic(vec[317] == true);
    assert_or_panic(vec[318] == false);
    assert_or_panic(vec[319] == true);
    assert_or_panic(vec[320] == true);
    assert_or_panic(vec[321] == false);
    assert_or_panic(vec[322] == false);
    assert_or_panic(vec[323] == true);
    assert_or_panic(vec[324] == false);
    assert_or_panic(vec[325] == false);
    assert_or_panic(vec[326] == false);
    assert_or_panic(vec[327] == false);
    assert_or_panic(vec[328] == true);
    assert_or_panic(vec[329] == false);
    assert_or_panic(vec[330] == true);
    assert_or_panic(vec[331] == true);
    assert_or_panic(vec[332] == true);
    assert_or_panic(vec[333] == true);
    assert_or_panic(vec[334] == false);
    assert_or_panic(vec[335] == false);
    assert_or_panic(vec[336] == true);
    assert_or_panic(vec[337] == false);
    assert_or_panic(vec[338] == true);
    assert_or_panic(vec[339] == false);
    assert_or_panic(vec[340] == false);
    assert_or_panic(vec[341] == false);
    assert_or_panic(vec[342] == true);
    assert_or_panic(vec[343] == false);
    assert_or_panic(vec[344] == true);
    assert_or_panic(vec[345] == false);
    assert_or_panic(vec[346] == false);
    assert_or_panic(vec[347] == true);
    assert_or_panic(vec[348] == true);
    assert_or_panic(vec[349] == true);
    assert_or_panic(vec[350] == true);
    assert_or_panic(vec[351] == false);
    assert_or_panic(vec[352] == false);
    assert_or_panic(vec[353] == false);
    assert_or_panic(vec[354] == true);
    assert_or_panic(vec[355] == true);
    assert_or_panic(vec[356] == false);
    assert_or_panic(vec[357] == true);
    assert_or_panic(vec[358] == false);
    assert_or_panic(vec[359] == false);
    assert_or_panic(vec[360] == true);
    assert_or_panic(vec[361] == false);
    assert_or_panic(vec[362] == true);
    assert_or_panic(vec[363] == false);
    assert_or_panic(vec[364] == true);
    assert_or_panic(vec[365] == true);
    assert_or_panic(vec[366] == false);
    assert_or_panic(vec[367] == false);
    assert_or_panic(vec[368] == true);
    assert_or_panic(vec[369] == true);
    assert_or_panic(vec[370] == true);
    assert_or_panic(vec[371] == true);
    assert_or_panic(vec[372] == false);
    assert_or_panic(vec[373] == false);
    assert_or_panic(vec[374] == true);
    assert_or_panic(vec[375] == false);
    assert_or_panic(vec[376] == true);
    assert_or_panic(vec[377] == true);
    assert_or_panic(vec[378] == false);
    assert_or_panic(vec[379] == true);
    assert_or_panic(vec[380] == true);
    assert_or_panic(vec[381] == false);
    assert_or_panic(vec[382] == true);
    assert_or_panic(vec[383] == true);
    assert_or_panic(vec[384] == true);
    assert_or_panic(vec[385] == false);
    assert_or_panic(vec[386] == true);
    assert_or_panic(vec[387] == true);
    assert_or_panic(vec[388] == true);
    assert_or_panic(vec[389] == false);
    assert_or_panic(vec[390] == false);
    assert_or_panic(vec[391] == true);
    assert_or_panic(vec[392] == false);
    assert_or_panic(vec[393] == true);
    assert_or_panic(vec[394] == true);
    assert_or_panic(vec[395] == true);
    assert_or_panic(vec[396] == false);
    assert_or_panic(vec[397] == false);
    assert_or_panic(vec[398] == false);
    assert_or_panic(vec[399] == false);
    assert_or_panic(vec[400] == false);
    assert_or_panic(vec[401] == true);
    assert_or_panic(vec[402] == false);
    assert_or_panic(vec[403] == false);
    assert_or_panic(vec[404] == false);
    assert_or_panic(vec[405] == false);
    assert_or_panic(vec[406] == true);
    assert_or_panic(vec[407] == false);
    assert_or_panic(vec[408] == false);
    assert_or_panic(vec[409] == true);
    assert_or_panic(vec[410] == true);
    assert_or_panic(vec[411] == false);
    assert_or_panic(vec[412] == false);
    assert_or_panic(vec[413] == false);
    assert_or_panic(vec[414] == false);
    assert_or_panic(vec[415] == true);
    assert_or_panic(vec[416] == true);
    assert_or_panic(vec[417] == true);
    assert_or_panic(vec[418] == true);
    assert_or_panic(vec[419] == true);
    assert_or_panic(vec[420] == false);
    assert_or_panic(vec[421] == false);
    assert_or_panic(vec[422] == false);
    assert_or_panic(vec[423] == true);
    assert_or_panic(vec[424] == false);
    assert_or_panic(vec[425] == false);
    assert_or_panic(vec[426] == false);
    assert_or_panic(vec[427] == false);
    assert_or_panic(vec[428] == true);
    assert_or_panic(vec[429] == false);
    assert_or_panic(vec[430] == true);
    assert_or_panic(vec[431] == false);
    assert_or_panic(vec[432] == true);
    assert_or_panic(vec[433] == true);
    assert_or_panic(vec[434] == true);
    assert_or_panic(vec[435] == true);
    assert_or_panic(vec[436] == false);
    assert_or_panic(vec[437] == false);
    assert_or_panic(vec[438] == false);
    assert_or_panic(vec[439] == false);
    assert_or_panic(vec[440] == false);
    assert_or_panic(vec[441] == true);
    assert_or_panic(vec[442] == true);
    assert_or_panic(vec[443] == true);
    assert_or_panic(vec[444] == true);
    assert_or_panic(vec[445] == true);
    assert_or_panic(vec[446] == true);
    assert_or_panic(vec[447] == true);
    assert_or_panic(vec[448] == true);
    assert_or_panic(vec[449] == true);
    assert_or_panic(vec[450] == false);
    assert_or_panic(vec[451] == false);
    assert_or_panic(vec[452] == true);
    assert_or_panic(vec[453] == false);
    assert_or_panic(vec[454] == true);
    assert_or_panic(vec[455] == false);
    assert_or_panic(vec[456] == false);
    assert_or_panic(vec[457] == true);
    assert_or_panic(vec[458] == false);
    assert_or_panic(vec[459] == false);
    assert_or_panic(vec[460] == true);
    assert_or_panic(vec[461] == true);
    assert_or_panic(vec[462] == true);
    assert_or_panic(vec[463] == true);
    assert_or_panic(vec[464] == true);
    assert_or_panic(vec[465] == true);
    assert_or_panic(vec[466] == false);
    assert_or_panic(vec[467] == true);
    assert_or_panic(vec[468] == false);
    assert_or_panic(vec[469] == false);
    assert_or_panic(vec[470] == false);
    assert_or_panic(vec[471] == true);
    assert_or_panic(vec[472] == true);
    assert_or_panic(vec[473] == false);
    assert_or_panic(vec[474] == true);
    assert_or_panic(vec[475] == true);
    assert_or_panic(vec[476] == false);
    assert_or_panic(vec[477] == false);
    assert_or_panic(vec[478] == true);
    assert_or_panic(vec[479] == true);
    assert_or_panic(vec[480] == false);
    assert_or_panic(vec[481] == false);
    assert_or_panic(vec[482] == true);
    assert_or_panic(vec[483] == true);
    assert_or_panic(vec[484] == false);
    assert_or_panic(vec[485] == true);
    assert_or_panic(vec[486] == false);
    assert_or_panic(vec[487] == true);
    assert_or_panic(vec[488] == true);
    assert_or_panic(vec[489] == true);
    assert_or_panic(vec[490] == true);
    assert_or_panic(vec[491] == true);
    assert_or_panic(vec[492] == true);
    assert_or_panic(vec[493] == true);
    assert_or_panic(vec[494] == true);
    assert_or_panic(vec[495] == true);
    assert_or_panic(vec[496] == false);
    assert_or_panic(vec[497] == true);
    assert_or_panic(vec[498] == true);
    assert_or_panic(vec[499] == true);
    assert_or_panic(vec[500] == false);
    assert_or_panic(vec[501] == false);
    assert_or_panic(vec[502] == true);
    assert_or_panic(vec[503] == false);
    assert_or_panic(vec[504] == false);
    assert_or_panic(vec[505] == false);
    assert_or_panic(vec[506] == true);
    assert_or_panic(vec[507] == true);
    assert_or_panic(vec[508] == false);
    assert_or_panic(vec[509] == true);
    assert_or_panic(vec[510] == false);
    assert_or_panic(vec[511] == true);
}
#endif
void c_test_vector_512_bool(void) {
    Vector_512_bool vec = zig_ret_vector_512_bool();
    assert_or_panic(vec[0] == true);
    assert_or_panic(vec[1] == true);
    assert_or_panic(vec[2] == true);
    assert_or_panic(vec[3] == true);
    assert_or_panic(vec[4] == false);
    assert_or_panic(vec[5] == true);
    assert_or_panic(vec[6] == false);
    assert_or_panic(vec[7] == true);
    assert_or_panic(vec[8] == true);
    assert_or_panic(vec[9] == true);
    assert_or_panic(vec[10] == false);
    assert_or_panic(vec[11] == true);
    assert_or_panic(vec[12] == false);
    assert_or_panic(vec[13] == false);
    assert_or_panic(vec[14] == false);
    assert_or_panic(vec[15] == true);
    assert_or_panic(vec[16] == true);
    assert_or_panic(vec[17] == false);
    assert_or_panic(vec[18] == false);
    assert_or_panic(vec[19] == false);
    assert_or_panic(vec[20] == true);
    assert_or_panic(vec[21] == true);
    assert_or_panic(vec[22] == false);
    assert_or_panic(vec[23] == false);
    assert_or_panic(vec[24] == false);
    assert_or_panic(vec[25] == false);
    assert_or_panic(vec[26] == true);
    assert_or_panic(vec[27] == false);
    assert_or_panic(vec[28] == false);
    assert_or_panic(vec[29] == false);
    assert_or_panic(vec[30] == true);
    assert_or_panic(vec[31] == true);
    assert_or_panic(vec[32] == true);
    assert_or_panic(vec[33] == true);
    assert_or_panic(vec[34] == false);
    assert_or_panic(vec[35] == false);
    assert_or_panic(vec[36] == false);
    assert_or_panic(vec[37] == true);
    assert_or_panic(vec[38] == true);
    assert_or_panic(vec[39] == true);
    assert_or_panic(vec[40] == false);
    assert_or_panic(vec[41] == false);
    assert_or_panic(vec[42] == true);
    assert_or_panic(vec[43] == false);
    assert_or_panic(vec[44] == false);
    assert_or_panic(vec[45] == true);
    assert_or_panic(vec[46] == false);
    assert_or_panic(vec[47] == false);
    assert_or_panic(vec[48] == true);
    assert_or_panic(vec[49] == true);
    assert_or_panic(vec[50] == true);
    assert_or_panic(vec[51] == true);
    assert_or_panic(vec[52] == false);
    assert_or_panic(vec[53] == false);
    assert_or_panic(vec[54] == false);
    assert_or_panic(vec[55] == true);
    assert_or_panic(vec[56] == false);
    assert_or_panic(vec[57] == true);
    assert_or_panic(vec[58] == false);
    assert_or_panic(vec[59] == true);
    assert_or_panic(vec[60] == true);
    assert_or_panic(vec[61] == false);
    assert_or_panic(vec[62] == false);
    assert_or_panic(vec[63] == true);
    assert_or_panic(vec[64] == true);
    assert_or_panic(vec[65] == false);
    assert_or_panic(vec[66] == true);
    assert_or_panic(vec[67] == false);
    assert_or_panic(vec[68] == false);
    assert_or_panic(vec[69] == false);
    assert_or_panic(vec[70] == true);
    assert_or_panic(vec[71] == true);
    assert_or_panic(vec[72] == true);
    assert_or_panic(vec[73] == true);
    assert_or_panic(vec[74] == true);
    assert_or_panic(vec[75] == false);
    assert_or_panic(vec[76] == true);
    assert_or_panic(vec[77] == false);
    assert_or_panic(vec[78] == true);
    assert_or_panic(vec[79] == true);
    assert_or_panic(vec[80] == true);
    assert_or_panic(vec[81] == true);
    assert_or_panic(vec[82] == true);
    assert_or_panic(vec[83] == false);
    assert_or_panic(vec[84] == true);
    assert_or_panic(vec[85] == true);
    assert_or_panic(vec[86] == false);
    assert_or_panic(vec[87] == true);
    assert_or_panic(vec[88] == false);
    assert_or_panic(vec[89] == false);
    assert_or_panic(vec[90] == true);
    assert_or_panic(vec[91] == false);
    assert_or_panic(vec[92] == true);
    assert_or_panic(vec[93] == false);
    assert_or_panic(vec[94] == false);
    assert_or_panic(vec[95] == false);
    assert_or_panic(vec[96] == true);
    assert_or_panic(vec[97] == true);
    assert_or_panic(vec[98] == false);
    assert_or_panic(vec[99] == true);
    assert_or_panic(vec[100] == true);
    assert_or_panic(vec[101] == false);
    assert_or_panic(vec[102] == true);
    assert_or_panic(vec[103] == false);
    assert_or_panic(vec[104] == true);
    assert_or_panic(vec[105] == false);
    assert_or_panic(vec[106] == true);
    assert_or_panic(vec[107] == false);
    assert_or_panic(vec[108] == false);
    assert_or_panic(vec[109] == true);
    assert_or_panic(vec[110] == false);
    assert_or_panic(vec[111] == false);
    assert_or_panic(vec[112] == true);
    assert_or_panic(vec[113] == false);
    assert_or_panic(vec[114] == true);
    assert_or_panic(vec[115] == false);
    assert_or_panic(vec[116] == true);
    assert_or_panic(vec[117] == false);
    assert_or_panic(vec[118] == false);
    assert_or_panic(vec[119] == true);
    assert_or_panic(vec[120] == true);
    assert_or_panic(vec[121] == true);
    assert_or_panic(vec[122] == false);
    assert_or_panic(vec[123] == true);
    assert_or_panic(vec[124] == false);
    assert_or_panic(vec[125] == false);
    assert_or_panic(vec[126] == true);
    assert_or_panic(vec[127] == true);
    assert_or_panic(vec[128] == false);
    assert_or_panic(vec[129] == true);
    assert_or_panic(vec[130] == true);
    assert_or_panic(vec[131] == false);
    assert_or_panic(vec[132] == true);
    assert_or_panic(vec[133] == true);
    assert_or_panic(vec[134] == false);
    assert_or_panic(vec[135] == true);
    assert_or_panic(vec[136] == true);
    assert_or_panic(vec[137] == false);
    assert_or_panic(vec[138] == false);
    assert_or_panic(vec[139] == false);
    assert_or_panic(vec[140] == true);
    assert_or_panic(vec[141] == false);
    assert_or_panic(vec[142] == true);
    assert_or_panic(vec[143] == false);
    assert_or_panic(vec[144] == false);
    assert_or_panic(vec[145] == false);
    assert_or_panic(vec[146] == true);
    assert_or_panic(vec[147] == false);
    assert_or_panic(vec[148] == true);
    assert_or_panic(vec[149] == false);
    assert_or_panic(vec[150] == false);
    assert_or_panic(vec[151] == true);
    assert_or_panic(vec[152] == false);
    assert_or_panic(vec[153] == true);
    assert_or_panic(vec[154] == true);
    assert_or_panic(vec[155] == false);
    assert_or_panic(vec[156] == true);
    assert_or_panic(vec[157] == true);
    assert_or_panic(vec[158] == false);
    assert_or_panic(vec[159] == true);
    assert_or_panic(vec[160] == true);
    assert_or_panic(vec[161] == false);
    assert_or_panic(vec[162] == false);
    assert_or_panic(vec[163] == false);
    assert_or_panic(vec[164] == true);
    assert_or_panic(vec[165] == false);
    assert_or_panic(vec[166] == true);
    assert_or_panic(vec[167] == true);
    assert_or_panic(vec[168] == true);
    assert_or_panic(vec[169] == true);
    assert_or_panic(vec[170] == false);
    assert_or_panic(vec[171] == true);
    assert_or_panic(vec[172] == false);
    assert_or_panic(vec[173] == false);
    assert_or_panic(vec[174] == true);
    assert_or_panic(vec[175] == true);
    assert_or_panic(vec[176] == true);
    assert_or_panic(vec[177] == false);
    assert_or_panic(vec[178] == false);
    assert_or_panic(vec[179] == false);
    assert_or_panic(vec[180] == true);
    assert_or_panic(vec[181] == false);
    assert_or_panic(vec[182] == false);
    assert_or_panic(vec[183] == true);
    assert_or_panic(vec[184] == true);
    assert_or_panic(vec[185] == false);
    assert_or_panic(vec[186] == true);
    assert_or_panic(vec[187] == false);
    assert_or_panic(vec[188] == true);
    assert_or_panic(vec[189] == true);
    assert_or_panic(vec[190] == true);
    assert_or_panic(vec[191] == true);
    assert_or_panic(vec[192] == true);
    assert_or_panic(vec[193] == true);
    assert_or_panic(vec[194] == true);
    assert_or_panic(vec[195] == false);
    assert_or_panic(vec[196] == false);
    assert_or_panic(vec[197] == false);
    assert_or_panic(vec[198] == false);
    assert_or_panic(vec[199] == false);
    assert_or_panic(vec[200] == true);
    assert_or_panic(vec[201] == false);
    assert_or_panic(vec[202] == true);
    assert_or_panic(vec[203] == false);
    assert_or_panic(vec[204] == true);
    assert_or_panic(vec[205] == true);
    assert_or_panic(vec[206] == false);
    assert_or_panic(vec[207] == false);
    assert_or_panic(vec[208] == false);
    assert_or_panic(vec[209] == true);
    assert_or_panic(vec[210] == true);
    assert_or_panic(vec[211] == true);
    assert_or_panic(vec[212] == false);
    assert_or_panic(vec[213] == false);
    assert_or_panic(vec[214] == true);
    assert_or_panic(vec[215] == true);
    assert_or_panic(vec[216] == true);
    assert_or_panic(vec[217] == false);
    assert_or_panic(vec[218] == false);
    assert_or_panic(vec[219] == true);
    assert_or_panic(vec[220] == false);
    assert_or_panic(vec[221] == true);
    assert_or_panic(vec[222] == true);
    assert_or_panic(vec[223] == false);
    assert_or_panic(vec[224] == true);
    assert_or_panic(vec[225] == false);
    assert_or_panic(vec[226] == false);
    assert_or_panic(vec[227] == true);
    assert_or_panic(vec[228] == false);
    assert_or_panic(vec[229] == false);
    assert_or_panic(vec[230] == true);
    assert_or_panic(vec[231] == true);
    assert_or_panic(vec[232] == false);
    assert_or_panic(vec[233] == true);
    assert_or_panic(vec[234] == true);
    assert_or_panic(vec[235] == true);
    assert_or_panic(vec[236] == true);
    assert_or_panic(vec[237] == true);
    assert_or_panic(vec[238] == false);
    assert_or_panic(vec[239] == true);
    assert_or_panic(vec[240] == false);
    assert_or_panic(vec[241] == false);
    assert_or_panic(vec[242] == true);
    assert_or_panic(vec[243] == false);
    assert_or_panic(vec[244] == true);
    assert_or_panic(vec[245] == false);
    assert_or_panic(vec[246] == true);
    assert_or_panic(vec[247] == false);
    assert_or_panic(vec[248] == true);
    assert_or_panic(vec[249] == true);
    assert_or_panic(vec[250] == true);
    assert_or_panic(vec[251] == true);
    assert_or_panic(vec[252] == true);
    assert_or_panic(vec[253] == false);
    assert_or_panic(vec[254] == false);
    assert_or_panic(vec[255] == false);
    assert_or_panic(vec[256] == false);
    assert_or_panic(vec[257] == false);
    assert_or_panic(vec[258] == false);
    assert_or_panic(vec[259] == true);
    assert_or_panic(vec[260] == true);
    assert_or_panic(vec[261] == true);
    assert_or_panic(vec[262] == true);
    assert_or_panic(vec[263] == false);
    assert_or_panic(vec[264] == false);
    assert_or_panic(vec[265] == false);
    assert_or_panic(vec[266] == true);
    assert_or_panic(vec[267] == false);
    assert_or_panic(vec[268] == true);
    assert_or_panic(vec[269] == false);
    assert_or_panic(vec[270] == true);
    assert_or_panic(vec[271] == true);
    assert_or_panic(vec[272] == true);
    assert_or_panic(vec[273] == true);
    assert_or_panic(vec[274] == true);
    assert_or_panic(vec[275] == true);
    assert_or_panic(vec[276] == false);
    assert_or_panic(vec[277] == false);
    assert_or_panic(vec[278] == true);
    assert_or_panic(vec[279] == true);
    assert_or_panic(vec[280] == false);
    assert_or_panic(vec[281] == false);
    assert_or_panic(vec[282] == false);
    assert_or_panic(vec[283] == false);
    assert_or_panic(vec[284] == true);
    assert_or_panic(vec[285] == true);
    assert_or_panic(vec[286] == true);
    assert_or_panic(vec[287] == false);
    assert_or_panic(vec[288] == false);
    assert_or_panic(vec[289] == false);
    assert_or_panic(vec[290] == true);
    assert_or_panic(vec[291] == false);
    assert_or_panic(vec[292] == true);
    assert_or_panic(vec[293] == true);
    assert_or_panic(vec[294] == false);
    assert_or_panic(vec[295] == true);
    assert_or_panic(vec[296] == true);
    assert_or_panic(vec[297] == true);
    assert_or_panic(vec[298] == false);
    assert_or_panic(vec[299] == true);
    assert_or_panic(vec[300] == true);
    assert_or_panic(vec[301] == false);
    assert_or_panic(vec[302] == false);
    assert_or_panic(vec[303] == true);
    assert_or_panic(vec[304] == false);
    assert_or_panic(vec[305] == false);
    assert_or_panic(vec[306] == true);
    assert_or_panic(vec[307] == true);
    assert_or_panic(vec[308] == true);
    assert_or_panic(vec[309] == true);
    assert_or_panic(vec[310] == false);
    assert_or_panic(vec[311] == false);
    assert_or_panic(vec[312] == false);
    assert_or_panic(vec[313] == false);
    assert_or_panic(vec[314] == false);
    assert_or_panic(vec[315] == true);
    assert_or_panic(vec[316] == false);
    assert_or_panic(vec[317] == false);
    assert_or_panic(vec[318] == true);
    assert_or_panic(vec[319] == false);
    assert_or_panic(vec[320] == false);
    assert_or_panic(vec[321] == true);
    assert_or_panic(vec[322] == true);
    assert_or_panic(vec[323] == true);
    assert_or_panic(vec[324] == true);
    assert_or_panic(vec[325] == false);
    assert_or_panic(vec[326] == false);
    assert_or_panic(vec[327] == false);
    assert_or_panic(vec[328] == true);
    assert_or_panic(vec[329] == true);
    assert_or_panic(vec[330] == false);
    assert_or_panic(vec[331] == true);
    assert_or_panic(vec[332] == true);
    assert_or_panic(vec[333] == false);
    assert_or_panic(vec[334] == false);
    assert_or_panic(vec[335] == true);
    assert_or_panic(vec[336] == true);
    assert_or_panic(vec[337] == false);
    assert_or_panic(vec[338] == true);
    assert_or_panic(vec[339] == true);
    assert_or_panic(vec[340] == true);
    assert_or_panic(vec[341] == false);
    assert_or_panic(vec[342] == false);
    assert_or_panic(vec[343] == false);
    assert_or_panic(vec[344] == true);
    assert_or_panic(vec[345] == true);
    assert_or_panic(vec[346] == false);
    assert_or_panic(vec[347] == true);
    assert_or_panic(vec[348] == false);
    assert_or_panic(vec[349] == true);
    assert_or_panic(vec[350] == false);
    assert_or_panic(vec[351] == false);
    assert_or_panic(vec[352] == true);
    assert_or_panic(vec[353] == false);
    assert_or_panic(vec[354] == true);
    assert_or_panic(vec[355] == false);
    assert_or_panic(vec[356] == false);
    assert_or_panic(vec[357] == false);
    assert_or_panic(vec[358] == false);
    assert_or_panic(vec[359] == false);
    assert_or_panic(vec[360] == true);
    assert_or_panic(vec[361] == true);
    assert_or_panic(vec[362] == false);
    assert_or_panic(vec[363] == false);
    assert_or_panic(vec[364] == false);
    assert_or_panic(vec[365] == false);
    assert_or_panic(vec[366] == true);
    assert_or_panic(vec[367] == false);
    assert_or_panic(vec[368] == true);
    assert_or_panic(vec[369] == false);
    assert_or_panic(vec[370] == true);
    assert_or_panic(vec[371] == true);
    assert_or_panic(vec[372] == false);
    assert_or_panic(vec[373] == true);
    assert_or_panic(vec[374] == true);
    assert_or_panic(vec[375] == true);
    assert_or_panic(vec[376] == true);
    assert_or_panic(vec[377] == true);
    assert_or_panic(vec[378] == false);
    assert_or_panic(vec[379] == true);
    assert_or_panic(vec[380] == false);
    assert_or_panic(vec[381] == true);
    assert_or_panic(vec[382] == true);
    assert_or_panic(vec[383] == true);
    assert_or_panic(vec[384] == true);
    assert_or_panic(vec[385] == true);
    assert_or_panic(vec[386] == false);
    assert_or_panic(vec[387] == true);
    assert_or_panic(vec[388] == true);
    assert_or_panic(vec[389] == false);
    assert_or_panic(vec[390] == true);
    assert_or_panic(vec[391] == false);
    assert_or_panic(vec[392] == true);
    assert_or_panic(vec[393] == false);
    assert_or_panic(vec[394] == true);
    assert_or_panic(vec[395] == false);
    assert_or_panic(vec[396] == true);
    assert_or_panic(vec[397] == false);
    assert_or_panic(vec[398] == false);
    assert_or_panic(vec[399] == true);
    assert_or_panic(vec[400] == true);
    assert_or_panic(vec[401] == true);
    assert_or_panic(vec[402] == true);
    assert_or_panic(vec[403] == false);
    assert_or_panic(vec[404] == false);
    assert_or_panic(vec[405] == true);
    assert_or_panic(vec[406] == false);
    assert_or_panic(vec[407] == false);
    assert_or_panic(vec[408] == false);
    assert_or_panic(vec[409] == true);
    assert_or_panic(vec[410] == false);
    assert_or_panic(vec[411] == true);
    assert_or_panic(vec[412] == true);
    assert_or_panic(vec[413] == false);
    assert_or_panic(vec[414] == true);
    assert_or_panic(vec[415] == true);
    assert_or_panic(vec[416] == false);
    assert_or_panic(vec[417] == true);
    assert_or_panic(vec[418] == true);
    assert_or_panic(vec[419] == false);
    assert_or_panic(vec[420] == false);
    assert_or_panic(vec[421] == true);
    assert_or_panic(vec[422] == false);
    assert_or_panic(vec[423] == false);
    assert_or_panic(vec[424] == true);
    assert_or_panic(vec[425] == false);
    assert_or_panic(vec[426] == true);
    assert_or_panic(vec[427] == false);
    assert_or_panic(vec[428] == false);
    assert_or_panic(vec[429] == true);
    assert_or_panic(vec[430] == false);
    assert_or_panic(vec[431] == true);
    assert_or_panic(vec[432] == true);
    assert_or_panic(vec[433] == false);
    assert_or_panic(vec[434] == true);
    assert_or_panic(vec[435] == false);
    assert_or_panic(vec[436] == true);
    assert_or_panic(vec[437] == false);
    assert_or_panic(vec[438] == true);
    assert_or_panic(vec[439] == false);
    assert_or_panic(vec[440] == false);
    assert_or_panic(vec[441] == true);
    assert_or_panic(vec[442] == true);
    assert_or_panic(vec[443] == false);
    assert_or_panic(vec[444] == true);
    assert_or_panic(vec[445] == true);
    assert_or_panic(vec[446] == false);
    assert_or_panic(vec[447] == true);
    assert_or_panic(vec[448] == true);
    assert_or_panic(vec[449] == false);
    assert_or_panic(vec[450] == false);
    assert_or_panic(vec[451] == false);
    assert_or_panic(vec[452] == false);
    assert_or_panic(vec[453] == false);
    assert_or_panic(vec[454] == true);
    assert_or_panic(vec[455] == false);
    assert_or_panic(vec[456] == false);
    assert_or_panic(vec[457] == true);
    assert_or_panic(vec[458] == false);
    assert_or_panic(vec[459] == true);
    assert_or_panic(vec[460] == false);
    assert_or_panic(vec[461] == false);
    assert_or_panic(vec[462] == false);
    assert_or_panic(vec[463] == true);
    assert_or_panic(vec[464] == false);
    assert_or_panic(vec[465] == true);
    assert_or_panic(vec[466] == false);
    assert_or_panic(vec[467] == false);
    assert_or_panic(vec[468] == false);
    assert_or_panic(vec[469] == false);
    assert_or_panic(vec[470] == true);
    assert_or_panic(vec[471] == true);
    assert_or_panic(vec[472] == false);
    assert_or_panic(vec[473] == true);
    assert_or_panic(vec[474] == true);
    assert_or_panic(vec[475] == false);
    assert_or_panic(vec[476] == false);
    assert_or_panic(vec[477] == true);
    assert_or_panic(vec[478] == true);
    assert_or_panic(vec[479] == true);
    assert_or_panic(vec[480] == false);
    assert_or_panic(vec[481] == false);
    assert_or_panic(vec[482] == true);
    assert_or_panic(vec[483] == false);
    assert_or_panic(vec[484] == false);
    assert_or_panic(vec[485] == false);
    assert_or_panic(vec[486] == true);
    assert_or_panic(vec[487] == true);
    assert_or_panic(vec[488] == false);
    assert_or_panic(vec[489] == false);
    assert_or_panic(vec[490] == false);
    assert_or_panic(vec[491] == false);
    assert_or_panic(vec[492] == false);
    assert_or_panic(vec[493] == true);
    assert_or_panic(vec[494] == true);
    assert_or_panic(vec[495] == true);
    assert_or_panic(vec[496] == true);
    assert_or_panic(vec[497] == false);
    assert_or_panic(vec[498] == false);
    assert_or_panic(vec[499] == false);
    assert_or_panic(vec[500] == true);
    assert_or_panic(vec[501] == false);
    assert_or_panic(vec[502] == true);
    assert_or_panic(vec[503] == true);
    assert_or_panic(vec[504] == true);
    assert_or_panic(vec[505] == true);
    assert_or_panic(vec[506] == false);
    assert_or_panic(vec[507] == false);
    assert_or_panic(vec[508] == true);
    assert_or_panic(vec[509] == true);
    assert_or_panic(vec[510] == false);
    assert_or_panic(vec[511] == false);
    zig_vector_512_bool((Vector_512_bool){
        false,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
        false,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        false,
        true,
        true,
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        false,
        true,
        true,
        true,
        true,
        true,
        false,
        true,
        true,
        true,
        false,
        true,
        false,
        false,
        true,
        false,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        false,
        false,
        true,
        true,
        false,
        true,
        true,
        false,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        false,
        false,
        true,
        false,
        true,
        false,
        false,
        true,
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        false,
        true,
        true,
        false,
        true,
        true,
        false,
        false,
        true,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        false,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        true,
        true,
        false,
        true,
        true,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        false,
        true,
        true,
        false,
        false,
        true,
        false,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        false,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        true,
        false,
        false,
        true,
        true,
        true,
        false,
        false,
        true,
        false,
        true,
        true,
        true,
        true,
        false,
        true,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        false,
        true,
        true,
        false,
        false,
        false,
        true,
        false,
        false,
        true,
        true,
        false,
        true,
        false,
        true,
        true,
        false,
        false,
        false,
        false,
        true,
        false,
        true,
        true,
        false,
        false,
        true,
        true,
        true,
        false,
        true,
        false,
        false,
        true,
        true,
        false,
        true,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        true,
        false,
        true,
        true,
        true,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        false,
        true,
        false,
        false,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        true,
        true,
        false,
        true,
        true,
        false,
        true,
        true,
        false,
        true,
        true,
        false,
        true,
        true,
        false,
        true,
        false,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        false,
        true,
        true,
        true,
        false,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        false,
        true,
        false,
        false,
        false,
        true,
        false,
        false,
        true,
        true,
        true,
        true,
        false,
        true,
        true,
        false,
        false,
        false,
        true,
        false,
        true,
        true,
        false,
        false,
        false,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
        false,
        true,
        false,
        false,
        true,
        true,
        true,
        false,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        false,
        true,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        false,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        false,
        false,
        true,
    });
}

#endif

typedef uint8_t Vector_1_u8 __attribute__((vector_size(1 * sizeof(uint8_t))));

Vector_1_u8 zig_ret_vector_1_u8(void);
void zig_vector_1_u8(Vector_1_u8, size_t);

Vector_1_u8 c_ret_vector_1_u8(void) {
    return (Vector_1_u8){ 3 };
}
void c_vector_1_u8(Vector_1_u8 v, size_t i) {
    assert_or_panic(v[0] == 4);
    assert_or_panic(i == 1);
}
void c_test_vector_1_u8(void) {
    Vector_1_u8 v = zig_ret_vector_1_u8();
    assert_or_panic(v[0] == 1);
    zig_vector_1_u8((Vector_1_u8){ 2 }, 1);
}

typedef uint8_t Vector_2_u8 __attribute__((vector_size(2 * sizeof(uint8_t))));

Vector_2_u8 zig_ret_vector_2_u8(void);
void zig_vector_2_u8(Vector_2_u8, size_t);

Vector_2_u8 c_ret_vector_2_u8(void) {
    return (Vector_2_u8){ 9, 10 };
}
void c_vector_2_u8(Vector_2_u8 v, size_t i) {
    assert_or_panic(v[0] == 11);
    assert_or_panic(v[1] == 12);
    assert_or_panic(i == 2);
}
void c_test_vector_2_u8(void) {
    Vector_2_u8 v = zig_ret_vector_2_u8();
    assert_or_panic(v[0] == 5);
    assert_or_panic(v[1] == 6);
    zig_vector_2_u8((Vector_2_u8){ 7, 8 }, 2);
}

typedef uint8_t Vector_3_u8 __attribute__((vector_size(3 * sizeof(uint8_t))));

Vector_3_u8 zig_ret_vector_3_u8(void);
void zig_vector_3_u8(Vector_3_u8, size_t);

Vector_3_u8 c_ret_vector_3_u8(void) {
    return (Vector_3_u8){ 19, 20, 21 };
}
void c_vector_3_u8(Vector_3_u8 v, size_t i) {
    assert_or_panic(v[0] == 22);
    assert_or_panic(v[1] == 23);
    assert_or_panic(v[2] == 24);
    assert_or_panic(i == 3);
}
void c_test_vector_3_u8(void) {
    Vector_3_u8 v = zig_ret_vector_3_u8();
    assert_or_panic(v[0] == 13);
    assert_or_panic(v[1] == 14);
    assert_or_panic(v[2] == 15);
    zig_vector_3_u8((Vector_3_u8){ 16, 17, 18 }, 3);
}

typedef uint8_t Vector_4_u8 __attribute__((vector_size(4 * sizeof(uint8_t))));

Vector_4_u8 zig_ret_vector_4_u8(void);
void zig_vector_4_u8(Vector_4_u8, size_t);
void zig_vector_4_u8_vector_4_u8(Vector_4_u8, Vector_4_u8, size_t);

Vector_4_u8 c_ret_vector_4_u8(void) {
    return (Vector_4_u8){ 41, 42, 43, 44 };
}
void c_vector_4_u8(Vector_4_u8 v, size_t i) {
    assert_or_panic(v[0] == 45);
    assert_or_panic(v[1] == 46);
    assert_or_panic(v[2] == 47);
    assert_or_panic(v[3] == 48);
    assert_or_panic(i == 4);
}
void c_vector_4_u8_vector_4_u8(Vector_4_u8 v0, Vector_4_u8 v1, size_t i) {
    assert_or_panic(v0[0] == 49);
    assert_or_panic(v0[1] == 50);
    assert_or_panic(v0[2] == 51);
    assert_or_panic(v0[3] == 52);
    assert_or_panic(v1[0] == 53);
    assert_or_panic(v1[1] == 54);
    assert_or_panic(v1[2] == 55);
    assert_or_panic(v1[3] == 56);
    assert_or_panic(i == 8);
}
void c_test_vector_4_u8(void) {
    Vector_4_u8 v = zig_ret_vector_4_u8();
    assert_or_panic(v[0] == 25);
    assert_or_panic(v[1] == 26);
    assert_or_panic(v[2] == 27);
    assert_or_panic(v[3] == 28);
    zig_vector_4_u8((Vector_4_u8){ 29, 30, 31, 32 }, 4);
    zig_vector_4_u8_vector_4_u8((Vector_4_u8){ 33, 34, 35, 36 }, (Vector_4_u8){ 37, 38, 39, 40 }, 8);
}

typedef uint8_t Vector_6_u8 __attribute__((vector_size(6 * sizeof(uint8_t))));

Vector_6_u8 zig_ret_vector_6_u8(void);
void zig_vector_6_u8(Vector_6_u8, size_t);

Vector_6_u8 c_ret_vector_6_u8(void) {
    return (Vector_6_u8){ 53, 54, 55, 56, 57, 58 };
}
void c_vector_6_u8(Vector_6_u8 v, size_t i) {
    assert_or_panic(v[0] == 59);
    assert_or_panic(v[1] == 60);
    assert_or_panic(v[2] == 61);
    assert_or_panic(v[3] == 62);
    assert_or_panic(v[4] == 63);
    assert_or_panic(v[5] == 64);
    assert_or_panic(i == 6);
}
void c_test_vector_6_u8(void) {
    Vector_6_u8 v = zig_ret_vector_6_u8();
    assert_or_panic(v[0] == 41);
    assert_or_panic(v[1] == 42);
    assert_or_panic(v[2] == 43);
    assert_or_panic(v[3] == 44);
    assert_or_panic(v[4] == 45);
    assert_or_panic(v[5] == 46);
    zig_vector_6_u8((Vector_6_u8){ 47, 48, 49, 50, 51, 52 }, 6);
}

typedef uint8_t Vector_8_u8 __attribute__((vector_size(8 * sizeof(uint8_t))));

Vector_8_u8 zig_ret_vector_8_u8(void);
void zig_vector_8_u8(Vector_8_u8, size_t);

Vector_8_u8 c_ret_vector_8_u8(void) {
    return (Vector_8_u8){ 81, 82, 83, 84, 85, 86, 87, 88 };
}
void c_vector_8_u8(Vector_8_u8 v, size_t i) {
    assert_or_panic(v[0] == 89);
    assert_or_panic(v[1] == 90);
    assert_or_panic(v[2] == 91);
    assert_or_panic(v[3] == 92);
    assert_or_panic(v[4] == 93);
    assert_or_panic(v[5] == 94);
    assert_or_panic(v[6] == 95);
    assert_or_panic(v[7] == 96);
    assert_or_panic(i == 8);
}
void c_test_vector_8_u8(void) {
    Vector_8_u8 v = zig_ret_vector_8_u8();
    assert_or_panic(v[0] == 65);
    assert_or_panic(v[1] == 66);
    assert_or_panic(v[2] == 67);
    assert_or_panic(v[3] == 68);
    assert_or_panic(v[4] == 69);
    assert_or_panic(v[5] == 70);
    assert_or_panic(v[6] == 71);
    assert_or_panic(v[7] == 72);
    zig_vector_8_u8((Vector_8_u8){ 73, 74, 75, 76, 77, 78, 79, 80 }, 8);
}

typedef uint8_t Vector_12_u8 __attribute__((vector_size(12 * sizeof(uint8_t))));

Vector_12_u8 zig_ret_vector_12_u8(void);
void zig_vector_12_u8(Vector_12_u8, size_t);

Vector_12_u8 c_ret_vector_12_u8(void) {
    return (Vector_12_u8){ 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32 };
}
void c_vector_12_u8(Vector_12_u8 v, size_t i) {
    assert_or_panic(v[0] == 33);
    assert_or_panic(v[1] == 34);
    assert_or_panic(v[2] == 35);
    assert_or_panic(v[3] == 36);
    assert_or_panic(v[4] == 37);
    assert_or_panic(v[5] == 38);
    assert_or_panic(v[6] == 39);
    assert_or_panic(v[7] == 40);
    assert_or_panic(v[8] == 41);
    assert_or_panic(v[9] == 42);
    assert_or_panic(v[10] == 43);
    assert_or_panic(v[11] == 44);
    assert_or_panic(i == 12);
}
void c_test_vector_12_u8(void) {
    Vector_12_u8 v = zig_ret_vector_12_u8();
    assert_or_panic(v[0] == 97);
    assert_or_panic(v[1] == 98);
    assert_or_panic(v[2] == 99);
    assert_or_panic(v[3] == 0);
    assert_or_panic(v[4] == 1);
    assert_or_panic(v[5] == 2);
    assert_or_panic(v[6] == 3);
    assert_or_panic(v[7] == 4);
    assert_or_panic(v[8] == 5);
    assert_or_panic(v[9] == 6);
    assert_or_panic(v[10] == 7);
    assert_or_panic(v[11] == 8);
    zig_vector_12_u8((Vector_12_u8){ 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 }, 12);
}

typedef uint8_t Vector_16_u8 __attribute__((vector_size(16 * sizeof(uint8_t))));

Vector_16_u8 zig_ret_vector_16_u8(void);
void zig_vector_16_u8(Vector_16_u8, size_t);

Vector_16_u8 c_ret_vector_16_u8(void) {
    return (Vector_16_u8){ 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92 };
}
void c_vector_16_u8(Vector_16_u8 v, size_t i) {
    assert_or_panic(v[0] == 93);
    assert_or_panic(v[1] == 94);
    assert_or_panic(v[2] == 95);
    assert_or_panic(v[3] == 96);
    assert_or_panic(v[4] == 97);
    assert_or_panic(v[5] == 98);
    assert_or_panic(v[6] == 99);
    assert_or_panic(v[7] == 0);
    assert_or_panic(v[8] == 1);
    assert_or_panic(v[9] == 2);
    assert_or_panic(v[10] == 3);
    assert_or_panic(v[11] == 4);
    assert_or_panic(v[12] == 5);
    assert_or_panic(v[13] == 6);
    assert_or_panic(v[14] == 7);
    assert_or_panic(v[15] == 8);
    assert_or_panic(i == 16);
}
void c_test_vector_16_u8(void) {
    Vector_16_u8 v = zig_ret_vector_16_u8();
    assert_or_panic(v[0] == 45);
    assert_or_panic(v[1] == 46);
    assert_or_panic(v[2] == 47);
    assert_or_panic(v[3] == 48);
    assert_or_panic(v[4] == 49);
    assert_or_panic(v[5] == 50);
    assert_or_panic(v[6] == 51);
    assert_or_panic(v[7] == 52);
    assert_or_panic(v[8] == 53);
    assert_or_panic(v[9] == 54);
    assert_or_panic(v[10] == 55);
    assert_or_panic(v[11] == 56);
    assert_or_panic(v[12] == 57);
    assert_or_panic(v[13] == 58);
    assert_or_panic(v[14] == 59);
    assert_or_panic(v[15] == 60);
    zig_vector_16_u8((Vector_16_u8){ 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76 }, 16);
}

typedef uint8_t Vector_24_u8 __attribute__((vector_size(24 * sizeof(uint8_t))));

Vector_24_u8 zig_ret_vector_24_u8(void);
void zig_vector_24_u8(Vector_24_u8, size_t);

Vector_24_u8 c_ret_vector_24_u8(void) {
    return (Vector_24_u8){
        57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72,
        73, 74, 75, 76, 77, 78, 79, 80,
    };
}
void c_vector_24_u8(Vector_24_u8 v, size_t i) {
    assert_or_panic(v[0] == 81);
    assert_or_panic(v[1] == 82);
    assert_or_panic(v[2] == 83);
    assert_or_panic(v[3] == 84);
    assert_or_panic(v[4] == 85);
    assert_or_panic(v[5] == 86);
    assert_or_panic(v[6] == 87);
    assert_or_panic(v[7] == 88);
    assert_or_panic(v[8] == 89);
    assert_or_panic(v[9] == 90);
    assert_or_panic(v[10] == 91);
    assert_or_panic(v[11] == 92);
    assert_or_panic(v[12] == 93);
    assert_or_panic(v[13] == 94);
    assert_or_panic(v[14] == 95);
    assert_or_panic(v[15] == 96);
    assert_or_panic(v[16] == 97);
    assert_or_panic(v[17] == 98);
    assert_or_panic(v[18] == 99);
    assert_or_panic(v[19] == 0);
    assert_or_panic(v[20] == 1);
    assert_or_panic(v[21] == 2);
    assert_or_panic(v[22] == 3);
    assert_or_panic(v[23] == 4);
    assert_or_panic(i == 24);
}
void c_test_vector_24_u8(void) {
    Vector_24_u8 v = zig_ret_vector_24_u8();
    assert_or_panic(v[0] == 9);
    assert_or_panic(v[1] == 10);
    assert_or_panic(v[2] == 11);
    assert_or_panic(v[3] == 12);
    assert_or_panic(v[4] == 13);
    assert_or_panic(v[5] == 14);
    assert_or_panic(v[6] == 15);
    assert_or_panic(v[7] == 16);
    assert_or_panic(v[8] == 17);
    assert_or_panic(v[9] == 18);
    assert_or_panic(v[10] == 19);
    assert_or_panic(v[11] == 20);
    assert_or_panic(v[12] == 21);
    assert_or_panic(v[13] == 22);
    assert_or_panic(v[14] == 23);
    assert_or_panic(v[15] == 24);
    assert_or_panic(v[16] == 25);
    assert_or_panic(v[17] == 26);
    assert_or_panic(v[18] == 27);
    assert_or_panic(v[19] == 28);
    assert_or_panic(v[20] == 29);
    assert_or_panic(v[21] == 30);
    assert_or_panic(v[22] == 31);
    assert_or_panic(v[23] == 32);
    zig_vector_24_u8((Vector_24_u8){
        33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48,
        49, 50, 51, 52, 53, 54, 55, 56,
    }, 24);
}

typedef uint8_t Vector_32_u8 __attribute__((vector_size(32 * sizeof(uint8_t))));

Vector_32_u8 zig_ret_vector_32_u8(void);
void zig_vector_32_u8(Vector_32_u8, size_t);

Vector_32_u8 c_ret_vector_32_u8(void) {
    return (Vector_32_u8){
        69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84,
        85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,
    };
}
void c_vector_32_u8(Vector_32_u8 v, size_t i) {
    assert_or_panic(v[0] == 1);
    assert_or_panic(v[1] == 2);
    assert_or_panic(v[2] == 3);
    assert_or_panic(v[3] == 4);
    assert_or_panic(v[4] == 5);
    assert_or_panic(v[5] == 6);
    assert_or_panic(v[6] == 7);
    assert_or_panic(v[7] == 8);
    assert_or_panic(v[8] == 9);
    assert_or_panic(v[9] == 10);
    assert_or_panic(v[10] == 11);
    assert_or_panic(v[11] == 12);
    assert_or_panic(v[12] == 13);
    assert_or_panic(v[13] == 14);
    assert_or_panic(v[14] == 15);
    assert_or_panic(v[15] == 16);
    assert_or_panic(v[16] == 17);
    assert_or_panic(v[17] == 18);
    assert_or_panic(v[18] == 19);
    assert_or_panic(v[19] == 20);
    assert_or_panic(v[20] == 21);
    assert_or_panic(v[21] == 22);
    assert_or_panic(v[22] == 23);
    assert_or_panic(v[23] == 24);
    assert_or_panic(v[24] == 25);
    assert_or_panic(v[25] == 26);
    assert_or_panic(v[26] == 27);
    assert_or_panic(v[27] == 28);
    assert_or_panic(v[28] == 29);
    assert_or_panic(v[29] == 30);
    assert_or_panic(v[30] == 31);
    assert_or_panic(v[31] == 32);
    assert_or_panic(i == 32);
}
void c_test_vector_32_u8(void) {
    Vector_32_u8 v = zig_ret_vector_32_u8();
    assert_or_panic(v[0] == 5);
    assert_or_panic(v[1] == 6);
    assert_or_panic(v[2] == 7);
    assert_or_panic(v[3] == 8);
    assert_or_panic(v[4] == 9);
    assert_or_panic(v[5] == 10);
    assert_or_panic(v[6] == 11);
    assert_or_panic(v[7] == 12);
    assert_or_panic(v[8] == 13);
    assert_or_panic(v[9] == 14);
    assert_or_panic(v[10] == 15);
    assert_or_panic(v[11] == 16);
    assert_or_panic(v[12] == 17);
    assert_or_panic(v[13] == 18);
    assert_or_panic(v[14] == 19);
    assert_or_panic(v[15] == 20);
    assert_or_panic(v[16] == 21);
    assert_or_panic(v[17] == 22);
    assert_or_panic(v[18] == 23);
    assert_or_panic(v[19] == 24);
    assert_or_panic(v[20] == 25);
    assert_or_panic(v[21] == 26);
    assert_or_panic(v[22] == 27);
    assert_or_panic(v[23] == 28);
    assert_or_panic(v[24] == 29);
    assert_or_panic(v[25] == 30);
    assert_or_panic(v[26] == 31);
    assert_or_panic(v[27] == 32);
    assert_or_panic(v[28] == 33);
    assert_or_panic(v[29] == 34);
    assert_or_panic(v[30] == 35);
    assert_or_panic(v[31] == 36);
    zig_vector_32_u8((Vector_32_u8){
        37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52,
        53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68,
    }, 32);
}

typedef uint8_t Vector_48_u8 __attribute__((vector_size(48 * sizeof(uint8_t))));

Vector_48_u8 zig_ret_vector_48_u8(void);
void zig_vector_48_u8(Vector_48_u8, size_t);

Vector_48_u8 c_ret_vector_48_u8(void) {
    return (Vector_48_u8){
        29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44,
        45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60,
        61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76,
    };
}
void c_vector_48_u8(Vector_48_u8 v, size_t i) {
    assert_or_panic(v[0] == 77);
    assert_or_panic(v[1] == 78);
    assert_or_panic(v[2] == 79);
    assert_or_panic(v[3] == 80);
    assert_or_panic(v[4] == 81);
    assert_or_panic(v[5] == 82);
    assert_or_panic(v[6] == 83);
    assert_or_panic(v[7] == 84);
    assert_or_panic(v[8] == 85);
    assert_or_panic(v[9] == 86);
    assert_or_panic(v[10] == 87);
    assert_or_panic(v[11] == 88);
    assert_or_panic(v[12] == 89);
    assert_or_panic(v[13] == 90);
    assert_or_panic(v[14] == 91);
    assert_or_panic(v[15] == 92);
    assert_or_panic(v[16] == 93);
    assert_or_panic(v[17] == 94);
    assert_or_panic(v[18] == 95);
    assert_or_panic(v[19] == 96);
    assert_or_panic(v[20] == 97);
    assert_or_panic(v[21] == 98);
    assert_or_panic(v[22] == 99);
    assert_or_panic(v[23] == 0);
    assert_or_panic(v[24] == 1);
    assert_or_panic(v[25] == 2);
    assert_or_panic(v[26] == 3);
    assert_or_panic(v[27] == 4);
    assert_or_panic(v[28] == 5);
    assert_or_panic(v[29] == 6);
    assert_or_panic(v[30] == 7);
    assert_or_panic(v[31] == 8);
    assert_or_panic(v[32] == 9);
    assert_or_panic(v[33] == 10);
    assert_or_panic(v[34] == 11);
    assert_or_panic(v[35] == 12);
    assert_or_panic(v[36] == 13);
    assert_or_panic(v[37] == 14);
    assert_or_panic(v[38] == 15);
    assert_or_panic(v[39] == 16);
    assert_or_panic(v[40] == 17);
    assert_or_panic(v[41] == 18);
    assert_or_panic(v[42] == 19);
    assert_or_panic(v[43] == 20);
    assert_or_panic(v[44] == 21);
    assert_or_panic(v[45] == 22);
    assert_or_panic(v[46] == 23);
    assert_or_panic(v[47] == 24);
    assert_or_panic(i == 48);
}
void c_test_vector_48_u8(void) {
    Vector_48_u8 v = zig_ret_vector_48_u8();
    assert_or_panic(v[0] == 33);
    assert_or_panic(v[1] == 34);
    assert_or_panic(v[2] == 35);
    assert_or_panic(v[3] == 36);
    assert_or_panic(v[4] == 37);
    assert_or_panic(v[5] == 38);
    assert_or_panic(v[6] == 39);
    assert_or_panic(v[7] == 40);
    assert_or_panic(v[8] == 41);
    assert_or_panic(v[9] == 42);
    assert_or_panic(v[10] == 43);
    assert_or_panic(v[11] == 44);
    assert_or_panic(v[12] == 45);
    assert_or_panic(v[13] == 46);
    assert_or_panic(v[14] == 47);
    assert_or_panic(v[15] == 48);
    assert_or_panic(v[16] == 49);
    assert_or_panic(v[17] == 50);
    assert_or_panic(v[18] == 51);
    assert_or_panic(v[19] == 52);
    assert_or_panic(v[20] == 53);
    assert_or_panic(v[21] == 54);
    assert_or_panic(v[22] == 55);
    assert_or_panic(v[23] == 56);
    assert_or_panic(v[24] == 57);
    assert_or_panic(v[25] == 58);
    assert_or_panic(v[26] == 59);
    assert_or_panic(v[27] == 60);
    assert_or_panic(v[28] == 61);
    assert_or_panic(v[29] == 62);
    assert_or_panic(v[30] == 63);
    assert_or_panic(v[31] == 64);
    assert_or_panic(v[32] == 65);
    assert_or_panic(v[33] == 66);
    assert_or_panic(v[34] == 67);
    assert_or_panic(v[35] == 68);
    assert_or_panic(v[36] == 69);
    assert_or_panic(v[37] == 70);
    assert_or_panic(v[38] == 71);
    assert_or_panic(v[39] == 72);
    assert_or_panic(v[40] == 73);
    assert_or_panic(v[41] == 74);
    assert_or_panic(v[42] == 75);
    assert_or_panic(v[43] == 76);
    assert_or_panic(v[44] == 77);
    assert_or_panic(v[45] == 78);
    assert_or_panic(v[46] == 79);
    assert_or_panic(v[47] == 80);
    zig_vector_48_u8((Vector_48_u8){
        81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96,
        97, 98, 99, 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12,
        13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28,
    }, 48);
}

typedef uint8_t Vector_64_u8 __attribute__((vector_size(64 * sizeof(uint8_t))));

Vector_64_u8 zig_ret_vector_64_u8(void);
void zig_vector_64_u8(Vector_64_u8, size_t);

Vector_64_u8 c_ret_vector_64_u8(void) {
    return (Vector_64_u8){
        53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68,
        69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84,
        85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,
        1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16,
    };
}
void c_vector_64_u8(Vector_64_u8 v, size_t i) {
    assert_or_panic(v[0] == 17);
    assert_or_panic(v[1] == 18);
    assert_or_panic(v[2] == 19);
    assert_or_panic(v[3] == 20);
    assert_or_panic(v[4] == 21);
    assert_or_panic(v[5] == 22);
    assert_or_panic(v[6] == 23);
    assert_or_panic(v[7] == 24);
    assert_or_panic(v[8] == 25);
    assert_or_panic(v[9] == 26);
    assert_or_panic(v[10] == 27);
    assert_or_panic(v[11] == 28);
    assert_or_panic(v[12] == 29);
    assert_or_panic(v[13] == 30);
    assert_or_panic(v[14] == 31);
    assert_or_panic(v[15] == 32);
    assert_or_panic(v[16] == 33);
    assert_or_panic(v[17] == 34);
    assert_or_panic(v[18] == 35);
    assert_or_panic(v[19] == 36);
    assert_or_panic(v[20] == 37);
    assert_or_panic(v[21] == 38);
    assert_or_panic(v[22] == 39);
    assert_or_panic(v[23] == 40);
    assert_or_panic(v[24] == 41);
    assert_or_panic(v[25] == 42);
    assert_or_panic(v[26] == 43);
    assert_or_panic(v[27] == 44);
    assert_or_panic(v[28] == 45);
    assert_or_panic(v[29] == 46);
    assert_or_panic(v[30] == 47);
    assert_or_panic(v[31] == 48);
    assert_or_panic(v[32] == 49);
    assert_or_panic(v[33] == 50);
    assert_or_panic(v[34] == 51);
    assert_or_panic(v[35] == 52);
    assert_or_panic(v[36] == 53);
    assert_or_panic(v[37] == 54);
    assert_or_panic(v[38] == 55);
    assert_or_panic(v[39] == 56);
    assert_or_panic(v[40] == 57);
    assert_or_panic(v[41] == 58);
    assert_or_panic(v[42] == 59);
    assert_or_panic(v[43] == 60);
    assert_or_panic(v[44] == 61);
    assert_or_panic(v[45] == 62);
    assert_or_panic(v[46] == 63);
    assert_or_panic(v[47] == 64);
    assert_or_panic(v[48] == 65);
    assert_or_panic(v[49] == 66);
    assert_or_panic(v[50] == 67);
    assert_or_panic(v[51] == 68);
    assert_or_panic(v[52] == 69);
    assert_or_panic(v[53] == 70);
    assert_or_panic(v[54] == 71);
    assert_or_panic(v[55] == 72);
    assert_or_panic(v[56] == 73);
    assert_or_panic(v[57] == 74);
    assert_or_panic(v[58] == 75);
    assert_or_panic(v[59] == 76);
    assert_or_panic(v[60] == 77);
    assert_or_panic(v[61] == 78);
    assert_or_panic(v[62] == 79);
    assert_or_panic(v[63] == 80);
    assert_or_panic(i == 64);
}
void c_test_vector_64_u8(void) {
    Vector_64_u8 v = zig_ret_vector_64_u8();
    assert_or_panic(v[0] == 25);
    assert_or_panic(v[1] == 26);
    assert_or_panic(v[2] == 27);
    assert_or_panic(v[3] == 28);
    assert_or_panic(v[4] == 29);
    assert_or_panic(v[5] == 30);
    assert_or_panic(v[6] == 31);
    assert_or_panic(v[7] == 32);
    assert_or_panic(v[8] == 33);
    assert_or_panic(v[9] == 34);
    assert_or_panic(v[10] == 35);
    assert_or_panic(v[11] == 36);
    assert_or_panic(v[12] == 37);
    assert_or_panic(v[13] == 38);
    assert_or_panic(v[14] == 39);
    assert_or_panic(v[15] == 40);
    assert_or_panic(v[16] == 41);
    assert_or_panic(v[17] == 42);
    assert_or_panic(v[18] == 43);
    assert_or_panic(v[19] == 44);
    assert_or_panic(v[20] == 45);
    assert_or_panic(v[21] == 46);
    assert_or_panic(v[22] == 47);
    assert_or_panic(v[23] == 48);
    assert_or_panic(v[24] == 49);
    assert_or_panic(v[25] == 50);
    assert_or_panic(v[26] == 51);
    assert_or_panic(v[27] == 52);
    assert_or_panic(v[28] == 53);
    assert_or_panic(v[29] == 54);
    assert_or_panic(v[30] == 55);
    assert_or_panic(v[31] == 56);
    assert_or_panic(v[32] == 57);
    assert_or_panic(v[33] == 58);
    assert_or_panic(v[34] == 59);
    assert_or_panic(v[35] == 60);
    assert_or_panic(v[36] == 61);
    assert_or_panic(v[37] == 62);
    assert_or_panic(v[38] == 63);
    assert_or_panic(v[39] == 64);
    assert_or_panic(v[40] == 65);
    assert_or_panic(v[41] == 66);
    assert_or_panic(v[42] == 67);
    assert_or_panic(v[43] == 68);
    assert_or_panic(v[44] == 69);
    assert_or_panic(v[45] == 70);
    assert_or_panic(v[46] == 71);
    assert_or_panic(v[47] == 72);
    assert_or_panic(v[48] == 73);
    assert_or_panic(v[49] == 74);
    assert_or_panic(v[50] == 75);
    assert_or_panic(v[51] == 76);
    assert_or_panic(v[52] == 77);
    assert_or_panic(v[53] == 78);
    assert_or_panic(v[54] == 79);
    assert_or_panic(v[55] == 80);
    assert_or_panic(v[56] == 81);
    assert_or_panic(v[57] == 82);
    assert_or_panic(v[58] == 83);
    assert_or_panic(v[59] == 84);
    assert_or_panic(v[60] == 85);
    assert_or_panic(v[61] == 86);
    assert_or_panic(v[62] == 87);
    assert_or_panic(v[63] == 88);
    zig_vector_64_u8((Vector_64_u8){
        89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,  1,  2,  3,  4,
        5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
        21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36,
        37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52,
    }, 64);
}

typedef uint8_t Vector_96_u8 __attribute__((vector_size(96 * sizeof(uint8_t))));

Vector_96_u8 zig_ret_vector_96_u8(void);
void zig_vector_96_u8(Vector_96_u8, size_t);

Vector_96_u8 c_ret_vector_96_u8(void) {
    return (Vector_96_u8){
        82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97,
        98, 99, 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13,
        14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
        30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45,
        46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61,
        62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77,
    };
}
void c_vector_96_u8(Vector_96_u8 v, size_t i) {
    assert_or_panic(v[0] == 78);
    assert_or_panic(v[1] == 79);
    assert_or_panic(v[2] == 80);
    assert_or_panic(v[3] == 81);
    assert_or_panic(v[4] == 82);
    assert_or_panic(v[5] == 83);
    assert_or_panic(v[6] == 84);
    assert_or_panic(v[7] == 85);
    assert_or_panic(v[8] == 86);
    assert_or_panic(v[9] == 87);
    assert_or_panic(v[10] == 88);
    assert_or_panic(v[11] == 89);
    assert_or_panic(v[12] == 90);
    assert_or_panic(v[13] == 91);
    assert_or_panic(v[14] == 92);
    assert_or_panic(v[15] == 93);
    assert_or_panic(v[16] == 94);
    assert_or_panic(v[17] == 95);
    assert_or_panic(v[18] == 96);
    assert_or_panic(v[19] == 97);
    assert_or_panic(v[20] == 98);
    assert_or_panic(v[21] == 99);
    assert_or_panic(v[22] == 0);
    assert_or_panic(v[23] == 1);
    assert_or_panic(v[24] == 2);
    assert_or_panic(v[25] == 3);
    assert_or_panic(v[26] == 4);
    assert_or_panic(v[27] == 5);
    assert_or_panic(v[28] == 6);
    assert_or_panic(v[29] == 7);
    assert_or_panic(v[30] == 8);
    assert_or_panic(v[31] == 9);
    assert_or_panic(v[32] == 10);
    assert_or_panic(v[33] == 11);
    assert_or_panic(v[34] == 12);
    assert_or_panic(v[35] == 13);
    assert_or_panic(v[36] == 14);
    assert_or_panic(v[37] == 15);
    assert_or_panic(v[38] == 16);
    assert_or_panic(v[39] == 17);
    assert_or_panic(v[40] == 18);
    assert_or_panic(v[41] == 19);
    assert_or_panic(v[42] == 20);
    assert_or_panic(v[43] == 21);
    assert_or_panic(v[44] == 22);
    assert_or_panic(v[45] == 23);
    assert_or_panic(v[46] == 24);
    assert_or_panic(v[47] == 25);
    assert_or_panic(v[48] == 26);
    assert_or_panic(v[49] == 27);
    assert_or_panic(v[50] == 28);
    assert_or_panic(v[51] == 29);
    assert_or_panic(v[52] == 30);
    assert_or_panic(v[53] == 31);
    assert_or_panic(v[54] == 32);
    assert_or_panic(v[55] == 33);
    assert_or_panic(v[56] == 34);
    assert_or_panic(v[57] == 35);
    assert_or_panic(v[58] == 36);
    assert_or_panic(v[59] == 37);
    assert_or_panic(v[60] == 38);
    assert_or_panic(v[61] == 39);
    assert_or_panic(v[62] == 40);
    assert_or_panic(v[63] == 41);
    assert_or_panic(v[64] == 42);
    assert_or_panic(v[65] == 43);
    assert_or_panic(v[66] == 44);
    assert_or_panic(v[67] == 45);
    assert_or_panic(v[68] == 46);
    assert_or_panic(v[69] == 47);
    assert_or_panic(v[70] == 48);
    assert_or_panic(v[71] == 49);
    assert_or_panic(v[72] == 50);
    assert_or_panic(v[73] == 51);
    assert_or_panic(v[74] == 52);
    assert_or_panic(v[75] == 53);
    assert_or_panic(v[76] == 54);
    assert_or_panic(v[77] == 55);
    assert_or_panic(v[80] == 58);
    assert_or_panic(v[81] == 59);
    assert_or_panic(v[82] == 60);
    assert_or_panic(v[83] == 61);
    assert_or_panic(v[84] == 62);
    assert_or_panic(v[85] == 63);
    assert_or_panic(v[86] == 64);
    assert_or_panic(v[87] == 65);
    assert_or_panic(v[88] == 66);
    assert_or_panic(v[89] == 67);
    assert_or_panic(v[90] == 68);
    assert_or_panic(v[91] == 69);
    assert_or_panic(v[92] == 70);
    assert_or_panic(v[93] == 71);
    assert_or_panic(v[94] == 72);
    assert_or_panic(v[95] == 73);
    assert_or_panic(i == 96);
}
void c_test_vector_96_u8(void) {
    Vector_96_u8 v = zig_ret_vector_96_u8();
    assert_or_panic(v[0] == 90);
    assert_or_panic(v[1] == 91);
    assert_or_panic(v[2] == 92);
    assert_or_panic(v[3] == 93);
    assert_or_panic(v[4] == 94);
    assert_or_panic(v[5] == 95);
    assert_or_panic(v[6] == 96);
    assert_or_panic(v[7] == 97);
    assert_or_panic(v[8] == 98);
    assert_or_panic(v[9] == 99);
    assert_or_panic(v[10] == 0);
    assert_or_panic(v[11] == 1);
    assert_or_panic(v[12] == 2);
    assert_or_panic(v[13] == 3);
    assert_or_panic(v[14] == 4);
    assert_or_panic(v[15] == 5);
    assert_or_panic(v[16] == 6);
    assert_or_panic(v[17] == 7);
    assert_or_panic(v[18] == 8);
    assert_or_panic(v[19] == 9);
    assert_or_panic(v[20] == 10);
    assert_or_panic(v[21] == 11);
    assert_or_panic(v[22] == 12);
    assert_or_panic(v[23] == 13);
    assert_or_panic(v[24] == 14);
    assert_or_panic(v[25] == 15);
    assert_or_panic(v[26] == 16);
    assert_or_panic(v[27] == 17);
    assert_or_panic(v[28] == 18);
    assert_or_panic(v[29] == 19);
    assert_or_panic(v[30] == 20);
    assert_or_panic(v[31] == 21);
    assert_or_panic(v[32] == 22);
    assert_or_panic(v[33] == 23);
    assert_or_panic(v[34] == 24);
    assert_or_panic(v[35] == 25);
    assert_or_panic(v[36] == 26);
    assert_or_panic(v[37] == 27);
    assert_or_panic(v[38] == 28);
    assert_or_panic(v[39] == 29);
    assert_or_panic(v[40] == 30);
    assert_or_panic(v[41] == 31);
    assert_or_panic(v[42] == 32);
    assert_or_panic(v[43] == 33);
    assert_or_panic(v[44] == 34);
    assert_or_panic(v[45] == 35);
    assert_or_panic(v[46] == 36);
    assert_or_panic(v[47] == 37);
    assert_or_panic(v[48] == 38);
    assert_or_panic(v[49] == 39);
    assert_or_panic(v[50] == 40);
    assert_or_panic(v[51] == 41);
    assert_or_panic(v[52] == 42);
    assert_or_panic(v[53] == 43);
    assert_or_panic(v[54] == 44);
    assert_or_panic(v[55] == 45);
    assert_or_panic(v[56] == 46);
    assert_or_panic(v[57] == 47);
    assert_or_panic(v[58] == 48);
    assert_or_panic(v[59] == 49);
    assert_or_panic(v[60] == 50);
    assert_or_panic(v[61] == 51);
    assert_or_panic(v[62] == 52);
    assert_or_panic(v[63] == 53);
    assert_or_panic(v[64] == 54);
    assert_or_panic(v[65] == 55);
    assert_or_panic(v[66] == 56);
    assert_or_panic(v[67] == 57);
    assert_or_panic(v[68] == 58);
    assert_or_panic(v[69] == 59);
    assert_or_panic(v[70] == 60);
    assert_or_panic(v[71] == 61);
    assert_or_panic(v[72] == 62);
    assert_or_panic(v[73] == 63);
    assert_or_panic(v[74] == 64);
    assert_or_panic(v[75] == 65);
    assert_or_panic(v[76] == 66);
    assert_or_panic(v[77] == 67);
    assert_or_panic(v[78] == 68);
    assert_or_panic(v[79] == 69);
    assert_or_panic(v[80] == 70);
    assert_or_panic(v[81] == 71);
    assert_or_panic(v[82] == 72);
    assert_or_panic(v[83] == 73);
    assert_or_panic(v[84] == 74);
    assert_or_panic(v[85] == 75);
    assert_or_panic(v[86] == 76);
    assert_or_panic(v[87] == 77);
    assert_or_panic(v[88] == 78);
    assert_or_panic(v[89] == 79);
    assert_or_panic(v[90] == 80);
    assert_or_panic(v[91] == 81);
    assert_or_panic(v[92] == 82);
    assert_or_panic(v[93] == 83);
    assert_or_panic(v[94] == 84);
    assert_or_panic(v[95] == 85);
    zig_vector_96_u8((Vector_96_u8){
        86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,  1,
        2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17,
        18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33,
        34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
        50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65,
        66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81,
    }, 96);
}

typedef uint8_t Vector_128_u8 __attribute__((vector_size(128 * sizeof(uint8_t))));

Vector_128_u8 zig_ret_vector_128_u8(void);
void zig_vector_128_u8(Vector_128_u8, size_t);

Vector_128_u8 c_ret_vector_128_u8(void) {
    return (Vector_128_u8){
        30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45,
        46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61,
        62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77,
        78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93,
        94, 95, 96, 97, 98, 99, 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,
        10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,
        26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41,
        42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
    };
}
void c_vector_128_u8(Vector_128_u8 v, size_t i) {
    assert_or_panic(v[0] == 58);
    assert_or_panic(v[1] == 59);
    assert_or_panic(v[2] == 60);
    assert_or_panic(v[3] == 61);
    assert_or_panic(v[4] == 62);
    assert_or_panic(v[5] == 63);
    assert_or_panic(v[6] == 64);
    assert_or_panic(v[7] == 65);
    assert_or_panic(v[8] == 66);
    assert_or_panic(v[9] == 67);
    assert_or_panic(v[10] == 68);
    assert_or_panic(v[11] == 69);
    assert_or_panic(v[12] == 70);
    assert_or_panic(v[13] == 71);
    assert_or_panic(v[14] == 72);
    assert_or_panic(v[15] == 73);
    assert_or_panic(v[16] == 74);
    assert_or_panic(v[17] == 75);
    assert_or_panic(v[18] == 76);
    assert_or_panic(v[19] == 77);
    assert_or_panic(v[20] == 78);
    assert_or_panic(v[21] == 79);
    assert_or_panic(v[22] == 80);
    assert_or_panic(v[23] == 81);
    assert_or_panic(v[24] == 82);
    assert_or_panic(v[25] == 83);
    assert_or_panic(v[26] == 84);
    assert_or_panic(v[27] == 85);
    assert_or_panic(v[28] == 86);
    assert_or_panic(v[29] == 87);
    assert_or_panic(v[30] == 88);
    assert_or_panic(v[31] == 89);
    assert_or_panic(v[32] == 90);
    assert_or_panic(v[33] == 91);
    assert_or_panic(v[34] == 92);
    assert_or_panic(v[35] == 93);
    assert_or_panic(v[36] == 94);
    assert_or_panic(v[37] == 95);
    assert_or_panic(v[38] == 96);
    assert_or_panic(v[39] == 97);
    assert_or_panic(v[40] == 98);
    assert_or_panic(v[41] == 99);
    assert_or_panic(v[42] == 0);
    assert_or_panic(v[43] == 1);
    assert_or_panic(v[44] == 2);
    assert_or_panic(v[45] == 3);
    assert_or_panic(v[46] == 4);
    assert_or_panic(v[47] == 5);
    assert_or_panic(v[48] == 6);
    assert_or_panic(v[49] == 7);
    assert_or_panic(v[50] == 8);
    assert_or_panic(v[51] == 9);
    assert_or_panic(v[52] == 10);
    assert_or_panic(v[53] == 11);
    assert_or_panic(v[54] == 12);
    assert_or_panic(v[55] == 13);
    assert_or_panic(v[56] == 14);
    assert_or_panic(v[57] == 15);
    assert_or_panic(v[58] == 16);
    assert_or_panic(v[59] == 17);
    assert_or_panic(v[60] == 18);
    assert_or_panic(v[61] == 19);
    assert_or_panic(v[62] == 20);
    assert_or_panic(v[63] == 21);
    assert_or_panic(v[64] == 22);
    assert_or_panic(v[65] == 23);
    assert_or_panic(v[66] == 24);
    assert_or_panic(v[67] == 25);
    assert_or_panic(v[68] == 26);
    assert_or_panic(v[69] == 27);
    assert_or_panic(v[70] == 28);
    assert_or_panic(v[71] == 29);
    assert_or_panic(v[72] == 30);
    assert_or_panic(v[73] == 31);
    assert_or_panic(v[74] == 32);
    assert_or_panic(v[75] == 33);
    assert_or_panic(v[76] == 34);
    assert_or_panic(v[77] == 35);
    assert_or_panic(v[78] == 36);
    assert_or_panic(v[79] == 37);
    assert_or_panic(v[80] == 38);
    assert_or_panic(v[81] == 39);
    assert_or_panic(v[82] == 40);
    assert_or_panic(v[83] == 41);
    assert_or_panic(v[84] == 42);
    assert_or_panic(v[85] == 43);
    assert_or_panic(v[86] == 44);
    assert_or_panic(v[87] == 45);
    assert_or_panic(v[88] == 46);
    assert_or_panic(v[89] == 47);
    assert_or_panic(v[90] == 48);
    assert_or_panic(v[91] == 49);
    assert_or_panic(v[92] == 50);
    assert_or_panic(v[93] == 51);
    assert_or_panic(v[94] == 52);
    assert_or_panic(v[95] == 53);
    assert_or_panic(v[96] == 54);
    assert_or_panic(v[97] == 55);
    assert_or_panic(v[98] == 56);
    assert_or_panic(v[99] == 57);
    assert_or_panic(v[100] == 58);
    assert_or_panic(v[101] == 59);
    assert_or_panic(v[102] == 60);
    assert_or_panic(v[103] == 61);
    assert_or_panic(v[104] == 62);
    assert_or_panic(v[105] == 63);
    assert_or_panic(v[106] == 64);
    assert_or_panic(v[107] == 65);
    assert_or_panic(v[108] == 66);
    assert_or_panic(v[109] == 67);
    assert_or_panic(v[110] == 68);
    assert_or_panic(v[111] == 69);
    assert_or_panic(v[112] == 70);
    assert_or_panic(v[113] == 71);
    assert_or_panic(v[114] == 72);
    assert_or_panic(v[115] == 73);
    assert_or_panic(v[116] == 74);
    assert_or_panic(v[117] == 75);
    assert_or_panic(v[118] == 76);
    assert_or_panic(v[119] == 77);
    assert_or_panic(v[120] == 78);
    assert_or_panic(v[121] == 79);
    assert_or_panic(v[122] == 80);
    assert_or_panic(v[123] == 81);
    assert_or_panic(v[124] == 82);
    assert_or_panic(v[125] == 83);
    assert_or_panic(v[126] == 84);
    assert_or_panic(v[127] == 85);
    assert_or_panic(i == 128);
}
void c_test_vector_128_u8(void) {
    Vector_128_u8 v = zig_ret_vector_128_u8();
    assert_or_panic(v[0] == 74);
    assert_or_panic(v[1] == 75);
    assert_or_panic(v[2] == 76);
    assert_or_panic(v[3] == 77);
    assert_or_panic(v[4] == 78);
    assert_or_panic(v[5] == 79);
    assert_or_panic(v[6] == 80);
    assert_or_panic(v[7] == 81);
    assert_or_panic(v[8] == 82);
    assert_or_panic(v[9] == 83);
    assert_or_panic(v[10] == 84);
    assert_or_panic(v[11] == 85);
    assert_or_panic(v[12] == 86);
    assert_or_panic(v[13] == 87);
    assert_or_panic(v[14] == 88);
    assert_or_panic(v[15] == 89);
    assert_or_panic(v[16] == 90);
    assert_or_panic(v[17] == 91);
    assert_or_panic(v[18] == 92);
    assert_or_panic(v[19] == 93);
    assert_or_panic(v[20] == 94);
    assert_or_panic(v[21] == 95);
    assert_or_panic(v[22] == 96);
    assert_or_panic(v[23] == 97);
    assert_or_panic(v[24] == 98);
    assert_or_panic(v[25] == 99);
    assert_or_panic(v[26] == 0);
    assert_or_panic(v[27] == 1);
    assert_or_panic(v[28] == 2);
    assert_or_panic(v[29] == 3);
    assert_or_panic(v[30] == 4);
    assert_or_panic(v[31] == 5);
    assert_or_panic(v[32] == 6);
    assert_or_panic(v[33] == 7);
    assert_or_panic(v[34] == 8);
    assert_or_panic(v[35] == 9);
    assert_or_panic(v[36] == 10);
    assert_or_panic(v[37] == 11);
    assert_or_panic(v[38] == 12);
    assert_or_panic(v[39] == 13);
    assert_or_panic(v[40] == 14);
    assert_or_panic(v[41] == 15);
    assert_or_panic(v[42] == 16);
    assert_or_panic(v[43] == 17);
    assert_or_panic(v[44] == 18);
    assert_or_panic(v[45] == 19);
    assert_or_panic(v[46] == 20);
    assert_or_panic(v[47] == 21);
    assert_or_panic(v[48] == 22);
    assert_or_panic(v[49] == 23);
    assert_or_panic(v[50] == 24);
    assert_or_panic(v[51] == 25);
    assert_or_panic(v[52] == 26);
    assert_or_panic(v[53] == 27);
    assert_or_panic(v[54] == 28);
    assert_or_panic(v[55] == 29);
    assert_or_panic(v[56] == 30);
    assert_or_panic(v[57] == 31);
    assert_or_panic(v[58] == 32);
    assert_or_panic(v[59] == 33);
    assert_or_panic(v[60] == 34);
    assert_or_panic(v[61] == 35);
    assert_or_panic(v[62] == 36);
    assert_or_panic(v[63] == 37);
    assert_or_panic(v[64] == 38);
    assert_or_panic(v[65] == 39);
    assert_or_panic(v[66] == 40);
    assert_or_panic(v[67] == 41);
    assert_or_panic(v[68] == 42);
    assert_or_panic(v[69] == 43);
    assert_or_panic(v[70] == 44);
    assert_or_panic(v[71] == 45);
    assert_or_panic(v[72] == 46);
    assert_or_panic(v[73] == 47);
    assert_or_panic(v[74] == 48);
    assert_or_panic(v[75] == 49);
    assert_or_panic(v[76] == 50);
    assert_or_panic(v[77] == 51);
    assert_or_panic(v[78] == 52);
    assert_or_panic(v[79] == 53);
    assert_or_panic(v[80] == 54);
    assert_or_panic(v[81] == 55);
    assert_or_panic(v[82] == 56);
    assert_or_panic(v[83] == 57);
    assert_or_panic(v[84] == 58);
    assert_or_panic(v[85] == 59);
    assert_or_panic(v[86] == 60);
    assert_or_panic(v[87] == 61);
    assert_or_panic(v[88] == 62);
    assert_or_panic(v[89] == 63);
    assert_or_panic(v[90] == 64);
    assert_or_panic(v[91] == 65);
    assert_or_panic(v[92] == 66);
    assert_or_panic(v[93] == 67);
    assert_or_panic(v[94] == 68);
    assert_or_panic(v[95] == 69);
    assert_or_panic(v[96] == 70);
    assert_or_panic(v[97] == 71);
    assert_or_panic(v[98] == 72);
    assert_or_panic(v[99] == 73);
    assert_or_panic(v[100] == 74);
    assert_or_panic(v[101] == 75);
    assert_or_panic(v[102] == 76);
    assert_or_panic(v[103] == 77);
    assert_or_panic(v[104] == 78);
    assert_or_panic(v[105] == 79);
    assert_or_panic(v[106] == 80);
    assert_or_panic(v[107] == 81);
    assert_or_panic(v[108] == 82);
    assert_or_panic(v[109] == 83);
    assert_or_panic(v[110] == 84);
    assert_or_panic(v[111] == 85);
    assert_or_panic(v[112] == 86);
    assert_or_panic(v[113] == 87);
    assert_or_panic(v[114] == 88);
    assert_or_panic(v[115] == 89);
    assert_or_panic(v[116] == 90);
    assert_or_panic(v[117] == 91);
    assert_or_panic(v[118] == 92);
    assert_or_panic(v[119] == 93);
    assert_or_panic(v[120] == 94);
    assert_or_panic(v[121] == 95);
    assert_or_panic(v[122] == 96);
    assert_or_panic(v[123] == 97);
    assert_or_panic(v[124] == 98);
    assert_or_panic(v[125] == 99);
    assert_or_panic(v[126] == 0);
    assert_or_panic(v[127] == 1);
    zig_vector_128_u8((Vector_128_u8){
        2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17,
        18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33,
        34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
        50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65,
        66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81,
        82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97,
        98, 99, 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13,
        14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
    }, 128);
}

typedef uint8_t Vector_192_u8 __attribute__((vector_size(192 * sizeof(uint8_t))));

Vector_192_u8 zig_ret_vector_192_u8(void);
void zig_vector_192_u8(Vector_192_u8, size_t);

Vector_192_u8 c_ret_vector_192_u8(void) {
    return (Vector_192_u8){
        70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85,
        86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,  1,
        2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17,
        18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33,
        34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
        50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65,
        66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81,
        82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97,
        98, 99, 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13,
        14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
        30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45,
        46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61,
    };
}
void c_vector_192_u8(Vector_192_u8 v, size_t i) {
    assert_or_panic(v[0] == 62);
    assert_or_panic(v[1] == 63);
    assert_or_panic(v[2] == 64);
    assert_or_panic(v[3] == 65);
    assert_or_panic(v[4] == 66);
    assert_or_panic(v[5] == 67);
    assert_or_panic(v[6] == 68);
    assert_or_panic(v[7] == 69);
    assert_or_panic(v[8] == 70);
    assert_or_panic(v[9] == 71);
    assert_or_panic(v[10] == 72);
    assert_or_panic(v[11] == 73);
    assert_or_panic(v[12] == 74);
    assert_or_panic(v[13] == 75);
    assert_or_panic(v[14] == 76);
    assert_or_panic(v[15] == 77);
    assert_or_panic(v[16] == 78);
    assert_or_panic(v[17] == 79);
    assert_or_panic(v[18] == 80);
    assert_or_panic(v[19] == 81);
    assert_or_panic(v[20] == 82);
    assert_or_panic(v[21] == 83);
    assert_or_panic(v[22] == 84);
    assert_or_panic(v[23] == 85);
    assert_or_panic(v[24] == 86);
    assert_or_panic(v[25] == 87);
    assert_or_panic(v[26] == 88);
    assert_or_panic(v[27] == 89);
    assert_or_panic(v[28] == 90);
    assert_or_panic(v[29] == 91);
    assert_or_panic(v[30] == 92);
    assert_or_panic(v[31] == 93);
    assert_or_panic(v[32] == 94);
    assert_or_panic(v[33] == 95);
    assert_or_panic(v[34] == 96);
    assert_or_panic(v[35] == 97);
    assert_or_panic(v[36] == 98);
    assert_or_panic(v[37] == 99);
    assert_or_panic(v[38] == 0);
    assert_or_panic(v[39] == 1);
    assert_or_panic(v[40] == 2);
    assert_or_panic(v[41] == 3);
    assert_or_panic(v[42] == 4);
    assert_or_panic(v[43] == 5);
    assert_or_panic(v[44] == 6);
    assert_or_panic(v[45] == 7);
    assert_or_panic(v[46] == 8);
    assert_or_panic(v[47] == 9);
    assert_or_panic(v[48] == 10);
    assert_or_panic(v[49] == 11);
    assert_or_panic(v[50] == 12);
    assert_or_panic(v[51] == 13);
    assert_or_panic(v[52] == 14);
    assert_or_panic(v[53] == 15);
    assert_or_panic(v[54] == 16);
    assert_or_panic(v[55] == 17);
    assert_or_panic(v[56] == 18);
    assert_or_panic(v[57] == 19);
    assert_or_panic(v[58] == 20);
    assert_or_panic(v[59] == 21);
    assert_or_panic(v[60] == 22);
    assert_or_panic(v[61] == 23);
    assert_or_panic(v[62] == 24);
    assert_or_panic(v[63] == 25);
    assert_or_panic(v[64] == 26);
    assert_or_panic(v[65] == 27);
    assert_or_panic(v[66] == 28);
    assert_or_panic(v[67] == 29);
    assert_or_panic(v[68] == 30);
    assert_or_panic(v[69] == 31);
    assert_or_panic(v[70] == 32);
    assert_or_panic(v[71] == 33);
    assert_or_panic(v[72] == 34);
    assert_or_panic(v[73] == 35);
    assert_or_panic(v[74] == 36);
    assert_or_panic(v[75] == 37);
    assert_or_panic(v[76] == 38);
    assert_or_panic(v[77] == 39);
    assert_or_panic(v[78] == 40);
    assert_or_panic(v[79] == 41);
    assert_or_panic(v[80] == 42);
    assert_or_panic(v[81] == 43);
    assert_or_panic(v[82] == 44);
    assert_or_panic(v[83] == 45);
    assert_or_panic(v[84] == 46);
    assert_or_panic(v[85] == 47);
    assert_or_panic(v[86] == 48);
    assert_or_panic(v[87] == 49);
    assert_or_panic(v[88] == 50);
    assert_or_panic(v[89] == 51);
    assert_or_panic(v[90] == 52);
    assert_or_panic(v[91] == 53);
    assert_or_panic(v[92] == 54);
    assert_or_panic(v[93] == 55);
    assert_or_panic(v[94] == 56);
    assert_or_panic(v[95] == 57);
    assert_or_panic(v[96] == 58);
    assert_or_panic(v[97] == 59);
    assert_or_panic(v[98] == 60);
    assert_or_panic(v[99] == 61);
    assert_or_panic(v[100] == 62);
    assert_or_panic(v[101] == 63);
    assert_or_panic(v[102] == 64);
    assert_or_panic(v[103] == 65);
    assert_or_panic(v[104] == 66);
    assert_or_panic(v[105] == 67);
    assert_or_panic(v[106] == 68);
    assert_or_panic(v[107] == 69);
    assert_or_panic(v[108] == 70);
    assert_or_panic(v[109] == 71);
    assert_or_panic(v[110] == 72);
    assert_or_panic(v[111] == 73);
    assert_or_panic(v[112] == 74);
    assert_or_panic(v[113] == 75);
    assert_or_panic(v[114] == 76);
    assert_or_panic(v[115] == 77);
    assert_or_panic(v[116] == 78);
    assert_or_panic(v[117] == 79);
    assert_or_panic(v[118] == 80);
    assert_or_panic(v[119] == 81);
    assert_or_panic(v[120] == 82);
    assert_or_panic(v[121] == 83);
    assert_or_panic(v[122] == 84);
    assert_or_panic(v[123] == 85);
    assert_or_panic(v[124] == 86);
    assert_or_panic(v[125] == 87);
    assert_or_panic(v[126] == 88);
    assert_or_panic(v[127] == 89);
    assert_or_panic(v[128] == 90);
    assert_or_panic(v[129] == 91);
    assert_or_panic(v[130] == 92);
    assert_or_panic(v[131] == 93);
    assert_or_panic(v[132] == 94);
    assert_or_panic(v[133] == 95);
    assert_or_panic(v[134] == 96);
    assert_or_panic(v[135] == 97);
    assert_or_panic(v[136] == 98);
    assert_or_panic(v[137] == 99);
    assert_or_panic(v[138] == 0);
    assert_or_panic(v[139] == 1);
    assert_or_panic(v[140] == 2);
    assert_or_panic(v[141] == 3);
    assert_or_panic(v[142] == 4);
    assert_or_panic(v[143] == 5);
    assert_or_panic(v[144] == 6);
    assert_or_panic(v[145] == 7);
    assert_or_panic(v[146] == 8);
    assert_or_panic(v[147] == 9);
    assert_or_panic(v[148] == 10);
    assert_or_panic(v[149] == 11);
    assert_or_panic(v[150] == 12);
    assert_or_panic(v[151] == 13);
    assert_or_panic(v[152] == 14);
    assert_or_panic(v[153] == 15);
    assert_or_panic(v[154] == 16);
    assert_or_panic(v[155] == 17);
    assert_or_panic(v[156] == 18);
    assert_or_panic(v[157] == 19);
    assert_or_panic(v[158] == 20);
    assert_or_panic(v[159] == 21);
    assert_or_panic(v[160] == 22);
    assert_or_panic(v[161] == 23);
    assert_or_panic(v[162] == 24);
    assert_or_panic(v[163] == 25);
    assert_or_panic(v[164] == 26);
    assert_or_panic(v[165] == 27);
    assert_or_panic(v[166] == 28);
    assert_or_panic(v[167] == 29);
    assert_or_panic(v[168] == 30);
    assert_or_panic(v[169] == 31);
    assert_or_panic(v[170] == 32);
    assert_or_panic(v[171] == 33);
    assert_or_panic(v[172] == 34);
    assert_or_panic(v[173] == 35);
    assert_or_panic(v[174] == 36);
    assert_or_panic(v[175] == 37);
    assert_or_panic(v[176] == 38);
    assert_or_panic(v[177] == 39);
    assert_or_panic(v[178] == 40);
    assert_or_panic(v[179] == 41);
    assert_or_panic(v[180] == 42);
    assert_or_panic(v[181] == 43);
    assert_or_panic(v[182] == 44);
    assert_or_panic(v[183] == 45);
    assert_or_panic(v[184] == 46);
    assert_or_panic(v[185] == 47);
    assert_or_panic(v[186] == 48);
    assert_or_panic(v[187] == 49);
    assert_or_panic(v[188] == 50);
    assert_or_panic(v[189] == 51);
    assert_or_panic(v[190] == 52);
    assert_or_panic(v[191] == 53);
    assert_or_panic(i == 192);
}
void c_test_vector_192_u8(void) {
    Vector_192_u8 v = zig_ret_vector_192_u8();
    assert_or_panic(v[0] == 86);
    assert_or_panic(v[1] == 87);
    assert_or_panic(v[2] == 88);
    assert_or_panic(v[3] == 89);
    assert_or_panic(v[4] == 90);
    assert_or_panic(v[5] == 91);
    assert_or_panic(v[6] == 92);
    assert_or_panic(v[7] == 93);
    assert_or_panic(v[8] == 94);
    assert_or_panic(v[9] == 95);
    assert_or_panic(v[10] == 96);
    assert_or_panic(v[11] == 97);
    assert_or_panic(v[12] == 98);
    assert_or_panic(v[13] == 99);
    assert_or_panic(v[14] == 0);
    assert_or_panic(v[15] == 1);
    assert_or_panic(v[16] == 2);
    assert_or_panic(v[17] == 3);
    assert_or_panic(v[18] == 4);
    assert_or_panic(v[19] == 5);
    assert_or_panic(v[20] == 6);
    assert_or_panic(v[21] == 7);
    assert_or_panic(v[22] == 8);
    assert_or_panic(v[23] == 9);
    assert_or_panic(v[24] == 10);
    assert_or_panic(v[25] == 11);
    assert_or_panic(v[26] == 12);
    assert_or_panic(v[27] == 13);
    assert_or_panic(v[28] == 14);
    assert_or_panic(v[29] == 15);
    assert_or_panic(v[30] == 16);
    assert_or_panic(v[31] == 17);
    assert_or_panic(v[32] == 18);
    assert_or_panic(v[33] == 19);
    assert_or_panic(v[34] == 20);
    assert_or_panic(v[35] == 21);
    assert_or_panic(v[36] == 22);
    assert_or_panic(v[37] == 23);
    assert_or_panic(v[38] == 24);
    assert_or_panic(v[39] == 25);
    assert_or_panic(v[40] == 26);
    assert_or_panic(v[41] == 27);
    assert_or_panic(v[42] == 28);
    assert_or_panic(v[43] == 29);
    assert_or_panic(v[44] == 30);
    assert_or_panic(v[45] == 31);
    assert_or_panic(v[46] == 32);
    assert_or_panic(v[47] == 33);
    assert_or_panic(v[48] == 34);
    assert_or_panic(v[49] == 35);
    assert_or_panic(v[50] == 36);
    assert_or_panic(v[51] == 37);
    assert_or_panic(v[52] == 38);
    assert_or_panic(v[53] == 39);
    assert_or_panic(v[54] == 40);
    assert_or_panic(v[55] == 41);
    assert_or_panic(v[56] == 42);
    assert_or_panic(v[57] == 43);
    assert_or_panic(v[58] == 44);
    assert_or_panic(v[59] == 45);
    assert_or_panic(v[60] == 46);
    assert_or_panic(v[61] == 47);
    assert_or_panic(v[62] == 48);
    assert_or_panic(v[63] == 49);
    assert_or_panic(v[64] == 50);
    assert_or_panic(v[65] == 51);
    assert_or_panic(v[66] == 52);
    assert_or_panic(v[67] == 53);
    assert_or_panic(v[68] == 54);
    assert_or_panic(v[69] == 55);
    assert_or_panic(v[70] == 56);
    assert_or_panic(v[71] == 57);
    assert_or_panic(v[72] == 58);
    assert_or_panic(v[73] == 59);
    assert_or_panic(v[74] == 60);
    assert_or_panic(v[75] == 61);
    assert_or_panic(v[76] == 62);
    assert_or_panic(v[77] == 63);
    assert_or_panic(v[78] == 64);
    assert_or_panic(v[79] == 65);
    assert_or_panic(v[80] == 66);
    assert_or_panic(v[81] == 67);
    assert_or_panic(v[82] == 68);
    assert_or_panic(v[83] == 69);
    assert_or_panic(v[84] == 70);
    assert_or_panic(v[85] == 71);
    assert_or_panic(v[86] == 72);
    assert_or_panic(v[87] == 73);
    assert_or_panic(v[88] == 74);
    assert_or_panic(v[89] == 75);
    assert_or_panic(v[90] == 76);
    assert_or_panic(v[91] == 77);
    assert_or_panic(v[92] == 78);
    assert_or_panic(v[93] == 79);
    assert_or_panic(v[94] == 80);
    assert_or_panic(v[95] == 81);
    assert_or_panic(v[96] == 82);
    assert_or_panic(v[97] == 83);
    assert_or_panic(v[98] == 84);
    assert_or_panic(v[99] == 85);
    assert_or_panic(v[100] == 86);
    assert_or_panic(v[101] == 87);
    assert_or_panic(v[102] == 88);
    assert_or_panic(v[103] == 89);
    assert_or_panic(v[104] == 90);
    assert_or_panic(v[105] == 91);
    assert_or_panic(v[106] == 92);
    assert_or_panic(v[107] == 93);
    assert_or_panic(v[108] == 94);
    assert_or_panic(v[109] == 95);
    assert_or_panic(v[110] == 96);
    assert_or_panic(v[111] == 97);
    assert_or_panic(v[112] == 98);
    assert_or_panic(v[113] == 99);
    assert_or_panic(v[114] == 0);
    assert_or_panic(v[115] == 1);
    assert_or_panic(v[116] == 2);
    assert_or_panic(v[117] == 3);
    assert_or_panic(v[118] == 4);
    assert_or_panic(v[119] == 5);
    assert_or_panic(v[120] == 6);
    assert_or_panic(v[121] == 7);
    assert_or_panic(v[122] == 8);
    assert_or_panic(v[123] == 9);
    assert_or_panic(v[124] == 10);
    assert_or_panic(v[125] == 11);
    assert_or_panic(v[126] == 12);
    assert_or_panic(v[127] == 13);
    assert_or_panic(v[128] == 14);
    assert_or_panic(v[129] == 15);
    assert_or_panic(v[130] == 16);
    assert_or_panic(v[131] == 17);
    assert_or_panic(v[132] == 18);
    assert_or_panic(v[133] == 19);
    assert_or_panic(v[134] == 20);
    assert_or_panic(v[135] == 21);
    assert_or_panic(v[136] == 22);
    assert_or_panic(v[137] == 23);
    assert_or_panic(v[138] == 24);
    assert_or_panic(v[139] == 25);
    assert_or_panic(v[140] == 26);
    assert_or_panic(v[141] == 27);
    assert_or_panic(v[142] == 28);
    assert_or_panic(v[143] == 29);
    assert_or_panic(v[144] == 30);
    assert_or_panic(v[145] == 31);
    assert_or_panic(v[146] == 32);
    assert_or_panic(v[147] == 33);
    assert_or_panic(v[148] == 34);
    assert_or_panic(v[149] == 35);
    assert_or_panic(v[150] == 36);
    assert_or_panic(v[151] == 37);
    assert_or_panic(v[152] == 38);
    assert_or_panic(v[153] == 39);
    assert_or_panic(v[154] == 40);
    assert_or_panic(v[155] == 41);
    assert_or_panic(v[156] == 42);
    assert_or_panic(v[157] == 43);
    assert_or_panic(v[158] == 44);
    assert_or_panic(v[159] == 45);
    assert_or_panic(v[160] == 46);
    assert_or_panic(v[161] == 47);
    assert_or_panic(v[162] == 48);
    assert_or_panic(v[163] == 49);
    assert_or_panic(v[164] == 50);
    assert_or_panic(v[165] == 51);
    assert_or_panic(v[166] == 52);
    assert_or_panic(v[167] == 53);
    assert_or_panic(v[168] == 54);
    assert_or_panic(v[169] == 55);
    assert_or_panic(v[170] == 56);
    assert_or_panic(v[171] == 57);
    assert_or_panic(v[172] == 58);
    assert_or_panic(v[173] == 59);
    assert_or_panic(v[174] == 60);
    assert_or_panic(v[175] == 61);
    assert_or_panic(v[176] == 62);
    assert_or_panic(v[177] == 63);
    assert_or_panic(v[178] == 64);
    assert_or_panic(v[179] == 65);
    assert_or_panic(v[180] == 66);
    assert_or_panic(v[181] == 67);
    assert_or_panic(v[182] == 68);
    assert_or_panic(v[183] == 69);
    assert_or_panic(v[184] == 70);
    assert_or_panic(v[185] == 71);
    assert_or_panic(v[186] == 72);
    assert_or_panic(v[187] == 73);
    assert_or_panic(v[188] == 74);
    assert_or_panic(v[189] == 75);
    assert_or_panic(v[190] == 76);
    assert_or_panic(v[191] == 77);
    zig_vector_192_u8((Vector_192_u8){
        78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93,
        94, 95, 96, 97, 98, 99, 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,
        10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,
        26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41,
        42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
        58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73,
        74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89,
        90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,  1,  2,  3,  4,  5,
        6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
        22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37,
        38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53,
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69,
    }, 192);
}

typedef uint8_t Vector_256_u8 __attribute__((vector_size(256 * sizeof(uint8_t))));

Vector_256_u8 zig_ret_vector_256_u8(void);
void zig_vector_256_u8(Vector_256_u8, size_t);

Vector_256_u8 c_ret_vector_256_u8(void) {
    return (Vector_256_u8){
        66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81,
        82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97,
        98, 99, 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13,
        14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
        30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45,
        46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61,
        62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77,
        78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93,
        94, 95, 96, 97, 98, 99, 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,
        10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,
        26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41,
        42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
        58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73,
        74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89,
        90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,  1,  2,  3,  4,  5,
        6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
    };
}
void c_vector_256_u8(Vector_256_u8 v, size_t i) {
    assert_or_panic(v[0] == 22);
    assert_or_panic(v[1] == 23);
    assert_or_panic(v[2] == 24);
    assert_or_panic(v[3] == 25);
    assert_or_panic(v[4] == 26);
    assert_or_panic(v[5] == 27);
    assert_or_panic(v[6] == 28);
    assert_or_panic(v[7] == 29);
    assert_or_panic(v[8] == 30);
    assert_or_panic(v[9] == 31);
    assert_or_panic(v[10] == 32);
    assert_or_panic(v[11] == 33);
    assert_or_panic(v[12] == 34);
    assert_or_panic(v[13] == 35);
    assert_or_panic(v[14] == 36);
    assert_or_panic(v[15] == 37);
    assert_or_panic(v[16] == 38);
    assert_or_panic(v[17] == 39);
    assert_or_panic(v[18] == 40);
    assert_or_panic(v[19] == 41);
    assert_or_panic(v[20] == 42);
    assert_or_panic(v[21] == 43);
    assert_or_panic(v[22] == 44);
    assert_or_panic(v[23] == 45);
    assert_or_panic(v[24] == 46);
    assert_or_panic(v[25] == 47);
    assert_or_panic(v[26] == 48);
    assert_or_panic(v[27] == 49);
    assert_or_panic(v[28] == 50);
    assert_or_panic(v[29] == 51);
    assert_or_panic(v[30] == 52);
    assert_or_panic(v[31] == 53);
    assert_or_panic(v[32] == 54);
    assert_or_panic(v[33] == 55);
    assert_or_panic(v[34] == 56);
    assert_or_panic(v[35] == 57);
    assert_or_panic(v[36] == 58);
    assert_or_panic(v[37] == 59);
    assert_or_panic(v[38] == 60);
    assert_or_panic(v[39] == 61);
    assert_or_panic(v[40] == 62);
    assert_or_panic(v[41] == 63);
    assert_or_panic(v[42] == 64);
    assert_or_panic(v[43] == 65);
    assert_or_panic(v[44] == 66);
    assert_or_panic(v[45] == 67);
    assert_or_panic(v[46] == 68);
    assert_or_panic(v[47] == 69);
    assert_or_panic(v[48] == 70);
    assert_or_panic(v[49] == 71);
    assert_or_panic(v[50] == 72);
    assert_or_panic(v[51] == 73);
    assert_or_panic(v[52] == 74);
    assert_or_panic(v[53] == 75);
    assert_or_panic(v[54] == 76);
    assert_or_panic(v[55] == 77);
    assert_or_panic(v[56] == 78);
    assert_or_panic(v[57] == 79);
    assert_or_panic(v[58] == 80);
    assert_or_panic(v[59] == 81);
    assert_or_panic(v[60] == 82);
    assert_or_panic(v[61] == 83);
    assert_or_panic(v[62] == 84);
    assert_or_panic(v[63] == 85);
    assert_or_panic(v[64] == 86);
    assert_or_panic(v[65] == 87);
    assert_or_panic(v[66] == 88);
    assert_or_panic(v[67] == 89);
    assert_or_panic(v[68] == 90);
    assert_or_panic(v[69] == 91);
    assert_or_panic(v[70] == 92);
    assert_or_panic(v[71] == 93);
    assert_or_panic(v[72] == 94);
    assert_or_panic(v[73] == 95);
    assert_or_panic(v[74] == 96);
    assert_or_panic(v[75] == 97);
    assert_or_panic(v[76] == 98);
    assert_or_panic(v[77] == 99);
    assert_or_panic(v[78] == 0);
    assert_or_panic(v[79] == 1);
    assert_or_panic(v[80] == 2);
    assert_or_panic(v[81] == 3);
    assert_or_panic(v[82] == 4);
    assert_or_panic(v[83] == 5);
    assert_or_panic(v[84] == 6);
    assert_or_panic(v[85] == 7);
    assert_or_panic(v[86] == 8);
    assert_or_panic(v[87] == 9);
    assert_or_panic(v[88] == 10);
    assert_or_panic(v[89] == 11);
    assert_or_panic(v[90] == 12);
    assert_or_panic(v[91] == 13);
    assert_or_panic(v[92] == 14);
    assert_or_panic(v[93] == 15);
    assert_or_panic(v[94] == 16);
    assert_or_panic(v[95] == 17);
    assert_or_panic(v[96] == 18);
    assert_or_panic(v[97] == 19);
    assert_or_panic(v[98] == 20);
    assert_or_panic(v[99] == 21);
    assert_or_panic(v[100] == 22);
    assert_or_panic(v[101] == 23);
    assert_or_panic(v[102] == 24);
    assert_or_panic(v[103] == 25);
    assert_or_panic(v[104] == 26);
    assert_or_panic(v[105] == 27);
    assert_or_panic(v[106] == 28);
    assert_or_panic(v[107] == 29);
    assert_or_panic(v[108] == 30);
    assert_or_panic(v[109] == 31);
    assert_or_panic(v[110] == 32);
    assert_or_panic(v[111] == 33);
    assert_or_panic(v[112] == 34);
    assert_or_panic(v[113] == 35);
    assert_or_panic(v[114] == 36);
    assert_or_panic(v[115] == 37);
    assert_or_panic(v[116] == 38);
    assert_or_panic(v[117] == 39);
    assert_or_panic(v[118] == 40);
    assert_or_panic(v[119] == 41);
    assert_or_panic(v[120] == 42);
    assert_or_panic(v[121] == 43);
    assert_or_panic(v[122] == 44);
    assert_or_panic(v[123] == 45);
    assert_or_panic(v[124] == 46);
    assert_or_panic(v[125] == 47);
    assert_or_panic(v[126] == 48);
    assert_or_panic(v[127] == 49);
    assert_or_panic(v[128] == 50);
    assert_or_panic(v[129] == 51);
    assert_or_panic(v[130] == 52);
    assert_or_panic(v[131] == 53);
    assert_or_panic(v[132] == 54);
    assert_or_panic(v[133] == 55);
    assert_or_panic(v[134] == 56);
    assert_or_panic(v[135] == 57);
    assert_or_panic(v[136] == 58);
    assert_or_panic(v[137] == 59);
    assert_or_panic(v[138] == 60);
    assert_or_panic(v[139] == 61);
    assert_or_panic(v[140] == 62);
    assert_or_panic(v[141] == 63);
    assert_or_panic(v[142] == 64);
    assert_or_panic(v[143] == 65);
    assert_or_panic(v[144] == 66);
    assert_or_panic(v[145] == 67);
    assert_or_panic(v[146] == 68);
    assert_or_panic(v[147] == 69);
    assert_or_panic(v[148] == 70);
    assert_or_panic(v[149] == 71);
    assert_or_panic(v[150] == 72);
    assert_or_panic(v[151] == 73);
    assert_or_panic(v[152] == 74);
    assert_or_panic(v[153] == 75);
    assert_or_panic(v[154] == 76);
    assert_or_panic(v[155] == 77);
    assert_or_panic(v[156] == 78);
    assert_or_panic(v[157] == 79);
    assert_or_panic(v[158] == 80);
    assert_or_panic(v[159] == 81);
    assert_or_panic(v[160] == 82);
    assert_or_panic(v[161] == 83);
    assert_or_panic(v[162] == 84);
    assert_or_panic(v[163] == 85);
    assert_or_panic(v[164] == 86);
    assert_or_panic(v[165] == 87);
    assert_or_panic(v[166] == 88);
    assert_or_panic(v[167] == 89);
    assert_or_panic(v[168] == 90);
    assert_or_panic(v[169] == 91);
    assert_or_panic(v[170] == 92);
    assert_or_panic(v[171] == 93);
    assert_or_panic(v[172] == 94);
    assert_or_panic(v[173] == 95);
    assert_or_panic(v[174] == 96);
    assert_or_panic(v[175] == 97);
    assert_or_panic(v[176] == 98);
    assert_or_panic(v[177] == 99);
    assert_or_panic(v[178] == 0);
    assert_or_panic(v[179] == 1);
    assert_or_panic(v[180] == 2);
    assert_or_panic(v[181] == 3);
    assert_or_panic(v[182] == 4);
    assert_or_panic(v[183] == 5);
    assert_or_panic(v[184] == 6);
    assert_or_panic(v[185] == 7);
    assert_or_panic(v[186] == 8);
    assert_or_panic(v[187] == 9);
    assert_or_panic(v[188] == 10);
    assert_or_panic(v[189] == 11);
    assert_or_panic(v[190] == 12);
    assert_or_panic(v[191] == 13);
    assert_or_panic(v[192] == 14);
    assert_or_panic(v[193] == 15);
    assert_or_panic(v[194] == 16);
    assert_or_panic(v[195] == 17);
    assert_or_panic(v[196] == 18);
    assert_or_panic(v[197] == 19);
    assert_or_panic(v[198] == 20);
    assert_or_panic(v[199] == 21);
    assert_or_panic(v[200] == 22);
    assert_or_panic(v[201] == 23);
    assert_or_panic(v[202] == 24);
    assert_or_panic(v[203] == 25);
    assert_or_panic(v[204] == 26);
    assert_or_panic(v[205] == 27);
    assert_or_panic(v[206] == 28);
    assert_or_panic(v[207] == 29);
    assert_or_panic(v[208] == 30);
    assert_or_panic(v[209] == 31);
    assert_or_panic(v[210] == 32);
    assert_or_panic(v[211] == 33);
    assert_or_panic(v[212] == 34);
    assert_or_panic(v[213] == 35);
    assert_or_panic(v[214] == 36);
    assert_or_panic(v[215] == 37);
    assert_or_panic(v[216] == 38);
    assert_or_panic(v[217] == 39);
    assert_or_panic(v[218] == 40);
    assert_or_panic(v[219] == 41);
    assert_or_panic(v[220] == 42);
    assert_or_panic(v[221] == 43);
    assert_or_panic(v[222] == 44);
    assert_or_panic(v[223] == 45);
    assert_or_panic(v[224] == 46);
    assert_or_panic(v[225] == 47);
    assert_or_panic(v[226] == 48);
    assert_or_panic(v[227] == 49);
    assert_or_panic(v[228] == 50);
    assert_or_panic(v[229] == 51);
    assert_or_panic(v[230] == 52);
    assert_or_panic(v[231] == 53);
    assert_or_panic(v[232] == 54);
    assert_or_panic(v[233] == 55);
    assert_or_panic(v[234] == 56);
    assert_or_panic(v[235] == 57);
    assert_or_panic(v[236] == 58);
    assert_or_panic(v[237] == 59);
    assert_or_panic(v[238] == 60);
    assert_or_panic(v[239] == 61);
    assert_or_panic(v[240] == 62);
    assert_or_panic(v[241] == 63);
    assert_or_panic(v[242] == 64);
    assert_or_panic(v[243] == 65);
    assert_or_panic(v[244] == 66);
    assert_or_panic(v[245] == 67);
    assert_or_panic(v[246] == 68);
    assert_or_panic(v[247] == 69);
    assert_or_panic(v[248] == 70);
    assert_or_panic(v[249] == 71);
    assert_or_panic(v[250] == 72);
    assert_or_panic(v[251] == 73);
    assert_or_panic(v[252] == 74);
    assert_or_panic(v[253] == 75);
    assert_or_panic(v[254] == 76);
    assert_or_panic(v[255] == 77);
    assert_or_panic(i == 256);
}
void c_test_vector_256_u8(void) {
    Vector_256_u8 v = zig_ret_vector_256_u8();
    assert_or_panic(v[0] == 54);
    assert_or_panic(v[1] == 55);
    assert_or_panic(v[2] == 56);
    assert_or_panic(v[3] == 57);
    assert_or_panic(v[4] == 58);
    assert_or_panic(v[5] == 59);
    assert_or_panic(v[6] == 60);
    assert_or_panic(v[7] == 61);
    assert_or_panic(v[8] == 62);
    assert_or_panic(v[9] == 63);
    assert_or_panic(v[10] == 64);
    assert_or_panic(v[11] == 65);
    assert_or_panic(v[12] == 66);
    assert_or_panic(v[13] == 67);
    assert_or_panic(v[14] == 68);
    assert_or_panic(v[15] == 69);
    assert_or_panic(v[16] == 70);
    assert_or_panic(v[17] == 71);
    assert_or_panic(v[18] == 72);
    assert_or_panic(v[19] == 73);
    assert_or_panic(v[20] == 74);
    assert_or_panic(v[21] == 75);
    assert_or_panic(v[22] == 76);
    assert_or_panic(v[23] == 77);
    assert_or_panic(v[24] == 78);
    assert_or_panic(v[25] == 79);
    assert_or_panic(v[26] == 80);
    assert_or_panic(v[27] == 81);
    assert_or_panic(v[28] == 82);
    assert_or_panic(v[29] == 83);
    assert_or_panic(v[30] == 84);
    assert_or_panic(v[31] == 85);
    assert_or_panic(v[32] == 86);
    assert_or_panic(v[33] == 87);
    assert_or_panic(v[34] == 88);
    assert_or_panic(v[35] == 89);
    assert_or_panic(v[36] == 90);
    assert_or_panic(v[37] == 91);
    assert_or_panic(v[38] == 92);
    assert_or_panic(v[39] == 93);
    assert_or_panic(v[40] == 94);
    assert_or_panic(v[41] == 95);
    assert_or_panic(v[42] == 96);
    assert_or_panic(v[43] == 97);
    assert_or_panic(v[44] == 98);
    assert_or_panic(v[45] == 99);
    assert_or_panic(v[46] == 0);
    assert_or_panic(v[47] == 1);
    assert_or_panic(v[48] == 2);
    assert_or_panic(v[49] == 3);
    assert_or_panic(v[50] == 4);
    assert_or_panic(v[51] == 5);
    assert_or_panic(v[52] == 6);
    assert_or_panic(v[53] == 7);
    assert_or_panic(v[54] == 8);
    assert_or_panic(v[55] == 9);
    assert_or_panic(v[56] == 10);
    assert_or_panic(v[57] == 11);
    assert_or_panic(v[58] == 12);
    assert_or_panic(v[59] == 13);
    assert_or_panic(v[60] == 14);
    assert_or_panic(v[61] == 15);
    assert_or_panic(v[62] == 16);
    assert_or_panic(v[63] == 17);
    assert_or_panic(v[64] == 18);
    assert_or_panic(v[65] == 19);
    assert_or_panic(v[66] == 20);
    assert_or_panic(v[67] == 21);
    assert_or_panic(v[68] == 22);
    assert_or_panic(v[69] == 23);
    assert_or_panic(v[70] == 24);
    assert_or_panic(v[71] == 25);
    assert_or_panic(v[72] == 26);
    assert_or_panic(v[73] == 27);
    assert_or_panic(v[74] == 28);
    assert_or_panic(v[75] == 29);
    assert_or_panic(v[76] == 30);
    assert_or_panic(v[77] == 31);
    assert_or_panic(v[78] == 32);
    assert_or_panic(v[79] == 33);
    assert_or_panic(v[80] == 34);
    assert_or_panic(v[81] == 35);
    assert_or_panic(v[82] == 36);
    assert_or_panic(v[83] == 37);
    assert_or_panic(v[84] == 38);
    assert_or_panic(v[85] == 39);
    assert_or_panic(v[86] == 40);
    assert_or_panic(v[87] == 41);
    assert_or_panic(v[88] == 42);
    assert_or_panic(v[89] == 43);
    assert_or_panic(v[90] == 44);
    assert_or_panic(v[91] == 45);
    assert_or_panic(v[92] == 46);
    assert_or_panic(v[93] == 47);
    assert_or_panic(v[94] == 48);
    assert_or_panic(v[95] == 49);
    assert_or_panic(v[96] == 50);
    assert_or_panic(v[97] == 51);
    assert_or_panic(v[98] == 52);
    assert_or_panic(v[99] == 53);
    assert_or_panic(v[100] == 54);
    assert_or_panic(v[101] == 55);
    assert_or_panic(v[102] == 56);
    assert_or_panic(v[103] == 57);
    assert_or_panic(v[104] == 58);
    assert_or_panic(v[105] == 59);
    assert_or_panic(v[106] == 60);
    assert_or_panic(v[107] == 61);
    assert_or_panic(v[108] == 62);
    assert_or_panic(v[109] == 63);
    assert_or_panic(v[110] == 64);
    assert_or_panic(v[111] == 65);
    assert_or_panic(v[112] == 66);
    assert_or_panic(v[113] == 67);
    assert_or_panic(v[114] == 68);
    assert_or_panic(v[115] == 69);
    assert_or_panic(v[116] == 70);
    assert_or_panic(v[117] == 71);
    assert_or_panic(v[118] == 72);
    assert_or_panic(v[119] == 73);
    assert_or_panic(v[120] == 74);
    assert_or_panic(v[121] == 75);
    assert_or_panic(v[122] == 76);
    assert_or_panic(v[123] == 77);
    assert_or_panic(v[124] == 78);
    assert_or_panic(v[125] == 79);
    assert_or_panic(v[126] == 80);
    assert_or_panic(v[127] == 81);
    assert_or_panic(v[128] == 82);
    assert_or_panic(v[129] == 83);
    assert_or_panic(v[130] == 84);
    assert_or_panic(v[131] == 85);
    assert_or_panic(v[132] == 86);
    assert_or_panic(v[133] == 87);
    assert_or_panic(v[134] == 88);
    assert_or_panic(v[135] == 89);
    assert_or_panic(v[136] == 90);
    assert_or_panic(v[137] == 91);
    assert_or_panic(v[138] == 92);
    assert_or_panic(v[139] == 93);
    assert_or_panic(v[140] == 94);
    assert_or_panic(v[141] == 95);
    assert_or_panic(v[142] == 96);
    assert_or_panic(v[143] == 97);
    assert_or_panic(v[144] == 98);
    assert_or_panic(v[145] == 99);
    assert_or_panic(v[146] == 0);
    assert_or_panic(v[147] == 1);
    assert_or_panic(v[148] == 2);
    assert_or_panic(v[149] == 3);
    assert_or_panic(v[150] == 4);
    assert_or_panic(v[151] == 5);
    assert_or_panic(v[152] == 6);
    assert_or_panic(v[153] == 7);
    assert_or_panic(v[154] == 8);
    assert_or_panic(v[155] == 9);
    assert_or_panic(v[156] == 10);
    assert_or_panic(v[157] == 11);
    assert_or_panic(v[158] == 12);
    assert_or_panic(v[159] == 13);
    assert_or_panic(v[160] == 14);
    assert_or_panic(v[161] == 15);
    assert_or_panic(v[162] == 16);
    assert_or_panic(v[163] == 17);
    assert_or_panic(v[164] == 18);
    assert_or_panic(v[165] == 19);
    assert_or_panic(v[166] == 20);
    assert_or_panic(v[167] == 21);
    assert_or_panic(v[168] == 22);
    assert_or_panic(v[169] == 23);
    assert_or_panic(v[170] == 24);
    assert_or_panic(v[171] == 25);
    assert_or_panic(v[172] == 26);
    assert_or_panic(v[173] == 27);
    assert_or_panic(v[174] == 28);
    assert_or_panic(v[175] == 29);
    assert_or_panic(v[176] == 30);
    assert_or_panic(v[177] == 31);
    assert_or_panic(v[178] == 32);
    assert_or_panic(v[179] == 33);
    assert_or_panic(v[180] == 34);
    assert_or_panic(v[181] == 35);
    assert_or_panic(v[182] == 36);
    assert_or_panic(v[183] == 37);
    assert_or_panic(v[184] == 38);
    assert_or_panic(v[185] == 39);
    assert_or_panic(v[186] == 40);
    assert_or_panic(v[187] == 41);
    assert_or_panic(v[188] == 42);
    assert_or_panic(v[189] == 43);
    assert_or_panic(v[190] == 44);
    assert_or_panic(v[191] == 45);
    assert_or_panic(v[192] == 46);
    assert_or_panic(v[193] == 47);
    assert_or_panic(v[194] == 48);
    assert_or_panic(v[195] == 49);
    assert_or_panic(v[196] == 50);
    assert_or_panic(v[197] == 51);
    assert_or_panic(v[198] == 52);
    assert_or_panic(v[199] == 53);
    assert_or_panic(v[200] == 54);
    assert_or_panic(v[201] == 55);
    assert_or_panic(v[202] == 56);
    assert_or_panic(v[203] == 57);
    assert_or_panic(v[204] == 58);
    assert_or_panic(v[205] == 59);
    assert_or_panic(v[206] == 60);
    assert_or_panic(v[207] == 61);
    assert_or_panic(v[208] == 62);
    assert_or_panic(v[209] == 63);
    assert_or_panic(v[210] == 64);
    assert_or_panic(v[211] == 65);
    assert_or_panic(v[212] == 66);
    assert_or_panic(v[213] == 67);
    assert_or_panic(v[214] == 68);
    assert_or_panic(v[215] == 69);
    assert_or_panic(v[216] == 70);
    assert_or_panic(v[217] == 71);
    assert_or_panic(v[218] == 72);
    assert_or_panic(v[219] == 73);
    assert_or_panic(v[220] == 74);
    assert_or_panic(v[221] == 75);
    assert_or_panic(v[222] == 76);
    assert_or_panic(v[223] == 77);
    assert_or_panic(v[224] == 78);
    assert_or_panic(v[225] == 79);
    assert_or_panic(v[226] == 80);
    assert_or_panic(v[227] == 81);
    assert_or_panic(v[228] == 82);
    assert_or_panic(v[229] == 83);
    assert_or_panic(v[230] == 84);
    assert_or_panic(v[231] == 85);
    assert_or_panic(v[232] == 86);
    assert_or_panic(v[233] == 87);
    assert_or_panic(v[234] == 88);
    assert_or_panic(v[235] == 89);
    assert_or_panic(v[236] == 90);
    assert_or_panic(v[237] == 91);
    assert_or_panic(v[238] == 92);
    assert_or_panic(v[239] == 93);
    assert_or_panic(v[240] == 94);
    assert_or_panic(v[241] == 95);
    assert_or_panic(v[242] == 96);
    assert_or_panic(v[243] == 97);
    assert_or_panic(v[244] == 98);
    assert_or_panic(v[245] == 99);
    assert_or_panic(v[246] == 0);
    assert_or_panic(v[247] == 1);
    assert_or_panic(v[248] == 2);
    assert_or_panic(v[249] == 3);
    assert_or_panic(v[250] == 4);
    assert_or_panic(v[251] == 5);
    assert_or_panic(v[252] == 6);
    assert_or_panic(v[253] == 7);
    assert_or_panic(v[254] == 8);
    assert_or_panic(v[255] == 9);
    zig_vector_256_u8((Vector_256_u8){
        10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,
        26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41,
        42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
        58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73,
        74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89,
        90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,  1,  2,  3,  4,  5,
        6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
        22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37,
        38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53,
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69,
        70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85,
        86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,  1,
        2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17,
        18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33,
        34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
        50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65,
    }, 256);
}

typedef uint8_t Vector_384_u8 __attribute__((vector_size(384 * sizeof(uint8_t))));

Vector_384_u8 zig_ret_vector_384_u8(void);
void zig_vector_384_u8(Vector_384_u8, size_t);

Vector_384_u8 c_ret_vector_384_u8(void) {
    return (Vector_384_u8){
        46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61,
        62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77,
        78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93,
        94, 95, 96, 97, 98, 99, 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,
        10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,
        26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41,
        42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
        58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73,
        74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89,
        90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,  1,  2,  3,  4,  5,
        6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
        22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37,
        38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53,
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69,
        70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85,
        86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,  1,
        2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17,
        18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33,
        34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
        50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65,
        66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81,
        82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97,
        98, 99, 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13,
        14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
    };
}
void c_vector_384_u8(Vector_384_u8 v, size_t i) {
    assert_or_panic(v[0] == 30);
    assert_or_panic(v[1] == 31);
    assert_or_panic(v[2] == 32);
    assert_or_panic(v[3] == 33);
    assert_or_panic(v[4] == 34);
    assert_or_panic(v[5] == 35);
    assert_or_panic(v[6] == 36);
    assert_or_panic(v[7] == 37);
    assert_or_panic(v[8] == 38);
    assert_or_panic(v[9] == 39);
    assert_or_panic(v[10] == 40);
    assert_or_panic(v[11] == 41);
    assert_or_panic(v[12] == 42);
    assert_or_panic(v[13] == 43);
    assert_or_panic(v[14] == 44);
    assert_or_panic(v[15] == 45);
    assert_or_panic(v[16] == 46);
    assert_or_panic(v[17] == 47);
    assert_or_panic(v[18] == 48);
    assert_or_panic(v[19] == 49);
    assert_or_panic(v[20] == 50);
    assert_or_panic(v[21] == 51);
    assert_or_panic(v[22] == 52);
    assert_or_panic(v[23] == 53);
    assert_or_panic(v[24] == 54);
    assert_or_panic(v[25] == 55);
    assert_or_panic(v[26] == 56);
    assert_or_panic(v[27] == 57);
    assert_or_panic(v[28] == 58);
    assert_or_panic(v[29] == 59);
    assert_or_panic(v[30] == 60);
    assert_or_panic(v[31] == 61);
    assert_or_panic(v[32] == 62);
    assert_or_panic(v[33] == 63);
    assert_or_panic(v[34] == 64);
    assert_or_panic(v[35] == 65);
    assert_or_panic(v[36] == 66);
    assert_or_panic(v[37] == 67);
    assert_or_panic(v[38] == 68);
    assert_or_panic(v[39] == 69);
    assert_or_panic(v[40] == 70);
    assert_or_panic(v[41] == 71);
    assert_or_panic(v[42] == 72);
    assert_or_panic(v[43] == 73);
    assert_or_panic(v[44] == 74);
    assert_or_panic(v[45] == 75);
    assert_or_panic(v[46] == 76);
    assert_or_panic(v[47] == 77);
    assert_or_panic(v[48] == 78);
    assert_or_panic(v[49] == 79);
    assert_or_panic(v[50] == 80);
    assert_or_panic(v[51] == 81);
    assert_or_panic(v[52] == 82);
    assert_or_panic(v[53] == 83);
    assert_or_panic(v[54] == 84);
    assert_or_panic(v[55] == 85);
    assert_or_panic(v[56] == 86);
    assert_or_panic(v[57] == 87);
    assert_or_panic(v[58] == 88);
    assert_or_panic(v[59] == 89);
    assert_or_panic(v[60] == 90);
    assert_or_panic(v[61] == 91);
    assert_or_panic(v[62] == 92);
    assert_or_panic(v[63] == 93);
    assert_or_panic(v[64] == 94);
    assert_or_panic(v[65] == 95);
    assert_or_panic(v[66] == 96);
    assert_or_panic(v[67] == 97);
    assert_or_panic(v[68] == 98);
    assert_or_panic(v[69] == 99);
    assert_or_panic(v[70] == 0);
    assert_or_panic(v[71] == 1);
    assert_or_panic(v[72] == 2);
    assert_or_panic(v[73] == 3);
    assert_or_panic(v[74] == 4);
    assert_or_panic(v[75] == 5);
    assert_or_panic(v[76] == 6);
    assert_or_panic(v[77] == 7);
    assert_or_panic(v[78] == 8);
    assert_or_panic(v[79] == 9);
    assert_or_panic(v[80] == 10);
    assert_or_panic(v[81] == 11);
    assert_or_panic(v[82] == 12);
    assert_or_panic(v[83] == 13);
    assert_or_panic(v[84] == 14);
    assert_or_panic(v[85] == 15);
    assert_or_panic(v[86] == 16);
    assert_or_panic(v[87] == 17);
    assert_or_panic(v[88] == 18);
    assert_or_panic(v[89] == 19);
    assert_or_panic(v[90] == 20);
    assert_or_panic(v[91] == 21);
    assert_or_panic(v[92] == 22);
    assert_or_panic(v[93] == 23);
    assert_or_panic(v[94] == 24);
    assert_or_panic(v[95] == 25);
    assert_or_panic(v[96] == 26);
    assert_or_panic(v[97] == 27);
    assert_or_panic(v[98] == 28);
    assert_or_panic(v[99] == 29);
    assert_or_panic(v[100] == 30);
    assert_or_panic(v[101] == 31);
    assert_or_panic(v[102] == 32);
    assert_or_panic(v[103] == 33);
    assert_or_panic(v[104] == 34);
    assert_or_panic(v[105] == 35);
    assert_or_panic(v[106] == 36);
    assert_or_panic(v[107] == 37);
    assert_or_panic(v[108] == 38);
    assert_or_panic(v[109] == 39);
    assert_or_panic(v[110] == 40);
    assert_or_panic(v[111] == 41);
    assert_or_panic(v[112] == 42);
    assert_or_panic(v[113] == 43);
    assert_or_panic(v[114] == 44);
    assert_or_panic(v[115] == 45);
    assert_or_panic(v[116] == 46);
    assert_or_panic(v[117] == 47);
    assert_or_panic(v[118] == 48);
    assert_or_panic(v[119] == 49);
    assert_or_panic(v[120] == 50);
    assert_or_panic(v[121] == 51);
    assert_or_panic(v[122] == 52);
    assert_or_panic(v[123] == 53);
    assert_or_panic(v[124] == 54);
    assert_or_panic(v[125] == 55);
    assert_or_panic(v[126] == 56);
    assert_or_panic(v[127] == 57);
    assert_or_panic(v[128] == 58);
    assert_or_panic(v[129] == 59);
    assert_or_panic(v[130] == 60);
    assert_or_panic(v[131] == 61);
    assert_or_panic(v[132] == 62);
    assert_or_panic(v[133] == 63);
    assert_or_panic(v[134] == 64);
    assert_or_panic(v[135] == 65);
    assert_or_panic(v[136] == 66);
    assert_or_panic(v[137] == 67);
    assert_or_panic(v[138] == 68);
    assert_or_panic(v[139] == 69);
    assert_or_panic(v[140] == 70);
    assert_or_panic(v[141] == 71);
    assert_or_panic(v[142] == 72);
    assert_or_panic(v[143] == 73);
    assert_or_panic(v[144] == 74);
    assert_or_panic(v[145] == 75);
    assert_or_panic(v[146] == 76);
    assert_or_panic(v[147] == 77);
    assert_or_panic(v[148] == 78);
    assert_or_panic(v[149] == 79);
    assert_or_panic(v[150] == 80);
    assert_or_panic(v[151] == 81);
    assert_or_panic(v[152] == 82);
    assert_or_panic(v[153] == 83);
    assert_or_panic(v[154] == 84);
    assert_or_panic(v[155] == 85);
    assert_or_panic(v[156] == 86);
    assert_or_panic(v[157] == 87);
    assert_or_panic(v[158] == 88);
    assert_or_panic(v[159] == 89);
    assert_or_panic(v[160] == 90);
    assert_or_panic(v[161] == 91);
    assert_or_panic(v[162] == 92);
    assert_or_panic(v[163] == 93);
    assert_or_panic(v[164] == 94);
    assert_or_panic(v[165] == 95);
    assert_or_panic(v[166] == 96);
    assert_or_panic(v[167] == 97);
    assert_or_panic(v[168] == 98);
    assert_or_panic(v[169] == 99);
    assert_or_panic(v[170] == 0);
    assert_or_panic(v[171] == 1);
    assert_or_panic(v[172] == 2);
    assert_or_panic(v[173] == 3);
    assert_or_panic(v[174] == 4);
    assert_or_panic(v[175] == 5);
    assert_or_panic(v[176] == 6);
    assert_or_panic(v[177] == 7);
    assert_or_panic(v[178] == 8);
    assert_or_panic(v[179] == 9);
    assert_or_panic(v[180] == 10);
    assert_or_panic(v[181] == 11);
    assert_or_panic(v[182] == 12);
    assert_or_panic(v[183] == 13);
    assert_or_panic(v[184] == 14);
    assert_or_panic(v[185] == 15);
    assert_or_panic(v[186] == 16);
    assert_or_panic(v[187] == 17);
    assert_or_panic(v[188] == 18);
    assert_or_panic(v[189] == 19);
    assert_or_panic(v[190] == 20);
    assert_or_panic(v[191] == 21);
    assert_or_panic(v[192] == 22);
    assert_or_panic(v[193] == 23);
    assert_or_panic(v[194] == 24);
    assert_or_panic(v[195] == 25);
    assert_or_panic(v[196] == 26);
    assert_or_panic(v[197] == 27);
    assert_or_panic(v[198] == 28);
    assert_or_panic(v[199] == 29);
    assert_or_panic(v[200] == 30);
    assert_or_panic(v[201] == 31);
    assert_or_panic(v[202] == 32);
    assert_or_panic(v[203] == 33);
    assert_or_panic(v[204] == 34);
    assert_or_panic(v[205] == 35);
    assert_or_panic(v[206] == 36);
    assert_or_panic(v[207] == 37);
    assert_or_panic(v[208] == 38);
    assert_or_panic(v[209] == 39);
    assert_or_panic(v[210] == 40);
    assert_or_panic(v[211] == 41);
    assert_or_panic(v[212] == 42);
    assert_or_panic(v[213] == 43);
    assert_or_panic(v[214] == 44);
    assert_or_panic(v[215] == 45);
    assert_or_panic(v[216] == 46);
    assert_or_panic(v[217] == 47);
    assert_or_panic(v[218] == 48);
    assert_or_panic(v[219] == 49);
    assert_or_panic(v[220] == 50);
    assert_or_panic(v[221] == 51);
    assert_or_panic(v[222] == 52);
    assert_or_panic(v[223] == 53);
    assert_or_panic(v[224] == 54);
    assert_or_panic(v[225] == 55);
    assert_or_panic(v[226] == 56);
    assert_or_panic(v[227] == 57);
    assert_or_panic(v[228] == 58);
    assert_or_panic(v[229] == 59);
    assert_or_panic(v[230] == 60);
    assert_or_panic(v[231] == 61);
    assert_or_panic(v[232] == 62);
    assert_or_panic(v[233] == 63);
    assert_or_panic(v[234] == 64);
    assert_or_panic(v[235] == 65);
    assert_or_panic(v[236] == 66);
    assert_or_panic(v[237] == 67);
    assert_or_panic(v[238] == 68);
    assert_or_panic(v[239] == 69);
    assert_or_panic(v[240] == 70);
    assert_or_panic(v[241] == 71);
    assert_or_panic(v[242] == 72);
    assert_or_panic(v[243] == 73);
    assert_or_panic(v[244] == 74);
    assert_or_panic(v[245] == 75);
    assert_or_panic(v[246] == 76);
    assert_or_panic(v[247] == 77);
    assert_or_panic(v[248] == 78);
    assert_or_panic(v[249] == 79);
    assert_or_panic(v[250] == 80);
    assert_or_panic(v[251] == 81);
    assert_or_panic(v[252] == 82);
    assert_or_panic(v[253] == 83);
    assert_or_panic(v[254] == 84);
    assert_or_panic(v[255] == 85);
    assert_or_panic(v[256] == 86);
    assert_or_panic(v[257] == 87);
    assert_or_panic(v[258] == 88);
    assert_or_panic(v[259] == 89);
    assert_or_panic(v[260] == 90);
    assert_or_panic(v[261] == 91);
    assert_or_panic(v[262] == 92);
    assert_or_panic(v[263] == 93);
    assert_or_panic(v[264] == 94);
    assert_or_panic(v[265] == 95);
    assert_or_panic(v[266] == 96);
    assert_or_panic(v[267] == 97);
    assert_or_panic(v[268] == 98);
    assert_or_panic(v[269] == 99);
    assert_or_panic(v[270] == 0);
    assert_or_panic(v[271] == 1);
    assert_or_panic(v[272] == 2);
    assert_or_panic(v[273] == 3);
    assert_or_panic(v[274] == 4);
    assert_or_panic(v[275] == 5);
    assert_or_panic(v[276] == 6);
    assert_or_panic(v[277] == 7);
    assert_or_panic(v[278] == 8);
    assert_or_panic(v[279] == 9);
    assert_or_panic(v[280] == 10);
    assert_or_panic(v[281] == 11);
    assert_or_panic(v[282] == 12);
    assert_or_panic(v[283] == 13);
    assert_or_panic(v[284] == 14);
    assert_or_panic(v[285] == 15);
    assert_or_panic(v[286] == 16);
    assert_or_panic(v[287] == 17);
    assert_or_panic(v[288] == 18);
    assert_or_panic(v[289] == 19);
    assert_or_panic(v[290] == 20);
    assert_or_panic(v[291] == 21);
    assert_or_panic(v[292] == 22);
    assert_or_panic(v[293] == 23);
    assert_or_panic(v[294] == 24);
    assert_or_panic(v[295] == 25);
    assert_or_panic(v[296] == 26);
    assert_or_panic(v[297] == 27);
    assert_or_panic(v[298] == 28);
    assert_or_panic(v[299] == 29);
    assert_or_panic(v[300] == 30);
    assert_or_panic(v[301] == 31);
    assert_or_panic(v[302] == 32);
    assert_or_panic(v[303] == 33);
    assert_or_panic(v[304] == 34);
    assert_or_panic(v[305] == 35);
    assert_or_panic(v[306] == 36);
    assert_or_panic(v[307] == 37);
    assert_or_panic(v[308] == 38);
    assert_or_panic(v[309] == 39);
    assert_or_panic(v[310] == 40);
    assert_or_panic(v[311] == 41);
    assert_or_panic(v[312] == 42);
    assert_or_panic(v[313] == 43);
    assert_or_panic(v[314] == 44);
    assert_or_panic(v[315] == 45);
    assert_or_panic(v[316] == 46);
    assert_or_panic(v[317] == 47);
    assert_or_panic(v[318] == 48);
    assert_or_panic(v[319] == 49);
    assert_or_panic(v[320] == 50);
    assert_or_panic(v[321] == 51);
    assert_or_panic(v[322] == 52);
    assert_or_panic(v[323] == 53);
    assert_or_panic(v[324] == 54);
    assert_or_panic(v[325] == 55);
    assert_or_panic(v[326] == 56);
    assert_or_panic(v[327] == 57);
    assert_or_panic(v[328] == 58);
    assert_or_panic(v[329] == 59);
    assert_or_panic(v[330] == 60);
    assert_or_panic(v[331] == 61);
    assert_or_panic(v[332] == 62);
    assert_or_panic(v[333] == 63);
    assert_or_panic(v[334] == 64);
    assert_or_panic(v[335] == 65);
    assert_or_panic(v[336] == 66);
    assert_or_panic(v[337] == 67);
    assert_or_panic(v[338] == 68);
    assert_or_panic(v[339] == 69);
    assert_or_panic(v[340] == 70);
    assert_or_panic(v[341] == 71);
    assert_or_panic(v[342] == 72);
    assert_or_panic(v[343] == 73);
    assert_or_panic(v[344] == 74);
    assert_or_panic(v[345] == 75);
    assert_or_panic(v[346] == 76);
    assert_or_panic(v[347] == 77);
    assert_or_panic(v[348] == 78);
    assert_or_panic(v[349] == 79);
    assert_or_panic(v[350] == 80);
    assert_or_panic(v[351] == 81);
    assert_or_panic(v[352] == 82);
    assert_or_panic(v[353] == 83);
    assert_or_panic(v[354] == 84);
    assert_or_panic(v[355] == 85);
    assert_or_panic(v[356] == 86);
    assert_or_panic(v[357] == 87);
    assert_or_panic(v[358] == 88);
    assert_or_panic(v[359] == 89);
    assert_or_panic(v[360] == 90);
    assert_or_panic(v[361] == 91);
    assert_or_panic(v[362] == 92);
    assert_or_panic(v[363] == 93);
    assert_or_panic(v[364] == 94);
    assert_or_panic(v[365] == 95);
    assert_or_panic(v[366] == 96);
    assert_or_panic(v[367] == 97);
    assert_or_panic(v[368] == 98);
    assert_or_panic(v[369] == 99);
    assert_or_panic(v[370] == 0);
    assert_or_panic(v[371] == 1);
    assert_or_panic(v[372] == 2);
    assert_or_panic(v[373] == 3);
    assert_or_panic(v[374] == 4);
    assert_or_panic(v[375] == 5);
    assert_or_panic(v[376] == 6);
    assert_or_panic(v[377] == 7);
    assert_or_panic(v[378] == 8);
    assert_or_panic(v[379] == 9);
    assert_or_panic(v[380] == 10);
    assert_or_panic(v[381] == 11);
    assert_or_panic(v[382] == 12);
    assert_or_panic(v[383] == 13);
    assert_or_panic(i == 384);
}
void c_test_vector_384_u8(void) {
    Vector_384_u8 v = zig_ret_vector_384_u8();
    assert_or_panic(v[0] == 78);
    assert_or_panic(v[1] == 79);
    assert_or_panic(v[2] == 80);
    assert_or_panic(v[3] == 81);
    assert_or_panic(v[4] == 82);
    assert_or_panic(v[5] == 83);
    assert_or_panic(v[6] == 84);
    assert_or_panic(v[7] == 85);
    assert_or_panic(v[8] == 86);
    assert_or_panic(v[9] == 87);
    assert_or_panic(v[10] == 88);
    assert_or_panic(v[11] == 89);
    assert_or_panic(v[12] == 90);
    assert_or_panic(v[13] == 91);
    assert_or_panic(v[14] == 92);
    assert_or_panic(v[15] == 93);
    assert_or_panic(v[16] == 94);
    assert_or_panic(v[17] == 95);
    assert_or_panic(v[18] == 96);
    assert_or_panic(v[19] == 97);
    assert_or_panic(v[20] == 98);
    assert_or_panic(v[21] == 99);
    assert_or_panic(v[22] == 0);
    assert_or_panic(v[23] == 1);
    assert_or_panic(v[24] == 2);
    assert_or_panic(v[25] == 3);
    assert_or_panic(v[26] == 4);
    assert_or_panic(v[27] == 5);
    assert_or_panic(v[28] == 6);
    assert_or_panic(v[29] == 7);
    assert_or_panic(v[30] == 8);
    assert_or_panic(v[31] == 9);
    assert_or_panic(v[32] == 10);
    assert_or_panic(v[33] == 11);
    assert_or_panic(v[34] == 12);
    assert_or_panic(v[35] == 13);
    assert_or_panic(v[36] == 14);
    assert_or_panic(v[37] == 15);
    assert_or_panic(v[38] == 16);
    assert_or_panic(v[39] == 17);
    assert_or_panic(v[40] == 18);
    assert_or_panic(v[41] == 19);
    assert_or_panic(v[42] == 20);
    assert_or_panic(v[43] == 21);
    assert_or_panic(v[44] == 22);
    assert_or_panic(v[45] == 23);
    assert_or_panic(v[46] == 24);
    assert_or_panic(v[47] == 25);
    assert_or_panic(v[48] == 26);
    assert_or_panic(v[49] == 27);
    assert_or_panic(v[50] == 28);
    assert_or_panic(v[51] == 29);
    assert_or_panic(v[52] == 30);
    assert_or_panic(v[53] == 31);
    assert_or_panic(v[54] == 32);
    assert_or_panic(v[55] == 33);
    assert_or_panic(v[56] == 34);
    assert_or_panic(v[57] == 35);
    assert_or_panic(v[58] == 36);
    assert_or_panic(v[59] == 37);
    assert_or_panic(v[60] == 38);
    assert_or_panic(v[61] == 39);
    assert_or_panic(v[62] == 40);
    assert_or_panic(v[63] == 41);
    assert_or_panic(v[64] == 42);
    assert_or_panic(v[65] == 43);
    assert_or_panic(v[66] == 44);
    assert_or_panic(v[67] == 45);
    assert_or_panic(v[68] == 46);
    assert_or_panic(v[69] == 47);
    assert_or_panic(v[70] == 48);
    assert_or_panic(v[71] == 49);
    assert_or_panic(v[72] == 50);
    assert_or_panic(v[73] == 51);
    assert_or_panic(v[74] == 52);
    assert_or_panic(v[75] == 53);
    assert_or_panic(v[76] == 54);
    assert_or_panic(v[77] == 55);
    assert_or_panic(v[78] == 56);
    assert_or_panic(v[79] == 57);
    assert_or_panic(v[80] == 58);
    assert_or_panic(v[81] == 59);
    assert_or_panic(v[82] == 60);
    assert_or_panic(v[83] == 61);
    assert_or_panic(v[84] == 62);
    assert_or_panic(v[85] == 63);
    assert_or_panic(v[86] == 64);
    assert_or_panic(v[87] == 65);
    assert_or_panic(v[88] == 66);
    assert_or_panic(v[89] == 67);
    assert_or_panic(v[90] == 68);
    assert_or_panic(v[91] == 69);
    assert_or_panic(v[92] == 70);
    assert_or_panic(v[93] == 71);
    assert_or_panic(v[94] == 72);
    assert_or_panic(v[95] == 73);
    assert_or_panic(v[96] == 74);
    assert_or_panic(v[97] == 75);
    assert_or_panic(v[98] == 76);
    assert_or_panic(v[99] == 77);
    assert_or_panic(v[100] == 78);
    assert_or_panic(v[101] == 79);
    assert_or_panic(v[102] == 80);
    assert_or_panic(v[103] == 81);
    assert_or_panic(v[104] == 82);
    assert_or_panic(v[105] == 83);
    assert_or_panic(v[106] == 84);
    assert_or_panic(v[107] == 85);
    assert_or_panic(v[108] == 86);
    assert_or_panic(v[109] == 87);
    assert_or_panic(v[110] == 88);
    assert_or_panic(v[111] == 89);
    assert_or_panic(v[112] == 90);
    assert_or_panic(v[113] == 91);
    assert_or_panic(v[114] == 92);
    assert_or_panic(v[115] == 93);
    assert_or_panic(v[116] == 94);
    assert_or_panic(v[117] == 95);
    assert_or_panic(v[118] == 96);
    assert_or_panic(v[119] == 97);
    assert_or_panic(v[120] == 98);
    assert_or_panic(v[121] == 99);
    assert_or_panic(v[122] == 0);
    assert_or_panic(v[123] == 1);
    assert_or_panic(v[124] == 2);
    assert_or_panic(v[125] == 3);
    assert_or_panic(v[126] == 4);
    assert_or_panic(v[127] == 5);
    assert_or_panic(v[128] == 6);
    assert_or_panic(v[129] == 7);
    assert_or_panic(v[130] == 8);
    assert_or_panic(v[131] == 9);
    assert_or_panic(v[132] == 10);
    assert_or_panic(v[133] == 11);
    assert_or_panic(v[134] == 12);
    assert_or_panic(v[135] == 13);
    assert_or_panic(v[136] == 14);
    assert_or_panic(v[137] == 15);
    assert_or_panic(v[138] == 16);
    assert_or_panic(v[139] == 17);
    assert_or_panic(v[140] == 18);
    assert_or_panic(v[141] == 19);
    assert_or_panic(v[142] == 20);
    assert_or_panic(v[143] == 21);
    assert_or_panic(v[144] == 22);
    assert_or_panic(v[145] == 23);
    assert_or_panic(v[146] == 24);
    assert_or_panic(v[147] == 25);
    assert_or_panic(v[148] == 26);
    assert_or_panic(v[149] == 27);
    assert_or_panic(v[150] == 28);
    assert_or_panic(v[151] == 29);
    assert_or_panic(v[152] == 30);
    assert_or_panic(v[153] == 31);
    assert_or_panic(v[154] == 32);
    assert_or_panic(v[155] == 33);
    assert_or_panic(v[156] == 34);
    assert_or_panic(v[157] == 35);
    assert_or_panic(v[158] == 36);
    assert_or_panic(v[159] == 37);
    assert_or_panic(v[160] == 38);
    assert_or_panic(v[161] == 39);
    assert_or_panic(v[162] == 40);
    assert_or_panic(v[163] == 41);
    assert_or_panic(v[164] == 42);
    assert_or_panic(v[165] == 43);
    assert_or_panic(v[166] == 44);
    assert_or_panic(v[167] == 45);
    assert_or_panic(v[168] == 46);
    assert_or_panic(v[169] == 47);
    assert_or_panic(v[170] == 48);
    assert_or_panic(v[171] == 49);
    assert_or_panic(v[172] == 50);
    assert_or_panic(v[173] == 51);
    assert_or_panic(v[174] == 52);
    assert_or_panic(v[175] == 53);
    assert_or_panic(v[176] == 54);
    assert_or_panic(v[177] == 55);
    assert_or_panic(v[178] == 56);
    assert_or_panic(v[179] == 57);
    assert_or_panic(v[180] == 58);
    assert_or_panic(v[181] == 59);
    assert_or_panic(v[182] == 60);
    assert_or_panic(v[183] == 61);
    assert_or_panic(v[184] == 62);
    assert_or_panic(v[185] == 63);
    assert_or_panic(v[186] == 64);
    assert_or_panic(v[187] == 65);
    assert_or_panic(v[188] == 66);
    assert_or_panic(v[189] == 67);
    assert_or_panic(v[190] == 68);
    assert_or_panic(v[191] == 69);
    assert_or_panic(v[192] == 70);
    assert_or_panic(v[193] == 71);
    assert_or_panic(v[194] == 72);
    assert_or_panic(v[195] == 73);
    assert_or_panic(v[196] == 74);
    assert_or_panic(v[197] == 75);
    assert_or_panic(v[198] == 76);
    assert_or_panic(v[199] == 77);
    assert_or_panic(v[200] == 78);
    assert_or_panic(v[201] == 79);
    assert_or_panic(v[202] == 80);
    assert_or_panic(v[203] == 81);
    assert_or_panic(v[204] == 82);
    assert_or_panic(v[205] == 83);
    assert_or_panic(v[206] == 84);
    assert_or_panic(v[207] == 85);
    assert_or_panic(v[208] == 86);
    assert_or_panic(v[209] == 87);
    assert_or_panic(v[210] == 88);
    assert_or_panic(v[211] == 89);
    assert_or_panic(v[212] == 90);
    assert_or_panic(v[213] == 91);
    assert_or_panic(v[214] == 92);
    assert_or_panic(v[215] == 93);
    assert_or_panic(v[216] == 94);
    assert_or_panic(v[217] == 95);
    assert_or_panic(v[218] == 96);
    assert_or_panic(v[219] == 97);
    assert_or_panic(v[220] == 98);
    assert_or_panic(v[221] == 99);
    assert_or_panic(v[222] == 0);
    assert_or_panic(v[223] == 1);
    assert_or_panic(v[224] == 2);
    assert_or_panic(v[225] == 3);
    assert_or_panic(v[226] == 4);
    assert_or_panic(v[227] == 5);
    assert_or_panic(v[228] == 6);
    assert_or_panic(v[229] == 7);
    assert_or_panic(v[230] == 8);
    assert_or_panic(v[231] == 9);
    assert_or_panic(v[232] == 10);
    assert_or_panic(v[233] == 11);
    assert_or_panic(v[234] == 12);
    assert_or_panic(v[235] == 13);
    assert_or_panic(v[236] == 14);
    assert_or_panic(v[237] == 15);
    assert_or_panic(v[238] == 16);
    assert_or_panic(v[239] == 17);
    assert_or_panic(v[240] == 18);
    assert_or_panic(v[241] == 19);
    assert_or_panic(v[242] == 20);
    assert_or_panic(v[243] == 21);
    assert_or_panic(v[244] == 22);
    assert_or_panic(v[245] == 23);
    assert_or_panic(v[246] == 24);
    assert_or_panic(v[247] == 25);
    assert_or_panic(v[248] == 26);
    assert_or_panic(v[249] == 27);
    assert_or_panic(v[250] == 28);
    assert_or_panic(v[251] == 29);
    assert_or_panic(v[252] == 30);
    assert_or_panic(v[253] == 31);
    assert_or_panic(v[254] == 32);
    assert_or_panic(v[255] == 33);
    assert_or_panic(v[256] == 34);
    assert_or_panic(v[257] == 35);
    assert_or_panic(v[258] == 36);
    assert_or_panic(v[259] == 37);
    assert_or_panic(v[260] == 38);
    assert_or_panic(v[261] == 39);
    assert_or_panic(v[262] == 40);
    assert_or_panic(v[263] == 41);
    assert_or_panic(v[264] == 42);
    assert_or_panic(v[265] == 43);
    assert_or_panic(v[266] == 44);
    assert_or_panic(v[267] == 45);
    assert_or_panic(v[268] == 46);
    assert_or_panic(v[269] == 47);
    assert_or_panic(v[270] == 48);
    assert_or_panic(v[271] == 49);
    assert_or_panic(v[272] == 50);
    assert_or_panic(v[273] == 51);
    assert_or_panic(v[274] == 52);
    assert_or_panic(v[275] == 53);
    assert_or_panic(v[276] == 54);
    assert_or_panic(v[277] == 55);
    assert_or_panic(v[278] == 56);
    assert_or_panic(v[279] == 57);
    assert_or_panic(v[280] == 58);
    assert_or_panic(v[281] == 59);
    assert_or_panic(v[282] == 60);
    assert_or_panic(v[283] == 61);
    assert_or_panic(v[284] == 62);
    assert_or_panic(v[285] == 63);
    assert_or_panic(v[286] == 64);
    assert_or_panic(v[287] == 65);
    assert_or_panic(v[288] == 66);
    assert_or_panic(v[289] == 67);
    assert_or_panic(v[290] == 68);
    assert_or_panic(v[291] == 69);
    assert_or_panic(v[292] == 70);
    assert_or_panic(v[293] == 71);
    assert_or_panic(v[294] == 72);
    assert_or_panic(v[295] == 73);
    assert_or_panic(v[296] == 74);
    assert_or_panic(v[297] == 75);
    assert_or_panic(v[298] == 76);
    assert_or_panic(v[299] == 77);
    assert_or_panic(v[300] == 78);
    assert_or_panic(v[301] == 79);
    assert_or_panic(v[302] == 80);
    assert_or_panic(v[303] == 81);
    assert_or_panic(v[304] == 82);
    assert_or_panic(v[305] == 83);
    assert_or_panic(v[306] == 84);
    assert_or_panic(v[307] == 85);
    assert_or_panic(v[308] == 86);
    assert_or_panic(v[309] == 87);
    assert_or_panic(v[310] == 88);
    assert_or_panic(v[311] == 89);
    assert_or_panic(v[312] == 90);
    assert_or_panic(v[313] == 91);
    assert_or_panic(v[314] == 92);
    assert_or_panic(v[315] == 93);
    assert_or_panic(v[316] == 94);
    assert_or_panic(v[317] == 95);
    assert_or_panic(v[318] == 96);
    assert_or_panic(v[319] == 97);
    assert_or_panic(v[320] == 98);
    assert_or_panic(v[321] == 99);
    assert_or_panic(v[322] == 0);
    assert_or_panic(v[323] == 1);
    assert_or_panic(v[324] == 2);
    assert_or_panic(v[325] == 3);
    assert_or_panic(v[326] == 4);
    assert_or_panic(v[327] == 5);
    assert_or_panic(v[328] == 6);
    assert_or_panic(v[329] == 7);
    assert_or_panic(v[330] == 8);
    assert_or_panic(v[331] == 9);
    assert_or_panic(v[332] == 10);
    assert_or_panic(v[333] == 11);
    assert_or_panic(v[334] == 12);
    assert_or_panic(v[335] == 13);
    assert_or_panic(v[336] == 14);
    assert_or_panic(v[337] == 15);
    assert_or_panic(v[338] == 16);
    assert_or_panic(v[339] == 17);
    assert_or_panic(v[340] == 18);
    assert_or_panic(v[341] == 19);
    assert_or_panic(v[342] == 20);
    assert_or_panic(v[343] == 21);
    assert_or_panic(v[344] == 22);
    assert_or_panic(v[345] == 23);
    assert_or_panic(v[346] == 24);
    assert_or_panic(v[347] == 25);
    assert_or_panic(v[348] == 26);
    assert_or_panic(v[349] == 27);
    assert_or_panic(v[350] == 28);
    assert_or_panic(v[351] == 29);
    assert_or_panic(v[352] == 30);
    assert_or_panic(v[353] == 31);
    assert_or_panic(v[354] == 32);
    assert_or_panic(v[355] == 33);
    assert_or_panic(v[356] == 34);
    assert_or_panic(v[357] == 35);
    assert_or_panic(v[358] == 36);
    assert_or_panic(v[359] == 37);
    assert_or_panic(v[360] == 38);
    assert_or_panic(v[361] == 39);
    assert_or_panic(v[362] == 40);
    assert_or_panic(v[363] == 41);
    assert_or_panic(v[364] == 42);
    assert_or_panic(v[365] == 43);
    assert_or_panic(v[366] == 44);
    assert_or_panic(v[367] == 45);
    assert_or_panic(v[368] == 46);
    assert_or_panic(v[369] == 47);
    assert_or_panic(v[370] == 48);
    assert_or_panic(v[371] == 49);
    assert_or_panic(v[372] == 50);
    assert_or_panic(v[373] == 51);
    assert_or_panic(v[374] == 52);
    assert_or_panic(v[375] == 53);
    assert_or_panic(v[376] == 54);
    assert_or_panic(v[377] == 55);
    assert_or_panic(v[378] == 56);
    assert_or_panic(v[379] == 57);
    assert_or_panic(v[380] == 58);
    assert_or_panic(v[381] == 59);
    assert_or_panic(v[382] == 60);
    assert_or_panic(v[383] == 61);
    zig_vector_384_u8((Vector_384_u8){
        62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77,
        78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93,
        94, 95, 96, 97, 98, 99, 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,
        10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,
        26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41,
        42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
        58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73,
        74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89,
        90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,  1,  2,  3,  4,  5,
        6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
        22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37,
        38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53,
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69,
        70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85,
        86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,  1,
        2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17,
        18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33,
        34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
        50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65,
        66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81,
        82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97,
        98, 99, 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13,
        14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
        30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45,
    }, 384);
}

typedef uint8_t Vector_512_u8 __attribute__((vector_size(512 * sizeof(uint8_t))));

Vector_512_u8 zig_ret_vector_512_u8(void);
void zig_vector_512_u8(Vector_512_u8, size_t);

Vector_512_u8 c_ret_vector_512_u8(void) {
    return (Vector_512_u8){
        38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53,
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69,
        70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85,
        86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,  1,
        2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17,
        18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33,
        34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
        50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65,
        66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81,
        82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97,
        98, 99, 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13,
        14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
        30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45,
        46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61,
        62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77,
        78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93,
        94, 95, 96, 97, 98, 99, 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,
        10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,
        26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41,
        42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
        58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73,
        74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89,
        90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,  1,  2,  3,  4,  5,
        6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
        22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37,
        38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53,
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69,
        70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85,
        86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,  1,
        2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17,
        18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33,
        34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
    };
}
void c_vector_512_u8(Vector_512_u8 v, size_t i) {
    assert_or_panic(v[0] == 50);
    assert_or_panic(v[1] == 51);
    assert_or_panic(v[2] == 52);
    assert_or_panic(v[3] == 53);
    assert_or_panic(v[4] == 54);
    assert_or_panic(v[5] == 55);
    assert_or_panic(v[6] == 56);
    assert_or_panic(v[7] == 57);
    assert_or_panic(v[8] == 58);
    assert_or_panic(v[9] == 59);
    assert_or_panic(v[10] == 60);
    assert_or_panic(v[11] == 61);
    assert_or_panic(v[12] == 62);
    assert_or_panic(v[13] == 63);
    assert_or_panic(v[14] == 64);
    assert_or_panic(v[15] == 65);
    assert_or_panic(v[16] == 66);
    assert_or_panic(v[17] == 67);
    assert_or_panic(v[18] == 68);
    assert_or_panic(v[19] == 69);
    assert_or_panic(v[20] == 70);
    assert_or_panic(v[21] == 71);
    assert_or_panic(v[22] == 72);
    assert_or_panic(v[23] == 73);
    assert_or_panic(v[24] == 74);
    assert_or_panic(v[25] == 75);
    assert_or_panic(v[26] == 76);
    assert_or_panic(v[27] == 77);
    assert_or_panic(v[28] == 78);
    assert_or_panic(v[29] == 79);
    assert_or_panic(v[30] == 80);
    assert_or_panic(v[31] == 81);
    assert_or_panic(v[32] == 82);
    assert_or_panic(v[33] == 83);
    assert_or_panic(v[34] == 84);
    assert_or_panic(v[35] == 85);
    assert_or_panic(v[36] == 86);
    assert_or_panic(v[37] == 87);
    assert_or_panic(v[38] == 88);
    assert_or_panic(v[39] == 89);
    assert_or_panic(v[40] == 90);
    assert_or_panic(v[41] == 91);
    assert_or_panic(v[42] == 92);
    assert_or_panic(v[43] == 93);
    assert_or_panic(v[44] == 94);
    assert_or_panic(v[45] == 95);
    assert_or_panic(v[46] == 96);
    assert_or_panic(v[47] == 97);
    assert_or_panic(v[48] == 98);
    assert_or_panic(v[49] == 99);
    assert_or_panic(v[50] == 0);
    assert_or_panic(v[51] == 1);
    assert_or_panic(v[52] == 2);
    assert_or_panic(v[53] == 3);
    assert_or_panic(v[54] == 4);
    assert_or_panic(v[55] == 5);
    assert_or_panic(v[56] == 6);
    assert_or_panic(v[57] == 7);
    assert_or_panic(v[58] == 8);
    assert_or_panic(v[59] == 9);
    assert_or_panic(v[60] == 10);
    assert_or_panic(v[61] == 11);
    assert_or_panic(v[62] == 12);
    assert_or_panic(v[63] == 13);
    assert_or_panic(v[64] == 14);
    assert_or_panic(v[65] == 15);
    assert_or_panic(v[66] == 16);
    assert_or_panic(v[67] == 17);
    assert_or_panic(v[68] == 18);
    assert_or_panic(v[69] == 19);
    assert_or_panic(v[70] == 20);
    assert_or_panic(v[71] == 21);
    assert_or_panic(v[72] == 22);
    assert_or_panic(v[73] == 23);
    assert_or_panic(v[74] == 24);
    assert_or_panic(v[75] == 25);
    assert_or_panic(v[76] == 26);
    assert_or_panic(v[77] == 27);
    assert_or_panic(v[78] == 28);
    assert_or_panic(v[79] == 29);
    assert_or_panic(v[80] == 30);
    assert_or_panic(v[81] == 31);
    assert_or_panic(v[82] == 32);
    assert_or_panic(v[83] == 33);
    assert_or_panic(v[84] == 34);
    assert_or_panic(v[85] == 35);
    assert_or_panic(v[86] == 36);
    assert_or_panic(v[87] == 37);
    assert_or_panic(v[88] == 38);
    assert_or_panic(v[89] == 39);
    assert_or_panic(v[90] == 40);
    assert_or_panic(v[91] == 41);
    assert_or_panic(v[92] == 42);
    assert_or_panic(v[93] == 43);
    assert_or_panic(v[94] == 44);
    assert_or_panic(v[95] == 45);
    assert_or_panic(v[96] == 46);
    assert_or_panic(v[97] == 47);
    assert_or_panic(v[98] == 48);
    assert_or_panic(v[99] == 49);
    assert_or_panic(v[100] == 50);
    assert_or_panic(v[101] == 51);
    assert_or_panic(v[102] == 52);
    assert_or_panic(v[103] == 53);
    assert_or_panic(v[104] == 54);
    assert_or_panic(v[105] == 55);
    assert_or_panic(v[106] == 56);
    assert_or_panic(v[107] == 57);
    assert_or_panic(v[108] == 58);
    assert_or_panic(v[109] == 59);
    assert_or_panic(v[110] == 60);
    assert_or_panic(v[111] == 61);
    assert_or_panic(v[112] == 62);
    assert_or_panic(v[113] == 63);
    assert_or_panic(v[114] == 64);
    assert_or_panic(v[115] == 65);
    assert_or_panic(v[116] == 66);
    assert_or_panic(v[117] == 67);
    assert_or_panic(v[118] == 68);
    assert_or_panic(v[119] == 69);
    assert_or_panic(v[120] == 70);
    assert_or_panic(v[121] == 71);
    assert_or_panic(v[122] == 72);
    assert_or_panic(v[123] == 73);
    assert_or_panic(v[124] == 74);
    assert_or_panic(v[125] == 75);
    assert_or_panic(v[126] == 76);
    assert_or_panic(v[127] == 77);
    assert_or_panic(v[128] == 78);
    assert_or_panic(v[129] == 79);
    assert_or_panic(v[130] == 80);
    assert_or_panic(v[131] == 81);
    assert_or_panic(v[132] == 82);
    assert_or_panic(v[133] == 83);
    assert_or_panic(v[134] == 84);
    assert_or_panic(v[135] == 85);
    assert_or_panic(v[136] == 86);
    assert_or_panic(v[137] == 87);
    assert_or_panic(v[138] == 88);
    assert_or_panic(v[139] == 89);
    assert_or_panic(v[140] == 90);
    assert_or_panic(v[141] == 91);
    assert_or_panic(v[142] == 92);
    assert_or_panic(v[143] == 93);
    assert_or_panic(v[144] == 94);
    assert_or_panic(v[145] == 95);
    assert_or_panic(v[146] == 96);
    assert_or_panic(v[147] == 97);
    assert_or_panic(v[148] == 98);
    assert_or_panic(v[149] == 99);
    assert_or_panic(v[150] == 0);
    assert_or_panic(v[151] == 1);
    assert_or_panic(v[152] == 2);
    assert_or_panic(v[153] == 3);
    assert_or_panic(v[154] == 4);
    assert_or_panic(v[155] == 5);
    assert_or_panic(v[156] == 6);
    assert_or_panic(v[157] == 7);
    assert_or_panic(v[158] == 8);
    assert_or_panic(v[159] == 9);
    assert_or_panic(v[160] == 10);
    assert_or_panic(v[161] == 11);
    assert_or_panic(v[162] == 12);
    assert_or_panic(v[163] == 13);
    assert_or_panic(v[164] == 14);
    assert_or_panic(v[165] == 15);
    assert_or_panic(v[166] == 16);
    assert_or_panic(v[167] == 17);
    assert_or_panic(v[168] == 18);
    assert_or_panic(v[169] == 19);
    assert_or_panic(v[170] == 20);
    assert_or_panic(v[171] == 21);
    assert_or_panic(v[172] == 22);
    assert_or_panic(v[173] == 23);
    assert_or_panic(v[174] == 24);
    assert_or_panic(v[175] == 25);
    assert_or_panic(v[176] == 26);
    assert_or_panic(v[177] == 27);
    assert_or_panic(v[178] == 28);
    assert_or_panic(v[179] == 29);
    assert_or_panic(v[180] == 30);
    assert_or_panic(v[181] == 31);
    assert_or_panic(v[182] == 32);
    assert_or_panic(v[183] == 33);
    assert_or_panic(v[184] == 34);
    assert_or_panic(v[185] == 35);
    assert_or_panic(v[186] == 36);
    assert_or_panic(v[187] == 37);
    assert_or_panic(v[188] == 38);
    assert_or_panic(v[189] == 39);
    assert_or_panic(v[190] == 40);
    assert_or_panic(v[191] == 41);
    assert_or_panic(v[192] == 42);
    assert_or_panic(v[193] == 43);
    assert_or_panic(v[194] == 44);
    assert_or_panic(v[195] == 45);
    assert_or_panic(v[196] == 46);
    assert_or_panic(v[197] == 47);
    assert_or_panic(v[198] == 48);
    assert_or_panic(v[199] == 49);
    assert_or_panic(v[200] == 50);
    assert_or_panic(v[201] == 51);
    assert_or_panic(v[202] == 52);
    assert_or_panic(v[203] == 53);
    assert_or_panic(v[204] == 54);
    assert_or_panic(v[205] == 55);
    assert_or_panic(v[206] == 56);
    assert_or_panic(v[207] == 57);
    assert_or_panic(v[208] == 58);
    assert_or_panic(v[209] == 59);
    assert_or_panic(v[210] == 60);
    assert_or_panic(v[211] == 61);
    assert_or_panic(v[212] == 62);
    assert_or_panic(v[213] == 63);
    assert_or_panic(v[214] == 64);
    assert_or_panic(v[215] == 65);
    assert_or_panic(v[216] == 66);
    assert_or_panic(v[217] == 67);
    assert_or_panic(v[218] == 68);
    assert_or_panic(v[219] == 69);
    assert_or_panic(v[220] == 70);
    assert_or_panic(v[221] == 71);
    assert_or_panic(v[222] == 72);
    assert_or_panic(v[223] == 73);
    assert_or_panic(v[224] == 74);
    assert_or_panic(v[225] == 75);
    assert_or_panic(v[226] == 76);
    assert_or_panic(v[227] == 77);
    assert_or_panic(v[228] == 78);
    assert_or_panic(v[229] == 79);
    assert_or_panic(v[230] == 80);
    assert_or_panic(v[231] == 81);
    assert_or_panic(v[232] == 82);
    assert_or_panic(v[233] == 83);
    assert_or_panic(v[234] == 84);
    assert_or_panic(v[235] == 85);
    assert_or_panic(v[236] == 86);
    assert_or_panic(v[237] == 87);
    assert_or_panic(v[238] == 88);
    assert_or_panic(v[239] == 89);
    assert_or_panic(v[240] == 90);
    assert_or_panic(v[241] == 91);
    assert_or_panic(v[242] == 92);
    assert_or_panic(v[243] == 93);
    assert_or_panic(v[244] == 94);
    assert_or_panic(v[245] == 95);
    assert_or_panic(v[246] == 96);
    assert_or_panic(v[247] == 97);
    assert_or_panic(v[248] == 98);
    assert_or_panic(v[249] == 99);
    assert_or_panic(v[250] == 0);
    assert_or_panic(v[251] == 1);
    assert_or_panic(v[252] == 2);
    assert_or_panic(v[253] == 3);
    assert_or_panic(v[254] == 4);
    assert_or_panic(v[255] == 5);
    assert_or_panic(v[256] == 6);
    assert_or_panic(v[257] == 7);
    assert_or_panic(v[258] == 8);
    assert_or_panic(v[259] == 9);
    assert_or_panic(v[260] == 10);
    assert_or_panic(v[261] == 11);
    assert_or_panic(v[262] == 12);
    assert_or_panic(v[263] == 13);
    assert_or_panic(v[264] == 14);
    assert_or_panic(v[265] == 15);
    assert_or_panic(v[266] == 16);
    assert_or_panic(v[267] == 17);
    assert_or_panic(v[268] == 18);
    assert_or_panic(v[269] == 19);
    assert_or_panic(v[270] == 20);
    assert_or_panic(v[271] == 21);
    assert_or_panic(v[272] == 22);
    assert_or_panic(v[273] == 23);
    assert_or_panic(v[274] == 24);
    assert_or_panic(v[275] == 25);
    assert_or_panic(v[276] == 26);
    assert_or_panic(v[277] == 27);
    assert_or_panic(v[278] == 28);
    assert_or_panic(v[279] == 29);
    assert_or_panic(v[280] == 30);
    assert_or_panic(v[281] == 31);
    assert_or_panic(v[282] == 32);
    assert_or_panic(v[283] == 33);
    assert_or_panic(v[284] == 34);
    assert_or_panic(v[285] == 35);
    assert_or_panic(v[286] == 36);
    assert_or_panic(v[287] == 37);
    assert_or_panic(v[288] == 38);
    assert_or_panic(v[289] == 39);
    assert_or_panic(v[290] == 40);
    assert_or_panic(v[291] == 41);
    assert_or_panic(v[292] == 42);
    assert_or_panic(v[293] == 43);
    assert_or_panic(v[294] == 44);
    assert_or_panic(v[295] == 45);
    assert_or_panic(v[296] == 46);
    assert_or_panic(v[297] == 47);
    assert_or_panic(v[298] == 48);
    assert_or_panic(v[299] == 49);
    assert_or_panic(v[300] == 50);
    assert_or_panic(v[301] == 51);
    assert_or_panic(v[302] == 52);
    assert_or_panic(v[303] == 53);
    assert_or_panic(v[304] == 54);
    assert_or_panic(v[305] == 55);
    assert_or_panic(v[306] == 56);
    assert_or_panic(v[307] == 57);
    assert_or_panic(v[308] == 58);
    assert_or_panic(v[309] == 59);
    assert_or_panic(v[310] == 60);
    assert_or_panic(v[311] == 61);
    assert_or_panic(v[312] == 62);
    assert_or_panic(v[313] == 63);
    assert_or_panic(v[314] == 64);
    assert_or_panic(v[315] == 65);
    assert_or_panic(v[316] == 66);
    assert_or_panic(v[317] == 67);
    assert_or_panic(v[318] == 68);
    assert_or_panic(v[319] == 69);
    assert_or_panic(v[320] == 70);
    assert_or_panic(v[321] == 71);
    assert_or_panic(v[322] == 72);
    assert_or_panic(v[323] == 73);
    assert_or_panic(v[324] == 74);
    assert_or_panic(v[325] == 75);
    assert_or_panic(v[326] == 76);
    assert_or_panic(v[327] == 77);
    assert_or_panic(v[328] == 78);
    assert_or_panic(v[329] == 79);
    assert_or_panic(v[330] == 80);
    assert_or_panic(v[331] == 81);
    assert_or_panic(v[332] == 82);
    assert_or_panic(v[333] == 83);
    assert_or_panic(v[334] == 84);
    assert_or_panic(v[335] == 85);
    assert_or_panic(v[336] == 86);
    assert_or_panic(v[337] == 87);
    assert_or_panic(v[338] == 88);
    assert_or_panic(v[339] == 89);
    assert_or_panic(v[340] == 90);
    assert_or_panic(v[341] == 91);
    assert_or_panic(v[342] == 92);
    assert_or_panic(v[343] == 93);
    assert_or_panic(v[344] == 94);
    assert_or_panic(v[345] == 95);
    assert_or_panic(v[346] == 96);
    assert_or_panic(v[347] == 97);
    assert_or_panic(v[348] == 98);
    assert_or_panic(v[349] == 99);
    assert_or_panic(v[350] == 0);
    assert_or_panic(v[351] == 1);
    assert_or_panic(v[352] == 2);
    assert_or_panic(v[353] == 3);
    assert_or_panic(v[354] == 4);
    assert_or_panic(v[355] == 5);
    assert_or_panic(v[356] == 6);
    assert_or_panic(v[357] == 7);
    assert_or_panic(v[358] == 8);
    assert_or_panic(v[359] == 9);
    assert_or_panic(v[360] == 10);
    assert_or_panic(v[361] == 11);
    assert_or_panic(v[362] == 12);
    assert_or_panic(v[363] == 13);
    assert_or_panic(v[364] == 14);
    assert_or_panic(v[365] == 15);
    assert_or_panic(v[366] == 16);
    assert_or_panic(v[367] == 17);
    assert_or_panic(v[368] == 18);
    assert_or_panic(v[369] == 19);
    assert_or_panic(v[370] == 20);
    assert_or_panic(v[371] == 21);
    assert_or_panic(v[372] == 22);
    assert_or_panic(v[373] == 23);
    assert_or_panic(v[374] == 24);
    assert_or_panic(v[375] == 25);
    assert_or_panic(v[376] == 26);
    assert_or_panic(v[377] == 27);
    assert_or_panic(v[378] == 28);
    assert_or_panic(v[379] == 29);
    assert_or_panic(v[380] == 30);
    assert_or_panic(v[381] == 31);
    assert_or_panic(v[382] == 32);
    assert_or_panic(v[383] == 33);
    assert_or_panic(v[384] == 34);
    assert_or_panic(v[385] == 35);
    assert_or_panic(v[386] == 36);
    assert_or_panic(v[387] == 37);
    assert_or_panic(v[388] == 38);
    assert_or_panic(v[389] == 39);
    assert_or_panic(v[390] == 40);
    assert_or_panic(v[391] == 41);
    assert_or_panic(v[392] == 42);
    assert_or_panic(v[393] == 43);
    assert_or_panic(v[394] == 44);
    assert_or_panic(v[395] == 45);
    assert_or_panic(v[396] == 46);
    assert_or_panic(v[397] == 47);
    assert_or_panic(v[398] == 48);
    assert_or_panic(v[399] == 49);
    assert_or_panic(v[400] == 50);
    assert_or_panic(v[401] == 51);
    assert_or_panic(v[402] == 52);
    assert_or_panic(v[403] == 53);
    assert_or_panic(v[404] == 54);
    assert_or_panic(v[405] == 55);
    assert_or_panic(v[406] == 56);
    assert_or_panic(v[407] == 57);
    assert_or_panic(v[408] == 58);
    assert_or_panic(v[409] == 59);
    assert_or_panic(v[410] == 60);
    assert_or_panic(v[411] == 61);
    assert_or_panic(v[412] == 62);
    assert_or_panic(v[413] == 63);
    assert_or_panic(v[414] == 64);
    assert_or_panic(v[415] == 65);
    assert_or_panic(v[416] == 66);
    assert_or_panic(v[417] == 67);
    assert_or_panic(v[418] == 68);
    assert_or_panic(v[419] == 69);
    assert_or_panic(v[420] == 70);
    assert_or_panic(v[421] == 71);
    assert_or_panic(v[422] == 72);
    assert_or_panic(v[423] == 73);
    assert_or_panic(v[424] == 74);
    assert_or_panic(v[425] == 75);
    assert_or_panic(v[426] == 76);
    assert_or_panic(v[427] == 77);
    assert_or_panic(v[428] == 78);
    assert_or_panic(v[429] == 79);
    assert_or_panic(v[430] == 80);
    assert_or_panic(v[431] == 81);
    assert_or_panic(v[432] == 82);
    assert_or_panic(v[433] == 83);
    assert_or_panic(v[434] == 84);
    assert_or_panic(v[435] == 85);
    assert_or_panic(v[436] == 86);
    assert_or_panic(v[437] == 87);
    assert_or_panic(v[438] == 88);
    assert_or_panic(v[439] == 89);
    assert_or_panic(v[440] == 90);
    assert_or_panic(v[441] == 91);
    assert_or_panic(v[442] == 92);
    assert_or_panic(v[443] == 93);
    assert_or_panic(v[444] == 94);
    assert_or_panic(v[445] == 95);
    assert_or_panic(v[446] == 96);
    assert_or_panic(v[447] == 97);
    assert_or_panic(v[448] == 98);
    assert_or_panic(v[449] == 99);
    assert_or_panic(v[450] == 0);
    assert_or_panic(v[451] == 1);
    assert_or_panic(v[452] == 2);
    assert_or_panic(v[453] == 3);
    assert_or_panic(v[454] == 4);
    assert_or_panic(v[455] == 5);
    assert_or_panic(v[456] == 6);
    assert_or_panic(v[457] == 7);
    assert_or_panic(v[458] == 8);
    assert_or_panic(v[459] == 9);
    assert_or_panic(v[460] == 10);
    assert_or_panic(v[461] == 11);
    assert_or_panic(v[462] == 12);
    assert_or_panic(v[463] == 13);
    assert_or_panic(v[464] == 14);
    assert_or_panic(v[465] == 15);
    assert_or_panic(v[466] == 16);
    assert_or_panic(v[467] == 17);
    assert_or_panic(v[468] == 18);
    assert_or_panic(v[469] == 19);
    assert_or_panic(v[470] == 20);
    assert_or_panic(v[471] == 21);
    assert_or_panic(v[472] == 22);
    assert_or_panic(v[473] == 23);
    assert_or_panic(v[474] == 24);
    assert_or_panic(v[475] == 25);
    assert_or_panic(v[476] == 26);
    assert_or_panic(v[477] == 27);
    assert_or_panic(v[478] == 28);
    assert_or_panic(v[479] == 29);
    assert_or_panic(v[480] == 30);
    assert_or_panic(v[481] == 31);
    assert_or_panic(v[482] == 32);
    assert_or_panic(v[483] == 33);
    assert_or_panic(v[484] == 34);
    assert_or_panic(v[485] == 35);
    assert_or_panic(v[486] == 36);
    assert_or_panic(v[487] == 37);
    assert_or_panic(v[488] == 38);
    assert_or_panic(v[489] == 39);
    assert_or_panic(v[490] == 40);
    assert_or_panic(v[491] == 41);
    assert_or_panic(v[492] == 42);
    assert_or_panic(v[493] == 43);
    assert_or_panic(v[494] == 44);
    assert_or_panic(v[495] == 45);
    assert_or_panic(v[496] == 46);
    assert_or_panic(v[497] == 47);
    assert_or_panic(v[498] == 48);
    assert_or_panic(v[499] == 49);
    assert_or_panic(v[500] == 50);
    assert_or_panic(v[501] == 51);
    assert_or_panic(v[502] == 52);
    assert_or_panic(v[503] == 53);
    assert_or_panic(v[504] == 54);
    assert_or_panic(v[505] == 55);
    assert_or_panic(v[506] == 56);
    assert_or_panic(v[507] == 57);
    assert_or_panic(v[508] == 58);
    assert_or_panic(v[509] == 59);
    assert_or_panic(v[510] == 60);
    assert_or_panic(v[511] == 61);
    assert_or_panic(i == 512);
}
void c_test_vector_512_u8(void) {
    Vector_512_u8 v = zig_ret_vector_512_u8();
    assert_or_panic(v[0]   == 14);
    assert_or_panic(v[1]   == 15);
    assert_or_panic(v[2]   == 16);
    assert_or_panic(v[3]   == 17);
    assert_or_panic(v[4]   == 18);
    assert_or_panic(v[5]   == 19);
    assert_or_panic(v[6]   == 20);
    assert_or_panic(v[7]   == 21);
    assert_or_panic(v[8]   == 22);
    assert_or_panic(v[9]   == 23);
    assert_or_panic(v[10]  == 24);
    assert_or_panic(v[11]  == 25);
    assert_or_panic(v[12]  == 26);
    assert_or_panic(v[13]  == 27);
    assert_or_panic(v[14]  == 28);
    assert_or_panic(v[15]  == 29);
    assert_or_panic(v[16]  == 30);
    assert_or_panic(v[17]  == 31);
    assert_or_panic(v[18]  == 32);
    assert_or_panic(v[19]  == 33);
    assert_or_panic(v[20]  == 34);
    assert_or_panic(v[21]  == 35);
    assert_or_panic(v[22]  == 36);
    assert_or_panic(v[23]  == 37);
    assert_or_panic(v[24]  == 38);
    assert_or_panic(v[25]  == 39);
    assert_or_panic(v[26]  == 40);
    assert_or_panic(v[27]  == 41);
    assert_or_panic(v[28]  == 42);
    assert_or_panic(v[29]  == 43);
    assert_or_panic(v[30]  == 44);
    assert_or_panic(v[31]  == 45);
    assert_or_panic(v[32]  == 46);
    assert_or_panic(v[33]  == 47);
    assert_or_panic(v[34]  == 48);
    assert_or_panic(v[35]  == 49);
    assert_or_panic(v[36]  == 50);
    assert_or_panic(v[37]  == 51);
    assert_or_panic(v[38]  == 52);
    assert_or_panic(v[39]  == 53);
    assert_or_panic(v[40]  == 54);
    assert_or_panic(v[41]  == 55);
    assert_or_panic(v[42]  == 56);
    assert_or_panic(v[43]  == 57);
    assert_or_panic(v[44]  == 58);
    assert_or_panic(v[45]  == 59);
    assert_or_panic(v[46]  == 60);
    assert_or_panic(v[47]  == 61);
    assert_or_panic(v[48]  == 62);
    assert_or_panic(v[49]  == 63);
    assert_or_panic(v[50]  == 64);
    assert_or_panic(v[51]  == 65);
    assert_or_panic(v[52]  == 66);
    assert_or_panic(v[53]  == 67);
    assert_or_panic(v[54]  == 68);
    assert_or_panic(v[55]  == 69);
    assert_or_panic(v[56]  == 70);
    assert_or_panic(v[57]  == 71);
    assert_or_panic(v[58]  == 72);
    assert_or_panic(v[59]  == 73);
    assert_or_panic(v[60]  == 74);
    assert_or_panic(v[61]  == 75);
    assert_or_panic(v[62]  == 76);
    assert_or_panic(v[63]  == 77);
    assert_or_panic(v[64]  == 78);
    assert_or_panic(v[65]  == 79);
    assert_or_panic(v[66]  == 80);
    assert_or_panic(v[67]  == 81);
    assert_or_panic(v[68]  == 82);
    assert_or_panic(v[69]  == 83);
    assert_or_panic(v[70]  == 84);
    assert_or_panic(v[71]  == 85);
    assert_or_panic(v[72]  == 86);
    assert_or_panic(v[73]  == 87);
    assert_or_panic(v[74]  == 88);
    assert_or_panic(v[75]  == 89);
    assert_or_panic(v[76]  == 90);
    assert_or_panic(v[77]  == 91);
    assert_or_panic(v[78]  == 92);
    assert_or_panic(v[79]  == 93);
    assert_or_panic(v[80]  == 94);
    assert_or_panic(v[81]  == 95);
    assert_or_panic(v[82]  == 96);
    assert_or_panic(v[83]  == 97);
    assert_or_panic(v[84]  == 98);
    assert_or_panic(v[85]  == 99);
    assert_or_panic(v[86]  ==  0);
    assert_or_panic(v[87]  ==  1);
    assert_or_panic(v[88]  ==  2);
    assert_or_panic(v[89]  ==  3);
    assert_or_panic(v[90]  ==  4);
    assert_or_panic(v[91]  ==  5);
    assert_or_panic(v[92]  ==  6);
    assert_or_panic(v[93]  ==  7);
    assert_or_panic(v[94]  ==  8);
    assert_or_panic(v[95]  ==  9);
    assert_or_panic(v[96]  == 10);
    assert_or_panic(v[97]  == 11);
    assert_or_panic(v[98]  == 12);
    assert_or_panic(v[99]  == 13);
    assert_or_panic(v[100] == 14);
    assert_or_panic(v[101] == 15);
    assert_or_panic(v[102] == 16);
    assert_or_panic(v[103] == 17);
    assert_or_panic(v[104] == 18);
    assert_or_panic(v[105] == 19);
    assert_or_panic(v[106] == 20);
    assert_or_panic(v[107] == 21);
    assert_or_panic(v[108] == 22);
    assert_or_panic(v[109] == 23);
    assert_or_panic(v[110] == 24);
    assert_or_panic(v[111] == 25);
    assert_or_panic(v[112] == 26);
    assert_or_panic(v[113] == 27);
    assert_or_panic(v[114] == 28);
    assert_or_panic(v[115] == 29);
    assert_or_panic(v[116] == 30);
    assert_or_panic(v[117] == 31);
    assert_or_panic(v[118] == 32);
    assert_or_panic(v[119] == 33);
    assert_or_panic(v[120] == 34);
    assert_or_panic(v[121] == 35);
    assert_or_panic(v[122] == 36);
    assert_or_panic(v[123] == 37);
    assert_or_panic(v[124] == 38);
    assert_or_panic(v[125] == 39);
    assert_or_panic(v[126] == 40);
    assert_or_panic(v[127] == 41);
    assert_or_panic(v[128] == 42);
    assert_or_panic(v[129] == 43);
    assert_or_panic(v[130] == 44);
    assert_or_panic(v[131] == 45);
    assert_or_panic(v[132] == 46);
    assert_or_panic(v[133] == 47);
    assert_or_panic(v[134] == 48);
    assert_or_panic(v[135] == 49);
    assert_or_panic(v[136] == 50);
    assert_or_panic(v[137] == 51);
    assert_or_panic(v[138] == 52);
    assert_or_panic(v[139] == 53);
    assert_or_panic(v[140] == 54);
    assert_or_panic(v[141] == 55);
    assert_or_panic(v[142] == 56);
    assert_or_panic(v[143] == 57);
    assert_or_panic(v[144] == 58);
    assert_or_panic(v[145] == 59);
    assert_or_panic(v[146] == 60);
    assert_or_panic(v[147] == 61);
    assert_or_panic(v[148] == 62);
    assert_or_panic(v[149] == 63);
    assert_or_panic(v[150] == 64);
    assert_or_panic(v[151] == 65);
    assert_or_panic(v[152] == 66);
    assert_or_panic(v[153] == 67);
    assert_or_panic(v[154] == 68);
    assert_or_panic(v[155] == 69);
    assert_or_panic(v[156] == 70);
    assert_or_panic(v[157] == 71);
    assert_or_panic(v[158] == 72);
    assert_or_panic(v[159] == 73);
    assert_or_panic(v[160] == 74);
    assert_or_panic(v[161] == 75);
    assert_or_panic(v[162] == 76);
    assert_or_panic(v[163] == 77);
    assert_or_panic(v[164] == 78);
    assert_or_panic(v[165] == 79);
    assert_or_panic(v[166] == 80);
    assert_or_panic(v[167] == 81);
    assert_or_panic(v[168] == 82);
    assert_or_panic(v[169] == 83);
    assert_or_panic(v[170] == 84);
    assert_or_panic(v[171] == 85);
    assert_or_panic(v[172] == 86);
    assert_or_panic(v[173] == 87);
    assert_or_panic(v[174] == 88);
    assert_or_panic(v[175] == 89);
    assert_or_panic(v[176] == 90);
    assert_or_panic(v[177] == 91);
    assert_or_panic(v[178] == 92);
    assert_or_panic(v[179] == 93);
    assert_or_panic(v[180] == 94);
    assert_or_panic(v[181] == 95);
    assert_or_panic(v[182] == 96);
    assert_or_panic(v[183] == 97);
    assert_or_panic(v[184] == 98);
    assert_or_panic(v[185] == 99);
    assert_or_panic(v[186] ==  0);
    assert_or_panic(v[187] ==  1);
    assert_or_panic(v[188] ==  2);
    assert_or_panic(v[189] ==  3);
    assert_or_panic(v[190] ==  4);
    assert_or_panic(v[191] ==  5);
    assert_or_panic(v[192] ==  6);
    assert_or_panic(v[193] ==  7);
    assert_or_panic(v[194] ==  8);
    assert_or_panic(v[195] ==  9);
    assert_or_panic(v[196] == 10);
    assert_or_panic(v[197] == 11);
    assert_or_panic(v[198] == 12);
    assert_or_panic(v[199] == 13);
    assert_or_panic(v[200] == 14);
    assert_or_panic(v[201] == 15);
    assert_or_panic(v[202] == 16);
    assert_or_panic(v[203] == 17);
    assert_or_panic(v[204] == 18);
    assert_or_panic(v[205] == 19);
    assert_or_panic(v[206] == 20);
    assert_or_panic(v[207] == 21);
    assert_or_panic(v[208] == 22);
    assert_or_panic(v[209] == 23);
    assert_or_panic(v[210] == 24);
    assert_or_panic(v[211] == 25);
    assert_or_panic(v[212] == 26);
    assert_or_panic(v[213] == 27);
    assert_or_panic(v[214] == 28);
    assert_or_panic(v[215] == 29);
    assert_or_panic(v[216] == 30);
    assert_or_panic(v[217] == 31);
    assert_or_panic(v[218] == 32);
    assert_or_panic(v[219] == 33);
    assert_or_panic(v[220] == 34);
    assert_or_panic(v[221] == 35);
    assert_or_panic(v[222] == 36);
    assert_or_panic(v[223] == 37);
    assert_or_panic(v[224] == 38);
    assert_or_panic(v[225] == 39);
    assert_or_panic(v[226] == 40);
    assert_or_panic(v[227] == 41);
    assert_or_panic(v[228] == 42);
    assert_or_panic(v[229] == 43);
    assert_or_panic(v[230] == 44);
    assert_or_panic(v[231] == 45);
    assert_or_panic(v[232] == 46);
    assert_or_panic(v[233] == 47);
    assert_or_panic(v[234] == 48);
    assert_or_panic(v[235] == 49);
    assert_or_panic(v[236] == 50);
    assert_or_panic(v[237] == 51);
    assert_or_panic(v[238] == 52);
    assert_or_panic(v[239] == 53);
    assert_or_panic(v[240] == 54);
    assert_or_panic(v[241] == 55);
    assert_or_panic(v[242] == 56);
    assert_or_panic(v[243] == 57);
    assert_or_panic(v[244] == 58);
    assert_or_panic(v[245] == 59);
    assert_or_panic(v[246] == 60);
    assert_or_panic(v[247] == 61);
    assert_or_panic(v[248] == 62);
    assert_or_panic(v[249] == 63);
    assert_or_panic(v[250] == 64);
    assert_or_panic(v[251] == 65);
    assert_or_panic(v[252] == 66);
    assert_or_panic(v[253] == 67);
    assert_or_panic(v[254] == 68);
    assert_or_panic(v[255] == 69);
    assert_or_panic(v[256] == 70);
    assert_or_panic(v[257] == 71);
    assert_or_panic(v[258] == 72);
    assert_or_panic(v[259] == 73);
    assert_or_panic(v[260] == 74);
    assert_or_panic(v[261] == 75);
    assert_or_panic(v[262] == 76);
    assert_or_panic(v[263] == 77);
    assert_or_panic(v[264] == 78);
    assert_or_panic(v[265] == 79);
    assert_or_panic(v[266] == 80);
    assert_or_panic(v[267] == 81);
    assert_or_panic(v[268] == 82);
    assert_or_panic(v[269] == 83);
    assert_or_panic(v[270] == 84);
    assert_or_panic(v[271] == 85);
    assert_or_panic(v[272] == 86);
    assert_or_panic(v[273] == 87);
    assert_or_panic(v[274] == 88);
    assert_or_panic(v[275] == 89);
    assert_or_panic(v[276] == 90);
    assert_or_panic(v[277] == 91);
    assert_or_panic(v[278] == 92);
    assert_or_panic(v[279] == 93);
    assert_or_panic(v[280] == 94);
    assert_or_panic(v[281] == 95);
    assert_or_panic(v[282] == 96);
    assert_or_panic(v[283] == 97);
    assert_or_panic(v[284] == 98);
    assert_or_panic(v[285] == 99);
    assert_or_panic(v[286] ==  0);
    assert_or_panic(v[287] ==  1);
    assert_or_panic(v[288] ==  2);
    assert_or_panic(v[289] ==  3);
    assert_or_panic(v[290] ==  4);
    assert_or_panic(v[291] ==  5);
    assert_or_panic(v[292] ==  6);
    assert_or_panic(v[293] ==  7);
    assert_or_panic(v[294] ==  8);
    assert_or_panic(v[295] ==  9);
    assert_or_panic(v[296] == 10);
    assert_or_panic(v[297] == 11);
    assert_or_panic(v[298] == 12);
    assert_or_panic(v[299] == 13);
    assert_or_panic(v[300] == 14);
    assert_or_panic(v[301] == 15);
    assert_or_panic(v[302] == 16);
    assert_or_panic(v[303] == 17);
    assert_or_panic(v[304] == 18);
    assert_or_panic(v[305] == 19);
    assert_or_panic(v[306] == 20);
    assert_or_panic(v[307] == 21);
    assert_or_panic(v[308] == 22);
    assert_or_panic(v[309] == 23);
    assert_or_panic(v[310] == 24);
    assert_or_panic(v[311] == 25);
    assert_or_panic(v[312] == 26);
    assert_or_panic(v[313] == 27);
    assert_or_panic(v[314] == 28);
    assert_or_panic(v[315] == 29);
    assert_or_panic(v[316] == 30);
    assert_or_panic(v[317] == 31);
    assert_or_panic(v[318] == 32);
    assert_or_panic(v[319] == 33);
    assert_or_panic(v[320] == 34);
    assert_or_panic(v[321] == 35);
    assert_or_panic(v[322] == 36);
    assert_or_panic(v[323] == 37);
    assert_or_panic(v[324] == 38);
    assert_or_panic(v[325] == 39);
    assert_or_panic(v[326] == 40);
    assert_or_panic(v[327] == 41);
    assert_or_panic(v[328] == 42);
    assert_or_panic(v[329] == 43);
    assert_or_panic(v[330] == 44);
    assert_or_panic(v[331] == 45);
    assert_or_panic(v[332] == 46);
    assert_or_panic(v[333] == 47);
    assert_or_panic(v[334] == 48);
    assert_or_panic(v[335] == 49);
    assert_or_panic(v[336] == 50);
    assert_or_panic(v[337] == 51);
    assert_or_panic(v[338] == 52);
    assert_or_panic(v[339] == 53);
    assert_or_panic(v[340] == 54);
    assert_or_panic(v[341] == 55);
    assert_or_panic(v[342] == 56);
    assert_or_panic(v[343] == 57);
    assert_or_panic(v[344] == 58);
    assert_or_panic(v[345] == 59);
    assert_or_panic(v[346] == 60);
    assert_or_panic(v[347] == 61);
    assert_or_panic(v[348] == 62);
    assert_or_panic(v[349] == 63);
    assert_or_panic(v[350] == 64);
    assert_or_panic(v[351] == 65);
    assert_or_panic(v[352] == 66);
    assert_or_panic(v[353] == 67);
    assert_or_panic(v[354] == 68);
    assert_or_panic(v[355] == 69);
    assert_or_panic(v[356] == 70);
    assert_or_panic(v[357] == 71);
    assert_or_panic(v[358] == 72);
    assert_or_panic(v[359] == 73);
    assert_or_panic(v[360] == 74);
    assert_or_panic(v[361] == 75);
    assert_or_panic(v[362] == 76);
    assert_or_panic(v[363] == 77);
    assert_or_panic(v[364] == 78);
    assert_or_panic(v[365] == 79);
    assert_or_panic(v[366] == 80);
    assert_or_panic(v[367] == 81);
    assert_or_panic(v[368] == 82);
    assert_or_panic(v[369] == 83);
    assert_or_panic(v[370] == 84);
    assert_or_panic(v[371] == 85);
    assert_or_panic(v[372] == 86);
    assert_or_panic(v[373] == 87);
    assert_or_panic(v[374] == 88);
    assert_or_panic(v[375] == 89);
    assert_or_panic(v[376] == 90);
    assert_or_panic(v[377] == 91);
    assert_or_panic(v[378] == 92);
    assert_or_panic(v[379] == 93);
    assert_or_panic(v[380] == 94);
    assert_or_panic(v[381] == 95);
    assert_or_panic(v[382] == 96);
    assert_or_panic(v[383] == 97);
    assert_or_panic(v[384] == 98);
    assert_or_panic(v[385] == 99);
    assert_or_panic(v[386] ==  0);
    assert_or_panic(v[387] ==  1);
    assert_or_panic(v[388] ==  2);
    assert_or_panic(v[389] ==  3);
    assert_or_panic(v[390] ==  4);
    assert_or_panic(v[391] ==  5);
    assert_or_panic(v[392] ==  6);
    assert_or_panic(v[393] ==  7);
    assert_or_panic(v[394] ==  8);
    assert_or_panic(v[395] ==  9);
    assert_or_panic(v[396] == 10);
    assert_or_panic(v[397] == 11);
    assert_or_panic(v[398] == 12);
    assert_or_panic(v[399] == 13);
    assert_or_panic(v[400] == 14);
    assert_or_panic(v[401] == 15);
    assert_or_panic(v[402] == 16);
    assert_or_panic(v[403] == 17);
    assert_or_panic(v[404] == 18);
    assert_or_panic(v[405] == 19);
    assert_or_panic(v[406] == 20);
    assert_or_panic(v[407] == 21);
    assert_or_panic(v[408] == 22);
    assert_or_panic(v[409] == 23);
    assert_or_panic(v[410] == 24);
    assert_or_panic(v[411] == 25);
    assert_or_panic(v[412] == 26);
    assert_or_panic(v[413] == 27);
    assert_or_panic(v[414] == 28);
    assert_or_panic(v[415] == 29);
    assert_or_panic(v[416] == 30);
    assert_or_panic(v[417] == 31);
    assert_or_panic(v[418] == 32);
    assert_or_panic(v[419] == 33);
    assert_or_panic(v[420] == 34);
    assert_or_panic(v[421] == 35);
    assert_or_panic(v[422] == 36);
    assert_or_panic(v[423] == 37);
    assert_or_panic(v[424] == 38);
    assert_or_panic(v[425] == 39);
    assert_or_panic(v[426] == 40);
    assert_or_panic(v[427] == 41);
    assert_or_panic(v[428] == 42);
    assert_or_panic(v[429] == 43);
    assert_or_panic(v[430] == 44);
    assert_or_panic(v[431] == 45);
    assert_or_panic(v[432] == 46);
    assert_or_panic(v[433] == 47);
    assert_or_panic(v[434] == 48);
    assert_or_panic(v[435] == 49);
    assert_or_panic(v[436] == 50);
    assert_or_panic(v[437] == 51);
    assert_or_panic(v[438] == 52);
    assert_or_panic(v[439] == 53);
    assert_or_panic(v[440] == 54);
    assert_or_panic(v[441] == 55);
    assert_or_panic(v[442] == 56);
    assert_or_panic(v[443] == 57);
    assert_or_panic(v[444] == 58);
    assert_or_panic(v[445] == 59);
    assert_or_panic(v[446] == 60);
    assert_or_panic(v[447] == 61);
    assert_or_panic(v[448] == 62);
    assert_or_panic(v[449] == 63);
    assert_or_panic(v[450] == 64);
    assert_or_panic(v[451] == 65);
    assert_or_panic(v[452] == 66);
    assert_or_panic(v[453] == 67);
    assert_or_panic(v[454] == 68);
    assert_or_panic(v[455] == 69);
    assert_or_panic(v[456] == 70);
    assert_or_panic(v[457] == 71);
    assert_or_panic(v[458] == 72);
    assert_or_panic(v[459] == 73);
    assert_or_panic(v[460] == 74);
    assert_or_panic(v[461] == 75);
    assert_or_panic(v[462] == 76);
    assert_or_panic(v[463] == 77);
    assert_or_panic(v[464] == 78);
    assert_or_panic(v[465] == 79);
    assert_or_panic(v[466] == 80);
    assert_or_panic(v[467] == 81);
    assert_or_panic(v[468] == 82);
    assert_or_panic(v[469] == 83);
    assert_or_panic(v[470] == 84);
    assert_or_panic(v[471] == 85);
    assert_or_panic(v[472] == 86);
    assert_or_panic(v[473] == 87);
    assert_or_panic(v[474] == 88);
    assert_or_panic(v[475] == 89);
    assert_or_panic(v[476] == 90);
    assert_or_panic(v[477] == 91);
    assert_or_panic(v[478] == 92);
    assert_or_panic(v[479] == 93);
    assert_or_panic(v[480] == 94);
    assert_or_panic(v[481] == 95);
    assert_or_panic(v[482] == 96);
    assert_or_panic(v[483] == 97);
    assert_or_panic(v[484] == 98);
    assert_or_panic(v[485] == 99);
    assert_or_panic(v[486] ==  0);
    assert_or_panic(v[487] ==  1);
    assert_or_panic(v[488] ==  2);
    assert_or_panic(v[489] ==  3);
    assert_or_panic(v[490] ==  4);
    assert_or_panic(v[491] ==  5);
    assert_or_panic(v[492] ==  6);
    assert_or_panic(v[493] ==  7);
    assert_or_panic(v[494] ==  8);
    assert_or_panic(v[495] ==  9);
    assert_or_panic(v[496] == 10);
    assert_or_panic(v[497] == 11);
    assert_or_panic(v[498] == 12);
    assert_or_panic(v[499] == 13);
    assert_or_panic(v[500] == 14);
    assert_or_panic(v[501] == 15);
    assert_or_panic(v[502] == 16);
    assert_or_panic(v[503] == 17);
    assert_or_panic(v[504] == 18);
    assert_or_panic(v[505] == 19);
    assert_or_panic(v[506] == 20);
    assert_or_panic(v[507] == 21);
    assert_or_panic(v[508] == 22);
    assert_or_panic(v[509] == 23);
    assert_or_panic(v[510] == 24);
    assert_or_panic(v[511] == 25);
    zig_vector_512_u8((Vector_512_u8){
        26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41,
        42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
        58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73,
        74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89,
        90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,  1,  2,  3,  4,  5,
        6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
        22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37,
        38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53,
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69,
        70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85,
        86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,  1,
        2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17,
        18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33,
        34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
        50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65,
        66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81,
        82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97,
        98, 99, 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13,
        14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
        30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45,
        46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61,
        62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77,
        78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93,
        94, 95, 96, 97, 98, 99, 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,
        10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,
        26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41,
        42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
        58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73,
        74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89,
        90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,  1,  2,  3,  4,  5,
        6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
        22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37,
    }, 512);
}

typedef uint16_t Vector_1_u16 __attribute__((vector_size(1 * sizeof(uint16_t))));

Vector_1_u16 zig_ret_vector_1_u16(void);
void zig_vector_1_u16(Vector_1_u16, size_t);

Vector_1_u16 c_ret_vector_1_u16(void) {
    return (Vector_1_u16){ 3 };
}
void c_vector_1_u16(Vector_1_u16 v, size_t i) {
    assert_or_panic(v[0] == 4);
    assert_or_panic(i == 1);
}
void c_test_vector_1_u16(void) {
    Vector_1_u16 v = zig_ret_vector_1_u16();
    assert_or_panic(v[0] == 1);
    zig_vector_1_u16((Vector_1_u16){ 2 }, 1);
}

typedef uint16_t Vector_2_u16 __attribute__((vector_size(2 * sizeof(uint16_t))));

Vector_2_u16 zig_ret_vector_2_u16(void);
void zig_vector_2_u16(Vector_2_u16, size_t);

Vector_2_u16 c_ret_vector_2_u16(void) {
    return (Vector_2_u16){ 9, 10 };
}
void c_vector_2_u16(Vector_2_u16 v, size_t i) {
    assert_or_panic(v[0] == 11);
    assert_or_panic(v[1] == 12);
    assert_or_panic(i == 2);
}
void c_test_vector_2_u16(void) {
    Vector_2_u16 v = zig_ret_vector_2_u16();
    assert_or_panic(v[0] == 5);
    assert_or_panic(v[1] == 6);
    zig_vector_2_u16((Vector_2_u16){ 7, 8 }, 2);
}

typedef uint16_t Vector_3_u16 __attribute__((vector_size(3 * sizeof(uint16_t))));

Vector_3_u16 zig_ret_vector_3_u16(void);
void zig_vector_3_u16(Vector_3_u16, size_t);

Vector_3_u16 c_ret_vector_3_u16(void) {
    return (Vector_3_u16){ 19, 20, 21 };
}
void c_vector_3_u16(Vector_3_u16 v, size_t i) {
    assert_or_panic(v[0] == 22);
    assert_or_panic(v[1] == 23);
    assert_or_panic(v[2] == 24);
    assert_or_panic(i == 3);
}
void c_test_vector_3_u16(void) {
    Vector_3_u16 v = zig_ret_vector_3_u16();
    assert_or_panic(v[0] == 13);
    assert_or_panic(v[1] == 14);
    assert_or_panic(v[2] == 15);
    zig_vector_3_u16((Vector_3_u16){ 16, 17, 18 }, 3);
}

typedef uint16_t Vector_4_u16 __attribute__((vector_size(4 * sizeof(uint16_t))));

Vector_4_u16 zig_ret_vector_4_u16(void);

void zig_vector_4_u16(Vector_4_u16, size_t);
void zig_vector_4_u16_vector_4_u16(Vector_4_u16, Vector_4_u16, size_t);

Vector_4_u16 c_ret_vector_4_u16(void) {
    return (Vector_4_u16){ 41, 42, 43, 44 };
}
void c_vector_4_u16(Vector_4_u16 v, size_t i) {
    assert_or_panic(v[0] == 45);
    assert_or_panic(v[1] == 46);
    assert_or_panic(v[2] == 47);
    assert_or_panic(v[3] == 48);
    assert_or_panic(i == 4);
}
void c_vector_4_u16_vector_4_u16(Vector_4_u16 v0, Vector_4_u16 v1, size_t i) {
    assert_or_panic(v0[0] == 49);
    assert_or_panic(v0[1] == 50);
    assert_or_panic(v0[2] == 51);
    assert_or_panic(v0[3] == 52);
    assert_or_panic(v1[0] == 53);
    assert_or_panic(v1[1] == 54);
    assert_or_panic(v1[2] == 55);
    assert_or_panic(v1[3] == 56);
    assert_or_panic(i == 8);
}
void c_test_vector_4_u16(void) {
    Vector_4_u16 v = zig_ret_vector_4_u16();
    assert_or_panic(v[0] == 25);
    assert_or_panic(v[1] == 26);
    assert_or_panic(v[2] == 27);
    assert_or_panic(v[3] == 28);
    zig_vector_4_u16((Vector_4_u16){ 29, 30, 31, 32 }, 4);
    zig_vector_4_u16_vector_4_u16((Vector_4_u16){ 33, 34, 35, 36 }, (Vector_4_u16){ 37, 38, 39, 40 }, 8);
}

typedef uint16_t Vector_6_u16 __attribute__((vector_size(6 * sizeof(uint16_t))));

Vector_6_u16 zig_ret_vector_6_u16(void);
void zig_vector_6_u16(Vector_6_u16, size_t);

Vector_6_u16 c_ret_vector_6_u16(void) {
    return (Vector_6_u16){ 53, 54, 55, 56, 57, 58 };
}
void c_vector_6_u16(Vector_6_u16 v, size_t i) {
    assert_or_panic(v[0] == 59);
    assert_or_panic(v[1] == 60);
    assert_or_panic(v[2] == 61);
    assert_or_panic(v[3] == 62);
    assert_or_panic(v[4] == 63);
    assert_or_panic(v[5] == 64);
    assert_or_panic(i == 6);
}
void c_test_vector_6_u16(void) {
    Vector_6_u16 v = zig_ret_vector_6_u16();
    assert_or_panic(v[0] == 41);
    assert_or_panic(v[1] == 42);
    assert_or_panic(v[2] == 43);
    assert_or_panic(v[3] == 44);
    assert_or_panic(v[4] == 45);
    assert_or_panic(v[5] == 46);
    zig_vector_6_u16((Vector_6_u16){ 47, 48, 49, 50, 51, 52 }, 6);
}

typedef uint16_t Vector_8_u16 __attribute__((vector_size(8 * sizeof(uint16_t))));

Vector_8_u16 zig_ret_vector_8_u16(void);
void zig_vector_8_u16(Vector_8_u16, size_t);

Vector_8_u16 c_ret_vector_8_u16(void) {
    return (Vector_8_u16){ 81, 82, 83, 84, 85, 86, 87, 88 };
}
void c_vector_8_u16(Vector_8_u16 v, size_t i) {
    assert_or_panic(v[0] == 89);
    assert_or_panic(v[1] == 90);
    assert_or_panic(v[2] == 91);
    assert_or_panic(v[3] == 92);
    assert_or_panic(v[4] == 93);
    assert_or_panic(v[5] == 94);
    assert_or_panic(v[6] == 95);
    assert_or_panic(v[7] == 96);
    assert_or_panic(i == 8);
}
void c_test_vector_8_u16(void) {
    Vector_8_u16 v = zig_ret_vector_8_u16();
    assert_or_panic(v[0] == 65);
    assert_or_panic(v[1] == 66);
    assert_or_panic(v[2] == 67);
    assert_or_panic(v[3] == 68);
    assert_or_panic(v[4] == 69);
    assert_or_panic(v[5] == 70);
    assert_or_panic(v[6] == 71);
    assert_or_panic(v[7] == 72);
    zig_vector_8_u16((Vector_8_u16){ 73, 74, 75, 76, 77, 78, 79, 80 }, 8);
}

typedef uint16_t Vector_12_u16 __attribute__((vector_size(12 * sizeof(uint16_t))));

Vector_12_u16 zig_ret_vector_12_u16(void);
void zig_vector_12_u16(Vector_12_u16, size_t);

Vector_12_u16 c_ret_vector_12_u16(void) {
    return (Vector_12_u16){ 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132 };
}
void c_vector_12_u16(Vector_12_u16 v, size_t i) {
    assert_or_panic(v[0] == 133);
    assert_or_panic(v[1] == 134);
    assert_or_panic(v[2] == 135);
    assert_or_panic(v[3] == 136);
    assert_or_panic(v[4] == 137);
    assert_or_panic(v[5] == 138);
    assert_or_panic(v[6] == 139);
    assert_or_panic(v[7] == 140);
    assert_or_panic(v[8] == 141);
    assert_or_panic(v[9] == 142);
    assert_or_panic(v[10] == 143);
    assert_or_panic(v[11] == 144);
    assert_or_panic(i == 12);
}
void c_test_vector_12_u16(void) {
    Vector_12_u16 v = zig_ret_vector_12_u16();
    assert_or_panic(v[0] == 97);
    assert_or_panic(v[1] == 98);
    assert_or_panic(v[2] == 99);
    assert_or_panic(v[3] == 100);
    assert_or_panic(v[4] == 101);
    assert_or_panic(v[5] == 102);
    assert_or_panic(v[6] == 103);
    assert_or_panic(v[7] == 104);
    assert_or_panic(v[8] == 105);
    assert_or_panic(v[9] == 106);
    assert_or_panic(v[10] == 107);
    assert_or_panic(v[11] == 108);
    zig_vector_12_u16((Vector_12_u16){ 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120 }, 12);
}

typedef uint16_t Vector_16_u16 __attribute__((vector_size(16 * sizeof(uint16_t))));

Vector_16_u16 zig_ret_vector_16_u16(void);
void zig_vector_16_u16(Vector_16_u16, size_t);

Vector_16_u16 c_ret_vector_16_u16(void) {
    return (Vector_16_u16){ 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192 };
}
void c_vector_16_u16(Vector_16_u16 v, size_t i) {
    assert_or_panic(v[0] == 193);
    assert_or_panic(v[1] == 194);
    assert_or_panic(v[2] == 195);
    assert_or_panic(v[3] == 196);
    assert_or_panic(v[4] == 197);
    assert_or_panic(v[5] == 198);
    assert_or_panic(v[6] == 199);
    assert_or_panic(v[7] == 200);
    assert_or_panic(v[8] == 201);
    assert_or_panic(v[9] == 202);
    assert_or_panic(v[10] == 203);
    assert_or_panic(v[11] == 204);
    assert_or_panic(v[12] == 205);
    assert_or_panic(v[13] == 206);
    assert_or_panic(v[14] == 207);
    assert_or_panic(v[15] == 208);
    assert_or_panic(i == 16);
}
void c_test_vector_16_u16(void) {
    Vector_16_u16 v = zig_ret_vector_16_u16();
    assert_or_panic(v[0] == 145);
    assert_or_panic(v[1] == 146);
    assert_or_panic(v[2] == 147);
    assert_or_panic(v[3] == 148);
    assert_or_panic(v[4] == 149);
    assert_or_panic(v[5] == 150);
    assert_or_panic(v[6] == 151);
    assert_or_panic(v[7] == 152);
    assert_or_panic(v[8] == 153);
    assert_or_panic(v[9] == 154);
    assert_or_panic(v[10] == 155);
    assert_or_panic(v[11] == 156);
    assert_or_panic(v[12] == 157);
    assert_or_panic(v[13] == 158);
    assert_or_panic(v[14] == 159);
    assert_or_panic(v[15] == 160);
    zig_vector_16_u16((Vector_16_u16){ 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176 }, 16);
}

typedef uint16_t Vector_24_u16 __attribute__((vector_size(24 * sizeof(uint16_t))));

Vector_24_u16 zig_ret_vector_24_u16(void);
void zig_vector_24_u16(Vector_24_u16, size_t);

Vector_24_u16 c_ret_vector_24_u16(void) {
    return (Vector_24_u16){
        257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272,
        273, 274, 275, 276, 277, 278, 279, 280,
    };
}
void c_vector_24_u16(Vector_24_u16 v, size_t i) {
    assert_or_panic(v[0] == 281);
    assert_or_panic(v[1] == 282);
    assert_or_panic(v[2] == 283);
    assert_or_panic(v[3] == 284);
    assert_or_panic(v[4] == 285);
    assert_or_panic(v[5] == 286);
    assert_or_panic(v[6] == 287);
    assert_or_panic(v[7] == 288);
    assert_or_panic(v[8] == 289);
    assert_or_panic(v[9] == 290);
    assert_or_panic(v[10] == 291);
    assert_or_panic(v[11] == 292);
    assert_or_panic(v[12] == 293);
    assert_or_panic(v[13] == 294);
    assert_or_panic(v[14] == 295);
    assert_or_panic(v[15] == 296);
    assert_or_panic(v[16] == 297);
    assert_or_panic(v[17] == 298);
    assert_or_panic(v[18] == 299);
    assert_or_panic(v[19] == 300);
    assert_or_panic(v[20] == 301);
    assert_or_panic(v[21] == 302);
    assert_or_panic(v[22] == 303);
    assert_or_panic(v[23] == 304);
    assert_or_panic(i == 24);
}
void c_test_vector_24_u16(void) {
    Vector_24_u16 v = zig_ret_vector_24_u16();
    assert_or_panic(v[0] == 209);
    assert_or_panic(v[1] == 210);
    assert_or_panic(v[2] == 211);
    assert_or_panic(v[3] == 212);
    assert_or_panic(v[4] == 213);
    assert_or_panic(v[5] == 214);
    assert_or_panic(v[6] == 215);
    assert_or_panic(v[7] == 216);
    assert_or_panic(v[8] == 217);
    assert_or_panic(v[9] == 218);
    assert_or_panic(v[10] == 219);
    assert_or_panic(v[11] == 220);
    assert_or_panic(v[12] == 221);
    assert_or_panic(v[13] == 222);
    assert_or_panic(v[14] == 223);
    assert_or_panic(v[15] == 224);
    assert_or_panic(v[16] == 225);
    assert_or_panic(v[17] == 226);
    assert_or_panic(v[18] == 227);
    assert_or_panic(v[19] == 228);
    assert_or_panic(v[20] == 229);
    assert_or_panic(v[21] == 230);
    assert_or_panic(v[22] == 231);
    assert_or_panic(v[23] == 232);
    zig_vector_24_u16((Vector_24_u16){
        233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248,
        249, 250, 251, 252, 253, 254, 255, 256,
    }, 24);
}

typedef uint16_t Vector_32_u16 __attribute__((vector_size(32 * sizeof(uint16_t))));

Vector_32_u16 zig_ret_vector_32_u16(void);
void zig_vector_32_u16(Vector_32_u16, size_t);

Vector_32_u16 c_ret_vector_32_u16(void) {
    return (Vector_32_u16){
        369, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 382, 383, 384,
        385, 386, 387, 388, 389, 390, 391, 392, 393, 394, 395, 396, 397, 398, 399, 400,
    };
}
void c_vector_32_u16(Vector_32_u16 v, size_t i) {
    assert_or_panic(v[0] == 401);
    assert_or_panic(v[1] == 402);
    assert_or_panic(v[2] == 403);
    assert_or_panic(v[3] == 404);
    assert_or_panic(v[4] == 405);
    assert_or_panic(v[5] == 406);
    assert_or_panic(v[6] == 407);
    assert_or_panic(v[7] == 408);
    assert_or_panic(v[8] == 409);
    assert_or_panic(v[9] == 410);
    assert_or_panic(v[10] == 411);
    assert_or_panic(v[11] == 412);
    assert_or_panic(v[12] == 413);
    assert_or_panic(v[13] == 414);
    assert_or_panic(v[14] == 415);
    assert_or_panic(v[15] == 416);
    assert_or_panic(v[16] == 417);
    assert_or_panic(v[17] == 418);
    assert_or_panic(v[18] == 419);
    assert_or_panic(v[19] == 420);
    assert_or_panic(v[20] == 421);
    assert_or_panic(v[21] == 422);
    assert_or_panic(v[22] == 423);
    assert_or_panic(v[23] == 424);
    assert_or_panic(v[24] == 425);
    assert_or_panic(v[25] == 426);
    assert_or_panic(v[26] == 427);
    assert_or_panic(v[27] == 428);
    assert_or_panic(v[28] == 429);
    assert_or_panic(v[29] == 430);
    assert_or_panic(v[30] == 431);
    assert_or_panic(v[31] == 432);
    assert_or_panic(i == 32);
}
void c_test_vector_32_u16(void) {
    Vector_32_u16 v = zig_ret_vector_32_u16();
    assert_or_panic(v[0] == 305);
    assert_or_panic(v[1] == 306);
    assert_or_panic(v[2] == 307);
    assert_or_panic(v[3] == 308);
    assert_or_panic(v[4] == 309);
    assert_or_panic(v[5] == 310);
    assert_or_panic(v[6] == 311);
    assert_or_panic(v[7] == 312);
    assert_or_panic(v[8] == 313);
    assert_or_panic(v[9] == 314);
    assert_or_panic(v[10] == 315);
    assert_or_panic(v[11] == 316);
    assert_or_panic(v[12] == 317);
    assert_or_panic(v[13] == 318);
    assert_or_panic(v[14] == 319);
    assert_or_panic(v[15] == 320);
    assert_or_panic(v[16] == 321);
    assert_or_panic(v[17] == 322);
    assert_or_panic(v[18] == 323);
    assert_or_panic(v[19] == 324);
    assert_or_panic(v[20] == 325);
    assert_or_panic(v[21] == 326);
    assert_or_panic(v[22] == 327);
    assert_or_panic(v[23] == 328);
    assert_or_panic(v[24] == 329);
    assert_or_panic(v[25] == 330);
    assert_or_panic(v[26] == 331);
    assert_or_panic(v[27] == 332);
    assert_or_panic(v[28] == 333);
    assert_or_panic(v[29] == 334);
    assert_or_panic(v[30] == 335);
    assert_or_panic(v[31] == 336);
    zig_vector_32_u16((Vector_32_u16){
        337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351, 352,
        353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368,
    }, 32);
}

typedef uint16_t Vector_48_u16 __attribute__((vector_size(48 * sizeof(uint16_t))));

Vector_48_u16 zig_ret_vector_48_u16(void);
void zig_vector_48_u16(Vector_48_u16, size_t);

Vector_48_u16 c_ret_vector_48_u16(void) {
    return (Vector_48_u16){
        529, 530, 531, 532, 533, 534, 535, 536, 537, 538, 539, 540, 541, 542, 543, 544,
        545, 546, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 560,
        561, 562, 563, 564, 565, 566, 567, 568, 569, 570, 571, 572, 573, 574, 575, 576,
    };
}
void c_vector_48_u16(Vector_48_u16 v, size_t i) {
    assert_or_panic(v[0] == 577);
    assert_or_panic(v[1] == 578);
    assert_or_panic(v[2] == 579);
    assert_or_panic(v[3] == 580);
    assert_or_panic(v[4] == 581);
    assert_or_panic(v[5] == 582);
    assert_or_panic(v[6] == 583);
    assert_or_panic(v[7] == 584);
    assert_or_panic(v[8] == 585);
    assert_or_panic(v[9] == 586);
    assert_or_panic(v[10] == 587);
    assert_or_panic(v[11] == 588);
    assert_or_panic(v[12] == 589);
    assert_or_panic(v[13] == 590);
    assert_or_panic(v[14] == 591);
    assert_or_panic(v[15] == 592);
    assert_or_panic(v[16] == 593);
    assert_or_panic(v[17] == 594);
    assert_or_panic(v[18] == 595);
    assert_or_panic(v[19] == 596);
    assert_or_panic(v[20] == 597);
    assert_or_panic(v[21] == 598);
    assert_or_panic(v[22] == 599);
    assert_or_panic(v[23] == 600);
    assert_or_panic(v[24] == 601);
    assert_or_panic(v[25] == 602);
    assert_or_panic(v[26] == 603);
    assert_or_panic(v[27] == 604);
    assert_or_panic(v[28] == 605);
    assert_or_panic(v[29] == 606);
    assert_or_panic(v[30] == 607);
    assert_or_panic(v[31] == 608);
    assert_or_panic(v[32] == 609);
    assert_or_panic(v[33] == 610);
    assert_or_panic(v[34] == 611);
    assert_or_panic(v[35] == 612);
    assert_or_panic(v[36] == 613);
    assert_or_panic(v[37] == 614);
    assert_or_panic(v[38] == 615);
    assert_or_panic(v[39] == 616);
    assert_or_panic(v[40] == 617);
    assert_or_panic(v[41] == 618);
    assert_or_panic(v[42] == 619);
    assert_or_panic(v[43] == 620);
    assert_or_panic(v[44] == 621);
    assert_or_panic(v[45] == 622);
    assert_or_panic(v[46] == 623);
    assert_or_panic(v[47] == 624);
    assert_or_panic(i == 48);
}
void c_test_vector_48_u16(void) {
    Vector_48_u16 v = zig_ret_vector_48_u16();
    assert_or_panic(v[0] == 433);
    assert_or_panic(v[1] == 434);
    assert_or_panic(v[2] == 435);
    assert_or_panic(v[3] == 436);
    assert_or_panic(v[4] == 437);
    assert_or_panic(v[5] == 438);
    assert_or_panic(v[6] == 439);
    assert_or_panic(v[7] == 440);
    assert_or_panic(v[8] == 441);
    assert_or_panic(v[9] == 442);
    assert_or_panic(v[10] == 443);
    assert_or_panic(v[11] == 444);
    assert_or_panic(v[12] == 445);
    assert_or_panic(v[13] == 446);
    assert_or_panic(v[14] == 447);
    assert_or_panic(v[15] == 448);
    assert_or_panic(v[16] == 449);
    assert_or_panic(v[17] == 450);
    assert_or_panic(v[18] == 451);
    assert_or_panic(v[19] == 452);
    assert_or_panic(v[20] == 453);
    assert_or_panic(v[21] == 454);
    assert_or_panic(v[22] == 455);
    assert_or_panic(v[23] == 456);
    assert_or_panic(v[24] == 457);
    assert_or_panic(v[25] == 458);
    assert_or_panic(v[26] == 459);
    assert_or_panic(v[27] == 460);
    assert_or_panic(v[28] == 461);
    assert_or_panic(v[29] == 462);
    assert_or_panic(v[30] == 463);
    assert_or_panic(v[31] == 464);
    assert_or_panic(v[32] == 465);
    assert_or_panic(v[33] == 466);
    assert_or_panic(v[34] == 467);
    assert_or_panic(v[35] == 468);
    assert_or_panic(v[36] == 469);
    assert_or_panic(v[37] == 470);
    assert_or_panic(v[38] == 471);
    assert_or_panic(v[39] == 472);
    assert_or_panic(v[40] == 473);
    assert_or_panic(v[41] == 474);
    assert_or_panic(v[42] == 475);
    assert_or_panic(v[43] == 476);
    assert_or_panic(v[44] == 477);
    assert_or_panic(v[45] == 478);
    assert_or_panic(v[46] == 479);
    assert_or_panic(v[47] == 480);
    zig_vector_48_u16((Vector_48_u16){
        481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496,
        497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512,
        513, 514, 515, 516, 517, 518, 519, 520, 521, 522, 523, 524, 525, 526, 527, 528,
    }, 48);
}

typedef uint16_t Vector_64_u16 __attribute__((vector_size(64 * sizeof(uint16_t))));

Vector_64_u16 zig_ret_vector_64_u16(void);
void zig_vector_64_u16(Vector_64_u16, size_t);

Vector_64_u16 c_ret_vector_64_u16(void) {
    return (Vector_64_u16){
        753, 754, 755, 756, 757, 758, 759, 760, 761, 762, 763, 764, 765, 766, 767, 768,
        769, 770, 771, 772, 773, 774, 775, 776, 777, 778, 779, 780, 781, 782, 783, 784,
        785, 786, 787, 788, 789, 790, 791, 792, 793, 794, 795, 796, 797, 798, 799, 800,
        801, 802, 803, 804, 805, 806, 807, 808, 809, 810, 811, 812, 813, 814, 815, 816,
    };
}
void c_vector_64_u16(Vector_64_u16 v, size_t i) {
    assert_or_panic(v[0] == 817);
    assert_or_panic(v[1] == 818);
    assert_or_panic(v[2] == 819);
    assert_or_panic(v[3] == 820);
    assert_or_panic(v[4] == 821);
    assert_or_panic(v[5] == 822);
    assert_or_panic(v[6] == 823);
    assert_or_panic(v[7] == 824);
    assert_or_panic(v[8] == 825);
    assert_or_panic(v[9] == 826);
    assert_or_panic(v[10] == 827);
    assert_or_panic(v[11] == 828);
    assert_or_panic(v[12] == 829);
    assert_or_panic(v[13] == 830);
    assert_or_panic(v[14] == 831);
    assert_or_panic(v[15] == 832);
    assert_or_panic(v[16] == 833);
    assert_or_panic(v[17] == 834);
    assert_or_panic(v[18] == 835);
    assert_or_panic(v[19] == 836);
    assert_or_panic(v[20] == 837);
    assert_or_panic(v[21] == 838);
    assert_or_panic(v[22] == 839);
    assert_or_panic(v[23] == 840);
    assert_or_panic(v[24] == 841);
    assert_or_panic(v[25] == 842);
    assert_or_panic(v[26] == 843);
    assert_or_panic(v[27] == 844);
    assert_or_panic(v[28] == 845);
    assert_or_panic(v[29] == 846);
    assert_or_panic(v[30] == 847);
    assert_or_panic(v[31] == 848);
    assert_or_panic(v[32] == 849);
    assert_or_panic(v[33] == 850);
    assert_or_panic(v[34] == 851);
    assert_or_panic(v[35] == 852);
    assert_or_panic(v[36] == 853);
    assert_or_panic(v[37] == 854);
    assert_or_panic(v[38] == 855);
    assert_or_panic(v[39] == 856);
    assert_or_panic(v[40] == 857);
    assert_or_panic(v[41] == 858);
    assert_or_panic(v[42] == 859);
    assert_or_panic(v[43] == 860);
    assert_or_panic(v[44] == 861);
    assert_or_panic(v[45] == 862);
    assert_or_panic(v[46] == 863);
    assert_or_panic(v[47] == 864);
    assert_or_panic(v[48] == 865);
    assert_or_panic(v[49] == 866);
    assert_or_panic(v[50] == 867);
    assert_or_panic(v[51] == 868);
    assert_or_panic(v[52] == 869);
    assert_or_panic(v[53] == 870);
    assert_or_panic(v[54] == 871);
    assert_or_panic(v[55] == 872);
    assert_or_panic(v[56] == 873);
    assert_or_panic(v[57] == 874);
    assert_or_panic(v[58] == 875);
    assert_or_panic(v[59] == 876);
    assert_or_panic(v[60] == 877);
    assert_or_panic(v[61] == 878);
    assert_or_panic(v[62] == 879);
    assert_or_panic(v[63] == 880);
    assert_or_panic(i == 64);
}
void c_test_vector_64_u16(void) {
    Vector_64_u16 v = zig_ret_vector_64_u16();
    assert_or_panic(v[0] == 625);
    assert_or_panic(v[1] == 626);
    assert_or_panic(v[2] == 627);
    assert_or_panic(v[3] == 628);
    assert_or_panic(v[4] == 629);
    assert_or_panic(v[5] == 630);
    assert_or_panic(v[6] == 631);
    assert_or_panic(v[7] == 632);
    assert_or_panic(v[8] == 633);
    assert_or_panic(v[9] == 634);
    assert_or_panic(v[10] == 635);
    assert_or_panic(v[11] == 636);
    assert_or_panic(v[12] == 637);
    assert_or_panic(v[13] == 638);
    assert_or_panic(v[14] == 639);
    assert_or_panic(v[15] == 640);
    assert_or_panic(v[16] == 641);
    assert_or_panic(v[17] == 642);
    assert_or_panic(v[18] == 643);
    assert_or_panic(v[19] == 644);
    assert_or_panic(v[20] == 645);
    assert_or_panic(v[21] == 646);
    assert_or_panic(v[22] == 647);
    assert_or_panic(v[23] == 648);
    assert_or_panic(v[24] == 649);
    assert_or_panic(v[25] == 650);
    assert_or_panic(v[26] == 651);
    assert_or_panic(v[27] == 652);
    assert_or_panic(v[28] == 653);
    assert_or_panic(v[29] == 654);
    assert_or_panic(v[30] == 655);
    assert_or_panic(v[31] == 656);
    assert_or_panic(v[32] == 657);
    assert_or_panic(v[33] == 658);
    assert_or_panic(v[34] == 659);
    assert_or_panic(v[35] == 660);
    assert_or_panic(v[36] == 661);
    assert_or_panic(v[37] == 662);
    assert_or_panic(v[38] == 663);
    assert_or_panic(v[39] == 664);
    assert_or_panic(v[40] == 665);
    assert_or_panic(v[41] == 666);
    assert_or_panic(v[42] == 667);
    assert_or_panic(v[43] == 668);
    assert_or_panic(v[44] == 669);
    assert_or_panic(v[45] == 670);
    assert_or_panic(v[46] == 671);
    assert_or_panic(v[47] == 672);
    assert_or_panic(v[48] == 673);
    assert_or_panic(v[49] == 674);
    assert_or_panic(v[50] == 675);
    assert_or_panic(v[51] == 676);
    assert_or_panic(v[52] == 677);
    assert_or_panic(v[53] == 678);
    assert_or_panic(v[54] == 679);
    assert_or_panic(v[55] == 680);
    assert_or_panic(v[56] == 681);
    assert_or_panic(v[57] == 682);
    assert_or_panic(v[58] == 683);
    assert_or_panic(v[59] == 684);
    assert_or_panic(v[60] == 685);
    assert_or_panic(v[61] == 686);
    assert_or_panic(v[62] == 687);
    assert_or_panic(v[63] == 688);
    zig_vector_64_u16((Vector_64_u16){
        689, 690, 691, 692, 693, 694, 695, 696, 697, 698, 699, 700, 701, 702, 703, 704,
        705, 706, 707, 708, 709, 710, 711, 712, 713, 714, 715, 716, 717, 718, 719, 720,
        721, 722, 723, 724, 725, 726, 727, 728, 729, 730, 731, 732, 733, 734, 735, 736,
        737, 738, 739, 740, 741, 742, 743, 744, 745, 746, 747, 748, 749, 750, 751, 752,
    }, 64);
}

typedef uint16_t Vector_96_u16 __attribute__((vector_size(96 * sizeof(uint16_t))));

Vector_96_u16 zig_ret_vector_96_u16(void);
void zig_vector_96_u16(Vector_96_u16, size_t);

Vector_96_u16 c_ret_vector_96_u16(void) {
    return (Vector_96_u16){
        1082, 1083, 1084, 1085, 1086, 1087, 1088, 1089, 1090, 1091, 1092, 1093, 1094, 1095, 1096, 1097,
        1098, 1099, 1100, 1101, 1102, 1103, 1104, 1105, 1106, 1107, 1108, 1109, 1110, 1111, 1112, 1113,
        1114, 1115, 1116, 1117, 1118, 1119, 1120, 1121, 1122, 1123, 1124, 1125, 1126, 1127, 1128, 1129,
        1130, 1131, 1132, 1133, 1134, 1135, 1136, 1137, 1138, 1139, 1140, 1141, 1142, 1143, 1144, 1145,
        1146, 1147, 1148, 1149, 1150, 1151, 1152, 1153, 1154, 1155, 1156, 1157, 1158, 1159, 1160, 1161,
        1162, 1163, 1164, 1165, 1166, 1167, 1168, 1169, 1170, 1171, 1172, 1173, 1174, 1175, 1176, 1177,
    };
}
void c_vector_96_u16(Vector_96_u16 v, size_t i) {
    assert_or_panic(v[0] == 1178);
    assert_or_panic(v[1] == 1179);
    assert_or_panic(v[2] == 1180);
    assert_or_panic(v[3] == 1181);
    assert_or_panic(v[4] == 1182);
    assert_or_panic(v[5] == 1183);
    assert_or_panic(v[6] == 1184);
    assert_or_panic(v[7] == 1185);
    assert_or_panic(v[8] == 1186);
    assert_or_panic(v[9] == 1187);
    assert_or_panic(v[10] == 1188);
    assert_or_panic(v[11] == 1189);
    assert_or_panic(v[12] == 1190);
    assert_or_panic(v[13] == 1191);
    assert_or_panic(v[14] == 1192);
    assert_or_panic(v[15] == 1193);
    assert_or_panic(v[16] == 1194);
    assert_or_panic(v[17] == 1195);
    assert_or_panic(v[18] == 1196);
    assert_or_panic(v[19] == 1197);
    assert_or_panic(v[20] == 1198);
    assert_or_panic(v[21] == 1199);
    assert_or_panic(v[22] == 1200);
    assert_or_panic(v[23] == 1201);
    assert_or_panic(v[24] == 1202);
    assert_or_panic(v[25] == 1203);
    assert_or_panic(v[26] == 1204);
    assert_or_panic(v[27] == 1205);
    assert_or_panic(v[28] == 1206);
    assert_or_panic(v[29] == 1207);
    assert_or_panic(v[30] == 1208);
    assert_or_panic(v[31] == 1209);
    assert_or_panic(v[32] == 1210);
    assert_or_panic(v[33] == 1211);
    assert_or_panic(v[34] == 1212);
    assert_or_panic(v[35] == 1213);
    assert_or_panic(v[36] == 1214);
    assert_or_panic(v[37] == 1215);
    assert_or_panic(v[38] == 1216);
    assert_or_panic(v[39] == 1217);
    assert_or_panic(v[40] == 1218);
    assert_or_panic(v[41] == 1219);
    assert_or_panic(v[42] == 1220);
    assert_or_panic(v[43] == 1221);
    assert_or_panic(v[44] == 1222);
    assert_or_panic(v[45] == 1223);
    assert_or_panic(v[46] == 1224);
    assert_or_panic(v[47] == 1225);
    assert_or_panic(v[48] == 1226);
    assert_or_panic(v[49] == 1227);
    assert_or_panic(v[50] == 1228);
    assert_or_panic(v[51] == 1229);
    assert_or_panic(v[52] == 1230);
    assert_or_panic(v[53] == 1231);
    assert_or_panic(v[54] == 1232);
    assert_or_panic(v[55] == 1233);
    assert_or_panic(v[56] == 1234);
    assert_or_panic(v[57] == 1235);
    assert_or_panic(v[58] == 1236);
    assert_or_panic(v[59] == 1237);
    assert_or_panic(v[60] == 1238);
    assert_or_panic(v[61] == 1239);
    assert_or_panic(v[62] == 1240);
    assert_or_panic(v[63] == 1241);
    assert_or_panic(v[64] == 1242);
    assert_or_panic(v[65] == 1243);
    assert_or_panic(v[66] == 1244);
    assert_or_panic(v[67] == 1245);
    assert_or_panic(v[68] == 1246);
    assert_or_panic(v[69] == 1247);
    assert_or_panic(v[70] == 1248);
    assert_or_panic(v[71] == 1249);
    assert_or_panic(v[72] == 1250);
    assert_or_panic(v[73] == 1251);
    assert_or_panic(v[74] == 1252);
    assert_or_panic(v[75] == 1253);
    assert_or_panic(v[76] == 1254);
    assert_or_panic(v[77] == 1255);
    assert_or_panic(v[80] == 1258);
    assert_or_panic(v[81] == 1259);
    assert_or_panic(v[82] == 1260);
    assert_or_panic(v[83] == 1261);
    assert_or_panic(v[84] == 1262);
    assert_or_panic(v[85] == 1263);
    assert_or_panic(v[86] == 1264);
    assert_or_panic(v[87] == 1265);
    assert_or_panic(v[88] == 1266);
    assert_or_panic(v[89] == 1267);
    assert_or_panic(v[90] == 1268);
    assert_or_panic(v[91] == 1269);
    assert_or_panic(v[92] == 1270);
    assert_or_panic(v[93] == 1271);
    assert_or_panic(v[94] == 1272);
    assert_or_panic(v[95] == 1273);
    assert_or_panic(i == 96);
}
void c_test_vector_96_u16(void) {
    Vector_96_u16 v = zig_ret_vector_96_u16();
    assert_or_panic(v[0] == 890);
    assert_or_panic(v[1] == 891);
    assert_or_panic(v[2] == 892);
    assert_or_panic(v[3] == 893);
    assert_or_panic(v[4] == 894);
    assert_or_panic(v[5] == 895);
    assert_or_panic(v[6] == 896);
    assert_or_panic(v[7] == 897);
    assert_or_panic(v[8] == 898);
    assert_or_panic(v[9] == 899);
    assert_or_panic(v[10] == 900);
    assert_or_panic(v[11] == 901);
    assert_or_panic(v[12] == 902);
    assert_or_panic(v[13] == 903);
    assert_or_panic(v[14] == 904);
    assert_or_panic(v[15] == 905);
    assert_or_panic(v[16] == 906);
    assert_or_panic(v[17] == 907);
    assert_or_panic(v[18] == 908);
    assert_or_panic(v[19] == 909);
    assert_or_panic(v[20] == 910);
    assert_or_panic(v[21] == 911);
    assert_or_panic(v[22] == 912);
    assert_or_panic(v[23] == 913);
    assert_or_panic(v[24] == 914);
    assert_or_panic(v[25] == 915);
    assert_or_panic(v[26] == 916);
    assert_or_panic(v[27] == 917);
    assert_or_panic(v[28] == 918);
    assert_or_panic(v[29] == 919);
    assert_or_panic(v[30] == 920);
    assert_or_panic(v[31] == 921);
    assert_or_panic(v[32] == 922);
    assert_or_panic(v[33] == 923);
    assert_or_panic(v[34] == 924);
    assert_or_panic(v[35] == 925);
    assert_or_panic(v[36] == 926);
    assert_or_panic(v[37] == 927);
    assert_or_panic(v[38] == 928);
    assert_or_panic(v[39] == 929);
    assert_or_panic(v[40] == 930);
    assert_or_panic(v[41] == 931);
    assert_or_panic(v[42] == 932);
    assert_or_panic(v[43] == 933);
    assert_or_panic(v[44] == 934);
    assert_or_panic(v[45] == 935);
    assert_or_panic(v[46] == 936);
    assert_or_panic(v[47] == 937);
    assert_or_panic(v[48] == 938);
    assert_or_panic(v[49] == 939);
    assert_or_panic(v[50] == 940);
    assert_or_panic(v[51] == 941);
    assert_or_panic(v[52] == 942);
    assert_or_panic(v[53] == 943);
    assert_or_panic(v[54] == 944);
    assert_or_panic(v[55] == 945);
    assert_or_panic(v[56] == 946);
    assert_or_panic(v[57] == 947);
    assert_or_panic(v[58] == 948);
    assert_or_panic(v[59] == 949);
    assert_or_panic(v[60] == 950);
    assert_or_panic(v[61] == 951);
    assert_or_panic(v[62] == 952);
    assert_or_panic(v[63] == 953);
    assert_or_panic(v[64] == 954);
    assert_or_panic(v[65] == 955);
    assert_or_panic(v[66] == 956);
    assert_or_panic(v[67] == 957);
    assert_or_panic(v[68] == 958);
    assert_or_panic(v[69] == 959);
    assert_or_panic(v[70] == 960);
    assert_or_panic(v[71] == 961);
    assert_or_panic(v[72] == 962);
    assert_or_panic(v[73] == 963);
    assert_or_panic(v[74] == 964);
    assert_or_panic(v[75] == 965);
    assert_or_panic(v[76] == 966);
    assert_or_panic(v[77] == 967);
    assert_or_panic(v[78] == 968);
    assert_or_panic(v[79] == 969);
    assert_or_panic(v[80] == 970);
    assert_or_panic(v[81] == 971);
    assert_or_panic(v[82] == 972);
    assert_or_panic(v[83] == 973);
    assert_or_panic(v[84] == 974);
    assert_or_panic(v[85] == 975);
    assert_or_panic(v[86] == 976);
    assert_or_panic(v[87] == 977);
    assert_or_panic(v[88] == 978);
    assert_or_panic(v[89] == 979);
    assert_or_panic(v[90] == 980);
    assert_or_panic(v[91] == 981);
    assert_or_panic(v[92] == 982);
    assert_or_panic(v[93] == 983);
    assert_or_panic(v[94] == 984);
    assert_or_panic(v[95] == 985);
    zig_vector_96_u16((Vector_96_u16){
        986,  987,  988,  989,  990,  991,  992,  993,  994,  995,  996,  997,  998,  999,  1000, 1001,
        1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010, 1011, 1012, 1013, 1014, 1015, 1016, 1017,
        1018, 1019, 1020, 1021, 1022, 1023, 1024, 1025, 1026, 1027, 1028, 1029, 1030, 1031, 1032, 1033,
        1034, 1035, 1036, 1037, 1038, 1039, 1040, 1041, 1042, 1043, 1044, 1045, 1046, 1047, 1048, 1049,
        1050, 1051, 1052, 1053, 1054, 1055, 1056, 1057, 1058, 1059, 1060, 1061, 1062, 1063, 1064, 1065,
        1066, 1067, 1068, 1069, 1070, 1071, 1072, 1073, 1074, 1075, 1076, 1077, 1078, 1079, 1080, 1081,
    }, 96);
}

typedef uint16_t Vector_128_u16 __attribute__((vector_size(128 * sizeof(uint16_t))));

Vector_128_u16 zig_ret_vector_128_u16(void);
void zig_vector_128_u16(Vector_128_u16, size_t);

Vector_128_u16 c_ret_vector_128_u16(void) {
    return (Vector_128_u16){
        1530, 1531, 1532, 1533, 1534, 1535, 1536, 1537, 1538, 1539, 1540, 1541, 1542, 1543, 1544, 1545,
        1546, 1547, 1548, 1549, 1550, 1551, 1552, 1553, 1554, 1555, 1556, 1557, 1558, 1559, 1560, 1561,
        1562, 1563, 1564, 1565, 1566, 1567, 1568, 1569, 1570, 1571, 1572, 1573, 1574, 1575, 1576, 1577,
        1578, 1579, 1580, 1581, 1582, 1583, 1584, 1585, 1586, 1587, 1588, 1589, 1590, 1591, 1592, 1593,
        1594, 1595, 1596, 1597, 1598, 1599, 1600, 1601, 1602, 1603, 1604, 1605, 1606, 1607, 1608, 1609,
        1610, 1611, 1612, 1613, 1614, 1615, 1616, 1617, 1618, 1619, 1620, 1621, 1622, 1623, 1624, 1625,
        1626, 1627, 1628, 1629, 1630, 1631, 1632, 1633, 1634, 1635, 1636, 1637, 1638, 1639, 1640, 1641,
        1642, 1643, 1644, 1645, 1646, 1647, 1648, 1649, 1650, 1651, 1652, 1653, 1654, 1655, 1656, 1657,
    };
}
void c_vector_128_u16(Vector_128_u16 v, size_t i) {
    assert_or_panic(v[0] == 1658);
    assert_or_panic(v[1] == 1659);
    assert_or_panic(v[2] == 1660);
    assert_or_panic(v[3] == 1661);
    assert_or_panic(v[4] == 1662);
    assert_or_panic(v[5] == 1663);
    assert_or_panic(v[6] == 1664);
    assert_or_panic(v[7] == 1665);
    assert_or_panic(v[8] == 1666);
    assert_or_panic(v[9] == 1667);
    assert_or_panic(v[10] == 1668);
    assert_or_panic(v[11] == 1669);
    assert_or_panic(v[12] == 1670);
    assert_or_panic(v[13] == 1671);
    assert_or_panic(v[14] == 1672);
    assert_or_panic(v[15] == 1673);
    assert_or_panic(v[16] == 1674);
    assert_or_panic(v[17] == 1675);
    assert_or_panic(v[18] == 1676);
    assert_or_panic(v[19] == 1677);
    assert_or_panic(v[20] == 1678);
    assert_or_panic(v[21] == 1679);
    assert_or_panic(v[22] == 1680);
    assert_or_panic(v[23] == 1681);
    assert_or_panic(v[24] == 1682);
    assert_or_panic(v[25] == 1683);
    assert_or_panic(v[26] == 1684);
    assert_or_panic(v[27] == 1685);
    assert_or_panic(v[28] == 1686);
    assert_or_panic(v[29] == 1687);
    assert_or_panic(v[30] == 1688);
    assert_or_panic(v[31] == 1689);
    assert_or_panic(v[32] == 1690);
    assert_or_panic(v[33] == 1691);
    assert_or_panic(v[34] == 1692);
    assert_or_panic(v[35] == 1693);
    assert_or_panic(v[36] == 1694);
    assert_or_panic(v[37] == 1695);
    assert_or_panic(v[38] == 1696);
    assert_or_panic(v[39] == 1697);
    assert_or_panic(v[40] == 1698);
    assert_or_panic(v[41] == 1699);
    assert_or_panic(v[42] == 1700);
    assert_or_panic(v[43] == 1701);
    assert_or_panic(v[44] == 1702);
    assert_or_panic(v[45] == 1703);
    assert_or_panic(v[46] == 1704);
    assert_or_panic(v[47] == 1705);
    assert_or_panic(v[48] == 1706);
    assert_or_panic(v[49] == 1707);
    assert_or_panic(v[50] == 1708);
    assert_or_panic(v[51] == 1709);
    assert_or_panic(v[52] == 1710);
    assert_or_panic(v[53] == 1711);
    assert_or_panic(v[54] == 1712);
    assert_or_panic(v[55] == 1713);
    assert_or_panic(v[56] == 1714);
    assert_or_panic(v[57] == 1715);
    assert_or_panic(v[58] == 1716);
    assert_or_panic(v[59] == 1717);
    assert_or_panic(v[60] == 1718);
    assert_or_panic(v[61] == 1719);
    assert_or_panic(v[62] == 1720);
    assert_or_panic(v[63] == 1721);
    assert_or_panic(v[64] == 1722);
    assert_or_panic(v[65] == 1723);
    assert_or_panic(v[66] == 1724);
    assert_or_panic(v[67] == 1725);
    assert_or_panic(v[68] == 1726);
    assert_or_panic(v[69] == 1727);
    assert_or_panic(v[70] == 1728);
    assert_or_panic(v[71] == 1729);
    assert_or_panic(v[72] == 1730);
    assert_or_panic(v[73] == 1731);
    assert_or_panic(v[74] == 1732);
    assert_or_panic(v[75] == 1733);
    assert_or_panic(v[76] == 1734);
    assert_or_panic(v[77] == 1735);
    assert_or_panic(v[78] == 1736);
    assert_or_panic(v[79] == 1737);
    assert_or_panic(v[80] == 1738);
    assert_or_panic(v[81] == 1739);
    assert_or_panic(v[82] == 1740);
    assert_or_panic(v[83] == 1741);
    assert_or_panic(v[84] == 1742);
    assert_or_panic(v[85] == 1743);
    assert_or_panic(v[86] == 1744);
    assert_or_panic(v[87] == 1745);
    assert_or_panic(v[88] == 1746);
    assert_or_panic(v[89] == 1747);
    assert_or_panic(v[90] == 1748);
    assert_or_panic(v[91] == 1749);
    assert_or_panic(v[92] == 1750);
    assert_or_panic(v[93] == 1751);
    assert_or_panic(v[94] == 1752);
    assert_or_panic(v[95] == 1753);
    assert_or_panic(v[96] == 1754);
    assert_or_panic(v[97] == 1755);
    assert_or_panic(v[98] == 1756);
    assert_or_panic(v[99] == 1757);
    assert_or_panic(v[100] == 1758);
    assert_or_panic(v[101] == 1759);
    assert_or_panic(v[102] == 1760);
    assert_or_panic(v[103] == 1761);
    assert_or_panic(v[104] == 1762);
    assert_or_panic(v[105] == 1763);
    assert_or_panic(v[106] == 1764);
    assert_or_panic(v[107] == 1765);
    assert_or_panic(v[108] == 1766);
    assert_or_panic(v[109] == 1767);
    assert_or_panic(v[110] == 1768);
    assert_or_panic(v[111] == 1769);
    assert_or_panic(v[112] == 1770);
    assert_or_panic(v[113] == 1771);
    assert_or_panic(v[114] == 1772);
    assert_or_panic(v[115] == 1773);
    assert_or_panic(v[116] == 1774);
    assert_or_panic(v[117] == 1775);
    assert_or_panic(v[118] == 1776);
    assert_or_panic(v[119] == 1777);
    assert_or_panic(v[120] == 1778);
    assert_or_panic(v[121] == 1779);
    assert_or_panic(v[122] == 1780);
    assert_or_panic(v[123] == 1781);
    assert_or_panic(v[124] == 1782);
    assert_or_panic(v[125] == 1783);
    assert_or_panic(v[126] == 1784);
    assert_or_panic(v[127] == 1785);
    assert_or_panic(i == 128);
}
void c_test_vector_128_u16(void) {
    Vector_128_u16 v = zig_ret_vector_128_u16();
    assert_or_panic(v[0] == 1274);
    assert_or_panic(v[1] == 1275);
    assert_or_panic(v[2] == 1276);
    assert_or_panic(v[3] == 1277);
    assert_or_panic(v[4] == 1278);
    assert_or_panic(v[5] == 1279);
    assert_or_panic(v[6] == 1280);
    assert_or_panic(v[7] == 1281);
    assert_or_panic(v[8] == 1282);
    assert_or_panic(v[9] == 1283);
    assert_or_panic(v[10] == 1284);
    assert_or_panic(v[11] == 1285);
    assert_or_panic(v[12] == 1286);
    assert_or_panic(v[13] == 1287);
    assert_or_panic(v[14] == 1288);
    assert_or_panic(v[15] == 1289);
    assert_or_panic(v[16] == 1290);
    assert_or_panic(v[17] == 1291);
    assert_or_panic(v[18] == 1292);
    assert_or_panic(v[19] == 1293);
    assert_or_panic(v[20] == 1294);
    assert_or_panic(v[21] == 1295);
    assert_or_panic(v[22] == 1296);
    assert_or_panic(v[23] == 1297);
    assert_or_panic(v[24] == 1298);
    assert_or_panic(v[25] == 1299);
    assert_or_panic(v[26] == 1300);
    assert_or_panic(v[27] == 1301);
    assert_or_panic(v[28] == 1302);
    assert_or_panic(v[29] == 1303);
    assert_or_panic(v[30] == 1304);
    assert_or_panic(v[31] == 1305);
    assert_or_panic(v[32] == 1306);
    assert_or_panic(v[33] == 1307);
    assert_or_panic(v[34] == 1308);
    assert_or_panic(v[35] == 1309);
    assert_or_panic(v[36] == 1310);
    assert_or_panic(v[37] == 1311);
    assert_or_panic(v[38] == 1312);
    assert_or_panic(v[39] == 1313);
    assert_or_panic(v[40] == 1314);
    assert_or_panic(v[41] == 1315);
    assert_or_panic(v[42] == 1316);
    assert_or_panic(v[43] == 1317);
    assert_or_panic(v[44] == 1318);
    assert_or_panic(v[45] == 1319);
    assert_or_panic(v[46] == 1320);
    assert_or_panic(v[47] == 1321);
    assert_or_panic(v[48] == 1322);
    assert_or_panic(v[49] == 1323);
    assert_or_panic(v[50] == 1324);
    assert_or_panic(v[51] == 1325);
    assert_or_panic(v[52] == 1326);
    assert_or_panic(v[53] == 1327);
    assert_or_panic(v[54] == 1328);
    assert_or_panic(v[55] == 1329);
    assert_or_panic(v[56] == 1330);
    assert_or_panic(v[57] == 1331);
    assert_or_panic(v[58] == 1332);
    assert_or_panic(v[59] == 1333);
    assert_or_panic(v[60] == 1334);
    assert_or_panic(v[61] == 1335);
    assert_or_panic(v[62] == 1336);
    assert_or_panic(v[63] == 1337);
    assert_or_panic(v[64] == 1338);
    assert_or_panic(v[65] == 1339);
    assert_or_panic(v[66] == 1340);
    assert_or_panic(v[67] == 1341);
    assert_or_panic(v[68] == 1342);
    assert_or_panic(v[69] == 1343);
    assert_or_panic(v[70] == 1344);
    assert_or_panic(v[71] == 1345);
    assert_or_panic(v[72] == 1346);
    assert_or_panic(v[73] == 1347);
    assert_or_panic(v[74] == 1348);
    assert_or_panic(v[75] == 1349);
    assert_or_panic(v[76] == 1350);
    assert_or_panic(v[77] == 1351);
    assert_or_panic(v[78] == 1352);
    assert_or_panic(v[79] == 1353);
    assert_or_panic(v[80] == 1354);
    assert_or_panic(v[81] == 1355);
    assert_or_panic(v[82] == 1356);
    assert_or_panic(v[83] == 1357);
    assert_or_panic(v[84] == 1358);
    assert_or_panic(v[85] == 1359);
    assert_or_panic(v[86] == 1360);
    assert_or_panic(v[87] == 1361);
    assert_or_panic(v[88] == 1362);
    assert_or_panic(v[89] == 1363);
    assert_or_panic(v[90] == 1364);
    assert_or_panic(v[91] == 1365);
    assert_or_panic(v[92] == 1366);
    assert_or_panic(v[93] == 1367);
    assert_or_panic(v[94] == 1368);
    assert_or_panic(v[95] == 1369);
    assert_or_panic(v[96] == 1370);
    assert_or_panic(v[97] == 1371);
    assert_or_panic(v[98] == 1372);
    assert_or_panic(v[99] == 1373);
    assert_or_panic(v[100] == 1374);
    assert_or_panic(v[101] == 1375);
    assert_or_panic(v[102] == 1376);
    assert_or_panic(v[103] == 1377);
    assert_or_panic(v[104] == 1378);
    assert_or_panic(v[105] == 1379);
    assert_or_panic(v[106] == 1380);
    assert_or_panic(v[107] == 1381);
    assert_or_panic(v[108] == 1382);
    assert_or_panic(v[109] == 1383);
    assert_or_panic(v[110] == 1384);
    assert_or_panic(v[111] == 1385);
    assert_or_panic(v[112] == 1386);
    assert_or_panic(v[113] == 1387);
    assert_or_panic(v[114] == 1388);
    assert_or_panic(v[115] == 1389);
    assert_or_panic(v[116] == 1390);
    assert_or_panic(v[117] == 1391);
    assert_or_panic(v[118] == 1392);
    assert_or_panic(v[119] == 1393);
    assert_or_panic(v[120] == 1394);
    assert_or_panic(v[121] == 1395);
    assert_or_panic(v[122] == 1396);
    assert_or_panic(v[123] == 1397);
    assert_or_panic(v[124] == 1398);
    assert_or_panic(v[125] == 1399);
    assert_or_panic(v[126] == 1400);
    assert_or_panic(v[127] == 1401);
    zig_vector_128_u16((Vector_128_u16){
        1402, 1403, 1404, 1405, 1406, 1407, 1408, 1409, 1410, 1411, 1412, 1413, 1414, 1415, 1416, 1417,
        1418, 1419, 1420, 1421, 1422, 1423, 1424, 1425, 1426, 1427, 1428, 1429, 1430, 1431, 1432, 1433,
        1434, 1435, 1436, 1437, 1438, 1439, 1440, 1441, 1442, 1443, 1444, 1445, 1446, 1447, 1448, 1449,
        1450, 1451, 1452, 1453, 1454, 1455, 1456, 1457, 1458, 1459, 1460, 1461, 1462, 1463, 1464, 1465,
        1466, 1467, 1468, 1469, 1470, 1471, 1472, 1473, 1474, 1475, 1476, 1477, 1478, 1479, 1480, 1481,
        1482, 1483, 1484, 1485, 1486, 1487, 1488, 1489, 1490, 1491, 1492, 1493, 1494, 1495, 1496, 1497,
        1498, 1499, 1500, 1501, 1502, 1503, 1504, 1505, 1506, 1507, 1508, 1509, 1510, 1511, 1512, 1513,
        1514, 1515, 1516, 1517, 1518, 1519, 1520, 1521, 1522, 1523, 1524, 1525, 1526, 1527, 1528, 1529,
    }, 128);
}

typedef uint16_t Vector_192_u16 __attribute__((vector_size(192 * sizeof(uint16_t))));

Vector_192_u16 zig_ret_vector_192_u16(void);
void zig_vector_192_u16(Vector_192_u16, size_t);

Vector_192_u16 c_ret_vector_192_u16(void) {
    return (Vector_192_u16){
        2170, 2171, 2172, 2173, 2174, 2175, 2176, 2177, 2178, 2179, 2180, 2181, 2182, 2183, 2184, 2185,
        2186, 2187, 2188, 2189, 2190, 2191, 2192, 2193, 2194, 2195, 2196, 2197, 2198, 2199, 2200, 2201,
        2202, 2203, 2204, 2205, 2206, 2207, 2208, 2209, 2210, 2211, 2212, 2213, 2214, 2215, 2216, 2217,
        2218, 2219, 2220, 2221, 2222, 2223, 2224, 2225, 2226, 2227, 2228, 2229, 2230, 2231, 2232, 2233,
        2234, 2235, 2236, 2237, 2238, 2239, 2240, 2241, 2242, 2243, 2244, 2245, 2246, 2247, 2248, 2249,
        2250, 2251, 2252, 2253, 2254, 2255, 2256, 2257, 2258, 2259, 2260, 2261, 2262, 2263, 2264, 2265,
        2266, 2267, 2268, 2269, 2270, 2271, 2272, 2273, 2274, 2275, 2276, 2277, 2278, 2279, 2280, 2281,
        2282, 2283, 2284, 2285, 2286, 2287, 2288, 2289, 2290, 2291, 2292, 2293, 2294, 2295, 2296, 2297,
        2298, 2299, 2300, 2301, 2302, 2303, 2304, 2305, 2306, 2307, 2308, 2309, 2310, 2311, 2312, 2313,
        2314, 2315, 2316, 2317, 2318, 2319, 2320, 2321, 2322, 2323, 2324, 2325, 2326, 2327, 2328, 2329,
        2330, 2331, 2332, 2333, 2334, 2335, 2336, 2337, 2338, 2339, 2340, 2341, 2342, 2343, 2344, 2345,
        2346, 2347, 2348, 2349, 2350, 2351, 2352, 2353, 2354, 2355, 2356, 2357, 2358, 2359, 2360, 2361,
    };
}
void c_vector_192_u16(Vector_192_u16 v, size_t i) {
    assert_or_panic(v[0] == 2362);
    assert_or_panic(v[1] == 2363);
    assert_or_panic(v[2] == 2364);
    assert_or_panic(v[3] == 2365);
    assert_or_panic(v[4] == 2366);
    assert_or_panic(v[5] == 2367);
    assert_or_panic(v[6] == 2368);
    assert_or_panic(v[7] == 2369);
    assert_or_panic(v[8] == 2370);
    assert_or_panic(v[9] == 2371);
    assert_or_panic(v[10] == 2372);
    assert_or_panic(v[11] == 2373);
    assert_or_panic(v[12] == 2374);
    assert_or_panic(v[13] == 2375);
    assert_or_panic(v[14] == 2376);
    assert_or_panic(v[15] == 2377);
    assert_or_panic(v[16] == 2378);
    assert_or_panic(v[17] == 2379);
    assert_or_panic(v[18] == 2380);
    assert_or_panic(v[19] == 2381);
    assert_or_panic(v[20] == 2382);
    assert_or_panic(v[21] == 2383);
    assert_or_panic(v[22] == 2384);
    assert_or_panic(v[23] == 2385);
    assert_or_panic(v[24] == 2386);
    assert_or_panic(v[25] == 2387);
    assert_or_panic(v[26] == 2388);
    assert_or_panic(v[27] == 2389);
    assert_or_panic(v[28] == 2390);
    assert_or_panic(v[29] == 2391);
    assert_or_panic(v[30] == 2392);
    assert_or_panic(v[31] == 2393);
    assert_or_panic(v[32] == 2394);
    assert_or_panic(v[33] == 2395);
    assert_or_panic(v[34] == 2396);
    assert_or_panic(v[35] == 2397);
    assert_or_panic(v[36] == 2398);
    assert_or_panic(v[37] == 2399);
    assert_or_panic(v[38] == 2400);
    assert_or_panic(v[39] == 2401);
    assert_or_panic(v[40] == 2402);
    assert_or_panic(v[41] == 2403);
    assert_or_panic(v[42] == 2404);
    assert_or_panic(v[43] == 2405);
    assert_or_panic(v[44] == 2406);
    assert_or_panic(v[45] == 2407);
    assert_or_panic(v[46] == 2408);
    assert_or_panic(v[47] == 2409);
    assert_or_panic(v[48] == 2410);
    assert_or_panic(v[49] == 2411);
    assert_or_panic(v[50] == 2412);
    assert_or_panic(v[51] == 2413);
    assert_or_panic(v[52] == 2414);
    assert_or_panic(v[53] == 2415);
    assert_or_panic(v[54] == 2416);
    assert_or_panic(v[55] == 2417);
    assert_or_panic(v[56] == 2418);
    assert_or_panic(v[57] == 2419);
    assert_or_panic(v[58] == 2420);
    assert_or_panic(v[59] == 2421);
    assert_or_panic(v[60] == 2422);
    assert_or_panic(v[61] == 2423);
    assert_or_panic(v[62] == 2424);
    assert_or_panic(v[63] == 2425);
    assert_or_panic(v[64] == 2426);
    assert_or_panic(v[65] == 2427);
    assert_or_panic(v[66] == 2428);
    assert_or_panic(v[67] == 2429);
    assert_or_panic(v[68] == 2430);
    assert_or_panic(v[69] == 2431);
    assert_or_panic(v[70] == 2432);
    assert_or_panic(v[71] == 2433);
    assert_or_panic(v[72] == 2434);
    assert_or_panic(v[73] == 2435);
    assert_or_panic(v[74] == 2436);
    assert_or_panic(v[75] == 2437);
    assert_or_panic(v[76] == 2438);
    assert_or_panic(v[77] == 2439);
    assert_or_panic(v[78] == 2440);
    assert_or_panic(v[79] == 2441);
    assert_or_panic(v[80] == 2442);
    assert_or_panic(v[81] == 2443);
    assert_or_panic(v[82] == 2444);
    assert_or_panic(v[83] == 2445);
    assert_or_panic(v[84] == 2446);
    assert_or_panic(v[85] == 2447);
    assert_or_panic(v[86] == 2448);
    assert_or_panic(v[87] == 2449);
    assert_or_panic(v[88] == 2450);
    assert_or_panic(v[89] == 2451);
    assert_or_panic(v[90] == 2452);
    assert_or_panic(v[91] == 2453);
    assert_or_panic(v[92] == 2454);
    assert_or_panic(v[93] == 2455);
    assert_or_panic(v[94] == 2456);
    assert_or_panic(v[95] == 2457);
    assert_or_panic(v[96] == 2458);
    assert_or_panic(v[97] == 2459);
    assert_or_panic(v[98] == 2460);
    assert_or_panic(v[99] == 2461);
    assert_or_panic(v[100] == 2462);
    assert_or_panic(v[101] == 2463);
    assert_or_panic(v[102] == 2464);
    assert_or_panic(v[103] == 2465);
    assert_or_panic(v[104] == 2466);
    assert_or_panic(v[105] == 2467);
    assert_or_panic(v[106] == 2468);
    assert_or_panic(v[107] == 2469);
    assert_or_panic(v[108] == 2470);
    assert_or_panic(v[109] == 2471);
    assert_or_panic(v[110] == 2472);
    assert_or_panic(v[111] == 2473);
    assert_or_panic(v[112] == 2474);
    assert_or_panic(v[113] == 2475);
    assert_or_panic(v[114] == 2476);
    assert_or_panic(v[115] == 2477);
    assert_or_panic(v[116] == 2478);
    assert_or_panic(v[117] == 2479);
    assert_or_panic(v[118] == 2480);
    assert_or_panic(v[119] == 2481);
    assert_or_panic(v[120] == 2482);
    assert_or_panic(v[121] == 2483);
    assert_or_panic(v[122] == 2484);
    assert_or_panic(v[123] == 2485);
    assert_or_panic(v[124] == 2486);
    assert_or_panic(v[125] == 2487);
    assert_or_panic(v[126] == 2488);
    assert_or_panic(v[127] == 2489);
    assert_or_panic(v[128] == 2490);
    assert_or_panic(v[129] == 2491);
    assert_or_panic(v[130] == 2492);
    assert_or_panic(v[131] == 2493);
    assert_or_panic(v[132] == 2494);
    assert_or_panic(v[133] == 2495);
    assert_or_panic(v[134] == 2496);
    assert_or_panic(v[135] == 2497);
    assert_or_panic(v[136] == 2498);
    assert_or_panic(v[137] == 2499);
    assert_or_panic(v[138] == 2500);
    assert_or_panic(v[139] == 2501);
    assert_or_panic(v[140] == 2502);
    assert_or_panic(v[141] == 2503);
    assert_or_panic(v[142] == 2504);
    assert_or_panic(v[143] == 2505);
    assert_or_panic(v[144] == 2506);
    assert_or_panic(v[145] == 2507);
    assert_or_panic(v[146] == 2508);
    assert_or_panic(v[147] == 2509);
    assert_or_panic(v[148] == 2510);
    assert_or_panic(v[149] == 2511);
    assert_or_panic(v[150] == 2512);
    assert_or_panic(v[151] == 2513);
    assert_or_panic(v[152] == 2514);
    assert_or_panic(v[153] == 2515);
    assert_or_panic(v[154] == 2516);
    assert_or_panic(v[155] == 2517);
    assert_or_panic(v[156] == 2518);
    assert_or_panic(v[157] == 2519);
    assert_or_panic(v[158] == 2520);
    assert_or_panic(v[159] == 2521);
    assert_or_panic(v[160] == 2522);
    assert_or_panic(v[161] == 2523);
    assert_or_panic(v[162] == 2524);
    assert_or_panic(v[163] == 2525);
    assert_or_panic(v[164] == 2526);
    assert_or_panic(v[165] == 2527);
    assert_or_panic(v[166] == 2528);
    assert_or_panic(v[167] == 2529);
    assert_or_panic(v[168] == 2530);
    assert_or_panic(v[169] == 2531);
    assert_or_panic(v[170] == 2532);
    assert_or_panic(v[171] == 2533);
    assert_or_panic(v[172] == 2534);
    assert_or_panic(v[173] == 2535);
    assert_or_panic(v[174] == 2536);
    assert_or_panic(v[175] == 2537);
    assert_or_panic(v[176] == 2538);
    assert_or_panic(v[177] == 2539);
    assert_or_panic(v[178] == 2540);
    assert_or_panic(v[179] == 2541);
    assert_or_panic(v[180] == 2542);
    assert_or_panic(v[181] == 2543);
    assert_or_panic(v[182] == 2544);
    assert_or_panic(v[183] == 2545);
    assert_or_panic(v[184] == 2546);
    assert_or_panic(v[185] == 2547);
    assert_or_panic(v[186] == 2548);
    assert_or_panic(v[187] == 2549);
    assert_or_panic(v[188] == 2550);
    assert_or_panic(v[189] == 2551);
    assert_or_panic(v[190] == 2552);
    assert_or_panic(v[191] == 2553);
    assert_or_panic(i == 192);
}
void c_test_vector_192_u16(void) {
    Vector_192_u16 v = zig_ret_vector_192_u16();
    assert_or_panic(v[0] == 1786);
    assert_or_panic(v[1] == 1787);
    assert_or_panic(v[2] == 1788);
    assert_or_panic(v[3] == 1789);
    assert_or_panic(v[4] == 1790);
    assert_or_panic(v[5] == 1791);
    assert_or_panic(v[6] == 1792);
    assert_or_panic(v[7] == 1793);
    assert_or_panic(v[8] == 1794);
    assert_or_panic(v[9] == 1795);
    assert_or_panic(v[10] == 1796);
    assert_or_panic(v[11] == 1797);
    assert_or_panic(v[12] == 1798);
    assert_or_panic(v[13] == 1799);
    assert_or_panic(v[14] == 1800);
    assert_or_panic(v[15] == 1801);
    assert_or_panic(v[16] == 1802);
    assert_or_panic(v[17] == 1803);
    assert_or_panic(v[18] == 1804);
    assert_or_panic(v[19] == 1805);
    assert_or_panic(v[20] == 1806);
    assert_or_panic(v[21] == 1807);
    assert_or_panic(v[22] == 1808);
    assert_or_panic(v[23] == 1809);
    assert_or_panic(v[24] == 1810);
    assert_or_panic(v[25] == 1811);
    assert_or_panic(v[26] == 1812);
    assert_or_panic(v[27] == 1813);
    assert_or_panic(v[28] == 1814);
    assert_or_panic(v[29] == 1815);
    assert_or_panic(v[30] == 1816);
    assert_or_panic(v[31] == 1817);
    assert_or_panic(v[32] == 1818);
    assert_or_panic(v[33] == 1819);
    assert_or_panic(v[34] == 1820);
    assert_or_panic(v[35] == 1821);
    assert_or_panic(v[36] == 1822);
    assert_or_panic(v[37] == 1823);
    assert_or_panic(v[38] == 1824);
    assert_or_panic(v[39] == 1825);
    assert_or_panic(v[40] == 1826);
    assert_or_panic(v[41] == 1827);
    assert_or_panic(v[42] == 1828);
    assert_or_panic(v[43] == 1829);
    assert_or_panic(v[44] == 1830);
    assert_or_panic(v[45] == 1831);
    assert_or_panic(v[46] == 1832);
    assert_or_panic(v[47] == 1833);
    assert_or_panic(v[48] == 1834);
    assert_or_panic(v[49] == 1835);
    assert_or_panic(v[50] == 1836);
    assert_or_panic(v[51] == 1837);
    assert_or_panic(v[52] == 1838);
    assert_or_panic(v[53] == 1839);
    assert_or_panic(v[54] == 1840);
    assert_or_panic(v[55] == 1841);
    assert_or_panic(v[56] == 1842);
    assert_or_panic(v[57] == 1843);
    assert_or_panic(v[58] == 1844);
    assert_or_panic(v[59] == 1845);
    assert_or_panic(v[60] == 1846);
    assert_or_panic(v[61] == 1847);
    assert_or_panic(v[62] == 1848);
    assert_or_panic(v[63] == 1849);
    assert_or_panic(v[64] == 1850);
    assert_or_panic(v[65] == 1851);
    assert_or_panic(v[66] == 1852);
    assert_or_panic(v[67] == 1853);
    assert_or_panic(v[68] == 1854);
    assert_or_panic(v[69] == 1855);
    assert_or_panic(v[70] == 1856);
    assert_or_panic(v[71] == 1857);
    assert_or_panic(v[72] == 1858);
    assert_or_panic(v[73] == 1859);
    assert_or_panic(v[74] == 1860);
    assert_or_panic(v[75] == 1861);
    assert_or_panic(v[76] == 1862);
    assert_or_panic(v[77] == 1863);
    assert_or_panic(v[78] == 1864);
    assert_or_panic(v[79] == 1865);
    assert_or_panic(v[80] == 1866);
    assert_or_panic(v[81] == 1867);
    assert_or_panic(v[82] == 1868);
    assert_or_panic(v[83] == 1869);
    assert_or_panic(v[84] == 1870);
    assert_or_panic(v[85] == 1871);
    assert_or_panic(v[86] == 1872);
    assert_or_panic(v[87] == 1873);
    assert_or_panic(v[88] == 1874);
    assert_or_panic(v[89] == 1875);
    assert_or_panic(v[90] == 1876);
    assert_or_panic(v[91] == 1877);
    assert_or_panic(v[92] == 1878);
    assert_or_panic(v[93] == 1879);
    assert_or_panic(v[94] == 1880);
    assert_or_panic(v[95] == 1881);
    assert_or_panic(v[96] == 1882);
    assert_or_panic(v[97] == 1883);
    assert_or_panic(v[98] == 1884);
    assert_or_panic(v[99] == 1885);
    assert_or_panic(v[100] == 1886);
    assert_or_panic(v[101] == 1887);
    assert_or_panic(v[102] == 1888);
    assert_or_panic(v[103] == 1889);
    assert_or_panic(v[104] == 1890);
    assert_or_panic(v[105] == 1891);
    assert_or_panic(v[106] == 1892);
    assert_or_panic(v[107] == 1893);
    assert_or_panic(v[108] == 1894);
    assert_or_panic(v[109] == 1895);
    assert_or_panic(v[110] == 1896);
    assert_or_panic(v[111] == 1897);
    assert_or_panic(v[112] == 1898);
    assert_or_panic(v[113] == 1899);
    assert_or_panic(v[114] == 1900);
    assert_or_panic(v[115] == 1901);
    assert_or_panic(v[116] == 1902);
    assert_or_panic(v[117] == 1903);
    assert_or_panic(v[118] == 1904);
    assert_or_panic(v[119] == 1905);
    assert_or_panic(v[120] == 1906);
    assert_or_panic(v[121] == 1907);
    assert_or_panic(v[122] == 1908);
    assert_or_panic(v[123] == 1909);
    assert_or_panic(v[124] == 1910);
    assert_or_panic(v[125] == 1911);
    assert_or_panic(v[126] == 1912);
    assert_or_panic(v[127] == 1913);
    assert_or_panic(v[128] == 1914);
    assert_or_panic(v[129] == 1915);
    assert_or_panic(v[130] == 1916);
    assert_or_panic(v[131] == 1917);
    assert_or_panic(v[132] == 1918);
    assert_or_panic(v[133] == 1919);
    assert_or_panic(v[134] == 1920);
    assert_or_panic(v[135] == 1921);
    assert_or_panic(v[136] == 1922);
    assert_or_panic(v[137] == 1923);
    assert_or_panic(v[138] == 1924);
    assert_or_panic(v[139] == 1925);
    assert_or_panic(v[140] == 1926);
    assert_or_panic(v[141] == 1927);
    assert_or_panic(v[142] == 1928);
    assert_or_panic(v[143] == 1929);
    assert_or_panic(v[144] == 1930);
    assert_or_panic(v[145] == 1931);
    assert_or_panic(v[146] == 1932);
    assert_or_panic(v[147] == 1933);
    assert_or_panic(v[148] == 1934);
    assert_or_panic(v[149] == 1935);
    assert_or_panic(v[150] == 1936);
    assert_or_panic(v[151] == 1937);
    assert_or_panic(v[152] == 1938);
    assert_or_panic(v[153] == 1939);
    assert_or_panic(v[154] == 1940);
    assert_or_panic(v[155] == 1941);
    assert_or_panic(v[156] == 1942);
    assert_or_panic(v[157] == 1943);
    assert_or_panic(v[158] == 1944);
    assert_or_panic(v[159] == 1945);
    assert_or_panic(v[160] == 1946);
    assert_or_panic(v[161] == 1947);
    assert_or_panic(v[162] == 1948);
    assert_or_panic(v[163] == 1949);
    assert_or_panic(v[164] == 1950);
    assert_or_panic(v[165] == 1951);
    assert_or_panic(v[166] == 1952);
    assert_or_panic(v[167] == 1953);
    assert_or_panic(v[168] == 1954);
    assert_or_panic(v[169] == 1955);
    assert_or_panic(v[170] == 1956);
    assert_or_panic(v[171] == 1957);
    assert_or_panic(v[172] == 1958);
    assert_or_panic(v[173] == 1959);
    assert_or_panic(v[174] == 1960);
    assert_or_panic(v[175] == 1961);
    assert_or_panic(v[176] == 1962);
    assert_or_panic(v[177] == 1963);
    assert_or_panic(v[178] == 1964);
    assert_or_panic(v[179] == 1965);
    assert_or_panic(v[180] == 1966);
    assert_or_panic(v[181] == 1967);
    assert_or_panic(v[182] == 1968);
    assert_or_panic(v[183] == 1969);
    assert_or_panic(v[184] == 1970);
    assert_or_panic(v[185] == 1971);
    assert_or_panic(v[186] == 1972);
    assert_or_panic(v[187] == 1973);
    assert_or_panic(v[188] == 1974);
    assert_or_panic(v[189] == 1975);
    assert_or_panic(v[190] == 1976);
    assert_or_panic(v[191] == 1977);
    zig_vector_192_u16((Vector_192_u16){
        1978, 1979, 1980, 1981, 1982, 1983, 1984, 1985, 1986, 1987, 1988, 1989, 1990, 1991, 1992, 1993,
        1994, 1995, 1996, 1997, 1998, 1999, 2000, 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2009,
        2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024, 2025,
        2026, 2027, 2028, 2029, 2030, 2031, 2032, 2033, 2034, 2035, 2036, 2037, 2038, 2039, 2040, 2041,
        2042, 2043, 2044, 2045, 2046, 2047, 2048, 2049, 2050, 2051, 2052, 2053, 2054, 2055, 2056, 2057,
        2058, 2059, 2060, 2061, 2062, 2063, 2064, 2065, 2066, 2067, 2068, 2069, 2070, 2071, 2072, 2073,
        2074, 2075, 2076, 2077, 2078, 2079, 2080, 2081, 2082, 2083, 2084, 2085, 2086, 2087, 2088, 2089,
        2090, 2091, 2092, 2093, 2094, 2095, 2096, 2097, 2098, 2099, 2100, 2101, 2102, 2103, 2104, 2105,
        2106, 2107, 2108, 2109, 2110, 2111, 2112, 2113, 2114, 2115, 2116, 2117, 2118, 2119, 2120, 2121,
        2122, 2123, 2124, 2125, 2126, 2127, 2128, 2129, 2130, 2131, 2132, 2133, 2134, 2135, 2136, 2137,
        2138, 2139, 2140, 2141, 2142, 2143, 2144, 2145, 2146, 2147, 2148, 2149, 2150, 2151, 2152, 2153,
        2154, 2155, 2156, 2157, 2158, 2159, 2160, 2161, 2162, 2163, 2164, 2165, 2166, 2167, 2168, 2169,
    }, 192);
}

typedef uint16_t Vector_256_u16 __attribute__((vector_size(256 * sizeof(uint16_t))));

Vector_256_u16 zig_ret_vector_256_u16(void);
void zig_vector_256_u16(Vector_256_u16, size_t);

Vector_256_u16 c_ret_vector_256_u16(void) {
    return (Vector_256_u16){
        3066, 3067, 3068, 3069, 3070, 3071, 3072, 3073, 3074, 3075, 3076, 3077, 3078, 3079, 3080, 3081,
        3082, 3083, 3084, 3085, 3086, 3087, 3088, 3089, 3090, 3091, 3092, 3093, 3094, 3095, 3096, 3097,
        3098, 3099, 3100, 3101, 3102, 3103, 3104, 3105, 3106, 3107, 3108, 3109, 3110, 3111, 3112, 3113,
        3114, 3115, 3116, 3117, 3118, 3119, 3120, 3121, 3122, 3123, 3124, 3125, 3126, 3127, 3128, 3129,
        3130, 3131, 3132, 3133, 3134, 3135, 3136, 3137, 3138, 3139, 3140, 3141, 3142, 3143, 3144, 3145,
        3146, 3147, 3148, 3149, 3150, 3151, 3152, 3153, 3154, 3155, 3156, 3157, 3158, 3159, 3160, 3161,
        3162, 3163, 3164, 3165, 3166, 3167, 3168, 3169, 3170, 3171, 3172, 3173, 3174, 3175, 3176, 3177,
        3178, 3179, 3180, 3181, 3182, 3183, 3184, 3185, 3186, 3187, 3188, 3189, 3190, 3191, 3192, 3193,
        3194, 3195, 3196, 3197, 3198, 3199, 3200, 3201, 3202, 3203, 3204, 3205, 3206, 3207, 3208, 3209,
        3210, 3211, 3212, 3213, 3214, 3215, 3216, 3217, 3218, 3219, 3220, 3221, 3222, 3223, 3224, 3225,
        3226, 3227, 3228, 3229, 3230, 3231, 3232, 3233, 3234, 3235, 3236, 3237, 3238, 3239, 3240, 3241,
        3242, 3243, 3244, 3245, 3246, 3247, 3248, 3249, 3250, 3251, 3252, 3253, 3254, 3255, 3256, 3257,
        3258, 3259, 3260, 3261, 3262, 3263, 3264, 3265, 3266, 3267, 3268, 3269, 3270, 3271, 3272, 3273,
        3274, 3275, 3276, 3277, 3278, 3279, 3280, 3281, 3282, 3283, 3284, 3285, 3286, 3287, 3288, 3289,
        3290, 3291, 3292, 3293, 3294, 3295, 3296, 3297, 3298, 3299, 3300, 3301, 3302, 3303, 3304, 3305,
        3306, 3307, 3308, 3309, 3310, 3311, 3312, 3313, 3314, 3315, 3316, 3317, 3318, 3319, 3320, 3321,
    };
}
void c_vector_256_u16(Vector_256_u16 v, size_t i) {
    assert_or_panic(v[0] == 3322);
    assert_or_panic(v[1] == 3323);
    assert_or_panic(v[2] == 3324);
    assert_or_panic(v[3] == 3325);
    assert_or_panic(v[4] == 3326);
    assert_or_panic(v[5] == 3327);
    assert_or_panic(v[6] == 3328);
    assert_or_panic(v[7] == 3329);
    assert_or_panic(v[8] == 3330);
    assert_or_panic(v[9] == 3331);
    assert_or_panic(v[10] == 3332);
    assert_or_panic(v[11] == 3333);
    assert_or_panic(v[12] == 3334);
    assert_or_panic(v[13] == 3335);
    assert_or_panic(v[14] == 3336);
    assert_or_panic(v[15] == 3337);
    assert_or_panic(v[16] == 3338);
    assert_or_panic(v[17] == 3339);
    assert_or_panic(v[18] == 3340);
    assert_or_panic(v[19] == 3341);
    assert_or_panic(v[20] == 3342);
    assert_or_panic(v[21] == 3343);
    assert_or_panic(v[22] == 3344);
    assert_or_panic(v[23] == 3345);
    assert_or_panic(v[24] == 3346);
    assert_or_panic(v[25] == 3347);
    assert_or_panic(v[26] == 3348);
    assert_or_panic(v[27] == 3349);
    assert_or_panic(v[28] == 3350);
    assert_or_panic(v[29] == 3351);
    assert_or_panic(v[30] == 3352);
    assert_or_panic(v[31] == 3353);
    assert_or_panic(v[32] == 3354);
    assert_or_panic(v[33] == 3355);
    assert_or_panic(v[34] == 3356);
    assert_or_panic(v[35] == 3357);
    assert_or_panic(v[36] == 3358);
    assert_or_panic(v[37] == 3359);
    assert_or_panic(v[38] == 3360);
    assert_or_panic(v[39] == 3361);
    assert_or_panic(v[40] == 3362);
    assert_or_panic(v[41] == 3363);
    assert_or_panic(v[42] == 3364);
    assert_or_panic(v[43] == 3365);
    assert_or_panic(v[44] == 3366);
    assert_or_panic(v[45] == 3367);
    assert_or_panic(v[46] == 3368);
    assert_or_panic(v[47] == 3369);
    assert_or_panic(v[48] == 3370);
    assert_or_panic(v[49] == 3371);
    assert_or_panic(v[50] == 3372);
    assert_or_panic(v[51] == 3373);
    assert_or_panic(v[52] == 3374);
    assert_or_panic(v[53] == 3375);
    assert_or_panic(v[54] == 3376);
    assert_or_panic(v[55] == 3377);
    assert_or_panic(v[56] == 3378);
    assert_or_panic(v[57] == 3379);
    assert_or_panic(v[58] == 3380);
    assert_or_panic(v[59] == 3381);
    assert_or_panic(v[60] == 3382);
    assert_or_panic(v[61] == 3383);
    assert_or_panic(v[62] == 3384);
    assert_or_panic(v[63] == 3385);
    assert_or_panic(v[64] == 3386);
    assert_or_panic(v[65] == 3387);
    assert_or_panic(v[66] == 3388);
    assert_or_panic(v[67] == 3389);
    assert_or_panic(v[68] == 3390);
    assert_or_panic(v[69] == 3391);
    assert_or_panic(v[70] == 3392);
    assert_or_panic(v[71] == 3393);
    assert_or_panic(v[72] == 3394);
    assert_or_panic(v[73] == 3395);
    assert_or_panic(v[74] == 3396);
    assert_or_panic(v[75] == 3397);
    assert_or_panic(v[76] == 3398);
    assert_or_panic(v[77] == 3399);
    assert_or_panic(v[78] == 3400);
    assert_or_panic(v[79] == 3401);
    assert_or_panic(v[80] == 3402);
    assert_or_panic(v[81] == 3403);
    assert_or_panic(v[82] == 3404);
    assert_or_panic(v[83] == 3405);
    assert_or_panic(v[84] == 3406);
    assert_or_panic(v[85] == 3407);
    assert_or_panic(v[86] == 3408);
    assert_or_panic(v[87] == 3409);
    assert_or_panic(v[88] == 3410);
    assert_or_panic(v[89] == 3411);
    assert_or_panic(v[90] == 3412);
    assert_or_panic(v[91] == 3413);
    assert_or_panic(v[92] == 3414);
    assert_or_panic(v[93] == 3415);
    assert_or_panic(v[94] == 3416);
    assert_or_panic(v[95] == 3417);
    assert_or_panic(v[96] == 3418);
    assert_or_panic(v[97] == 3419);
    assert_or_panic(v[98] == 3420);
    assert_or_panic(v[99] == 3421);
    assert_or_panic(v[100] == 3422);
    assert_or_panic(v[101] == 3423);
    assert_or_panic(v[102] == 3424);
    assert_or_panic(v[103] == 3425);
    assert_or_panic(v[104] == 3426);
    assert_or_panic(v[105] == 3427);
    assert_or_panic(v[106] == 3428);
    assert_or_panic(v[107] == 3429);
    assert_or_panic(v[108] == 3430);
    assert_or_panic(v[109] == 3431);
    assert_or_panic(v[110] == 3432);
    assert_or_panic(v[111] == 3433);
    assert_or_panic(v[112] == 3434);
    assert_or_panic(v[113] == 3435);
    assert_or_panic(v[114] == 3436);
    assert_or_panic(v[115] == 3437);
    assert_or_panic(v[116] == 3438);
    assert_or_panic(v[117] == 3439);
    assert_or_panic(v[118] == 3440);
    assert_or_panic(v[119] == 3441);
    assert_or_panic(v[120] == 3442);
    assert_or_panic(v[121] == 3443);
    assert_or_panic(v[122] == 3444);
    assert_or_panic(v[123] == 3445);
    assert_or_panic(v[124] == 3446);
    assert_or_panic(v[125] == 3447);
    assert_or_panic(v[126] == 3448);
    assert_or_panic(v[127] == 3449);
    assert_or_panic(v[128] == 3450);
    assert_or_panic(v[129] == 3451);
    assert_or_panic(v[130] == 3452);
    assert_or_panic(v[131] == 3453);
    assert_or_panic(v[132] == 3454);
    assert_or_panic(v[133] == 3455);
    assert_or_panic(v[134] == 3456);
    assert_or_panic(v[135] == 3457);
    assert_or_panic(v[136] == 3458);
    assert_or_panic(v[137] == 3459);
    assert_or_panic(v[138] == 3460);
    assert_or_panic(v[139] == 3461);
    assert_or_panic(v[140] == 3462);
    assert_or_panic(v[141] == 3463);
    assert_or_panic(v[142] == 3464);
    assert_or_panic(v[143] == 3465);
    assert_or_panic(v[144] == 3466);
    assert_or_panic(v[145] == 3467);
    assert_or_panic(v[146] == 3468);
    assert_or_panic(v[147] == 3469);
    assert_or_panic(v[148] == 3470);
    assert_or_panic(v[149] == 3471);
    assert_or_panic(v[150] == 3472);
    assert_or_panic(v[151] == 3473);
    assert_or_panic(v[152] == 3474);
    assert_or_panic(v[153] == 3475);
    assert_or_panic(v[154] == 3476);
    assert_or_panic(v[155] == 3477);
    assert_or_panic(v[156] == 3478);
    assert_or_panic(v[157] == 3479);
    assert_or_panic(v[158] == 3480);
    assert_or_panic(v[159] == 3481);
    assert_or_panic(v[160] == 3482);
    assert_or_panic(v[161] == 3483);
    assert_or_panic(v[162] == 3484);
    assert_or_panic(v[163] == 3485);
    assert_or_panic(v[164] == 3486);
    assert_or_panic(v[165] == 3487);
    assert_or_panic(v[166] == 3488);
    assert_or_panic(v[167] == 3489);
    assert_or_panic(v[168] == 3490);
    assert_or_panic(v[169] == 3491);
    assert_or_panic(v[170] == 3492);
    assert_or_panic(v[171] == 3493);
    assert_or_panic(v[172] == 3494);
    assert_or_panic(v[173] == 3495);
    assert_or_panic(v[174] == 3496);
    assert_or_panic(v[175] == 3497);
    assert_or_panic(v[176] == 3498);
    assert_or_panic(v[177] == 3499);
    assert_or_panic(v[178] == 3500);
    assert_or_panic(v[179] == 3501);
    assert_or_panic(v[180] == 3502);
    assert_or_panic(v[181] == 3503);
    assert_or_panic(v[182] == 3504);
    assert_or_panic(v[183] == 3505);
    assert_or_panic(v[184] == 3506);
    assert_or_panic(v[185] == 3507);
    assert_or_panic(v[186] == 3508);
    assert_or_panic(v[187] == 3509);
    assert_or_panic(v[188] == 3510);
    assert_or_panic(v[189] == 3511);
    assert_or_panic(v[190] == 3512);
    assert_or_panic(v[191] == 3513);
    assert_or_panic(v[192] == 3514);
    assert_or_panic(v[193] == 3515);
    assert_or_panic(v[194] == 3516);
    assert_or_panic(v[195] == 3517);
    assert_or_panic(v[196] == 3518);
    assert_or_panic(v[197] == 3519);
    assert_or_panic(v[198] == 3520);
    assert_or_panic(v[199] == 3521);
    assert_or_panic(v[200] == 3522);
    assert_or_panic(v[201] == 3523);
    assert_or_panic(v[202] == 3524);
    assert_or_panic(v[203] == 3525);
    assert_or_panic(v[204] == 3526);
    assert_or_panic(v[205] == 3527);
    assert_or_panic(v[206] == 3528);
    assert_or_panic(v[207] == 3529);
    assert_or_panic(v[208] == 3530);
    assert_or_panic(v[209] == 3531);
    assert_or_panic(v[210] == 3532);
    assert_or_panic(v[211] == 3533);
    assert_or_panic(v[212] == 3534);
    assert_or_panic(v[213] == 3535);
    assert_or_panic(v[214] == 3536);
    assert_or_panic(v[215] == 3537);
    assert_or_panic(v[216] == 3538);
    assert_or_panic(v[217] == 3539);
    assert_or_panic(v[218] == 3540);
    assert_or_panic(v[219] == 3541);
    assert_or_panic(v[220] == 3542);
    assert_or_panic(v[221] == 3543);
    assert_or_panic(v[222] == 3544);
    assert_or_panic(v[223] == 3545);
    assert_or_panic(v[224] == 3546);
    assert_or_panic(v[225] == 3547);
    assert_or_panic(v[226] == 3548);
    assert_or_panic(v[227] == 3549);
    assert_or_panic(v[228] == 3550);
    assert_or_panic(v[229] == 3551);
    assert_or_panic(v[230] == 3552);
    assert_or_panic(v[231] == 3553);
    assert_or_panic(v[232] == 3554);
    assert_or_panic(v[233] == 3555);
    assert_or_panic(v[234] == 3556);
    assert_or_panic(v[235] == 3557);
    assert_or_panic(v[236] == 3558);
    assert_or_panic(v[237] == 3559);
    assert_or_panic(v[238] == 3560);
    assert_or_panic(v[239] == 3561);
    assert_or_panic(v[240] == 3562);
    assert_or_panic(v[241] == 3563);
    assert_or_panic(v[242] == 3564);
    assert_or_panic(v[243] == 3565);
    assert_or_panic(v[244] == 3566);
    assert_or_panic(v[245] == 3567);
    assert_or_panic(v[246] == 3568);
    assert_or_panic(v[247] == 3569);
    assert_or_panic(v[248] == 3570);
    assert_or_panic(v[249] == 3571);
    assert_or_panic(v[250] == 3572);
    assert_or_panic(v[251] == 3573);
    assert_or_panic(v[252] == 3574);
    assert_or_panic(v[253] == 3575);
    assert_or_panic(v[254] == 3576);
    assert_or_panic(v[255] == 3577);
    assert_or_panic(i == 256);
}
void c_test_vector_256_u16(void) {
    Vector_256_u16 v = zig_ret_vector_256_u16();
    assert_or_panic(v[0] == 2554);
    assert_or_panic(v[1] == 2555);
    assert_or_panic(v[2] == 2556);
    assert_or_panic(v[3] == 2557);
    assert_or_panic(v[4] == 2558);
    assert_or_panic(v[5] == 2559);
    assert_or_panic(v[6] == 2560);
    assert_or_panic(v[7] == 2561);
    assert_or_panic(v[8] == 2562);
    assert_or_panic(v[9] == 2563);
    assert_or_panic(v[10] == 2564);
    assert_or_panic(v[11] == 2565);
    assert_or_panic(v[12] == 2566);
    assert_or_panic(v[13] == 2567);
    assert_or_panic(v[14] == 2568);
    assert_or_panic(v[15] == 2569);
    assert_or_panic(v[16] == 2570);
    assert_or_panic(v[17] == 2571);
    assert_or_panic(v[18] == 2572);
    assert_or_panic(v[19] == 2573);
    assert_or_panic(v[20] == 2574);
    assert_or_panic(v[21] == 2575);
    assert_or_panic(v[22] == 2576);
    assert_or_panic(v[23] == 2577);
    assert_or_panic(v[24] == 2578);
    assert_or_panic(v[25] == 2579);
    assert_or_panic(v[26] == 2580);
    assert_or_panic(v[27] == 2581);
    assert_or_panic(v[28] == 2582);
    assert_or_panic(v[29] == 2583);
    assert_or_panic(v[30] == 2584);
    assert_or_panic(v[31] == 2585);
    assert_or_panic(v[32] == 2586);
    assert_or_panic(v[33] == 2587);
    assert_or_panic(v[34] == 2588);
    assert_or_panic(v[35] == 2589);
    assert_or_panic(v[36] == 2590);
    assert_or_panic(v[37] == 2591);
    assert_or_panic(v[38] == 2592);
    assert_or_panic(v[39] == 2593);
    assert_or_panic(v[40] == 2594);
    assert_or_panic(v[41] == 2595);
    assert_or_panic(v[42] == 2596);
    assert_or_panic(v[43] == 2597);
    assert_or_panic(v[44] == 2598);
    assert_or_panic(v[45] == 2599);
    assert_or_panic(v[46] == 2600);
    assert_or_panic(v[47] == 2601);
    assert_or_panic(v[48] == 2602);
    assert_or_panic(v[49] == 2603);
    assert_or_panic(v[50] == 2604);
    assert_or_panic(v[51] == 2605);
    assert_or_panic(v[52] == 2606);
    assert_or_panic(v[53] == 2607);
    assert_or_panic(v[54] == 2608);
    assert_or_panic(v[55] == 2609);
    assert_or_panic(v[56] == 2610);
    assert_or_panic(v[57] == 2611);
    assert_or_panic(v[58] == 2612);
    assert_or_panic(v[59] == 2613);
    assert_or_panic(v[60] == 2614);
    assert_or_panic(v[61] == 2615);
    assert_or_panic(v[62] == 2616);
    assert_or_panic(v[63] == 2617);
    assert_or_panic(v[64] == 2618);
    assert_or_panic(v[65] == 2619);
    assert_or_panic(v[66] == 2620);
    assert_or_panic(v[67] == 2621);
    assert_or_panic(v[68] == 2622);
    assert_or_panic(v[69] == 2623);
    assert_or_panic(v[70] == 2624);
    assert_or_panic(v[71] == 2625);
    assert_or_panic(v[72] == 2626);
    assert_or_panic(v[73] == 2627);
    assert_or_panic(v[74] == 2628);
    assert_or_panic(v[75] == 2629);
    assert_or_panic(v[76] == 2630);
    assert_or_panic(v[77] == 2631);
    assert_or_panic(v[78] == 2632);
    assert_or_panic(v[79] == 2633);
    assert_or_panic(v[80] == 2634);
    assert_or_panic(v[81] == 2635);
    assert_or_panic(v[82] == 2636);
    assert_or_panic(v[83] == 2637);
    assert_or_panic(v[84] == 2638);
    assert_or_panic(v[85] == 2639);
    assert_or_panic(v[86] == 2640);
    assert_or_panic(v[87] == 2641);
    assert_or_panic(v[88] == 2642);
    assert_or_panic(v[89] == 2643);
    assert_or_panic(v[90] == 2644);
    assert_or_panic(v[91] == 2645);
    assert_or_panic(v[92] == 2646);
    assert_or_panic(v[93] == 2647);
    assert_or_panic(v[94] == 2648);
    assert_or_panic(v[95] == 2649);
    assert_or_panic(v[96] == 2650);
    assert_or_panic(v[97] == 2651);
    assert_or_panic(v[98] == 2652);
    assert_or_panic(v[99] == 2653);
    assert_or_panic(v[100] == 2654);
    assert_or_panic(v[101] == 2655);
    assert_or_panic(v[102] == 2656);
    assert_or_panic(v[103] == 2657);
    assert_or_panic(v[104] == 2658);
    assert_or_panic(v[105] == 2659);
    assert_or_panic(v[106] == 2660);
    assert_or_panic(v[107] == 2661);
    assert_or_panic(v[108] == 2662);
    assert_or_panic(v[109] == 2663);
    assert_or_panic(v[110] == 2664);
    assert_or_panic(v[111] == 2665);
    assert_or_panic(v[112] == 2666);
    assert_or_panic(v[113] == 2667);
    assert_or_panic(v[114] == 2668);
    assert_or_panic(v[115] == 2669);
    assert_or_panic(v[116] == 2670);
    assert_or_panic(v[117] == 2671);
    assert_or_panic(v[118] == 2672);
    assert_or_panic(v[119] == 2673);
    assert_or_panic(v[120] == 2674);
    assert_or_panic(v[121] == 2675);
    assert_or_panic(v[122] == 2676);
    assert_or_panic(v[123] == 2677);
    assert_or_panic(v[124] == 2678);
    assert_or_panic(v[125] == 2679);
    assert_or_panic(v[126] == 2680);
    assert_or_panic(v[127] == 2681);
    assert_or_panic(v[128] == 2682);
    assert_or_panic(v[129] == 2683);
    assert_or_panic(v[130] == 2684);
    assert_or_panic(v[131] == 2685);
    assert_or_panic(v[132] == 2686);
    assert_or_panic(v[133] == 2687);
    assert_or_panic(v[134] == 2688);
    assert_or_panic(v[135] == 2689);
    assert_or_panic(v[136] == 2690);
    assert_or_panic(v[137] == 2691);
    assert_or_panic(v[138] == 2692);
    assert_or_panic(v[139] == 2693);
    assert_or_panic(v[140] == 2694);
    assert_or_panic(v[141] == 2695);
    assert_or_panic(v[142] == 2696);
    assert_or_panic(v[143] == 2697);
    assert_or_panic(v[144] == 2698);
    assert_or_panic(v[145] == 2699);
    assert_or_panic(v[146] == 2700);
    assert_or_panic(v[147] == 2701);
    assert_or_panic(v[148] == 2702);
    assert_or_panic(v[149] == 2703);
    assert_or_panic(v[150] == 2704);
    assert_or_panic(v[151] == 2705);
    assert_or_panic(v[152] == 2706);
    assert_or_panic(v[153] == 2707);
    assert_or_panic(v[154] == 2708);
    assert_or_panic(v[155] == 2709);
    assert_or_panic(v[156] == 2710);
    assert_or_panic(v[157] == 2711);
    assert_or_panic(v[158] == 2712);
    assert_or_panic(v[159] == 2713);
    assert_or_panic(v[160] == 2714);
    assert_or_panic(v[161] == 2715);
    assert_or_panic(v[162] == 2716);
    assert_or_panic(v[163] == 2717);
    assert_or_panic(v[164] == 2718);
    assert_or_panic(v[165] == 2719);
    assert_or_panic(v[166] == 2720);
    assert_or_panic(v[167] == 2721);
    assert_or_panic(v[168] == 2722);
    assert_or_panic(v[169] == 2723);
    assert_or_panic(v[170] == 2724);
    assert_or_panic(v[171] == 2725);
    assert_or_panic(v[172] == 2726);
    assert_or_panic(v[173] == 2727);
    assert_or_panic(v[174] == 2728);
    assert_or_panic(v[175] == 2729);
    assert_or_panic(v[176] == 2730);
    assert_or_panic(v[177] == 2731);
    assert_or_panic(v[178] == 2732);
    assert_or_panic(v[179] == 2733);
    assert_or_panic(v[180] == 2734);
    assert_or_panic(v[181] == 2735);
    assert_or_panic(v[182] == 2736);
    assert_or_panic(v[183] == 2737);
    assert_or_panic(v[184] == 2738);
    assert_or_panic(v[185] == 2739);
    assert_or_panic(v[186] == 2740);
    assert_or_panic(v[187] == 2741);
    assert_or_panic(v[188] == 2742);
    assert_or_panic(v[189] == 2743);
    assert_or_panic(v[190] == 2744);
    assert_or_panic(v[191] == 2745);
    assert_or_panic(v[192] == 2746);
    assert_or_panic(v[193] == 2747);
    assert_or_panic(v[194] == 2748);
    assert_or_panic(v[195] == 2749);
    assert_or_panic(v[196] == 2750);
    assert_or_panic(v[197] == 2751);
    assert_or_panic(v[198] == 2752);
    assert_or_panic(v[199] == 2753);
    assert_or_panic(v[200] == 2754);
    assert_or_panic(v[201] == 2755);
    assert_or_panic(v[202] == 2756);
    assert_or_panic(v[203] == 2757);
    assert_or_panic(v[204] == 2758);
    assert_or_panic(v[205] == 2759);
    assert_or_panic(v[206] == 2760);
    assert_or_panic(v[207] == 2761);
    assert_or_panic(v[208] == 2762);
    assert_or_panic(v[209] == 2763);
    assert_or_panic(v[210] == 2764);
    assert_or_panic(v[211] == 2765);
    assert_or_panic(v[212] == 2766);
    assert_or_panic(v[213] == 2767);
    assert_or_panic(v[214] == 2768);
    assert_or_panic(v[215] == 2769);
    assert_or_panic(v[216] == 2770);
    assert_or_panic(v[217] == 2771);
    assert_or_panic(v[218] == 2772);
    assert_or_panic(v[219] == 2773);
    assert_or_panic(v[220] == 2774);
    assert_or_panic(v[221] == 2775);
    assert_or_panic(v[222] == 2776);
    assert_or_panic(v[223] == 2777);
    assert_or_panic(v[224] == 2778);
    assert_or_panic(v[225] == 2779);
    assert_or_panic(v[226] == 2780);
    assert_or_panic(v[227] == 2781);
    assert_or_panic(v[228] == 2782);
    assert_or_panic(v[229] == 2783);
    assert_or_panic(v[230] == 2784);
    assert_or_panic(v[231] == 2785);
    assert_or_panic(v[232] == 2786);
    assert_or_panic(v[233] == 2787);
    assert_or_panic(v[234] == 2788);
    assert_or_panic(v[235] == 2789);
    assert_or_panic(v[236] == 2790);
    assert_or_panic(v[237] == 2791);
    assert_or_panic(v[238] == 2792);
    assert_or_panic(v[239] == 2793);
    assert_or_panic(v[240] == 2794);
    assert_or_panic(v[241] == 2795);
    assert_or_panic(v[242] == 2796);
    assert_or_panic(v[243] == 2797);
    assert_or_panic(v[244] == 2798);
    assert_or_panic(v[245] == 2799);
    assert_or_panic(v[246] == 2800);
    assert_or_panic(v[247] == 2801);
    assert_or_panic(v[248] == 2802);
    assert_or_panic(v[249] == 2803);
    assert_or_panic(v[250] == 2804);
    assert_or_panic(v[251] == 2805);
    assert_or_panic(v[252] == 2806);
    assert_or_panic(v[253] == 2807);
    assert_or_panic(v[254] == 2808);
    assert_or_panic(v[255] == 2809);
    zig_vector_256_u16((Vector_256_u16){
        2810, 2811, 2812, 2813, 2814, 2815, 2816, 2817, 2818, 2819, 2820, 2821, 2822, 2823, 2824, 2825,
        2826, 2827, 2828, 2829, 2830, 2831, 2832, 2833, 2834, 2835, 2836, 2837, 2838, 2839, 2840, 2841,
        2842, 2843, 2844, 2845, 2846, 2847, 2848, 2849, 2850, 2851, 2852, 2853, 2854, 2855, 2856, 2857,
        2858, 2859, 2860, 2861, 2862, 2863, 2864, 2865, 2866, 2867, 2868, 2869, 2870, 2871, 2872, 2873,
        2874, 2875, 2876, 2877, 2878, 2879, 2880, 2881, 2882, 2883, 2884, 2885, 2886, 2887, 2888, 2889,
        2890, 2891, 2892, 2893, 2894, 2895, 2896, 2897, 2898, 2899, 2900, 2901, 2902, 2903, 2904, 2905,
        2906, 2907, 2908, 2909, 2910, 2911, 2912, 2913, 2914, 2915, 2916, 2917, 2918, 2919, 2920, 2921,
        2922, 2923, 2924, 2925, 2926, 2927, 2928, 2929, 2930, 2931, 2932, 2933, 2934, 2935, 2936, 2937,
        2938, 2939, 2940, 2941, 2942, 2943, 2944, 2945, 2946, 2947, 2948, 2949, 2950, 2951, 2952, 2953,
        2954, 2955, 2956, 2957, 2958, 2959, 2960, 2961, 2962, 2963, 2964, 2965, 2966, 2967, 2968, 2969,
        2970, 2971, 2972, 2973, 2974, 2975, 2976, 2977, 2978, 2979, 2980, 2981, 2982, 2983, 2984, 2985,
        2986, 2987, 2988, 2989, 2990, 2991, 2992, 2993, 2994, 2995, 2996, 2997, 2998, 2999, 3000, 3001,
        3002, 3003, 3004, 3005, 3006, 3007, 3008, 3009, 3010, 3011, 3012, 3013, 3014, 3015, 3016, 3017,
        3018, 3019, 3020, 3021, 3022, 3023, 3024, 3025, 3026, 3027, 3028, 3029, 3030, 3031, 3032, 3033,
        3034, 3035, 3036, 3037, 3038, 3039, 3040, 3041, 3042, 3043, 3044, 3045, 3046, 3047, 3048, 3049,
        3050, 3051, 3052, 3053, 3054, 3055, 3056, 3057, 3058, 3059, 3060, 3061, 3062, 3063, 3064, 3065,
    }, 256);
}

typedef uint32_t Vector_1_u32 __attribute__((vector_size(1 * sizeof(uint32_t))));

Vector_1_u32 zig_ret_vector_1_u32(void);
void zig_vector_1_u32(Vector_1_u32, size_t);

Vector_1_u32 c_ret_vector_1_u32(void) {
    return (Vector_1_u32){ 3 };
}
void c_vector_1_u32(Vector_1_u32 v, size_t i) {
    assert_or_panic(v[0] == 4);
    assert_or_panic(i == 1);
}
void c_test_vector_1_u32(void) {
    Vector_1_u32 v = zig_ret_vector_1_u32();
    assert_or_panic(v[0] == 1);
    zig_vector_1_u32((Vector_1_u32){ 2 }, 1);
}

typedef uint32_t Vector_2_u32 __attribute__((vector_size(2 * sizeof(uint32_t))));

Vector_2_u32 zig_ret_vector_2_u32(void);
void zig_vector_2_u32(Vector_2_u32, size_t);

Vector_2_u32 c_ret_vector_2_u32(void) {
    return (Vector_2_u32){ 9, 10 };
}
void c_vector_2_u32(Vector_2_u32 v, size_t i) {
    assert_or_panic(v[0] == 11);
    assert_or_panic(v[1] == 12);
    assert_or_panic(i == 2);
}
void c_test_vector_2_u32(void) {
    Vector_2_u32 v = zig_ret_vector_2_u32();
    assert_or_panic(v[0] == 5);
    assert_or_panic(v[1] == 6);
    zig_vector_2_u32((Vector_2_u32){ 7, 8 }, 2);
}

typedef uint32_t Vector_3_u32 __attribute__((vector_size(3 * sizeof(uint32_t))));

Vector_3_u32 zig_ret_vector_3_u32(void);
void zig_vector_3_u32(Vector_3_u32, size_t);

Vector_3_u32 c_ret_vector_3_u32(void) {
    return (Vector_3_u32){ 19, 20, 21 };
}
void c_vector_3_u32(Vector_3_u32 v, size_t i) {
    assert_or_panic(v[0] == 22);
    assert_or_panic(v[1] == 23);
    assert_or_panic(v[2] == 24);
    assert_or_panic(i == 3);
}
void c_test_vector_3_u32(void) {
    Vector_3_u32 v = zig_ret_vector_3_u32();
    assert_or_panic(v[0] == 13);
    assert_or_panic(v[1] == 14);
    assert_or_panic(v[2] == 15);
    zig_vector_3_u32((Vector_3_u32){ 16, 17, 18 }, 3);
}

typedef uint32_t Vector_4_u32 __attribute__((vector_size(4 * sizeof(uint32_t))));

Vector_4_u32 zig_ret_vector_4_u32(void);

void zig_vector_4_u32(Vector_4_u32, size_t);
void zig_vector_4_u32_vector_4_u32(Vector_4_u32, Vector_4_u32, size_t);

Vector_4_u32 c_ret_vector_4_u32(void) {
    return (Vector_4_u32){ 41, 42, 43, 44 };
}
void c_vector_4_u32(Vector_4_u32 v, size_t i) {
    assert_or_panic(v[0] == 45);
    assert_or_panic(v[1] == 46);
    assert_or_panic(v[2] == 47);
    assert_or_panic(v[3] == 48);
    assert_or_panic(i == 4);
}
void c_vector_4_u32_vector_4_u32(Vector_4_u32 v0, Vector_4_u32 v1, size_t i) {
    assert_or_panic(v0[0] == 49);
    assert_or_panic(v0[1] == 50);
    assert_or_panic(v0[2] == 51);
    assert_or_panic(v0[3] == 52);
    assert_or_panic(v1[0] == 53);
    assert_or_panic(v1[1] == 54);
    assert_or_panic(v1[2] == 55);
    assert_or_panic(v1[3] == 56);
    assert_or_panic(i == 8);
}
void c_test_vector_4_u32(void) {
    Vector_4_u32 v = zig_ret_vector_4_u32();
    assert_or_panic(v[0] == 25);
    assert_or_panic(v[1] == 26);
    assert_or_panic(v[2] == 27);
    assert_or_panic(v[3] == 28);
    zig_vector_4_u32((Vector_4_u32){ 29, 30, 31, 32 }, 4);
    zig_vector_4_u32_vector_4_u32((Vector_4_u32){ 33, 34, 35, 36 }, (Vector_4_u32){ 37, 38, 39, 40 }, 8);
}

typedef uint32_t Vector_6_u32 __attribute__((vector_size(6 * sizeof(uint32_t))));

Vector_6_u32 zig_ret_vector_6_u32(void);
void zig_vector_6_u32(Vector_6_u32, size_t);

Vector_6_u32 c_ret_vector_6_u32(void) {
    return (Vector_6_u32){ 53, 54, 55, 56, 57, 58 };
}
void c_vector_6_u32(Vector_6_u32 v, size_t i) {
    assert_or_panic(v[0] == 59);
    assert_or_panic(v[1] == 60);
    assert_or_panic(v[2] == 61);
    assert_or_panic(v[3] == 62);
    assert_or_panic(v[4] == 63);
    assert_or_panic(v[5] == 64);
    assert_or_panic(i == 6);
}
void c_test_vector_6_u32(void) {
    Vector_6_u32 v = zig_ret_vector_6_u32();
    assert_or_panic(v[0] == 41);
    assert_or_panic(v[1] == 42);
    assert_or_panic(v[2] == 43);
    assert_or_panic(v[3] == 44);
    assert_or_panic(v[4] == 45);
    assert_or_panic(v[5] == 46);
    zig_vector_6_u32((Vector_6_u32){ 47, 48, 49, 50, 51, 52 }, 6);
}

typedef uint32_t Vector_8_u32 __attribute__((vector_size(8 * sizeof(uint32_t))));

Vector_8_u32 zig_ret_vector_8_u32(void);
void zig_vector_8_u32(Vector_8_u32, size_t);

Vector_8_u32 c_ret_vector_8_u32(void) {
    return (Vector_8_u32){ 81, 82, 83, 84, 85, 86, 87, 88 };
}
void c_vector_8_u32(Vector_8_u32 v, size_t i) {
    assert_or_panic(v[0] == 89);
    assert_or_panic(v[1] == 90);
    assert_or_panic(v[2] == 91);
    assert_or_panic(v[3] == 92);
    assert_or_panic(v[4] == 93);
    assert_or_panic(v[5] == 94);
    assert_or_panic(v[6] == 95);
    assert_or_panic(v[7] == 96);
    assert_or_panic(i == 8);
}
void c_test_vector_8_u32(void) {
    Vector_8_u32 v = zig_ret_vector_8_u32();
    assert_or_panic(v[0] == 65);
    assert_or_panic(v[1] == 66);
    assert_or_panic(v[2] == 67);
    assert_or_panic(v[3] == 68);
    assert_or_panic(v[4] == 69);
    assert_or_panic(v[5] == 70);
    assert_or_panic(v[6] == 71);
    assert_or_panic(v[7] == 72);
    zig_vector_8_u32((Vector_8_u32){ 73, 74, 75, 76, 77, 78, 79, 80 }, 8);
}

typedef uint32_t Vector_12_u32 __attribute__((vector_size(12 * sizeof(uint32_t))));

Vector_12_u32 zig_ret_vector_12_u32(void);
void zig_vector_12_u32(Vector_12_u32, size_t);

Vector_12_u32 c_ret_vector_12_u32(void) {
    return (Vector_12_u32){ 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132 };
}
void c_vector_12_u32(Vector_12_u32 v, size_t i) {
    assert_or_panic(v[0] == 133);
    assert_or_panic(v[1] == 134);
    assert_or_panic(v[2] == 135);
    assert_or_panic(v[3] == 136);
    assert_or_panic(v[4] == 137);
    assert_or_panic(v[5] == 138);
    assert_or_panic(v[6] == 139);
    assert_or_panic(v[7] == 140);
    assert_or_panic(v[8] == 141);
    assert_or_panic(v[9] == 142);
    assert_or_panic(v[10] == 143);
    assert_or_panic(v[11] == 144);
    assert_or_panic(i == 12);
}
void c_test_vector_12_u32(void) {
    Vector_12_u32 v = zig_ret_vector_12_u32();
    assert_or_panic(v[0] == 97);
    assert_or_panic(v[1] == 98);
    assert_or_panic(v[2] == 99);
    assert_or_panic(v[3] == 100);
    assert_or_panic(v[4] == 101);
    assert_or_panic(v[5] == 102);
    assert_or_panic(v[6] == 103);
    assert_or_panic(v[7] == 104);
    assert_or_panic(v[8] == 105);
    assert_or_panic(v[9] == 106);
    assert_or_panic(v[10] == 107);
    assert_or_panic(v[11] == 108);
    zig_vector_12_u32((Vector_12_u32){ 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120 }, 12);
}

typedef uint32_t Vector_16_u32 __attribute__((vector_size(16 * sizeof(uint32_t))));

Vector_16_u32 zig_ret_vector_16_u32(void);
void zig_vector_16_u32(Vector_16_u32, size_t);

Vector_16_u32 c_ret_vector_16_u32(void) {
    return (Vector_16_u32){ 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192 };
}
void c_vector_16_u32(Vector_16_u32 v, size_t i) {
    assert_or_panic(v[0] == 193);
    assert_or_panic(v[1] == 194);
    assert_or_panic(v[2] == 195);
    assert_or_panic(v[3] == 196);
    assert_or_panic(v[4] == 197);
    assert_or_panic(v[5] == 198);
    assert_or_panic(v[6] == 199);
    assert_or_panic(v[7] == 200);
    assert_or_panic(v[8] == 201);
    assert_or_panic(v[9] == 202);
    assert_or_panic(v[10] == 203);
    assert_or_panic(v[11] == 204);
    assert_or_panic(v[12] == 205);
    assert_or_panic(v[13] == 206);
    assert_or_panic(v[14] == 207);
    assert_or_panic(v[15] == 208);
    assert_or_panic(i == 16);
}
void c_test_vector_16_u32(void) {
    Vector_16_u32 v = zig_ret_vector_16_u32();
    assert_or_panic(v[0] == 145);
    assert_or_panic(v[1] == 146);
    assert_or_panic(v[2] == 147);
    assert_or_panic(v[3] == 148);
    assert_or_panic(v[4] == 149);
    assert_or_panic(v[5] == 150);
    assert_or_panic(v[6] == 151);
    assert_or_panic(v[7] == 152);
    assert_or_panic(v[8] == 153);
    assert_or_panic(v[9] == 154);
    assert_or_panic(v[10] == 155);
    assert_or_panic(v[11] == 156);
    assert_or_panic(v[12] == 157);
    assert_or_panic(v[13] == 158);
    assert_or_panic(v[14] == 159);
    assert_or_panic(v[15] == 160);
    zig_vector_16_u32((Vector_16_u32){ 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176 }, 16);
}

typedef uint32_t Vector_24_u32 __attribute__((vector_size(24 * sizeof(uint32_t))));

Vector_24_u32 zig_ret_vector_24_u32(void);
void zig_vector_24_u32(Vector_24_u32, size_t);

Vector_24_u32 c_ret_vector_24_u32(void) {
    return (Vector_24_u32){
        257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272,
        273, 274, 275, 276, 277, 278, 279, 280,
    };
}
void c_vector_24_u32(Vector_24_u32 v, size_t i) {
    assert_or_panic(v[0] == 281);
    assert_or_panic(v[1] == 282);
    assert_or_panic(v[2] == 283);
    assert_or_panic(v[3] == 284);
    assert_or_panic(v[4] == 285);
    assert_or_panic(v[5] == 286);
    assert_or_panic(v[6] == 287);
    assert_or_panic(v[7] == 288);
    assert_or_panic(v[8] == 289);
    assert_or_panic(v[9] == 290);
    assert_or_panic(v[10] == 291);
    assert_or_panic(v[11] == 292);
    assert_or_panic(v[12] == 293);
    assert_or_panic(v[13] == 294);
    assert_or_panic(v[14] == 295);
    assert_or_panic(v[15] == 296);
    assert_or_panic(v[16] == 297);
    assert_or_panic(v[17] == 298);
    assert_or_panic(v[18] == 299);
    assert_or_panic(v[19] == 300);
    assert_or_panic(v[20] == 301);
    assert_or_panic(v[21] == 302);
    assert_or_panic(v[22] == 303);
    assert_or_panic(v[23] == 304);
    assert_or_panic(i == 24);
}
void c_test_vector_24_u32(void) {
    Vector_24_u32 v = zig_ret_vector_24_u32();
    assert_or_panic(v[0] == 209);
    assert_or_panic(v[1] == 210);
    assert_or_panic(v[2] == 211);
    assert_or_panic(v[3] == 212);
    assert_or_panic(v[4] == 213);
    assert_or_panic(v[5] == 214);
    assert_or_panic(v[6] == 215);
    assert_or_panic(v[7] == 216);
    assert_or_panic(v[8] == 217);
    assert_or_panic(v[9] == 218);
    assert_or_panic(v[10] == 219);
    assert_or_panic(v[11] == 220);
    assert_or_panic(v[12] == 221);
    assert_or_panic(v[13] == 222);
    assert_or_panic(v[14] == 223);
    assert_or_panic(v[15] == 224);
    assert_or_panic(v[16] == 225);
    assert_or_panic(v[17] == 226);
    assert_or_panic(v[18] == 227);
    assert_or_panic(v[19] == 228);
    assert_or_panic(v[20] == 229);
    assert_or_panic(v[21] == 230);
    assert_or_panic(v[22] == 231);
    assert_or_panic(v[23] == 232);
    zig_vector_24_u32((Vector_24_u32){
        233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248,
        249, 250, 251, 252, 253, 254, 255, 256,
    }, 24);
}

typedef uint32_t Vector_32_u32 __attribute__((vector_size(32 * sizeof(uint32_t))));

Vector_32_u32 zig_ret_vector_32_u32(void);
void zig_vector_32_u32(Vector_32_u32, size_t);

Vector_32_u32 c_ret_vector_32_u32(void) {
    return (Vector_32_u32){
        369, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 382, 383, 384,
        385, 386, 387, 388, 389, 390, 391, 392, 393, 394, 395, 396, 397, 398, 399, 400,
    };
}
void c_vector_32_u32(Vector_32_u32 v, size_t i) {
    assert_or_panic(v[0] == 401);
    assert_or_panic(v[1] == 402);
    assert_or_panic(v[2] == 403);
    assert_or_panic(v[3] == 404);
    assert_or_panic(v[4] == 405);
    assert_or_panic(v[5] == 406);
    assert_or_panic(v[6] == 407);
    assert_or_panic(v[7] == 408);
    assert_or_panic(v[8] == 409);
    assert_or_panic(v[9] == 410);
    assert_or_panic(v[10] == 411);
    assert_or_panic(v[11] == 412);
    assert_or_panic(v[12] == 413);
    assert_or_panic(v[13] == 414);
    assert_or_panic(v[14] == 415);
    assert_or_panic(v[15] == 416);
    assert_or_panic(v[16] == 417);
    assert_or_panic(v[17] == 418);
    assert_or_panic(v[18] == 419);
    assert_or_panic(v[19] == 420);
    assert_or_panic(v[20] == 421);
    assert_or_panic(v[21] == 422);
    assert_or_panic(v[22] == 423);
    assert_or_panic(v[23] == 424);
    assert_or_panic(v[24] == 425);
    assert_or_panic(v[25] == 426);
    assert_or_panic(v[26] == 427);
    assert_or_panic(v[27] == 428);
    assert_or_panic(v[28] == 429);
    assert_or_panic(v[29] == 430);
    assert_or_panic(v[30] == 431);
    assert_or_panic(v[31] == 432);
    assert_or_panic(i == 32);
}
void c_test_vector_32_u32(void) {
    Vector_32_u32 v = zig_ret_vector_32_u32();
    assert_or_panic(v[0] == 305);
    assert_or_panic(v[1] == 306);
    assert_or_panic(v[2] == 307);
    assert_or_panic(v[3] == 308);
    assert_or_panic(v[4] == 309);
    assert_or_panic(v[5] == 310);
    assert_or_panic(v[6] == 311);
    assert_or_panic(v[7] == 312);
    assert_or_panic(v[8] == 313);
    assert_or_panic(v[9] == 314);
    assert_or_panic(v[10] == 315);
    assert_or_panic(v[11] == 316);
    assert_or_panic(v[12] == 317);
    assert_or_panic(v[13] == 318);
    assert_or_panic(v[14] == 319);
    assert_or_panic(v[15] == 320);
    assert_or_panic(v[16] == 321);
    assert_or_panic(v[17] == 322);
    assert_or_panic(v[18] == 323);
    assert_or_panic(v[19] == 324);
    assert_or_panic(v[20] == 325);
    assert_or_panic(v[21] == 326);
    assert_or_panic(v[22] == 327);
    assert_or_panic(v[23] == 328);
    assert_or_panic(v[24] == 329);
    assert_or_panic(v[25] == 330);
    assert_or_panic(v[26] == 331);
    assert_or_panic(v[27] == 332);
    assert_or_panic(v[28] == 333);
    assert_or_panic(v[29] == 334);
    assert_or_panic(v[30] == 335);
    assert_or_panic(v[31] == 336);
    zig_vector_32_u32((Vector_32_u32){
        337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351, 352,
        353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368,
    }, 32);
}

typedef uint32_t Vector_48_u32 __attribute__((vector_size(48 * sizeof(uint32_t))));

Vector_48_u32 zig_ret_vector_48_u32(void);
void zig_vector_48_u32(Vector_48_u32, size_t);

Vector_48_u32 c_ret_vector_48_u32(void) {
    return (Vector_48_u32){
        529, 530, 531, 532, 533, 534, 535, 536, 537, 538, 539, 540, 541, 542, 543, 544,
        545, 546, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 560,
        561, 562, 563, 564, 565, 566, 567, 568, 569, 570, 571, 572, 573, 574, 575, 576,
    };
}
void c_vector_48_u32(Vector_48_u32 v, size_t i) {
    assert_or_panic(v[0] == 577);
    assert_or_panic(v[1] == 578);
    assert_or_panic(v[2] == 579);
    assert_or_panic(v[3] == 580);
    assert_or_panic(v[4] == 581);
    assert_or_panic(v[5] == 582);
    assert_or_panic(v[6] == 583);
    assert_or_panic(v[7] == 584);
    assert_or_panic(v[8] == 585);
    assert_or_panic(v[9] == 586);
    assert_or_panic(v[10] == 587);
    assert_or_panic(v[11] == 588);
    assert_or_panic(v[12] == 589);
    assert_or_panic(v[13] == 590);
    assert_or_panic(v[14] == 591);
    assert_or_panic(v[15] == 592);
    assert_or_panic(v[16] == 593);
    assert_or_panic(v[17] == 594);
    assert_or_panic(v[18] == 595);
    assert_or_panic(v[19] == 596);
    assert_or_panic(v[20] == 597);
    assert_or_panic(v[21] == 598);
    assert_or_panic(v[22] == 599);
    assert_or_panic(v[23] == 600);
    assert_or_panic(v[24] == 601);
    assert_or_panic(v[25] == 602);
    assert_or_panic(v[26] == 603);
    assert_or_panic(v[27] == 604);
    assert_or_panic(v[28] == 605);
    assert_or_panic(v[29] == 606);
    assert_or_panic(v[30] == 607);
    assert_or_panic(v[31] == 608);
    assert_or_panic(v[32] == 609);
    assert_or_panic(v[33] == 610);
    assert_or_panic(v[34] == 611);
    assert_or_panic(v[35] == 612);
    assert_or_panic(v[36] == 613);
    assert_or_panic(v[37] == 614);
    assert_or_panic(v[38] == 615);
    assert_or_panic(v[39] == 616);
    assert_or_panic(v[40] == 617);
    assert_or_panic(v[41] == 618);
    assert_or_panic(v[42] == 619);
    assert_or_panic(v[43] == 620);
    assert_or_panic(v[44] == 621);
    assert_or_panic(v[45] == 622);
    assert_or_panic(v[46] == 623);
    assert_or_panic(v[47] == 624);
    assert_or_panic(i == 48);
}
void c_test_vector_48_u32(void) {
    Vector_48_u32 v = zig_ret_vector_48_u32();
    assert_or_panic(v[0] == 433);
    assert_or_panic(v[1] == 434);
    assert_or_panic(v[2] == 435);
    assert_or_panic(v[3] == 436);
    assert_or_panic(v[4] == 437);
    assert_or_panic(v[5] == 438);
    assert_or_panic(v[6] == 439);
    assert_or_panic(v[7] == 440);
    assert_or_panic(v[8] == 441);
    assert_or_panic(v[9] == 442);
    assert_or_panic(v[10] == 443);
    assert_or_panic(v[11] == 444);
    assert_or_panic(v[12] == 445);
    assert_or_panic(v[13] == 446);
    assert_or_panic(v[14] == 447);
    assert_or_panic(v[15] == 448);
    assert_or_panic(v[16] == 449);
    assert_or_panic(v[17] == 450);
    assert_or_panic(v[18] == 451);
    assert_or_panic(v[19] == 452);
    assert_or_panic(v[20] == 453);
    assert_or_panic(v[21] == 454);
    assert_or_panic(v[22] == 455);
    assert_or_panic(v[23] == 456);
    assert_or_panic(v[24] == 457);
    assert_or_panic(v[25] == 458);
    assert_or_panic(v[26] == 459);
    assert_or_panic(v[27] == 460);
    assert_or_panic(v[28] == 461);
    assert_or_panic(v[29] == 462);
    assert_or_panic(v[30] == 463);
    assert_or_panic(v[31] == 464);
    assert_or_panic(v[32] == 465);
    assert_or_panic(v[33] == 466);
    assert_or_panic(v[34] == 467);
    assert_or_panic(v[35] == 468);
    assert_or_panic(v[36] == 469);
    assert_or_panic(v[37] == 470);
    assert_or_panic(v[38] == 471);
    assert_or_panic(v[39] == 472);
    assert_or_panic(v[40] == 473);
    assert_or_panic(v[41] == 474);
    assert_or_panic(v[42] == 475);
    assert_or_panic(v[43] == 476);
    assert_or_panic(v[44] == 477);
    assert_or_panic(v[45] == 478);
    assert_or_panic(v[46] == 479);
    assert_or_panic(v[47] == 480);
    zig_vector_48_u32((Vector_48_u32){
        481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496,
        497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512,
        513, 514, 515, 516, 517, 518, 519, 520, 521, 522, 523, 524, 525, 526, 527, 528,
    }, 48);
}

typedef uint32_t Vector_64_u32 __attribute__((vector_size(64 * sizeof(uint32_t))));

Vector_64_u32 zig_ret_vector_64_u32(void);
void zig_vector_64_u32(Vector_64_u32, size_t);

Vector_64_u32 c_ret_vector_64_u32(void) {
    return (Vector_64_u32){
        753, 754, 755, 756, 757, 758, 759, 760, 761, 762, 763, 764, 765, 766, 767, 768,
        769, 770, 771, 772, 773, 774, 775, 776, 777, 778, 779, 780, 781, 782, 783, 784,
        785, 786, 787, 788, 789, 790, 791, 792, 793, 794, 795, 796, 797, 798, 799, 800,
        801, 802, 803, 804, 805, 806, 807, 808, 809, 810, 811, 812, 813, 814, 815, 816,
    };
}
void c_vector_64_u32(Vector_64_u32 v, size_t i) {
    assert_or_panic(v[0] == 817);
    assert_or_panic(v[1] == 818);
    assert_or_panic(v[2] == 819);
    assert_or_panic(v[3] == 820);
    assert_or_panic(v[4] == 821);
    assert_or_panic(v[5] == 822);
    assert_or_panic(v[6] == 823);
    assert_or_panic(v[7] == 824);
    assert_or_panic(v[8] == 825);
    assert_or_panic(v[9] == 826);
    assert_or_panic(v[10] == 827);
    assert_or_panic(v[11] == 828);
    assert_or_panic(v[12] == 829);
    assert_or_panic(v[13] == 830);
    assert_or_panic(v[14] == 831);
    assert_or_panic(v[15] == 832);
    assert_or_panic(v[16] == 833);
    assert_or_panic(v[17] == 834);
    assert_or_panic(v[18] == 835);
    assert_or_panic(v[19] == 836);
    assert_or_panic(v[20] == 837);
    assert_or_panic(v[21] == 838);
    assert_or_panic(v[22] == 839);
    assert_or_panic(v[23] == 840);
    assert_or_panic(v[24] == 841);
    assert_or_panic(v[25] == 842);
    assert_or_panic(v[26] == 843);
    assert_or_panic(v[27] == 844);
    assert_or_panic(v[28] == 845);
    assert_or_panic(v[29] == 846);
    assert_or_panic(v[30] == 847);
    assert_or_panic(v[31] == 848);
    assert_or_panic(v[32] == 849);
    assert_or_panic(v[33] == 850);
    assert_or_panic(v[34] == 851);
    assert_or_panic(v[35] == 852);
    assert_or_panic(v[36] == 853);
    assert_or_panic(v[37] == 854);
    assert_or_panic(v[38] == 855);
    assert_or_panic(v[39] == 856);
    assert_or_panic(v[40] == 857);
    assert_or_panic(v[41] == 858);
    assert_or_panic(v[42] == 859);
    assert_or_panic(v[43] == 860);
    assert_or_panic(v[44] == 861);
    assert_or_panic(v[45] == 862);
    assert_or_panic(v[46] == 863);
    assert_or_panic(v[47] == 864);
    assert_or_panic(v[48] == 865);
    assert_or_panic(v[49] == 866);
    assert_or_panic(v[50] == 867);
    assert_or_panic(v[51] == 868);
    assert_or_panic(v[52] == 869);
    assert_or_panic(v[53] == 870);
    assert_or_panic(v[54] == 871);
    assert_or_panic(v[55] == 872);
    assert_or_panic(v[56] == 873);
    assert_or_panic(v[57] == 874);
    assert_or_panic(v[58] == 875);
    assert_or_panic(v[59] == 876);
    assert_or_panic(v[60] == 877);
    assert_or_panic(v[61] == 878);
    assert_or_panic(v[62] == 879);
    assert_or_panic(v[63] == 880);
    assert_or_panic(i == 64);
}
void c_test_vector_64_u32(void) {
    Vector_64_u32 v = zig_ret_vector_64_u32();
    assert_or_panic(v[0] == 625);
    assert_or_panic(v[1] == 626);
    assert_or_panic(v[2] == 627);
    assert_or_panic(v[3] == 628);
    assert_or_panic(v[4] == 629);
    assert_or_panic(v[5] == 630);
    assert_or_panic(v[6] == 631);
    assert_or_panic(v[7] == 632);
    assert_or_panic(v[8] == 633);
    assert_or_panic(v[9] == 634);
    assert_or_panic(v[10] == 635);
    assert_or_panic(v[11] == 636);
    assert_or_panic(v[12] == 637);
    assert_or_panic(v[13] == 638);
    assert_or_panic(v[14] == 639);
    assert_or_panic(v[15] == 640);
    assert_or_panic(v[16] == 641);
    assert_or_panic(v[17] == 642);
    assert_or_panic(v[18] == 643);
    assert_or_panic(v[19] == 644);
    assert_or_panic(v[20] == 645);
    assert_or_panic(v[21] == 646);
    assert_or_panic(v[22] == 647);
    assert_or_panic(v[23] == 648);
    assert_or_panic(v[24] == 649);
    assert_or_panic(v[25] == 650);
    assert_or_panic(v[26] == 651);
    assert_or_panic(v[27] == 652);
    assert_or_panic(v[28] == 653);
    assert_or_panic(v[29] == 654);
    assert_or_panic(v[30] == 655);
    assert_or_panic(v[31] == 656);
    assert_or_panic(v[32] == 657);
    assert_or_panic(v[33] == 658);
    assert_or_panic(v[34] == 659);
    assert_or_panic(v[35] == 660);
    assert_or_panic(v[36] == 661);
    assert_or_panic(v[37] == 662);
    assert_or_panic(v[38] == 663);
    assert_or_panic(v[39] == 664);
    assert_or_panic(v[40] == 665);
    assert_or_panic(v[41] == 666);
    assert_or_panic(v[42] == 667);
    assert_or_panic(v[43] == 668);
    assert_or_panic(v[44] == 669);
    assert_or_panic(v[45] == 670);
    assert_or_panic(v[46] == 671);
    assert_or_panic(v[47] == 672);
    assert_or_panic(v[48] == 673);
    assert_or_panic(v[49] == 674);
    assert_or_panic(v[50] == 675);
    assert_or_panic(v[51] == 676);
    assert_or_panic(v[52] == 677);
    assert_or_panic(v[53] == 678);
    assert_or_panic(v[54] == 679);
    assert_or_panic(v[55] == 680);
    assert_or_panic(v[56] == 681);
    assert_or_panic(v[57] == 682);
    assert_or_panic(v[58] == 683);
    assert_or_panic(v[59] == 684);
    assert_or_panic(v[60] == 685);
    assert_or_panic(v[61] == 686);
    assert_or_panic(v[62] == 687);
    assert_or_panic(v[63] == 688);
    zig_vector_64_u32((Vector_64_u32){
        689, 690, 691, 692, 693, 694, 695, 696, 697, 698, 699, 700, 701, 702, 703, 704,
        705, 706, 707, 708, 709, 710, 711, 712, 713, 714, 715, 716, 717, 718, 719, 720,
        721, 722, 723, 724, 725, 726, 727, 728, 729, 730, 731, 732, 733, 734, 735, 736,
        737, 738, 739, 740, 741, 742, 743, 744, 745, 746, 747, 748, 749, 750, 751, 752,
    }, 64);
}

typedef uint32_t Vector_96_u32 __attribute__((vector_size(96 * sizeof(uint32_t))));

Vector_96_u32 zig_ret_vector_96_u32(void);
void zig_vector_96_u32(Vector_96_u32, size_t);

Vector_96_u32 c_ret_vector_96_u32(void) {
    return (Vector_96_u32){
        1082, 1083, 1084, 1085, 1086, 1087, 1088, 1089, 1090, 1091, 1092, 1093, 1094, 1095, 1096, 1097,
        1098, 1099, 1100, 1101, 1102, 1103, 1104, 1105, 1106, 1107, 1108, 1109, 1110, 1111, 1112, 1113,
        1114, 1115, 1116, 1117, 1118, 1119, 1120, 1121, 1122, 1123, 1124, 1125, 1126, 1127, 1128, 1129,
        1130, 1131, 1132, 1133, 1134, 1135, 1136, 1137, 1138, 1139, 1140, 1141, 1142, 1143, 1144, 1145,
        1146, 1147, 1148, 1149, 1150, 1151, 1152, 1153, 1154, 1155, 1156, 1157, 1158, 1159, 1160, 1161,
        1162, 1163, 1164, 1165, 1166, 1167, 1168, 1169, 1170, 1171, 1172, 1173, 1174, 1175, 1176, 1177,
    };
}
void c_vector_96_u32(Vector_96_u32 v, size_t i) {
    assert_or_panic(v[0] == 1178);
    assert_or_panic(v[1] == 1179);
    assert_or_panic(v[2] == 1180);
    assert_or_panic(v[3] == 1181);
    assert_or_panic(v[4] == 1182);
    assert_or_panic(v[5] == 1183);
    assert_or_panic(v[6] == 1184);
    assert_or_panic(v[7] == 1185);
    assert_or_panic(v[8] == 1186);
    assert_or_panic(v[9] == 1187);
    assert_or_panic(v[10] == 1188);
    assert_or_panic(v[11] == 1189);
    assert_or_panic(v[12] == 1190);
    assert_or_panic(v[13] == 1191);
    assert_or_panic(v[14] == 1192);
    assert_or_panic(v[15] == 1193);
    assert_or_panic(v[16] == 1194);
    assert_or_panic(v[17] == 1195);
    assert_or_panic(v[18] == 1196);
    assert_or_panic(v[19] == 1197);
    assert_or_panic(v[20] == 1198);
    assert_or_panic(v[21] == 1199);
    assert_or_panic(v[22] == 1200);
    assert_or_panic(v[23] == 1201);
    assert_or_panic(v[24] == 1202);
    assert_or_panic(v[25] == 1203);
    assert_or_panic(v[26] == 1204);
    assert_or_panic(v[27] == 1205);
    assert_or_panic(v[28] == 1206);
    assert_or_panic(v[29] == 1207);
    assert_or_panic(v[30] == 1208);
    assert_or_panic(v[31] == 1209);
    assert_or_panic(v[32] == 1210);
    assert_or_panic(v[33] == 1211);
    assert_or_panic(v[34] == 1212);
    assert_or_panic(v[35] == 1213);
    assert_or_panic(v[36] == 1214);
    assert_or_panic(v[37] == 1215);
    assert_or_panic(v[38] == 1216);
    assert_or_panic(v[39] == 1217);
    assert_or_panic(v[40] == 1218);
    assert_or_panic(v[41] == 1219);
    assert_or_panic(v[42] == 1220);
    assert_or_panic(v[43] == 1221);
    assert_or_panic(v[44] == 1222);
    assert_or_panic(v[45] == 1223);
    assert_or_panic(v[46] == 1224);
    assert_or_panic(v[47] == 1225);
    assert_or_panic(v[48] == 1226);
    assert_or_panic(v[49] == 1227);
    assert_or_panic(v[50] == 1228);
    assert_or_panic(v[51] == 1229);
    assert_or_panic(v[52] == 1230);
    assert_or_panic(v[53] == 1231);
    assert_or_panic(v[54] == 1232);
    assert_or_panic(v[55] == 1233);
    assert_or_panic(v[56] == 1234);
    assert_or_panic(v[57] == 1235);
    assert_or_panic(v[58] == 1236);
    assert_or_panic(v[59] == 1237);
    assert_or_panic(v[60] == 1238);
    assert_or_panic(v[61] == 1239);
    assert_or_panic(v[62] == 1240);
    assert_or_panic(v[63] == 1241);
    assert_or_panic(v[64] == 1242);
    assert_or_panic(v[65] == 1243);
    assert_or_panic(v[66] == 1244);
    assert_or_panic(v[67] == 1245);
    assert_or_panic(v[68] == 1246);
    assert_or_panic(v[69] == 1247);
    assert_or_panic(v[70] == 1248);
    assert_or_panic(v[71] == 1249);
    assert_or_panic(v[72] == 1250);
    assert_or_panic(v[73] == 1251);
    assert_or_panic(v[74] == 1252);
    assert_or_panic(v[75] == 1253);
    assert_or_panic(v[76] == 1254);
    assert_or_panic(v[77] == 1255);
    assert_or_panic(v[80] == 1258);
    assert_or_panic(v[81] == 1259);
    assert_or_panic(v[82] == 1260);
    assert_or_panic(v[83] == 1261);
    assert_or_panic(v[84] == 1262);
    assert_or_panic(v[85] == 1263);
    assert_or_panic(v[86] == 1264);
    assert_or_panic(v[87] == 1265);
    assert_or_panic(v[88] == 1266);
    assert_or_panic(v[89] == 1267);
    assert_or_panic(v[90] == 1268);
    assert_or_panic(v[91] == 1269);
    assert_or_panic(v[92] == 1270);
    assert_or_panic(v[93] == 1271);
    assert_or_panic(v[94] == 1272);
    assert_or_panic(v[95] == 1273);
    assert_or_panic(i == 96);
}
void c_test_vector_96_u32(void) {
    Vector_96_u32 v = zig_ret_vector_96_u32();
    assert_or_panic(v[0] == 890);
    assert_or_panic(v[1] == 891);
    assert_or_panic(v[2] == 892);
    assert_or_panic(v[3] == 893);
    assert_or_panic(v[4] == 894);
    assert_or_panic(v[5] == 895);
    assert_or_panic(v[6] == 896);
    assert_or_panic(v[7] == 897);
    assert_or_panic(v[8] == 898);
    assert_or_panic(v[9] == 899);
    assert_or_panic(v[10] == 900);
    assert_or_panic(v[11] == 901);
    assert_or_panic(v[12] == 902);
    assert_or_panic(v[13] == 903);
    assert_or_panic(v[14] == 904);
    assert_or_panic(v[15] == 905);
    assert_or_panic(v[16] == 906);
    assert_or_panic(v[17] == 907);
    assert_or_panic(v[18] == 908);
    assert_or_panic(v[19] == 909);
    assert_or_panic(v[20] == 910);
    assert_or_panic(v[21] == 911);
    assert_or_panic(v[22] == 912);
    assert_or_panic(v[23] == 913);
    assert_or_panic(v[24] == 914);
    assert_or_panic(v[25] == 915);
    assert_or_panic(v[26] == 916);
    assert_or_panic(v[27] == 917);
    assert_or_panic(v[28] == 918);
    assert_or_panic(v[29] == 919);
    assert_or_panic(v[30] == 920);
    assert_or_panic(v[31] == 921);
    assert_or_panic(v[32] == 922);
    assert_or_panic(v[33] == 923);
    assert_or_panic(v[34] == 924);
    assert_or_panic(v[35] == 925);
    assert_or_panic(v[36] == 926);
    assert_or_panic(v[37] == 927);
    assert_or_panic(v[38] == 928);
    assert_or_panic(v[39] == 929);
    assert_or_panic(v[40] == 930);
    assert_or_panic(v[41] == 931);
    assert_or_panic(v[42] == 932);
    assert_or_panic(v[43] == 933);
    assert_or_panic(v[44] == 934);
    assert_or_panic(v[45] == 935);
    assert_or_panic(v[46] == 936);
    assert_or_panic(v[47] == 937);
    assert_or_panic(v[48] == 938);
    assert_or_panic(v[49] == 939);
    assert_or_panic(v[50] == 940);
    assert_or_panic(v[51] == 941);
    assert_or_panic(v[52] == 942);
    assert_or_panic(v[53] == 943);
    assert_or_panic(v[54] == 944);
    assert_or_panic(v[55] == 945);
    assert_or_panic(v[56] == 946);
    assert_or_panic(v[57] == 947);
    assert_or_panic(v[58] == 948);
    assert_or_panic(v[59] == 949);
    assert_or_panic(v[60] == 950);
    assert_or_panic(v[61] == 951);
    assert_or_panic(v[62] == 952);
    assert_or_panic(v[63] == 953);
    assert_or_panic(v[64] == 954);
    assert_or_panic(v[65] == 955);
    assert_or_panic(v[66] == 956);
    assert_or_panic(v[67] == 957);
    assert_or_panic(v[68] == 958);
    assert_or_panic(v[69] == 959);
    assert_or_panic(v[70] == 960);
    assert_or_panic(v[71] == 961);
    assert_or_panic(v[72] == 962);
    assert_or_panic(v[73] == 963);
    assert_or_panic(v[74] == 964);
    assert_or_panic(v[75] == 965);
    assert_or_panic(v[76] == 966);
    assert_or_panic(v[77] == 967);
    assert_or_panic(v[78] == 968);
    assert_or_panic(v[79] == 969);
    assert_or_panic(v[80] == 970);
    assert_or_panic(v[81] == 971);
    assert_or_panic(v[82] == 972);
    assert_or_panic(v[83] == 973);
    assert_or_panic(v[84] == 974);
    assert_or_panic(v[85] == 975);
    assert_or_panic(v[86] == 976);
    assert_or_panic(v[87] == 977);
    assert_or_panic(v[88] == 978);
    assert_or_panic(v[89] == 979);
    assert_or_panic(v[90] == 980);
    assert_or_panic(v[91] == 981);
    assert_or_panic(v[92] == 982);
    assert_or_panic(v[93] == 983);
    assert_or_panic(v[94] == 984);
    assert_or_panic(v[95] == 985);
    zig_vector_96_u32((Vector_96_u32){
        986,  987,  988,  989,  990,  991,  992,  993,  994,  995,  996,  997,  998,  999,  1000, 1001,
        1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010, 1011, 1012, 1013, 1014, 1015, 1016, 1017,
        1018, 1019, 1020, 1021, 1022, 1023, 1024, 1025, 1026, 1027, 1028, 1029, 1030, 1031, 1032, 1033,
        1034, 1035, 1036, 1037, 1038, 1039, 1040, 1041, 1042, 1043, 1044, 1045, 1046, 1047, 1048, 1049,
        1050, 1051, 1052, 1053, 1054, 1055, 1056, 1057, 1058, 1059, 1060, 1061, 1062, 1063, 1064, 1065,
        1066, 1067, 1068, 1069, 1070, 1071, 1072, 1073, 1074, 1075, 1076, 1077, 1078, 1079, 1080, 1081,
    }, 96);
}

typedef uint32_t Vector_128_u32 __attribute__((vector_size(128 * sizeof(uint32_t))));

Vector_128_u32 zig_ret_vector_128_u32(void);
void zig_vector_128_u32(Vector_128_u32, size_t);

Vector_128_u32 c_ret_vector_128_u32(void) {
    return (Vector_128_u32){
        1530, 1531, 1532, 1533, 1534, 1535, 1536, 1537, 1538, 1539, 1540, 1541, 1542, 1543, 1544, 1545,
        1546, 1547, 1548, 1549, 1550, 1551, 1552, 1553, 1554, 1555, 1556, 1557, 1558, 1559, 1560, 1561,
        1562, 1563, 1564, 1565, 1566, 1567, 1568, 1569, 1570, 1571, 1572, 1573, 1574, 1575, 1576, 1577,
        1578, 1579, 1580, 1581, 1582, 1583, 1584, 1585, 1586, 1587, 1588, 1589, 1590, 1591, 1592, 1593,
        1594, 1595, 1596, 1597, 1598, 1599, 1600, 1601, 1602, 1603, 1604, 1605, 1606, 1607, 1608, 1609,
        1610, 1611, 1612, 1613, 1614, 1615, 1616, 1617, 1618, 1619, 1620, 1621, 1622, 1623, 1624, 1625,
        1626, 1627, 1628, 1629, 1630, 1631, 1632, 1633, 1634, 1635, 1636, 1637, 1638, 1639, 1640, 1641,
        1642, 1643, 1644, 1645, 1646, 1647, 1648, 1649, 1650, 1651, 1652, 1653, 1654, 1655, 1656, 1657,
    };
}
void c_vector_128_u32(Vector_128_u32 v, size_t i) {
    assert_or_panic(v[0] == 1658);
    assert_or_panic(v[1] == 1659);
    assert_or_panic(v[2] == 1660);
    assert_or_panic(v[3] == 1661);
    assert_or_panic(v[4] == 1662);
    assert_or_panic(v[5] == 1663);
    assert_or_panic(v[6] == 1664);
    assert_or_panic(v[7] == 1665);
    assert_or_panic(v[8] == 1666);
    assert_or_panic(v[9] == 1667);
    assert_or_panic(v[10] == 1668);
    assert_or_panic(v[11] == 1669);
    assert_or_panic(v[12] == 1670);
    assert_or_panic(v[13] == 1671);
    assert_or_panic(v[14] == 1672);
    assert_or_panic(v[15] == 1673);
    assert_or_panic(v[16] == 1674);
    assert_or_panic(v[17] == 1675);
    assert_or_panic(v[18] == 1676);
    assert_or_panic(v[19] == 1677);
    assert_or_panic(v[20] == 1678);
    assert_or_panic(v[21] == 1679);
    assert_or_panic(v[22] == 1680);
    assert_or_panic(v[23] == 1681);
    assert_or_panic(v[24] == 1682);
    assert_or_panic(v[25] == 1683);
    assert_or_panic(v[26] == 1684);
    assert_or_panic(v[27] == 1685);
    assert_or_panic(v[28] == 1686);
    assert_or_panic(v[29] == 1687);
    assert_or_panic(v[30] == 1688);
    assert_or_panic(v[31] == 1689);
    assert_or_panic(v[32] == 1690);
    assert_or_panic(v[33] == 1691);
    assert_or_panic(v[34] == 1692);
    assert_or_panic(v[35] == 1693);
    assert_or_panic(v[36] == 1694);
    assert_or_panic(v[37] == 1695);
    assert_or_panic(v[38] == 1696);
    assert_or_panic(v[39] == 1697);
    assert_or_panic(v[40] == 1698);
    assert_or_panic(v[41] == 1699);
    assert_or_panic(v[42] == 1700);
    assert_or_panic(v[43] == 1701);
    assert_or_panic(v[44] == 1702);
    assert_or_panic(v[45] == 1703);
    assert_or_panic(v[46] == 1704);
    assert_or_panic(v[47] == 1705);
    assert_or_panic(v[48] == 1706);
    assert_or_panic(v[49] == 1707);
    assert_or_panic(v[50] == 1708);
    assert_or_panic(v[51] == 1709);
    assert_or_panic(v[52] == 1710);
    assert_or_panic(v[53] == 1711);
    assert_or_panic(v[54] == 1712);
    assert_or_panic(v[55] == 1713);
    assert_or_panic(v[56] == 1714);
    assert_or_panic(v[57] == 1715);
    assert_or_panic(v[58] == 1716);
    assert_or_panic(v[59] == 1717);
    assert_or_panic(v[60] == 1718);
    assert_or_panic(v[61] == 1719);
    assert_or_panic(v[62] == 1720);
    assert_or_panic(v[63] == 1721);
    assert_or_panic(v[64] == 1722);
    assert_or_panic(v[65] == 1723);
    assert_or_panic(v[66] == 1724);
    assert_or_panic(v[67] == 1725);
    assert_or_panic(v[68] == 1726);
    assert_or_panic(v[69] == 1727);
    assert_or_panic(v[70] == 1728);
    assert_or_panic(v[71] == 1729);
    assert_or_panic(v[72] == 1730);
    assert_or_panic(v[73] == 1731);
    assert_or_panic(v[74] == 1732);
    assert_or_panic(v[75] == 1733);
    assert_or_panic(v[76] == 1734);
    assert_or_panic(v[77] == 1735);
    assert_or_panic(v[78] == 1736);
    assert_or_panic(v[79] == 1737);
    assert_or_panic(v[80] == 1738);
    assert_or_panic(v[81] == 1739);
    assert_or_panic(v[82] == 1740);
    assert_or_panic(v[83] == 1741);
    assert_or_panic(v[84] == 1742);
    assert_or_panic(v[85] == 1743);
    assert_or_panic(v[86] == 1744);
    assert_or_panic(v[87] == 1745);
    assert_or_panic(v[88] == 1746);
    assert_or_panic(v[89] == 1747);
    assert_or_panic(v[90] == 1748);
    assert_or_panic(v[91] == 1749);
    assert_or_panic(v[92] == 1750);
    assert_or_panic(v[93] == 1751);
    assert_or_panic(v[94] == 1752);
    assert_or_panic(v[95] == 1753);
    assert_or_panic(v[96] == 1754);
    assert_or_panic(v[97] == 1755);
    assert_or_panic(v[98] == 1756);
    assert_or_panic(v[99] == 1757);
    assert_or_panic(v[100] == 1758);
    assert_or_panic(v[101] == 1759);
    assert_or_panic(v[102] == 1760);
    assert_or_panic(v[103] == 1761);
    assert_or_panic(v[104] == 1762);
    assert_or_panic(v[105] == 1763);
    assert_or_panic(v[106] == 1764);
    assert_or_panic(v[107] == 1765);
    assert_or_panic(v[108] == 1766);
    assert_or_panic(v[109] == 1767);
    assert_or_panic(v[110] == 1768);
    assert_or_panic(v[111] == 1769);
    assert_or_panic(v[112] == 1770);
    assert_or_panic(v[113] == 1771);
    assert_or_panic(v[114] == 1772);
    assert_or_panic(v[115] == 1773);
    assert_or_panic(v[116] == 1774);
    assert_or_panic(v[117] == 1775);
    assert_or_panic(v[118] == 1776);
    assert_or_panic(v[119] == 1777);
    assert_or_panic(v[120] == 1778);
    assert_or_panic(v[121] == 1779);
    assert_or_panic(v[122] == 1780);
    assert_or_panic(v[123] == 1781);
    assert_or_panic(v[124] == 1782);
    assert_or_panic(v[125] == 1783);
    assert_or_panic(v[126] == 1784);
    assert_or_panic(v[127] == 1785);
    assert_or_panic(i == 128);
}
void c_test_vector_128_u32(void) {
    Vector_128_u32 v = zig_ret_vector_128_u32();
    assert_or_panic(v[0] == 1274);
    assert_or_panic(v[1] == 1275);
    assert_or_panic(v[2] == 1276);
    assert_or_panic(v[3] == 1277);
    assert_or_panic(v[4] == 1278);
    assert_or_panic(v[5] == 1279);
    assert_or_panic(v[6] == 1280);
    assert_or_panic(v[7] == 1281);
    assert_or_panic(v[8] == 1282);
    assert_or_panic(v[9] == 1283);
    assert_or_panic(v[10] == 1284);
    assert_or_panic(v[11] == 1285);
    assert_or_panic(v[12] == 1286);
    assert_or_panic(v[13] == 1287);
    assert_or_panic(v[14] == 1288);
    assert_or_panic(v[15] == 1289);
    assert_or_panic(v[16] == 1290);
    assert_or_panic(v[17] == 1291);
    assert_or_panic(v[18] == 1292);
    assert_or_panic(v[19] == 1293);
    assert_or_panic(v[20] == 1294);
    assert_or_panic(v[21] == 1295);
    assert_or_panic(v[22] == 1296);
    assert_or_panic(v[23] == 1297);
    assert_or_panic(v[24] == 1298);
    assert_or_panic(v[25] == 1299);
    assert_or_panic(v[26] == 1300);
    assert_or_panic(v[27] == 1301);
    assert_or_panic(v[28] == 1302);
    assert_or_panic(v[29] == 1303);
    assert_or_panic(v[30] == 1304);
    assert_or_panic(v[31] == 1305);
    assert_or_panic(v[32] == 1306);
    assert_or_panic(v[33] == 1307);
    assert_or_panic(v[34] == 1308);
    assert_or_panic(v[35] == 1309);
    assert_or_panic(v[36] == 1310);
    assert_or_panic(v[37] == 1311);
    assert_or_panic(v[38] == 1312);
    assert_or_panic(v[39] == 1313);
    assert_or_panic(v[40] == 1314);
    assert_or_panic(v[41] == 1315);
    assert_or_panic(v[42] == 1316);
    assert_or_panic(v[43] == 1317);
    assert_or_panic(v[44] == 1318);
    assert_or_panic(v[45] == 1319);
    assert_or_panic(v[46] == 1320);
    assert_or_panic(v[47] == 1321);
    assert_or_panic(v[48] == 1322);
    assert_or_panic(v[49] == 1323);
    assert_or_panic(v[50] == 1324);
    assert_or_panic(v[51] == 1325);
    assert_or_panic(v[52] == 1326);
    assert_or_panic(v[53] == 1327);
    assert_or_panic(v[54] == 1328);
    assert_or_panic(v[55] == 1329);
    assert_or_panic(v[56] == 1330);
    assert_or_panic(v[57] == 1331);
    assert_or_panic(v[58] == 1332);
    assert_or_panic(v[59] == 1333);
    assert_or_panic(v[60] == 1334);
    assert_or_panic(v[61] == 1335);
    assert_or_panic(v[62] == 1336);
    assert_or_panic(v[63] == 1337);
    assert_or_panic(v[64] == 1338);
    assert_or_panic(v[65] == 1339);
    assert_or_panic(v[66] == 1340);
    assert_or_panic(v[67] == 1341);
    assert_or_panic(v[68] == 1342);
    assert_or_panic(v[69] == 1343);
    assert_or_panic(v[70] == 1344);
    assert_or_panic(v[71] == 1345);
    assert_or_panic(v[72] == 1346);
    assert_or_panic(v[73] == 1347);
    assert_or_panic(v[74] == 1348);
    assert_or_panic(v[75] == 1349);
    assert_or_panic(v[76] == 1350);
    assert_or_panic(v[77] == 1351);
    assert_or_panic(v[78] == 1352);
    assert_or_panic(v[79] == 1353);
    assert_or_panic(v[80] == 1354);
    assert_or_panic(v[81] == 1355);
    assert_or_panic(v[82] == 1356);
    assert_or_panic(v[83] == 1357);
    assert_or_panic(v[84] == 1358);
    assert_or_panic(v[85] == 1359);
    assert_or_panic(v[86] == 1360);
    assert_or_panic(v[87] == 1361);
    assert_or_panic(v[88] == 1362);
    assert_or_panic(v[89] == 1363);
    assert_or_panic(v[90] == 1364);
    assert_or_panic(v[91] == 1365);
    assert_or_panic(v[92] == 1366);
    assert_or_panic(v[93] == 1367);
    assert_or_panic(v[94] == 1368);
    assert_or_panic(v[95] == 1369);
    assert_or_panic(v[96] == 1370);
    assert_or_panic(v[97] == 1371);
    assert_or_panic(v[98] == 1372);
    assert_or_panic(v[99] == 1373);
    assert_or_panic(v[100] == 1374);
    assert_or_panic(v[101] == 1375);
    assert_or_panic(v[102] == 1376);
    assert_or_panic(v[103] == 1377);
    assert_or_panic(v[104] == 1378);
    assert_or_panic(v[105] == 1379);
    assert_or_panic(v[106] == 1380);
    assert_or_panic(v[107] == 1381);
    assert_or_panic(v[108] == 1382);
    assert_or_panic(v[109] == 1383);
    assert_or_panic(v[110] == 1384);
    assert_or_panic(v[111] == 1385);
    assert_or_panic(v[112] == 1386);
    assert_or_panic(v[113] == 1387);
    assert_or_panic(v[114] == 1388);
    assert_or_panic(v[115] == 1389);
    assert_or_panic(v[116] == 1390);
    assert_or_panic(v[117] == 1391);
    assert_or_panic(v[118] == 1392);
    assert_or_panic(v[119] == 1393);
    assert_or_panic(v[120] == 1394);
    assert_or_panic(v[121] == 1395);
    assert_or_panic(v[122] == 1396);
    assert_or_panic(v[123] == 1397);
    assert_or_panic(v[124] == 1398);
    assert_or_panic(v[125] == 1399);
    assert_or_panic(v[126] == 1400);
    assert_or_panic(v[127] == 1401);
    zig_vector_128_u32((Vector_128_u32){
        1402, 1403, 1404, 1405, 1406, 1407, 1408, 1409, 1410, 1411, 1412, 1413, 1414, 1415, 1416, 1417,
        1418, 1419, 1420, 1421, 1422, 1423, 1424, 1425, 1426, 1427, 1428, 1429, 1430, 1431, 1432, 1433,
        1434, 1435, 1436, 1437, 1438, 1439, 1440, 1441, 1442, 1443, 1444, 1445, 1446, 1447, 1448, 1449,
        1450, 1451, 1452, 1453, 1454, 1455, 1456, 1457, 1458, 1459, 1460, 1461, 1462, 1463, 1464, 1465,
        1466, 1467, 1468, 1469, 1470, 1471, 1472, 1473, 1474, 1475, 1476, 1477, 1478, 1479, 1480, 1481,
        1482, 1483, 1484, 1485, 1486, 1487, 1488, 1489, 1490, 1491, 1492, 1493, 1494, 1495, 1496, 1497,
        1498, 1499, 1500, 1501, 1502, 1503, 1504, 1505, 1506, 1507, 1508, 1509, 1510, 1511, 1512, 1513,
        1514, 1515, 1516, 1517, 1518, 1519, 1520, 1521, 1522, 1523, 1524, 1525, 1526, 1527, 1528, 1529,
    }, 128);
}

typedef uint64_t Vector_1_u64 __attribute__((vector_size(1 * sizeof(uint64_t))));

Vector_1_u64 zig_ret_vector_1_u64(void);
void zig_vector_1_u64(Vector_1_u64, size_t);

Vector_1_u64 c_ret_vector_1_u64(void) {
    return (Vector_1_u64){ 3 };
}
void c_vector_1_u64(Vector_1_u64 v, size_t i) {
    assert_or_panic(v[0] == 4);
    assert_or_panic(i == 1);
}
void c_test_vector_1_u64(void) {
    Vector_1_u64 v = zig_ret_vector_1_u64();
    assert_or_panic(v[0] == 1);
    zig_vector_1_u64((Vector_1_u64){ 2 }, 1);
}

typedef uint64_t Vector_2_u64 __attribute__((vector_size(2 * sizeof(uint64_t))));

Vector_2_u64 zig_ret_vector_2_u64(void);
void zig_vector_2_u64(Vector_2_u64, size_t);

Vector_2_u64 c_ret_vector_2_u64(void) {
    return (Vector_2_u64){ 9, 10 };
}
void c_vector_2_u64(Vector_2_u64 v, size_t i) {
    assert_or_panic(v[0] == 11);
    assert_or_panic(v[1] == 12);
    assert_or_panic(i == 2);
}
void c_test_vector_2_u64(void) {
    Vector_2_u64 v = zig_ret_vector_2_u64();
    assert_or_panic(v[0] == 5);
    assert_or_panic(v[1] == 6);
    zig_vector_2_u64((Vector_2_u64){ 7, 8 }, 2);
}

typedef uint64_t Vector_3_u64 __attribute__((vector_size(3 * sizeof(uint64_t))));

Vector_3_u64 zig_ret_vector_3_u64(void);
void zig_vector_3_u64(Vector_3_u64, size_t);

Vector_3_u64 c_ret_vector_3_u64(void) {
    return (Vector_3_u64){ 19, 20, 21 };
}
void c_vector_3_u64(Vector_3_u64 v, size_t i) {
    assert_or_panic(v[0] == 22);
    assert_or_panic(v[1] == 23);
    assert_or_panic(v[2] == 24);
    assert_or_panic(i == 3);
}
void c_test_vector_3_u64(void) {
    Vector_3_u64 v = zig_ret_vector_3_u64();
    assert_or_panic(v[0] == 13);
    assert_or_panic(v[1] == 14);
    assert_or_panic(v[2] == 15);
    zig_vector_3_u64((Vector_3_u64){ 16, 17, 18 }, 3);
}

typedef uint64_t Vector_4_u64 __attribute__((vector_size(4 * sizeof(uint64_t))));

Vector_4_u64 zig_ret_vector_4_u64(void);
void zig_vector_4_u64(Vector_4_u64, size_t);

Vector_4_u64 c_ret_vector_4_u64(void) {
    return (Vector_4_u64){ 33, 34, 35, 36 };
}
void c_vector_4_u64(Vector_4_u64 v, size_t i) {
    assert_or_panic(v[0] == 37);
    assert_or_panic(v[1] == 38);
    assert_or_panic(v[2] == 39);
    assert_or_panic(v[3] == 40);
    assert_or_panic(i == 4);
}
void c_test_vector_4_u64(void) {
    Vector_4_u64 v = zig_ret_vector_4_u64();
    assert_or_panic(v[0] == 25);
    assert_or_panic(v[1] == 26);
    assert_or_panic(v[2] == 27);
    assert_or_panic(v[3] == 28);
    zig_vector_4_u64((Vector_4_u64){ 29, 30, 31, 32 }, 4);
}

typedef uint64_t Vector_6_u64 __attribute__((vector_size(6 * sizeof(uint64_t))));

Vector_6_u64 zig_ret_vector_6_u64(void);
void zig_vector_6_u64(Vector_6_u64, size_t);

Vector_6_u64 c_ret_vector_6_u64(void) {
    return (Vector_6_u64){ 53, 54, 55, 56, 57, 58 };
}
void c_vector_6_u64(Vector_6_u64 v, size_t i) {
    assert_or_panic(v[0] == 59);
    assert_or_panic(v[1] == 60);
    assert_or_panic(v[2] == 61);
    assert_or_panic(v[3] == 62);
    assert_or_panic(v[4] == 63);
    assert_or_panic(v[5] == 64);
    assert_or_panic(i == 6);
}
void c_test_vector_6_u64(void) {
    Vector_6_u64 v = zig_ret_vector_6_u64();
    assert_or_panic(v[0] == 41);
    assert_or_panic(v[1] == 42);
    assert_or_panic(v[2] == 43);
    assert_or_panic(v[3] == 44);
    assert_or_panic(v[4] == 45);
    assert_or_panic(v[5] == 46);
    zig_vector_6_u64((Vector_6_u64){ 47, 48, 49, 50, 51, 52 }, 6);
}

typedef uint64_t Vector_8_u64 __attribute__((vector_size(8 * sizeof(uint64_t))));

Vector_8_u64 zig_ret_vector_8_u64(void);
void zig_vector_8_u64(Vector_8_u64, size_t);

Vector_8_u64 c_ret_vector_8_u64(void) {
    return (Vector_8_u64){ 81, 82, 83, 84, 85, 86, 87, 88 };
}
void c_vector_8_u64(Vector_8_u64 v, size_t i) {
    assert_or_panic(v[0] == 89);
    assert_or_panic(v[1] == 90);
    assert_or_panic(v[2] == 91);
    assert_or_panic(v[3] == 92);
    assert_or_panic(v[4] == 93);
    assert_or_panic(v[5] == 94);
    assert_or_panic(v[6] == 95);
    assert_or_panic(v[7] == 96);
    assert_or_panic(i == 8);
}
void c_test_vector_8_u64(void) {
    Vector_8_u64 v = zig_ret_vector_8_u64();
    assert_or_panic(v[0] == 65);
    assert_or_panic(v[1] == 66);
    assert_or_panic(v[2] == 67);
    assert_or_panic(v[3] == 68);
    assert_or_panic(v[4] == 69);
    assert_or_panic(v[5] == 70);
    assert_or_panic(v[6] == 71);
    assert_or_panic(v[7] == 72);
    zig_vector_8_u64((Vector_8_u64){ 73, 74, 75, 76, 77, 78, 79, 80 }, 8);
}

typedef uint64_t Vector_12_u64 __attribute__((vector_size(12 * sizeof(uint64_t))));

Vector_12_u64 zig_ret_vector_12_u64(void);
void zig_vector_12_u64(Vector_12_u64, size_t);

Vector_12_u64 c_ret_vector_12_u64(void) {
    return (Vector_12_u64){ 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132 };
}
void c_vector_12_u64(Vector_12_u64 v, size_t i) {
    assert_or_panic(v[0] == 133);
    assert_or_panic(v[1] == 134);
    assert_or_panic(v[2] == 135);
    assert_or_panic(v[3] == 136);
    assert_or_panic(v[4] == 137);
    assert_or_panic(v[5] == 138);
    assert_or_panic(v[6] == 139);
    assert_or_panic(v[7] == 140);
    assert_or_panic(v[8] == 141);
    assert_or_panic(v[9] == 142);
    assert_or_panic(v[10] == 143);
    assert_or_panic(v[11] == 144);
    assert_or_panic(i == 12);
}
void c_test_vector_12_u64(void) {
    Vector_12_u64 v = zig_ret_vector_12_u64();
    assert_or_panic(v[0] == 97);
    assert_or_panic(v[1] == 98);
    assert_or_panic(v[2] == 99);
    assert_or_panic(v[3] == 100);
    assert_or_panic(v[4] == 101);
    assert_or_panic(v[5] == 102);
    assert_or_panic(v[6] == 103);
    assert_or_panic(v[7] == 104);
    assert_or_panic(v[8] == 105);
    assert_or_panic(v[9] == 106);
    assert_or_panic(v[10] == 107);
    assert_or_panic(v[11] == 108);
    zig_vector_12_u64((Vector_12_u64){ 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120 }, 12);
}

typedef uint64_t Vector_16_u64 __attribute__((vector_size(16 * sizeof(uint64_t))));

Vector_16_u64 zig_ret_vector_16_u64(void);
void zig_vector_16_u64(Vector_16_u64, size_t);

Vector_16_u64 c_ret_vector_16_u64(void) {
    return (Vector_16_u64){ 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192 };
}
void c_vector_16_u64(Vector_16_u64 v, size_t i) {
    assert_or_panic(v[0] == 193);
    assert_or_panic(v[1] == 194);
    assert_or_panic(v[2] == 195);
    assert_or_panic(v[3] == 196);
    assert_or_panic(v[4] == 197);
    assert_or_panic(v[5] == 198);
    assert_or_panic(v[6] == 199);
    assert_or_panic(v[7] == 200);
    assert_or_panic(v[8] == 201);
    assert_or_panic(v[9] == 202);
    assert_or_panic(v[10] == 203);
    assert_or_panic(v[11] == 204);
    assert_or_panic(v[12] == 205);
    assert_or_panic(v[13] == 206);
    assert_or_panic(v[14] == 207);
    assert_or_panic(v[15] == 208);
    assert_or_panic(i == 16);
}
void c_test_vector_16_u64(void) {
    Vector_16_u64 v = zig_ret_vector_16_u64();
    assert_or_panic(v[0] == 145);
    assert_or_panic(v[1] == 146);
    assert_or_panic(v[2] == 147);
    assert_or_panic(v[3] == 148);
    assert_or_panic(v[4] == 149);
    assert_or_panic(v[5] == 150);
    assert_or_panic(v[6] == 151);
    assert_or_panic(v[7] == 152);
    assert_or_panic(v[8] == 153);
    assert_or_panic(v[9] == 154);
    assert_or_panic(v[10] == 155);
    assert_or_panic(v[11] == 156);
    assert_or_panic(v[12] == 157);
    assert_or_panic(v[13] == 158);
    assert_or_panic(v[14] == 159);
    assert_or_panic(v[15] == 160);
    zig_vector_16_u64((Vector_16_u64){ 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176 }, 16);
}

typedef uint64_t Vector_24_u64 __attribute__((vector_size(24 * sizeof(uint64_t))));

Vector_24_u64 zig_ret_vector_24_u64(void);
void zig_vector_24_u64(Vector_24_u64, size_t);

Vector_24_u64 c_ret_vector_24_u64(void) {
    return (Vector_24_u64){
        257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272,
        273, 274, 275, 276, 277, 278, 279, 280,
    };
}
void c_vector_24_u64(Vector_24_u64 v, size_t i) {
    assert_or_panic(v[0] == 281);
    assert_or_panic(v[1] == 282);
    assert_or_panic(v[2] == 283);
    assert_or_panic(v[3] == 284);
    assert_or_panic(v[4] == 285);
    assert_or_panic(v[5] == 286);
    assert_or_panic(v[6] == 287);
    assert_or_panic(v[7] == 288);
    assert_or_panic(v[8] == 289);
    assert_or_panic(v[9] == 290);
    assert_or_panic(v[10] == 291);
    assert_or_panic(v[11] == 292);
    assert_or_panic(v[12] == 293);
    assert_or_panic(v[13] == 294);
    assert_or_panic(v[14] == 295);
    assert_or_panic(v[15] == 296);
    assert_or_panic(v[16] == 297);
    assert_or_panic(v[17] == 298);
    assert_or_panic(v[18] == 299);
    assert_or_panic(v[19] == 300);
    assert_or_panic(v[20] == 301);
    assert_or_panic(v[21] == 302);
    assert_or_panic(v[22] == 303);
    assert_or_panic(v[23] == 304);
    assert_or_panic(i == 24);
}
void c_test_vector_24_u64(void) {
    Vector_24_u64 v = zig_ret_vector_24_u64();
    assert_or_panic(v[0] == 209);
    assert_or_panic(v[1] == 210);
    assert_or_panic(v[2] == 211);
    assert_or_panic(v[3] == 212);
    assert_or_panic(v[4] == 213);
    assert_or_panic(v[5] == 214);
    assert_or_panic(v[6] == 215);
    assert_or_panic(v[7] == 216);
    assert_or_panic(v[8] == 217);
    assert_or_panic(v[9] == 218);
    assert_or_panic(v[10] == 219);
    assert_or_panic(v[11] == 220);
    assert_or_panic(v[12] == 221);
    assert_or_panic(v[13] == 222);
    assert_or_panic(v[14] == 223);
    assert_or_panic(v[15] == 224);
    assert_or_panic(v[16] == 225);
    assert_or_panic(v[17] == 226);
    assert_or_panic(v[18] == 227);
    assert_or_panic(v[19] == 228);
    assert_or_panic(v[20] == 229);
    assert_or_panic(v[21] == 230);
    assert_or_panic(v[22] == 231);
    assert_or_panic(v[23] == 232);
    zig_vector_24_u64((Vector_24_u64){
        233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248,
        249, 250, 251, 252, 253, 254, 255, 256,
    }, 24);
}

typedef uint64_t Vector_32_u64 __attribute__((vector_size(32 * sizeof(uint64_t))));

Vector_32_u64 zig_ret_vector_32_u64(void);
void zig_vector_32_u64(Vector_32_u64, size_t);

Vector_32_u64 c_ret_vector_32_u64(void) {
    return (Vector_32_u64){
        369, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 382, 383, 384,
        385, 386, 387, 388, 389, 390, 391, 392, 393, 394, 395, 396, 397, 398, 399, 400,
    };
}
void c_vector_32_u64(Vector_32_u64 v, size_t i) {
    assert_or_panic(v[0] == 401);
    assert_or_panic(v[1] == 402);
    assert_or_panic(v[2] == 403);
    assert_or_panic(v[3] == 404);
    assert_or_panic(v[4] == 405);
    assert_or_panic(v[5] == 406);
    assert_or_panic(v[6] == 407);
    assert_or_panic(v[7] == 408);
    assert_or_panic(v[8] == 409);
    assert_or_panic(v[9] == 410);
    assert_or_panic(v[10] == 411);
    assert_or_panic(v[11] == 412);
    assert_or_panic(v[12] == 413);
    assert_or_panic(v[13] == 414);
    assert_or_panic(v[14] == 415);
    assert_or_panic(v[15] == 416);
    assert_or_panic(v[16] == 417);
    assert_or_panic(v[17] == 418);
    assert_or_panic(v[18] == 419);
    assert_or_panic(v[19] == 420);
    assert_or_panic(v[20] == 421);
    assert_or_panic(v[21] == 422);
    assert_or_panic(v[22] == 423);
    assert_or_panic(v[23] == 424);
    assert_or_panic(v[24] == 425);
    assert_or_panic(v[25] == 426);
    assert_or_panic(v[26] == 427);
    assert_or_panic(v[27] == 428);
    assert_or_panic(v[28] == 429);
    assert_or_panic(v[29] == 430);
    assert_or_panic(v[30] == 431);
    assert_or_panic(v[31] == 432);
    assert_or_panic(i == 32);
}
void c_test_vector_32_u64(void) {
    Vector_32_u64 v = zig_ret_vector_32_u64();
    assert_or_panic(v[0] == 305);
    assert_or_panic(v[1] == 306);
    assert_or_panic(v[2] == 307);
    assert_or_panic(v[3] == 308);
    assert_or_panic(v[4] == 309);
    assert_or_panic(v[5] == 310);
    assert_or_panic(v[6] == 311);
    assert_or_panic(v[7] == 312);
    assert_or_panic(v[8] == 313);
    assert_or_panic(v[9] == 314);
    assert_or_panic(v[10] == 315);
    assert_or_panic(v[11] == 316);
    assert_or_panic(v[12] == 317);
    assert_or_panic(v[13] == 318);
    assert_or_panic(v[14] == 319);
    assert_or_panic(v[15] == 320);
    assert_or_panic(v[16] == 321);
    assert_or_panic(v[17] == 322);
    assert_or_panic(v[18] == 323);
    assert_or_panic(v[19] == 324);
    assert_or_panic(v[20] == 325);
    assert_or_panic(v[21] == 326);
    assert_or_panic(v[22] == 327);
    assert_or_panic(v[23] == 328);
    assert_or_panic(v[24] == 329);
    assert_or_panic(v[25] == 330);
    assert_or_panic(v[26] == 331);
    assert_or_panic(v[27] == 332);
    assert_or_panic(v[28] == 333);
    assert_or_panic(v[29] == 334);
    assert_or_panic(v[30] == 335);
    assert_or_panic(v[31] == 336);
    zig_vector_32_u64((Vector_32_u64){
        337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351, 352,
        353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368,
    }, 32);
}

typedef uint64_t Vector_48_u64 __attribute__((vector_size(48 * sizeof(uint64_t))));

Vector_48_u64 zig_ret_vector_48_u64(void);
void zig_vector_48_u64(Vector_48_u64, size_t);

Vector_48_u64 c_ret_vector_48_u64(void) {
    return (Vector_48_u64){
        529, 530, 531, 532, 533, 534, 535, 536, 537, 538, 539, 540, 541, 542, 543, 544,
        545, 546, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 560,
        561, 562, 563, 564, 565, 566, 567, 568, 569, 570, 571, 572, 573, 574, 575, 576,
    };
}
void c_vector_48_u64(Vector_48_u64 v, size_t i) {
    assert_or_panic(v[0] == 577);
    assert_or_panic(v[1] == 578);
    assert_or_panic(v[2] == 579);
    assert_or_panic(v[3] == 580);
    assert_or_panic(v[4] == 581);
    assert_or_panic(v[5] == 582);
    assert_or_panic(v[6] == 583);
    assert_or_panic(v[7] == 584);
    assert_or_panic(v[8] == 585);
    assert_or_panic(v[9] == 586);
    assert_or_panic(v[10] == 587);
    assert_or_panic(v[11] == 588);
    assert_or_panic(v[12] == 589);
    assert_or_panic(v[13] == 590);
    assert_or_panic(v[14] == 591);
    assert_or_panic(v[15] == 592);
    assert_or_panic(v[16] == 593);
    assert_or_panic(v[17] == 594);
    assert_or_panic(v[18] == 595);
    assert_or_panic(v[19] == 596);
    assert_or_panic(v[20] == 597);
    assert_or_panic(v[21] == 598);
    assert_or_panic(v[22] == 599);
    assert_or_panic(v[23] == 600);
    assert_or_panic(v[24] == 601);
    assert_or_panic(v[25] == 602);
    assert_or_panic(v[26] == 603);
    assert_or_panic(v[27] == 604);
    assert_or_panic(v[28] == 605);
    assert_or_panic(v[29] == 606);
    assert_or_panic(v[30] == 607);
    assert_or_panic(v[31] == 608);
    assert_or_panic(v[32] == 609);
    assert_or_panic(v[33] == 610);
    assert_or_panic(v[34] == 611);
    assert_or_panic(v[35] == 612);
    assert_or_panic(v[36] == 613);
    assert_or_panic(v[37] == 614);
    assert_or_panic(v[38] == 615);
    assert_or_panic(v[39] == 616);
    assert_or_panic(v[40] == 617);
    assert_or_panic(v[41] == 618);
    assert_or_panic(v[42] == 619);
    assert_or_panic(v[43] == 620);
    assert_or_panic(v[44] == 621);
    assert_or_panic(v[45] == 622);
    assert_or_panic(v[46] == 623);
    assert_or_panic(v[47] == 624);
    assert_or_panic(i == 48);
}
void c_test_vector_48_u64(void) {
    Vector_48_u64 v = zig_ret_vector_48_u64();
    assert_or_panic(v[0] == 433);
    assert_or_panic(v[1] == 434);
    assert_or_panic(v[2] == 435);
    assert_or_panic(v[3] == 436);
    assert_or_panic(v[4] == 437);
    assert_or_panic(v[5] == 438);
    assert_or_panic(v[6] == 439);
    assert_or_panic(v[7] == 440);
    assert_or_panic(v[8] == 441);
    assert_or_panic(v[9] == 442);
    assert_or_panic(v[10] == 443);
    assert_or_panic(v[11] == 444);
    assert_or_panic(v[12] == 445);
    assert_or_panic(v[13] == 446);
    assert_or_panic(v[14] == 447);
    assert_or_panic(v[15] == 448);
    assert_or_panic(v[16] == 449);
    assert_or_panic(v[17] == 450);
    assert_or_panic(v[18] == 451);
    assert_or_panic(v[19] == 452);
    assert_or_panic(v[20] == 453);
    assert_or_panic(v[21] == 454);
    assert_or_panic(v[22] == 455);
    assert_or_panic(v[23] == 456);
    assert_or_panic(v[24] == 457);
    assert_or_panic(v[25] == 458);
    assert_or_panic(v[26] == 459);
    assert_or_panic(v[27] == 460);
    assert_or_panic(v[28] == 461);
    assert_or_panic(v[29] == 462);
    assert_or_panic(v[30] == 463);
    assert_or_panic(v[31] == 464);
    assert_or_panic(v[32] == 465);
    assert_or_panic(v[33] == 466);
    assert_or_panic(v[34] == 467);
    assert_or_panic(v[35] == 468);
    assert_or_panic(v[36] == 469);
    assert_or_panic(v[37] == 470);
    assert_or_panic(v[38] == 471);
    assert_or_panic(v[39] == 472);
    assert_or_panic(v[40] == 473);
    assert_or_panic(v[41] == 474);
    assert_or_panic(v[42] == 475);
    assert_or_panic(v[43] == 476);
    assert_or_panic(v[44] == 477);
    assert_or_panic(v[45] == 478);
    assert_or_panic(v[46] == 479);
    assert_or_panic(v[47] == 480);
    zig_vector_48_u64((Vector_48_u64){
        481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496,
        497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512,
        513, 514, 515, 516, 517, 518, 519, 520, 521, 522, 523, 524, 525, 526, 527, 528,
    }, 48);
}

typedef uint64_t Vector_64_u64 __attribute__((vector_size(64 * sizeof(uint64_t))));

Vector_64_u64 zig_ret_vector_64_u64(void);
void zig_vector_64_u64(Vector_64_u64, size_t);

Vector_64_u64 c_ret_vector_64_u64(void) {
    return (Vector_64_u64){
        753, 754, 755, 756, 757, 758, 759, 760, 761, 762, 763, 764, 765, 766, 767, 768,
        769, 770, 771, 772, 773, 774, 775, 776, 777, 778, 779, 780, 781, 782, 783, 784,
        785, 786, 787, 788, 789, 790, 791, 792, 793, 794, 795, 796, 797, 798, 799, 800,
        801, 802, 803, 804, 805, 806, 807, 808, 809, 810, 811, 812, 813, 814, 815, 816,
    };
}
void c_vector_64_u64(Vector_64_u64 v, size_t i) {
    assert_or_panic(v[0] == 817);
    assert_or_panic(v[1] == 818);
    assert_or_panic(v[2] == 819);
    assert_or_panic(v[3] == 820);
    assert_or_panic(v[4] == 821);
    assert_or_panic(v[5] == 822);
    assert_or_panic(v[6] == 823);
    assert_or_panic(v[7] == 824);
    assert_or_panic(v[8] == 825);
    assert_or_panic(v[9] == 826);
    assert_or_panic(v[10] == 827);
    assert_or_panic(v[11] == 828);
    assert_or_panic(v[12] == 829);
    assert_or_panic(v[13] == 830);
    assert_or_panic(v[14] == 831);
    assert_or_panic(v[15] == 832);
    assert_or_panic(v[16] == 833);
    assert_or_panic(v[17] == 834);
    assert_or_panic(v[18] == 835);
    assert_or_panic(v[19] == 836);
    assert_or_panic(v[20] == 837);
    assert_or_panic(v[21] == 838);
    assert_or_panic(v[22] == 839);
    assert_or_panic(v[23] == 840);
    assert_or_panic(v[24] == 841);
    assert_or_panic(v[25] == 842);
    assert_or_panic(v[26] == 843);
    assert_or_panic(v[27] == 844);
    assert_or_panic(v[28] == 845);
    assert_or_panic(v[29] == 846);
    assert_or_panic(v[30] == 847);
    assert_or_panic(v[31] == 848);
    assert_or_panic(v[32] == 849);
    assert_or_panic(v[33] == 850);
    assert_or_panic(v[34] == 851);
    assert_or_panic(v[35] == 852);
    assert_or_panic(v[36] == 853);
    assert_or_panic(v[37] == 854);
    assert_or_panic(v[38] == 855);
    assert_or_panic(v[39] == 856);
    assert_or_panic(v[40] == 857);
    assert_or_panic(v[41] == 858);
    assert_or_panic(v[42] == 859);
    assert_or_panic(v[43] == 860);
    assert_or_panic(v[44] == 861);
    assert_or_panic(v[45] == 862);
    assert_or_panic(v[46] == 863);
    assert_or_panic(v[47] == 864);
    assert_or_panic(v[48] == 865);
    assert_or_panic(v[49] == 866);
    assert_or_panic(v[50] == 867);
    assert_or_panic(v[51] == 868);
    assert_or_panic(v[52] == 869);
    assert_or_panic(v[53] == 870);
    assert_or_panic(v[54] == 871);
    assert_or_panic(v[55] == 872);
    assert_or_panic(v[56] == 873);
    assert_or_panic(v[57] == 874);
    assert_or_panic(v[58] == 875);
    assert_or_panic(v[59] == 876);
    assert_or_panic(v[60] == 877);
    assert_or_panic(v[61] == 878);
    assert_or_panic(v[62] == 879);
    assert_or_panic(v[63] == 880);
    assert_or_panic(i == 64);
}
void c_test_vector_64_u64(void) {
    Vector_64_u64 v = zig_ret_vector_64_u64();
    assert_or_panic(v[0] == 625);
    assert_or_panic(v[1] == 626);
    assert_or_panic(v[2] == 627);
    assert_or_panic(v[3] == 628);
    assert_or_panic(v[4] == 629);
    assert_or_panic(v[5] == 630);
    assert_or_panic(v[6] == 631);
    assert_or_panic(v[7] == 632);
    assert_or_panic(v[8] == 633);
    assert_or_panic(v[9] == 634);
    assert_or_panic(v[10] == 635);
    assert_or_panic(v[11] == 636);
    assert_or_panic(v[12] == 637);
    assert_or_panic(v[13] == 638);
    assert_or_panic(v[14] == 639);
    assert_or_panic(v[15] == 640);
    assert_or_panic(v[16] == 641);
    assert_or_panic(v[17] == 642);
    assert_or_panic(v[18] == 643);
    assert_or_panic(v[19] == 644);
    assert_or_panic(v[20] == 645);
    assert_or_panic(v[21] == 646);
    assert_or_panic(v[22] == 647);
    assert_or_panic(v[23] == 648);
    assert_or_panic(v[24] == 649);
    assert_or_panic(v[25] == 650);
    assert_or_panic(v[26] == 651);
    assert_or_panic(v[27] == 652);
    assert_or_panic(v[28] == 653);
    assert_or_panic(v[29] == 654);
    assert_or_panic(v[30] == 655);
    assert_or_panic(v[31] == 656);
    assert_or_panic(v[32] == 657);
    assert_or_panic(v[33] == 658);
    assert_or_panic(v[34] == 659);
    assert_or_panic(v[35] == 660);
    assert_or_panic(v[36] == 661);
    assert_or_panic(v[37] == 662);
    assert_or_panic(v[38] == 663);
    assert_or_panic(v[39] == 664);
    assert_or_panic(v[40] == 665);
    assert_or_panic(v[41] == 666);
    assert_or_panic(v[42] == 667);
    assert_or_panic(v[43] == 668);
    assert_or_panic(v[44] == 669);
    assert_or_panic(v[45] == 670);
    assert_or_panic(v[46] == 671);
    assert_or_panic(v[47] == 672);
    assert_or_panic(v[48] == 673);
    assert_or_panic(v[49] == 674);
    assert_or_panic(v[50] == 675);
    assert_or_panic(v[51] == 676);
    assert_or_panic(v[52] == 677);
    assert_or_panic(v[53] == 678);
    assert_or_panic(v[54] == 679);
    assert_or_panic(v[55] == 680);
    assert_or_panic(v[56] == 681);
    assert_or_panic(v[57] == 682);
    assert_or_panic(v[58] == 683);
    assert_or_panic(v[59] == 684);
    assert_or_panic(v[60] == 685);
    assert_or_panic(v[61] == 686);
    assert_or_panic(v[62] == 687);
    assert_or_panic(v[63] == 688);
    zig_vector_64_u64((Vector_64_u64){
        689, 690, 691, 692, 693, 694, 695, 696, 697, 698, 699, 700, 701, 702, 703, 704,
        705, 706, 707, 708, 709, 710, 711, 712, 713, 714, 715, 716, 717, 718, 719, 720,
        721, 722, 723, 724, 725, 726, 727, 728, 729, 730, 731, 732, 733, 734, 735, 736,
        737, 738, 739, 740, 741, 742, 743, 744, 745, 746, 747, 748, 749, 750, 751, 752,
    }, 64);
}

typedef float Vector_1_f32 __attribute__((vector_size(1 * sizeof(float))));

Vector_1_f32 zig_ret_vector_1_f32(void);
void zig_vector_1_f32(Vector_1_f32, size_t);

Vector_1_f32 c_ret_vector_1_f32(void) {
    return (Vector_1_f32){ 3 };
}
void c_vector_1_f32(Vector_1_f32 v, size_t i) {
    assert_or_panic(v[0] == 4);
    assert_or_panic(i == 1);
}
void c_test_vector_1_f32(void) {
    Vector_1_f32 v = zig_ret_vector_1_f32();
    assert_or_panic(v[0] == 1);
    zig_vector_1_f32((Vector_1_f32){ 2 }, 1);
}

typedef float Vector_2_f32 __attribute__((vector_size(2 * sizeof(float))));

Vector_2_f32 zig_ret_vector_2_f32(void);
void zig_vector_2_f32(Vector_2_f32, size_t);

Vector_2_f32 c_ret_vector_2_f32(void) {
    return (Vector_2_f32){ 9, 10 };
}
void c_vector_2_f32(Vector_2_f32 v, size_t i) {
    assert_or_panic(v[0] == 11);
    assert_or_panic(v[1] == 12);
    assert_or_panic(i == 2);
}
void c_test_vector_2_f32(void) {
    Vector_2_f32 v = zig_ret_vector_2_f32();
    assert_or_panic(v[0] == 5);
    assert_or_panic(v[1] == 6);
    zig_vector_2_f32((Vector_2_f32){ 7, 8 }, 2);
}

typedef float Vector_3_f32 __attribute__((vector_size(3 * sizeof(float))));

Vector_3_f32 zig_ret_vector_3_f32(void);
void zig_vector_3_f32(Vector_3_f32, size_t);

Vector_3_f32 c_ret_vector_3_f32(void) {
    return (Vector_3_f32){ 19, 20, 21 };
}
void c_vector_3_f32(Vector_3_f32 v, size_t i) {
    assert_or_panic(v[0] == 22);
    assert_or_panic(v[1] == 23);
    assert_or_panic(v[2] == 24);
    assert_or_panic(i == 32);
}
void c_test_vector_3_f32(void) {
    Vector_3_f32 v = zig_ret_vector_3_f32();
    assert_or_panic(v[0] == 13);
    assert_or_panic(v[1] == 14);
    assert_or_panic(v[2] == 15);
    zig_vector_3_f32((Vector_3_f32){ 16, 17, 18 }, 3);
}

typedef float Vector_4_f32 __attribute__((vector_size(4 * sizeof(float))));

Vector_4_f32 zig_ret_vector_4_f32(void);
void zig_vector_4_f32(Vector_4_f32, size_t);
void zig_vector_4_f32_vector_4_f32(Vector_4_f32, Vector_4_f32, size_t);

Vector_4_f32 c_ret_vector_4_f32(void) {
    return (Vector_4_f32){ 41, 42, 43, 44 };
}
void c_vector_4_f32(Vector_4_f32 v, size_t i) {
    assert_or_panic(v[0] == 45);
    assert_or_panic(v[1] == 46);
    assert_or_panic(v[2] == 47);
    assert_or_panic(v[3] == 48);
    assert_or_panic(i == 4);
}
void c_vector_4_f32_vector_4_f32(Vector_4_f32 v0, Vector_4_f32 v1, size_t i) {
    assert_or_panic(v0[0] == 49);
    assert_or_panic(v0[1] == 50);
    assert_or_panic(v0[2] == 51);
    assert_or_panic(v0[3] == 52);
    assert_or_panic(v1[0] == 53);
    assert_or_panic(v1[1] == 54);
    assert_or_panic(v1[2] == 55);
    assert_or_panic(v1[3] == 56);
    assert_or_panic(i == 8);
}
void c_test_vector_4_f32(void) {
    Vector_4_f32 v = zig_ret_vector_4_f32();
    assert_or_panic(v[0] == 25);
    assert_or_panic(v[1] == 26);
    assert_or_panic(v[2] == 27);
    assert_or_panic(v[3] == 28);
    zig_vector_4_f32((Vector_4_f32){ 29, 30, 31, 32 }, 4);
    zig_vector_4_f32_vector_4_f32((Vector_4_f32){ 33, 34, 35, 36 }, (Vector_4_f32){ 37, 38, 39, 40 }, 8);
}

typedef float Vector_6_f32 __attribute__((vector_size(6 * sizeof(float))));

Vector_6_f32 zig_ret_vector_6_f32(void);
void zig_vector_6_f32(Vector_6_f32, size_t);

Vector_6_f32 c_ret_vector_6_f32(void) {
    return (Vector_6_f32){ 53, 54, 55, 56, 57, 58 };
}
void c_vector_6_f32(Vector_6_f32 v, size_t i) {
    assert_or_panic(v[0] == 59);
    assert_or_panic(v[1] == 60);
    assert_or_panic(v[2] == 61);
    assert_or_panic(v[3] == 62);
    assert_or_panic(v[4] == 63);
    assert_or_panic(v[5] == 64);
    assert_or_panic(i == 6);
}
void c_test_vector_6_f32(void) {
    Vector_6_f32 v = zig_ret_vector_6_f32();
    assert_or_panic(v[0] == 41);
    assert_or_panic(v[1] == 42);
    assert_or_panic(v[2] == 43);
    assert_or_panic(v[3] == 44);
    assert_or_panic(v[4] == 45);
    assert_or_panic(v[5] == 46);
    zig_vector_6_f32((Vector_6_f32){ 47, 48, 49, 50, 51, 52 }, 6);
}

typedef float Vector_8_f32 __attribute__((vector_size(8 * sizeof(float))));

Vector_8_f32 zig_ret_vector_8_f32(void);
void zig_vector_8_f32(Vector_8_f32, size_t);

Vector_8_f32 c_ret_vector_8_f32(void) {
    return (Vector_8_f32){ 81, 82, 83, 84, 85, 86, 87, 88 };
}
void c_vector_8_f32(Vector_8_f32 v, size_t i) {
    assert_or_panic(v[0] == 89);
    assert_or_panic(v[1] == 90);
    assert_or_panic(v[2] == 91);
    assert_or_panic(v[3] == 92);
    assert_or_panic(v[4] == 93);
    assert_or_panic(v[5] == 94);
    assert_or_panic(v[6] == 95);
    assert_or_panic(v[7] == 96);
    assert_or_panic(i == 8);
}
void c_test_vector_8_f32(void) {
    Vector_8_f32 v = zig_ret_vector_8_f32();
    assert_or_panic(v[0] == 65);
    assert_or_panic(v[1] == 66);
    assert_or_panic(v[2] == 67);
    assert_or_panic(v[3] == 68);
    assert_or_panic(v[4] == 69);
    assert_or_panic(v[5] == 70);
    assert_or_panic(v[6] == 71);
    assert_or_panic(v[7] == 72);
    zig_vector_8_f32((Vector_8_f32){ 73, 74, 75, 76, 77, 78, 79, 80 }, 8);
}

typedef float Vector_12_f32 __attribute__((vector_size(12 * sizeof(float))));

Vector_12_f32 zig_ret_vector_12_f32(void);
void zig_vector_12_f32(Vector_12_f32, size_t);

Vector_12_f32 c_ret_vector_12_f32(void) {
    return (Vector_12_f32){ 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132 };
}
void c_vector_12_f32(Vector_12_f32 v, size_t i) {
    assert_or_panic(v[0] == 133);
    assert_or_panic(v[1] == 134);
    assert_or_panic(v[2] == 135);
    assert_or_panic(v[3] == 136);
    assert_or_panic(v[4] == 137);
    assert_or_panic(v[5] == 138);
    assert_or_panic(v[6] == 139);
    assert_or_panic(v[7] == 140);
    assert_or_panic(v[8] == 141);
    assert_or_panic(v[9] == 142);
    assert_or_panic(v[10] == 143);
    assert_or_panic(v[11] == 144);
    assert_or_panic(i == 12);
}
void c_test_vector_12_f32(void) {
    Vector_12_f32 v = zig_ret_vector_12_f32();
    assert_or_panic(v[0] == 97);
    assert_or_panic(v[1] == 98);
    assert_or_panic(v[2] == 99);
    assert_or_panic(v[3] == 100);
    assert_or_panic(v[4] == 101);
    assert_or_panic(v[5] == 102);
    assert_or_panic(v[6] == 103);
    assert_or_panic(v[7] == 104);
    assert_or_panic(v[8] == 105);
    assert_or_panic(v[9] == 106);
    assert_or_panic(v[10] == 107);
    assert_or_panic(v[11] == 108);
    zig_vector_12_f32((Vector_12_f32){ 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120 }, 12);
}

typedef float Vector_16_f32 __attribute__((vector_size(16 * sizeof(float))));

Vector_16_f32 zig_ret_vector_16_f32(void);
void zig_vector_16_f32(Vector_16_f32, size_t);

Vector_16_f32 c_ret_vector_16_f32(void) {
    return (Vector_16_f32){ 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192 };
}
void c_vector_16_f32(Vector_16_f32 v, size_t i) {
    assert_or_panic(v[0] == 193);
    assert_or_panic(v[1] == 194);
    assert_or_panic(v[2] == 195);
    assert_or_panic(v[3] == 196);
    assert_or_panic(v[4] == 197);
    assert_or_panic(v[5] == 198);
    assert_or_panic(v[6] == 199);
    assert_or_panic(v[7] == 200);
    assert_or_panic(v[8] == 201);
    assert_or_panic(v[9] == 202);
    assert_or_panic(v[10] == 203);
    assert_or_panic(v[11] == 204);
    assert_or_panic(v[12] == 205);
    assert_or_panic(v[13] == 206);
    assert_or_panic(v[14] == 207);
    assert_or_panic(v[15] == 208);
    assert_or_panic(i == 16);
}
void c_test_vector_16_f32(void) {
    Vector_16_f32 v = zig_ret_vector_16_f32();
    assert_or_panic(v[0] == 145);
    assert_or_panic(v[1] == 146);
    assert_or_panic(v[2] == 147);
    assert_or_panic(v[3] == 148);
    assert_or_panic(v[4] == 149);
    assert_or_panic(v[5] == 150);
    assert_or_panic(v[6] == 151);
    assert_or_panic(v[7] == 152);
    assert_or_panic(v[8] == 153);
    assert_or_panic(v[9] == 154);
    assert_or_panic(v[10] == 155);
    assert_or_panic(v[11] == 156);
    assert_or_panic(v[12] == 157);
    assert_or_panic(v[13] == 158);
    assert_or_panic(v[14] == 159);
    assert_or_panic(v[15] == 160);
    zig_vector_16_f32((Vector_16_f32){ 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176 }, 16);
}

typedef float Vector_24_f32 __attribute__((vector_size(24 * sizeof(float))));

Vector_24_f32 zig_ret_vector_24_f32(void);
void zig_vector_24_f32(Vector_24_f32, size_t);

Vector_24_f32 c_ret_vector_24_f32(void) {
    return (Vector_24_f32){
        257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272,
        273, 274, 275, 276, 277, 278, 279, 280,
    };
}
void c_vector_24_f32(Vector_24_f32 v, size_t i) {
    assert_or_panic(v[0] == 281);
    assert_or_panic(v[1] == 282);
    assert_or_panic(v[2] == 283);
    assert_or_panic(v[3] == 284);
    assert_or_panic(v[4] == 285);
    assert_or_panic(v[5] == 286);
    assert_or_panic(v[6] == 287);
    assert_or_panic(v[7] == 288);
    assert_or_panic(v[8] == 289);
    assert_or_panic(v[9] == 290);
    assert_or_panic(v[10] == 291);
    assert_or_panic(v[11] == 292);
    assert_or_panic(v[12] == 293);
    assert_or_panic(v[13] == 294);
    assert_or_panic(v[14] == 295);
    assert_or_panic(v[15] == 296);
    assert_or_panic(v[16] == 297);
    assert_or_panic(v[17] == 298);
    assert_or_panic(v[18] == 299);
    assert_or_panic(v[19] == 300);
    assert_or_panic(v[20] == 301);
    assert_or_panic(v[21] == 302);
    assert_or_panic(v[22] == 303);
    assert_or_panic(v[23] == 304);
    assert_or_panic(i == 24);
}
void c_test_vector_24_f32(void) {
    Vector_24_f32 v = zig_ret_vector_24_f32();
    assert_or_panic(v[0] == 209);
    assert_or_panic(v[1] == 210);
    assert_or_panic(v[2] == 211);
    assert_or_panic(v[3] == 212);
    assert_or_panic(v[4] == 213);
    assert_or_panic(v[5] == 214);
    assert_or_panic(v[6] == 215);
    assert_or_panic(v[7] == 216);
    assert_or_panic(v[8] == 217);
    assert_or_panic(v[9] == 218);
    assert_or_panic(v[10] == 219);
    assert_or_panic(v[11] == 220);
    assert_or_panic(v[12] == 221);
    assert_or_panic(v[13] == 222);
    assert_or_panic(v[14] == 223);
    assert_or_panic(v[15] == 224);
    assert_or_panic(v[16] == 225);
    assert_or_panic(v[17] == 226);
    assert_or_panic(v[18] == 227);
    assert_or_panic(v[19] == 228);
    assert_or_panic(v[20] == 229);
    assert_or_panic(v[21] == 230);
    assert_or_panic(v[22] == 231);
    assert_or_panic(v[23] == 232);
    zig_vector_24_f32((Vector_24_f32){
        233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248,
        249, 250, 251, 252, 253, 254, 255, 256,
    }, 24);
}

typedef float Vector_32_f32 __attribute__((vector_size(32 * sizeof(float))));

Vector_32_f32 zig_ret_vector_32_f32(void);
void zig_vector_32_f32(Vector_32_f32, size_t);

Vector_32_f32 c_ret_vector_32_f32(void) {
    return (Vector_32_f32){
        369, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 382, 383, 384,
        385, 386, 387, 388, 389, 390, 391, 392, 393, 394, 395, 396, 397, 398, 399, 400,
    };
}
void c_vector_32_f32(Vector_32_f32 v, size_t i) {
    assert_or_panic(v[0] == 401);
    assert_or_panic(v[1] == 402);
    assert_or_panic(v[2] == 403);
    assert_or_panic(v[3] == 404);
    assert_or_panic(v[4] == 405);
    assert_or_panic(v[5] == 406);
    assert_or_panic(v[6] == 407);
    assert_or_panic(v[7] == 408);
    assert_or_panic(v[8] == 409);
    assert_or_panic(v[9] == 410);
    assert_or_panic(v[10] == 411);
    assert_or_panic(v[11] == 412);
    assert_or_panic(v[12] == 413);
    assert_or_panic(v[13] == 414);
    assert_or_panic(v[14] == 415);
    assert_or_panic(v[15] == 416);
    assert_or_panic(v[16] == 417);
    assert_or_panic(v[17] == 418);
    assert_or_panic(v[18] == 419);
    assert_or_panic(v[19] == 420);
    assert_or_panic(v[20] == 421);
    assert_or_panic(v[21] == 422);
    assert_or_panic(v[22] == 423);
    assert_or_panic(v[23] == 424);
    assert_or_panic(v[24] == 425);
    assert_or_panic(v[25] == 426);
    assert_or_panic(v[26] == 427);
    assert_or_panic(v[27] == 428);
    assert_or_panic(v[28] == 429);
    assert_or_panic(v[29] == 430);
    assert_or_panic(v[30] == 431);
    assert_or_panic(v[31] == 432);
    assert_or_panic(i == 32);
}
void c_test_vector_32_f32(void) {
    Vector_32_f32 v = zig_ret_vector_32_f32();
    assert_or_panic(v[0] == 305);
    assert_or_panic(v[1] == 306);
    assert_or_panic(v[2] == 307);
    assert_or_panic(v[3] == 308);
    assert_or_panic(v[4] == 309);
    assert_or_panic(v[5] == 310);
    assert_or_panic(v[6] == 311);
    assert_or_panic(v[7] == 312);
    assert_or_panic(v[8] == 313);
    assert_or_panic(v[9] == 314);
    assert_or_panic(v[10] == 315);
    assert_or_panic(v[11] == 316);
    assert_or_panic(v[12] == 317);
    assert_or_panic(v[13] == 318);
    assert_or_panic(v[14] == 319);
    assert_or_panic(v[15] == 320);
    assert_or_panic(v[16] == 321);
    assert_or_panic(v[17] == 322);
    assert_or_panic(v[18] == 323);
    assert_or_panic(v[19] == 324);
    assert_or_panic(v[20] == 325);
    assert_or_panic(v[21] == 326);
    assert_or_panic(v[22] == 327);
    assert_or_panic(v[23] == 328);
    assert_or_panic(v[24] == 329);
    assert_or_panic(v[25] == 330);
    assert_or_panic(v[26] == 331);
    assert_or_panic(v[27] == 332);
    assert_or_panic(v[28] == 333);
    assert_or_panic(v[29] == 334);
    assert_or_panic(v[30] == 335);
    assert_or_panic(v[31] == 336);
    zig_vector_32_f32((Vector_32_f32){
        337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351, 352,
        353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368,
    }, 32);
}

typedef float Vector_48_f32 __attribute__((vector_size(48 * sizeof(float))));

Vector_48_f32 zig_ret_vector_48_f32(void);
void zig_vector_48_f32(Vector_48_f32, size_t);

Vector_48_f32 c_ret_vector_48_f32(void) {
    return (Vector_48_f32){
        529, 530, 531, 532, 533, 534, 535, 536, 537, 538, 539, 540, 541, 542, 543, 544,
        545, 546, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 560,
        561, 562, 563, 564, 565, 566, 567, 568, 569, 570, 571, 572, 573, 574, 575, 576,
    };
}
void c_vector_48_f32(Vector_48_f32 v, size_t i) {
    assert_or_panic(v[0] == 577);
    assert_or_panic(v[1] == 578);
    assert_or_panic(v[2] == 579);
    assert_or_panic(v[3] == 580);
    assert_or_panic(v[4] == 581);
    assert_or_panic(v[5] == 582);
    assert_or_panic(v[6] == 583);
    assert_or_panic(v[7] == 584);
    assert_or_panic(v[8] == 585);
    assert_or_panic(v[9] == 586);
    assert_or_panic(v[10] == 587);
    assert_or_panic(v[11] == 588);
    assert_or_panic(v[12] == 589);
    assert_or_panic(v[13] == 590);
    assert_or_panic(v[14] == 591);
    assert_or_panic(v[15] == 592);
    assert_or_panic(v[16] == 593);
    assert_or_panic(v[17] == 594);
    assert_or_panic(v[18] == 595);
    assert_or_panic(v[19] == 596);
    assert_or_panic(v[20] == 597);
    assert_or_panic(v[21] == 598);
    assert_or_panic(v[22] == 599);
    assert_or_panic(v[23] == 600);
    assert_or_panic(v[24] == 601);
    assert_or_panic(v[25] == 602);
    assert_or_panic(v[26] == 603);
    assert_or_panic(v[27] == 604);
    assert_or_panic(v[28] == 605);
    assert_or_panic(v[29] == 606);
    assert_or_panic(v[30] == 607);
    assert_or_panic(v[31] == 608);
    assert_or_panic(v[32] == 609);
    assert_or_panic(v[33] == 610);
    assert_or_panic(v[34] == 611);
    assert_or_panic(v[35] == 612);
    assert_or_panic(v[36] == 613);
    assert_or_panic(v[37] == 614);
    assert_or_panic(v[38] == 615);
    assert_or_panic(v[39] == 616);
    assert_or_panic(v[40] == 617);
    assert_or_panic(v[41] == 618);
    assert_or_panic(v[42] == 619);
    assert_or_panic(v[43] == 620);
    assert_or_panic(v[44] == 621);
    assert_or_panic(v[45] == 622);
    assert_or_panic(v[46] == 623);
    assert_or_panic(v[47] == 624);
    assert_or_panic(i == 48);
}
void c_test_vector_48_f32(void) {
    Vector_48_f32 v = zig_ret_vector_48_f32();
    assert_or_panic(v[0] == 433);
    assert_or_panic(v[1] == 434);
    assert_or_panic(v[2] == 435);
    assert_or_panic(v[3] == 436);
    assert_or_panic(v[4] == 437);
    assert_or_panic(v[5] == 438);
    assert_or_panic(v[6] == 439);
    assert_or_panic(v[7] == 440);
    assert_or_panic(v[8] == 441);
    assert_or_panic(v[9] == 442);
    assert_or_panic(v[10] == 443);
    assert_or_panic(v[11] == 444);
    assert_or_panic(v[12] == 445);
    assert_or_panic(v[13] == 446);
    assert_or_panic(v[14] == 447);
    assert_or_panic(v[15] == 448);
    assert_or_panic(v[16] == 449);
    assert_or_panic(v[17] == 450);
    assert_or_panic(v[18] == 451);
    assert_or_panic(v[19] == 452);
    assert_or_panic(v[20] == 453);
    assert_or_panic(v[21] == 454);
    assert_or_panic(v[22] == 455);
    assert_or_panic(v[23] == 456);
    assert_or_panic(v[24] == 457);
    assert_or_panic(v[25] == 458);
    assert_or_panic(v[26] == 459);
    assert_or_panic(v[27] == 460);
    assert_or_panic(v[28] == 461);
    assert_or_panic(v[29] == 462);
    assert_or_panic(v[30] == 463);
    assert_or_panic(v[31] == 464);
    assert_or_panic(v[32] == 465);
    assert_or_panic(v[33] == 466);
    assert_or_panic(v[34] == 467);
    assert_or_panic(v[35] == 468);
    assert_or_panic(v[36] == 469);
    assert_or_panic(v[37] == 470);
    assert_or_panic(v[38] == 471);
    assert_or_panic(v[39] == 472);
    assert_or_panic(v[40] == 473);
    assert_or_panic(v[41] == 474);
    assert_or_panic(v[42] == 475);
    assert_or_panic(v[43] == 476);
    assert_or_panic(v[44] == 477);
    assert_or_panic(v[45] == 478);
    assert_or_panic(v[46] == 479);
    assert_or_panic(v[47] == 480);
    zig_vector_48_f32((Vector_48_f32){
        481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496,
        497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512,
        513, 514, 515, 516, 517, 518, 519, 520, 521, 522, 523, 524, 525, 526, 527, 528,
    }, 48);
}

typedef float Vector_64_f32 __attribute__((vector_size(64 * sizeof(float))));

Vector_64_f32 zig_ret_vector_64_f32(void);
void zig_vector_64_f32(Vector_64_f32, size_t);

Vector_64_f32 c_ret_vector_64_f32(void) {
    return (Vector_64_f32){
        753, 754, 755, 756, 757, 758, 759, 760, 761, 762, 763, 764, 765, 766, 767, 768,
        769, 770, 771, 772, 773, 774, 775, 776, 777, 778, 779, 780, 781, 782, 783, 784,
        785, 786, 787, 788, 789, 790, 791, 792, 793, 794, 795, 796, 797, 798, 799, 800,
        801, 802, 803, 804, 805, 806, 807, 808, 809, 810, 811, 812, 813, 814, 815, 816,
    };
}
void c_vector_64_f32(Vector_64_f32 v, size_t i) {
    assert_or_panic(v[0] == 817);
    assert_or_panic(v[1] == 818);
    assert_or_panic(v[2] == 819);
    assert_or_panic(v[3] == 820);
    assert_or_panic(v[4] == 821);
    assert_or_panic(v[5] == 822);
    assert_or_panic(v[6] == 823);
    assert_or_panic(v[7] == 824);
    assert_or_panic(v[8] == 825);
    assert_or_panic(v[9] == 826);
    assert_or_panic(v[10] == 827);
    assert_or_panic(v[11] == 828);
    assert_or_panic(v[12] == 829);
    assert_or_panic(v[13] == 830);
    assert_or_panic(v[14] == 831);
    assert_or_panic(v[15] == 832);
    assert_or_panic(v[16] == 833);
    assert_or_panic(v[17] == 834);
    assert_or_panic(v[18] == 835);
    assert_or_panic(v[19] == 836);
    assert_or_panic(v[20] == 837);
    assert_or_panic(v[21] == 838);
    assert_or_panic(v[22] == 839);
    assert_or_panic(v[23] == 840);
    assert_or_panic(v[24] == 841);
    assert_or_panic(v[25] == 842);
    assert_or_panic(v[26] == 843);
    assert_or_panic(v[27] == 844);
    assert_or_panic(v[28] == 845);
    assert_or_panic(v[29] == 846);
    assert_or_panic(v[30] == 847);
    assert_or_panic(v[31] == 848);
    assert_or_panic(v[32] == 849);
    assert_or_panic(v[33] == 850);
    assert_or_panic(v[34] == 851);
    assert_or_panic(v[35] == 852);
    assert_or_panic(v[36] == 853);
    assert_or_panic(v[37] == 854);
    assert_or_panic(v[38] == 855);
    assert_or_panic(v[39] == 856);
    assert_or_panic(v[40] == 857);
    assert_or_panic(v[41] == 858);
    assert_or_panic(v[42] == 859);
    assert_or_panic(v[43] == 860);
    assert_or_panic(v[44] == 861);
    assert_or_panic(v[45] == 862);
    assert_or_panic(v[46] == 863);
    assert_or_panic(v[47] == 864);
    assert_or_panic(v[48] == 865);
    assert_or_panic(v[49] == 866);
    assert_or_panic(v[50] == 867);
    assert_or_panic(v[51] == 868);
    assert_or_panic(v[52] == 869);
    assert_or_panic(v[53] == 870);
    assert_or_panic(v[54] == 871);
    assert_or_panic(v[55] == 872);
    assert_or_panic(v[56] == 873);
    assert_or_panic(v[57] == 874);
    assert_or_panic(v[58] == 875);
    assert_or_panic(v[59] == 876);
    assert_or_panic(v[60] == 877);
    assert_or_panic(v[61] == 878);
    assert_or_panic(v[62] == 879);
    assert_or_panic(v[63] == 880);
    assert_or_panic(i == 64);
}
void c_test_vector_64_f32(void) {
    Vector_64_f32 v = zig_ret_vector_64_f32();
    assert_or_panic(v[0] == 625);
    assert_or_panic(v[1] == 626);
    assert_or_panic(v[2] == 627);
    assert_or_panic(v[3] == 628);
    assert_or_panic(v[4] == 629);
    assert_or_panic(v[5] == 630);
    assert_or_panic(v[6] == 631);
    assert_or_panic(v[7] == 632);
    assert_or_panic(v[8] == 633);
    assert_or_panic(v[9] == 634);
    assert_or_panic(v[10] == 635);
    assert_or_panic(v[11] == 636);
    assert_or_panic(v[12] == 637);
    assert_or_panic(v[13] == 638);
    assert_or_panic(v[14] == 639);
    assert_or_panic(v[15] == 640);
    assert_or_panic(v[16] == 641);
    assert_or_panic(v[17] == 642);
    assert_or_panic(v[18] == 643);
    assert_or_panic(v[19] == 644);
    assert_or_panic(v[20] == 645);
    assert_or_panic(v[21] == 646);
    assert_or_panic(v[22] == 647);
    assert_or_panic(v[23] == 648);
    assert_or_panic(v[24] == 649);
    assert_or_panic(v[25] == 650);
    assert_or_panic(v[26] == 651);
    assert_or_panic(v[27] == 652);
    assert_or_panic(v[28] == 653);
    assert_or_panic(v[29] == 654);
    assert_or_panic(v[30] == 655);
    assert_or_panic(v[31] == 656);
    assert_or_panic(v[32] == 657);
    assert_or_panic(v[33] == 658);
    assert_or_panic(v[34] == 659);
    assert_or_panic(v[35] == 660);
    assert_or_panic(v[36] == 661);
    assert_or_panic(v[37] == 662);
    assert_or_panic(v[38] == 663);
    assert_or_panic(v[39] == 664);
    assert_or_panic(v[40] == 665);
    assert_or_panic(v[41] == 666);
    assert_or_panic(v[42] == 667);
    assert_or_panic(v[43] == 668);
    assert_or_panic(v[44] == 669);
    assert_or_panic(v[45] == 670);
    assert_or_panic(v[46] == 671);
    assert_or_panic(v[47] == 672);
    assert_or_panic(v[48] == 673);
    assert_or_panic(v[49] == 674);
    assert_or_panic(v[50] == 675);
    assert_or_panic(v[51] == 676);
    assert_or_panic(v[52] == 677);
    assert_or_panic(v[53] == 678);
    assert_or_panic(v[54] == 679);
    assert_or_panic(v[55] == 680);
    assert_or_panic(v[56] == 681);
    assert_or_panic(v[57] == 682);
    assert_or_panic(v[58] == 683);
    assert_or_panic(v[59] == 684);
    assert_or_panic(v[60] == 685);
    assert_or_panic(v[61] == 686);
    assert_or_panic(v[62] == 687);
    assert_or_panic(v[63] == 688);
    zig_vector_64_f32((Vector_64_f32){
        689, 690, 691, 692, 693, 694, 695, 696, 697, 698, 699, 700, 701, 702, 703, 704,
        705, 706, 707, 708, 709, 710, 711, 712, 713, 714, 715, 716, 717, 718, 719, 720,
        721, 722, 723, 724, 725, 726, 727, 728, 729, 730, 731, 732, 733, 734, 735, 736,
        737, 738, 739, 740, 741, 742, 743, 744, 745, 746, 747, 748, 749, 750, 751, 752,
    }, 64);
}

typedef float Vector_96_f32 __attribute__((vector_size(96 * sizeof(float))));

Vector_96_f32 zig_ret_vector_96_f32(void);
void zig_vector_96_f32(Vector_96_f32, size_t);

Vector_96_f32 c_ret_vector_96_f32(void) {
    return (Vector_96_f32){
        1082, 1083, 1084, 1085, 1086, 1087, 1088, 1089, 1090, 1091, 1092, 1093, 1094, 1095, 1096, 1097,
        1098, 1099, 1100, 1101, 1102, 1103, 1104, 1105, 1106, 1107, 1108, 1109, 1110, 1111, 1112, 1113,
        1114, 1115, 1116, 1117, 1118, 1119, 1120, 1121, 1122, 1123, 1124, 1125, 1126, 1127, 1128, 1129,
        1130, 1131, 1132, 1133, 1134, 1135, 1136, 1137, 1138, 1139, 1140, 1141, 1142, 1143, 1144, 1145,
        1146, 1147, 1148, 1149, 1150, 1151, 1152, 1153, 1154, 1155, 1156, 1157, 1158, 1159, 1160, 1161,
        1162, 1163, 1164, 1165, 1166, 1167, 1168, 1169, 1170, 1171, 1172, 1173, 1174, 1175, 1176, 1177,
    };
}
void c_vector_96_f32(Vector_96_f32 v, size_t i) {
    assert_or_panic(v[0] == 1178);
    assert_or_panic(v[1] == 1179);
    assert_or_panic(v[2] == 1180);
    assert_or_panic(v[3] == 1181);
    assert_or_panic(v[4] == 1182);
    assert_or_panic(v[5] == 1183);
    assert_or_panic(v[6] == 1184);
    assert_or_panic(v[7] == 1185);
    assert_or_panic(v[8] == 1186);
    assert_or_panic(v[9] == 1187);
    assert_or_panic(v[10] == 1188);
    assert_or_panic(v[11] == 1189);
    assert_or_panic(v[12] == 1190);
    assert_or_panic(v[13] == 1191);
    assert_or_panic(v[14] == 1192);
    assert_or_panic(v[15] == 1193);
    assert_or_panic(v[16] == 1194);
    assert_or_panic(v[17] == 1195);
    assert_or_panic(v[18] == 1196);
    assert_or_panic(v[19] == 1197);
    assert_or_panic(v[20] == 1198);
    assert_or_panic(v[21] == 1199);
    assert_or_panic(v[22] == 1200);
    assert_or_panic(v[23] == 1201);
    assert_or_panic(v[24] == 1202);
    assert_or_panic(v[25] == 1203);
    assert_or_panic(v[26] == 1204);
    assert_or_panic(v[27] == 1205);
    assert_or_panic(v[28] == 1206);
    assert_or_panic(v[29] == 1207);
    assert_or_panic(v[30] == 1208);
    assert_or_panic(v[31] == 1209);
    assert_or_panic(v[32] == 1210);
    assert_or_panic(v[33] == 1211);
    assert_or_panic(v[34] == 1212);
    assert_or_panic(v[35] == 1213);
    assert_or_panic(v[36] == 1214);
    assert_or_panic(v[37] == 1215);
    assert_or_panic(v[38] == 1216);
    assert_or_panic(v[39] == 1217);
    assert_or_panic(v[40] == 1218);
    assert_or_panic(v[41] == 1219);
    assert_or_panic(v[42] == 1220);
    assert_or_panic(v[43] == 1221);
    assert_or_panic(v[44] == 1222);
    assert_or_panic(v[45] == 1223);
    assert_or_panic(v[46] == 1224);
    assert_or_panic(v[47] == 1225);
    assert_or_panic(v[48] == 1226);
    assert_or_panic(v[49] == 1227);
    assert_or_panic(v[50] == 1228);
    assert_or_panic(v[51] == 1229);
    assert_or_panic(v[52] == 1230);
    assert_or_panic(v[53] == 1231);
    assert_or_panic(v[54] == 1232);
    assert_or_panic(v[55] == 1233);
    assert_or_panic(v[56] == 1234);
    assert_or_panic(v[57] == 1235);
    assert_or_panic(v[58] == 1236);
    assert_or_panic(v[59] == 1237);
    assert_or_panic(v[60] == 1238);
    assert_or_panic(v[61] == 1239);
    assert_or_panic(v[62] == 1240);
    assert_or_panic(v[63] == 1241);
    assert_or_panic(v[64] == 1242);
    assert_or_panic(v[65] == 1243);
    assert_or_panic(v[66] == 1244);
    assert_or_panic(v[67] == 1245);
    assert_or_panic(v[68] == 1246);
    assert_or_panic(v[69] == 1247);
    assert_or_panic(v[70] == 1248);
    assert_or_panic(v[71] == 1249);
    assert_or_panic(v[72] == 1250);
    assert_or_panic(v[73] == 1251);
    assert_or_panic(v[74] == 1252);
    assert_or_panic(v[75] == 1253);
    assert_or_panic(v[76] == 1254);
    assert_or_panic(v[77] == 1255);
    assert_or_panic(v[80] == 1258);
    assert_or_panic(v[81] == 1259);
    assert_or_panic(v[82] == 1260);
    assert_or_panic(v[83] == 1261);
    assert_or_panic(v[84] == 1262);
    assert_or_panic(v[85] == 1263);
    assert_or_panic(v[86] == 1264);
    assert_or_panic(v[87] == 1265);
    assert_or_panic(v[88] == 1266);
    assert_or_panic(v[89] == 1267);
    assert_or_panic(v[90] == 1268);
    assert_or_panic(v[91] == 1269);
    assert_or_panic(v[92] == 1270);
    assert_or_panic(v[93] == 1271);
    assert_or_panic(v[94] == 1272);
    assert_or_panic(v[95] == 1273);
    assert_or_panic(i == 96);
}
void c_test_vector_96_f32(void) {
    Vector_96_f32 v = zig_ret_vector_96_f32();
    assert_or_panic(v[0] == 890);
    assert_or_panic(v[1] == 891);
    assert_or_panic(v[2] == 892);
    assert_or_panic(v[3] == 893);
    assert_or_panic(v[4] == 894);
    assert_or_panic(v[5] == 895);
    assert_or_panic(v[6] == 896);
    assert_or_panic(v[7] == 897);
    assert_or_panic(v[8] == 898);
    assert_or_panic(v[9] == 899);
    assert_or_panic(v[10] == 900);
    assert_or_panic(v[11] == 901);
    assert_or_panic(v[12] == 902);
    assert_or_panic(v[13] == 903);
    assert_or_panic(v[14] == 904);
    assert_or_panic(v[15] == 905);
    assert_or_panic(v[16] == 906);
    assert_or_panic(v[17] == 907);
    assert_or_panic(v[18] == 908);
    assert_or_panic(v[19] == 909);
    assert_or_panic(v[20] == 910);
    assert_or_panic(v[21] == 911);
    assert_or_panic(v[22] == 912);
    assert_or_panic(v[23] == 913);
    assert_or_panic(v[24] == 914);
    assert_or_panic(v[25] == 915);
    assert_or_panic(v[26] == 916);
    assert_or_panic(v[27] == 917);
    assert_or_panic(v[28] == 918);
    assert_or_panic(v[29] == 919);
    assert_or_panic(v[30] == 920);
    assert_or_panic(v[31] == 921);
    assert_or_panic(v[32] == 922);
    assert_or_panic(v[33] == 923);
    assert_or_panic(v[34] == 924);
    assert_or_panic(v[35] == 925);
    assert_or_panic(v[36] == 926);
    assert_or_panic(v[37] == 927);
    assert_or_panic(v[38] == 928);
    assert_or_panic(v[39] == 929);
    assert_or_panic(v[40] == 930);
    assert_or_panic(v[41] == 931);
    assert_or_panic(v[42] == 932);
    assert_or_panic(v[43] == 933);
    assert_or_panic(v[44] == 934);
    assert_or_panic(v[45] == 935);
    assert_or_panic(v[46] == 936);
    assert_or_panic(v[47] == 937);
    assert_or_panic(v[48] == 938);
    assert_or_panic(v[49] == 939);
    assert_or_panic(v[50] == 940);
    assert_or_panic(v[51] == 941);
    assert_or_panic(v[52] == 942);
    assert_or_panic(v[53] == 943);
    assert_or_panic(v[54] == 944);
    assert_or_panic(v[55] == 945);
    assert_or_panic(v[56] == 946);
    assert_or_panic(v[57] == 947);
    assert_or_panic(v[58] == 948);
    assert_or_panic(v[59] == 949);
    assert_or_panic(v[60] == 950);
    assert_or_panic(v[61] == 951);
    assert_or_panic(v[62] == 952);
    assert_or_panic(v[63] == 953);
    assert_or_panic(v[64] == 954);
    assert_or_panic(v[65] == 955);
    assert_or_panic(v[66] == 956);
    assert_or_panic(v[67] == 957);
    assert_or_panic(v[68] == 958);
    assert_or_panic(v[69] == 959);
    assert_or_panic(v[70] == 960);
    assert_or_panic(v[71] == 961);
    assert_or_panic(v[72] == 962);
    assert_or_panic(v[73] == 963);
    assert_or_panic(v[74] == 964);
    assert_or_panic(v[75] == 965);
    assert_or_panic(v[76] == 966);
    assert_or_panic(v[77] == 967);
    assert_or_panic(v[78] == 968);
    assert_or_panic(v[79] == 969);
    assert_or_panic(v[80] == 970);
    assert_or_panic(v[81] == 971);
    assert_or_panic(v[82] == 972);
    assert_or_panic(v[83] == 973);
    assert_or_panic(v[84] == 974);
    assert_or_panic(v[85] == 975);
    assert_or_panic(v[86] == 976);
    assert_or_panic(v[87] == 977);
    assert_or_panic(v[88] == 978);
    assert_or_panic(v[89] == 979);
    assert_or_panic(v[90] == 980);
    assert_or_panic(v[91] == 981);
    assert_or_panic(v[92] == 982);
    assert_or_panic(v[93] == 983);
    assert_or_panic(v[94] == 984);
    assert_or_panic(v[95] == 985);
    zig_vector_96_f32((Vector_96_f32){
        986,  987,  988,  989,  990,  991,  992,  993,  994,  995,  996,  997,  998,  999,  1000, 1001,
        1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010, 1011, 1012, 1013, 1014, 1015, 1016, 1017,
        1018, 1019, 1020, 1021, 1022, 1023, 1024, 1025, 1026, 1027, 1028, 1029, 1030, 1031, 1032, 1033,
        1034, 1035, 1036, 1037, 1038, 1039, 1040, 1041, 1042, 1043, 1044, 1045, 1046, 1047, 1048, 1049,
        1050, 1051, 1052, 1053, 1054, 1055, 1056, 1057, 1058, 1059, 1060, 1061, 1062, 1063, 1064, 1065,
        1066, 1067, 1068, 1069, 1070, 1071, 1072, 1073, 1074, 1075, 1076, 1077, 1078, 1079, 1080, 1081,
    }, 96);
}

typedef float Vector_128_f32 __attribute__((vector_size(128 * sizeof(float))));

Vector_128_f32 zig_ret_vector_128_f32(void);
void zig_vector_128_f32(Vector_128_f32, size_t);

Vector_128_f32 c_ret_vector_128_f32(void) {
    return (Vector_128_f32){
        1530, 1531, 1532, 1533, 1534, 1535, 1536, 1537, 1538, 1539, 1540, 1541, 1542, 1543, 1544, 1545,
        1546, 1547, 1548, 1549, 1550, 1551, 1552, 1553, 1554, 1555, 1556, 1557, 1558, 1559, 1560, 1561,
        1562, 1563, 1564, 1565, 1566, 1567, 1568, 1569, 1570, 1571, 1572, 1573, 1574, 1575, 1576, 1577,
        1578, 1579, 1580, 1581, 1582, 1583, 1584, 1585, 1586, 1587, 1588, 1589, 1590, 1591, 1592, 1593,
        1594, 1595, 1596, 1597, 1598, 1599, 1600, 1601, 1602, 1603, 1604, 1605, 1606, 1607, 1608, 1609,
        1610, 1611, 1612, 1613, 1614, 1615, 1616, 1617, 1618, 1619, 1620, 1621, 1622, 1623, 1624, 1625,
        1626, 1627, 1628, 1629, 1630, 1631, 1632, 1633, 1634, 1635, 1636, 1637, 1638, 1639, 1640, 1641,
        1642, 1643, 1644, 1645, 1646, 1647, 1648, 1649, 1650, 1651, 1652, 1653, 1654, 1655, 1656, 1657,
    };
}
void c_vector_128_f32(Vector_128_f32 v, size_t i) {
    assert_or_panic(v[0] == 1658);
    assert_or_panic(v[1] == 1659);
    assert_or_panic(v[2] == 1660);
    assert_or_panic(v[3] == 1661);
    assert_or_panic(v[4] == 1662);
    assert_or_panic(v[5] == 1663);
    assert_or_panic(v[6] == 1664);
    assert_or_panic(v[7] == 1665);
    assert_or_panic(v[8] == 1666);
    assert_or_panic(v[9] == 1667);
    assert_or_panic(v[10] == 1668);
    assert_or_panic(v[11] == 1669);
    assert_or_panic(v[12] == 1670);
    assert_or_panic(v[13] == 1671);
    assert_or_panic(v[14] == 1672);
    assert_or_panic(v[15] == 1673);
    assert_or_panic(v[16] == 1674);
    assert_or_panic(v[17] == 1675);
    assert_or_panic(v[18] == 1676);
    assert_or_panic(v[19] == 1677);
    assert_or_panic(v[20] == 1678);
    assert_or_panic(v[21] == 1679);
    assert_or_panic(v[22] == 1680);
    assert_or_panic(v[23] == 1681);
    assert_or_panic(v[24] == 1682);
    assert_or_panic(v[25] == 1683);
    assert_or_panic(v[26] == 1684);
    assert_or_panic(v[27] == 1685);
    assert_or_panic(v[28] == 1686);
    assert_or_panic(v[29] == 1687);
    assert_or_panic(v[30] == 1688);
    assert_or_panic(v[31] == 1689);
    assert_or_panic(v[32] == 1690);
    assert_or_panic(v[33] == 1691);
    assert_or_panic(v[34] == 1692);
    assert_or_panic(v[35] == 1693);
    assert_or_panic(v[36] == 1694);
    assert_or_panic(v[37] == 1695);
    assert_or_panic(v[38] == 1696);
    assert_or_panic(v[39] == 1697);
    assert_or_panic(v[40] == 1698);
    assert_or_panic(v[41] == 1699);
    assert_or_panic(v[42] == 1700);
    assert_or_panic(v[43] == 1701);
    assert_or_panic(v[44] == 1702);
    assert_or_panic(v[45] == 1703);
    assert_or_panic(v[46] == 1704);
    assert_or_panic(v[47] == 1705);
    assert_or_panic(v[48] == 1706);
    assert_or_panic(v[49] == 1707);
    assert_or_panic(v[50] == 1708);
    assert_or_panic(v[51] == 1709);
    assert_or_panic(v[52] == 1710);
    assert_or_panic(v[53] == 1711);
    assert_or_panic(v[54] == 1712);
    assert_or_panic(v[55] == 1713);
    assert_or_panic(v[56] == 1714);
    assert_or_panic(v[57] == 1715);
    assert_or_panic(v[58] == 1716);
    assert_or_panic(v[59] == 1717);
    assert_or_panic(v[60] == 1718);
    assert_or_panic(v[61] == 1719);
    assert_or_panic(v[62] == 1720);
    assert_or_panic(v[63] == 1721);
    assert_or_panic(v[64] == 1722);
    assert_or_panic(v[65] == 1723);
    assert_or_panic(v[66] == 1724);
    assert_or_panic(v[67] == 1725);
    assert_or_panic(v[68] == 1726);
    assert_or_panic(v[69] == 1727);
    assert_or_panic(v[70] == 1728);
    assert_or_panic(v[71] == 1729);
    assert_or_panic(v[72] == 1730);
    assert_or_panic(v[73] == 1731);
    assert_or_panic(v[74] == 1732);
    assert_or_panic(v[75] == 1733);
    assert_or_panic(v[76] == 1734);
    assert_or_panic(v[77] == 1735);
    assert_or_panic(v[78] == 1736);
    assert_or_panic(v[79] == 1737);
    assert_or_panic(v[80] == 1738);
    assert_or_panic(v[81] == 1739);
    assert_or_panic(v[82] == 1740);
    assert_or_panic(v[83] == 1741);
    assert_or_panic(v[84] == 1742);
    assert_or_panic(v[85] == 1743);
    assert_or_panic(v[86] == 1744);
    assert_or_panic(v[87] == 1745);
    assert_or_panic(v[88] == 1746);
    assert_or_panic(v[89] == 1747);
    assert_or_panic(v[90] == 1748);
    assert_or_panic(v[91] == 1749);
    assert_or_panic(v[92] == 1750);
    assert_or_panic(v[93] == 1751);
    assert_or_panic(v[94] == 1752);
    assert_or_panic(v[95] == 1753);
    assert_or_panic(v[96] == 1754);
    assert_or_panic(v[97] == 1755);
    assert_or_panic(v[98] == 1756);
    assert_or_panic(v[99] == 1757);
    assert_or_panic(v[100] == 1758);
    assert_or_panic(v[101] == 1759);
    assert_or_panic(v[102] == 1760);
    assert_or_panic(v[103] == 1761);
    assert_or_panic(v[104] == 1762);
    assert_or_panic(v[105] == 1763);
    assert_or_panic(v[106] == 1764);
    assert_or_panic(v[107] == 1765);
    assert_or_panic(v[108] == 1766);
    assert_or_panic(v[109] == 1767);
    assert_or_panic(v[110] == 1768);
    assert_or_panic(v[111] == 1769);
    assert_or_panic(v[112] == 1770);
    assert_or_panic(v[113] == 1771);
    assert_or_panic(v[114] == 1772);
    assert_or_panic(v[115] == 1773);
    assert_or_panic(v[116] == 1774);
    assert_or_panic(v[117] == 1775);
    assert_or_panic(v[118] == 1776);
    assert_or_panic(v[119] == 1777);
    assert_or_panic(v[120] == 1778);
    assert_or_panic(v[121] == 1779);
    assert_or_panic(v[122] == 1780);
    assert_or_panic(v[123] == 1781);
    assert_or_panic(v[124] == 1782);
    assert_or_panic(v[125] == 1783);
    assert_or_panic(v[126] == 1784);
    assert_or_panic(v[127] == 1785);
    assert_or_panic(i == 128);
}
void c_test_vector_128_f32(void) {
    Vector_128_f32 v = zig_ret_vector_128_f32();
    assert_or_panic(v[0] == 1274);
    assert_or_panic(v[1] == 1275);
    assert_or_panic(v[2] == 1276);
    assert_or_panic(v[3] == 1277);
    assert_or_panic(v[4] == 1278);
    assert_or_panic(v[5] == 1279);
    assert_or_panic(v[6] == 1280);
    assert_or_panic(v[7] == 1281);
    assert_or_panic(v[8] == 1282);
    assert_or_panic(v[9] == 1283);
    assert_or_panic(v[10] == 1284);
    assert_or_panic(v[11] == 1285);
    assert_or_panic(v[12] == 1286);
    assert_or_panic(v[13] == 1287);
    assert_or_panic(v[14] == 1288);
    assert_or_panic(v[15] == 1289);
    assert_or_panic(v[16] == 1290);
    assert_or_panic(v[17] == 1291);
    assert_or_panic(v[18] == 1292);
    assert_or_panic(v[19] == 1293);
    assert_or_panic(v[20] == 1294);
    assert_or_panic(v[21] == 1295);
    assert_or_panic(v[22] == 1296);
    assert_or_panic(v[23] == 1297);
    assert_or_panic(v[24] == 1298);
    assert_or_panic(v[25] == 1299);
    assert_or_panic(v[26] == 1300);
    assert_or_panic(v[27] == 1301);
    assert_or_panic(v[28] == 1302);
    assert_or_panic(v[29] == 1303);
    assert_or_panic(v[30] == 1304);
    assert_or_panic(v[31] == 1305);
    assert_or_panic(v[32] == 1306);
    assert_or_panic(v[33] == 1307);
    assert_or_panic(v[34] == 1308);
    assert_or_panic(v[35] == 1309);
    assert_or_panic(v[36] == 1310);
    assert_or_panic(v[37] == 1311);
    assert_or_panic(v[38] == 1312);
    assert_or_panic(v[39] == 1313);
    assert_or_panic(v[40] == 1314);
    assert_or_panic(v[41] == 1315);
    assert_or_panic(v[42] == 1316);
    assert_or_panic(v[43] == 1317);
    assert_or_panic(v[44] == 1318);
    assert_or_panic(v[45] == 1319);
    assert_or_panic(v[46] == 1320);
    assert_or_panic(v[47] == 1321);
    assert_or_panic(v[48] == 1322);
    assert_or_panic(v[49] == 1323);
    assert_or_panic(v[50] == 1324);
    assert_or_panic(v[51] == 1325);
    assert_or_panic(v[52] == 1326);
    assert_or_panic(v[53] == 1327);
    assert_or_panic(v[54] == 1328);
    assert_or_panic(v[55] == 1329);
    assert_or_panic(v[56] == 1330);
    assert_or_panic(v[57] == 1331);
    assert_or_panic(v[58] == 1332);
    assert_or_panic(v[59] == 1333);
    assert_or_panic(v[60] == 1334);
    assert_or_panic(v[61] == 1335);
    assert_or_panic(v[62] == 1336);
    assert_or_panic(v[63] == 1337);
    assert_or_panic(v[64] == 1338);
    assert_or_panic(v[65] == 1339);
    assert_or_panic(v[66] == 1340);
    assert_or_panic(v[67] == 1341);
    assert_or_panic(v[68] == 1342);
    assert_or_panic(v[69] == 1343);
    assert_or_panic(v[70] == 1344);
    assert_or_panic(v[71] == 1345);
    assert_or_panic(v[72] == 1346);
    assert_or_panic(v[73] == 1347);
    assert_or_panic(v[74] == 1348);
    assert_or_panic(v[75] == 1349);
    assert_or_panic(v[76] == 1350);
    assert_or_panic(v[77] == 1351);
    assert_or_panic(v[78] == 1352);
    assert_or_panic(v[79] == 1353);
    assert_or_panic(v[80] == 1354);
    assert_or_panic(v[81] == 1355);
    assert_or_panic(v[82] == 1356);
    assert_or_panic(v[83] == 1357);
    assert_or_panic(v[84] == 1358);
    assert_or_panic(v[85] == 1359);
    assert_or_panic(v[86] == 1360);
    assert_or_panic(v[87] == 1361);
    assert_or_panic(v[88] == 1362);
    assert_or_panic(v[89] == 1363);
    assert_or_panic(v[90] == 1364);
    assert_or_panic(v[91] == 1365);
    assert_or_panic(v[92] == 1366);
    assert_or_panic(v[93] == 1367);
    assert_or_panic(v[94] == 1368);
    assert_or_panic(v[95] == 1369);
    assert_or_panic(v[96] == 1370);
    assert_or_panic(v[97] == 1371);
    assert_or_panic(v[98] == 1372);
    assert_or_panic(v[99] == 1373);
    assert_or_panic(v[100] == 1374);
    assert_or_panic(v[101] == 1375);
    assert_or_panic(v[102] == 1376);
    assert_or_panic(v[103] == 1377);
    assert_or_panic(v[104] == 1378);
    assert_or_panic(v[105] == 1379);
    assert_or_panic(v[106] == 1380);
    assert_or_panic(v[107] == 1381);
    assert_or_panic(v[108] == 1382);
    assert_or_panic(v[109] == 1383);
    assert_or_panic(v[110] == 1384);
    assert_or_panic(v[111] == 1385);
    assert_or_panic(v[112] == 1386);
    assert_or_panic(v[113] == 1387);
    assert_or_panic(v[114] == 1388);
    assert_or_panic(v[115] == 1389);
    assert_or_panic(v[116] == 1390);
    assert_or_panic(v[117] == 1391);
    assert_or_panic(v[118] == 1392);
    assert_or_panic(v[119] == 1393);
    assert_or_panic(v[120] == 1394);
    assert_or_panic(v[121] == 1395);
    assert_or_panic(v[122] == 1396);
    assert_or_panic(v[123] == 1397);
    assert_or_panic(v[124] == 1398);
    assert_or_panic(v[125] == 1399);
    assert_or_panic(v[126] == 1400);
    assert_or_panic(v[127] == 1401);
    zig_vector_128_f32((Vector_128_f32){
        1402, 1403, 1404, 1405, 1406, 1407, 1408, 1409, 1410, 1411, 1412, 1413, 1414, 1415, 1416, 1417,
        1418, 1419, 1420, 1421, 1422, 1423, 1424, 1425, 1426, 1427, 1428, 1429, 1430, 1431, 1432, 1433,
        1434, 1435, 1436, 1437, 1438, 1439, 1440, 1441, 1442, 1443, 1444, 1445, 1446, 1447, 1448, 1449,
        1450, 1451, 1452, 1453, 1454, 1455, 1456, 1457, 1458, 1459, 1460, 1461, 1462, 1463, 1464, 1465,
        1466, 1467, 1468, 1469, 1470, 1471, 1472, 1473, 1474, 1475, 1476, 1477, 1478, 1479, 1480, 1481,
        1482, 1483, 1484, 1485, 1486, 1487, 1488, 1489, 1490, 1491, 1492, 1493, 1494, 1495, 1496, 1497,
        1498, 1499, 1500, 1501, 1502, 1503, 1504, 1505, 1506, 1507, 1508, 1509, 1510, 1511, 1512, 1513,
        1514, 1515, 1516, 1517, 1518, 1519, 1520, 1521, 1522, 1523, 1524, 1525, 1526, 1527, 1528, 1529,
    }, 128);
}

typedef double Vector_1_f64 __attribute__((vector_size(1 * sizeof(double))));

Vector_1_f64 zig_ret_vector_1_f64(void);
void zig_vector_1_f64(Vector_1_f64, size_t);

Vector_1_f64 c_ret_vector_1_f64(void) {
    return (Vector_1_f64){ 3 };
}
void c_vector_1_f64(Vector_1_f64 v, size_t i) {
    assert_or_panic(v[0] == 4);
    assert_or_panic(i == 1);
}
void c_test_vector_1_f64(void) {
    Vector_1_f64 v = zig_ret_vector_1_f64();
    assert_or_panic(v[0] == 1);
    zig_vector_1_f64((Vector_1_f64){ 2 }, 1);
}

typedef double Vector_2_f64 __attribute__((vector_size(2 * sizeof(double))));

Vector_2_f64 zig_ret_vector_2_f64(void);
void zig_vector_2_f64(Vector_2_f64, size_t);

Vector_2_f64 c_ret_vector_2_f64(void) {
    return (Vector_2_f64){ 9, 10 };
}
void c_vector_2_f64(Vector_2_f64 v, size_t i) {
    assert_or_panic(v[0] == 11);
    assert_or_panic(v[1] == 12);
    assert_or_panic(i == 2);
}
void c_test_vector_2_f64(void) {
    Vector_2_f64 v = zig_ret_vector_2_f64();
    assert_or_panic(v[0] == 5);
    assert_or_panic(v[1] == 6);
    zig_vector_2_f64((Vector_2_f64){ 7, 8 }, 2);
}

typedef double Vector_3_f64 __attribute__((vector_size(3 * sizeof(double))));

Vector_3_f64 zig_ret_vector_3_f64(void);
void zig_vector_3_f64(Vector_3_f64, size_t);

Vector_3_f64 c_ret_vector_3_f64(void) {
    return (Vector_3_f64){ 19, 20, 21 };
}
void c_vector_3_f64(Vector_3_f64 v, size_t i) {
    assert_or_panic(v[0] == 22);
    assert_or_panic(v[1] == 23);
    assert_or_panic(v[2] == 24);
    assert_or_panic(i == 3);
}
void c_test_vector_3_f64(void) {
    Vector_3_f64 v = zig_ret_vector_3_f64();
    assert_or_panic(v[0] == 13);
    assert_or_panic(v[1] == 14);
    assert_or_panic(v[2] == 15);
    zig_vector_3_f64((Vector_3_f64){ 16, 17, 18 }, 3);
}

typedef double Vector_4_f64 __attribute__((vector_size(4 * sizeof(double))));

Vector_4_f64 zig_ret_vector_4_f64(void);
void zig_vector_4_f64(Vector_4_f64, size_t);

Vector_4_f64 c_ret_vector_4_f64(void) {
    return (Vector_4_f64){ 33, 34, 35, 36 };
}
void c_vector_4_f64(Vector_4_f64 v, size_t i) {
    assert_or_panic(v[0] == 37);
    assert_or_panic(v[1] == 38);
    assert_or_panic(v[2] == 39);
    assert_or_panic(v[3] == 40);
    assert_or_panic(i == 4);
}
void c_test_vector_4_f64(void) {
    Vector_4_f64 v = zig_ret_vector_4_f64();
    assert_or_panic(v[0] == 25);
    assert_or_panic(v[1] == 26);
    assert_or_panic(v[2] == 27);
    assert_or_panic(v[3] == 28);
    zig_vector_4_f64((Vector_4_f64){ 29, 30, 31, 32 }, 4);
}

typedef double Vector_6_f64 __attribute__((vector_size(6 * sizeof(double))));

Vector_6_f64 zig_ret_vector_6_f64(void);
void zig_vector_6_f64(Vector_6_f64, size_t);

Vector_6_f64 c_ret_vector_6_f64(void) {
    return (Vector_6_f64){ 53, 54, 55, 56, 57, 58 };
}
void c_vector_6_f64(Vector_6_f64 v, size_t i) {
    assert_or_panic(v[0] == 59);
    assert_or_panic(v[1] == 60);
    assert_or_panic(v[2] == 61);
    assert_or_panic(v[3] == 62);
    assert_or_panic(v[4] == 63);
    assert_or_panic(v[5] == 64);
    assert_or_panic(i == 6);
}
void c_test_vector_6_f64(void) {
    Vector_6_f64 v = zig_ret_vector_6_f64();
    assert_or_panic(v[0] == 41);
    assert_or_panic(v[1] == 42);
    assert_or_panic(v[2] == 43);
    assert_or_panic(v[3] == 44);
    assert_or_panic(v[4] == 45);
    assert_or_panic(v[5] == 46);
    zig_vector_6_f64((Vector_6_f64){ 47, 48, 49, 50, 51, 52 }, 6);
}

typedef double Vector_8_f64 __attribute__((vector_size(8 * sizeof(double))));

Vector_8_f64 zig_ret_vector_8_f64(void);
void zig_vector_8_f64(Vector_8_f64, size_t);

Vector_8_f64 c_ret_vector_8_f64(void) {
    return (Vector_8_f64){ 81, 82, 83, 84, 85, 86, 87, 88 };
}
void c_vector_8_f64(Vector_8_f64 v, size_t i) {
    assert_or_panic(v[0] == 89);
    assert_or_panic(v[1] == 90);
    assert_or_panic(v[2] == 91);
    assert_or_panic(v[3] == 92);
    assert_or_panic(v[4] == 93);
    assert_or_panic(v[5] == 94);
    assert_or_panic(v[6] == 95);
    assert_or_panic(v[7] == 96);
    assert_or_panic(i == 8);
}
void c_test_vector_8_f64(void) {
    Vector_8_f64 v = zig_ret_vector_8_f64();
    assert_or_panic(v[0] == 65);
    assert_or_panic(v[1] == 66);
    assert_or_panic(v[2] == 67);
    assert_or_panic(v[3] == 68);
    assert_or_panic(v[4] == 69);
    assert_or_panic(v[5] == 70);
    assert_or_panic(v[6] == 71);
    assert_or_panic(v[7] == 72);
    zig_vector_8_f64((Vector_8_f64){ 73, 74, 75, 76, 77, 78, 79, 80 }, 8);
}

typedef double Vector_12_f64 __attribute__((vector_size(12 * sizeof(double))));

Vector_12_f64 zig_ret_vector_12_f64(void);
void zig_vector_12_f64(Vector_12_f64, size_t);

Vector_12_f64 c_ret_vector_12_f64(void) {
    return (Vector_12_f64){ 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132 };
}
void c_vector_12_f64(Vector_12_f64 v, size_t i) {
    assert_or_panic(v[0] == 133);
    assert_or_panic(v[1] == 134);
    assert_or_panic(v[2] == 135);
    assert_or_panic(v[3] == 136);
    assert_or_panic(v[4] == 137);
    assert_or_panic(v[5] == 138);
    assert_or_panic(v[6] == 139);
    assert_or_panic(v[7] == 140);
    assert_or_panic(v[8] == 141);
    assert_or_panic(v[9] == 142);
    assert_or_panic(v[10] == 143);
    assert_or_panic(v[11] == 144);
    assert_or_panic(i == 12);
}
void c_test_vector_12_f64(void) {
    Vector_12_f64 v = zig_ret_vector_12_f64();
    assert_or_panic(v[0] == 97);
    assert_or_panic(v[1] == 98);
    assert_or_panic(v[2] == 99);
    assert_or_panic(v[3] == 100);
    assert_or_panic(v[4] == 101);
    assert_or_panic(v[5] == 102);
    assert_or_panic(v[6] == 103);
    assert_or_panic(v[7] == 104);
    assert_or_panic(v[8] == 105);
    assert_or_panic(v[9] == 106);
    assert_or_panic(v[10] == 107);
    assert_or_panic(v[11] == 108);
    zig_vector_12_f64((Vector_12_f64){ 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120 }, 12);
}

typedef double Vector_16_f64 __attribute__((vector_size(16 * sizeof(double))));

Vector_16_f64 zig_ret_vector_16_f64(void);
void zig_vector_16_f64(Vector_16_f64, size_t);

Vector_16_f64 c_ret_vector_16_f64(void) {
    return (Vector_16_f64){ 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192 };
}
void c_vector_16_f64(Vector_16_f64 v, size_t i) {
    assert_or_panic(v[0] == 193);
    assert_or_panic(v[1] == 194);
    assert_or_panic(v[2] == 195);
    assert_or_panic(v[3] == 196);
    assert_or_panic(v[4] == 197);
    assert_or_panic(v[5] == 198);
    assert_or_panic(v[6] == 199);
    assert_or_panic(v[7] == 200);
    assert_or_panic(v[8] == 201);
    assert_or_panic(v[9] == 202);
    assert_or_panic(v[10] == 203);
    assert_or_panic(v[11] == 204);
    assert_or_panic(v[12] == 205);
    assert_or_panic(v[13] == 206);
    assert_or_panic(v[14] == 207);
    assert_or_panic(v[15] == 208);
    assert_or_panic(i == 16);
}
void c_test_vector_16_f64(void) {
    Vector_16_f64 v = zig_ret_vector_16_f64();
    assert_or_panic(v[0] == 145);
    assert_or_panic(v[1] == 146);
    assert_or_panic(v[2] == 147);
    assert_or_panic(v[3] == 148);
    assert_or_panic(v[4] == 149);
    assert_or_panic(v[5] == 150);
    assert_or_panic(v[6] == 151);
    assert_or_panic(v[7] == 152);
    assert_or_panic(v[8] == 153);
    assert_or_panic(v[9] == 154);
    assert_or_panic(v[10] == 155);
    assert_or_panic(v[11] == 156);
    assert_or_panic(v[12] == 157);
    assert_or_panic(v[13] == 158);
    assert_or_panic(v[14] == 159);
    assert_or_panic(v[15] == 160);
    zig_vector_16_f64((Vector_16_f64){ 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176 }, 16);
}

typedef double Vector_24_f64 __attribute__((vector_size(24 * sizeof(double))));

Vector_24_f64 zig_ret_vector_24_f64(void);
void zig_vector_24_f64(Vector_24_f64, size_t);

Vector_24_f64 c_ret_vector_24_f64(void) {
    return (Vector_24_f64){
        257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272,
        273, 274, 275, 276, 277, 278, 279, 280,
    };
}
void c_vector_24_f64(Vector_24_f64 v, size_t i) {
    assert_or_panic(v[0] == 281);
    assert_or_panic(v[1] == 282);
    assert_or_panic(v[2] == 283);
    assert_or_panic(v[3] == 284);
    assert_or_panic(v[4] == 285);
    assert_or_panic(v[5] == 286);
    assert_or_panic(v[6] == 287);
    assert_or_panic(v[7] == 288);
    assert_or_panic(v[8] == 289);
    assert_or_panic(v[9] == 290);
    assert_or_panic(v[10] == 291);
    assert_or_panic(v[11] == 292);
    assert_or_panic(v[12] == 293);
    assert_or_panic(v[13] == 294);
    assert_or_panic(v[14] == 295);
    assert_or_panic(v[15] == 296);
    assert_or_panic(v[16] == 297);
    assert_or_panic(v[17] == 298);
    assert_or_panic(v[18] == 299);
    assert_or_panic(v[19] == 300);
    assert_or_panic(v[20] == 301);
    assert_or_panic(v[21] == 302);
    assert_or_panic(v[22] == 303);
    assert_or_panic(v[23] == 304);
    assert_or_panic(i == 24);
}
void c_test_vector_24_f64(void) {
    Vector_24_f64 v = zig_ret_vector_24_f64();
    assert_or_panic(v[0] == 209);
    assert_or_panic(v[1] == 210);
    assert_or_panic(v[2] == 211);
    assert_or_panic(v[3] == 212);
    assert_or_panic(v[4] == 213);
    assert_or_panic(v[5] == 214);
    assert_or_panic(v[6] == 215);
    assert_or_panic(v[7] == 216);
    assert_or_panic(v[8] == 217);
    assert_or_panic(v[9] == 218);
    assert_or_panic(v[10] == 219);
    assert_or_panic(v[11] == 220);
    assert_or_panic(v[12] == 221);
    assert_or_panic(v[13] == 222);
    assert_or_panic(v[14] == 223);
    assert_or_panic(v[15] == 224);
    assert_or_panic(v[16] == 225);
    assert_or_panic(v[17] == 226);
    assert_or_panic(v[18] == 227);
    assert_or_panic(v[19] == 228);
    assert_or_panic(v[20] == 229);
    assert_or_panic(v[21] == 230);
    assert_or_panic(v[22] == 231);
    assert_or_panic(v[23] == 232);
    zig_vector_24_f64((Vector_24_f64){
        233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248,
        249, 250, 251, 252, 253, 254, 255, 256,
    }, 24);
}

typedef double Vector_32_f64 __attribute__((vector_size(32 * sizeof(double))));

Vector_32_f64 zig_ret_vector_32_f64(void);
void zig_vector_32_f64(Vector_32_f64, size_t);

Vector_32_f64 c_ret_vector_32_f64(void) {
    return (Vector_32_f64){
        369, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 382, 383, 384,
        385, 386, 387, 388, 389, 390, 391, 392, 393, 394, 395, 396, 397, 398, 399, 400,
    };
}
void c_vector_32_f64(Vector_32_f64 v, size_t i) {
    assert_or_panic(v[0] == 401);
    assert_or_panic(v[1] == 402);
    assert_or_panic(v[2] == 403);
    assert_or_panic(v[3] == 404);
    assert_or_panic(v[4] == 405);
    assert_or_panic(v[5] == 406);
    assert_or_panic(v[6] == 407);
    assert_or_panic(v[7] == 408);
    assert_or_panic(v[8] == 409);
    assert_or_panic(v[9] == 410);
    assert_or_panic(v[10] == 411);
    assert_or_panic(v[11] == 412);
    assert_or_panic(v[12] == 413);
    assert_or_panic(v[13] == 414);
    assert_or_panic(v[14] == 415);
    assert_or_panic(v[15] == 416);
    assert_or_panic(v[16] == 417);
    assert_or_panic(v[17] == 418);
    assert_or_panic(v[18] == 419);
    assert_or_panic(v[19] == 420);
    assert_or_panic(v[20] == 421);
    assert_or_panic(v[21] == 422);
    assert_or_panic(v[22] == 423);
    assert_or_panic(v[23] == 424);
    assert_or_panic(v[24] == 425);
    assert_or_panic(v[25] == 426);
    assert_or_panic(v[26] == 427);
    assert_or_panic(v[27] == 428);
    assert_or_panic(v[28] == 429);
    assert_or_panic(v[29] == 430);
    assert_or_panic(v[30] == 431);
    assert_or_panic(v[31] == 432);
    assert_or_panic(i == 32);
}
void c_test_vector_32_f64(void) {
    Vector_32_f64 v = zig_ret_vector_32_f64();
    assert_or_panic(v[0] == 305);
    assert_or_panic(v[1] == 306);
    assert_or_panic(v[2] == 307);
    assert_or_panic(v[3] == 308);
    assert_or_panic(v[4] == 309);
    assert_or_panic(v[5] == 310);
    assert_or_panic(v[6] == 311);
    assert_or_panic(v[7] == 312);
    assert_or_panic(v[8] == 313);
    assert_or_panic(v[9] == 314);
    assert_or_panic(v[10] == 315);
    assert_or_panic(v[11] == 316);
    assert_or_panic(v[12] == 317);
    assert_or_panic(v[13] == 318);
    assert_or_panic(v[14] == 319);
    assert_or_panic(v[15] == 320);
    assert_or_panic(v[16] == 321);
    assert_or_panic(v[17] == 322);
    assert_or_panic(v[18] == 323);
    assert_or_panic(v[19] == 324);
    assert_or_panic(v[20] == 325);
    assert_or_panic(v[21] == 326);
    assert_or_panic(v[22] == 327);
    assert_or_panic(v[23] == 328);
    assert_or_panic(v[24] == 329);
    assert_or_panic(v[25] == 330);
    assert_or_panic(v[26] == 331);
    assert_or_panic(v[27] == 332);
    assert_or_panic(v[28] == 333);
    assert_or_panic(v[29] == 334);
    assert_or_panic(v[30] == 335);
    assert_or_panic(v[31] == 336);
    zig_vector_32_f64((Vector_32_f64){
        337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351, 352,
        353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368,
    }, 32);
}

typedef double Vector_48_f64 __attribute__((vector_size(48 * sizeof(double))));

Vector_48_f64 zig_ret_vector_48_f64(void);
void zig_vector_48_f64(Vector_48_f64, size_t);

Vector_48_f64 c_ret_vector_48_f64(void) {
    return (Vector_48_f64){
        529, 530, 531, 532, 533, 534, 535, 536, 537, 538, 539, 540, 541, 542, 543, 544,
        545, 546, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 560,
        561, 562, 563, 564, 565, 566, 567, 568, 569, 570, 571, 572, 573, 574, 575, 576,
    };
}
void c_vector_48_f64(Vector_48_f64 v, size_t i) {
    assert_or_panic(v[0] == 577);
    assert_or_panic(v[1] == 578);
    assert_or_panic(v[2] == 579);
    assert_or_panic(v[3] == 580);
    assert_or_panic(v[4] == 581);
    assert_or_panic(v[5] == 582);
    assert_or_panic(v[6] == 583);
    assert_or_panic(v[7] == 584);
    assert_or_panic(v[8] == 585);
    assert_or_panic(v[9] == 586);
    assert_or_panic(v[10] == 587);
    assert_or_panic(v[11] == 588);
    assert_or_panic(v[12] == 589);
    assert_or_panic(v[13] == 590);
    assert_or_panic(v[14] == 591);
    assert_or_panic(v[15] == 592);
    assert_or_panic(v[16] == 593);
    assert_or_panic(v[17] == 594);
    assert_or_panic(v[18] == 595);
    assert_or_panic(v[19] == 596);
    assert_or_panic(v[20] == 597);
    assert_or_panic(v[21] == 598);
    assert_or_panic(v[22] == 599);
    assert_or_panic(v[23] == 600);
    assert_or_panic(v[24] == 601);
    assert_or_panic(v[25] == 602);
    assert_or_panic(v[26] == 603);
    assert_or_panic(v[27] == 604);
    assert_or_panic(v[28] == 605);
    assert_or_panic(v[29] == 606);
    assert_or_panic(v[30] == 607);
    assert_or_panic(v[31] == 608);
    assert_or_panic(v[32] == 609);
    assert_or_panic(v[33] == 610);
    assert_or_panic(v[34] == 611);
    assert_or_panic(v[35] == 612);
    assert_or_panic(v[36] == 613);
    assert_or_panic(v[37] == 614);
    assert_or_panic(v[38] == 615);
    assert_or_panic(v[39] == 616);
    assert_or_panic(v[40] == 617);
    assert_or_panic(v[41] == 618);
    assert_or_panic(v[42] == 619);
    assert_or_panic(v[43] == 620);
    assert_or_panic(v[44] == 621);
    assert_or_panic(v[45] == 622);
    assert_or_panic(v[46] == 623);
    assert_or_panic(v[47] == 624);
    assert_or_panic(i == 48);
}
void c_test_vector_48_f64(void) {
    Vector_48_f64 v = zig_ret_vector_48_f64();
    assert_or_panic(v[0] == 433);
    assert_or_panic(v[1] == 434);
    assert_or_panic(v[2] == 435);
    assert_or_panic(v[3] == 436);
    assert_or_panic(v[4] == 437);
    assert_or_panic(v[5] == 438);
    assert_or_panic(v[6] == 439);
    assert_or_panic(v[7] == 440);
    assert_or_panic(v[8] == 441);
    assert_or_panic(v[9] == 442);
    assert_or_panic(v[10] == 443);
    assert_or_panic(v[11] == 444);
    assert_or_panic(v[12] == 445);
    assert_or_panic(v[13] == 446);
    assert_or_panic(v[14] == 447);
    assert_or_panic(v[15] == 448);
    assert_or_panic(v[16] == 449);
    assert_or_panic(v[17] == 450);
    assert_or_panic(v[18] == 451);
    assert_or_panic(v[19] == 452);
    assert_or_panic(v[20] == 453);
    assert_or_panic(v[21] == 454);
    assert_or_panic(v[22] == 455);
    assert_or_panic(v[23] == 456);
    assert_or_panic(v[24] == 457);
    assert_or_panic(v[25] == 458);
    assert_or_panic(v[26] == 459);
    assert_or_panic(v[27] == 460);
    assert_or_panic(v[28] == 461);
    assert_or_panic(v[29] == 462);
    assert_or_panic(v[30] == 463);
    assert_or_panic(v[31] == 464);
    assert_or_panic(v[32] == 465);
    assert_or_panic(v[33] == 466);
    assert_or_panic(v[34] == 467);
    assert_or_panic(v[35] == 468);
    assert_or_panic(v[36] == 469);
    assert_or_panic(v[37] == 470);
    assert_or_panic(v[38] == 471);
    assert_or_panic(v[39] == 472);
    assert_or_panic(v[40] == 473);
    assert_or_panic(v[41] == 474);
    assert_or_panic(v[42] == 475);
    assert_or_panic(v[43] == 476);
    assert_or_panic(v[44] == 477);
    assert_or_panic(v[45] == 478);
    assert_or_panic(v[46] == 479);
    assert_or_panic(v[47] == 480);
    zig_vector_48_f64((Vector_48_f64){
        481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496,
        497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512,
        513, 514, 515, 516, 517, 518, 519, 520, 521, 522, 523, 524, 525, 526, 527, 528,
    }, 48);
}

typedef double Vector_64_f64 __attribute__((vector_size(64 * sizeof(double))));

Vector_64_f64 zig_ret_vector_64_f64(void);
void zig_vector_64_f64(Vector_64_f64, size_t);

Vector_64_f64 c_ret_vector_64_f64(void) {
    return (Vector_64_f64){
        753, 754, 755, 756, 757, 758, 759, 760, 761, 762, 763, 764, 765, 766, 767, 768,
        769, 770, 771, 772, 773, 774, 775, 776, 777, 778, 779, 780, 781, 782, 783, 784,
        785, 786, 787, 788, 789, 790, 791, 792, 793, 794, 795, 796, 797, 798, 799, 800,
        801, 802, 803, 804, 805, 806, 807, 808, 809, 810, 811, 812, 813, 814, 815, 816,
    };
}
void c_vector_64_f64(Vector_64_f64 v, size_t i) {
    assert_or_panic(v[0] == 817);
    assert_or_panic(v[1] == 818);
    assert_or_panic(v[2] == 819);
    assert_or_panic(v[3] == 820);
    assert_or_panic(v[4] == 821);
    assert_or_panic(v[5] == 822);
    assert_or_panic(v[6] == 823);
    assert_or_panic(v[7] == 824);
    assert_or_panic(v[8] == 825);
    assert_or_panic(v[9] == 826);
    assert_or_panic(v[10] == 827);
    assert_or_panic(v[11] == 828);
    assert_or_panic(v[12] == 829);
    assert_or_panic(v[13] == 830);
    assert_or_panic(v[14] == 831);
    assert_or_panic(v[15] == 832);
    assert_or_panic(v[16] == 833);
    assert_or_panic(v[17] == 834);
    assert_or_panic(v[18] == 835);
    assert_or_panic(v[19] == 836);
    assert_or_panic(v[20] == 837);
    assert_or_panic(v[21] == 838);
    assert_or_panic(v[22] == 839);
    assert_or_panic(v[23] == 840);
    assert_or_panic(v[24] == 841);
    assert_or_panic(v[25] == 842);
    assert_or_panic(v[26] == 843);
    assert_or_panic(v[27] == 844);
    assert_or_panic(v[28] == 845);
    assert_or_panic(v[29] == 846);
    assert_or_panic(v[30] == 847);
    assert_or_panic(v[31] == 848);
    assert_or_panic(v[32] == 849);
    assert_or_panic(v[33] == 850);
    assert_or_panic(v[34] == 851);
    assert_or_panic(v[35] == 852);
    assert_or_panic(v[36] == 853);
    assert_or_panic(v[37] == 854);
    assert_or_panic(v[38] == 855);
    assert_or_panic(v[39] == 856);
    assert_or_panic(v[40] == 857);
    assert_or_panic(v[41] == 858);
    assert_or_panic(v[42] == 859);
    assert_or_panic(v[43] == 860);
    assert_or_panic(v[44] == 861);
    assert_or_panic(v[45] == 862);
    assert_or_panic(v[46] == 863);
    assert_or_panic(v[47] == 864);
    assert_or_panic(v[48] == 865);
    assert_or_panic(v[49] == 866);
    assert_or_panic(v[50] == 867);
    assert_or_panic(v[51] == 868);
    assert_or_panic(v[52] == 869);
    assert_or_panic(v[53] == 870);
    assert_or_panic(v[54] == 871);
    assert_or_panic(v[55] == 872);
    assert_or_panic(v[56] == 873);
    assert_or_panic(v[57] == 874);
    assert_or_panic(v[58] == 875);
    assert_or_panic(v[59] == 876);
    assert_or_panic(v[60] == 877);
    assert_or_panic(v[61] == 878);
    assert_or_panic(v[62] == 879);
    assert_or_panic(v[63] == 880);
    assert_or_panic(i == 64);
}
void c_test_vector_64_f64(void) {
    Vector_64_f64 v = zig_ret_vector_64_f64();
    assert_or_panic(v[0] == 625);
    assert_or_panic(v[1] == 626);
    assert_or_panic(v[2] == 627);
    assert_or_panic(v[3] == 628);
    assert_or_panic(v[4] == 629);
    assert_or_panic(v[5] == 630);
    assert_or_panic(v[6] == 631);
    assert_or_panic(v[7] == 632);
    assert_or_panic(v[8] == 633);
    assert_or_panic(v[9] == 634);
    assert_or_panic(v[10] == 635);
    assert_or_panic(v[11] == 636);
    assert_or_panic(v[12] == 637);
    assert_or_panic(v[13] == 638);
    assert_or_panic(v[14] == 639);
    assert_or_panic(v[15] == 640);
    assert_or_panic(v[16] == 641);
    assert_or_panic(v[17] == 642);
    assert_or_panic(v[18] == 643);
    assert_or_panic(v[19] == 644);
    assert_or_panic(v[20] == 645);
    assert_or_panic(v[21] == 646);
    assert_or_panic(v[22] == 647);
    assert_or_panic(v[23] == 648);
    assert_or_panic(v[24] == 649);
    assert_or_panic(v[25] == 650);
    assert_or_panic(v[26] == 651);
    assert_or_panic(v[27] == 652);
    assert_or_panic(v[28] == 653);
    assert_or_panic(v[29] == 654);
    assert_or_panic(v[30] == 655);
    assert_or_panic(v[31] == 656);
    assert_or_panic(v[32] == 657);
    assert_or_panic(v[33] == 658);
    assert_or_panic(v[34] == 659);
    assert_or_panic(v[35] == 660);
    assert_or_panic(v[36] == 661);
    assert_or_panic(v[37] == 662);
    assert_or_panic(v[38] == 663);
    assert_or_panic(v[39] == 664);
    assert_or_panic(v[40] == 665);
    assert_or_panic(v[41] == 666);
    assert_or_panic(v[42] == 667);
    assert_or_panic(v[43] == 668);
    assert_or_panic(v[44] == 669);
    assert_or_panic(v[45] == 670);
    assert_or_panic(v[46] == 671);
    assert_or_panic(v[47] == 672);
    assert_or_panic(v[48] == 673);
    assert_or_panic(v[49] == 674);
    assert_or_panic(v[50] == 675);
    assert_or_panic(v[51] == 676);
    assert_or_panic(v[52] == 677);
    assert_or_panic(v[53] == 678);
    assert_or_panic(v[54] == 679);
    assert_or_panic(v[55] == 680);
    assert_or_panic(v[56] == 681);
    assert_or_panic(v[57] == 682);
    assert_or_panic(v[58] == 683);
    assert_or_panic(v[59] == 684);
    assert_or_panic(v[60] == 685);
    assert_or_panic(v[61] == 686);
    assert_or_panic(v[62] == 687);
    assert_or_panic(v[63] == 688);
    zig_vector_64_f64((Vector_64_f64){
        689, 690, 691, 692, 693, 694, 695, 696, 697, 698, 699, 700, 701, 702, 703, 704,
        705, 706, 707, 708, 709, 710, 711, 712, 713, 714, 715, 716, 717, 718, 719, 720,
        721, 722, 723, 724, 725, 726, 727, 728, 729, 730, 731, 732, 733, 734, 735, 736,
        737, 738, 739, 740, 741, 742, 743, 744, 745, 746, 747, 748, 749, 750, 751, 752,
    }, 64);
}

struct Struct_u8 {
    uint8_t a;
};

struct Struct_u8 zig_ret_struct_u8(void);
void zig_struct_u8(struct Struct_u8, size_t);

struct Struct_u8 c_ret_struct_u8(void) {
    return (struct Struct_u8){ .a = 4 };
}
void c_struct_u8(struct Struct_u8 s, size_t i) {
    assert_or_panic(s.a == 5);
    assert_or_panic(i == 6);
}
void c_test_struct_u8(void) {
    struct Struct_u8 s = zig_ret_struct_u8();
    assert_or_panic(s.a == 1);
    zig_struct_u8((struct Struct_u8){ .a = 2 }, 3);
}

struct Struct_u8_u8 {
    uint8_t a, b;
};

struct Struct_u8_u8 zig_ret_struct_u8_u8(void);
void zig_struct_u8_u8(struct Struct_u8_u8, size_t);

struct Struct_u8_u8 c_ret_struct_u8_u8(void) {
    return (struct Struct_u8_u8){ .a = 6, .b = 7 };
}
void c_struct_u8_u8(struct Struct_u8_u8 s, size_t i) {
    assert_or_panic(s.a == 8);
    assert_or_panic(s.b == 9);
    assert_or_panic(i == 10);
}
void c_test_struct_u8_u8(void) {
    struct Struct_u8_u8 s = zig_ret_struct_u8_u8();
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
    zig_struct_u8_u8((struct Struct_u8_u8){ .a = 3, .b = 4 }, 5);
}

struct Struct_u8_u8_u8 {
    uint8_t a, b, c;
};

struct Struct_u8_u8_u8 zig_ret_struct_u8_u8_u8(void);
void zig_struct_u8_u8_u8(struct Struct_u8_u8_u8, size_t);

struct Struct_u8_u8_u8 c_ret_struct_u8_u8_u8(void) {
    return (struct Struct_u8_u8_u8){ .a = 8, .b = 9, .c = 10 };
}
void c_struct_u8_u8_u8(struct Struct_u8_u8_u8 s, size_t i) {
    assert_or_panic(s.a == 11);
    assert_or_panic(s.b == 12);
    assert_or_panic(s.c == 13);
    assert_or_panic(i == 14);
}
void c_test_struct_u8_u8_u8(void) {
    struct Struct_u8_u8_u8 s = zig_ret_struct_u8_u8_u8();
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
    assert_or_panic(s.c == 3);
    zig_struct_u8_u8_u8((struct Struct_u8_u8_u8){ .a = 4, .b = 5, .c = 6 }, 7);
}

struct Struct_u8_u8_u8_u8 {
    uint8_t a, b, c, d;
};

struct Struct_u8_u8_u8_u8 zig_ret_struct_u8_u8_u8_u8(void);
void zig_struct_u8_u8_u8_u8(struct Struct_u8_u8_u8_u8, size_t);

struct Struct_u8_u8_u8_u8 c_ret_struct_u8_u8_u8_u8(void) {
    return (struct Struct_u8_u8_u8_u8){ .a = 10, .b = 11, .c = 12, .d = 13 };
}
void c_struct_u8_u8_u8_u8(struct Struct_u8_u8_u8_u8 s, size_t i) {
    assert_or_panic(s.a == 14);
    assert_or_panic(s.b == 15);
    assert_or_panic(s.c == 16);
    assert_or_panic(s.d == 17);
    assert_or_panic(i == 18);
}
void c_test_struct_u8_u8_u8_u8(void) {
    struct Struct_u8_u8_u8_u8 s = zig_ret_struct_u8_u8_u8_u8();
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
    assert_or_panic(s.c == 3);
    assert_or_panic(s.d == 4);
    zig_struct_u8_u8_u8_u8((struct Struct_u8_u8_u8_u8){ .a = 5, .b = 6, .c = 7, .d = 8 }, 9);
}

struct Struct_u16 {
    uint16_t a;
};

struct Struct_u16 zig_ret_struct_u16(void);
void zig_struct_u16(struct Struct_u16, size_t);

struct Struct_u16 c_ret_struct_u16(void) {
    return (struct Struct_u16){ .a = 4 };
}
void c_struct_u16(struct Struct_u16 s, size_t i) {
    assert_or_panic(s.a == 5);
    assert_or_panic(i == 6);
}
void c_test_struct_u16(void) {
    struct Struct_u16 s = zig_ret_struct_u16();
    assert_or_panic(s.a == 1);
    zig_struct_u16((struct Struct_u16){ .a = 2 }, 3);
}

struct Struct_u16_u16 {
    uint16_t a, b;
};

struct Struct_u16_u16 zig_ret_struct_u16_u16(void);
void zig_struct_u16_u16(struct Struct_u16_u16, size_t);

struct Struct_u16_u16 c_ret_struct_u16_u16(void) {
    return (struct Struct_u16_u16){ .a = 6, .b = 7 };
}
void c_struct_u16_u16(struct Struct_u16_u16 s, size_t i) {
    assert_or_panic(s.a == 8);
    assert_or_panic(s.b == 9);
    assert_or_panic(i == 10);
}
void c_test_struct_u16_u16(void) {
    struct Struct_u16_u16 s = zig_ret_struct_u16_u16();
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
    zig_struct_u16_u16((struct Struct_u16_u16){ .a = 3, .b = 4 }, 5);
}

struct Struct_u16_u16_u16 {
    uint16_t a, b, c;
};

struct Struct_u16_u16_u16 zig_ret_struct_u16_u16_u16(void);
void zig_struct_u16_u16_u16(struct Struct_u16_u16_u16, size_t);

struct Struct_u16_u16_u16 c_ret_struct_u16_u16_u16(void) {
    return (struct Struct_u16_u16_u16){ .a = 8, .b = 9, .c = 10 };
}
void c_struct_u16_u16_u16(struct Struct_u16_u16_u16 s, size_t i) {
    assert_or_panic(s.a == 11);
    assert_or_panic(s.b == 12);
    assert_or_panic(s.c == 13);
    assert_or_panic(i == 14);
}
void c_test_struct_u16_u16_u16(void) {
    struct Struct_u16_u16_u16 s = zig_ret_struct_u16_u16_u16();
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
    assert_or_panic(s.c == 3);
    zig_struct_u16_u16_u16((struct Struct_u16_u16_u16){ .a = 4, .b = 5, .c = 6 }, 7);
}

struct Struct_u16_u16_u16_u16 {
    uint16_t a, b, c, d;
};

struct Struct_u16_u16_u16_u16 zig_ret_struct_u16_u16_u16_u16(void);
void zig_struct_u16_u16_u16_u16(struct Struct_u16_u16_u16_u16, size_t);

struct Struct_u16_u16_u16_u16 c_ret_struct_u16_u16_u16_u16(void) {
    return (struct Struct_u16_u16_u16_u16){ .a = 10, .b = 11, .c = 12, .d = 13 };
}
void c_struct_u16_u16_u16_u16(struct Struct_u16_u16_u16_u16 s, size_t i) {
    assert_or_panic(s.a == 14);
    assert_or_panic(s.b == 15);
    assert_or_panic(s.c == 16);
    assert_or_panic(s.d == 17);
    assert_or_panic(i == 18);
}
void c_test_struct_u16_u16_u16_u16(void) {
    struct Struct_u16_u16_u16_u16 s = zig_ret_struct_u16_u16_u16_u16();
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
    assert_or_panic(s.c == 3);
    assert_or_panic(s.d == 4);
    zig_struct_u16_u16_u16_u16((struct Struct_u16_u16_u16_u16){ .a = 5, .b = 6, .c = 7, .d = 8 }, 9);
}

struct Struct_u32 {
    uint32_t a;
};

struct Struct_u32 zig_ret_struct_u32(void);
void zig_struct_u32(struct Struct_u32, size_t);

struct Struct_u32 c_ret_struct_u32(void) {
    return (struct Struct_u32){ .a = 4 };
}
void c_struct_u32(struct Struct_u32 s, size_t i) {
    assert_or_panic(s.a == 5);
    assert_or_panic(i == 6);
}
void c_test_struct_u32(void) {
    struct Struct_u32 s = zig_ret_struct_u32();
    assert_or_panic(s.a == 1);
    zig_struct_u32((struct Struct_u32){ .a = 2 }, 3);
}

struct Struct_u32_u32 {
    uint32_t a, b;
};

struct Struct_u32_u32 zig_ret_struct_u32_u32(void);
void zig_struct_u32_u32(struct Struct_u32_u32, size_t);

struct Struct_u32_u32 c_ret_struct_u32_u32(void) {
    return (struct Struct_u32_u32){ .a = 6, .b = 7 };
}
void c_struct_u32_u32(struct Struct_u32_u32 s, size_t i) {
    assert_or_panic(s.a == 8);
    assert_or_panic(s.b == 9);
    assert_or_panic(i == 10);
}
void c_test_struct_u32_u32(void) {
    struct Struct_u32_u32 s = zig_ret_struct_u32_u32();
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
    zig_struct_u32_u32((struct Struct_u32_u32){ .a = 3, .b = 4 }, 5);
}

struct Struct_u32_u32_u32 {
    uint32_t a, b, c;
};

struct Struct_u32_u32_u32 zig_ret_struct_u32_u32_u32(void);
void zig_struct_u32_u32_u32(struct Struct_u32_u32_u32, size_t);

struct Struct_u32_u32_u32 c_ret_struct_u32_u32_u32(void) {
    return (struct Struct_u32_u32_u32){ .a = 8, .b = 9, .c = 10 };
}
void c_struct_u32_u32_u32(struct Struct_u32_u32_u32 s, size_t i) {
    assert_or_panic(s.a == 11);
    assert_or_panic(s.b == 12);
    assert_or_panic(s.c == 13);
    assert_or_panic(i == 14);
}
void c_test_struct_u32_u32_u32(void) {
    struct Struct_u32_u32_u32 s = zig_ret_struct_u32_u32_u32();
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
    assert_or_panic(s.c == 3);
    zig_struct_u32_u32_u32((struct Struct_u32_u32_u32){ .a = 4, .b = 5, .c = 6 }, 7);
}

struct Struct_u32_u32_u32_u32 {
    uint32_t a, b, c, d;
};

struct Struct_u32_u32_u32_u32 zig_ret_struct_u32_u32_u32_u32(void);
void zig_struct_u32_u32_u32_u32(struct Struct_u32_u32_u32_u32, size_t);

struct Struct_u32_u32_u32_u32 c_ret_struct_u32_u32_u32_u32(void) {
    return (struct Struct_u32_u32_u32_u32){ .a = 10, .b = 11, .c = 12, .d = 13 };
}
void c_struct_u32_u32_u32_u32(struct Struct_u32_u32_u32_u32 s, size_t i) {
    assert_or_panic(s.a == 14);
    assert_or_panic(s.b == 15);
    assert_or_panic(s.c == 16);
    assert_or_panic(s.d == 17);
    assert_or_panic(i == 18);
}
void c_test_struct_u32_u32_u32_u32(void) {
    struct Struct_u32_u32_u32_u32 s = zig_ret_struct_u32_u32_u32_u32();
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
    assert_or_panic(s.c == 3);
    assert_or_panic(s.d == 4);
    zig_struct_u32_u32_u32_u32((struct Struct_u32_u32_u32_u32){ .a = 5, .b = 6, .c = 7, .d = 8 }, 9);
}

struct Struct_u64 {
    uint64_t a;
};

struct Struct_u64 zig_ret_struct_u64(void);
void zig_struct_u64(struct Struct_u64, size_t);

struct Struct_u64 c_ret_struct_u64(void) {
    return (struct Struct_u64){ .a = 4 };
}
void c_struct_u64(struct Struct_u64 s, size_t i) {
    assert_or_panic(s.a == 5);
    assert_or_panic(i == 6);
}
void c_test_struct_u64(void) {
    struct Struct_u64 s = zig_ret_struct_u64();
    assert_or_panic(s.a == 1);
    zig_struct_u64((struct Struct_u64){ .a = 2 }, 3);
}

struct Struct_u64_u64 {
    uint64_t a;
    uint64_t b;
};

struct Struct_u64_u64 zig_ret_struct_u64_u64(void);
void zig_struct_u64_u64(struct Struct_u64_u64, size_t);
void zig_1_struct_u64_u64(size_t, struct Struct_u64_u64, size_t);
void zig_2_struct_u64_u64(size_t, size_t, struct Struct_u64_u64, size_t);
void zig_3_struct_u64_u64(size_t, size_t, size_t, struct Struct_u64_u64, size_t);
void zig_4_struct_u64_u64(size_t, size_t, size_t, size_t, struct Struct_u64_u64, size_t);
void zig_5_struct_u64_u64(size_t, size_t, size_t, size_t, size_t, struct Struct_u64_u64, size_t);
void zig_6_struct_u64_u64(size_t, size_t, size_t, size_t, size_t, size_t, struct Struct_u64_u64, size_t);
void zig_7_struct_u64_u64(size_t, size_t, size_t, size_t, size_t, size_t, size_t, struct Struct_u64_u64, size_t);
void zig_8_struct_u64_u64(size_t, size_t, size_t, size_t, size_t, size_t, size_t, size_t, struct Struct_u64_u64, size_t);

struct Struct_u64_u64 c_ret_struct_u64_u64(void) {
    return (struct Struct_u64_u64){ .a = 21, .b = 22 };
}
void c_struct_u64_u64(struct Struct_u64_u64 s, size_t i) {
    assert_or_panic(s.a == 23);
    assert_or_panic(s.b == 24);
    assert_or_panic(i == 1);
}
void c_1_struct_u64_u64(size_t a0, struct Struct_u64_u64 s, size_t i) {
    assert_or_panic(s.a == 25);
    assert_or_panic(s.b == 26);
    assert_or_panic(i == 2);
}
void c_2_struct_u64_u64(size_t a0, size_t a1, struct Struct_u64_u64 s, size_t i) {
    assert_or_panic(s.a == 27);
    assert_or_panic(s.b == 28);
    assert_or_panic(i == 3);
}
void c_3_struct_u64_u64(size_t a0, size_t a1, size_t a2, struct Struct_u64_u64 s, size_t i) {
    assert_or_panic(s.a == 29);
    assert_or_panic(s.b == 30);
    assert_or_panic(i == 4);
}
void c_4_struct_u64_u64(size_t a0, size_t a1, size_t a2, size_t a3, struct Struct_u64_u64 s, size_t i) {
    assert_or_panic(s.a == 31);
    assert_or_panic(s.b == 32);
    assert_or_panic(i == 5);
}
void c_5_struct_u64_u64(size_t a0, size_t a1, size_t a2, size_t a3, size_t a4, struct Struct_u64_u64 s, size_t i) {
    assert_or_panic(s.a == 33);
    assert_or_panic(s.b == 34);
    assert_or_panic(i == 6);
}
void c_6_struct_u64_u64(size_t a0, size_t a1, size_t a2, size_t a3, size_t a4, size_t a5, struct Struct_u64_u64 s, size_t i) {
    assert_or_panic(s.a == 35);
    assert_or_panic(s.b == 36);
    assert_or_panic(i == 7);
}
void c_7_struct_u64_u64(size_t a0, size_t a1, size_t a2, size_t a3, size_t a4, size_t a5, size_t a6, struct Struct_u64_u64 s, size_t i) {
    assert_or_panic(s.a == 37);
    assert_or_panic(s.b == 38);
    assert_or_panic(i == 8);
}
void c_8_struct_u64_u64(size_t a0, size_t a1, size_t a2, size_t a3, size_t a4, size_t a5, size_t a6, size_t a7, struct Struct_u64_u64 s, size_t i) {
    assert_or_panic(s.a == 39);
    assert_or_panic(s.b == 40);
    assert_or_panic(i == 9);
}
void c_test_struct_u64_u64(void) {
    struct Struct_u64_u64 s = zig_ret_struct_u64_u64();
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
    zig_struct_u64_u64((struct Struct_u64_u64){ .a = 3, .b = 4 }, 1);
    zig_1_struct_u64_u64(0, (struct Struct_u64_u64){ .a = 5, .b = 6 }, 2);
    zig_2_struct_u64_u64(0, 1, (struct Struct_u64_u64){ .a = 7, .b = 8 }, 3);
    zig_3_struct_u64_u64(0, 1, 2, (struct Struct_u64_u64){ .a = 9, .b = 10 }, 4);
    zig_4_struct_u64_u64(0, 1, 2, 3, (struct Struct_u64_u64){ .a = 11, .b = 12 }, 5);
    zig_5_struct_u64_u64(0, 1, 2, 3, 4, (struct Struct_u64_u64){ .a = 13, .b = 14 }, 6);
    zig_6_struct_u64_u64(0, 1, 2, 3, 4, 5, (struct Struct_u64_u64){ .a = 15, .b = 16 }, 7);
    zig_7_struct_u64_u64(0, 1, 2, 3, 4, 5, 6, (struct Struct_u64_u64){ .a = 17, .b = 18 }, 8);
    zig_8_struct_u64_u64(0, 1, 2, 3, 4, 5, 6, 7, (struct Struct_u64_u64){ .a = 19, .b = 20 }, 9);
}

struct Struct_u64_u64_u64 {
    uint64_t a, b, c;
};

struct Struct_u64_u64_u64 zig_ret_struct_u64_u64_u64(void);
void zig_struct_u64_u64_u64(struct Struct_u64_u64_u64, size_t);

struct Struct_u64_u64_u64 c_ret_struct_u64_u64_u64(void) {
    return (struct Struct_u64_u64_u64){ .a = 8, .b = 9, .c = 10 };
}
void c_struct_u64_u64_u64(struct Struct_u64_u64_u64 s, size_t i) {
    assert_or_panic(s.a == 11);
    assert_or_panic(s.b == 12);
    assert_or_panic(s.c == 13);
    assert_or_panic(i == 14);
}
void c_test_struct_u64_u64_u64(void) {
    struct Struct_u64_u64_u64 s = zig_ret_struct_u64_u64_u64();
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
    assert_or_panic(s.c == 3);
    zig_struct_u64_u64_u64((struct Struct_u64_u64_u64){ .a = 4, .b = 5, .c = 6 }, 7);
}

struct Struct_u64_u64_u64_u64 {
    uint64_t a, b, c, d;
};

struct Struct_u64_u64_u64_u64 zig_ret_struct_u64_u64_u64_u64(void);
void zig_struct_u64_u64_u64_u64(struct Struct_u64_u64_u64_u64, size_t);

struct Struct_u64_u64_u64_u64 c_ret_struct_u64_u64_u64_u64(void) {
    return (struct Struct_u64_u64_u64_u64){ .a = 10, .b = 11, .c = 12, .d = 13 };
}
void c_struct_u64_u64_u64_u64(struct Struct_u64_u64_u64_u64 s, size_t i) {
    assert_or_panic(s.a == 14);
    assert_or_panic(s.b == 15);
    assert_or_panic(s.c == 16);
    assert_or_panic(s.d == 17);
    assert_or_panic(i == 18);
}
void c_test_struct_u64_u64_u64_u64(void) {
    struct Struct_u64_u64_u64_u64 s = zig_ret_struct_u64_u64_u64_u64();
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
    assert_or_panic(s.c == 3);
    assert_or_panic(s.d == 4);
    zig_struct_u64_u64_u64_u64((struct Struct_u64_u64_u64_u64){ .a = 5, .b = 6, .c = 7, .d = 8 }, 9);
}

struct Struct_f32 {
    float a;
};

struct Struct_f32 zig_ret_struct_f32(void);
void zig_struct_f32(struct Struct_f32, size_t);

struct Struct_f32 c_ret_struct_f32(void) {
    return (struct Struct_f32){ .a = 4 };
}
void c_struct_f32(struct Struct_f32 s, size_t i) {
    assert_or_panic(s.a == 5);
    assert_or_panic(i == 6);
}
void c_test_struct_f32(void) {
    struct Struct_f32 s = zig_ret_struct_f32();
    assert_or_panic(s.a == 1);
    zig_struct_f32((struct Struct_f32){ .a = 2 }, 3);
}

struct Struct_f32_f32 {
    float a, b;
};

struct Struct_f32_f32 zig_ret_struct_f32_f32(void);
void zig_struct_f32_f32(struct Struct_f32_f32, size_t);

struct Struct_f32_f32 c_ret_struct_f32_f32(void) {
    return (struct Struct_f32_f32){ .a = 6, .b = 7 };
}
void c_struct_f32_f32(struct Struct_f32_f32 s, size_t i) {
    assert_or_panic(s.a == 8);
    assert_or_panic(s.b == 9);
    assert_or_panic(i == 10);
}
void c_test_struct_f32_f32(void) {
    struct Struct_f32_f32 s = zig_ret_struct_f32_f32();
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
    zig_struct_f32_f32((struct Struct_f32_f32){ .a = 3, .b = 4 }, 5);
}

struct Struct_f32_f32_f32 {
    float a, b, c;
};

struct Struct_f32_f32_f32 zig_ret_struct_f32_f32_f32(void);
void zig_struct_f32_f32_f32(struct Struct_f32_f32_f32, size_t);

struct Struct_f32_f32_f32 c_ret_struct_f32_f32_f32(void) {
    return (struct Struct_f32_f32_f32){ .a = 8, .b = 9, .c = 10 };
}
void c_struct_f32_f32_f32(struct Struct_f32_f32_f32 s, size_t i) {
    assert_or_panic(s.a == 11);
    assert_or_panic(s.b == 12);
    assert_or_panic(s.c == 13);
    assert_or_panic(i == 14);
}
void c_test_struct_f32_f32_f32(void) {
    struct Struct_f32_f32_f32 s = zig_ret_struct_f32_f32_f32();
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
    assert_or_panic(s.c == 3);
    zig_struct_f32_f32_f32((struct Struct_f32_f32_f32){ .a = 4, .b = 5, .c = 6 }, 7);
}

struct Struct_f32_f32_f32_f32 {
    float a, b, c, d;
};

struct Struct_f32_f32_f32_f32 zig_ret_struct_f32_f32_f32_f32(void);
void zig_struct_f32_f32_f32_f32(struct Struct_f32_f32_f32_f32, size_t);

struct Struct_f32_f32_f32_f32 c_ret_struct_f32_f32_f32_f32(void) {
    return (struct Struct_f32_f32_f32_f32){ .a = 10, .b = 11, .c = 12, .d = 13 };
}
void c_struct_f32_f32_f32_f32(struct Struct_f32_f32_f32_f32 s, size_t i) {
    assert_or_panic(s.a == 14);
    assert_or_panic(s.b == 15);
    assert_or_panic(s.c == 16);
    assert_or_panic(s.d == 17);
    assert_or_panic(i == 18);
}
void c_test_struct_f32_f32_f32_f32(void) {
    struct Struct_f32_f32_f32_f32 s = zig_ret_struct_f32_f32_f32_f32();
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
    assert_or_panic(s.c == 3);
    assert_or_panic(s.d == 4);
    zig_struct_f32_f32_f32_f32((struct Struct_f32_f32_f32_f32){ .a = 5, .b = 6, .c = 7, .d = 8 }, 9);
}

struct Struct_f32_f32_f32_f32_f32 {
    float a, b, c, d, e;
};

struct Struct_f32_f32_f32_f32_f32 zig_ret_struct_f32_f32_f32_f32_f32(void);
void zig_struct_f32_f32_f32_f32_f32(struct Struct_f32_f32_f32_f32_f32, size_t);

struct Struct_f32_f32_f32_f32_f32 c_ret_struct_f32_f32_f32_f32_f32(void) {
    return (struct Struct_f32_f32_f32_f32_f32){ .a = 12, .b = 13, .c = 14, .d = 15, .e = 16 };
}
void c_struct_f32_f32_f32_f32_f32(struct Struct_f32_f32_f32_f32_f32 s, size_t i) {
    assert_or_panic(s.a == 17);
    assert_or_panic(s.b == 18);
    assert_or_panic(s.c == 19);
    assert_or_panic(s.d == 20);
    assert_or_panic(s.e == 21);
    assert_or_panic(i == 22);
}
void c_test_struct_f32_f32_f32_f32_f32(void) {
    struct Struct_f32_f32_f32_f32_f32 s = zig_ret_struct_f32_f32_f32_f32_f32();
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
    assert_or_panic(s.c == 3);
    assert_or_panic(s.d == 4);
    assert_or_panic(s.e == 5);
    zig_struct_f32_f32_f32_f32_f32((struct Struct_f32_f32_f32_f32_f32){ .a = 6, .b = 7, .c = 8, .d = 9, .e = 10 }, 11);
}

struct Struct_f32a8 {
    alignas(8) float a;
};

struct Struct_f32a8 zig_ret_struct_f32a8(void);
void zig_struct_f32a8(struct Struct_f32a8, float);

struct Struct_f32a8 c_ret_struct_f32a8(void) {
    return (struct Struct_f32a8){ .a = 4.125f };
}
void c_struct_f32a8(struct Struct_f32a8 s, float f) {
    assert_or_panic(s.a == 5.375f);
    assert_or_panic(f == 6.5f);
}
void c_test_struct_f32a8(void) {
    struct Struct_f32a8 s = zig_ret_struct_f32a8();
    assert_or_panic(s.a == 1.25f);
    zig_struct_f32a8((struct Struct_f32a8){ .a = 2.75f }, 3.5f);
}

struct Struct_f32a8_f32a8 {
    alignas(8) float a;
    alignas(8) float b;
};

struct Struct_f32a8_f32a8 zig_ret_struct_f32a8_f32a8(void);
void zig_struct_f32a8_f32a8(struct Struct_f32a8_f32a8, float);

struct Struct_f32a8_f32a8 c_ret_struct_f32a8_f32a8(void) {
    return (struct Struct_f32a8_f32a8){ .a = 6.625f, .b = 7.875f };
}
void c_struct_f32a8_f32a8(struct Struct_f32a8_f32a8 s, float f) {
    assert_or_panic(s.a == 8.0625f);
    assert_or_panic(s.b == 9.1875f);
    assert_or_panic(f == 10.5f);
}
void c_test_struct_f32a8_f32a8(void) {
    struct Struct_f32a8_f32a8 s = zig_ret_struct_f32a8_f32a8();
    assert_or_panic(s.a == 1.25f);
    assert_or_panic(s.b == 2.75f);
    zig_struct_f32a8_f32a8((struct Struct_f32a8_f32a8){ .a = 3.125f, .b = 4.375f }, 5.5f);
}

struct Struct_f32f32_f32 {
    struct {
        float b, c;
    } a;
    float d;
};

struct Struct_f32f32_f32 zig_ret_struct_f32f32_f32(void);
void zig_struct_f32f32_f32(struct Struct_f32f32_f32);

struct Struct_f32f32_f32 c_ret_struct_f32f32_f32(void) {
    return (struct Struct_f32f32_f32){ .a = { .b = 1.0f, .c = 2.0f }, .d = 3.0f };
}
void c_struct_f32f32_f32(struct Struct_f32f32_f32 s) {
    assert_or_panic(s.a.b == 1.0f);
    assert_or_panic(s.a.c == 2.0f);
    assert_or_panic(s.d == 3.0f);
}
void c_test_struct_f32f32_f32(void) {
    struct Struct_f32f32_f32 s = zig_ret_struct_f32f32_f32();
    assert_or_panic(s.a.b == 1.0f);
    assert_or_panic(s.a.c == 2.0f);
    assert_or_panic(s.d == 3.0f);
    zig_struct_f32f32_f32((struct Struct_f32f32_f32){ .a = { .b = 1.0f, .c = 2.0f }, .d = 3.0f });
}

struct Struct_f32_f32f32 {
    float a;
    struct {
        float c, d;
    } b;
};

struct Struct_f32_f32f32 zig_ret_struct_f32_f32f32(void);
void zig_struct_f32_f32f32(struct Struct_f32_f32f32);

struct Struct_f32_f32f32 c_ret_struct_f32_f32f32(void) {
    return (struct Struct_f32_f32f32){ .a = 1.0f, .b = { .c = 2.0f, .d = 3.0f } };
}
void c_struct_f32_f32f32(struct Struct_f32_f32f32 s) {
    assert_or_panic(s.a == 1.0f);
    assert_or_panic(s.b.c == 2.0f);
    assert_or_panic(s.b.d == 3.0f);
}
void c_test_struct_f32_f32f32(void) {
    struct Struct_f32_f32f32 s = zig_ret_struct_f32_f32f32();
    assert_or_panic(s.a == 1.0f);
    assert_or_panic(s.b.c == 2.0f);
    assert_or_panic(s.b.d == 3.0f);
    zig_struct_f32_f32f32((struct Struct_f32_f32f32){ .a = 1.0f, .b = { .c = 2.0f, .d = 3.0f } });
}

struct Struct_f64 {
    double a;
};

struct Struct_f64 zig_ret_struct_f64(void);
void zig_struct_f64(struct Struct_f64, size_t);

struct Struct_f64 c_ret_struct_f64(void) {
    return (struct Struct_f64){ .a = 4 };
}
void c_struct_f64(struct Struct_f64 s, size_t i) {
    assert_or_panic(s.a == 5);
    assert_or_panic(i == 6);
}
void c_test_struct_f64(void) {
    struct Struct_f64 s = zig_ret_struct_f64();
    assert_or_panic(s.a == 1);
    zig_struct_f64((struct Struct_f64){ .a = 2 }, 3);
}

struct Struct_f64_f64 {
    double a, b;
};

struct Struct_f64_f64 zig_ret_struct_f64_f64(void);
void zig_struct_f64_f64(struct Struct_f64_f64, size_t);

struct Struct_f64_f64 c_ret_struct_f64_f64(void) {
    return (struct Struct_f64_f64){ .a = 6, .b = 7 };
}
void c_struct_f64_f64(struct Struct_f64_f64 s, size_t i) {
    assert_or_panic(s.a == 8);
    assert_or_panic(s.b == 9);
    assert_or_panic(i == 10);
}
void c_test_struct_f64_f64(void) {
    struct Struct_f64_f64 s = zig_ret_struct_f64_f64();
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
    zig_struct_f64_f64((struct Struct_f64_f64){ .a = 3, .b = 4 }, 5);
}

struct Struct_f64_f64_f64 {
    double a, b, c;
};

struct Struct_f64_f64_f64 zig_ret_struct_f64_f64_f64(void);
void zig_struct_f64_f64_f64(struct Struct_f64_f64_f64, size_t);

struct Struct_f64_f64_f64 c_ret_struct_f64_f64_f64(void) {
    return (struct Struct_f64_f64_f64){ .a = 8, .b = 9, .c = 10 };
}
void c_struct_f64_f64_f64(struct Struct_f64_f64_f64 s, size_t i) {
    assert_or_panic(s.a == 11);
    assert_or_panic(s.b == 12);
    assert_or_panic(s.c == 13);
    assert_or_panic(i == 14);
}
void c_test_struct_f64_f64_f64(void) {
    struct Struct_f64_f64_f64 s = zig_ret_struct_f64_f64_f64();
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
    assert_or_panic(s.c == 3);
    zig_struct_f64_f64_f64((struct Struct_f64_f64_f64){ .a = 4, .b = 5, .c = 6 }, 7);
}

struct Struct_f64_f64_f64_f64 {
    double a, b, c, d;
};

struct Struct_f64_f64_f64_f64 zig_ret_struct_f64_f64_f64_f64(void);
void zig_struct_f64_f64_f64_f64(struct Struct_f64_f64_f64_f64, size_t);

struct Struct_f64_f64_f64_f64 c_ret_struct_f64_f64_f64_f64(void) {
    return (struct Struct_f64_f64_f64_f64){ .a = 10, .b = 11, .c = 12, .d = 13 };
}
void c_struct_f64_f64_f64_f64(struct Struct_f64_f64_f64_f64 s, size_t i) {
    assert_or_panic(s.a == 14);
    assert_or_panic(s.b == 15);
    assert_or_panic(s.c == 16);
    assert_or_panic(s.d == 17);
    assert_or_panic(i == 18);
}
void c_test_struct_f64_f64_f64_f64(void) {
    struct Struct_f64_f64_f64_f64 s = zig_ret_struct_f64_f64_f64_f64();
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
    assert_or_panic(s.c == 3);
    assert_or_panic(s.d == 4);
    zig_struct_f64_f64_f64_f64((struct Struct_f64_f64_f64_f64){ .a = 5, .b = 6, .c = 7, .d = 8 }, 9);
}

struct Struct_f64_f64_f64_f64_f64 {
    double a, b, c, d, e;
};

struct Struct_f64_f64_f64_f64_f64 zig_ret_struct_f64_f64_f64_f64_f64(void);
void zig_struct_f64_f64_f64_f64_f64(struct Struct_f64_f64_f64_f64_f64, size_t);

struct Struct_f64_f64_f64_f64_f64 c_ret_struct_f64_f64_f64_f64_f64(void) {
    return (struct Struct_f64_f64_f64_f64_f64){ .a = 12, .b = 13, .c = 14, .d = 15, .e = 16 };
}
void c_struct_f64_f64_f64_f64_f64(struct Struct_f64_f64_f64_f64_f64 s, size_t i) {
    assert_or_panic(s.a == 17);
    assert_or_panic(s.b == 18);
    assert_or_panic(s.c == 19);
    assert_or_panic(s.d == 20);
    assert_or_panic(s.e == 21);
    assert_or_panic(i == 22);
}
void c_test_struct_f64_f64_f64_f64_f64(void) {
    struct Struct_f64_f64_f64_f64_f64 s = zig_ret_struct_f64_f64_f64_f64_f64();
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
    assert_or_panic(s.c == 3);
    assert_or_panic(s.d == 4);
    assert_or_panic(s.e == 5);
    zig_struct_f64_f64_f64_f64_f64((struct Struct_f64_f64_f64_f64_f64){ .a = 6, .b = 7, .c = 8, .d = 9, .e = 10 }, 11);
}

struct Struct_u32_Union_u32_u32u32 {
    uint32_t a;
    union {
        struct {
            uint32_t d, e;
        } c;
    } b;
};

struct Struct_u32_Union_u32_u32u32 zig_ret_struct_u32_union_u32_u32u32(void);
void zig_struct_u32_union_u32_u32u32(struct Struct_u32_Union_u32_u32u32);

struct Struct_u32_Union_u32_u32u32 c_ret_struct_u32_union_u32_u32u32(void) {
    struct Struct_u32_Union_u32_u32u32 s;
    s.a = 1;
    s.b.c.d = 2;
    s.b.c.e = 3;
    return s;
}
void c_struct_u32_union_u32_u32u32(struct Struct_u32_Union_u32_u32u32 s) {
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b.c.d == 2);
    assert_or_panic(s.b.c.e == 3);
}
void c_test_struct_u32_union_u32_u32u32(void) {
    struct Struct_u32_Union_u32_u32u32 s = zig_ret_struct_u32_union_u32_u32u32();
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b.c.d == 2);
    assert_or_panic(s.b.c.e == 3);
    zig_struct_u32_union_u32_u32u32(s);
}

struct Struct_i32_i32 {
    int32_t a;
    int32_t b;
};

void zig_struct_i32_i32(struct Struct_i32_i32);

struct BigStruct {
    uint64_t a;
    uint64_t b;
    uint64_t c;
    uint64_t d;
    uint8_t e;
};

void zig_big_struct(struct BigStruct);

union BigUnion {
    struct BigStruct a;
};

void zig_big_union(union BigUnion);

struct MedStructMixed {
    uint32_t a;
    float b;
    float c;
    uint32_t d;
};

void zig_med_struct_mixed(struct MedStructMixed);
struct MedStructMixed zig_ret_med_struct_mixed();

void zig_small_packed_struct(uint8_t);
#ifndef ZIG_NO_I128
void zig_big_packed_struct(__int128);
#endif

struct SplitStructInts {
    uint64_t a;
    uint8_t b;
    uint32_t c;
};
void zig_split_struct_ints(struct SplitStructInts);

struct SplitStructMixed {
    uint64_t a;
    uint8_t b;
    float c;
};
void zig_split_struct_mixed(struct SplitStructMixed);
struct SplitStructMixed zig_ret_split_struct_mixed();

struct BigStruct zig_big_struct_both(struct BigStruct);

void run_c_tests(void) {
    zig_u8(0xff);
    zig_u16(0xfffe);
    zig_u32(0xfffffffd);
    zig_u64(0xfffffffffffffffc);

#ifndef ZIG_NO_I128
    {
        struct u128 s = {0xfffffffffffffffc};
        zig_struct_u128(s);
    }
#endif

    zig_i8(-1);
    zig_i16(-2);
    zig_i32(-3);
    zig_i64(-4);

#ifndef ZIG_NO_I128
    {
        struct i128 s = {-6};
        zig_struct_i128(s);
    }
#endif

    zig_five_integers(12, 34, 56, 78, 90);

    zig_f32(12.34f);
    zig_f64(56.78);
    zig_longdouble(12.34l);
    zig_five_floats(1.0f, 2.0f, 3.0f, 4.0f, 5.0f);

    zig_ptr((void *)0xdeadbeefL);

    zig_bool(true);

#ifndef ZIG_NO_COMPLEX
    // TODO: Resolve https://github.com/ziglang/zig/issues/8465
    //{
    //    float complex a = 1.25f + I * 2.6f;
    //    float complex b = 11.3f - I * 1.5f;
    //    float complex z = zig_cmultf(a, b);
    //    assert_or_panic(creal(z) == 1.5f);
    //    assert_or_panic(cimag(z) == 13.5f);
    //}

    {
        double complex a = 1.25 + I * 2.6;
        double complex b = 11.3 - I * 1.5;
        double complex z = zig_cmultd(a, b);
        assert_or_panic(creal(z) == 1.5);
        assert_or_panic(cimag(z) == 13.5);
    }

    {
        float a_r = 1.25f;
        float a_i = 2.6f;
        float b_r = 11.3f;
        float b_i = -1.5f;
        float complex z = zig_cmultf_comp(a_r, a_i, b_r, b_i);
        assert_or_panic(creal(z) == 1.5f);
        assert_or_panic(cimag(z) == 13.5f);
    }

    {
        double a_r = 1.25;
        double a_i = 2.6;
        double b_r = 11.3;
        double b_i = -1.5;
        double complex z = zig_cmultd_comp(a_r, a_i, b_r, b_i);
        assert_or_panic(creal(z) == 1.5);
        assert_or_panic(cimag(z) == 13.5);
    }
#endif

#if !(defined(__i386__) && defined(_WIN32))
#ifndef __loongarch__
#ifndef ZIG_MIPS64
#ifndef __powerpc__
#ifndef __s390x__
    {
        struct Struct_i32_i32 s = {1, 2};
        zig_struct_i32_i32(s);
    }
#endif
#endif
#endif
#endif
#endif

#ifndef __hexagon__
#ifndef __loongarch__
#ifndef ZIG_MIPS64
#ifndef __powerpc__
#ifndef __s390x__
    {
        struct BigStruct s = {1, 2, 3, 4, 5};
        zig_big_struct(s);
    }
#endif
#endif
#endif
#endif
#endif

#ifndef ZIG_NO_I128
    {
        __int128 s = 0;
        s |= 1 << 0;
        s |= (__int128)2 << 64;
        zig_big_packed_struct(s);
    }
#endif

    {
        uint8_t s = 0;
        s |= 0 << 0;
        s |= 1 << 2;
        s |= 2 << 4;
        s |= 3 << 6;
        zig_small_packed_struct(s);
    }

#ifndef __hexagon__
#ifndef __i386__
#ifndef __loongarch__
#ifndef ZIG_MIPS64
#ifndef __powerpc__
#ifndef __s390x__
    {
        struct SplitStructInts s = {1234, 100, 1337};
        zig_split_struct_ints(s);
    }
#endif
#endif
#endif
#endif
#endif
#endif

#ifndef __hexagon__
#ifndef __loongarch__
#ifndef ZIG_MIPS64
#ifndef __powerpc__
#ifndef __s390x__
    {
        struct MedStructMixed s = {1234, 100.0f, 1337.0f};
        zig_med_struct_mixed(s);
    }
#endif
#endif
#endif
#endif
#endif

#ifndef __hexagon__
#ifndef __i386__
#ifndef __loongarch__
#ifndef ZIG_MIPS64
#ifndef __powerpc__
#ifndef __s390x__
    {
        struct SplitStructMixed s = {1234, 100, 1337.0f};
        zig_split_struct_mixed(s);
    }
#endif
#endif
#endif
#endif
#endif
#endif

#ifndef __hexagon__
#ifndef __loongarch__
#ifndef ZIG_MIPS64
#ifndef __powerpc__
#ifndef __s390x__
    {
        struct BigStruct s = {30, 31, 32, 33, 34};
        struct BigStruct res = zig_big_struct_both(s);
        assert_or_panic(res.a == 20);
        assert_or_panic(res.b == 21);
        assert_or_panic(res.c == 22);
        assert_or_panic(res.d == 23);
        assert_or_panic(res.e == 24);
    }
#endif
#endif
#endif
#endif
#endif

    {
        assert_or_panic(zig_ret_bool() == 1);

        assert_or_panic(zig_ret_u8() == 0xff);
        assert_or_panic(zig_ret_u16() == 0xffff);
        assert_or_panic(zig_ret_u32() == 0xffffffff);
        assert_or_panic(zig_ret_u64() == 0xffffffffffffffff);

        assert_or_panic(zig_ret_i8() == -1);
        assert_or_panic(zig_ret_i16() == -1);
        assert_or_panic(zig_ret_i32() == -1);
        assert_or_panic(zig_ret_i64() == -1);
    }
}

void c_u8(uint8_t x) {
    assert_or_panic(x == 0xff);
}

void c_u16(uint16_t x) {
    assert_or_panic(x == 0xfffe);
}

void c_u32(uint32_t x) {
    assert_or_panic(x == 0xfffffffd);
}

void c_u64(uint64_t x) {
    assert_or_panic(x == 0xfffffffffffffffcULL);
}

#ifndef ZIG_NO_I128
void c_struct_u128(struct u128 x) {
    assert_or_panic(x.value == 0xfffffffffffffffcULL);
}
#endif

void c_i8(int8_t x) {
    assert_or_panic(x == -1);
}

void c_i16(int16_t x) {
    assert_or_panic(x == -2);
}

void c_i32(int32_t x) {
    assert_or_panic(x == -3);
}

void c_i64(int64_t x) {
    assert_or_panic(x == -4);
}

#ifndef ZIG_NO_I128
void c_struct_i128(struct i128 x) {
    assert_or_panic(x.value == -6);
}
#endif

void c_f32(float x) {
    assert_or_panic(x == 12.34f);
}

void c_f64(double x) {
    assert_or_panic(x == 56.78);
}

void c_long_double(long double x) {
    assert_or_panic(x == 12.34l);
}

void c_ptr(void *x) {
    assert_or_panic(x == (void *)0xdeadbeefL);
}

void c_bool(bool x) {
    assert_or_panic(x);
}

void c_five_integers(int32_t a, int32_t b, int32_t c, int32_t d, int32_t e) {
    assert_or_panic(a == 12);
    assert_or_panic(b == 34);
    assert_or_panic(c == 56);
    assert_or_panic(d == 78);
    assert_or_panic(e == 90);
}

void c_five_floats(float a, float b, float c, float d, float e) {
    assert_or_panic(a == 1.0);
    assert_or_panic(b == 2.0);
    assert_or_panic(c == 3.0);
    assert_or_panic(d == 4.0);
    assert_or_panic(e == 5.0);
}

#ifndef ZIG_NO_COMPLEX
float complex c_cmultf_comp(float a_r, float a_i, float b_r, float b_i) {
    assert_or_panic(a_r == 1.25f);
    assert_or_panic(a_i == 2.6f);
    assert_or_panic(b_r == 11.3f);
    assert_or_panic(b_i == -1.5f);

    return 1.5f + I * 13.5f;
}

double complex c_cmultd_comp(double a_r, double a_i, double b_r, double b_i) {
    assert_or_panic(a_r == 1.25);
    assert_or_panic(a_i == 2.6);
    assert_or_panic(b_r == 11.3);
    assert_or_panic(b_i == -1.5);

    return 1.5 + I * 13.5;
}

float complex c_cmultf(float complex a, float complex b) {
    assert_or_panic(creal(a) == 1.25f);
    assert_or_panic(cimag(a) == 2.6f);
    assert_or_panic(creal(b) == 11.3f);
    assert_or_panic(cimag(b) == -1.5f);

    return 1.5f + I * 13.5f;
}

double complex c_cmultd(double complex a, double complex b) {
    assert_or_panic(creal(a) == 1.25);
    assert_or_panic(cimag(a) == 2.6);
    assert_or_panic(creal(b) == 11.3);
    assert_or_panic(cimag(b) == -1.5);

    return 1.5 + I * 13.5;
}
#endif

struct Struct_i32_i32 c_mut_struct_i32_i32(struct Struct_i32_i32 s) {
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
    s.a += 100;
    s.b += 250;
    assert_or_panic(s.a == 101);
    assert_or_panic(s.b == 252);
    return s;
}

void c_struct_i32_i32(struct Struct_i32_i32 s) {
    assert_or_panic(s.a == 1);
    assert_or_panic(s.b == 2);
}

void c_big_struct(struct BigStruct x) {
    assert_or_panic(x.a == 1);
    assert_or_panic(x.b == 2);
    assert_or_panic(x.c == 3);
    assert_or_panic(x.d == 4);
    assert_or_panic(x.e == 5);
}

void c_big_union(union BigUnion x) {
    assert_or_panic(x.a.a == 1);
    assert_or_panic(x.a.b == 2);
    assert_or_panic(x.a.c == 3);
    assert_or_panic(x.a.d == 4);
}

void c_med_struct_mixed(struct MedStructMixed x) {
    assert_or_panic(x.a == 1234);
    assert_or_panic(x.b == 100.0f);
    assert_or_panic(x.c == 1337.0f);

    struct MedStructMixed y = zig_ret_med_struct_mixed();

    assert_or_panic(y.a == 1234);
    assert_or_panic(y.b == 100.0f);
    assert_or_panic(y.c == 1337.0f);
}

struct MedStructMixed c_ret_med_struct_mixed(void) {
    struct MedStructMixed s = {
        .a = 1234,
        .b = 100.0,
        .c = 1337.0,
    };
    return s;
}

void c_split_struct_ints(struct SplitStructInts x) {
    assert_or_panic(x.a == 1234);
    assert_or_panic(x.b == 100);
    assert_or_panic(x.c == 1337);
}

void c_split_struct_mixed(struct SplitStructMixed x) {
    assert_or_panic(x.a == 1234);
    assert_or_panic(x.b == 100);
    assert_or_panic(x.c == 1337.0f);
    struct SplitStructMixed y = zig_ret_split_struct_mixed();

    assert_or_panic(y.a == 1234);
    assert_or_panic(y.b == 100);
    assert_or_panic(y.c == 1337.0f);
}

uint8_t c_ret_small_packed_struct(void) {
    uint8_t s = 0;
    s |= 0 << 0;
    s |= 1 << 2;
    s |= 2 << 4;
    s |= 3 << 6;
    return s;
}

void c_small_packed_struct(uint8_t x) {
    assert_or_panic(((x >> 0) & 0x3) == 0);
    assert_or_panic(((x >> 2) & 0x3) == 1);
    assert_or_panic(((x >> 4) & 0x3) == 2);
    assert_or_panic(((x >> 6) & 0x3) == 3);
}

#ifndef ZIG_NO_I128
__int128 c_ret_big_packed_struct(void) {
    __int128 s = 0;
    s |= 1 << 0;
    s |= (__int128)2 << 64;
    return s;
}

void c_big_packed_struct(__int128 x) {
    assert_or_panic(((x >> 0) & 0xFFFFFFFFFFFFFFFF) == 1);
    assert_or_panic(((x >> 64) & 0xFFFFFFFFFFFFFFFF) == 2);
}
#endif

struct SplitStructMixed c_ret_split_struct_mixed(void) {
    struct SplitStructMixed s = {
        .a = 1234,
        .b = 100,
        .c = 1337.0f,
    };
    return s;
}

struct BigStruct c_big_struct_both(struct BigStruct x) {
    assert_or_panic(x.a == 1);
    assert_or_panic(x.b == 2);
    assert_or_panic(x.c == 3);
    assert_or_panic(x.d == 4);
    assert_or_panic(x.e == 5);
    struct BigStruct y = {10, 11, 12, 13, 14};
    return y;
}

bool c_ret_bool(void) {
    return 1;
}
uint8_t c_ret_u8(void) {
    return 0xff;
}
uint16_t c_ret_u16(void) {
    return 0xffff;
}
uint32_t c_ret_u32(void) {
    return 0xffffffff;
}
uint64_t c_ret_u64(void) {
    return 0xffffffffffffffff;
}
int8_t c_ret_i8(void) {
    return -1;
}
int16_t c_ret_i16(void) {
    return -1;
}
int32_t c_ret_i32(void) {
    return -1;
}
int64_t c_ret_i64(void) {
    return -1;
}

typedef struct {
    uint32_t a;
    uint8_t padding[4];
    uint64_t b;
} StructWithArray;

void c_struct_with_array(StructWithArray x) {
    assert_or_panic(x.a == 1);
    assert_or_panic(x.b == 2);
}

StructWithArray c_ret_struct_with_array(void) {
    return (StructWithArray){4, {}, 155};
}

typedef struct {
    struct Point {
        double x;
        double y;
    } origin;
    struct Size {
        double width;
        double height;
    } size;
} FloatArrayStruct;

void c_float_array_struct(FloatArrayStruct x) {
    assert_or_panic(x.origin.x == 5);
    assert_or_panic(x.origin.y == 6);
    assert_or_panic(x.size.width == 7);
    assert_or_panic(x.size.height == 8);
}

FloatArrayStruct c_ret_float_array_struct(void) {
    FloatArrayStruct x;
    x.origin.x = 1;
    x.origin.y = 2;
    x.size.width = 3;
    x.size.height = 4;
    return x;
}

typedef uint32_t SmallVec __attribute__((vector_size(2 * sizeof(uint32_t))));

void c_small_vec(SmallVec vec) {
    assert_or_panic(vec[0] == 1);
    assert_or_panic(vec[1] == 2);
}

SmallVec c_ret_small_vec(void) {
    return (SmallVec){3, 4};
}

typedef size_t MediumVec __attribute__((vector_size(4 * sizeof(size_t))));

void c_medium_vec(MediumVec vec) {
    assert_or_panic(vec[0] == 1);
    assert_or_panic(vec[1] == 2);
    assert_or_panic(vec[2] == 3);
    assert_or_panic(vec[3] == 4);
}

MediumVec c_ret_medium_vec(void) {
    return (MediumVec){5, 6, 7, 8};
}

typedef size_t BigVec __attribute__((vector_size(8 * sizeof(size_t))));

void c_big_vec(BigVec vec) {
    assert_or_panic(vec[0] == 1);
    assert_or_panic(vec[1] == 2);
    assert_or_panic(vec[2] == 3);
    assert_or_panic(vec[3] == 4);
    assert_or_panic(vec[4] == 5);
    assert_or_panic(vec[5] == 6);
    assert_or_panic(vec[6] == 7);
    assert_or_panic(vec[7] == 8);
}

BigVec c_ret_big_vec(void) {
    return (BigVec){9, 10, 11, 12, 13, 14, 15, 16};
}

typedef struct {
    float x, y;
} Vector2;

void c_ptr_size_float_struct(Vector2 vec) {
    assert_or_panic(vec.x == 1);
    assert_or_panic(vec.y == 2);
}
Vector2 c_ret_ptr_size_float_struct(void) {
    return (Vector2){3, 4};
}

/// Tests for Double + Char struct
struct DC { double v1; char v2; };

int c_assert_DC(struct DC lv){
  if (lv.v1 != -0.25) return 1;
  if (lv.v2 != 15) return 2;
  return 0;
}
struct DC c_ret_DC(){
    struct DC lv = { .v1 = -0.25, .v2 = 15 };
    return lv;
}
int zig_assert_DC(struct DC);
int c_send_DC(){
    return zig_assert_DC(c_ret_DC());
}
struct DC zig_ret_DC();
int c_assert_ret_DC(){
    return c_assert_DC(zig_ret_DC());
}

/// Tests for Char + Float + Float struct
struct CFF { char v1; float v2; float v3; };

int c_assert_CFF(struct CFF lv){
  if (lv.v1 != 39) return 1;
  if (lv.v2 != 0.875) return 2;
  if (lv.v3 != 1.0) return 3;
  return 0;
}
struct CFF c_ret_CFF(){
    struct CFF lv = { .v1 = 39, .v2 = 0.875, .v3 = 1.0 };
    return lv;
}
int zig_assert_CFF(struct CFF);
int c_send_CFF(){
    return zig_assert_CFF(c_ret_CFF());
}
struct CFF zig_ret_CFF();
int c_assert_ret_CFF(){
    return c_assert_CFF(zig_ret_CFF());
}

struct PD { void* v1; double v2; };

int c_assert_PD(struct PD lv){
  if (lv.v1 != 0) return 1;
  if (lv.v2 != 0.5) return 2;
  return 0;
}
struct PD c_ret_PD(){
    struct PD lv = { .v1 = 0, .v2 = 0.5 };
    return lv;
}
int zig_assert_PD(struct PD);
int c_send_PD(){
    return zig_assert_PD(c_ret_PD());
}
struct PD zig_ret_PD();
int c_assert_ret_PD(){
    return c_assert_PD(zig_ret_PD());
}

struct ByRef {
    int val;
    int arr[15];
};
struct ByRef c_modify_by_ref_param(struct ByRef in) {
    in.val = 42;
    return in;
}

struct ByVal {
    struct {
        unsigned long x;
        unsigned long y;
        unsigned long z;
    } origin;
    struct {
        unsigned long width;
        unsigned long height;
        unsigned long depth;
    } size;
};

void c_func_ptr_byval(void *a, void *b, struct ByVal in, unsigned long c, void *d, unsigned long e) {
    assert_or_panic((intptr_t)a == 1);
    assert_or_panic((intptr_t)b == 2);

    assert_or_panic(in.origin.x == 9);
    assert_or_panic(in.origin.y == 10);
    assert_or_panic(in.origin.z == 11);
    assert_or_panic(in.size.width == 12);
    assert_or_panic(in.size.height == 13);
    assert_or_panic(in.size.depth == 14);

    assert_or_panic(c == 3);
    assert_or_panic((intptr_t)d == 4);
    assert_or_panic(e == 5);
}

#ifndef ZIG_NO_RAW_F16
__fp16 c_f16(__fp16 a) {
    assert_or_panic(a == 12);
    return 34;
}
#endif

typedef struct {
    __fp16 a;
} f16_struct;
f16_struct c_f16_struct(f16_struct a) {
    assert_or_panic(a.a == 12);
    return (f16_struct){34};
}

#if (defined __x86_64__ || defined __i386__) && !defined _MSC_VER
typedef long double f80;
f80 c_f80(f80 a) {
    assert_or_panic((double)a == 12.34);
    return 56.78;
}
typedef struct {
    f80 a;
} f80_struct;
f80_struct c_f80_struct(f80_struct a) {
    assert_or_panic((double)a.a == 12.34);
    return (f80_struct){56.78};
}
typedef struct {
    f80 a;
    int b;
} f80_extra_struct;
f80_extra_struct c_f80_extra_struct(f80_extra_struct a) {
    assert_or_panic((double)a.a == 12.34);
    assert_or_panic(a.b == 42);
    return (f80_extra_struct){56.78, 24};
}
#endif

#ifndef ZIG_NO_F128
__float128 zig_f128(__float128 a);
__float128 c_f128(__float128 a) {
    assert_or_panic((double)a == 12.34);
    assert_or_panic(zig_f128(12) == 34);
    return 56.78;
}
typedef struct {
    __float128 a;
} f128_struct;
f128_struct zig_f128_struct(f128_struct a);
f128_struct c_f128_struct(f128_struct a) {
    assert_or_panic((double)a.a == 12.34);
    f128_struct b = zig_f128_struct((f128_struct){12345});
    assert_or_panic(b.a == 98765);
    return (f128_struct){56.78};
}

typedef struct {
    __float128 a, b;
} f128_f128_struct;
f128_f128_struct zig_f128_f128_struct(f128_f128_struct a);
f128_f128_struct c_f128_f128_struct(f128_f128_struct a) {
    assert_or_panic((double)a.a == 12.34);
    assert_or_panic((double)a.b == 87.65);
    f128_f128_struct b = zig_f128_f128_struct((f128_f128_struct){13, 57});
    assert_or_panic((double)b.a == 24);
    assert_or_panic((double)b.b == 68);
    return (f128_f128_struct){56.78, 43.21};
}
#endif

void __attribute__((stdcall)) stdcall_scalars(char a, short b, int c, float d, double e) {
    assert_or_panic(a == 1);
    assert_or_panic(b == 2);
    assert_or_panic(c == 3);
    assert_or_panic(d == 4.0);
    assert_or_panic(e == 5.0);
}

typedef struct {
    short x;
    short y;
} Coord2;

Coord2 __attribute__((stdcall)) stdcall_coord2(Coord2 a, Coord2 b, Coord2 c) {
    assert_or_panic(a.x == 0x1111);
    assert_or_panic(a.y == 0x2222);
    assert_or_panic(b.x == 0x3333);
    assert_or_panic(b.y == 0x4444);
    assert_or_panic(c.x == 0x5555);
    assert_or_panic(c.y == 0x6666);
    return (Coord2){123, 456};
}

void __attribute__((stdcall)) stdcall_big_union(union BigUnion x) {
    assert_or_panic(x.a.a == 1);
    assert_or_panic(x.a.b == 2);
    assert_or_panic(x.a.c == 3);
    assert_or_panic(x.a.d == 4);
}

#ifdef __x86_64__
struct ByRef __attribute__((ms_abi)) c_explict_win64(struct ByRef in) {
    in.val = 42;
    return in;
}

struct ByRef __attribute__((sysv_abi)) c_explict_sys_v(struct ByRef in) {
    in.val = 42;
    return in;
}
#endif

struct byval_tail_callsite_attr_Point {
    double x;
    double y;
} Point;
struct byval_tail_callsite_attr_Size {
    double width;
    double height;
} Size;
struct byval_tail_callsite_attr_Rect {
    struct byval_tail_callsite_attr_Point origin;
    struct byval_tail_callsite_attr_Size size;
};
double c_byval_tail_callsite_attr(struct byval_tail_callsite_attr_Rect in) {
    return in.size.width;
}

#if defined(__i386__) && defined(_WIN32) && !defined(_WIN64) && defined(_MSC_VER)
void __attribute__((fastcall)) zig_fastcall_check(int a, float b, void *c, double d, int e);
void __attribute__((fastcall)) c_fastcall_check(int a, float b, void *c, double d, int e) {
    assert_or_panic(a == 1);
    assert_or_panic(b == 2.0);
    assert_or_panic((uintptr_t)c == 3);
    assert_or_panic(d == 4.0);
    assert_or_panic(e == 5);
}

typedef struct {
    int a;
    int b;
    int c;
} FastcallSRet;
FastcallSRet __attribute__((fastcall)) zig_fastcall_sret(void);
FastcallSRet __attribute__((fastcall)) c_fastcall_sret(void) {
    return (FastcallSRet){
        .a = 1,
        .b = 2,
        .c = 3
    };
}

typedef struct {
    char a;
    short b;
} FastcallNoSRet;
FastcallNoSRet __attribute__((fastcall)) zig_fastcall_no_sret(void);
FastcallNoSRet __attribute__((fastcall)) c_fastcall_no_sret(void) {
    return (FastcallNoSRet){
        .a = 1,
        .b = 2
    };
}

typedef struct {
    float a;
    float b;
} FastcallNoSRetF32F32;
FastcallNoSRetF32F32 __attribute__((fastcall)) zig_fastcall_no_sret_f32_f32(void);
FastcallNoSRetF32F32 __attribute__((fastcall)) c_fastcall_no_sret_f32_f32(void) {
    return (FastcallNoSRetF32F32){
        .a = 1,
        .b = 2
    };
}

typedef struct {
    double a;
} FastcallNoSRetF64;
FastcallNoSRetF64 __attribute__((fastcall)) zig_fastcall_no_sret_f64(void);
FastcallNoSRetF64 __attribute__((fastcall)) c_fastcall_no_sret_f64(void) {
    return (FastcallNoSRetF64){
        .a = 1
    };
}

float __attribute__((fastcall)) zig_fastcall_ret_f32(void);
float __attribute__((fastcall)) c_fastcall_ret_f32(void) {
    return 1;
}

double __attribute__((fastcall)) zig_fastcall_ret_f64(void);
double __attribute__((fastcall)) c_fastcall_ret_f64(void) {
    return 1;
}

void run_c_fastcall_tests(void) {
    {
        zig_fastcall_check(1, 2, (void*)3, 4, 5);
    }
    {
        const FastcallSRet s = zig_fastcall_sret();
        assert_or_panic(s.a == 1);
        assert_or_panic(s.b == 2);
        assert_or_panic(s.c == 3);
    }
    {
        const FastcallNoSRet s = zig_fastcall_no_sret();
        assert_or_panic(s.a == 1);
        assert_or_panic(s.b == 2);
    }
    {
        const FastcallNoSRetF32F32 s = zig_fastcall_no_sret_f32_f32();
        assert_or_panic(s.a == 1);
        assert_or_panic(s.b == 2);
    }
    {
        const FastcallNoSRetF64 s = zig_fastcall_no_sret_f64();
        assert_or_panic(s.a == 1);
    }
    {
        const float s = zig_fastcall_ret_f32();
        assert_or_panic(s == 1);
    }
    {
        const double s = zig_fastcall_ret_f64();
        assert_or_panic(s == 1);
    }
}

void __attribute__((vectorcall)) zig_vectorcall_check(int a, float b, double c, void *d, float e, double f, double g, float h, float i, int j);
void __attribute__((vectorcall)) c_vectorcall_check(int a, float b, double c, void *d, float e, double f, double g, float h, float i, int j) {
    assert_or_panic(a == 1);
    assert_or_panic(b == 2.0);
    assert_or_panic(c == 3.0);
    assert_or_panic((uintptr_t)d == 4);
    assert_or_panic(e == 5.0);
    assert_or_panic(f == 6.0);
    assert_or_panic(g == 7.0);
    assert_or_panic(h == 8.0);
    assert_or_panic(i == 9.0);
    assert_or_panic(j == 10);
    zig_vectorcall_check(a, b, c, d, e, f, g, h, i, j);
}
#endif

#if defined(__x86_64__) && defined(_WIN64)
void c_win64_varargs_u64_f64_u64_f64(uint64_t a, double b, uint64_t c, double d) {
    assert_or_panic(a == UINT64_C(0x3ff0000000000000));
    assert_or_panic(b == 2.0);
    assert_or_panic(c == UINT64_C(0x4008000000000000));
    assert_or_panic(d == 4.0);
}
void c_win64_varargs_f64_u64_f64_u64(double a, uint64_t b, double c, uint64_t d) {
    assert_or_panic(a == 5.0);
    assert_or_panic(b == UINT64_C(0x4018000000000000));
    assert_or_panic(c == 7.0);
    assert_or_panic(d == UINT64_C(0x4020000000000000));
}
#endif

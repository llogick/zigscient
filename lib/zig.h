#undef linux

#include <stdarg.h>
#include <stddef.h>

#if defined(_MSC_VER)
#define zig_msvc
#elif defined(__clang__)
#define zig_clang
#define zig_gnuc
#elif defined(__GNUC__)
#define zig_gcc
#define zig_gnuc
#elif defined(__TINYC__)
#define zig_tinyc
#elif defined(__slimcc__)
#define zig_slimcc
#endif

#if defined(__aarch64__) || (defined(zig_msvc) && defined(_M_ARM64))
#define zig_aarch64
#elif defined(__alpha__)
#define zig_alpha
#elif defined(__thumb__) || (defined(zig_msvc) && defined(_M_ARM))
#define zig_thumb
#define zig_arm
#elif defined(__arm__)
#define zig_arm
#elif defined(__arc__)
#define zig_arc
#elif defined(__csky__)
#define zig_csky
#elif defined(__hexagon__)
#define zig_hexagon
#elif defined(__hppa__) && defined(_LP64)
#define zig_hppa64
#define zig_hppa
#elif defined(__hppa__)
#define zig_hppa32
#define zig_hppa
#elif defined(__kvx__)
#define zig_kvx
#elif defined(__loongarch32)
#define zig_loongarch32
#define zig_loongarch
#elif defined(__loongarch64)
#define zig_loongarch64
#define zig_loongarch
#elif defined(__m68k__)
#define zig_m68k
#elif defined(__m88k__)
#define zig_m88k
#elif defined(__microblaze__)
#define zig_microblaze
#elif defined(__mips64)
#define zig_mips64
#define zig_mips
#elif defined(__mips__)
#define zig_mips32
#define zig_mips
#elif defined(__or1k__)
#define zig_or1k
#elif defined(__powerpc64__)
#define zig_powerpc64
#define zig_powerpc
#elif defined(__powerpc__)
#define zig_powerpc32
#define zig_powerpc
#elif defined(__riscv) && __riscv_xlen == 32
#define zig_riscv32
#define zig_riscv
#elif defined(__riscv) && __riscv_xlen == 64
#define zig_riscv64
#define zig_riscv
#elif defined(__s390x__)
#define zig_s390x
#elif defined(__sh__)
#define zig_sh
#elif defined(__sparc__) && defined(__arch64__)
#define zig_sparc64
#define zig_sparc
#elif defined(__sparc__)
#define zig_sparc32
#define zig_sparc
#elif defined(__wasm32__)
#define zig_wasm32
#define zig_wasm
#elif defined(__wasm64__)
#define zig_wasm64
#define zig_wasm
#elif defined(__i386__) || (defined(zig_msvc) && defined(_M_IX86))
#define zig_x86_32
#define zig_x86
#elif defined (__x86_64__) || (defined(zig_msvc) && defined(_M_X64))
#define zig_x86_64
#define zig_x86
#elif defined(__I86__)
#define zig_x86_16
#define zig_x86
#elif defined(__xtensa__)
#define zig_xtensa
#elif defined (__ez80)
#define zig_ez80
#define zig_z80
#endif

#if defined(zig_msvc) || __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#define zig_little_endian 1
#define zig_big_endian 0
#else
#define zig_little_endian 0
#define zig_big_endian 1
#endif

#if defined(__APPLE__)
#define zig_darwin
#elif defined(__DragonFly__)
#define zig_dragonfly
#elif defined(__EMSCRIPTEN__)
#define zig_emscripten
#elif defined(__FreeBSD__)
#define zig_freebsd
#elif defined(__Fuchsia__)
#define zig_fuchsia
#elif defined(__HAIKU__)
#define zig_haiku
#elif defined(__gnu_hurd__)
#define zig_hurd
#elif defined(__illumos__)
#define zig_illumos
#elif defined(__linux__)
#define zig_linux
#elif defined(__NetBSD__)
#define zig_netbsd
#elif defined(__OpenBSD__)
#define zig_openbsd
#elif defined(__serenity__)
#define zig_serenity
#elif defined(__wasi__)
#define zig_wasi
#elif defined(_WIN32)
#define zig_windows
#endif

#if defined(zig_windows)
#define zig_coff
#elif defined(__ELF__)
#define zig_elf
#elif defined(zig_darwin)
#define zig_macho
#endif

#define zig_concat(lhs, rhs) lhs##rhs
#define zig_expand_concat(lhs, rhs) zig_concat(lhs, rhs)

#if defined(__has_include)
#define zig_has_include(include) __has_include(include)
#else
#define zig_has_include(include) 0
#endif

#if defined(__has_builtin)
#define zig_has_builtin(builtin) __has_builtin(__builtin_##builtin)
#else
#define zig_has_builtin(builtin) 0
#endif
#define zig_expand_has_builtin(b) zig_has_builtin(b)

#if defined(__has_feature)
#define zig_has_feature(feature) __has_feature(feature)
#else
#define zig_has_feature(feature) 0
#endif

#if defined(__has_attribute)
#define zig_has_attribute(attribute) __has_attribute(attribute)
#else
#define zig_has_attribute(attribute) 0
#endif

#if __STDC_VERSION__ >= 201112L
#define zig_static_assert(cond, msg) _Static_assert(cond, msg)
#elif zig_has_attribute(unused)
#define zig_static_assert(cond, msg) typedef char zig_expand_concat(zig_static_assert_fail_, __LINE__)[(cond) ? 1 : -1] __attribute__((unused))
#else
#define zig_static_assert(cond, msg) typedef char zig_expand_concat(zig_static_assert_fail_, __LINE__)[(cond) ? 1 : -1]
#endif

#if __STDC_VERSION__ >= 202311L
#define zig_threadlocal thread_local
#elif __STDC_VERSION__ >= 201112L
#define zig_threadlocal _Thread_local
#elif defined(zig_gnuc) || defined(zig_slimcc)
#define zig_threadlocal __thread
#elif defined(zig_msvc)
#define zig_threadlocal __declspec(thread)
#else
#define zig_threadlocal zig_threadlocal_unavailable
#endif

#if defined(zig_msvc)
#define zig_callconv(c) __##c
#else
#define zig_callconv(c) __attribute__((c))
#endif

#if zig_has_attribute(naked) || defined(zig_gcc)
#define zig_naked_decl __attribute__((naked))
#define zig_naked __attribute__((naked))
#elif defined(zig_msvc)
#define zig_naked_decl
#define zig_naked __declspec(naked)
#else
#define zig_naked_decl zig_naked_unavailable
#define zig_naked zig_naked_unavailable
#endif

#if zig_has_attribute(cold)
#define zig_cold __attribute__((cold))
#else
#define zig_cold
#endif

#if zig_has_attribute(flatten)
#define zig_maybe_flatten __attribute__((flatten))
#else
#define zig_maybe_flatten
#endif

#if zig_has_attribute(noinline)
#define zig_never_inline __attribute__((noinline)) zig_maybe_flatten
#elif defined(zig_msvc)
#define zig_never_inline __declspec(noinline) zig_maybe_flatten
#else
#define zig_never_inline zig_never_inline_unavailable
#endif

#if zig_has_attribute(not_tail_called)
#define zig_never_tail __attribute__((not_tail_called)) zig_never_inline
#else
#define zig_never_tail zig_never_tail_unavailable
#endif

#if zig_has_attribute(musttail)
#define zig_always_tail __attribute__((musttail))
#else
#define zig_always_tail zig_always_tail_unavailable
#endif

#if __STDC_VERSION__ >= 199901L
#define zig_restrict restrict
#elif defined(zig_gnuc) || defined(zig_tinyc)
#define zig_restrict __restrict
#else
#define zig_restrict
#endif

#if zig_has_attribute(no_builtin)
#define zig_no_builtin __attribute__((no_builtin))
#else
#define zig_no_builtin
#endif

#if zig_has_attribute(aligned) || defined(zig_tinyc)
#define zig_under_align(alignment) __attribute__((aligned(alignment)))
#elif defined(zig_msvc)
#define zig_under_align(alignment) __declspec(align(alignment))
#else
#define zig_under_align zig_align_unavailable
#endif

#if __STDC_VERSION__ >= 202311L
#define zig_align(alignment) alignas(alignment)
#elif __STDC_VERSION__ >= 201112L || zig_has_feature(c_alignas)
#define zig_align(alignment) _Alignas(alignment)
#else
#define zig_align(alignment) zig_under_align(alignment)
#endif

#if __STDC_VERSION__ >= 202311L
#define zig_alignOf(Type) alignof(Type)
#elif __STDC_VERSION__ >= 201112L || zig_has_feature(c_alignof)
#define zig_alignOf(Type) _Alignof(Type)
#else
#define zig_alignOf(Type) (sizeof(struct { char c; Type t; }) - sizeof(Type))
#endif

#if zig_has_attribute(aligned) || defined(zig_tinyc)
#define zig_align_fn(alignment) __attribute__((aligned(alignment)))
#elif defined(zig_msvc)
#define zig_align_fn(alignment)
#else
#define zig_align_fn zig_align_fn_unavailable
#endif

#if zig_has_attribute(nonstring)
#define zig_nonstring __attribute__((nonstring))
#else
#define zig_nonstring
#endif

#if zig_has_attribute(packed) || defined(zig_tinyc)
#define zig_packed(definition) definition __attribute__((packed))
#elif defined(zig_msvc)
#define zig_packed(definition) __pragma(pack(1)) definition __pragma(pack())
#else
#define zig_packed(definition) zig_packed_unavailable
#endif

#if zig_has_attribute(section) || defined(zig_tinyc)
#define zig_linksection(name) __attribute__((section(name)))
#define zig_linksection_fn zig_linksection
#elif defined(zig_msvc)
#define zig_linksection(name) __pragma(section(name, read, write)) __declspec(allocate(name))
#define zig_linksection_fn(name) __pragma(section(name, read, execute)) __declspec(code_seg(name))
#else
#define zig_linksection(name) zig_linksection_unavailable
#define zig_linksection_fn zig_linksection
#endif

#if zig_has_attribute(visibility)
#define zig_visibility(name) __attribute__((visibility(#name)))
#else
#define zig_visibility(name) zig_visibility_##name
#define zig_visibility_default
#define zig_visibility_hidden zig_visibility_hidden_unavailable
#define zig_visibility_protected zig_visibility_protected_unavailable
#endif

#if zig_has_builtin(unreachable) || defined(zig_gcc) || defined(zig_tinyc)
#define zig_unreachable() __builtin_unreachable()
#elif defined(zig_msvc)
#define zig_unreachable() __assume(0)
#else
#define zig_unreachable()
#endif

#if defined(__cplusplus)
#define zig_extern extern "C"
#else
#define zig_extern extern
#endif

#if defined(zig_msvc)
#if defined(zig_x86_64)
#define zig_mangle_c(symbol) symbol
#else /* zig_x86_64 */
#define zig_mangle_c(symbol) "_" symbol
#endif /* zig_x86_64 */
#else /* zig_msvc */
#if defined(zig_macho)
#define zig_mangle_c(symbol) "_" symbol
#else /* zig_macho */
#define zig_mangle_c(symbol) symbol
#endif /* zig_macho */
#endif /* zig_msvc */

#if defined(zig_msvc)
#define zig_export(symbol, name) ; \
    __pragma(comment(linker, "/alternatename:" zig_mangle_c(name) "=" zig_mangle_c(symbol)))
#elif (zig_has_attribute(alias) || defined(zig_tinyc)) && !defined(zig_macho)
#define zig_export(symbol, name) __attribute__((alias(symbol)))
#else
#define zig_export(symbol, name) ; \
    __asm("\t.globl\t" zig_mangle_c(name) "\n" zig_mangle_c(name) " = " zig_mangle_c(symbol))
#endif

#if defined(zig_msvc)
#define zig_mangled(mangled, unmangled) ; \
    zig_export(#mangled, unmangled)
#define zig_mangled_export(mangled, unmangled, symbol) \
    zig_export(unmangled, #mangled) \
    zig_export(symbol, unmangled)
#else /* zig_msvc */
#define zig_mangled(mangled, unmangled) __asm(zig_mangle_c(unmangled))
#define zig_mangled_export(mangled, unmangled, symbol) \
    zig_mangled(mangled, unmangled) \
    zig_export(symbol, unmangled)
#endif /* zig_msvc */

#if defined(zig_msvc)
#define zig_import(Type, fn_name, libc_name, sig_args, call_args) zig_extern Type fn_name sig_args;\
    __pragma(comment(linker, "/alternatename:" zig_mangle_c(#fn_name) "=" zig_mangle_c(#libc_name)));
#define zig_import_builtin(Type, fn_name, libc_name, sig_args, call_args) zig_import(Type, fn_name, libc_name, sig_args, call_args)
#else /* zig_msvc */
#define zig_import(Type, fn_name, libc_name, sig_args, call_args) zig_extern Type fn_name sig_args __asm(zig_mangle_c(#libc_name));
#define zig_import_builtin(Type, fn_name, libc_name, sig_args, call_args) zig_extern Type libc_name sig_args; \
    static inline Type fn_name sig_args { return libc_name call_args; }
#endif

#define zig_expand_import_0(Type, fn_name, libc_name, sig_args, call_args) zig_import(Type, fn_name, libc_name, sig_args, call_args)
#define zig_expand_import_1(Type, fn_name, libc_name, sig_args, call_args) zig_import_builtin(Type, fn_name, libc_name, sig_args, call_args)

#if zig_has_attribute(weak) || defined(zig_gcc) || defined(zig_tinyc)
#define zig_weak_linkage __attribute__((weak))
#define zig_weak_linkage_fn __attribute__((weak))
#elif defined(zig_msvc)
#define zig_weak_linkage __declspec(selectany)
#define zig_weak_linkage_fn
#else
#define zig_weak_linkage zig_weak_linkage_unavailable
#define zig_weak_linkage_fn zig_weak_linkage_unavailable
#endif

#if defined(zig_gnuc) || defined(zig_tinyc) || defined(zig_slimcc)
#define zig_gnuc_asm
#endif

#if zig_has_builtin(trap)
#define zig_trap() __builtin_trap()
#elif defined(zig_msvc)

#if defined(zig_x86)
#define zig_trap() __ud2()
#else
#define zig_trap() __fastfail(7)
#endif

#elif defined(zig_gnuc_asm)

#if defined(zig_alpha)
#define zig_trap() __asm__ volatile("call_pal 0x000000")
#elif defined(zig_thumb)
#define zig_trap() __asm__ volatile("udf #0xfe")
#elif defined(zig_arm) || defined(zig_aarch64)
#define zig_trap() __asm__ volatile("udf #0xfdee")
#elif defined(zig_arc)
#define zig_trap() __asm__ volatile("unimp_s")
#elif defined(zig_csky)
#define zig_trap() __asm__ volatile(".word 0x3fff")
#elif defined(zig_hexagon)
#define zig_trap() __asm__ volatile("r27:26 = memd(#0xbadc0fee)")
#elif defined(zig_hppa)
#define zig_trap() __asm__ volatile("iitlbp %r0, (%sr0, %r0)")
#elif defined(zig_kvx) || defined(zig_loongarch) || defined(zig_powerpc)
#define zig_trap() __asm__ volatile(".word 0x0")
#elif defined(zig_m68k)
#define zig_trap() __asm__ volatile("illegal")
#elif defined(zig_m88k)
#define zig_trap() __asm__ volatile("tb0 0, %%r0, 511")
#elif defined(zig_microblaze)
#define zig_trap() __asm__ volatile("getd r0, r0")
#elif defined(zig_mips)
#define zig_trap() __asm__ volatile(".word 0x3d")
#elif defined(zig_or1k)
#define zig_trap() __asm__ volatile("l.cust8")
#elif defined(zig_riscv)
#define zig_trap() __asm__ volatile("unimp")
#elif defined(zig_s390x)
#define zig_trap() __asm__ volatile("j 0x2")
#elif defined(zig_sh)
#define zig_trap() __asm__ volatile(".word 0x0001")
#elif defined(zig_sparc)
#define zig_trap() __asm__ volatile("illtrap")
#elif defined(zig_x86_16)
#define zig_trap() __asm__ volatile("int $0x3")
#elif defined(zig_x86)
#define zig_trap() __asm__ volatile("ud2")
#elif defined(zig_xtensa)
#define zig_trap() __asm__ volatile("ill")
#elif defined(zig_z80)
#define zig_trap() __asm__ volatile("rst 00h")
#else
#define zig_trap() zig_trap_unavailable
#endif

#else
#define zig_trap() zig_trap_unavailable
#endif

#if zig_has_builtin(debugtrap)
#define zig_breakpoint() __builtin_debugtrap()
#elif defined(zig_msvc)
#define zig_breakpoint() __debugbreak()
#elif defined(zig_gnuc_asm)

#if defined(zig_alpha)
#define zig_breakpoint() __asm__ volatile("call_pal 0x000080")
#elif defined(zig_arm) || defined(zig_csky)
#define zig_breakpoint() __asm__ volatile("bkpt #0x0")
#elif defined(zig_aarch64)
#define zig_breakpoint() __asm__ volatile("brk #0xf000")
#elif defined(zig_arc)
#define zig_breakpoint() __asm__ volatile("brk_s")
#elif defined(zig_hexagon)
#define zig_breakpoint() __asm__ volatile("brkpt")
#elif defined(zig_hppa)
#define zig_breakpoint() __asm__ volatile("break 0x04, 0x0008")
#elif defined(zig_kvx) || defined(zig_loongarch)
#define zig_breakpoint() __asm__ volatile("break 0x0")
#elif defined(zig_m88k)
#define zig_breakpoint() __asm__ volatile("illop1")
#elif defined(zig_microblaze)
#define zig_breakpoint() __asm__ volatile("brki r16, 0x0018")
#elif defined(zig_mips)
#define zig_breakpoint() __asm__ volatile("break")
#elif defined(zig_or1k)
#define zig_breakpoint() __asm__ volatile("l.trap 0x0")
#elif defined(zig_powerpc)
#define zig_breakpoint() __asm__ volatile("trap")
#elif defined(zig_riscv)
#define zig_breakpoint() __asm__ volatile("ebreak")
#elif defined(zig_s390x)
#define zig_breakpoint() __asm__ volatile("j 0x6")
#elif defined(zig_sh)
#define zig_breakpoint() __asm__ volatile("trapa #0xc3")
#elif defined(zig_sparc)
#define zig_breakpoint() __asm__ volatile("ta 0x1")
#elif defined(zig_x86)
#define zig_breakpoint() __asm__ volatile("int $0x3")
#elif defined(zig_xtensa)
#define zig_breakpoint() __asm__ volatile("break 1, 1")
#else
#define zig_breakpoint() zig_breakpoint_unavailable
#endif

#else
#define zig_breakpoint() zig_breakpoint_unavailable
#endif

#if zig_has_builtin(return_address) || defined(zig_gcc) || defined(zig_tinyc)
#define zig_return_address() __builtin_extract_return_addr(__builtin_return_address(0))
#elif defined(zig_msvc)
#define zig_return_address() _ReturnAddress()
#else
#define zig_return_address() 0
#endif

#if zig_has_builtin(frame_address) || defined(zig_gcc) || defined(zig_tinyc)
#define zig_frame_address() __builtin_frame_address(0)
#elif defined(zig_msvc)
#define zig_frame_address() _AddressOfReturnAddress()
#else
#define zig_frame_address() 0
#endif

#if zig_has_builtin(prefetch) || defined(zig_gcc)
#define zig_prefetch(addr, rw, locality) __builtin_prefetch(addr, rw, locality)
#else
#define zig_prefetch(addr, rw, locality)
#endif

#if zig_has_builtin(memory_size) && zig_has_builtin(memory_grow)
#define zig_wasm_memory_size(index) __builtin_wasm_memory_size(index)
#define zig_wasm_memory_grow(index, delta) __builtin_wasm_memory_grow(index, delta)
#else
#define zig_wasm_memory_size(index) zig_unimplemented()
#define zig_wasm_memory_grow(index, delta) zig_unimplemented()
#endif

#if __STDC_VERSION__ >= 202311L
#define zig_noreturn [[noreturn]]
#elif __STDC_VERSION__ >= 201112L
#define zig_noreturn _Noreturn
#elif zig_has_attribute(noreturn) || defined(zig_gcc) || defined(zig_tinyc)
#define zig_noreturn __attribute__((noreturn))
#elif defined(zig_msvc)
#define zig_noreturn __declspec(noreturn)
#else
#define zig_noreturn
#endif

#define zig_has_always 1
#define zig_has_never 0

#define zig_compiler_rt_abbrev_uint32_t si
#define zig_compiler_rt_abbrev_int32_t  si
#define zig_compiler_rt_abbrev_uint64_t di
#define zig_compiler_rt_abbrev_int64_t  di
#define zig_compiler_rt_abbrev_zig_u128 ti
#define zig_compiler_rt_abbrev_zig_i128 ti
#define zig_compiler_rt_abbrev_zig_f16  hf
#define zig_compiler_rt_abbrev_zig_f32  sf
#define zig_compiler_rt_abbrev_zig_f64  df
#define zig_compiler_rt_abbrev_zig_f80  xf
#ifdef zig_powerpc
#define zig_compiler_rt_abbrev_zig_f128 kf
#else
#define zig_compiler_rt_abbrev_zig_f128 tf
#endif

zig_extern void *memcpy (void *zig_restrict, void const *zig_restrict, size_t);
zig_extern void *memset (void *, int, size_t);
zig_extern void *memmove (void *, void const *, size_t);

/* ================ Bool and 8/16/24/32/48/64-bit Integer Support ================= */

#include <limits.h>

#define zig_bitSizeOf(T) (CHAR_BIT * sizeof(T))

#if __STDC_VERSION__ >= 202311L
/* bool, true, and false are provided by the language. */
#elif __STDC_VERSION__ >= 199901L || zig_has_include(<stdbool.h>)
#include <stdbool.h>
#else
typedef char bool;
#define false 0
#define true  1
#endif

#if __STDC_VERSION__ >= 199901L || defined(zig_msvc) || zig_has_include(<stdint.h>)
#include <stdint.h>
#else
#if SCHAR_MIN == ~0x7F && SCHAR_MAX == 0x7F && UCHAR_MAX == 0xFF
typedef unsigned      char uint8_t;
typedef   signed      char  int8_t;
#define  INT8_C(c) c
#define UINT8_C(c) c##U
#elif SHRT_MIN == ~0x7F && SHRT_MAX == 0x7F && USHRT_MAX == 0xFF
typedef unsigned     short uint8_t;
typedef   signed     short  int8_t;
#define  INT8_C(c) c
#define UINT8_C(c) c##U
#elif INT_MIN == ~0x7F && INT_MAX == 0x7F && UINT_MAX == 0xFF
typedef unsigned       int uint8_t;
typedef   signed       int  int8_t;
#define  INT8_C(c) c
#define UINT8_C(c) c##U
#elif LONG_MIN == ~0x7F && LONG_MAX == 0x7F && ULONG_MAX == 0xFF
typedef unsigned      long uint8_t;
typedef   signed      long  int8_t;
#define  INT8_C(c) c##L
#define UINT8_C(c) c##LU
#elif LLONG_MIN == ~0x7F && LLONG_MAX == 0x7F && ULLONG_MAX == 0xFF
typedef unsigned long long uint8_t;
typedef   signed long long  int8_t;
#define  INT8_C(c) c##LL
#define UINT8_C(c) c##LLU
#endif
#define  INT8_MIN (~INT8_C(0x7F))
#define  INT8_MAX ( INT8_C(0x7F))
#define UINT8_MAX ( INT8_C(0xFF))

#if SCHAR_MIN == ~0x7FFF && SCHAR_MAX == 0x7FFF && UCHAR_MAX == 0xFFFF
typedef unsigned      char uint16_t;
typedef   signed      char  int16_t;
#define  INT16_C(c) c
#define UINT16_C(c) c##U
#elif SHRT_MIN == ~0x7FFF && SHRT_MAX == 0x7FFF && USHRT_MAX == 0xFFFF
typedef unsigned     short uint16_t;
typedef   signed     short  int16_t;
#define  INT16_C(c) c
#define UINT16_C(c) c##U
#elif INT_MIN == ~0x7FFF && INT_MAX == 0x7FFF && UINT_MAX == 0xFFFF
typedef unsigned       int uint16_t;
typedef   signed       int  int16_t;
#define  INT16_C(c) c
#define UINT16_C(c) c##U
#elif LONG_MIN == ~0x7FFF && LONG_MAX == 0x7FFF && ULONG_MAX == 0xFFFF
typedef unsigned      long uint16_t;
typedef   signed      long  int16_t;
#define  INT16_C(c) c##L
#define UINT16_C(c) c##LU
#elif LLONG_MIN == ~0x7FFF && LLONG_MAX == 0x7FFF && ULLONG_MAX == 0xFFFF
typedef unsigned long long uint16_t;
typedef   signed long long  int16_t;
#define  INT16_C(c) c##LL
#define UINT16_C(c) c##LLU
#endif
#define  INT16_MIN (~INT16_C(0x7FFF))
#define  INT16_MAX ( INT16_C(0x7FFF))
#define UINT16_MAX ( INT16_C(0xFFFF))

#if SCHAR_MIN == ~0x7FFFFFFF && SCHAR_MAX == 0x7FFFFFFF && UCHAR_MAX == 0xFFFFFFFF
typedef unsigned      char uint32_t;
typedef   signed      char  int32_t;
#define  INT32_C(c) c
#define UINT32_C(c) c##U
#elif SHRT_MIN == ~0x7FFFFFFF && SHRT_MAX == 0x7FFFFFFF && USHRT_MAX == 0xFFFFFFFF
typedef unsigned     short uint32_t;
typedef   signed     short  int32_t;
#define  INT32_C(c) c
#define UINT32_C(c) c##U
#elif INT_MIN == ~0x7FFFFFFF && INT_MAX == 0x7FFFFFFF && UINT_MAX == 0xFFFFFFFF
typedef unsigned       int uint32_t;
typedef   signed       int  int32_t;
#define  INT32_C(c) c
#define UINT32_C(c) c##U
#elif LONG_MIN == ~0x7FFFFFFF && LONG_MAX == 0x7FFFFFFF && ULONG_MAX == 0xFFFFFFFF
typedef unsigned      long uint32_t;
typedef   signed      long  int32_t;
#define  INT32_C(c) c##L
#define UINT32_C(c) c##LU
#elif LLONG_MIN == ~0x7FFFFFFF && LLONG_MAX == 0x7FFFFFFF && ULLONG_MAX == 0xFFFFFFFF
typedef unsigned long long uint32_t;
typedef   signed long long  int32_t;
#define  INT32_C(c) c##LL
#define UINT32_C(c) c##LLU
#endif
#define  INT32_MIN (~INT32_C(0x7FFFFFFF))
#define  INT32_MAX ( INT32_C(0x7FFFFFFF))
#define UINT32_MAX ( INT32_C(0xFFFFFFFF))

#if SCHAR_MIN == ~0x7FFFFFFFFFFFFFFF && SCHAR_MAX == 0x7FFFFFFFFFFFFFFF && UCHAR_MAX == 0xFFFFFFFFFFFFFFFF
typedef unsigned      char uint64_t;
typedef   signed      char  int64_t;
#define  INT64_C(c) c
#define UINT64_C(c) c##U
#elif SHRT_MIN == ~0x7FFFFFFFFFFFFFFF && SHRT_MAX == 0x7FFFFFFFFFFFFFFF && USHRT_MAX == 0xFFFFFFFFFFFFFFFF
typedef unsigned     short uint64_t;
typedef   signed     short  int64_t;
#define  INT64_C(c) c
#define UINT64_C(c) c##U
#elif INT_MIN == ~0x7FFFFFFFFFFFFFFF && INT_MAX == 0x7FFFFFFFFFFFFFFF && UINT_MAX == 0xFFFFFFFFFFFFFFFF
typedef unsigned       int uint64_t;
typedef   signed       int  int64_t;
#define  INT64_C(c) c
#define UINT64_C(c) c##U
#elif LONG_MIN == ~0x7FFFFFFFFFFFFFFF && LONG_MAX == 0x7FFFFFFFFFFFFFFF && ULONG_MAX == 0xFFFFFFFFFFFFFFFF
typedef unsigned      long uint64_t;
typedef   signed      long  int64_t;
#define  INT64_C(c) c##L
#define UINT64_C(c) c##LU
#elif LLONG_MIN == ~0x7FFFFFFFFFFFFFFF && LLONG_MAX == 0x7FFFFFFFFFFFFFFF && ULLONG_MAX == 0xFFFFFFFFFFFFFFFF
typedef unsigned long long uint64_t;
typedef   signed long long  int64_t;
#define  INT64_C(c) c##LL
#define UINT64_C(c) c##LLU
#endif
#define  INT64_MIN (~INT64_C(0x7FFFFFFFFFFFFFFF))
#define  INT64_MAX ( INT64_C(0x7FFFFFFFFFFFFFFF))
#define UINT64_MAX ( INT64_C(0xFFFFFFFFFFFFFFFF))

#if defined(zig_ez80)

typedef unsigned       int uint24_t;
typedef   signed       int  int24_t;
#define  INT24_C(c) c
#define UINT24_C(c) c##U
#define  INT24_MIN (~INT24_C(0x7FFF))
#define  INT24_MAX ( INT24_C(0x7FFF))
#define UINT24_MAX ( INT24_C(0xFFFF))

typedef unsigned   __int48 uint48_t;
typedef   signed   __int48  int48_t;
#define  INT48_C(c) c
/* no suffix */
#define UINT48_C(c) ((uint48_t)(c))
#define  INT48_MIN (~INT48_C(0x7FFFFFFFFFFF))
#define  INT48_MAX ( INT48_C(0x7FFFFFFFFFFF))
#define UINT48_MAX ( INT48_C(0xFFFFFFFFFFFF))

#endif

typedef size_t uintptr_t;
typedef ptrdiff_t intptr_t;

#endif

#define zig_minInt_i8    INT8_MIN
#define zig_maxInt_i8    INT8_MAX
#define zig_minInt_u8   UINT8_C(0)
#define zig_maxInt_u8   UINT8_MAX
#define zig_minInt_i16  INT16_MIN
#define zig_maxInt_i16  INT16_MAX
#define zig_minInt_u16 UINT16_C(0)
#define zig_maxInt_u16 UINT16_MAX
#define zig_minInt_i32  INT32_MIN
#define zig_maxInt_i32  INT32_MAX
#define zig_minInt_u32 UINT32_C(0)
#define zig_maxInt_u32 UINT32_MAX
#define zig_minInt_i64  INT64_MIN
#define zig_maxInt_i64  INT64_MAX
#define zig_minInt_u64 UINT64_C(0)
#define zig_maxInt_u64 UINT64_MAX

// zig_promoted_T implements C integral promotions except with signedness preserved, which
// allows wrapping operations to avoid the ub that would be caused by the normal promotion.

#if INT8_MAX <= INT_MAX
typedef unsigned int zig_promoted_i8;
#elif INT8_MAX <= LONG_MAX
typedef unsigned long zig_promoted_i8;
#elif INT8_MAX <= LLONG_MAX
typedef unsigned long long zig_promoted_i8;
#else
typedef int8_t zig_promoted_i8;
#endif
#if UINT8_MAX <= UINT_MAX
typedef unsigned int zig_promoted_u8;
#elif UINT8_MAX <= ULONG_MAX
typedef unsigned long zig_promoted_u8;
#elif UINT8_MAX <= ULLONG_MAX
typedef unsigned long long zig_promoted_u8;
#else
typedef uint8_t zig_promoted_u8;
#endif

#if INT16_MAX <= INT_MAX
typedef unsigned int zig_promoted_i16;
#elif INT16_MAX <= LONG_MAX
typedef unsigned long zig_promoted_i16;
#elif INT16_MAX <= LLONG_MAX
typedef unsigned long long zig_promoted_i16;
#else
typedef int16_t zig_promoted_i16;
#endif
#if UINT16_MAX <= UINT_MAX
typedef unsigned int zig_promoted_u16;
#elif UINT16_MAX <= ULONG_MAX
typedef unsigned long zig_promoted_u16;
#elif UINT16_MAX <= ULLONG_MAX
typedef unsigned long long zig_promoted_u16;
#else
typedef uint16_t zig_promoted_u16;
#endif

#if INT32_MAX <= INT_MAX
typedef unsigned int zig_promoted_i32;
#elif INT32_MAX <= LONG_MAX
typedef unsigned long zig_promoted_i32;
#elif INT32_MAX <= LLONG_MAX
typedef unsigned long long zig_promoted_i32;
#else
typedef int32_t zig_promoted_i32;
#endif
#if UINT32_MAX <= UINT_MAX
typedef unsigned int zig_promoted_u32;
#elif UINT32_MAX <= ULONG_MAX
typedef unsigned long zig_promoted_u32;
#elif UINT32_MAX <= ULLONG_MAX
typedef unsigned long long zig_promoted_u32;
#else
typedef uint32_t zig_promoted_u32;
#endif

#if INT64_MAX <= INT_MAX
typedef unsigned int zig_promoted_i64;
#elif INT64_MAX <= LONG_MAX
typedef unsigned long zig_promoted_i64;
#elif INT64_MAX <= LLONG_MAX
typedef unsigned long long zig_promoted_i64;
#else
typedef int64_t zig_promoted_i64;
#endif
#if UINT64_MAX <= UINT_MAX
typedef unsigned int zig_promoted_u64;
#elif UINT64_MAX <= ULONG_MAX
typedef unsigned long zig_promoted_u64;
#elif UINT64_MAX <= ULLONG_MAX
typedef unsigned long long zig_promoted_u64;
#else
typedef uint64_t zig_promoted_u64;
#endif

#ifdef zig_ez80

#define zig_minInt_i24  INT24_MIN
#define zig_maxInt_i24  INT24_MAX
#define zig_minInt_u24 UINT24_C(0)
#define zig_maxInt_u24 UINT24_MAX
#define zig_minInt_i48  INT48_MIN
#define zig_maxInt_i48  INT48_MAX
#define zig_minInt_u48 UINT48_C(0)
#define zig_maxInt_u48 UINT48_MAX

#if INT24_MAX <= INT_MAX
typedef unsigned int zig_promoted_i24;
#elif INT24_MAX <= LONG_MAX
typedef unsigned long zig_promoted_i24;
#elif INT24_MAX <= LLONG_MAX
typedef unsigned long long zig_promoted_i24;
#else
typedef int24_t zig_promoted_i24;
#endif
#if UINT24_MAX <= UINT_MAX
typedef unsigned int zig_promoted_u24;
#elif UINT24_MAX <= ULONG_MAX
typedef unsigned long zig_promoted_u24;
#elif UINT24_MAX <= ULLONG_MAX
typedef unsigned long long zig_promoted_u24;
#else
typedef uint24_t zig_promoted_u24;
#endif

#if INT48_MAX <= INT_MAX
typedef unsigned int zig_promoted_i48;
#elif INT48_MAX <= LONG_MAX
typedef unsigned long zig_promoted_i48;
#elif INT48_MAX <= LLONG_MAX
typedef unsigned long long zig_promoted_i48;
#else
typedef int48_t zig_promoted_i48;
#endif
#if UINT48_MAX <= UINT_MAX
typedef unsigned int zig_promoted_u48;
#elif UINT48_MAX <= ULONG_MAX
typedef unsigned long zig_promoted_u48;
#elif UINT48_MAX <= ULLONG_MAX
typedef unsigned long long zig_promoted_u48;
#else
typedef uint48_t zig_promoted_u48;
#endif

#endif

#define zig_intLimit(s, w, limit, bits) zig_shr_##s##w(zig_##limit##Int_##s##w, w - (bits))
#define zig_minInt_i(w, bits) zig_intLimit(i, w, min, bits)
#define zig_maxInt_i(w, bits) zig_intLimit(i, w, max, bits)
#define zig_minInt_u(w, bits) zig_intLimit(u, w, min, bits)
#define zig_maxInt_u(w, bits) zig_intLimit(u, w, max, bits)

#define zig_operator(Type, RhsType, operation, operator) \
    static inline Type zig_##operation(Type lhs, RhsType rhs) { \
        return lhs operator rhs; \
    }
#define zig_basic_operator(Type, operation, operator) \
    zig_operator(Type,    Type, operation, operator)
#define zig_shift_operator(Type, operation, operator) \
    zig_operator(Type, uint8_t, operation, operator)

#define zig_int_casts_common(bw, sw) \
    static inline uint##bw##_t zig_u##bw##_intCast_u##sw(uint##sw##_t arg) { \
        return arg; \
    } \
\
    static inline uint##bw##_t zig_u##bw##_intCast_i##sw(int##sw##_t arg) { \
        return (uint##bw##_t)arg; \
    } \
\
    static inline int##bw##_t zig_i##bw##_intCast_u##sw(uint##sw##_t arg) { \
        return arg; \
    } \
\
    static inline int##bw##_t zig_i##bw##_intCast_i##sw(int##sw##_t arg) { \
        return arg; \
    } \
\
    static inline uint##sw##_t zig_u##sw##_truncate_u##bw(uint##bw##_t arg, uint8_t bits) { \
        return (uint##sw##_t)arg & zig_maxInt_u(sw, bits); \
    } \
\
    static inline int##sw##_t zig_i##sw##_truncate_i##bw(int##bw##_t arg, uint8_t bits) { \
        return ((uint##sw##_t)arg & UINT##sw##_C(1) << (bits - UINT8_C(1))) != UINT##sw##_C(0) \
            ? (int##sw##_t)arg | zig_minInt_i(sw, bits) : (int##sw##_t)arg & zig_maxInt_i(sw, bits); \
    }
#define zig_int_operators(w) \
    zig_basic_operator(uint##w##_t, and_u##w,  &) \
    zig_basic_operator( int##w##_t, and_i##w,  &) \
    zig_basic_operator(uint##w##_t,  or_u##w,  |) \
    zig_basic_operator( int##w##_t,  or_i##w,  |) \
    zig_basic_operator(uint##w##_t, xor_u##w,  ^) \
    zig_basic_operator( int##w##_t, xor_i##w,  ^) \
    zig_shift_operator(uint##w##_t, shl_u##w, <<) \
    zig_shift_operator( int##w##_t, shl_i##w, <<) \
    zig_shift_operator(uint##w##_t, shr_u##w, >>) \
\
    static inline int##w##_t zig_shr_i##w(int##w##_t lhs, uint8_t rhs) { \
        int##w##_t sign_mask = lhs < INT##w##_C(0) ? -INT##w##_C(1) : INT##w##_C(0); \
        return ((lhs ^ sign_mask) >> rhs) ^ sign_mask; \
    } \
\
    static inline uint##w##_t zig_not_u##w(uint##w##_t arg, uint8_t bits) { \
        return arg ^ zig_maxInt_u(w, bits); \
    } \
\
    static inline int##w##_t zig_not_i##w(int##w##_t arg, uint8_t bits) { \
        (void)bits; \
        return ~arg; \
    } \
\
    zig_basic_operator(uint##w##_t, divFloor_u##w, /) \
\
    static inline int##w##_t zig_divFloor_i##w(int##w##_t lhs, int##w##_t rhs) { \
        return lhs / rhs + (lhs % rhs != INT##w##_C(0) ? zig_shr_i##w(lhs ^ rhs, UINT8_C(w) - UINT8_C(1)) : INT##w##_C(0)); \
    } \
\
    static inline uint##w##_t zig_divCeil_u##w(uint##w##_t lhs, uint##w##_t rhs) { \
        return lhs / rhs + (lhs % rhs != UINT##w##_C(0) ? UINT##w##_C(1) : UINT##w##_C(0)); \
    } \
\
    static inline int##w##_t zig_divCeil_i##w(int##w##_t lhs, int##w##_t rhs) { \
        return lhs / rhs + (lhs % rhs != INT##w##_C(0) \
            ? zig_shr_i##w(lhs ^ rhs, UINT8_C(w) - UINT8_C(1)) + INT##w##_C(1) : INT##w##_C(0)); \
    } \
\
    zig_basic_operator(uint##w##_t, mod_u##w, %) \
    zig_int_casts_common(w, w) \
\
    static inline uint##w##_t zig_u##w##_bitCast_u##w(uint##w##_t arg, uint8_t bits) { \
        return zig_u##w##_truncate_u##w(arg, bits); \
    } \
\
    static inline uint##w##_t zig_u##w##_bitCast_i##w(int##w##_t arg, uint8_t bits) { \
        return zig_u##w##_bitCast_u##w((uint##w##_t)arg, bits); \
    } \
\
    static inline int##w##_t zig_i##w##_bitCast_i##w(int##w##_t arg, uint8_t bits) { \
        return zig_i##w##_truncate_i##w(arg, bits); \
    } \
\
    static inline int##w##_t zig_i##w##_bitCast_u##w(uint##w##_t arg, uint8_t bits) { \
        return zig_i##w##_bitCast_i##w((int##w##_t)arg, bits); \
    } \
\
    static inline int##w##_t zig_mod_i##w(int##w##_t lhs, int##w##_t rhs) { \
        int##w##_t rem = lhs % rhs; \
        return rem + (rem != INT##w##_C(0) ? rhs & zig_shr_i##w(lhs ^ rhs, UINT8_C(w) - UINT8_C(1)) : INT##w##_C(0)); \
    } \
\
    static inline uint##w##_t zig_shlw_u##w(uint##w##_t lhs, uint8_t rhs, uint8_t bits) { \
        return zig_u##w##_truncate_u##w(zig_shl_u##w(lhs, rhs), bits); \
    } \
\
    static inline int##w##_t zig_shlw_i##w(int##w##_t lhs, uint8_t rhs, uint8_t bits) { \
        return zig_i##w##_bitCast_u##w(zig_shl_u##w(zig_u##w##_bitCast_i##w(lhs, bits), rhs), bits); \
    } \
\
    static inline uint##w##_t zig_addw_u##w(uint##w##_t lhs, uint##w##_t rhs, uint8_t bits) { \
        return zig_u##w##_truncate_u##w((zig_promoted_u##w)lhs + rhs, bits); \
    } \
\
    static inline int##w##_t zig_addw_i##w(int##w##_t lhs, int##w##_t rhs, uint8_t bits) { \
        return zig_i##w##_bitCast_u##w(zig_addw_u##w(zig_u##w##_bitCast_i##w(lhs, bits), zig_u##w##_bitCast_i##w(rhs, bits), bits), bits); \
    } \
\
    static inline uint##w##_t zig_subw_u##w(uint##w##_t lhs, uint##w##_t rhs, uint8_t bits) { \
        return zig_u##w##_truncate_u##w((zig_promoted_u##w)lhs - rhs, bits); \
    } \
\
    static inline int##w##_t zig_subw_i##w(int##w##_t lhs, int##w##_t rhs, uint8_t bits) { \
        return zig_i##w##_bitCast_u##w(zig_subw_u##w(zig_u##w##_bitCast_i##w(lhs, bits), zig_u##w##_bitCast_i##w(rhs, bits), bits), bits); \
    } \
\
    static inline uint##w##_t zig_mulw_u##w(uint##w##_t lhs, uint##w##_t rhs, uint8_t bits) { \
        return zig_u##w##_truncate_u##w((zig_promoted_u##w)lhs * rhs, bits); \
    } \
\
    static inline int##w##_t zig_mulw_i##w(int##w##_t lhs, int##w##_t rhs, uint8_t bits) { \
        return zig_i##w##_bitCast_u##w(zig_mulw_u##w(zig_u##w##_bitCast_i##w(lhs, bits), zig_u##w##_bitCast_i##w(rhs, bits), bits), bits); \
    } \
\
    static inline uint##w##_t zig_abs_i##w(int##w##_t arg) { \
        int##w##_t tmp = zig_shr_i##w(arg, UINT8_C(w) - UINT8_C(1)); \
        return zig_u##w##_bitCast_i##w(zig_subw_i##w(zig_xor_i##w(arg, tmp), tmp, UINT8_C(w)), UINT8_C(w)); \
    } \
\
    static inline uint##w##_t zig_min_u##w(uint##w##_t lhs, uint##w##_t rhs) { \
        return lhs < rhs ? lhs : rhs; \
    } \
\
    static inline int##w##_t zig_min_i##w(int##w##_t lhs, int##w##_t rhs) { \
        return lhs < rhs ? lhs : rhs; \
    } \
\
    static inline uint##w##_t zig_max_u##w(uint##w##_t lhs, uint##w##_t rhs) { \
        return lhs >= rhs ? lhs : rhs; \
    } \
\
    static inline int##w##_t zig_max_i##w(int##w##_t lhs, int##w##_t rhs) { \
        return lhs >= rhs ? lhs : rhs; \
    }
zig_int_operators(8)
zig_int_operators(16)
zig_int_operators(32)
zig_int_operators(64)
#ifdef zig_ez80
zig_int_operators(24)
zig_int_operators(48)
#endif

#define zig_int_casts(bw, sw) \
    static inline uint##sw##_t zig_u##sw##_intCast_u##bw(uint##bw##_t arg) { \
        return (uint##sw##_t)arg; \
    } \
\
    static inline uint##sw##_t zig_u##sw##_intCast_i##bw(int##bw##_t arg) { \
        return (uint##sw##_t)arg; \
    } \
\
    static inline int##sw##_t zig_i##sw##_intCast_u##bw(uint##bw##_t arg) { \
        return (int##sw##_t)arg; \
    } \
\
    static inline int##sw##_t zig_i##sw##_intCast_i##bw(int##bw##_t arg) { \
        return (int##sw##_t)arg; \
    } \
\
    zig_int_casts_common(bw, sw)
zig_int_casts(16,  8)
zig_int_casts(32,  8)
zig_int_casts(64,  8)
zig_int_casts(32, 16)
zig_int_casts(64, 16)
zig_int_casts(64, 32)
#ifdef zig_ez80
zig_int_casts(32, 24)
zig_int_casts(48, 24)
zig_int_casts(64, 24)
zig_int_casts(64, 48)
#endif

static inline bool zig_addo_u32(uint32_t *res, uint32_t lhs, uint32_t rhs, uint8_t bits) {
#if zig_has_builtin(add_overflow) || defined(zig_gcc)
    uint32_t full_res;
    bool overflow = __builtin_add_overflow(lhs, rhs, &full_res);
    *res = zig_u32_truncate_u32(full_res, bits);
    return overflow || full_res < zig_minInt_u(32, bits) || full_res > zig_maxInt_u(32, bits);
#else
    *res = zig_addw_u32(lhs, rhs, bits);
    return *res < lhs;
#endif
}

static inline bool zig_addo_i32(int32_t *res, int32_t lhs, int32_t rhs, uint8_t bits) {
#if zig_has_builtin(add_overflow) || defined(zig_gcc)
    int32_t full_res;
    bool overflow = __builtin_add_overflow(lhs, rhs, &full_res);
    *res = zig_i32_truncate_i32(full_res, bits);
    return overflow || full_res < zig_minInt_i(32, bits) || full_res > zig_maxInt_i(32, bits);
#else
    *res = zig_addw_i32(lhs, rhs, bits);
    return ((*res ^ lhs) & (*res ^ rhs)) < INT32_C(0);
#endif
}

static inline bool zig_addo_u64(uint64_t *res, uint64_t lhs, uint64_t rhs, uint8_t bits) {
#if zig_has_builtin(add_overflow) || defined(zig_gcc)
    uint64_t full_res;
    bool overflow = __builtin_add_overflow(lhs, rhs, &full_res);
    *res = zig_u64_truncate_u64(full_res, bits);
    return overflow || full_res < zig_minInt_u(64, bits) || full_res > zig_maxInt_u(64, bits);
#else
    *res = zig_addw_u64(lhs, rhs, bits);
    return *res < lhs;
#endif
}

static inline bool zig_addo_i64(int64_t *res, int64_t lhs, int64_t rhs, uint8_t bits) {
#if zig_has_builtin(add_overflow) || defined(zig_gcc)
    int64_t full_res;
    bool overflow = __builtin_add_overflow(lhs, rhs, &full_res);
    *res = zig_i64_truncate_i64(full_res, bits);
    return overflow || full_res < zig_minInt_i(64, bits) || full_res > zig_maxInt_i(64, bits);
#else
    *res = zig_addw_i64(lhs, rhs, bits);
    return ((*res ^ lhs) & (*res ^ rhs)) < INT64_C(0);
#endif
}

static inline bool zig_addo_u8(uint8_t *res, uint8_t lhs, uint8_t rhs, uint8_t bits) {
#if zig_has_builtin(add_overflow) || defined(zig_gcc)
    uint8_t full_res;
    bool overflow = __builtin_add_overflow(lhs, rhs, &full_res);
    *res = zig_u8_truncate_u8(full_res, bits);
    return overflow || full_res < zig_minInt_u(8, bits) || full_res > zig_maxInt_u(8, bits);
#else
    uint32_t full_res;
    bool overflow = zig_addo_u32(&full_res, lhs, rhs, bits);
    *res = zig_u8_intCast_u32(full_res);
    return overflow;
#endif
}

static inline bool zig_addo_i8(int8_t *res, int8_t lhs, int8_t rhs, uint8_t bits) {
#if zig_has_builtin(add_overflow) || defined(zig_gcc)
    int8_t full_res;
    bool overflow = __builtin_add_overflow(lhs, rhs, &full_res);
    *res = zig_i8_truncate_i8(full_res, bits);
    return overflow || full_res < zig_minInt_i(8, bits) || full_res > zig_maxInt_i(8, bits);
#else
    int32_t full_res;
    bool overflow = zig_addo_i32(&full_res, lhs, rhs, bits);
    *res = zig_i8_intCast_i32(full_res);
    return overflow;
#endif
}

static inline bool zig_addo_u16(uint16_t *res, uint16_t lhs, uint16_t rhs, uint8_t bits) {
#if zig_has_builtin(add_overflow) || defined(zig_gcc)
    uint16_t full_res;
    bool overflow = __builtin_add_overflow(lhs, rhs, &full_res);
    *res = zig_u16_truncate_u16(full_res, bits);
    return overflow || full_res < zig_minInt_u(16, bits) || full_res > zig_maxInt_u(16, bits);
#else
    uint32_t full_res;
    bool overflow = zig_addo_u32(&full_res, lhs, rhs, bits);
    *res = zig_u16_intCast_u32(full_res);
    return overflow;
#endif
}

static inline bool zig_addo_i16(int16_t *res, int16_t lhs, int16_t rhs, uint8_t bits) {
#if zig_has_builtin(add_overflow) || defined(zig_gcc)
    int16_t full_res;
    bool overflow = __builtin_add_overflow(lhs, rhs, &full_res);
    *res = zig_i16_truncate_i16(full_res, bits);
    return overflow || full_res < zig_minInt_i(16, bits) || full_res > zig_maxInt_i(16, bits);
#else
    int32_t full_res;
    bool overflow = zig_addo_i32(&full_res, lhs, rhs, bits);
    *res = zig_i16_intCast_i32(full_res);
    return overflow;
#endif
}

#if defined(zig_ez80)

static inline bool zig_addo_u24(uint24_t *res, uint24_t lhs, uint24_t rhs, uint8_t bits) {
#if zig_has_builtin(add_overflow) || defined(zig_gcc)
    uint24_t full_res;
    bool overflow = __builtin_add_overflow(lhs, rhs, &full_res);
    *res = zig_u24_truncate_u24(full_res, bits);
    return overflow || full_res < zig_minInt_u(24, bits) || full_res > zig_maxInt_u(24, bits);
#else
    uint32_t full_res;
    bool overflow = zig_addo_u32(&full_res, lhs, rhs, bits);
    *res = zig_u24_intCast_u32(full_res);
    return overflow;
#endif
}

static inline bool zig_addo_i24(int24_t *res, int24_t lhs, int24_t rhs, uint8_t bits) {
#if zig_has_builtin(add_overflow) || defined(zig_gcc)
    int24_t full_res;
    bool overflow = __builtin_add_overflow(lhs, rhs, &full_res);
    *res = zig_i24_truncate_i24(full_res, bits);
    return overflow || full_res < zig_minInt_i(24, bits) || full_res > zig_maxInt_i(24, bits);
#else
    int32_t full_res;
    bool overflow = zig_addo_i32(&full_res, lhs, rhs, bits);
    *res = zig_i24_intCast_i32(full_res);
    return overflow;
#endif
}

static inline bool zig_addo_u48(uint48_t *res, uint48_t lhs, uint48_t rhs, uint8_t bits) {
#if zig_has_builtin(add_overflow) || defined(zig_gcc)
    uint48_t full_res;
    bool overflow = __builtin_add_overflow(lhs, rhs, &full_res);
    *res = zig_u48_truncate_u48(full_res, bits);
    return overflow || full_res < zig_minInt_u(48, bits) || full_res > zig_maxInt_u(48, bits);
#else
    uint64_t full_res;
    bool overflow = zig_addo_u64(&full_res, lhs, rhs, bits);
    *res = zig_u48_intCast_u64(full_res);
    return overflow;
#endif
}

static inline bool zig_addo_i48(int48_t *res, int48_t lhs, int48_t rhs, uint8_t bits) {
#if zig_has_builtin(add_overflow) || defined(zig_gcc)
    int48_t full_res;
    bool overflow = __builtin_add_overflow(lhs, rhs, &full_res);
    *res = zig_i48_truncate_i48(full_res, bits);
    return overflow || full_res < zig_minInt_i(48, bits) || full_res > zig_maxInt_i(48, bits);
#else
    int64_t full_res;
    bool overflow = zig_addo_i64(&full_res, lhs, rhs, bits);
    *res = zig_i48_intCast_i64(full_res);
    return overflow;
#endif
}

#endif

static inline bool zig_subo_u32(uint32_t *res, uint32_t lhs, uint32_t rhs, uint8_t bits) {
#if zig_has_builtin(sub_overflow) || defined(zig_gcc)
    uint32_t full_res;
    bool overflow = __builtin_sub_overflow(lhs, rhs, &full_res);
    *res = zig_u32_truncate_u32(full_res, bits);
    return overflow || full_res < zig_minInt_u(32, bits) || full_res > zig_maxInt_u(32, bits);
#else
    *res = zig_subw_u32(lhs, rhs, bits);
    return *res > lhs;
#endif
}

static inline bool zig_subo_i32(int32_t *res, int32_t lhs, int32_t rhs, uint8_t bits) {
#if zig_has_builtin(sub_overflow) || defined(zig_gcc)
    int32_t full_res;
    bool overflow = __builtin_sub_overflow(lhs, rhs, &full_res);
    *res = zig_i32_truncate_i32(full_res, bits);
    return overflow || full_res < zig_minInt_i(32, bits) || full_res > zig_maxInt_i(32, bits);
#else
    *res = zig_subw_i32(lhs, rhs, bits);
    return ((lhs ^ rhs) & (*res ^ lhs)) < INT32_C(0);
#endif
}

static inline bool zig_subo_u64(uint64_t *res, uint64_t lhs, uint64_t rhs, uint8_t bits) {
#if zig_has_builtin(sub_overflow) || defined(zig_gcc)
    uint64_t full_res;
    bool overflow = __builtin_sub_overflow(lhs, rhs, &full_res);
    *res = zig_u64_truncate_u64(full_res, bits);
    return overflow || full_res < zig_minInt_u(64, bits) || full_res > zig_maxInt_u(64, bits);
#else
    *res = zig_subw_u64(lhs, rhs, bits);
    return *res > lhs;
#endif
}

static inline bool zig_subo_i64(int64_t *res, int64_t lhs, int64_t rhs, uint8_t bits) {
#if zig_has_builtin(sub_overflow) || defined(zig_gcc)
    int64_t full_res;
    bool overflow = __builtin_sub_overflow(lhs, rhs, &full_res);
    *res = zig_i64_truncate_i64(full_res, bits);
    return overflow || full_res < zig_minInt_i(64, bits) || full_res > zig_maxInt_i(64, bits);
#else
    *res = zig_subw_i64(lhs, rhs, bits);
    return ((lhs ^ rhs) & (*res ^ lhs)) < INT64_C(0);
#endif
}

static inline bool zig_subo_u8(uint8_t *res, uint8_t lhs, uint8_t rhs, uint8_t bits) {
#if zig_has_builtin(sub_overflow) || defined(zig_gcc)
    uint8_t full_res;
    bool overflow = __builtin_sub_overflow(lhs, rhs, &full_res);
    *res = zig_u8_truncate_u8(full_res, bits);
    return overflow || full_res < zig_minInt_u(8, bits) || full_res > zig_maxInt_u(8, bits);
#else
    uint32_t full_res;
    bool overflow = zig_subo_u32(&full_res, lhs, rhs, bits);
    *res = zig_u8_intCast_u32(full_res);
    return overflow;
#endif
}

static inline bool zig_subo_i8(int8_t *res, int8_t lhs, int8_t rhs, uint8_t bits) {
#if zig_has_builtin(sub_overflow) || defined(zig_gcc)
    int8_t full_res;
    bool overflow = __builtin_sub_overflow(lhs, rhs, &full_res);
    *res = zig_i8_truncate_i8(full_res, bits);
    return overflow || full_res < zig_minInt_i(8, bits) || full_res > zig_maxInt_i(8, bits);
#else
    int32_t full_res;
    bool overflow = zig_subo_i32(&full_res, lhs, rhs, bits);
    *res = zig_i8_intCast_i32(full_res);
    return overflow;
#endif
}

static inline bool zig_subo_u16(uint16_t *res, uint16_t lhs, uint16_t rhs, uint8_t bits) {
#if zig_has_builtin(sub_overflow) || defined(zig_gcc)
    uint16_t full_res;
    bool overflow = __builtin_sub_overflow(lhs, rhs, &full_res);
    *res = zig_u16_truncate_u16(full_res, bits);
    return overflow || full_res < zig_minInt_u(16, bits) || full_res > zig_maxInt_u(16, bits);
#else
    uint32_t full_res;
    bool overflow = zig_subo_u32(&full_res, lhs, rhs, bits);
    *res = zig_u16_intCast_u32(full_res);
    return overflow;
#endif
}

static inline bool zig_subo_i16(int16_t *res, int16_t lhs, int16_t rhs, uint8_t bits) {
#if zig_has_builtin(sub_overflow) || defined(zig_gcc)
    int16_t full_res;
    bool overflow = __builtin_sub_overflow(lhs, rhs, &full_res);
    *res = zig_i16_truncate_i16(full_res, bits);
    return overflow || full_res < zig_minInt_i(16, bits) || full_res > zig_maxInt_i(16, bits);
#else
    int32_t full_res;
    bool overflow = zig_subo_i32(&full_res, lhs, rhs, bits);
    *res = zig_i16_intCast_i32(full_res);
    return overflow;
#endif
}

#if defined(zig_ez80)

static inline bool zig_subo_u24(uint24_t *res, uint24_t lhs, uint24_t rhs, uint8_t bits) {
#if zig_has_builtin(sub_overflow) || defined(zig_gcc)
    uint24_t full_res;
    bool overflow = __builtin_sub_overflow(lhs, rhs, &full_res);
    *res = zig_u24_truncate_u24(full_res, bits);
    return overflow || full_res < zig_minInt_u(24, bits) || full_res > zig_maxInt_u(24, bits);
#else
    uint32_t full_res;
    bool overflow = zig_subo_u32(&full_res, lhs, rhs, bits);
    *res = zig_u24_intCast_u32(full_res);
    return overflow;
#endif
}

static inline bool zig_subo_i24(int24_t *res, int24_t lhs, int24_t rhs, uint8_t bits) {
#if zig_has_builtin(sub_overflow) || defined(zig_gcc)
    int24_t full_res;
    bool overflow = __builtin_sub_overflow(lhs, rhs, &full_res);
    *res = zig_i24_truncate_i24(full_res, bits);
    return overflow || full_res < zig_minInt_i(24, bits) || full_res > zig_maxInt_i(24, bits);
#else
    int32_t full_res;
    bool overflow = zig_subo_i32(&full_res, lhs, rhs, bits);
    *res = zig_i24_intCast_i32(full_res);
    return overflow;
#endif
}

static inline bool zig_subo_u48(uint48_t *res, uint48_t lhs, uint48_t rhs, uint8_t bits) {
#if zig_has_builtin(sub_overflow) || defined(zig_gcc)
    uint48_t full_res;
    bool overflow = __builtin_sub_overflow(lhs, rhs, &full_res);
    *res = zig_u48_truncate_u48(full_res, bits);
    return overflow || full_res < zig_minInt_u(48, bits) || full_res > zig_maxInt_u(48, bits);
#else
    uint64_t full_res;
    bool overflow = zig_subo_u64(&full_res, lhs, rhs, bits);
    *res = zig_u48_intCast_u64(full_res);
    return overflow;
#endif
}

static inline bool zig_subo_i48(int48_t *res, int48_t lhs, int48_t rhs, uint8_t bits) {
#if zig_has_builtin(sub_overflow) || defined(zig_gcc)
    int48_t full_res;
    bool overflow = __builtin_sub_overflow(lhs, rhs, &full_res);
    *res = zig_i48_truncate_i48(full_res, bits);
    return overflow || full_res < zig_minInt_i(48, bits) || full_res > zig_maxInt_i(48, bits);
#else
    int64_t full_res;
    bool overflow = zig_subo_i64(&full_res, lhs, rhs, bits);
    *res = zig_i48_intCast_i64(full_res);
    return overflow;
#endif
}

#endif

static inline bool zig_mulo_u32(uint32_t *res, uint32_t lhs, uint32_t rhs, uint8_t bits) {
#if zig_has_builtin(mul_overflow) || defined(zig_gcc)
    uint32_t full_res;
    bool overflow = __builtin_mul_overflow(lhs, rhs, &full_res);
    *res = zig_u32_truncate_u32(full_res, bits);
    return overflow || full_res < zig_minInt_u(32, bits) || full_res > zig_maxInt_u(32, bits);
#else
    *res = zig_mulw_u32(lhs, rhs, bits);
    return rhs != UINT32_C(0) && lhs > zig_maxInt_u(32, bits) / rhs;
#endif
}

static inline bool zig_mulo_i32(int32_t *res, int32_t lhs, int32_t rhs, uint8_t bits) {
    zig_extern int32_t  __mulosi4(int32_t lhs, int32_t rhs, int *overflow);
#if zig_has_builtin(mul_overflow) || defined(zig_gcc)
    int32_t full_res;
    bool overflow = __builtin_mul_overflow(lhs, rhs, &full_res);
#else
    int overflow_int;
    int32_t full_res = __mulosi4(lhs, rhs, &overflow_int);
    bool overflow = overflow_int != 0;
#endif
    *res = zig_i32_truncate_i32(full_res, bits);
    return overflow || full_res < zig_minInt_i(32, bits) || full_res > zig_maxInt_i(32, bits);
}

static inline bool zig_mulo_u64(uint64_t *res, uint64_t lhs, uint64_t rhs, uint8_t bits) {
#if zig_has_builtin(mul_overflow) || defined(zig_gcc)
    uint64_t full_res;
    bool overflow = __builtin_mul_overflow(lhs, rhs, &full_res);
    *res = zig_u64_truncate_u64(full_res, bits);
    return overflow || full_res < zig_minInt_u(64, bits) || full_res > zig_maxInt_u(64, bits);
#else
    *res = zig_mulw_u64(lhs, rhs, bits);
    return rhs != UINT64_C(0) && lhs > zig_maxInt_u(64, bits) / rhs;
#endif
}

static inline bool zig_mulo_i64(int64_t *res, int64_t lhs, int64_t rhs, uint8_t bits) {
    zig_extern int64_t  __mulodi4(int64_t lhs, int64_t rhs, int *overflow);
#if zig_has_builtin(mul_overflow) || defined(zig_gcc)
    int64_t full_res;
    bool overflow = __builtin_mul_overflow(lhs, rhs, &full_res);
#else
    int overflow_int;
    int64_t full_res = __mulodi4(lhs, rhs, &overflow_int);
    bool overflow = overflow_int != 0;
#endif
    *res = zig_i64_truncate_i64(full_res, bits);
    return overflow || full_res < zig_minInt_i(64, bits) || full_res > zig_maxInt_i(64, bits);
}

static inline bool zig_mulo_u8(uint8_t *res, uint8_t lhs, uint8_t rhs, uint8_t bits) {
#if zig_has_builtin(mul_overflow) || defined(zig_gcc)
    uint8_t full_res;
    bool overflow = __builtin_mul_overflow(lhs, rhs, &full_res);
    *res = zig_u8_truncate_u8(full_res, bits);
    return overflow || full_res < zig_minInt_u(8, bits) || full_res > zig_maxInt_u(8, bits);
#else
    uint32_t full_res;
    bool overflow = zig_mulo_u32(&full_res, lhs, rhs, bits);
    *res = zig_u8_intCast_u32(full_res);
    return overflow;
#endif
}

static inline bool zig_mulo_i8(int8_t *res, int8_t lhs, int8_t rhs, uint8_t bits) {
#if zig_has_builtin(mul_overflow) || defined(zig_gcc)
    int8_t full_res;
    bool overflow = __builtin_mul_overflow(lhs, rhs, &full_res);
    *res = zig_i8_truncate_i8(full_res, bits);
    return overflow || full_res < zig_minInt_i(8, bits) || full_res > zig_maxInt_i(8, bits);
#else
    int32_t full_res;
    bool overflow = zig_mulo_i32(&full_res, lhs, rhs, bits);
    *res = zig_i8_intCast_i32(full_res);
    return overflow;
#endif
}

static inline bool zig_mulo_u16(uint16_t *res, uint16_t lhs, uint16_t rhs, uint8_t bits) {
#if zig_has_builtin(mul_overflow) || defined(zig_gcc)
    uint16_t full_res;
    bool overflow = __builtin_mul_overflow(lhs, rhs, &full_res);
    *res = zig_u16_truncate_u16(full_res, bits);
    return overflow || full_res < zig_minInt_u(16, bits) || full_res > zig_maxInt_u(16, bits);
#else
    uint32_t full_res;
    bool overflow = zig_mulo_u32(&full_res, lhs, rhs, bits);
    *res = zig_u16_intCast_u32(full_res);
    return overflow;
#endif
}

static inline bool zig_mulo_i16(int16_t *res, int16_t lhs, int16_t rhs, uint8_t bits) {
#if zig_has_builtin(mul_overflow) || defined(zig_gcc)
    int16_t full_res;
    bool overflow = __builtin_mul_overflow(lhs, rhs, &full_res);
    *res = zig_i16_truncate_i16(full_res, bits);
    return overflow || full_res < zig_minInt_i(16, bits) || full_res > zig_maxInt_i(16, bits);
#else
    int32_t full_res;
    bool overflow = zig_mulo_i32(&full_res, lhs, rhs, bits);
    *res = zig_i16_intCast_i32(full_res);
    return overflow;
#endif
}

#if defined(zig_ez80)

static inline bool zig_mulo_u24(uint24_t *res, uint24_t lhs, uint24_t rhs, uint8_t bits) {
#if zig_has_builtin(mul_overflow) || defined(zig_gcc)
    uint24_t full_res;
    bool overflow = __builtin_mul_overflow(lhs, rhs, &full_res);
    *res = zig_u24_truncate_u24(full_res, bits);
    return overflow || full_res < zig_minInt_u(24, bits) || full_res > zig_maxInt_u(24, bits);
#else
    uint32_t full_res;
    bool overflow = zig_mulo_u32(&full_res, lhs, rhs, bits);
    *res = zig_u24_intCast_u32(full_res);
    return overflow;
#endif
}

static inline bool zig_mulo_i24(int24_t *res, int24_t lhs, int24_t rhs, uint8_t bits) {
#if zig_has_builtin(mul_overflow) || defined(zig_gcc)
    int24_t full_res;
    bool overflow = __builtin_mul_overflow(lhs, rhs, &full_res);
    *res = zig_i24_truncate_i24(full_res, bits);
    return overflow || full_res < zig_minInt_i(24, bits) || full_res > zig_maxInt_i(24, bits);
#else
    int32_t full_res;
    bool overflow = zig_mulo_i32(&full_res, lhs, rhs, bits);
    *res = zig_i24_intCast_i32(full_res);
    return overflow;
#endif
}

static inline bool zig_mulo_u48(uint48_t *res, uint48_t lhs, uint48_t rhs, uint8_t bits) {
#if zig_has_builtin(mul_overflow) || defined(zig_gcc)
    uint48_t full_res;
    bool overflow = __builtin_mul_overflow(lhs, rhs, &full_res);
    *res = zig_u48_truncate_u48(full_res, bits);
    return overflow || full_res < zig_minInt_u(48, bits) || full_res > zig_maxInt_u(48, bits);
#else
    uint64_t full_res;
    bool overflow = zig_mulo_u64(&full_res, lhs, rhs, bits);
    *res = zig_u48_intCast_u64(full_res);
    return overflow;
#endif
}

static inline bool zig_mulo_i48(int48_t *res, int48_t lhs, int48_t rhs, uint8_t bits) {
#if zig_has_builtin(mul_overflow) || defined(zig_gcc)
    int48_t full_res;
    bool overflow = __builtin_mul_overflow(lhs, rhs, &full_res);
    *res = zig_i48_truncate_i48(full_res, bits);
    return overflow || full_res < zig_minInt_i(48, bits) || full_res > zig_maxInt_i(48, bits);
#else
    int64_t full_res;
    bool overflow = zig_mulo_i64(&full_res, lhs, rhs, bits);
    *res = zig_i48_intCast_i64(full_res);
    return overflow;
#endif
}

#endif

#define zig_shls_builtins(lw, rw) \
    static inline uint##lw##_t zig_shls_u##lw##_u##rw(uint##lw##_t lhs, uint##rw##_t rhs, uint8_t bits) { \
        uint##lw##_t res; \
        if (rhs < bits && !zig_shlo_u##lw(&res, lhs, zig_u8_intCast_u##rw(rhs), bits)) return res; \
        return lhs == INT##lw##_C(0) ? zig_minInt_u(lw, bits) : zig_maxInt_u(lw, bits); \
    } \
\
    static inline int##lw##_t zig_shls_i##lw##_u##rw(int##lw##_t lhs, uint##rw##_t rhs, uint8_t bits) { \
        int##lw##_t res; \
        if (rhs < bits && !zig_shlo_i##lw(&res, lhs, zig_u8_intCast_u##rw(rhs), bits)) return res; \
        return lhs == INT##lw##_C(0) ? INT##lw##_C(0) : \
            lhs < INT##lw##_C(0) ? zig_minInt_i(lw, bits) : zig_maxInt_i(lw, bits); \
    }
#define zig_int_sat_builtins(w) \
    static inline bool zig_shlo_u##w(uint##w##_t *res, uint##w##_t lhs, uint8_t rhs, uint8_t bits) { \
        *res = zig_shlw_u##w(lhs, rhs, bits); \
        return lhs > zig_maxInt_u(w, bits) >> rhs; \
    } \
\
    static inline bool zig_shlo_i##w(int##w##_t *res, int##w##_t lhs, uint8_t rhs, uint8_t bits) { \
        *res = zig_shlw_i##w(lhs, rhs, bits); \
        int##w##_t mask = (int##w##_t)(UINT##w##_MAX << (bits - rhs - 1)); \
        return (lhs & mask) != INT##w##_C(0) && (lhs & mask) != mask; \
    } \
\
    zig_shls_builtins(w, 8) \
    zig_shls_builtins(w, 16) \
    zig_shls_builtins(w, 32) \
    zig_shls_builtins(w, 64) \
\
    static inline uint##w##_t zig_adds_u##w(uint##w##_t lhs, uint##w##_t rhs, uint8_t bits) { \
        uint##w##_t res; \
        return zig_addo_u##w(&res, lhs, rhs, bits) ? zig_maxInt_u(w, bits) : res; \
    } \
\
    static inline int##w##_t zig_adds_i##w(int##w##_t lhs, int##w##_t rhs, uint8_t bits) { \
        int##w##_t res; \
        if (!zig_addo_i##w(&res, lhs, rhs, bits)) return res; \
        return res >= INT##w##_C(0) ? zig_minInt_i(w, bits) : zig_maxInt_i(w, bits); \
    } \
\
    static inline uint##w##_t zig_subs_u##w(uint##w##_t lhs, uint##w##_t rhs, uint8_t bits) { \
        uint##w##_t res; \
        return zig_subo_u##w(&res, lhs, rhs, bits) ? zig_minInt_u(w, bits) : res; \
    } \
\
    static inline int##w##_t zig_subs_i##w(int##w##_t lhs, int##w##_t rhs, uint8_t bits) { \
        int##w##_t res; \
        if (!zig_subo_i##w(&res, lhs, rhs, bits)) return res; \
        return res >= INT##w##_C(0) ? zig_minInt_i(w, bits) : zig_maxInt_i(w, bits); \
    } \
\
    static inline uint##w##_t zig_muls_u##w(uint##w##_t lhs, uint##w##_t rhs, uint8_t bits) { \
        uint##w##_t res; \
        return zig_mulo_u##w(&res, lhs, rhs, bits) ? zig_maxInt_u(w, bits) : res; \
    } \
\
    static inline int##w##_t zig_muls_i##w(int##w##_t lhs, int##w##_t rhs, uint8_t bits) { \
        int##w##_t res; \
        if (!zig_mulo_i##w(&res, lhs, rhs, bits)) return res; \
        return (lhs ^ rhs) < INT##w##_C(0) ? zig_minInt_i(w, bits) : zig_maxInt_i(w, bits); \
    }
zig_int_sat_builtins(8)
zig_int_sat_builtins(16)
zig_int_sat_builtins(32)
zig_int_sat_builtins(64)
#if defined(zig_ez80)
zig_int_sat_builtins(24)
zig_int_sat_builtins(48)
#endif

#define zig_builtin8(name, arg) __builtin_##name(arg)
typedef unsigned int zig_Builtin8;

#define zig_builtin16(name, arg) __builtin_##name(arg)
typedef unsigned int zig_Builtin16;

#if INT_MIN <= INT32_MIN
#define zig_builtin32(name, arg) __builtin_##name(arg)
typedef unsigned int zig_Builtin32;
#elif LONG_MIN <= INT32_MIN
#define zig_builtin32(name, arg) __builtin_##name##l(arg)
typedef unsigned long zig_Builtin32;
#endif

#if INT_MIN <= INT64_MIN
#define zig_builtin64(name, arg) __builtin_##name(arg)
typedef unsigned int zig_Builtin64;
#elif LONG_MIN <= INT64_MIN
#define zig_builtin64(name, arg) __builtin_##name##l(arg)
typedef unsigned long zig_Builtin64;
#elif LLONG_MIN <= INT64_MIN
#define zig_builtin64(name, arg) __builtin_##name##ll(arg)
typedef unsigned long long zig_Builtin64;
#endif

#if defined(zig_ez80)
#define zig_builtin24(name, arg) __builtin_##name(arg)
typedef unsigned int zig_Builtin24;
#define zig_builtin48(name, arg) __builtin_##name(arg)
typedef unsigned long long zig_Builtin48;
#endif

static inline uint8_t zig_byteSwap_u8(uint8_t arg, uint8_t bits) {
    return zig_u8_truncate_u8(arg >> (8 - bits), bits);
}

static inline int8_t zig_byteSwap_i8(int8_t arg, uint8_t bits) {
    return zig_i8_truncate_i8((int8_t)zig_byteSwap_u8((uint8_t)arg, bits), bits);
}

static inline uint16_t zig_byteSwap_u16(uint16_t arg, uint8_t bits) {
    uint16_t full_res;
#if zig_has_builtin(bswap16) || defined(zig_gcc)
    full_res = __builtin_bswap16(arg);
#else
    full_res = (uint16_t)zig_byteSwap_u8((uint8_t)(arg >>  0), 8) <<  8 |
               (uint16_t)zig_byteSwap_u8((uint8_t)(arg >>  8), 8) >>  0;
#endif
    return zig_u16_truncate_u16(full_res >> (16 - bits), bits);
}

static inline int16_t zig_byteSwap_i16(int16_t arg, uint8_t bits) {
    return zig_i16_truncate_i16((int16_t)zig_byteSwap_u16((uint16_t)arg, bits), bits);
}

#if defined(zig_ez80)
static inline uint16_t zig_byteSwap_u24(uint24_t arg, uint8_t bits) {
    uint24_t full_res;
#if zig_has_builtin(bswap24) || defined(zig_gcc)
    full_res = __builtin_bswap24(arg);
#else
    full_res = (uint24_t)zig_byteSwap_u8((uint8_t)(arg >>  0), 8) <<  16 |
               (uint24_t)zig_byteSwap_u16((uint16_t)(arg >>  8), 16) >>  0;
#endif
    return zig_u24_truncate_u24(full_res >> (24 - bits), bits);
}

static inline int16_t zig_byteSwap_i24(int24_t arg, uint8_t bits) {
    return zig_i24_truncate_i24((int24_t)zig_byteSwap_u24((uint24_t)arg, bits), bits);
}
#endif

static inline uint32_t zig_byteSwap_u32(uint32_t arg, uint8_t bits) {
    uint32_t full_res;
#if zig_has_builtin(bswap32) || defined(zig_gcc)
    full_res = __builtin_bswap32(arg);
#else
    full_res = (uint32_t)zig_byteSwap_u16((uint16_t)(arg >>  0), 16) << 16 |
               (uint32_t)zig_byteSwap_u16((uint16_t)(arg >> 16), 16) >>  0;
#endif
    return zig_u32_truncate_u32(full_res >> (32 - bits), bits);
}

static inline int32_t zig_byteSwap_i32(int32_t arg, uint8_t bits) {
    return zig_i32_truncate_i32((int32_t)zig_byteSwap_u32((uint32_t)arg, bits), bits);
}

#if defined(zig_ez80)
static inline uint32_t zig_byteSwap_u48(uint48_t arg, uint8_t bits) {
    uint48_t full_res;
#if zig_has_builtin(bswap48) || defined(zig_gcc)
    full_res = __builtin_bswap48(arg);
#else
    full_res = (uint48_t)zig_byteSwap_u24((uint24_t)(arg >>  0), 24) << 24 |
               (uint48_t)zig_byteSwap_u24((uint24_t)(arg >> 24), 24) >>  0;
#endif
    return zig_u48_truncate_u48(full_res >> (48 - bits), bits);
}

static inline int32_t zig_byteSwap_i48(int48_t arg, uint8_t bits) {
    return zig_i48_truncate_i48((int48_t)zig_byteSwap_u48((uint48_t)arg, bits), bits);
}
#endif

static inline uint64_t zig_byteSwap_u64(uint64_t arg, uint8_t bits) {
    uint64_t full_res;
#if zig_has_builtin(bswap64) || defined(zig_gcc)
    full_res = __builtin_bswap64(arg);
#else
    full_res = (uint64_t)zig_byteSwap_u32((uint32_t)(arg >>  0), 32) << 32 |
               (uint64_t)zig_byteSwap_u32((uint32_t)(arg >> 32), 32) >>  0;
#endif
    return zig_u64_truncate_u64(full_res >> (64 - bits), bits);
}

static inline int64_t zig_byteSwap_i64(int64_t arg, uint8_t bits) {
    return zig_i64_truncate_i64((int64_t)zig_byteSwap_u64((uint64_t)arg, bits), bits);
}

static inline uint8_t zig_bitReverse_u8(uint8_t arg, uint8_t bits) {
    uint8_t full_res;
#if zig_has_builtin(bitreverse8)
    full_res = __builtin_bitreverse8(arg);
#else
    static uint8_t const lut[0x10] = {
        0x0, 0x8, 0x4, 0xc, 0x2, 0xa, 0x6, 0xe,
        0x1, 0x9, 0x5, 0xd, 0x3, 0xb, 0x7, 0xf
    };
    full_res = lut[arg >> 0 & 0xF] << 4 | lut[arg >> 4 & 0xF] << 0;
#endif
    return zig_u8_truncate_u8(full_res >> (8 - bits), bits);
}

static inline int8_t zig_bitReverse_i8(int8_t arg, uint8_t bits) {
    return zig_i8_truncate_i8((int8_t)zig_bitReverse_u8((uint8_t)arg, bits), bits);
}

static inline uint16_t zig_bitReverse_u16(uint16_t arg, uint8_t bits) {
    uint16_t full_res;
#if zig_has_builtin(bitreverse16)
    full_res = __builtin_bitreverse16(arg);
#else
    full_res = (uint16_t)zig_bitReverse_u8((uint8_t)(arg >>  0), 8) <<  8 |
               (uint16_t)zig_bitReverse_u8((uint8_t)(arg >>  8), 8) >>  0;
#endif
    return zig_u16_truncate_u16(full_res >> (16 - bits), bits);
}

static inline int16_t zig_bitReverse_i16(int16_t arg, uint8_t bits) {
    return zig_i16_truncate_i16((int16_t)zig_bitReverse_u16((uint16_t)arg, bits), bits);
}

#if defined(zig_ez80)
static inline uint24_t zig_bitReverse_u24(uint24_t arg, uint8_t bits) {
    uint24_t full_res;
#if zig_has_builtin(bitreverse24)
    full_res = __builtin_bitreverse24(arg);
#else
    full_res = (uint24_t)zig_bitReverse_u8((uint8_t)(arg >>  0), 8) <<  16 |
               (uint24_t)zig_bitReverse_u16((uint16_t)(arg >>  8), 16) >>  0;
#endif
    return zig_u24_truncate_u24(full_res >> (24 - bits), bits);
}

static inline int24_t zig_bitReverse_i24(int24_t arg, uint8_t bits) {
    return zig_i24_truncate_i24((int24_t)zig_bitReverse_u24((uint24_t)arg, bits), bits);
}
#endif

static inline uint32_t zig_bitReverse_u32(uint32_t arg, uint8_t bits) {
    uint32_t full_res;
#if zig_has_builtin(bitreverse32)
    full_res = __builtin_bitreverse32(arg);
#else
    full_res = (uint32_t)zig_bitReverse_u16((uint16_t)(arg >>  0), 16) << 16 |
               (uint32_t)zig_bitReverse_u16((uint16_t)(arg >> 16), 16) >>  0;
#endif
    return zig_u32_truncate_u32(full_res >> (32 - bits), bits);
}

static inline int32_t zig_bitReverse_i32(int32_t arg, uint8_t bits) {
    return zig_i32_truncate_i32((int32_t)zig_bitReverse_u32((uint32_t)arg, bits), bits);
}

#if defined(zig_ez80)
static inline uint32_t zig_bitReverse_u48(uint48_t arg, uint8_t bits) {
    uint48_t full_res;
#if zig_has_builtin(bitreverse48)
    full_res = __builtin_bitreverse48(arg);
#else
    full_res = (uint48_t)zig_bitReverse_u24((uint24_t)(arg >>  0), 24) << 24 |
               (uint48_t)zig_bitReverse_u24((uint24_t)(arg >> 24), 24) >>  0;
#endif
    return zig_u48_truncate_u48(full_res >> (48 - bits), bits);
}

static inline int32_t zig_bitReverse_i48(int48_t arg, uint8_t bits) {
    return zig_i48_truncate_i48((int48_t)zig_bitReverse_u48((uint48_t)arg, bits), bits);
}
#endif

static inline uint64_t zig_bitReverse_u64(uint64_t arg, uint8_t bits) {
    uint64_t full_res;
#if zig_has_builtin(bitreverse64)
    full_res = __builtin_bitreverse64(arg);
#else
    full_res = (uint64_t)zig_bitReverse_u32((uint32_t)(arg >>  0), 32) << 32 |
               (uint64_t)zig_bitReverse_u32((uint32_t)(arg >> 32), 32) >>  0;
#endif
    return zig_u64_truncate_u64(full_res >> (64 - bits), bits);
}

static inline int64_t zig_bitReverse_i64(int64_t arg, uint8_t bits) {
    return zig_i64_truncate_i64((int64_t)zig_bitReverse_u64((uint64_t)arg, bits), bits);
}

#define zig_builtin_popCount_common(w) \
    static inline uint8_t zig_popCount_i##w(int##w##_t arg, uint8_t bits) { \
        return zig_popCount_u##w((uint##w##_t)arg, bits); \
    }
#if zig_has_builtin(popCount) || defined(zig_gcc) || defined(zig_tinyc)
#define zig_builtin_popCount(w) \
    static inline uint8_t zig_popCount_u##w(uint##w##_t arg, uint8_t bits) { \
        (void)bits; \
        return zig_builtin##w(popcount, arg); \
    } \
\
    zig_builtin_popCount_common(w)
#else
#define zig_builtin_popCount(w) \
    static inline uint8_t zig_popCount_u##w(uint##w##_t arg, uint8_t bits) { \
        (void)bits; \
        uint##w##_t temp = arg - ((arg >> 1) & (UINT##w##_MAX / 3)); \
        temp = (temp & (UINT##w##_MAX / 5)) + ((temp >> 2) & (UINT##w##_MAX / 5)); \
        temp = (temp + (temp >> 4)) & (UINT##w##_MAX / 17); \
        return temp * (UINT##w##_MAX / 255) >> (UINT8_C(w) - UINT8_C(8)); \
    } \
\
    zig_builtin_popCount_common(w)
#endif
zig_builtin_popCount(8)
zig_builtin_popCount(16)
zig_builtin_popCount(32)
zig_builtin_popCount(64)
#if defined(zig_ez80)
zig_builtin_popCount(24)
zig_builtin_popCount(48)
#endif

#define zig_builtin_ctz_common(w) \
    static inline uint8_t zig_ctz_i##w(int##w##_t arg, uint8_t bits) { \
        return zig_ctz_u##w((uint##w##_t)arg, bits); \
    }
#if zig_has_builtin(ctz) || defined(zig_gcc) || defined(zig_tinyc)
#define zig_builtin_ctz(w) \
    static inline uint8_t zig_ctz_u##w(uint##w##_t arg, uint8_t bits) { \
        if (arg == 0) return bits; \
        return zig_builtin##w(ctz, arg); \
    } \
\
    zig_builtin_ctz_common(w)
#else
#define zig_builtin_ctz(w) \
    static inline uint8_t zig_ctz_u##w(uint##w##_t arg, uint8_t bits) { \
        return zig_popCount_u##w(zig_not_u##w(arg, bits) & zig_subw_u##w(arg, 1, bits), bits); \
    } \
\
    zig_builtin_ctz_common(w)
#endif
zig_builtin_ctz(8)
zig_builtin_ctz(16)
zig_builtin_ctz(32)
zig_builtin_ctz(64)
#if defined(zig_ez80)
zig_builtin_ctz(24)
zig_builtin_ctz(48)
#endif

#define zig_builtin_clz_common(w) \
    static inline uint8_t zig_clz_i##w(int##w##_t arg, uint8_t bits) { \
        return zig_clz_u##w((uint##w##_t)arg, bits); \
    }
#if zig_has_builtin(clz) || defined(zig_gcc) || defined(zig_tinyc)
#define zig_builtin_clz(w) \
    static inline uint8_t zig_clz_u##w(uint##w##_t arg, uint8_t bits) { \
        if (arg == 0) return bits; \
        return zig_builtin##w(clz, arg) - (zig_bitSizeOf(zig_Builtin##w) - bits); \
    } \
\
    zig_builtin_clz_common(w)
#else
#define zig_builtin_clz(w) \
    static inline uint8_t zig_clz_u##w(uint##w##_t arg, uint8_t bits) { \
        return zig_ctz_u##w(zig_bitReverse_u##w(arg, bits), bits); \
    } \
\
    zig_builtin_clz_common(w)
#endif
zig_builtin_clz(8)
zig_builtin_clz(16)
zig_builtin_clz(32)
zig_builtin_clz(64)
#if defined(zig_ez80)
zig_builtin_clz(24)
zig_builtin_clz(48)
#endif

/* ======================== 128-bit Integer Support ========================= */

#if !defined(zig_has_int128)
# if defined(__SIZEOF_INT128__)
#  define zig_has_int128 1
# else
#  define zig_has_int128 0
# endif
#endif

#if zig_has_int128

typedef unsigned __int128 zig_u128;
typedef   signed __int128 zig_i128;

#define zig_init_u128(hi, lo) ((zig_u128)(hi)<<64|(lo))
#define zig_init_i128(hi, lo) ((zig_i128)zig_make_u128(hi, lo))
#define zig_make_u128(hi, lo) zig_init_u128(hi, lo)
#define zig_make_i128(hi, lo) zig_init_i128(hi, lo)
#define zig_hi_u128(arg) ((uint64_t)((arg) >> 64))
#define zig_lo_u128(arg) ((uint64_t)((arg) >>  0))
#define zig_hi_i128(arg) (( int64_t)((arg) >> 64))
#define zig_lo_i128(arg) ((uint64_t)((arg) >>  0))
#define zig_cmp_int128(Type) \
    static inline int32_t zig_cmp_##Type(zig_##Type lhs, zig_##Type rhs) { \
        return (lhs > rhs) - (lhs < rhs); \
    }
#define zig_bit_int128(Type, operation, operator) \
    static inline zig_##Type zig_##operation##_##Type(zig_##Type lhs, zig_##Type rhs) { \
        return lhs operator rhs; \
    }

static inline zig_u128 zig_shl_u128(zig_u128 lhs, uint8_t rhs) {
    return lhs << rhs;
}

static inline zig_u128 zig_shr_u128(zig_u128 lhs, uint8_t rhs) {
    return lhs >> rhs;
}

static inline zig_i128 zig_shl_i128(zig_i128 lhs, uint8_t rhs) {
    return lhs << rhs;
}

static inline zig_i128 zig_shr_i128(zig_i128 lhs, uint8_t rhs) {
    // This works around a GCC miscompilation, but it has the side benefit of
    // emitting better code. It is behind the `#if` because it depends on
    // arithmetic right shift, which is implementation-defined in C, but should
    // be guaranteed on any GCC-compatible compiler.
#if defined(zig_gnuc)
    return lhs >> rhs;
#else
    zig_i128 sign_mask = lhs < zig_make_i128(0, 0) ? -zig_make_i128(0, 1) : zig_make_i128(0, 0);
    return ((lhs ^ sign_mask) >> rhs) ^ sign_mask;
#endif
}

#else /* zig_has_int128 */

#if zig_little_endian
typedef struct { zig_align(ZIG_TARGET_MAX_INT_ALIGNMENT) uint64_t lo; uint64_t hi; } zig_u128;
typedef struct { zig_align(ZIG_TARGET_MAX_INT_ALIGNMENT) uint64_t lo;  int64_t hi; } zig_i128;
#else
typedef struct { zig_align(ZIG_TARGET_MAX_INT_ALIGNMENT) uint64_t hi; uint64_t lo; } zig_u128;
typedef struct { zig_align(ZIG_TARGET_MAX_INT_ALIGNMENT)  int64_t hi; uint64_t lo; } zig_i128;
#endif

#define zig_init_u128(hi, lo) { .h##i = hi, .l##o = lo }
#define zig_init_i128(hi, lo) { .h##i = hi, .l##o = lo }
#define zig_make_u128(hi, lo) (zig_u128)zig_init_u128(hi, lo)
#define zig_make_i128(hi, lo) (zig_i128)zig_init_i128(hi, lo)
#define zig_hi_u128(arg) (arg).hi
#define zig_lo_u128(arg) (arg).lo
#define zig_hi_i128(arg) (arg).hi
#define zig_lo_i128(arg) (arg).lo
#define zig_cmp_int128(Type) \
    static inline int32_t zig_cmp_##Type(zig_##Type lhs, zig_##Type rhs) { \
        return (lhs.hi == rhs.hi) \
            ? (lhs.lo > rhs.lo) - (lhs.lo < rhs.lo) \
            : (lhs.hi > rhs.hi) - (lhs.hi < rhs.hi); \
    }
#define zig_bit_int128(Type, operation, operator) \
    static inline zig_##Type zig_##operation##_##Type(zig_##Type lhs, zig_##Type rhs) { \
        return (zig_##Type){ .hi = lhs.hi operator rhs.hi, .lo = lhs.lo operator rhs.lo }; \
    }

static inline zig_u128 zig_shl_u128(zig_u128 lhs, uint8_t rhs) {
    if (rhs == UINT8_C(0)) return lhs;
    if (rhs >= UINT8_C(64)) return (zig_u128){ .hi = lhs.lo << (rhs - UINT8_C(64)), .lo = zig_minInt_u64 };
    return (zig_u128){ .hi = lhs.hi << rhs | lhs.lo >> (UINT8_C(64) - rhs), .lo = lhs.lo << rhs };
}

static inline zig_u128 zig_shr_u128(zig_u128 lhs, uint8_t rhs) {
    if (rhs == UINT8_C(0)) return lhs;
    if (rhs >= UINT8_C(64)) return (zig_u128){ .hi = zig_minInt_u64, .lo = lhs.hi >> (rhs - UINT8_C(64)) };
    return (zig_u128){ .hi = lhs.hi >> rhs, .lo = lhs.hi << (UINT8_C(64) - rhs) | lhs.lo >> rhs };
}

static inline zig_i128 zig_shl_i128(zig_i128 lhs, uint8_t rhs) {
    if (rhs == UINT8_C(0)) return lhs;
    if (rhs >= UINT8_C(64)) return (zig_i128){ .hi = lhs.lo << (rhs - UINT8_C(64)), .lo = zig_minInt_u64 };
    return (zig_i128){ .hi = lhs.hi << rhs | lhs.lo >> (UINT8_C(64) - rhs), .lo = lhs.lo << rhs };
}

static inline zig_i128 zig_shr_i128(zig_i128 lhs, uint8_t rhs) {
    if (rhs == UINT8_C(0)) return lhs;
    if (rhs >= UINT8_C(64)) return (zig_i128){ .hi = zig_shr_i64(lhs.hi, 63), .lo = zig_shr_i64(lhs.hi, (rhs - UINT8_C(64))) };
    return (zig_i128){ .hi = zig_shr_i64(lhs.hi, rhs), .lo = lhs.lo >> rhs | (uint64_t)lhs.hi << (UINT8_C(64) - rhs) };
}

#endif /* zig_has_int128 */

#define zig_minInt_u128 zig_make_u128(zig_minInt_u64, zig_minInt_u64)
#define zig_maxInt_u128 zig_make_u128(zig_maxInt_u64, zig_maxInt_u64)
#define zig_minInt_i128 zig_make_i128(zig_minInt_i64, zig_minInt_u64)
#define zig_maxInt_i128 zig_make_i128(zig_maxInt_i64, zig_maxInt_u64)

zig_cmp_int128(u128)
zig_cmp_int128(i128)

zig_bit_int128(u128, and, &)
zig_bit_int128(i128, and, &)

zig_bit_int128(u128,  or, |)
zig_bit_int128(i128,  or, |)

zig_bit_int128(u128, xor, ^)
zig_bit_int128(i128, xor, ^)

static inline uint8_t zig_u8_intCast_u128(zig_u128 arg) {
    return (uint8_t)zig_lo_u128(arg);
}
static inline uint8_t zig_u8_intCast_i128(zig_i128 arg) {
    return (uint8_t)zig_lo_i128(arg);
}
static inline int8_t zig_i8_intCast_i128(zig_i128 arg) {
    return (int8_t)zig_lo_i128(arg);
}
static inline int8_t zig_i8_intCast_u128(zig_u128 arg) {
    return (int8_t)zig_lo_u128(arg);
}

static inline uint16_t zig_u16_intCast_u128(zig_u128 arg) {
    return (uint16_t)zig_lo_u128(arg);
}
static inline uint16_t zig_u16_intCast_i128(zig_i128 arg) {
    return (uint16_t)zig_lo_i128(arg);
}
static inline int16_t zig_i16_intCast_i128(zig_i128 arg) {
    return (int16_t)zig_lo_i128(arg);
}
static inline int16_t zig_i16_intCast_u128(zig_u128 arg) {
    return (int16_t)zig_lo_u128(arg);
}

static inline uint32_t zig_u32_intCast_u128(zig_u128 arg) {
    return (uint32_t)zig_lo_u128(arg);
}
static inline uint32_t zig_u32_intCast_i128(zig_i128 arg) {
    return (uint32_t)zig_lo_i128(arg);
}
static inline int32_t zig_i32_intCast_i128(zig_i128 arg) {
    return (int32_t)zig_lo_i128(arg);
}
static inline int32_t zig_i32_intCast_u128(zig_u128 arg) {
    return (int32_t)zig_lo_u128(arg);
}

static inline uint64_t zig_u64_intCast_u128(zig_u128 arg) {
    return zig_lo_u128(arg);
}
static inline uint64_t zig_u64_intCast_i128(zig_i128 arg) {
    return zig_lo_i128(arg);
}
static inline int64_t zig_i64_intCast_i128(zig_i128 arg) {
    return (int64_t)zig_lo_i128(arg);
}
static inline int64_t zig_i64_intCast_u128(zig_u128 arg) {
    return (int64_t)zig_lo_u128(arg);
}

static inline zig_u128 zig_u128_intCast_u8(uint8_t arg) {
    return zig_make_u128(UINT8_C(0), arg);
}
static inline zig_u128 zig_u128_intCast_i8(int8_t arg) {
    return zig_make_u128(UINT8_C(0), (uint8_t)arg);
}
static inline zig_i128 zig_i128_intCast_i8(int8_t arg) {
    return zig_make_i128(zig_shr_i64(arg, 63), (uint8_t)arg);
}
static inline zig_i128 zig_i128_intCast_u8(uint8_t arg) {
    return zig_make_i128(INT8_C(0), arg);
}

static inline zig_u128 zig_u128_intCast_u16(uint16_t arg) {
    return zig_make_u128(UINT16_C(0), arg);
}
static inline zig_u128 zig_u128_intCast_i16(int16_t arg) {
    return zig_make_u128(UINT16_C(0), (uint16_t)arg);
}
static inline zig_i128 zig_i128_intCast_i16(int16_t arg) {
    return zig_make_i128(zig_shr_i64(arg, 63), (uint16_t)arg);
}
static inline zig_i128 zig_i128_intCast_u16(uint16_t arg) {
    return zig_make_i128(INT16_C(0), arg);
}

static inline zig_u128 zig_u128_intCast_u32(uint32_t arg) {
    return zig_make_u128(UINT32_C(0), arg);
}
static inline zig_u128 zig_u128_intCast_i32(int32_t arg) {
    return zig_make_u128(UINT32_C(0), (uint32_t)arg);
}
static inline zig_i128 zig_i128_intCast_i32(int32_t arg) {
    return zig_make_i128(zig_shr_i64(arg, 63), (uint32_t)arg);
}
static inline zig_i128 zig_i128_intCast_u32(uint32_t arg) {
    return zig_make_i128(INT32_C(0), arg);
}

static inline zig_u128 zig_u128_intCast_u64(uint64_t arg) {
    return zig_make_u128(UINT64_C(0), arg);
}
static inline zig_u128 zig_u128_intCast_i64(int64_t arg) {
    return zig_make_u128(UINT64_C(0), (uint64_t)arg);
}
static inline zig_i128 zig_i128_intCast_i64(int64_t arg) {
    return zig_make_i128(zig_shr_i64(arg, 63), (uint64_t)arg);
}
static inline zig_i128 zig_i128_intCast_u64(uint64_t arg) {
    return zig_make_i128(INT64_C(0), arg);
}

static inline zig_u128 zig_u128_intCast_u128(zig_u128 arg) {
    return arg;
}
static inline zig_u128 zig_u128_intCast_i128(zig_i128 arg) {
#if zig_has_int128
    return (zig_u128)arg;
#else
    return zig_make_u128(zig_u64_bitCast_i64(zig_hi_i128(arg), UINT8_C(64)), zig_lo_u128(arg));
#endif
}
static inline zig_i128 zig_i128_intCast_i128(zig_i128 arg) {
    return arg;
}
static inline zig_i128 zig_i128_intCast_u128(zig_u128 arg) {
#if zig_has_int128
    return (zig_i128)arg;
#else
    return zig_make_i128(zig_i64_bitCast_u64(zig_hi_i128(arg), UINT8_C(64)), zig_lo_u128(arg));
#endif
}

#define zig_int128_cast_builtins(w) \
    static inline uint##w##_t zig_u##w##_truncate_u128(zig_u128 arg, uint8_t bits) { \
        return zig_u##w##_truncate_u##w((uint##w##_t)zig_lo_u128(arg), bits); \
    } \
\
    static inline int##w##_t zig_i##w##_truncate_i128(zig_i128 arg, uint8_t bits) { \
        return zig_i##w##_truncate_i##w((int##w##_t)zig_lo_i128(arg), bits); \
    }
zig_int128_cast_builtins(8)
zig_int128_cast_builtins(16)
zig_int128_cast_builtins(32)
zig_int128_cast_builtins(64)

static inline zig_u128 zig_u128_truncate_u128(zig_u128 arg, uint8_t bits) {
    return zig_and_u128(arg, zig_maxInt_u(128, bits));
}
static inline zig_i128 zig_i128_truncate_i128(zig_i128 arg, uint8_t bits) {
    if (bits > UINT8_C(64)) return zig_make_i128(zig_i64_truncate_i64(zig_hi_i128(arg), bits - UINT8_C(64)), zig_lo_i128(arg));
    int64_t lo = zig_i64_truncate_i128(arg, bits);
    return zig_make_i128(zig_shr_i64(lo, 63), (uint64_t)lo);
}

static inline zig_u128 zig_u128_bitCast_u128(zig_u128 arg, uint8_t bits) {
    (void)bits;
    return arg;
}
static inline zig_u128 zig_u128_bitCast_i128(zig_i128 arg, uint8_t bits) {
    return zig_u128_truncate_u128(zig_u128_intCast_i128(arg), bits);
}
static inline zig_i128 zig_i128_bitCast_i128(zig_i128 arg, uint8_t bits) {
    (void)bits;
    return arg;
}
static inline zig_i128 zig_i128_bitCast_u128(zig_u128 arg, uint8_t bits) {
    return zig_i128_truncate_i128(zig_i128_intCast_u128(arg), bits);
}

#if zig_has_int128

static inline zig_u128 zig_not_u128(zig_u128 arg, uint8_t bits) {
    return arg ^ zig_maxInt_u(128, bits);
}

static inline zig_i128 zig_not_i128(zig_i128 arg, uint8_t bits) {
    (void)bits;
    return ~arg;
}

static inline zig_u128 zig_add_u128(zig_u128 lhs, zig_u128 rhs) {
    return lhs + rhs;
}

static inline zig_i128 zig_add_i128(zig_i128 lhs, zig_i128 rhs) {
    return lhs + rhs;
}

static inline zig_u128 zig_sub_u128(zig_u128 lhs, zig_u128 rhs) {
    return lhs - rhs;
}

static inline zig_i128 zig_sub_i128(zig_i128 lhs, zig_i128 rhs) {
    return lhs - rhs;
}

static inline zig_u128 zig_mul_u128(zig_u128 lhs, zig_u128 rhs) {
    return lhs * rhs;
}

static inline zig_i128 zig_mul_i128(zig_i128 lhs, zig_i128 rhs) {
    return lhs * rhs;
}

static inline zig_u128 zig_divTrunc_u128(zig_u128 lhs, zig_u128 rhs) {
    return lhs / rhs;
}

static inline zig_i128 zig_divTrunc_i128(zig_i128 lhs, zig_i128 rhs) {
    return lhs / rhs;
}

static inline zig_u128 zig_rem_u128(zig_u128 lhs, zig_u128 rhs) {
    return lhs % rhs;
}

static inline zig_i128 zig_rem_i128(zig_i128 lhs, zig_i128 rhs) {
    return lhs % rhs;
}

#else /* zig_has_int128 */

static inline zig_u128 zig_not_u128(zig_u128 arg, uint8_t bits) {
    if (bits <= UINT8_C(64)) return (zig_u128){ .hi = UINT64_C(0), .lo = zig_not_u64(arg.lo, bits) };
    return (zig_u128){ .hi = zig_not_u64(arg.hi, bits - UINT8_C(64)), .lo = zig_not_u64(arg.lo, UINT8_C(64)) };
}

static inline zig_i128 zig_not_i128(zig_i128 arg, uint8_t bits) {
    (void)bits;
    return (zig_i128){ .hi = ~arg.hi, .lo = ~arg.lo };
}

static inline zig_u128 zig_add_u128(zig_u128 lhs, zig_u128 rhs) {
    zig_u128 res;
    res.hi = lhs.hi + rhs.hi + zig_addo_u64(&res.lo, lhs.lo, rhs.lo, 64);
    return res;
}

static inline zig_i128 zig_add_i128(zig_i128 lhs, zig_i128 rhs) {
    zig_i128 res;
    res.hi = lhs.hi + rhs.hi + zig_addo_u64(&res.lo, lhs.lo, rhs.lo, 64);
    return res;
}

static inline zig_u128 zig_sub_u128(zig_u128 lhs, zig_u128 rhs) {
    zig_u128 res;
    res.hi = lhs.hi - rhs.hi - zig_subo_u64(&res.lo, lhs.lo, rhs.lo, 64);
    return res;
}

static inline zig_i128 zig_sub_i128(zig_i128 lhs, zig_i128 rhs) {
    zig_i128 res;
    res.hi = lhs.hi - rhs.hi - zig_subo_u64(&res.lo, lhs.lo, rhs.lo, 64);
    return res;
}

static zig_i128 zig_mul_i128(zig_i128 lhs, zig_i128 rhs) {
    zig_extern zig_i128 __multi3(zig_i128 lhs, zig_i128 rhs);
    return __multi3(lhs, rhs);
}

static zig_u128 zig_mul_u128(zig_u128 lhs, zig_u128 rhs) {
    return zig_u128_bitCast_i128(zig_mul_i128(zig_i128_bitCast_u128(lhs, UINT8_C(128)), zig_i128_bitCast_u128(rhs, UINT8_C(128))), UINT8_C(128));
}

static zig_u128 zig_divTrunc_u128(zig_u128 lhs, zig_u128 rhs) {
    zig_extern zig_u128 __udivti3(zig_u128 lhs, zig_u128 rhs);
    return __udivti3(lhs, rhs);
}

static zig_i128 zig_divTrunc_i128(zig_i128 lhs, zig_i128 rhs) {
    zig_extern zig_i128 __divti3(zig_i128 lhs, zig_i128 rhs);
    return __divti3(lhs, rhs);
}

static zig_u128 zig_rem_u128(zig_u128 lhs, zig_u128 rhs) {
    zig_extern zig_u128 __umodti3(zig_u128 lhs, zig_u128 rhs);
    return __umodti3(lhs, rhs);
}

static zig_i128 zig_rem_i128(zig_i128 lhs, zig_i128 rhs) {
    zig_extern zig_i128 __modti3(zig_i128 lhs, zig_i128 rhs);
    return __modti3(lhs, rhs);
}

#endif /* zig_has_int128 */

#define zig_divFloor_u128 zig_divTrunc_u128

static inline zig_i128 zig_divFloor_i128(zig_i128 lhs, zig_i128 rhs) {
    zig_i128 rem = zig_rem_i128(lhs, rhs);
    int64_t mask = zig_or_u64((uint64_t)zig_hi_i128(rem), zig_lo_i128(rem)) != UINT64_C(0)
        ? zig_shr_i64(zig_xor_i64(zig_hi_i128(lhs), zig_hi_i128(rhs)), UINT8_C(63)) : INT64_C(0);
    return zig_add_i128(zig_divTrunc_i128(lhs, rhs), zig_make_i128(mask, (uint64_t)mask));
}

static inline zig_u128 zig_divCeil_u128(zig_u128 lhs, zig_u128 rhs) {
    zig_u128 rem = zig_rem_u128(lhs, rhs);
    uint64_t mask = zig_or_u64(zig_hi_u128(rem), zig_lo_u128(rem)) != UINT64_C(0)
        ? UINT64_C(1) : UINT64_C(0);
    return zig_add_u128(zig_divTrunc_u128(lhs, rhs), zig_make_u128(UINT64_C(0), mask));
}

static inline zig_i128 zig_divCeil_i128(zig_i128 lhs, zig_i128 rhs) {
    zig_i128 rem = zig_rem_i128(lhs, rhs);
    int64_t mask = zig_or_u64((uint64_t)zig_hi_i128(rem), zig_lo_i128(rem)) != UINT64_C(0)
        ? zig_shr_i64(zig_xor_i64(zig_hi_i128(lhs), zig_hi_i128(rhs)), UINT8_C(63)) + INT64_C(1)
        : INT64_C(0);
    return zig_add_i128(zig_divTrunc_i128(lhs, rhs), zig_make_i128(INT64_C(0), (uint64_t)mask));
}

#define zig_mod_u128 zig_rem_u128

static inline zig_i128 zig_mod_i128(zig_i128 lhs, zig_i128 rhs) {
    zig_i128 rem = zig_rem_i128(lhs, rhs);
    int64_t mask = zig_or_u64((uint64_t)zig_hi_i128(rem), zig_lo_i128(rem)) != UINT64_C(0)
        ? zig_shr_i64(zig_xor_i64(zig_hi_i128(lhs), zig_hi_i128(rhs)), UINT8_C(63)) : INT64_C(0);
    return zig_add_i128(rem, zig_and_i128(rhs, zig_make_i128(mask, (uint64_t)mask)));
}

static inline zig_u128 zig_min_u128(zig_u128 lhs, zig_u128 rhs) {
    return zig_cmp_u128(lhs, rhs) < INT32_C(0) ? lhs : rhs;
}

static inline zig_i128 zig_min_i128(zig_i128 lhs, zig_i128 rhs) {
    return zig_cmp_i128(lhs, rhs) < INT32_C(0) ? lhs : rhs;
}

static inline zig_u128 zig_max_u128(zig_u128 lhs, zig_u128 rhs) {
    return zig_cmp_u128(lhs, rhs) > INT32_C(0) ? lhs : rhs;
}

static inline zig_i128 zig_max_i128(zig_i128 lhs, zig_i128 rhs) {
    return zig_cmp_i128(lhs, rhs) > INT32_C(0) ? lhs : rhs;
}

static inline zig_u128 zig_shlw_u128(zig_u128 lhs, uint8_t rhs, uint8_t bits) {
    return zig_u128_truncate_u128(zig_shl_u128(lhs, rhs), bits);
}

static inline zig_i128 zig_shlw_i128(zig_i128 lhs, uint8_t rhs, uint8_t bits) {
    return zig_i128_truncate_i128(zig_i128_bitCast_u128(zig_shl_u128(zig_u128_bitCast_i128(lhs, bits), rhs), bits), bits);
}

static inline zig_u128 zig_addw_u128(zig_u128 lhs, zig_u128 rhs, uint8_t bits) {
    return zig_u128_truncate_u128(zig_add_u128(lhs, rhs), bits);
}

static inline zig_i128 zig_addw_i128(zig_i128 lhs, zig_i128 rhs, uint8_t bits) {
    return zig_i128_truncate_i128(zig_i128_bitCast_u128(zig_add_u128(zig_u128_bitCast_i128(lhs, bits), zig_u128_bitCast_i128(rhs, bits)), bits), bits);
}

static inline zig_u128 zig_subw_u128(zig_u128 lhs, zig_u128 rhs, uint8_t bits) {
    return zig_u128_truncate_u128(zig_sub_u128(lhs, rhs), bits);
}

static inline zig_i128 zig_subw_i128(zig_i128 lhs, zig_i128 rhs, uint8_t bits) {
    return zig_i128_truncate_i128(zig_i128_bitCast_u128(zig_sub_u128(zig_u128_bitCast_i128(lhs, bits), zig_u128_bitCast_i128(rhs, bits)), bits), bits);
}

static inline zig_u128 zig_mulw_u128(zig_u128 lhs, zig_u128 rhs, uint8_t bits) {
    return zig_u128_truncate_u128(zig_mul_u128(lhs, rhs), bits);
}

static inline zig_i128 zig_mulw_i128(zig_i128 lhs, zig_i128 rhs, uint8_t bits) {
    return zig_i128_truncate_i128(zig_i128_bitCast_u128(zig_mul_u128(zig_u128_bitCast_i128(lhs, bits), zig_u128_bitCast_i128(rhs, bits)), bits), bits);
}

static inline zig_u128 zig_abs_i128(zig_i128 arg) {
    zig_u128 tmp = zig_u128_bitCast_i128(zig_shr_i128(arg, 127), UINT8_C(128));
    return zig_sub_u128(zig_xor_u128(zig_u128_bitCast_i128(arg, UINT8_C(128)), tmp), tmp);
}

#if zig_has_int128

static inline bool zig_addo_u128(zig_u128 *res, zig_u128 lhs, zig_u128 rhs, uint8_t bits) {
#if zig_has_builtin(add_overflow)
    zig_u128 full_res;
    bool overflow = __builtin_add_overflow(lhs, rhs, &full_res);
    *res = zig_u128_truncate_u128(full_res, bits);
    return overflow || full_res < zig_minInt_u(128, bits) || full_res > zig_maxInt_u(128, bits);
#else
    *res = zig_addw_u128(lhs, rhs, bits);
    return *res < lhs;
#endif
}

static inline bool zig_addo_i128(zig_i128 *res, zig_i128 lhs, zig_i128 rhs, uint8_t bits) {
#if zig_has_builtin(add_overflow)
    zig_i128 full_res;
    bool overflow = __builtin_add_overflow(lhs, rhs, &full_res);
#else
    zig_i128 full_res = (zig_i128)((zig_u128)lhs + (zig_u128)rhs);
    bool overflow = ((full_res ^ lhs) & (full_res ^ rhs)) < 0;
#endif
    *res = zig_i128_truncate_i128(full_res, bits);
    return overflow || full_res < zig_minInt_i(128, bits) || full_res > zig_maxInt_i(128, bits);
}

static inline bool zig_subo_u128(zig_u128 *res, zig_u128 lhs, zig_u128 rhs, uint8_t bits) {
#if zig_has_builtin(sub_overflow)
    zig_u128 full_res;
    bool overflow = __builtin_sub_overflow(lhs, rhs, &full_res);
    *res = zig_u128_truncate_u128(full_res, bits);
    return overflow || full_res < zig_minInt_u(128, bits) || full_res > zig_maxInt_u(128, bits);
#else
    *res = zig_subw_u128(lhs, rhs, bits);
    return *res > lhs;
#endif
}

static inline bool zig_subo_i128(zig_i128 *res, zig_i128 lhs, zig_i128 rhs, uint8_t bits) {
#if zig_has_builtin(sub_overflow)
    zig_i128 full_res;
    bool overflow = __builtin_sub_overflow(lhs, rhs, &full_res);
#else
    zig_i128 full_res = (zig_i128)((zig_u128)lhs - (zig_u128)rhs);
    bool overflow = ((lhs ^ rhs) & (full_res ^ lhs)) < 0;
#endif
    *res = zig_i128_truncate_i128(full_res, bits);
    return overflow || full_res < zig_minInt_i(128, bits) || full_res > zig_maxInt_i(128, bits);
}

static inline bool zig_mulo_u128(zig_u128 *res, zig_u128 lhs, zig_u128 rhs, uint8_t bits) {
#if zig_has_builtin(mul_overflow)
    zig_u128 full_res;
    bool overflow = __builtin_mul_overflow(lhs, rhs, &full_res);
    *res = zig_u128_truncate_u128(full_res, bits);
    return overflow || full_res < zig_minInt_u(128, bits) || full_res > zig_maxInt_u(128, bits);
#else
    *res = zig_mulw_u128(lhs, rhs, bits);
    return rhs != zig_make_u128(0, 0) && lhs > zig_maxInt_u(128, bits) / rhs;
#endif
}

static inline bool zig_mulo_i128(zig_i128 *res, zig_i128 lhs, zig_i128 rhs, uint8_t bits) {
    zig_extern zig_i128  __muloti4(zig_i128 lhs, zig_i128 rhs, int *overflow);
#if zig_has_builtin(mul_overflow)
    zig_i128 full_res;
    bool overflow = __builtin_mul_overflow(lhs, rhs, &full_res);
#else
    int overflow_int;
    zig_i128 full_res =  __muloti4(lhs, rhs, &overflow_int);
    bool overflow = overflow_int != 0;
#endif
    *res = zig_i128_truncate_i128(full_res, bits);
    return overflow || full_res < zig_minInt_i(128, bits) || full_res > zig_maxInt_i(128, bits);
}

#else /* zig_has_int128 */

static inline bool zig_addo_u128(zig_u128 *res, zig_u128 lhs, zig_u128 rhs, uint8_t bits) {
    if (bits <= UINT8_C(64)) {
        uint64_t lo;
        bool overflow = zig_addo_u64(&lo, zig_u64_intCast_u128(lhs), zig_u64_intCast_u128(rhs), bits);
        *res = zig_u128_intCast_u64(lo);
        return overflow;
    } else {
        uint64_t hi;
        bool overflow = zig_addo_u64(&hi, lhs.hi, rhs.hi, bits - UINT8_C(64));
        return overflow ^ zig_addo_u64(&res->hi, hi, zig_addo_u64(&res->lo, lhs.lo, rhs.lo, UINT8_C(64)), bits - UINT8_C(64));
    }
}

static inline bool zig_addo_i128(zig_i128 *res, zig_i128 lhs, zig_i128 rhs, uint8_t bits) {
    if (bits <= UINT8_C(64)) {
        int64_t lo;
        bool overflow = zig_addo_i64(&lo, zig_i64_intCast_i128(lhs), zig_i64_intCast_i128(rhs), bits);
        *res = zig_i128_intCast_i64(lo);
        return overflow;
    } else {
        int64_t hi;
        bool overflow = zig_addo_i64(&hi, lhs.hi, rhs.hi, bits - UINT8_C(64));
        return overflow ^ zig_addo_i64(&res->hi, hi, zig_addo_u64(&res->lo, lhs.lo, rhs.lo, UINT8_C(64)), bits - UINT8_C(64));
    }
}

static inline bool zig_subo_u128(zig_u128 *res, zig_u128 lhs, zig_u128 rhs, uint8_t bits) {
    if (bits <= UINT8_C(64)) {
        uint64_t lo;
        bool overflow = zig_subo_u64(&lo, zig_u64_intCast_u128(lhs), zig_u64_intCast_u128(rhs), bits);
        *res = zig_u128_intCast_u64(lo);
        return overflow;
    } else {
        uint64_t hi;
        bool overflow = zig_subo_u64(&hi, lhs.hi, rhs.hi, bits - UINT8_C(64));
        return overflow ^ zig_subo_u64(&res->hi, hi, zig_subo_u64(&res->lo, lhs.lo, rhs.lo, UINT8_C(64)), bits - UINT8_C(64));
    }
}

static inline bool zig_subo_i128(zig_i128 *res, zig_i128 lhs, zig_i128 rhs, uint8_t bits) {
    if (bits <= UINT8_C(64)) {
        int64_t lo;
        bool overflow = zig_subo_i64(&lo, zig_i64_intCast_i128(lhs), zig_i64_intCast_i128(rhs), bits);
        *res = zig_i128_intCast_i64(lo);
        return overflow;
    } else {
        int64_t hi;
        bool overflow = zig_subo_i64(&hi, lhs.hi, rhs.hi, bits - UINT8_C(64));
        return overflow ^ zig_subo_i64(&res->hi, hi, zig_subo_u64(&res->lo, lhs.lo, rhs.lo, UINT8_C(64)), bits - UINT8_C(64));
    }
}

static inline bool zig_mulo_u128(zig_u128 *res, zig_u128 lhs, zig_u128 rhs, uint8_t bits) {
    *res = zig_mulw_u128(lhs, rhs, bits);
    return zig_cmp_u128(rhs, zig_make_u128(0, 0)) != INT32_C(0) &&
        zig_cmp_u128(lhs, zig_divTrunc_u128(zig_maxInt_u(128, bits), rhs)) > INT32_C(0);
}

static inline bool zig_mulo_i128(zig_i128 *res, zig_i128 lhs, zig_i128 rhs, uint8_t bits) {
    zig_extern zig_i128 __muloti4(zig_i128 lhs, zig_i128 rhs, int *overflow);
    int overflow_int;
    zig_i128 full_res = __muloti4(lhs, rhs, &overflow_int);
    bool overflow = overflow_int != 0 ||
        zig_cmp_i128(full_res, zig_minInt_i(128, bits)) < INT32_C(0) ||
        zig_cmp_i128(full_res, zig_maxInt_i(128, bits)) > INT32_C(0);
    *res = zig_i128_truncate_i128(full_res, bits);
    return overflow;
}

#endif /* zig_has_int128 */

static inline bool zig_shlo_u128(zig_u128 *res, zig_u128 lhs, uint8_t rhs, uint8_t bits) {
    *res = zig_shlw_u128(lhs, rhs, bits);
    return zig_cmp_u128(lhs, zig_shr_u128(zig_maxInt_u(128, bits), rhs)) > INT32_C(0);
}

static inline bool zig_shlo_i128(zig_i128 *res, zig_i128 lhs, uint8_t rhs, uint8_t bits) {
    *res = zig_shlw_i128(lhs, rhs, bits);
    zig_i128 mask = zig_i128_bitCast_u128(zig_shl_u128(zig_maxInt_u128, bits - rhs - UINT8_C(1)), bits);
    return zig_cmp_i128(zig_and_i128(lhs, mask), zig_make_i128(0, 0)) != INT32_C(0) &&
           zig_cmp_i128(zig_and_i128(lhs, mask), mask) != INT32_C(0);
}

#define zig_int128_shls_builtins(rw) \
    static inline zig_u128 zig_shls_u128_u##rw(zig_u128 lhs, uint##rw##_t rhs, uint8_t bits) { \
        zig_u128 res; \
        if (rhs < bits && !zig_shlo_u128(&res, lhs, zig_u8_intCast_u##rw(rhs), bits)) return res; \
        switch (zig_cmp_u128(lhs, zig_make_u128(UINT64_C(0), UINT64_C(0)))) { \
            case 0: return zig_minInt_u(128, bits); \
            case 1: return zig_maxInt_u(128, bits); \
            default: zig_unreachable(); \
        } \
    } \
\
    static inline zig_i128 zig_shls_i128_u##rw(zig_i128 lhs, uint##rw##_t rhs, uint8_t bits) { \
        zig_i128 res; \
        if (rhs < bits && !zig_shlo_i128(&res, lhs, zig_u8_intCast_u##rw(rhs), bits)) return res; \
        switch (zig_cmp_i128(lhs, zig_make_i128(INT64_C(0), UINT64_C(0)))) { \
            case -1: return zig_minInt_i(128, bits); \
            case  0: return zig_make_i128(INT64_C(0), UINT64_C(0)); \
            case  1: return zig_maxInt_i(128, bits); \
            default: zig_unreachable(); \
        } \
    }
zig_int128_shls_builtins(8)
zig_int128_shls_builtins(16)
zig_int128_shls_builtins(32)
zig_int128_shls_builtins(64)

static inline zig_u128 zig_shls_u128_u128(zig_u128 lhs, zig_u128 rhs, uint8_t bits) {
    zig_u128 res;
    if (zig_cmp_u128(rhs, zig_make_u128(0, bits)) < INT32_C(0) && !zig_shlo_u128(&res, lhs, (uint8_t)zig_lo_u128(rhs), bits)) return res;
    switch (zig_cmp_u128(lhs, zig_make_u128(0, 0))) {
        case INT32_C(0): return zig_make_u128(0, 0);
        case INT32_C(1): return zig_maxInt_u(128, bits);
        default: zig_unreachable();
    }
}

static inline zig_i128 zig_shls_i128_u128(zig_i128 lhs, zig_u128 rhs, uint8_t bits) {
    zig_i128 res;
    if (zig_cmp_u128(rhs, zig_make_u128(0, bits)) < INT32_C(0) && !zig_shlo_i128(&res, lhs, (uint8_t)zig_lo_u128(rhs), bits)) return res;
    switch (zig_cmp_i128(lhs, zig_make_i128(0, 0))) {
        case -INT32_C(1): return zig_minInt_i(128, bits);
        case  INT32_C(0): return zig_make_i128(0, 0);
        case  INT32_C(1): return zig_maxInt_i(128, bits);
        default: zig_unreachable();
    }
}

static inline zig_u128 zig_adds_u128(zig_u128 lhs, zig_u128 rhs, uint8_t bits) {
    zig_u128 res;
    return zig_addo_u128(&res, lhs, rhs, bits) ? zig_maxInt_u(128, bits) : res;
}

static inline zig_i128 zig_adds_i128(zig_i128 lhs, zig_i128 rhs, uint8_t bits) {
    zig_i128 res;
    if (!zig_addo_i128(&res, lhs, rhs, bits)) return res;
    return zig_cmp_i128(res, zig_make_i128(0, 0)) >= INT32_C(0) ? zig_minInt_i(128, bits) : zig_maxInt_i(128, bits);
}

static inline zig_u128 zig_subs_u128(zig_u128 lhs, zig_u128 rhs, uint8_t bits) {
    zig_u128 res;
    return zig_subo_u128(&res, lhs, rhs, bits) ? zig_minInt_u(128, bits) : res;
}

static inline zig_i128 zig_subs_i128(zig_i128 lhs, zig_i128 rhs, uint8_t bits) {
    zig_i128 res;
    if (!zig_subo_i128(&res, lhs, rhs, bits)) return res;
    return zig_cmp_i128(res, zig_make_i128(0, 0)) >= INT32_C(0) ? zig_minInt_i(128, bits) : zig_maxInt_i(128, bits);
}

static inline zig_u128 zig_muls_u128(zig_u128 lhs, zig_u128 rhs, uint8_t bits) {
    zig_u128 res;
    return zig_mulo_u128(&res, lhs, rhs, bits) ? zig_maxInt_u(128, bits) : res;
}

static inline zig_i128 zig_muls_i128(zig_i128 lhs, zig_i128 rhs, uint8_t bits) {
    zig_i128 res;
    if (!zig_mulo_i128(&res, lhs, rhs, bits)) return res;
    return zig_cmp_i128(zig_xor_i128(lhs, rhs), zig_make_i128(0, 0)) < INT32_C(0) ? zig_minInt_i(128, bits) : zig_maxInt_i(128, bits);
}

static inline uint8_t zig_clz_u128(zig_u128 arg, uint8_t bits) {
    if (bits <= UINT8_C(64)) return zig_clz_u64(zig_lo_u128(arg), bits);
    if (zig_hi_u128(arg) != 0) return zig_clz_u64(zig_hi_u128(arg), bits - UINT8_C(64));
    return zig_clz_u64(zig_lo_u128(arg), UINT8_C(64)) + (bits - UINT8_C(64));
}

static inline uint8_t zig_clz_i128(zig_i128 arg, uint8_t bits) {
    return zig_clz_u128(zig_u128_bitCast_i128(arg, bits), bits);
}

static inline uint8_t zig_ctz_u128(zig_u128 arg, uint8_t bits) {
    if (zig_lo_u128(arg) != 0) return zig_ctz_u64(zig_lo_u128(arg), UINT8_C(64));
    return zig_ctz_u64(zig_hi_u128(arg), bits - UINT8_C(64)) + UINT8_C(64);
}

static inline uint8_t zig_ctz_i128(zig_i128 arg, uint8_t bits) {
    return zig_ctz_u128(zig_u128_bitCast_i128(arg, bits), bits);
}

static inline uint8_t zig_popCount_u128(zig_u128 arg, uint8_t bits) {
    return (bits > UINT8_C(64) ? zig_popCount_u64(zig_hi_u128(arg), bits - UINT8_C(64)) : UINT8_C(0)) +
           zig_popCount_u64(zig_lo_u128(arg), UINT8_C(64));
}

static inline uint8_t zig_popCount_i128(zig_i128 arg, uint8_t bits) {
    return zig_popCount_u128(zig_u128_bitCast_i128(arg, bits), bits);
}

static inline zig_u128 zig_byteSwap_u128(zig_u128 arg, uint8_t bits) {
    zig_u128 full_res;
#if zig_has_builtin(bswap128)
    full_res = __builtin_bswap128(arg);
#else
    full_res = zig_make_u128(
        zig_byteSwap_u64(zig_lo_u128(arg), UINT8_C(64)),
        zig_byteSwap_u64(zig_hi_u128(arg), UINT8_C(64))
    );
#endif
    return zig_shr_u128(full_res, UINT8_C(128) - bits);
}

static inline zig_i128 zig_byteSwap_i128(zig_i128 arg, uint8_t bits) {
    return zig_i128_bitCast_u128(zig_byteSwap_u128(zig_u128_bitCast_i128(arg, bits), bits), bits);
}

static inline zig_u128 zig_bitReverse_u128(zig_u128 arg, uint8_t bits) {
    return zig_shr_u128(zig_make_u128(
        zig_bitReverse_u64(zig_lo_u128(arg), UINT8_C(64)),
        zig_bitReverse_u64(zig_hi_u128(arg), UINT8_C(64))
    ), UINT8_C(128) - bits);
}

static inline zig_i128 zig_bitReverse_i128(zig_i128 arg, uint8_t bits) {
    return zig_i128_bitCast_u128(zig_bitReverse_u128(zig_u128_bitCast_i128(arg, bits), bits), bits);
}

#if zig_has_int128
#define zig_switch_int128(operand) switch (operand)
#define zig_switch_prong_begin_int128()
#define zig_switch_case_int128(Type, operand, value) case value:
#define zig_switch_prong_end_int128()
#define zig_switch_default_int128() default:
#else // zig_has_int128
#define zig_switch_int128(operand)
#define zig_switch_prong_begin_int128() if (0
#define zig_switch_case_int128(Type, operand, value) || (zig_cmp_##Type(operand, value) == 0)
#define zig_switch_prong_end_int128() )
#define zig_switch_default_int128()
#endif // zig_has_int128

/* ========================== Big Integer Support =========================== */

static inline uint16_t zig_int_bytes(uint16_t bits) {
    uint16_t bytes = (bits - UINT16_C(1)) / CHAR_BIT + UINT16_C(1);
    uint16_t alignment = ZIG_TARGET_MAX_INT_ALIGNMENT;

    while (alignment / 2 >= bytes) alignment /= 2;
    return (bytes + alignment - 1) / alignment * alignment;
}

static inline void zig_minInt_big(void *res, bool is_signed, uint16_t bits) {
    uint8_t *res_bytes = res;
    uint16_t size = zig_int_bytes(bits);
    uint16_t byte_offset = zig_shr_u16(bits - UINT16_C(1), UINT8_C(3));
    uint16_t remainder_bits = zig_u8_truncate_u16(bits - UINT16_C(1), UINT8_C(3)) + UINT8_C(1);
    uint8_t sign_byte;
    uint8_t fill_byte;

    if (is_signed) {
        int8_t signed_sign_byte = zig_minInt_i(8, remainder_bits);

        sign_byte = zig_u8_bitCast_i8(signed_sign_byte, UINT8_C(8));
        fill_byte = zig_u8_bitCast_i8(zig_shr_i8(signed_sign_byte, UINT8_C(7)), UINT8_C(8));
    } else {
        sign_byte = zig_minInt_u(8, remainder_bits);
        fill_byte = UINT8_C(0);
    }

#if zig_little_endian
    memset(&res_bytes[0], zig_minInt_u8, byte_offset);
    res_bytes[byte_offset] = sign_byte;
    byte_offset += UINT16_C(1);
    memset(&res_bytes[byte_offset], fill_byte, size - byte_offset);
#else
    byte_offset = size - UINT16_C(1) - byte_offset;
    memset(&res_bytes[0], fill_byte, byte_offset);
    res_bytes[byte_offset] = sign_byte;
    byte_offset += UINT16_C(1);
    memset(&res_bytes[byte_offset], zig_minInt_u8, size - byte_offset);
#endif
}

static inline void zig_maxInt_big(void *res, bool is_signed, uint16_t bits) {
    uint8_t *res_bytes = res;
    uint16_t size = zig_int_bytes(bits);
    uint16_t byte_offset = zig_shr_u16(bits - UINT16_C(1), UINT8_C(3));
    uint16_t remainder_bits = zig_u8_truncate_u16(bits - UINT16_C(1), UINT8_C(3)) + UINT8_C(1);
    uint8_t sign_byte;
    uint8_t fill_byte;

    if (is_signed) {
        int8_t signed_sign_byte = zig_maxInt_i(8, remainder_bits);

        sign_byte = zig_u8_bitCast_i8(signed_sign_byte, UINT8_C(8));
        fill_byte = zig_u8_bitCast_i8(zig_shr_i8(signed_sign_byte, UINT8_C(7)), UINT8_C(8));
    } else {
        sign_byte = zig_maxInt_u(8, remainder_bits);
        fill_byte = UINT8_C(0);
    }

#if zig_little_endian
    memset(&res_bytes[0], zig_maxInt_u8, byte_offset);
    res_bytes[byte_offset] = sign_byte;
    byte_offset += UINT16_C(1);
    memset(&res_bytes[byte_offset], fill_byte, size - byte_offset);
#else
    byte_offset = size - UINT16_C(1) - byte_offset;
    memset(&res_bytes[0], fill_byte, byte_offset);
    res_bytes[byte_offset] = sign_byte;
    byte_offset += UINT16_C(1);
    memset(&res_bytes[byte_offset], zig_maxInt_u8, size - byte_offset);
#endif
}

static inline int8_t zig_signFill_big(const void *arg, bool is_signed, uint16_t bits) {
    const uint8_t *arg_bytes = arg;
    uint16_t byte_offset = 0;

    if (!is_signed) return INT8_C(0);
#if zig_little_endian
    byte_offset = zig_int_bytes(bits) - 1;
#endif
    return zig_shr_i8(zig_i8_bitCast_u8(arg_bytes[byte_offset], UINT8_C(8)), UINT8_C(7));
}

static inline void zig_big_intCast_big(void *res, const void *arg, bool res_is_signed, uint16_t res_bits, bool arg_is_signed, uint16_t arg_bits) {
    uint8_t *res_bytes = res;
    const uint8_t *arg_bytes = arg;
    uint16_t res_size = zig_int_bytes(res_bits);
    uint16_t arg_size = zig_int_bytes(arg_bits);
    uint16_t copy_size = zig_min_u16(res_size, arg_size);
    uint8_t sign_fill = zig_u8_bitCast_i8(zig_signFill_big(arg, arg_is_signed, arg_bits), UINT8_C(8));

#if zig_little_endian
    memcpy(&res_bytes[0], &arg_bytes[0], copy_size);
    memset(&res_bytes[copy_size], sign_fill, res_size - copy_size);
#else
    memset(&res_bytes[0], sign_fill, res_size - copy_size);
    memcpy(&res_bytes[res_size - copy_size], &arg_bytes[arg_size - copy_size], copy_size);
#endif
}

static inline void zig_big_truncate_big(void *res, const void *arg, bool res_is_signed, uint16_t res_bits, bool arg_is_signed, uint16_t arg_bits) {
    uint8_t *res_bytes = res;
    const uint8_t *arg_bytes = arg;
    uint16_t res_size = zig_int_bytes(res_bits);

    if (res_is_signed != arg_is_signed) zig_unreachable();
    if (res_bits > arg_bits) zig_unreachable();

    if (res_is_signed) {
        uint16_t arg_byte_offset = UINT16_C(0);

#if zig_big_endian
        arg_byte_offset = zig_int_bytes(arg_bits) - res_size;
#endif

        memcpy(&res_bytes[0], &arg_bytes[arg_byte_offset], res_size);
    } else {
        uint16_t res_byte_offset = zig_shr_u16(res_bits - UINT16_C(1), UINT8_C(3));
        uint16_t arg_byte_offset = res_byte_offset;

#if zig_little_endian
        memcpy(&res_bytes[0], &arg_bytes[0], res_byte_offset);
#else
        res_byte_offset = res_size - UINT16_C(1) - res_byte_offset;
        arg_byte_offset = zig_int_bytes(arg_bits) - UINT16_C(1) - arg_byte_offset;

        memset(&res_bytes[0], zig_minInt_u8, res_byte_offset);
#endif

        res_bytes[res_byte_offset] = zig_u8_truncate_u8(
            arg_bytes[arg_byte_offset],
            zig_u8_truncate_u8(res_bits - UINT16_C(1), UINT8_C(3)) + UINT16_C(1)
        );
        res_byte_offset += UINT16_C(1);
        arg_byte_offset += UINT16_C(1);

#if zig_little_endian
        memset(&res_bytes[res_byte_offset], zig_minInt_u8, res_size - res_byte_offset);
#else
        memcpy(&res_bytes[res_byte_offset], &arg_bytes[arg_byte_offset], res_size - res_byte_offset);
#endif
    }
}

#define zig_big_casts(is, s, w, IntType) \
    static inline IntType zig_##s##w##_intCast_big(const void *arg, bool arg_is_signed, uint16_t arg_bits) { \
        IntType res; \
        zig_big_intCast_big(&res, arg, is, w, arg_is_signed, arg_bits); \
        return res; \
    } \
\
    static inline void zig_big_intCast_##s##w(void *res, IntType arg, bool res_is_signed, uint16_t res_bits) { \
        zig_big_intCast_big(res, &arg, res_is_signed, res_bits, is, w); \
    } \
\
    static inline IntType zig_##s##w##_truncate_big(const void *arg, uint8_t res_bits, bool arg_is_signed, uint16_t arg_bits) { \
        IntType res; \
        zig_big_truncate_big(&res, arg, is, res_bits, arg_is_signed, arg_bits); \
        return res; \
    } \
\
    static inline void zig_big_truncate_##s##w(void *res, IntType arg, bool res_is_signed, uint16_t res_bits) { \
        zig_big_truncate_big(res, &arg, res_is_signed, res_bits, is, w); \
    }
zig_big_casts(false, u,   8,  uint8_t)
zig_big_casts(true , i,   8,   int8_t)
zig_big_casts(false, u,  16, uint16_t)
zig_big_casts(true , i,  16,  int16_t)
zig_big_casts(false, u,  32, uint32_t)
zig_big_casts(true , i,  32,  int32_t)
zig_big_casts(false, u,  64, uint64_t)
zig_big_casts(true , i,  64,  int64_t)
zig_big_casts(false, u, 128, zig_u128)
zig_big_casts(true , i, 128, zig_i128)

static inline void zig_big_bitCast_big(void *res, const void *arg, bool res_is_signed, uint16_t bits) {
    uint8_t *res_bytes = res;
    const uint8_t *arg_bytes = arg;
    uint16_t size = zig_int_bytes(bits);
    uint16_t byte_offset = zig_shr_u16(bits - UINT16_C(1), UINT8_C(3));
    uint16_t remainder_bits = zig_u8_truncate_u16(bits - UINT16_C(1), UINT8_C(3)) + UINT8_C(1);
    uint8_t sign_byte;
    uint8_t fill_byte;

#if zig_big_endian
    byte_offset = size - UINT16_C(1) - byte_offset;
#endif

    if (res_is_signed) {
        int8_t signed_sign_byte = zig_i8_bitCast_u8(arg_bytes[byte_offset], remainder_bits);

        sign_byte = zig_u8_bitCast_i8(signed_sign_byte, UINT8_C(8));
        fill_byte = zig_u8_bitCast_i8(zig_shr_i8(signed_sign_byte, UINT8_C(7)), UINT8_C(8));
    } else {
        sign_byte = zig_u8_bitCast_u8(arg_bytes[byte_offset], remainder_bits);
        fill_byte = UINT8_C(0);
    }

#if zig_little_endian
    memcpy(&res_bytes[0], &arg_bytes[0], byte_offset);
    res_bytes[byte_offset] = sign_byte;
    byte_offset += UINT16_C(1);
    memset(&res_bytes[byte_offset], fill_byte, size - byte_offset);
#else
    memset(&res_bytes[0], fill_byte, byte_offset);
    res_bytes[byte_offset] = sign_byte;
    byte_offset += UINT16_C(1);
    memcpy(&res_bytes[byte_offset], &arg_bytes[byte_offset], size - byte_offset);
#endif
}

static inline int32_t zig_cmp_big_u8(const void *lhs, uint8_t rhs, bool is_signed, uint16_t bits) {
    const uint8_t *lhs_bytes = lhs;
    uint16_t byte_offset = 0;
    bool do_signed = is_signed;
    uint16_t remaining_bytes = zig_int_bytes(bits);

#if zig_little_endian
    byte_offset = remaining_bytes;
#endif

    while (remaining_bytes >= 128 / CHAR_BIT) {
        uint8_t rhs_byte = remaining_bytes == 128 / CHAR_BIT ? rhs : UINT8_C(0);
        int32_t limb_cmp;

#if zig_little_endian
        byte_offset -= 128 / CHAR_BIT;
#endif

        if (do_signed) {
            zig_i128 lhs_limb;
            zig_i128 rhs_limb = zig_i128_intCast_u8(rhs_byte);

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            limb_cmp = zig_cmp_i128(lhs_limb, rhs_limb);
            do_signed = false;
        } else {
            zig_u128 lhs_limb;
            zig_u128 rhs_limb = zig_u128_intCast_u8(rhs_byte);

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            limb_cmp = zig_cmp_u128(lhs_limb, rhs_limb);
        }

        if (limb_cmp != 0) return limb_cmp;
        remaining_bytes -= 128 / CHAR_BIT;

#if zig_big_endian
        byte_offset += 128 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 64 / CHAR_BIT) {
        uint8_t rhs_byte = remaining_bytes == 64 / CHAR_BIT ? rhs : UINT8_C(0);

#if zig_little_endian
        byte_offset -= 64 / CHAR_BIT;
#endif

        if (do_signed) {
            int64_t lhs_limb;
            int64_t rhs_limb = zig_i64_intCast_u8(rhs_byte);

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            if (lhs_limb != rhs_limb) return (lhs_limb > rhs_limb) - (lhs_limb < rhs_limb);
            do_signed = false;
        } else {
            uint64_t lhs_limb;
            uint64_t rhs_limb = zig_u64_intCast_u8(rhs_byte);

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            if (lhs_limb != rhs_limb) return (lhs_limb > rhs_limb) - (lhs_limb < rhs_limb);
        }

        remaining_bytes -= 64 / CHAR_BIT;

#if zig_big_endian
        byte_offset += 64 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 32 / CHAR_BIT) {
        uint8_t rhs_byte = remaining_bytes == 32 / CHAR_BIT ? rhs : UINT8_C(0);

#if zig_little_endian
        byte_offset -= 32 / CHAR_BIT;
#endif

        if (do_signed) {
            int32_t lhs_limb;
            int32_t rhs_limb = zig_i32_intCast_u8(rhs_byte);

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            if (lhs_limb != rhs_limb) return (lhs_limb > rhs_limb) - (lhs_limb < rhs_limb);
            do_signed = false;
        } else {
            uint32_t lhs_limb;
            uint32_t rhs_limb = zig_u32_intCast_u8(rhs_byte);

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            if (lhs_limb != rhs_limb) return (lhs_limb > rhs_limb) - (lhs_limb < rhs_limb);
        }

        remaining_bytes -= 32 / CHAR_BIT;

#if zig_big_endian
        byte_offset += 32 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 16 / CHAR_BIT) {
        uint8_t rhs_byte = remaining_bytes == 16 / CHAR_BIT ? rhs : UINT8_C(0);

#if zig_little_endian
        byte_offset -= 16 / CHAR_BIT;
#endif

        if (do_signed) {
            int16_t lhs_limb;
            int16_t rhs_limb = zig_i16_intCast_u8(rhs_byte);

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            if (lhs_limb != rhs_limb) return (lhs_limb > rhs_limb) - (lhs_limb < rhs_limb);
            do_signed = false;
        } else {
            uint16_t lhs_limb;
            uint16_t rhs_limb = zig_u16_intCast_u8(rhs_byte);

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            if (lhs_limb != rhs_limb) return (lhs_limb > rhs_limb) - (lhs_limb < rhs_limb);
        }

        remaining_bytes -= 16 / CHAR_BIT;

#if zig_big_endian
        byte_offset += 16 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 8 / CHAR_BIT) {
        uint8_t rhs_byte = remaining_bytes == 16 / CHAR_BIT ? rhs : UINT8_C(0);

#if zig_little_endian
        byte_offset -= 8 / CHAR_BIT;
#endif

        if (do_signed) {
            int8_t lhs_limb;
            int16_t lhs_cmp_limb;
            int16_t rhs_cmp_limb = zig_i16_intCast_u8(rhs_byte);

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            lhs_cmp_limb = zig_i16_intCast_i8(lhs_limb);
            if (lhs_cmp_limb != rhs_cmp_limb) return (lhs_cmp_limb > rhs_cmp_limb) - (lhs_cmp_limb < rhs_cmp_limb);
            do_signed = false;
        } else {
            uint8_t lhs_limb;
            uint8_t rhs_limb = rhs_byte;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            if (lhs_limb != rhs_limb) return (lhs_limb > rhs_limb) - (lhs_limb < rhs_limb);
        }

        remaining_bytes -= 8 / CHAR_BIT;

#if zig_big_endian
        byte_offset += 8 / CHAR_BIT;
#endif
    }

    return 0;
}

static inline int32_t zig_cmp_big(const void *lhs, const void *rhs, bool is_signed, uint16_t bits) {
    const uint8_t *lhs_bytes = lhs;
    const uint8_t *rhs_bytes = rhs;
    uint16_t byte_offset = 0;
    bool do_signed = is_signed;
    uint16_t remaining_bytes = zig_int_bytes(bits);

#if zig_little_endian
    byte_offset = remaining_bytes;
#endif

    while (remaining_bytes >= 128 / CHAR_BIT) {
        int32_t limb_cmp;

#if zig_little_endian
        byte_offset -= 128 / CHAR_BIT;
#endif

        if (do_signed) {
            zig_i128 lhs_limb;
            zig_i128 rhs_limb;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_cmp = zig_cmp_i128(lhs_limb, rhs_limb);
            do_signed = false;
        } else {
            zig_u128 lhs_limb;
            zig_u128 rhs_limb;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_cmp = zig_cmp_u128(lhs_limb, rhs_limb);
        }

        if (limb_cmp != 0) return limb_cmp;
        remaining_bytes -= 128 / CHAR_BIT;

#if zig_big_endian
        byte_offset += 128 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 64 / CHAR_BIT) {
#if zig_little_endian
        byte_offset -= 64 / CHAR_BIT;
#endif

        if (do_signed) {
            int64_t lhs_limb;
            int64_t rhs_limb;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            if (lhs_limb != rhs_limb) return (lhs_limb > rhs_limb) - (lhs_limb < rhs_limb);
            do_signed = false;
        } else {
            uint64_t lhs_limb;
            uint64_t rhs_limb;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            if (lhs_limb != rhs_limb) return (lhs_limb > rhs_limb) - (lhs_limb < rhs_limb);
        }

        remaining_bytes -= 64 / CHAR_BIT;

#if zig_big_endian
        byte_offset += 64 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 32 / CHAR_BIT) {
#if zig_little_endian
        byte_offset -= 32 / CHAR_BIT;
#endif

        if (do_signed) {
            int32_t lhs_limb;
            int32_t rhs_limb;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            if (lhs_limb != rhs_limb) return (lhs_limb > rhs_limb) - (lhs_limb < rhs_limb);
            do_signed = false;
        } else {
            uint32_t lhs_limb;
            uint32_t rhs_limb;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            if (lhs_limb != rhs_limb) return (lhs_limb > rhs_limb) - (lhs_limb < rhs_limb);
        }

        remaining_bytes -= 32 / CHAR_BIT;

#if zig_big_endian
        byte_offset += 32 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 16 / CHAR_BIT) {
#if zig_little_endian
        byte_offset -= 16 / CHAR_BIT;
#endif

        if (do_signed) {
            int16_t lhs_limb;
            int16_t rhs_limb;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            if (lhs_limb != rhs_limb) return (lhs_limb > rhs_limb) - (lhs_limb < rhs_limb);
            do_signed = false;
        } else {
            uint16_t lhs_limb;
            uint16_t rhs_limb;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            if (lhs_limb != rhs_limb) return (lhs_limb > rhs_limb) - (lhs_limb < rhs_limb);
        }

        remaining_bytes -= 16 / CHAR_BIT;

#if zig_big_endian
        byte_offset += 16 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 8 / CHAR_BIT) {
#if zig_little_endian
        byte_offset -= 8 / CHAR_BIT;
#endif

        if (do_signed) {
            int8_t lhs_limb;
            int8_t rhs_limb;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            if (lhs_limb != rhs_limb) return (lhs_limb > rhs_limb) - (lhs_limb < rhs_limb);
            do_signed = false;
        } else {
            uint8_t lhs_limb;
            uint8_t rhs_limb;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            if (lhs_limb != rhs_limb) return (lhs_limb > rhs_limb) - (lhs_limb < rhs_limb);
        }

        remaining_bytes -= 8 / CHAR_BIT;

#if zig_big_endian
        byte_offset += 8 / CHAR_BIT;
#endif
    }

    return 0;
}

static inline void zig_not_big(void *res, const void *arg, bool is_signed, uint16_t bits) {
    uint8_t *res_bytes = res;
    const uint8_t *arg_bytes = arg;
    uint16_t byte_offset = 0;
    uint16_t remaining_bytes = zig_int_bytes(bits);
    uint8_t top_bits = zig_u8_intCast_u16(remaining_bytes * CHAR_BIT - bits);

#if zig_big_endian
    byte_offset = remaining_bytes;
#endif

    while (remaining_bytes >= 128 / CHAR_BIT) {
        uint8_t limb_bits = 128 - (remaining_bytes == 128 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 128 / CHAR_BIT;
#endif

        if (remaining_bytes != 128 / CHAR_BIT || is_signed) {
            zig_i128 res_limb;
            zig_i128 arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            res_limb = zig_not_i128(arg_limb, limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        } else {
            zig_u128 res_limb;
            zig_u128 arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            res_limb = zig_not_u128(arg_limb, limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        }

        remaining_bytes -= 128 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 128 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 64 / CHAR_BIT) {
        uint8_t limb_bits = 64 - (remaining_bytes == 64 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 64 / CHAR_BIT;
#endif

        if (remaining_bytes != 64 / CHAR_BIT || is_signed) {
            int64_t res_limb;
            int64_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            res_limb = zig_not_i64(arg_limb, limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        } else {
            uint64_t res_limb;
            uint64_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            res_limb = zig_not_u64(arg_limb, limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        }

        remaining_bytes -= 64 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 64 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 32 / CHAR_BIT) {
        uint8_t limb_bits = 32 - (remaining_bytes == 32 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 32 / CHAR_BIT;
#endif

        if (remaining_bytes != 32 / CHAR_BIT || is_signed) {
            int32_t res_limb;
            int32_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            res_limb = zig_not_i32(arg_limb, limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        } else {
            uint32_t res_limb;
            uint32_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            res_limb = zig_not_u32(arg_limb, limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        }

        remaining_bytes -= 32 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 32 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 16 / CHAR_BIT) {
        uint8_t limb_bits = 16 - (remaining_bytes == 16 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 16 / CHAR_BIT;
#endif

        if (remaining_bytes != 16 / CHAR_BIT || is_signed) {
            int16_t res_limb;
            int16_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            res_limb = zig_not_i16(arg_limb, limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        } else {
            uint16_t res_limb;
            uint16_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            res_limb = zig_not_u16(arg_limb, limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        }

        remaining_bytes -= 16 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 16 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 8 / CHAR_BIT) {
        uint8_t limb_bits = 8 - (remaining_bytes == 8 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 8 / CHAR_BIT;
#endif

        if (remaining_bytes != 8 / CHAR_BIT || is_signed) {
            int8_t res_limb;
            int8_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            res_limb = zig_not_i8(arg_limb, limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        } else {
            uint8_t res_limb;
            uint8_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            res_limb = zig_not_u8(arg_limb, limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        }

        remaining_bytes -= 8 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 8 / CHAR_BIT;
#endif
    }
}

static inline void zig_and_big(void *res, const void *lhs, const void *rhs, bool is_signed, uint16_t bits) {
    uint8_t *res_bytes = res;
    const uint8_t *lhs_bytes = lhs;
    const uint8_t *rhs_bytes = rhs;
    uint16_t byte_offset = 0;
    uint16_t remaining_bytes = zig_int_bytes(bits);
    (void)is_signed;

    while (remaining_bytes >= 128 / CHAR_BIT) {
        zig_u128 res_limb;
        zig_u128 lhs_limb;
        zig_u128 rhs_limb;

        memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
        memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
        res_limb = zig_and_u128(lhs_limb, rhs_limb);
        memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));

        remaining_bytes -= 128 / CHAR_BIT;
        byte_offset += 128 / CHAR_BIT;
    }

    while (remaining_bytes >= 64 / CHAR_BIT) {
        uint64_t res_limb;
        uint64_t lhs_limb;
        uint64_t rhs_limb;

        memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
        memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
        res_limb = zig_and_u64(lhs_limb, rhs_limb);
        memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));

        remaining_bytes -= 64 / CHAR_BIT;
        byte_offset += 64 / CHAR_BIT;
    }

    while (remaining_bytes >= 32 / CHAR_BIT) {
        uint32_t res_limb;
        uint32_t lhs_limb;
        uint32_t rhs_limb;

        memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
        memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
        res_limb = zig_and_u32(lhs_limb, rhs_limb);
        memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));

        remaining_bytes -= 32 / CHAR_BIT;
        byte_offset += 32 / CHAR_BIT;
    }

    while (remaining_bytes >= 16 / CHAR_BIT) {
        uint16_t res_limb;
        uint16_t lhs_limb;
        uint16_t rhs_limb;

        memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
        memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
        res_limb = zig_and_u16(lhs_limb, rhs_limb);
        memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));

        remaining_bytes -= 16 / CHAR_BIT;
        byte_offset += 16 / CHAR_BIT;
    }

    while (remaining_bytes >= 8 / CHAR_BIT) {
        uint8_t res_limb;
        uint8_t lhs_limb;
        uint8_t rhs_limb;

        memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
        memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
        res_limb = zig_and_u8(lhs_limb, rhs_limb);
        memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));

        remaining_bytes -= 8 / CHAR_BIT;
        byte_offset += 8 / CHAR_BIT;
    }
}

static inline void zig_or_big(void *res, const void *lhs, const void *rhs, bool is_signed, uint16_t bits) {
    uint8_t *res_bytes = res;
    const uint8_t *lhs_bytes = lhs;
    const uint8_t *rhs_bytes = rhs;
    uint16_t byte_offset = 0;
    uint16_t remaining_bytes = zig_int_bytes(bits);
    (void)is_signed;

    while (remaining_bytes >= 128 / CHAR_BIT) {
        zig_u128 res_limb;
        zig_u128 lhs_limb;
        zig_u128 rhs_limb;

        memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
        memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
        res_limb = zig_or_u128(lhs_limb, rhs_limb);
        memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));

        remaining_bytes -= 128 / CHAR_BIT;
        byte_offset += 128 / CHAR_BIT;
    }

    while (remaining_bytes >= 64 / CHAR_BIT) {
        uint64_t res_limb;
        uint64_t lhs_limb;
        uint64_t rhs_limb;

        memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
        memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
        res_limb = zig_or_u64(lhs_limb, rhs_limb);
        memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));

        remaining_bytes -= 64 / CHAR_BIT;
        byte_offset += 64 / CHAR_BIT;
    }

    while (remaining_bytes >= 32 / CHAR_BIT) {
        uint32_t res_limb;
        uint32_t lhs_limb;
        uint32_t rhs_limb;

        memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
        memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
        res_limb = zig_or_u32(lhs_limb, rhs_limb);
        memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));

        remaining_bytes -= 32 / CHAR_BIT;
        byte_offset += 32 / CHAR_BIT;
    }

    while (remaining_bytes >= 16 / CHAR_BIT) {
        uint16_t res_limb;
        uint16_t lhs_limb;
        uint16_t rhs_limb;

        memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
        memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
        res_limb = zig_or_u16(lhs_limb, rhs_limb);
        memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));

        remaining_bytes -= 16 / CHAR_BIT;
        byte_offset += 16 / CHAR_BIT;
    }

    while (remaining_bytes >= 8 / CHAR_BIT) {
        uint8_t res_limb;
        uint8_t lhs_limb;
        uint8_t rhs_limb;

        memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
        memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
        res_limb = zig_or_u8(lhs_limb, rhs_limb);
        memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));

        remaining_bytes -= 8 / CHAR_BIT;
        byte_offset += 8 / CHAR_BIT;
    }
}

static inline void zig_xor_big(void *res, const void *lhs, const void *rhs, bool is_signed, uint16_t bits) {
    uint8_t *res_bytes = res;
    const uint8_t *lhs_bytes = lhs;
    const uint8_t *rhs_bytes = rhs;
    uint16_t byte_offset = 0;
    uint16_t remaining_bytes = zig_int_bytes(bits);
    (void)is_signed;

    while (remaining_bytes >= 128 / CHAR_BIT) {
        zig_u128 res_limb;
        zig_u128 lhs_limb;
        zig_u128 rhs_limb;

        memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
        memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
        res_limb = zig_xor_u128(lhs_limb, rhs_limb);
        memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));

        remaining_bytes -= 128 / CHAR_BIT;
        byte_offset += 128 / CHAR_BIT;
    }

    while (remaining_bytes >= 64 / CHAR_BIT) {
        uint64_t res_limb;
        uint64_t lhs_limb;
        uint64_t rhs_limb;

        memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
        memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
        res_limb = zig_xor_u64(lhs_limb, rhs_limb);
        memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));

        remaining_bytes -= 64 / CHAR_BIT;
        byte_offset += 64 / CHAR_BIT;
    }

    while (remaining_bytes >= 32 / CHAR_BIT) {
        uint32_t res_limb;
        uint32_t lhs_limb;
        uint32_t rhs_limb;

        memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
        memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
        res_limb = zig_xor_u32(lhs_limb, rhs_limb);
        memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));

        remaining_bytes -= 32 / CHAR_BIT;
        byte_offset += 32 / CHAR_BIT;
    }

    while (remaining_bytes >= 16 / CHAR_BIT) {
        uint16_t res_limb;
        uint16_t lhs_limb;
        uint16_t rhs_limb;

        memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
        memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
        res_limb = zig_xor_u16(lhs_limb, rhs_limb);
        memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));

        remaining_bytes -= 16 / CHAR_BIT;
        byte_offset += 16 / CHAR_BIT;
    }

    while (remaining_bytes >= 8 / CHAR_BIT) {
        uint8_t res_limb;
        uint8_t lhs_limb;
        uint8_t rhs_limb;

        memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
        memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
        res_limb = zig_xor_u8(lhs_limb, rhs_limb);
        memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));

        remaining_bytes -= 8 / CHAR_BIT;
        byte_offset += 8 / CHAR_BIT;
    }
}

static inline void zig_increment_big(void *res, bool is_signed, uint16_t bits) {
    uint8_t *res_bytes = res;
    uint16_t byte_offset = 0;
    uint16_t remaining_bytes = zig_int_bytes(bits);
    uint8_t top_bits = zig_u8_intCast_u16(remaining_bytes * CHAR_BIT - bits);

#if zig_big_endian
    byte_offset = remaining_bytes;
#endif

    while (remaining_bytes >= 128 / CHAR_BIT) {
        uint8_t limb_bits = 128 - (remaining_bytes == 128 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 128 / CHAR_BIT;
#endif

        {
            zig_u128 res_limb;
            bool limb_overflow;

            memcpy(&res_limb, &res_bytes[byte_offset], sizeof(res_limb));
            limb_overflow = zig_addo_u128(&res_limb, res_limb, zig_make_u128(UINT64_C(0), UINT64_C(1)), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
            if (!limb_overflow) return;
        }

        remaining_bytes -= 128 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 128 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 64 / CHAR_BIT) {
        uint8_t limb_bits = 64 - (remaining_bytes == 64 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 64 / CHAR_BIT;
#endif

        {
            uint64_t res_limb;
            bool limb_overflow;

            memcpy(&res_limb, &res_bytes[byte_offset], sizeof(res_limb));
            limb_overflow = zig_addo_u64(&res_limb, res_limb, UINT64_C(1), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
            if (!limb_overflow) return;
        }

        remaining_bytes -= 64 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 64 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 32 / CHAR_BIT) {
        uint8_t limb_bits = 32 - (remaining_bytes == 32 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 32 / CHAR_BIT;
#endif

        {
            uint32_t res_limb;
            bool limb_overflow;

            memcpy(&res_limb, &res_bytes[byte_offset], sizeof(res_limb));
            limb_overflow = zig_addo_u32(&res_limb, res_limb, UINT32_C(1), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
            if (!limb_overflow) return;
        }

        remaining_bytes -= 32 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 32 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 16 / CHAR_BIT) {
        uint8_t limb_bits = 16 - (remaining_bytes == 16 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 16 / CHAR_BIT;
#endif

        {
            uint16_t res_limb;
            bool limb_overflow;

            memcpy(&res_limb, &res_bytes[byte_offset], sizeof(res_limb));
            limb_overflow = zig_addo_u16(&res_limb, res_limb, UINT16_C(1), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
            if (!limb_overflow) return;
        }

        remaining_bytes -= 16 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 16 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 8 / CHAR_BIT) {
        uint8_t limb_bits = 8 - (remaining_bytes == 8 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 8 / CHAR_BIT;
#endif

        {
            uint8_t res_limb;
            bool limb_overflow;

            memcpy(&res_limb, &res_bytes[byte_offset], sizeof(res_limb));
            limb_overflow = zig_addo_u8(&res_limb, res_limb, UINT8_C(1), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
            if (!limb_overflow) return;
        }

        remaining_bytes -= 8 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 8 / CHAR_BIT;
#endif
    }
}

static inline void zig_decrement_big(void *res, bool is_signed, uint16_t bits) {
    uint8_t *res_bytes = res;
    uint16_t byte_offset = 0;
    uint16_t remaining_bytes = zig_int_bytes(bits);
    uint8_t top_bits = zig_u8_intCast_u16(remaining_bytes * CHAR_BIT - bits);

#if zig_big_endian
    byte_offset = remaining_bytes;
#endif

    while (remaining_bytes >= 128 / CHAR_BIT) {
        uint8_t limb_bits = 128 - (remaining_bytes == 128 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 128 / CHAR_BIT;
#endif

        {
            zig_u128 res_limb;
            bool limb_overflow;

            memcpy(&res_limb, &res_bytes[byte_offset], sizeof(res_limb));
            limb_overflow = zig_subo_u128(&res_limb, res_limb, zig_make_u128(UINT64_C(0), UINT64_C(1)), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
            if (!limb_overflow) return;
        }

        remaining_bytes -= 128 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 128 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 64 / CHAR_BIT) {
        uint8_t limb_bits = 64 - (remaining_bytes == 64 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 64 / CHAR_BIT;
#endif

        {
            uint64_t res_limb;
            bool limb_overflow;

            memcpy(&res_limb, &res_bytes[byte_offset], sizeof(res_limb));
            limb_overflow = zig_subo_u64(&res_limb, res_limb, UINT64_C(1), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
            if (!limb_overflow) return;
        }

        remaining_bytes -= 64 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 64 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 32 / CHAR_BIT) {
        uint8_t limb_bits = 32 - (remaining_bytes == 32 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 32 / CHAR_BIT;
#endif

        {
            uint32_t res_limb;
            bool limb_overflow;

            memcpy(&res_limb, &res_bytes[byte_offset], sizeof(res_limb));
            limb_overflow = zig_subo_u32(&res_limb, res_limb, UINT32_C(1), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
            if (!limb_overflow) return;
        }

        remaining_bytes -= 32 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 32 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 16 / CHAR_BIT) {
        uint8_t limb_bits = 16 - (remaining_bytes == 16 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 16 / CHAR_BIT;
#endif

        {
            uint16_t res_limb;
            bool limb_overflow;

            memcpy(&res_limb, &res_bytes[byte_offset], sizeof(res_limb));
            limb_overflow = zig_subo_u16(&res_limb, res_limb, UINT16_C(1), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
            if (!limb_overflow) return;
        }

        remaining_bytes -= 16 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 16 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 8 / CHAR_BIT) {
        uint8_t limb_bits = 8 - (remaining_bytes == 8 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 8 / CHAR_BIT;
#endif

        {
            uint8_t res_limb;
            bool limb_overflow;

            memcpy(&res_limb, &res_bytes[byte_offset], sizeof(res_limb));
            limb_overflow = zig_subo_u8(&res_limb, res_limb, UINT8_C(1), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
            if (!limb_overflow) return;
        }

        remaining_bytes -= 8 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 8 / CHAR_BIT;
#endif
    }
}

static inline void zig_abs_big(void *res, const void *arg, bool is_signed, uint16_t bits) {
    uint8_t *res_bytes = res;
    const uint8_t *arg_bytes = arg;
    uint16_t byte_offset = 0;
    uint16_t remaining_bytes = zig_int_bytes(bits);
    if (zig_signFill_big(arg, is_signed, bits) >= INT8_C(0)) {
        memcpy(res, arg, remaining_bytes);
        return;
    }
    uint8_t top_bits = zig_u8_intCast_u16(remaining_bytes * CHAR_BIT - bits);
    bool overflow = true;

#if zig_big_endian
    byte_offset = remaining_bytes;
#endif

    while (remaining_bytes >= 128 / CHAR_BIT) {
        uint8_t limb_bits = 128 - (remaining_bytes == 128 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 128 / CHAR_BIT;
#endif

        {
            zig_u128 res_limb;
            zig_u128 arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            overflow = zig_addo_u128(&res_limb, zig_not_u128(arg_limb, UINT8_C(128)), zig_make_u128(UINT64_C(0), overflow ? UINT64_C(1) : UINT64_C(0)), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        }

        remaining_bytes -= 128 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 128 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 64 / CHAR_BIT) {
        uint8_t limb_bits = 64 - (remaining_bytes == 64 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 64 / CHAR_BIT;
#endif

        {
            uint64_t res_limb;
            uint64_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            overflow = zig_addo_u64(&res_limb, zig_not_u64(arg_limb, UINT8_C(64)), overflow ? UINT64_C(1) : UINT64_C(0), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        }

        remaining_bytes -= 64 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 64 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 32 / CHAR_BIT) {
        uint8_t limb_bits = 32 - (remaining_bytes == 32 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 32 / CHAR_BIT;
#endif

        {
            uint32_t res_limb;
            uint32_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            overflow = zig_addo_u32(&res_limb, zig_not_u32(arg_limb, UINT8_C(32)), overflow ? UINT32_C(1) : UINT32_C(0), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        }

        remaining_bytes -= 32 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 32 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 16 / CHAR_BIT) {
        uint8_t limb_bits = 16 - (remaining_bytes == 16 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 16 / CHAR_BIT;
#endif

        {
            uint16_t res_limb;
            uint16_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            overflow = zig_addo_u16(&res_limb, zig_not_u16(arg_limb, UINT8_C(16)), overflow ? UINT16_C(1) : UINT16_C(0), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        }

        remaining_bytes -= 16 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 16 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 8 / CHAR_BIT) {
        uint8_t limb_bits = 8 - (remaining_bytes == 8 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 8 / CHAR_BIT;
#endif

        {
            uint8_t res_limb;
            uint8_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            overflow = zig_addo_u8(&res_limb, zig_not_u8(arg_limb, UINT8_C(8)), overflow ? UINT8_C(1) : UINT8_C(0), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        }

        remaining_bytes -= 8 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 8 / CHAR_BIT;
#endif
    }
}

static inline void zig_min_big(void *res, const void *lhs, const void *rhs, bool is_signed, uint16_t bits) {
    memcpy(res, zig_cmp_big(lhs, rhs, is_signed, bits) < INT32_C(0) ? lhs : rhs, zig_int_bytes(bits));
}

static inline void zig_max_big(void *res, const void *lhs, const void *rhs, bool is_signed, uint16_t bits) {
    memcpy(res, zig_cmp_big(lhs, rhs, is_signed, bits) >= INT32_C(0) ? lhs : rhs, zig_int_bytes(bits));
}

static inline bool zig_addo_big(void *res, const void *lhs, const void *rhs, bool is_signed, uint16_t bits) {
    uint8_t *res_bytes = res;
    const uint8_t *lhs_bytes = lhs;
    const uint8_t *rhs_bytes = rhs;
    uint16_t byte_offset = 0;
    uint16_t remaining_bytes = zig_int_bytes(bits);
    uint8_t top_bits = zig_u8_intCast_u16(remaining_bytes * CHAR_BIT - bits);
    bool overflow = false;

#if zig_big_endian
    byte_offset = remaining_bytes;
#endif

    while (remaining_bytes >= 128 / CHAR_BIT) {
        uint8_t limb_bits = 128 - (remaining_bytes == 128 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 128 / CHAR_BIT;
#endif

        if (remaining_bytes == 128 / CHAR_BIT && is_signed) {
            zig_i128 res_limb;
            zig_i128 tmp_limb;
            zig_i128 lhs_limb;
            zig_i128 rhs_limb;
            bool limb_overflow;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_overflow = zig_addo_i128(&tmp_limb, lhs_limb, rhs_limb, limb_bits);
            overflow = limb_overflow ^ zig_addo_i128(&res_limb, tmp_limb, zig_make_i128(INT64_C(0), overflow ? UINT64_C(1) : UINT64_C(0)), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        } else {
            zig_u128 res_limb;
            zig_u128 tmp_limb;
            zig_u128 lhs_limb;
            zig_u128 rhs_limb;
            bool limb_overflow;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_overflow = zig_addo_u128(&tmp_limb, lhs_limb, rhs_limb, limb_bits);
            overflow = limb_overflow ^ zig_addo_u128(&res_limb, tmp_limb, zig_make_u128(UINT64_C(0), overflow ? UINT64_C(1) : UINT64_C(0)), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        }

        remaining_bytes -= 128 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 128 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 64 / CHAR_BIT) {
        uint8_t limb_bits = 64 - (remaining_bytes == 64 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 64 / CHAR_BIT;
#endif

        if (remaining_bytes == 64 / CHAR_BIT && is_signed) {
            int64_t res_limb;
            int64_t tmp_limb;
            int64_t lhs_limb;
            int64_t rhs_limb;
            bool limb_overflow;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_overflow = zig_addo_i64(&tmp_limb, lhs_limb, rhs_limb, limb_bits);
            overflow = limb_overflow ^ zig_addo_i64(&res_limb, tmp_limb, overflow ? INT64_C(1) : INT64_C(0), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        } else {
            uint64_t res_limb;
            uint64_t tmp_limb;
            uint64_t lhs_limb;
            uint64_t rhs_limb;
            bool limb_overflow;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_overflow = zig_addo_u64(&tmp_limb, lhs_limb, rhs_limb, limb_bits);
            overflow = limb_overflow ^ zig_addo_u64(&res_limb, tmp_limb, overflow ? UINT64_C(1) : UINT64_C(0), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        }

        remaining_bytes -= 64 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 64 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 32 / CHAR_BIT) {
        uint8_t limb_bits = 32 - (remaining_bytes == 32 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 32 / CHAR_BIT;
#endif

        if (remaining_bytes == 32 / CHAR_BIT && is_signed) {
            int32_t res_limb;
            int32_t tmp_limb;
            int32_t lhs_limb;
            int32_t rhs_limb;
            bool limb_overflow;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_overflow = zig_addo_i32(&tmp_limb, lhs_limb, rhs_limb, limb_bits);
            overflow = limb_overflow ^ zig_addo_i32(&res_limb, tmp_limb, overflow ? INT32_C(1) : INT32_C(0), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        } else {
            uint32_t res_limb;
            uint32_t tmp_limb;
            uint32_t lhs_limb;
            uint32_t rhs_limb;
            bool limb_overflow;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_overflow = zig_addo_u32(&tmp_limb, lhs_limb, rhs_limb, limb_bits);
            overflow = limb_overflow ^ zig_addo_u32(&res_limb, tmp_limb, overflow ? UINT32_C(1) : UINT32_C(0), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        }

        remaining_bytes -= 32 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 32 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 16 / CHAR_BIT) {
        uint8_t limb_bits = 16 - (remaining_bytes == 16 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 16 / CHAR_BIT;
#endif

        if (remaining_bytes == 16 / CHAR_BIT && is_signed) {
            int16_t res_limb;
            int16_t tmp_limb;
            int16_t lhs_limb;
            int16_t rhs_limb;
            bool limb_overflow;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_overflow = zig_addo_i16(&tmp_limb, lhs_limb, rhs_limb, limb_bits);
            overflow = limb_overflow ^ zig_addo_i16(&res_limb, tmp_limb, overflow ? INT16_C(1) : INT16_C(0), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        } else {
            uint16_t res_limb;
            uint16_t tmp_limb;
            uint16_t lhs_limb;
            uint16_t rhs_limb;
            bool limb_overflow;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_overflow = zig_addo_u16(&tmp_limb, lhs_limb, rhs_limb, limb_bits);
            overflow = limb_overflow ^ zig_addo_u16(&res_limb, tmp_limb, overflow ? UINT16_C(1) : UINT16_C(0), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        }

        remaining_bytes -= 16 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 16 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 8 / CHAR_BIT) {
        uint8_t limb_bits = 8 - (remaining_bytes == 8 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 8 / CHAR_BIT;
#endif

        if (remaining_bytes == 8 / CHAR_BIT && is_signed) {
            int8_t res_limb;
            int8_t tmp_limb;
            int8_t lhs_limb;
            int8_t rhs_limb;
            bool limb_overflow;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_overflow = zig_addo_i8(&tmp_limb, lhs_limb, rhs_limb, limb_bits);
            overflow = limb_overflow ^ zig_addo_i8(&res_limb, tmp_limb, overflow ? INT8_C(1) : INT8_C(0), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        } else {
            uint8_t res_limb;
            uint8_t tmp_limb;
            uint8_t lhs_limb;
            uint8_t rhs_limb;
            bool limb_overflow;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_overflow = zig_addo_u8(&tmp_limb, lhs_limb, rhs_limb, limb_bits);
            overflow = limb_overflow ^ zig_addo_u8(&res_limb, tmp_limb, overflow ? UINT8_C(1) : UINT8_C(0), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        }

        remaining_bytes -= 8 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 8 / CHAR_BIT;
#endif
    }

    return overflow;
}

static inline bool zig_subo_big(void *res, const void *lhs, const void *rhs, bool is_signed, uint16_t bits) {
    uint8_t *res_bytes = res;
    const uint8_t *lhs_bytes = lhs;
    const uint8_t *rhs_bytes = rhs;
    uint16_t byte_offset = 0;
    uint16_t remaining_bytes = zig_int_bytes(bits);
    uint8_t top_bits = zig_u8_intCast_u16(remaining_bytes * CHAR_BIT - bits);
    bool overflow = false;

#if zig_big_endian
    byte_offset = remaining_bytes;
#endif

    while (remaining_bytes >= 128 / CHAR_BIT) {
        uint8_t limb_bits = 128 - (remaining_bytes == 128 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 128 / CHAR_BIT;
#endif

        if (remaining_bytes == 128 / CHAR_BIT && is_signed) {
            zig_i128 res_limb;
            zig_i128 tmp_limb;
            zig_i128 lhs_limb;
            zig_i128 rhs_limb;
            bool limb_overflow;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_overflow = zig_subo_i128(&tmp_limb, lhs_limb, rhs_limb, limb_bits);
            overflow = limb_overflow ^ zig_subo_i128(&res_limb, tmp_limb, zig_make_i128(INT64_C(0), overflow ? UINT64_C(1) : UINT64_C(0)), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        } else {
            zig_u128 res_limb;
            zig_u128 tmp_limb;
            zig_u128 lhs_limb;
            zig_u128 rhs_limb;
            bool limb_overflow;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_overflow = zig_subo_u128(&tmp_limb, lhs_limb, rhs_limb, limb_bits);
            overflow = limb_overflow ^ zig_subo_u128(&res_limb, tmp_limb, zig_make_u128(UINT64_C(0), overflow ? UINT64_C(1) : UINT64_C(0)), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        }

        remaining_bytes -= 128 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 128 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 64 / CHAR_BIT) {
        uint8_t limb_bits = 64 - (remaining_bytes == 64 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 64 / CHAR_BIT;
#endif

        if (remaining_bytes == 64 / CHAR_BIT && is_signed) {
            int64_t res_limb;
            int64_t tmp_limb;
            int64_t lhs_limb;
            int64_t rhs_limb;
            bool limb_overflow;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_overflow = zig_subo_i64(&tmp_limb, lhs_limb, rhs_limb, limb_bits);
            overflow = limb_overflow ^ zig_subo_i64(&res_limb, tmp_limb, overflow ? INT64_C(1) : INT64_C(0), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        } else {
            uint64_t res_limb;
            uint64_t tmp_limb;
            uint64_t lhs_limb;
            uint64_t rhs_limb;
            bool limb_overflow;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_overflow = zig_subo_u64(&tmp_limb, lhs_limb, rhs_limb, limb_bits);
            overflow = limb_overflow ^ zig_subo_u64(&res_limb, tmp_limb, overflow ? UINT64_C(1) : UINT64_C(0), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        }

        remaining_bytes -= 64 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 64 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 32 / CHAR_BIT) {
        uint8_t limb_bits = 32 - (remaining_bytes == 32 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 32 / CHAR_BIT;
#endif

        if (remaining_bytes == 32 / CHAR_BIT && is_signed) {
            int32_t res_limb;
            int32_t tmp_limb;
            int32_t lhs_limb;
            int32_t rhs_limb;
            bool limb_overflow;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_overflow = zig_subo_i32(&tmp_limb, lhs_limb, rhs_limb, limb_bits);
            overflow = limb_overflow ^ zig_subo_i32(&res_limb, tmp_limb, overflow ? INT32_C(1) : INT32_C(0), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        } else {
            uint32_t res_limb;
            uint32_t tmp_limb;
            uint32_t lhs_limb;
            uint32_t rhs_limb;
            bool limb_overflow;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_overflow = zig_subo_u32(&tmp_limb, lhs_limb, rhs_limb, limb_bits);
            overflow = limb_overflow ^ zig_subo_u32(&res_limb, tmp_limb, overflow ? UINT32_C(1) : UINT32_C(0), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        }

        remaining_bytes -= 32 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 32 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 16 / CHAR_BIT) {
        uint8_t limb_bits = 16 - (remaining_bytes == 16 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 16 / CHAR_BIT;
#endif

        if (remaining_bytes == 16 / CHAR_BIT && is_signed) {
            int16_t res_limb;
            int16_t tmp_limb;
            int16_t lhs_limb;
            int16_t rhs_limb;
            bool limb_overflow;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_overflow = zig_subo_i16(&tmp_limb, lhs_limb, rhs_limb, limb_bits);
            overflow = limb_overflow ^ zig_subo_i16(&res_limb, tmp_limb, overflow ? INT16_C(1) : INT16_C(0), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        } else {
            uint16_t res_limb;
            uint16_t tmp_limb;
            uint16_t lhs_limb;
            uint16_t rhs_limb;
            bool limb_overflow;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_overflow = zig_subo_u16(&tmp_limb, lhs_limb, rhs_limb, limb_bits);
            overflow = limb_overflow ^ zig_subo_u16(&res_limb, tmp_limb, overflow ? UINT16_C(1) : UINT16_C(0), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        }

        remaining_bytes -= 16 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 16 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 8 / CHAR_BIT) {
        uint8_t limb_bits = 8 - (remaining_bytes == 8 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 8 / CHAR_BIT;
#endif

        if (remaining_bytes == 8 / CHAR_BIT && is_signed) {
            int8_t res_limb;
            int8_t tmp_limb;
            int8_t lhs_limb;
            int8_t rhs_limb;
            bool limb_overflow;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_overflow = zig_subo_i8(&tmp_limb, lhs_limb, rhs_limb, limb_bits);
            overflow = limb_overflow ^ zig_subo_i8(&res_limb, tmp_limb, overflow ? INT8_C(1) : INT8_C(0), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        } else {
            uint8_t res_limb;
            uint8_t tmp_limb;
            uint8_t lhs_limb;
            uint8_t rhs_limb;
            bool limb_overflow;

            memcpy(&lhs_limb, &lhs_bytes[byte_offset], sizeof(lhs_limb));
            memcpy(&rhs_limb, &rhs_bytes[byte_offset], sizeof(rhs_limb));
            limb_overflow = zig_subo_u8(&tmp_limb, lhs_limb, rhs_limb, limb_bits);
            overflow = limb_overflow ^ zig_subo_u8(&res_limb, tmp_limb, overflow ? UINT8_C(1) : UINT8_C(0), limb_bits);
            memcpy(&res_bytes[byte_offset], &res_limb, sizeof(res_limb));
        }

        remaining_bytes -= 8 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 8 / CHAR_BIT;
#endif
    }

    return overflow;
}

static inline void zig_add_big(void *res, const void *lhs, const void *rhs, bool is_signed, uint16_t bits) {
    if (zig_addo_big(res, lhs, rhs, is_signed, bits)) zig_trap(); // panic: integer overflow
}

static inline void zig_addw_big(void *res, const void *lhs, const void *rhs, bool is_signed, uint16_t bits) {
    (void)zig_addo_big(res, lhs, rhs, is_signed, bits);
}

static inline void zig_adds_big(void *res, const void *lhs, const void *rhs, bool is_signed, uint16_t bits) {
    int8_t sat_sign = zig_signFill_big(lhs, is_signed, bits);

    if (!zig_addo_big(res, lhs, rhs, is_signed, bits)) return;
    switch (sat_sign) {
        case -INT8_C(1): return zig_minInt_big(res, is_signed, bits);
        case  INT8_C(0): return zig_maxInt_big(res, is_signed, bits);
    }
}

static inline void zig_sub_big(void *res, const void *lhs, const void *rhs, bool is_signed, uint16_t bits) {
    if (zig_subo_big(res, lhs, rhs, is_signed, bits)) zig_trap(); // panic: integer overflow
}

static inline void zig_subw_big(void *res, const void *lhs, const void *rhs, bool is_signed, uint16_t bits) {
    (void)zig_subo_big(res, lhs, rhs, is_signed, bits);
}

static inline void zig_subs_big(void *res, const void *lhs, const void *rhs, bool is_signed, uint16_t bits) {
    int8_t sat_sign = is_signed ? zig_signFill_big(lhs, is_signed, bits) : -INT8_C(1);

    if (!zig_subo_big(res, lhs, rhs, is_signed, bits)) return;
    switch (sat_sign) {
        case -INT8_C(1): return zig_minInt_big(res, is_signed, bits);
        case  INT8_C(0): return zig_maxInt_big(res, is_signed, bits);
    }
}

static inline bool zig_mulo_big(void *res, const void *lhs, const void *rhs, bool is_signed, uint16_t bits) {
    uint8_t *res_bytes = res;
    const uint8_t *lhs_bytes = lhs;
    const uint8_t *rhs_bytes = rhs;
    uint16_t size = zig_int_bytes(bits);
    uint16_t sign_byte_offset = zig_shr_u16(bits - UINT16_C(1), UINT8_C(3)) + UINT16_C(1);
    uint8_t lhs_sign_fill = zig_u8_bitCast_i8(zig_signFill_big(lhs, is_signed, bits), UINT8_C(8));
    uint8_t rhs_sign_fill = zig_u8_bitCast_i8(zig_signFill_big(rhs, is_signed, bits), UINT8_C(8));
    uint16_t lhs_byte_offset = sign_byte_offset;
    uint16_t lhs_end_byte_offset = UINT16_C(0);
    bool overflow = false;

#if zig_big_endian
    lhs_byte_offset = size - lhs_byte_offset;
    lhs_end_byte_offset = size - lhs_end_byte_offset;
#endif

    while (lhs_byte_offset != lhs_end_byte_offset) {
        uint16_t rhs_byte_offset = UINT16_C(0);
        uint16_t end_byte_offset = sign_byte_offset;
        uint16_t res_byte_offset;
        uint16_t lhs_byte;
        uint8_t res_byte = UINT8_C(0);
        uint16_t mul_res = UINT16_C(0);
        uint8_t carry = UINT8_C(0);

#if zig_little_endian
        lhs_byte_offset -= UINT16_C(1);
#else
        rhs_byte_offset = size - rhs_byte_offset;
        end_byte_offset = size - end_byte_offset;
#endif

        lhs_byte = zig_u16_intCast_u8(lhs_bytes[lhs_byte_offset]) ^ lhs_sign_fill;

#if zig_big_endian
        lhs_byte_offset += UINT16_C(1);
#endif

        res_byte_offset = lhs_byte_offset;

        while (res_byte_offset != end_byte_offset) {
            bool res_byte_initialized = res_byte_offset != lhs_byte_offset;

#if zig_big_endian
            rhs_byte_offset -= UINT16_C(1);
            res_byte_offset -= UINT16_C(1);
#endif

            if (res_byte_initialized) res_byte = res_bytes[res_byte_offset];
            carry = zig_addo_u8(&res_byte, res_byte, carry, UINT8_C(8));
            carry += zig_addo_u8(&res_byte, res_byte, zig_u8_intCast_u16(
                zig_shr_u16(mul_res, UINT8_C(8))
            ), UINT8_C(8));
            mul_res = lhs_byte * zig_u16_intCast_u8(rhs_bytes[rhs_byte_offset] ^ rhs_sign_fill);
            carry += zig_addo_u8(&res_bytes[res_byte_offset], res_byte, zig_u8_truncate_u16(
                mul_res,
                UINT8_C(8)
            ), UINT8_C(8));

#if zig_little_endian
            rhs_byte_offset += UINT16_C(1);
            res_byte_offset += UINT16_C(1);
#endif
        }

        while (rhs_byte_offset != end_byte_offset) {
#if zig_big_endian
            rhs_byte_offset -= UINT16_C(1);
#endif

            carry = zig_addo_u8(
                &res_byte,
                zig_u8_intCast_u16(zig_shr_u16(mul_res, UINT8_C(8))),
                carry,
                UINT8_C(8)
            );
            mul_res = lhs_byte * zig_u16_intCast_u8(rhs_bytes[rhs_byte_offset] ^ rhs_sign_fill);
            carry += zig_addo_u8(&res_byte, res_byte, zig_u8_truncate_u16(
                mul_res,
                UINT8_C(8)
            ), UINT8_C(8));
            overflow |= res_byte != UINT8_C(0);

#if zig_little_endian
            rhs_byte_offset += UINT16_C(1);
#endif
        }

        overflow |= zig_shr_u16(mul_res, UINT8_C(8)) != UINT16_C(0);
        overflow |= carry != UINT8_C(0);
    }

#if zig_little_endian
        sign_byte_offset -= UINT64_C(1);
#else
        sign_byte_offset = size - sign_byte_offset;
#endif

    if (lhs_sign_fill != rhs_sign_fill) {
        uint16_t byte_offset = UINT16_C(0);
        uint16_t end_byte_offset = sign_byte_offset;
        uint8_t res_byte;
        int8_t signed_res_byte;
        uint8_t carry = UINT8_C(0);

#if zig_big_endian
        byte_offset = size - byte_offset;
        end_byte_offset += UINT16_C(1);
#endif

        while (byte_offset != end_byte_offset) {
#if zig_big_endian
            byte_offset -= UINT16_C(1);
#endif

            carry = zig_subo_u8(&res_byte, UINT8_C(0), carry, UINT8_C(8));
            carry += zig_subo_u8(&res_byte, res_byte, res_bytes[byte_offset], UINT8_C(8));
            carry += zig_subo_u8(
                &res_bytes[byte_offset],
                res_byte,
                (lhs_sign_fill == UINT8_C(0) ? lhs_bytes : rhs_bytes)[byte_offset],
                UINT8_C(8)
            );

#if zig_little_endian
            byte_offset += UINT16_C(1);
#endif
        }

#if zig_big_endian
        byte_offset -= UINT16_C(1);
#endif

        signed_res_byte = zig_i8_bitCast_u8(res_bytes[byte_offset], UINT8_C(8));
        overflow |= signed_res_byte < INT8_C(0);
        overflow |= zig_subo_i8(&signed_res_byte, INT8_C(0), signed_res_byte, UINT8_C(8));
        overflow |= zig_subo_i8(&signed_res_byte, signed_res_byte, zig_i8_intCast_u8(carry), UINT8_C(8));
        overflow |= zig_subo_i8(&signed_res_byte, signed_res_byte, zig_i8_bitCast_u8(
            (lhs_sign_fill == UINT8_C(0) ? lhs_bytes : rhs_bytes)[byte_offset],
            UINT8_C(8)
        ), UINT8_C(8));
        res_bytes[byte_offset] = zig_i8_bitCast_u8(signed_res_byte, UINT8_C(8));
    } else if (lhs_sign_fill != UINT8_C(0)) {
        uint16_t byte_offset = UINT16_C(0);
        uint16_t end_byte_offset = sign_byte_offset;
        uint8_t res_byte;
        int8_t signed_res_byte;
        uint8_t carry = UINT8_C(1);

#if zig_big_endian
        byte_offset = size - byte_offset;
        end_byte_offset += UINT16_C(1);
#endif

        while (byte_offset != end_byte_offset) {
#if zig_big_endian
            byte_offset -= UINT16_C(1);
#endif

            carry = zig_subo_u8(&res_byte, res_bytes[byte_offset], carry, UINT8_C(8));
            carry += zig_subo_u8(&res_byte, res_byte, lhs_bytes[byte_offset], UINT8_C(8));
            carry += zig_subo_u8(&res_bytes[byte_offset], res_byte, rhs_bytes[byte_offset], UINT8_C(8));

#if zig_little_endian
            byte_offset += UINT16_C(1);
#endif
        }

#if zig_big_endian
        byte_offset -= UINT16_C(1);
#endif

        signed_res_byte = zig_i8_bitCast_u8(res_bytes[byte_offset], UINT8_C(8));
        overflow |= signed_res_byte < INT8_C(0);
        overflow |= zig_subo_i8(&signed_res_byte, signed_res_byte, zig_i8_intCast_u8(carry), UINT8_C(8));
        overflow |= zig_subo_i8(&signed_res_byte, signed_res_byte, zig_i8_bitCast_u8(
            lhs_bytes[byte_offset],
            UINT8_C(8)
        ), UINT8_C(8));
        overflow |= zig_subo_i8(&signed_res_byte, signed_res_byte, zig_i8_bitCast_u8(
            rhs_bytes[byte_offset],
            UINT8_C(8)
        ), UINT8_C(8));
        res_bytes[byte_offset] = zig_i8_bitCast_u8(signed_res_byte, UINT8_C(8));
    } else if (is_signed) {
        int8_t signed_res_byte = zig_i8_bitCast_u8(res_bytes[sign_byte_offset], UINT8_C(8));

        overflow |= signed_res_byte < INT8_C(0);
    }

    {
        uint8_t truncate_bits = zig_u8_truncate_u16(bits - UINT16_C(1), UINT8_C(3)) + UINT16_C(1);
        uint8_t fill_byte = UINT8_C(0);

        if (is_signed) {
            int8_t sign_byte = zig_i8_bitCast_u8(res_bytes[sign_byte_offset], UINT8_C(8));
            int8_t truncated = zig_i8_truncate_i8(sign_byte, truncate_bits);

            overflow |= sign_byte != truncated;
            res_bytes[sign_byte_offset] = zig_u8_bitCast_i8(truncated, UINT8_C(8));
            fill_byte = zig_u8_bitCast_i8(zig_shr_i8(truncated, UINT8_C(7)), UINT8_C(8));
        } else {
            uint8_t sign_byte = res_bytes[sign_byte_offset];
            uint8_t truncated = zig_u8_truncate_u8(sign_byte, truncate_bits);

            overflow |= sign_byte != truncated;
            res_bytes[sign_byte_offset] = truncated;
        }

#if zig_little_endian
        sign_byte_offset += UINT16_C(1);
        memset(&res_bytes[sign_byte_offset], fill_byte, size - sign_byte_offset);
#else
        memset(&res_bytes[0], fill_byte, sign_byte_offset);
#endif
    }

    return overflow;
}

static inline void zig_mul_big(void *res, const void *lhs, const void *rhs, bool is_signed, uint16_t bits) {
    if (zig_mulo_big(res, lhs, rhs, is_signed, bits)) zig_trap(); // panic: integer overflow
}

static inline void zig_mulw_big(void *res, const void *lhs, const void *rhs, bool is_signed, uint16_t bits) {
    (void)zig_mulo_big(res, lhs, rhs, is_signed, bits);
}

static inline void zig_muls_big(void *res, const void *lhs, const void *rhs, bool is_signed, uint16_t bits) {
    int8_t sat_sign = zig_signFill_big(lhs, is_signed, bits) ^ zig_signFill_big(rhs, is_signed, bits);

    if (!zig_mulo_big(res, lhs, rhs, is_signed, bits)) return;
    switch (sat_sign) {
        case -INT8_C(1): return zig_minInt_big(res, is_signed, bits);
        case  INT8_C(0): return zig_maxInt_big(res, is_signed, bits);
    }
}

static inline void zig_divTrunc_big(void *res, const void *lhs, const void *rhs, void *temp, bool is_signed, uint16_t bits) {
    if (is_signed) {
        zig_extern void __divei5(uint32_t *res, const uint32_t *lhs, const uint32_t *rhs, uint32_t *temp, uintptr_t bits);
        __divei5(res, lhs, rhs, temp, bits);
    } else {
        zig_extern void __udivei5(uint32_t *res, const uint32_t *lhs, const uint32_t *rhs, uint32_t *temp, uintptr_t bits);
        __udivei5(res, lhs, rhs, temp, bits);
    }
}

static inline void zig_rem_big(void *res, const void *lhs, const void *rhs, void *temp, bool is_signed, uint16_t bits) {
    if (is_signed) {
        zig_extern void __modei5(uint32_t *res, const uint32_t *lhs, const uint32_t *rhs, uint32_t *temp, uintptr_t bits);
        __modei5(res, lhs, rhs, temp, bits);
    } else {
        zig_extern void __umodei5(uint32_t *res, const uint32_t *lhs, const uint32_t *rhs, uint32_t *temp, uintptr_t bits);
        __umodei5(res, lhs, rhs, temp, bits);
    }
}

static inline void zig_divFloor_big(void *res, const void *lhs, const void *rhs, void *temp, bool is_signed, uint16_t bits) {
    bool decrement = false;

    if (is_signed) {
        zig_rem_big(res, lhs, rhs, temp, is_signed, bits);
        decrement = zig_u32_bitCast_i32(zig_xor_i32(
            zig_cmp_big_u8(res, UINT8_C(0), is_signed, bits),
            zig_and_i32(zig_i32_intCast_i8(zig_signFill_big(rhs, is_signed, bits)), zig_minInt_i32)
        ), UINT8_C(32)) > zig_u32_bitCast_i32(zig_minInt_i32, UINT8_C(32));
    }
    zig_divTrunc_big(res, lhs, rhs, temp, is_signed, bits);
    if (decrement) zig_decrement_big(res, is_signed, bits);
}

static inline void zig_divCeil_big(void *res, const void *lhs, const void *rhs, void *temp, bool is_signed, uint16_t bits) {
    bool increment = false;

    zig_rem_big(res, lhs, rhs, temp, is_signed, bits);
    increment = zig_xor_i32(
        zig_cmp_big_u8(res, UINT8_C(0), is_signed, bits),
        zig_and_i32(zig_i32_intCast_i8(zig_signFill_big(rhs, is_signed, bits)), zig_minInt_i32)
    ) > INT32_C(0);
    zig_divTrunc_big(res, lhs, rhs, temp, is_signed, bits);
    if (increment) zig_increment_big(res, is_signed, bits);
}

static inline void zig_mod_big(void *res, const void *lhs, const void *rhs, void *temp, bool is_signed, uint16_t bits) {
    bool fixup = false;

    zig_rem_big(res, lhs, rhs, temp, is_signed, bits);
    if (is_signed && zig_u32_bitCast_i32(zig_xor_i32(
        zig_cmp_big_u8(res, UINT8_C(0), is_signed, bits),
        zig_and_i32(zig_i32_intCast_i8(zig_signFill_big(rhs, is_signed, bits)), zig_minInt_i32)
    ), UINT8_C(32)) > zig_u32_bitCast_i32(zig_minInt_i32, UINT8_C(32))) zig_add_big(res, res, rhs, is_signed, bits);
}

static inline void zig_shr_big(void *res, const void *lhs, uint16_t rhs, bool is_signed, uint16_t bits) {
    uint8_t *res_bytes = res;
    const uint8_t *lhs_bytes = lhs;
    uint16_t size = zig_int_bytes(bits);
    uint16_t res_byte_offset = UINT16_C(0);
    uint16_t lhs_byte_offset = zig_shr_u16(rhs, UINT8_C(3));
    uint16_t end_byte_offset = zig_shr_u16(bits - UINT16_C(1), UINT8_C(3)) + UINT16_C(1);
    uint8_t lhs_prev_byte;
    uint8_t byte_shift = zig_u8_truncate_u16(rhs, UINT8_C(3));

#if zig_big_endian
    res_byte_offset = size - res_byte_offset;
    lhs_byte_offset = size - lhs_byte_offset;
    end_byte_offset = size - end_byte_offset;
#endif

    {
#if zig_big_endian
        lhs_byte_offset -= UINT16_C(1);
#endif

        lhs_prev_byte = lhs_bytes[lhs_byte_offset];

#if zig_little_endian
        lhs_byte_offset += UINT16_C(1);
#endif
    }

    while (lhs_byte_offset != end_byte_offset) {
#if zig_big_endian
        res_byte_offset -= UINT16_C(1);
        lhs_byte_offset -= UINT16_C(1);
#endif

        {
            uint8_t lhs_byte = lhs_bytes[lhs_byte_offset];

            res_bytes[res_byte_offset] = zig_u8_intCast_u16(zig_shr_u16(zig_or_u16(
                zig_shl_u16(zig_u16_intCast_u8(lhs_byte), UINT8_C(8)),
                zig_u16_intCast_u8(lhs_prev_byte)
            ), byte_shift));
            lhs_prev_byte = lhs_byte;
        }

#if zig_little_endian
        res_byte_offset += UINT16_C(1);
        lhs_byte_offset += UINT16_C(1);
#endif
    }

    {
        uint8_t lhs_sign_fill = UINT8_C(0);

#if zig_big_endian
        res_byte_offset -= UINT16_C(1);
#endif

        if (is_signed) {
            int8_t signed_byte = zig_i8_bitCast_u8(lhs_prev_byte, UINT8_C(8));

            res_bytes[res_byte_offset] = zig_shr_i8(signed_byte, byte_shift);
            lhs_sign_fill = zig_u8_bitCast_i8(zig_shr_i8(signed_byte, UINT8_C(7)), UINT8_C(8));
        } else {
            res_bytes[res_byte_offset] = zig_shr_u8(lhs_prev_byte, byte_shift);
        }

#if zig_little_endian
        res_byte_offset += UINT16_C(1);
        memset(&res_bytes[res_byte_offset], lhs_sign_fill, size - res_byte_offset);
#else
        memset(&res_bytes[0], lhs_sign_fill, res_byte_offset);
#endif
    }
}

static inline bool zig_shlo_big(void *res, const void *lhs, uint16_t rhs, bool is_signed, uint16_t bits) {
    uint8_t *res_bytes = res;
    const uint8_t *lhs_bytes = lhs;
    uint8_t lhs_sign_fill = zig_u8_bitCast_i8(zig_signFill_big(lhs, is_signed, bits), UINT8_C(8));
    uint16_t size = zig_int_bytes(bits);
    uint16_t res_byte_offset = zig_shr_u16(bits - UINT16_C(1), UINT8_C(3)) + UINT16_C(1);
    uint16_t lhs_byte_offset = UINT16_C(0);
    uint16_t end_byte_offset = res_byte_offset - UINT16_C(1) - zig_shr_u16(rhs, UINT8_C(3));
    uint8_t lhs_prev_byte = lhs_sign_fill;
    uint8_t byte_shift = UINT8_C(8) - zig_u8_truncate_u16(rhs, UINT8_C(3));
    bool overflow = false;

#if zig_little_endian
    lhs_byte_offset = size - lhs_byte_offset;
#else
    res_byte_offset = size - res_byte_offset;
    end_byte_offset = size - end_byte_offset;
#endif

    while (lhs_byte_offset != end_byte_offset) {
#if zig_little_endian
        lhs_byte_offset -= UINT16_C(1);
#endif

        overflow |= lhs_prev_byte != lhs_sign_fill;
        lhs_prev_byte = lhs_bytes[lhs_byte_offset];

#if zig_big_endian
        lhs_byte_offset += UINT16_C(1);
#endif
    }

#if zig_little_endian
    end_byte_offset = UINT16_C(0);
#else
    end_byte_offset = size;
#endif

    {
        bool lhs_more_bytes = lhs_byte_offset != end_byte_offset;

#if zig_little_endian
        if (lhs_more_bytes) lhs_byte_offset -= UINT16_C(1);
#endif

        {
            uint8_t lhs_byte = UINT8_C(0);

            if (lhs_more_bytes) lhs_byte = lhs_bytes[lhs_byte_offset];

            if (is_signed) {
                int16_t shifted = zig_shr_i16(zig_or_i16(
                    zig_shl_i16(zig_i16_intCast_u8(lhs_prev_byte), UINT8_C(8)),
                    zig_i16_intCast_u8(lhs_byte)
                ), byte_shift);
                int8_t truncated = zig_i8_truncate_i16(
                    shifted,
                    zig_u8_truncate_u16(bits - UINT16_C(1), UINT8_C(3)) + UINT8_C(1)
                );
                uint8_t fill = zig_u8_bitCast_i8(zig_shr_i8(truncated, UINT8_C(7)), UINT8_C(8));

                overflow |= zig_i16_intCast_i8(truncated) != shifted;
#if zig_little_endian
                memset(&res_bytes[res_byte_offset], fill, size - res_byte_offset);
                res_byte_offset -= UINT16_C(1);
#else
                memset(&res_bytes[0], fill, res_byte_offset);
#endif
                res_bytes[res_byte_offset] = zig_u8_bitCast_i8(truncated, UINT8_C(8));
            } else {
                uint16_t shifted = zig_shr_u16(zig_or_u16(
                    zig_shl_u16(zig_u16_intCast_u8(lhs_prev_byte), UINT8_C(8)),
                    zig_u16_intCast_u8(lhs_byte)
                ), byte_shift);
                uint8_t truncated = zig_u8_truncate_u16(
                    shifted,
                    zig_u8_truncate_u16(bits - UINT16_C(1), UINT8_C(3)) + UINT8_C(1)
                );

                overflow |= zig_u16_intCast_u8(truncated) != shifted;
#if zig_little_endian
                memset(&res_bytes[res_byte_offset], zig_minInt_u8, size - res_byte_offset);
                res_byte_offset -= UINT16_C(1);
#else
                memset(&res_bytes[0], zig_minInt_u8, res_byte_offset);
#endif
                res_bytes[res_byte_offset] = truncated;
            }

            lhs_prev_byte = lhs_byte;
        }

#if zig_big_endian
        res_byte_offset += UINT16_C(1);
        if (lhs_more_bytes) lhs_byte_offset += UINT16_C(1);
#endif
    }

    while (lhs_byte_offset != end_byte_offset) {
#if zig_little_endian
        res_byte_offset -= UINT16_C(1);
        lhs_byte_offset -= UINT16_C(1);
#endif

        {
            uint8_t lhs_byte = lhs_bytes[lhs_byte_offset];

            res_bytes[res_byte_offset] = zig_u8_intCast_u16(zig_shr_u16(zig_or_u16(
                zig_shl_u16(zig_u16_intCast_u8(lhs_prev_byte), UINT8_C(8)),
                zig_u16_intCast_u8(lhs_byte)
            ), byte_shift));
            lhs_prev_byte = lhs_byte;
        }

#if zig_big_endian
        res_byte_offset += UINT16_C(1);
        lhs_byte_offset += UINT16_C(1);
#endif
    }

    {
#if zig_little_endian
        res_byte_offset -= UINT16_C(1);
#endif

        res_bytes[res_byte_offset] = zig_u8_intCast_u16(zig_shr_u16(
            zig_shl_u16(zig_u16_intCast_u8(lhs_prev_byte), UINT8_C(8)),
            byte_shift
        ));

#if zig_big_endian
        res_byte_offset += UINT16_C(1);
#endif
    }

#if zig_little_endian
    memset(&res_bytes[0], zig_minInt_u8, res_byte_offset);
#else
    memset(&res_bytes[res_byte_offset], zig_minInt_u8, size - res_byte_offset);
#endif

    return overflow;
}

static inline void zig_shl_big(void *res, const void *lhs, uint16_t rhs, bool is_signed, uint16_t bits) {
    if (zig_shlo_big(res, lhs, rhs, is_signed, bits)) zig_trap(); // panic: left shift overflowed bits
}

static inline void zig_shlw_big(void *res, const void *lhs, uint16_t rhs, bool is_signed, uint16_t bits) {
    (void)zig_shlo_big(res, lhs, rhs, is_signed, bits);
}

#define zig_big_shls_builtin(w) \
    static inline uint##w##_t zig_shls_u##w##_big(uint##w##_t lhs, const void *rhs, \
            uint8_t lhs_bits, bool rhs_is_signed, uint16_t rhs_bits) { \
        uint##w##_t res; \
        const uint8_t *rhs_bytes = rhs; \
        if (zig_cmp_big_u8(rhs, lhs_bits, rhs_is_signed, rhs_bits) < INT32_C(0) && \
            !zig_shlo_u##w(&res, lhs, rhs_bytes[0], lhs_bits)) return res; \
        return lhs == INT##w##_C(0) ? zig_minInt_u(w, lhs_bits) : zig_maxInt_u(w, lhs_bits); \
    } \
\
    static inline int##w##_t zig_shls_i##w##_big(int##w##_t lhs, const void *rhs, \
            uint8_t lhs_bits, bool rhs_is_signed, uint16_t rhs_bits) { \
        int##w##_t res; \
        const uint8_t *rhs_bytes = rhs; \
        if (zig_cmp_big_u8(rhs, lhs_bits, rhs_is_signed, rhs_bits) < INT32_C(0) && \
            !zig_shlo_i##w(&res, lhs, rhs_bytes[0], lhs_bits)) return res; \
        return lhs == INT##w##_C(0) ? INT##w##_C(0) : \
            lhs < INT##w##_C(0) ? zig_minInt_i(w, lhs_bits) : zig_maxInt_i(w, lhs_bits); \
    } \
\
    static inline void zig_shls_big_u##w(void *res, const void *lhs, uint##w##_t rhs, bool is_signed, uint16_t bits) { \
        const uint8_t *lhs_bytes = lhs; \
        if (rhs < bits && !zig_shlo_big(res, lhs, zig_u16_intCast_u##w(rhs), is_signed, bits)) return; \
        switch (zig_cmp_big_u8(lhs, UINT8_C(0), is_signed, bits)) { \
            case -INT32_C(1): return zig_minInt_big(res, is_signed, bits); \
            case  INT32_C(0): return zig_minInt_big(res,     false, bits); \
            case  INT32_C(1): return zig_maxInt_big(res, is_signed, bits); \
            default: zig_unreachable(); \
        } \
    }
zig_big_shls_builtin(8)
zig_big_shls_builtin(16)
zig_big_shls_builtin(32)
zig_big_shls_builtin(64)

static inline void zig_byteSwap_big(void *res, const void *arg, bool is_signed, uint16_t bits) {
    uint8_t *res_bytes = res;
    const uint8_t *arg_bytes = arg;
    uint16_t res_byte_offset = UINT16_C(0);
    uint16_t arg_byte_offset = bits / CHAR_BIT;
    uint16_t end_byte_offset = UINT16_C(1);
    uint16_t size = zig_int_bytes(bits);

#if zig_big_endian
    res_byte_offset = size - res_byte_offset;
    arg_byte_offset = size - arg_byte_offset;
    end_byte_offset = size - end_byte_offset;
#endif

    while (arg_byte_offset != end_byte_offset) {
#if zig_little_endian
        arg_byte_offset -= UINT16_C(1);
#else
        res_byte_offset -= UINT16_C(1);
#endif

        res_bytes[res_byte_offset] = arg_bytes[arg_byte_offset];

#if zig_little_endian
        res_byte_offset += UINT16_C(1);
#else
        arg_byte_offset += UINT16_C(1);
#endif
    }

    {
#if zig_little_endian
        arg_byte_offset -= UINT16_C(1);
#else
        res_byte_offset -= UINT16_C(1);
#endif

        {
            uint8_t byte = arg_bytes[arg_byte_offset];
            uint8_t fill = is_signed
                ? zig_u8_bitCast_i8(zig_shr_i8(zig_i8_bitCast_u8(byte, UINT8_C(8)), UINT8_C(7)), UINT8_C(8))
                : UINT8_C(0);

            res_bytes[res_byte_offset] = byte;

#if zig_little_endian
            res_byte_offset += UINT16_C(1);
            memset(&res_bytes[res_byte_offset], fill, size - res_byte_offset);
#else
            memset(&res_bytes[0], fill, res_byte_offset);
#endif
        }
    }
}

static inline void zig_bitReverse_big(void *res, const void *arg, bool is_signed, uint16_t bits) {
    uint8_t *res_bytes = res;
    const uint8_t *arg_bytes = arg;
    uint16_t size = zig_int_bytes(bits);
    uint16_t res_byte_offset = UINT16_C(0);
    uint16_t arg_byte_offset = zig_shr_u16(bits - UINT16_C(1), UINT8_C(3)) + UINT16_C(1);
    uint16_t end_byte_offset = UINT16_C(0);
    uint8_t arg_prev_byte;
    uint8_t byte_shift = zig_u8_intCast_u16(zig_subw_u16(UINT16_C(0), bits, UINT8_C(3)));

#if zig_big_endian
    res_byte_offset = size - res_byte_offset;
    arg_byte_offset = size - arg_byte_offset;
    end_byte_offset = size - end_byte_offset;
#endif

    {
#if zig_little_endian
        arg_byte_offset -= UINT16_C(1);
#endif

        arg_prev_byte = zig_bitReverse_u8(arg_bytes[arg_byte_offset], UINT8_C(8));

#if zig_big_endian
        arg_byte_offset += UINT16_C(1);
#endif
    }

    while (arg_byte_offset != end_byte_offset) {
#if zig_big_endian
        res_byte_offset -= UINT16_C(1);
#else
        arg_byte_offset -= UINT16_C(1);
#endif

        {
            uint8_t arg_byte = zig_bitReverse_u8(arg_bytes[arg_byte_offset], UINT8_C(8));

            res_bytes[res_byte_offset] = zig_u8_intCast_u16(zig_shr_u16(zig_or_u16(
                zig_shl_u16(zig_u16_intCast_u8(arg_byte), UINT8_C(8)),
                zig_u16_intCast_u8(arg_prev_byte)
            ), byte_shift));
            arg_prev_byte = arg_byte;
        }

#if zig_little_endian
        res_byte_offset += UINT16_C(1);
#else
        arg_byte_offset += UINT16_C(1);
#endif
    }

    {
        uint8_t arg_sign_fill = UINT8_C(0);

#if zig_big_endian
        res_byte_offset -= UINT16_C(1);
#endif

        if (is_signed) {
            int8_t signed_byte = zig_i8_bitCast_u8(arg_prev_byte, UINT8_C(8));

            res_bytes[res_byte_offset] = zig_shr_i8(signed_byte, byte_shift);
            arg_sign_fill = zig_u8_bitCast_i8(zig_shr_i8(signed_byte, UINT8_C(7)), UINT8_C(8));
        } else {
            res_bytes[res_byte_offset] = zig_shr_u8(arg_prev_byte, byte_shift);
        }

#if zig_little_endian
        res_byte_offset += UINT16_C(1);
        memset(&res_bytes[res_byte_offset], arg_sign_fill, size - res_byte_offset);
#else
        memset(&res_bytes[0], arg_sign_fill, res_byte_offset);
#endif
    }
}

static inline uint16_t zig_popCount_big(const void *arg, bool is_signed, uint16_t bits) {
    const uint8_t *arg_bytes = arg;
    uint16_t byte_offset = 0;
    uint16_t remaining_bytes = zig_shr_u16(bits - UINT16_C(1), UINT8_C(3)) + UINT16_C(1);
    uint8_t top_bits = zig_u8_intCast_u16(remaining_bytes * CHAR_BIT - bits);
    uint16_t total_pc = 0;
    (void)is_signed;

#if zig_big_endian
    byte_offset = zig_int_bytes(bits);
#endif

    while (remaining_bytes >= 128 / CHAR_BIT) {
        uint8_t limb_bits = 128 - (remaining_bytes == 128 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 128 / CHAR_BIT;
#endif

        {
            zig_u128 arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            total_pc += zig_popCount_u128(zig_u128_truncate_u128(arg_limb, limb_bits), limb_bits);
        }

        remaining_bytes -= 128 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 128 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 64 / CHAR_BIT) {
        uint8_t limb_bits = 64 - (remaining_bytes == 64 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 64 / CHAR_BIT;
#endif

        {
            uint64_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            total_pc += zig_popCount_u64(zig_u64_truncate_u64(arg_limb, limb_bits), limb_bits);
        }

        remaining_bytes -= 64 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 64 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 32 / CHAR_BIT) {
        uint8_t limb_bits = 32 - (remaining_bytes == 32 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 32 / CHAR_BIT;
#endif

        {
            uint32_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            total_pc += zig_popCount_u32(zig_u32_truncate_u32(arg_limb, limb_bits), limb_bits);
        }

        remaining_bytes -= 32 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 32 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 16 / CHAR_BIT) {
        uint8_t limb_bits = 16 - (remaining_bytes == 16 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 16 / CHAR_BIT;
#endif

        {
            uint16_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            total_pc += zig_popCount_u16(zig_u16_truncate_u16(arg_limb, limb_bits), limb_bits);
        }

        remaining_bytes -= 16 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 16 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 8 / CHAR_BIT) {
        uint8_t limb_bits = 8 - (remaining_bytes == 8 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 8 / CHAR_BIT;
#endif

        {
            uint8_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            total_pc += zig_popCount_u8(zig_u8_truncate_u8(arg_limb, limb_bits), limb_bits);
        }

        remaining_bytes -= 8 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 8 / CHAR_BIT;
#endif
    }

    return total_pc;
}

static inline uint16_t zig_ctz_big(const void *arg, bool is_signed, uint16_t bits) {
    const uint8_t *arg_bytes = arg;
    uint16_t byte_offset = UINT16_C(0);
    uint16_t remaining_bytes = zig_shr_u16(bits - UINT16_C(1), UINT8_C(3)) + UINT16_C(1);
    uint8_t top_bits = zig_u8_intCast_u16(remaining_bytes * CHAR_BIT - bits);
    uint16_t total_tz = UINT16_C(0);
    uint16_t limb_tz;
    (void)is_signed;

#if zig_big_endian
    byte_offset = zig_int_bytes(bits);
#endif

    while (remaining_bytes >= 128 / CHAR_BIT) {
        uint8_t limb_bits = 128 - (remaining_bytes == 128 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 128 / CHAR_BIT;
#endif

        {
            zig_u128 arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            limb_tz = zig_ctz_u128(zig_u128_truncate_u128(arg_limb, limb_bits), limb_bits);
        }

        total_tz += limb_tz;
        if (limb_tz < limb_bits) return total_tz;
        remaining_bytes -= 128 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 128 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 64 / CHAR_BIT) {
        uint8_t limb_bits = 64 - (remaining_bytes == 64 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 64 / CHAR_BIT;
#endif

        {
            uint64_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            limb_tz = zig_ctz_u64(zig_u64_truncate_u64(arg_limb, limb_bits), limb_bits);
        }

        total_tz += limb_tz;
        if (limb_tz < limb_bits) return total_tz;
        remaining_bytes -= 64 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 64 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 32 / CHAR_BIT) {
        uint8_t limb_bits = 32 - (remaining_bytes == 32 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 32 / CHAR_BIT;
#endif

        {
            uint32_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            limb_tz = zig_ctz_u32(zig_u32_truncate_u32(arg_limb, limb_bits), limb_bits);
        }

        total_tz += limb_tz;
        if (limb_tz < limb_bits) return total_tz;
        remaining_bytes -= 32 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 32 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 16 / CHAR_BIT) {
        uint8_t limb_bits = 16 - (remaining_bytes == 16 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 16 / CHAR_BIT;
#endif

        {
            uint16_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            limb_tz = zig_ctz_u16(zig_u16_truncate_u16(arg_limb, limb_bits), limb_bits);
        }

        total_tz += limb_tz;
        if (limb_tz < limb_bits) return total_tz;
        remaining_bytes -= 16 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 16 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 8 / CHAR_BIT) {
        uint8_t limb_bits = 8 - (remaining_bytes == 8 / CHAR_BIT ? top_bits : 0);

#if zig_big_endian
        byte_offset -= 8 / CHAR_BIT;
#endif

        {
            uint8_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            limb_tz = zig_ctz_u8(zig_u8_truncate_u8(arg_limb, limb_bits), limb_bits);
        }

        total_tz += limb_tz;
        if (limb_tz < limb_bits) return total_tz;
        remaining_bytes -= 8 / CHAR_BIT;

#if zig_little_endian
        byte_offset += 8 / CHAR_BIT;
#endif
    }

    return total_tz;
}

static inline uint16_t zig_clz_big(const void *arg, bool is_signed, uint16_t bits) {
    const uint8_t *arg_bytes = arg;
    uint16_t byte_offset = zig_shr_u16(bits - UINT16_C(1), UINT8_C(3)) + UINT16_C(1);
    uint16_t remaining_bytes = byte_offset;
    uint8_t top_bits = zig_u8_intCast_u16(remaining_bytes * CHAR_BIT - bits);
    bool sign_limb = true;
    uint16_t total_lz = UINT16_C(0);
    uint16_t limb_lz;
    (void)is_signed;

#if zig_big_endian
    byte_offset = zig_int_bytes(bits) - remaining_bytes;
#endif

    while (remaining_bytes >= 128 / CHAR_BIT) {
        uint8_t limb_bits = UINT8_C(128) - (sign_limb ? top_bits : UINT8_C(0));

#if zig_little_endian
        byte_offset -= 128 / CHAR_BIT;
#endif

        {
            zig_u128 arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            limb_lz = zig_clz_u128(zig_u128_truncate_u128(arg_limb, limb_bits), limb_bits);
        }

        total_lz += limb_lz;
        if (limb_lz < limb_bits) return total_lz;
        sign_limb = false;
        remaining_bytes -= 128 / CHAR_BIT;

#if zig_big_endian
        byte_offset += 128 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 64 / CHAR_BIT) {
        uint8_t limb_bits = UINT8_C(64) - (sign_limb ? top_bits : UINT8_C(0));

#if zig_little_endian
        byte_offset -= 64 / CHAR_BIT;
#endif

        {
            uint64_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            limb_lz = zig_clz_u64(zig_u64_truncate_u64(arg_limb, limb_bits), limb_bits);
        }

        total_lz += limb_lz;
        if (limb_lz < limb_bits) return total_lz;
        sign_limb = false;
        remaining_bytes -= 64 / CHAR_BIT;

#if zig_big_endian
        byte_offset += 64 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 32 / CHAR_BIT) {
        uint8_t limb_bits = UINT8_C(32) - (sign_limb ? top_bits : UINT8_C(0));

#if zig_little_endian
        byte_offset -= 32 / CHAR_BIT;
#endif

        {
            uint32_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            limb_lz = zig_clz_u32(zig_u32_truncate_u32(arg_limb, limb_bits), limb_bits);
        }

        total_lz += limb_lz;
        if (limb_lz < limb_bits) return total_lz;
        sign_limb = false;
        remaining_bytes -= 32 / CHAR_BIT;

#if zig_big_endian
        byte_offset += 32 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 16 / CHAR_BIT) {
        uint8_t limb_bits = UINT8_C(16) - (sign_limb ? top_bits : UINT8_C(0));

#if zig_little_endian
        byte_offset -= 16 / CHAR_BIT;
#endif

        {
            uint16_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            limb_lz = zig_clz_u16(zig_u16_truncate_u16(arg_limb, limb_bits), limb_bits);
        }

        total_lz += limb_lz;
        if (limb_lz < limb_bits) return total_lz;
        sign_limb = false;
        remaining_bytes -= 16 / CHAR_BIT;

#if zig_big_endian
        byte_offset += 16 / CHAR_BIT;
#endif
    }

    while (remaining_bytes >= 8 / CHAR_BIT) {
        uint8_t limb_bits = UINT8_C(8) - (sign_limb ? top_bits : UINT8_C(0));

#if zig_little_endian
        byte_offset -= 8 / CHAR_BIT;
#endif

        {
            uint8_t arg_limb;

            memcpy(&arg_limb, &arg_bytes[byte_offset], sizeof(arg_limb));
            limb_lz = zig_clz_u8(zig_u8_truncate_u8(arg_limb, limb_bits), limb_bits);
        }

        total_lz += limb_lz;
        if (limb_lz < limb_bits) return total_lz;
        sign_limb = false;
        remaining_bytes -= 8 / CHAR_BIT;

#if zig_big_endian
        byte_offset += 8 / CHAR_BIT;
#endif
    }

    return total_lz;
}

/* ========================= Floating Point Support ========================= */

#ifndef __STDC_WANT_IEC_60559_TYPES_EXT__
#define __STDC_WANT_IEC_60559_TYPES_EXT__
#endif

#include <float.h>

#if defined(zig_msvc)
float __cdecl nanf(char const* input);
double __cdecl nan(char const* input);
long double __cdecl nanl(char const* input);

#define zig_msvc_flt_inf ((double)(1e+300 * 1e+300))
#define zig_msvc_flt_inff ((float)(1e+300 * 1e+300))
#define zig_msvc_flt_infl ((long double)(1e+300 * 1e+300))
#define zig_msvc_flt_nan ((double)(zig_msvc_flt_inf * 0.f))
#define zig_msvc_flt_nanf ((float)(zig_msvc_flt_inf * 0.f))
#define zig_msvc_flt_nanl ((long double)(zig_msvc_flt_inf * 0.f))
#define __builtin_nan(str) nan(str)
#define __builtin_nanf(str) nanf(str)
#define __builtin_nanl(str) nanl(str)
#define __builtin_inf() zig_msvc_flt_inf
#define __builtin_inff() zig_msvc_flt_inff
#define __builtin_infl() zig_msvc_flt_infl
#endif

#if (zig_has_builtin(nan) && zig_has_builtin(nans) && zig_has_builtin(inf)) || defined(zig_gcc)
#define  zig_make_special_f16(sign, name, arg, repr) sign zig_make_f16 (__builtin_##name, )(arg)
#define  zig_make_special_f32(sign, name, arg, repr) sign zig_make_f32 (__builtin_##name, )(arg)
#define  zig_make_special_f64(sign, name, arg, repr) sign zig_make_f64 (__builtin_##name, )(arg)
#define  zig_make_special_f80(sign, name, arg, repr) sign zig_make_f80 (__builtin_##name, )(arg)
#define zig_make_special_f128(sign, name, arg, repr) sign zig_make_f128(__builtin_##name, )(arg)
#else
#define  zig_make_special_f16(sign, name, arg, repr)  zig_f16_bitCast_u16 (repr)
#define  zig_make_special_f32(sign, name, arg, repr)  zig_f32_bitCast_u32 (repr)
#define  zig_make_special_f64(sign, name, arg, repr)  zig_f64_bitCast_u64 (repr)
#define  zig_make_special_f80(sign, name, arg, repr)  zig_f80_bitCast_u128(repr)
#define zig_make_special_f128(sign, name, arg, repr) zig_f128_bitCast_u128(repr)
#endif

#define zig_has_f16 1
#define zig_libc_name_f16(name) __##name##h
#define zig_init_special_f16(sign, name, arg, repr) zig_make_special_f16(sign, name, arg, repr)
#if !defined(ZIG_TARGET_SOFT_COMPILER_RT_F16_ABI) && FLT_MANT_DIG == 11
typedef float zig_f16;
#define zig_make_f16(fp, repr) fp##f
#elif !defined(ZIG_TARGET_SOFT_COMPILER_RT_F16_ABI) && DBL_MANT_DIG == 11
typedef double zig_f16;
#define zig_make_f16(fp, repr) fp
#elif !defined(ZIG_TARGET_SOFT_COMPILER_RT_F16_ABI) && LDBL_MANT_DIG == 11
typedef long double zig_f16;
#define zig_make_f16(fp, repr) fp##l
#elif !defined(ZIG_TARGET_SOFT_COMPILER_RT_F16_ABI) && FLT16_MANT_DIG == 11 && (zig_has_builtin(inff16) || defined(zig_gcc))
typedef _Float16 zig_f16;
#define zig_make_f16(fp, repr) fp##f16
#elif !defined(ZIG_TARGET_SOFT_COMPILER_RT_F16_ABI) && defined(__SIZEOF_FP16__)
typedef __fp16 zig_f16;
#define zig_make_f16(fp, repr) fp##f16
#else
#undef zig_has_f16
#define zig_has_f16 0
#define zig_repr_f16 u16
typedef uint16_t zig_f16;
#define zig_make_f16(fp, repr) repr
#undef zig_make_special_f16
#define zig_make_special_f16(sign, name, arg, repr) repr
#undef zig_init_special_f16
#define zig_init_special_f16(sign, name, arg, repr) repr
#endif

#define zig_has_f32 1
#define zig_libc_name_f32(name) name##f
#if defined(zig_msvc)
#define zig_init_special_f32(sign, name, arg, repr) sign zig_make_f32(zig_msvc_flt_##name, )
#else
#define zig_init_special_f32(sign, name, arg, repr) zig_make_special_f32(sign, name, arg, repr)
#endif
#if !defined(ZIG_TARGET_SOFT_COMPILER_RT_F32_ABI) && FLT_MANT_DIG == 24
typedef float zig_f32;
#define zig_make_f32(fp, repr) fp##f
#elif !defined(ZIG_TARGET_SOFT_COMPILER_RT_F32_ABI) && DBL_MANT_DIG == 24
typedef double zig_f32;
#define zig_make_f32(fp, repr) fp
#elif !defined(ZIG_TARGET_SOFT_COMPILER_RT_F32_ABI) && LDBL_MANT_DIG == 24
typedef long double zig_f32;
#define zig_make_f32(fp, repr) fp##l
#elif !defined(ZIG_TARGET_SOFT_COMPILER_RT_F32_ABI) && FLT32_MANT_DIG == 24
typedef _Float32 zig_f32;
#define zig_make_f32(fp, repr) fp##f32
#else
#undef zig_has_f32
#define zig_has_f32 0
#define zig_repr_f32 u32
typedef uint32_t zig_f32;
#define zig_make_f32(fp, repr) repr
#undef zig_make_special_f32
#define zig_make_special_f32(sign, name, arg, repr) repr
#undef zig_init_special_f32
#define zig_init_special_f32(sign, name, arg, repr) repr
#endif

#define zig_has_f64 1
#define zig_libc_name_f64(name) name

#if defined(zig_msvc)
#define zig_init_special_f64(sign, name, arg, repr) sign zig_make_f64(zig_msvc_flt_##name, )
#else
#define zig_init_special_f64(sign, name, arg, repr) zig_make_special_f64(sign, name, arg, repr)
#endif
#if !defined(ZIG_TARGET_SOFT_COMPILER_RT_F64_ABI) && FLT_MANT_DIG == 53
typedef float zig_f64;
#define zig_make_f64(fp, repr) fp##f
#elif !defined(ZIG_TARGET_SOFT_COMPILER_RT_F64_ABI) && DBL_MANT_DIG == 53
typedef double zig_f64;
#define zig_make_f64(fp, repr) fp
#elif !defined(ZIG_TARGET_SOFT_COMPILER_RT_F64_ABI) && LDBL_MANT_DIG == 53
typedef long double zig_f64;
#define zig_make_f64(fp, repr) fp##l
#elif !defined(ZIG_TARGET_SOFT_COMPILER_RT_F64_ABI) && FLT64_MANT_DIG == 53
typedef _Float64 zig_f64;
#define zig_make_f64(fp, repr) fp##f64
#elif !defined(ZIG_TARGET_SOFT_COMPILER_RT_F64_ABI) && FLT32X_MANT_DIG == 53
typedef _Float32x zig_f64;
#define zig_make_f64(fp, repr) fp##f32x
#else
#undef zig_has_f64
#define zig_has_f64 0
#define zig_repr_f64 u64
typedef uint64_t zig_f64;
#define zig_make_f64(fp, repr) repr
#undef zig_make_special_f64
#define zig_make_special_f64(sign, name, arg, repr) repr
#undef zig_init_special_f64
#define zig_init_special_f64(sign, name, arg, repr) repr
#endif

#define zig_has_f80 1
#define zig_libc_name_f80(name) __##name##x
#define zig_init_special_f80(sign, name, arg, repr) zig_make_special_f80(sign, name, arg, repr)
#ifdef ZIG_TARGET_SOFT_COMPILER_RT_F80_ABI
#undef zig_has_f80
typedef struct { uint64_t mantissa; uint16_t exponent; } zig_f80;
#define zig_init_repr_f80(mantissa, exponent) { .mant##issa = mantissa, .expo##nent = exponent }
#define zig_make_repr_f80(mantissa, exponent) (zig_f80)zig_init_repr_f80(mantissa, exponent)
#define zig_mantissa_repr_f80(arg) (arg).mantissa
#define zig_exponent_repr_f80(arg) (arg).exponent
#elif FLT_MANT_DIG == 64
typedef float zig_f80;
#define zig_make_f80(fp, repr) fp##f
#elif DBL_MANT_DIG == 64
typedef double zig_f80;
#define zig_make_f80(fp, repr) fp
#elif LDBL_MANT_DIG == 64
typedef long double zig_f80;
#define zig_make_f80(fp, repr) fp##l
#elif FLT80_MANT_DIG == 64
typedef _Float80 zig_f80;
#define zig_make_f80(fp, repr) fp##f80
#elif FLT64X_MANT_DIG == 64
typedef _Float64x zig_f80;
#define zig_make_f80(fp, repr) fp##f64x
#elif defined(__SIZEOF_FLOAT80__)
typedef __float80 zig_f80;
#define zig_make_f80(fp, repr) fp##l
#else
#undef zig_has_f80
typedef zig_u128 zig_f80;
#define zig_init_repr_f80(mantissa, exponent) zig_init_u128(exponent, mantissa)
#define zig_make_repr_f80(mantissa, exponent) zig_make_u128(exponent, mantissa)
#define zig_mantissa_repr_f80(arg) zig_lo_u128(arg)
#define zig_exponent_repr_f80(arg) (uint16_t)zig_hi_u128(arg)
#endif
#ifndef zig_has_f80
#define zig_has_f80 0
#define zig_make_f80(fp, repr) repr
#ifndef zig_make_repr_f80
#define zig_make_repr_f80(mantissa, exponent) (zig_f80)zig_init_repr_f80(mantissa, exponent)
#endif
#undef zig_make_special_f80
#define zig_make_special_f80(sign, name, arg, repr) repr
#undef zig_init_special_f80
#define zig_init_special_f80(sign, name, arg, repr) repr
#endif

#define zig_has_f128 1
#define zig_libc_name_f128(name) name##f128
#define zig_init_special_f128(sign, name, arg, repr) zig_make_special_f128(sign, name, arg, repr)
#ifdef ZIG_TARGET_SOFT_COMPILER_RT_F128_ABI
#undef zig_has_f128
#if zig_little_endian
typedef struct { uint64_t lo, hi; } zig_f128;
#else
typedef struct { uint64_t hi, lo; } zig_f128;
#endif
#define zig_init_repr_f128(hi, lo) { .h##i = hi, .l##o = lo }
#define zig_lo_repr_f128(arg) (arg).lo
#define zig_hi_repr_f128(arg) (arg).hi
#elif FLT_MANT_DIG == 113
typedef float zig_f128;
#define zig_make_f128(fp, repr) fp##f
#elif DBL_MANT_DIG == 113
typedef double zig_f128;
#define zig_make_f128(fp, repr) fp
#elif LDBL_MANT_DIG == 113
typedef long double zig_f128;
#define zig_make_f128(fp, repr) fp##l
#elif FLT128_MANT_DIG == 113
typedef _Float128 zig_f128;
#define zig_make_f128(fp, repr) fp##f128
#elif FLT64X_MANT_DIG == 113
typedef _Float64x zig_f128;
#define zig_make_f128(fp, repr) fp##f64x
#elif defined(__SIZEOF_FLOAT128__)
typedef __float128 zig_f128;
#define zig_make_f128(fp, repr) fp##q
#undef zig_make_special_f128
#define zig_make_special_f128(sign, name, arg, repr) sign __builtin_##name##f128(arg)
#else
#undef zig_has_f128
#if defined(zig_x86_64) && defined(ZIG_TARGET_ABI_MSVC)
#if defined(zig_msvc) && !defined(__clang__)
#include <emmintrin.h>
typedef __m128i zig_f128;
#define zig_init_repr_f128(hi, lo) { .m128i_u64 = { lo, hi } }
#define zig_lo_repr_f128(arg) (arg).m128i_u64[0]
#define zig_hi_repr_f128(arg) (arg).m128i_u64[1]
#else
typedef __attribute__((__vector_size__(2 * sizeof(uint64_t)))) uint64_t zig_f128;
#define zig_init_repr_f128(hi, lo) { lo, hi }
#define zig_lo_repr_f128(arg) (arg)[0]
#define zig_hi_repr_f128(arg) (arg)[1]
#endif
#else
typedef zig_u128 zig_f128;
#define zig_init_repr_f128(hi, lo) zig_init_u128(hi, lo)
#define zig_make_repr_f128(hi, lo) zig_make_u128(hi, lo)
#define zig_lo_repr_f128(arg) zig_lo_u128(arg)
#define zig_hi_repr_f128(arg) zig_hi_u128(arg)
#endif
#endif
#ifndef zig_has_f128
#define zig_has_f128 0
#define zig_make_f128(fp, repr) repr
#ifndef zig_make_repr_f128
#define zig_make_repr_f128(hi, lo) (zig_f128)zig_init_repr_f128(hi, lo)
#endif
#undef zig_make_special_f128
#define zig_make_special_f128(sign, name, arg, repr) repr
#undef zig_init_special_f128
#define zig_init_special_f128(sign, name, arg, repr) repr
#endif

#if !defined(zig_msvc) && defined(ZIG_TARGET_ABI_MSVC)
/* Emulate msvc abi on a gnu compiler */
typedef zig_f64 zig_c_longdouble;
#elif defined(zig_msvc) && !defined(ZIG_TARGET_ABI_MSVC)
/* Emulate gnu abi on an msvc compiler */
typedef zig_f128 zig_c_longdouble;
#else
/* Target and compiler abi match */
typedef long double zig_c_longdouble;
#endif

#if __AVR__
typedef signed char zig_FloatCompareResult;
#elif defined(zig_aarch64)
typedef signed int zig_FloatCompareResult;
#elif __SIZEOF_LONG__ >= __SIZEOF_POINTER__
typedef signed long zig_FloatCompareResult;
#else
typedef signed long long zig_FloatCompareResult;
#endif

#define zig_bitCast_float(w, iw, UnsignedReprType, SignedReprType) \
    static inline zig_f##w zig_f##w##_bitCast_u##iw(UnsignedReprType arg) { \
        zig_f##w res; \
        memcpy(&res, &arg, sizeof(zig_f##w)); \
        return res; \
    } \
    static inline zig_f##w zig_f##w##_bitCast_i##iw(SignedReprType arg) { \
        zig_f##w res; \
        memcpy(&res, &arg, sizeof(zig_f##w)); \
        return res; \
    } \
    static inline UnsignedReprType zig_u##iw##_bitCast_f##w(zig_f##w arg) { \
        UnsignedReprType res; \
        memcpy(&res, &arg, sizeof(zig_f##w)); \
        return zig_u##iw##_truncate_u##iw(res, w); \
    } \
    static inline SignedReprType zig_i##iw##_bitCast_f##w(zig_f##w arg) { \
        SignedReprType res; \
        memcpy(&res, &arg, sizeof(zig_f##w)); \
        return zig_i##iw##_truncate_i##iw(res, w); \
    }
zig_bitCast_float(16, 16, uint16_t, int16_t)
zig_bitCast_float(32, 32, uint32_t, int32_t)
zig_bitCast_float(64, 64, uint64_t, int64_t)
#if zig_has_f80
zig_bitCast_float(80, 128, zig_u128, zig_i128)
#else
static inline zig_f80 zig_f80_bitCast_u128(zig_u128 arg) {
    return zig_make_repr_f80(zig_lo_u128(arg), (uint16_t)zig_hi_u128(arg));
}
static inline zig_f80 zig_f80_bitCast_i128(zig_i128 arg) {
    return zig_make_repr_f80(zig_lo_i128(arg), (uint16_t)zig_hi_i128(arg));
}
static inline zig_u128 zig_u128_bitCast_f80(zig_f80 arg) {
    return zig_make_u128(zig_exponent_repr_f80(arg), zig_mantissa_repr_f80(arg));
}
static inline zig_i128 zig_i128_bitCast_f80(zig_f80 arg) {
    return zig_make_i128((int16_t)zig_exponent_repr_f80(arg), zig_mantissa_repr_f80(arg));
}
#endif
static inline zig_f80 zig_f80_bitCast_big(const void *arg) {
    return zig_f80_bitCast_u128(zig_u128_truncate_big(arg, UINT8_C(80), false, UINT16_C(80)));
}
static inline void zig_big_bitCast_f80(void *res, zig_f80 arg, bool res_is_signed, uint16_t res_bits) {
    if (res_is_signed) {
        zig_big_truncate_i128(res, zig_i128_bitCast_f80(arg), res_is_signed, res_bits);
    } else {
        zig_big_truncate_u128(res, zig_u128_bitCast_f80(arg), res_is_signed, res_bits);
    }
}
#if zig_has_f128
zig_bitCast_float(128, 128, zig_u128, zig_i128)
#else
static inline zig_f128 zig_f128_bitCast_u128(zig_u128 arg) {
    return zig_make_repr_f128(zig_hi_u128(arg), zig_lo_u128(arg));
}
static inline zig_f128 zig_f128_bitCast_i128(zig_i128 arg) {
    return zig_make_repr_f128((uint64_t)zig_hi_i128(arg), zig_lo_i128(arg));
}
static inline zig_u128 zig_u128_bitCast_f128(zig_f128 arg) {
    return zig_make_u128(zig_hi_repr_f128(arg), zig_lo_repr_f128(arg));
}
static inline zig_i128 zig_i128_bitCast_f128(zig_f128 arg) {
    return zig_make_i128((int64_t)zig_hi_repr_f128(arg), zig_lo_repr_f128(arg));
}
#endif

#define zig_convert_float_00(ResType, operation, ArgType, version) \
    zig_extern ResType zig_expand_concat(zig_expand_concat(zig_expand_concat(__##operation, \
        zig_compiler_rt_abbrev_##ArgType), zig_compiler_rt_abbrev_##ResType), version)(ArgType arg); \
    return zig_expand_concat(zig_expand_concat(zig_expand_concat(__##operation, \
        zig_compiler_rt_abbrev_##ArgType), zig_compiler_rt_abbrev_##ResType), version)(arg)
#define zig_convert_float_01(ResType, operation, ArgType, version) \
    zig_convert_float_00(ResType, operation, ArgType, version)
#define zig_convert_float_10(ResType, operation, ArgType, version) \
    zig_convert_float_00(ResType, operation, ArgType, version)
#define zig_convert_float_11(ResType, operation, ArgType, version) \
    return (ResType)arg
#define zig_convert_float(res_when, ResType, operation, arg_when, ArgType, version) \
    static inline ResType zig_expand_concat(zig_expand_concat(zig_##operation, \
        zig_compiler_rt_abbrev_##ArgType), zig_compiler_rt_abbrev_##ResType)(ArgType arg) { \
        zig_expand_concat(zig_expand_concat(zig_convert_float_, zig_has_##res_when), \
            zig_has_##arg_when)(ResType, operation, ArgType, version); \
    }

#define zig_convert_floats(SmallType, BigType) \
    zig_convert_float(SmallType, zig_##SmallType, trunc, BigType, zig_##BigType, 2) \
    zig_convert_float(BigType, zig_##BigType, extend, SmallType, zig_##SmallType, 2)
zig_convert_floats(f16, f32)
zig_convert_floats(f16, f64)
zig_convert_floats(f16, f80)
zig_convert_floats(f16, f128)
zig_convert_floats(f32, f64)
zig_convert_floats(f32, f80)
zig_convert_floats(f32, f128)
zig_convert_floats(f64, f80)
zig_convert_floats(f64, f128)
zig_convert_floats(f80, f128)

#define zig_float_negate_builtin_0(w, sb) \
    zig_expand_concat(zig_xor_, zig_repr_f##w)(arg, zig_make_f##w(-0x0.0p0, sb))
#define zig_float_negate_builtin_1(w, sb) -arg
#define zig_float_negate_builtin(w, sb) \
    static inline zig_f##w zig_neg_f##w(zig_f##w arg) { \
        return zig_expand_concat(zig_float_negate_builtin_, zig_has_f##w)(w, sb); \
    }
zig_float_negate_builtin(16, UINT16_C(1) << 15)
zig_float_negate_builtin(32, UINT32_C(1) << 31)
zig_float_negate_builtin(64, UINT64_C(1) << 63)

#undef zig_float_negate_builtin_0
#define zig_float_negate_builtin_0(w, sb) \
    zig_make_repr_f##w(zig_mantissa_repr_f##w(arg), zig_xor_u16(zig_exponent_repr_f##w(arg), sb))
zig_float_negate_builtin(80, UINT16_C(1) << 15)

#undef zig_float_negate_builtin_0
#define zig_float_negate_builtin_0(w, sb) \
    zig_make_repr_f##w(zig_xor_u64(zig_hi_repr_f##w(arg), sb), zig_lo_repr_f##w(arg))
zig_float_negate_builtin(128, UINT64_C(1) << 63)

#define zig_float_less_builtin_0(Type, operation) \
    zig_extern zig_FloatCompareResult zig_expand_concat(zig_expand_concat(__##operation, \
        zig_compiler_rt_abbrev_zig_##Type), 2)(zig_##Type, zig_##Type); \
    static inline int32_t zig_##operation##_##Type(zig_##Type lhs, zig_##Type rhs) { \
        return (int32_t)zig_expand_concat(zig_expand_concat(__##operation, zig_compiler_rt_abbrev_zig_##Type), 2)(lhs, rhs); \
    }
#define zig_float_less_builtin_1(Type, operation) \
    static inline int32_t zig_##operation##_##Type(zig_##Type lhs, zig_##Type rhs) { \
        return (!(lhs <= rhs) - (lhs < rhs)); \
    }

#define zig_float_greater_builtin_0(Type, operation) \
    zig_float_less_builtin_0(Type, operation)
#define zig_float_greater_builtin_1(Type, operation) \
    static inline int32_t zig_##operation##_##Type(zig_##Type lhs, zig_##Type rhs) { \
        return ((lhs > rhs) - !(lhs >= rhs)); \
    }

#define zig_float_binary_builtin_0(Type, operation, operator) \
    zig_extern zig_##Type zig_expand_concat(zig_expand_concat(__##operation, \
        zig_compiler_rt_abbrev_zig_##Type), 3)(zig_##Type, zig_##Type); \
    static inline zig_##Type zig_##operation##_##Type(zig_##Type lhs, zig_##Type rhs) { \
        return zig_expand_concat(zig_expand_concat(__##operation, zig_compiler_rt_abbrev_zig_##Type), 3)(lhs, rhs); \
    }
#define zig_float_binary_builtin_1(Type, operation, operator) \
    static inline zig_##Type zig_##operation##_##Type(zig_##Type lhs, zig_##Type rhs) { \
        return lhs operator rhs; \
    }

#define zig_float_builtins(w) \
    zig_common_float_builtins(w) \
    zig_convert_float(f##w,   zig_f##w, float,    int128, zig_i128, ) \
    zig_convert_float(f##w,   zig_f##w, floatun,  int128, zig_u128, )
#define zig_common_float_builtins(w) \
    zig_convert_float(always,  int32_t, fix,        f##w, zig_f##w, ) \
    zig_convert_float(always,  int64_t, fix,        f##w, zig_f##w, ) \
    zig_convert_float(int128, zig_i128, fix,        f##w, zig_f##w, ) \
    zig_convert_float(always, uint32_t, fixuns,     f##w, zig_f##w, ) \
    zig_convert_float(always, uint64_t, fixuns,     f##w, zig_f##w, ) \
    zig_convert_float(int128, zig_u128, fixuns,     f##w, zig_f##w, ) \
    zig_convert_float(f##w,   zig_f##w, float,    always,  int32_t, ) \
    zig_convert_float(f##w,   zig_f##w, float,    always,  int64_t, ) \
    zig_convert_float(f##w,   zig_f##w, floatun,  always, uint32_t, ) \
    zig_convert_float(f##w,   zig_f##w, floatun,  always, uint64_t, ) \
\
    static inline void zig_expand_concat(zig_expand_concat(zig_fix, \
        zig_compiler_rt_abbrev_zig_f##w), ei)(void *res, zig_f##w arg, uint16_t bits) { \
        zig_extern void zig_expand_concat(zig_expand_concat(__fix, \
            zig_compiler_rt_abbrev_zig_f##w), ei)(uint8_t *res, uintptr_t bits, zig_f##w arg); \
        zig_expand_concat(zig_expand_concat(__fix, \
            zig_compiler_rt_abbrev_zig_f##w), ei)(res, bits, arg); \
    } \
\
    static inline void zig_expand_concat(zig_expand_concat(zig_fixuns, \
        zig_compiler_rt_abbrev_zig_f##w), ei)(void *res, zig_f##w arg, uint16_t bits) { \
        zig_extern void zig_expand_concat(zig_expand_concat(__fixuns, \
            zig_compiler_rt_abbrev_zig_f##w), ei)(uint8_t *res, uintptr_t bits, zig_f##w arg); \
        zig_expand_concat(zig_expand_concat(__fixuns, \
            zig_compiler_rt_abbrev_zig_f##w), ei)(res, bits, arg); \
    } \
\
    static inline zig_f##w zig_expand_concat(zig_floatei, \
        zig_compiler_rt_abbrev_zig_f##w)(void *res, uint16_t bits) { \
        zig_extern zig_f##w zig_expand_concat(__floatei, \
            zig_compiler_rt_abbrev_zig_f##w)(const uint8_t *arg, uintptr_t bits); \
        return zig_expand_concat(__floatei, zig_compiler_rt_abbrev_zig_f##w)(res, bits); \
    } \
\
    static inline zig_f##w zig_expand_concat(zig_floatunei, \
        zig_compiler_rt_abbrev_zig_f##w)(void *res, uint16_t bits) { \
        zig_extern zig_f##w zig_expand_concat(__floatunei, \
            zig_compiler_rt_abbrev_zig_f##w)(const uint8_t *arg, uintptr_t bits); \
        return zig_expand_concat(__floatunei, zig_compiler_rt_abbrev_zig_f##w)(res, bits); \
    } \
\
    zig_expand_concat(zig_float_less_builtin_,    zig_has_f##w)(f##w, cmp) \
    zig_expand_concat(zig_float_less_builtin_,    zig_has_f##w)(f##w, ne) \
    zig_expand_concat(zig_float_less_builtin_,    zig_has_f##w)(f##w, eq) \
    zig_expand_concat(zig_float_less_builtin_,    zig_has_f##w)(f##w, lt) \
    zig_expand_concat(zig_float_less_builtin_,    zig_has_f##w)(f##w, le) \
    zig_expand_concat(zig_float_greater_builtin_, zig_has_f##w)(f##w, gt) \
    zig_expand_concat(zig_float_greater_builtin_, zig_has_f##w)(f##w, ge) \
    zig_expand_concat(zig_float_binary_builtin_,  zig_has_f##w)(f##w, add, +) \
    zig_expand_concat(zig_float_binary_builtin_,  zig_has_f##w)(f##w, sub, -) \
    zig_expand_concat(zig_float_binary_builtin_,  zig_has_f##w)(f##w, mul, *) \
    zig_expand_concat(zig_float_binary_builtin_,  zig_has_f##w)(f##w, div, /) \
    zig_expand_concat(zig_expand_import_, zig_expand_has_builtin(zig_libc_name_f##w(sqrt)))(zig_f##w, zig_sqrt_f##w, zig_libc_name_f##w(sqrt), (zig_f##w x), (x)) \
    zig_expand_concat(zig_expand_import_, zig_expand_has_builtin(zig_libc_name_f##w(sin)))(zig_f##w, zig_sin_f##w, zig_libc_name_f##w(sin), (zig_f##w x), (x)) \
    zig_expand_concat(zig_expand_import_, zig_expand_has_builtin(zig_libc_name_f##w(cos)))(zig_f##w, zig_cos_f##w, zig_libc_name_f##w(cos), (zig_f##w x), (x)) \
    zig_expand_concat(zig_expand_import_, zig_expand_has_builtin(zig_libc_name_f##w(tan)))(zig_f##w, zig_tan_f##w, zig_libc_name_f##w(tan), (zig_f##w x), (x)) \
    zig_expand_concat(zig_expand_import_, zig_expand_has_builtin(zig_libc_name_f##w(exp)))(zig_f##w, zig_exp_f##w, zig_libc_name_f##w(exp), (zig_f##w x), (x)) \
    zig_expand_concat(zig_expand_import_, zig_expand_has_builtin(zig_libc_name_f##w(exp2)))(zig_f##w, zig_exp2_f##w, zig_libc_name_f##w(exp2), (zig_f##w x), (x)) \
    zig_expand_concat(zig_expand_import_, zig_expand_has_builtin(zig_libc_name_f##w(log)))(zig_f##w, zig_log_f##w, zig_libc_name_f##w(log), (zig_f##w x), (x)) \
    zig_expand_concat(zig_expand_import_, zig_expand_has_builtin(zig_libc_name_f##w(log2)))(zig_f##w, zig_log2_f##w, zig_libc_name_f##w(log2), (zig_f##w x), (x)) \
    zig_expand_concat(zig_expand_import_, zig_expand_has_builtin(zig_libc_name_f##w(log10)))(zig_f##w, zig_log10_f##w, zig_libc_name_f##w(log10), (zig_f##w x), (x)) \
    zig_expand_concat(zig_expand_import_, zig_expand_has_builtin(zig_libc_name_f##w(fabs)))(zig_f##w, zig_abs_f##w, zig_libc_name_f##w(fabs), (zig_f##w x), (x)) \
    zig_expand_concat(zig_expand_import_, zig_expand_has_builtin(zig_libc_name_f##w(floor)))(zig_f##w, zig_floor_f##w, zig_libc_name_f##w(floor), (zig_f##w x), (x)) \
    zig_expand_concat(zig_expand_import_, zig_expand_has_builtin(zig_libc_name_f##w(ceil)))(zig_f##w, zig_ceil_f##w, zig_libc_name_f##w(ceil), (zig_f##w x), (x)) \
    zig_expand_concat(zig_expand_import_, zig_expand_has_builtin(zig_libc_name_f##w(round)))(zig_f##w, zig_round_f##w, zig_libc_name_f##w(round), (zig_f##w x), (x)) \
    zig_expand_concat(zig_expand_import_, zig_expand_has_builtin(zig_libc_name_f##w(trunc)))(zig_f##w, zig_trunc_f##w, zig_libc_name_f##w(trunc), (zig_f##w x), (x)) \
    zig_expand_concat(zig_expand_import_, zig_expand_has_builtin(zig_libc_name_f##w(fmod)))(zig_f##w, zig_fmod_f##w, zig_libc_name_f##w(fmod), (zig_f##w x, zig_f##w y), (x, y)) \
    zig_expand_concat(zig_expand_import_, zig_expand_has_builtin(zig_libc_name_f##w(fmin)))(zig_f##w, zig_min_f##w, zig_libc_name_f##w(fmin), (zig_f##w x, zig_f##w y), (x, y)) \
    zig_expand_concat(zig_expand_import_, zig_expand_has_builtin(zig_libc_name_f##w(fmax)))(zig_f##w, zig_max_f##w, zig_libc_name_f##w(fmax), (zig_f##w x, zig_f##w y), (x, y)) \
    zig_expand_concat(zig_expand_import_, zig_expand_has_builtin(zig_libc_name_f##w(fma)))(zig_f##w, zig_fma_f##w, zig_libc_name_f##w(fma), (zig_f##w x, zig_f##w y, zig_f##w z), (x, y, z)) \
\
    static inline zig_f##w zig_divTrunc_f##w(zig_f##w lhs, zig_f##w rhs) { \
        return zig_trunc_f##w(zig_div_f##w(lhs, rhs)); \
    } \
\
    static inline zig_f##w zig_divFloor_f##w(zig_f##w lhs, zig_f##w rhs) { \
        return zig_floor_f##w(zig_div_f##w(lhs, rhs)); \
    } \
\
    static inline zig_f##w zig_divCeil_f##w(zig_f##w lhs, zig_f##w rhs) { \
        return zig_ceil_f##w(zig_div_f##w(lhs, rhs)); \
    } \
\
    static inline zig_f##w zig_mod_f##w(zig_f##w lhs, zig_f##w rhs) { \
        return zig_sub_f##w(lhs, zig_mul_f##w(zig_divFloor_f##w(lhs, rhs), rhs)); \
    }
zig_float_builtins(16)
zig_float_builtins(32)
zig_float_builtins(64)
zig_float_builtins(80)
#if defined(zig_x86_32)
zig_common_float_builtins(128)
static inline zig_f128 zig_floattitf(zig_i128 arg) {
    extern zig_f128 __floattitf(zig_f128 arg);
    return __floattitf(zig_f128_bitCast_i128(arg));
}
static inline zig_f128 zig_floatuntitf(zig_u128 arg) {
    extern zig_f128 __floatuntitf(zig_f128 arg);
    return __floatuntitf(zig_f128_bitCast_u128(arg));
}
#elif defined(zig_x86_64) && defined(zig_windows)
zig_common_float_builtins(128)
static inline zig_f128 zig_floattitf(zig_i128 arg) {
    extern zig_f128 __floattitf(zig_i128 arg);
    return __floattitf(arg);
}
static inline zig_f128 zig_floatuntitf(zig_u128 arg) {
    extern zig_f128 __floatuntitf(uint64_t arg_lo, uint64_t arg_hi);
    return __floatuntitf(zig_lo_u128(arg), zig_hi_u128(arg));
}
#else
zig_float_builtins(128)
#endif

/* ============================ Atomics Support ============================= */

/* Note that atomics should be implemented as macros because most
   compilers silently discard runtime atomic order information. */

/* Define fallback implementations first that can later be undef'd on compilers with builtin support. */
/* Note that zig_atomicrmw_expected is needed to handle aliasing between res and arg. */
#define zig_atomicrmw_xchg_float(res, obj, arg, order, Type, ReprType) do { \
    zig_##Type zig_atomicrmw_expected; \
    zig_atomic_load(zig_atomicrmw_expected, obj, zig_memory_order_relaxed, Type, ReprType); \
    while (!zig_cmpxchg_weak(obj, zig_atomicrmw_expected, arg, order, zig_memory_order_relaxed, Type, ReprType)); \
    res = zig_atomicrmw_expected; \
} while (0)
#define  zig_atomicrmw_add_float(res, obj, arg, order, Type, ReprType) do { \
    zig_##Type zig_atomicrmw_expected; \
    zig_##Type zig_atomicrmw_desired; \
    zig_atomic_load(zig_atomicrmw_expected, obj, zig_memory_order_relaxed, Type, ReprType); \
    do { \
        zig_atomicrmw_desired = zig_add_##Type(zig_atomicrmw_expected, arg); \
    } while (!zig_cmpxchg_weak(obj, zig_atomicrmw_expected, zig_atomicrmw_desired, order, zig_memory_order_relaxed, Type, ReprType)); \
    res = zig_atomicrmw_expected; \
} while (0)
#define  zig_atomicrmw_sub_float(res, obj, arg, order, Type, ReprType) do { \
    zig_##Type zig_atomicrmw_expected; \
    zig_##Type zig_atomicrmw_desired; \
    zig_atomic_load(zig_atomicrmw_expected, obj, zig_memory_order_relaxed, Type, ReprType); \
    do { \
        zig_atomicrmw_desired = zig_sub_##Type(zig_atomicrmw_expected, arg); \
    } while (!zig_cmpxchg_weak(obj, zig_atomicrmw_expected, zig_atomicrmw_desired, order, zig_memory_order_relaxed, Type, ReprType)); \
    res = zig_atomicrmw_expected; \
} while (0)
#define  zig_atomicrmw_min_float(res, obj, arg, order, Type, ReprType) do { \
    zig_##Type zig_atomicrmw_expected; \
    zig_##Type zig_atomicrmw_desired; \
    zig_atomic_load(zig_atomicrmw_expected, obj, zig_memory_order_relaxed, Type, ReprType); \
    do { \
        zig_atomicrmw_desired = zig_min_##Type(zig_atomicrmw_expected, arg); \
    } while (!zig_cmpxchg_weak(obj, zig_atomicrmw_expected, zig_atomicrmw_desired, order, zig_memory_order_relaxed, Type, ReprType)); \
    res = zig_atomicrmw_expected; \
} while (0)
#define  zig_atomicrmw_max_float(res, obj, arg, order, Type, ReprType) do { \
    zig_##Type zig_atomicrmw_expected; \
    zig_##Type zig_atomicrmw_desired; \
    zig_atomic_load(zig_atomicrmw_expected, obj, zig_memory_order_relaxed, Type, ReprType); \
    do { \
        zig_atomicrmw_desired = zig_max_##Type(zig_atomicrmw_expected, arg); \
    } while (!zig_cmpxchg_weak(obj, zig_atomicrmw_expected, zig_atomicrmw_desired, order, zig_memory_order_relaxed, Type, ReprType)); \
    res = zig_atomicrmw_expected; \
} while (0)

#define zig_atomicrmw_xchg_int128(res, obj, arg, order, Type, ReprType) do { \
    zig_##Type zig_atomicrmw_expected; \
    zig_atomic_load(zig_atomicrmw_expected, obj, zig_memory_order_relaxed, Type, ReprType); \
    while (!zig_cmpxchg_weak(obj, zig_atomicrmw_expected, arg, order, zig_memory_order_relaxed, Type, ReprType)); \
    res = zig_atomicrmw_expected; \
} while (0)
#define  zig_atomicrmw_add_int128(res, obj, arg, order, Type, ReprType) do { \
    zig_##Type zig_atomicrmw_expected; \
    zig_##Type zig_atomicrmw_desired; \
    zig_atomic_load(zig_atomicrmw_expected, obj, zig_memory_order_relaxed, Type, ReprType); \
    do { \
        zig_atomicrmw_desired = zig_add_##Type(zig_atomicrmw_expected, arg); \
    } while (!zig_cmpxchg_weak(obj, zig_atomicrmw_expected, zig_atomicrmw_desired, order, zig_memory_order_relaxed, Type, ReprType)); \
    res = zig_atomicrmw_expected; \
} while (0)
#define  zig_atomicrmw_sub_int128(res, obj, arg, order, Type, ReprType) do { \
    zig_##Type zig_atomicrmw_expected; \
    zig_##Type zig_atomicrmw_desired; \
    zig_atomic_load(zig_atomicrmw_expected, obj, zig_memory_order_relaxed, Type, ReprType); \
    do { \
        zig_atomicrmw_desired = zig_sub_##Type(zig_atomicrmw_expected, arg); \
    } while (!zig_cmpxchg_weak(obj, zig_atomicrmw_expected, zig_atomicrmw_desired, order, zig_memory_order_relaxed, Type, ReprType)); \
    res = zig_atomicrmw_expected; \
} while (0)
#define  zig_atomicrmw_and_int128(res, obj, arg, order, Type, ReprType) do { \
    zig_##Type zig_atomicrmw_expected; \
    zig_##Type zig_atomicrmw_desired; \
    zig_atomic_load(zig_atomicrmw_expected, obj, zig_memory_order_relaxed, Type, ReprType); \
    do { \
        zig_atomicrmw_desired = zig_and_##Type(zig_atomicrmw_expected, arg); \
    } while (!zig_cmpxchg_weak(obj, zig_atomicrmw_expected, zig_atomicrmw_desired, order, zig_memory_order_relaxed, Type, ReprType)); \
    res = zig_atomicrmw_expected; \
} while (0)
#define  zig_atomicrmw_nand_int128(res, obj, arg, order, Type, ReprType) do { \
    zig_##Type zig_atomicrmw_expected; \
    zig_##Type zig_atomicrmw_desired; \
    zig_atomic_load(zig_atomicrmw_expected, obj, zig_memory_order_relaxed, Type, ReprType); \
    do { \
        zig_atomicrmw_desired = zig_not_##Type(zig_and_##Type(zig_atomicrmw_expected, arg), 128); \
    } while (!zig_cmpxchg_weak(obj, zig_atomicrmw_expected, zig_atomicrmw_desired, order, zig_memory_order_relaxed, Type, ReprType)); \
    res = zig_atomicrmw_expected; \
} while (0)
#define  zig_atomicrmw_or_int128(res, obj, arg, order, Type, ReprType) do { \
    zig_##Type zig_atomicrmw_expected; \
    zig_##Type zig_atomicrmw_desired; \
    zig_atomic_load(zig_atomicrmw_expected, obj, zig_memory_order_relaxed, Type, ReprType); \
    do { \
        zig_atomicrmw_desired = zig_or_##Type(zig_atomicrmw_expected, arg); \
    } while (!zig_cmpxchg_weak(obj, zig_atomicrmw_expected, zig_atomicrmw_desired, order, zig_memory_order_relaxed, Type, ReprType)); \
    res = zig_atomicrmw_expected; \
} while (0)
#define  zig_atomicrmw_xor_int128(res, obj, arg, order, Type, ReprType) do { \
    zig_##Type zig_atomicrmw_expected; \
    zig_##Type zig_atomicrmw_desired; \
    zig_atomic_load(zig_atomicrmw_expected, obj, zig_memory_order_relaxed, Type, ReprType); \
    do { \
        zig_atomicrmw_desired = zig_xor_##Type(zig_atomicrmw_expected, arg); \
    } while (!zig_cmpxchg_weak(obj, zig_atomicrmw_expected, zig_atomicrmw_desired, order, zig_memory_order_relaxed, Type, ReprType)); \
    res = zig_atomicrmw_expected; \
} while (0)
#define  zig_atomicrmw_min_int128(res, obj, arg, order, Type, ReprType) do { \
    zig_##Type zig_atomicrmw_expected; \
    zig_##Type zig_atomicrmw_desired; \
    zig_atomic_load(zig_atomicrmw_expected, obj, zig_memory_order_relaxed, Type, ReprType); \
    do { \
        zig_atomicrmw_desired = zig_min_##Type(zig_atomicrmw_expected, arg); \
    } while (!zig_cmpxchg_weak(obj, zig_atomicrmw_expected, zig_atomicrmw_desired, order, zig_memory_order_relaxed, Type, ReprType)); \
    res = zig_atomicrmw_expected; \
} while (0)
#define  zig_atomicrmw_max_int128(res, obj, arg, order, Type, ReprType) do { \
    zig_##Type zig_atomicrmw_expected; \
    zig_##Type zig_atomicrmw_desired; \
    zig_atomic_load(zig_atomicrmw_expected, obj, zig_memory_order_relaxed, Type, ReprType); \
    do { \
        zig_atomicrmw_desired = zig_max_##Type(zig_atomicrmw_expected, arg); \
    } while (!zig_cmpxchg_weak(obj, zig_atomicrmw_expected, zig_atomicrmw_desired, order, zig_memory_order_relaxed, Type, ReprType)); \
    res = zig_atomicrmw_expected; \
} while (0)

#if (__STDC_VERSION__ >= 201112L && !defined(__STDC_NO_ATOMICS__)) || (zig_has_include(<stdatomic.h>) && !defined(zig_msvc))
#define zig_c11_atomics
#endif

#if defined(zig_c11_atomics)
#include <stdatomic.h>
typedef enum memory_order zig_memory_order;
#define zig_memory_order_relaxed memory_order_relaxed
#define zig_memory_order_acquire memory_order_acquire
#define zig_memory_order_release memory_order_release
#define zig_memory_order_acq_rel memory_order_acq_rel
#define zig_memory_order_seq_cst memory_order_seq_cst
#define zig_atomic(Type) _Atomic(Type)
#define zig_cmpxchg_strong(     obj, expected, desired, succ, fail, Type, ReprType) atomic_compare_exchange_strong_explicit(obj, &(expected), desired, succ, fail)
#define   zig_cmpxchg_weak(     obj, expected, desired, succ, fail, Type, ReprType) atomic_compare_exchange_weak_explicit  (obj, &(expected), desired, succ, fail)
#define zig_atomicrmw_xchg(res, obj, arg, order, Type, ReprType) res = atomic_exchange_explicit  (obj, arg, order)
#define  zig_atomicrmw_add(res, obj, arg, order, Type, ReprType) res = atomic_fetch_add_explicit (obj, arg, order)
#define  zig_atomicrmw_sub(res, obj, arg, order, Type, ReprType) res = atomic_fetch_sub_explicit (obj, arg, order)
#define   zig_atomicrmw_or(res, obj, arg, order, Type, ReprType) res = atomic_fetch_or_explicit  (obj, arg, order)
#define  zig_atomicrmw_xor(res, obj, arg, order, Type, ReprType) res = atomic_fetch_xor_explicit (obj, arg, order)
#define  zig_atomicrmw_and(res, obj, arg, order, Type, ReprType) res = atomic_fetch_and_explicit (obj, arg, order)
#define zig_atomicrmw_nand(res, obj, arg, order, Type, ReprType) res = __atomic_fetch_nand(obj, arg, order)
#define  zig_atomicrmw_min(res, obj, arg, order, Type, ReprType) res = __atomic_fetch_min (obj, arg, order)
#define  zig_atomicrmw_max(res, obj, arg, order, Type, ReprType) res = __atomic_fetch_max (obj, arg, order)
#define   zig_atomic_store(     obj, arg, order, Type, ReprType)       atomic_store_explicit     (obj, arg, order)
#define    zig_atomic_load(res, obj,      order, Type, ReprType) res = atomic_load_explicit      (obj,      order)
#undef  zig_atomicrmw_xchg_float
#define zig_atomicrmw_xchg_float zig_atomicrmw_xchg
#undef  zig_atomicrmw_add_float
#define zig_atomicrmw_add_float zig_atomicrmw_add
#undef  zig_atomicrmw_sub_float
#define zig_atomicrmw_sub_float zig_atomicrmw_sub
#elif defined(zig_gnuc)
typedef int zig_memory_order;
#define zig_memory_order_relaxed __ATOMIC_RELAXED
#define zig_memory_order_acquire __ATOMIC_ACQUIRE
#define zig_memory_order_release __ATOMIC_RELEASE
#define zig_memory_order_acq_rel __ATOMIC_ACQ_REL
#define zig_memory_order_seq_cst __ATOMIC_SEQ_CST
#define zig_atomic(Type) Type
#define zig_cmpxchg_strong(     obj, expected, desired, succ, fail, Type, ReprType) __atomic_compare_exchange(obj, (ReprType *)&(expected), (ReprType *)&(desired), false, succ, fail)
#define   zig_cmpxchg_weak(     obj, expected, desired, succ, fail, Type, ReprType) __atomic_compare_exchange(obj, (ReprType *)&(expected), (ReprType *)&(desired),  true, succ, fail)
#define zig_atomicrmw_xchg(res, obj, arg, order, Type, ReprType)       __atomic_exchange(obj, (ReprType *)&(arg), &(res), order)
#define  zig_atomicrmw_add(res, obj, arg, order, Type, ReprType) res = __atomic_fetch_add (obj, arg, order)
#define  zig_atomicrmw_sub(res, obj, arg, order, Type, ReprType) res = __atomic_fetch_sub (obj, arg, order)
#define   zig_atomicrmw_or(res, obj, arg, order, Type, ReprType) res = __atomic_fetch_or  (obj, arg, order)
#define  zig_atomicrmw_xor(res, obj, arg, order, Type, ReprType) res = __atomic_fetch_xor (obj, arg, order)
#define  zig_atomicrmw_and(res, obj, arg, order, Type, ReprType) res = __atomic_fetch_and (obj, arg, order)
#define zig_atomicrmw_nand(res, obj, arg, order, Type, ReprType) res = __atomic_fetch_nand(obj, arg, order)
#define  zig_atomicrmw_min(res, obj, arg, order, Type, ReprType) res = __atomic_fetch_min (obj, arg, order)
#define  zig_atomicrmw_max(res, obj, arg, order, Type, ReprType) res = __atomic_fetch_max (obj, arg, order)
#define   zig_atomic_store(     obj, arg, order, Type, ReprType)       __atomic_store     (obj, (ReprType *)&(arg), order)
#define    zig_atomic_load(res, obj,      order, Type, ReprType)       __atomic_load      (obj, &(res), order)
#undef  zig_atomicrmw_xchg_float
#define zig_atomicrmw_xchg_float zig_atomicrmw_xchg
#elif defined(zig_msvc) && defined(zig_x86)
#define zig_memory_order_relaxed 0
#define zig_memory_order_acquire 2
#define zig_memory_order_release 3
#define zig_memory_order_acq_rel 4
#define zig_memory_order_seq_cst 5
#define zig_atomic(Type) Type
#define zig_cmpxchg_strong(     obj, expected, desired, succ, fail, Type, ReprType) zig_msvc_cmpxchg_##Type(obj, &(expected), desired)
#define   zig_cmpxchg_weak(     obj, expected, desired, succ, fail, Type, ReprType) zig_cmpxchg_strong(obj, expected, desired, succ, fail, Type, ReprType)
#define zig_atomicrmw_xchg(res, obj, arg, order, Type, ReprType) res = zig_msvc_atomicrmw_xchg_##Type(obj, arg)
#define  zig_atomicrmw_add(res, obj, arg, order, Type, ReprType) res = zig_msvc_atomicrmw_add_ ##Type(obj, arg)
#define  zig_atomicrmw_sub(res, obj, arg, order, Type, ReprType) res = zig_msvc_atomicrmw_sub_ ##Type(obj, arg)
#define   zig_atomicrmw_or(res, obj, arg, order, Type, ReprType) res = zig_msvc_atomicrmw_or_  ##Type(obj, arg)
#define  zig_atomicrmw_xor(res, obj, arg, order, Type, ReprType) res = zig_msvc_atomicrmw_xor_ ##Type(obj, arg)
#define  zig_atomicrmw_and(res, obj, arg, order, Type, ReprType) res = zig_msvc_atomicrmw_and_ ##Type(obj, arg)
#define zig_atomicrmw_nand(res, obj, arg, order, Type, ReprType) res = zig_msvc_atomicrmw_nand_##Type(obj, arg)
#define  zig_atomicrmw_min(res, obj, arg, order, Type, ReprType) res = zig_msvc_atomicrmw_min_ ##Type(obj, arg)
#define  zig_atomicrmw_max(res, obj, arg, order, Type, ReprType) res = zig_msvc_atomicrmw_max_ ##Type(obj, arg)
#define   zig_atomic_store(     obj, arg, order, Type, ReprType)       zig_msvc_atomic_store_  ##Type(obj, arg)
#define    zig_atomic_load(res, obj,      order, Type, ReprType) res = zig_msvc_atomic_load_   ##order##_##Type(obj)
/* TODO: zig_msvc && (zig_thumb || zig_aarch64) */
#else
#define zig_memory_order_relaxed 0
#define zig_memory_order_acquire 2
#define zig_memory_order_release 3
#define zig_memory_order_acq_rel 4
#define zig_memory_order_seq_cst 5
#define zig_atomic(Type) Type
#define zig_cmpxchg_strong(     obj, expected, desired, succ, fail, Type, ReprType) zig_atomics_unavailable
#define   zig_cmpxchg_weak(     obj, expected, desired, succ, fail, Type, ReprType) zig_atomics_unavailable
#define zig_atomicrmw_xchg(res, obj, arg, order, Type, ReprType) zig_atomics_unavailable
#define  zig_atomicrmw_add(res, obj, arg, order, Type, ReprType) zig_atomics_unavailable
#define  zig_atomicrmw_sub(res, obj, arg, order, Type, ReprType) zig_atomics_unavailable
#define   zig_atomicrmw_or(res, obj, arg, order, Type, ReprType) zig_atomics_unavailable
#define  zig_atomicrmw_xor(res, obj, arg, order, Type, ReprType) zig_atomics_unavailable
#define  zig_atomicrmw_and(res, obj, arg, order, Type, ReprType) zig_atomics_unavailable
#define zig_atomicrmw_nand(res, obj, arg, order, Type, ReprType) zig_atomics_unavailable
#define  zig_atomicrmw_min(res, obj, arg, order, Type, ReprType) zig_atomics_unavailable
#define  zig_atomicrmw_max(res, obj, arg, order, Type, ReprType) zig_atomics_unavailable
#define   zig_atomic_store(     obj, arg, order, Type, ReprType) zig_atomics_unavailable
#define    zig_atomic_load(res, obj,      order, Type, ReprType) zig_atomics_unavailable
#endif

#if !defined(zig_c11_atomics) && defined(zig_msvc) && defined(zig_x86)

/* TODO: zig_msvc_atomic_load should load 32 bit without interlocked on x86, and load 64 bit without interlocked on x64 */

#define zig_msvc_atomics(ZigType, Type, SigType, suffix, iso_suffix) \
    static inline bool zig_msvc_cmpxchg_##ZigType(Type volatile* obj, Type* expected, Type desired) { \
        Type comparand = *expected; \
        Type initial = _InterlockedCompareExchange##suffix((SigType volatile*)obj, (SigType)desired, (SigType)comparand); \
        bool exchanged = initial == comparand; \
        if (!exchanged) { \
            *expected = initial; \
        } \
        return exchanged; \
    } \
    static inline Type zig_msvc_atomicrmw_xchg_##ZigType(Type volatile* obj, Type value) { \
        return _InterlockedExchange##suffix((SigType volatile*)obj, (SigType)value); \
    } \
    static inline Type zig_msvc_atomicrmw_add_##ZigType(Type volatile* obj, Type value) { \
        return _InterlockedExchangeAdd##suffix((SigType volatile*)obj, (SigType)value); \
    } \
    static inline Type zig_msvc_atomicrmw_sub_##ZigType(Type volatile* obj, Type value) { \
        bool success = false; \
        Type new; \
        Type prev; \
        while (!success) { \
            prev = *obj; \
            new = prev - value; \
            success = zig_msvc_cmpxchg_##ZigType(obj, &prev, new); \
        } \
        return prev; \
    } \
    static inline Type zig_msvc_atomicrmw_or_##ZigType(Type volatile* obj, Type value) { \
        return _InterlockedOr##suffix((SigType volatile*)obj, (SigType)value); \
    } \
    static inline Type zig_msvc_atomicrmw_xor_##ZigType(Type volatile* obj, Type value) { \
        return _InterlockedXor##suffix((SigType volatile*)obj, (SigType)value); \
    } \
    static inline Type zig_msvc_atomicrmw_and_##ZigType(Type volatile* obj, Type value) { \
        return _InterlockedAnd##suffix((SigType volatile*)obj, (SigType)value); \
    } \
    static inline Type zig_msvc_atomicrmw_nand_##ZigType(Type volatile* obj, Type value) { \
        bool success = false; \
        Type new; \
        Type prev; \
        while (!success) { \
            prev = *obj; \
            new = ~(prev & value); \
            success = zig_msvc_cmpxchg_##ZigType(obj, &prev, new); \
        } \
        return prev; \
    } \
    static inline Type zig_msvc_atomicrmw_min_##ZigType(Type volatile* obj, Type value) { \
        bool success = false; \
        Type new; \
        Type prev; \
        while (!success) { \
            prev = *obj; \
            new = value < prev ? value : prev; \
            success = zig_msvc_cmpxchg_##ZigType(obj, &prev, new); \
        } \
        return prev; \
    } \
    static inline Type zig_msvc_atomicrmw_max_##ZigType(Type volatile* obj, Type value) { \
        bool success = false; \
        Type new; \
        Type prev; \
        while (!success) { \
            prev = *obj; \
            new = value > prev ? value : prev; \
            success = zig_msvc_cmpxchg_##ZigType(obj, &prev, new); \
        } \
        return prev; \
    } \
    static inline void zig_msvc_atomic_store_##ZigType(Type volatile* obj, Type value) { \
        (void)_InterlockedExchange##suffix((SigType volatile*)obj, (SigType)value); \
    } \
    static inline Type zig_msvc_atomic_load_zig_memory_order_relaxed_##ZigType(Type volatile* obj) { \
        return __iso_volatile_load##iso_suffix((SigType volatile*)obj); \
    } \
    static inline Type zig_msvc_atomic_load_zig_memory_order_acquire_##ZigType(Type volatile* obj) { \
        Type value = __iso_volatile_load##iso_suffix((SigType volatile*)obj); \
        _ReadWriteBarrier(); \
        return value; \
    } \
    static inline Type zig_msvc_atomic_load_zig_memory_order_seq_cst_##ZigType(Type volatile* obj) { \
        Type value = __iso_volatile_load##iso_suffix((SigType volatile*)obj); \
        _ReadWriteBarrier(); \
        return value; \
    }

zig_msvc_atomics( u8,  uint8_t,    char,  8, 8)
zig_msvc_atomics( i8,   int8_t,    char,  8, 8)
zig_msvc_atomics(u16, uint16_t,   short, 16, 16)
zig_msvc_atomics(i16,  int16_t,   short, 16, 16)
zig_msvc_atomics(u32, uint32_t,    long,   , 32)
zig_msvc_atomics(i32,  int32_t,    long,   , 32)

#if defined(zig_x86_64)
zig_msvc_atomics(u64, uint64_t, __int64, 64, 64)
zig_msvc_atomics(i64,  int64_t, __int64, 64, 64)
#endif

#define zig_msvc_flt_atomics(Type, SigType, suffix, iso_suffix) \
    static inline bool zig_msvc_cmpxchg_##Type(zig_##Type volatile* obj, zig_##Type* expected, zig_##Type desired) { \
        SigType exchange; \
        SigType comparand; \
        SigType initial; \
        bool success; \
        memcpy(&comparand, expected, sizeof(comparand)); \
        memcpy(&exchange, &desired, sizeof(exchange)); \
        initial = _InterlockedCompareExchange##suffix((SigType volatile*)obj, exchange, comparand); \
        success = initial == comparand; \
        if (!success) memcpy(expected, &initial, sizeof(*expected)); \
        return success; \
    } \
    static inline void zig_msvc_atomic_store_##Type(zig_##Type volatile* obj, zig_##Type arg) { \
        SigType value; \
        memcpy(&value, &arg, sizeof(value)); \
        (void)_InterlockedExchange##suffix((SigType volatile*)obj, value); \
    } \
    static inline zig_##Type zig_msvc_atomic_load_zig_memory_order_relaxed_##Type(zig_##Type volatile* obj) { \
        zig_##Type result; \
        SigType initial = __iso_volatile_load##iso_suffix((SigType volatile*)obj); \
        memcpy(&result, &initial, sizeof(result)); \
        return result; \
    } \
    static inline zig_##Type zig_msvc_atomic_load_zig_memory_order_acquire_##Type(zig_##Type volatile* obj) { \
        zig_##Type result; \
        SigType initial = __iso_volatile_load##iso_suffix((SigType volatile*)obj); \
        _ReadWriteBarrier(); \
        memcpy(&result, &initial, sizeof(result)); \
        return result; \
    } \
    static inline zig_##Type zig_msvc_atomic_load_zig_memory_order_seq_cst_##Type(zig_##Type volatile* obj) { \
        zig_##Type result; \
        SigType initial = __iso_volatile_load##iso_suffix((SigType volatile*)obj); \
        _ReadWriteBarrier(); \
        memcpy(&result, &initial, sizeof(result)); \
        return result; \
    }

zig_msvc_flt_atomics(f32,    long,   , 32)
#if defined(zig_x86_64)
zig_msvc_flt_atomics(f64, int64_t, 64, 64)
#endif

#if defined(zig_x86_32)
static inline void zig_msvc_atomic_barrier() {
    int32_t barrier;
    __asm {
        xchg barrier, eax
    }
}

static inline void* zig_msvc_atomicrmw_xchg_p32(void volatile* obj, void* arg) {
    return _InterlockedExchangePointer(obj, arg);
}

static inline void zig_msvc_atomic_store_p32(void volatile* obj, void* arg) {
    (void)_InterlockedExchangePointer(obj, arg);
}

static inline void* zig_msvc_atomic_load_zig_memory_order_relaxed_p32(void volatile* obj) {
    return (void*)__iso_volatile_load32(obj);
}

static inline void* zig_msvc_atomic_load_zig_memory_order_acquire_p32(void volatile* obj) {
    void* value = (void*)__iso_volatile_load32(obj);
    _ReadWriteBarrier();
    return value;
}

static inline void* zig_msvc_atomic_load_zig_memory_order_seq_cst_p32(void volatile* obj) {
    return zig_msvc_atomic_load_zig_memory_order_acquire_p32(obj);
}

static inline bool zig_msvc_cmpxchg_p32(void volatile* obj, void* expected, void* desired) {
    void* comparand = *(void**)expected;
    void* initial = _InterlockedCompareExchangePointer(obj, desired, comparand);
    bool success = initial == comparand;
    if (!success) *(void**)expected = initial;
    return success;
}
#else /* zig_x86_32 */
static inline void* zig_msvc_atomicrmw_xchg_p64(void volatile* obj, void* arg) {
    return _InterlockedExchangePointer(obj, arg);
}

static inline void zig_msvc_atomic_store_p64(void volatile* obj, void* arg) {
    (void)_InterlockedExchangePointer(obj, arg);
}

static inline void* zig_msvc_atomic_load_zig_memory_order_relaxed_p64(void volatile* obj) {
    return (void*)__iso_volatile_load64(obj);
}

static inline void* zig_msvc_atomic_load_zig_memory_order_acquire_p64(void volatile* obj) {
    void* value = (void*)__iso_volatile_load64(obj);
    _ReadWriteBarrier();
    return value;
}

static inline void* zig_msvc_atomic_load_zig_memory_order_seq_cst_p64(void volatile* obj) {
    return zig_msvc_atomic_load_zig_memory_order_acquire_p64(obj);
}

static inline bool zig_msvc_cmpxchg_p64(void volatile* obj, void* expected, void* desired) {
    void* comparand = *(void**)expected;
    void* initial = _InterlockedCompareExchangePointer(obj, desired, comparand);
    bool success = initial == comparand;
    if (!success) *(void**)expected = initial;
    return success;
}

static inline bool zig_msvc_cmpxchg_u128(zig_u128 volatile* obj, zig_u128* expected, zig_u128 desired) {
    return _InterlockedCompareExchange128((__int64 volatile*)obj, (__int64)zig_hi_u128(desired), (__int64)zig_lo_u128(desired), (__int64*)expected);
}

static inline zig_u128 zig_msvc_atomic_load_u128(zig_u128 volatile* obj) {
    zig_u128 expected = zig_make_u128(UINT64_C(0), UINT64_C(0));
    (void)zig_cmpxchg_strong(obj, expected, expected, zig_memory_order_seq_cst, zig_memory_order_seq_cst, u128, zig_u128);
    return expected;
}

static inline void zig_msvc_atomic_store_u128(zig_u128 volatile* obj, zig_u128 arg) {
    zig_u128 expected = zig_make_u128(UINT64_C(0), UINT64_C(0));
    while (!zig_cmpxchg_weak(obj, expected, arg, zig_memory_order_seq_cst, zig_memory_order_seq_cst, u128, zig_u128));
}

static inline bool zig_msvc_cmpxchg_i128(zig_i128 volatile* obj, zig_i128* expected, zig_i128 desired) {
    return _InterlockedCompareExchange128((__int64 volatile*)obj, (__int64)zig_hi_i128(desired), (__int64)zig_lo_i128(desired), (__int64*)expected);
}

static inline zig_i128 zig_msvc_atomic_load_i128(zig_i128 volatile* obj) {
    zig_i128 expected = zig_make_i128(INT64_C(0), UINT64_C(0));
    (void)zig_cmpxchg_strong(obj, expected, expected, zig_memory_order_seq_cst, zig_memory_order_seq_cst, i128, zig_i128);
    return expected;
}

static inline void zig_msvc_atomic_store_i128(zig_i128 volatile* obj, zig_i128 arg) {
    zig_i128 expected = zig_make_i128(INT64_C(0), UINT64_C(0));
    while (!zig_cmpxchg_weak(obj, expected, arg, zig_memory_order_seq_cst, zig_memory_order_seq_cst, i128, zig_i128));
}

#endif /* zig_x86_32 */

#endif /* !zig_c11_atomics && zig_msvc && zig_x86 */

/* ======================== Special Case Intrinsics ========================= */

#if defined(zig_msvc)
#include <intrin.h>
#endif

static inline void* zig_e_zig_windows_teb(void) zig_mangled(zig_e_zig_windows_teb, "zig_windows_teb");
static inline void* zig_e_zig_windows_peb(void) zig_mangled(zig_e_zig_windows_peb, "zig_windows_peb");

#if defined(zig_thumb)

static inline void* zig_e_zig_windows_teb(void) {
    void* teb = 0;
#if defined(zig_msvc)
    teb = (void*)_MoveFromCoprocessor(15, 0, 13, 0, 2);
#elif defined(zig_gnuc_asm)
    __asm__ ("mrc p15, 0, %[ptr], c13, c0, 2" : [ptr] "=r" (teb));
#endif
    return teb;
}

#elif defined(zig_aarch64)

static inline void* zig_e_zig_windows_teb(void) {
    void* teb = 0;
#if defined(zig_msvc)
    teb = (void*)__readx18qword(0x0);
#elif defined(zig_gnuc_asm)
    __asm__ ("mov %[ptr], x18" : [ptr] "=r" (teb));
#endif
    return teb;
}

#elif defined(zig_x86_32)

static inline void* zig_e_zig_windows_teb(void) {
    void* teb = 0;
#if defined(zig_msvc)
    teb = (void*)__readfsdword(0x18);
#elif defined(zig_gnuc_asm)
    __asm__ ("movl %%fs:0x18, %[ptr]" : [ptr] "=r" (teb));
#endif
    return teb;
}

static inline void* zig_e_zig_windows_peb(void) {
    void* peb = 0;
#if defined(zig_msvc)
    peb = (void*)__readfsdword(0x30);
#elif defined(zig_gnuc_asm)
    __asm__ ("movl %%fs:0x30, %[ptr]" : [ptr] "=r" (peb));
#endif
    return peb;
}

#elif defined(zig_x86_64)

static inline void* zig_e_zig_windows_teb(void) {
    void* teb = 0;
#if defined(zig_msvc)
    teb = (void*)__readgsqword(0x30);
#elif defined(zig_gnuc_asm)
    __asm__ ("movq %%gs:0x30, %[ptr]" : [ptr] "=r" (teb));
#endif
    return teb;
}

static inline void* zig_e_zig_windows_peb(void) {
    void* peb = 0;
#if defined(zig_msvc)
    peb = (void*)__readgsqword(0x60);
#elif defined(zig_gnuc_asm)
    __asm__ ("movq %%gs:0x60, %[ptr]" : [ptr] "=r" (peb));
#endif
    return peb;
}

#endif

#if defined(zig_loongarch)

static inline void zig_e_zig_loongarch_cpucfg(uint32_t word, uint32_t* result) zig_mangled(zig_e_zig_loongarch_cpucfg, "zig_loongarch_cpucfg");

static inline void zig_e_zig_loongarch_cpucfg(uint32_t word, uint32_t* result) {
#if defined(zig_gnuc_asm)
    __asm__("cpucfg %[result], %[word]" : [result] "=r" (*result) : [word] "r" (word));
#else
    *result = 0;
#endif
}

#elif defined(zig_x86) && !defined(zig_x86_16)

static inline void zig_e_zig_x86_cpuid(uint32_t leaf_id, uint32_t subid, uint32_t* eax, uint32_t* ebx, uint32_t* ecx, uint32_t* edx) zig_mangled(zig_e_zig_x86_cpuid, "zig_x86_cpuid");
static inline uint32_t zig_e_zig_x86_get_xcr0(void) zig_mangled(zig_e_zig_x86_get_xcr0, "zig_x86_get_xcr0");

static inline void zig_e_zig_x86_cpuid(uint32_t leaf_id, uint32_t subid, uint32_t* eax, uint32_t* ebx, uint32_t* ecx, uint32_t* edx) {
#if defined(zig_msvc)
    int cpu_info[4];
    __cpuidex(cpu_info, leaf_id, subid);
    *eax = (uint32_t)cpu_info[0];
    *ebx = (uint32_t)cpu_info[1];
    *ecx = (uint32_t)cpu_info[2];
    *edx = (uint32_t)cpu_info[3];
#elif defined(zig_gnuc_asm)
    __asm__("cpuid" : "=a" (*eax), "=b" (*ebx), "=c" (*ecx), "=d" (*edx) : "a" (leaf_id), "c" (subid));
#else
    *eax = 0;
    *ebx = 0;
    *ecx = 0;
    *edx = 0;
#endif
}

static inline uint32_t zig_e_zig_x86_get_xcr0(void) {
#if defined(zig_msvc)
    return (uint32_t)_xgetbv(0);
#elif defined(zig_gnuc_asm)
    uint32_t eax;
    uint32_t edx;
    __asm__("xgetbv" : "=a" (eax), "=d" (edx) : "c" (0));
    return eax;
#else
    *eax = 0;
    *ebx = 0;
    *ecx = 0;
    *edx = 0;
#endif
}

#endif

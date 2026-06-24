//! Tests for the C ABI.
//! Those tests are passing back and forth struct and values across C ABI
//! by combining Zig code here and its mirror in cfunc.c
//! To run all the tests on the tier 1 architecture you can use:
//! zig build test-c-abi -fqemu
//! To run the tests on a specific architecture:
//! zig test -lc main.zig cfuncs.c -target mips-linux --test-cmd qemu-mips --test-cmd-bin
const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const have_i128 = builtin.cpu.arch != .x86 and !builtin.cpu.arch.isArm() and
    !builtin.cpu.arch.isMIPS() and !builtin.cpu.arch.isPowerPC32() and builtin.cpu.arch != .riscv32 and
    builtin.cpu.arch != .hexagon and
    builtin.cpu.arch != .s390x; // https://github.com/llvm/llvm-project/issues/168460

const have_f128 = builtin.cpu.arch.isWasm() or (builtin.cpu.arch.isX86() and !builtin.os.tag.isDarwin() and builtin.abi != .msvc);
const have_f80 = builtin.cpu.arch.isX86() and builtin.abi != .msvc;

export fn zig_panic() noreturn {
    @panic("zig_panic called from C");
}

extern fn run_c_tests() void;
test run_c_tests {
    run_c_tests();
}

extern fn c_u8(u8) void;
extern fn c_u16(u16) void;
extern fn c_u32(u32) void;
extern fn c_u64(u64) void;
extern fn c_struct_u128(U128) void;
extern fn c_i8(i8) void;
extern fn c_i16(i16) void;
extern fn c_i32(i32) void;
extern fn c_i64(i64) void;
extern fn c_struct_i128(I128) void;

// On windows x64, the first 4 are passed via registers, others on the stack.
extern fn c_five_integers(i32, i32, i32, i32, i32) void;

export fn zig_five_integers(a: i32, b: i32, c: i32, d: i32, e: i32) void {
    expect(a == 12) catch @panic("test failure: zig_five_integers 12");
    expect(b == 34) catch @panic("test failure: zig_five_integers 34");
    expect(c == 56) catch @panic("test failure: zig_five_integers 56");
    expect(d == 78) catch @panic("test failure: zig_five_integers 78");
    expect(e == 90) catch @panic("test failure: zig_five_integers 90");
}

test "integers" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;

    c_u8(0xff);
    c_u16(0xfffe);
    c_u32(0xfffffffd);
    c_u64(0xfffffffffffffffc);
    if (have_i128) c_struct_u128(.{ .value = 0xfffffffffffffffc });

    c_i8(-1);
    c_i16(-2);
    c_i32(-3);
    c_i64(-4);
    if (have_i128) c_struct_i128(.{ .value = -6 });
    c_five_integers(12, 34, 56, 78, 90);
}

export fn zig_u8(x: u8) void {
    expect(x == 0xff) catch @panic("test failure: zig_u8");
}
export fn zig_u16(x: u16) void {
    expect(x == 0xfffe) catch @panic("test failure: zig_u16");
}
export fn zig_u32(x: u32) void {
    expect(x == 0xfffffffd) catch @panic("test failure: zig_u32");
}
export fn zig_u64(x: u64) void {
    expect(x == 0xfffffffffffffffc) catch @panic("test failure: zig_u64");
}
export fn zig_i8(x: i8) void {
    expect(x == -1) catch @panic("test failure: zig_i8");
}
export fn zig_i16(x: i16) void {
    expect(x == -2) catch @panic("test failure: zig_i16");
}
export fn zig_i32(x: i32) void {
    expect(x == -3) catch @panic("test failure: zig_i32");
}
export fn zig_i64(x: i64) void {
    expect(x == -4) catch @panic("test failure: zig_i64");
}

const I128 = extern struct {
    value: i128,
};
const U128 = extern struct {
    value: u128,
};
export fn zig_struct_i128(a: I128) void {
    expect(a.value == -6) catch @panic("test failure: zig_struct_i128");
}
export fn zig_struct_u128(a: U128) void {
    expect(a.value == 0xfffffffffffffffc) catch @panic("test failure: zig_struct_u128");
}

extern fn c_f32(f32) void;
extern fn c_f64(f64) void;
extern fn c_long_double(c_longdouble) void;

// On windows x64, the first 4 are passed via registers, others on the stack.
extern fn c_five_floats(f32, f32, f32, f32, f32) void;

export fn zig_five_floats(a: f32, b: f32, c: f32, d: f32, e: f32) void {
    expect(a == 1.0) catch @panic("test failure: zig_five_floats 1.0");
    expect(b == 2.0) catch @panic("test failure: zig_five_floats 2.0");
    expect(c == 3.0) catch @panic("test failure: zig_five_floats 3.0");
    expect(d == 4.0) catch @panic("test failure: zig_five_floats 4.0");
    expect(e == 5.0) catch @panic("test failure: zig_five_floats 5.0");
}

test "floats" {
    c_f32(12.34);
    c_f64(56.78);
    c_five_floats(1.0, 2.0, 3.0, 4.0, 5.0);
}

test "long double" {
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;

    c_long_double(12.34);
}

export fn zig_f32(x: f32) void {
    expect(x == 12.34) catch @panic("test failure: zig_f32");
}
export fn zig_f64(x: f64) void {
    expect(x == 56.78) catch @panic("test failure: zig_f64");
}
export fn zig_longdouble(x: c_longdouble) void {
    if (!builtin.target.cpu.arch.isWasm()) return; // waiting for #1481
    expect(x == 12.34) catch @panic("test failure: zig_longdouble");
}

extern fn c_ptr(*anyopaque) void;

test "pointer" {
    c_ptr(@as(*anyopaque, @ptrFromInt(0xdeadbeef)));
}

export fn zig_ptr(x: *anyopaque) void {
    expect(@intFromPtr(x) == 0xdeadbeef) catch @panic("test failure: zig_ptr");
}

extern fn c_bool(bool) void;

test "bool" {
    c_bool(true);
}

export fn zig_bool(x: bool) void {
    expect(x) catch @panic("test failure: zig_bool");
}

// TODO: Replace these with the correct types once we resolve
//       https://github.com/ziglang/zig/issues/8465
//
// For now, we have no way of referring to the _Complex C types from Zig,
// so our ABI is unavoidably broken on some platforms (such as x86)
const ComplexFloat = extern struct {
    real: f32,
    imag: f32,
};
const ComplexDouble = extern struct {
    real: f64,
    imag: f64,
};

// Note: These two functions match the signature of __mulsc3 and __muldc3 in compiler-rt (and libgcc)
extern fn c_cmultf_comp(a_r: f32, a_i: f32, b_r: f32, b_i: f32) ComplexFloat;
extern fn c_cmultd_comp(a_r: f64, a_i: f64, b_r: f64, b_i: f64) ComplexDouble;

extern fn c_cmultf(a: ComplexFloat, b: ComplexFloat) ComplexFloat;
extern fn c_cmultd(a: ComplexDouble, b: ComplexDouble) ComplexDouble;

const complex_abi_compatible = builtin.cpu.arch != .x86 and !builtin.cpu.arch.isMIPS() and
    !builtin.cpu.arch.isArm() and !builtin.cpu.arch.isPowerPC32() and !builtin.cpu.arch.isRISCV() and
    builtin.cpu.arch != .hexagon and
    builtin.cpu.arch != .s390x and
    !(builtin.cpu.arch.isLoongArch() and builtin.abi.float() == .soft);

test "complex float" {
    if (!complex_abi_compatible) return error.SkipZigTest;

    const a = ComplexFloat{ .real = 1.25, .imag = 2.6 };
    const b = ComplexFloat{ .real = 11.3, .imag = -1.5 };

    const z = c_cmultf(a, b);
    try expect(z.real == 1.5);
    try expect(z.imag == 13.5);
}

test "complex float by component" {
    if (!complex_abi_compatible) return error.SkipZigTest;

    const a = ComplexFloat{ .real = 1.25, .imag = 2.6 };
    const b = ComplexFloat{ .real = 11.3, .imag = -1.5 };

    const z2 = c_cmultf_comp(a.real, a.imag, b.real, b.imag);
    try expect(z2.real == 1.5);
    try expect(z2.imag == 13.5);
}

test "complex double" {
    if (!complex_abi_compatible) return error.SkipZigTest;

    const a = ComplexDouble{ .real = 1.25, .imag = 2.6 };
    const b = ComplexDouble{ .real = 11.3, .imag = -1.5 };

    const z = c_cmultd(a, b);
    try expect(z.real == 1.5);
    try expect(z.imag == 13.5);
}

test "complex double by component" {
    if (!complex_abi_compatible) return error.SkipZigTest;

    const a = ComplexDouble{ .real = 1.25, .imag = 2.6 };
    const b = ComplexDouble{ .real = 11.3, .imag = -1.5 };

    const z = c_cmultd_comp(a.real, a.imag, b.real, b.imag);
    try expect(z.real == 1.5);
    try expect(z.imag == 13.5);
}

export fn zig_cmultf(a: ComplexFloat, b: ComplexFloat) ComplexFloat {
    expect(a.real == 1.25) catch @panic("test failure: zig_cmultf 1");
    expect(a.imag == 2.6) catch @panic("test failure: zig_cmultf 2");
    expect(b.real == 11.3) catch @panic("test failure: zig_cmultf 3");
    expect(b.imag == -1.5) catch @panic("test failure: zig_cmultf 4");

    return .{ .real = 1.5, .imag = 13.5 };
}

export fn zig_cmultd(a: ComplexDouble, b: ComplexDouble) ComplexDouble {
    expect(a.real == 1.25) catch @panic("test failure: zig_cmultd 1");
    expect(a.imag == 2.6) catch @panic("test failure: zig_cmultd 2");
    expect(b.real == 11.3) catch @panic("test failure: zig_cmultd 3");
    expect(b.imag == -1.5) catch @panic("test failure: zig_cmultd 4");

    return .{ .real = 1.5, .imag = 13.5 };
}

export fn zig_cmultf_comp(a_r: f32, a_i: f32, b_r: f32, b_i: f32) ComplexFloat {
    expect(a_r == 1.25) catch @panic("test failure: zig_cmultf_comp 1");
    expect(a_i == 2.6) catch @panic("test failure: zig_cmultf_comp 2");
    expect(b_r == 11.3) catch @panic("test failure: zig_cmultf_comp 3");
    expect(b_i == -1.5) catch @panic("test failure: zig_cmultf_comp 4");

    return .{ .real = 1.5, .imag = 13.5 };
}

export fn zig_cmultd_comp(a_r: f64, a_i: f64, b_r: f64, b_i: f64) ComplexDouble {
    expect(a_r == 1.25) catch @panic("test failure: zig_cmultd_comp 1");
    expect(a_i == 2.6) catch @panic("test failure: zig_cmultd_comp 2");
    expect(b_r == 11.3) catch @panic("test failure: zig_cmultd_comp 3");
    expect(b_i == -1.5) catch @panic("test failure: zig_cmultd_comp 4");

    return .{ .real = 1.5, .imag = 13.5 };
}

comptime {
    skip: {
        if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .x86_64) break :skip;
        if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch.isPowerPC64()) break :skip;

        _ = struct {
            export fn zig_ret_vector_2_bool() @Vector(2, bool) {
                return .{
                    false,
                    false,
                };
            }
            export fn zig_vector_2_bool(vec: @Vector(2, bool)) void {
                expect(vec[0] == false) catch @panic("test failure");
                expect(vec[1] == true) catch @panic("test failure");
            }
        };
    }
}

extern fn c_ret_vector_2_bool() @Vector(2, bool);
extern fn c_vector_2_bool(@Vector(2, bool)) void;
extern fn c_test_vector_2_bool() void;

test "@Vector(2, bool)" {
    if (builtin.zig_backend == .stage2_llvm and (builtin.cpu.arch != .powerpc and builtin.cpu.arch != .wasm32)) return error.SkipZigTest;

    const vec = c_ret_vector_2_bool();
    try expect(vec[0] == true);
    try expect(vec[1] == false);
    c_vector_2_bool(.{
        true,
        true,
    });
    c_test_vector_2_bool();
}

comptime {
    skip: {
        if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .x86_64) break :skip;
        if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch.isPowerPC64()) break :skip;

        _ = struct {
            export fn zig_ret_vector_4_bool() @Vector(4, bool) {
                return .{
                    false,
                    true,
                    true,
                    true,
                };
            }
            export fn zig_vector_4_bool(vec: @Vector(4, bool)) void {
                expect(vec[0] == false) catch @panic("test failure");
                expect(vec[1] == false) catch @panic("test failure");
                expect(vec[2] == false) catch @panic("test failure");
                expect(vec[3] == false) catch @panic("test failure");
            }
        };
    }
}

extern fn c_ret_vector_4_bool() @Vector(4, bool);
extern fn c_vector_4_bool(@Vector(4, bool)) void;
extern fn c_test_vector_4_bool() void;

test "@Vector(4, bool)" {
    if (builtin.zig_backend == .stage2_llvm and (builtin.cpu.arch != .powerpc and builtin.cpu.arch != .wasm32)) return error.SkipZigTest;

    const vec = c_ret_vector_4_bool();
    try expect(vec[0] == true);
    try expect(vec[1] == false);
    try expect(vec[2] == true);
    try expect(vec[3] == false);
    c_vector_4_bool(.{
        true,
        true,
        false,
        true,
    });
    c_test_vector_4_bool();
}

comptime {
    skip: {
        if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .x86_64) break :skip;
        if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch.isPowerPC64()) break :skip;

        _ = struct {
            export fn zig_ret_vector_8_bool() @Vector(8, bool) {
                return .{
                    false,
                    false,
                    false,
                    false,
                    true,
                    false,
                    false,
                    false,
                };
            }
            export fn zig_vector_8_bool(vec: @Vector(8, bool)) void {
                expect(vec[0] == true) catch @panic("test failure");
                expect(vec[1] == true) catch @panic("test failure");
                expect(vec[2] == false) catch @panic("test failure");
                expect(vec[3] == true) catch @panic("test failure");
                expect(vec[4] == false) catch @panic("test failure");
                expect(vec[5] == true) catch @panic("test failure");
                expect(vec[6] == true) catch @panic("test failure");
                expect(vec[7] == false) catch @panic("test failure");
            }
        };
    }
}

extern fn c_ret_vector_8_bool() @Vector(8, bool);
extern fn c_vector_8_bool(@Vector(8, bool)) void;
extern fn c_test_vector_8_bool() void;

test "@Vector(8, bool)" {
    if (builtin.zig_backend == .stage2_llvm and (builtin.cpu.arch != .powerpc and builtin.cpu.arch != .wasm32)) return error.SkipZigTest;

    const vec = c_ret_vector_8_bool();
    try expect(vec[0] == false);
    try expect(vec[1] == true);
    try expect(vec[2] == false);
    try expect(vec[3] == false);
    try expect(vec[4] == true);
    try expect(vec[5] == false);
    try expect(vec[6] == false);
    try expect(vec[7] == true);
    c_vector_8_bool(.{
        true,
        false,
        true,
        true,
        true,
        true,
        false,
        true,
    });
    c_test_vector_8_bool();
}

comptime {
    skip: {
        if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .x86_64) break :skip;
        if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch.isPowerPC64()) break :skip;

        _ = struct {
            export fn zig_ret_vector_16_bool() @Vector(16, bool) {
                return .{
                    false,
                    true,
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
                    true,
                    false,
                    false,
                };
            }
            export fn zig_vector_16_bool(vec: @Vector(16, bool)) void {
                expect(vec[0] == true) catch @panic("test failure");
                expect(vec[1] == false) catch @panic("test failure");
                expect(vec[2] == true) catch @panic("test failure");
                expect(vec[3] == true) catch @panic("test failure");
                expect(vec[4] == true) catch @panic("test failure");
                expect(vec[5] == false) catch @panic("test failure");
                expect(vec[6] == false) catch @panic("test failure");
                expect(vec[7] == false) catch @panic("test failure");
                expect(vec[8] == true) catch @panic("test failure");
                expect(vec[9] == true) catch @panic("test failure");
                expect(vec[10] == true) catch @panic("test failure");
                expect(vec[11] == true) catch @panic("test failure");
                expect(vec[12] == false) catch @panic("test failure");
                expect(vec[13] == false) catch @panic("test failure");
                expect(vec[14] == false) catch @panic("test failure");
                expect(vec[15] == true) catch @panic("test failure");
            }
        };
    }
}

extern fn c_ret_vector_16_bool() @Vector(16, bool);
extern fn c_vector_16_bool(@Vector(16, bool)) void;
extern fn c_test_vector_16_bool() void;

test "@Vector(16, bool)" {
    if (builtin.zig_backend == .stage2_llvm and (builtin.cpu.arch != .powerpc and builtin.cpu.arch != .wasm32)) return error.SkipZigTest;

    const vec = c_ret_vector_16_bool();
    try expect(vec[0] == true);
    try expect(vec[1] == true);
    try expect(vec[2] == false);
    try expect(vec[3] == false);
    try expect(vec[4] == false);
    try expect(vec[5] == false);
    try expect(vec[6] == true);
    try expect(vec[7] == false);
    try expect(vec[8] == true);
    try expect(vec[9] == false);
    try expect(vec[10] == false);
    try expect(vec[11] == true);
    try expect(vec[12] == true);
    try expect(vec[13] == false);
    try expect(vec[14] == true);
    try expect(vec[15] == true);
    c_vector_16_bool(.{
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
        false,
        false,
        false,
        false,
    });
    c_test_vector_16_bool();
}

comptime {
    skip: {
        if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .x86_64) break :skip;
        if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch.isPowerPC64()) break :skip;

        _ = struct {
            export fn zig_ret_vector_32_bool() @Vector(32, bool) {
                return .{
                    false,
                    true,
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
                    false,
                    true,
                    false,
                    false,
                    true,
                    false,
                    false,
                    true,
                    true,
                };
            }
            export fn zig_vector_32_bool(vec: @Vector(32, bool)) void {
                expect(vec[0] == false) catch @panic("test failure");
                expect(vec[1] == false) catch @panic("test failure");
                expect(vec[2] == false) catch @panic("test failure");
                expect(vec[3] == true) catch @panic("test failure");
                expect(vec[4] == true) catch @panic("test failure");
                expect(vec[5] == false) catch @panic("test failure");
                expect(vec[6] == false) catch @panic("test failure");
                expect(vec[7] == true) catch @panic("test failure");
                expect(vec[8] == false) catch @panic("test failure");
                expect(vec[9] == true) catch @panic("test failure");
                expect(vec[10] == true) catch @panic("test failure");
                expect(vec[11] == true) catch @panic("test failure");
                expect(vec[12] == false) catch @panic("test failure");
                expect(vec[13] == false) catch @panic("test failure");
                expect(vec[14] == true) catch @panic("test failure");
                expect(vec[15] == true) catch @panic("test failure");
                expect(vec[16] == true) catch @panic("test failure");
                expect(vec[17] == true) catch @panic("test failure");
                expect(vec[18] == true) catch @panic("test failure");
                expect(vec[19] == false) catch @panic("test failure");
                expect(vec[20] == true) catch @panic("test failure");
                expect(vec[21] == true) catch @panic("test failure");
                expect(vec[22] == true) catch @panic("test failure");
                expect(vec[23] == false) catch @panic("test failure");
                expect(vec[24] == false) catch @panic("test failure");
                expect(vec[25] == true) catch @panic("test failure");
                expect(vec[26] == true) catch @panic("test failure");
                expect(vec[27] == false) catch @panic("test failure");
                expect(vec[28] == true) catch @panic("test failure");
                expect(vec[29] == true) catch @panic("test failure");
                expect(vec[30] == false) catch @panic("test failure");
                expect(vec[31] == true) catch @panic("test failure");
            }
        };
    }
}

extern fn c_ret_vector_32_bool() @Vector(32, bool);
extern fn c_vector_32_bool(@Vector(32, bool)) void;
extern fn c_test_vector_32_bool() void;

test "@Vector(32, bool)" {
    if (builtin.zig_backend == .stage2_llvm and (builtin.cpu.arch != .powerpc and builtin.cpu.arch != .wasm32)) return error.SkipZigTest;

    const vec = c_ret_vector_32_bool();
    try expect(vec[0] == true);
    try expect(vec[1] == false);
    try expect(vec[2] == true);
    try expect(vec[3] == true);
    try expect(vec[4] == true);
    try expect(vec[5] == false);
    try expect(vec[6] == true);
    try expect(vec[7] == false);
    try expect(vec[8] == true);
    try expect(vec[9] == true);
    try expect(vec[10] == true);
    try expect(vec[11] == false);
    try expect(vec[12] == true);
    try expect(vec[13] == true);
    try expect(vec[14] == false);
    try expect(vec[15] == false);
    try expect(vec[16] == true);
    try expect(vec[17] == false);
    try expect(vec[18] == false);
    try expect(vec[19] == false);
    try expect(vec[20] == false);
    try expect(vec[21] == true);
    try expect(vec[22] == true);
    try expect(vec[23] == true);
    try expect(vec[24] == false);
    try expect(vec[25] == true);
    try expect(vec[26] == false);
    try expect(vec[27] == false);
    try expect(vec[28] == true);
    try expect(vec[29] == false);
    try expect(vec[30] == false);
    try expect(vec[31] == false);
    c_vector_32_bool(.{
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
        true,
        true,
        true,
        false,
        false,
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
        true,
        true,
        true,
        false,
        true,
        true,
        false,
    });
    c_test_vector_32_bool();
}

comptime {
    skip: {
        if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .x86_64) break :skip;
        if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch.isPowerPC64()) break :skip;

        _ = struct {
            export fn zig_ret_vector_64_bool() @Vector(64, bool) {
                return .{
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
                    true,
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
                    false,
                    false,
                    false,
                    true,
                    false,
                    false,
                    true,
                    false,
                    true,
                    false,
                };
            }
            export fn zig_vector_64_bool(vec: @Vector(64, bool)) void {
                expect(vec[0] == true) catch @panic("test failure");
                expect(vec[1] == true) catch @panic("test failure");
                expect(vec[2] == false) catch @panic("test failure");
                expect(vec[3] == true) catch @panic("test failure");
                expect(vec[4] == false) catch @panic("test failure");
                expect(vec[5] == true) catch @panic("test failure");
                expect(vec[6] == false) catch @panic("test failure");
                expect(vec[7] == false) catch @panic("test failure");
                expect(vec[8] == true) catch @panic("test failure");
                expect(vec[9] == true) catch @panic("test failure");
                expect(vec[10] == true) catch @panic("test failure");
                expect(vec[11] == true) catch @panic("test failure");
                expect(vec[12] == true) catch @panic("test failure");
                expect(vec[13] == true) catch @panic("test failure");
                expect(vec[14] == true) catch @panic("test failure");
                expect(vec[15] == false) catch @panic("test failure");
                expect(vec[16] == false) catch @panic("test failure");
                expect(vec[17] == true) catch @panic("test failure");
                expect(vec[18] == true) catch @panic("test failure");
                expect(vec[19] == false) catch @panic("test failure");
                expect(vec[20] == true) catch @panic("test failure");
                expect(vec[21] == true) catch @panic("test failure");
                expect(vec[22] == true) catch @panic("test failure");
                expect(vec[23] == true) catch @panic("test failure");
                expect(vec[24] == false) catch @panic("test failure");
                expect(vec[25] == false) catch @panic("test failure");
                expect(vec[26] == true) catch @panic("test failure");
                expect(vec[27] == false) catch @panic("test failure");
                expect(vec[28] == false) catch @panic("test failure");
                expect(vec[29] == true) catch @panic("test failure");
                expect(vec[30] == false) catch @panic("test failure");
                expect(vec[31] == true) catch @panic("test failure");
                expect(vec[32] == false) catch @panic("test failure");
                expect(vec[33] == true) catch @panic("test failure");
                expect(vec[34] == true) catch @panic("test failure");
                expect(vec[35] == false) catch @panic("test failure");
                expect(vec[36] == true) catch @panic("test failure");
                expect(vec[37] == true) catch @panic("test failure");
                expect(vec[38] == false) catch @panic("test failure");
                expect(vec[39] == false) catch @panic("test failure");
                expect(vec[40] == true) catch @panic("test failure");
                expect(vec[41] == true) catch @panic("test failure");
                expect(vec[42] == true) catch @panic("test failure");
                expect(vec[43] == true) catch @panic("test failure");
                expect(vec[44] == true) catch @panic("test failure");
                expect(vec[45] == false) catch @panic("test failure");
                expect(vec[46] == true) catch @panic("test failure");
                expect(vec[47] == false) catch @panic("test failure");
                expect(vec[48] == false) catch @panic("test failure");
                expect(vec[49] == false) catch @panic("test failure");
                expect(vec[50] == false) catch @panic("test failure");
                expect(vec[51] == false) catch @panic("test failure");
                expect(vec[52] == true) catch @panic("test failure");
                expect(vec[53] == false) catch @panic("test failure");
                expect(vec[54] == false) catch @panic("test failure");
                expect(vec[55] == true) catch @panic("test failure");
                expect(vec[56] == true) catch @panic("test failure");
                expect(vec[57] == false) catch @panic("test failure");
                expect(vec[58] == false) catch @panic("test failure");
                expect(vec[59] == false) catch @panic("test failure");
                expect(vec[60] == true) catch @panic("test failure");
                expect(vec[61] == true) catch @panic("test failure");
                expect(vec[62] == true) catch @panic("test failure");
                expect(vec[63] == true) catch @panic("test failure");
            }
        };
    }
}

extern fn c_ret_vector_64_bool() @Vector(64, bool);
extern fn c_vector_64_bool(@Vector(64, bool)) void;
extern fn c_test_vector_64_bool() void;

test "@Vector(64, bool)" {
    if (builtin.zig_backend == .stage2_llvm and (builtin.cpu.arch != .powerpc and builtin.cpu.arch != .wasm32)) return error.SkipZigTest;

    const vec = c_ret_vector_64_bool();
    try expect(vec[0] == false);
    try expect(vec[1] == true);
    try expect(vec[2] == false);
    try expect(vec[3] == true);
    try expect(vec[4] == true);
    try expect(vec[5] == true);
    try expect(vec[6] == false);
    try expect(vec[7] == true);
    try expect(vec[8] == true);
    try expect(vec[9] == true);
    try expect(vec[10] == true);
    try expect(vec[11] == true);
    try expect(vec[12] == true);
    try expect(vec[13] == false);
    try expect(vec[14] == true);
    try expect(vec[15] == true);
    try expect(vec[16] == true);
    try expect(vec[17] == false);
    try expect(vec[18] == false);
    try expect(vec[19] == false);
    try expect(vec[20] == true);
    try expect(vec[21] == true);
    try expect(vec[22] == false);
    try expect(vec[23] == true);
    try expect(vec[24] == false);
    try expect(vec[25] == true);
    try expect(vec[26] == false);
    try expect(vec[27] == true);
    try expect(vec[28] == false);
    try expect(vec[29] == true);
    try expect(vec[30] == false);
    try expect(vec[31] == true);
    try expect(vec[32] == false);
    try expect(vec[33] == false);
    try expect(vec[34] == true);
    try expect(vec[35] == true);
    try expect(vec[36] == false);
    try expect(vec[37] == false);
    try expect(vec[38] == false);
    try expect(vec[39] == true);
    try expect(vec[40] == true);
    try expect(vec[41] == true);
    try expect(vec[42] == true);
    try expect(vec[43] == false);
    try expect(vec[44] == false);
    try expect(vec[45] == false);
    try expect(vec[46] == true);
    try expect(vec[47] == true);
    try expect(vec[48] == false);
    try expect(vec[49] == false);
    try expect(vec[50] == true);
    try expect(vec[51] == false);
    try expect(vec[52] == false);
    try expect(vec[53] == false);
    try expect(vec[54] == false);
    try expect(vec[55] == true);
    try expect(vec[56] == false);
    try expect(vec[57] == false);
    try expect(vec[58] == false);
    try expect(vec[59] == true);
    try expect(vec[60] == true);
    try expect(vec[61] == true);
    try expect(vec[62] == true);
    try expect(vec[63] == true);
    c_vector_64_bool(.{
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
        true,
        true,
        true,
        true,
        false,
        false,
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
        false,
    });
    c_test_vector_64_bool();
}

comptime {
    skip: {
        if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .x86_64) break :skip;
        if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch.isPowerPC64()) break :skip;

        _ = struct {
            export fn zig_ret_vector_128_bool() @Vector(128, bool) {
                return .{
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
                    true,
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
                };
            }
            export fn zig_vector_128_bool(vec: @Vector(128, bool)) void {
                expect(vec[0] == true) catch @panic("test failure");
                expect(vec[1] == true) catch @panic("test failure");
                expect(vec[2] == false) catch @panic("test failure");
                expect(vec[3] == true) catch @panic("test failure");
                expect(vec[4] == true) catch @panic("test failure");
                expect(vec[5] == false) catch @panic("test failure");
                expect(vec[6] == false) catch @panic("test failure");
                expect(vec[7] == true) catch @panic("test failure");
                expect(vec[8] == true) catch @panic("test failure");
                expect(vec[9] == true) catch @panic("test failure");
                expect(vec[10] == true) catch @panic("test failure");
                expect(vec[11] == true) catch @panic("test failure");
                expect(vec[12] == false) catch @panic("test failure");
                expect(vec[13] == false) catch @panic("test failure");
                expect(vec[14] == false) catch @panic("test failure");
                expect(vec[15] == true) catch @panic("test failure");
                expect(vec[16] == false) catch @panic("test failure");
                expect(vec[17] == true) catch @panic("test failure");
                expect(vec[18] == false) catch @panic("test failure");
                expect(vec[19] == false) catch @panic("test failure");
                expect(vec[20] == true) catch @panic("test failure");
                expect(vec[21] == false) catch @panic("test failure");
                expect(vec[22] == true) catch @panic("test failure");
                expect(vec[23] == false) catch @panic("test failure");
                expect(vec[24] == false) catch @panic("test failure");
                expect(vec[25] == false) catch @panic("test failure");
                expect(vec[26] == true) catch @panic("test failure");
                expect(vec[27] == false) catch @panic("test failure");
                expect(vec[28] == true) catch @panic("test failure");
                expect(vec[29] == true) catch @panic("test failure");
                expect(vec[30] == false) catch @panic("test failure");
                expect(vec[31] == true) catch @panic("test failure");
                expect(vec[32] == false) catch @panic("test failure");
                expect(vec[33] == true) catch @panic("test failure");
                expect(vec[34] == true) catch @panic("test failure");
                expect(vec[35] == false) catch @panic("test failure");
                expect(vec[36] == false) catch @panic("test failure");
                expect(vec[37] == false) catch @panic("test failure");
                expect(vec[38] == false) catch @panic("test failure");
                expect(vec[39] == true) catch @panic("test failure");
                expect(vec[40] == true) catch @panic("test failure");
                expect(vec[41] == false) catch @panic("test failure");
                expect(vec[42] == true) catch @panic("test failure");
                expect(vec[43] == false) catch @panic("test failure");
                expect(vec[44] == false) catch @panic("test failure");
                expect(vec[45] == true) catch @panic("test failure");
                expect(vec[46] == false) catch @panic("test failure");
                expect(vec[47] == false) catch @panic("test failure");
                expect(vec[48] == true) catch @panic("test failure");
                expect(vec[49] == true) catch @panic("test failure");
                expect(vec[50] == false) catch @panic("test failure");
                expect(vec[51] == false) catch @panic("test failure");
                expect(vec[52] == true) catch @panic("test failure");
                expect(vec[53] == false) catch @panic("test failure");
                expect(vec[54] == false) catch @panic("test failure");
                expect(vec[55] == true) catch @panic("test failure");
                expect(vec[56] == true) catch @panic("test failure");
                expect(vec[57] == true) catch @panic("test failure");
                expect(vec[58] == true) catch @panic("test failure");
                expect(vec[59] == true) catch @panic("test failure");
                expect(vec[60] == true) catch @panic("test failure");
                expect(vec[61] == true) catch @panic("test failure");
                expect(vec[62] == true) catch @panic("test failure");
                expect(vec[63] == false) catch @panic("test failure");
                expect(vec[64] == false) catch @panic("test failure");
                expect(vec[65] == true) catch @panic("test failure");
                expect(vec[66] == false) catch @panic("test failure");
                expect(vec[67] == true) catch @panic("test failure");
                expect(vec[68] == true) catch @panic("test failure");
                expect(vec[69] == true) catch @panic("test failure");
                expect(vec[70] == true) catch @panic("test failure");
                expect(vec[71] == false) catch @panic("test failure");
                expect(vec[72] == false) catch @panic("test failure");
                expect(vec[73] == false) catch @panic("test failure");
                expect(vec[74] == true) catch @panic("test failure");
                expect(vec[75] == true) catch @panic("test failure");
                expect(vec[76] == false) catch @panic("test failure");
                expect(vec[77] == true) catch @panic("test failure");
                expect(vec[78] == true) catch @panic("test failure");
                expect(vec[79] == true) catch @panic("test failure");
                expect(vec[80] == true) catch @panic("test failure");
                expect(vec[81] == false) catch @panic("test failure");
                expect(vec[82] == true) catch @panic("test failure");
                expect(vec[83] == true) catch @panic("test failure");
                expect(vec[84] == true) catch @panic("test failure");
                expect(vec[85] == true) catch @panic("test failure");
                expect(vec[86] == true) catch @panic("test failure");
                expect(vec[87] == true) catch @panic("test failure");
                expect(vec[88] == false) catch @panic("test failure");
                expect(vec[89] == true) catch @panic("test failure");
                expect(vec[90] == true) catch @panic("test failure");
                expect(vec[91] == true) catch @panic("test failure");
                expect(vec[92] == true) catch @panic("test failure");
                expect(vec[93] == true) catch @panic("test failure");
                expect(vec[94] == true) catch @panic("test failure");
                expect(vec[95] == false) catch @panic("test failure");
                expect(vec[96] == false) catch @panic("test failure");
                expect(vec[97] == false) catch @panic("test failure");
                expect(vec[98] == true) catch @panic("test failure");
                expect(vec[99] == true) catch @panic("test failure");
                expect(vec[100] == true) catch @panic("test failure");
                expect(vec[101] == true) catch @panic("test failure");
                expect(vec[102] == true) catch @panic("test failure");
                expect(vec[103] == true) catch @panic("test failure");
                expect(vec[104] == true) catch @panic("test failure");
                expect(vec[105] == false) catch @panic("test failure");
                expect(vec[106] == false) catch @panic("test failure");
                expect(vec[107] == false) catch @panic("test failure");
                expect(vec[108] == false) catch @panic("test failure");
                expect(vec[109] == false) catch @panic("test failure");
                expect(vec[110] == true) catch @panic("test failure");
                expect(vec[111] == true) catch @panic("test failure");
                expect(vec[112] == true) catch @panic("test failure");
                expect(vec[113] == false) catch @panic("test failure");
                expect(vec[114] == false) catch @panic("test failure");
                expect(vec[115] == false) catch @panic("test failure");
                expect(vec[116] == false) catch @panic("test failure");
                expect(vec[117] == false) catch @panic("test failure");
                expect(vec[118] == true) catch @panic("test failure");
                expect(vec[119] == false) catch @panic("test failure");
                expect(vec[120] == false) catch @panic("test failure");
                expect(vec[121] == false) catch @panic("test failure");
                expect(vec[122] == false) catch @panic("test failure");
                expect(vec[123] == true) catch @panic("test failure");
                expect(vec[124] == true) catch @panic("test failure");
                expect(vec[125] == false) catch @panic("test failure");
                expect(vec[126] == true) catch @panic("test failure");
                expect(vec[127] == false) catch @panic("test failure");
            }
        };
    }
}

extern fn c_ret_vector_128_bool() @Vector(128, bool);
extern fn c_vector_128_bool(@Vector(128, bool)) void;
extern fn c_test_vector_128_bool() void;

test "@Vector(128, bool)" {
    if (builtin.zig_backend == .stage2_llvm and (builtin.cpu.arch != .powerpc and builtin.cpu.arch != .wasm32)) return error.SkipZigTest;

    const vec = c_ret_vector_128_bool();
    try expect(vec[0] == false);
    try expect(vec[1] == true);
    try expect(vec[2] == true);
    try expect(vec[3] == false);
    try expect(vec[4] == true);
    try expect(vec[5] == false);
    try expect(vec[6] == false);
    try expect(vec[7] == true);
    try expect(vec[8] == true);
    try expect(vec[9] == false);
    try expect(vec[10] == true);
    try expect(vec[11] == false);
    try expect(vec[12] == false);
    try expect(vec[13] == false);
    try expect(vec[14] == true);
    try expect(vec[15] == false);
    try expect(vec[16] == true);
    try expect(vec[17] == false);
    try expect(vec[18] == false);
    try expect(vec[19] == true);
    try expect(vec[20] == false);
    try expect(vec[21] == true);
    try expect(vec[22] == false);
    try expect(vec[23] == false);
    try expect(vec[24] == false);
    try expect(vec[25] == true);
    try expect(vec[26] == true);
    try expect(vec[27] == true);
    try expect(vec[28] == false);
    try expect(vec[29] == false);
    try expect(vec[30] == false);
    try expect(vec[31] == false);
    try expect(vec[32] == true);
    try expect(vec[33] == true);
    try expect(vec[34] == true);
    try expect(vec[35] == false);
    try expect(vec[36] == true);
    try expect(vec[37] == true);
    try expect(vec[38] == false);
    try expect(vec[39] == false);
    try expect(vec[40] == false);
    try expect(vec[41] == false);
    try expect(vec[42] == true);
    try expect(vec[43] == true);
    try expect(vec[44] == true);
    try expect(vec[45] == false);
    try expect(vec[46] == false);
    try expect(vec[47] == false);
    try expect(vec[48] == false);
    try expect(vec[49] == true);
    try expect(vec[50] == false);
    try expect(vec[51] == false);
    try expect(vec[52] == true);
    try expect(vec[53] == false);
    try expect(vec[54] == false);
    try expect(vec[55] == false);
    try expect(vec[56] == false);
    try expect(vec[57] == false);
    try expect(vec[58] == true);
    try expect(vec[59] == true);
    try expect(vec[60] == true);
    try expect(vec[61] == false);
    try expect(vec[62] == true);
    try expect(vec[63] == true);
    try expect(vec[64] == false);
    try expect(vec[65] == false);
    try expect(vec[66] == false);
    try expect(vec[67] == false);
    try expect(vec[68] == false);
    try expect(vec[69] == false);
    try expect(vec[70] == false);
    try expect(vec[71] == false);
    try expect(vec[72] == true);
    try expect(vec[73] == true);
    try expect(vec[74] == true);
    try expect(vec[75] == true);
    try expect(vec[76] == true);
    try expect(vec[77] == false);
    try expect(vec[78] == false);
    try expect(vec[79] == false);
    try expect(vec[80] == false);
    try expect(vec[81] == false);
    try expect(vec[82] == false);
    try expect(vec[83] == true);
    try expect(vec[84] == false);
    try expect(vec[85] == true);
    try expect(vec[86] == false);
    try expect(vec[87] == true);
    try expect(vec[88] == false);
    try expect(vec[89] == true);
    try expect(vec[90] == false);
    try expect(vec[91] == true);
    try expect(vec[92] == true);
    try expect(vec[93] == true);
    try expect(vec[94] == true);
    try expect(vec[95] == false);
    try expect(vec[96] == false);
    try expect(vec[97] == true);
    try expect(vec[98] == false);
    try expect(vec[99] == false);
    try expect(vec[100] == true);
    try expect(vec[101] == true);
    try expect(vec[102] == true);
    try expect(vec[103] == true);
    try expect(vec[104] == false);
    try expect(vec[105] == true);
    try expect(vec[106] == true);
    try expect(vec[107] == true);
    try expect(vec[108] == false);
    try expect(vec[109] == false);
    try expect(vec[110] == true);
    try expect(vec[111] == false);
    try expect(vec[112] == false);
    try expect(vec[113] == true);
    try expect(vec[114] == true);
    try expect(vec[115] == false);
    try expect(vec[116] == true);
    try expect(vec[117] == false);
    try expect(vec[118] == true);
    try expect(vec[119] == true);
    try expect(vec[120] == true);
    try expect(vec[121] == true);
    try expect(vec[122] == true);
    try expect(vec[123] == false);
    try expect(vec[124] == false);
    try expect(vec[125] == true);
    try expect(vec[126] == false);
    try expect(vec[127] == true);
    c_vector_128_bool(.{
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
        false,
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
        true,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
    });
    c_test_vector_128_bool();
}

comptime {
    skip: {
        if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .x86_64) break :skip;
        if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch.isPowerPC64()) break :skip;

        _ = struct {
            export fn zig_ret_vector_256_bool() @Vector(256, bool) {
                return .{
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
                    true,
                    false,
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
                    true,
                    true,
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
                    false,
                    true,
                    false,
                    true,
                };
            }
            export fn zig_vector_256_bool(vec: @Vector(256, bool)) void {
                expect(vec[0] == false) catch @panic("test failure");
                expect(vec[1] == false) catch @panic("test failure");
                expect(vec[2] == false) catch @panic("test failure");
                expect(vec[3] == false) catch @panic("test failure");
                expect(vec[4] == true) catch @panic("test failure");
                expect(vec[5] == true) catch @panic("test failure");
                expect(vec[6] == false) catch @panic("test failure");
                expect(vec[7] == false) catch @panic("test failure");
                expect(vec[8] == false) catch @panic("test failure");
                expect(vec[9] == true) catch @panic("test failure");
                expect(vec[10] == true) catch @panic("test failure");
                expect(vec[11] == false) catch @panic("test failure");
                expect(vec[12] == true) catch @panic("test failure");
                expect(vec[13] == false) catch @panic("test failure");
                expect(vec[14] == false) catch @panic("test failure");
                expect(vec[15] == false) catch @panic("test failure");
                expect(vec[16] == false) catch @panic("test failure");
                expect(vec[17] == true) catch @panic("test failure");
                expect(vec[18] == true) catch @panic("test failure");
                expect(vec[19] == true) catch @panic("test failure");
                expect(vec[20] == false) catch @panic("test failure");
                expect(vec[21] == true) catch @panic("test failure");
                expect(vec[22] == true) catch @panic("test failure");
                expect(vec[23] == false) catch @panic("test failure");
                expect(vec[24] == true) catch @panic("test failure");
                expect(vec[25] == false) catch @panic("test failure");
                expect(vec[26] == false) catch @panic("test failure");
                expect(vec[27] == true) catch @panic("test failure");
                expect(vec[28] == true) catch @panic("test failure");
                expect(vec[29] == true) catch @panic("test failure");
                expect(vec[30] == false) catch @panic("test failure");
                expect(vec[31] == true) catch @panic("test failure");
                expect(vec[32] == false) catch @panic("test failure");
                expect(vec[33] == true) catch @panic("test failure");
                expect(vec[34] == false) catch @panic("test failure");
                expect(vec[35] == false) catch @panic("test failure");
                expect(vec[36] == false) catch @panic("test failure");
                expect(vec[37] == true) catch @panic("test failure");
                expect(vec[38] == false) catch @panic("test failure");
                expect(vec[39] == false) catch @panic("test failure");
                expect(vec[40] == true) catch @panic("test failure");
                expect(vec[41] == true) catch @panic("test failure");
                expect(vec[42] == false) catch @panic("test failure");
                expect(vec[43] == true) catch @panic("test failure");
                expect(vec[44] == true) catch @panic("test failure");
                expect(vec[45] == false) catch @panic("test failure");
                expect(vec[46] == true) catch @panic("test failure");
                expect(vec[47] == false) catch @panic("test failure");
                expect(vec[48] == true) catch @panic("test failure");
                expect(vec[49] == false) catch @panic("test failure");
                expect(vec[50] == true) catch @panic("test failure");
                expect(vec[51] == false) catch @panic("test failure");
                expect(vec[52] == true) catch @panic("test failure");
                expect(vec[53] == true) catch @panic("test failure");
                expect(vec[54] == true) catch @panic("test failure");
                expect(vec[55] == false) catch @panic("test failure");
                expect(vec[56] == false) catch @panic("test failure");
                expect(vec[57] == true) catch @panic("test failure");
                expect(vec[58] == true) catch @panic("test failure");
                expect(vec[59] == false) catch @panic("test failure");
                expect(vec[60] == false) catch @panic("test failure");
                expect(vec[61] == true) catch @panic("test failure");
                expect(vec[62] == true) catch @panic("test failure");
                expect(vec[63] == false) catch @panic("test failure");
                expect(vec[64] == false) catch @panic("test failure");
                expect(vec[65] == false) catch @panic("test failure");
                expect(vec[66] == true) catch @panic("test failure");
                expect(vec[67] == true) catch @panic("test failure");
                expect(vec[68] == false) catch @panic("test failure");
                expect(vec[69] == true) catch @panic("test failure");
                expect(vec[70] == false) catch @panic("test failure");
                expect(vec[71] == true) catch @panic("test failure");
                expect(vec[72] == false) catch @panic("test failure");
                expect(vec[73] == true) catch @panic("test failure");
                expect(vec[74] == false) catch @panic("test failure");
                expect(vec[75] == false) catch @panic("test failure");
                expect(vec[76] == true) catch @panic("test failure");
                expect(vec[77] == false) catch @panic("test failure");
                expect(vec[78] == false) catch @panic("test failure");
                expect(vec[79] == false) catch @panic("test failure");
                expect(vec[80] == false) catch @panic("test failure");
                expect(vec[81] == false) catch @panic("test failure");
                expect(vec[82] == true) catch @panic("test failure");
                expect(vec[83] == false) catch @panic("test failure");
                expect(vec[84] == false) catch @panic("test failure");
                expect(vec[85] == false) catch @panic("test failure");
                expect(vec[86] == true) catch @panic("test failure");
                expect(vec[87] == true) catch @panic("test failure");
                expect(vec[88] == true) catch @panic("test failure");
                expect(vec[89] == false) catch @panic("test failure");
                expect(vec[90] == true) catch @panic("test failure");
                expect(vec[91] == false) catch @panic("test failure");
                expect(vec[92] == true) catch @panic("test failure");
                expect(vec[93] == false) catch @panic("test failure");
                expect(vec[94] == true) catch @panic("test failure");
                expect(vec[95] == true) catch @panic("test failure");
                expect(vec[96] == true) catch @panic("test failure");
                expect(vec[97] == true) catch @panic("test failure");
                expect(vec[98] == false) catch @panic("test failure");
                expect(vec[99] == true) catch @panic("test failure");
                expect(vec[100] == false) catch @panic("test failure");
                expect(vec[101] == true) catch @panic("test failure");
                expect(vec[102] == true) catch @panic("test failure");
                expect(vec[103] == false) catch @panic("test failure");
                expect(vec[104] == false) catch @panic("test failure");
                expect(vec[105] == true) catch @panic("test failure");
                expect(vec[106] == false) catch @panic("test failure");
                expect(vec[107] == true) catch @panic("test failure");
                expect(vec[108] == false) catch @panic("test failure");
                expect(vec[109] == false) catch @panic("test failure");
                expect(vec[110] == false) catch @panic("test failure");
                expect(vec[111] == false) catch @panic("test failure");
                expect(vec[112] == false) catch @panic("test failure");
                expect(vec[113] == false) catch @panic("test failure");
                expect(vec[114] == false) catch @panic("test failure");
                expect(vec[115] == false) catch @panic("test failure");
                expect(vec[116] == false) catch @panic("test failure");
                expect(vec[117] == false) catch @panic("test failure");
                expect(vec[118] == false) catch @panic("test failure");
                expect(vec[119] == false) catch @panic("test failure");
                expect(vec[120] == false) catch @panic("test failure");
                expect(vec[121] == false) catch @panic("test failure");
                expect(vec[122] == true) catch @panic("test failure");
                expect(vec[123] == true) catch @panic("test failure");
                expect(vec[124] == false) catch @panic("test failure");
                expect(vec[125] == false) catch @panic("test failure");
                expect(vec[126] == false) catch @panic("test failure");
                expect(vec[127] == true) catch @panic("test failure");
                expect(vec[128] == true) catch @panic("test failure");
                expect(vec[129] == true) catch @panic("test failure");
                expect(vec[130] == true) catch @panic("test failure");
                expect(vec[131] == false) catch @panic("test failure");
                expect(vec[132] == false) catch @panic("test failure");
                expect(vec[133] == false) catch @panic("test failure");
                expect(vec[134] == true) catch @panic("test failure");
                expect(vec[135] == true) catch @panic("test failure");
                expect(vec[136] == false) catch @panic("test failure");
                expect(vec[137] == false) catch @panic("test failure");
                expect(vec[138] == true) catch @panic("test failure");
                expect(vec[139] == true) catch @panic("test failure");
                expect(vec[140] == true) catch @panic("test failure");
                expect(vec[141] == true) catch @panic("test failure");
                expect(vec[142] == true) catch @panic("test failure");
                expect(vec[143] == false) catch @panic("test failure");
                expect(vec[144] == true) catch @panic("test failure");
                expect(vec[145] == true) catch @panic("test failure");
                expect(vec[146] == true) catch @panic("test failure");
                expect(vec[147] == false) catch @panic("test failure");
                expect(vec[148] == false) catch @panic("test failure");
                expect(vec[149] == false) catch @panic("test failure");
                expect(vec[150] == false) catch @panic("test failure");
                expect(vec[151] == false) catch @panic("test failure");
                expect(vec[152] == false) catch @panic("test failure");
                expect(vec[153] == false) catch @panic("test failure");
                expect(vec[154] == true) catch @panic("test failure");
                expect(vec[155] == false) catch @panic("test failure");
                expect(vec[156] == false) catch @panic("test failure");
                expect(vec[157] == false) catch @panic("test failure");
                expect(vec[158] == true) catch @panic("test failure");
                expect(vec[159] == true) catch @panic("test failure");
                expect(vec[160] == false) catch @panic("test failure");
                expect(vec[161] == true) catch @panic("test failure");
                expect(vec[162] == false) catch @panic("test failure");
                expect(vec[163] == false) catch @panic("test failure");
                expect(vec[164] == false) catch @panic("test failure");
                expect(vec[165] == true) catch @panic("test failure");
                expect(vec[166] == false) catch @panic("test failure");
                expect(vec[167] == true) catch @panic("test failure");
                expect(vec[168] == false) catch @panic("test failure");
                expect(vec[169] == false) catch @panic("test failure");
                expect(vec[170] == false) catch @panic("test failure");
                expect(vec[171] == false) catch @panic("test failure");
                expect(vec[172] == true) catch @panic("test failure");
                expect(vec[173] == true) catch @panic("test failure");
                expect(vec[174] == true) catch @panic("test failure");
                expect(vec[175] == true) catch @panic("test failure");
                expect(vec[176] == true) catch @panic("test failure");
                expect(vec[177] == true) catch @panic("test failure");
                expect(vec[178] == false) catch @panic("test failure");
                expect(vec[179] == true) catch @panic("test failure");
                expect(vec[180] == true) catch @panic("test failure");
                expect(vec[181] == false) catch @panic("test failure");
                expect(vec[182] == true) catch @panic("test failure");
                expect(vec[183] == false) catch @panic("test failure");
                expect(vec[184] == true) catch @panic("test failure");
                expect(vec[185] == false) catch @panic("test failure");
                expect(vec[186] == true) catch @panic("test failure");
                expect(vec[187] == false) catch @panic("test failure");
                expect(vec[188] == true) catch @panic("test failure");
                expect(vec[189] == false) catch @panic("test failure");
                expect(vec[190] == false) catch @panic("test failure");
                expect(vec[191] == false) catch @panic("test failure");
                expect(vec[192] == false) catch @panic("test failure");
                expect(vec[193] == true) catch @panic("test failure");
                expect(vec[194] == true) catch @panic("test failure");
                expect(vec[195] == true) catch @panic("test failure");
                expect(vec[196] == false) catch @panic("test failure");
                expect(vec[197] == false) catch @panic("test failure");
                expect(vec[198] == true) catch @panic("test failure");
                expect(vec[199] == false) catch @panic("test failure");
                expect(vec[200] == false) catch @panic("test failure");
                expect(vec[201] == true) catch @panic("test failure");
                expect(vec[202] == true) catch @panic("test failure");
                expect(vec[203] == false) catch @panic("test failure");
                expect(vec[204] == true) catch @panic("test failure");
                expect(vec[205] == false) catch @panic("test failure");
                expect(vec[206] == true) catch @panic("test failure");
                expect(vec[207] == false) catch @panic("test failure");
                expect(vec[208] == false) catch @panic("test failure");
                expect(vec[209] == false) catch @panic("test failure");
                expect(vec[210] == true) catch @panic("test failure");
                expect(vec[211] == true) catch @panic("test failure");
                expect(vec[212] == false) catch @panic("test failure");
                expect(vec[213] == false) catch @panic("test failure");
                expect(vec[214] == false) catch @panic("test failure");
                expect(vec[215] == true) catch @panic("test failure");
                expect(vec[216] == false) catch @panic("test failure");
                expect(vec[217] == true) catch @panic("test failure");
                expect(vec[218] == true) catch @panic("test failure");
                expect(vec[219] == true) catch @panic("test failure");
                expect(vec[220] == false) catch @panic("test failure");
                expect(vec[221] == true) catch @panic("test failure");
                expect(vec[222] == false) catch @panic("test failure");
                expect(vec[223] == true) catch @panic("test failure");
                expect(vec[224] == false) catch @panic("test failure");
                expect(vec[225] == false) catch @panic("test failure");
                expect(vec[226] == false) catch @panic("test failure");
                expect(vec[227] == true) catch @panic("test failure");
                expect(vec[228] == true) catch @panic("test failure");
                expect(vec[229] == false) catch @panic("test failure");
                expect(vec[230] == false) catch @panic("test failure");
                expect(vec[231] == false) catch @panic("test failure");
                expect(vec[232] == false) catch @panic("test failure");
                expect(vec[233] == false) catch @panic("test failure");
                expect(vec[234] == true) catch @panic("test failure");
                expect(vec[235] == false) catch @panic("test failure");
                expect(vec[236] == false) catch @panic("test failure");
                expect(vec[237] == false) catch @panic("test failure");
                expect(vec[238] == true) catch @panic("test failure");
                expect(vec[239] == false) catch @panic("test failure");
                expect(vec[240] == true) catch @panic("test failure");
                expect(vec[241] == true) catch @panic("test failure");
                expect(vec[242] == true) catch @panic("test failure");
                expect(vec[243] == false) catch @panic("test failure");
                expect(vec[244] == false) catch @panic("test failure");
                expect(vec[245] == true) catch @panic("test failure");
                expect(vec[246] == false) catch @panic("test failure");
                expect(vec[247] == false) catch @panic("test failure");
                expect(vec[248] == false) catch @panic("test failure");
                expect(vec[249] == true) catch @panic("test failure");
                expect(vec[250] == false) catch @panic("test failure");
                expect(vec[251] == false) catch @panic("test failure");
                expect(vec[252] == true) catch @panic("test failure");
                expect(vec[253] == true) catch @panic("test failure");
                expect(vec[254] == true) catch @panic("test failure");
                expect(vec[255] == true) catch @panic("test failure");
            }
        };
    }
}

extern fn c_ret_vector_256_bool() @Vector(256, bool);
extern fn c_vector_256_bool(@Vector(256, bool)) void;
extern fn c_test_vector_256_bool() void;

test "@Vector(256, bool)" {
    if (builtin.zig_backend == .stage2_llvm and (builtin.cpu.arch != .powerpc and builtin.cpu.arch != .wasm32)) return error.SkipZigTest;

    const vec = c_ret_vector_256_bool();
    try expect(vec[0] == true);
    try expect(vec[1] == false);
    try expect(vec[2] == true);
    try expect(vec[3] == true);
    try expect(vec[4] == false);
    try expect(vec[5] == false);
    try expect(vec[6] == false);
    try expect(vec[7] == false);
    try expect(vec[8] == false);
    try expect(vec[9] == true);
    try expect(vec[10] == false);
    try expect(vec[11] == true);
    try expect(vec[12] == false);
    try expect(vec[13] == true);
    try expect(vec[14] == false);
    try expect(vec[15] == false);
    try expect(vec[16] == true);
    try expect(vec[17] == true);
    try expect(vec[18] == true);
    try expect(vec[19] == false);
    try expect(vec[20] == false);
    try expect(vec[21] == false);
    try expect(vec[22] == true);
    try expect(vec[23] == false);
    try expect(vec[24] == true);
    try expect(vec[25] == false);
    try expect(vec[26] == false);
    try expect(vec[27] == true);
    try expect(vec[28] == true);
    try expect(vec[29] == true);
    try expect(vec[30] == false);
    try expect(vec[31] == false);
    try expect(vec[32] == true);
    try expect(vec[33] == true);
    try expect(vec[34] == true);
    try expect(vec[35] == false);
    try expect(vec[36] == true);
    try expect(vec[37] == true);
    try expect(vec[38] == true);
    try expect(vec[39] == false);
    try expect(vec[40] == true);
    try expect(vec[41] == false);
    try expect(vec[42] == true);
    try expect(vec[43] == true);
    try expect(vec[44] == false);
    try expect(vec[45] == true);
    try expect(vec[46] == false);
    try expect(vec[47] == true);
    try expect(vec[48] == true);
    try expect(vec[49] == false);
    try expect(vec[50] == false);
    try expect(vec[51] == true);
    try expect(vec[52] == true);
    try expect(vec[53] == false);
    try expect(vec[54] == false);
    try expect(vec[55] == true);
    try expect(vec[56] == false);
    try expect(vec[57] == true);
    try expect(vec[58] == true);
    try expect(vec[59] == true);
    try expect(vec[60] == false);
    try expect(vec[61] == true);
    try expect(vec[62] == true);
    try expect(vec[63] == false);
    try expect(vec[64] == true);
    try expect(vec[65] == true);
    try expect(vec[66] == false);
    try expect(vec[67] == true);
    try expect(vec[68] == false);
    try expect(vec[69] == true);
    try expect(vec[70] == true);
    try expect(vec[71] == true);
    try expect(vec[72] == false);
    try expect(vec[73] == true);
    try expect(vec[74] == true);
    try expect(vec[75] == false);
    try expect(vec[76] == true);
    try expect(vec[77] == true);
    try expect(vec[78] == true);
    try expect(vec[79] == true);
    try expect(vec[80] == false);
    try expect(vec[81] == true);
    try expect(vec[82] == false);
    try expect(vec[83] == true);
    try expect(vec[84] == true);
    try expect(vec[85] == true);
    try expect(vec[86] == false);
    try expect(vec[87] == true);
    try expect(vec[88] == false);
    try expect(vec[89] == true);
    try expect(vec[90] == false);
    try expect(vec[91] == false);
    try expect(vec[92] == true);
    try expect(vec[93] == false);
    try expect(vec[94] == false);
    try expect(vec[95] == false);
    try expect(vec[96] == true);
    try expect(vec[97] == true);
    try expect(vec[98] == false);
    try expect(vec[99] == false);
    try expect(vec[100] == false);
    try expect(vec[101] == true);
    try expect(vec[102] == true);
    try expect(vec[103] == true);
    try expect(vec[104] == false);
    try expect(vec[105] == false);
    try expect(vec[106] == false);
    try expect(vec[107] == true);
    try expect(vec[108] == false);
    try expect(vec[109] == true);
    try expect(vec[110] == true);
    try expect(vec[111] == true);
    try expect(vec[112] == true);
    try expect(vec[113] == true);
    try expect(vec[114] == true);
    try expect(vec[115] == true);
    try expect(vec[116] == true);
    try expect(vec[117] == false);
    try expect(vec[118] == true);
    try expect(vec[119] == false);
    try expect(vec[120] == true);
    try expect(vec[121] == false);
    try expect(vec[122] == false);
    try expect(vec[123] == true);
    try expect(vec[124] == true);
    try expect(vec[125] == false);
    try expect(vec[126] == true);
    try expect(vec[127] == false);
    try expect(vec[128] == false);
    try expect(vec[129] == false);
    try expect(vec[130] == false);
    try expect(vec[131] == true);
    try expect(vec[132] == false);
    try expect(vec[133] == false);
    try expect(vec[134] == true);
    try expect(vec[135] == false);
    try expect(vec[136] == false);
    try expect(vec[137] == false);
    try expect(vec[138] == false);
    try expect(vec[139] == false);
    try expect(vec[140] == false);
    try expect(vec[141] == true);
    try expect(vec[142] == false);
    try expect(vec[143] == true);
    try expect(vec[144] == false);
    try expect(vec[145] == true);
    try expect(vec[146] == true);
    try expect(vec[147] == true);
    try expect(vec[148] == false);
    try expect(vec[149] == true);
    try expect(vec[150] == true);
    try expect(vec[151] == false);
    try expect(vec[152] == true);
    try expect(vec[153] == true);
    try expect(vec[154] == false);
    try expect(vec[155] == true);
    try expect(vec[156] == true);
    try expect(vec[157] == true);
    try expect(vec[158] == true);
    try expect(vec[159] == true);
    try expect(vec[160] == true);
    try expect(vec[161] == true);
    try expect(vec[162] == false);
    try expect(vec[163] == false);
    try expect(vec[164] == false);
    try expect(vec[165] == true);
    try expect(vec[166] == false);
    try expect(vec[167] == false);
    try expect(vec[168] == true);
    try expect(vec[169] == false);
    try expect(vec[170] == true);
    try expect(vec[171] == true);
    try expect(vec[172] == true);
    try expect(vec[173] == false);
    try expect(vec[174] == false);
    try expect(vec[175] == true);
    try expect(vec[176] == true);
    try expect(vec[177] == true);
    try expect(vec[178] == true);
    try expect(vec[179] == false);
    try expect(vec[180] == true);
    try expect(vec[181] == true);
    try expect(vec[182] == false);
    try expect(vec[183] == true);
    try expect(vec[184] == false);
    try expect(vec[185] == false);
    try expect(vec[186] == false);
    try expect(vec[187] == true);
    try expect(vec[188] == true);
    try expect(vec[189] == true);
    try expect(vec[190] == true);
    try expect(vec[191] == true);
    try expect(vec[192] == true);
    try expect(vec[193] == true);
    try expect(vec[194] == true);
    try expect(vec[195] == false);
    try expect(vec[196] == false);
    try expect(vec[197] == true);
    try expect(vec[198] == false);
    try expect(vec[199] == false);
    try expect(vec[200] == false);
    try expect(vec[201] == true);
    try expect(vec[202] == true);
    try expect(vec[203] == true);
    try expect(vec[204] == true);
    try expect(vec[205] == true);
    try expect(vec[206] == true);
    try expect(vec[207] == false);
    try expect(vec[208] == false);
    try expect(vec[209] == false);
    try expect(vec[210] == true);
    try expect(vec[211] == true);
    try expect(vec[212] == true);
    try expect(vec[213] == false);
    try expect(vec[214] == true);
    try expect(vec[215] == false);
    try expect(vec[216] == true);
    try expect(vec[217] == false);
    try expect(vec[218] == true);
    try expect(vec[219] == false);
    try expect(vec[220] == true);
    try expect(vec[221] == true);
    try expect(vec[222] == true);
    try expect(vec[223] == false);
    try expect(vec[224] == true);
    try expect(vec[225] == false);
    try expect(vec[226] == true);
    try expect(vec[227] == false);
    try expect(vec[228] == true);
    try expect(vec[229] == false);
    try expect(vec[230] == true);
    try expect(vec[231] == false);
    try expect(vec[232] == false);
    try expect(vec[233] == true);
    try expect(vec[234] == false);
    try expect(vec[235] == true);
    try expect(vec[236] == true);
    try expect(vec[237] == false);
    try expect(vec[238] == false);
    try expect(vec[239] == true);
    try expect(vec[240] == false);
    try expect(vec[241] == false);
    try expect(vec[242] == false);
    try expect(vec[243] == true);
    try expect(vec[244] == true);
    try expect(vec[245] == false);
    try expect(vec[246] == false);
    try expect(vec[247] == false);
    try expect(vec[248] == false);
    try expect(vec[249] == false);
    try expect(vec[250] == true);
    try expect(vec[251] == false);
    try expect(vec[252] == true);
    try expect(vec[253] == false);
    try expect(vec[254] == false);
    try expect(vec[255] == false);
    if (!builtin.target.cpu.arch.isWasm()) c_vector_256_bool(.{
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
        true,
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
        true,
        false,
        true,
        true,
        false,
        true,
        true,
        true,
        false,
    });
    c_test_vector_512_bool();
}

comptime {
    skip: {
        if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .x86_64) break :skip;
        if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch.isPowerPC64()) break :skip;

        _ = struct {
            export fn zig_ret_vector_512_bool() @Vector(512, bool) {
                return .{
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
                    true,
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
                    true,
                    true,
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
                    true,
                    true,
                    false,
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
                    true,
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
                    false,
                    true,
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
                    false,
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
                    false,
                    false,
                    true,
                    true,
                    false,
                    false,
                };
            }
            export fn zig_vector_512_bool(vec: @Vector(512, bool)) void {
                expect(vec[0] == false) catch @panic("test failure");
                expect(vec[1] == true) catch @panic("test failure");
                expect(vec[2] == true) catch @panic("test failure");
                expect(vec[3] == false) catch @panic("test failure");
                expect(vec[4] == true) catch @panic("test failure");
                expect(vec[5] == false) catch @panic("test failure");
                expect(vec[6] == true) catch @panic("test failure");
                expect(vec[7] == false) catch @panic("test failure");
                expect(vec[8] == false) catch @panic("test failure");
                expect(vec[9] == false) catch @panic("test failure");
                expect(vec[10] == false) catch @panic("test failure");
                expect(vec[11] == false) catch @panic("test failure");
                expect(vec[12] == true) catch @panic("test failure");
                expect(vec[13] == false) catch @panic("test failure");
                expect(vec[14] == true) catch @panic("test failure");
                expect(vec[15] == false) catch @panic("test failure");
                expect(vec[16] == false) catch @panic("test failure");
                expect(vec[17] == false) catch @panic("test failure");
                expect(vec[18] == true) catch @panic("test failure");
                expect(vec[19] == true) catch @panic("test failure");
                expect(vec[20] == true) catch @panic("test failure");
                expect(vec[21] == true) catch @panic("test failure");
                expect(vec[22] == false) catch @panic("test failure");
                expect(vec[23] == false) catch @panic("test failure");
                expect(vec[24] == false) catch @panic("test failure");
                expect(vec[25] == true) catch @panic("test failure");
                expect(vec[26] == true) catch @panic("test failure");
                expect(vec[27] == false) catch @panic("test failure");
                expect(vec[28] == true) catch @panic("test failure");
                expect(vec[29] == true) catch @panic("test failure");
                expect(vec[30] == false) catch @panic("test failure");
                expect(vec[31] == false) catch @panic("test failure");
                expect(vec[32] == true) catch @panic("test failure");
                expect(vec[33] == true) catch @panic("test failure");
                expect(vec[34] == false) catch @panic("test failure");
                expect(vec[35] == false) catch @panic("test failure");
                expect(vec[36] == false) catch @panic("test failure");
                expect(vec[37] == false) catch @panic("test failure");
                expect(vec[38] == false) catch @panic("test failure");
                expect(vec[39] == false) catch @panic("test failure");
                expect(vec[40] == false) catch @panic("test failure");
                expect(vec[41] == true) catch @panic("test failure");
                expect(vec[42] == true) catch @panic("test failure");
                expect(vec[43] == true) catch @panic("test failure");
                expect(vec[44] == false) catch @panic("test failure");
                expect(vec[45] == true) catch @panic("test failure");
                expect(vec[46] == true) catch @panic("test failure");
                expect(vec[47] == true) catch @panic("test failure");
                expect(vec[48] == true) catch @panic("test failure");
                expect(vec[49] == true) catch @panic("test failure");
                expect(vec[50] == false) catch @panic("test failure");
                expect(vec[51] == true) catch @panic("test failure");
                expect(vec[52] == true) catch @panic("test failure");
                expect(vec[53] == true) catch @panic("test failure");
                expect(vec[54] == false) catch @panic("test failure");
                expect(vec[55] == true) catch @panic("test failure");
                expect(vec[56] == false) catch @panic("test failure");
                expect(vec[57] == false) catch @panic("test failure");
                expect(vec[58] == true) catch @panic("test failure");
                expect(vec[59] == false) catch @panic("test failure");
                expect(vec[60] == true) catch @panic("test failure");
                expect(vec[61] == true) catch @panic("test failure");
                expect(vec[62] == false) catch @panic("test failure");
                expect(vec[63] == false) catch @panic("test failure");
                expect(vec[64] == false) catch @panic("test failure");
                expect(vec[65] == true) catch @panic("test failure");
                expect(vec[66] == true) catch @panic("test failure");
                expect(vec[67] == true) catch @panic("test failure");
                expect(vec[68] == true) catch @panic("test failure");
                expect(vec[69] == false) catch @panic("test failure");
                expect(vec[70] == false) catch @panic("test failure");
                expect(vec[71] == true) catch @panic("test failure");
                expect(vec[72] == true) catch @panic("test failure");
                expect(vec[73] == false) catch @panic("test failure");
                expect(vec[74] == true) catch @panic("test failure");
                expect(vec[75] == true) catch @panic("test failure");
                expect(vec[76] == false) catch @panic("test failure");
                expect(vec[77] == false) catch @panic("test failure");
                expect(vec[78] == true) catch @panic("test failure");
                expect(vec[79] == false) catch @panic("test failure");
                expect(vec[80] == false) catch @panic("test failure");
                expect(vec[81] == false) catch @panic("test failure");
                expect(vec[82] == true) catch @panic("test failure");
                expect(vec[83] == true) catch @panic("test failure");
                expect(vec[84] == true) catch @panic("test failure");
                expect(vec[85] == false) catch @panic("test failure");
                expect(vec[86] == false) catch @panic("test failure");
                expect(vec[87] == true) catch @panic("test failure");
                expect(vec[88] == false) catch @panic("test failure");
                expect(vec[89] == true) catch @panic("test failure");
                expect(vec[90] == false) catch @panic("test failure");
                expect(vec[91] == false) catch @panic("test failure");
                expect(vec[92] == true) catch @panic("test failure");
                expect(vec[93] == false) catch @panic("test failure");
                expect(vec[94] == false) catch @panic("test failure");
                expect(vec[95] == true) catch @panic("test failure");
                expect(vec[96] == true) catch @panic("test failure");
                expect(vec[97] == false) catch @panic("test failure");
                expect(vec[98] == false) catch @panic("test failure");
                expect(vec[99] == false) catch @panic("test failure");
                expect(vec[100] == false) catch @panic("test failure");
                expect(vec[101] == true) catch @panic("test failure");
                expect(vec[102] == false) catch @panic("test failure");
                expect(vec[103] == false) catch @panic("test failure");
                expect(vec[104] == false) catch @panic("test failure");
                expect(vec[105] == false) catch @panic("test failure");
                expect(vec[106] == false) catch @panic("test failure");
                expect(vec[107] == false) catch @panic("test failure");
                expect(vec[108] == true) catch @panic("test failure");
                expect(vec[109] == true) catch @panic("test failure");
                expect(vec[110] == true) catch @panic("test failure");
                expect(vec[111] == true) catch @panic("test failure");
                expect(vec[112] == true) catch @panic("test failure");
                expect(vec[113] == false) catch @panic("test failure");
                expect(vec[114] == false) catch @panic("test failure");
                expect(vec[115] == false) catch @panic("test failure");
                expect(vec[116] == false) catch @panic("test failure");
                expect(vec[117] == true) catch @panic("test failure");
                expect(vec[118] == true) catch @panic("test failure");
                expect(vec[119] == false) catch @panic("test failure");
                expect(vec[120] == true) catch @panic("test failure");
                expect(vec[121] == true) catch @panic("test failure");
                expect(vec[122] == false) catch @panic("test failure");
                expect(vec[123] == false) catch @panic("test failure");
                expect(vec[124] == true) catch @panic("test failure");
                expect(vec[125] == false) catch @panic("test failure");
                expect(vec[126] == false) catch @panic("test failure");
                expect(vec[127] == false) catch @panic("test failure");
                expect(vec[128] == false) catch @panic("test failure");
                expect(vec[129] == true) catch @panic("test failure");
                expect(vec[130] == true) catch @panic("test failure");
                expect(vec[131] == true) catch @panic("test failure");
                expect(vec[132] == true) catch @panic("test failure");
                expect(vec[133] == false) catch @panic("test failure");
                expect(vec[134] == false) catch @panic("test failure");
                expect(vec[135] == false) catch @panic("test failure");
                expect(vec[136] == false) catch @panic("test failure");
                expect(vec[137] == true) catch @panic("test failure");
                expect(vec[138] == false) catch @panic("test failure");
                expect(vec[139] == false) catch @panic("test failure");
                expect(vec[140] == false) catch @panic("test failure");
                expect(vec[141] == false) catch @panic("test failure");
                expect(vec[142] == true) catch @panic("test failure");
                expect(vec[143] == true) catch @panic("test failure");
                expect(vec[144] == false) catch @panic("test failure");
                expect(vec[145] == true) catch @panic("test failure");
                expect(vec[146] == false) catch @panic("test failure");
                expect(vec[147] == true) catch @panic("test failure");
                expect(vec[148] == false) catch @panic("test failure");
                expect(vec[149] == false) catch @panic("test failure");
                expect(vec[150] == true) catch @panic("test failure");
                expect(vec[151] == true) catch @panic("test failure");
                expect(vec[152] == false) catch @panic("test failure");
                expect(vec[153] == true) catch @panic("test failure");
                expect(vec[154] == true) catch @panic("test failure");
                expect(vec[155] == false) catch @panic("test failure");
                expect(vec[156] == false) catch @panic("test failure");
                expect(vec[157] == false) catch @panic("test failure");
                expect(vec[158] == true) catch @panic("test failure");
                expect(vec[159] == false) catch @panic("test failure");
                expect(vec[160] == false) catch @panic("test failure");
                expect(vec[161] == false) catch @panic("test failure");
                expect(vec[162] == false) catch @panic("test failure");
                expect(vec[163] == true) catch @panic("test failure");
                expect(vec[164] == true) catch @panic("test failure");
                expect(vec[165] == false) catch @panic("test failure");
                expect(vec[166] == false) catch @panic("test failure");
                expect(vec[167] == true) catch @panic("test failure");
                expect(vec[168] == false) catch @panic("test failure");
                expect(vec[169] == true) catch @panic("test failure");
                expect(vec[170] == true) catch @panic("test failure");
                expect(vec[171] == false) catch @panic("test failure");
                expect(vec[172] == false) catch @panic("test failure");
                expect(vec[173] == false) catch @panic("test failure");
                expect(vec[174] == false) catch @panic("test failure");
                expect(vec[175] == false) catch @panic("test failure");
                expect(vec[176] == false) catch @panic("test failure");
                expect(vec[177] == true) catch @panic("test failure");
                expect(vec[178] == false) catch @panic("test failure");
                expect(vec[179] == false) catch @panic("test failure");
                expect(vec[180] == false) catch @panic("test failure");
                expect(vec[181] == false) catch @panic("test failure");
                expect(vec[182] == false) catch @panic("test failure");
                expect(vec[183] == false) catch @panic("test failure");
                expect(vec[184] == true) catch @panic("test failure");
                expect(vec[185] == false) catch @panic("test failure");
                expect(vec[186] == false) catch @panic("test failure");
                expect(vec[187] == false) catch @panic("test failure");
                expect(vec[188] == false) catch @panic("test failure");
                expect(vec[189] == true) catch @panic("test failure");
                expect(vec[190] == false) catch @panic("test failure");
                expect(vec[191] == false) catch @panic("test failure");
                expect(vec[192] == false) catch @panic("test failure");
                expect(vec[193] == false) catch @panic("test failure");
                expect(vec[194] == false) catch @panic("test failure");
                expect(vec[195] == false) catch @panic("test failure");
                expect(vec[196] == true) catch @panic("test failure");
                expect(vec[197] == true) catch @panic("test failure");
                expect(vec[198] == true) catch @panic("test failure");
                expect(vec[199] == false) catch @panic("test failure");
                expect(vec[200] == true) catch @panic("test failure");
                expect(vec[201] == true) catch @panic("test failure");
                expect(vec[202] == false) catch @panic("test failure");
                expect(vec[203] == false) catch @panic("test failure");
                expect(vec[204] == false) catch @panic("test failure");
                expect(vec[205] == false) catch @panic("test failure");
                expect(vec[206] == false) catch @panic("test failure");
                expect(vec[207] == true) catch @panic("test failure");
                expect(vec[208] == true) catch @panic("test failure");
                expect(vec[209] == false) catch @panic("test failure");
                expect(vec[210] == false) catch @panic("test failure");
                expect(vec[211] == false) catch @panic("test failure");
                expect(vec[212] == true) catch @panic("test failure");
                expect(vec[213] == false) catch @panic("test failure");
                expect(vec[214] == false) catch @panic("test failure");
                expect(vec[215] == true) catch @panic("test failure");
                expect(vec[216] == true) catch @panic("test failure");
                expect(vec[217] == true) catch @panic("test failure");
                expect(vec[218] == false) catch @panic("test failure");
                expect(vec[219] == false) catch @panic("test failure");
                expect(vec[220] == true) catch @panic("test failure");
                expect(vec[221] == false) catch @panic("test failure");
                expect(vec[222] == true) catch @panic("test failure");
                expect(vec[223] == true) catch @panic("test failure");
                expect(vec[224] == true) catch @panic("test failure");
                expect(vec[225] == true) catch @panic("test failure");
                expect(vec[226] == false) catch @panic("test failure");
                expect(vec[227] == true) catch @panic("test failure");
                expect(vec[228] == false) catch @panic("test failure");
                expect(vec[229] == false) catch @panic("test failure");
                expect(vec[230] == false) catch @panic("test failure");
                expect(vec[231] == true) catch @panic("test failure");
                expect(vec[232] == false) catch @panic("test failure");
                expect(vec[233] == false) catch @panic("test failure");
                expect(vec[234] == false) catch @panic("test failure");
                expect(vec[235] == false) catch @panic("test failure");
                expect(vec[236] == false) catch @panic("test failure");
                expect(vec[237] == false) catch @panic("test failure");
                expect(vec[238] == false) catch @panic("test failure");
                expect(vec[239] == true) catch @panic("test failure");
                expect(vec[240] == false) catch @panic("test failure");
                expect(vec[241] == false) catch @panic("test failure");
                expect(vec[242] == false) catch @panic("test failure");
                expect(vec[243] == true) catch @panic("test failure");
                expect(vec[244] == true) catch @panic("test failure");
                expect(vec[245] == true) catch @panic("test failure");
                expect(vec[246] == true) catch @panic("test failure");
                expect(vec[247] == false) catch @panic("test failure");
                expect(vec[248] == true) catch @panic("test failure");
                expect(vec[249] == true) catch @panic("test failure");
                expect(vec[250] == false) catch @panic("test failure");
                expect(vec[251] == false) catch @panic("test failure");
                expect(vec[252] == false) catch @panic("test failure");
                expect(vec[253] == true) catch @panic("test failure");
                expect(vec[254] == false) catch @panic("test failure");
                expect(vec[255] == false) catch @panic("test failure");
                expect(vec[256] == true) catch @panic("test failure");
                expect(vec[257] == true) catch @panic("test failure");
                expect(vec[258] == false) catch @panic("test failure");
                expect(vec[259] == true) catch @panic("test failure");
                expect(vec[260] == false) catch @panic("test failure");
                expect(vec[261] == true) catch @panic("test failure");
                expect(vec[262] == true) catch @panic("test failure");
                expect(vec[263] == false) catch @panic("test failure");
                expect(vec[264] == false) catch @panic("test failure");
                expect(vec[265] == false) catch @panic("test failure");
                expect(vec[266] == false) catch @panic("test failure");
                expect(vec[267] == true) catch @panic("test failure");
                expect(vec[268] == false) catch @panic("test failure");
                expect(vec[269] == true) catch @panic("test failure");
                expect(vec[270] == true) catch @panic("test failure");
                expect(vec[271] == false) catch @panic("test failure");
                expect(vec[272] == false) catch @panic("test failure");
                expect(vec[273] == true) catch @panic("test failure");
                expect(vec[274] == true) catch @panic("test failure");
                expect(vec[275] == true) catch @panic("test failure");
                expect(vec[276] == false) catch @panic("test failure");
                expect(vec[277] == true) catch @panic("test failure");
                expect(vec[278] == false) catch @panic("test failure");
                expect(vec[279] == false) catch @panic("test failure");
                expect(vec[280] == true) catch @panic("test failure");
                expect(vec[281] == true) catch @panic("test failure");
                expect(vec[282] == false) catch @panic("test failure");
                expect(vec[283] == true) catch @panic("test failure");
                expect(vec[284] == false) catch @panic("test failure");
                expect(vec[285] == true) catch @panic("test failure");
                expect(vec[286] == true) catch @panic("test failure");
                expect(vec[287] == true) catch @panic("test failure");
                expect(vec[288] == true) catch @panic("test failure");
                expect(vec[289] == true) catch @panic("test failure");
                expect(vec[290] == true) catch @panic("test failure");
                expect(vec[291] == true) catch @panic("test failure");
                expect(vec[292] == true) catch @panic("test failure");
                expect(vec[293] == true) catch @panic("test failure");
                expect(vec[294] == true) catch @panic("test failure");
                expect(vec[295] == false) catch @panic("test failure");
                expect(vec[296] == true) catch @panic("test failure");
                expect(vec[297] == false) catch @panic("test failure");
                expect(vec[298] == true) catch @panic("test failure");
                expect(vec[299] == false) catch @panic("test failure");
                expect(vec[300] == true) catch @panic("test failure");
                expect(vec[301] == true) catch @panic("test failure");
                expect(vec[302] == false) catch @panic("test failure");
                expect(vec[303] == true) catch @panic("test failure");
                expect(vec[304] == false) catch @panic("test failure");
                expect(vec[305] == true) catch @panic("test failure");
                expect(vec[306] == false) catch @panic("test failure");
                expect(vec[307] == true) catch @panic("test failure");
                expect(vec[308] == true) catch @panic("test failure");
                expect(vec[309] == false) catch @panic("test failure");
                expect(vec[310] == true) catch @panic("test failure");
                expect(vec[311] == true) catch @panic("test failure");
                expect(vec[312] == true) catch @panic("test failure");
                expect(vec[313] == false) catch @panic("test failure");
                expect(vec[314] == false) catch @panic("test failure");
                expect(vec[315] == false) catch @panic("test failure");
                expect(vec[316] == false) catch @panic("test failure");
                expect(vec[317] == true) catch @panic("test failure");
                expect(vec[318] == true) catch @panic("test failure");
                expect(vec[319] == true) catch @panic("test failure");
                expect(vec[320] == true) catch @panic("test failure");
                expect(vec[321] == true) catch @panic("test failure");
                expect(vec[322] == true) catch @panic("test failure");
                expect(vec[323] == true) catch @panic("test failure");
                expect(vec[324] == true) catch @panic("test failure");
                expect(vec[325] == true) catch @panic("test failure");
                expect(vec[326] == false) catch @panic("test failure");
                expect(vec[327] == true) catch @panic("test failure");
                expect(vec[328] == false) catch @panic("test failure");
                expect(vec[329] == false) catch @panic("test failure");
                expect(vec[330] == true) catch @panic("test failure");
                expect(vec[331] == false) catch @panic("test failure");
                expect(vec[332] == false) catch @panic("test failure");
                expect(vec[333] == false) catch @panic("test failure");
                expect(vec[334] == false) catch @panic("test failure");
                expect(vec[335] == false) catch @panic("test failure");
                expect(vec[336] == false) catch @panic("test failure");
                expect(vec[337] == false) catch @panic("test failure");
                expect(vec[338] == false) catch @panic("test failure");
                expect(vec[339] == false) catch @panic("test failure");
                expect(vec[340] == false) catch @panic("test failure");
                expect(vec[341] == false) catch @panic("test failure");
                expect(vec[342] == true) catch @panic("test failure");
                expect(vec[343] == true) catch @panic("test failure");
                expect(vec[344] == false) catch @panic("test failure");
                expect(vec[345] == false) catch @panic("test failure");
                expect(vec[346] == false) catch @panic("test failure");
                expect(vec[347] == false) catch @panic("test failure");
                expect(vec[348] == false) catch @panic("test failure");
                expect(vec[349] == true) catch @panic("test failure");
                expect(vec[350] == true) catch @panic("test failure");
                expect(vec[351] == true) catch @panic("test failure");
                expect(vec[352] == true) catch @panic("test failure");
                expect(vec[353] == false) catch @panic("test failure");
                expect(vec[354] == false) catch @panic("test failure");
                expect(vec[355] == false) catch @panic("test failure");
                expect(vec[356] == false) catch @panic("test failure");
                expect(vec[357] == true) catch @panic("test failure");
                expect(vec[358] == true) catch @panic("test failure");
                expect(vec[359] == false) catch @panic("test failure");
                expect(vec[360] == false) catch @panic("test failure");
                expect(vec[361] == false) catch @panic("test failure");
                expect(vec[362] == true) catch @panic("test failure");
                expect(vec[363] == true) catch @panic("test failure");
                expect(vec[364] == false) catch @panic("test failure");
                expect(vec[365] == false) catch @panic("test failure");
                expect(vec[366] == false) catch @panic("test failure");
                expect(vec[367] == false) catch @panic("test failure");
                expect(vec[368] == false) catch @panic("test failure");
                expect(vec[369] == true) catch @panic("test failure");
                expect(vec[370] == true) catch @panic("test failure");
                expect(vec[371] == false) catch @panic("test failure");
                expect(vec[372] == true) catch @panic("test failure");
                expect(vec[373] == true) catch @panic("test failure");
                expect(vec[374] == false) catch @panic("test failure");
                expect(vec[375] == true) catch @panic("test failure");
                expect(vec[376] == true) catch @panic("test failure");
                expect(vec[377] == false) catch @panic("test failure");
                expect(vec[378] == true) catch @panic("test failure");
                expect(vec[379] == true) catch @panic("test failure");
                expect(vec[380] == false) catch @panic("test failure");
                expect(vec[381] == true) catch @panic("test failure");
                expect(vec[382] == true) catch @panic("test failure");
                expect(vec[383] == false) catch @panic("test failure");
                expect(vec[384] == true) catch @panic("test failure");
                expect(vec[385] == false) catch @panic("test failure");
                expect(vec[386] == true) catch @panic("test failure");
                expect(vec[387] == true) catch @panic("test failure");
                expect(vec[388] == true) catch @panic("test failure");
                expect(vec[389] == true) catch @panic("test failure");
                expect(vec[390] == false) catch @panic("test failure");
                expect(vec[391] == false) catch @panic("test failure");
                expect(vec[392] == false) catch @panic("test failure");
                expect(vec[393] == true) catch @panic("test failure");
                expect(vec[394] == true) catch @panic("test failure");
                expect(vec[395] == true) catch @panic("test failure");
                expect(vec[396] == true) catch @panic("test failure");
                expect(vec[397] == false) catch @panic("test failure");
                expect(vec[398] == true) catch @panic("test failure");
                expect(vec[399] == true) catch @panic("test failure");
                expect(vec[400] == true) catch @panic("test failure");
                expect(vec[401] == false) catch @panic("test failure");
                expect(vec[402] == false) catch @panic("test failure");
                expect(vec[403] == true) catch @panic("test failure");
                expect(vec[404] == false) catch @panic("test failure");
                expect(vec[405] == false) catch @panic("test failure");
                expect(vec[406] == false) catch @panic("test failure");
                expect(vec[407] == true) catch @panic("test failure");
                expect(vec[408] == true) catch @panic("test failure");
                expect(vec[409] == true) catch @panic("test failure");
                expect(vec[410] == false) catch @panic("test failure");
                expect(vec[411] == true) catch @panic("test failure");
                expect(vec[412] == false) catch @panic("test failure");
                expect(vec[413] == false) catch @panic("test failure");
                expect(vec[414] == false) catch @panic("test failure");
                expect(vec[415] == true) catch @panic("test failure");
                expect(vec[416] == false) catch @panic("test failure");
                expect(vec[417] == false) catch @panic("test failure");
                expect(vec[418] == true) catch @panic("test failure");
                expect(vec[419] == true) catch @panic("test failure");
                expect(vec[420] == true) catch @panic("test failure");
                expect(vec[421] == true) catch @panic("test failure");
                expect(vec[422] == false) catch @panic("test failure");
                expect(vec[423] == true) catch @panic("test failure");
                expect(vec[424] == true) catch @panic("test failure");
                expect(vec[425] == false) catch @panic("test failure");
                expect(vec[426] == false) catch @panic("test failure");
                expect(vec[427] == false) catch @panic("test failure");
                expect(vec[428] == true) catch @panic("test failure");
                expect(vec[429] == false) catch @panic("test failure");
                expect(vec[430] == true) catch @panic("test failure");
                expect(vec[431] == true) catch @panic("test failure");
                expect(vec[432] == false) catch @panic("test failure");
                expect(vec[433] == false) catch @panic("test failure");
                expect(vec[434] == false) catch @panic("test failure");
                expect(vec[435] == false) catch @panic("test failure");
                expect(vec[436] == true) catch @panic("test failure");
                expect(vec[437] == false) catch @panic("test failure");
                expect(vec[438] == true) catch @panic("test failure");
                expect(vec[439] == false) catch @panic("test failure");
                expect(vec[440] == false) catch @panic("test failure");
                expect(vec[441] == false) catch @panic("test failure");
                expect(vec[442] == false) catch @panic("test failure");
                expect(vec[443] == true) catch @panic("test failure");
                expect(vec[444] == false) catch @panic("test failure");
                expect(vec[445] == false) catch @panic("test failure");
                expect(vec[446] == true) catch @panic("test failure");
                expect(vec[447] == true) catch @panic("test failure");
                expect(vec[448] == true) catch @panic("test failure");
                expect(vec[449] == false) catch @panic("test failure");
                expect(vec[450] == true) catch @panic("test failure");
                expect(vec[451] == true) catch @panic("test failure");
                expect(vec[452] == false) catch @panic("test failure");
                expect(vec[453] == true) catch @panic("test failure");
                expect(vec[454] == false) catch @panic("test failure");
                expect(vec[455] == true) catch @panic("test failure");
                expect(vec[456] == false) catch @panic("test failure");
                expect(vec[457] == false) catch @panic("test failure");
                expect(vec[458] == false) catch @panic("test failure");
                expect(vec[459] == true) catch @panic("test failure");
                expect(vec[460] == false) catch @panic("test failure");
                expect(vec[461] == false) catch @panic("test failure");
                expect(vec[462] == false) catch @panic("test failure");
                expect(vec[463] == true) catch @panic("test failure");
                expect(vec[464] == true) catch @panic("test failure");
                expect(vec[465] == true) catch @panic("test failure");
                expect(vec[466] == true) catch @panic("test failure");
                expect(vec[467] == true) catch @panic("test failure");
                expect(vec[468] == false) catch @panic("test failure");
                expect(vec[469] == false) catch @panic("test failure");
                expect(vec[470] == false) catch @panic("test failure");
                expect(vec[471] == false) catch @panic("test failure");
                expect(vec[472] == false) catch @panic("test failure");
                expect(vec[473] == false) catch @panic("test failure");
                expect(vec[474] == true) catch @panic("test failure");
                expect(vec[475] == true) catch @panic("test failure");
                expect(vec[476] == true) catch @panic("test failure");
                expect(vec[477] == true) catch @panic("test failure");
                expect(vec[478] == true) catch @panic("test failure");
                expect(vec[479] == false) catch @panic("test failure");
                expect(vec[480] == true) catch @panic("test failure");
                expect(vec[481] == true) catch @panic("test failure");
                expect(vec[482] == false) catch @panic("test failure");
                expect(vec[483] == true) catch @panic("test failure");
                expect(vec[484] == false) catch @panic("test failure");
                expect(vec[485] == true) catch @panic("test failure");
                expect(vec[486] == false) catch @panic("test failure");
                expect(vec[487] == true) catch @panic("test failure");
                expect(vec[488] == false) catch @panic("test failure");
                expect(vec[489] == false) catch @panic("test failure");
                expect(vec[490] == false) catch @panic("test failure");
                expect(vec[491] == true) catch @panic("test failure");
                expect(vec[492] == false) catch @panic("test failure");
                expect(vec[493] == false) catch @panic("test failure");
                expect(vec[494] == false) catch @panic("test failure");
                expect(vec[495] == true) catch @panic("test failure");
                expect(vec[496] == true) catch @panic("test failure");
                expect(vec[497] == false) catch @panic("test failure");
                expect(vec[498] == false) catch @panic("test failure");
                expect(vec[499] == true) catch @panic("test failure");
                expect(vec[500] == false) catch @panic("test failure");
                expect(vec[501] == true) catch @panic("test failure");
                expect(vec[502] == false) catch @panic("test failure");
                expect(vec[503] == false) catch @panic("test failure");
                expect(vec[504] == false) catch @panic("test failure");
                expect(vec[505] == true) catch @panic("test failure");
                expect(vec[506] == true) catch @panic("test failure");
                expect(vec[507] == true) catch @panic("test failure");
                expect(vec[508] == true) catch @panic("test failure");
                expect(vec[509] == false) catch @panic("test failure");
                expect(vec[510] == false) catch @panic("test failure");
                expect(vec[511] == true) catch @panic("test failure");
            }
        };
    }
}

extern fn c_ret_vector_512_bool() @Vector(512, bool);
extern fn c_vector_512_bool(@Vector(512, bool)) void;
extern fn c_test_vector_512_bool() void;

test "@Vector(512, bool)" {
    if (builtin.zig_backend == .stage2_llvm and (builtin.cpu.arch != .powerpc and builtin.cpu.arch != .wasm32)) return error.SkipZigTest;

    const vec = c_ret_vector_512_bool();
    try expect(vec[0] == false);
    try expect(vec[1] == true);
    try expect(vec[2] == false);
    try expect(vec[3] == false);
    try expect(vec[4] == false);
    try expect(vec[5] == true);
    try expect(vec[6] == false);
    try expect(vec[7] == false);
    try expect(vec[8] == false);
    try expect(vec[9] == true);
    try expect(vec[10] == false);
    try expect(vec[11] == false);
    try expect(vec[12] == false);
    try expect(vec[13] == true);
    try expect(vec[14] == false);
    try expect(vec[15] == true);
    try expect(vec[16] == false);
    try expect(vec[17] == false);
    try expect(vec[18] == false);
    try expect(vec[19] == false);
    try expect(vec[20] == false);
    try expect(vec[21] == false);
    try expect(vec[22] == true);
    try expect(vec[23] == true);
    try expect(vec[24] == false);
    try expect(vec[25] == false);
    try expect(vec[26] == false);
    try expect(vec[27] == false);
    try expect(vec[28] == true);
    try expect(vec[29] == true);
    try expect(vec[30] == false);
    try expect(vec[31] == true);
    try expect(vec[32] == false);
    try expect(vec[33] == true);
    try expect(vec[34] == true);
    try expect(vec[35] == true);
    try expect(vec[36] == false);
    try expect(vec[37] == false);
    try expect(vec[38] == true);
    try expect(vec[39] == true);
    try expect(vec[40] == false);
    try expect(vec[41] == false);
    try expect(vec[42] == false);
    try expect(vec[43] == false);
    try expect(vec[44] == false);
    try expect(vec[45] == true);
    try expect(vec[46] == false);
    try expect(vec[47] == true);
    try expect(vec[48] == true);
    try expect(vec[49] == false);
    try expect(vec[50] == true);
    try expect(vec[51] == true);
    try expect(vec[52] == true);
    try expect(vec[53] == true);
    try expect(vec[54] == false);
    try expect(vec[55] == false);
    try expect(vec[56] == false);
    try expect(vec[57] == true);
    try expect(vec[58] == true);
    try expect(vec[59] == false);
    try expect(vec[60] == false);
    try expect(vec[61] == false);
    try expect(vec[62] == false);
    try expect(vec[63] == true);
    try expect(vec[64] == true);
    try expect(vec[65] == true);
    try expect(vec[66] == true);
    try expect(vec[67] == true);
    try expect(vec[68] == false);
    try expect(vec[69] == false);
    try expect(vec[70] == false);
    try expect(vec[71] == false);
    try expect(vec[72] == false);
    try expect(vec[73] == true);
    try expect(vec[74] == false);
    try expect(vec[75] == true);
    try expect(vec[76] == false);
    try expect(vec[77] == false);
    try expect(vec[78] == true);
    try expect(vec[79] == true);
    try expect(vec[80] == false);
    try expect(vec[81] == false);
    try expect(vec[82] == false);
    try expect(vec[83] == true);
    try expect(vec[84] == false);
    try expect(vec[85] == true);
    try expect(vec[86] == true);
    try expect(vec[87] == true);
    try expect(vec[88] == false);
    try expect(vec[89] == true);
    try expect(vec[90] == false);
    try expect(vec[91] == false);
    try expect(vec[92] == true);
    try expect(vec[93] == true);
    try expect(vec[94] == false);
    try expect(vec[95] == true);
    try expect(vec[96] == true);
    try expect(vec[97] == false);
    try expect(vec[98] == true);
    try expect(vec[99] == false);
    try expect(vec[100] == true);
    try expect(vec[101] == true);
    try expect(vec[102] == false);
    try expect(vec[103] == true);
    try expect(vec[104] == true);
    try expect(vec[105] == false);
    try expect(vec[106] == false);
    try expect(vec[107] == false);
    try expect(vec[108] == true);
    try expect(vec[109] == false);
    try expect(vec[110] == false);
    try expect(vec[111] == false);
    try expect(vec[112] == true);
    try expect(vec[113] == true);
    try expect(vec[114] == true);
    try expect(vec[115] == false);
    try expect(vec[116] == true);
    try expect(vec[117] == false);
    try expect(vec[118] == true);
    try expect(vec[119] == false);
    try expect(vec[120] == true);
    try expect(vec[121] == true);
    try expect(vec[122] == false);
    try expect(vec[123] == true);
    try expect(vec[124] == false);
    try expect(vec[125] == true);
    try expect(vec[126] == true);
    try expect(vec[127] == true);
    try expect(vec[128] == false);
    try expect(vec[129] == true);
    try expect(vec[130] == false);
    try expect(vec[131] == false);
    try expect(vec[132] == false);
    try expect(vec[133] == false);
    try expect(vec[134] == false);
    try expect(vec[135] == false);
    try expect(vec[136] == true);
    try expect(vec[137] == false);
    try expect(vec[138] == true);
    try expect(vec[139] == false);
    try expect(vec[140] == true);
    try expect(vec[141] == true);
    try expect(vec[142] == false);
    try expect(vec[143] == true);
    try expect(vec[144] == false);
    try expect(vec[145] == false);
    try expect(vec[146] == true);
    try expect(vec[147] == false);
    try expect(vec[148] == false);
    try expect(vec[149] == true);
    try expect(vec[150] == false);
    try expect(vec[151] == true);
    try expect(vec[152] == false);
    try expect(vec[153] == true);
    try expect(vec[154] == false);
    try expect(vec[155] == false);
    try expect(vec[156] == true);
    try expect(vec[157] == false);
    try expect(vec[158] == true);
    try expect(vec[159] == true);
    try expect(vec[160] == true);
    try expect(vec[161] == false);
    try expect(vec[162] == false);
    try expect(vec[163] == true);
    try expect(vec[164] == false);
    try expect(vec[165] == false);
    try expect(vec[166] == false);
    try expect(vec[167] == true);
    try expect(vec[168] == true);
    try expect(vec[169] == true);
    try expect(vec[170] == false);
    try expect(vec[171] == true);
    try expect(vec[172] == false);
    try expect(vec[173] == false);
    try expect(vec[174] == false);
    try expect(vec[175] == false);
    try expect(vec[176] == false);
    try expect(vec[177] == true);
    try expect(vec[178] == true);
    try expect(vec[179] == false);
    try expect(vec[180] == false);
    try expect(vec[181] == true);
    try expect(vec[182] == false);
    try expect(vec[183] == false);
    try expect(vec[184] == false);
    try expect(vec[185] == false);
    try expect(vec[186] == false);
    try expect(vec[187] == true);
    try expect(vec[188] == true);
    try expect(vec[189] == false);
    try expect(vec[190] == false);
    try expect(vec[191] == false);
    try expect(vec[192] == false);
    try expect(vec[193] == false);
    try expect(vec[194] == false);
    try expect(vec[195] == true);
    try expect(vec[196] == true);
    try expect(vec[197] == false);
    try expect(vec[198] == true);
    try expect(vec[199] == true);
    try expect(vec[200] == true);
    try expect(vec[201] == true);
    try expect(vec[202] == true);
    try expect(vec[203] == true);
    try expect(vec[204] == false);
    try expect(vec[205] == false);
    try expect(vec[206] == false);
    try expect(vec[207] == false);
    try expect(vec[208] == true);
    try expect(vec[209] == false);
    try expect(vec[210] == true);
    try expect(vec[211] == true);
    try expect(vec[212] == true);
    try expect(vec[213] == true);
    try expect(vec[214] == false);
    try expect(vec[215] == false);
    try expect(vec[216] == false);
    try expect(vec[217] == true);
    try expect(vec[218] == true);
    try expect(vec[219] == false);
    try expect(vec[220] == true);
    try expect(vec[221] == true);
    try expect(vec[222] == false);
    try expect(vec[223] == false);
    try expect(vec[224] == false);
    try expect(vec[225] == true);
    try expect(vec[226] == true);
    try expect(vec[227] == true);
    try expect(vec[228] == true);
    try expect(vec[229] == false);
    try expect(vec[230] == true);
    try expect(vec[231] == false);
    try expect(vec[232] == true);
    try expect(vec[233] == true);
    try expect(vec[234] == true);
    try expect(vec[235] == true);
    try expect(vec[236] == false);
    try expect(vec[237] == true);
    try expect(vec[238] == false);
    try expect(vec[239] == true);
    try expect(vec[240] == false);
    try expect(vec[241] == true);
    try expect(vec[242] == false);
    try expect(vec[243] == false);
    try expect(vec[244] == false);
    try expect(vec[245] == true);
    try expect(vec[246] == true);
    try expect(vec[247] == false);
    try expect(vec[248] == true);
    try expect(vec[249] == false);
    try expect(vec[250] == false);
    try expect(vec[251] == false);
    try expect(vec[252] == true);
    try expect(vec[253] == true);
    try expect(vec[254] == true);
    try expect(vec[255] == true);
    try expect(vec[256] == true);
    try expect(vec[257] == false);
    try expect(vec[258] == true);
    try expect(vec[259] == true);
    try expect(vec[260] == true);
    try expect(vec[261] == true);
    try expect(vec[262] == false);
    try expect(vec[263] == true);
    try expect(vec[264] == false);
    try expect(vec[265] == false);
    try expect(vec[266] == true);
    try expect(vec[267] == false);
    try expect(vec[268] == true);
    try expect(vec[269] == false);
    try expect(vec[270] == false);
    try expect(vec[271] == true);
    try expect(vec[272] == true);
    try expect(vec[273] == false);
    try expect(vec[274] == true);
    try expect(vec[275] == false);
    try expect(vec[276] == false);
    try expect(vec[277] == true);
    try expect(vec[278] == false);
    try expect(vec[279] == false);
    try expect(vec[280] == true);
    try expect(vec[281] == true);
    try expect(vec[282] == true);
    try expect(vec[283] == false);
    try expect(vec[284] == false);
    try expect(vec[285] == true);
    try expect(vec[286] == true);
    try expect(vec[287] == true);
    try expect(vec[288] == false);
    try expect(vec[289] == false);
    try expect(vec[290] == false);
    try expect(vec[291] == false);
    try expect(vec[292] == false);
    try expect(vec[293] == false);
    try expect(vec[294] == true);
    try expect(vec[295] == false);
    try expect(vec[296] == true);
    try expect(vec[297] == false);
    try expect(vec[298] == true);
    try expect(vec[299] == true);
    try expect(vec[300] == false);
    try expect(vec[301] == false);
    try expect(vec[302] == false);
    try expect(vec[303] == false);
    try expect(vec[304] == true);
    try expect(vec[305] == true);
    try expect(vec[306] == true);
    try expect(vec[307] == true);
    try expect(vec[308] == true);
    try expect(vec[309] == false);
    try expect(vec[310] == true);
    try expect(vec[311] == true);
    try expect(vec[312] == true);
    try expect(vec[313] == true);
    try expect(vec[314] == true);
    try expect(vec[315] == false);
    try expect(vec[316] == true);
    try expect(vec[317] == true);
    try expect(vec[318] == true);
    try expect(vec[319] == false);
    try expect(vec[320] == true);
    try expect(vec[321] == false);
    try expect(vec[322] == true);
    try expect(vec[323] == true);
    try expect(vec[324] == true);
    try expect(vec[325] == false);
    try expect(vec[326] == false);
    try expect(vec[327] == true);
    try expect(vec[328] == true);
    try expect(vec[329] == true);
    try expect(vec[330] == false);
    try expect(vec[331] == false);
    try expect(vec[332] == true);
    try expect(vec[333] == true);
    try expect(vec[334] == false);
    try expect(vec[335] == true);
    try expect(vec[336] == true);
    try expect(vec[337] == true);
    try expect(vec[338] == true);
    try expect(vec[339] == true);
    try expect(vec[340] == true);
    try expect(vec[341] == false);
    try expect(vec[342] == true);
    try expect(vec[343] == false);
    try expect(vec[344] == true);
    try expect(vec[345] == false);
    try expect(vec[346] == false);
    try expect(vec[347] == false);
    try expect(vec[348] == false);
    try expect(vec[349] == true);
    try expect(vec[350] == true);
    try expect(vec[351] == true);
    try expect(vec[352] == true);
    try expect(vec[353] == false);
    try expect(vec[354] == true);
    try expect(vec[355] == false);
    try expect(vec[356] == true);
    try expect(vec[357] == true);
    try expect(vec[358] == false);
    try expect(vec[359] == true);
    try expect(vec[360] == false);
    try expect(vec[361] == false);
    try expect(vec[362] == true);
    try expect(vec[363] == false);
    try expect(vec[364] == false);
    try expect(vec[365] == false);
    try expect(vec[366] == false);
    try expect(vec[367] == false);
    try expect(vec[368] == false);
    try expect(vec[369] == false);
    try expect(vec[370] == true);
    try expect(vec[371] == false);
    try expect(vec[372] == true);
    try expect(vec[373] == true);
    try expect(vec[374] == false);
    try expect(vec[375] == false);
    try expect(vec[376] == true);
    try expect(vec[377] == false);
    try expect(vec[378] == false);
    try expect(vec[379] == true);
    try expect(vec[380] == false);
    try expect(vec[381] == false);
    try expect(vec[382] == true);
    try expect(vec[383] == false);
    try expect(vec[384] == false);
    try expect(vec[385] == false);
    try expect(vec[386] == false);
    try expect(vec[387] == true);
    try expect(vec[388] == true);
    try expect(vec[389] == true);
    try expect(vec[390] == true);
    try expect(vec[391] == true);
    try expect(vec[392] == true);
    try expect(vec[393] == true);
    try expect(vec[394] == false);
    try expect(vec[395] == true);
    try expect(vec[396] == true);
    try expect(vec[397] == false);
    try expect(vec[398] == false);
    try expect(vec[399] == false);
    try expect(vec[400] == true);
    try expect(vec[401] == false);
    try expect(vec[402] == true);
    try expect(vec[403] == true);
    try expect(vec[404] == false);
    try expect(vec[405] == true);
    try expect(vec[406] == true);
    try expect(vec[407] == true);
    try expect(vec[408] == true);
    try expect(vec[409] == false);
    try expect(vec[410] == false);
    try expect(vec[411] == false);
    try expect(vec[412] == true);
    try expect(vec[413] == true);
    try expect(vec[414] == false);
    try expect(vec[415] == true);
    try expect(vec[416] == false);
    try expect(vec[417] == true);
    try expect(vec[418] == false);
    try expect(vec[419] == false);
    try expect(vec[420] == false);
    try expect(vec[421] == false);
    try expect(vec[422] == true);
    try expect(vec[423] == true);
    try expect(vec[424] == true);
    try expect(vec[425] == false);
    try expect(vec[426] == true);
    try expect(vec[427] == false);
    try expect(vec[428] == false);
    try expect(vec[429] == false);
    try expect(vec[430] == true);
    try expect(vec[431] == true);
    try expect(vec[432] == false);
    try expect(vec[433] == true);
    try expect(vec[434] == false);
    try expect(vec[435] == false);
    try expect(vec[436] == true);
    try expect(vec[437] == true);
    try expect(vec[438] == true);
    try expect(vec[439] == true);
    try expect(vec[440] == true);
    try expect(vec[441] == true);
    try expect(vec[442] == false);
    try expect(vec[443] == false);
    try expect(vec[444] == false);
    try expect(vec[445] == true);
    try expect(vec[446] == true);
    try expect(vec[447] == true);
    try expect(vec[448] == false);
    try expect(vec[449] == false);
    try expect(vec[450] == false);
    try expect(vec[451] == false);
    try expect(vec[452] == false);
    try expect(vec[453] == false);
    try expect(vec[454] == false);
    try expect(vec[455] == false);
    try expect(vec[456] == false);
    try expect(vec[457] == false);
    try expect(vec[458] == false);
    try expect(vec[459] == true);
    try expect(vec[460] == false);
    try expect(vec[461] == false);
    try expect(vec[462] == false);
    try expect(vec[463] == true);
    try expect(vec[464] == false);
    try expect(vec[465] == false);
    try expect(vec[466] == false);
    try expect(vec[467] == false);
    try expect(vec[468] == true);
    try expect(vec[469] == true);
    try expect(vec[470] == true);
    try expect(vec[471] == true);
    try expect(vec[472] == true);
    try expect(vec[473] == false);
    try expect(vec[474] == false);
    try expect(vec[475] == true);
    try expect(vec[476] == true);
    try expect(vec[477] == true);
    try expect(vec[478] == false);
    try expect(vec[479] == true);
    try expect(vec[480] == true);
    try expect(vec[481] == true);
    try expect(vec[482] == false);
    try expect(vec[483] == true);
    try expect(vec[484] == false);
    try expect(vec[485] == true);
    try expect(vec[486] == false);
    try expect(vec[487] == true);
    try expect(vec[488] == false);
    try expect(vec[489] == true);
    try expect(vec[490] == true);
    try expect(vec[491] == true);
    try expect(vec[492] == true);
    try expect(vec[493] == false);
    try expect(vec[494] == true);
    try expect(vec[495] == true);
    try expect(vec[496] == false);
    try expect(vec[497] == true);
    try expect(vec[498] == false);
    try expect(vec[499] == false);
    try expect(vec[500] == false);
    try expect(vec[501] == false);
    try expect(vec[502] == false);
    try expect(vec[503] == false);
    try expect(vec[504] == false);
    try expect(vec[505] == false);
    try expect(vec[506] == false);
    try expect(vec[507] == true);
    try expect(vec[508] == true);
    try expect(vec[509] == false);
    try expect(vec[510] == true);
    try expect(vec[511] == false);
    if (!builtin.target.cpu.arch.isWasm()) c_vector_512_bool(.{
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
        true,
        true,
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
        false,
        true,
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
        false,
        false,
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
        true,
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
        false,
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
        false,
        true,
        false,
        true,
    });
    c_test_vector_512_bool();
}

export fn zig_ret_vector_1_u8() @Vector(1, u8) {
    return .{1};
}
export fn zig_vector_1_u8(v: @Vector(1, u8), i: usize) void {
    expect(v[0] == 2) catch @panic("test failure");
    expect(i == 1) catch @panic("test failure");
}

extern fn c_ret_vector_1_u8() @Vector(1, u8);
extern fn c_vector_1_u8(@Vector(1, u8), usize) void;
extern fn c_test_vector_1_u8() void;

test "@Vector(1, u8)" {
    if (builtin.cpu.arch.isAARCH64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;

    const v = c_ret_vector_1_u8();
    try expect(v[0] == 3);
    c_vector_1_u8(.{4}, 1);
    c_test_vector_1_u8();
}

export fn zig_ret_vector_2_u8() @Vector(2, u8) {
    return .{ 5, 6 };
}
export fn zig_vector_2_u8(v: @Vector(2, u8), i: usize) void {
    expect(v[0] == 7) catch @panic("test failure");
    expect(v[1] == 8) catch @panic("test failure");
    expect(i == 2) catch @panic("test failure");
}

extern fn c_ret_vector_2_u8() @Vector(2, u8);
extern fn c_vector_2_u8(@Vector(2, u8), usize) void;
extern fn c_test_vector_2_u8() void;

test "@Vector(2, u8)" {
    if (builtin.cpu.arch.isAARCH64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .x86_64) return error.SkipZigTest;

    const v = c_ret_vector_2_u8();
    try expect(v[0] == 9);
    try expect(v[1] == 10);
    c_vector_2_u8(.{ 11, 12 }, 2);
    c_test_vector_2_u8();
}

export fn zig_ret_vector_3_u8() @Vector(3, u8) {
    return .{ 13, 14, 15 };
}
export fn zig_vector_3_u8(v: @Vector(3, u8), i: usize) void {
    expect(v[0] == 16) catch @panic("test failure");
    expect(v[1] == 17) catch @panic("test failure");
    expect(v[2] == 18) catch @panic("test failure");
    expect(i == 3) catch @panic("test failure");
}

extern fn c_ret_vector_3_u8() @Vector(3, u8);
extern fn c_vector_3_u8(@Vector(3, u8), usize) void;
extern fn c_test_vector_3_u8() void;

test "@Vector(3, u8)" {
    if (builtin.cpu.arch.isAARCH64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .x86_64 and builtin.os.tag != .windows) return error.SkipZigTest;

    const v = c_ret_vector_3_u8();
    try expect(v[0] == 19);
    try expect(v[1] == 20);
    try expect(v[2] == 21);
    c_vector_3_u8(.{ 22, 23, 24 }, 3);
    c_test_vector_3_u8();
}

export fn zig_ret_vector_4_u8() @Vector(4, u8) {
    return .{ 25, 26, 27, 28 };
}
export fn zig_vector_4_u8(v: @Vector(4, u8), i: usize) void {
    expect(v[0] == 29) catch @panic("test failure");
    expect(v[1] == 30) catch @panic("test failure");
    expect(v[2] == 31) catch @panic("test failure");
    expect(v[3] == 32) catch @panic("test failure");
    expect(i == 4) catch @panic("test failure");
}
export fn zig_vector_4_u8_vector_4_u8(v0: @Vector(4, u8), v1: @Vector(4, u8), i: usize) void {
    expect(v0[0] == 33) catch @panic("test failure");
    expect(v0[1] == 34) catch @panic("test failure");
    expect(v0[2] == 35) catch @panic("test failure");
    expect(v0[3] == 36) catch @panic("test failure");
    expect(v1[0] == 37) catch @panic("test failure");
    expect(v1[1] == 38) catch @panic("test failure");
    expect(v1[2] == 39) catch @panic("test failure");
    expect(v1[3] == 40) catch @panic("test failure");
    expect(i == 8) catch @panic("test failure");
}

extern fn c_ret_vector_4_u8() @Vector(4, u8);
extern fn c_vector_4_u8(@Vector(4, u8), usize) void;
extern fn c_vector_4_u8_vector_4_u8(@Vector(4, u8), @Vector(4, u8), usize) void;
extern fn c_test_vector_4_u8() void;

test "@Vector(4, u8)" {
    if (builtin.cpu.arch.isAARCH64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .x86_64) return error.SkipZigTest;

    const v = c_ret_vector_4_u8();
    try expect(v[0] == 41);
    try expect(v[1] == 42);
    try expect(v[2] == 43);
    try expect(v[3] == 44);
    c_vector_4_u8(.{ 45, 46, 47, 48 }, 4);
    c_vector_4_u8_vector_4_u8(.{ 49, 50, 51, 52 }, .{ 53, 54, 55, 56 }, 8);
    c_test_vector_4_u8();
}

export fn zig_ret_vector_6_u8() @Vector(6, u8) {
    return .{ 41, 42, 43, 44, 45, 46 };
}
export fn zig_vector_6_u8(v: @Vector(6, u8), i: usize) void {
    expect(v[0] == 47) catch @panic("test failure");
    expect(v[1] == 48) catch @panic("test failure");
    expect(v[2] == 49) catch @panic("test failure");
    expect(v[3] == 50) catch @panic("test failure");
    expect(v[4] == 51) catch @panic("test failure");
    expect(v[5] == 52) catch @panic("test failure");
    expect(i == 6) catch @panic("test failure");
}

extern fn c_ret_vector_6_u8() @Vector(6, u8);
extern fn c_vector_6_u8(@Vector(6, u8), usize) void;
extern fn c_test_vector_6_u8() void;

test "@Vector(6, u8)" {
    if (builtin.cpu.arch.isArm() and builtin.abi.float() == .soft) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .x86_64 and builtin.os.tag != .windows) return error.SkipZigTest;

    const v = c_ret_vector_6_u8();
    try expect(v[0] == 53);
    try expect(v[1] == 54);
    try expect(v[2] == 55);
    try expect(v[3] == 56);
    try expect(v[4] == 57);
    try expect(v[5] == 58);
    c_vector_6_u8(.{ 59, 60, 61, 62, 63, 64 }, 6);
    c_test_vector_6_u8();
}

export fn zig_ret_vector_8_u8() @Vector(8, u8) {
    return .{ 65, 66, 67, 68, 69, 70, 71, 72 };
}
export fn zig_vector_8_u8(v: @Vector(8, u8), i: usize) void {
    expect(v[0] == 73) catch @panic("test failure");
    expect(v[1] == 74) catch @panic("test failure");
    expect(v[2] == 75) catch @panic("test failure");
    expect(v[3] == 76) catch @panic("test failure");
    expect(v[4] == 77) catch @panic("test failure");
    expect(v[5] == 78) catch @panic("test failure");
    expect(v[6] == 79) catch @panic("test failure");
    expect(v[7] == 80) catch @panic("test failure");
    expect(i == 8) catch @panic("test failure");
}

extern fn c_ret_vector_8_u8() @Vector(8, u8);
extern fn c_vector_8_u8(@Vector(8, u8), usize) void;
extern fn c_test_vector_8_u8() void;

test "@Vector(8, u8)" {
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .x86_64 and builtin.os.tag == .windows) return error.SkipZigTest;

    const v = c_ret_vector_8_u8();
    try expect(v[0] == 81);
    try expect(v[1] == 82);
    try expect(v[2] == 83);
    try expect(v[3] == 84);
    try expect(v[4] == 85);
    try expect(v[5] == 86);
    try expect(v[6] == 87);
    try expect(v[7] == 88);
    c_vector_8_u8(.{ 89, 90, 91, 92, 93, 94, 95, 96 }, 8);
    c_test_vector_8_u8();
}

export fn zig_ret_vector_12_u8() @Vector(12, u8) {
    return .{ 97, 98, 99, 0, 1, 2, 3, 4, 5, 6, 7, 8 };
}
export fn zig_vector_12_u8(v: @Vector(12, u8), i: usize) void {
    expect(v[0] == 9) catch @panic("test failure");
    expect(v[1] == 10) catch @panic("test failure");
    expect(v[2] == 11) catch @panic("test failure");
    expect(v[3] == 12) catch @panic("test failure");
    expect(v[4] == 13) catch @panic("test failure");
    expect(v[5] == 14) catch @panic("test failure");
    expect(v[6] == 15) catch @panic("test failure");
    expect(v[7] == 16) catch @panic("test failure");
    expect(v[8] == 17) catch @panic("test failure");
    expect(v[9] == 18) catch @panic("test failure");
    expect(v[10] == 19) catch @panic("test failure");
    expect(v[11] == 20) catch @panic("test failure");
    expect(i == 12) catch @panic("test failure");
}

extern fn c_ret_vector_12_u8() @Vector(12, u8);
extern fn c_vector_12_u8(@Vector(12, u8), usize) void;
extern fn c_test_vector_12_u8() void;

test "@Vector(12, u8)" {
    if (builtin.cpu.arch.isArm() and builtin.abi.float() == .soft) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;

    const v = c_ret_vector_12_u8();
    try expect(v[0] == 21);
    try expect(v[1] == 22);
    try expect(v[2] == 23);
    try expect(v[3] == 24);
    try expect(v[4] == 25);
    try expect(v[5] == 26);
    try expect(v[6] == 27);
    try expect(v[7] == 28);
    try expect(v[8] == 29);
    try expect(v[9] == 30);
    try expect(v[10] == 31);
    try expect(v[11] == 32);
    c_vector_12_u8(.{ 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44 }, 12);
    c_test_vector_12_u8();
}

export fn zig_ret_vector_16_u8() @Vector(16, u8) {
    return .{ 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60 };
}
export fn zig_vector_16_u8(v: @Vector(16, u8), i: usize) void {
    expect(v[0] == 61) catch @panic("test failure");
    expect(v[1] == 62) catch @panic("test failure");
    expect(v[2] == 63) catch @panic("test failure");
    expect(v[3] == 64) catch @panic("test failure");
    expect(v[4] == 65) catch @panic("test failure");
    expect(v[5] == 66) catch @panic("test failure");
    expect(v[6] == 67) catch @panic("test failure");
    expect(v[7] == 68) catch @panic("test failure");
    expect(v[8] == 69) catch @panic("test failure");
    expect(v[9] == 70) catch @panic("test failure");
    expect(v[10] == 71) catch @panic("test failure");
    expect(v[11] == 72) catch @panic("test failure");
    expect(v[12] == 73) catch @panic("test failure");
    expect(v[13] == 74) catch @panic("test failure");
    expect(v[14] == 75) catch @panic("test failure");
    expect(v[15] == 76) catch @panic("test failure");
    expect(i == 16) catch @panic("test failure");
}

extern fn c_ret_vector_16_u8() @Vector(16, u8);
extern fn c_vector_16_u8(@Vector(16, u8), usize) void;
extern fn c_test_vector_16_u8() void;

test "@Vector(16, u8)" {
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;

    const v = c_ret_vector_16_u8();
    try expect(v[0] == 77);
    try expect(v[1] == 78);
    try expect(v[2] == 79);
    try expect(v[3] == 80);
    try expect(v[4] == 81);
    try expect(v[5] == 82);
    try expect(v[6] == 83);
    try expect(v[7] == 84);
    try expect(v[8] == 85);
    try expect(v[9] == 86);
    try expect(v[10] == 87);
    try expect(v[11] == 88);
    try expect(v[12] == 89);
    try expect(v[13] == 90);
    try expect(v[14] == 91);
    try expect(v[15] == 92);
    c_vector_16_u8(.{ 93, 94, 95, 96, 97, 98, 99, 0, 1, 2, 3, 4, 5, 6, 7, 8 }, 16);
    c_test_vector_16_u8();
}

export fn zig_ret_vector_24_u8() @Vector(24, u8) {
    return .{
        9,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
        25, 26, 27, 28, 29, 30, 31, 32,
    };
}
export fn zig_vector_24_u8(v: @Vector(24, u8), i: usize) void {
    expect(v[0] == 33) catch @panic("test failure");
    expect(v[1] == 34) catch @panic("test failure");
    expect(v[2] == 35) catch @panic("test failure");
    expect(v[3] == 36) catch @panic("test failure");
    expect(v[4] == 37) catch @panic("test failure");
    expect(v[5] == 38) catch @panic("test failure");
    expect(v[6] == 39) catch @panic("test failure");
    expect(v[7] == 40) catch @panic("test failure");
    expect(v[8] == 41) catch @panic("test failure");
    expect(v[9] == 42) catch @panic("test failure");
    expect(v[10] == 43) catch @panic("test failure");
    expect(v[11] == 44) catch @panic("test failure");
    expect(v[12] == 45) catch @panic("test failure");
    expect(v[13] == 46) catch @panic("test failure");
    expect(v[14] == 47) catch @panic("test failure");
    expect(v[15] == 48) catch @panic("test failure");
    expect(v[16] == 49) catch @panic("test failure");
    expect(v[17] == 50) catch @panic("test failure");
    expect(v[18] == 51) catch @panic("test failure");
    expect(v[19] == 52) catch @panic("test failure");
    expect(v[20] == 53) catch @panic("test failure");
    expect(v[21] == 54) catch @panic("test failure");
    expect(v[22] == 55) catch @panic("test failure");
    expect(v[23] == 56) catch @panic("test failure");
    expect(i == 24) catch @panic("test failure");
}

extern fn c_ret_vector_24_u8() @Vector(24, u8);
extern fn c_vector_24_u8(@Vector(24, u8), usize) void;
extern fn c_test_vector_24_u8() void;

test "@Vector(24, u8)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_24_u8();
    try expect(v[0] == 57);
    try expect(v[1] == 58);
    try expect(v[2] == 59);
    try expect(v[3] == 60);
    try expect(v[4] == 61);
    try expect(v[5] == 62);
    try expect(v[6] == 63);
    try expect(v[7] == 64);
    try expect(v[8] == 65);
    try expect(v[9] == 66);
    try expect(v[10] == 67);
    try expect(v[11] == 68);
    try expect(v[12] == 69);
    try expect(v[13] == 70);
    try expect(v[14] == 71);
    try expect(v[15] == 72);
    try expect(v[16] == 73);
    try expect(v[17] == 74);
    try expect(v[18] == 75);
    try expect(v[19] == 76);
    try expect(v[20] == 77);
    try expect(v[21] == 78);
    try expect(v[22] == 79);
    try expect(v[23] == 80);
    c_vector_24_u8(.{
        81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96,
        97, 98, 99, 0,  1,  2,  3,  4,
    }, 24);
    c_test_vector_24_u8();
}

export fn zig_ret_vector_32_u8() @Vector(32, u8) {
    return .{
        5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
        21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36,
    };
}
export fn zig_vector_32_u8(v: @Vector(32, u8), i: usize) void {
    expect(v[0] == 37) catch @panic("test failure");
    expect(v[1] == 38) catch @panic("test failure");
    expect(v[2] == 39) catch @panic("test failure");
    expect(v[3] == 40) catch @panic("test failure");
    expect(v[4] == 41) catch @panic("test failure");
    expect(v[5] == 42) catch @panic("test failure");
    expect(v[6] == 43) catch @panic("test failure");
    expect(v[7] == 44) catch @panic("test failure");
    expect(v[8] == 45) catch @panic("test failure");
    expect(v[9] == 46) catch @panic("test failure");
    expect(v[10] == 47) catch @panic("test failure");
    expect(v[11] == 48) catch @panic("test failure");
    expect(v[12] == 49) catch @panic("test failure");
    expect(v[13] == 50) catch @panic("test failure");
    expect(v[14] == 51) catch @panic("test failure");
    expect(v[15] == 52) catch @panic("test failure");
    expect(v[16] == 53) catch @panic("test failure");
    expect(v[17] == 54) catch @panic("test failure");
    expect(v[18] == 55) catch @panic("test failure");
    expect(v[19] == 56) catch @panic("test failure");
    expect(v[20] == 57) catch @panic("test failure");
    expect(v[21] == 58) catch @panic("test failure");
    expect(v[22] == 59) catch @panic("test failure");
    expect(v[23] == 60) catch @panic("test failure");
    expect(v[24] == 61) catch @panic("test failure");
    expect(v[25] == 62) catch @panic("test failure");
    expect(v[26] == 63) catch @panic("test failure");
    expect(v[27] == 64) catch @panic("test failure");
    expect(v[28] == 65) catch @panic("test failure");
    expect(v[29] == 66) catch @panic("test failure");
    expect(v[30] == 67) catch @panic("test failure");
    expect(v[31] == 68) catch @panic("test failure");
    expect(i == 32) catch @panic("test failure");
}

extern fn c_ret_vector_32_u8() @Vector(32, u8);
extern fn c_vector_32_u8(@Vector(32, u8), usize) void;
extern fn c_test_vector_32_u8() void;

test "@Vector(32, u8)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_32_u8();
    try expect(v[0] == 69);
    try expect(v[1] == 70);
    try expect(v[2] == 71);
    try expect(v[3] == 72);
    try expect(v[4] == 73);
    try expect(v[5] == 74);
    try expect(v[6] == 75);
    try expect(v[7] == 76);
    try expect(v[8] == 77);
    try expect(v[9] == 78);
    try expect(v[10] == 79);
    try expect(v[11] == 80);
    try expect(v[12] == 81);
    try expect(v[13] == 82);
    try expect(v[14] == 83);
    try expect(v[15] == 84);
    try expect(v[16] == 85);
    try expect(v[17] == 86);
    try expect(v[18] == 87);
    try expect(v[19] == 88);
    try expect(v[20] == 89);
    try expect(v[21] == 90);
    try expect(v[22] == 91);
    try expect(v[23] == 92);
    try expect(v[24] == 93);
    try expect(v[25] == 94);
    try expect(v[26] == 95);
    try expect(v[27] == 96);
    try expect(v[28] == 97);
    try expect(v[29] == 98);
    try expect(v[30] == 99);
    try expect(v[31] == 0);
    c_vector_32_u8(.{
        1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16,
        17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
    }, 32);
    c_test_vector_32_u8();
}

export fn zig_ret_vector_48_u8() @Vector(48, u8) {
    return .{
        33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48,
        49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64,
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80,
    };
}
export fn zig_vector_48_u8(v: @Vector(48, u8), i: usize) void {
    expect(v[0] == 81) catch @panic("test failure");
    expect(v[1] == 82) catch @panic("test failure");
    expect(v[2] == 83) catch @panic("test failure");
    expect(v[3] == 84) catch @panic("test failure");
    expect(v[4] == 85) catch @panic("test failure");
    expect(v[5] == 86) catch @panic("test failure");
    expect(v[6] == 87) catch @panic("test failure");
    expect(v[7] == 88) catch @panic("test failure");
    expect(v[8] == 89) catch @panic("test failure");
    expect(v[9] == 90) catch @panic("test failure");
    expect(v[10] == 91) catch @panic("test failure");
    expect(v[11] == 92) catch @panic("test failure");
    expect(v[12] == 93) catch @panic("test failure");
    expect(v[13] == 94) catch @panic("test failure");
    expect(v[14] == 95) catch @panic("test failure");
    expect(v[15] == 96) catch @panic("test failure");
    expect(v[16] == 97) catch @panic("test failure");
    expect(v[17] == 98) catch @panic("test failure");
    expect(v[18] == 99) catch @panic("test failure");
    expect(v[19] == 0) catch @panic("test failure");
    expect(v[20] == 1) catch @panic("test failure");
    expect(v[21] == 2) catch @panic("test failure");
    expect(v[22] == 3) catch @panic("test failure");
    expect(v[23] == 4) catch @panic("test failure");
    expect(v[24] == 5) catch @panic("test failure");
    expect(v[25] == 6) catch @panic("test failure");
    expect(v[26] == 7) catch @panic("test failure");
    expect(v[27] == 8) catch @panic("test failure");
    expect(v[28] == 9) catch @panic("test failure");
    expect(v[29] == 10) catch @panic("test failure");
    expect(v[30] == 11) catch @panic("test failure");
    expect(v[31] == 12) catch @panic("test failure");
    expect(v[32] == 13) catch @panic("test failure");
    expect(v[33] == 14) catch @panic("test failure");
    expect(v[34] == 15) catch @panic("test failure");
    expect(v[35] == 16) catch @panic("test failure");
    expect(v[36] == 17) catch @panic("test failure");
    expect(v[37] == 18) catch @panic("test failure");
    expect(v[38] == 19) catch @panic("test failure");
    expect(v[39] == 20) catch @panic("test failure");
    expect(v[40] == 21) catch @panic("test failure");
    expect(v[41] == 22) catch @panic("test failure");
    expect(v[42] == 23) catch @panic("test failure");
    expect(v[43] == 24) catch @panic("test failure");
    expect(v[44] == 25) catch @panic("test failure");
    expect(v[45] == 26) catch @panic("test failure");
    expect(v[46] == 27) catch @panic("test failure");
    expect(v[47] == 28) catch @panic("test failure");
    expect(i == 48) catch @panic("test failure");
}

extern fn c_ret_vector_48_u8() @Vector(48, u8);
extern fn c_vector_48_u8(@Vector(48, u8), usize) void;
extern fn c_test_vector_48_u8() void;

test "@Vector(48, u8)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_48_u8();
    try expect(v[0] == 29);
    try expect(v[1] == 30);
    try expect(v[2] == 31);
    try expect(v[3] == 32);
    try expect(v[4] == 33);
    try expect(v[5] == 34);
    try expect(v[6] == 35);
    try expect(v[7] == 36);
    try expect(v[8] == 37);
    try expect(v[9] == 38);
    try expect(v[10] == 39);
    try expect(v[11] == 40);
    try expect(v[12] == 41);
    try expect(v[13] == 42);
    try expect(v[14] == 43);
    try expect(v[15] == 44);
    try expect(v[16] == 45);
    try expect(v[17] == 46);
    try expect(v[18] == 47);
    try expect(v[19] == 48);
    try expect(v[20] == 49);
    try expect(v[21] == 50);
    try expect(v[22] == 51);
    try expect(v[23] == 52);
    try expect(v[24] == 53);
    try expect(v[25] == 54);
    try expect(v[26] == 55);
    try expect(v[27] == 56);
    try expect(v[28] == 57);
    try expect(v[29] == 58);
    try expect(v[30] == 59);
    try expect(v[31] == 60);
    try expect(v[32] == 61);
    try expect(v[33] == 62);
    try expect(v[34] == 63);
    try expect(v[35] == 64);
    try expect(v[36] == 65);
    try expect(v[37] == 66);
    try expect(v[38] == 67);
    try expect(v[39] == 68);
    try expect(v[40] == 69);
    try expect(v[41] == 70);
    try expect(v[42] == 71);
    try expect(v[43] == 72);
    try expect(v[44] == 73);
    try expect(v[45] == 74);
    try expect(v[46] == 75);
    try expect(v[47] == 76);
    c_vector_48_u8(.{
        77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92,
        93, 94, 95, 96, 97, 98, 99, 0,  1,  2,  3,  4,  5,  6,  7,  8,
        9,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
    }, 48);
    c_test_vector_48_u8();
}

export fn zig_ret_vector_64_u8() @Vector(64, u8) {
    return .{
        25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
        41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56,
        57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72,
        73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88,
    };
}
export fn zig_vector_64_u8(v: @Vector(64, u8), i: usize) void {
    expect(v[0] == 89) catch @panic("test failure");
    expect(v[1] == 90) catch @panic("test failure");
    expect(v[2] == 91) catch @panic("test failure");
    expect(v[3] == 92) catch @panic("test failure");
    expect(v[4] == 93) catch @panic("test failure");
    expect(v[5] == 94) catch @panic("test failure");
    expect(v[6] == 95) catch @panic("test failure");
    expect(v[7] == 96) catch @panic("test failure");
    expect(v[8] == 97) catch @panic("test failure");
    expect(v[9] == 98) catch @panic("test failure");
    expect(v[10] == 99) catch @panic("test failure");
    expect(v[11] == 0) catch @panic("test failure");
    expect(v[12] == 1) catch @panic("test failure");
    expect(v[13] == 2) catch @panic("test failure");
    expect(v[14] == 3) catch @panic("test failure");
    expect(v[15] == 4) catch @panic("test failure");
    expect(v[16] == 5) catch @panic("test failure");
    expect(v[17] == 6) catch @panic("test failure");
    expect(v[18] == 7) catch @panic("test failure");
    expect(v[19] == 8) catch @panic("test failure");
    expect(v[20] == 9) catch @panic("test failure");
    expect(v[21] == 10) catch @panic("test failure");
    expect(v[22] == 11) catch @panic("test failure");
    expect(v[23] == 12) catch @panic("test failure");
    expect(v[24] == 13) catch @panic("test failure");
    expect(v[25] == 14) catch @panic("test failure");
    expect(v[26] == 15) catch @panic("test failure");
    expect(v[27] == 16) catch @panic("test failure");
    expect(v[28] == 17) catch @panic("test failure");
    expect(v[29] == 18) catch @panic("test failure");
    expect(v[30] == 19) catch @panic("test failure");
    expect(v[31] == 20) catch @panic("test failure");
    expect(v[32] == 21) catch @panic("test failure");
    expect(v[33] == 22) catch @panic("test failure");
    expect(v[34] == 23) catch @panic("test failure");
    expect(v[35] == 24) catch @panic("test failure");
    expect(v[36] == 25) catch @panic("test failure");
    expect(v[37] == 26) catch @panic("test failure");
    expect(v[38] == 27) catch @panic("test failure");
    expect(v[39] == 28) catch @panic("test failure");
    expect(v[40] == 29) catch @panic("test failure");
    expect(v[41] == 30) catch @panic("test failure");
    expect(v[42] == 31) catch @panic("test failure");
    expect(v[43] == 32) catch @panic("test failure");
    expect(v[44] == 33) catch @panic("test failure");
    expect(v[45] == 34) catch @panic("test failure");
    expect(v[46] == 35) catch @panic("test failure");
    expect(v[47] == 36) catch @panic("test failure");
    expect(v[48] == 37) catch @panic("test failure");
    expect(v[49] == 38) catch @panic("test failure");
    expect(v[50] == 39) catch @panic("test failure");
    expect(v[51] == 40) catch @panic("test failure");
    expect(v[52] == 41) catch @panic("test failure");
    expect(v[53] == 42) catch @panic("test failure");
    expect(v[54] == 43) catch @panic("test failure");
    expect(v[55] == 44) catch @panic("test failure");
    expect(v[56] == 45) catch @panic("test failure");
    expect(v[57] == 46) catch @panic("test failure");
    expect(v[58] == 47) catch @panic("test failure");
    expect(v[59] == 48) catch @panic("test failure");
    expect(v[60] == 49) catch @panic("test failure");
    expect(v[61] == 50) catch @panic("test failure");
    expect(v[62] == 51) catch @panic("test failure");
    expect(v[63] == 52) catch @panic("test failure");
    expect(i == 64) catch @panic("test failure");
}

extern fn c_ret_vector_64_u8() @Vector(64, u8);
extern fn c_vector_64_u8(@Vector(64, u8), usize) void;
extern fn c_test_vector_64_u8() void;

test "@Vector(64, u8)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_64_u8();
    try expect(v[0] == 53);
    try expect(v[1] == 54);
    try expect(v[2] == 55);
    try expect(v[3] == 56);
    try expect(v[4] == 57);
    try expect(v[5] == 58);
    try expect(v[6] == 59);
    try expect(v[7] == 60);
    try expect(v[8] == 61);
    try expect(v[9] == 62);
    try expect(v[10] == 63);
    try expect(v[11] == 64);
    try expect(v[12] == 65);
    try expect(v[13] == 66);
    try expect(v[14] == 67);
    try expect(v[15] == 68);
    try expect(v[16] == 69);
    try expect(v[17] == 70);
    try expect(v[18] == 71);
    try expect(v[19] == 72);
    try expect(v[20] == 73);
    try expect(v[21] == 74);
    try expect(v[22] == 75);
    try expect(v[23] == 76);
    try expect(v[24] == 77);
    try expect(v[25] == 78);
    try expect(v[26] == 79);
    try expect(v[27] == 80);
    try expect(v[28] == 81);
    try expect(v[29] == 82);
    try expect(v[30] == 83);
    try expect(v[31] == 84);
    try expect(v[32] == 85);
    try expect(v[33] == 86);
    try expect(v[34] == 87);
    try expect(v[35] == 88);
    try expect(v[36] == 89);
    try expect(v[37] == 90);
    try expect(v[38] == 91);
    try expect(v[39] == 92);
    try expect(v[40] == 93);
    try expect(v[41] == 94);
    try expect(v[42] == 95);
    try expect(v[43] == 96);
    try expect(v[44] == 97);
    try expect(v[45] == 98);
    try expect(v[46] == 99);
    try expect(v[47] == 0);
    try expect(v[48] == 1);
    try expect(v[49] == 2);
    try expect(v[50] == 3);
    try expect(v[51] == 4);
    try expect(v[52] == 5);
    try expect(v[53] == 6);
    try expect(v[54] == 7);
    try expect(v[55] == 8);
    try expect(v[56] == 9);
    try expect(v[57] == 10);
    try expect(v[58] == 11);
    try expect(v[59] == 12);
    try expect(v[60] == 13);
    try expect(v[61] == 14);
    try expect(v[62] == 15);
    try expect(v[63] == 16);
    c_vector_64_u8(.{
        17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
        33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48,
        49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64,
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80,
    }, 64);
    c_test_vector_64_u8();
}

export fn zig_ret_vector_96_u8() @Vector(96, u8) {
    return .{
        90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,  1,  2,  3,  4,  5,
        6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
        22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37,
        38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53,
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69,
        70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85,
    };
}
export fn zig_vector_96_u8(v: @Vector(96, u8), i: usize) void {
    expect(v[0] == 86) catch @panic("test failure");
    expect(v[1] == 87) catch @panic("test failure");
    expect(v[2] == 88) catch @panic("test failure");
    expect(v[3] == 89) catch @panic("test failure");
    expect(v[4] == 90) catch @panic("test failure");
    expect(v[5] == 91) catch @panic("test failure");
    expect(v[6] == 92) catch @panic("test failure");
    expect(v[7] == 93) catch @panic("test failure");
    expect(v[8] == 94) catch @panic("test failure");
    expect(v[9] == 95) catch @panic("test failure");
    expect(v[10] == 96) catch @panic("test failure");
    expect(v[11] == 97) catch @panic("test failure");
    expect(v[12] == 98) catch @panic("test failure");
    expect(v[13] == 99) catch @panic("test failure");
    expect(v[14] == 0) catch @panic("test failure");
    expect(v[15] == 1) catch @panic("test failure");
    expect(v[16] == 2) catch @panic("test failure");
    expect(v[17] == 3) catch @panic("test failure");
    expect(v[18] == 4) catch @panic("test failure");
    expect(v[19] == 5) catch @panic("test failure");
    expect(v[20] == 6) catch @panic("test failure");
    expect(v[21] == 7) catch @panic("test failure");
    expect(v[22] == 8) catch @panic("test failure");
    expect(v[23] == 9) catch @panic("test failure");
    expect(v[24] == 10) catch @panic("test failure");
    expect(v[25] == 11) catch @panic("test failure");
    expect(v[26] == 12) catch @panic("test failure");
    expect(v[27] == 13) catch @panic("test failure");
    expect(v[28] == 14) catch @panic("test failure");
    expect(v[29] == 15) catch @panic("test failure");
    expect(v[30] == 16) catch @panic("test failure");
    expect(v[31] == 17) catch @panic("test failure");
    expect(v[32] == 18) catch @panic("test failure");
    expect(v[33] == 19) catch @panic("test failure");
    expect(v[34] == 20) catch @panic("test failure");
    expect(v[35] == 21) catch @panic("test failure");
    expect(v[36] == 22) catch @panic("test failure");
    expect(v[37] == 23) catch @panic("test failure");
    expect(v[38] == 24) catch @panic("test failure");
    expect(v[39] == 25) catch @panic("test failure");
    expect(v[40] == 26) catch @panic("test failure");
    expect(v[41] == 27) catch @panic("test failure");
    expect(v[42] == 28) catch @panic("test failure");
    expect(v[43] == 29) catch @panic("test failure");
    expect(v[44] == 30) catch @panic("test failure");
    expect(v[45] == 31) catch @panic("test failure");
    expect(v[46] == 32) catch @panic("test failure");
    expect(v[47] == 33) catch @panic("test failure");
    expect(v[48] == 34) catch @panic("test failure");
    expect(v[49] == 35) catch @panic("test failure");
    expect(v[50] == 36) catch @panic("test failure");
    expect(v[51] == 37) catch @panic("test failure");
    expect(v[52] == 38) catch @panic("test failure");
    expect(v[53] == 39) catch @panic("test failure");
    expect(v[54] == 40) catch @panic("test failure");
    expect(v[55] == 41) catch @panic("test failure");
    expect(v[56] == 42) catch @panic("test failure");
    expect(v[57] == 43) catch @panic("test failure");
    expect(v[58] == 44) catch @panic("test failure");
    expect(v[59] == 45) catch @panic("test failure");
    expect(v[60] == 46) catch @panic("test failure");
    expect(v[61] == 47) catch @panic("test failure");
    expect(v[62] == 48) catch @panic("test failure");
    expect(v[63] == 49) catch @panic("test failure");
    expect(v[64] == 50) catch @panic("test failure");
    expect(v[65] == 51) catch @panic("test failure");
    expect(v[66] == 52) catch @panic("test failure");
    expect(v[67] == 53) catch @panic("test failure");
    expect(v[68] == 54) catch @panic("test failure");
    expect(v[69] == 55) catch @panic("test failure");
    expect(v[70] == 56) catch @panic("test failure");
    expect(v[71] == 57) catch @panic("test failure");
    expect(v[72] == 58) catch @panic("test failure");
    expect(v[73] == 59) catch @panic("test failure");
    expect(v[74] == 60) catch @panic("test failure");
    expect(v[75] == 61) catch @panic("test failure");
    expect(v[76] == 62) catch @panic("test failure");
    expect(v[77] == 63) catch @panic("test failure");
    expect(v[78] == 64) catch @panic("test failure");
    expect(v[79] == 65) catch @panic("test failure");
    expect(v[80] == 66) catch @panic("test failure");
    expect(v[81] == 67) catch @panic("test failure");
    expect(v[82] == 68) catch @panic("test failure");
    expect(v[83] == 69) catch @panic("test failure");
    expect(v[84] == 70) catch @panic("test failure");
    expect(v[85] == 71) catch @panic("test failure");
    expect(v[86] == 72) catch @panic("test failure");
    expect(v[87] == 73) catch @panic("test failure");
    expect(v[88] == 74) catch @panic("test failure");
    expect(v[89] == 75) catch @panic("test failure");
    expect(v[90] == 76) catch @panic("test failure");
    expect(v[91] == 77) catch @panic("test failure");
    expect(v[92] == 78) catch @panic("test failure");
    expect(v[93] == 79) catch @panic("test failure");
    expect(v[94] == 80) catch @panic("test failure");
    expect(v[95] == 81) catch @panic("test failure");
    expect(i == 96) catch @panic("test failure");
}

extern fn c_ret_vector_96_u8() @Vector(96, u8);
extern fn c_vector_96_u8(@Vector(96, u8), usize) void;
extern fn c_test_vector_96_u8() void;

test "@Vector(96, u8)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_96_u8();
    try expect(v[0] == 82);
    try expect(v[1] == 83);
    try expect(v[2] == 84);
    try expect(v[3] == 85);
    try expect(v[4] == 86);
    try expect(v[5] == 87);
    try expect(v[6] == 88);
    try expect(v[7] == 89);
    try expect(v[8] == 90);
    try expect(v[9] == 91);
    try expect(v[10] == 92);
    try expect(v[11] == 93);
    try expect(v[12] == 94);
    try expect(v[13] == 95);
    try expect(v[14] == 96);
    try expect(v[15] == 97);
    try expect(v[16] == 98);
    try expect(v[17] == 99);
    try expect(v[18] == 0);
    try expect(v[19] == 1);
    try expect(v[20] == 2);
    try expect(v[21] == 3);
    try expect(v[22] == 4);
    try expect(v[23] == 5);
    try expect(v[24] == 6);
    try expect(v[25] == 7);
    try expect(v[26] == 8);
    try expect(v[27] == 9);
    try expect(v[28] == 10);
    try expect(v[29] == 11);
    try expect(v[30] == 12);
    try expect(v[31] == 13);
    try expect(v[32] == 14);
    try expect(v[33] == 15);
    try expect(v[34] == 16);
    try expect(v[35] == 17);
    try expect(v[36] == 18);
    try expect(v[37] == 19);
    try expect(v[38] == 20);
    try expect(v[39] == 21);
    try expect(v[40] == 22);
    try expect(v[41] == 23);
    try expect(v[42] == 24);
    try expect(v[43] == 25);
    try expect(v[44] == 26);
    try expect(v[45] == 27);
    try expect(v[46] == 28);
    try expect(v[47] == 29);
    try expect(v[48] == 30);
    try expect(v[49] == 31);
    try expect(v[50] == 32);
    try expect(v[51] == 33);
    try expect(v[52] == 34);
    try expect(v[53] == 35);
    try expect(v[54] == 36);
    try expect(v[55] == 37);
    try expect(v[56] == 38);
    try expect(v[57] == 39);
    try expect(v[58] == 40);
    try expect(v[59] == 41);
    try expect(v[60] == 42);
    try expect(v[61] == 43);
    try expect(v[62] == 44);
    try expect(v[63] == 45);
    try expect(v[64] == 46);
    try expect(v[65] == 47);
    try expect(v[66] == 48);
    try expect(v[67] == 49);
    try expect(v[68] == 50);
    try expect(v[69] == 51);
    try expect(v[70] == 52);
    try expect(v[71] == 53);
    try expect(v[72] == 54);
    try expect(v[73] == 55);
    try expect(v[74] == 56);
    try expect(v[75] == 57);
    try expect(v[76] == 58);
    try expect(v[77] == 59);
    try expect(v[78] == 60);
    try expect(v[79] == 61);
    try expect(v[80] == 62);
    try expect(v[81] == 63);
    try expect(v[82] == 64);
    try expect(v[83] == 65);
    try expect(v[84] == 66);
    try expect(v[85] == 67);
    try expect(v[86] == 68);
    try expect(v[87] == 69);
    try expect(v[88] == 70);
    try expect(v[89] == 71);
    try expect(v[90] == 72);
    try expect(v[91] == 73);
    try expect(v[92] == 74);
    try expect(v[93] == 75);
    try expect(v[94] == 76);
    try expect(v[95] == 77);
    c_vector_96_u8(.{
        78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93,
        94, 95, 96, 97, 98, 99, 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,
        10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,
        26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41,
        42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
        58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73,
    }, 96);
    c_test_vector_96_u8();
}

export fn zig_ret_vector_128_u8() @Vector(128, u8) {
    return .{
        74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89,
        90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,  1,  2,  3,  4,  5,
        6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
        22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37,
        38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53,
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69,
        70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85,
        86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,  1,
    };
}
export fn zig_vector_128_u8(v: @Vector(128, u8), i: usize) void {
    expect(v[0] == 2) catch @panic("test failure");
    expect(v[1] == 3) catch @panic("test failure");
    expect(v[2] == 4) catch @panic("test failure");
    expect(v[3] == 5) catch @panic("test failure");
    expect(v[4] == 6) catch @panic("test failure");
    expect(v[5] == 7) catch @panic("test failure");
    expect(v[6] == 8) catch @panic("test failure");
    expect(v[7] == 9) catch @panic("test failure");
    expect(v[8] == 10) catch @panic("test failure");
    expect(v[9] == 11) catch @panic("test failure");
    expect(v[10] == 12) catch @panic("test failure");
    expect(v[11] == 13) catch @panic("test failure");
    expect(v[12] == 14) catch @panic("test failure");
    expect(v[13] == 15) catch @panic("test failure");
    expect(v[14] == 16) catch @panic("test failure");
    expect(v[15] == 17) catch @panic("test failure");
    expect(v[16] == 18) catch @panic("test failure");
    expect(v[17] == 19) catch @panic("test failure");
    expect(v[18] == 20) catch @panic("test failure");
    expect(v[19] == 21) catch @panic("test failure");
    expect(v[20] == 22) catch @panic("test failure");
    expect(v[21] == 23) catch @panic("test failure");
    expect(v[22] == 24) catch @panic("test failure");
    expect(v[23] == 25) catch @panic("test failure");
    expect(v[24] == 26) catch @panic("test failure");
    expect(v[25] == 27) catch @panic("test failure");
    expect(v[26] == 28) catch @panic("test failure");
    expect(v[27] == 29) catch @panic("test failure");
    expect(v[28] == 30) catch @panic("test failure");
    expect(v[29] == 31) catch @panic("test failure");
    expect(v[30] == 32) catch @panic("test failure");
    expect(v[31] == 33) catch @panic("test failure");
    expect(v[32] == 34) catch @panic("test failure");
    expect(v[33] == 35) catch @panic("test failure");
    expect(v[34] == 36) catch @panic("test failure");
    expect(v[35] == 37) catch @panic("test failure");
    expect(v[36] == 38) catch @panic("test failure");
    expect(v[37] == 39) catch @panic("test failure");
    expect(v[38] == 40) catch @panic("test failure");
    expect(v[39] == 41) catch @panic("test failure");
    expect(v[40] == 42) catch @panic("test failure");
    expect(v[41] == 43) catch @panic("test failure");
    expect(v[42] == 44) catch @panic("test failure");
    expect(v[43] == 45) catch @panic("test failure");
    expect(v[44] == 46) catch @panic("test failure");
    expect(v[45] == 47) catch @panic("test failure");
    expect(v[46] == 48) catch @panic("test failure");
    expect(v[47] == 49) catch @panic("test failure");
    expect(v[48] == 50) catch @panic("test failure");
    expect(v[49] == 51) catch @panic("test failure");
    expect(v[50] == 52) catch @panic("test failure");
    expect(v[51] == 53) catch @panic("test failure");
    expect(v[52] == 54) catch @panic("test failure");
    expect(v[53] == 55) catch @panic("test failure");
    expect(v[54] == 56) catch @panic("test failure");
    expect(v[55] == 57) catch @panic("test failure");
    expect(v[56] == 58) catch @panic("test failure");
    expect(v[57] == 59) catch @panic("test failure");
    expect(v[58] == 60) catch @panic("test failure");
    expect(v[59] == 61) catch @panic("test failure");
    expect(v[60] == 62) catch @panic("test failure");
    expect(v[61] == 63) catch @panic("test failure");
    expect(v[62] == 64) catch @panic("test failure");
    expect(v[63] == 65) catch @panic("test failure");
    expect(v[64] == 66) catch @panic("test failure");
    expect(v[65] == 67) catch @panic("test failure");
    expect(v[66] == 68) catch @panic("test failure");
    expect(v[67] == 69) catch @panic("test failure");
    expect(v[68] == 70) catch @panic("test failure");
    expect(v[69] == 71) catch @panic("test failure");
    expect(v[70] == 72) catch @panic("test failure");
    expect(v[71] == 73) catch @panic("test failure");
    expect(v[72] == 74) catch @panic("test failure");
    expect(v[73] == 75) catch @panic("test failure");
    expect(v[74] == 76) catch @panic("test failure");
    expect(v[75] == 77) catch @panic("test failure");
    expect(v[76] == 78) catch @panic("test failure");
    expect(v[77] == 79) catch @panic("test failure");
    expect(v[78] == 80) catch @panic("test failure");
    expect(v[79] == 81) catch @panic("test failure");
    expect(v[80] == 82) catch @panic("test failure");
    expect(v[81] == 83) catch @panic("test failure");
    expect(v[82] == 84) catch @panic("test failure");
    expect(v[83] == 85) catch @panic("test failure");
    expect(v[84] == 86) catch @panic("test failure");
    expect(v[85] == 87) catch @panic("test failure");
    expect(v[86] == 88) catch @panic("test failure");
    expect(v[87] == 89) catch @panic("test failure");
    expect(v[88] == 90) catch @panic("test failure");
    expect(v[89] == 91) catch @panic("test failure");
    expect(v[90] == 92) catch @panic("test failure");
    expect(v[91] == 93) catch @panic("test failure");
    expect(v[92] == 94) catch @panic("test failure");
    expect(v[93] == 95) catch @panic("test failure");
    expect(v[94] == 96) catch @panic("test failure");
    expect(v[95] == 97) catch @panic("test failure");
    expect(v[96] == 98) catch @panic("test failure");
    expect(v[97] == 99) catch @panic("test failure");
    expect(v[98] == 0) catch @panic("test failure");
    expect(v[99] == 1) catch @panic("test failure");
    expect(v[100] == 2) catch @panic("test failure");
    expect(v[101] == 3) catch @panic("test failure");
    expect(v[102] == 4) catch @panic("test failure");
    expect(v[103] == 5) catch @panic("test failure");
    expect(v[104] == 6) catch @panic("test failure");
    expect(v[105] == 7) catch @panic("test failure");
    expect(v[106] == 8) catch @panic("test failure");
    expect(v[107] == 9) catch @panic("test failure");
    expect(v[108] == 10) catch @panic("test failure");
    expect(v[109] == 11) catch @panic("test failure");
    expect(v[110] == 12) catch @panic("test failure");
    expect(v[111] == 13) catch @panic("test failure");
    expect(v[112] == 14) catch @panic("test failure");
    expect(v[113] == 15) catch @panic("test failure");
    expect(v[114] == 16) catch @panic("test failure");
    expect(v[115] == 17) catch @panic("test failure");
    expect(v[116] == 18) catch @panic("test failure");
    expect(v[117] == 19) catch @panic("test failure");
    expect(v[118] == 20) catch @panic("test failure");
    expect(v[119] == 21) catch @panic("test failure");
    expect(v[120] == 22) catch @panic("test failure");
    expect(v[121] == 23) catch @panic("test failure");
    expect(v[122] == 24) catch @panic("test failure");
    expect(v[123] == 25) catch @panic("test failure");
    expect(v[124] == 26) catch @panic("test failure");
    expect(v[125] == 27) catch @panic("test failure");
    expect(v[126] == 28) catch @panic("test failure");
    expect(v[127] == 29) catch @panic("test failure");
    expect(i == 128) catch @panic("test failure");
}

extern fn c_ret_vector_128_u8() @Vector(128, u8);
extern fn c_vector_128_u8(@Vector(128, u8), usize) void;
extern fn c_test_vector_128_u8() void;

test "@Vector(128, u8)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_128_u8();
    try expect(v[0] == 30);
    try expect(v[1] == 31);
    try expect(v[2] == 32);
    try expect(v[3] == 33);
    try expect(v[4] == 34);
    try expect(v[5] == 35);
    try expect(v[6] == 36);
    try expect(v[7] == 37);
    try expect(v[8] == 38);
    try expect(v[9] == 39);
    try expect(v[10] == 40);
    try expect(v[11] == 41);
    try expect(v[12] == 42);
    try expect(v[13] == 43);
    try expect(v[14] == 44);
    try expect(v[15] == 45);
    try expect(v[16] == 46);
    try expect(v[17] == 47);
    try expect(v[18] == 48);
    try expect(v[19] == 49);
    try expect(v[20] == 50);
    try expect(v[21] == 51);
    try expect(v[22] == 52);
    try expect(v[23] == 53);
    try expect(v[24] == 54);
    try expect(v[25] == 55);
    try expect(v[26] == 56);
    try expect(v[27] == 57);
    try expect(v[28] == 58);
    try expect(v[29] == 59);
    try expect(v[30] == 60);
    try expect(v[31] == 61);
    try expect(v[32] == 62);
    try expect(v[33] == 63);
    try expect(v[34] == 64);
    try expect(v[35] == 65);
    try expect(v[36] == 66);
    try expect(v[37] == 67);
    try expect(v[38] == 68);
    try expect(v[39] == 69);
    try expect(v[40] == 70);
    try expect(v[41] == 71);
    try expect(v[42] == 72);
    try expect(v[43] == 73);
    try expect(v[44] == 74);
    try expect(v[45] == 75);
    try expect(v[46] == 76);
    try expect(v[47] == 77);
    try expect(v[48] == 78);
    try expect(v[49] == 79);
    try expect(v[50] == 80);
    try expect(v[51] == 81);
    try expect(v[52] == 82);
    try expect(v[53] == 83);
    try expect(v[54] == 84);
    try expect(v[55] == 85);
    try expect(v[56] == 86);
    try expect(v[57] == 87);
    try expect(v[58] == 88);
    try expect(v[59] == 89);
    try expect(v[60] == 90);
    try expect(v[61] == 91);
    try expect(v[62] == 92);
    try expect(v[63] == 93);
    try expect(v[64] == 94);
    try expect(v[65] == 95);
    try expect(v[66] == 96);
    try expect(v[67] == 97);
    try expect(v[68] == 98);
    try expect(v[69] == 99);
    try expect(v[70] == 0);
    try expect(v[71] == 1);
    try expect(v[72] == 2);
    try expect(v[73] == 3);
    try expect(v[74] == 4);
    try expect(v[75] == 5);
    try expect(v[76] == 6);
    try expect(v[77] == 7);
    try expect(v[78] == 8);
    try expect(v[79] == 9);
    try expect(v[80] == 10);
    try expect(v[81] == 11);
    try expect(v[82] == 12);
    try expect(v[83] == 13);
    try expect(v[84] == 14);
    try expect(v[85] == 15);
    try expect(v[86] == 16);
    try expect(v[87] == 17);
    try expect(v[88] == 18);
    try expect(v[89] == 19);
    try expect(v[90] == 20);
    try expect(v[91] == 21);
    try expect(v[92] == 22);
    try expect(v[93] == 23);
    try expect(v[94] == 24);
    try expect(v[95] == 25);
    try expect(v[96] == 26);
    try expect(v[97] == 27);
    try expect(v[98] == 28);
    try expect(v[99] == 29);
    try expect(v[100] == 30);
    try expect(v[101] == 31);
    try expect(v[102] == 32);
    try expect(v[103] == 33);
    try expect(v[104] == 34);
    try expect(v[105] == 35);
    try expect(v[106] == 36);
    try expect(v[107] == 37);
    try expect(v[108] == 38);
    try expect(v[109] == 39);
    try expect(v[110] == 40);
    try expect(v[111] == 41);
    try expect(v[112] == 42);
    try expect(v[113] == 43);
    try expect(v[114] == 44);
    try expect(v[115] == 45);
    try expect(v[116] == 46);
    try expect(v[117] == 47);
    try expect(v[118] == 48);
    try expect(v[119] == 49);
    try expect(v[120] == 50);
    try expect(v[121] == 51);
    try expect(v[122] == 52);
    try expect(v[123] == 53);
    try expect(v[124] == 54);
    try expect(v[125] == 55);
    try expect(v[126] == 56);
    try expect(v[127] == 57);
    c_vector_128_u8(.{
        58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73,
        74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89,
        90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 0,  1,  2,  3,  4,  5,
        6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
        22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37,
        38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53,
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69,
        70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85,
    }, 128);
    c_test_vector_128_u8();
}

export fn zig_ret_vector_192_u8() @Vector(192, u8) {
    return .{
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
    };
}
export fn zig_vector_192_u8(v: @Vector(192, u8), i: usize) void {
    expect(v[0] == 78) catch @panic("test failure");
    expect(v[1] == 79) catch @panic("test failure");
    expect(v[2] == 80) catch @panic("test failure");
    expect(v[3] == 81) catch @panic("test failure");
    expect(v[4] == 82) catch @panic("test failure");
    expect(v[5] == 83) catch @panic("test failure");
    expect(v[6] == 84) catch @panic("test failure");
    expect(v[7] == 85) catch @panic("test failure");
    expect(v[8] == 86) catch @panic("test failure");
    expect(v[9] == 87) catch @panic("test failure");
    expect(v[10] == 88) catch @panic("test failure");
    expect(v[11] == 89) catch @panic("test failure");
    expect(v[12] == 90) catch @panic("test failure");
    expect(v[13] == 91) catch @panic("test failure");
    expect(v[14] == 92) catch @panic("test failure");
    expect(v[15] == 93) catch @panic("test failure");
    expect(v[16] == 94) catch @panic("test failure");
    expect(v[17] == 95) catch @panic("test failure");
    expect(v[18] == 96) catch @panic("test failure");
    expect(v[19] == 97) catch @panic("test failure");
    expect(v[20] == 98) catch @panic("test failure");
    expect(v[21] == 99) catch @panic("test failure");
    expect(v[22] == 0) catch @panic("test failure");
    expect(v[23] == 1) catch @panic("test failure");
    expect(v[24] == 2) catch @panic("test failure");
    expect(v[25] == 3) catch @panic("test failure");
    expect(v[26] == 4) catch @panic("test failure");
    expect(v[27] == 5) catch @panic("test failure");
    expect(v[28] == 6) catch @panic("test failure");
    expect(v[29] == 7) catch @panic("test failure");
    expect(v[30] == 8) catch @panic("test failure");
    expect(v[31] == 9) catch @panic("test failure");
    expect(v[32] == 10) catch @panic("test failure");
    expect(v[33] == 11) catch @panic("test failure");
    expect(v[34] == 12) catch @panic("test failure");
    expect(v[35] == 13) catch @panic("test failure");
    expect(v[36] == 14) catch @panic("test failure");
    expect(v[37] == 15) catch @panic("test failure");
    expect(v[38] == 16) catch @panic("test failure");
    expect(v[39] == 17) catch @panic("test failure");
    expect(v[40] == 18) catch @panic("test failure");
    expect(v[41] == 19) catch @panic("test failure");
    expect(v[42] == 20) catch @panic("test failure");
    expect(v[43] == 21) catch @panic("test failure");
    expect(v[44] == 22) catch @panic("test failure");
    expect(v[45] == 23) catch @panic("test failure");
    expect(v[46] == 24) catch @panic("test failure");
    expect(v[47] == 25) catch @panic("test failure");
    expect(v[48] == 26) catch @panic("test failure");
    expect(v[49] == 27) catch @panic("test failure");
    expect(v[50] == 28) catch @panic("test failure");
    expect(v[51] == 29) catch @panic("test failure");
    expect(v[52] == 30) catch @panic("test failure");
    expect(v[53] == 31) catch @panic("test failure");
    expect(v[54] == 32) catch @panic("test failure");
    expect(v[55] == 33) catch @panic("test failure");
    expect(v[56] == 34) catch @panic("test failure");
    expect(v[57] == 35) catch @panic("test failure");
    expect(v[58] == 36) catch @panic("test failure");
    expect(v[59] == 37) catch @panic("test failure");
    expect(v[60] == 38) catch @panic("test failure");
    expect(v[61] == 39) catch @panic("test failure");
    expect(v[62] == 40) catch @panic("test failure");
    expect(v[63] == 41) catch @panic("test failure");
    expect(v[64] == 42) catch @panic("test failure");
    expect(v[65] == 43) catch @panic("test failure");
    expect(v[66] == 44) catch @panic("test failure");
    expect(v[67] == 45) catch @panic("test failure");
    expect(v[68] == 46) catch @panic("test failure");
    expect(v[69] == 47) catch @panic("test failure");
    expect(v[70] == 48) catch @panic("test failure");
    expect(v[71] == 49) catch @panic("test failure");
    expect(v[72] == 50) catch @panic("test failure");
    expect(v[73] == 51) catch @panic("test failure");
    expect(v[74] == 52) catch @panic("test failure");
    expect(v[75] == 53) catch @panic("test failure");
    expect(v[76] == 54) catch @panic("test failure");
    expect(v[77] == 55) catch @panic("test failure");
    expect(v[78] == 56) catch @panic("test failure");
    expect(v[79] == 57) catch @panic("test failure");
    expect(v[80] == 58) catch @panic("test failure");
    expect(v[81] == 59) catch @panic("test failure");
    expect(v[82] == 60) catch @panic("test failure");
    expect(v[83] == 61) catch @panic("test failure");
    expect(v[84] == 62) catch @panic("test failure");
    expect(v[85] == 63) catch @panic("test failure");
    expect(v[86] == 64) catch @panic("test failure");
    expect(v[87] == 65) catch @panic("test failure");
    expect(v[88] == 66) catch @panic("test failure");
    expect(v[89] == 67) catch @panic("test failure");
    expect(v[90] == 68) catch @panic("test failure");
    expect(v[91] == 69) catch @panic("test failure");
    expect(v[92] == 70) catch @panic("test failure");
    expect(v[93] == 71) catch @panic("test failure");
    expect(v[94] == 72) catch @panic("test failure");
    expect(v[95] == 73) catch @panic("test failure");
    expect(v[96] == 74) catch @panic("test failure");
    expect(v[97] == 75) catch @panic("test failure");
    expect(v[98] == 76) catch @panic("test failure");
    expect(v[99] == 77) catch @panic("test failure");
    expect(v[100] == 78) catch @panic("test failure");
    expect(v[101] == 79) catch @panic("test failure");
    expect(v[102] == 80) catch @panic("test failure");
    expect(v[103] == 81) catch @panic("test failure");
    expect(v[104] == 82) catch @panic("test failure");
    expect(v[105] == 83) catch @panic("test failure");
    expect(v[106] == 84) catch @panic("test failure");
    expect(v[107] == 85) catch @panic("test failure");
    expect(v[108] == 86) catch @panic("test failure");
    expect(v[109] == 87) catch @panic("test failure");
    expect(v[110] == 88) catch @panic("test failure");
    expect(v[111] == 89) catch @panic("test failure");
    expect(v[112] == 90) catch @panic("test failure");
    expect(v[113] == 91) catch @panic("test failure");
    expect(v[114] == 92) catch @panic("test failure");
    expect(v[115] == 93) catch @panic("test failure");
    expect(v[116] == 94) catch @panic("test failure");
    expect(v[117] == 95) catch @panic("test failure");
    expect(v[118] == 96) catch @panic("test failure");
    expect(v[119] == 97) catch @panic("test failure");
    expect(v[120] == 98) catch @panic("test failure");
    expect(v[121] == 99) catch @panic("test failure");
    expect(v[122] == 0) catch @panic("test failure");
    expect(v[123] == 1) catch @panic("test failure");
    expect(v[124] == 2) catch @panic("test failure");
    expect(v[125] == 3) catch @panic("test failure");
    expect(v[126] == 4) catch @panic("test failure");
    expect(v[127] == 5) catch @panic("test failure");
    expect(v[128] == 6) catch @panic("test failure");
    expect(v[129] == 7) catch @panic("test failure");
    expect(v[130] == 8) catch @panic("test failure");
    expect(v[131] == 9) catch @panic("test failure");
    expect(v[132] == 10) catch @panic("test failure");
    expect(v[133] == 11) catch @panic("test failure");
    expect(v[134] == 12) catch @panic("test failure");
    expect(v[135] == 13) catch @panic("test failure");
    expect(v[136] == 14) catch @panic("test failure");
    expect(v[137] == 15) catch @panic("test failure");
    expect(v[138] == 16) catch @panic("test failure");
    expect(v[139] == 17) catch @panic("test failure");
    expect(v[140] == 18) catch @panic("test failure");
    expect(v[141] == 19) catch @panic("test failure");
    expect(v[142] == 20) catch @panic("test failure");
    expect(v[143] == 21) catch @panic("test failure");
    expect(v[144] == 22) catch @panic("test failure");
    expect(v[145] == 23) catch @panic("test failure");
    expect(v[146] == 24) catch @panic("test failure");
    expect(v[147] == 25) catch @panic("test failure");
    expect(v[148] == 26) catch @panic("test failure");
    expect(v[149] == 27) catch @panic("test failure");
    expect(v[150] == 28) catch @panic("test failure");
    expect(v[151] == 29) catch @panic("test failure");
    expect(v[152] == 30) catch @panic("test failure");
    expect(v[153] == 31) catch @panic("test failure");
    expect(v[154] == 32) catch @panic("test failure");
    expect(v[155] == 33) catch @panic("test failure");
    expect(v[156] == 34) catch @panic("test failure");
    expect(v[157] == 35) catch @panic("test failure");
    expect(v[158] == 36) catch @panic("test failure");
    expect(v[159] == 37) catch @panic("test failure");
    expect(v[160] == 38) catch @panic("test failure");
    expect(v[161] == 39) catch @panic("test failure");
    expect(v[162] == 40) catch @panic("test failure");
    expect(v[163] == 41) catch @panic("test failure");
    expect(v[164] == 42) catch @panic("test failure");
    expect(v[165] == 43) catch @panic("test failure");
    expect(v[166] == 44) catch @panic("test failure");
    expect(v[167] == 45) catch @panic("test failure");
    expect(v[168] == 46) catch @panic("test failure");
    expect(v[169] == 47) catch @panic("test failure");
    expect(v[170] == 48) catch @panic("test failure");
    expect(v[171] == 49) catch @panic("test failure");
    expect(v[172] == 50) catch @panic("test failure");
    expect(v[173] == 51) catch @panic("test failure");
    expect(v[174] == 52) catch @panic("test failure");
    expect(v[175] == 53) catch @panic("test failure");
    expect(v[176] == 54) catch @panic("test failure");
    expect(v[177] == 55) catch @panic("test failure");
    expect(v[178] == 56) catch @panic("test failure");
    expect(v[179] == 57) catch @panic("test failure");
    expect(v[180] == 58) catch @panic("test failure");
    expect(v[181] == 59) catch @panic("test failure");
    expect(v[182] == 60) catch @panic("test failure");
    expect(v[183] == 61) catch @panic("test failure");
    expect(v[184] == 62) catch @panic("test failure");
    expect(v[185] == 63) catch @panic("test failure");
    expect(v[186] == 64) catch @panic("test failure");
    expect(v[187] == 65) catch @panic("test failure");
    expect(v[188] == 66) catch @panic("test failure");
    expect(v[189] == 67) catch @panic("test failure");
    expect(v[190] == 68) catch @panic("test failure");
    expect(v[191] == 69) catch @panic("test failure");
    expect(i == 192) catch @panic("test failure");
}

extern fn c_ret_vector_192_u8() @Vector(192, u8);
extern fn c_vector_192_u8(@Vector(192, u8), usize) void;
extern fn c_test_vector_192_u8() void;

test "@Vector(192, u8)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_192_u8();
    try expect(v[0] == 70);
    try expect(v[1] == 71);
    try expect(v[2] == 72);
    try expect(v[3] == 73);
    try expect(v[4] == 74);
    try expect(v[5] == 75);
    try expect(v[6] == 76);
    try expect(v[7] == 77);
    try expect(v[8] == 78);
    try expect(v[9] == 79);
    try expect(v[10] == 80);
    try expect(v[11] == 81);
    try expect(v[12] == 82);
    try expect(v[13] == 83);
    try expect(v[14] == 84);
    try expect(v[15] == 85);
    try expect(v[16] == 86);
    try expect(v[17] == 87);
    try expect(v[18] == 88);
    try expect(v[19] == 89);
    try expect(v[20] == 90);
    try expect(v[21] == 91);
    try expect(v[22] == 92);
    try expect(v[23] == 93);
    try expect(v[24] == 94);
    try expect(v[25] == 95);
    try expect(v[26] == 96);
    try expect(v[27] == 97);
    try expect(v[28] == 98);
    try expect(v[29] == 99);
    try expect(v[30] == 0);
    try expect(v[31] == 1);
    try expect(v[32] == 2);
    try expect(v[33] == 3);
    try expect(v[34] == 4);
    try expect(v[35] == 5);
    try expect(v[36] == 6);
    try expect(v[37] == 7);
    try expect(v[38] == 8);
    try expect(v[39] == 9);
    try expect(v[40] == 10);
    try expect(v[41] == 11);
    try expect(v[42] == 12);
    try expect(v[43] == 13);
    try expect(v[44] == 14);
    try expect(v[45] == 15);
    try expect(v[46] == 16);
    try expect(v[47] == 17);
    try expect(v[48] == 18);
    try expect(v[49] == 19);
    try expect(v[50] == 20);
    try expect(v[51] == 21);
    try expect(v[52] == 22);
    try expect(v[53] == 23);
    try expect(v[54] == 24);
    try expect(v[55] == 25);
    try expect(v[56] == 26);
    try expect(v[57] == 27);
    try expect(v[58] == 28);
    try expect(v[59] == 29);
    try expect(v[60] == 30);
    try expect(v[61] == 31);
    try expect(v[62] == 32);
    try expect(v[63] == 33);
    try expect(v[64] == 34);
    try expect(v[65] == 35);
    try expect(v[66] == 36);
    try expect(v[67] == 37);
    try expect(v[68] == 38);
    try expect(v[69] == 39);
    try expect(v[70] == 40);
    try expect(v[71] == 41);
    try expect(v[72] == 42);
    try expect(v[73] == 43);
    try expect(v[74] == 44);
    try expect(v[75] == 45);
    try expect(v[76] == 46);
    try expect(v[77] == 47);
    try expect(v[78] == 48);
    try expect(v[79] == 49);
    try expect(v[80] == 50);
    try expect(v[81] == 51);
    try expect(v[82] == 52);
    try expect(v[83] == 53);
    try expect(v[84] == 54);
    try expect(v[85] == 55);
    try expect(v[86] == 56);
    try expect(v[87] == 57);
    try expect(v[88] == 58);
    try expect(v[89] == 59);
    try expect(v[90] == 60);
    try expect(v[91] == 61);
    try expect(v[92] == 62);
    try expect(v[93] == 63);
    try expect(v[94] == 64);
    try expect(v[95] == 65);
    try expect(v[96] == 66);
    try expect(v[97] == 67);
    try expect(v[98] == 68);
    try expect(v[99] == 69);
    try expect(v[100] == 70);
    try expect(v[101] == 71);
    try expect(v[102] == 72);
    try expect(v[103] == 73);
    try expect(v[104] == 74);
    try expect(v[105] == 75);
    try expect(v[106] == 76);
    try expect(v[107] == 77);
    try expect(v[108] == 78);
    try expect(v[109] == 79);
    try expect(v[110] == 80);
    try expect(v[111] == 81);
    try expect(v[112] == 82);
    try expect(v[113] == 83);
    try expect(v[114] == 84);
    try expect(v[115] == 85);
    try expect(v[116] == 86);
    try expect(v[117] == 87);
    try expect(v[118] == 88);
    try expect(v[119] == 89);
    try expect(v[120] == 90);
    try expect(v[121] == 91);
    try expect(v[122] == 92);
    try expect(v[123] == 93);
    try expect(v[124] == 94);
    try expect(v[125] == 95);
    try expect(v[126] == 96);
    try expect(v[127] == 97);
    try expect(v[128] == 98);
    try expect(v[129] == 99);
    try expect(v[130] == 0);
    try expect(v[131] == 1);
    try expect(v[132] == 2);
    try expect(v[133] == 3);
    try expect(v[134] == 4);
    try expect(v[135] == 5);
    try expect(v[136] == 6);
    try expect(v[137] == 7);
    try expect(v[138] == 8);
    try expect(v[139] == 9);
    try expect(v[140] == 10);
    try expect(v[141] == 11);
    try expect(v[142] == 12);
    try expect(v[143] == 13);
    try expect(v[144] == 14);
    try expect(v[145] == 15);
    try expect(v[146] == 16);
    try expect(v[147] == 17);
    try expect(v[148] == 18);
    try expect(v[149] == 19);
    try expect(v[150] == 20);
    try expect(v[151] == 21);
    try expect(v[152] == 22);
    try expect(v[153] == 23);
    try expect(v[154] == 24);
    try expect(v[155] == 25);
    try expect(v[156] == 26);
    try expect(v[157] == 27);
    try expect(v[158] == 28);
    try expect(v[159] == 29);
    try expect(v[160] == 30);
    try expect(v[161] == 31);
    try expect(v[162] == 32);
    try expect(v[163] == 33);
    try expect(v[164] == 34);
    try expect(v[165] == 35);
    try expect(v[166] == 36);
    try expect(v[167] == 37);
    try expect(v[168] == 38);
    try expect(v[169] == 39);
    try expect(v[170] == 40);
    try expect(v[171] == 41);
    try expect(v[172] == 42);
    try expect(v[173] == 43);
    try expect(v[174] == 44);
    try expect(v[175] == 45);
    try expect(v[176] == 46);
    try expect(v[177] == 47);
    try expect(v[178] == 48);
    try expect(v[179] == 49);
    try expect(v[180] == 50);
    try expect(v[181] == 51);
    try expect(v[182] == 52);
    try expect(v[183] == 53);
    try expect(v[184] == 54);
    try expect(v[185] == 55);
    try expect(v[186] == 56);
    try expect(v[187] == 57);
    try expect(v[188] == 58);
    try expect(v[189] == 59);
    try expect(v[190] == 60);
    try expect(v[191] == 61);
    c_vector_192_u8(.{
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
    }, 192);
    c_test_vector_192_u8();
}

export fn zig_ret_vector_256_u8() @Vector(256, u8) {
    return .{
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
    };
}
export fn zig_vector_256_u8(v: @Vector(256, u8), i: usize) void {
    expect(v[0] == 10) catch @panic("test failure");
    expect(v[1] == 11) catch @panic("test failure");
    expect(v[2] == 12) catch @panic("test failure");
    expect(v[3] == 13) catch @panic("test failure");
    expect(v[4] == 14) catch @panic("test failure");
    expect(v[5] == 15) catch @panic("test failure");
    expect(v[6] == 16) catch @panic("test failure");
    expect(v[7] == 17) catch @panic("test failure");
    expect(v[8] == 18) catch @panic("test failure");
    expect(v[9] == 19) catch @panic("test failure");
    expect(v[10] == 20) catch @panic("test failure");
    expect(v[11] == 21) catch @panic("test failure");
    expect(v[12] == 22) catch @panic("test failure");
    expect(v[13] == 23) catch @panic("test failure");
    expect(v[14] == 24) catch @panic("test failure");
    expect(v[15] == 25) catch @panic("test failure");
    expect(v[16] == 26) catch @panic("test failure");
    expect(v[17] == 27) catch @panic("test failure");
    expect(v[18] == 28) catch @panic("test failure");
    expect(v[19] == 29) catch @panic("test failure");
    expect(v[20] == 30) catch @panic("test failure");
    expect(v[21] == 31) catch @panic("test failure");
    expect(v[22] == 32) catch @panic("test failure");
    expect(v[23] == 33) catch @panic("test failure");
    expect(v[24] == 34) catch @panic("test failure");
    expect(v[25] == 35) catch @panic("test failure");
    expect(v[26] == 36) catch @panic("test failure");
    expect(v[27] == 37) catch @panic("test failure");
    expect(v[28] == 38) catch @panic("test failure");
    expect(v[29] == 39) catch @panic("test failure");
    expect(v[30] == 40) catch @panic("test failure");
    expect(v[31] == 41) catch @panic("test failure");
    expect(v[32] == 42) catch @panic("test failure");
    expect(v[33] == 43) catch @panic("test failure");
    expect(v[34] == 44) catch @panic("test failure");
    expect(v[35] == 45) catch @panic("test failure");
    expect(v[36] == 46) catch @panic("test failure");
    expect(v[37] == 47) catch @panic("test failure");
    expect(v[38] == 48) catch @panic("test failure");
    expect(v[39] == 49) catch @panic("test failure");
    expect(v[40] == 50) catch @panic("test failure");
    expect(v[41] == 51) catch @panic("test failure");
    expect(v[42] == 52) catch @panic("test failure");
    expect(v[43] == 53) catch @panic("test failure");
    expect(v[44] == 54) catch @panic("test failure");
    expect(v[45] == 55) catch @panic("test failure");
    expect(v[46] == 56) catch @panic("test failure");
    expect(v[47] == 57) catch @panic("test failure");
    expect(v[48] == 58) catch @panic("test failure");
    expect(v[49] == 59) catch @panic("test failure");
    expect(v[50] == 60) catch @panic("test failure");
    expect(v[51] == 61) catch @panic("test failure");
    expect(v[52] == 62) catch @panic("test failure");
    expect(v[53] == 63) catch @panic("test failure");
    expect(v[54] == 64) catch @panic("test failure");
    expect(v[55] == 65) catch @panic("test failure");
    expect(v[56] == 66) catch @panic("test failure");
    expect(v[57] == 67) catch @panic("test failure");
    expect(v[58] == 68) catch @panic("test failure");
    expect(v[59] == 69) catch @panic("test failure");
    expect(v[60] == 70) catch @panic("test failure");
    expect(v[61] == 71) catch @panic("test failure");
    expect(v[62] == 72) catch @panic("test failure");
    expect(v[63] == 73) catch @panic("test failure");
    expect(v[64] == 74) catch @panic("test failure");
    expect(v[65] == 75) catch @panic("test failure");
    expect(v[66] == 76) catch @panic("test failure");
    expect(v[67] == 77) catch @panic("test failure");
    expect(v[68] == 78) catch @panic("test failure");
    expect(v[69] == 79) catch @panic("test failure");
    expect(v[70] == 80) catch @panic("test failure");
    expect(v[71] == 81) catch @panic("test failure");
    expect(v[72] == 82) catch @panic("test failure");
    expect(v[73] == 83) catch @panic("test failure");
    expect(v[74] == 84) catch @panic("test failure");
    expect(v[75] == 85) catch @panic("test failure");
    expect(v[76] == 86) catch @panic("test failure");
    expect(v[77] == 87) catch @panic("test failure");
    expect(v[78] == 88) catch @panic("test failure");
    expect(v[79] == 89) catch @panic("test failure");
    expect(v[80] == 90) catch @panic("test failure");
    expect(v[81] == 91) catch @panic("test failure");
    expect(v[82] == 92) catch @panic("test failure");
    expect(v[83] == 93) catch @panic("test failure");
    expect(v[84] == 94) catch @panic("test failure");
    expect(v[85] == 95) catch @panic("test failure");
    expect(v[86] == 96) catch @panic("test failure");
    expect(v[87] == 97) catch @panic("test failure");
    expect(v[88] == 98) catch @panic("test failure");
    expect(v[89] == 99) catch @panic("test failure");
    expect(v[90] == 0) catch @panic("test failure");
    expect(v[91] == 1) catch @panic("test failure");
    expect(v[92] == 2) catch @panic("test failure");
    expect(v[93] == 3) catch @panic("test failure");
    expect(v[94] == 4) catch @panic("test failure");
    expect(v[95] == 5) catch @panic("test failure");
    expect(v[96] == 6) catch @panic("test failure");
    expect(v[97] == 7) catch @panic("test failure");
    expect(v[98] == 8) catch @panic("test failure");
    expect(v[99] == 9) catch @panic("test failure");
    expect(v[100] == 10) catch @panic("test failure");
    expect(v[101] == 11) catch @panic("test failure");
    expect(v[102] == 12) catch @panic("test failure");
    expect(v[103] == 13) catch @panic("test failure");
    expect(v[104] == 14) catch @panic("test failure");
    expect(v[105] == 15) catch @panic("test failure");
    expect(v[106] == 16) catch @panic("test failure");
    expect(v[107] == 17) catch @panic("test failure");
    expect(v[108] == 18) catch @panic("test failure");
    expect(v[109] == 19) catch @panic("test failure");
    expect(v[110] == 20) catch @panic("test failure");
    expect(v[111] == 21) catch @panic("test failure");
    expect(v[112] == 22) catch @panic("test failure");
    expect(v[113] == 23) catch @panic("test failure");
    expect(v[114] == 24) catch @panic("test failure");
    expect(v[115] == 25) catch @panic("test failure");
    expect(v[116] == 26) catch @panic("test failure");
    expect(v[117] == 27) catch @panic("test failure");
    expect(v[118] == 28) catch @panic("test failure");
    expect(v[119] == 29) catch @panic("test failure");
    expect(v[120] == 30) catch @panic("test failure");
    expect(v[121] == 31) catch @panic("test failure");
    expect(v[122] == 32) catch @panic("test failure");
    expect(v[123] == 33) catch @panic("test failure");
    expect(v[124] == 34) catch @panic("test failure");
    expect(v[125] == 35) catch @panic("test failure");
    expect(v[126] == 36) catch @panic("test failure");
    expect(v[127] == 37) catch @panic("test failure");
    expect(v[128] == 38) catch @panic("test failure");
    expect(v[129] == 39) catch @panic("test failure");
    expect(v[130] == 40) catch @panic("test failure");
    expect(v[131] == 41) catch @panic("test failure");
    expect(v[132] == 42) catch @panic("test failure");
    expect(v[133] == 43) catch @panic("test failure");
    expect(v[134] == 44) catch @panic("test failure");
    expect(v[135] == 45) catch @panic("test failure");
    expect(v[136] == 46) catch @panic("test failure");
    expect(v[137] == 47) catch @panic("test failure");
    expect(v[138] == 48) catch @panic("test failure");
    expect(v[139] == 49) catch @panic("test failure");
    expect(v[140] == 50) catch @panic("test failure");
    expect(v[141] == 51) catch @panic("test failure");
    expect(v[142] == 52) catch @panic("test failure");
    expect(v[143] == 53) catch @panic("test failure");
    expect(v[144] == 54) catch @panic("test failure");
    expect(v[145] == 55) catch @panic("test failure");
    expect(v[146] == 56) catch @panic("test failure");
    expect(v[147] == 57) catch @panic("test failure");
    expect(v[148] == 58) catch @panic("test failure");
    expect(v[149] == 59) catch @panic("test failure");
    expect(v[150] == 60) catch @panic("test failure");
    expect(v[151] == 61) catch @panic("test failure");
    expect(v[152] == 62) catch @panic("test failure");
    expect(v[153] == 63) catch @panic("test failure");
    expect(v[154] == 64) catch @panic("test failure");
    expect(v[155] == 65) catch @panic("test failure");
    expect(v[156] == 66) catch @panic("test failure");
    expect(v[157] == 67) catch @panic("test failure");
    expect(v[158] == 68) catch @panic("test failure");
    expect(v[159] == 69) catch @panic("test failure");
    expect(v[160] == 70) catch @panic("test failure");
    expect(v[161] == 71) catch @panic("test failure");
    expect(v[162] == 72) catch @panic("test failure");
    expect(v[163] == 73) catch @panic("test failure");
    expect(v[164] == 74) catch @panic("test failure");
    expect(v[165] == 75) catch @panic("test failure");
    expect(v[166] == 76) catch @panic("test failure");
    expect(v[167] == 77) catch @panic("test failure");
    expect(v[168] == 78) catch @panic("test failure");
    expect(v[169] == 79) catch @panic("test failure");
    expect(v[170] == 80) catch @panic("test failure");
    expect(v[171] == 81) catch @panic("test failure");
    expect(v[172] == 82) catch @panic("test failure");
    expect(v[173] == 83) catch @panic("test failure");
    expect(v[174] == 84) catch @panic("test failure");
    expect(v[175] == 85) catch @panic("test failure");
    expect(v[176] == 86) catch @panic("test failure");
    expect(v[177] == 87) catch @panic("test failure");
    expect(v[178] == 88) catch @panic("test failure");
    expect(v[179] == 89) catch @panic("test failure");
    expect(v[180] == 90) catch @panic("test failure");
    expect(v[181] == 91) catch @panic("test failure");
    expect(v[182] == 92) catch @panic("test failure");
    expect(v[183] == 93) catch @panic("test failure");
    expect(v[184] == 94) catch @panic("test failure");
    expect(v[185] == 95) catch @panic("test failure");
    expect(v[186] == 96) catch @panic("test failure");
    expect(v[187] == 97) catch @panic("test failure");
    expect(v[188] == 98) catch @panic("test failure");
    expect(v[189] == 99) catch @panic("test failure");
    expect(v[190] == 0) catch @panic("test failure");
    expect(v[191] == 1) catch @panic("test failure");
    expect(v[192] == 2) catch @panic("test failure");
    expect(v[193] == 3) catch @panic("test failure");
    expect(v[194] == 4) catch @panic("test failure");
    expect(v[195] == 5) catch @panic("test failure");
    expect(v[196] == 6) catch @panic("test failure");
    expect(v[197] == 7) catch @panic("test failure");
    expect(v[198] == 8) catch @panic("test failure");
    expect(v[199] == 9) catch @panic("test failure");
    expect(v[200] == 10) catch @panic("test failure");
    expect(v[201] == 11) catch @panic("test failure");
    expect(v[202] == 12) catch @panic("test failure");
    expect(v[203] == 13) catch @panic("test failure");
    expect(v[204] == 14) catch @panic("test failure");
    expect(v[205] == 15) catch @panic("test failure");
    expect(v[206] == 16) catch @panic("test failure");
    expect(v[207] == 17) catch @panic("test failure");
    expect(v[208] == 18) catch @panic("test failure");
    expect(v[209] == 19) catch @panic("test failure");
    expect(v[210] == 20) catch @panic("test failure");
    expect(v[211] == 21) catch @panic("test failure");
    expect(v[212] == 22) catch @panic("test failure");
    expect(v[213] == 23) catch @panic("test failure");
    expect(v[214] == 24) catch @panic("test failure");
    expect(v[215] == 25) catch @panic("test failure");
    expect(v[216] == 26) catch @panic("test failure");
    expect(v[217] == 27) catch @panic("test failure");
    expect(v[218] == 28) catch @panic("test failure");
    expect(v[219] == 29) catch @panic("test failure");
    expect(v[220] == 30) catch @panic("test failure");
    expect(v[221] == 31) catch @panic("test failure");
    expect(v[222] == 32) catch @panic("test failure");
    expect(v[223] == 33) catch @panic("test failure");
    expect(v[224] == 34) catch @panic("test failure");
    expect(v[225] == 35) catch @panic("test failure");
    expect(v[226] == 36) catch @panic("test failure");
    expect(v[227] == 37) catch @panic("test failure");
    expect(v[228] == 38) catch @panic("test failure");
    expect(v[229] == 39) catch @panic("test failure");
    expect(v[230] == 40) catch @panic("test failure");
    expect(v[231] == 41) catch @panic("test failure");
    expect(v[232] == 42) catch @panic("test failure");
    expect(v[233] == 43) catch @panic("test failure");
    expect(v[234] == 44) catch @panic("test failure");
    expect(v[235] == 45) catch @panic("test failure");
    expect(v[236] == 46) catch @panic("test failure");
    expect(v[237] == 47) catch @panic("test failure");
    expect(v[238] == 48) catch @panic("test failure");
    expect(v[239] == 49) catch @panic("test failure");
    expect(v[240] == 50) catch @panic("test failure");
    expect(v[241] == 51) catch @panic("test failure");
    expect(v[242] == 52) catch @panic("test failure");
    expect(v[243] == 53) catch @panic("test failure");
    expect(v[244] == 54) catch @panic("test failure");
    expect(v[245] == 55) catch @panic("test failure");
    expect(v[246] == 56) catch @panic("test failure");
    expect(v[247] == 57) catch @panic("test failure");
    expect(v[248] == 58) catch @panic("test failure");
    expect(v[249] == 59) catch @panic("test failure");
    expect(v[250] == 60) catch @panic("test failure");
    expect(v[251] == 61) catch @panic("test failure");
    expect(v[252] == 62) catch @panic("test failure");
    expect(v[253] == 63) catch @panic("test failure");
    expect(v[254] == 64) catch @panic("test failure");
    expect(v[255] == 65) catch @panic("test failure");
    expect(i == 256) catch @panic("test failure");
}

extern fn c_ret_vector_256_u8() @Vector(256, u8);
extern fn c_vector_256_u8(@Vector(256, u8), usize) void;
extern fn c_test_vector_256_u8() void;

test "@Vector(256, u8)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_256_u8();
    try expect(v[0] == 66);
    try expect(v[1] == 67);
    try expect(v[2] == 68);
    try expect(v[3] == 69);
    try expect(v[4] == 70);
    try expect(v[5] == 71);
    try expect(v[6] == 72);
    try expect(v[7] == 73);
    try expect(v[8] == 74);
    try expect(v[9] == 75);
    try expect(v[10] == 76);
    try expect(v[11] == 77);
    try expect(v[12] == 78);
    try expect(v[13] == 79);
    try expect(v[14] == 80);
    try expect(v[15] == 81);
    try expect(v[16] == 82);
    try expect(v[17] == 83);
    try expect(v[18] == 84);
    try expect(v[19] == 85);
    try expect(v[20] == 86);
    try expect(v[21] == 87);
    try expect(v[22] == 88);
    try expect(v[23] == 89);
    try expect(v[24] == 90);
    try expect(v[25] == 91);
    try expect(v[26] == 92);
    try expect(v[27] == 93);
    try expect(v[28] == 94);
    try expect(v[29] == 95);
    try expect(v[30] == 96);
    try expect(v[31] == 97);
    try expect(v[32] == 98);
    try expect(v[33] == 99);
    try expect(v[34] == 0);
    try expect(v[35] == 1);
    try expect(v[36] == 2);
    try expect(v[37] == 3);
    try expect(v[38] == 4);
    try expect(v[39] == 5);
    try expect(v[40] == 6);
    try expect(v[41] == 7);
    try expect(v[42] == 8);
    try expect(v[43] == 9);
    try expect(v[44] == 10);
    try expect(v[45] == 11);
    try expect(v[46] == 12);
    try expect(v[47] == 13);
    try expect(v[48] == 14);
    try expect(v[49] == 15);
    try expect(v[50] == 16);
    try expect(v[51] == 17);
    try expect(v[52] == 18);
    try expect(v[53] == 19);
    try expect(v[54] == 20);
    try expect(v[55] == 21);
    try expect(v[56] == 22);
    try expect(v[57] == 23);
    try expect(v[58] == 24);
    try expect(v[59] == 25);
    try expect(v[60] == 26);
    try expect(v[61] == 27);
    try expect(v[62] == 28);
    try expect(v[63] == 29);
    try expect(v[64] == 30);
    try expect(v[65] == 31);
    try expect(v[66] == 32);
    try expect(v[67] == 33);
    try expect(v[68] == 34);
    try expect(v[69] == 35);
    try expect(v[70] == 36);
    try expect(v[71] == 37);
    try expect(v[72] == 38);
    try expect(v[73] == 39);
    try expect(v[74] == 40);
    try expect(v[75] == 41);
    try expect(v[76] == 42);
    try expect(v[77] == 43);
    try expect(v[78] == 44);
    try expect(v[79] == 45);
    try expect(v[80] == 46);
    try expect(v[81] == 47);
    try expect(v[82] == 48);
    try expect(v[83] == 49);
    try expect(v[84] == 50);
    try expect(v[85] == 51);
    try expect(v[86] == 52);
    try expect(v[87] == 53);
    try expect(v[88] == 54);
    try expect(v[89] == 55);
    try expect(v[90] == 56);
    try expect(v[91] == 57);
    try expect(v[92] == 58);
    try expect(v[93] == 59);
    try expect(v[94] == 60);
    try expect(v[95] == 61);
    try expect(v[96] == 62);
    try expect(v[97] == 63);
    try expect(v[98] == 64);
    try expect(v[99] == 65);
    try expect(v[100] == 66);
    try expect(v[101] == 67);
    try expect(v[102] == 68);
    try expect(v[103] == 69);
    try expect(v[104] == 70);
    try expect(v[105] == 71);
    try expect(v[106] == 72);
    try expect(v[107] == 73);
    try expect(v[108] == 74);
    try expect(v[109] == 75);
    try expect(v[110] == 76);
    try expect(v[111] == 77);
    try expect(v[112] == 78);
    try expect(v[113] == 79);
    try expect(v[114] == 80);
    try expect(v[115] == 81);
    try expect(v[116] == 82);
    try expect(v[117] == 83);
    try expect(v[118] == 84);
    try expect(v[119] == 85);
    try expect(v[120] == 86);
    try expect(v[121] == 87);
    try expect(v[122] == 88);
    try expect(v[123] == 89);
    try expect(v[124] == 90);
    try expect(v[125] == 91);
    try expect(v[126] == 92);
    try expect(v[127] == 93);
    try expect(v[128] == 94);
    try expect(v[129] == 95);
    try expect(v[130] == 96);
    try expect(v[131] == 97);
    try expect(v[132] == 98);
    try expect(v[133] == 99);
    try expect(v[134] == 0);
    try expect(v[135] == 1);
    try expect(v[136] == 2);
    try expect(v[137] == 3);
    try expect(v[138] == 4);
    try expect(v[139] == 5);
    try expect(v[140] == 6);
    try expect(v[141] == 7);
    try expect(v[142] == 8);
    try expect(v[143] == 9);
    try expect(v[144] == 10);
    try expect(v[145] == 11);
    try expect(v[146] == 12);
    try expect(v[147] == 13);
    try expect(v[148] == 14);
    try expect(v[149] == 15);
    try expect(v[150] == 16);
    try expect(v[151] == 17);
    try expect(v[152] == 18);
    try expect(v[153] == 19);
    try expect(v[154] == 20);
    try expect(v[155] == 21);
    try expect(v[156] == 22);
    try expect(v[157] == 23);
    try expect(v[158] == 24);
    try expect(v[159] == 25);
    try expect(v[160] == 26);
    try expect(v[161] == 27);
    try expect(v[162] == 28);
    try expect(v[163] == 29);
    try expect(v[164] == 30);
    try expect(v[165] == 31);
    try expect(v[166] == 32);
    try expect(v[167] == 33);
    try expect(v[168] == 34);
    try expect(v[169] == 35);
    try expect(v[170] == 36);
    try expect(v[171] == 37);
    try expect(v[172] == 38);
    try expect(v[173] == 39);
    try expect(v[174] == 40);
    try expect(v[175] == 41);
    try expect(v[176] == 42);
    try expect(v[177] == 43);
    try expect(v[178] == 44);
    try expect(v[179] == 45);
    try expect(v[180] == 46);
    try expect(v[181] == 47);
    try expect(v[182] == 48);
    try expect(v[183] == 49);
    try expect(v[184] == 50);
    try expect(v[185] == 51);
    try expect(v[186] == 52);
    try expect(v[187] == 53);
    try expect(v[188] == 54);
    try expect(v[189] == 55);
    try expect(v[190] == 56);
    try expect(v[191] == 57);
    try expect(v[192] == 58);
    try expect(v[193] == 59);
    try expect(v[194] == 60);
    try expect(v[195] == 61);
    try expect(v[196] == 62);
    try expect(v[197] == 63);
    try expect(v[198] == 64);
    try expect(v[199] == 65);
    try expect(v[200] == 66);
    try expect(v[201] == 67);
    try expect(v[202] == 68);
    try expect(v[203] == 69);
    try expect(v[204] == 70);
    try expect(v[205] == 71);
    try expect(v[206] == 72);
    try expect(v[207] == 73);
    try expect(v[208] == 74);
    try expect(v[209] == 75);
    try expect(v[210] == 76);
    try expect(v[211] == 77);
    try expect(v[212] == 78);
    try expect(v[213] == 79);
    try expect(v[214] == 80);
    try expect(v[215] == 81);
    try expect(v[216] == 82);
    try expect(v[217] == 83);
    try expect(v[218] == 84);
    try expect(v[219] == 85);
    try expect(v[220] == 86);
    try expect(v[221] == 87);
    try expect(v[222] == 88);
    try expect(v[223] == 89);
    try expect(v[224] == 90);
    try expect(v[225] == 91);
    try expect(v[226] == 92);
    try expect(v[227] == 93);
    try expect(v[228] == 94);
    try expect(v[229] == 95);
    try expect(v[230] == 96);
    try expect(v[231] == 97);
    try expect(v[232] == 98);
    try expect(v[233] == 99);
    try expect(v[234] == 0);
    try expect(v[235] == 1);
    try expect(v[236] == 2);
    try expect(v[237] == 3);
    try expect(v[238] == 4);
    try expect(v[239] == 5);
    try expect(v[240] == 6);
    try expect(v[241] == 7);
    try expect(v[242] == 8);
    try expect(v[243] == 9);
    try expect(v[244] == 10);
    try expect(v[245] == 11);
    try expect(v[246] == 12);
    try expect(v[247] == 13);
    try expect(v[248] == 14);
    try expect(v[249] == 15);
    try expect(v[250] == 16);
    try expect(v[251] == 17);
    try expect(v[252] == 18);
    try expect(v[253] == 19);
    try expect(v[254] == 20);
    try expect(v[255] == 21);
    c_vector_256_u8(.{
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
    }, 256);
    c_test_vector_256_u8();
}

export fn zig_ret_vector_384_u8() @Vector(384, u8) {
    return .{
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
        46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61,
    };
}
export fn zig_vector_384_u8(v: @Vector(384, u8), i: usize) void {
    expect(v[0] == 62) catch @panic("test failure");
    expect(v[1] == 63) catch @panic("test failure");
    expect(v[2] == 64) catch @panic("test failure");
    expect(v[3] == 65) catch @panic("test failure");
    expect(v[4] == 66) catch @panic("test failure");
    expect(v[5] == 67) catch @panic("test failure");
    expect(v[6] == 68) catch @panic("test failure");
    expect(v[7] == 69) catch @panic("test failure");
    expect(v[8] == 70) catch @panic("test failure");
    expect(v[9] == 71) catch @panic("test failure");
    expect(v[10] == 72) catch @panic("test failure");
    expect(v[11] == 73) catch @panic("test failure");
    expect(v[12] == 74) catch @panic("test failure");
    expect(v[13] == 75) catch @panic("test failure");
    expect(v[14] == 76) catch @panic("test failure");
    expect(v[15] == 77) catch @panic("test failure");
    expect(v[16] == 78) catch @panic("test failure");
    expect(v[17] == 79) catch @panic("test failure");
    expect(v[18] == 80) catch @panic("test failure");
    expect(v[19] == 81) catch @panic("test failure");
    expect(v[20] == 82) catch @panic("test failure");
    expect(v[21] == 83) catch @panic("test failure");
    expect(v[22] == 84) catch @panic("test failure");
    expect(v[23] == 85) catch @panic("test failure");
    expect(v[24] == 86) catch @panic("test failure");
    expect(v[25] == 87) catch @panic("test failure");
    expect(v[26] == 88) catch @panic("test failure");
    expect(v[27] == 89) catch @panic("test failure");
    expect(v[28] == 90) catch @panic("test failure");
    expect(v[29] == 91) catch @panic("test failure");
    expect(v[30] == 92) catch @panic("test failure");
    expect(v[31] == 93) catch @panic("test failure");
    expect(v[32] == 94) catch @panic("test failure");
    expect(v[33] == 95) catch @panic("test failure");
    expect(v[34] == 96) catch @panic("test failure");
    expect(v[35] == 97) catch @panic("test failure");
    expect(v[36] == 98) catch @panic("test failure");
    expect(v[37] == 99) catch @panic("test failure");
    expect(v[38] == 0) catch @panic("test failure");
    expect(v[39] == 1) catch @panic("test failure");
    expect(v[40] == 2) catch @panic("test failure");
    expect(v[41] == 3) catch @panic("test failure");
    expect(v[42] == 4) catch @panic("test failure");
    expect(v[43] == 5) catch @panic("test failure");
    expect(v[44] == 6) catch @panic("test failure");
    expect(v[45] == 7) catch @panic("test failure");
    expect(v[46] == 8) catch @panic("test failure");
    expect(v[47] == 9) catch @panic("test failure");
    expect(v[48] == 10) catch @panic("test failure");
    expect(v[49] == 11) catch @panic("test failure");
    expect(v[50] == 12) catch @panic("test failure");
    expect(v[51] == 13) catch @panic("test failure");
    expect(v[52] == 14) catch @panic("test failure");
    expect(v[53] == 15) catch @panic("test failure");
    expect(v[54] == 16) catch @panic("test failure");
    expect(v[55] == 17) catch @panic("test failure");
    expect(v[56] == 18) catch @panic("test failure");
    expect(v[57] == 19) catch @panic("test failure");
    expect(v[58] == 20) catch @panic("test failure");
    expect(v[59] == 21) catch @panic("test failure");
    expect(v[60] == 22) catch @panic("test failure");
    expect(v[61] == 23) catch @panic("test failure");
    expect(v[62] == 24) catch @panic("test failure");
    expect(v[63] == 25) catch @panic("test failure");
    expect(v[64] == 26) catch @panic("test failure");
    expect(v[65] == 27) catch @panic("test failure");
    expect(v[66] == 28) catch @panic("test failure");
    expect(v[67] == 29) catch @panic("test failure");
    expect(v[68] == 30) catch @panic("test failure");
    expect(v[69] == 31) catch @panic("test failure");
    expect(v[70] == 32) catch @panic("test failure");
    expect(v[71] == 33) catch @panic("test failure");
    expect(v[72] == 34) catch @panic("test failure");
    expect(v[73] == 35) catch @panic("test failure");
    expect(v[74] == 36) catch @panic("test failure");
    expect(v[75] == 37) catch @panic("test failure");
    expect(v[76] == 38) catch @panic("test failure");
    expect(v[77] == 39) catch @panic("test failure");
    expect(v[78] == 40) catch @panic("test failure");
    expect(v[79] == 41) catch @panic("test failure");
    expect(v[80] == 42) catch @panic("test failure");
    expect(v[81] == 43) catch @panic("test failure");
    expect(v[82] == 44) catch @panic("test failure");
    expect(v[83] == 45) catch @panic("test failure");
    expect(v[84] == 46) catch @panic("test failure");
    expect(v[85] == 47) catch @panic("test failure");
    expect(v[86] == 48) catch @panic("test failure");
    expect(v[87] == 49) catch @panic("test failure");
    expect(v[88] == 50) catch @panic("test failure");
    expect(v[89] == 51) catch @panic("test failure");
    expect(v[90] == 52) catch @panic("test failure");
    expect(v[91] == 53) catch @panic("test failure");
    expect(v[92] == 54) catch @panic("test failure");
    expect(v[93] == 55) catch @panic("test failure");
    expect(v[94] == 56) catch @panic("test failure");
    expect(v[95] == 57) catch @panic("test failure");
    expect(v[96] == 58) catch @panic("test failure");
    expect(v[97] == 59) catch @panic("test failure");
    expect(v[98] == 60) catch @panic("test failure");
    expect(v[99] == 61) catch @panic("test failure");
    expect(v[100] == 62) catch @panic("test failure");
    expect(v[101] == 63) catch @panic("test failure");
    expect(v[102] == 64) catch @panic("test failure");
    expect(v[103] == 65) catch @panic("test failure");
    expect(v[104] == 66) catch @panic("test failure");
    expect(v[105] == 67) catch @panic("test failure");
    expect(v[106] == 68) catch @panic("test failure");
    expect(v[107] == 69) catch @panic("test failure");
    expect(v[108] == 70) catch @panic("test failure");
    expect(v[109] == 71) catch @panic("test failure");
    expect(v[110] == 72) catch @panic("test failure");
    expect(v[111] == 73) catch @panic("test failure");
    expect(v[112] == 74) catch @panic("test failure");
    expect(v[113] == 75) catch @panic("test failure");
    expect(v[114] == 76) catch @panic("test failure");
    expect(v[115] == 77) catch @panic("test failure");
    expect(v[116] == 78) catch @panic("test failure");
    expect(v[117] == 79) catch @panic("test failure");
    expect(v[118] == 80) catch @panic("test failure");
    expect(v[119] == 81) catch @panic("test failure");
    expect(v[120] == 82) catch @panic("test failure");
    expect(v[121] == 83) catch @panic("test failure");
    expect(v[122] == 84) catch @panic("test failure");
    expect(v[123] == 85) catch @panic("test failure");
    expect(v[124] == 86) catch @panic("test failure");
    expect(v[125] == 87) catch @panic("test failure");
    expect(v[126] == 88) catch @panic("test failure");
    expect(v[127] == 89) catch @panic("test failure");
    expect(v[128] == 90) catch @panic("test failure");
    expect(v[129] == 91) catch @panic("test failure");
    expect(v[130] == 92) catch @panic("test failure");
    expect(v[131] == 93) catch @panic("test failure");
    expect(v[132] == 94) catch @panic("test failure");
    expect(v[133] == 95) catch @panic("test failure");
    expect(v[134] == 96) catch @panic("test failure");
    expect(v[135] == 97) catch @panic("test failure");
    expect(v[136] == 98) catch @panic("test failure");
    expect(v[137] == 99) catch @panic("test failure");
    expect(v[138] == 0) catch @panic("test failure");
    expect(v[139] == 1) catch @panic("test failure");
    expect(v[140] == 2) catch @panic("test failure");
    expect(v[141] == 3) catch @panic("test failure");
    expect(v[142] == 4) catch @panic("test failure");
    expect(v[143] == 5) catch @panic("test failure");
    expect(v[144] == 6) catch @panic("test failure");
    expect(v[145] == 7) catch @panic("test failure");
    expect(v[146] == 8) catch @panic("test failure");
    expect(v[147] == 9) catch @panic("test failure");
    expect(v[148] == 10) catch @panic("test failure");
    expect(v[149] == 11) catch @panic("test failure");
    expect(v[150] == 12) catch @panic("test failure");
    expect(v[151] == 13) catch @panic("test failure");
    expect(v[152] == 14) catch @panic("test failure");
    expect(v[153] == 15) catch @panic("test failure");
    expect(v[154] == 16) catch @panic("test failure");
    expect(v[155] == 17) catch @panic("test failure");
    expect(v[156] == 18) catch @panic("test failure");
    expect(v[157] == 19) catch @panic("test failure");
    expect(v[158] == 20) catch @panic("test failure");
    expect(v[159] == 21) catch @panic("test failure");
    expect(v[160] == 22) catch @panic("test failure");
    expect(v[161] == 23) catch @panic("test failure");
    expect(v[162] == 24) catch @panic("test failure");
    expect(v[163] == 25) catch @panic("test failure");
    expect(v[164] == 26) catch @panic("test failure");
    expect(v[165] == 27) catch @panic("test failure");
    expect(v[166] == 28) catch @panic("test failure");
    expect(v[167] == 29) catch @panic("test failure");
    expect(v[168] == 30) catch @panic("test failure");
    expect(v[169] == 31) catch @panic("test failure");
    expect(v[170] == 32) catch @panic("test failure");
    expect(v[171] == 33) catch @panic("test failure");
    expect(v[172] == 34) catch @panic("test failure");
    expect(v[173] == 35) catch @panic("test failure");
    expect(v[174] == 36) catch @panic("test failure");
    expect(v[175] == 37) catch @panic("test failure");
    expect(v[176] == 38) catch @panic("test failure");
    expect(v[177] == 39) catch @panic("test failure");
    expect(v[178] == 40) catch @panic("test failure");
    expect(v[179] == 41) catch @panic("test failure");
    expect(v[180] == 42) catch @panic("test failure");
    expect(v[181] == 43) catch @panic("test failure");
    expect(v[182] == 44) catch @panic("test failure");
    expect(v[183] == 45) catch @panic("test failure");
    expect(v[184] == 46) catch @panic("test failure");
    expect(v[185] == 47) catch @panic("test failure");
    expect(v[186] == 48) catch @panic("test failure");
    expect(v[187] == 49) catch @panic("test failure");
    expect(v[188] == 50) catch @panic("test failure");
    expect(v[189] == 51) catch @panic("test failure");
    expect(v[190] == 52) catch @panic("test failure");
    expect(v[191] == 53) catch @panic("test failure");
    expect(v[192] == 54) catch @panic("test failure");
    expect(v[193] == 55) catch @panic("test failure");
    expect(v[194] == 56) catch @panic("test failure");
    expect(v[195] == 57) catch @panic("test failure");
    expect(v[196] == 58) catch @panic("test failure");
    expect(v[197] == 59) catch @panic("test failure");
    expect(v[198] == 60) catch @panic("test failure");
    expect(v[199] == 61) catch @panic("test failure");
    expect(v[200] == 62) catch @panic("test failure");
    expect(v[201] == 63) catch @panic("test failure");
    expect(v[202] == 64) catch @panic("test failure");
    expect(v[203] == 65) catch @panic("test failure");
    expect(v[204] == 66) catch @panic("test failure");
    expect(v[205] == 67) catch @panic("test failure");
    expect(v[206] == 68) catch @panic("test failure");
    expect(v[207] == 69) catch @panic("test failure");
    expect(v[208] == 70) catch @panic("test failure");
    expect(v[209] == 71) catch @panic("test failure");
    expect(v[210] == 72) catch @panic("test failure");
    expect(v[211] == 73) catch @panic("test failure");
    expect(v[212] == 74) catch @panic("test failure");
    expect(v[213] == 75) catch @panic("test failure");
    expect(v[214] == 76) catch @panic("test failure");
    expect(v[215] == 77) catch @panic("test failure");
    expect(v[216] == 78) catch @panic("test failure");
    expect(v[217] == 79) catch @panic("test failure");
    expect(v[218] == 80) catch @panic("test failure");
    expect(v[219] == 81) catch @panic("test failure");
    expect(v[220] == 82) catch @panic("test failure");
    expect(v[221] == 83) catch @panic("test failure");
    expect(v[222] == 84) catch @panic("test failure");
    expect(v[223] == 85) catch @panic("test failure");
    expect(v[224] == 86) catch @panic("test failure");
    expect(v[225] == 87) catch @panic("test failure");
    expect(v[226] == 88) catch @panic("test failure");
    expect(v[227] == 89) catch @panic("test failure");
    expect(v[228] == 90) catch @panic("test failure");
    expect(v[229] == 91) catch @panic("test failure");
    expect(v[230] == 92) catch @panic("test failure");
    expect(v[231] == 93) catch @panic("test failure");
    expect(v[232] == 94) catch @panic("test failure");
    expect(v[233] == 95) catch @panic("test failure");
    expect(v[234] == 96) catch @panic("test failure");
    expect(v[235] == 97) catch @panic("test failure");
    expect(v[236] == 98) catch @panic("test failure");
    expect(v[237] == 99) catch @panic("test failure");
    expect(v[238] == 0) catch @panic("test failure");
    expect(v[239] == 1) catch @panic("test failure");
    expect(v[240] == 2) catch @panic("test failure");
    expect(v[241] == 3) catch @panic("test failure");
    expect(v[242] == 4) catch @panic("test failure");
    expect(v[243] == 5) catch @panic("test failure");
    expect(v[244] == 6) catch @panic("test failure");
    expect(v[245] == 7) catch @panic("test failure");
    expect(v[246] == 8) catch @panic("test failure");
    expect(v[247] == 9) catch @panic("test failure");
    expect(v[248] == 10) catch @panic("test failure");
    expect(v[249] == 11) catch @panic("test failure");
    expect(v[250] == 12) catch @panic("test failure");
    expect(v[251] == 13) catch @panic("test failure");
    expect(v[252] == 14) catch @panic("test failure");
    expect(v[253] == 15) catch @panic("test failure");
    expect(v[254] == 16) catch @panic("test failure");
    expect(v[255] == 17) catch @panic("test failure");
    expect(v[256] == 18) catch @panic("test failure");
    expect(v[257] == 19) catch @panic("test failure");
    expect(v[258] == 20) catch @panic("test failure");
    expect(v[259] == 21) catch @panic("test failure");
    expect(v[260] == 22) catch @panic("test failure");
    expect(v[261] == 23) catch @panic("test failure");
    expect(v[262] == 24) catch @panic("test failure");
    expect(v[263] == 25) catch @panic("test failure");
    expect(v[264] == 26) catch @panic("test failure");
    expect(v[265] == 27) catch @panic("test failure");
    expect(v[266] == 28) catch @panic("test failure");
    expect(v[267] == 29) catch @panic("test failure");
    expect(v[268] == 30) catch @panic("test failure");
    expect(v[269] == 31) catch @panic("test failure");
    expect(v[270] == 32) catch @panic("test failure");
    expect(v[271] == 33) catch @panic("test failure");
    expect(v[272] == 34) catch @panic("test failure");
    expect(v[273] == 35) catch @panic("test failure");
    expect(v[274] == 36) catch @panic("test failure");
    expect(v[275] == 37) catch @panic("test failure");
    expect(v[276] == 38) catch @panic("test failure");
    expect(v[277] == 39) catch @panic("test failure");
    expect(v[278] == 40) catch @panic("test failure");
    expect(v[279] == 41) catch @panic("test failure");
    expect(v[280] == 42) catch @panic("test failure");
    expect(v[281] == 43) catch @panic("test failure");
    expect(v[282] == 44) catch @panic("test failure");
    expect(v[283] == 45) catch @panic("test failure");
    expect(v[284] == 46) catch @panic("test failure");
    expect(v[285] == 47) catch @panic("test failure");
    expect(v[286] == 48) catch @panic("test failure");
    expect(v[287] == 49) catch @panic("test failure");
    expect(v[288] == 50) catch @panic("test failure");
    expect(v[289] == 51) catch @panic("test failure");
    expect(v[290] == 52) catch @panic("test failure");
    expect(v[291] == 53) catch @panic("test failure");
    expect(v[292] == 54) catch @panic("test failure");
    expect(v[293] == 55) catch @panic("test failure");
    expect(v[294] == 56) catch @panic("test failure");
    expect(v[295] == 57) catch @panic("test failure");
    expect(v[296] == 58) catch @panic("test failure");
    expect(v[297] == 59) catch @panic("test failure");
    expect(v[298] == 60) catch @panic("test failure");
    expect(v[299] == 61) catch @panic("test failure");
    expect(v[300] == 62) catch @panic("test failure");
    expect(v[301] == 63) catch @panic("test failure");
    expect(v[302] == 64) catch @panic("test failure");
    expect(v[303] == 65) catch @panic("test failure");
    expect(v[304] == 66) catch @panic("test failure");
    expect(v[305] == 67) catch @panic("test failure");
    expect(v[306] == 68) catch @panic("test failure");
    expect(v[307] == 69) catch @panic("test failure");
    expect(v[308] == 70) catch @panic("test failure");
    expect(v[309] == 71) catch @panic("test failure");
    expect(v[310] == 72) catch @panic("test failure");
    expect(v[311] == 73) catch @panic("test failure");
    expect(v[312] == 74) catch @panic("test failure");
    expect(v[313] == 75) catch @panic("test failure");
    expect(v[314] == 76) catch @panic("test failure");
    expect(v[315] == 77) catch @panic("test failure");
    expect(v[316] == 78) catch @panic("test failure");
    expect(v[317] == 79) catch @panic("test failure");
    expect(v[318] == 80) catch @panic("test failure");
    expect(v[319] == 81) catch @panic("test failure");
    expect(v[320] == 82) catch @panic("test failure");
    expect(v[321] == 83) catch @panic("test failure");
    expect(v[322] == 84) catch @panic("test failure");
    expect(v[323] == 85) catch @panic("test failure");
    expect(v[324] == 86) catch @panic("test failure");
    expect(v[325] == 87) catch @panic("test failure");
    expect(v[326] == 88) catch @panic("test failure");
    expect(v[327] == 89) catch @panic("test failure");
    expect(v[328] == 90) catch @panic("test failure");
    expect(v[329] == 91) catch @panic("test failure");
    expect(v[330] == 92) catch @panic("test failure");
    expect(v[331] == 93) catch @panic("test failure");
    expect(v[332] == 94) catch @panic("test failure");
    expect(v[333] == 95) catch @panic("test failure");
    expect(v[334] == 96) catch @panic("test failure");
    expect(v[335] == 97) catch @panic("test failure");
    expect(v[336] == 98) catch @panic("test failure");
    expect(v[337] == 99) catch @panic("test failure");
    expect(v[338] == 0) catch @panic("test failure");
    expect(v[339] == 1) catch @panic("test failure");
    expect(v[340] == 2) catch @panic("test failure");
    expect(v[341] == 3) catch @panic("test failure");
    expect(v[342] == 4) catch @panic("test failure");
    expect(v[343] == 5) catch @panic("test failure");
    expect(v[344] == 6) catch @panic("test failure");
    expect(v[345] == 7) catch @panic("test failure");
    expect(v[346] == 8) catch @panic("test failure");
    expect(v[347] == 9) catch @panic("test failure");
    expect(v[348] == 10) catch @panic("test failure");
    expect(v[349] == 11) catch @panic("test failure");
    expect(v[350] == 12) catch @panic("test failure");
    expect(v[351] == 13) catch @panic("test failure");
    expect(v[352] == 14) catch @panic("test failure");
    expect(v[353] == 15) catch @panic("test failure");
    expect(v[354] == 16) catch @panic("test failure");
    expect(v[355] == 17) catch @panic("test failure");
    expect(v[356] == 18) catch @panic("test failure");
    expect(v[357] == 19) catch @panic("test failure");
    expect(v[358] == 20) catch @panic("test failure");
    expect(v[359] == 21) catch @panic("test failure");
    expect(v[360] == 22) catch @panic("test failure");
    expect(v[361] == 23) catch @panic("test failure");
    expect(v[362] == 24) catch @panic("test failure");
    expect(v[363] == 25) catch @panic("test failure");
    expect(v[364] == 26) catch @panic("test failure");
    expect(v[365] == 27) catch @panic("test failure");
    expect(v[366] == 28) catch @panic("test failure");
    expect(v[367] == 29) catch @panic("test failure");
    expect(v[368] == 30) catch @panic("test failure");
    expect(v[369] == 31) catch @panic("test failure");
    expect(v[370] == 32) catch @panic("test failure");
    expect(v[371] == 33) catch @panic("test failure");
    expect(v[372] == 34) catch @panic("test failure");
    expect(v[373] == 35) catch @panic("test failure");
    expect(v[374] == 36) catch @panic("test failure");
    expect(v[375] == 37) catch @panic("test failure");
    expect(v[376] == 38) catch @panic("test failure");
    expect(v[377] == 39) catch @panic("test failure");
    expect(v[378] == 40) catch @panic("test failure");
    expect(v[379] == 41) catch @panic("test failure");
    expect(v[380] == 42) catch @panic("test failure");
    expect(v[381] == 43) catch @panic("test failure");
    expect(v[382] == 44) catch @panic("test failure");
    expect(v[383] == 45) catch @panic("test failure");
    expect(i == 384) catch @panic("test failure");
}

extern fn c_ret_vector_384_u8() @Vector(384, u8);
extern fn c_vector_384_u8(@Vector(384, u8), usize) void;
extern fn c_test_vector_384_u8() void;

test "@Vector(384, u8)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_384_u8();
    try expect(v[0] == 46);
    try expect(v[1] == 47);
    try expect(v[2] == 48);
    try expect(v[3] == 49);
    try expect(v[4] == 50);
    try expect(v[5] == 51);
    try expect(v[6] == 52);
    try expect(v[7] == 53);
    try expect(v[8] == 54);
    try expect(v[9] == 55);
    try expect(v[10] == 56);
    try expect(v[11] == 57);
    try expect(v[12] == 58);
    try expect(v[13] == 59);
    try expect(v[14] == 60);
    try expect(v[15] == 61);
    try expect(v[16] == 62);
    try expect(v[17] == 63);
    try expect(v[18] == 64);
    try expect(v[19] == 65);
    try expect(v[20] == 66);
    try expect(v[21] == 67);
    try expect(v[22] == 68);
    try expect(v[23] == 69);
    try expect(v[24] == 70);
    try expect(v[25] == 71);
    try expect(v[26] == 72);
    try expect(v[27] == 73);
    try expect(v[28] == 74);
    try expect(v[29] == 75);
    try expect(v[30] == 76);
    try expect(v[31] == 77);
    try expect(v[32] == 78);
    try expect(v[33] == 79);
    try expect(v[34] == 80);
    try expect(v[35] == 81);
    try expect(v[36] == 82);
    try expect(v[37] == 83);
    try expect(v[38] == 84);
    try expect(v[39] == 85);
    try expect(v[40] == 86);
    try expect(v[41] == 87);
    try expect(v[42] == 88);
    try expect(v[43] == 89);
    try expect(v[44] == 90);
    try expect(v[45] == 91);
    try expect(v[46] == 92);
    try expect(v[47] == 93);
    try expect(v[48] == 94);
    try expect(v[49] == 95);
    try expect(v[50] == 96);
    try expect(v[51] == 97);
    try expect(v[52] == 98);
    try expect(v[53] == 99);
    try expect(v[54] == 0);
    try expect(v[55] == 1);
    try expect(v[56] == 2);
    try expect(v[57] == 3);
    try expect(v[58] == 4);
    try expect(v[59] == 5);
    try expect(v[60] == 6);
    try expect(v[61] == 7);
    try expect(v[62] == 8);
    try expect(v[63] == 9);
    try expect(v[64] == 10);
    try expect(v[65] == 11);
    try expect(v[66] == 12);
    try expect(v[67] == 13);
    try expect(v[68] == 14);
    try expect(v[69] == 15);
    try expect(v[70] == 16);
    try expect(v[71] == 17);
    try expect(v[72] == 18);
    try expect(v[73] == 19);
    try expect(v[74] == 20);
    try expect(v[75] == 21);
    try expect(v[76] == 22);
    try expect(v[77] == 23);
    try expect(v[78] == 24);
    try expect(v[79] == 25);
    try expect(v[80] == 26);
    try expect(v[81] == 27);
    try expect(v[82] == 28);
    try expect(v[83] == 29);
    try expect(v[84] == 30);
    try expect(v[85] == 31);
    try expect(v[86] == 32);
    try expect(v[87] == 33);
    try expect(v[88] == 34);
    try expect(v[89] == 35);
    try expect(v[90] == 36);
    try expect(v[91] == 37);
    try expect(v[92] == 38);
    try expect(v[93] == 39);
    try expect(v[94] == 40);
    try expect(v[95] == 41);
    try expect(v[96] == 42);
    try expect(v[97] == 43);
    try expect(v[98] == 44);
    try expect(v[99] == 45);
    try expect(v[100] == 46);
    try expect(v[101] == 47);
    try expect(v[102] == 48);
    try expect(v[103] == 49);
    try expect(v[104] == 50);
    try expect(v[105] == 51);
    try expect(v[106] == 52);
    try expect(v[107] == 53);
    try expect(v[108] == 54);
    try expect(v[109] == 55);
    try expect(v[110] == 56);
    try expect(v[111] == 57);
    try expect(v[112] == 58);
    try expect(v[113] == 59);
    try expect(v[114] == 60);
    try expect(v[115] == 61);
    try expect(v[116] == 62);
    try expect(v[117] == 63);
    try expect(v[118] == 64);
    try expect(v[119] == 65);
    try expect(v[120] == 66);
    try expect(v[121] == 67);
    try expect(v[122] == 68);
    try expect(v[123] == 69);
    try expect(v[124] == 70);
    try expect(v[125] == 71);
    try expect(v[126] == 72);
    try expect(v[127] == 73);
    try expect(v[128] == 74);
    try expect(v[129] == 75);
    try expect(v[130] == 76);
    try expect(v[131] == 77);
    try expect(v[132] == 78);
    try expect(v[133] == 79);
    try expect(v[134] == 80);
    try expect(v[135] == 81);
    try expect(v[136] == 82);
    try expect(v[137] == 83);
    try expect(v[138] == 84);
    try expect(v[139] == 85);
    try expect(v[140] == 86);
    try expect(v[141] == 87);
    try expect(v[142] == 88);
    try expect(v[143] == 89);
    try expect(v[144] == 90);
    try expect(v[145] == 91);
    try expect(v[146] == 92);
    try expect(v[147] == 93);
    try expect(v[148] == 94);
    try expect(v[149] == 95);
    try expect(v[150] == 96);
    try expect(v[151] == 97);
    try expect(v[152] == 98);
    try expect(v[153] == 99);
    try expect(v[154] == 0);
    try expect(v[155] == 1);
    try expect(v[156] == 2);
    try expect(v[157] == 3);
    try expect(v[158] == 4);
    try expect(v[159] == 5);
    try expect(v[160] == 6);
    try expect(v[161] == 7);
    try expect(v[162] == 8);
    try expect(v[163] == 9);
    try expect(v[164] == 10);
    try expect(v[165] == 11);
    try expect(v[166] == 12);
    try expect(v[167] == 13);
    try expect(v[168] == 14);
    try expect(v[169] == 15);
    try expect(v[170] == 16);
    try expect(v[171] == 17);
    try expect(v[172] == 18);
    try expect(v[173] == 19);
    try expect(v[174] == 20);
    try expect(v[175] == 21);
    try expect(v[176] == 22);
    try expect(v[177] == 23);
    try expect(v[178] == 24);
    try expect(v[179] == 25);
    try expect(v[180] == 26);
    try expect(v[181] == 27);
    try expect(v[182] == 28);
    try expect(v[183] == 29);
    try expect(v[184] == 30);
    try expect(v[185] == 31);
    try expect(v[186] == 32);
    try expect(v[187] == 33);
    try expect(v[188] == 34);
    try expect(v[189] == 35);
    try expect(v[190] == 36);
    try expect(v[191] == 37);
    try expect(v[192] == 38);
    try expect(v[193] == 39);
    try expect(v[194] == 40);
    try expect(v[195] == 41);
    try expect(v[196] == 42);
    try expect(v[197] == 43);
    try expect(v[198] == 44);
    try expect(v[199] == 45);
    try expect(v[200] == 46);
    try expect(v[201] == 47);
    try expect(v[202] == 48);
    try expect(v[203] == 49);
    try expect(v[204] == 50);
    try expect(v[205] == 51);
    try expect(v[206] == 52);
    try expect(v[207] == 53);
    try expect(v[208] == 54);
    try expect(v[209] == 55);
    try expect(v[210] == 56);
    try expect(v[211] == 57);
    try expect(v[212] == 58);
    try expect(v[213] == 59);
    try expect(v[214] == 60);
    try expect(v[215] == 61);
    try expect(v[216] == 62);
    try expect(v[217] == 63);
    try expect(v[218] == 64);
    try expect(v[219] == 65);
    try expect(v[220] == 66);
    try expect(v[221] == 67);
    try expect(v[222] == 68);
    try expect(v[223] == 69);
    try expect(v[224] == 70);
    try expect(v[225] == 71);
    try expect(v[226] == 72);
    try expect(v[227] == 73);
    try expect(v[228] == 74);
    try expect(v[229] == 75);
    try expect(v[230] == 76);
    try expect(v[231] == 77);
    try expect(v[232] == 78);
    try expect(v[233] == 79);
    try expect(v[234] == 80);
    try expect(v[235] == 81);
    try expect(v[236] == 82);
    try expect(v[237] == 83);
    try expect(v[238] == 84);
    try expect(v[239] == 85);
    try expect(v[240] == 86);
    try expect(v[241] == 87);
    try expect(v[242] == 88);
    try expect(v[243] == 89);
    try expect(v[244] == 90);
    try expect(v[245] == 91);
    try expect(v[246] == 92);
    try expect(v[247] == 93);
    try expect(v[248] == 94);
    try expect(v[249] == 95);
    try expect(v[250] == 96);
    try expect(v[251] == 97);
    try expect(v[252] == 98);
    try expect(v[253] == 99);
    try expect(v[254] == 0);
    try expect(v[255] == 1);
    try expect(v[256] == 2);
    try expect(v[257] == 3);
    try expect(v[258] == 4);
    try expect(v[259] == 5);
    try expect(v[260] == 6);
    try expect(v[261] == 7);
    try expect(v[262] == 8);
    try expect(v[263] == 9);
    try expect(v[264] == 10);
    try expect(v[265] == 11);
    try expect(v[266] == 12);
    try expect(v[267] == 13);
    try expect(v[268] == 14);
    try expect(v[269] == 15);
    try expect(v[270] == 16);
    try expect(v[271] == 17);
    try expect(v[272] == 18);
    try expect(v[273] == 19);
    try expect(v[274] == 20);
    try expect(v[275] == 21);
    try expect(v[276] == 22);
    try expect(v[277] == 23);
    try expect(v[278] == 24);
    try expect(v[279] == 25);
    try expect(v[280] == 26);
    try expect(v[281] == 27);
    try expect(v[282] == 28);
    try expect(v[283] == 29);
    try expect(v[284] == 30);
    try expect(v[285] == 31);
    try expect(v[286] == 32);
    try expect(v[287] == 33);
    try expect(v[288] == 34);
    try expect(v[289] == 35);
    try expect(v[290] == 36);
    try expect(v[291] == 37);
    try expect(v[292] == 38);
    try expect(v[293] == 39);
    try expect(v[294] == 40);
    try expect(v[295] == 41);
    try expect(v[296] == 42);
    try expect(v[297] == 43);
    try expect(v[298] == 44);
    try expect(v[299] == 45);
    try expect(v[300] == 46);
    try expect(v[301] == 47);
    try expect(v[302] == 48);
    try expect(v[303] == 49);
    try expect(v[304] == 50);
    try expect(v[305] == 51);
    try expect(v[306] == 52);
    try expect(v[307] == 53);
    try expect(v[308] == 54);
    try expect(v[309] == 55);
    try expect(v[310] == 56);
    try expect(v[311] == 57);
    try expect(v[312] == 58);
    try expect(v[313] == 59);
    try expect(v[314] == 60);
    try expect(v[315] == 61);
    try expect(v[316] == 62);
    try expect(v[317] == 63);
    try expect(v[318] == 64);
    try expect(v[319] == 65);
    try expect(v[320] == 66);
    try expect(v[321] == 67);
    try expect(v[322] == 68);
    try expect(v[323] == 69);
    try expect(v[324] == 70);
    try expect(v[325] == 71);
    try expect(v[326] == 72);
    try expect(v[327] == 73);
    try expect(v[328] == 74);
    try expect(v[329] == 75);
    try expect(v[330] == 76);
    try expect(v[331] == 77);
    try expect(v[332] == 78);
    try expect(v[333] == 79);
    try expect(v[334] == 80);
    try expect(v[335] == 81);
    try expect(v[336] == 82);
    try expect(v[337] == 83);
    try expect(v[338] == 84);
    try expect(v[339] == 85);
    try expect(v[340] == 86);
    try expect(v[341] == 87);
    try expect(v[342] == 88);
    try expect(v[343] == 89);
    try expect(v[344] == 90);
    try expect(v[345] == 91);
    try expect(v[346] == 92);
    try expect(v[347] == 93);
    try expect(v[348] == 94);
    try expect(v[349] == 95);
    try expect(v[350] == 96);
    try expect(v[351] == 97);
    try expect(v[352] == 98);
    try expect(v[353] == 99);
    try expect(v[354] == 0);
    try expect(v[355] == 1);
    try expect(v[356] == 2);
    try expect(v[357] == 3);
    try expect(v[358] == 4);
    try expect(v[359] == 5);
    try expect(v[360] == 6);
    try expect(v[361] == 7);
    try expect(v[362] == 8);
    try expect(v[363] == 9);
    try expect(v[364] == 10);
    try expect(v[365] == 11);
    try expect(v[366] == 12);
    try expect(v[367] == 13);
    try expect(v[368] == 14);
    try expect(v[369] == 15);
    try expect(v[370] == 16);
    try expect(v[371] == 17);
    try expect(v[372] == 18);
    try expect(v[373] == 19);
    try expect(v[374] == 20);
    try expect(v[375] == 21);
    try expect(v[376] == 22);
    try expect(v[377] == 23);
    try expect(v[378] == 24);
    try expect(v[379] == 25);
    try expect(v[380] == 26);
    try expect(v[381] == 27);
    try expect(v[382] == 28);
    try expect(v[383] == 29);
    c_vector_384_u8(.{
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
        50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65,
        66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81,
        82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97,
        98, 99, 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13,
    }, 384);
    c_test_vector_384_u8();
}

export fn zig_ret_vector_512_u8() @Vector(512, u8) {
    return .{
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
    };
}
export fn zig_vector_512_u8(v: @Vector(512, u8), i: usize) void {
    expect(v[0] == 26) catch @panic("test failure");
    expect(v[1] == 27) catch @panic("test failure");
    expect(v[2] == 28) catch @panic("test failure");
    expect(v[3] == 29) catch @panic("test failure");
    expect(v[4] == 30) catch @panic("test failure");
    expect(v[5] == 31) catch @panic("test failure");
    expect(v[6] == 32) catch @panic("test failure");
    expect(v[7] == 33) catch @panic("test failure");
    expect(v[8] == 34) catch @panic("test failure");
    expect(v[9] == 35) catch @panic("test failure");
    expect(v[10] == 36) catch @panic("test failure");
    expect(v[11] == 37) catch @panic("test failure");
    expect(v[12] == 38) catch @panic("test failure");
    expect(v[13] == 39) catch @panic("test failure");
    expect(v[14] == 40) catch @panic("test failure");
    expect(v[15] == 41) catch @panic("test failure");
    expect(v[16] == 42) catch @panic("test failure");
    expect(v[17] == 43) catch @panic("test failure");
    expect(v[18] == 44) catch @panic("test failure");
    expect(v[19] == 45) catch @panic("test failure");
    expect(v[20] == 46) catch @panic("test failure");
    expect(v[21] == 47) catch @panic("test failure");
    expect(v[22] == 48) catch @panic("test failure");
    expect(v[23] == 49) catch @panic("test failure");
    expect(v[24] == 50) catch @panic("test failure");
    expect(v[25] == 51) catch @panic("test failure");
    expect(v[26] == 52) catch @panic("test failure");
    expect(v[27] == 53) catch @panic("test failure");
    expect(v[28] == 54) catch @panic("test failure");
    expect(v[29] == 55) catch @panic("test failure");
    expect(v[30] == 56) catch @panic("test failure");
    expect(v[31] == 57) catch @panic("test failure");
    expect(v[32] == 58) catch @panic("test failure");
    expect(v[33] == 59) catch @panic("test failure");
    expect(v[34] == 60) catch @panic("test failure");
    expect(v[35] == 61) catch @panic("test failure");
    expect(v[36] == 62) catch @panic("test failure");
    expect(v[37] == 63) catch @panic("test failure");
    expect(v[38] == 64) catch @panic("test failure");
    expect(v[39] == 65) catch @panic("test failure");
    expect(v[40] == 66) catch @panic("test failure");
    expect(v[41] == 67) catch @panic("test failure");
    expect(v[42] == 68) catch @panic("test failure");
    expect(v[43] == 69) catch @panic("test failure");
    expect(v[44] == 70) catch @panic("test failure");
    expect(v[45] == 71) catch @panic("test failure");
    expect(v[46] == 72) catch @panic("test failure");
    expect(v[47] == 73) catch @panic("test failure");
    expect(v[48] == 74) catch @panic("test failure");
    expect(v[49] == 75) catch @panic("test failure");
    expect(v[50] == 76) catch @panic("test failure");
    expect(v[51] == 77) catch @panic("test failure");
    expect(v[52] == 78) catch @panic("test failure");
    expect(v[53] == 79) catch @panic("test failure");
    expect(v[54] == 80) catch @panic("test failure");
    expect(v[55] == 81) catch @panic("test failure");
    expect(v[56] == 82) catch @panic("test failure");
    expect(v[57] == 83) catch @panic("test failure");
    expect(v[58] == 84) catch @panic("test failure");
    expect(v[59] == 85) catch @panic("test failure");
    expect(v[60] == 86) catch @panic("test failure");
    expect(v[61] == 87) catch @panic("test failure");
    expect(v[62] == 88) catch @panic("test failure");
    expect(v[63] == 89) catch @panic("test failure");
    expect(v[64] == 90) catch @panic("test failure");
    expect(v[65] == 91) catch @panic("test failure");
    expect(v[66] == 92) catch @panic("test failure");
    expect(v[67] == 93) catch @panic("test failure");
    expect(v[68] == 94) catch @panic("test failure");
    expect(v[69] == 95) catch @panic("test failure");
    expect(v[70] == 96) catch @panic("test failure");
    expect(v[71] == 97) catch @panic("test failure");
    expect(v[72] == 98) catch @panic("test failure");
    expect(v[73] == 99) catch @panic("test failure");
    expect(v[74] == 0) catch @panic("test failure");
    expect(v[75] == 1) catch @panic("test failure");
    expect(v[76] == 2) catch @panic("test failure");
    expect(v[77] == 3) catch @panic("test failure");
    expect(v[78] == 4) catch @panic("test failure");
    expect(v[79] == 5) catch @panic("test failure");
    expect(v[80] == 6) catch @panic("test failure");
    expect(v[81] == 7) catch @panic("test failure");
    expect(v[82] == 8) catch @panic("test failure");
    expect(v[83] == 9) catch @panic("test failure");
    expect(v[84] == 10) catch @panic("test failure");
    expect(v[85] == 11) catch @panic("test failure");
    expect(v[86] == 12) catch @panic("test failure");
    expect(v[87] == 13) catch @panic("test failure");
    expect(v[88] == 14) catch @panic("test failure");
    expect(v[89] == 15) catch @panic("test failure");
    expect(v[90] == 16) catch @panic("test failure");
    expect(v[91] == 17) catch @panic("test failure");
    expect(v[92] == 18) catch @panic("test failure");
    expect(v[93] == 19) catch @panic("test failure");
    expect(v[94] == 20) catch @panic("test failure");
    expect(v[95] == 21) catch @panic("test failure");
    expect(v[96] == 22) catch @panic("test failure");
    expect(v[97] == 23) catch @panic("test failure");
    expect(v[98] == 24) catch @panic("test failure");
    expect(v[99] == 25) catch @panic("test failure");
    expect(v[100] == 26) catch @panic("test failure");
    expect(v[101] == 27) catch @panic("test failure");
    expect(v[102] == 28) catch @panic("test failure");
    expect(v[103] == 29) catch @panic("test failure");
    expect(v[104] == 30) catch @panic("test failure");
    expect(v[105] == 31) catch @panic("test failure");
    expect(v[106] == 32) catch @panic("test failure");
    expect(v[107] == 33) catch @panic("test failure");
    expect(v[108] == 34) catch @panic("test failure");
    expect(v[109] == 35) catch @panic("test failure");
    expect(v[110] == 36) catch @panic("test failure");
    expect(v[111] == 37) catch @panic("test failure");
    expect(v[112] == 38) catch @panic("test failure");
    expect(v[113] == 39) catch @panic("test failure");
    expect(v[114] == 40) catch @panic("test failure");
    expect(v[115] == 41) catch @panic("test failure");
    expect(v[116] == 42) catch @panic("test failure");
    expect(v[117] == 43) catch @panic("test failure");
    expect(v[118] == 44) catch @panic("test failure");
    expect(v[119] == 45) catch @panic("test failure");
    expect(v[120] == 46) catch @panic("test failure");
    expect(v[121] == 47) catch @panic("test failure");
    expect(v[122] == 48) catch @panic("test failure");
    expect(v[123] == 49) catch @panic("test failure");
    expect(v[124] == 50) catch @panic("test failure");
    expect(v[125] == 51) catch @panic("test failure");
    expect(v[126] == 52) catch @panic("test failure");
    expect(v[127] == 53) catch @panic("test failure");
    expect(v[128] == 54) catch @panic("test failure");
    expect(v[129] == 55) catch @panic("test failure");
    expect(v[130] == 56) catch @panic("test failure");
    expect(v[131] == 57) catch @panic("test failure");
    expect(v[132] == 58) catch @panic("test failure");
    expect(v[133] == 59) catch @panic("test failure");
    expect(v[134] == 60) catch @panic("test failure");
    expect(v[135] == 61) catch @panic("test failure");
    expect(v[136] == 62) catch @panic("test failure");
    expect(v[137] == 63) catch @panic("test failure");
    expect(v[138] == 64) catch @panic("test failure");
    expect(v[139] == 65) catch @panic("test failure");
    expect(v[140] == 66) catch @panic("test failure");
    expect(v[141] == 67) catch @panic("test failure");
    expect(v[142] == 68) catch @panic("test failure");
    expect(v[143] == 69) catch @panic("test failure");
    expect(v[144] == 70) catch @panic("test failure");
    expect(v[145] == 71) catch @panic("test failure");
    expect(v[146] == 72) catch @panic("test failure");
    expect(v[147] == 73) catch @panic("test failure");
    expect(v[148] == 74) catch @panic("test failure");
    expect(v[149] == 75) catch @panic("test failure");
    expect(v[150] == 76) catch @panic("test failure");
    expect(v[151] == 77) catch @panic("test failure");
    expect(v[152] == 78) catch @panic("test failure");
    expect(v[153] == 79) catch @panic("test failure");
    expect(v[154] == 80) catch @panic("test failure");
    expect(v[155] == 81) catch @panic("test failure");
    expect(v[156] == 82) catch @panic("test failure");
    expect(v[157] == 83) catch @panic("test failure");
    expect(v[158] == 84) catch @panic("test failure");
    expect(v[159] == 85) catch @panic("test failure");
    expect(v[160] == 86) catch @panic("test failure");
    expect(v[161] == 87) catch @panic("test failure");
    expect(v[162] == 88) catch @panic("test failure");
    expect(v[163] == 89) catch @panic("test failure");
    expect(v[164] == 90) catch @panic("test failure");
    expect(v[165] == 91) catch @panic("test failure");
    expect(v[166] == 92) catch @panic("test failure");
    expect(v[167] == 93) catch @panic("test failure");
    expect(v[168] == 94) catch @panic("test failure");
    expect(v[169] == 95) catch @panic("test failure");
    expect(v[170] == 96) catch @panic("test failure");
    expect(v[171] == 97) catch @panic("test failure");
    expect(v[172] == 98) catch @panic("test failure");
    expect(v[173] == 99) catch @panic("test failure");
    expect(v[174] == 0) catch @panic("test failure");
    expect(v[175] == 1) catch @panic("test failure");
    expect(v[176] == 2) catch @panic("test failure");
    expect(v[177] == 3) catch @panic("test failure");
    expect(v[178] == 4) catch @panic("test failure");
    expect(v[179] == 5) catch @panic("test failure");
    expect(v[180] == 6) catch @panic("test failure");
    expect(v[181] == 7) catch @panic("test failure");
    expect(v[182] == 8) catch @panic("test failure");
    expect(v[183] == 9) catch @panic("test failure");
    expect(v[184] == 10) catch @panic("test failure");
    expect(v[185] == 11) catch @panic("test failure");
    expect(v[186] == 12) catch @panic("test failure");
    expect(v[187] == 13) catch @panic("test failure");
    expect(v[188] == 14) catch @panic("test failure");
    expect(v[189] == 15) catch @panic("test failure");
    expect(v[190] == 16) catch @panic("test failure");
    expect(v[191] == 17) catch @panic("test failure");
    expect(v[192] == 18) catch @panic("test failure");
    expect(v[193] == 19) catch @panic("test failure");
    expect(v[194] == 20) catch @panic("test failure");
    expect(v[195] == 21) catch @panic("test failure");
    expect(v[196] == 22) catch @panic("test failure");
    expect(v[197] == 23) catch @panic("test failure");
    expect(v[198] == 24) catch @panic("test failure");
    expect(v[199] == 25) catch @panic("test failure");
    expect(v[200] == 26) catch @panic("test failure");
    expect(v[201] == 27) catch @panic("test failure");
    expect(v[202] == 28) catch @panic("test failure");
    expect(v[203] == 29) catch @panic("test failure");
    expect(v[204] == 30) catch @panic("test failure");
    expect(v[205] == 31) catch @panic("test failure");
    expect(v[206] == 32) catch @panic("test failure");
    expect(v[207] == 33) catch @panic("test failure");
    expect(v[208] == 34) catch @panic("test failure");
    expect(v[209] == 35) catch @panic("test failure");
    expect(v[210] == 36) catch @panic("test failure");
    expect(v[211] == 37) catch @panic("test failure");
    expect(v[212] == 38) catch @panic("test failure");
    expect(v[213] == 39) catch @panic("test failure");
    expect(v[214] == 40) catch @panic("test failure");
    expect(v[215] == 41) catch @panic("test failure");
    expect(v[216] == 42) catch @panic("test failure");
    expect(v[217] == 43) catch @panic("test failure");
    expect(v[218] == 44) catch @panic("test failure");
    expect(v[219] == 45) catch @panic("test failure");
    expect(v[220] == 46) catch @panic("test failure");
    expect(v[221] == 47) catch @panic("test failure");
    expect(v[222] == 48) catch @panic("test failure");
    expect(v[223] == 49) catch @panic("test failure");
    expect(v[224] == 50) catch @panic("test failure");
    expect(v[225] == 51) catch @panic("test failure");
    expect(v[226] == 52) catch @panic("test failure");
    expect(v[227] == 53) catch @panic("test failure");
    expect(v[228] == 54) catch @panic("test failure");
    expect(v[229] == 55) catch @panic("test failure");
    expect(v[230] == 56) catch @panic("test failure");
    expect(v[231] == 57) catch @panic("test failure");
    expect(v[232] == 58) catch @panic("test failure");
    expect(v[233] == 59) catch @panic("test failure");
    expect(v[234] == 60) catch @panic("test failure");
    expect(v[235] == 61) catch @panic("test failure");
    expect(v[236] == 62) catch @panic("test failure");
    expect(v[237] == 63) catch @panic("test failure");
    expect(v[238] == 64) catch @panic("test failure");
    expect(v[239] == 65) catch @panic("test failure");
    expect(v[240] == 66) catch @panic("test failure");
    expect(v[241] == 67) catch @panic("test failure");
    expect(v[242] == 68) catch @panic("test failure");
    expect(v[243] == 69) catch @panic("test failure");
    expect(v[244] == 70) catch @panic("test failure");
    expect(v[245] == 71) catch @panic("test failure");
    expect(v[246] == 72) catch @panic("test failure");
    expect(v[247] == 73) catch @panic("test failure");
    expect(v[248] == 74) catch @panic("test failure");
    expect(v[249] == 75) catch @panic("test failure");
    expect(v[250] == 76) catch @panic("test failure");
    expect(v[251] == 77) catch @panic("test failure");
    expect(v[252] == 78) catch @panic("test failure");
    expect(v[253] == 79) catch @panic("test failure");
    expect(v[254] == 80) catch @panic("test failure");
    expect(v[255] == 81) catch @panic("test failure");
    expect(v[256] == 82) catch @panic("test failure");
    expect(v[257] == 83) catch @panic("test failure");
    expect(v[258] == 84) catch @panic("test failure");
    expect(v[259] == 85) catch @panic("test failure");
    expect(v[260] == 86) catch @panic("test failure");
    expect(v[261] == 87) catch @panic("test failure");
    expect(v[262] == 88) catch @panic("test failure");
    expect(v[263] == 89) catch @panic("test failure");
    expect(v[264] == 90) catch @panic("test failure");
    expect(v[265] == 91) catch @panic("test failure");
    expect(v[266] == 92) catch @panic("test failure");
    expect(v[267] == 93) catch @panic("test failure");
    expect(v[268] == 94) catch @panic("test failure");
    expect(v[269] == 95) catch @panic("test failure");
    expect(v[270] == 96) catch @panic("test failure");
    expect(v[271] == 97) catch @panic("test failure");
    expect(v[272] == 98) catch @panic("test failure");
    expect(v[273] == 99) catch @panic("test failure");
    expect(v[274] == 0) catch @panic("test failure");
    expect(v[275] == 1) catch @panic("test failure");
    expect(v[276] == 2) catch @panic("test failure");
    expect(v[277] == 3) catch @panic("test failure");
    expect(v[278] == 4) catch @panic("test failure");
    expect(v[279] == 5) catch @panic("test failure");
    expect(v[280] == 6) catch @panic("test failure");
    expect(v[281] == 7) catch @panic("test failure");
    expect(v[282] == 8) catch @panic("test failure");
    expect(v[283] == 9) catch @panic("test failure");
    expect(v[284] == 10) catch @panic("test failure");
    expect(v[285] == 11) catch @panic("test failure");
    expect(v[286] == 12) catch @panic("test failure");
    expect(v[287] == 13) catch @panic("test failure");
    expect(v[288] == 14) catch @panic("test failure");
    expect(v[289] == 15) catch @panic("test failure");
    expect(v[290] == 16) catch @panic("test failure");
    expect(v[291] == 17) catch @panic("test failure");
    expect(v[292] == 18) catch @panic("test failure");
    expect(v[293] == 19) catch @panic("test failure");
    expect(v[294] == 20) catch @panic("test failure");
    expect(v[295] == 21) catch @panic("test failure");
    expect(v[296] == 22) catch @panic("test failure");
    expect(v[297] == 23) catch @panic("test failure");
    expect(v[298] == 24) catch @panic("test failure");
    expect(v[299] == 25) catch @panic("test failure");
    expect(v[300] == 26) catch @panic("test failure");
    expect(v[301] == 27) catch @panic("test failure");
    expect(v[302] == 28) catch @panic("test failure");
    expect(v[303] == 29) catch @panic("test failure");
    expect(v[304] == 30) catch @panic("test failure");
    expect(v[305] == 31) catch @panic("test failure");
    expect(v[306] == 32) catch @panic("test failure");
    expect(v[307] == 33) catch @panic("test failure");
    expect(v[308] == 34) catch @panic("test failure");
    expect(v[309] == 35) catch @panic("test failure");
    expect(v[310] == 36) catch @panic("test failure");
    expect(v[311] == 37) catch @panic("test failure");
    expect(v[312] == 38) catch @panic("test failure");
    expect(v[313] == 39) catch @panic("test failure");
    expect(v[314] == 40) catch @panic("test failure");
    expect(v[315] == 41) catch @panic("test failure");
    expect(v[316] == 42) catch @panic("test failure");
    expect(v[317] == 43) catch @panic("test failure");
    expect(v[318] == 44) catch @panic("test failure");
    expect(v[319] == 45) catch @panic("test failure");
    expect(v[320] == 46) catch @panic("test failure");
    expect(v[321] == 47) catch @panic("test failure");
    expect(v[322] == 48) catch @panic("test failure");
    expect(v[323] == 49) catch @panic("test failure");
    expect(v[324] == 50) catch @panic("test failure");
    expect(v[325] == 51) catch @panic("test failure");
    expect(v[326] == 52) catch @panic("test failure");
    expect(v[327] == 53) catch @panic("test failure");
    expect(v[328] == 54) catch @panic("test failure");
    expect(v[329] == 55) catch @panic("test failure");
    expect(v[330] == 56) catch @panic("test failure");
    expect(v[331] == 57) catch @panic("test failure");
    expect(v[332] == 58) catch @panic("test failure");
    expect(v[333] == 59) catch @panic("test failure");
    expect(v[334] == 60) catch @panic("test failure");
    expect(v[335] == 61) catch @panic("test failure");
    expect(v[336] == 62) catch @panic("test failure");
    expect(v[337] == 63) catch @panic("test failure");
    expect(v[338] == 64) catch @panic("test failure");
    expect(v[339] == 65) catch @panic("test failure");
    expect(v[340] == 66) catch @panic("test failure");
    expect(v[341] == 67) catch @panic("test failure");
    expect(v[342] == 68) catch @panic("test failure");
    expect(v[343] == 69) catch @panic("test failure");
    expect(v[344] == 70) catch @panic("test failure");
    expect(v[345] == 71) catch @panic("test failure");
    expect(v[346] == 72) catch @panic("test failure");
    expect(v[347] == 73) catch @panic("test failure");
    expect(v[348] == 74) catch @panic("test failure");
    expect(v[349] == 75) catch @panic("test failure");
    expect(v[350] == 76) catch @panic("test failure");
    expect(v[351] == 77) catch @panic("test failure");
    expect(v[352] == 78) catch @panic("test failure");
    expect(v[353] == 79) catch @panic("test failure");
    expect(v[354] == 80) catch @panic("test failure");
    expect(v[355] == 81) catch @panic("test failure");
    expect(v[356] == 82) catch @panic("test failure");
    expect(v[357] == 83) catch @panic("test failure");
    expect(v[358] == 84) catch @panic("test failure");
    expect(v[359] == 85) catch @panic("test failure");
    expect(v[360] == 86) catch @panic("test failure");
    expect(v[361] == 87) catch @panic("test failure");
    expect(v[362] == 88) catch @panic("test failure");
    expect(v[363] == 89) catch @panic("test failure");
    expect(v[364] == 90) catch @panic("test failure");
    expect(v[365] == 91) catch @panic("test failure");
    expect(v[366] == 92) catch @panic("test failure");
    expect(v[367] == 93) catch @panic("test failure");
    expect(v[368] == 94) catch @panic("test failure");
    expect(v[369] == 95) catch @panic("test failure");
    expect(v[370] == 96) catch @panic("test failure");
    expect(v[371] == 97) catch @panic("test failure");
    expect(v[372] == 98) catch @panic("test failure");
    expect(v[373] == 99) catch @panic("test failure");
    expect(v[374] == 0) catch @panic("test failure");
    expect(v[375] == 1) catch @panic("test failure");
    expect(v[376] == 2) catch @panic("test failure");
    expect(v[377] == 3) catch @panic("test failure");
    expect(v[378] == 4) catch @panic("test failure");
    expect(v[379] == 5) catch @panic("test failure");
    expect(v[380] == 6) catch @panic("test failure");
    expect(v[381] == 7) catch @panic("test failure");
    expect(v[382] == 8) catch @panic("test failure");
    expect(v[383] == 9) catch @panic("test failure");
    expect(v[384] == 10) catch @panic("test failure");
    expect(v[385] == 11) catch @panic("test failure");
    expect(v[386] == 12) catch @panic("test failure");
    expect(v[387] == 13) catch @panic("test failure");
    expect(v[388] == 14) catch @panic("test failure");
    expect(v[389] == 15) catch @panic("test failure");
    expect(v[390] == 16) catch @panic("test failure");
    expect(v[391] == 17) catch @panic("test failure");
    expect(v[392] == 18) catch @panic("test failure");
    expect(v[393] == 19) catch @panic("test failure");
    expect(v[394] == 20) catch @panic("test failure");
    expect(v[395] == 21) catch @panic("test failure");
    expect(v[396] == 22) catch @panic("test failure");
    expect(v[397] == 23) catch @panic("test failure");
    expect(v[398] == 24) catch @panic("test failure");
    expect(v[399] == 25) catch @panic("test failure");
    expect(v[400] == 26) catch @panic("test failure");
    expect(v[401] == 27) catch @panic("test failure");
    expect(v[402] == 28) catch @panic("test failure");
    expect(v[403] == 29) catch @panic("test failure");
    expect(v[404] == 30) catch @panic("test failure");
    expect(v[405] == 31) catch @panic("test failure");
    expect(v[406] == 32) catch @panic("test failure");
    expect(v[407] == 33) catch @panic("test failure");
    expect(v[408] == 34) catch @panic("test failure");
    expect(v[409] == 35) catch @panic("test failure");
    expect(v[410] == 36) catch @panic("test failure");
    expect(v[411] == 37) catch @panic("test failure");
    expect(v[412] == 38) catch @panic("test failure");
    expect(v[413] == 39) catch @panic("test failure");
    expect(v[414] == 40) catch @panic("test failure");
    expect(v[415] == 41) catch @panic("test failure");
    expect(v[416] == 42) catch @panic("test failure");
    expect(v[417] == 43) catch @panic("test failure");
    expect(v[418] == 44) catch @panic("test failure");
    expect(v[419] == 45) catch @panic("test failure");
    expect(v[420] == 46) catch @panic("test failure");
    expect(v[421] == 47) catch @panic("test failure");
    expect(v[422] == 48) catch @panic("test failure");
    expect(v[423] == 49) catch @panic("test failure");
    expect(v[424] == 50) catch @panic("test failure");
    expect(v[425] == 51) catch @panic("test failure");
    expect(v[426] == 52) catch @panic("test failure");
    expect(v[427] == 53) catch @panic("test failure");
    expect(v[428] == 54) catch @panic("test failure");
    expect(v[429] == 55) catch @panic("test failure");
    expect(v[430] == 56) catch @panic("test failure");
    expect(v[431] == 57) catch @panic("test failure");
    expect(v[432] == 58) catch @panic("test failure");
    expect(v[433] == 59) catch @panic("test failure");
    expect(v[434] == 60) catch @panic("test failure");
    expect(v[435] == 61) catch @panic("test failure");
    expect(v[436] == 62) catch @panic("test failure");
    expect(v[437] == 63) catch @panic("test failure");
    expect(v[438] == 64) catch @panic("test failure");
    expect(v[439] == 65) catch @panic("test failure");
    expect(v[440] == 66) catch @panic("test failure");
    expect(v[441] == 67) catch @panic("test failure");
    expect(v[442] == 68) catch @panic("test failure");
    expect(v[443] == 69) catch @panic("test failure");
    expect(v[444] == 70) catch @panic("test failure");
    expect(v[445] == 71) catch @panic("test failure");
    expect(v[446] == 72) catch @panic("test failure");
    expect(v[447] == 73) catch @panic("test failure");
    expect(v[448] == 74) catch @panic("test failure");
    expect(v[449] == 75) catch @panic("test failure");
    expect(v[450] == 76) catch @panic("test failure");
    expect(v[451] == 77) catch @panic("test failure");
    expect(v[452] == 78) catch @panic("test failure");
    expect(v[453] == 79) catch @panic("test failure");
    expect(v[454] == 80) catch @panic("test failure");
    expect(v[455] == 81) catch @panic("test failure");
    expect(v[456] == 82) catch @panic("test failure");
    expect(v[457] == 83) catch @panic("test failure");
    expect(v[458] == 84) catch @panic("test failure");
    expect(v[459] == 85) catch @panic("test failure");
    expect(v[460] == 86) catch @panic("test failure");
    expect(v[461] == 87) catch @panic("test failure");
    expect(v[462] == 88) catch @panic("test failure");
    expect(v[463] == 89) catch @panic("test failure");
    expect(v[464] == 90) catch @panic("test failure");
    expect(v[465] == 91) catch @panic("test failure");
    expect(v[466] == 92) catch @panic("test failure");
    expect(v[467] == 93) catch @panic("test failure");
    expect(v[468] == 94) catch @panic("test failure");
    expect(v[469] == 95) catch @panic("test failure");
    expect(v[470] == 96) catch @panic("test failure");
    expect(v[471] == 97) catch @panic("test failure");
    expect(v[472] == 98) catch @panic("test failure");
    expect(v[473] == 99) catch @panic("test failure");
    expect(v[474] == 0) catch @panic("test failure");
    expect(v[475] == 1) catch @panic("test failure");
    expect(v[476] == 2) catch @panic("test failure");
    expect(v[477] == 3) catch @panic("test failure");
    expect(v[478] == 4) catch @panic("test failure");
    expect(v[479] == 5) catch @panic("test failure");
    expect(v[480] == 6) catch @panic("test failure");
    expect(v[481] == 7) catch @panic("test failure");
    expect(v[482] == 8) catch @panic("test failure");
    expect(v[483] == 9) catch @panic("test failure");
    expect(v[484] == 10) catch @panic("test failure");
    expect(v[485] == 11) catch @panic("test failure");
    expect(v[486] == 12) catch @panic("test failure");
    expect(v[487] == 13) catch @panic("test failure");
    expect(v[488] == 14) catch @panic("test failure");
    expect(v[489] == 15) catch @panic("test failure");
    expect(v[490] == 16) catch @panic("test failure");
    expect(v[491] == 17) catch @panic("test failure");
    expect(v[492] == 18) catch @panic("test failure");
    expect(v[493] == 19) catch @panic("test failure");
    expect(v[494] == 20) catch @panic("test failure");
    expect(v[495] == 21) catch @panic("test failure");
    expect(v[496] == 22) catch @panic("test failure");
    expect(v[497] == 23) catch @panic("test failure");
    expect(v[498] == 24) catch @panic("test failure");
    expect(v[499] == 25) catch @panic("test failure");
    expect(v[500] == 26) catch @panic("test failure");
    expect(v[501] == 27) catch @panic("test failure");
    expect(v[502] == 28) catch @panic("test failure");
    expect(v[503] == 29) catch @panic("test failure");
    expect(v[504] == 30) catch @panic("test failure");
    expect(v[505] == 31) catch @panic("test failure");
    expect(v[506] == 32) catch @panic("test failure");
    expect(v[507] == 33) catch @panic("test failure");
    expect(v[508] == 34) catch @panic("test failure");
    expect(v[509] == 35) catch @panic("test failure");
    expect(v[510] == 36) catch @panic("test failure");
    expect(v[511] == 37) catch @panic("test failure");
    expect(i == 512) catch @panic("test failure");
}

extern fn c_ret_vector_512_u8() @Vector(512, u8);
extern fn c_vector_512_u8(@Vector(512, u8), usize) void;
extern fn c_test_vector_512_u8() void;

test "@Vector(512, u8)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_512_u8();
    try expect(v[0] == 38);
    try expect(v[1] == 39);
    try expect(v[2] == 40);
    try expect(v[3] == 41);
    try expect(v[4] == 42);
    try expect(v[5] == 43);
    try expect(v[6] == 44);
    try expect(v[7] == 45);
    try expect(v[8] == 46);
    try expect(v[9] == 47);
    try expect(v[10] == 48);
    try expect(v[11] == 49);
    try expect(v[12] == 50);
    try expect(v[13] == 51);
    try expect(v[14] == 52);
    try expect(v[15] == 53);
    try expect(v[16] == 54);
    try expect(v[17] == 55);
    try expect(v[18] == 56);
    try expect(v[19] == 57);
    try expect(v[20] == 58);
    try expect(v[21] == 59);
    try expect(v[22] == 60);
    try expect(v[23] == 61);
    try expect(v[24] == 62);
    try expect(v[25] == 63);
    try expect(v[26] == 64);
    try expect(v[27] == 65);
    try expect(v[28] == 66);
    try expect(v[29] == 67);
    try expect(v[30] == 68);
    try expect(v[31] == 69);
    try expect(v[32] == 70);
    try expect(v[33] == 71);
    try expect(v[34] == 72);
    try expect(v[35] == 73);
    try expect(v[36] == 74);
    try expect(v[37] == 75);
    try expect(v[38] == 76);
    try expect(v[39] == 77);
    try expect(v[40] == 78);
    try expect(v[41] == 79);
    try expect(v[42] == 80);
    try expect(v[43] == 81);
    try expect(v[44] == 82);
    try expect(v[45] == 83);
    try expect(v[46] == 84);
    try expect(v[47] == 85);
    try expect(v[48] == 86);
    try expect(v[49] == 87);
    try expect(v[50] == 88);
    try expect(v[51] == 89);
    try expect(v[52] == 90);
    try expect(v[53] == 91);
    try expect(v[54] == 92);
    try expect(v[55] == 93);
    try expect(v[56] == 94);
    try expect(v[57] == 95);
    try expect(v[58] == 96);
    try expect(v[59] == 97);
    try expect(v[60] == 98);
    try expect(v[61] == 99);
    try expect(v[62] == 0);
    try expect(v[63] == 1);
    try expect(v[64] == 2);
    try expect(v[65] == 3);
    try expect(v[66] == 4);
    try expect(v[67] == 5);
    try expect(v[68] == 6);
    try expect(v[69] == 7);
    try expect(v[70] == 8);
    try expect(v[71] == 9);
    try expect(v[72] == 10);
    try expect(v[73] == 11);
    try expect(v[74] == 12);
    try expect(v[75] == 13);
    try expect(v[76] == 14);
    try expect(v[77] == 15);
    try expect(v[78] == 16);
    try expect(v[79] == 17);
    try expect(v[80] == 18);
    try expect(v[81] == 19);
    try expect(v[82] == 20);
    try expect(v[83] == 21);
    try expect(v[84] == 22);
    try expect(v[85] == 23);
    try expect(v[86] == 24);
    try expect(v[87] == 25);
    try expect(v[88] == 26);
    try expect(v[89] == 27);
    try expect(v[90] == 28);
    try expect(v[91] == 29);
    try expect(v[92] == 30);
    try expect(v[93] == 31);
    try expect(v[94] == 32);
    try expect(v[95] == 33);
    try expect(v[96] == 34);
    try expect(v[97] == 35);
    try expect(v[98] == 36);
    try expect(v[99] == 37);
    try expect(v[100] == 38);
    try expect(v[101] == 39);
    try expect(v[102] == 40);
    try expect(v[103] == 41);
    try expect(v[104] == 42);
    try expect(v[105] == 43);
    try expect(v[106] == 44);
    try expect(v[107] == 45);
    try expect(v[108] == 46);
    try expect(v[109] == 47);
    try expect(v[110] == 48);
    try expect(v[111] == 49);
    try expect(v[112] == 50);
    try expect(v[113] == 51);
    try expect(v[114] == 52);
    try expect(v[115] == 53);
    try expect(v[116] == 54);
    try expect(v[117] == 55);
    try expect(v[118] == 56);
    try expect(v[119] == 57);
    try expect(v[120] == 58);
    try expect(v[121] == 59);
    try expect(v[122] == 60);
    try expect(v[123] == 61);
    try expect(v[124] == 62);
    try expect(v[125] == 63);
    try expect(v[126] == 64);
    try expect(v[127] == 65);
    try expect(v[128] == 66);
    try expect(v[129] == 67);
    try expect(v[130] == 68);
    try expect(v[131] == 69);
    try expect(v[132] == 70);
    try expect(v[133] == 71);
    try expect(v[134] == 72);
    try expect(v[135] == 73);
    try expect(v[136] == 74);
    try expect(v[137] == 75);
    try expect(v[138] == 76);
    try expect(v[139] == 77);
    try expect(v[140] == 78);
    try expect(v[141] == 79);
    try expect(v[142] == 80);
    try expect(v[143] == 81);
    try expect(v[144] == 82);
    try expect(v[145] == 83);
    try expect(v[146] == 84);
    try expect(v[147] == 85);
    try expect(v[148] == 86);
    try expect(v[149] == 87);
    try expect(v[150] == 88);
    try expect(v[151] == 89);
    try expect(v[152] == 90);
    try expect(v[153] == 91);
    try expect(v[154] == 92);
    try expect(v[155] == 93);
    try expect(v[156] == 94);
    try expect(v[157] == 95);
    try expect(v[158] == 96);
    try expect(v[159] == 97);
    try expect(v[160] == 98);
    try expect(v[161] == 99);
    try expect(v[162] == 0);
    try expect(v[163] == 1);
    try expect(v[164] == 2);
    try expect(v[165] == 3);
    try expect(v[166] == 4);
    try expect(v[167] == 5);
    try expect(v[168] == 6);
    try expect(v[169] == 7);
    try expect(v[170] == 8);
    try expect(v[171] == 9);
    try expect(v[172] == 10);
    try expect(v[173] == 11);
    try expect(v[174] == 12);
    try expect(v[175] == 13);
    try expect(v[176] == 14);
    try expect(v[177] == 15);
    try expect(v[178] == 16);
    try expect(v[179] == 17);
    try expect(v[180] == 18);
    try expect(v[181] == 19);
    try expect(v[182] == 20);
    try expect(v[183] == 21);
    try expect(v[184] == 22);
    try expect(v[185] == 23);
    try expect(v[186] == 24);
    try expect(v[187] == 25);
    try expect(v[188] == 26);
    try expect(v[189] == 27);
    try expect(v[190] == 28);
    try expect(v[191] == 29);
    try expect(v[192] == 30);
    try expect(v[193] == 31);
    try expect(v[194] == 32);
    try expect(v[195] == 33);
    try expect(v[196] == 34);
    try expect(v[197] == 35);
    try expect(v[198] == 36);
    try expect(v[199] == 37);
    try expect(v[200] == 38);
    try expect(v[201] == 39);
    try expect(v[202] == 40);
    try expect(v[203] == 41);
    try expect(v[204] == 42);
    try expect(v[205] == 43);
    try expect(v[206] == 44);
    try expect(v[207] == 45);
    try expect(v[208] == 46);
    try expect(v[209] == 47);
    try expect(v[210] == 48);
    try expect(v[211] == 49);
    try expect(v[212] == 50);
    try expect(v[213] == 51);
    try expect(v[214] == 52);
    try expect(v[215] == 53);
    try expect(v[216] == 54);
    try expect(v[217] == 55);
    try expect(v[218] == 56);
    try expect(v[219] == 57);
    try expect(v[220] == 58);
    try expect(v[221] == 59);
    try expect(v[222] == 60);
    try expect(v[223] == 61);
    try expect(v[224] == 62);
    try expect(v[225] == 63);
    try expect(v[226] == 64);
    try expect(v[227] == 65);
    try expect(v[228] == 66);
    try expect(v[229] == 67);
    try expect(v[230] == 68);
    try expect(v[231] == 69);
    try expect(v[232] == 70);
    try expect(v[233] == 71);
    try expect(v[234] == 72);
    try expect(v[235] == 73);
    try expect(v[236] == 74);
    try expect(v[237] == 75);
    try expect(v[238] == 76);
    try expect(v[239] == 77);
    try expect(v[240] == 78);
    try expect(v[241] == 79);
    try expect(v[242] == 80);
    try expect(v[243] == 81);
    try expect(v[244] == 82);
    try expect(v[245] == 83);
    try expect(v[246] == 84);
    try expect(v[247] == 85);
    try expect(v[248] == 86);
    try expect(v[249] == 87);
    try expect(v[250] == 88);
    try expect(v[251] == 89);
    try expect(v[252] == 90);
    try expect(v[253] == 91);
    try expect(v[254] == 92);
    try expect(v[255] == 93);
    try expect(v[256] == 94);
    try expect(v[257] == 95);
    try expect(v[258] == 96);
    try expect(v[259] == 97);
    try expect(v[260] == 98);
    try expect(v[261] == 99);
    try expect(v[262] == 0);
    try expect(v[263] == 1);
    try expect(v[264] == 2);
    try expect(v[265] == 3);
    try expect(v[266] == 4);
    try expect(v[267] == 5);
    try expect(v[268] == 6);
    try expect(v[269] == 7);
    try expect(v[270] == 8);
    try expect(v[271] == 9);
    try expect(v[272] == 10);
    try expect(v[273] == 11);
    try expect(v[274] == 12);
    try expect(v[275] == 13);
    try expect(v[276] == 14);
    try expect(v[277] == 15);
    try expect(v[278] == 16);
    try expect(v[279] == 17);
    try expect(v[280] == 18);
    try expect(v[281] == 19);
    try expect(v[282] == 20);
    try expect(v[283] == 21);
    try expect(v[284] == 22);
    try expect(v[285] == 23);
    try expect(v[286] == 24);
    try expect(v[287] == 25);
    try expect(v[288] == 26);
    try expect(v[289] == 27);
    try expect(v[290] == 28);
    try expect(v[291] == 29);
    try expect(v[292] == 30);
    try expect(v[293] == 31);
    try expect(v[294] == 32);
    try expect(v[295] == 33);
    try expect(v[296] == 34);
    try expect(v[297] == 35);
    try expect(v[298] == 36);
    try expect(v[299] == 37);
    try expect(v[300] == 38);
    try expect(v[301] == 39);
    try expect(v[302] == 40);
    try expect(v[303] == 41);
    try expect(v[304] == 42);
    try expect(v[305] == 43);
    try expect(v[306] == 44);
    try expect(v[307] == 45);
    try expect(v[308] == 46);
    try expect(v[309] == 47);
    try expect(v[310] == 48);
    try expect(v[311] == 49);
    try expect(v[312] == 50);
    try expect(v[313] == 51);
    try expect(v[314] == 52);
    try expect(v[315] == 53);
    try expect(v[316] == 54);
    try expect(v[317] == 55);
    try expect(v[318] == 56);
    try expect(v[319] == 57);
    try expect(v[320] == 58);
    try expect(v[321] == 59);
    try expect(v[322] == 60);
    try expect(v[323] == 61);
    try expect(v[324] == 62);
    try expect(v[325] == 63);
    try expect(v[326] == 64);
    try expect(v[327] == 65);
    try expect(v[328] == 66);
    try expect(v[329] == 67);
    try expect(v[330] == 68);
    try expect(v[331] == 69);
    try expect(v[332] == 70);
    try expect(v[333] == 71);
    try expect(v[334] == 72);
    try expect(v[335] == 73);
    try expect(v[336] == 74);
    try expect(v[337] == 75);
    try expect(v[338] == 76);
    try expect(v[339] == 77);
    try expect(v[340] == 78);
    try expect(v[341] == 79);
    try expect(v[342] == 80);
    try expect(v[343] == 81);
    try expect(v[344] == 82);
    try expect(v[345] == 83);
    try expect(v[346] == 84);
    try expect(v[347] == 85);
    try expect(v[348] == 86);
    try expect(v[349] == 87);
    try expect(v[350] == 88);
    try expect(v[351] == 89);
    try expect(v[352] == 90);
    try expect(v[353] == 91);
    try expect(v[354] == 92);
    try expect(v[355] == 93);
    try expect(v[356] == 94);
    try expect(v[357] == 95);
    try expect(v[358] == 96);
    try expect(v[359] == 97);
    try expect(v[360] == 98);
    try expect(v[361] == 99);
    try expect(v[362] == 0);
    try expect(v[363] == 1);
    try expect(v[364] == 2);
    try expect(v[365] == 3);
    try expect(v[366] == 4);
    try expect(v[367] == 5);
    try expect(v[368] == 6);
    try expect(v[369] == 7);
    try expect(v[370] == 8);
    try expect(v[371] == 9);
    try expect(v[372] == 10);
    try expect(v[373] == 11);
    try expect(v[374] == 12);
    try expect(v[375] == 13);
    try expect(v[376] == 14);
    try expect(v[377] == 15);
    try expect(v[378] == 16);
    try expect(v[379] == 17);
    try expect(v[380] == 18);
    try expect(v[381] == 19);
    try expect(v[382] == 20);
    try expect(v[383] == 21);
    try expect(v[384] == 22);
    try expect(v[385] == 23);
    try expect(v[386] == 24);
    try expect(v[387] == 25);
    try expect(v[388] == 26);
    try expect(v[389] == 27);
    try expect(v[390] == 28);
    try expect(v[391] == 29);
    try expect(v[392] == 30);
    try expect(v[393] == 31);
    try expect(v[394] == 32);
    try expect(v[395] == 33);
    try expect(v[396] == 34);
    try expect(v[397] == 35);
    try expect(v[398] == 36);
    try expect(v[399] == 37);
    try expect(v[400] == 38);
    try expect(v[401] == 39);
    try expect(v[402] == 40);
    try expect(v[403] == 41);
    try expect(v[404] == 42);
    try expect(v[405] == 43);
    try expect(v[406] == 44);
    try expect(v[407] == 45);
    try expect(v[408] == 46);
    try expect(v[409] == 47);
    try expect(v[410] == 48);
    try expect(v[411] == 49);
    try expect(v[412] == 50);
    try expect(v[413] == 51);
    try expect(v[414] == 52);
    try expect(v[415] == 53);
    try expect(v[416] == 54);
    try expect(v[417] == 55);
    try expect(v[418] == 56);
    try expect(v[419] == 57);
    try expect(v[420] == 58);
    try expect(v[421] == 59);
    try expect(v[422] == 60);
    try expect(v[423] == 61);
    try expect(v[424] == 62);
    try expect(v[425] == 63);
    try expect(v[426] == 64);
    try expect(v[427] == 65);
    try expect(v[428] == 66);
    try expect(v[429] == 67);
    try expect(v[430] == 68);
    try expect(v[431] == 69);
    try expect(v[432] == 70);
    try expect(v[433] == 71);
    try expect(v[434] == 72);
    try expect(v[435] == 73);
    try expect(v[436] == 74);
    try expect(v[437] == 75);
    try expect(v[438] == 76);
    try expect(v[439] == 77);
    try expect(v[440] == 78);
    try expect(v[441] == 79);
    try expect(v[442] == 80);
    try expect(v[443] == 81);
    try expect(v[444] == 82);
    try expect(v[445] == 83);
    try expect(v[446] == 84);
    try expect(v[447] == 85);
    try expect(v[448] == 86);
    try expect(v[449] == 87);
    try expect(v[450] == 88);
    try expect(v[451] == 89);
    try expect(v[452] == 90);
    try expect(v[453] == 91);
    try expect(v[454] == 92);
    try expect(v[455] == 93);
    try expect(v[456] == 94);
    try expect(v[457] == 95);
    try expect(v[458] == 96);
    try expect(v[459] == 97);
    try expect(v[460] == 98);
    try expect(v[461] == 99);
    try expect(v[462] == 0);
    try expect(v[463] == 1);
    try expect(v[464] == 2);
    try expect(v[465] == 3);
    try expect(v[466] == 4);
    try expect(v[467] == 5);
    try expect(v[468] == 6);
    try expect(v[469] == 7);
    try expect(v[470] == 8);
    try expect(v[471] == 9);
    try expect(v[472] == 10);
    try expect(v[473] == 11);
    try expect(v[474] == 12);
    try expect(v[475] == 13);
    try expect(v[476] == 14);
    try expect(v[477] == 15);
    try expect(v[478] == 16);
    try expect(v[479] == 17);
    try expect(v[480] == 18);
    try expect(v[481] == 19);
    try expect(v[482] == 20);
    try expect(v[483] == 21);
    try expect(v[484] == 22);
    try expect(v[485] == 23);
    try expect(v[486] == 24);
    try expect(v[487] == 25);
    try expect(v[488] == 26);
    try expect(v[489] == 27);
    try expect(v[490] == 28);
    try expect(v[491] == 29);
    try expect(v[492] == 30);
    try expect(v[493] == 31);
    try expect(v[494] == 32);
    try expect(v[495] == 33);
    try expect(v[496] == 34);
    try expect(v[497] == 35);
    try expect(v[498] == 36);
    try expect(v[499] == 37);
    try expect(v[500] == 38);
    try expect(v[501] == 39);
    try expect(v[502] == 40);
    try expect(v[503] == 41);
    try expect(v[504] == 42);
    try expect(v[505] == 43);
    try expect(v[506] == 44);
    try expect(v[507] == 45);
    try expect(v[508] == 46);
    try expect(v[509] == 47);
    try expect(v[510] == 48);
    try expect(v[511] == 49);
    c_vector_512_u8(.{
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
        50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65,
        66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81,
        82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97,
        98, 99, 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13,
        14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
        30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45,
        46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61,
    }, 512);
    c_test_vector_512_u8();
}

export fn zig_ret_vector_1_u16() @Vector(1, u16) {
    return .{1};
}
export fn zig_vector_1_u16(v: @Vector(1, u16), i: usize) void {
    expect(v[0] == 2) catch @panic("test failure");
    expect(i == 1) catch @panic("test failure");
}

extern fn c_ret_vector_1_u16() @Vector(1, u16);
extern fn c_vector_1_u16(@Vector(1, u16), usize) void;
extern fn c_test_vector_1_u16() void;

test "@Vector(1, u16)" {
    if (builtin.cpu.arch.isAARCH64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;

    const v = c_ret_vector_1_u16();
    try expect(v[0] == 3);
    c_vector_1_u16(.{4}, 1);
    c_test_vector_1_u16();
}

export fn zig_ret_vector_2_u16() @Vector(2, u16) {
    return .{ 5, 6 };
}
export fn zig_vector_2_u16(v: @Vector(2, u16), i: usize) void {
    expect(v[0] == 7) catch @panic("test failure");
    expect(v[1] == 8) catch @panic("test failure");
    expect(i == 2) catch @panic("test failure");
}

extern fn c_ret_vector_2_u16() @Vector(2, u16);
extern fn c_vector_2_u16(@Vector(2, u16), usize) void;
extern fn c_test_vector_2_u16() void;

test "@Vector(2, u16)" {
    if (builtin.cpu.arch.isAARCH64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .x86_64) return error.SkipZigTest;

    const v = c_ret_vector_2_u16();
    try expect(v[0] == 9);
    try expect(v[1] == 10);
    c_vector_2_u16(.{ 11, 12 }, 2);
    c_test_vector_2_u16();
}

export fn zig_ret_vector_3_u16() @Vector(3, u16) {
    return .{ 13, 14, 15 };
}
export fn zig_vector_3_u16(v: @Vector(3, u16), i: usize) void {
    expect(v[0] == 16) catch @panic("test failure");
    expect(v[1] == 17) catch @panic("test failure");
    expect(v[2] == 18) catch @panic("test failure");
    expect(i == 3) catch @panic("test failure");
}

extern fn c_ret_vector_3_u16() @Vector(3, u16);
extern fn c_vector_3_u16(@Vector(3, u16), usize) void;
extern fn c_test_vector_3_u16() void;

test "@Vector(3, u16)" {
    if (builtin.cpu.arch.isArm() and builtin.abi.float() == .soft) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .x86_64 and builtin.os.tag != .windows) return error.SkipZigTest;

    const v = c_ret_vector_3_u16();
    try expect(v[0] == 19);
    try expect(v[1] == 20);
    try expect(v[2] == 21);
    c_vector_3_u16(.{ 22, 23, 24 }, 3);
    c_test_vector_3_u16();
}

export fn zig_ret_vector_4_u16() @Vector(4, u16) {
    return .{ 25, 26, 27, 28 };
}
export fn zig_vector_4_u16(v: @Vector(4, u16), i: usize) void {
    expect(v[0] == 29) catch @panic("test failure");
    expect(v[1] == 30) catch @panic("test failure");
    expect(v[2] == 31) catch @panic("test failure");
    expect(v[3] == 32) catch @panic("test failure");
    expect(i == 4) catch @panic("test failure");
}
export fn zig_vector_4_u16_vector_4_u16(v0: @Vector(4, u16), v1: @Vector(4, u16), i: usize) void {
    expect(v0[0] == 33) catch @panic("test failure");
    expect(v0[1] == 34) catch @panic("test failure");
    expect(v0[2] == 35) catch @panic("test failure");
    expect(v0[3] == 36) catch @panic("test failure");
    expect(v1[0] == 37) catch @panic("test failure");
    expect(v1[1] == 38) catch @panic("test failure");
    expect(v1[2] == 39) catch @panic("test failure");
    expect(v1[3] == 40) catch @panic("test failure");
    expect(i == 8) catch @panic("test failure");
}

extern fn c_ret_vector_4_u16() @Vector(4, u16);
extern fn c_vector_4_u16(@Vector(4, u16), usize) void;
extern fn c_vector_4_u16_vector_4_u16(@Vector(4, u16), @Vector(4, u16), usize) void;
extern fn c_test_vector_4_u16() void;

test "@Vector(4, u16)" {
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .x86_64 and builtin.os.tag == .windows) return error.SkipZigTest;

    const v = c_ret_vector_4_u16();
    try expect(v[0] == 41);
    try expect(v[1] == 42);
    try expect(v[2] == 43);
    try expect(v[3] == 44);
    c_vector_4_u16(.{ 45, 46, 47, 48 }, 4);
    c_vector_4_u16_vector_4_u16(.{ 49, 50, 51, 52 }, .{ 53, 54, 55, 56 }, 8);
    c_test_vector_4_u16();
}

export fn zig_ret_vector_6_u16() @Vector(6, u16) {
    return .{ 41, 42, 43, 44, 45, 46 };
}
export fn zig_vector_6_u16(v: @Vector(6, u16), i: usize) void {
    expect(v[0] == 47) catch @panic("test failure");
    expect(v[1] == 48) catch @panic("test failure");
    expect(v[2] == 49) catch @panic("test failure");
    expect(v[3] == 50) catch @panic("test failure");
    expect(v[4] == 51) catch @panic("test failure");
    expect(v[5] == 52) catch @panic("test failure");
    expect(i == 6) catch @panic("test failure");
}

extern fn c_ret_vector_6_u16() @Vector(6, u16);
extern fn c_vector_6_u16(@Vector(6, u16), usize) void;
extern fn c_test_vector_6_u16() void;

test "@Vector(6, u16)" {
    if (builtin.cpu.arch.isArm() and builtin.abi.float() == .soft) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;

    const v = c_ret_vector_6_u16();
    try expect(v[0] == 53);
    try expect(v[1] == 54);
    try expect(v[2] == 55);
    try expect(v[3] == 56);
    try expect(v[4] == 57);
    try expect(v[5] == 58);
    c_vector_6_u16(.{ 59, 60, 61, 62, 63, 64 }, 6);
    c_test_vector_6_u16();
}

export fn zig_ret_vector_8_u16() @Vector(8, u16) {
    return .{ 65, 66, 67, 68, 69, 70, 71, 72 };
}
export fn zig_vector_8_u16(v: @Vector(8, u16), i: usize) void {
    expect(v[0] == 73) catch @panic("test failure");
    expect(v[1] == 74) catch @panic("test failure");
    expect(v[2] == 75) catch @panic("test failure");
    expect(v[3] == 76) catch @panic("test failure");
    expect(v[4] == 77) catch @panic("test failure");
    expect(v[5] == 78) catch @panic("test failure");
    expect(v[6] == 79) catch @panic("test failure");
    expect(v[7] == 80) catch @panic("test failure");
    expect(i == 8) catch @panic("test failure");
}

extern fn c_ret_vector_8_u16() @Vector(8, u16);
extern fn c_vector_8_u16(@Vector(8, u16), usize) void;
extern fn c_test_vector_8_u16() void;

test "@Vector(8, u16)" {
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;

    const v = c_ret_vector_8_u16();
    try expect(v[0] == 81);
    try expect(v[1] == 82);
    try expect(v[2] == 83);
    try expect(v[3] == 84);
    try expect(v[4] == 85);
    try expect(v[5] == 86);
    try expect(v[6] == 87);
    try expect(v[7] == 88);
    c_vector_8_u16(.{ 89, 90, 91, 92, 93, 94, 95, 96 }, 8);
    c_test_vector_8_u16();
}

export fn zig_ret_vector_12_u16() @Vector(12, u16) {
    return .{ 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108 };
}
export fn zig_vector_12_u16(v: @Vector(12, u16), i: usize) void {
    expect(v[0] == 109) catch @panic("test failure");
    expect(v[1] == 110) catch @panic("test failure");
    expect(v[2] == 111) catch @panic("test failure");
    expect(v[3] == 112) catch @panic("test failure");
    expect(v[4] == 113) catch @panic("test failure");
    expect(v[5] == 114) catch @panic("test failure");
    expect(v[6] == 115) catch @panic("test failure");
    expect(v[7] == 116) catch @panic("test failure");
    expect(v[8] == 117) catch @panic("test failure");
    expect(v[9] == 118) catch @panic("test failure");
    expect(v[10] == 119) catch @panic("test failure");
    expect(v[11] == 120) catch @panic("test failure");
    expect(i == 12) catch @panic("test failure");
}

extern fn c_ret_vector_12_u16() @Vector(12, u16);
extern fn c_vector_12_u16(@Vector(12, u16), usize) void;
extern fn c_test_vector_12_u16() void;

test "@Vector(12, u16)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_12_u16();
    try expect(v[0] == 121);
    try expect(v[1] == 122);
    try expect(v[2] == 123);
    try expect(v[3] == 124);
    try expect(v[4] == 125);
    try expect(v[5] == 126);
    try expect(v[6] == 127);
    try expect(v[7] == 128);
    try expect(v[8] == 129);
    try expect(v[9] == 130);
    try expect(v[10] == 131);
    try expect(v[11] == 132);
    c_vector_12_u16(.{ 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144 }, 12);
    c_test_vector_12_u16();
}

export fn zig_ret_vector_16_u16() @Vector(16, u16) {
    return .{ 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160 };
}
export fn zig_vector_16_u16(v: @Vector(16, u16), i: usize) void {
    expect(v[0] == 161) catch @panic("test failure");
    expect(v[1] == 162) catch @panic("test failure");
    expect(v[2] == 163) catch @panic("test failure");
    expect(v[3] == 164) catch @panic("test failure");
    expect(v[4] == 165) catch @panic("test failure");
    expect(v[5] == 166) catch @panic("test failure");
    expect(v[6] == 167) catch @panic("test failure");
    expect(v[7] == 168) catch @panic("test failure");
    expect(v[8] == 169) catch @panic("test failure");
    expect(v[9] == 170) catch @panic("test failure");
    expect(v[10] == 171) catch @panic("test failure");
    expect(v[11] == 172) catch @panic("test failure");
    expect(v[12] == 173) catch @panic("test failure");
    expect(v[13] == 174) catch @panic("test failure");
    expect(v[14] == 175) catch @panic("test failure");
    expect(v[15] == 176) catch @panic("test failure");
    expect(i == 16) catch @panic("test failure");
}

extern fn c_ret_vector_16_u16() @Vector(16, u16);
extern fn c_vector_16_u16(@Vector(16, u16), usize) void;
extern fn c_test_vector_16_u16() void;

test "@Vector(16, u16)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_16_u16();
    try expect(v[0] == 177);
    try expect(v[1] == 178);
    try expect(v[2] == 179);
    try expect(v[3] == 180);
    try expect(v[4] == 181);
    try expect(v[5] == 182);
    try expect(v[6] == 183);
    try expect(v[7] == 184);
    try expect(v[8] == 185);
    try expect(v[9] == 186);
    try expect(v[10] == 187);
    try expect(v[11] == 188);
    try expect(v[12] == 189);
    try expect(v[13] == 190);
    try expect(v[14] == 191);
    try expect(v[15] == 192);
    c_vector_16_u16(.{ 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208 }, 16);
    c_test_vector_16_u16();
}

export fn zig_ret_vector_24_u16() @Vector(24, u16) {
    return .{
        209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224,
        225, 226, 227, 228, 229, 230, 231, 232,
    };
}
export fn zig_vector_24_u16(v: @Vector(24, u16), i: usize) void {
    expect(v[0] == 233) catch @panic("test failure");
    expect(v[1] == 234) catch @panic("test failure");
    expect(v[2] == 235) catch @panic("test failure");
    expect(v[3] == 236) catch @panic("test failure");
    expect(v[4] == 237) catch @panic("test failure");
    expect(v[5] == 238) catch @panic("test failure");
    expect(v[6] == 239) catch @panic("test failure");
    expect(v[7] == 240) catch @panic("test failure");
    expect(v[8] == 241) catch @panic("test failure");
    expect(v[9] == 242) catch @panic("test failure");
    expect(v[10] == 243) catch @panic("test failure");
    expect(v[11] == 244) catch @panic("test failure");
    expect(v[12] == 245) catch @panic("test failure");
    expect(v[13] == 246) catch @panic("test failure");
    expect(v[14] == 247) catch @panic("test failure");
    expect(v[15] == 248) catch @panic("test failure");
    expect(v[16] == 249) catch @panic("test failure");
    expect(v[17] == 250) catch @panic("test failure");
    expect(v[18] == 251) catch @panic("test failure");
    expect(v[19] == 252) catch @panic("test failure");
    expect(v[20] == 253) catch @panic("test failure");
    expect(v[21] == 254) catch @panic("test failure");
    expect(v[22] == 255) catch @panic("test failure");
    expect(v[23] == 256) catch @panic("test failure");
    expect(i == 24) catch @panic("test failure");
}

extern fn c_ret_vector_24_u16() @Vector(24, u16);
extern fn c_vector_24_u16(@Vector(24, u16), usize) void;
extern fn c_test_vector_24_u16() void;

test "@Vector(24, u16)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_24_u16();
    try expect(v[0] == 257);
    try expect(v[1] == 258);
    try expect(v[2] == 259);
    try expect(v[3] == 260);
    try expect(v[4] == 261);
    try expect(v[5] == 262);
    try expect(v[6] == 263);
    try expect(v[7] == 264);
    try expect(v[8] == 265);
    try expect(v[9] == 266);
    try expect(v[10] == 267);
    try expect(v[11] == 268);
    try expect(v[12] == 269);
    try expect(v[13] == 270);
    try expect(v[14] == 271);
    try expect(v[15] == 272);
    try expect(v[16] == 273);
    try expect(v[17] == 274);
    try expect(v[18] == 275);
    try expect(v[19] == 276);
    try expect(v[20] == 277);
    try expect(v[21] == 278);
    try expect(v[22] == 279);
    try expect(v[23] == 280);
    c_vector_24_u16(.{
        281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296,
        297, 298, 299, 300, 301, 302, 303, 304,
    }, 24);
    c_test_vector_24_u16();
}

export fn zig_ret_vector_32_u16() @Vector(32, u16) {
    return .{
        305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320,
        321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336,
    };
}
export fn zig_vector_32_u16(v: @Vector(32, u16), i: usize) void {
    expect(v[0] == 337) catch @panic("test failure");
    expect(v[1] == 338) catch @panic("test failure");
    expect(v[2] == 339) catch @panic("test failure");
    expect(v[3] == 340) catch @panic("test failure");
    expect(v[4] == 341) catch @panic("test failure");
    expect(v[5] == 342) catch @panic("test failure");
    expect(v[6] == 343) catch @panic("test failure");
    expect(v[7] == 344) catch @panic("test failure");
    expect(v[8] == 345) catch @panic("test failure");
    expect(v[9] == 346) catch @panic("test failure");
    expect(v[10] == 347) catch @panic("test failure");
    expect(v[11] == 348) catch @panic("test failure");
    expect(v[12] == 349) catch @panic("test failure");
    expect(v[13] == 350) catch @panic("test failure");
    expect(v[14] == 351) catch @panic("test failure");
    expect(v[15] == 352) catch @panic("test failure");
    expect(v[16] == 353) catch @panic("test failure");
    expect(v[17] == 354) catch @panic("test failure");
    expect(v[18] == 355) catch @panic("test failure");
    expect(v[19] == 356) catch @panic("test failure");
    expect(v[20] == 357) catch @panic("test failure");
    expect(v[21] == 358) catch @panic("test failure");
    expect(v[22] == 359) catch @panic("test failure");
    expect(v[23] == 360) catch @panic("test failure");
    expect(v[24] == 361) catch @panic("test failure");
    expect(v[25] == 362) catch @panic("test failure");
    expect(v[26] == 363) catch @panic("test failure");
    expect(v[27] == 364) catch @panic("test failure");
    expect(v[28] == 365) catch @panic("test failure");
    expect(v[29] == 366) catch @panic("test failure");
    expect(v[30] == 367) catch @panic("test failure");
    expect(v[31] == 368) catch @panic("test failure");
    expect(i == 32) catch @panic("test failure");
}

extern fn c_ret_vector_32_u16() @Vector(32, u16);
extern fn c_vector_32_u16(@Vector(32, u16), usize) void;
extern fn c_test_vector_32_u16() void;

test "@Vector(32, u16)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_32_u16();
    try expect(v[0] == 369);
    try expect(v[1] == 370);
    try expect(v[2] == 371);
    try expect(v[3] == 372);
    try expect(v[4] == 373);
    try expect(v[5] == 374);
    try expect(v[6] == 375);
    try expect(v[7] == 376);
    try expect(v[8] == 377);
    try expect(v[9] == 378);
    try expect(v[10] == 379);
    try expect(v[11] == 380);
    try expect(v[12] == 381);
    try expect(v[13] == 382);
    try expect(v[14] == 383);
    try expect(v[15] == 384);
    try expect(v[16] == 385);
    try expect(v[17] == 386);
    try expect(v[18] == 387);
    try expect(v[19] == 388);
    try expect(v[20] == 389);
    try expect(v[21] == 390);
    try expect(v[22] == 391);
    try expect(v[23] == 392);
    try expect(v[24] == 393);
    try expect(v[25] == 394);
    try expect(v[26] == 395);
    try expect(v[27] == 396);
    try expect(v[28] == 397);
    try expect(v[29] == 398);
    try expect(v[30] == 399);
    try expect(v[31] == 400);
    c_vector_32_u16(.{
        401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416,
        417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, 431, 432,
    }, 32);
    c_test_vector_32_u16();
}

export fn zig_ret_vector_48_u16() @Vector(48, u16) {
    return .{
        433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 443, 444, 445, 446, 447, 448,
        449, 450, 451, 452, 453, 454, 455, 456, 457, 458, 459, 460, 461, 462, 463, 464,
        465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480,
    };
}
export fn zig_vector_48_u16(v: @Vector(48, u16), i: usize) void {
    expect(v[0] == 481) catch @panic("test failure");
    expect(v[1] == 482) catch @panic("test failure");
    expect(v[2] == 483) catch @panic("test failure");
    expect(v[3] == 484) catch @panic("test failure");
    expect(v[4] == 485) catch @panic("test failure");
    expect(v[5] == 486) catch @panic("test failure");
    expect(v[6] == 487) catch @panic("test failure");
    expect(v[7] == 488) catch @panic("test failure");
    expect(v[8] == 489) catch @panic("test failure");
    expect(v[9] == 490) catch @panic("test failure");
    expect(v[10] == 491) catch @panic("test failure");
    expect(v[11] == 492) catch @panic("test failure");
    expect(v[12] == 493) catch @panic("test failure");
    expect(v[13] == 494) catch @panic("test failure");
    expect(v[14] == 495) catch @panic("test failure");
    expect(v[15] == 496) catch @panic("test failure");
    expect(v[16] == 497) catch @panic("test failure");
    expect(v[17] == 498) catch @panic("test failure");
    expect(v[18] == 499) catch @panic("test failure");
    expect(v[19] == 500) catch @panic("test failure");
    expect(v[20] == 501) catch @panic("test failure");
    expect(v[21] == 502) catch @panic("test failure");
    expect(v[22] == 503) catch @panic("test failure");
    expect(v[23] == 504) catch @panic("test failure");
    expect(v[24] == 505) catch @panic("test failure");
    expect(v[25] == 506) catch @panic("test failure");
    expect(v[26] == 507) catch @panic("test failure");
    expect(v[27] == 508) catch @panic("test failure");
    expect(v[28] == 509) catch @panic("test failure");
    expect(v[29] == 510) catch @panic("test failure");
    expect(v[30] == 511) catch @panic("test failure");
    expect(v[31] == 512) catch @panic("test failure");
    expect(v[32] == 513) catch @panic("test failure");
    expect(v[33] == 514) catch @panic("test failure");
    expect(v[34] == 515) catch @panic("test failure");
    expect(v[35] == 516) catch @panic("test failure");
    expect(v[36] == 517) catch @panic("test failure");
    expect(v[37] == 518) catch @panic("test failure");
    expect(v[38] == 519) catch @panic("test failure");
    expect(v[39] == 520) catch @panic("test failure");
    expect(v[40] == 521) catch @panic("test failure");
    expect(v[41] == 522) catch @panic("test failure");
    expect(v[42] == 523) catch @panic("test failure");
    expect(v[43] == 524) catch @panic("test failure");
    expect(v[44] == 525) catch @panic("test failure");
    expect(v[45] == 526) catch @panic("test failure");
    expect(v[46] == 527) catch @panic("test failure");
    expect(v[47] == 528) catch @panic("test failure");
    expect(i == 48) catch @panic("test failure");
}

extern fn c_ret_vector_48_u16() @Vector(48, u16);
extern fn c_vector_48_u16(@Vector(48, u16), usize) void;
extern fn c_test_vector_48_u16() void;

test "@Vector(48, u16)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_48_u16();
    try expect(v[0] == 529);
    try expect(v[1] == 530);
    try expect(v[2] == 531);
    try expect(v[3] == 532);
    try expect(v[4] == 533);
    try expect(v[5] == 534);
    try expect(v[6] == 535);
    try expect(v[7] == 536);
    try expect(v[8] == 537);
    try expect(v[9] == 538);
    try expect(v[10] == 539);
    try expect(v[11] == 540);
    try expect(v[12] == 541);
    try expect(v[13] == 542);
    try expect(v[14] == 543);
    try expect(v[15] == 544);
    try expect(v[16] == 545);
    try expect(v[17] == 546);
    try expect(v[18] == 547);
    try expect(v[19] == 548);
    try expect(v[20] == 549);
    try expect(v[21] == 550);
    try expect(v[22] == 551);
    try expect(v[23] == 552);
    try expect(v[24] == 553);
    try expect(v[25] == 554);
    try expect(v[26] == 555);
    try expect(v[27] == 556);
    try expect(v[28] == 557);
    try expect(v[29] == 558);
    try expect(v[30] == 559);
    try expect(v[31] == 560);
    try expect(v[32] == 561);
    try expect(v[33] == 562);
    try expect(v[34] == 563);
    try expect(v[35] == 564);
    try expect(v[36] == 565);
    try expect(v[37] == 566);
    try expect(v[38] == 567);
    try expect(v[39] == 568);
    try expect(v[40] == 569);
    try expect(v[41] == 570);
    try expect(v[42] == 571);
    try expect(v[43] == 572);
    try expect(v[44] == 573);
    try expect(v[45] == 574);
    try expect(v[46] == 575);
    try expect(v[47] == 576);
    c_vector_48_u16(.{
        577, 578, 579, 580, 581, 582, 583, 584, 585, 586, 587, 588, 589, 590, 591, 592,
        593, 594, 595, 596, 597, 598, 599, 600, 601, 602, 603, 604, 605, 606, 607, 608,
        609, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621, 622, 623, 624,
    }, 48);
    c_test_vector_48_u16();
}

export fn zig_ret_vector_64_u16() @Vector(64, u16) {
    return .{
        625, 626, 627, 628, 629, 630, 631, 632, 633, 634, 635, 636, 637, 638, 639, 640,
        641, 642, 643, 644, 645, 646, 647, 648, 649, 650, 651, 652, 653, 654, 655, 656,
        657, 658, 659, 660, 661, 662, 663, 664, 665, 666, 667, 668, 669, 670, 671, 672,
        673, 674, 675, 676, 677, 678, 679, 680, 681, 682, 683, 684, 685, 686, 687, 688,
    };
}
export fn zig_vector_64_u16(v: @Vector(64, u16), i: usize) void {
    expect(v[0] == 689) catch @panic("test failure");
    expect(v[1] == 690) catch @panic("test failure");
    expect(v[2] == 691) catch @panic("test failure");
    expect(v[3] == 692) catch @panic("test failure");
    expect(v[4] == 693) catch @panic("test failure");
    expect(v[5] == 694) catch @panic("test failure");
    expect(v[6] == 695) catch @panic("test failure");
    expect(v[7] == 696) catch @panic("test failure");
    expect(v[8] == 697) catch @panic("test failure");
    expect(v[9] == 698) catch @panic("test failure");
    expect(v[10] == 699) catch @panic("test failure");
    expect(v[11] == 700) catch @panic("test failure");
    expect(v[12] == 701) catch @panic("test failure");
    expect(v[13] == 702) catch @panic("test failure");
    expect(v[14] == 703) catch @panic("test failure");
    expect(v[15] == 704) catch @panic("test failure");
    expect(v[16] == 705) catch @panic("test failure");
    expect(v[17] == 706) catch @panic("test failure");
    expect(v[18] == 707) catch @panic("test failure");
    expect(v[19] == 708) catch @panic("test failure");
    expect(v[20] == 709) catch @panic("test failure");
    expect(v[21] == 710) catch @panic("test failure");
    expect(v[22] == 711) catch @panic("test failure");
    expect(v[23] == 712) catch @panic("test failure");
    expect(v[24] == 713) catch @panic("test failure");
    expect(v[25] == 714) catch @panic("test failure");
    expect(v[26] == 715) catch @panic("test failure");
    expect(v[27] == 716) catch @panic("test failure");
    expect(v[28] == 717) catch @panic("test failure");
    expect(v[29] == 718) catch @panic("test failure");
    expect(v[30] == 719) catch @panic("test failure");
    expect(v[31] == 720) catch @panic("test failure");
    expect(v[32] == 721) catch @panic("test failure");
    expect(v[33] == 722) catch @panic("test failure");
    expect(v[34] == 723) catch @panic("test failure");
    expect(v[35] == 724) catch @panic("test failure");
    expect(v[36] == 725) catch @panic("test failure");
    expect(v[37] == 726) catch @panic("test failure");
    expect(v[38] == 727) catch @panic("test failure");
    expect(v[39] == 728) catch @panic("test failure");
    expect(v[40] == 729) catch @panic("test failure");
    expect(v[41] == 730) catch @panic("test failure");
    expect(v[42] == 731) catch @panic("test failure");
    expect(v[43] == 732) catch @panic("test failure");
    expect(v[44] == 733) catch @panic("test failure");
    expect(v[45] == 734) catch @panic("test failure");
    expect(v[46] == 735) catch @panic("test failure");
    expect(v[47] == 736) catch @panic("test failure");
    expect(v[48] == 737) catch @panic("test failure");
    expect(v[49] == 738) catch @panic("test failure");
    expect(v[50] == 739) catch @panic("test failure");
    expect(v[51] == 740) catch @panic("test failure");
    expect(v[52] == 741) catch @panic("test failure");
    expect(v[53] == 742) catch @panic("test failure");
    expect(v[54] == 743) catch @panic("test failure");
    expect(v[55] == 744) catch @panic("test failure");
    expect(v[56] == 745) catch @panic("test failure");
    expect(v[57] == 746) catch @panic("test failure");
    expect(v[58] == 747) catch @panic("test failure");
    expect(v[59] == 748) catch @panic("test failure");
    expect(v[60] == 749) catch @panic("test failure");
    expect(v[61] == 750) catch @panic("test failure");
    expect(v[62] == 751) catch @panic("test failure");
    expect(v[63] == 752) catch @panic("test failure");
    expect(i == 64) catch @panic("test failure");
}

extern fn c_ret_vector_64_u16() @Vector(64, u16);
extern fn c_vector_64_u16(@Vector(64, u16), usize) void;
extern fn c_test_vector_64_u16() void;

test "@Vector(64, u16)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_64_u16();
    try expect(v[0] == 753);
    try expect(v[1] == 754);
    try expect(v[2] == 755);
    try expect(v[3] == 756);
    try expect(v[4] == 757);
    try expect(v[5] == 758);
    try expect(v[6] == 759);
    try expect(v[7] == 760);
    try expect(v[8] == 761);
    try expect(v[9] == 762);
    try expect(v[10] == 763);
    try expect(v[11] == 764);
    try expect(v[12] == 765);
    try expect(v[13] == 766);
    try expect(v[14] == 767);
    try expect(v[15] == 768);
    try expect(v[16] == 769);
    try expect(v[17] == 770);
    try expect(v[18] == 771);
    try expect(v[19] == 772);
    try expect(v[20] == 773);
    try expect(v[21] == 774);
    try expect(v[22] == 775);
    try expect(v[23] == 776);
    try expect(v[24] == 777);
    try expect(v[25] == 778);
    try expect(v[26] == 779);
    try expect(v[27] == 780);
    try expect(v[28] == 781);
    try expect(v[29] == 782);
    try expect(v[30] == 783);
    try expect(v[31] == 784);
    try expect(v[32] == 785);
    try expect(v[33] == 786);
    try expect(v[34] == 787);
    try expect(v[35] == 788);
    try expect(v[36] == 789);
    try expect(v[37] == 790);
    try expect(v[38] == 791);
    try expect(v[39] == 792);
    try expect(v[40] == 793);
    try expect(v[41] == 794);
    try expect(v[42] == 795);
    try expect(v[43] == 796);
    try expect(v[44] == 797);
    try expect(v[45] == 798);
    try expect(v[46] == 799);
    try expect(v[47] == 800);
    try expect(v[48] == 801);
    try expect(v[49] == 802);
    try expect(v[50] == 803);
    try expect(v[51] == 804);
    try expect(v[52] == 805);
    try expect(v[53] == 806);
    try expect(v[54] == 807);
    try expect(v[55] == 808);
    try expect(v[56] == 809);
    try expect(v[57] == 810);
    try expect(v[58] == 811);
    try expect(v[59] == 812);
    try expect(v[60] == 813);
    try expect(v[61] == 814);
    try expect(v[62] == 815);
    try expect(v[63] == 816);
    c_vector_64_u16(.{
        817, 818, 819, 820, 821, 822, 823, 824, 825, 826, 827, 828, 829, 830, 831, 832,
        833, 834, 835, 836, 837, 838, 839, 840, 841, 842, 843, 844, 845, 846, 847, 848,
        849, 850, 851, 852, 853, 854, 855, 856, 857, 858, 859, 860, 861, 862, 863, 864,
        865, 866, 867, 868, 869, 870, 871, 872, 873, 874, 875, 876, 877, 878, 879, 880,
    }, 64);
    c_test_vector_64_u16();
}

export fn zig_ret_vector_96_u16() @Vector(96, u16) {
    return .{
        890, 891, 892, 893, 894, 895, 896, 897, 898, 899, 900, 901, 902, 903, 904, 905,
        906, 907, 908, 909, 910, 911, 912, 913, 914, 915, 916, 917, 918, 919, 920, 921,
        922, 923, 924, 925, 926, 927, 928, 929, 930, 931, 932, 933, 934, 935, 936, 937,
        938, 939, 940, 941, 942, 943, 944, 945, 946, 947, 948, 949, 950, 951, 952, 953,
        954, 955, 956, 957, 958, 959, 960, 961, 962, 963, 964, 965, 966, 967, 968, 969,
        970, 971, 972, 973, 974, 975, 976, 977, 978, 979, 980, 981, 982, 983, 984, 985,
    };
}
export fn zig_vector_96_u16(v: @Vector(96, u16), i: usize) void {
    expect(v[0] == 986) catch @panic("test failure");
    expect(v[1] == 987) catch @panic("test failure");
    expect(v[2] == 988) catch @panic("test failure");
    expect(v[3] == 989) catch @panic("test failure");
    expect(v[4] == 990) catch @panic("test failure");
    expect(v[5] == 991) catch @panic("test failure");
    expect(v[6] == 992) catch @panic("test failure");
    expect(v[7] == 993) catch @panic("test failure");
    expect(v[8] == 994) catch @panic("test failure");
    expect(v[9] == 995) catch @panic("test failure");
    expect(v[10] == 996) catch @panic("test failure");
    expect(v[11] == 997) catch @panic("test failure");
    expect(v[12] == 998) catch @panic("test failure");
    expect(v[13] == 999) catch @panic("test failure");
    expect(v[14] == 1000) catch @panic("test failure");
    expect(v[15] == 1001) catch @panic("test failure");
    expect(v[16] == 1002) catch @panic("test failure");
    expect(v[17] == 1003) catch @panic("test failure");
    expect(v[18] == 1004) catch @panic("test failure");
    expect(v[19] == 1005) catch @panic("test failure");
    expect(v[20] == 1006) catch @panic("test failure");
    expect(v[21] == 1007) catch @panic("test failure");
    expect(v[22] == 1008) catch @panic("test failure");
    expect(v[23] == 1009) catch @panic("test failure");
    expect(v[24] == 1010) catch @panic("test failure");
    expect(v[25] == 1011) catch @panic("test failure");
    expect(v[26] == 1012) catch @panic("test failure");
    expect(v[27] == 1013) catch @panic("test failure");
    expect(v[28] == 1014) catch @panic("test failure");
    expect(v[29] == 1015) catch @panic("test failure");
    expect(v[30] == 1016) catch @panic("test failure");
    expect(v[31] == 1017) catch @panic("test failure");
    expect(v[32] == 1018) catch @panic("test failure");
    expect(v[33] == 1019) catch @panic("test failure");
    expect(v[34] == 1020) catch @panic("test failure");
    expect(v[35] == 1021) catch @panic("test failure");
    expect(v[36] == 1022) catch @panic("test failure");
    expect(v[37] == 1023) catch @panic("test failure");
    expect(v[38] == 1024) catch @panic("test failure");
    expect(v[39] == 1025) catch @panic("test failure");
    expect(v[40] == 1026) catch @panic("test failure");
    expect(v[41] == 1027) catch @panic("test failure");
    expect(v[42] == 1028) catch @panic("test failure");
    expect(v[43] == 1029) catch @panic("test failure");
    expect(v[44] == 1030) catch @panic("test failure");
    expect(v[45] == 1031) catch @panic("test failure");
    expect(v[46] == 1032) catch @panic("test failure");
    expect(v[47] == 1033) catch @panic("test failure");
    expect(v[48] == 1034) catch @panic("test failure");
    expect(v[49] == 1035) catch @panic("test failure");
    expect(v[50] == 1036) catch @panic("test failure");
    expect(v[51] == 1037) catch @panic("test failure");
    expect(v[52] == 1038) catch @panic("test failure");
    expect(v[53] == 1039) catch @panic("test failure");
    expect(v[54] == 1040) catch @panic("test failure");
    expect(v[55] == 1041) catch @panic("test failure");
    expect(v[56] == 1042) catch @panic("test failure");
    expect(v[57] == 1043) catch @panic("test failure");
    expect(v[58] == 1044) catch @panic("test failure");
    expect(v[59] == 1045) catch @panic("test failure");
    expect(v[60] == 1046) catch @panic("test failure");
    expect(v[61] == 1047) catch @panic("test failure");
    expect(v[62] == 1048) catch @panic("test failure");
    expect(v[63] == 1049) catch @panic("test failure");
    expect(v[64] == 1050) catch @panic("test failure");
    expect(v[65] == 1051) catch @panic("test failure");
    expect(v[66] == 1052) catch @panic("test failure");
    expect(v[67] == 1053) catch @panic("test failure");
    expect(v[68] == 1054) catch @panic("test failure");
    expect(v[69] == 1055) catch @panic("test failure");
    expect(v[70] == 1056) catch @panic("test failure");
    expect(v[71] == 1057) catch @panic("test failure");
    expect(v[72] == 1058) catch @panic("test failure");
    expect(v[73] == 1059) catch @panic("test failure");
    expect(v[74] == 1060) catch @panic("test failure");
    expect(v[75] == 1061) catch @panic("test failure");
    expect(v[76] == 1062) catch @panic("test failure");
    expect(v[77] == 1063) catch @panic("test failure");
    expect(v[78] == 1064) catch @panic("test failure");
    expect(v[79] == 1065) catch @panic("test failure");
    expect(v[80] == 1066) catch @panic("test failure");
    expect(v[81] == 1067) catch @panic("test failure");
    expect(v[82] == 1068) catch @panic("test failure");
    expect(v[83] == 1069) catch @panic("test failure");
    expect(v[84] == 1070) catch @panic("test failure");
    expect(v[85] == 1071) catch @panic("test failure");
    expect(v[86] == 1072) catch @panic("test failure");
    expect(v[87] == 1073) catch @panic("test failure");
    expect(v[88] == 1074) catch @panic("test failure");
    expect(v[89] == 1075) catch @panic("test failure");
    expect(v[90] == 1076) catch @panic("test failure");
    expect(v[91] == 1077) catch @panic("test failure");
    expect(v[92] == 1078) catch @panic("test failure");
    expect(v[93] == 1079) catch @panic("test failure");
    expect(v[94] == 1080) catch @panic("test failure");
    expect(v[95] == 1081) catch @panic("test failure");
    expect(i == 96) catch @panic("test failure");
}

extern fn c_ret_vector_96_u16() @Vector(96, u16);
extern fn c_vector_96_u16(@Vector(96, u16), usize) void;
extern fn c_test_vector_96_u16() void;

test "@Vector(96, u16)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_96_u16();
    try expect(v[0] == 1082);
    try expect(v[1] == 1083);
    try expect(v[2] == 1084);
    try expect(v[3] == 1085);
    try expect(v[4] == 1086);
    try expect(v[5] == 1087);
    try expect(v[6] == 1088);
    try expect(v[7] == 1089);
    try expect(v[8] == 1090);
    try expect(v[9] == 1091);
    try expect(v[10] == 1092);
    try expect(v[11] == 1093);
    try expect(v[12] == 1094);
    try expect(v[13] == 1095);
    try expect(v[14] == 1096);
    try expect(v[15] == 1097);
    try expect(v[16] == 1098);
    try expect(v[17] == 1099);
    try expect(v[18] == 1100);
    try expect(v[19] == 1101);
    try expect(v[20] == 1102);
    try expect(v[21] == 1103);
    try expect(v[22] == 1104);
    try expect(v[23] == 1105);
    try expect(v[24] == 1106);
    try expect(v[25] == 1107);
    try expect(v[26] == 1108);
    try expect(v[27] == 1109);
    try expect(v[28] == 1110);
    try expect(v[29] == 1111);
    try expect(v[30] == 1112);
    try expect(v[31] == 1113);
    try expect(v[32] == 1114);
    try expect(v[33] == 1115);
    try expect(v[34] == 1116);
    try expect(v[35] == 1117);
    try expect(v[36] == 1118);
    try expect(v[37] == 1119);
    try expect(v[38] == 1120);
    try expect(v[39] == 1121);
    try expect(v[40] == 1122);
    try expect(v[41] == 1123);
    try expect(v[42] == 1124);
    try expect(v[43] == 1125);
    try expect(v[44] == 1126);
    try expect(v[45] == 1127);
    try expect(v[46] == 1128);
    try expect(v[47] == 1129);
    try expect(v[48] == 1130);
    try expect(v[49] == 1131);
    try expect(v[50] == 1132);
    try expect(v[51] == 1133);
    try expect(v[52] == 1134);
    try expect(v[53] == 1135);
    try expect(v[54] == 1136);
    try expect(v[55] == 1137);
    try expect(v[56] == 1138);
    try expect(v[57] == 1139);
    try expect(v[58] == 1140);
    try expect(v[59] == 1141);
    try expect(v[60] == 1142);
    try expect(v[61] == 1143);
    try expect(v[62] == 1144);
    try expect(v[63] == 1145);
    try expect(v[64] == 1146);
    try expect(v[65] == 1147);
    try expect(v[66] == 1148);
    try expect(v[67] == 1149);
    try expect(v[68] == 1150);
    try expect(v[69] == 1151);
    try expect(v[70] == 1152);
    try expect(v[71] == 1153);
    try expect(v[72] == 1154);
    try expect(v[73] == 1155);
    try expect(v[74] == 1156);
    try expect(v[75] == 1157);
    try expect(v[76] == 1158);
    try expect(v[77] == 1159);
    try expect(v[78] == 1160);
    try expect(v[79] == 1161);
    try expect(v[80] == 1162);
    try expect(v[81] == 1163);
    try expect(v[82] == 1164);
    try expect(v[83] == 1165);
    try expect(v[84] == 1166);
    try expect(v[85] == 1167);
    try expect(v[86] == 1168);
    try expect(v[87] == 1169);
    try expect(v[88] == 1170);
    try expect(v[89] == 1171);
    try expect(v[90] == 1172);
    try expect(v[91] == 1173);
    try expect(v[92] == 1174);
    try expect(v[93] == 1175);
    try expect(v[94] == 1176);
    try expect(v[95] == 1177);
    c_vector_96_u16(.{
        1178, 1179, 1180, 1181, 1182, 1183, 1184, 1185, 1186, 1187, 1188, 1189, 1190, 1191, 1192, 1193,
        1194, 1195, 1196, 1197, 1198, 1199, 1200, 1201, 1202, 1203, 1204, 1205, 1206, 1207, 1208, 1209,
        1210, 1211, 1212, 1213, 1214, 1215, 1216, 1217, 1218, 1219, 1220, 1221, 1222, 1223, 1224, 1225,
        1226, 1227, 1228, 1229, 1230, 1231, 1232, 1233, 1234, 1235, 1236, 1237, 1238, 1239, 1240, 1241,
        1242, 1243, 1244, 1245, 1246, 1247, 1248, 1249, 1250, 1251, 1252, 1253, 1254, 1255, 1256, 1257,
        1258, 1259, 1260, 1261, 1262, 1263, 1264, 1265, 1266, 1267, 1268, 1269, 1270, 1271, 1272, 1273,
    }, 96);
    c_test_vector_96_u16();
}

export fn zig_ret_vector_128_u16() @Vector(128, u16) {
    return .{
        1274, 1275, 1276, 1277, 1278, 1279, 1280, 1281, 1282, 1283, 1284, 1285, 1286, 1287, 1288, 1289,
        1290, 1291, 1292, 1293, 1294, 1295, 1296, 1297, 1298, 1299, 1300, 1301, 1302, 1303, 1304, 1305,
        1306, 1307, 1308, 1309, 1310, 1311, 1312, 1313, 1314, 1315, 1316, 1317, 1318, 1319, 1320, 1321,
        1322, 1323, 1324, 1325, 1326, 1327, 1328, 1329, 1330, 1331, 1332, 1333, 1334, 1335, 1336, 1337,
        1338, 1339, 1340, 1341, 1342, 1343, 1344, 1345, 1346, 1347, 1348, 1349, 1350, 1351, 1352, 1353,
        1354, 1355, 1356, 1357, 1358, 1359, 1360, 1361, 1362, 1363, 1364, 1365, 1366, 1367, 1368, 1369,
        1370, 1371, 1372, 1373, 1374, 1375, 1376, 1377, 1378, 1379, 1380, 1381, 1382, 1383, 1384, 1385,
        1386, 1387, 1388, 1389, 1390, 1391, 1392, 1393, 1394, 1395, 1396, 1397, 1398, 1399, 1400, 1401,
    };
}
export fn zig_vector_128_u16(v: @Vector(128, u16), i: usize) void {
    expect(v[0] == 1402) catch @panic("test failure");
    expect(v[1] == 1403) catch @panic("test failure");
    expect(v[2] == 1404) catch @panic("test failure");
    expect(v[3] == 1405) catch @panic("test failure");
    expect(v[4] == 1406) catch @panic("test failure");
    expect(v[5] == 1407) catch @panic("test failure");
    expect(v[6] == 1408) catch @panic("test failure");
    expect(v[7] == 1409) catch @panic("test failure");
    expect(v[8] == 1410) catch @panic("test failure");
    expect(v[9] == 1411) catch @panic("test failure");
    expect(v[10] == 1412) catch @panic("test failure");
    expect(v[11] == 1413) catch @panic("test failure");
    expect(v[12] == 1414) catch @panic("test failure");
    expect(v[13] == 1415) catch @panic("test failure");
    expect(v[14] == 1416) catch @panic("test failure");
    expect(v[15] == 1417) catch @panic("test failure");
    expect(v[16] == 1418) catch @panic("test failure");
    expect(v[17] == 1419) catch @panic("test failure");
    expect(v[18] == 1420) catch @panic("test failure");
    expect(v[19] == 1421) catch @panic("test failure");
    expect(v[20] == 1422) catch @panic("test failure");
    expect(v[21] == 1423) catch @panic("test failure");
    expect(v[22] == 1424) catch @panic("test failure");
    expect(v[23] == 1425) catch @panic("test failure");
    expect(v[24] == 1426) catch @panic("test failure");
    expect(v[25] == 1427) catch @panic("test failure");
    expect(v[26] == 1428) catch @panic("test failure");
    expect(v[27] == 1429) catch @panic("test failure");
    expect(v[28] == 1430) catch @panic("test failure");
    expect(v[29] == 1431) catch @panic("test failure");
    expect(v[30] == 1432) catch @panic("test failure");
    expect(v[31] == 1433) catch @panic("test failure");
    expect(v[32] == 1434) catch @panic("test failure");
    expect(v[33] == 1435) catch @panic("test failure");
    expect(v[34] == 1436) catch @panic("test failure");
    expect(v[35] == 1437) catch @panic("test failure");
    expect(v[36] == 1438) catch @panic("test failure");
    expect(v[37] == 1439) catch @panic("test failure");
    expect(v[38] == 1440) catch @panic("test failure");
    expect(v[39] == 1441) catch @panic("test failure");
    expect(v[40] == 1442) catch @panic("test failure");
    expect(v[41] == 1443) catch @panic("test failure");
    expect(v[42] == 1444) catch @panic("test failure");
    expect(v[43] == 1445) catch @panic("test failure");
    expect(v[44] == 1446) catch @panic("test failure");
    expect(v[45] == 1447) catch @panic("test failure");
    expect(v[46] == 1448) catch @panic("test failure");
    expect(v[47] == 1449) catch @panic("test failure");
    expect(v[48] == 1450) catch @panic("test failure");
    expect(v[49] == 1451) catch @panic("test failure");
    expect(v[50] == 1452) catch @panic("test failure");
    expect(v[51] == 1453) catch @panic("test failure");
    expect(v[52] == 1454) catch @panic("test failure");
    expect(v[53] == 1455) catch @panic("test failure");
    expect(v[54] == 1456) catch @panic("test failure");
    expect(v[55] == 1457) catch @panic("test failure");
    expect(v[56] == 1458) catch @panic("test failure");
    expect(v[57] == 1459) catch @panic("test failure");
    expect(v[58] == 1460) catch @panic("test failure");
    expect(v[59] == 1461) catch @panic("test failure");
    expect(v[60] == 1462) catch @panic("test failure");
    expect(v[61] == 1463) catch @panic("test failure");
    expect(v[62] == 1464) catch @panic("test failure");
    expect(v[63] == 1465) catch @panic("test failure");
    expect(v[64] == 1466) catch @panic("test failure");
    expect(v[65] == 1467) catch @panic("test failure");
    expect(v[66] == 1468) catch @panic("test failure");
    expect(v[67] == 1469) catch @panic("test failure");
    expect(v[68] == 1470) catch @panic("test failure");
    expect(v[69] == 1471) catch @panic("test failure");
    expect(v[70] == 1472) catch @panic("test failure");
    expect(v[71] == 1473) catch @panic("test failure");
    expect(v[72] == 1474) catch @panic("test failure");
    expect(v[73] == 1475) catch @panic("test failure");
    expect(v[74] == 1476) catch @panic("test failure");
    expect(v[75] == 1477) catch @panic("test failure");
    expect(v[76] == 1478) catch @panic("test failure");
    expect(v[77] == 1479) catch @panic("test failure");
    expect(v[78] == 1480) catch @panic("test failure");
    expect(v[79] == 1481) catch @panic("test failure");
    expect(v[80] == 1482) catch @panic("test failure");
    expect(v[81] == 1483) catch @panic("test failure");
    expect(v[82] == 1484) catch @panic("test failure");
    expect(v[83] == 1485) catch @panic("test failure");
    expect(v[84] == 1486) catch @panic("test failure");
    expect(v[85] == 1487) catch @panic("test failure");
    expect(v[86] == 1488) catch @panic("test failure");
    expect(v[87] == 1489) catch @panic("test failure");
    expect(v[88] == 1490) catch @panic("test failure");
    expect(v[89] == 1491) catch @panic("test failure");
    expect(v[90] == 1492) catch @panic("test failure");
    expect(v[91] == 1493) catch @panic("test failure");
    expect(v[92] == 1494) catch @panic("test failure");
    expect(v[93] == 1495) catch @panic("test failure");
    expect(v[94] == 1496) catch @panic("test failure");
    expect(v[95] == 1497) catch @panic("test failure");
    expect(v[96] == 1498) catch @panic("test failure");
    expect(v[97] == 1499) catch @panic("test failure");
    expect(v[98] == 1500) catch @panic("test failure");
    expect(v[99] == 1501) catch @panic("test failure");
    expect(v[100] == 1502) catch @panic("test failure");
    expect(v[101] == 1503) catch @panic("test failure");
    expect(v[102] == 1504) catch @panic("test failure");
    expect(v[103] == 1505) catch @panic("test failure");
    expect(v[104] == 1506) catch @panic("test failure");
    expect(v[105] == 1507) catch @panic("test failure");
    expect(v[106] == 1508) catch @panic("test failure");
    expect(v[107] == 1509) catch @panic("test failure");
    expect(v[108] == 1510) catch @panic("test failure");
    expect(v[109] == 1511) catch @panic("test failure");
    expect(v[110] == 1512) catch @panic("test failure");
    expect(v[111] == 1513) catch @panic("test failure");
    expect(v[112] == 1514) catch @panic("test failure");
    expect(v[113] == 1515) catch @panic("test failure");
    expect(v[114] == 1516) catch @panic("test failure");
    expect(v[115] == 1517) catch @panic("test failure");
    expect(v[116] == 1518) catch @panic("test failure");
    expect(v[117] == 1519) catch @panic("test failure");
    expect(v[118] == 1520) catch @panic("test failure");
    expect(v[119] == 1521) catch @panic("test failure");
    expect(v[120] == 1522) catch @panic("test failure");
    expect(v[121] == 1523) catch @panic("test failure");
    expect(v[122] == 1524) catch @panic("test failure");
    expect(v[123] == 1525) catch @panic("test failure");
    expect(v[124] == 1526) catch @panic("test failure");
    expect(v[125] == 1527) catch @panic("test failure");
    expect(v[126] == 1528) catch @panic("test failure");
    expect(v[127] == 1529) catch @panic("test failure");
    expect(i == 128) catch @panic("test failure");
}

extern fn c_ret_vector_128_u16() @Vector(128, u16);
extern fn c_vector_128_u16(@Vector(128, u16), usize) void;
extern fn c_test_vector_128_u16() void;

test "@Vector(128, u16)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_128_u16();
    try expect(v[0] == 1530);
    try expect(v[1] == 1531);
    try expect(v[2] == 1532);
    try expect(v[3] == 1533);
    try expect(v[4] == 1534);
    try expect(v[5] == 1535);
    try expect(v[6] == 1536);
    try expect(v[7] == 1537);
    try expect(v[8] == 1538);
    try expect(v[9] == 1539);
    try expect(v[10] == 1540);
    try expect(v[11] == 1541);
    try expect(v[12] == 1542);
    try expect(v[13] == 1543);
    try expect(v[14] == 1544);
    try expect(v[15] == 1545);
    try expect(v[16] == 1546);
    try expect(v[17] == 1547);
    try expect(v[18] == 1548);
    try expect(v[19] == 1549);
    try expect(v[20] == 1550);
    try expect(v[21] == 1551);
    try expect(v[22] == 1552);
    try expect(v[23] == 1553);
    try expect(v[24] == 1554);
    try expect(v[25] == 1555);
    try expect(v[26] == 1556);
    try expect(v[27] == 1557);
    try expect(v[28] == 1558);
    try expect(v[29] == 1559);
    try expect(v[30] == 1560);
    try expect(v[31] == 1561);
    try expect(v[32] == 1562);
    try expect(v[33] == 1563);
    try expect(v[34] == 1564);
    try expect(v[35] == 1565);
    try expect(v[36] == 1566);
    try expect(v[37] == 1567);
    try expect(v[38] == 1568);
    try expect(v[39] == 1569);
    try expect(v[40] == 1570);
    try expect(v[41] == 1571);
    try expect(v[42] == 1572);
    try expect(v[43] == 1573);
    try expect(v[44] == 1574);
    try expect(v[45] == 1575);
    try expect(v[46] == 1576);
    try expect(v[47] == 1577);
    try expect(v[48] == 1578);
    try expect(v[49] == 1579);
    try expect(v[50] == 1580);
    try expect(v[51] == 1581);
    try expect(v[52] == 1582);
    try expect(v[53] == 1583);
    try expect(v[54] == 1584);
    try expect(v[55] == 1585);
    try expect(v[56] == 1586);
    try expect(v[57] == 1587);
    try expect(v[58] == 1588);
    try expect(v[59] == 1589);
    try expect(v[60] == 1590);
    try expect(v[61] == 1591);
    try expect(v[62] == 1592);
    try expect(v[63] == 1593);
    try expect(v[64] == 1594);
    try expect(v[65] == 1595);
    try expect(v[66] == 1596);
    try expect(v[67] == 1597);
    try expect(v[68] == 1598);
    try expect(v[69] == 1599);
    try expect(v[70] == 1600);
    try expect(v[71] == 1601);
    try expect(v[72] == 1602);
    try expect(v[73] == 1603);
    try expect(v[74] == 1604);
    try expect(v[75] == 1605);
    try expect(v[76] == 1606);
    try expect(v[77] == 1607);
    try expect(v[78] == 1608);
    try expect(v[79] == 1609);
    try expect(v[80] == 1610);
    try expect(v[81] == 1611);
    try expect(v[82] == 1612);
    try expect(v[83] == 1613);
    try expect(v[84] == 1614);
    try expect(v[85] == 1615);
    try expect(v[86] == 1616);
    try expect(v[87] == 1617);
    try expect(v[88] == 1618);
    try expect(v[89] == 1619);
    try expect(v[90] == 1620);
    try expect(v[91] == 1621);
    try expect(v[92] == 1622);
    try expect(v[93] == 1623);
    try expect(v[94] == 1624);
    try expect(v[95] == 1625);
    try expect(v[96] == 1626);
    try expect(v[97] == 1627);
    try expect(v[98] == 1628);
    try expect(v[99] == 1629);
    try expect(v[100] == 1630);
    try expect(v[101] == 1631);
    try expect(v[102] == 1632);
    try expect(v[103] == 1633);
    try expect(v[104] == 1634);
    try expect(v[105] == 1635);
    try expect(v[106] == 1636);
    try expect(v[107] == 1637);
    try expect(v[108] == 1638);
    try expect(v[109] == 1639);
    try expect(v[110] == 1640);
    try expect(v[111] == 1641);
    try expect(v[112] == 1642);
    try expect(v[113] == 1643);
    try expect(v[114] == 1644);
    try expect(v[115] == 1645);
    try expect(v[116] == 1646);
    try expect(v[117] == 1647);
    try expect(v[118] == 1648);
    try expect(v[119] == 1649);
    try expect(v[120] == 1650);
    try expect(v[121] == 1651);
    try expect(v[122] == 1652);
    try expect(v[123] == 1653);
    try expect(v[124] == 1654);
    try expect(v[125] == 1655);
    try expect(v[126] == 1656);
    try expect(v[127] == 1657);
    c_vector_128_u16(.{
        1658, 1659, 1660, 1661, 1662, 1663, 1664, 1665, 1666, 1667, 1668, 1669, 1670, 1671, 1672, 1673,
        1674, 1675, 1676, 1677, 1678, 1679, 1680, 1681, 1682, 1683, 1684, 1685, 1686, 1687, 1688, 1689,
        1690, 1691, 1692, 1693, 1694, 1695, 1696, 1697, 1698, 1699, 1700, 1701, 1702, 1703, 1704, 1705,
        1706, 1707, 1708, 1709, 1710, 1711, 1712, 1713, 1714, 1715, 1716, 1717, 1718, 1719, 1720, 1721,
        1722, 1723, 1724, 1725, 1726, 1727, 1728, 1729, 1730, 1731, 1732, 1733, 1734, 1735, 1736, 1737,
        1738, 1739, 1740, 1741, 1742, 1743, 1744, 1745, 1746, 1747, 1748, 1749, 1750, 1751, 1752, 1753,
        1754, 1755, 1756, 1757, 1758, 1759, 1760, 1761, 1762, 1763, 1764, 1765, 1766, 1767, 1768, 1769,
        1770, 1771, 1772, 1773, 1774, 1775, 1776, 1777, 1778, 1779, 1780, 1781, 1782, 1783, 1784, 1785,
    }, 128);
    c_test_vector_128_u16();
}

export fn zig_ret_vector_192_u16() @Vector(192, u16) {
    return .{
        1786, 1787, 1788, 1789, 1790, 1791, 1792, 1793, 1794, 1795, 1796, 1797, 1798, 1799, 1800, 1801,
        1802, 1803, 1804, 1805, 1806, 1807, 1808, 1809, 1810, 1811, 1812, 1813, 1814, 1815, 1816, 1817,
        1818, 1819, 1820, 1821, 1822, 1823, 1824, 1825, 1826, 1827, 1828, 1829, 1830, 1831, 1832, 1833,
        1834, 1835, 1836, 1837, 1838, 1839, 1840, 1841, 1842, 1843, 1844, 1845, 1846, 1847, 1848, 1849,
        1850, 1851, 1852, 1853, 1854, 1855, 1856, 1857, 1858, 1859, 1860, 1861, 1862, 1863, 1864, 1865,
        1866, 1867, 1868, 1869, 1870, 1871, 1872, 1873, 1874, 1875, 1876, 1877, 1878, 1879, 1880, 1881,
        1882, 1883, 1884, 1885, 1886, 1887, 1888, 1889, 1890, 1891, 1892, 1893, 1894, 1895, 1896, 1897,
        1898, 1899, 1900, 1901, 1902, 1903, 1904, 1905, 1906, 1907, 1908, 1909, 1910, 1911, 1912, 1913,
        1914, 1915, 1916, 1917, 1918, 1919, 1920, 1921, 1922, 1923, 1924, 1925, 1926, 1927, 1928, 1929,
        1930, 1931, 1932, 1933, 1934, 1935, 1936, 1937, 1938, 1939, 1940, 1941, 1942, 1943, 1944, 1945,
        1946, 1947, 1948, 1949, 1950, 1951, 1952, 1953, 1954, 1955, 1956, 1957, 1958, 1959, 1960, 1961,
        1962, 1963, 1964, 1965, 1966, 1967, 1968, 1969, 1970, 1971, 1972, 1973, 1974, 1975, 1976, 1977,
    };
}
export fn zig_vector_192_u16(v: @Vector(192, u16), i: usize) void {
    expect(v[0] == 1978) catch @panic("test failure");
    expect(v[1] == 1979) catch @panic("test failure");
    expect(v[2] == 1980) catch @panic("test failure");
    expect(v[3] == 1981) catch @panic("test failure");
    expect(v[4] == 1982) catch @panic("test failure");
    expect(v[5] == 1983) catch @panic("test failure");
    expect(v[6] == 1984) catch @panic("test failure");
    expect(v[7] == 1985) catch @panic("test failure");
    expect(v[8] == 1986) catch @panic("test failure");
    expect(v[9] == 1987) catch @panic("test failure");
    expect(v[10] == 1988) catch @panic("test failure");
    expect(v[11] == 1989) catch @panic("test failure");
    expect(v[12] == 1990) catch @panic("test failure");
    expect(v[13] == 1991) catch @panic("test failure");
    expect(v[14] == 1992) catch @panic("test failure");
    expect(v[15] == 1993) catch @panic("test failure");
    expect(v[16] == 1994) catch @panic("test failure");
    expect(v[17] == 1995) catch @panic("test failure");
    expect(v[18] == 1996) catch @panic("test failure");
    expect(v[19] == 1997) catch @panic("test failure");
    expect(v[20] == 1998) catch @panic("test failure");
    expect(v[21] == 1999) catch @panic("test failure");
    expect(v[22] == 2000) catch @panic("test failure");
    expect(v[23] == 2001) catch @panic("test failure");
    expect(v[24] == 2002) catch @panic("test failure");
    expect(v[25] == 2003) catch @panic("test failure");
    expect(v[26] == 2004) catch @panic("test failure");
    expect(v[27] == 2005) catch @panic("test failure");
    expect(v[28] == 2006) catch @panic("test failure");
    expect(v[29] == 2007) catch @panic("test failure");
    expect(v[30] == 2008) catch @panic("test failure");
    expect(v[31] == 2009) catch @panic("test failure");
    expect(v[32] == 2010) catch @panic("test failure");
    expect(v[33] == 2011) catch @panic("test failure");
    expect(v[34] == 2012) catch @panic("test failure");
    expect(v[35] == 2013) catch @panic("test failure");
    expect(v[36] == 2014) catch @panic("test failure");
    expect(v[37] == 2015) catch @panic("test failure");
    expect(v[38] == 2016) catch @panic("test failure");
    expect(v[39] == 2017) catch @panic("test failure");
    expect(v[40] == 2018) catch @panic("test failure");
    expect(v[41] == 2019) catch @panic("test failure");
    expect(v[42] == 2020) catch @panic("test failure");
    expect(v[43] == 2021) catch @panic("test failure");
    expect(v[44] == 2022) catch @panic("test failure");
    expect(v[45] == 2023) catch @panic("test failure");
    expect(v[46] == 2024) catch @panic("test failure");
    expect(v[47] == 2025) catch @panic("test failure");
    expect(v[48] == 2026) catch @panic("test failure");
    expect(v[49] == 2027) catch @panic("test failure");
    expect(v[50] == 2028) catch @panic("test failure");
    expect(v[51] == 2029) catch @panic("test failure");
    expect(v[52] == 2030) catch @panic("test failure");
    expect(v[53] == 2031) catch @panic("test failure");
    expect(v[54] == 2032) catch @panic("test failure");
    expect(v[55] == 2033) catch @panic("test failure");
    expect(v[56] == 2034) catch @panic("test failure");
    expect(v[57] == 2035) catch @panic("test failure");
    expect(v[58] == 2036) catch @panic("test failure");
    expect(v[59] == 2037) catch @panic("test failure");
    expect(v[60] == 2038) catch @panic("test failure");
    expect(v[61] == 2039) catch @panic("test failure");
    expect(v[62] == 2040) catch @panic("test failure");
    expect(v[63] == 2041) catch @panic("test failure");
    expect(v[64] == 2042) catch @panic("test failure");
    expect(v[65] == 2043) catch @panic("test failure");
    expect(v[66] == 2044) catch @panic("test failure");
    expect(v[67] == 2045) catch @panic("test failure");
    expect(v[68] == 2046) catch @panic("test failure");
    expect(v[69] == 2047) catch @panic("test failure");
    expect(v[70] == 2048) catch @panic("test failure");
    expect(v[71] == 2049) catch @panic("test failure");
    expect(v[72] == 2050) catch @panic("test failure");
    expect(v[73] == 2051) catch @panic("test failure");
    expect(v[74] == 2052) catch @panic("test failure");
    expect(v[75] == 2053) catch @panic("test failure");
    expect(v[76] == 2054) catch @panic("test failure");
    expect(v[77] == 2055) catch @panic("test failure");
    expect(v[78] == 2056) catch @panic("test failure");
    expect(v[79] == 2057) catch @panic("test failure");
    expect(v[80] == 2058) catch @panic("test failure");
    expect(v[81] == 2059) catch @panic("test failure");
    expect(v[82] == 2060) catch @panic("test failure");
    expect(v[83] == 2061) catch @panic("test failure");
    expect(v[84] == 2062) catch @panic("test failure");
    expect(v[85] == 2063) catch @panic("test failure");
    expect(v[86] == 2064) catch @panic("test failure");
    expect(v[87] == 2065) catch @panic("test failure");
    expect(v[88] == 2066) catch @panic("test failure");
    expect(v[89] == 2067) catch @panic("test failure");
    expect(v[90] == 2068) catch @panic("test failure");
    expect(v[91] == 2069) catch @panic("test failure");
    expect(v[92] == 2070) catch @panic("test failure");
    expect(v[93] == 2071) catch @panic("test failure");
    expect(v[94] == 2072) catch @panic("test failure");
    expect(v[95] == 2073) catch @panic("test failure");
    expect(v[96] == 2074) catch @panic("test failure");
    expect(v[97] == 2075) catch @panic("test failure");
    expect(v[98] == 2076) catch @panic("test failure");
    expect(v[99] == 2077) catch @panic("test failure");
    expect(v[100] == 2078) catch @panic("test failure");
    expect(v[101] == 2079) catch @panic("test failure");
    expect(v[102] == 2080) catch @panic("test failure");
    expect(v[103] == 2081) catch @panic("test failure");
    expect(v[104] == 2082) catch @panic("test failure");
    expect(v[105] == 2083) catch @panic("test failure");
    expect(v[106] == 2084) catch @panic("test failure");
    expect(v[107] == 2085) catch @panic("test failure");
    expect(v[108] == 2086) catch @panic("test failure");
    expect(v[109] == 2087) catch @panic("test failure");
    expect(v[110] == 2088) catch @panic("test failure");
    expect(v[111] == 2089) catch @panic("test failure");
    expect(v[112] == 2090) catch @panic("test failure");
    expect(v[113] == 2091) catch @panic("test failure");
    expect(v[114] == 2092) catch @panic("test failure");
    expect(v[115] == 2093) catch @panic("test failure");
    expect(v[116] == 2094) catch @panic("test failure");
    expect(v[117] == 2095) catch @panic("test failure");
    expect(v[118] == 2096) catch @panic("test failure");
    expect(v[119] == 2097) catch @panic("test failure");
    expect(v[120] == 2098) catch @panic("test failure");
    expect(v[121] == 2099) catch @panic("test failure");
    expect(v[122] == 2100) catch @panic("test failure");
    expect(v[123] == 2101) catch @panic("test failure");
    expect(v[124] == 2102) catch @panic("test failure");
    expect(v[125] == 2103) catch @panic("test failure");
    expect(v[126] == 2104) catch @panic("test failure");
    expect(v[127] == 2105) catch @panic("test failure");
    expect(v[128] == 2106) catch @panic("test failure");
    expect(v[129] == 2107) catch @panic("test failure");
    expect(v[130] == 2108) catch @panic("test failure");
    expect(v[131] == 2109) catch @panic("test failure");
    expect(v[132] == 2110) catch @panic("test failure");
    expect(v[133] == 2111) catch @panic("test failure");
    expect(v[134] == 2112) catch @panic("test failure");
    expect(v[135] == 2113) catch @panic("test failure");
    expect(v[136] == 2114) catch @panic("test failure");
    expect(v[137] == 2115) catch @panic("test failure");
    expect(v[138] == 2116) catch @panic("test failure");
    expect(v[139] == 2117) catch @panic("test failure");
    expect(v[140] == 2118) catch @panic("test failure");
    expect(v[141] == 2119) catch @panic("test failure");
    expect(v[142] == 2120) catch @panic("test failure");
    expect(v[143] == 2121) catch @panic("test failure");
    expect(v[144] == 2122) catch @panic("test failure");
    expect(v[145] == 2123) catch @panic("test failure");
    expect(v[146] == 2124) catch @panic("test failure");
    expect(v[147] == 2125) catch @panic("test failure");
    expect(v[148] == 2126) catch @panic("test failure");
    expect(v[149] == 2127) catch @panic("test failure");
    expect(v[150] == 2128) catch @panic("test failure");
    expect(v[151] == 2129) catch @panic("test failure");
    expect(v[152] == 2130) catch @panic("test failure");
    expect(v[153] == 2131) catch @panic("test failure");
    expect(v[154] == 2132) catch @panic("test failure");
    expect(v[155] == 2133) catch @panic("test failure");
    expect(v[156] == 2134) catch @panic("test failure");
    expect(v[157] == 2135) catch @panic("test failure");
    expect(v[158] == 2136) catch @panic("test failure");
    expect(v[159] == 2137) catch @panic("test failure");
    expect(v[160] == 2138) catch @panic("test failure");
    expect(v[161] == 2139) catch @panic("test failure");
    expect(v[162] == 2140) catch @panic("test failure");
    expect(v[163] == 2141) catch @panic("test failure");
    expect(v[164] == 2142) catch @panic("test failure");
    expect(v[165] == 2143) catch @panic("test failure");
    expect(v[166] == 2144) catch @panic("test failure");
    expect(v[167] == 2145) catch @panic("test failure");
    expect(v[168] == 2146) catch @panic("test failure");
    expect(v[169] == 2147) catch @panic("test failure");
    expect(v[170] == 2148) catch @panic("test failure");
    expect(v[171] == 2149) catch @panic("test failure");
    expect(v[172] == 2150) catch @panic("test failure");
    expect(v[173] == 2151) catch @panic("test failure");
    expect(v[174] == 2152) catch @panic("test failure");
    expect(v[175] == 2153) catch @panic("test failure");
    expect(v[176] == 2154) catch @panic("test failure");
    expect(v[177] == 2155) catch @panic("test failure");
    expect(v[178] == 2156) catch @panic("test failure");
    expect(v[179] == 2157) catch @panic("test failure");
    expect(v[180] == 2158) catch @panic("test failure");
    expect(v[181] == 2159) catch @panic("test failure");
    expect(v[182] == 2160) catch @panic("test failure");
    expect(v[183] == 2161) catch @panic("test failure");
    expect(v[184] == 2162) catch @panic("test failure");
    expect(v[185] == 2163) catch @panic("test failure");
    expect(v[186] == 2164) catch @panic("test failure");
    expect(v[187] == 2165) catch @panic("test failure");
    expect(v[188] == 2166) catch @panic("test failure");
    expect(v[189] == 2167) catch @panic("test failure");
    expect(v[190] == 2168) catch @panic("test failure");
    expect(v[191] == 2169) catch @panic("test failure");
    expect(i == 192) catch @panic("test failure");
}

extern fn c_ret_vector_192_u16() @Vector(192, u16);
extern fn c_vector_192_u16(@Vector(192, u16), usize) void;
extern fn c_test_vector_192_u16() void;

test "@Vector(192, u16)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_192_u16();
    try expect(v[0] == 2170);
    try expect(v[1] == 2171);
    try expect(v[2] == 2172);
    try expect(v[3] == 2173);
    try expect(v[4] == 2174);
    try expect(v[5] == 2175);
    try expect(v[6] == 2176);
    try expect(v[7] == 2177);
    try expect(v[8] == 2178);
    try expect(v[9] == 2179);
    try expect(v[10] == 2180);
    try expect(v[11] == 2181);
    try expect(v[12] == 2182);
    try expect(v[13] == 2183);
    try expect(v[14] == 2184);
    try expect(v[15] == 2185);
    try expect(v[16] == 2186);
    try expect(v[17] == 2187);
    try expect(v[18] == 2188);
    try expect(v[19] == 2189);
    try expect(v[20] == 2190);
    try expect(v[21] == 2191);
    try expect(v[22] == 2192);
    try expect(v[23] == 2193);
    try expect(v[24] == 2194);
    try expect(v[25] == 2195);
    try expect(v[26] == 2196);
    try expect(v[27] == 2197);
    try expect(v[28] == 2198);
    try expect(v[29] == 2199);
    try expect(v[30] == 2200);
    try expect(v[31] == 2201);
    try expect(v[32] == 2202);
    try expect(v[33] == 2203);
    try expect(v[34] == 2204);
    try expect(v[35] == 2205);
    try expect(v[36] == 2206);
    try expect(v[37] == 2207);
    try expect(v[38] == 2208);
    try expect(v[39] == 2209);
    try expect(v[40] == 2210);
    try expect(v[41] == 2211);
    try expect(v[42] == 2212);
    try expect(v[43] == 2213);
    try expect(v[44] == 2214);
    try expect(v[45] == 2215);
    try expect(v[46] == 2216);
    try expect(v[47] == 2217);
    try expect(v[48] == 2218);
    try expect(v[49] == 2219);
    try expect(v[50] == 2220);
    try expect(v[51] == 2221);
    try expect(v[52] == 2222);
    try expect(v[53] == 2223);
    try expect(v[54] == 2224);
    try expect(v[55] == 2225);
    try expect(v[56] == 2226);
    try expect(v[57] == 2227);
    try expect(v[58] == 2228);
    try expect(v[59] == 2229);
    try expect(v[60] == 2230);
    try expect(v[61] == 2231);
    try expect(v[62] == 2232);
    try expect(v[63] == 2233);
    try expect(v[64] == 2234);
    try expect(v[65] == 2235);
    try expect(v[66] == 2236);
    try expect(v[67] == 2237);
    try expect(v[68] == 2238);
    try expect(v[69] == 2239);
    try expect(v[70] == 2240);
    try expect(v[71] == 2241);
    try expect(v[72] == 2242);
    try expect(v[73] == 2243);
    try expect(v[74] == 2244);
    try expect(v[75] == 2245);
    try expect(v[76] == 2246);
    try expect(v[77] == 2247);
    try expect(v[78] == 2248);
    try expect(v[79] == 2249);
    try expect(v[80] == 2250);
    try expect(v[81] == 2251);
    try expect(v[82] == 2252);
    try expect(v[83] == 2253);
    try expect(v[84] == 2254);
    try expect(v[85] == 2255);
    try expect(v[86] == 2256);
    try expect(v[87] == 2257);
    try expect(v[88] == 2258);
    try expect(v[89] == 2259);
    try expect(v[90] == 2260);
    try expect(v[91] == 2261);
    try expect(v[92] == 2262);
    try expect(v[93] == 2263);
    try expect(v[94] == 2264);
    try expect(v[95] == 2265);
    try expect(v[96] == 2266);
    try expect(v[97] == 2267);
    try expect(v[98] == 2268);
    try expect(v[99] == 2269);
    try expect(v[100] == 2270);
    try expect(v[101] == 2271);
    try expect(v[102] == 2272);
    try expect(v[103] == 2273);
    try expect(v[104] == 2274);
    try expect(v[105] == 2275);
    try expect(v[106] == 2276);
    try expect(v[107] == 2277);
    try expect(v[108] == 2278);
    try expect(v[109] == 2279);
    try expect(v[110] == 2280);
    try expect(v[111] == 2281);
    try expect(v[112] == 2282);
    try expect(v[113] == 2283);
    try expect(v[114] == 2284);
    try expect(v[115] == 2285);
    try expect(v[116] == 2286);
    try expect(v[117] == 2287);
    try expect(v[118] == 2288);
    try expect(v[119] == 2289);
    try expect(v[120] == 2290);
    try expect(v[121] == 2291);
    try expect(v[122] == 2292);
    try expect(v[123] == 2293);
    try expect(v[124] == 2294);
    try expect(v[125] == 2295);
    try expect(v[126] == 2296);
    try expect(v[127] == 2297);
    try expect(v[128] == 2298);
    try expect(v[129] == 2299);
    try expect(v[130] == 2300);
    try expect(v[131] == 2301);
    try expect(v[132] == 2302);
    try expect(v[133] == 2303);
    try expect(v[134] == 2304);
    try expect(v[135] == 2305);
    try expect(v[136] == 2306);
    try expect(v[137] == 2307);
    try expect(v[138] == 2308);
    try expect(v[139] == 2309);
    try expect(v[140] == 2310);
    try expect(v[141] == 2311);
    try expect(v[142] == 2312);
    try expect(v[143] == 2313);
    try expect(v[144] == 2314);
    try expect(v[145] == 2315);
    try expect(v[146] == 2316);
    try expect(v[147] == 2317);
    try expect(v[148] == 2318);
    try expect(v[149] == 2319);
    try expect(v[150] == 2320);
    try expect(v[151] == 2321);
    try expect(v[152] == 2322);
    try expect(v[153] == 2323);
    try expect(v[154] == 2324);
    try expect(v[155] == 2325);
    try expect(v[156] == 2326);
    try expect(v[157] == 2327);
    try expect(v[158] == 2328);
    try expect(v[159] == 2329);
    try expect(v[160] == 2330);
    try expect(v[161] == 2331);
    try expect(v[162] == 2332);
    try expect(v[163] == 2333);
    try expect(v[164] == 2334);
    try expect(v[165] == 2335);
    try expect(v[166] == 2336);
    try expect(v[167] == 2337);
    try expect(v[168] == 2338);
    try expect(v[169] == 2339);
    try expect(v[170] == 2340);
    try expect(v[171] == 2341);
    try expect(v[172] == 2342);
    try expect(v[173] == 2343);
    try expect(v[174] == 2344);
    try expect(v[175] == 2345);
    try expect(v[176] == 2346);
    try expect(v[177] == 2347);
    try expect(v[178] == 2348);
    try expect(v[179] == 2349);
    try expect(v[180] == 2350);
    try expect(v[181] == 2351);
    try expect(v[182] == 2352);
    try expect(v[183] == 2353);
    try expect(v[184] == 2354);
    try expect(v[185] == 2355);
    try expect(v[186] == 2356);
    try expect(v[187] == 2357);
    try expect(v[188] == 2358);
    try expect(v[189] == 2359);
    try expect(v[190] == 2360);
    try expect(v[191] == 2361);
    c_vector_192_u16(.{
        2362, 2363, 2364, 2365, 2366, 2367, 2368, 2369, 2370, 2371, 2372, 2373, 2374, 2375, 2376, 2377,
        2378, 2379, 2380, 2381, 2382, 2383, 2384, 2385, 2386, 2387, 2388, 2389, 2390, 2391, 2392, 2393,
        2394, 2395, 2396, 2397, 2398, 2399, 2400, 2401, 2402, 2403, 2404, 2405, 2406, 2407, 2408, 2409,
        2410, 2411, 2412, 2413, 2414, 2415, 2416, 2417, 2418, 2419, 2420, 2421, 2422, 2423, 2424, 2425,
        2426, 2427, 2428, 2429, 2430, 2431, 2432, 2433, 2434, 2435, 2436, 2437, 2438, 2439, 2440, 2441,
        2442, 2443, 2444, 2445, 2446, 2447, 2448, 2449, 2450, 2451, 2452, 2453, 2454, 2455, 2456, 2457,
        2458, 2459, 2460, 2461, 2462, 2463, 2464, 2465, 2466, 2467, 2468, 2469, 2470, 2471, 2472, 2473,
        2474, 2475, 2476, 2477, 2478, 2479, 2480, 2481, 2482, 2483, 2484, 2485, 2486, 2487, 2488, 2489,
        2490, 2491, 2492, 2493, 2494, 2495, 2496, 2497, 2498, 2499, 2500, 2501, 2502, 2503, 2504, 2505,
        2506, 2507, 2508, 2509, 2510, 2511, 2512, 2513, 2514, 2515, 2516, 2517, 2518, 2519, 2520, 2521,
        2522, 2523, 2524, 2525, 2526, 2527, 2528, 2529, 2530, 2531, 2532, 2533, 2534, 2535, 2536, 2537,
        2538, 2539, 2540, 2541, 2542, 2543, 2544, 2545, 2546, 2547, 2548, 2549, 2550, 2551, 2552, 2553,
    }, 192);
    c_test_vector_192_u16();
}

export fn zig_ret_vector_256_u16() @Vector(256, u16) {
    return .{
        2554, 2555, 2556, 2557, 2558, 2559, 2560, 2561, 2562, 2563, 2564, 2565, 2566, 2567, 2568, 2569,
        2570, 2571, 2572, 2573, 2574, 2575, 2576, 2577, 2578, 2579, 2580, 2581, 2582, 2583, 2584, 2585,
        2586, 2587, 2588, 2589, 2590, 2591, 2592, 2593, 2594, 2595, 2596, 2597, 2598, 2599, 2600, 2601,
        2602, 2603, 2604, 2605, 2606, 2607, 2608, 2609, 2610, 2611, 2612, 2613, 2614, 2615, 2616, 2617,
        2618, 2619, 2620, 2621, 2622, 2623, 2624, 2625, 2626, 2627, 2628, 2629, 2630, 2631, 2632, 2633,
        2634, 2635, 2636, 2637, 2638, 2639, 2640, 2641, 2642, 2643, 2644, 2645, 2646, 2647, 2648, 2649,
        2650, 2651, 2652, 2653, 2654, 2655, 2656, 2657, 2658, 2659, 2660, 2661, 2662, 2663, 2664, 2665,
        2666, 2667, 2668, 2669, 2670, 2671, 2672, 2673, 2674, 2675, 2676, 2677, 2678, 2679, 2680, 2681,
        2682, 2683, 2684, 2685, 2686, 2687, 2688, 2689, 2690, 2691, 2692, 2693, 2694, 2695, 2696, 2697,
        2698, 2699, 2700, 2701, 2702, 2703, 2704, 2705, 2706, 2707, 2708, 2709, 2710, 2711, 2712, 2713,
        2714, 2715, 2716, 2717, 2718, 2719, 2720, 2721, 2722, 2723, 2724, 2725, 2726, 2727, 2728, 2729,
        2730, 2731, 2732, 2733, 2734, 2735, 2736, 2737, 2738, 2739, 2740, 2741, 2742, 2743, 2744, 2745,
        2746, 2747, 2748, 2749, 2750, 2751, 2752, 2753, 2754, 2755, 2756, 2757, 2758, 2759, 2760, 2761,
        2762, 2763, 2764, 2765, 2766, 2767, 2768, 2769, 2770, 2771, 2772, 2773, 2774, 2775, 2776, 2777,
        2778, 2779, 2780, 2781, 2782, 2783, 2784, 2785, 2786, 2787, 2788, 2789, 2790, 2791, 2792, 2793,
        2794, 2795, 2796, 2797, 2798, 2799, 2800, 2801, 2802, 2803, 2804, 2805, 2806, 2807, 2808, 2809,
    };
}
export fn zig_vector_256_u16(v: @Vector(256, u16), i: usize) void {
    expect(v[0] == 2810) catch @panic("test failure");
    expect(v[1] == 2811) catch @panic("test failure");
    expect(v[2] == 2812) catch @panic("test failure");
    expect(v[3] == 2813) catch @panic("test failure");
    expect(v[4] == 2814) catch @panic("test failure");
    expect(v[5] == 2815) catch @panic("test failure");
    expect(v[6] == 2816) catch @panic("test failure");
    expect(v[7] == 2817) catch @panic("test failure");
    expect(v[8] == 2818) catch @panic("test failure");
    expect(v[9] == 2819) catch @panic("test failure");
    expect(v[10] == 2820) catch @panic("test failure");
    expect(v[11] == 2821) catch @panic("test failure");
    expect(v[12] == 2822) catch @panic("test failure");
    expect(v[13] == 2823) catch @panic("test failure");
    expect(v[14] == 2824) catch @panic("test failure");
    expect(v[15] == 2825) catch @panic("test failure");
    expect(v[16] == 2826) catch @panic("test failure");
    expect(v[17] == 2827) catch @panic("test failure");
    expect(v[18] == 2828) catch @panic("test failure");
    expect(v[19] == 2829) catch @panic("test failure");
    expect(v[20] == 2830) catch @panic("test failure");
    expect(v[21] == 2831) catch @panic("test failure");
    expect(v[22] == 2832) catch @panic("test failure");
    expect(v[23] == 2833) catch @panic("test failure");
    expect(v[24] == 2834) catch @panic("test failure");
    expect(v[25] == 2835) catch @panic("test failure");
    expect(v[26] == 2836) catch @panic("test failure");
    expect(v[27] == 2837) catch @panic("test failure");
    expect(v[28] == 2838) catch @panic("test failure");
    expect(v[29] == 2839) catch @panic("test failure");
    expect(v[30] == 2840) catch @panic("test failure");
    expect(v[31] == 2841) catch @panic("test failure");
    expect(v[32] == 2842) catch @panic("test failure");
    expect(v[33] == 2843) catch @panic("test failure");
    expect(v[34] == 2844) catch @panic("test failure");
    expect(v[35] == 2845) catch @panic("test failure");
    expect(v[36] == 2846) catch @panic("test failure");
    expect(v[37] == 2847) catch @panic("test failure");
    expect(v[38] == 2848) catch @panic("test failure");
    expect(v[39] == 2849) catch @panic("test failure");
    expect(v[40] == 2850) catch @panic("test failure");
    expect(v[41] == 2851) catch @panic("test failure");
    expect(v[42] == 2852) catch @panic("test failure");
    expect(v[43] == 2853) catch @panic("test failure");
    expect(v[44] == 2854) catch @panic("test failure");
    expect(v[45] == 2855) catch @panic("test failure");
    expect(v[46] == 2856) catch @panic("test failure");
    expect(v[47] == 2857) catch @panic("test failure");
    expect(v[48] == 2858) catch @panic("test failure");
    expect(v[49] == 2859) catch @panic("test failure");
    expect(v[50] == 2860) catch @panic("test failure");
    expect(v[51] == 2861) catch @panic("test failure");
    expect(v[52] == 2862) catch @panic("test failure");
    expect(v[53] == 2863) catch @panic("test failure");
    expect(v[54] == 2864) catch @panic("test failure");
    expect(v[55] == 2865) catch @panic("test failure");
    expect(v[56] == 2866) catch @panic("test failure");
    expect(v[57] == 2867) catch @panic("test failure");
    expect(v[58] == 2868) catch @panic("test failure");
    expect(v[59] == 2869) catch @panic("test failure");
    expect(v[60] == 2870) catch @panic("test failure");
    expect(v[61] == 2871) catch @panic("test failure");
    expect(v[62] == 2872) catch @panic("test failure");
    expect(v[63] == 2873) catch @panic("test failure");
    expect(v[64] == 2874) catch @panic("test failure");
    expect(v[65] == 2875) catch @panic("test failure");
    expect(v[66] == 2876) catch @panic("test failure");
    expect(v[67] == 2877) catch @panic("test failure");
    expect(v[68] == 2878) catch @panic("test failure");
    expect(v[69] == 2879) catch @panic("test failure");
    expect(v[70] == 2880) catch @panic("test failure");
    expect(v[71] == 2881) catch @panic("test failure");
    expect(v[72] == 2882) catch @panic("test failure");
    expect(v[73] == 2883) catch @panic("test failure");
    expect(v[74] == 2884) catch @panic("test failure");
    expect(v[75] == 2885) catch @panic("test failure");
    expect(v[76] == 2886) catch @panic("test failure");
    expect(v[77] == 2887) catch @panic("test failure");
    expect(v[78] == 2888) catch @panic("test failure");
    expect(v[79] == 2889) catch @panic("test failure");
    expect(v[80] == 2890) catch @panic("test failure");
    expect(v[81] == 2891) catch @panic("test failure");
    expect(v[82] == 2892) catch @panic("test failure");
    expect(v[83] == 2893) catch @panic("test failure");
    expect(v[84] == 2894) catch @panic("test failure");
    expect(v[85] == 2895) catch @panic("test failure");
    expect(v[86] == 2896) catch @panic("test failure");
    expect(v[87] == 2897) catch @panic("test failure");
    expect(v[88] == 2898) catch @panic("test failure");
    expect(v[89] == 2899) catch @panic("test failure");
    expect(v[90] == 2900) catch @panic("test failure");
    expect(v[91] == 2901) catch @panic("test failure");
    expect(v[92] == 2902) catch @panic("test failure");
    expect(v[93] == 2903) catch @panic("test failure");
    expect(v[94] == 2904) catch @panic("test failure");
    expect(v[95] == 2905) catch @panic("test failure");
    expect(v[96] == 2906) catch @panic("test failure");
    expect(v[97] == 2907) catch @panic("test failure");
    expect(v[98] == 2908) catch @panic("test failure");
    expect(v[99] == 2909) catch @panic("test failure");
    expect(v[100] == 2910) catch @panic("test failure");
    expect(v[101] == 2911) catch @panic("test failure");
    expect(v[102] == 2912) catch @panic("test failure");
    expect(v[103] == 2913) catch @panic("test failure");
    expect(v[104] == 2914) catch @panic("test failure");
    expect(v[105] == 2915) catch @panic("test failure");
    expect(v[106] == 2916) catch @panic("test failure");
    expect(v[107] == 2917) catch @panic("test failure");
    expect(v[108] == 2918) catch @panic("test failure");
    expect(v[109] == 2919) catch @panic("test failure");
    expect(v[110] == 2920) catch @panic("test failure");
    expect(v[111] == 2921) catch @panic("test failure");
    expect(v[112] == 2922) catch @panic("test failure");
    expect(v[113] == 2923) catch @panic("test failure");
    expect(v[114] == 2924) catch @panic("test failure");
    expect(v[115] == 2925) catch @panic("test failure");
    expect(v[116] == 2926) catch @panic("test failure");
    expect(v[117] == 2927) catch @panic("test failure");
    expect(v[118] == 2928) catch @panic("test failure");
    expect(v[119] == 2929) catch @panic("test failure");
    expect(v[120] == 2930) catch @panic("test failure");
    expect(v[121] == 2931) catch @panic("test failure");
    expect(v[122] == 2932) catch @panic("test failure");
    expect(v[123] == 2933) catch @panic("test failure");
    expect(v[124] == 2934) catch @panic("test failure");
    expect(v[125] == 2935) catch @panic("test failure");
    expect(v[126] == 2936) catch @panic("test failure");
    expect(v[127] == 2937) catch @panic("test failure");
    expect(v[128] == 2938) catch @panic("test failure");
    expect(v[129] == 2939) catch @panic("test failure");
    expect(v[130] == 2940) catch @panic("test failure");
    expect(v[131] == 2941) catch @panic("test failure");
    expect(v[132] == 2942) catch @panic("test failure");
    expect(v[133] == 2943) catch @panic("test failure");
    expect(v[134] == 2944) catch @panic("test failure");
    expect(v[135] == 2945) catch @panic("test failure");
    expect(v[136] == 2946) catch @panic("test failure");
    expect(v[137] == 2947) catch @panic("test failure");
    expect(v[138] == 2948) catch @panic("test failure");
    expect(v[139] == 2949) catch @panic("test failure");
    expect(v[140] == 2950) catch @panic("test failure");
    expect(v[141] == 2951) catch @panic("test failure");
    expect(v[142] == 2952) catch @panic("test failure");
    expect(v[143] == 2953) catch @panic("test failure");
    expect(v[144] == 2954) catch @panic("test failure");
    expect(v[145] == 2955) catch @panic("test failure");
    expect(v[146] == 2956) catch @panic("test failure");
    expect(v[147] == 2957) catch @panic("test failure");
    expect(v[148] == 2958) catch @panic("test failure");
    expect(v[149] == 2959) catch @panic("test failure");
    expect(v[150] == 2960) catch @panic("test failure");
    expect(v[151] == 2961) catch @panic("test failure");
    expect(v[152] == 2962) catch @panic("test failure");
    expect(v[153] == 2963) catch @panic("test failure");
    expect(v[154] == 2964) catch @panic("test failure");
    expect(v[155] == 2965) catch @panic("test failure");
    expect(v[156] == 2966) catch @panic("test failure");
    expect(v[157] == 2967) catch @panic("test failure");
    expect(v[158] == 2968) catch @panic("test failure");
    expect(v[159] == 2969) catch @panic("test failure");
    expect(v[160] == 2970) catch @panic("test failure");
    expect(v[161] == 2971) catch @panic("test failure");
    expect(v[162] == 2972) catch @panic("test failure");
    expect(v[163] == 2973) catch @panic("test failure");
    expect(v[164] == 2974) catch @panic("test failure");
    expect(v[165] == 2975) catch @panic("test failure");
    expect(v[166] == 2976) catch @panic("test failure");
    expect(v[167] == 2977) catch @panic("test failure");
    expect(v[168] == 2978) catch @panic("test failure");
    expect(v[169] == 2979) catch @panic("test failure");
    expect(v[170] == 2980) catch @panic("test failure");
    expect(v[171] == 2981) catch @panic("test failure");
    expect(v[172] == 2982) catch @panic("test failure");
    expect(v[173] == 2983) catch @panic("test failure");
    expect(v[174] == 2984) catch @panic("test failure");
    expect(v[175] == 2985) catch @panic("test failure");
    expect(v[176] == 2986) catch @panic("test failure");
    expect(v[177] == 2987) catch @panic("test failure");
    expect(v[178] == 2988) catch @panic("test failure");
    expect(v[179] == 2989) catch @panic("test failure");
    expect(v[180] == 2990) catch @panic("test failure");
    expect(v[181] == 2991) catch @panic("test failure");
    expect(v[182] == 2992) catch @panic("test failure");
    expect(v[183] == 2993) catch @panic("test failure");
    expect(v[184] == 2994) catch @panic("test failure");
    expect(v[185] == 2995) catch @panic("test failure");
    expect(v[186] == 2996) catch @panic("test failure");
    expect(v[187] == 2997) catch @panic("test failure");
    expect(v[188] == 2998) catch @panic("test failure");
    expect(v[189] == 2999) catch @panic("test failure");
    expect(v[190] == 3000) catch @panic("test failure");
    expect(v[191] == 3001) catch @panic("test failure");
    expect(v[192] == 3002) catch @panic("test failure");
    expect(v[193] == 3003) catch @panic("test failure");
    expect(v[194] == 3004) catch @panic("test failure");
    expect(v[195] == 3005) catch @panic("test failure");
    expect(v[196] == 3006) catch @panic("test failure");
    expect(v[197] == 3007) catch @panic("test failure");
    expect(v[198] == 3008) catch @panic("test failure");
    expect(v[199] == 3009) catch @panic("test failure");
    expect(v[200] == 3010) catch @panic("test failure");
    expect(v[201] == 3011) catch @panic("test failure");
    expect(v[202] == 3012) catch @panic("test failure");
    expect(v[203] == 3013) catch @panic("test failure");
    expect(v[204] == 3014) catch @panic("test failure");
    expect(v[205] == 3015) catch @panic("test failure");
    expect(v[206] == 3016) catch @panic("test failure");
    expect(v[207] == 3017) catch @panic("test failure");
    expect(v[208] == 3018) catch @panic("test failure");
    expect(v[209] == 3019) catch @panic("test failure");
    expect(v[210] == 3020) catch @panic("test failure");
    expect(v[211] == 3021) catch @panic("test failure");
    expect(v[212] == 3022) catch @panic("test failure");
    expect(v[213] == 3023) catch @panic("test failure");
    expect(v[214] == 3024) catch @panic("test failure");
    expect(v[215] == 3025) catch @panic("test failure");
    expect(v[216] == 3026) catch @panic("test failure");
    expect(v[217] == 3027) catch @panic("test failure");
    expect(v[218] == 3028) catch @panic("test failure");
    expect(v[219] == 3029) catch @panic("test failure");
    expect(v[220] == 3030) catch @panic("test failure");
    expect(v[221] == 3031) catch @panic("test failure");
    expect(v[222] == 3032) catch @panic("test failure");
    expect(v[223] == 3033) catch @panic("test failure");
    expect(v[224] == 3034) catch @panic("test failure");
    expect(v[225] == 3035) catch @panic("test failure");
    expect(v[226] == 3036) catch @panic("test failure");
    expect(v[227] == 3037) catch @panic("test failure");
    expect(v[228] == 3038) catch @panic("test failure");
    expect(v[229] == 3039) catch @panic("test failure");
    expect(v[230] == 3040) catch @panic("test failure");
    expect(v[231] == 3041) catch @panic("test failure");
    expect(v[232] == 3042) catch @panic("test failure");
    expect(v[233] == 3043) catch @panic("test failure");
    expect(v[234] == 3044) catch @panic("test failure");
    expect(v[235] == 3045) catch @panic("test failure");
    expect(v[236] == 3046) catch @panic("test failure");
    expect(v[237] == 3047) catch @panic("test failure");
    expect(v[238] == 3048) catch @panic("test failure");
    expect(v[239] == 3049) catch @panic("test failure");
    expect(v[240] == 3050) catch @panic("test failure");
    expect(v[241] == 3051) catch @panic("test failure");
    expect(v[242] == 3052) catch @panic("test failure");
    expect(v[243] == 3053) catch @panic("test failure");
    expect(v[244] == 3054) catch @panic("test failure");
    expect(v[245] == 3055) catch @panic("test failure");
    expect(v[246] == 3056) catch @panic("test failure");
    expect(v[247] == 3057) catch @panic("test failure");
    expect(v[248] == 3058) catch @panic("test failure");
    expect(v[249] == 3059) catch @panic("test failure");
    expect(v[250] == 3060) catch @panic("test failure");
    expect(v[251] == 3061) catch @panic("test failure");
    expect(v[252] == 3062) catch @panic("test failure");
    expect(v[253] == 3063) catch @panic("test failure");
    expect(v[254] == 3064) catch @panic("test failure");
    expect(v[255] == 3065) catch @panic("test failure");
    expect(i == 256) catch @panic("test failure");
}

extern fn c_ret_vector_256_u16() @Vector(256, u16);
extern fn c_vector_256_u16(@Vector(256, u16), usize) void;
extern fn c_test_vector_256_u16() void;

test "@Vector(256, u16)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_256_u16();
    try expect(v[0] == 3066);
    try expect(v[1] == 3067);
    try expect(v[2] == 3068);
    try expect(v[3] == 3069);
    try expect(v[4] == 3070);
    try expect(v[5] == 3071);
    try expect(v[6] == 3072);
    try expect(v[7] == 3073);
    try expect(v[8] == 3074);
    try expect(v[9] == 3075);
    try expect(v[10] == 3076);
    try expect(v[11] == 3077);
    try expect(v[12] == 3078);
    try expect(v[13] == 3079);
    try expect(v[14] == 3080);
    try expect(v[15] == 3081);
    try expect(v[16] == 3082);
    try expect(v[17] == 3083);
    try expect(v[18] == 3084);
    try expect(v[19] == 3085);
    try expect(v[20] == 3086);
    try expect(v[21] == 3087);
    try expect(v[22] == 3088);
    try expect(v[23] == 3089);
    try expect(v[24] == 3090);
    try expect(v[25] == 3091);
    try expect(v[26] == 3092);
    try expect(v[27] == 3093);
    try expect(v[28] == 3094);
    try expect(v[29] == 3095);
    try expect(v[30] == 3096);
    try expect(v[31] == 3097);
    try expect(v[32] == 3098);
    try expect(v[33] == 3099);
    try expect(v[34] == 3100);
    try expect(v[35] == 3101);
    try expect(v[36] == 3102);
    try expect(v[37] == 3103);
    try expect(v[38] == 3104);
    try expect(v[39] == 3105);
    try expect(v[40] == 3106);
    try expect(v[41] == 3107);
    try expect(v[42] == 3108);
    try expect(v[43] == 3109);
    try expect(v[44] == 3110);
    try expect(v[45] == 3111);
    try expect(v[46] == 3112);
    try expect(v[47] == 3113);
    try expect(v[48] == 3114);
    try expect(v[49] == 3115);
    try expect(v[50] == 3116);
    try expect(v[51] == 3117);
    try expect(v[52] == 3118);
    try expect(v[53] == 3119);
    try expect(v[54] == 3120);
    try expect(v[55] == 3121);
    try expect(v[56] == 3122);
    try expect(v[57] == 3123);
    try expect(v[58] == 3124);
    try expect(v[59] == 3125);
    try expect(v[60] == 3126);
    try expect(v[61] == 3127);
    try expect(v[62] == 3128);
    try expect(v[63] == 3129);
    try expect(v[64] == 3130);
    try expect(v[65] == 3131);
    try expect(v[66] == 3132);
    try expect(v[67] == 3133);
    try expect(v[68] == 3134);
    try expect(v[69] == 3135);
    try expect(v[70] == 3136);
    try expect(v[71] == 3137);
    try expect(v[72] == 3138);
    try expect(v[73] == 3139);
    try expect(v[74] == 3140);
    try expect(v[75] == 3141);
    try expect(v[76] == 3142);
    try expect(v[77] == 3143);
    try expect(v[78] == 3144);
    try expect(v[79] == 3145);
    try expect(v[80] == 3146);
    try expect(v[81] == 3147);
    try expect(v[82] == 3148);
    try expect(v[83] == 3149);
    try expect(v[84] == 3150);
    try expect(v[85] == 3151);
    try expect(v[86] == 3152);
    try expect(v[87] == 3153);
    try expect(v[88] == 3154);
    try expect(v[89] == 3155);
    try expect(v[90] == 3156);
    try expect(v[91] == 3157);
    try expect(v[92] == 3158);
    try expect(v[93] == 3159);
    try expect(v[94] == 3160);
    try expect(v[95] == 3161);
    try expect(v[96] == 3162);
    try expect(v[97] == 3163);
    try expect(v[98] == 3164);
    try expect(v[99] == 3165);
    try expect(v[100] == 3166);
    try expect(v[101] == 3167);
    try expect(v[102] == 3168);
    try expect(v[103] == 3169);
    try expect(v[104] == 3170);
    try expect(v[105] == 3171);
    try expect(v[106] == 3172);
    try expect(v[107] == 3173);
    try expect(v[108] == 3174);
    try expect(v[109] == 3175);
    try expect(v[110] == 3176);
    try expect(v[111] == 3177);
    try expect(v[112] == 3178);
    try expect(v[113] == 3179);
    try expect(v[114] == 3180);
    try expect(v[115] == 3181);
    try expect(v[116] == 3182);
    try expect(v[117] == 3183);
    try expect(v[118] == 3184);
    try expect(v[119] == 3185);
    try expect(v[120] == 3186);
    try expect(v[121] == 3187);
    try expect(v[122] == 3188);
    try expect(v[123] == 3189);
    try expect(v[124] == 3190);
    try expect(v[125] == 3191);
    try expect(v[126] == 3192);
    try expect(v[127] == 3193);
    try expect(v[128] == 3194);
    try expect(v[129] == 3195);
    try expect(v[130] == 3196);
    try expect(v[131] == 3197);
    try expect(v[132] == 3198);
    try expect(v[133] == 3199);
    try expect(v[134] == 3200);
    try expect(v[135] == 3201);
    try expect(v[136] == 3202);
    try expect(v[137] == 3203);
    try expect(v[138] == 3204);
    try expect(v[139] == 3205);
    try expect(v[140] == 3206);
    try expect(v[141] == 3207);
    try expect(v[142] == 3208);
    try expect(v[143] == 3209);
    try expect(v[144] == 3210);
    try expect(v[145] == 3211);
    try expect(v[146] == 3212);
    try expect(v[147] == 3213);
    try expect(v[148] == 3214);
    try expect(v[149] == 3215);
    try expect(v[150] == 3216);
    try expect(v[151] == 3217);
    try expect(v[152] == 3218);
    try expect(v[153] == 3219);
    try expect(v[154] == 3220);
    try expect(v[155] == 3221);
    try expect(v[156] == 3222);
    try expect(v[157] == 3223);
    try expect(v[158] == 3224);
    try expect(v[159] == 3225);
    try expect(v[160] == 3226);
    try expect(v[161] == 3227);
    try expect(v[162] == 3228);
    try expect(v[163] == 3229);
    try expect(v[164] == 3230);
    try expect(v[165] == 3231);
    try expect(v[166] == 3232);
    try expect(v[167] == 3233);
    try expect(v[168] == 3234);
    try expect(v[169] == 3235);
    try expect(v[170] == 3236);
    try expect(v[171] == 3237);
    try expect(v[172] == 3238);
    try expect(v[173] == 3239);
    try expect(v[174] == 3240);
    try expect(v[175] == 3241);
    try expect(v[176] == 3242);
    try expect(v[177] == 3243);
    try expect(v[178] == 3244);
    try expect(v[179] == 3245);
    try expect(v[180] == 3246);
    try expect(v[181] == 3247);
    try expect(v[182] == 3248);
    try expect(v[183] == 3249);
    try expect(v[184] == 3250);
    try expect(v[185] == 3251);
    try expect(v[186] == 3252);
    try expect(v[187] == 3253);
    try expect(v[188] == 3254);
    try expect(v[189] == 3255);
    try expect(v[190] == 3256);
    try expect(v[191] == 3257);
    try expect(v[192] == 3258);
    try expect(v[193] == 3259);
    try expect(v[194] == 3260);
    try expect(v[195] == 3261);
    try expect(v[196] == 3262);
    try expect(v[197] == 3263);
    try expect(v[198] == 3264);
    try expect(v[199] == 3265);
    try expect(v[200] == 3266);
    try expect(v[201] == 3267);
    try expect(v[202] == 3268);
    try expect(v[203] == 3269);
    try expect(v[204] == 3270);
    try expect(v[205] == 3271);
    try expect(v[206] == 3272);
    try expect(v[207] == 3273);
    try expect(v[208] == 3274);
    try expect(v[209] == 3275);
    try expect(v[210] == 3276);
    try expect(v[211] == 3277);
    try expect(v[212] == 3278);
    try expect(v[213] == 3279);
    try expect(v[214] == 3280);
    try expect(v[215] == 3281);
    try expect(v[216] == 3282);
    try expect(v[217] == 3283);
    try expect(v[218] == 3284);
    try expect(v[219] == 3285);
    try expect(v[220] == 3286);
    try expect(v[221] == 3287);
    try expect(v[222] == 3288);
    try expect(v[223] == 3289);
    try expect(v[224] == 3290);
    try expect(v[225] == 3291);
    try expect(v[226] == 3292);
    try expect(v[227] == 3293);
    try expect(v[228] == 3294);
    try expect(v[229] == 3295);
    try expect(v[230] == 3296);
    try expect(v[231] == 3297);
    try expect(v[232] == 3298);
    try expect(v[233] == 3299);
    try expect(v[234] == 3300);
    try expect(v[235] == 3301);
    try expect(v[236] == 3302);
    try expect(v[237] == 3303);
    try expect(v[238] == 3304);
    try expect(v[239] == 3305);
    try expect(v[240] == 3306);
    try expect(v[241] == 3307);
    try expect(v[242] == 3308);
    try expect(v[243] == 3309);
    try expect(v[244] == 3310);
    try expect(v[245] == 3311);
    try expect(v[246] == 3312);
    try expect(v[247] == 3313);
    try expect(v[248] == 3314);
    try expect(v[249] == 3315);
    try expect(v[250] == 3316);
    try expect(v[251] == 3317);
    try expect(v[252] == 3318);
    try expect(v[253] == 3319);
    try expect(v[254] == 3320);
    try expect(v[255] == 3321);
    c_vector_256_u16(.{
        3322, 3323, 3324, 3325, 3326, 3327, 3328, 3329, 3330, 3331, 3332, 3333, 3334, 3335, 3336, 3337,
        3338, 3339, 3340, 3341, 3342, 3343, 3344, 3345, 3346, 3347, 3348, 3349, 3350, 3351, 3352, 3353,
        3354, 3355, 3356, 3357, 3358, 3359, 3360, 3361, 3362, 3363, 3364, 3365, 3366, 3367, 3368, 3369,
        3370, 3371, 3372, 3373, 3374, 3375, 3376, 3377, 3378, 3379, 3380, 3381, 3382, 3383, 3384, 3385,
        3386, 3387, 3388, 3389, 3390, 3391, 3392, 3393, 3394, 3395, 3396, 3397, 3398, 3399, 3400, 3401,
        3402, 3403, 3404, 3405, 3406, 3407, 3408, 3409, 3410, 3411, 3412, 3413, 3414, 3415, 3416, 3417,
        3418, 3419, 3420, 3421, 3422, 3423, 3424, 3425, 3426, 3427, 3428, 3429, 3430, 3431, 3432, 3433,
        3434, 3435, 3436, 3437, 3438, 3439, 3440, 3441, 3442, 3443, 3444, 3445, 3446, 3447, 3448, 3449,
        3450, 3451, 3452, 3453, 3454, 3455, 3456, 3457, 3458, 3459, 3460, 3461, 3462, 3463, 3464, 3465,
        3466, 3467, 3468, 3469, 3470, 3471, 3472, 3473, 3474, 3475, 3476, 3477, 3478, 3479, 3480, 3481,
        3482, 3483, 3484, 3485, 3486, 3487, 3488, 3489, 3490, 3491, 3492, 3493, 3494, 3495, 3496, 3497,
        3498, 3499, 3500, 3501, 3502, 3503, 3504, 3505, 3506, 3507, 3508, 3509, 3510, 3511, 3512, 3513,
        3514, 3515, 3516, 3517, 3518, 3519, 3520, 3521, 3522, 3523, 3524, 3525, 3526, 3527, 3528, 3529,
        3530, 3531, 3532, 3533, 3534, 3535, 3536, 3537, 3538, 3539, 3540, 3541, 3542, 3543, 3544, 3545,
        3546, 3547, 3548, 3549, 3550, 3551, 3552, 3553, 3554, 3555, 3556, 3557, 3558, 3559, 3560, 3561,
        3562, 3563, 3564, 3565, 3566, 3567, 3568, 3569, 3570, 3571, 3572, 3573, 3574, 3575, 3576, 3577,
    }, 256);
    c_test_vector_256_u16();
}

export fn zig_ret_vector_1_u32() @Vector(1, u32) {
    return .{1};
}
export fn zig_vector_1_u32(v: @Vector(1, u32), i: usize) void {
    expect(v[0] == 2) catch @panic("test failure");
    expect(i == 1) catch @panic("test failure");
}

extern fn c_ret_vector_1_u32() @Vector(1, u32);
extern fn c_vector_1_u32(@Vector(1, u32), usize) void;
extern fn c_test_vector_1_u32() void;

test "@Vector(1, u32)" {
    if (builtin.cpu.arch.isAARCH64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;

    const v = c_ret_vector_1_u32();
    try expect(v[0] == 3);
    c_vector_1_u32(.{4}, 1);
    c_test_vector_1_u32();
}

export fn zig_ret_vector_2_u32() @Vector(2, u32) {
    return .{ 5, 6 };
}
export fn zig_vector_2_u32(v: @Vector(2, u32), i: usize) void {
    expect(v[0] == 7) catch @panic("test failure");
    expect(v[1] == 8) catch @panic("test failure");
    expect(i == 2) catch @panic("test failure");
}

extern fn c_ret_vector_2_u32() @Vector(2, u32);
extern fn c_vector_2_u32(@Vector(2, u32), usize) void;
extern fn c_test_vector_2_u32() void;

test "@Vector(2, u32)" {
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .x86_64 and builtin.os.tag == .windows) return error.SkipZigTest;

    const v = c_ret_vector_2_u32();
    try expect(v[0] == 9);
    try expect(v[1] == 10);
    c_vector_2_u32(.{ 11, 12 }, 2);
    c_test_vector_2_u32();
}

export fn zig_ret_vector_3_u32() @Vector(3, u32) {
    return .{ 13, 14, 15 };
}
export fn zig_vector_3_u32(v: @Vector(3, u32), i: usize) void {
    expect(v[0] == 16) catch @panic("test failure");
    expect(v[1] == 17) catch @panic("test failure");
    expect(v[2] == 18) catch @panic("test failure");
    expect(i == 3) catch @panic("test failure");
}

extern fn c_ret_vector_3_u32() @Vector(3, u32);
extern fn c_vector_3_u32(@Vector(3, u32), usize) void;
extern fn c_test_vector_3_u32() void;

test "@Vector(3, u32)" {
    if (builtin.cpu.arch.isArm() and builtin.abi.float() == .soft) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;

    const v = c_ret_vector_3_u32();
    try expect(v[0] == 19);
    try expect(v[1] == 20);
    try expect(v[2] == 21);
    c_vector_3_u32(.{ 22, 23, 24 }, 3);
    c_test_vector_3_u32();
}

export fn zig_ret_vector_4_u32() @Vector(4, u32) {
    return .{ 25, 26, 27, 28 };
}
export fn zig_vector_4_u32(v: @Vector(4, u32), i: usize) void {
    expect(v[0] == 29) catch @panic("test failure");
    expect(v[1] == 30) catch @panic("test failure");
    expect(v[2] == 31) catch @panic("test failure");
    expect(v[3] == 32) catch @panic("test failure");
    expect(i == 4) catch @panic("test failure");
}
export fn zig_vector_4_u32_vector_4_u32(v0: @Vector(4, u32), v1: @Vector(4, u32), i: usize) void {
    expect(v0[0] == 33) catch @panic("test failure");
    expect(v0[1] == 34) catch @panic("test failure");
    expect(v0[2] == 35) catch @panic("test failure");
    expect(v0[3] == 36) catch @panic("test failure");
    expect(v1[0] == 37) catch @panic("test failure");
    expect(v1[1] == 38) catch @panic("test failure");
    expect(v1[2] == 39) catch @panic("test failure");
    expect(v1[3] == 40) catch @panic("test failure");
    expect(i == 8) catch @panic("test failure");
}

extern fn c_ret_vector_4_u32() @Vector(4, u32);
extern fn c_vector_4_u32(@Vector(4, u32), usize) void;
extern fn c_vector_4_u32_vector_4_u32(@Vector(4, u32), @Vector(4, u32), usize) void;
extern fn c_test_vector_4_u32() void;

test "@Vector(4, u32)" {
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;

    const v = c_ret_vector_4_u32();
    try expect(v[0] == 41);
    try expect(v[1] == 42);
    try expect(v[2] == 43);
    try expect(v[3] == 44);
    c_vector_4_u32(.{ 45, 46, 47, 48 }, 4);
    c_vector_4_u32_vector_4_u32(.{ 49, 50, 51, 52 }, .{ 53, 54, 55, 56 }, 8);
    c_test_vector_4_u32();
}

export fn zig_ret_vector_6_u32() @Vector(6, u32) {
    return .{ 41, 42, 43, 44, 45, 46 };
}
export fn zig_vector_6_u32(v: @Vector(6, u32), i: usize) void {
    expect(v[0] == 47) catch @panic("test failure");
    expect(v[1] == 48) catch @panic("test failure");
    expect(v[2] == 49) catch @panic("test failure");
    expect(v[3] == 50) catch @panic("test failure");
    expect(v[4] == 51) catch @panic("test failure");
    expect(v[5] == 52) catch @panic("test failure");
    expect(i == 6) catch @panic("test failure");
}

extern fn c_ret_vector_6_u32() @Vector(6, u32);
extern fn c_vector_6_u32(@Vector(6, u32), usize) void;
extern fn c_test_vector_6_u32() void;

test "@Vector(6, u32)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_6_u32();
    try expect(v[0] == 53);
    try expect(v[1] == 54);
    try expect(v[2] == 55);
    try expect(v[3] == 56);
    try expect(v[4] == 57);
    try expect(v[5] == 58);
    c_vector_6_u32(.{ 59, 60, 61, 62, 63, 64 }, 6);
    c_test_vector_6_u32();
}

export fn zig_ret_vector_8_u32() @Vector(8, u32) {
    return .{ 65, 66, 67, 68, 69, 70, 71, 72 };
}
export fn zig_vector_8_u32(v: @Vector(8, u32), i: usize) void {
    expect(v[0] == 73) catch @panic("test failure");
    expect(v[1] == 74) catch @panic("test failure");
    expect(v[2] == 75) catch @panic("test failure");
    expect(v[3] == 76) catch @panic("test failure");
    expect(v[4] == 77) catch @panic("test failure");
    expect(v[5] == 78) catch @panic("test failure");
    expect(v[6] == 79) catch @panic("test failure");
    expect(v[7] == 80) catch @panic("test failure");
    expect(i == 8) catch @panic("test failure");
}

extern fn c_ret_vector_8_u32() @Vector(8, u32);
extern fn c_vector_8_u32(@Vector(8, u32), usize) void;
extern fn c_test_vector_8_u32() void;

test "@Vector(8, u32)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_8_u32();
    try expect(v[0] == 81);
    try expect(v[1] == 82);
    try expect(v[2] == 83);
    try expect(v[3] == 84);
    try expect(v[4] == 85);
    try expect(v[5] == 86);
    try expect(v[6] == 87);
    try expect(v[7] == 88);
    c_vector_8_u32(.{ 89, 90, 91, 92, 93, 94, 95, 96 }, 8);
    c_test_vector_8_u32();
}

export fn zig_ret_vector_12_u32() @Vector(12, u32) {
    return .{ 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108 };
}
export fn zig_vector_12_u32(v: @Vector(12, u32), i: usize) void {
    expect(v[0] == 109) catch @panic("test failure");
    expect(v[1] == 110) catch @panic("test failure");
    expect(v[2] == 111) catch @panic("test failure");
    expect(v[3] == 112) catch @panic("test failure");
    expect(v[4] == 113) catch @panic("test failure");
    expect(v[5] == 114) catch @panic("test failure");
    expect(v[6] == 115) catch @panic("test failure");
    expect(v[7] == 116) catch @panic("test failure");
    expect(v[8] == 117) catch @panic("test failure");
    expect(v[9] == 118) catch @panic("test failure");
    expect(v[10] == 119) catch @panic("test failure");
    expect(v[11] == 120) catch @panic("test failure");
    expect(i == 12) catch @panic("test failure");
}

extern fn c_ret_vector_12_u32() @Vector(12, u32);
extern fn c_vector_12_u32(@Vector(12, u32), usize) void;
extern fn c_test_vector_12_u32() void;

test "@Vector(12, u32)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_12_u32();
    try expect(v[0] == 121);
    try expect(v[1] == 122);
    try expect(v[2] == 123);
    try expect(v[3] == 124);
    try expect(v[4] == 125);
    try expect(v[5] == 126);
    try expect(v[6] == 127);
    try expect(v[7] == 128);
    try expect(v[8] == 129);
    try expect(v[9] == 130);
    try expect(v[10] == 131);
    try expect(v[11] == 132);
    c_vector_12_u32(.{ 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144 }, 12);
    c_test_vector_12_u32();
}

export fn zig_ret_vector_16_u32() @Vector(16, u32) {
    return .{ 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160 };
}
export fn zig_vector_16_u32(v: @Vector(16, u32), i: usize) void {
    expect(v[0] == 161) catch @panic("test failure");
    expect(v[1] == 162) catch @panic("test failure");
    expect(v[2] == 163) catch @panic("test failure");
    expect(v[3] == 164) catch @panic("test failure");
    expect(v[4] == 165) catch @panic("test failure");
    expect(v[5] == 166) catch @panic("test failure");
    expect(v[6] == 167) catch @panic("test failure");
    expect(v[7] == 168) catch @panic("test failure");
    expect(v[8] == 169) catch @panic("test failure");
    expect(v[9] == 170) catch @panic("test failure");
    expect(v[10] == 171) catch @panic("test failure");
    expect(v[11] == 172) catch @panic("test failure");
    expect(v[12] == 173) catch @panic("test failure");
    expect(v[13] == 174) catch @panic("test failure");
    expect(v[14] == 175) catch @panic("test failure");
    expect(v[15] == 176) catch @panic("test failure");
    expect(i == 16) catch @panic("test failure");
}

extern fn c_ret_vector_16_u32() @Vector(16, u32);
extern fn c_vector_16_u32(@Vector(16, u32), usize) void;
extern fn c_test_vector_16_u32() void;

test "@Vector(16, u32)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_16_u32();
    try expect(v[0] == 177);
    try expect(v[1] == 178);
    try expect(v[2] == 179);
    try expect(v[3] == 180);
    try expect(v[4] == 181);
    try expect(v[5] == 182);
    try expect(v[6] == 183);
    try expect(v[7] == 184);
    try expect(v[8] == 185);
    try expect(v[9] == 186);
    try expect(v[10] == 187);
    try expect(v[11] == 188);
    try expect(v[12] == 189);
    try expect(v[13] == 190);
    try expect(v[14] == 191);
    try expect(v[15] == 192);
    c_vector_16_u32(.{ 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208 }, 16);
    c_test_vector_16_u32();
}

export fn zig_ret_vector_24_u32() @Vector(24, u32) {
    return .{
        209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224,
        225, 226, 227, 228, 229, 230, 231, 232,
    };
}
export fn zig_vector_24_u32(v: @Vector(24, u32), i: usize) void {
    expect(v[0] == 233) catch @panic("test failure");
    expect(v[1] == 234) catch @panic("test failure");
    expect(v[2] == 235) catch @panic("test failure");
    expect(v[3] == 236) catch @panic("test failure");
    expect(v[4] == 237) catch @panic("test failure");
    expect(v[5] == 238) catch @panic("test failure");
    expect(v[6] == 239) catch @panic("test failure");
    expect(v[7] == 240) catch @panic("test failure");
    expect(v[8] == 241) catch @panic("test failure");
    expect(v[9] == 242) catch @panic("test failure");
    expect(v[10] == 243) catch @panic("test failure");
    expect(v[11] == 244) catch @panic("test failure");
    expect(v[12] == 245) catch @panic("test failure");
    expect(v[13] == 246) catch @panic("test failure");
    expect(v[14] == 247) catch @panic("test failure");
    expect(v[15] == 248) catch @panic("test failure");
    expect(v[16] == 249) catch @panic("test failure");
    expect(v[17] == 250) catch @panic("test failure");
    expect(v[18] == 251) catch @panic("test failure");
    expect(v[19] == 252) catch @panic("test failure");
    expect(v[20] == 253) catch @panic("test failure");
    expect(v[21] == 254) catch @panic("test failure");
    expect(v[22] == 255) catch @panic("test failure");
    expect(v[23] == 256) catch @panic("test failure");
    expect(i == 24) catch @panic("test failure");
}

extern fn c_ret_vector_24_u32() @Vector(24, u32);
extern fn c_vector_24_u32(@Vector(24, u32), usize) void;
extern fn c_test_vector_24_u32() void;

test "@Vector(24, u32)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_24_u32();
    try expect(v[0] == 257);
    try expect(v[1] == 258);
    try expect(v[2] == 259);
    try expect(v[3] == 260);
    try expect(v[4] == 261);
    try expect(v[5] == 262);
    try expect(v[6] == 263);
    try expect(v[7] == 264);
    try expect(v[8] == 265);
    try expect(v[9] == 266);
    try expect(v[10] == 267);
    try expect(v[11] == 268);
    try expect(v[12] == 269);
    try expect(v[13] == 270);
    try expect(v[14] == 271);
    try expect(v[15] == 272);
    try expect(v[16] == 273);
    try expect(v[17] == 274);
    try expect(v[18] == 275);
    try expect(v[19] == 276);
    try expect(v[20] == 277);
    try expect(v[21] == 278);
    try expect(v[22] == 279);
    try expect(v[23] == 280);
    c_vector_24_u32(.{
        281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296,
        297, 298, 299, 300, 301, 302, 303, 304,
    }, 24);
    c_test_vector_24_u32();
}

export fn zig_ret_vector_32_u32() @Vector(32, u32) {
    return .{
        305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320,
        321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336,
    };
}
export fn zig_vector_32_u32(v: @Vector(32, u32), i: usize) void {
    expect(v[0] == 337) catch @panic("test failure");
    expect(v[1] == 338) catch @panic("test failure");
    expect(v[2] == 339) catch @panic("test failure");
    expect(v[3] == 340) catch @panic("test failure");
    expect(v[4] == 341) catch @panic("test failure");
    expect(v[5] == 342) catch @panic("test failure");
    expect(v[6] == 343) catch @panic("test failure");
    expect(v[7] == 344) catch @panic("test failure");
    expect(v[8] == 345) catch @panic("test failure");
    expect(v[9] == 346) catch @panic("test failure");
    expect(v[10] == 347) catch @panic("test failure");
    expect(v[11] == 348) catch @panic("test failure");
    expect(v[12] == 349) catch @panic("test failure");
    expect(v[13] == 350) catch @panic("test failure");
    expect(v[14] == 351) catch @panic("test failure");
    expect(v[15] == 352) catch @panic("test failure");
    expect(v[16] == 353) catch @panic("test failure");
    expect(v[17] == 354) catch @panic("test failure");
    expect(v[18] == 355) catch @panic("test failure");
    expect(v[19] == 356) catch @panic("test failure");
    expect(v[20] == 357) catch @panic("test failure");
    expect(v[21] == 358) catch @panic("test failure");
    expect(v[22] == 359) catch @panic("test failure");
    expect(v[23] == 360) catch @panic("test failure");
    expect(v[24] == 361) catch @panic("test failure");
    expect(v[25] == 362) catch @panic("test failure");
    expect(v[26] == 363) catch @panic("test failure");
    expect(v[27] == 364) catch @panic("test failure");
    expect(v[28] == 365) catch @panic("test failure");
    expect(v[29] == 366) catch @panic("test failure");
    expect(v[30] == 367) catch @panic("test failure");
    expect(v[31] == 368) catch @panic("test failure");
    expect(i == 32) catch @panic("test failure");
}

extern fn c_ret_vector_32_u32() @Vector(32, u32);
extern fn c_vector_32_u32(@Vector(32, u32), usize) void;
extern fn c_test_vector_32_u32() void;

test "@Vector(32, u32)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_32_u32();
    try expect(v[0] == 369);
    try expect(v[1] == 370);
    try expect(v[2] == 371);
    try expect(v[3] == 372);
    try expect(v[4] == 373);
    try expect(v[5] == 374);
    try expect(v[6] == 375);
    try expect(v[7] == 376);
    try expect(v[8] == 377);
    try expect(v[9] == 378);
    try expect(v[10] == 379);
    try expect(v[11] == 380);
    try expect(v[12] == 381);
    try expect(v[13] == 382);
    try expect(v[14] == 383);
    try expect(v[15] == 384);
    try expect(v[16] == 385);
    try expect(v[17] == 386);
    try expect(v[18] == 387);
    try expect(v[19] == 388);
    try expect(v[20] == 389);
    try expect(v[21] == 390);
    try expect(v[22] == 391);
    try expect(v[23] == 392);
    try expect(v[24] == 393);
    try expect(v[25] == 394);
    try expect(v[26] == 395);
    try expect(v[27] == 396);
    try expect(v[28] == 397);
    try expect(v[29] == 398);
    try expect(v[30] == 399);
    try expect(v[31] == 400);
    c_vector_32_u32(.{
        401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416,
        417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, 431, 432,
    }, 32);
    c_test_vector_32_u32();
}

export fn zig_ret_vector_48_u32() @Vector(48, u32) {
    return .{
        433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 443, 444, 445, 446, 447, 448,
        449, 450, 451, 452, 453, 454, 455, 456, 457, 458, 459, 460, 461, 462, 463, 464,
        465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480,
    };
}
export fn zig_vector_48_u32(v: @Vector(48, u32), i: usize) void {
    expect(v[0] == 481) catch @panic("test failure");
    expect(v[1] == 482) catch @panic("test failure");
    expect(v[2] == 483) catch @panic("test failure");
    expect(v[3] == 484) catch @panic("test failure");
    expect(v[4] == 485) catch @panic("test failure");
    expect(v[5] == 486) catch @panic("test failure");
    expect(v[6] == 487) catch @panic("test failure");
    expect(v[7] == 488) catch @panic("test failure");
    expect(v[8] == 489) catch @panic("test failure");
    expect(v[9] == 490) catch @panic("test failure");
    expect(v[10] == 491) catch @panic("test failure");
    expect(v[11] == 492) catch @panic("test failure");
    expect(v[12] == 493) catch @panic("test failure");
    expect(v[13] == 494) catch @panic("test failure");
    expect(v[14] == 495) catch @panic("test failure");
    expect(v[15] == 496) catch @panic("test failure");
    expect(v[16] == 497) catch @panic("test failure");
    expect(v[17] == 498) catch @panic("test failure");
    expect(v[18] == 499) catch @panic("test failure");
    expect(v[19] == 500) catch @panic("test failure");
    expect(v[20] == 501) catch @panic("test failure");
    expect(v[21] == 502) catch @panic("test failure");
    expect(v[22] == 503) catch @panic("test failure");
    expect(v[23] == 504) catch @panic("test failure");
    expect(v[24] == 505) catch @panic("test failure");
    expect(v[25] == 506) catch @panic("test failure");
    expect(v[26] == 507) catch @panic("test failure");
    expect(v[27] == 508) catch @panic("test failure");
    expect(v[28] == 509) catch @panic("test failure");
    expect(v[29] == 510) catch @panic("test failure");
    expect(v[30] == 511) catch @panic("test failure");
    expect(v[31] == 512) catch @panic("test failure");
    expect(v[32] == 513) catch @panic("test failure");
    expect(v[33] == 514) catch @panic("test failure");
    expect(v[34] == 515) catch @panic("test failure");
    expect(v[35] == 516) catch @panic("test failure");
    expect(v[36] == 517) catch @panic("test failure");
    expect(v[37] == 518) catch @panic("test failure");
    expect(v[38] == 519) catch @panic("test failure");
    expect(v[39] == 520) catch @panic("test failure");
    expect(v[40] == 521) catch @panic("test failure");
    expect(v[41] == 522) catch @panic("test failure");
    expect(v[42] == 523) catch @panic("test failure");
    expect(v[43] == 524) catch @panic("test failure");
    expect(v[44] == 525) catch @panic("test failure");
    expect(v[45] == 526) catch @panic("test failure");
    expect(v[46] == 527) catch @panic("test failure");
    expect(v[47] == 528) catch @panic("test failure");
    expect(i == 48) catch @panic("test failure");
}

extern fn c_ret_vector_48_u32() @Vector(48, u32);
extern fn c_vector_48_u32(@Vector(48, u32), usize) void;
extern fn c_test_vector_48_u32() void;

test "@Vector(48, u32)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_48_u32();
    try expect(v[0] == 529);
    try expect(v[1] == 530);
    try expect(v[2] == 531);
    try expect(v[3] == 532);
    try expect(v[4] == 533);
    try expect(v[5] == 534);
    try expect(v[6] == 535);
    try expect(v[7] == 536);
    try expect(v[8] == 537);
    try expect(v[9] == 538);
    try expect(v[10] == 539);
    try expect(v[11] == 540);
    try expect(v[12] == 541);
    try expect(v[13] == 542);
    try expect(v[14] == 543);
    try expect(v[15] == 544);
    try expect(v[16] == 545);
    try expect(v[17] == 546);
    try expect(v[18] == 547);
    try expect(v[19] == 548);
    try expect(v[20] == 549);
    try expect(v[21] == 550);
    try expect(v[22] == 551);
    try expect(v[23] == 552);
    try expect(v[24] == 553);
    try expect(v[25] == 554);
    try expect(v[26] == 555);
    try expect(v[27] == 556);
    try expect(v[28] == 557);
    try expect(v[29] == 558);
    try expect(v[30] == 559);
    try expect(v[31] == 560);
    try expect(v[32] == 561);
    try expect(v[33] == 562);
    try expect(v[34] == 563);
    try expect(v[35] == 564);
    try expect(v[36] == 565);
    try expect(v[37] == 566);
    try expect(v[38] == 567);
    try expect(v[39] == 568);
    try expect(v[40] == 569);
    try expect(v[41] == 570);
    try expect(v[42] == 571);
    try expect(v[43] == 572);
    try expect(v[44] == 573);
    try expect(v[45] == 574);
    try expect(v[46] == 575);
    try expect(v[47] == 576);
    c_vector_48_u32(.{
        577, 578, 579, 580, 581, 582, 583, 584, 585, 586, 587, 588, 589, 590, 591, 592,
        593, 594, 595, 596, 597, 598, 599, 600, 601, 602, 603, 604, 605, 606, 607, 608,
        609, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621, 622, 623, 624,
    }, 48);
    c_test_vector_48_u32();
}

export fn zig_ret_vector_64_u32() @Vector(64, u32) {
    return .{
        625, 626, 627, 628, 629, 630, 631, 632, 633, 634, 635, 636, 637, 638, 639, 640,
        641, 642, 643, 644, 645, 646, 647, 648, 649, 650, 651, 652, 653, 654, 655, 656,
        657, 658, 659, 660, 661, 662, 663, 664, 665, 666, 667, 668, 669, 670, 671, 672,
        673, 674, 675, 676, 677, 678, 679, 680, 681, 682, 683, 684, 685, 686, 687, 688,
    };
}
export fn zig_vector_64_u32(v: @Vector(64, u32), i: usize) void {
    expect(v[0] == 689) catch @panic("test failure");
    expect(v[1] == 690) catch @panic("test failure");
    expect(v[2] == 691) catch @panic("test failure");
    expect(v[3] == 692) catch @panic("test failure");
    expect(v[4] == 693) catch @panic("test failure");
    expect(v[5] == 694) catch @panic("test failure");
    expect(v[6] == 695) catch @panic("test failure");
    expect(v[7] == 696) catch @panic("test failure");
    expect(v[8] == 697) catch @panic("test failure");
    expect(v[9] == 698) catch @panic("test failure");
    expect(v[10] == 699) catch @panic("test failure");
    expect(v[11] == 700) catch @panic("test failure");
    expect(v[12] == 701) catch @panic("test failure");
    expect(v[13] == 702) catch @panic("test failure");
    expect(v[14] == 703) catch @panic("test failure");
    expect(v[15] == 704) catch @panic("test failure");
    expect(v[16] == 705) catch @panic("test failure");
    expect(v[17] == 706) catch @panic("test failure");
    expect(v[18] == 707) catch @panic("test failure");
    expect(v[19] == 708) catch @panic("test failure");
    expect(v[20] == 709) catch @panic("test failure");
    expect(v[21] == 710) catch @panic("test failure");
    expect(v[22] == 711) catch @panic("test failure");
    expect(v[23] == 712) catch @panic("test failure");
    expect(v[24] == 713) catch @panic("test failure");
    expect(v[25] == 714) catch @panic("test failure");
    expect(v[26] == 715) catch @panic("test failure");
    expect(v[27] == 716) catch @panic("test failure");
    expect(v[28] == 717) catch @panic("test failure");
    expect(v[29] == 718) catch @panic("test failure");
    expect(v[30] == 719) catch @panic("test failure");
    expect(v[31] == 720) catch @panic("test failure");
    expect(v[32] == 721) catch @panic("test failure");
    expect(v[33] == 722) catch @panic("test failure");
    expect(v[34] == 723) catch @panic("test failure");
    expect(v[35] == 724) catch @panic("test failure");
    expect(v[36] == 725) catch @panic("test failure");
    expect(v[37] == 726) catch @panic("test failure");
    expect(v[38] == 727) catch @panic("test failure");
    expect(v[39] == 728) catch @panic("test failure");
    expect(v[40] == 729) catch @panic("test failure");
    expect(v[41] == 730) catch @panic("test failure");
    expect(v[42] == 731) catch @panic("test failure");
    expect(v[43] == 732) catch @panic("test failure");
    expect(v[44] == 733) catch @panic("test failure");
    expect(v[45] == 734) catch @panic("test failure");
    expect(v[46] == 735) catch @panic("test failure");
    expect(v[47] == 736) catch @panic("test failure");
    expect(v[48] == 737) catch @panic("test failure");
    expect(v[49] == 738) catch @panic("test failure");
    expect(v[50] == 739) catch @panic("test failure");
    expect(v[51] == 740) catch @panic("test failure");
    expect(v[52] == 741) catch @panic("test failure");
    expect(v[53] == 742) catch @panic("test failure");
    expect(v[54] == 743) catch @panic("test failure");
    expect(v[55] == 744) catch @panic("test failure");
    expect(v[56] == 745) catch @panic("test failure");
    expect(v[57] == 746) catch @panic("test failure");
    expect(v[58] == 747) catch @panic("test failure");
    expect(v[59] == 748) catch @panic("test failure");
    expect(v[60] == 749) catch @panic("test failure");
    expect(v[61] == 750) catch @panic("test failure");
    expect(v[62] == 751) catch @panic("test failure");
    expect(v[63] == 752) catch @panic("test failure");
    expect(i == 64) catch @panic("test failure");
}

extern fn c_ret_vector_64_u32() @Vector(64, u32);
extern fn c_vector_64_u32(@Vector(64, u32), usize) void;
extern fn c_test_vector_64_u32() void;

test "@Vector(64, u32)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_64_u32();
    try expect(v[0] == 753);
    try expect(v[1] == 754);
    try expect(v[2] == 755);
    try expect(v[3] == 756);
    try expect(v[4] == 757);
    try expect(v[5] == 758);
    try expect(v[6] == 759);
    try expect(v[7] == 760);
    try expect(v[8] == 761);
    try expect(v[9] == 762);
    try expect(v[10] == 763);
    try expect(v[11] == 764);
    try expect(v[12] == 765);
    try expect(v[13] == 766);
    try expect(v[14] == 767);
    try expect(v[15] == 768);
    try expect(v[16] == 769);
    try expect(v[17] == 770);
    try expect(v[18] == 771);
    try expect(v[19] == 772);
    try expect(v[20] == 773);
    try expect(v[21] == 774);
    try expect(v[22] == 775);
    try expect(v[23] == 776);
    try expect(v[24] == 777);
    try expect(v[25] == 778);
    try expect(v[26] == 779);
    try expect(v[27] == 780);
    try expect(v[28] == 781);
    try expect(v[29] == 782);
    try expect(v[30] == 783);
    try expect(v[31] == 784);
    try expect(v[32] == 785);
    try expect(v[33] == 786);
    try expect(v[34] == 787);
    try expect(v[35] == 788);
    try expect(v[36] == 789);
    try expect(v[37] == 790);
    try expect(v[38] == 791);
    try expect(v[39] == 792);
    try expect(v[40] == 793);
    try expect(v[41] == 794);
    try expect(v[42] == 795);
    try expect(v[43] == 796);
    try expect(v[44] == 797);
    try expect(v[45] == 798);
    try expect(v[46] == 799);
    try expect(v[47] == 800);
    try expect(v[48] == 801);
    try expect(v[49] == 802);
    try expect(v[50] == 803);
    try expect(v[51] == 804);
    try expect(v[52] == 805);
    try expect(v[53] == 806);
    try expect(v[54] == 807);
    try expect(v[55] == 808);
    try expect(v[56] == 809);
    try expect(v[57] == 810);
    try expect(v[58] == 811);
    try expect(v[59] == 812);
    try expect(v[60] == 813);
    try expect(v[61] == 814);
    try expect(v[62] == 815);
    try expect(v[63] == 816);
    c_vector_64_u32(.{
        817, 818, 819, 820, 821, 822, 823, 824, 825, 826, 827, 828, 829, 830, 831, 832,
        833, 834, 835, 836, 837, 838, 839, 840, 841, 842, 843, 844, 845, 846, 847, 848,
        849, 850, 851, 852, 853, 854, 855, 856, 857, 858, 859, 860, 861, 862, 863, 864,
        865, 866, 867, 868, 869, 870, 871, 872, 873, 874, 875, 876, 877, 878, 879, 880,
    }, 64);
    c_test_vector_64_u32();
}

export fn zig_ret_vector_96_u32() @Vector(96, u32) {
    return .{
        890, 891, 892, 893, 894, 895, 896, 897, 898, 899, 900, 901, 902, 903, 904, 905,
        906, 907, 908, 909, 910, 911, 912, 913, 914, 915, 916, 917, 918, 919, 920, 921,
        922, 923, 924, 925, 926, 927, 928, 929, 930, 931, 932, 933, 934, 935, 936, 937,
        938, 939, 940, 941, 942, 943, 944, 945, 946, 947, 948, 949, 950, 951, 952, 953,
        954, 955, 956, 957, 958, 959, 960, 961, 962, 963, 964, 965, 966, 967, 968, 969,
        970, 971, 972, 973, 974, 975, 976, 977, 978, 979, 980, 981, 982, 983, 984, 985,
    };
}
export fn zig_vector_96_u32(v: @Vector(96, u32), i: usize) void {
    expect(v[0] == 986) catch @panic("test failure");
    expect(v[1] == 987) catch @panic("test failure");
    expect(v[2] == 988) catch @panic("test failure");
    expect(v[3] == 989) catch @panic("test failure");
    expect(v[4] == 990) catch @panic("test failure");
    expect(v[5] == 991) catch @panic("test failure");
    expect(v[6] == 992) catch @panic("test failure");
    expect(v[7] == 993) catch @panic("test failure");
    expect(v[8] == 994) catch @panic("test failure");
    expect(v[9] == 995) catch @panic("test failure");
    expect(v[10] == 996) catch @panic("test failure");
    expect(v[11] == 997) catch @panic("test failure");
    expect(v[12] == 998) catch @panic("test failure");
    expect(v[13] == 999) catch @panic("test failure");
    expect(v[14] == 1000) catch @panic("test failure");
    expect(v[15] == 1001) catch @panic("test failure");
    expect(v[16] == 1002) catch @panic("test failure");
    expect(v[17] == 1003) catch @panic("test failure");
    expect(v[18] == 1004) catch @panic("test failure");
    expect(v[19] == 1005) catch @panic("test failure");
    expect(v[20] == 1006) catch @panic("test failure");
    expect(v[21] == 1007) catch @panic("test failure");
    expect(v[22] == 1008) catch @panic("test failure");
    expect(v[23] == 1009) catch @panic("test failure");
    expect(v[24] == 1010) catch @panic("test failure");
    expect(v[25] == 1011) catch @panic("test failure");
    expect(v[26] == 1012) catch @panic("test failure");
    expect(v[27] == 1013) catch @panic("test failure");
    expect(v[28] == 1014) catch @panic("test failure");
    expect(v[29] == 1015) catch @panic("test failure");
    expect(v[30] == 1016) catch @panic("test failure");
    expect(v[31] == 1017) catch @panic("test failure");
    expect(v[32] == 1018) catch @panic("test failure");
    expect(v[33] == 1019) catch @panic("test failure");
    expect(v[34] == 1020) catch @panic("test failure");
    expect(v[35] == 1021) catch @panic("test failure");
    expect(v[36] == 1022) catch @panic("test failure");
    expect(v[37] == 1023) catch @panic("test failure");
    expect(v[38] == 1024) catch @panic("test failure");
    expect(v[39] == 1025) catch @panic("test failure");
    expect(v[40] == 1026) catch @panic("test failure");
    expect(v[41] == 1027) catch @panic("test failure");
    expect(v[42] == 1028) catch @panic("test failure");
    expect(v[43] == 1029) catch @panic("test failure");
    expect(v[44] == 1030) catch @panic("test failure");
    expect(v[45] == 1031) catch @panic("test failure");
    expect(v[46] == 1032) catch @panic("test failure");
    expect(v[47] == 1033) catch @panic("test failure");
    expect(v[48] == 1034) catch @panic("test failure");
    expect(v[49] == 1035) catch @panic("test failure");
    expect(v[50] == 1036) catch @panic("test failure");
    expect(v[51] == 1037) catch @panic("test failure");
    expect(v[52] == 1038) catch @panic("test failure");
    expect(v[53] == 1039) catch @panic("test failure");
    expect(v[54] == 1040) catch @panic("test failure");
    expect(v[55] == 1041) catch @panic("test failure");
    expect(v[56] == 1042) catch @panic("test failure");
    expect(v[57] == 1043) catch @panic("test failure");
    expect(v[58] == 1044) catch @panic("test failure");
    expect(v[59] == 1045) catch @panic("test failure");
    expect(v[60] == 1046) catch @panic("test failure");
    expect(v[61] == 1047) catch @panic("test failure");
    expect(v[62] == 1048) catch @panic("test failure");
    expect(v[63] == 1049) catch @panic("test failure");
    expect(v[64] == 1050) catch @panic("test failure");
    expect(v[65] == 1051) catch @panic("test failure");
    expect(v[66] == 1052) catch @panic("test failure");
    expect(v[67] == 1053) catch @panic("test failure");
    expect(v[68] == 1054) catch @panic("test failure");
    expect(v[69] == 1055) catch @panic("test failure");
    expect(v[70] == 1056) catch @panic("test failure");
    expect(v[71] == 1057) catch @panic("test failure");
    expect(v[72] == 1058) catch @panic("test failure");
    expect(v[73] == 1059) catch @panic("test failure");
    expect(v[74] == 1060) catch @panic("test failure");
    expect(v[75] == 1061) catch @panic("test failure");
    expect(v[76] == 1062) catch @panic("test failure");
    expect(v[77] == 1063) catch @panic("test failure");
    expect(v[78] == 1064) catch @panic("test failure");
    expect(v[79] == 1065) catch @panic("test failure");
    expect(v[80] == 1066) catch @panic("test failure");
    expect(v[81] == 1067) catch @panic("test failure");
    expect(v[82] == 1068) catch @panic("test failure");
    expect(v[83] == 1069) catch @panic("test failure");
    expect(v[84] == 1070) catch @panic("test failure");
    expect(v[85] == 1071) catch @panic("test failure");
    expect(v[86] == 1072) catch @panic("test failure");
    expect(v[87] == 1073) catch @panic("test failure");
    expect(v[88] == 1074) catch @panic("test failure");
    expect(v[89] == 1075) catch @panic("test failure");
    expect(v[90] == 1076) catch @panic("test failure");
    expect(v[91] == 1077) catch @panic("test failure");
    expect(v[92] == 1078) catch @panic("test failure");
    expect(v[93] == 1079) catch @panic("test failure");
    expect(v[94] == 1080) catch @panic("test failure");
    expect(v[95] == 1081) catch @panic("test failure");
    expect(i == 96) catch @panic("test failure");
}

extern fn c_ret_vector_96_u32() @Vector(96, u32);
extern fn c_vector_96_u32(@Vector(96, u32), usize) void;
extern fn c_test_vector_96_u32() void;

test "@Vector(96, u32)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_96_u32();
    try expect(v[0] == 1082);
    try expect(v[1] == 1083);
    try expect(v[2] == 1084);
    try expect(v[3] == 1085);
    try expect(v[4] == 1086);
    try expect(v[5] == 1087);
    try expect(v[6] == 1088);
    try expect(v[7] == 1089);
    try expect(v[8] == 1090);
    try expect(v[9] == 1091);
    try expect(v[10] == 1092);
    try expect(v[11] == 1093);
    try expect(v[12] == 1094);
    try expect(v[13] == 1095);
    try expect(v[14] == 1096);
    try expect(v[15] == 1097);
    try expect(v[16] == 1098);
    try expect(v[17] == 1099);
    try expect(v[18] == 1100);
    try expect(v[19] == 1101);
    try expect(v[20] == 1102);
    try expect(v[21] == 1103);
    try expect(v[22] == 1104);
    try expect(v[23] == 1105);
    try expect(v[24] == 1106);
    try expect(v[25] == 1107);
    try expect(v[26] == 1108);
    try expect(v[27] == 1109);
    try expect(v[28] == 1110);
    try expect(v[29] == 1111);
    try expect(v[30] == 1112);
    try expect(v[31] == 1113);
    try expect(v[32] == 1114);
    try expect(v[33] == 1115);
    try expect(v[34] == 1116);
    try expect(v[35] == 1117);
    try expect(v[36] == 1118);
    try expect(v[37] == 1119);
    try expect(v[38] == 1120);
    try expect(v[39] == 1121);
    try expect(v[40] == 1122);
    try expect(v[41] == 1123);
    try expect(v[42] == 1124);
    try expect(v[43] == 1125);
    try expect(v[44] == 1126);
    try expect(v[45] == 1127);
    try expect(v[46] == 1128);
    try expect(v[47] == 1129);
    try expect(v[48] == 1130);
    try expect(v[49] == 1131);
    try expect(v[50] == 1132);
    try expect(v[51] == 1133);
    try expect(v[52] == 1134);
    try expect(v[53] == 1135);
    try expect(v[54] == 1136);
    try expect(v[55] == 1137);
    try expect(v[56] == 1138);
    try expect(v[57] == 1139);
    try expect(v[58] == 1140);
    try expect(v[59] == 1141);
    try expect(v[60] == 1142);
    try expect(v[61] == 1143);
    try expect(v[62] == 1144);
    try expect(v[63] == 1145);
    try expect(v[64] == 1146);
    try expect(v[65] == 1147);
    try expect(v[66] == 1148);
    try expect(v[67] == 1149);
    try expect(v[68] == 1150);
    try expect(v[69] == 1151);
    try expect(v[70] == 1152);
    try expect(v[71] == 1153);
    try expect(v[72] == 1154);
    try expect(v[73] == 1155);
    try expect(v[74] == 1156);
    try expect(v[75] == 1157);
    try expect(v[76] == 1158);
    try expect(v[77] == 1159);
    try expect(v[78] == 1160);
    try expect(v[79] == 1161);
    try expect(v[80] == 1162);
    try expect(v[81] == 1163);
    try expect(v[82] == 1164);
    try expect(v[83] == 1165);
    try expect(v[84] == 1166);
    try expect(v[85] == 1167);
    try expect(v[86] == 1168);
    try expect(v[87] == 1169);
    try expect(v[88] == 1170);
    try expect(v[89] == 1171);
    try expect(v[90] == 1172);
    try expect(v[91] == 1173);
    try expect(v[92] == 1174);
    try expect(v[93] == 1175);
    try expect(v[94] == 1176);
    try expect(v[95] == 1177);
    c_vector_96_u32(.{
        1178, 1179, 1180, 1181, 1182, 1183, 1184, 1185, 1186, 1187, 1188, 1189, 1190, 1191, 1192, 1193,
        1194, 1195, 1196, 1197, 1198, 1199, 1200, 1201, 1202, 1203, 1204, 1205, 1206, 1207, 1208, 1209,
        1210, 1211, 1212, 1213, 1214, 1215, 1216, 1217, 1218, 1219, 1220, 1221, 1222, 1223, 1224, 1225,
        1226, 1227, 1228, 1229, 1230, 1231, 1232, 1233, 1234, 1235, 1236, 1237, 1238, 1239, 1240, 1241,
        1242, 1243, 1244, 1245, 1246, 1247, 1248, 1249, 1250, 1251, 1252, 1253, 1254, 1255, 1256, 1257,
        1258, 1259, 1260, 1261, 1262, 1263, 1264, 1265, 1266, 1267, 1268, 1269, 1270, 1271, 1272, 1273,
    }, 96);
    c_test_vector_96_u32();
}

export fn zig_ret_vector_128_u32() @Vector(128, u32) {
    return .{
        1274, 1275, 1276, 1277, 1278, 1279, 1280, 1281, 1282, 1283, 1284, 1285, 1286, 1287, 1288, 1289,
        1290, 1291, 1292, 1293, 1294, 1295, 1296, 1297, 1298, 1299, 1300, 1301, 1302, 1303, 1304, 1305,
        1306, 1307, 1308, 1309, 1310, 1311, 1312, 1313, 1314, 1315, 1316, 1317, 1318, 1319, 1320, 1321,
        1322, 1323, 1324, 1325, 1326, 1327, 1328, 1329, 1330, 1331, 1332, 1333, 1334, 1335, 1336, 1337,
        1338, 1339, 1340, 1341, 1342, 1343, 1344, 1345, 1346, 1347, 1348, 1349, 1350, 1351, 1352, 1353,
        1354, 1355, 1356, 1357, 1358, 1359, 1360, 1361, 1362, 1363, 1364, 1365, 1366, 1367, 1368, 1369,
        1370, 1371, 1372, 1373, 1374, 1375, 1376, 1377, 1378, 1379, 1380, 1381, 1382, 1383, 1384, 1385,
        1386, 1387, 1388, 1389, 1390, 1391, 1392, 1393, 1394, 1395, 1396, 1397, 1398, 1399, 1400, 1401,
    };
}
export fn zig_vector_128_u32(v: @Vector(128, u32), i: usize) void {
    expect(v[0] == 1402) catch @panic("test failure");
    expect(v[1] == 1403) catch @panic("test failure");
    expect(v[2] == 1404) catch @panic("test failure");
    expect(v[3] == 1405) catch @panic("test failure");
    expect(v[4] == 1406) catch @panic("test failure");
    expect(v[5] == 1407) catch @panic("test failure");
    expect(v[6] == 1408) catch @panic("test failure");
    expect(v[7] == 1409) catch @panic("test failure");
    expect(v[8] == 1410) catch @panic("test failure");
    expect(v[9] == 1411) catch @panic("test failure");
    expect(v[10] == 1412) catch @panic("test failure");
    expect(v[11] == 1413) catch @panic("test failure");
    expect(v[12] == 1414) catch @panic("test failure");
    expect(v[13] == 1415) catch @panic("test failure");
    expect(v[14] == 1416) catch @panic("test failure");
    expect(v[15] == 1417) catch @panic("test failure");
    expect(v[16] == 1418) catch @panic("test failure");
    expect(v[17] == 1419) catch @panic("test failure");
    expect(v[18] == 1420) catch @panic("test failure");
    expect(v[19] == 1421) catch @panic("test failure");
    expect(v[20] == 1422) catch @panic("test failure");
    expect(v[21] == 1423) catch @panic("test failure");
    expect(v[22] == 1424) catch @panic("test failure");
    expect(v[23] == 1425) catch @panic("test failure");
    expect(v[24] == 1426) catch @panic("test failure");
    expect(v[25] == 1427) catch @panic("test failure");
    expect(v[26] == 1428) catch @panic("test failure");
    expect(v[27] == 1429) catch @panic("test failure");
    expect(v[28] == 1430) catch @panic("test failure");
    expect(v[29] == 1431) catch @panic("test failure");
    expect(v[30] == 1432) catch @panic("test failure");
    expect(v[31] == 1433) catch @panic("test failure");
    expect(v[32] == 1434) catch @panic("test failure");
    expect(v[33] == 1435) catch @panic("test failure");
    expect(v[34] == 1436) catch @panic("test failure");
    expect(v[35] == 1437) catch @panic("test failure");
    expect(v[36] == 1438) catch @panic("test failure");
    expect(v[37] == 1439) catch @panic("test failure");
    expect(v[38] == 1440) catch @panic("test failure");
    expect(v[39] == 1441) catch @panic("test failure");
    expect(v[40] == 1442) catch @panic("test failure");
    expect(v[41] == 1443) catch @panic("test failure");
    expect(v[42] == 1444) catch @panic("test failure");
    expect(v[43] == 1445) catch @panic("test failure");
    expect(v[44] == 1446) catch @panic("test failure");
    expect(v[45] == 1447) catch @panic("test failure");
    expect(v[46] == 1448) catch @panic("test failure");
    expect(v[47] == 1449) catch @panic("test failure");
    expect(v[48] == 1450) catch @panic("test failure");
    expect(v[49] == 1451) catch @panic("test failure");
    expect(v[50] == 1452) catch @panic("test failure");
    expect(v[51] == 1453) catch @panic("test failure");
    expect(v[52] == 1454) catch @panic("test failure");
    expect(v[53] == 1455) catch @panic("test failure");
    expect(v[54] == 1456) catch @panic("test failure");
    expect(v[55] == 1457) catch @panic("test failure");
    expect(v[56] == 1458) catch @panic("test failure");
    expect(v[57] == 1459) catch @panic("test failure");
    expect(v[58] == 1460) catch @panic("test failure");
    expect(v[59] == 1461) catch @panic("test failure");
    expect(v[60] == 1462) catch @panic("test failure");
    expect(v[61] == 1463) catch @panic("test failure");
    expect(v[62] == 1464) catch @panic("test failure");
    expect(v[63] == 1465) catch @panic("test failure");
    expect(v[64] == 1466) catch @panic("test failure");
    expect(v[65] == 1467) catch @panic("test failure");
    expect(v[66] == 1468) catch @panic("test failure");
    expect(v[67] == 1469) catch @panic("test failure");
    expect(v[68] == 1470) catch @panic("test failure");
    expect(v[69] == 1471) catch @panic("test failure");
    expect(v[70] == 1472) catch @panic("test failure");
    expect(v[71] == 1473) catch @panic("test failure");
    expect(v[72] == 1474) catch @panic("test failure");
    expect(v[73] == 1475) catch @panic("test failure");
    expect(v[74] == 1476) catch @panic("test failure");
    expect(v[75] == 1477) catch @panic("test failure");
    expect(v[76] == 1478) catch @panic("test failure");
    expect(v[77] == 1479) catch @panic("test failure");
    expect(v[78] == 1480) catch @panic("test failure");
    expect(v[79] == 1481) catch @panic("test failure");
    expect(v[80] == 1482) catch @panic("test failure");
    expect(v[81] == 1483) catch @panic("test failure");
    expect(v[82] == 1484) catch @panic("test failure");
    expect(v[83] == 1485) catch @panic("test failure");
    expect(v[84] == 1486) catch @panic("test failure");
    expect(v[85] == 1487) catch @panic("test failure");
    expect(v[86] == 1488) catch @panic("test failure");
    expect(v[87] == 1489) catch @panic("test failure");
    expect(v[88] == 1490) catch @panic("test failure");
    expect(v[89] == 1491) catch @panic("test failure");
    expect(v[90] == 1492) catch @panic("test failure");
    expect(v[91] == 1493) catch @panic("test failure");
    expect(v[92] == 1494) catch @panic("test failure");
    expect(v[93] == 1495) catch @panic("test failure");
    expect(v[94] == 1496) catch @panic("test failure");
    expect(v[95] == 1497) catch @panic("test failure");
    expect(v[96] == 1498) catch @panic("test failure");
    expect(v[97] == 1499) catch @panic("test failure");
    expect(v[98] == 1500) catch @panic("test failure");
    expect(v[99] == 1501) catch @panic("test failure");
    expect(v[100] == 1502) catch @panic("test failure");
    expect(v[101] == 1503) catch @panic("test failure");
    expect(v[102] == 1504) catch @panic("test failure");
    expect(v[103] == 1505) catch @panic("test failure");
    expect(v[104] == 1506) catch @panic("test failure");
    expect(v[105] == 1507) catch @panic("test failure");
    expect(v[106] == 1508) catch @panic("test failure");
    expect(v[107] == 1509) catch @panic("test failure");
    expect(v[108] == 1510) catch @panic("test failure");
    expect(v[109] == 1511) catch @panic("test failure");
    expect(v[110] == 1512) catch @panic("test failure");
    expect(v[111] == 1513) catch @panic("test failure");
    expect(v[112] == 1514) catch @panic("test failure");
    expect(v[113] == 1515) catch @panic("test failure");
    expect(v[114] == 1516) catch @panic("test failure");
    expect(v[115] == 1517) catch @panic("test failure");
    expect(v[116] == 1518) catch @panic("test failure");
    expect(v[117] == 1519) catch @panic("test failure");
    expect(v[118] == 1520) catch @panic("test failure");
    expect(v[119] == 1521) catch @panic("test failure");
    expect(v[120] == 1522) catch @panic("test failure");
    expect(v[121] == 1523) catch @panic("test failure");
    expect(v[122] == 1524) catch @panic("test failure");
    expect(v[123] == 1525) catch @panic("test failure");
    expect(v[124] == 1526) catch @panic("test failure");
    expect(v[125] == 1527) catch @panic("test failure");
    expect(v[126] == 1528) catch @panic("test failure");
    expect(v[127] == 1529) catch @panic("test failure");
    expect(i == 128) catch @panic("test failure");
}

extern fn c_ret_vector_128_u32() @Vector(128, u32);
extern fn c_vector_128_u32(@Vector(128, u32), usize) void;
extern fn c_test_vector_128_u32() void;

test "@Vector(128, u32)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_128_u32();
    try expect(v[0] == 1530);
    try expect(v[1] == 1531);
    try expect(v[2] == 1532);
    try expect(v[3] == 1533);
    try expect(v[4] == 1534);
    try expect(v[5] == 1535);
    try expect(v[6] == 1536);
    try expect(v[7] == 1537);
    try expect(v[8] == 1538);
    try expect(v[9] == 1539);
    try expect(v[10] == 1540);
    try expect(v[11] == 1541);
    try expect(v[12] == 1542);
    try expect(v[13] == 1543);
    try expect(v[14] == 1544);
    try expect(v[15] == 1545);
    try expect(v[16] == 1546);
    try expect(v[17] == 1547);
    try expect(v[18] == 1548);
    try expect(v[19] == 1549);
    try expect(v[20] == 1550);
    try expect(v[21] == 1551);
    try expect(v[22] == 1552);
    try expect(v[23] == 1553);
    try expect(v[24] == 1554);
    try expect(v[25] == 1555);
    try expect(v[26] == 1556);
    try expect(v[27] == 1557);
    try expect(v[28] == 1558);
    try expect(v[29] == 1559);
    try expect(v[30] == 1560);
    try expect(v[31] == 1561);
    try expect(v[32] == 1562);
    try expect(v[33] == 1563);
    try expect(v[34] == 1564);
    try expect(v[35] == 1565);
    try expect(v[36] == 1566);
    try expect(v[37] == 1567);
    try expect(v[38] == 1568);
    try expect(v[39] == 1569);
    try expect(v[40] == 1570);
    try expect(v[41] == 1571);
    try expect(v[42] == 1572);
    try expect(v[43] == 1573);
    try expect(v[44] == 1574);
    try expect(v[45] == 1575);
    try expect(v[46] == 1576);
    try expect(v[47] == 1577);
    try expect(v[48] == 1578);
    try expect(v[49] == 1579);
    try expect(v[50] == 1580);
    try expect(v[51] == 1581);
    try expect(v[52] == 1582);
    try expect(v[53] == 1583);
    try expect(v[54] == 1584);
    try expect(v[55] == 1585);
    try expect(v[56] == 1586);
    try expect(v[57] == 1587);
    try expect(v[58] == 1588);
    try expect(v[59] == 1589);
    try expect(v[60] == 1590);
    try expect(v[61] == 1591);
    try expect(v[62] == 1592);
    try expect(v[63] == 1593);
    try expect(v[64] == 1594);
    try expect(v[65] == 1595);
    try expect(v[66] == 1596);
    try expect(v[67] == 1597);
    try expect(v[68] == 1598);
    try expect(v[69] == 1599);
    try expect(v[70] == 1600);
    try expect(v[71] == 1601);
    try expect(v[72] == 1602);
    try expect(v[73] == 1603);
    try expect(v[74] == 1604);
    try expect(v[75] == 1605);
    try expect(v[76] == 1606);
    try expect(v[77] == 1607);
    try expect(v[78] == 1608);
    try expect(v[79] == 1609);
    try expect(v[80] == 1610);
    try expect(v[81] == 1611);
    try expect(v[82] == 1612);
    try expect(v[83] == 1613);
    try expect(v[84] == 1614);
    try expect(v[85] == 1615);
    try expect(v[86] == 1616);
    try expect(v[87] == 1617);
    try expect(v[88] == 1618);
    try expect(v[89] == 1619);
    try expect(v[90] == 1620);
    try expect(v[91] == 1621);
    try expect(v[92] == 1622);
    try expect(v[93] == 1623);
    try expect(v[94] == 1624);
    try expect(v[95] == 1625);
    try expect(v[96] == 1626);
    try expect(v[97] == 1627);
    try expect(v[98] == 1628);
    try expect(v[99] == 1629);
    try expect(v[100] == 1630);
    try expect(v[101] == 1631);
    try expect(v[102] == 1632);
    try expect(v[103] == 1633);
    try expect(v[104] == 1634);
    try expect(v[105] == 1635);
    try expect(v[106] == 1636);
    try expect(v[107] == 1637);
    try expect(v[108] == 1638);
    try expect(v[109] == 1639);
    try expect(v[110] == 1640);
    try expect(v[111] == 1641);
    try expect(v[112] == 1642);
    try expect(v[113] == 1643);
    try expect(v[114] == 1644);
    try expect(v[115] == 1645);
    try expect(v[116] == 1646);
    try expect(v[117] == 1647);
    try expect(v[118] == 1648);
    try expect(v[119] == 1649);
    try expect(v[120] == 1650);
    try expect(v[121] == 1651);
    try expect(v[122] == 1652);
    try expect(v[123] == 1653);
    try expect(v[124] == 1654);
    try expect(v[125] == 1655);
    try expect(v[126] == 1656);
    try expect(v[127] == 1657);
    c_vector_128_u32(.{
        1658, 1659, 1660, 1661, 1662, 1663, 1664, 1665, 1666, 1667, 1668, 1669, 1670, 1671, 1672, 1673,
        1674, 1675, 1676, 1677, 1678, 1679, 1680, 1681, 1682, 1683, 1684, 1685, 1686, 1687, 1688, 1689,
        1690, 1691, 1692, 1693, 1694, 1695, 1696, 1697, 1698, 1699, 1700, 1701, 1702, 1703, 1704, 1705,
        1706, 1707, 1708, 1709, 1710, 1711, 1712, 1713, 1714, 1715, 1716, 1717, 1718, 1719, 1720, 1721,
        1722, 1723, 1724, 1725, 1726, 1727, 1728, 1729, 1730, 1731, 1732, 1733, 1734, 1735, 1736, 1737,
        1738, 1739, 1740, 1741, 1742, 1743, 1744, 1745, 1746, 1747, 1748, 1749, 1750, 1751, 1752, 1753,
        1754, 1755, 1756, 1757, 1758, 1759, 1760, 1761, 1762, 1763, 1764, 1765, 1766, 1767, 1768, 1769,
        1770, 1771, 1772, 1773, 1774, 1775, 1776, 1777, 1778, 1779, 1780, 1781, 1782, 1783, 1784, 1785,
    }, 128);
    c_test_vector_128_u32();
}

export fn zig_ret_vector_1_u64() @Vector(1, u64) {
    return .{1};
}
export fn zig_vector_1_u64(v: @Vector(1, u64), i: usize) void {
    expect(v[0] == 2) catch @panic("test failure");
    expect(i == 1) catch @panic("test failure");
}

extern fn c_ret_vector_1_u64() @Vector(1, u64);
extern fn c_vector_1_u64(@Vector(1, u64), usize) void;
extern fn c_test_vector_1_u64() void;

test "@Vector(1, u64)" {
    if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .x86_64 and builtin.os.tag != .windows) return error.SkipZigTest;

    const v = c_ret_vector_1_u64();
    try expect(v[0] == 3);
    c_vector_1_u64(.{4}, 1);
    c_test_vector_1_u64();
}

export fn zig_ret_vector_2_u64() @Vector(2, u64) {
    return .{ 5, 6 };
}
export fn zig_vector_2_u64(v: @Vector(2, u64), i: usize) void {
    expect(v[0] == 7) catch @panic("test failure");
    expect(v[1] == 8) catch @panic("test failure");
    expect(i == 2) catch @panic("test failure");
}

extern fn c_ret_vector_2_u64() @Vector(2, u64);
extern fn c_vector_2_u64(@Vector(2, u64), usize) void;
extern fn c_test_vector_2_u64() void;

test "@Vector(2, u64)" {
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;

    const v = c_ret_vector_2_u64();
    try expect(v[0] == 9);
    try expect(v[1] == 10);
    c_vector_2_u64(.{ 11, 12 }, 2);
    c_test_vector_2_u64();
}

export fn zig_ret_vector_3_u64() @Vector(3, u64) {
    return .{ 13, 14, 15 };
}
export fn zig_vector_3_u64(v: @Vector(3, u64), i: usize) void {
    expect(v[0] == 16) catch @panic("test failure");
    expect(v[1] == 17) catch @panic("test failure");
    expect(v[2] == 18) catch @panic("test failure");
    expect(i == 3) catch @panic("test failure");
}

extern fn c_ret_vector_3_u64() @Vector(3, u64);
extern fn c_vector_3_u64(@Vector(3, u64), usize) void;
extern fn c_test_vector_3_u64() void;

test "@Vector(3, u64)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_3_u64();
    try expect(v[0] == 19);
    try expect(v[1] == 20);
    try expect(v[2] == 21);
    c_vector_3_u64(.{ 22, 23, 24 }, 3);
    c_test_vector_3_u64();
}

export fn zig_ret_vector_4_u64() @Vector(4, u64) {
    return .{ 25, 26, 27, 28 };
}
export fn zig_vector_4_u64(v: @Vector(4, u64), i: usize) void {
    expect(v[0] == 29) catch @panic("test failure");
    expect(v[1] == 30) catch @panic("test failure");
    expect(v[2] == 31) catch @panic("test failure");
    expect(v[3] == 32) catch @panic("test failure");
    expect(i == 4) catch @panic("test failure");
}

extern fn c_ret_vector_4_u64() @Vector(4, u64);
extern fn c_vector_4_u64(@Vector(4, u64), usize) void;
extern fn c_test_vector_4_u64() void;

test "@Vector(4, u64)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_4_u64();
    try expect(v[0] == 33);
    try expect(v[1] == 34);
    try expect(v[2] == 35);
    try expect(v[3] == 36);
    c_vector_4_u64(.{ 37, 38, 39, 40 }, 4);
    c_test_vector_4_u64();
}

export fn zig_ret_vector_6_u64() @Vector(6, u64) {
    return .{ 41, 42, 43, 44, 45, 46 };
}
export fn zig_vector_6_u64(v: @Vector(6, u64), i: usize) void {
    expect(v[0] == 47) catch @panic("test failure");
    expect(v[1] == 48) catch @panic("test failure");
    expect(v[2] == 49) catch @panic("test failure");
    expect(v[3] == 50) catch @panic("test failure");
    expect(v[4] == 51) catch @panic("test failure");
    expect(v[5] == 52) catch @panic("test failure");
    expect(i == 6) catch @panic("test failure");
}

extern fn c_ret_vector_6_u64() @Vector(6, u64);
extern fn c_vector_6_u64(@Vector(6, u64), usize) void;
extern fn c_test_vector_6_u64() void;

test "@Vector(6, u64)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;

    const v = c_ret_vector_6_u64();
    try expect(v[0] == 53);
    try expect(v[1] == 54);
    try expect(v[2] == 55);
    try expect(v[3] == 56);
    try expect(v[4] == 57);
    try expect(v[5] == 58);
    c_vector_6_u64(.{ 59, 60, 61, 62, 63, 64 }, 6);
    c_test_vector_6_u64();
}

export fn zig_ret_vector_8_u64() @Vector(8, u64) {
    return .{ 65, 66, 67, 68, 69, 70, 71, 72 };
}
export fn zig_vector_8_u64(v: @Vector(8, u64), i: usize) void {
    expect(v[0] == 73) catch @panic("test failure");
    expect(v[1] == 74) catch @panic("test failure");
    expect(v[2] == 75) catch @panic("test failure");
    expect(v[3] == 76) catch @panic("test failure");
    expect(v[4] == 77) catch @panic("test failure");
    expect(v[5] == 78) catch @panic("test failure");
    expect(v[6] == 79) catch @panic("test failure");
    expect(v[7] == 80) catch @panic("test failure");
    expect(i == 8) catch @panic("test failure");
}

extern fn c_ret_vector_8_u64() @Vector(8, u64);
extern fn c_vector_8_u64(@Vector(8, u64), usize) void;
extern fn c_test_vector_8_u64() void;

test "@Vector(8, u64)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_8_u64();
    try expect(v[0] == 81);
    try expect(v[1] == 82);
    try expect(v[2] == 83);
    try expect(v[3] == 84);
    try expect(v[4] == 85);
    try expect(v[5] == 86);
    try expect(v[6] == 87);
    try expect(v[7] == 88);
    c_vector_8_u64(.{ 89, 90, 91, 92, 93, 94, 95, 96 }, 8);
    c_test_vector_8_u64();
}

export fn zig_ret_vector_12_u64() @Vector(12, u64) {
    return .{ 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108 };
}
export fn zig_vector_12_u64(v: @Vector(12, u64), i: usize) void {
    expect(v[0] == 109) catch @panic("test failure");
    expect(v[1] == 110) catch @panic("test failure");
    expect(v[2] == 111) catch @panic("test failure");
    expect(v[3] == 112) catch @panic("test failure");
    expect(v[4] == 113) catch @panic("test failure");
    expect(v[5] == 114) catch @panic("test failure");
    expect(v[6] == 115) catch @panic("test failure");
    expect(v[7] == 116) catch @panic("test failure");
    expect(v[8] == 117) catch @panic("test failure");
    expect(v[9] == 118) catch @panic("test failure");
    expect(v[10] == 119) catch @panic("test failure");
    expect(v[11] == 120) catch @panic("test failure");
    expect(i == 12) catch @panic("test failure");
}

extern fn c_ret_vector_12_u64() @Vector(12, u64);
extern fn c_vector_12_u64(@Vector(12, u64), usize) void;
extern fn c_test_vector_12_u64() void;

test "@Vector(12, u64)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;

    const v = c_ret_vector_12_u64();
    try expect(v[0] == 121);
    try expect(v[1] == 122);
    try expect(v[2] == 123);
    try expect(v[3] == 124);
    try expect(v[4] == 125);
    try expect(v[5] == 126);
    try expect(v[6] == 127);
    try expect(v[7] == 128);
    try expect(v[8] == 129);
    try expect(v[9] == 130);
    try expect(v[10] == 131);
    try expect(v[11] == 132);
    c_vector_12_u64(.{ 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144 }, 12);
    c_test_vector_12_u64();
}

export fn zig_ret_vector_16_u64() @Vector(16, u64) {
    return .{ 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160 };
}
export fn zig_vector_16_u64(v: @Vector(16, u64), i: usize) void {
    expect(v[0] == 161) catch @panic("test failure");
    expect(v[1] == 162) catch @panic("test failure");
    expect(v[2] == 163) catch @panic("test failure");
    expect(v[3] == 164) catch @panic("test failure");
    expect(v[4] == 165) catch @panic("test failure");
    expect(v[5] == 166) catch @panic("test failure");
    expect(v[6] == 167) catch @panic("test failure");
    expect(v[7] == 168) catch @panic("test failure");
    expect(v[8] == 169) catch @panic("test failure");
    expect(v[9] == 170) catch @panic("test failure");
    expect(v[10] == 171) catch @panic("test failure");
    expect(v[11] == 172) catch @panic("test failure");
    expect(v[12] == 173) catch @panic("test failure");
    expect(v[13] == 174) catch @panic("test failure");
    expect(v[14] == 175) catch @panic("test failure");
    expect(v[15] == 176) catch @panic("test failure");
    expect(i == 16) catch @panic("test failure");
}

extern fn c_ret_vector_16_u64() @Vector(16, u64);
extern fn c_vector_16_u64(@Vector(16, u64), usize) void;
extern fn c_test_vector_16_u64() void;

test "@Vector(16, u64)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_16_u64();
    try expect(v[0] == 177);
    try expect(v[1] == 178);
    try expect(v[2] == 179);
    try expect(v[3] == 180);
    try expect(v[4] == 181);
    try expect(v[5] == 182);
    try expect(v[6] == 183);
    try expect(v[7] == 184);
    try expect(v[8] == 185);
    try expect(v[9] == 186);
    try expect(v[10] == 187);
    try expect(v[11] == 188);
    try expect(v[12] == 189);
    try expect(v[13] == 190);
    try expect(v[14] == 191);
    try expect(v[15] == 192);
    c_vector_16_u64(.{ 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208 }, 16);
    c_test_vector_16_u64();
}

export fn zig_ret_vector_24_u64() @Vector(24, u64) {
    return .{
        209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224,
        225, 226, 227, 228, 229, 230, 231, 232,
    };
}
export fn zig_vector_24_u64(v: @Vector(24, u64), i: usize) void {
    expect(v[0] == 233) catch @panic("test failure");
    expect(v[1] == 234) catch @panic("test failure");
    expect(v[2] == 235) catch @panic("test failure");
    expect(v[3] == 236) catch @panic("test failure");
    expect(v[4] == 237) catch @panic("test failure");
    expect(v[5] == 238) catch @panic("test failure");
    expect(v[6] == 239) catch @panic("test failure");
    expect(v[7] == 240) catch @panic("test failure");
    expect(v[8] == 241) catch @panic("test failure");
    expect(v[9] == 242) catch @panic("test failure");
    expect(v[10] == 243) catch @panic("test failure");
    expect(v[11] == 244) catch @panic("test failure");
    expect(v[12] == 245) catch @panic("test failure");
    expect(v[13] == 246) catch @panic("test failure");
    expect(v[14] == 247) catch @panic("test failure");
    expect(v[15] == 248) catch @panic("test failure");
    expect(v[16] == 249) catch @panic("test failure");
    expect(v[17] == 250) catch @panic("test failure");
    expect(v[18] == 251) catch @panic("test failure");
    expect(v[19] == 252) catch @panic("test failure");
    expect(v[20] == 253) catch @panic("test failure");
    expect(v[21] == 254) catch @panic("test failure");
    expect(v[22] == 255) catch @panic("test failure");
    expect(v[23] == 256) catch @panic("test failure");
    expect(i == 24) catch @panic("test failure");
}

extern fn c_ret_vector_24_u64() @Vector(24, u64);
extern fn c_vector_24_u64(@Vector(24, u64), usize) void;
extern fn c_test_vector_24_u64() void;

test "@Vector(24, u64)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;

    const v = c_ret_vector_24_u64();
    try expect(v[0] == 257);
    try expect(v[1] == 258);
    try expect(v[2] == 259);
    try expect(v[3] == 260);
    try expect(v[4] == 261);
    try expect(v[5] == 262);
    try expect(v[6] == 263);
    try expect(v[7] == 264);
    try expect(v[8] == 265);
    try expect(v[9] == 266);
    try expect(v[10] == 267);
    try expect(v[11] == 268);
    try expect(v[12] == 269);
    try expect(v[13] == 270);
    try expect(v[14] == 271);
    try expect(v[15] == 272);
    try expect(v[16] == 273);
    try expect(v[17] == 274);
    try expect(v[18] == 275);
    try expect(v[19] == 276);
    try expect(v[20] == 277);
    try expect(v[21] == 278);
    try expect(v[22] == 279);
    try expect(v[23] == 280);
    c_vector_24_u64(.{
        281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296,
        297, 298, 299, 300, 301, 302, 303, 304,
    }, 24);
    c_test_vector_24_u64();
}

export fn zig_ret_vector_32_u64() @Vector(32, u64) {
    return .{
        305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320,
        321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336,
    };
}
export fn zig_vector_32_u64(v: @Vector(32, u64), i: usize) void {
    expect(v[0] == 337) catch @panic("test failure");
    expect(v[1] == 338) catch @panic("test failure");
    expect(v[2] == 339) catch @panic("test failure");
    expect(v[3] == 340) catch @panic("test failure");
    expect(v[4] == 341) catch @panic("test failure");
    expect(v[5] == 342) catch @panic("test failure");
    expect(v[6] == 343) catch @panic("test failure");
    expect(v[7] == 344) catch @panic("test failure");
    expect(v[8] == 345) catch @panic("test failure");
    expect(v[9] == 346) catch @panic("test failure");
    expect(v[10] == 347) catch @panic("test failure");
    expect(v[11] == 348) catch @panic("test failure");
    expect(v[12] == 349) catch @panic("test failure");
    expect(v[13] == 350) catch @panic("test failure");
    expect(v[14] == 351) catch @panic("test failure");
    expect(v[15] == 352) catch @panic("test failure");
    expect(v[16] == 353) catch @panic("test failure");
    expect(v[17] == 354) catch @panic("test failure");
    expect(v[18] == 355) catch @panic("test failure");
    expect(v[19] == 356) catch @panic("test failure");
    expect(v[20] == 357) catch @panic("test failure");
    expect(v[21] == 358) catch @panic("test failure");
    expect(v[22] == 359) catch @panic("test failure");
    expect(v[23] == 360) catch @panic("test failure");
    expect(v[24] == 361) catch @panic("test failure");
    expect(v[25] == 362) catch @panic("test failure");
    expect(v[26] == 363) catch @panic("test failure");
    expect(v[27] == 364) catch @panic("test failure");
    expect(v[28] == 365) catch @panic("test failure");
    expect(v[29] == 366) catch @panic("test failure");
    expect(v[30] == 367) catch @panic("test failure");
    expect(v[31] == 368) catch @panic("test failure");
    expect(i == 32) catch @panic("test failure");
}

extern fn c_ret_vector_32_u64() @Vector(32, u64);
extern fn c_vector_32_u64(@Vector(32, u64), usize) void;
extern fn c_test_vector_32_u64() void;

test "@Vector(32, u64)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_32_u64();
    try expect(v[0] == 369);
    try expect(v[1] == 370);
    try expect(v[2] == 371);
    try expect(v[3] == 372);
    try expect(v[4] == 373);
    try expect(v[5] == 374);
    try expect(v[6] == 375);
    try expect(v[7] == 376);
    try expect(v[8] == 377);
    try expect(v[9] == 378);
    try expect(v[10] == 379);
    try expect(v[11] == 380);
    try expect(v[12] == 381);
    try expect(v[13] == 382);
    try expect(v[14] == 383);
    try expect(v[15] == 384);
    try expect(v[16] == 385);
    try expect(v[17] == 386);
    try expect(v[18] == 387);
    try expect(v[19] == 388);
    try expect(v[20] == 389);
    try expect(v[21] == 390);
    try expect(v[22] == 391);
    try expect(v[23] == 392);
    try expect(v[24] == 393);
    try expect(v[25] == 394);
    try expect(v[26] == 395);
    try expect(v[27] == 396);
    try expect(v[28] == 397);
    try expect(v[29] == 398);
    try expect(v[30] == 399);
    try expect(v[31] == 400);
    c_vector_32_u64(.{
        401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416,
        417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, 431, 432,
    }, 32);
    c_test_vector_32_u64();
}

export fn zig_ret_vector_48_u64() @Vector(48, u64) {
    return .{
        433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 443, 444, 445, 446, 447, 448,
        449, 450, 451, 452, 453, 454, 455, 456, 457, 458, 459, 460, 461, 462, 463, 464,
        465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480,
    };
}
export fn zig_vector_48_u64(v: @Vector(48, u64), i: usize) void {
    expect(v[0] == 481) catch @panic("test failure");
    expect(v[1] == 482) catch @panic("test failure");
    expect(v[2] == 483) catch @panic("test failure");
    expect(v[3] == 484) catch @panic("test failure");
    expect(v[4] == 485) catch @panic("test failure");
    expect(v[5] == 486) catch @panic("test failure");
    expect(v[6] == 487) catch @panic("test failure");
    expect(v[7] == 488) catch @panic("test failure");
    expect(v[8] == 489) catch @panic("test failure");
    expect(v[9] == 490) catch @panic("test failure");
    expect(v[10] == 491) catch @panic("test failure");
    expect(v[11] == 492) catch @panic("test failure");
    expect(v[12] == 493) catch @panic("test failure");
    expect(v[13] == 494) catch @panic("test failure");
    expect(v[14] == 495) catch @panic("test failure");
    expect(v[15] == 496) catch @panic("test failure");
    expect(v[16] == 497) catch @panic("test failure");
    expect(v[17] == 498) catch @panic("test failure");
    expect(v[18] == 499) catch @panic("test failure");
    expect(v[19] == 500) catch @panic("test failure");
    expect(v[20] == 501) catch @panic("test failure");
    expect(v[21] == 502) catch @panic("test failure");
    expect(v[22] == 503) catch @panic("test failure");
    expect(v[23] == 504) catch @panic("test failure");
    expect(v[24] == 505) catch @panic("test failure");
    expect(v[25] == 506) catch @panic("test failure");
    expect(v[26] == 507) catch @panic("test failure");
    expect(v[27] == 508) catch @panic("test failure");
    expect(v[28] == 509) catch @panic("test failure");
    expect(v[29] == 510) catch @panic("test failure");
    expect(v[30] == 511) catch @panic("test failure");
    expect(v[31] == 512) catch @panic("test failure");
    expect(v[32] == 513) catch @panic("test failure");
    expect(v[33] == 514) catch @panic("test failure");
    expect(v[34] == 515) catch @panic("test failure");
    expect(v[35] == 516) catch @panic("test failure");
    expect(v[36] == 517) catch @panic("test failure");
    expect(v[37] == 518) catch @panic("test failure");
    expect(v[38] == 519) catch @panic("test failure");
    expect(v[39] == 520) catch @panic("test failure");
    expect(v[40] == 521) catch @panic("test failure");
    expect(v[41] == 522) catch @panic("test failure");
    expect(v[42] == 523) catch @panic("test failure");
    expect(v[43] == 524) catch @panic("test failure");
    expect(v[44] == 525) catch @panic("test failure");
    expect(v[45] == 526) catch @panic("test failure");
    expect(v[46] == 527) catch @panic("test failure");
    expect(v[47] == 528) catch @panic("test failure");
    expect(i == 48) catch @panic("test failure");
}

extern fn c_ret_vector_48_u64() @Vector(48, u64);
extern fn c_vector_48_u64(@Vector(48, u64), usize) void;
extern fn c_test_vector_48_u64() void;

test "@Vector(48, u64)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;

    const v = c_ret_vector_48_u64();
    try expect(v[0] == 529);
    try expect(v[1] == 530);
    try expect(v[2] == 531);
    try expect(v[3] == 532);
    try expect(v[4] == 533);
    try expect(v[5] == 534);
    try expect(v[6] == 535);
    try expect(v[7] == 536);
    try expect(v[8] == 537);
    try expect(v[9] == 538);
    try expect(v[10] == 539);
    try expect(v[11] == 540);
    try expect(v[12] == 541);
    try expect(v[13] == 542);
    try expect(v[14] == 543);
    try expect(v[15] == 544);
    try expect(v[16] == 545);
    try expect(v[17] == 546);
    try expect(v[18] == 547);
    try expect(v[19] == 548);
    try expect(v[20] == 549);
    try expect(v[21] == 550);
    try expect(v[22] == 551);
    try expect(v[23] == 552);
    try expect(v[24] == 553);
    try expect(v[25] == 554);
    try expect(v[26] == 555);
    try expect(v[27] == 556);
    try expect(v[28] == 557);
    try expect(v[29] == 558);
    try expect(v[30] == 559);
    try expect(v[31] == 560);
    try expect(v[32] == 561);
    try expect(v[33] == 562);
    try expect(v[34] == 563);
    try expect(v[35] == 564);
    try expect(v[36] == 565);
    try expect(v[37] == 566);
    try expect(v[38] == 567);
    try expect(v[39] == 568);
    try expect(v[40] == 569);
    try expect(v[41] == 570);
    try expect(v[42] == 571);
    try expect(v[43] == 572);
    try expect(v[44] == 573);
    try expect(v[45] == 574);
    try expect(v[46] == 575);
    try expect(v[47] == 576);
    c_vector_48_u64(.{
        577, 578, 579, 580, 581, 582, 583, 584, 585, 586, 587, 588, 589, 590, 591, 592,
        593, 594, 595, 596, 597, 598, 599, 600, 601, 602, 603, 604, 605, 606, 607, 608,
        609, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621, 622, 623, 624,
    }, 48);
    c_test_vector_48_u64();
}

export fn zig_ret_vector_64_u64() @Vector(64, u64) {
    return .{
        625, 626, 627, 628, 629, 630, 631, 632, 633, 634, 635, 636, 637, 638, 639, 640,
        641, 642, 643, 644, 645, 646, 647, 648, 649, 650, 651, 652, 653, 654, 655, 656,
        657, 658, 659, 660, 661, 662, 663, 664, 665, 666, 667, 668, 669, 670, 671, 672,
        673, 674, 675, 676, 677, 678, 679, 680, 681, 682, 683, 684, 685, 686, 687, 688,
    };
}
export fn zig_vector_64_u64(v: @Vector(64, u64), i: usize) void {
    expect(v[0] == 689) catch @panic("test failure");
    expect(v[1] == 690) catch @panic("test failure");
    expect(v[2] == 691) catch @panic("test failure");
    expect(v[3] == 692) catch @panic("test failure");
    expect(v[4] == 693) catch @panic("test failure");
    expect(v[5] == 694) catch @panic("test failure");
    expect(v[6] == 695) catch @panic("test failure");
    expect(v[7] == 696) catch @panic("test failure");
    expect(v[8] == 697) catch @panic("test failure");
    expect(v[9] == 698) catch @panic("test failure");
    expect(v[10] == 699) catch @panic("test failure");
    expect(v[11] == 700) catch @panic("test failure");
    expect(v[12] == 701) catch @panic("test failure");
    expect(v[13] == 702) catch @panic("test failure");
    expect(v[14] == 703) catch @panic("test failure");
    expect(v[15] == 704) catch @panic("test failure");
    expect(v[16] == 705) catch @panic("test failure");
    expect(v[17] == 706) catch @panic("test failure");
    expect(v[18] == 707) catch @panic("test failure");
    expect(v[19] == 708) catch @panic("test failure");
    expect(v[20] == 709) catch @panic("test failure");
    expect(v[21] == 710) catch @panic("test failure");
    expect(v[22] == 711) catch @panic("test failure");
    expect(v[23] == 712) catch @panic("test failure");
    expect(v[24] == 713) catch @panic("test failure");
    expect(v[25] == 714) catch @panic("test failure");
    expect(v[26] == 715) catch @panic("test failure");
    expect(v[27] == 716) catch @panic("test failure");
    expect(v[28] == 717) catch @panic("test failure");
    expect(v[29] == 718) catch @panic("test failure");
    expect(v[30] == 719) catch @panic("test failure");
    expect(v[31] == 720) catch @panic("test failure");
    expect(v[32] == 721) catch @panic("test failure");
    expect(v[33] == 722) catch @panic("test failure");
    expect(v[34] == 723) catch @panic("test failure");
    expect(v[35] == 724) catch @panic("test failure");
    expect(v[36] == 725) catch @panic("test failure");
    expect(v[37] == 726) catch @panic("test failure");
    expect(v[38] == 727) catch @panic("test failure");
    expect(v[39] == 728) catch @panic("test failure");
    expect(v[40] == 729) catch @panic("test failure");
    expect(v[41] == 730) catch @panic("test failure");
    expect(v[42] == 731) catch @panic("test failure");
    expect(v[43] == 732) catch @panic("test failure");
    expect(v[44] == 733) catch @panic("test failure");
    expect(v[45] == 734) catch @panic("test failure");
    expect(v[46] == 735) catch @panic("test failure");
    expect(v[47] == 736) catch @panic("test failure");
    expect(v[48] == 737) catch @panic("test failure");
    expect(v[49] == 738) catch @panic("test failure");
    expect(v[50] == 739) catch @panic("test failure");
    expect(v[51] == 740) catch @panic("test failure");
    expect(v[52] == 741) catch @panic("test failure");
    expect(v[53] == 742) catch @panic("test failure");
    expect(v[54] == 743) catch @panic("test failure");
    expect(v[55] == 744) catch @panic("test failure");
    expect(v[56] == 745) catch @panic("test failure");
    expect(v[57] == 746) catch @panic("test failure");
    expect(v[58] == 747) catch @panic("test failure");
    expect(v[59] == 748) catch @panic("test failure");
    expect(v[60] == 749) catch @panic("test failure");
    expect(v[61] == 750) catch @panic("test failure");
    expect(v[62] == 751) catch @panic("test failure");
    expect(v[63] == 752) catch @panic("test failure");
    expect(i == 64) catch @panic("test failure");
}

extern fn c_ret_vector_64_u64() @Vector(64, u64);
extern fn c_vector_64_u64(@Vector(64, u64), usize) void;
extern fn c_test_vector_64_u64() void;

test "@Vector(64, u64)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_64_u64();
    try expect(v[0] == 753);
    try expect(v[1] == 754);
    try expect(v[2] == 755);
    try expect(v[3] == 756);
    try expect(v[4] == 757);
    try expect(v[5] == 758);
    try expect(v[6] == 759);
    try expect(v[7] == 760);
    try expect(v[8] == 761);
    try expect(v[9] == 762);
    try expect(v[10] == 763);
    try expect(v[11] == 764);
    try expect(v[12] == 765);
    try expect(v[13] == 766);
    try expect(v[14] == 767);
    try expect(v[15] == 768);
    try expect(v[16] == 769);
    try expect(v[17] == 770);
    try expect(v[18] == 771);
    try expect(v[19] == 772);
    try expect(v[20] == 773);
    try expect(v[21] == 774);
    try expect(v[22] == 775);
    try expect(v[23] == 776);
    try expect(v[24] == 777);
    try expect(v[25] == 778);
    try expect(v[26] == 779);
    try expect(v[27] == 780);
    try expect(v[28] == 781);
    try expect(v[29] == 782);
    try expect(v[30] == 783);
    try expect(v[31] == 784);
    try expect(v[32] == 785);
    try expect(v[33] == 786);
    try expect(v[34] == 787);
    try expect(v[35] == 788);
    try expect(v[36] == 789);
    try expect(v[37] == 790);
    try expect(v[38] == 791);
    try expect(v[39] == 792);
    try expect(v[40] == 793);
    try expect(v[41] == 794);
    try expect(v[42] == 795);
    try expect(v[43] == 796);
    try expect(v[44] == 797);
    try expect(v[45] == 798);
    try expect(v[46] == 799);
    try expect(v[47] == 800);
    try expect(v[48] == 801);
    try expect(v[49] == 802);
    try expect(v[50] == 803);
    try expect(v[51] == 804);
    try expect(v[52] == 805);
    try expect(v[53] == 806);
    try expect(v[54] == 807);
    try expect(v[55] == 808);
    try expect(v[56] == 809);
    try expect(v[57] == 810);
    try expect(v[58] == 811);
    try expect(v[59] == 812);
    try expect(v[60] == 813);
    try expect(v[61] == 814);
    try expect(v[62] == 815);
    try expect(v[63] == 816);
    c_vector_64_u64(.{
        817, 818, 819, 820, 821, 822, 823, 824, 825, 826, 827, 828, 829, 830, 831, 832,
        833, 834, 835, 836, 837, 838, 839, 840, 841, 842, 843, 844, 845, 846, 847, 848,
        849, 850, 851, 852, 853, 854, 855, 856, 857, 858, 859, 860, 861, 862, 863, 864,
        865, 866, 867, 868, 869, 870, 871, 872, 873, 874, 875, 876, 877, 878, 879, 880,
    }, 64);
    c_test_vector_64_u64();
}

export fn zig_ret_vector_1_f32() @Vector(1, f32) {
    return .{1};
}
export fn zig_vector_1_f32(v: @Vector(1, f32), i: usize) void {
    expect(v[0] == 2) catch @panic("test failure");
    expect(i == 1) catch @panic("test failure");
}

extern fn c_ret_vector_1_f32() @Vector(1, f32);
extern fn c_vector_1_f32(@Vector(1, f32), usize) void;
extern fn c_test_vector_1_f32() void;

test "@Vector(1, f32)" {
    if (builtin.cpu.arch.isAARCH64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .x86_64 and builtin.os.tag != .windows) return error.SkipZigTest;

    const v = c_ret_vector_1_f32();
    try expect(v[0] == 3);
    c_vector_1_f32(.{4}, 1);
    c_test_vector_1_f32();
}

export fn zig_ret_vector_2_f32() @Vector(2, f32) {
    return .{ 5, 6 };
}
export fn zig_vector_2_f32(v: @Vector(2, f32), i: usize) void {
    expect(v[0] == 7) catch @panic("test failure");
    expect(v[1] == 8) catch @panic("test failure");
    expect(i == 2) catch @panic("test failure");
}

extern fn c_ret_vector_2_f32() @Vector(2, f32);
extern fn c_vector_2_f32(@Vector(2, f32), usize) void;
extern fn c_test_vector_2_f32() void;

test "@Vector(2, f32)" {
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .x86_64 and builtin.os.tag == .windows) return error.SkipZigTest;

    const v = c_ret_vector_2_f32();
    try expect(v[0] == 9);
    try expect(v[1] == 10);
    c_vector_2_f32(.{ 11, 12 }, 2);
    c_test_vector_2_f32();
}

export fn zig_ret_vector_3_f32() @Vector(3, f32) {
    return .{ 13, 14, 15 };
}
export fn zig_vector_3_f32(v: @Vector(3, f32), i: usize) void {
    expect(v[0] == 16) catch @panic("test failure");
    expect(v[1] == 17) catch @panic("test failure");
    expect(v[2] == 18) catch @panic("test failure");
    expect(i == 3) catch @panic("test failure");
}

extern fn c_ret_vector_3_f32() @Vector(3, f32);
extern fn c_vector_3_f32(@Vector(3, f32), usize) void;
extern fn c_test_vector_3_f32() void;

test "@Vector(3, f32)" {
    if (builtin.cpu.arch.isArm() and builtin.abi.float() == .soft) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;

    const v = c_ret_vector_3_f32();
    try expect(v[0] == 19);
    try expect(v[1] == 20);
    try expect(v[2] == 21);
    c_vector_3_f32(.{ 22, 23, 24 }, 32);
    c_test_vector_3_f32();
}

export fn zig_ret_vector_4_f32() @Vector(4, f32) {
    return .{ 25, 26, 27, 28 };
}
export fn zig_vector_4_f32(v: @Vector(4, f32), i: usize) void {
    expect(v[0] == 29) catch @panic("test failure");
    expect(v[1] == 30) catch @panic("test failure");
    expect(v[2] == 31) catch @panic("test failure");
    expect(v[3] == 32) catch @panic("test failure");
    expect(i == 4) catch @panic("test failure");
}
export fn zig_vector_4_f32_vector_4_f32(v0: @Vector(4, f32), v1: @Vector(4, f32), i: usize) void {
    expect(v0[0] == 33) catch @panic("test failure");
    expect(v0[1] == 34) catch @panic("test failure");
    expect(v0[2] == 35) catch @panic("test failure");
    expect(v0[3] == 36) catch @panic("test failure");
    expect(v1[0] == 37) catch @panic("test failure");
    expect(v1[1] == 38) catch @panic("test failure");
    expect(v1[2] == 39) catch @panic("test failure");
    expect(v1[3] == 40) catch @panic("test failure");
    expect(i == 8) catch @panic("test failure");
}
extern fn c_ret_vector_4_f32() @Vector(4, f32);

extern fn c_vector_4_f32(@Vector(4, f32), usize) void;
extern fn c_vector_4_f32_vector_4_f32(@Vector(4, f32), @Vector(4, f32), usize) void;
extern fn c_test_vector_4_f32() void;

test "@Vector(4, f32)" {
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;

    const v = c_ret_vector_4_f32();
    try expect(v[0] == 41);
    try expect(v[1] == 42);
    try expect(v[2] == 43);
    try expect(v[3] == 44);
    c_vector_4_f32(.{ 45, 46, 47, 48 }, 4);
    c_vector_4_f32_vector_4_f32(.{ 49, 50, 51, 52 }, .{ 53, 54, 55, 56 }, 8);
    c_test_vector_4_f32();
}

export fn zig_ret_vector_6_f32() @Vector(6, f32) {
    return .{ 41, 42, 43, 44, 45, 46 };
}
export fn zig_vector_6_f32(v: @Vector(6, f32), i: usize) void {
    expect(v[0] == 47) catch @panic("test failure");
    expect(v[1] == 48) catch @panic("test failure");
    expect(v[2] == 49) catch @panic("test failure");
    expect(v[3] == 50) catch @panic("test failure");
    expect(v[4] == 51) catch @panic("test failure");
    expect(v[5] == 52) catch @panic("test failure");
    expect(i == 6) catch @panic("test failure");
}

extern fn c_ret_vector_6_f32() @Vector(6, f32);
extern fn c_vector_6_f32(@Vector(6, f32), usize) void;
extern fn c_test_vector_6_f32() void;

test "@Vector(6, f32)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_6_f32();
    try expect(v[0] == 53);
    try expect(v[1] == 54);
    try expect(v[2] == 55);
    try expect(v[3] == 56);
    try expect(v[4] == 57);
    try expect(v[5] == 58);
    c_vector_6_f32(.{ 59, 60, 61, 62, 63, 64 }, 6);
    c_test_vector_6_f32();
}

export fn zig_ret_vector_8_f32() @Vector(8, f32) {
    return .{ 65, 66, 67, 68, 69, 70, 71, 72 };
}
export fn zig_vector_8_f32(v: @Vector(8, f32), i: usize) void {
    expect(v[0] == 73) catch @panic("test failure");
    expect(v[1] == 74) catch @panic("test failure");
    expect(v[2] == 75) catch @panic("test failure");
    expect(v[3] == 76) catch @panic("test failure");
    expect(v[4] == 77) catch @panic("test failure");
    expect(v[5] == 78) catch @panic("test failure");
    expect(v[6] == 79) catch @panic("test failure");
    expect(v[7] == 80) catch @panic("test failure");
    expect(i == 8) catch @panic("test failure");
}

extern fn c_ret_vector_8_f32() @Vector(8, f32);
extern fn c_vector_8_f32(@Vector(8, f32), usize) void;
extern fn c_test_vector_8_f32() void;

test "@Vector(8, f32)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_8_f32();
    try expect(v[0] == 81);
    try expect(v[1] == 82);
    try expect(v[2] == 83);
    try expect(v[3] == 84);
    try expect(v[4] == 85);
    try expect(v[5] == 86);
    try expect(v[6] == 87);
    try expect(v[7] == 88);
    c_vector_8_f32(.{ 89, 90, 91, 92, 93, 94, 95, 96 }, 8);
    c_test_vector_8_f32();
}

export fn zig_ret_vector_12_f32() @Vector(12, f32) {
    return .{ 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108 };
}
export fn zig_vector_12_f32(v: @Vector(12, f32), i: usize) void {
    expect(v[0] == 109) catch @panic("test failure");
    expect(v[1] == 110) catch @panic("test failure");
    expect(v[2] == 111) catch @panic("test failure");
    expect(v[3] == 112) catch @panic("test failure");
    expect(v[4] == 113) catch @panic("test failure");
    expect(v[5] == 114) catch @panic("test failure");
    expect(v[6] == 115) catch @panic("test failure");
    expect(v[7] == 116) catch @panic("test failure");
    expect(v[8] == 117) catch @panic("test failure");
    expect(v[9] == 118) catch @panic("test failure");
    expect(v[10] == 119) catch @panic("test failure");
    expect(v[11] == 120) catch @panic("test failure");
    expect(i == 12) catch @panic("test failure");
}

extern fn c_ret_vector_12_f32() @Vector(12, f32);
extern fn c_vector_12_f32(@Vector(12, f32), usize) void;
extern fn c_test_vector_12_f32() void;

test "@Vector(12, f32)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_12_f32();
    try expect(v[0] == 121);
    try expect(v[1] == 122);
    try expect(v[2] == 123);
    try expect(v[3] == 124);
    try expect(v[4] == 125);
    try expect(v[5] == 126);
    try expect(v[6] == 127);
    try expect(v[7] == 128);
    try expect(v[8] == 129);
    try expect(v[9] == 130);
    try expect(v[10] == 131);
    try expect(v[11] == 132);
    c_vector_12_f32(.{ 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144 }, 12);
    c_test_vector_12_f32();
}

export fn zig_ret_vector_16_f32() @Vector(16, f32) {
    return .{ 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160 };
}
export fn zig_vector_16_f32(v: @Vector(16, f32), i: usize) void {
    expect(v[0] == 161) catch @panic("test failure");
    expect(v[1] == 162) catch @panic("test failure");
    expect(v[2] == 163) catch @panic("test failure");
    expect(v[3] == 164) catch @panic("test failure");
    expect(v[4] == 165) catch @panic("test failure");
    expect(v[5] == 166) catch @panic("test failure");
    expect(v[6] == 167) catch @panic("test failure");
    expect(v[7] == 168) catch @panic("test failure");
    expect(v[8] == 169) catch @panic("test failure");
    expect(v[9] == 170) catch @panic("test failure");
    expect(v[10] == 171) catch @panic("test failure");
    expect(v[11] == 172) catch @panic("test failure");
    expect(v[12] == 173) catch @panic("test failure");
    expect(v[13] == 174) catch @panic("test failure");
    expect(v[14] == 175) catch @panic("test failure");
    expect(v[15] == 176) catch @panic("test failure");
    expect(i == 16) catch @panic("test failure");
}

extern fn c_ret_vector_16_f32() @Vector(16, f32);
extern fn c_vector_16_f32(@Vector(16, f32), usize) void;
extern fn c_test_vector_16_f32() void;

test "@Vector(16, f32)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_16_f32();
    try expect(v[0] == 177);
    try expect(v[1] == 178);
    try expect(v[2] == 179);
    try expect(v[3] == 180);
    try expect(v[4] == 181);
    try expect(v[5] == 182);
    try expect(v[6] == 183);
    try expect(v[7] == 184);
    try expect(v[8] == 185);
    try expect(v[9] == 186);
    try expect(v[10] == 187);
    try expect(v[11] == 188);
    try expect(v[12] == 189);
    try expect(v[13] == 190);
    try expect(v[14] == 191);
    try expect(v[15] == 192);
    c_vector_16_f32(.{ 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208 }, 16);
    c_test_vector_16_f32();
}

export fn zig_ret_vector_24_f32() @Vector(24, f32) {
    return .{
        209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224,
        225, 226, 227, 228, 229, 230, 231, 232,
    };
}
export fn zig_vector_24_f32(v: @Vector(24, f32), i: usize) void {
    expect(v[0] == 233) catch @panic("test failure");
    expect(v[1] == 234) catch @panic("test failure");
    expect(v[2] == 235) catch @panic("test failure");
    expect(v[3] == 236) catch @panic("test failure");
    expect(v[4] == 237) catch @panic("test failure");
    expect(v[5] == 238) catch @panic("test failure");
    expect(v[6] == 239) catch @panic("test failure");
    expect(v[7] == 240) catch @panic("test failure");
    expect(v[8] == 241) catch @panic("test failure");
    expect(v[9] == 242) catch @panic("test failure");
    expect(v[10] == 243) catch @panic("test failure");
    expect(v[11] == 244) catch @panic("test failure");
    expect(v[12] == 245) catch @panic("test failure");
    expect(v[13] == 246) catch @panic("test failure");
    expect(v[14] == 247) catch @panic("test failure");
    expect(v[15] == 248) catch @panic("test failure");
    expect(v[16] == 249) catch @panic("test failure");
    expect(v[17] == 250) catch @panic("test failure");
    expect(v[18] == 251) catch @panic("test failure");
    expect(v[19] == 252) catch @panic("test failure");
    expect(v[20] == 253) catch @panic("test failure");
    expect(v[21] == 254) catch @panic("test failure");
    expect(v[22] == 255) catch @panic("test failure");
    expect(v[23] == 256) catch @panic("test failure");
    expect(i == 24) catch @panic("test failure");
}

extern fn c_ret_vector_24_f32() @Vector(24, f32);
extern fn c_vector_24_f32(@Vector(24, f32), usize) void;
extern fn c_test_vector_24_f32() void;

test "@Vector(24, f32)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_24_f32();
    try expect(v[0] == 257);
    try expect(v[1] == 258);
    try expect(v[2] == 259);
    try expect(v[3] == 260);
    try expect(v[4] == 261);
    try expect(v[5] == 262);
    try expect(v[6] == 263);
    try expect(v[7] == 264);
    try expect(v[8] == 265);
    try expect(v[9] == 266);
    try expect(v[10] == 267);
    try expect(v[11] == 268);
    try expect(v[12] == 269);
    try expect(v[13] == 270);
    try expect(v[14] == 271);
    try expect(v[15] == 272);
    try expect(v[16] == 273);
    try expect(v[17] == 274);
    try expect(v[18] == 275);
    try expect(v[19] == 276);
    try expect(v[20] == 277);
    try expect(v[21] == 278);
    try expect(v[22] == 279);
    try expect(v[23] == 280);
    c_vector_24_f32(.{
        281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296,
        297, 298, 299, 300, 301, 302, 303, 304,
    }, 24);
    c_test_vector_24_f32();
}

export fn zig_ret_vector_32_f32() @Vector(32, f32) {
    return .{
        305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320,
        321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336,
    };
}
export fn zig_vector_32_f32(v: @Vector(32, f32), i: usize) void {
    expect(v[0] == 337) catch @panic("test failure");
    expect(v[1] == 338) catch @panic("test failure");
    expect(v[2] == 339) catch @panic("test failure");
    expect(v[3] == 340) catch @panic("test failure");
    expect(v[4] == 341) catch @panic("test failure");
    expect(v[5] == 342) catch @panic("test failure");
    expect(v[6] == 343) catch @panic("test failure");
    expect(v[7] == 344) catch @panic("test failure");
    expect(v[8] == 345) catch @panic("test failure");
    expect(v[9] == 346) catch @panic("test failure");
    expect(v[10] == 347) catch @panic("test failure");
    expect(v[11] == 348) catch @panic("test failure");
    expect(v[12] == 349) catch @panic("test failure");
    expect(v[13] == 350) catch @panic("test failure");
    expect(v[14] == 351) catch @panic("test failure");
    expect(v[15] == 352) catch @panic("test failure");
    expect(v[16] == 353) catch @panic("test failure");
    expect(v[17] == 354) catch @panic("test failure");
    expect(v[18] == 355) catch @panic("test failure");
    expect(v[19] == 356) catch @panic("test failure");
    expect(v[20] == 357) catch @panic("test failure");
    expect(v[21] == 358) catch @panic("test failure");
    expect(v[22] == 359) catch @panic("test failure");
    expect(v[23] == 360) catch @panic("test failure");
    expect(v[24] == 361) catch @panic("test failure");
    expect(v[25] == 362) catch @panic("test failure");
    expect(v[26] == 363) catch @panic("test failure");
    expect(v[27] == 364) catch @panic("test failure");
    expect(v[28] == 365) catch @panic("test failure");
    expect(v[29] == 366) catch @panic("test failure");
    expect(v[30] == 367) catch @panic("test failure");
    expect(v[31] == 368) catch @panic("test failure");
    expect(i == 32) catch @panic("test failure");
}

extern fn c_ret_vector_32_f32() @Vector(32, f32);
extern fn c_vector_32_f32(@Vector(32, f32), usize) void;
extern fn c_test_vector_32_f32() void;

test "@Vector(32, f32)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_32_f32();
    try expect(v[0] == 369);
    try expect(v[1] == 370);
    try expect(v[2] == 371);
    try expect(v[3] == 372);
    try expect(v[4] == 373);
    try expect(v[5] == 374);
    try expect(v[6] == 375);
    try expect(v[7] == 376);
    try expect(v[8] == 377);
    try expect(v[9] == 378);
    try expect(v[10] == 379);
    try expect(v[11] == 380);
    try expect(v[12] == 381);
    try expect(v[13] == 382);
    try expect(v[14] == 383);
    try expect(v[15] == 384);
    try expect(v[16] == 385);
    try expect(v[17] == 386);
    try expect(v[18] == 387);
    try expect(v[19] == 388);
    try expect(v[20] == 389);
    try expect(v[21] == 390);
    try expect(v[22] == 391);
    try expect(v[23] == 392);
    try expect(v[24] == 393);
    try expect(v[25] == 394);
    try expect(v[26] == 395);
    try expect(v[27] == 396);
    try expect(v[28] == 397);
    try expect(v[29] == 398);
    try expect(v[30] == 399);
    try expect(v[31] == 400);
    c_vector_32_f32(.{
        401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416,
        417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, 431, 432,
    }, 32);
    c_test_vector_32_f32();
}

export fn zig_ret_vector_48_f32() @Vector(48, f32) {
    return .{
        433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 443, 444, 445, 446, 447, 448,
        449, 450, 451, 452, 453, 454, 455, 456, 457, 458, 459, 460, 461, 462, 463, 464,
        465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480,
    };
}
export fn zig_vector_48_f32(v: @Vector(48, f32), i: usize) void {
    expect(v[0] == 481) catch @panic("test failure");
    expect(v[1] == 482) catch @panic("test failure");
    expect(v[2] == 483) catch @panic("test failure");
    expect(v[3] == 484) catch @panic("test failure");
    expect(v[4] == 485) catch @panic("test failure");
    expect(v[5] == 486) catch @panic("test failure");
    expect(v[6] == 487) catch @panic("test failure");
    expect(v[7] == 488) catch @panic("test failure");
    expect(v[8] == 489) catch @panic("test failure");
    expect(v[9] == 490) catch @panic("test failure");
    expect(v[10] == 491) catch @panic("test failure");
    expect(v[11] == 492) catch @panic("test failure");
    expect(v[12] == 493) catch @panic("test failure");
    expect(v[13] == 494) catch @panic("test failure");
    expect(v[14] == 495) catch @panic("test failure");
    expect(v[15] == 496) catch @panic("test failure");
    expect(v[16] == 497) catch @panic("test failure");
    expect(v[17] == 498) catch @panic("test failure");
    expect(v[18] == 499) catch @panic("test failure");
    expect(v[19] == 500) catch @panic("test failure");
    expect(v[20] == 501) catch @panic("test failure");
    expect(v[21] == 502) catch @panic("test failure");
    expect(v[22] == 503) catch @panic("test failure");
    expect(v[23] == 504) catch @panic("test failure");
    expect(v[24] == 505) catch @panic("test failure");
    expect(v[25] == 506) catch @panic("test failure");
    expect(v[26] == 507) catch @panic("test failure");
    expect(v[27] == 508) catch @panic("test failure");
    expect(v[28] == 509) catch @panic("test failure");
    expect(v[29] == 510) catch @panic("test failure");
    expect(v[30] == 511) catch @panic("test failure");
    expect(v[31] == 512) catch @panic("test failure");
    expect(v[32] == 513) catch @panic("test failure");
    expect(v[33] == 514) catch @panic("test failure");
    expect(v[34] == 515) catch @panic("test failure");
    expect(v[35] == 516) catch @panic("test failure");
    expect(v[36] == 517) catch @panic("test failure");
    expect(v[37] == 518) catch @panic("test failure");
    expect(v[38] == 519) catch @panic("test failure");
    expect(v[39] == 520) catch @panic("test failure");
    expect(v[40] == 521) catch @panic("test failure");
    expect(v[41] == 522) catch @panic("test failure");
    expect(v[42] == 523) catch @panic("test failure");
    expect(v[43] == 524) catch @panic("test failure");
    expect(v[44] == 525) catch @panic("test failure");
    expect(v[45] == 526) catch @panic("test failure");
    expect(v[46] == 527) catch @panic("test failure");
    expect(v[47] == 528) catch @panic("test failure");
    expect(i == 48) catch @panic("test failure");
}

extern fn c_ret_vector_48_f32() @Vector(48, f32);
extern fn c_vector_48_f32(@Vector(48, f32), usize) void;
extern fn c_test_vector_48_f32() void;

test "@Vector(48, f32)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_48_f32();
    try expect(v[0] == 529);
    try expect(v[1] == 530);
    try expect(v[2] == 531);
    try expect(v[3] == 532);
    try expect(v[4] == 533);
    try expect(v[5] == 534);
    try expect(v[6] == 535);
    try expect(v[7] == 536);
    try expect(v[8] == 537);
    try expect(v[9] == 538);
    try expect(v[10] == 539);
    try expect(v[11] == 540);
    try expect(v[12] == 541);
    try expect(v[13] == 542);
    try expect(v[14] == 543);
    try expect(v[15] == 544);
    try expect(v[16] == 545);
    try expect(v[17] == 546);
    try expect(v[18] == 547);
    try expect(v[19] == 548);
    try expect(v[20] == 549);
    try expect(v[21] == 550);
    try expect(v[22] == 551);
    try expect(v[23] == 552);
    try expect(v[24] == 553);
    try expect(v[25] == 554);
    try expect(v[26] == 555);
    try expect(v[27] == 556);
    try expect(v[28] == 557);
    try expect(v[29] == 558);
    try expect(v[30] == 559);
    try expect(v[31] == 560);
    try expect(v[32] == 561);
    try expect(v[33] == 562);
    try expect(v[34] == 563);
    try expect(v[35] == 564);
    try expect(v[36] == 565);
    try expect(v[37] == 566);
    try expect(v[38] == 567);
    try expect(v[39] == 568);
    try expect(v[40] == 569);
    try expect(v[41] == 570);
    try expect(v[42] == 571);
    try expect(v[43] == 572);
    try expect(v[44] == 573);
    try expect(v[45] == 574);
    try expect(v[46] == 575);
    try expect(v[47] == 576);
    c_vector_48_f32(.{
        577, 578, 579, 580, 581, 582, 583, 584, 585, 586, 587, 588, 589, 590, 591, 592,
        593, 594, 595, 596, 597, 598, 599, 600, 601, 602, 603, 604, 605, 606, 607, 608,
        609, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621, 622, 623, 624,
    }, 48);
    c_test_vector_48_f32();
}

export fn zig_ret_vector_64_f32() @Vector(64, f32) {
    return .{
        625, 626, 627, 628, 629, 630, 631, 632, 633, 634, 635, 636, 637, 638, 639, 640,
        641, 642, 643, 644, 645, 646, 647, 648, 649, 650, 651, 652, 653, 654, 655, 656,
        657, 658, 659, 660, 661, 662, 663, 664, 665, 666, 667, 668, 669, 670, 671, 672,
        673, 674, 675, 676, 677, 678, 679, 680, 681, 682, 683, 684, 685, 686, 687, 688,
    };
}
export fn zig_vector_64_f32(v: @Vector(64, f32), i: usize) void {
    expect(v[0] == 689) catch @panic("test failure");
    expect(v[1] == 690) catch @panic("test failure");
    expect(v[2] == 691) catch @panic("test failure");
    expect(v[3] == 692) catch @panic("test failure");
    expect(v[4] == 693) catch @panic("test failure");
    expect(v[5] == 694) catch @panic("test failure");
    expect(v[6] == 695) catch @panic("test failure");
    expect(v[7] == 696) catch @panic("test failure");
    expect(v[8] == 697) catch @panic("test failure");
    expect(v[9] == 698) catch @panic("test failure");
    expect(v[10] == 699) catch @panic("test failure");
    expect(v[11] == 700) catch @panic("test failure");
    expect(v[12] == 701) catch @panic("test failure");
    expect(v[13] == 702) catch @panic("test failure");
    expect(v[14] == 703) catch @panic("test failure");
    expect(v[15] == 704) catch @panic("test failure");
    expect(v[16] == 705) catch @panic("test failure");
    expect(v[17] == 706) catch @panic("test failure");
    expect(v[18] == 707) catch @panic("test failure");
    expect(v[19] == 708) catch @panic("test failure");
    expect(v[20] == 709) catch @panic("test failure");
    expect(v[21] == 710) catch @panic("test failure");
    expect(v[22] == 711) catch @panic("test failure");
    expect(v[23] == 712) catch @panic("test failure");
    expect(v[24] == 713) catch @panic("test failure");
    expect(v[25] == 714) catch @panic("test failure");
    expect(v[26] == 715) catch @panic("test failure");
    expect(v[27] == 716) catch @panic("test failure");
    expect(v[28] == 717) catch @panic("test failure");
    expect(v[29] == 718) catch @panic("test failure");
    expect(v[30] == 719) catch @panic("test failure");
    expect(v[31] == 720) catch @panic("test failure");
    expect(v[32] == 721) catch @panic("test failure");
    expect(v[33] == 722) catch @panic("test failure");
    expect(v[34] == 723) catch @panic("test failure");
    expect(v[35] == 724) catch @panic("test failure");
    expect(v[36] == 725) catch @panic("test failure");
    expect(v[37] == 726) catch @panic("test failure");
    expect(v[38] == 727) catch @panic("test failure");
    expect(v[39] == 728) catch @panic("test failure");
    expect(v[40] == 729) catch @panic("test failure");
    expect(v[41] == 730) catch @panic("test failure");
    expect(v[42] == 731) catch @panic("test failure");
    expect(v[43] == 732) catch @panic("test failure");
    expect(v[44] == 733) catch @panic("test failure");
    expect(v[45] == 734) catch @panic("test failure");
    expect(v[46] == 735) catch @panic("test failure");
    expect(v[47] == 736) catch @panic("test failure");
    expect(v[48] == 737) catch @panic("test failure");
    expect(v[49] == 738) catch @panic("test failure");
    expect(v[50] == 739) catch @panic("test failure");
    expect(v[51] == 740) catch @panic("test failure");
    expect(v[52] == 741) catch @panic("test failure");
    expect(v[53] == 742) catch @panic("test failure");
    expect(v[54] == 743) catch @panic("test failure");
    expect(v[55] == 744) catch @panic("test failure");
    expect(v[56] == 745) catch @panic("test failure");
    expect(v[57] == 746) catch @panic("test failure");
    expect(v[58] == 747) catch @panic("test failure");
    expect(v[59] == 748) catch @panic("test failure");
    expect(v[60] == 749) catch @panic("test failure");
    expect(v[61] == 750) catch @panic("test failure");
    expect(v[62] == 751) catch @panic("test failure");
    expect(v[63] == 752) catch @panic("test failure");
    expect(i == 64) catch @panic("test failure");
}

extern fn c_ret_vector_64_f32() @Vector(64, f32);
extern fn c_vector_64_f32(@Vector(64, f32), usize) void;
extern fn c_test_vector_64_f32() void;

test "@Vector(64, f32)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_64_f32();
    try expect(v[0] == 753);
    try expect(v[1] == 754);
    try expect(v[2] == 755);
    try expect(v[3] == 756);
    try expect(v[4] == 757);
    try expect(v[5] == 758);
    try expect(v[6] == 759);
    try expect(v[7] == 760);
    try expect(v[8] == 761);
    try expect(v[9] == 762);
    try expect(v[10] == 763);
    try expect(v[11] == 764);
    try expect(v[12] == 765);
    try expect(v[13] == 766);
    try expect(v[14] == 767);
    try expect(v[15] == 768);
    try expect(v[16] == 769);
    try expect(v[17] == 770);
    try expect(v[18] == 771);
    try expect(v[19] == 772);
    try expect(v[20] == 773);
    try expect(v[21] == 774);
    try expect(v[22] == 775);
    try expect(v[23] == 776);
    try expect(v[24] == 777);
    try expect(v[25] == 778);
    try expect(v[26] == 779);
    try expect(v[27] == 780);
    try expect(v[28] == 781);
    try expect(v[29] == 782);
    try expect(v[30] == 783);
    try expect(v[31] == 784);
    try expect(v[32] == 785);
    try expect(v[33] == 786);
    try expect(v[34] == 787);
    try expect(v[35] == 788);
    try expect(v[36] == 789);
    try expect(v[37] == 790);
    try expect(v[38] == 791);
    try expect(v[39] == 792);
    try expect(v[40] == 793);
    try expect(v[41] == 794);
    try expect(v[42] == 795);
    try expect(v[43] == 796);
    try expect(v[44] == 797);
    try expect(v[45] == 798);
    try expect(v[46] == 799);
    try expect(v[47] == 800);
    try expect(v[48] == 801);
    try expect(v[49] == 802);
    try expect(v[50] == 803);
    try expect(v[51] == 804);
    try expect(v[52] == 805);
    try expect(v[53] == 806);
    try expect(v[54] == 807);
    try expect(v[55] == 808);
    try expect(v[56] == 809);
    try expect(v[57] == 810);
    try expect(v[58] == 811);
    try expect(v[59] == 812);
    try expect(v[60] == 813);
    try expect(v[61] == 814);
    try expect(v[62] == 815);
    try expect(v[63] == 816);
    c_vector_64_f32(.{
        817, 818, 819, 820, 821, 822, 823, 824, 825, 826, 827, 828, 829, 830, 831, 832,
        833, 834, 835, 836, 837, 838, 839, 840, 841, 842, 843, 844, 845, 846, 847, 848,
        849, 850, 851, 852, 853, 854, 855, 856, 857, 858, 859, 860, 861, 862, 863, 864,
        865, 866, 867, 868, 869, 870, 871, 872, 873, 874, 875, 876, 877, 878, 879, 880,
    }, 64);
    c_test_vector_64_f32();
}

export fn zig_ret_vector_96_f32() @Vector(96, f32) {
    return .{
        890, 891, 892, 893, 894, 895, 896, 897, 898, 899, 900, 901, 902, 903, 904, 905,
        906, 907, 908, 909, 910, 911, 912, 913, 914, 915, 916, 917, 918, 919, 920, 921,
        922, 923, 924, 925, 926, 927, 928, 929, 930, 931, 932, 933, 934, 935, 936, 937,
        938, 939, 940, 941, 942, 943, 944, 945, 946, 947, 948, 949, 950, 951, 952, 953,
        954, 955, 956, 957, 958, 959, 960, 961, 962, 963, 964, 965, 966, 967, 968, 969,
        970, 971, 972, 973, 974, 975, 976, 977, 978, 979, 980, 981, 982, 983, 984, 985,
    };
}
export fn zig_vector_96_f32(v: @Vector(96, f32), i: usize) void {
    expect(v[0] == 986) catch @panic("test failure");
    expect(v[1] == 987) catch @panic("test failure");
    expect(v[2] == 988) catch @panic("test failure");
    expect(v[3] == 989) catch @panic("test failure");
    expect(v[4] == 990) catch @panic("test failure");
    expect(v[5] == 991) catch @panic("test failure");
    expect(v[6] == 992) catch @panic("test failure");
    expect(v[7] == 993) catch @panic("test failure");
    expect(v[8] == 994) catch @panic("test failure");
    expect(v[9] == 995) catch @panic("test failure");
    expect(v[10] == 996) catch @panic("test failure");
    expect(v[11] == 997) catch @panic("test failure");
    expect(v[12] == 998) catch @panic("test failure");
    expect(v[13] == 999) catch @panic("test failure");
    expect(v[14] == 1000) catch @panic("test failure");
    expect(v[15] == 1001) catch @panic("test failure");
    expect(v[16] == 1002) catch @panic("test failure");
    expect(v[17] == 1003) catch @panic("test failure");
    expect(v[18] == 1004) catch @panic("test failure");
    expect(v[19] == 1005) catch @panic("test failure");
    expect(v[20] == 1006) catch @panic("test failure");
    expect(v[21] == 1007) catch @panic("test failure");
    expect(v[22] == 1008) catch @panic("test failure");
    expect(v[23] == 1009) catch @panic("test failure");
    expect(v[24] == 1010) catch @panic("test failure");
    expect(v[25] == 1011) catch @panic("test failure");
    expect(v[26] == 1012) catch @panic("test failure");
    expect(v[27] == 1013) catch @panic("test failure");
    expect(v[28] == 1014) catch @panic("test failure");
    expect(v[29] == 1015) catch @panic("test failure");
    expect(v[30] == 1016) catch @panic("test failure");
    expect(v[31] == 1017) catch @panic("test failure");
    expect(v[32] == 1018) catch @panic("test failure");
    expect(v[33] == 1019) catch @panic("test failure");
    expect(v[34] == 1020) catch @panic("test failure");
    expect(v[35] == 1021) catch @panic("test failure");
    expect(v[36] == 1022) catch @panic("test failure");
    expect(v[37] == 1023) catch @panic("test failure");
    expect(v[38] == 1024) catch @panic("test failure");
    expect(v[39] == 1025) catch @panic("test failure");
    expect(v[40] == 1026) catch @panic("test failure");
    expect(v[41] == 1027) catch @panic("test failure");
    expect(v[42] == 1028) catch @panic("test failure");
    expect(v[43] == 1029) catch @panic("test failure");
    expect(v[44] == 1030) catch @panic("test failure");
    expect(v[45] == 1031) catch @panic("test failure");
    expect(v[46] == 1032) catch @panic("test failure");
    expect(v[47] == 1033) catch @panic("test failure");
    expect(v[48] == 1034) catch @panic("test failure");
    expect(v[49] == 1035) catch @panic("test failure");
    expect(v[50] == 1036) catch @panic("test failure");
    expect(v[51] == 1037) catch @panic("test failure");
    expect(v[52] == 1038) catch @panic("test failure");
    expect(v[53] == 1039) catch @panic("test failure");
    expect(v[54] == 1040) catch @panic("test failure");
    expect(v[55] == 1041) catch @panic("test failure");
    expect(v[56] == 1042) catch @panic("test failure");
    expect(v[57] == 1043) catch @panic("test failure");
    expect(v[58] == 1044) catch @panic("test failure");
    expect(v[59] == 1045) catch @panic("test failure");
    expect(v[60] == 1046) catch @panic("test failure");
    expect(v[61] == 1047) catch @panic("test failure");
    expect(v[62] == 1048) catch @panic("test failure");
    expect(v[63] == 1049) catch @panic("test failure");
    expect(v[64] == 1050) catch @panic("test failure");
    expect(v[65] == 1051) catch @panic("test failure");
    expect(v[66] == 1052) catch @panic("test failure");
    expect(v[67] == 1053) catch @panic("test failure");
    expect(v[68] == 1054) catch @panic("test failure");
    expect(v[69] == 1055) catch @panic("test failure");
    expect(v[70] == 1056) catch @panic("test failure");
    expect(v[71] == 1057) catch @panic("test failure");
    expect(v[72] == 1058) catch @panic("test failure");
    expect(v[73] == 1059) catch @panic("test failure");
    expect(v[74] == 1060) catch @panic("test failure");
    expect(v[75] == 1061) catch @panic("test failure");
    expect(v[76] == 1062) catch @panic("test failure");
    expect(v[77] == 1063) catch @panic("test failure");
    expect(v[78] == 1064) catch @panic("test failure");
    expect(v[79] == 1065) catch @panic("test failure");
    expect(v[80] == 1066) catch @panic("test failure");
    expect(v[81] == 1067) catch @panic("test failure");
    expect(v[82] == 1068) catch @panic("test failure");
    expect(v[83] == 1069) catch @panic("test failure");
    expect(v[84] == 1070) catch @panic("test failure");
    expect(v[85] == 1071) catch @panic("test failure");
    expect(v[86] == 1072) catch @panic("test failure");
    expect(v[87] == 1073) catch @panic("test failure");
    expect(v[88] == 1074) catch @panic("test failure");
    expect(v[89] == 1075) catch @panic("test failure");
    expect(v[90] == 1076) catch @panic("test failure");
    expect(v[91] == 1077) catch @panic("test failure");
    expect(v[92] == 1078) catch @panic("test failure");
    expect(v[93] == 1079) catch @panic("test failure");
    expect(v[94] == 1080) catch @panic("test failure");
    expect(v[95] == 1081) catch @panic("test failure");
    expect(i == 96) catch @panic("test failure");
}

extern fn c_ret_vector_96_f32() @Vector(96, f32);
extern fn c_vector_96_f32(@Vector(96, f32), usize) void;
extern fn c_test_vector_96_f32() void;

test "@Vector(96, f32)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_96_f32();
    try expect(v[0] == 1082);
    try expect(v[1] == 1083);
    try expect(v[2] == 1084);
    try expect(v[3] == 1085);
    try expect(v[4] == 1086);
    try expect(v[5] == 1087);
    try expect(v[6] == 1088);
    try expect(v[7] == 1089);
    try expect(v[8] == 1090);
    try expect(v[9] == 1091);
    try expect(v[10] == 1092);
    try expect(v[11] == 1093);
    try expect(v[12] == 1094);
    try expect(v[13] == 1095);
    try expect(v[14] == 1096);
    try expect(v[15] == 1097);
    try expect(v[16] == 1098);
    try expect(v[17] == 1099);
    try expect(v[18] == 1100);
    try expect(v[19] == 1101);
    try expect(v[20] == 1102);
    try expect(v[21] == 1103);
    try expect(v[22] == 1104);
    try expect(v[23] == 1105);
    try expect(v[24] == 1106);
    try expect(v[25] == 1107);
    try expect(v[26] == 1108);
    try expect(v[27] == 1109);
    try expect(v[28] == 1110);
    try expect(v[29] == 1111);
    try expect(v[30] == 1112);
    try expect(v[31] == 1113);
    try expect(v[32] == 1114);
    try expect(v[33] == 1115);
    try expect(v[34] == 1116);
    try expect(v[35] == 1117);
    try expect(v[36] == 1118);
    try expect(v[37] == 1119);
    try expect(v[38] == 1120);
    try expect(v[39] == 1121);
    try expect(v[40] == 1122);
    try expect(v[41] == 1123);
    try expect(v[42] == 1124);
    try expect(v[43] == 1125);
    try expect(v[44] == 1126);
    try expect(v[45] == 1127);
    try expect(v[46] == 1128);
    try expect(v[47] == 1129);
    try expect(v[48] == 1130);
    try expect(v[49] == 1131);
    try expect(v[50] == 1132);
    try expect(v[51] == 1133);
    try expect(v[52] == 1134);
    try expect(v[53] == 1135);
    try expect(v[54] == 1136);
    try expect(v[55] == 1137);
    try expect(v[56] == 1138);
    try expect(v[57] == 1139);
    try expect(v[58] == 1140);
    try expect(v[59] == 1141);
    try expect(v[60] == 1142);
    try expect(v[61] == 1143);
    try expect(v[62] == 1144);
    try expect(v[63] == 1145);
    try expect(v[64] == 1146);
    try expect(v[65] == 1147);
    try expect(v[66] == 1148);
    try expect(v[67] == 1149);
    try expect(v[68] == 1150);
    try expect(v[69] == 1151);
    try expect(v[70] == 1152);
    try expect(v[71] == 1153);
    try expect(v[72] == 1154);
    try expect(v[73] == 1155);
    try expect(v[74] == 1156);
    try expect(v[75] == 1157);
    try expect(v[76] == 1158);
    try expect(v[77] == 1159);
    try expect(v[78] == 1160);
    try expect(v[79] == 1161);
    try expect(v[80] == 1162);
    try expect(v[81] == 1163);
    try expect(v[82] == 1164);
    try expect(v[83] == 1165);
    try expect(v[84] == 1166);
    try expect(v[85] == 1167);
    try expect(v[86] == 1168);
    try expect(v[87] == 1169);
    try expect(v[88] == 1170);
    try expect(v[89] == 1171);
    try expect(v[90] == 1172);
    try expect(v[91] == 1173);
    try expect(v[92] == 1174);
    try expect(v[93] == 1175);
    try expect(v[94] == 1176);
    try expect(v[95] == 1177);
    c_vector_96_f32(.{
        1178, 1179, 1180, 1181, 1182, 1183, 1184, 1185, 1186, 1187, 1188, 1189, 1190, 1191, 1192, 1193,
        1194, 1195, 1196, 1197, 1198, 1199, 1200, 1201, 1202, 1203, 1204, 1205, 1206, 1207, 1208, 1209,
        1210, 1211, 1212, 1213, 1214, 1215, 1216, 1217, 1218, 1219, 1220, 1221, 1222, 1223, 1224, 1225,
        1226, 1227, 1228, 1229, 1230, 1231, 1232, 1233, 1234, 1235, 1236, 1237, 1238, 1239, 1240, 1241,
        1242, 1243, 1244, 1245, 1246, 1247, 1248, 1249, 1250, 1251, 1252, 1253, 1254, 1255, 1256, 1257,
        1258, 1259, 1260, 1261, 1262, 1263, 1264, 1265, 1266, 1267, 1268, 1269, 1270, 1271, 1272, 1273,
    }, 96);
    c_test_vector_96_f32();
}

export fn zig_ret_vector_128_f32() @Vector(128, f32) {
    return .{
        1274, 1275, 1276, 1277, 1278, 1279, 1280, 1281, 1282, 1283, 1284, 1285, 1286, 1287, 1288, 1289,
        1290, 1291, 1292, 1293, 1294, 1295, 1296, 1297, 1298, 1299, 1300, 1301, 1302, 1303, 1304, 1305,
        1306, 1307, 1308, 1309, 1310, 1311, 1312, 1313, 1314, 1315, 1316, 1317, 1318, 1319, 1320, 1321,
        1322, 1323, 1324, 1325, 1326, 1327, 1328, 1329, 1330, 1331, 1332, 1333, 1334, 1335, 1336, 1337,
        1338, 1339, 1340, 1341, 1342, 1343, 1344, 1345, 1346, 1347, 1348, 1349, 1350, 1351, 1352, 1353,
        1354, 1355, 1356, 1357, 1358, 1359, 1360, 1361, 1362, 1363, 1364, 1365, 1366, 1367, 1368, 1369,
        1370, 1371, 1372, 1373, 1374, 1375, 1376, 1377, 1378, 1379, 1380, 1381, 1382, 1383, 1384, 1385,
        1386, 1387, 1388, 1389, 1390, 1391, 1392, 1393, 1394, 1395, 1396, 1397, 1398, 1399, 1400, 1401,
    };
}
export fn zig_vector_128_f32(v: @Vector(128, f32), i: usize) void {
    expect(v[0] == 1402) catch @panic("test failure");
    expect(v[1] == 1403) catch @panic("test failure");
    expect(v[2] == 1404) catch @panic("test failure");
    expect(v[3] == 1405) catch @panic("test failure");
    expect(v[4] == 1406) catch @panic("test failure");
    expect(v[5] == 1407) catch @panic("test failure");
    expect(v[6] == 1408) catch @panic("test failure");
    expect(v[7] == 1409) catch @panic("test failure");
    expect(v[8] == 1410) catch @panic("test failure");
    expect(v[9] == 1411) catch @panic("test failure");
    expect(v[10] == 1412) catch @panic("test failure");
    expect(v[11] == 1413) catch @panic("test failure");
    expect(v[12] == 1414) catch @panic("test failure");
    expect(v[13] == 1415) catch @panic("test failure");
    expect(v[14] == 1416) catch @panic("test failure");
    expect(v[15] == 1417) catch @panic("test failure");
    expect(v[16] == 1418) catch @panic("test failure");
    expect(v[17] == 1419) catch @panic("test failure");
    expect(v[18] == 1420) catch @panic("test failure");
    expect(v[19] == 1421) catch @panic("test failure");
    expect(v[20] == 1422) catch @panic("test failure");
    expect(v[21] == 1423) catch @panic("test failure");
    expect(v[22] == 1424) catch @panic("test failure");
    expect(v[23] == 1425) catch @panic("test failure");
    expect(v[24] == 1426) catch @panic("test failure");
    expect(v[25] == 1427) catch @panic("test failure");
    expect(v[26] == 1428) catch @panic("test failure");
    expect(v[27] == 1429) catch @panic("test failure");
    expect(v[28] == 1430) catch @panic("test failure");
    expect(v[29] == 1431) catch @panic("test failure");
    expect(v[30] == 1432) catch @panic("test failure");
    expect(v[31] == 1433) catch @panic("test failure");
    expect(v[32] == 1434) catch @panic("test failure");
    expect(v[33] == 1435) catch @panic("test failure");
    expect(v[34] == 1436) catch @panic("test failure");
    expect(v[35] == 1437) catch @panic("test failure");
    expect(v[36] == 1438) catch @panic("test failure");
    expect(v[37] == 1439) catch @panic("test failure");
    expect(v[38] == 1440) catch @panic("test failure");
    expect(v[39] == 1441) catch @panic("test failure");
    expect(v[40] == 1442) catch @panic("test failure");
    expect(v[41] == 1443) catch @panic("test failure");
    expect(v[42] == 1444) catch @panic("test failure");
    expect(v[43] == 1445) catch @panic("test failure");
    expect(v[44] == 1446) catch @panic("test failure");
    expect(v[45] == 1447) catch @panic("test failure");
    expect(v[46] == 1448) catch @panic("test failure");
    expect(v[47] == 1449) catch @panic("test failure");
    expect(v[48] == 1450) catch @panic("test failure");
    expect(v[49] == 1451) catch @panic("test failure");
    expect(v[50] == 1452) catch @panic("test failure");
    expect(v[51] == 1453) catch @panic("test failure");
    expect(v[52] == 1454) catch @panic("test failure");
    expect(v[53] == 1455) catch @panic("test failure");
    expect(v[54] == 1456) catch @panic("test failure");
    expect(v[55] == 1457) catch @panic("test failure");
    expect(v[56] == 1458) catch @panic("test failure");
    expect(v[57] == 1459) catch @panic("test failure");
    expect(v[58] == 1460) catch @panic("test failure");
    expect(v[59] == 1461) catch @panic("test failure");
    expect(v[60] == 1462) catch @panic("test failure");
    expect(v[61] == 1463) catch @panic("test failure");
    expect(v[62] == 1464) catch @panic("test failure");
    expect(v[63] == 1465) catch @panic("test failure");
    expect(v[64] == 1466) catch @panic("test failure");
    expect(v[65] == 1467) catch @panic("test failure");
    expect(v[66] == 1468) catch @panic("test failure");
    expect(v[67] == 1469) catch @panic("test failure");
    expect(v[68] == 1470) catch @panic("test failure");
    expect(v[69] == 1471) catch @panic("test failure");
    expect(v[70] == 1472) catch @panic("test failure");
    expect(v[71] == 1473) catch @panic("test failure");
    expect(v[72] == 1474) catch @panic("test failure");
    expect(v[73] == 1475) catch @panic("test failure");
    expect(v[74] == 1476) catch @panic("test failure");
    expect(v[75] == 1477) catch @panic("test failure");
    expect(v[76] == 1478) catch @panic("test failure");
    expect(v[77] == 1479) catch @panic("test failure");
    expect(v[78] == 1480) catch @panic("test failure");
    expect(v[79] == 1481) catch @panic("test failure");
    expect(v[80] == 1482) catch @panic("test failure");
    expect(v[81] == 1483) catch @panic("test failure");
    expect(v[82] == 1484) catch @panic("test failure");
    expect(v[83] == 1485) catch @panic("test failure");
    expect(v[84] == 1486) catch @panic("test failure");
    expect(v[85] == 1487) catch @panic("test failure");
    expect(v[86] == 1488) catch @panic("test failure");
    expect(v[87] == 1489) catch @panic("test failure");
    expect(v[88] == 1490) catch @panic("test failure");
    expect(v[89] == 1491) catch @panic("test failure");
    expect(v[90] == 1492) catch @panic("test failure");
    expect(v[91] == 1493) catch @panic("test failure");
    expect(v[92] == 1494) catch @panic("test failure");
    expect(v[93] == 1495) catch @panic("test failure");
    expect(v[94] == 1496) catch @panic("test failure");
    expect(v[95] == 1497) catch @panic("test failure");
    expect(v[96] == 1498) catch @panic("test failure");
    expect(v[97] == 1499) catch @panic("test failure");
    expect(v[98] == 1500) catch @panic("test failure");
    expect(v[99] == 1501) catch @panic("test failure");
    expect(v[100] == 1502) catch @panic("test failure");
    expect(v[101] == 1503) catch @panic("test failure");
    expect(v[102] == 1504) catch @panic("test failure");
    expect(v[103] == 1505) catch @panic("test failure");
    expect(v[104] == 1506) catch @panic("test failure");
    expect(v[105] == 1507) catch @panic("test failure");
    expect(v[106] == 1508) catch @panic("test failure");
    expect(v[107] == 1509) catch @panic("test failure");
    expect(v[108] == 1510) catch @panic("test failure");
    expect(v[109] == 1511) catch @panic("test failure");
    expect(v[110] == 1512) catch @panic("test failure");
    expect(v[111] == 1513) catch @panic("test failure");
    expect(v[112] == 1514) catch @panic("test failure");
    expect(v[113] == 1515) catch @panic("test failure");
    expect(v[114] == 1516) catch @panic("test failure");
    expect(v[115] == 1517) catch @panic("test failure");
    expect(v[116] == 1518) catch @panic("test failure");
    expect(v[117] == 1519) catch @panic("test failure");
    expect(v[118] == 1520) catch @panic("test failure");
    expect(v[119] == 1521) catch @panic("test failure");
    expect(v[120] == 1522) catch @panic("test failure");
    expect(v[121] == 1523) catch @panic("test failure");
    expect(v[122] == 1524) catch @panic("test failure");
    expect(v[123] == 1525) catch @panic("test failure");
    expect(v[124] == 1526) catch @panic("test failure");
    expect(v[125] == 1527) catch @panic("test failure");
    expect(v[126] == 1528) catch @panic("test failure");
    expect(v[127] == 1529) catch @panic("test failure");
    expect(i == 128) catch @panic("test failure");
}

extern fn c_ret_vector_128_f32() @Vector(128, f32);
extern fn c_vector_128_f32(@Vector(128, f32), usize) void;
extern fn c_test_vector_128_f32() void;

test "@Vector(128, f32)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_128_f32();
    try expect(v[0] == 1530);
    try expect(v[1] == 1531);
    try expect(v[2] == 1532);
    try expect(v[3] == 1533);
    try expect(v[4] == 1534);
    try expect(v[5] == 1535);
    try expect(v[6] == 1536);
    try expect(v[7] == 1537);
    try expect(v[8] == 1538);
    try expect(v[9] == 1539);
    try expect(v[10] == 1540);
    try expect(v[11] == 1541);
    try expect(v[12] == 1542);
    try expect(v[13] == 1543);
    try expect(v[14] == 1544);
    try expect(v[15] == 1545);
    try expect(v[16] == 1546);
    try expect(v[17] == 1547);
    try expect(v[18] == 1548);
    try expect(v[19] == 1549);
    try expect(v[20] == 1550);
    try expect(v[21] == 1551);
    try expect(v[22] == 1552);
    try expect(v[23] == 1553);
    try expect(v[24] == 1554);
    try expect(v[25] == 1555);
    try expect(v[26] == 1556);
    try expect(v[27] == 1557);
    try expect(v[28] == 1558);
    try expect(v[29] == 1559);
    try expect(v[30] == 1560);
    try expect(v[31] == 1561);
    try expect(v[32] == 1562);
    try expect(v[33] == 1563);
    try expect(v[34] == 1564);
    try expect(v[35] == 1565);
    try expect(v[36] == 1566);
    try expect(v[37] == 1567);
    try expect(v[38] == 1568);
    try expect(v[39] == 1569);
    try expect(v[40] == 1570);
    try expect(v[41] == 1571);
    try expect(v[42] == 1572);
    try expect(v[43] == 1573);
    try expect(v[44] == 1574);
    try expect(v[45] == 1575);
    try expect(v[46] == 1576);
    try expect(v[47] == 1577);
    try expect(v[48] == 1578);
    try expect(v[49] == 1579);
    try expect(v[50] == 1580);
    try expect(v[51] == 1581);
    try expect(v[52] == 1582);
    try expect(v[53] == 1583);
    try expect(v[54] == 1584);
    try expect(v[55] == 1585);
    try expect(v[56] == 1586);
    try expect(v[57] == 1587);
    try expect(v[58] == 1588);
    try expect(v[59] == 1589);
    try expect(v[60] == 1590);
    try expect(v[61] == 1591);
    try expect(v[62] == 1592);
    try expect(v[63] == 1593);
    try expect(v[64] == 1594);
    try expect(v[65] == 1595);
    try expect(v[66] == 1596);
    try expect(v[67] == 1597);
    try expect(v[68] == 1598);
    try expect(v[69] == 1599);
    try expect(v[70] == 1600);
    try expect(v[71] == 1601);
    try expect(v[72] == 1602);
    try expect(v[73] == 1603);
    try expect(v[74] == 1604);
    try expect(v[75] == 1605);
    try expect(v[76] == 1606);
    try expect(v[77] == 1607);
    try expect(v[78] == 1608);
    try expect(v[79] == 1609);
    try expect(v[80] == 1610);
    try expect(v[81] == 1611);
    try expect(v[82] == 1612);
    try expect(v[83] == 1613);
    try expect(v[84] == 1614);
    try expect(v[85] == 1615);
    try expect(v[86] == 1616);
    try expect(v[87] == 1617);
    try expect(v[88] == 1618);
    try expect(v[89] == 1619);
    try expect(v[90] == 1620);
    try expect(v[91] == 1621);
    try expect(v[92] == 1622);
    try expect(v[93] == 1623);
    try expect(v[94] == 1624);
    try expect(v[95] == 1625);
    try expect(v[96] == 1626);
    try expect(v[97] == 1627);
    try expect(v[98] == 1628);
    try expect(v[99] == 1629);
    try expect(v[100] == 1630);
    try expect(v[101] == 1631);
    try expect(v[102] == 1632);
    try expect(v[103] == 1633);
    try expect(v[104] == 1634);
    try expect(v[105] == 1635);
    try expect(v[106] == 1636);
    try expect(v[107] == 1637);
    try expect(v[108] == 1638);
    try expect(v[109] == 1639);
    try expect(v[110] == 1640);
    try expect(v[111] == 1641);
    try expect(v[112] == 1642);
    try expect(v[113] == 1643);
    try expect(v[114] == 1644);
    try expect(v[115] == 1645);
    try expect(v[116] == 1646);
    try expect(v[117] == 1647);
    try expect(v[118] == 1648);
    try expect(v[119] == 1649);
    try expect(v[120] == 1650);
    try expect(v[121] == 1651);
    try expect(v[122] == 1652);
    try expect(v[123] == 1653);
    try expect(v[124] == 1654);
    try expect(v[125] == 1655);
    try expect(v[126] == 1656);
    try expect(v[127] == 1657);
    c_vector_128_f32(.{
        1658, 1659, 1660, 1661, 1662, 1663, 1664, 1665, 1666, 1667, 1668, 1669, 1670, 1671, 1672, 1673,
        1674, 1675, 1676, 1677, 1678, 1679, 1680, 1681, 1682, 1683, 1684, 1685, 1686, 1687, 1688, 1689,
        1690, 1691, 1692, 1693, 1694, 1695, 1696, 1697, 1698, 1699, 1700, 1701, 1702, 1703, 1704, 1705,
        1706, 1707, 1708, 1709, 1710, 1711, 1712, 1713, 1714, 1715, 1716, 1717, 1718, 1719, 1720, 1721,
        1722, 1723, 1724, 1725, 1726, 1727, 1728, 1729, 1730, 1731, 1732, 1733, 1734, 1735, 1736, 1737,
        1738, 1739, 1740, 1741, 1742, 1743, 1744, 1745, 1746, 1747, 1748, 1749, 1750, 1751, 1752, 1753,
        1754, 1755, 1756, 1757, 1758, 1759, 1760, 1761, 1762, 1763, 1764, 1765, 1766, 1767, 1768, 1769,
        1770, 1771, 1772, 1773, 1774, 1775, 1776, 1777, 1778, 1779, 1780, 1781, 1782, 1783, 1784, 1785,
    }, 128);
    c_test_vector_128_f32();
}

export fn zig_ret_vector_1_f64() @Vector(1, f64) {
    return .{1};
}
export fn zig_vector_1_f64(v: @Vector(1, f64), i: usize) void {
    expect(v[0] == 2) catch @panic("test failure");
    expect(i == 1) catch @panic("test failure");
}

extern fn c_ret_vector_1_f64() @Vector(1, f64);
extern fn c_vector_1_f64(@Vector(1, f64), usize) void;
extern fn c_test_vector_1_f64() void;

test "@Vector(1, f64)" {
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;

    const v = c_ret_vector_1_f64();
    try expect(v[0] == 3);
    c_vector_1_f64(.{4}, 1);
    c_test_vector_1_f64();
}

export fn zig_ret_vector_2_f64() @Vector(2, f64) {
    return .{ 5, 6 };
}
export fn zig_vector_2_f64(v: @Vector(2, f64), i: usize) void {
    expect(v[0] == 7) catch @panic("test failure");
    expect(v[1] == 8) catch @panic("test failure");
    expect(i == 2) catch @panic("test failure");
}

extern fn c_ret_vector_2_f64() @Vector(2, f64);
extern fn c_vector_2_f64(@Vector(2, f64), usize) void;
extern fn c_test_vector_2_f64() void;

test "@Vector(2, f64)" {
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;

    const v = c_ret_vector_2_f64();
    try expect(v[0] == 9);
    try expect(v[1] == 10);
    c_vector_2_f64(.{ 11, 12 }, 2);
    c_test_vector_2_f64();
}

export fn zig_ret_vector_3_f64() @Vector(3, f64) {
    return .{ 13, 14, 15 };
}
export fn zig_vector_3_f64(v: @Vector(3, f64), i: usize) void {
    expect(v[0] == 16) catch @panic("test failure");
    expect(v[1] == 17) catch @panic("test failure");
    expect(v[2] == 18) catch @panic("test failure");
    expect(i == 3) catch @panic("test failure");
}

extern fn c_ret_vector_3_f64() @Vector(3, f64);
extern fn c_vector_3_f64(@Vector(3, f64), usize) void;
extern fn c_test_vector_3_f64() void;

test "@Vector(3, f64)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_3_f64();
    try expect(v[0] == 19);
    try expect(v[1] == 20);
    try expect(v[2] == 21);
    c_vector_3_f64(.{ 22, 23, 24 }, 3);
    c_test_vector_3_f64();
}

export fn zig_ret_vector_4_f64() @Vector(4, f64) {
    return .{ 25, 26, 27, 28 };
}
export fn zig_vector_4_f64(v: @Vector(4, f64), i: usize) void {
    expect(v[0] == 29) catch @panic("test failure");
    expect(v[1] == 30) catch @panic("test failure");
    expect(v[2] == 31) catch @panic("test failure");
    expect(v[3] == 32) catch @panic("test failure");
    expect(i == 4) catch @panic("test failure");
}

extern fn c_ret_vector_4_f64() @Vector(4, f64);
extern fn c_vector_4_f64(@Vector(4, f64), usize) void;
extern fn c_test_vector_4_f64() void;

test "@Vector(4, f64)" {
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest; // https://codeberg.org/ziglang/zig/issues/35899

    const v = c_ret_vector_4_f64();
    try expect(v[0] == 33);
    try expect(v[1] == 34);
    try expect(v[2] == 35);
    try expect(v[3] == 36);
    c_vector_4_f64(.{ 37, 38, 39, 40 }, 4);
    c_test_vector_4_f64();
}

export fn zig_ret_vector_6_f64() @Vector(6, f64) {
    return .{ 41, 42, 43, 44, 45, 46 };
}
export fn zig_vector_6_f64(v: @Vector(6, f64), i: usize) void {
    expect(v[0] == 47) catch @panic("test failure");
    expect(v[1] == 48) catch @panic("test failure");
    expect(v[2] == 49) catch @panic("test failure");
    expect(v[3] == 50) catch @panic("test failure");
    expect(v[4] == 51) catch @panic("test failure");
    expect(v[5] == 52) catch @panic("test failure");
    expect(i == 6) catch @panic("test failure");
}

extern fn c_ret_vector_6_f64() @Vector(6, f64);
extern fn c_vector_6_f64(@Vector(6, f64), usize) void;
extern fn c_test_vector_6_f64() void;

test "@Vector(6, f64)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_6_f64();
    try expect(v[0] == 53);
    try expect(v[1] == 54);
    try expect(v[2] == 55);
    try expect(v[3] == 56);
    try expect(v[4] == 57);
    try expect(v[5] == 58);
    c_vector_6_f64(.{ 59, 60, 61, 62, 63, 64 }, 6);
    c_test_vector_6_f64();
}

export fn zig_ret_vector_8_f64() @Vector(8, f64) {
    return .{ 65, 66, 67, 68, 69, 70, 71, 72 };
}
export fn zig_vector_8_f64(v: @Vector(8, f64), i: usize) void {
    expect(v[0] == 73) catch @panic("test failure");
    expect(v[1] == 74) catch @panic("test failure");
    expect(v[2] == 75) catch @panic("test failure");
    expect(v[3] == 76) catch @panic("test failure");
    expect(v[4] == 77) catch @panic("test failure");
    expect(v[5] == 78) catch @panic("test failure");
    expect(v[6] == 79) catch @panic("test failure");
    expect(v[7] == 80) catch @panic("test failure");
    expect(i == 8) catch @panic("test failure");
}

extern fn c_ret_vector_8_f64() @Vector(8, f64);
extern fn c_vector_8_f64(@Vector(8, f64), usize) void;
extern fn c_test_vector_8_f64() void;

test "@Vector(8, f64)" {
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest; // https://codeberg.org/ziglang/zig/issues/35899

    const v = c_ret_vector_8_f64();
    try expect(v[0] == 81);
    try expect(v[1] == 82);
    try expect(v[2] == 83);
    try expect(v[3] == 84);
    try expect(v[4] == 85);
    try expect(v[5] == 86);
    try expect(v[6] == 87);
    try expect(v[7] == 88);
    c_vector_8_f64(.{ 89, 90, 91, 92, 93, 94, 95, 96 }, 8);
    c_test_vector_8_f64();
}

export fn zig_ret_vector_12_f64() @Vector(12, f64) {
    return .{ 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108 };
}
export fn zig_vector_12_f64(v: @Vector(12, f64), i: usize) void {
    expect(v[0] == 109) catch @panic("test failure");
    expect(v[1] == 110) catch @panic("test failure");
    expect(v[2] == 111) catch @panic("test failure");
    expect(v[3] == 112) catch @panic("test failure");
    expect(v[4] == 113) catch @panic("test failure");
    expect(v[5] == 114) catch @panic("test failure");
    expect(v[6] == 115) catch @panic("test failure");
    expect(v[7] == 116) catch @panic("test failure");
    expect(v[8] == 117) catch @panic("test failure");
    expect(v[9] == 118) catch @panic("test failure");
    expect(v[10] == 119) catch @panic("test failure");
    expect(v[11] == 120) catch @panic("test failure");
    expect(i == 12) catch @panic("test failure");
}

extern fn c_ret_vector_12_f64() @Vector(12, f64);
extern fn c_vector_12_f64(@Vector(12, f64), usize) void;
extern fn c_test_vector_12_f64() void;

test "@Vector(12, f64)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_12_f64();
    try expect(v[0] == 121);
    try expect(v[1] == 122);
    try expect(v[2] == 123);
    try expect(v[3] == 124);
    try expect(v[4] == 125);
    try expect(v[5] == 126);
    try expect(v[6] == 127);
    try expect(v[7] == 128);
    try expect(v[8] == 129);
    try expect(v[9] == 130);
    try expect(v[10] == 131);
    try expect(v[11] == 132);
    c_vector_12_f64(.{ 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144 }, 12);
    c_test_vector_12_f64();
}

export fn zig_ret_vector_16_f64() @Vector(16, f64) {
    return .{ 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160 };
}
export fn zig_vector_16_f64(v: @Vector(16, f64), i: usize) void {
    expect(v[0] == 161) catch @panic("test failure");
    expect(v[1] == 162) catch @panic("test failure");
    expect(v[2] == 163) catch @panic("test failure");
    expect(v[3] == 164) catch @panic("test failure");
    expect(v[4] == 165) catch @panic("test failure");
    expect(v[5] == 166) catch @panic("test failure");
    expect(v[6] == 167) catch @panic("test failure");
    expect(v[7] == 168) catch @panic("test failure");
    expect(v[8] == 169) catch @panic("test failure");
    expect(v[9] == 170) catch @panic("test failure");
    expect(v[10] == 171) catch @panic("test failure");
    expect(v[11] == 172) catch @panic("test failure");
    expect(v[12] == 173) catch @panic("test failure");
    expect(v[13] == 174) catch @panic("test failure");
    expect(v[14] == 175) catch @panic("test failure");
    expect(v[15] == 176) catch @panic("test failure");
    expect(i == 16) catch @panic("test failure");
}

extern fn c_ret_vector_16_f64() @Vector(16, f64);
extern fn c_vector_16_f64(@Vector(16, f64), usize) void;
extern fn c_test_vector_16_f64() void;

test "@Vector(16, f64)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_16_f64();
    try expect(v[0] == 177);
    try expect(v[1] == 178);
    try expect(v[2] == 179);
    try expect(v[3] == 180);
    try expect(v[4] == 181);
    try expect(v[5] == 182);
    try expect(v[6] == 183);
    try expect(v[7] == 184);
    try expect(v[8] == 185);
    try expect(v[9] == 186);
    try expect(v[10] == 187);
    try expect(v[11] == 188);
    try expect(v[12] == 189);
    try expect(v[13] == 190);
    try expect(v[14] == 191);
    try expect(v[15] == 192);
    c_vector_16_f64(.{ 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208 }, 16);
    c_test_vector_16_f64();
}

export fn zig_ret_vector_24_f64() @Vector(24, f64) {
    return .{
        209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224,
        225, 226, 227, 228, 229, 230, 231, 232,
    };
}
export fn zig_vector_24_f64(v: @Vector(24, f64), i: usize) void {
    expect(v[0] == 233) catch @panic("test failure");
    expect(v[1] == 234) catch @panic("test failure");
    expect(v[2] == 235) catch @panic("test failure");
    expect(v[3] == 236) catch @panic("test failure");
    expect(v[4] == 237) catch @panic("test failure");
    expect(v[5] == 238) catch @panic("test failure");
    expect(v[6] == 239) catch @panic("test failure");
    expect(v[7] == 240) catch @panic("test failure");
    expect(v[8] == 241) catch @panic("test failure");
    expect(v[9] == 242) catch @panic("test failure");
    expect(v[10] == 243) catch @panic("test failure");
    expect(v[11] == 244) catch @panic("test failure");
    expect(v[12] == 245) catch @panic("test failure");
    expect(v[13] == 246) catch @panic("test failure");
    expect(v[14] == 247) catch @panic("test failure");
    expect(v[15] == 248) catch @panic("test failure");
    expect(v[16] == 249) catch @panic("test failure");
    expect(v[17] == 250) catch @panic("test failure");
    expect(v[18] == 251) catch @panic("test failure");
    expect(v[19] == 252) catch @panic("test failure");
    expect(v[20] == 253) catch @panic("test failure");
    expect(v[21] == 254) catch @panic("test failure");
    expect(v[22] == 255) catch @panic("test failure");
    expect(v[23] == 256) catch @panic("test failure");
    expect(i == 24) catch @panic("test failure");
}

extern fn c_ret_vector_24_f64() @Vector(24, f64);
extern fn c_vector_24_f64(@Vector(24, f64), usize) void;
extern fn c_test_vector_24_f64() void;

test "@Vector(24, f64)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_24_f64();
    try expect(v[0] == 257);
    try expect(v[1] == 258);
    try expect(v[2] == 259);
    try expect(v[3] == 260);
    try expect(v[4] == 261);
    try expect(v[5] == 262);
    try expect(v[6] == 263);
    try expect(v[7] == 264);
    try expect(v[8] == 265);
    try expect(v[9] == 266);
    try expect(v[10] == 267);
    try expect(v[11] == 268);
    try expect(v[12] == 269);
    try expect(v[13] == 270);
    try expect(v[14] == 271);
    try expect(v[15] == 272);
    try expect(v[16] == 273);
    try expect(v[17] == 274);
    try expect(v[18] == 275);
    try expect(v[19] == 276);
    try expect(v[20] == 277);
    try expect(v[21] == 278);
    try expect(v[22] == 279);
    try expect(v[23] == 280);
    c_vector_24_f64(.{
        281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296,
        297, 298, 299, 300, 301, 302, 303, 304,
    }, 24);
    c_test_vector_24_f64();
}

export fn zig_ret_vector_32_f64() @Vector(32, f64) {
    return .{
        305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320,
        321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336,
    };
}
export fn zig_vector_32_f64(v: @Vector(32, f64), i: usize) void {
    expect(v[0] == 337) catch @panic("test failure");
    expect(v[1] == 338) catch @panic("test failure");
    expect(v[2] == 339) catch @panic("test failure");
    expect(v[3] == 340) catch @panic("test failure");
    expect(v[4] == 341) catch @panic("test failure");
    expect(v[5] == 342) catch @panic("test failure");
    expect(v[6] == 343) catch @panic("test failure");
    expect(v[7] == 344) catch @panic("test failure");
    expect(v[8] == 345) catch @panic("test failure");
    expect(v[9] == 346) catch @panic("test failure");
    expect(v[10] == 347) catch @panic("test failure");
    expect(v[11] == 348) catch @panic("test failure");
    expect(v[12] == 349) catch @panic("test failure");
    expect(v[13] == 350) catch @panic("test failure");
    expect(v[14] == 351) catch @panic("test failure");
    expect(v[15] == 352) catch @panic("test failure");
    expect(v[16] == 353) catch @panic("test failure");
    expect(v[17] == 354) catch @panic("test failure");
    expect(v[18] == 355) catch @panic("test failure");
    expect(v[19] == 356) catch @panic("test failure");
    expect(v[20] == 357) catch @panic("test failure");
    expect(v[21] == 358) catch @panic("test failure");
    expect(v[22] == 359) catch @panic("test failure");
    expect(v[23] == 360) catch @panic("test failure");
    expect(v[24] == 361) catch @panic("test failure");
    expect(v[25] == 362) catch @panic("test failure");
    expect(v[26] == 363) catch @panic("test failure");
    expect(v[27] == 364) catch @panic("test failure");
    expect(v[28] == 365) catch @panic("test failure");
    expect(v[29] == 366) catch @panic("test failure");
    expect(v[30] == 367) catch @panic("test failure");
    expect(v[31] == 368) catch @panic("test failure");
    expect(i == 32) catch @panic("test failure");
}

extern fn c_ret_vector_32_f64() @Vector(32, f64);
extern fn c_vector_32_f64(@Vector(32, f64), usize) void;
extern fn c_test_vector_32_f64() void;

test "@Vector(32, f64)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_32_f64();
    try expect(v[0] == 369);
    try expect(v[1] == 370);
    try expect(v[2] == 371);
    try expect(v[3] == 372);
    try expect(v[4] == 373);
    try expect(v[5] == 374);
    try expect(v[6] == 375);
    try expect(v[7] == 376);
    try expect(v[8] == 377);
    try expect(v[9] == 378);
    try expect(v[10] == 379);
    try expect(v[11] == 380);
    try expect(v[12] == 381);
    try expect(v[13] == 382);
    try expect(v[14] == 383);
    try expect(v[15] == 384);
    try expect(v[16] == 385);
    try expect(v[17] == 386);
    try expect(v[18] == 387);
    try expect(v[19] == 388);
    try expect(v[20] == 389);
    try expect(v[21] == 390);
    try expect(v[22] == 391);
    try expect(v[23] == 392);
    try expect(v[24] == 393);
    try expect(v[25] == 394);
    try expect(v[26] == 395);
    try expect(v[27] == 396);
    try expect(v[28] == 397);
    try expect(v[29] == 398);
    try expect(v[30] == 399);
    try expect(v[31] == 400);
    c_vector_32_f64(.{
        401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416,
        417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, 431, 432,
    }, 32);
    c_test_vector_32_f64();
}

export fn zig_ret_vector_48_f64() @Vector(48, f64) {
    return .{
        433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 443, 444, 445, 446, 447, 448,
        449, 450, 451, 452, 453, 454, 455, 456, 457, 458, 459, 460, 461, 462, 463, 464,
        465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480,
    };
}
export fn zig_vector_48_f64(v: @Vector(48, f64), i: usize) void {
    expect(v[0] == 481) catch @panic("test failure");
    expect(v[1] == 482) catch @panic("test failure");
    expect(v[2] == 483) catch @panic("test failure");
    expect(v[3] == 484) catch @panic("test failure");
    expect(v[4] == 485) catch @panic("test failure");
    expect(v[5] == 486) catch @panic("test failure");
    expect(v[6] == 487) catch @panic("test failure");
    expect(v[7] == 488) catch @panic("test failure");
    expect(v[8] == 489) catch @panic("test failure");
    expect(v[9] == 490) catch @panic("test failure");
    expect(v[10] == 491) catch @panic("test failure");
    expect(v[11] == 492) catch @panic("test failure");
    expect(v[12] == 493) catch @panic("test failure");
    expect(v[13] == 494) catch @panic("test failure");
    expect(v[14] == 495) catch @panic("test failure");
    expect(v[15] == 496) catch @panic("test failure");
    expect(v[16] == 497) catch @panic("test failure");
    expect(v[17] == 498) catch @panic("test failure");
    expect(v[18] == 499) catch @panic("test failure");
    expect(v[19] == 500) catch @panic("test failure");
    expect(v[20] == 501) catch @panic("test failure");
    expect(v[21] == 502) catch @panic("test failure");
    expect(v[22] == 503) catch @panic("test failure");
    expect(v[23] == 504) catch @panic("test failure");
    expect(v[24] == 505) catch @panic("test failure");
    expect(v[25] == 506) catch @panic("test failure");
    expect(v[26] == 507) catch @panic("test failure");
    expect(v[27] == 508) catch @panic("test failure");
    expect(v[28] == 509) catch @panic("test failure");
    expect(v[29] == 510) catch @panic("test failure");
    expect(v[30] == 511) catch @panic("test failure");
    expect(v[31] == 512) catch @panic("test failure");
    expect(v[32] == 513) catch @panic("test failure");
    expect(v[33] == 514) catch @panic("test failure");
    expect(v[34] == 515) catch @panic("test failure");
    expect(v[35] == 516) catch @panic("test failure");
    expect(v[36] == 517) catch @panic("test failure");
    expect(v[37] == 518) catch @panic("test failure");
    expect(v[38] == 519) catch @panic("test failure");
    expect(v[39] == 520) catch @panic("test failure");
    expect(v[40] == 521) catch @panic("test failure");
    expect(v[41] == 522) catch @panic("test failure");
    expect(v[42] == 523) catch @panic("test failure");
    expect(v[43] == 524) catch @panic("test failure");
    expect(v[44] == 525) catch @panic("test failure");
    expect(v[45] == 526) catch @panic("test failure");
    expect(v[46] == 527) catch @panic("test failure");
    expect(v[47] == 528) catch @panic("test failure");
    expect(i == 48) catch @panic("test failure");
}

extern fn c_ret_vector_48_f64() @Vector(48, f64);
extern fn c_vector_48_f64(@Vector(48, f64), usize) void;
extern fn c_test_vector_48_f64() void;

test "@Vector(48, f64)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_48_f64();
    try expect(v[0] == 529);
    try expect(v[1] == 530);
    try expect(v[2] == 531);
    try expect(v[3] == 532);
    try expect(v[4] == 533);
    try expect(v[5] == 534);
    try expect(v[6] == 535);
    try expect(v[7] == 536);
    try expect(v[8] == 537);
    try expect(v[9] == 538);
    try expect(v[10] == 539);
    try expect(v[11] == 540);
    try expect(v[12] == 541);
    try expect(v[13] == 542);
    try expect(v[14] == 543);
    try expect(v[15] == 544);
    try expect(v[16] == 545);
    try expect(v[17] == 546);
    try expect(v[18] == 547);
    try expect(v[19] == 548);
    try expect(v[20] == 549);
    try expect(v[21] == 550);
    try expect(v[22] == 551);
    try expect(v[23] == 552);
    try expect(v[24] == 553);
    try expect(v[25] == 554);
    try expect(v[26] == 555);
    try expect(v[27] == 556);
    try expect(v[28] == 557);
    try expect(v[29] == 558);
    try expect(v[30] == 559);
    try expect(v[31] == 560);
    try expect(v[32] == 561);
    try expect(v[33] == 562);
    try expect(v[34] == 563);
    try expect(v[35] == 564);
    try expect(v[36] == 565);
    try expect(v[37] == 566);
    try expect(v[38] == 567);
    try expect(v[39] == 568);
    try expect(v[40] == 569);
    try expect(v[41] == 570);
    try expect(v[42] == 571);
    try expect(v[43] == 572);
    try expect(v[44] == 573);
    try expect(v[45] == 574);
    try expect(v[46] == 575);
    try expect(v[47] == 576);
    c_vector_48_f64(.{
        577, 578, 579, 580, 581, 582, 583, 584, 585, 586, 587, 588, 589, 590, 591, 592,
        593, 594, 595, 596, 597, 598, 599, 600, 601, 602, 603, 604, 605, 606, 607, 608,
        609, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621, 622, 623, 624,
    }, 48);
    c_test_vector_48_f64();
}

export fn zig_ret_vector_64_f64() @Vector(64, f64) {
    return .{
        625, 626, 627, 628, 629, 630, 631, 632, 633, 634, 635, 636, 637, 638, 639, 640,
        641, 642, 643, 644, 645, 646, 647, 648, 649, 650, 651, 652, 653, 654, 655, 656,
        657, 658, 659, 660, 661, 662, 663, 664, 665, 666, 667, 668, 669, 670, 671, 672,
        673, 674, 675, 676, 677, 678, 679, 680, 681, 682, 683, 684, 685, 686, 687, 688,
    };
}
export fn zig_vector_64_f64(v: @Vector(64, f64), i: usize) void {
    expect(v[0] == 689) catch @panic("test failure");
    expect(v[1] == 690) catch @panic("test failure");
    expect(v[2] == 691) catch @panic("test failure");
    expect(v[3] == 692) catch @panic("test failure");
    expect(v[4] == 693) catch @panic("test failure");
    expect(v[5] == 694) catch @panic("test failure");
    expect(v[6] == 695) catch @panic("test failure");
    expect(v[7] == 696) catch @panic("test failure");
    expect(v[8] == 697) catch @panic("test failure");
    expect(v[9] == 698) catch @panic("test failure");
    expect(v[10] == 699) catch @panic("test failure");
    expect(v[11] == 700) catch @panic("test failure");
    expect(v[12] == 701) catch @panic("test failure");
    expect(v[13] == 702) catch @panic("test failure");
    expect(v[14] == 703) catch @panic("test failure");
    expect(v[15] == 704) catch @panic("test failure");
    expect(v[16] == 705) catch @panic("test failure");
    expect(v[17] == 706) catch @panic("test failure");
    expect(v[18] == 707) catch @panic("test failure");
    expect(v[19] == 708) catch @panic("test failure");
    expect(v[20] == 709) catch @panic("test failure");
    expect(v[21] == 710) catch @panic("test failure");
    expect(v[22] == 711) catch @panic("test failure");
    expect(v[23] == 712) catch @panic("test failure");
    expect(v[24] == 713) catch @panic("test failure");
    expect(v[25] == 714) catch @panic("test failure");
    expect(v[26] == 715) catch @panic("test failure");
    expect(v[27] == 716) catch @panic("test failure");
    expect(v[28] == 717) catch @panic("test failure");
    expect(v[29] == 718) catch @panic("test failure");
    expect(v[30] == 719) catch @panic("test failure");
    expect(v[31] == 720) catch @panic("test failure");
    expect(v[32] == 721) catch @panic("test failure");
    expect(v[33] == 722) catch @panic("test failure");
    expect(v[34] == 723) catch @panic("test failure");
    expect(v[35] == 724) catch @panic("test failure");
    expect(v[36] == 725) catch @panic("test failure");
    expect(v[37] == 726) catch @panic("test failure");
    expect(v[38] == 727) catch @panic("test failure");
    expect(v[39] == 728) catch @panic("test failure");
    expect(v[40] == 729) catch @panic("test failure");
    expect(v[41] == 730) catch @panic("test failure");
    expect(v[42] == 731) catch @panic("test failure");
    expect(v[43] == 732) catch @panic("test failure");
    expect(v[44] == 733) catch @panic("test failure");
    expect(v[45] == 734) catch @panic("test failure");
    expect(v[46] == 735) catch @panic("test failure");
    expect(v[47] == 736) catch @panic("test failure");
    expect(v[48] == 737) catch @panic("test failure");
    expect(v[49] == 738) catch @panic("test failure");
    expect(v[50] == 739) catch @panic("test failure");
    expect(v[51] == 740) catch @panic("test failure");
    expect(v[52] == 741) catch @panic("test failure");
    expect(v[53] == 742) catch @panic("test failure");
    expect(v[54] == 743) catch @panic("test failure");
    expect(v[55] == 744) catch @panic("test failure");
    expect(v[56] == 745) catch @panic("test failure");
    expect(v[57] == 746) catch @panic("test failure");
    expect(v[58] == 747) catch @panic("test failure");
    expect(v[59] == 748) catch @panic("test failure");
    expect(v[60] == 749) catch @panic("test failure");
    expect(v[61] == 750) catch @panic("test failure");
    expect(v[62] == 751) catch @panic("test failure");
    expect(v[63] == 752) catch @panic("test failure");
    expect(i == 64) catch @panic("test failure");
}

extern fn c_ret_vector_64_f64() @Vector(64, f64);
extern fn c_vector_64_f64(@Vector(64, f64), usize) void;
extern fn c_test_vector_64_f64() void;

test "@Vector(64, f64)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC64()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const v = c_ret_vector_64_f64();
    try expect(v[0] == 753);
    try expect(v[1] == 754);
    try expect(v[2] == 755);
    try expect(v[3] == 756);
    try expect(v[4] == 757);
    try expect(v[5] == 758);
    try expect(v[6] == 759);
    try expect(v[7] == 760);
    try expect(v[8] == 761);
    try expect(v[9] == 762);
    try expect(v[10] == 763);
    try expect(v[11] == 764);
    try expect(v[12] == 765);
    try expect(v[13] == 766);
    try expect(v[14] == 767);
    try expect(v[15] == 768);
    try expect(v[16] == 769);
    try expect(v[17] == 770);
    try expect(v[18] == 771);
    try expect(v[19] == 772);
    try expect(v[20] == 773);
    try expect(v[21] == 774);
    try expect(v[22] == 775);
    try expect(v[23] == 776);
    try expect(v[24] == 777);
    try expect(v[25] == 778);
    try expect(v[26] == 779);
    try expect(v[27] == 780);
    try expect(v[28] == 781);
    try expect(v[29] == 782);
    try expect(v[30] == 783);
    try expect(v[31] == 784);
    try expect(v[32] == 785);
    try expect(v[33] == 786);
    try expect(v[34] == 787);
    try expect(v[35] == 788);
    try expect(v[36] == 789);
    try expect(v[37] == 790);
    try expect(v[38] == 791);
    try expect(v[39] == 792);
    try expect(v[40] == 793);
    try expect(v[41] == 794);
    try expect(v[42] == 795);
    try expect(v[43] == 796);
    try expect(v[44] == 797);
    try expect(v[45] == 798);
    try expect(v[46] == 799);
    try expect(v[47] == 800);
    try expect(v[48] == 801);
    try expect(v[49] == 802);
    try expect(v[50] == 803);
    try expect(v[51] == 804);
    try expect(v[52] == 805);
    try expect(v[53] == 806);
    try expect(v[54] == 807);
    try expect(v[55] == 808);
    try expect(v[56] == 809);
    try expect(v[57] == 810);
    try expect(v[58] == 811);
    try expect(v[59] == 812);
    try expect(v[60] == 813);
    try expect(v[61] == 814);
    try expect(v[62] == 815);
    try expect(v[63] == 816);
    c_vector_64_f64(.{
        817, 818, 819, 820, 821, 822, 823, 824, 825, 826, 827, 828, 829, 830, 831, 832,
        833, 834, 835, 836, 837, 838, 839, 840, 841, 842, 843, 844, 845, 846, 847, 848,
        849, 850, 851, 852, 853, 854, 855, 856, 857, 858, 859, 860, 861, 862, 863, 864,
        865, 866, 867, 868, 869, 870, 871, 872, 873, 874, 875, 876, 877, 878, 879, 880,
    }, 64);
    c_test_vector_64_f64();
}

const Struct_u8 = extern struct {
    a: u8,
};

export fn zig_ret_struct_u8() Struct_u8 {
    return .{ .a = 1 };
}
export fn zig_struct_u8(s: Struct_u8, i: usize) void {
    expect(s.a == 2) catch @panic("test failure");
    expect(i == 3) catch @panic("test failure");
}

extern fn c_ret_struct_u8() Struct_u8;
extern fn c_struct_u8(Struct_u8, usize) void;
extern fn c_test_struct_u8() void;

test "struct u8" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC32()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86 and builtin.os.tag == .windows) return error.SkipZigTest;

    const s = c_ret_struct_u8();
    try expect(s.a == 4);
    c_struct_u8(.{ .a = 5 }, 6);
    c_test_struct_u8();
}

const Struct_u8_u8 = extern struct {
    a: u8,
    b: u8,
};

export fn zig_ret_struct_u8_u8() Struct_u8_u8 {
    return .{ .a = 1, .b = 2 };
}
export fn zig_struct_u8_u8(s: Struct_u8_u8, i: usize) void {
    expect(s.a == 3) catch @panic("test failure");
    expect(s.b == 4) catch @panic("test failure");
    expect(i == 5) catch @panic("test failure");
}

extern fn c_ret_struct_u8_u8() Struct_u8_u8;
extern fn c_struct_u8_u8(Struct_u8_u8, usize) void;
extern fn c_test_struct_u8_u8() void;

test "struct u8, u8" {
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86) return error.SkipZigTest;

    const s = c_ret_struct_u8_u8();
    try expect(s.a == 6);
    try expect(s.b == 7);
    c_struct_u8_u8(.{ .a = 8, .b = 9 }, 10);
    c_test_struct_u8_u8();
}

const Struct_u8_u8_u8 = extern struct {
    a: u8,
    b: u8,
    c: u8,
};

export fn zig_ret_struct_u8_u8_u8() Struct_u8_u8_u8 {
    return .{ .a = 1, .b = 2, .c = 3 };
}
export fn zig_struct_u8_u8_u8(s: Struct_u8_u8_u8, i: usize) void {
    expect(s.a == 4) catch @panic("test failure");
    expect(s.b == 5) catch @panic("test failure");
    expect(s.c == 6) catch @panic("test failure");
    expect(i == 7) catch @panic("test failure");
}

extern fn c_ret_struct_u8_u8_u8() Struct_u8_u8_u8;
extern fn c_struct_u8_u8_u8(Struct_u8_u8_u8, usize) void;
extern fn c_test_struct_u8_u8_u8() void;

test "struct u8, u8, u8" {
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86) return error.SkipZigTest;

    const s = c_ret_struct_u8_u8_u8();
    try expect(s.a == 8);
    try expect(s.b == 9);
    try expect(s.c == 10);
    c_struct_u8_u8_u8(.{ .a = 11, .b = 12, .c = 13 }, 14);
    c_test_struct_u8_u8_u8();
}

const Struct_u8_u8_u8_u8 = extern struct {
    a: u8,
    b: u8,
    c: u8,
    d: u8,
};

export fn zig_ret_struct_u8_u8_u8_u8() Struct_u8_u8_u8_u8 {
    return .{ .a = 1, .b = 2, .c = 3, .d = 4 };
}
export fn zig_struct_u8_u8_u8_u8(s: Struct_u8_u8_u8_u8, i: usize) void {
    expect(s.a == 5) catch @panic("test failure");
    expect(s.b == 6) catch @panic("test failure");
    expect(s.c == 7) catch @panic("test failure");
    expect(s.d == 8) catch @panic("test failure");
    expect(i == 9) catch @panic("test failure");
}

extern fn c_ret_struct_u8_u8_u8_u8() Struct_u8_u8_u8_u8;
extern fn c_struct_u8_u8_u8_u8(Struct_u8_u8_u8_u8, usize) void;
extern fn c_test_struct_u8_u8_u8_u8() void;

test "struct u8, u8, u8, u8" {
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86) return error.SkipZigTest;

    const s = c_ret_struct_u8_u8_u8_u8();
    try expect(s.a == 10);
    try expect(s.b == 11);
    try expect(s.c == 12);
    try expect(s.d == 13);
    c_struct_u8_u8_u8_u8(.{ .a = 14, .b = 15, .c = 16, .d = 17 }, 18);
    c_test_struct_u8_u8_u8_u8();
}

const Struct_u16 = extern struct {
    a: u16,
};

export fn zig_ret_struct_u16() Struct_u16 {
    return .{ .a = 1 };
}
export fn zig_struct_u16(s: Struct_u16, i: usize) void {
    expect(s.a == 2) catch @panic("test failure");
    expect(i == 3) catch @panic("test failure");
}

extern fn c_ret_struct_u16() Struct_u16;
extern fn c_struct_u16(Struct_u16, usize) void;
extern fn c_test_struct_u16() void;

test "struct u16" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC32()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86 and builtin.os.tag == .windows) return error.SkipZigTest;

    const s = c_ret_struct_u16();
    try expect(s.a == 4);
    c_struct_u16(.{ .a = 5 }, 6);
    c_test_struct_u16();
}

const Struct_u16_u16 = extern struct {
    a: u16,
    b: u16,
};

export fn zig_ret_struct_u16_u16() Struct_u16_u16 {
    return .{ .a = 1, .b = 2 };
}
export fn zig_struct_u16_u16(s: Struct_u16_u16, i: usize) void {
    expect(s.a == 3) catch @panic("test failure");
    expect(s.b == 4) catch @panic("test failure");
    expect(i == 5) catch @panic("test failure");
}

extern fn c_ret_struct_u16_u16() Struct_u16_u16;
extern fn c_struct_u16_u16(Struct_u16_u16, usize) void;
extern fn c_test_struct_u16_u16() void;

test "struct u16, u16" {
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86) return error.SkipZigTest;

    const s = c_ret_struct_u16_u16();
    try expect(s.a == 6);
    try expect(s.b == 7);
    c_struct_u16_u16(.{ .a = 8, .b = 9 }, 10);
    c_test_struct_u16_u16();
}

const Struct_u16_u16_u16 = extern struct {
    a: u16,
    b: u16,
    c: u16,
};

export fn zig_ret_struct_u16_u16_u16() Struct_u16_u16_u16 {
    return .{ .a = 1, .b = 2, .c = 3 };
}
export fn zig_struct_u16_u16_u16(s: Struct_u16_u16_u16, i: usize) void {
    expect(s.a == 4) catch @panic("test failure");
    expect(s.b == 5) catch @panic("test failure");
    expect(s.c == 6) catch @panic("test failure");
    expect(i == 7) catch @panic("test failure");
}

extern fn c_ret_struct_u16_u16_u16() Struct_u16_u16_u16;
extern fn c_struct_u16_u16_u16(Struct_u16_u16_u16, usize) void;
extern fn c_test_struct_u16_u16_u16() void;

test "struct u16, u16, u16" {
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isRiscv32()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86) return error.SkipZigTest;

    const s = c_ret_struct_u16_u16_u16();
    try expect(s.a == 8);
    try expect(s.b == 9);
    try expect(s.c == 10);
    c_struct_u16_u16_u16(.{ .a = 11, .b = 12, .c = 13 }, 14);
    c_test_struct_u16_u16_u16();
}

const Struct_u16_u16_u16_u16 = extern struct {
    a: u16,
    b: u16,
    c: u16,
    d: u16,
};

export fn zig_ret_struct_u16_u16_u16_u16() Struct_u16_u16_u16_u16 {
    return .{ .a = 1, .b = 2, .c = 3, .d = 4 };
}
export fn zig_struct_u16_u16_u16_u16(s: Struct_u16_u16_u16_u16, i: usize) void {
    expect(s.a == 5) catch @panic("test failure");
    expect(s.b == 6) catch @panic("test failure");
    expect(s.c == 7) catch @panic("test failure");
    expect(s.d == 8) catch @panic("test failure");
    expect(i == 9) catch @panic("test failure");
}

extern fn c_ret_struct_u16_u16_u16_u16() Struct_u16_u16_u16_u16;
extern fn c_struct_u16_u16_u16_u16(Struct_u16_u16_u16_u16, usize) void;
extern fn c_test_struct_u16_u16_u16_u16() void;

test "struct u16, u16, u16, u16" {
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isRiscv32()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86) return error.SkipZigTest;

    const s = c_ret_struct_u16_u16_u16_u16();
    try expect(s.a == 10);
    try expect(s.b == 11);
    try expect(s.c == 12);
    try expect(s.d == 13);
    c_struct_u16_u16_u16_u16(.{ .a = 14, .b = 15, .c = 16, .d = 17 }, 18);
    c_test_struct_u16_u16_u16_u16();
}

const Struct_u32 = extern struct {
    a: u32,
};

export fn zig_ret_struct_u32() Struct_u32 {
    return .{ .a = 1 };
}
export fn zig_struct_u32(s: Struct_u32, i: usize) void {
    expect(s.a == 2) catch @panic("test failure");
    expect(i == 3) catch @panic("test failure");
}

extern fn c_ret_struct_u32() Struct_u32;
extern fn c_struct_u32(Struct_u32, usize) void;
extern fn c_test_struct_u32() void;

test "struct u32" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC32()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86 and builtin.os.tag == .windows) return error.SkipZigTest;

    const s = c_ret_struct_u32();
    try expect(s.a == 4);
    c_struct_u32(.{ .a = 5 }, 6);
    c_test_struct_u32();
}

const Struct_u32_u32 = extern struct {
    a: u32,
    b: u32,
};

export fn zig_ret_struct_u32_u32() Struct_u32_u32 {
    return .{ .a = 1, .b = 2 };
}
export fn zig_struct_u32_u32(s: Struct_u32_u32, i: usize) void {
    expect(s.a == 3) catch @panic("test failure");
    expect(s.b == 4) catch @panic("test failure");
    expect(i == 5) catch @panic("test failure");
}

extern fn c_ret_struct_u32_u32() Struct_u32_u32;
extern fn c_struct_u32_u32(Struct_u32_u32, usize) void;
extern fn c_test_struct_u32_u32() void;

test "struct u32, u32" {
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isRiscv32()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86 and builtin.os.tag == .windows) return error.SkipZigTest;

    const s = c_ret_struct_u32_u32();
    try expect(s.a == 6);
    try expect(s.b == 7);
    c_struct_u32_u32(.{ .a = 8, .b = 9 }, 10);
    c_test_struct_u32_u32();
}

const Struct_u32_u32_u32 = extern struct {
    a: u32,
    b: u32,
    c: u32,
};

export fn zig_ret_struct_u32_u32_u32() Struct_u32_u32_u32 {
    return .{ .a = 1, .b = 2, .c = 3 };
}
export fn zig_struct_u32_u32_u32(s: Struct_u32_u32_u32, i: usize) void {
    expect(s.a == 4) catch @panic("test failure");
    expect(s.b == 5) catch @panic("test failure");
    expect(s.c == 6) catch @panic("test failure");
    expect(i == 7) catch @panic("test failure");
}

extern fn c_ret_struct_u32_u32_u32() Struct_u32_u32_u32;
extern fn c_struct_u32_u32_u32(Struct_u32_u32_u32, usize) void;
extern fn c_test_struct_u32_u32_u32() void;

test "struct u32, u32, u32" {
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const s = c_ret_struct_u32_u32_u32();
    try expect(s.a == 8);
    try expect(s.b == 9);
    try expect(s.c == 10);
    c_struct_u32_u32_u32(.{ .a = 11, .b = 12, .c = 13 }, 14);
    c_test_struct_u32_u32_u32();
}

const Struct_u32_u32_u32_u32 = extern struct {
    a: u32,
    b: u32,
    c: u32,
    d: u32,
};

export fn zig_ret_struct_u32_u32_u32_u32() Struct_u32_u32_u32_u32 {
    return .{ .a = 1, .b = 2, .c = 3, .d = 4 };
}
export fn zig_struct_u32_u32_u32_u32(s: Struct_u32_u32_u32_u32, i: usize) void {
    expect(s.a == 5) catch @panic("test failure");
    expect(s.b == 6) catch @panic("test failure");
    expect(s.c == 7) catch @panic("test failure");
    expect(s.d == 8) catch @panic("test failure");
    expect(i == 9) catch @panic("test failure");
}

extern fn c_ret_struct_u32_u32_u32_u32() Struct_u32_u32_u32_u32;
extern fn c_struct_u32_u32_u32_u32(Struct_u32_u32_u32_u32, usize) void;
extern fn c_test_struct_u32_u32_u32_u32() void;

test "struct u32, u32, u32, u32" {
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const s = c_ret_struct_u32_u32_u32_u32();
    try expect(s.a == 10);
    try expect(s.b == 11);
    try expect(s.c == 12);
    try expect(s.d == 13);
    c_struct_u32_u32_u32_u32(.{ .a = 14, .b = 15, .c = 16, .d = 17 }, 18);
    c_test_struct_u32_u32_u32_u32();
}

const Struct_u64 = extern struct {
    a: u64,
};

export fn zig_ret_struct_u64() Struct_u64 {
    return .{ .a = 1 };
}
export fn zig_struct_u64(s: Struct_u64, i: usize) void {
    expect(s.a == 2) catch @panic("test failure");
    expect(i == 3) catch @panic("test failure");
}

extern fn c_ret_struct_u64() Struct_u64;
extern fn c_struct_u64(Struct_u64, usize) void;
extern fn c_test_struct_u64() void;

test "struct u64" {
    if (builtin.cpu.arch.isPowerPC32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isRiscv32()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86 and builtin.os.tag == .windows) return error.SkipZigTest;

    const s = c_ret_struct_u64();
    try expect(s.a == 4);
    c_struct_u64(.{ .a = 5 }, 6);
    c_test_struct_u64();
}

const Struct_u64_u64 = extern struct {
    a: u64,
    b: u64,
};

export fn zig_ret_struct_u64_u64() Struct_u64_u64 {
    return .{ .a = 1, .b = 2 };
}
export fn zig_struct_u64_u64(s: Struct_u64_u64, i: usize) void {
    expect(s.a == 3) catch @panic("test failure");
    expect(s.b == 4) catch @panic("test failure");
    expect(i == 1) catch @panic("test failure");
}
export fn zig_1_struct_u64_u64(_: usize, s: Struct_u64_u64, i: usize) void {
    expect(s.a == 5) catch @panic("test failure");
    expect(s.b == 6) catch @panic("test failure");
    expect(i == 2) catch @panic("test failure");
}
export fn zig_2_struct_u64_u64(_: usize, _: usize, s: Struct_u64_u64, i: usize) void {
    expect(s.a == 7) catch @panic("test failure");
    expect(s.b == 8) catch @panic("test failure");
    expect(i == 3) catch @panic("test failure");
}
export fn zig_3_struct_u64_u64(_: usize, _: usize, _: usize, s: Struct_u64_u64, i: usize) void {
    expect(s.a == 9) catch @panic("test failure");
    expect(s.b == 10) catch @panic("test failure");
    expect(i == 4) catch @panic("test failure");
}
export fn zig_4_struct_u64_u64(_: usize, _: usize, _: usize, _: usize, s: Struct_u64_u64, i: usize) void {
    expect(s.a == 11) catch @panic("test failure");
    expect(s.b == 12) catch @panic("test failure");
    expect(i == 5) catch @panic("test failure");
}
export fn zig_5_struct_u64_u64(_: usize, _: usize, _: usize, _: usize, _: usize, s: Struct_u64_u64, i: usize) void {
    expect(s.a == 13) catch @panic("test failure");
    expect(s.b == 14) catch @panic("test failure");
    expect(i == 6) catch @panic("test failure");
}
export fn zig_6_struct_u64_u64(_: usize, _: usize, _: usize, _: usize, _: usize, _: usize, s: Struct_u64_u64, i: usize) void {
    expect(s.a == 15) catch @panic("test failure");
    expect(s.b == 16) catch @panic("test failure");
    expect(i == 7) catch @panic("test failure");
}
export fn zig_7_struct_u64_u64(_: usize, _: usize, _: usize, _: usize, _: usize, _: usize, _: usize, s: Struct_u64_u64, i: usize) void {
    expect(s.a == 17) catch @panic("test failure");
    expect(s.b == 18) catch @panic("test failure");
    expect(i == 8) catch @panic("test failure");
}
export fn zig_8_struct_u64_u64(_: usize, _: usize, _: usize, _: usize, _: usize, _: usize, _: usize, _: usize, s: Struct_u64_u64, i: usize) void {
    expect(s.a == 19) catch @panic("test failure");
    expect(s.b == 20) catch @panic("test failure");
    expect(i == 9) catch @panic("test failure");
}

extern fn c_ret_struct_u64_u64() Struct_u64_u64;
extern fn c_struct_u64_u64(Struct_u64_u64, usize) void;
extern fn c_1_struct_u64_u64(usize, Struct_u64_u64, usize) void;
extern fn c_2_struct_u64_u64(usize, usize, Struct_u64_u64, usize) void;
extern fn c_3_struct_u64_u64(usize, usize, usize, Struct_u64_u64, usize) void;
extern fn c_4_struct_u64_u64(usize, usize, usize, usize, Struct_u64_u64, usize) void;
extern fn c_5_struct_u64_u64(usize, usize, usize, usize, usize, Struct_u64_u64, usize) void;
extern fn c_6_struct_u64_u64(usize, usize, usize, usize, usize, usize, Struct_u64_u64, usize) void;
extern fn c_7_struct_u64_u64(usize, usize, usize, usize, usize, usize, usize, Struct_u64_u64, usize) void;
extern fn c_8_struct_u64_u64(usize, usize, usize, usize, usize, usize, usize, usize, Struct_u64_u64, usize) void;
extern fn c_test_struct_u64_u64() void;

test "struct u64, u64" {
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC32()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const s = c_ret_struct_u64_u64();
    try expect(s.a == 21);
    try expect(s.b == 22);
    c_struct_u64_u64(.{ .a = 23, .b = 24 }, 1);
    c_1_struct_u64_u64(0, .{ .a = 25, .b = 26 }, 2);
    c_2_struct_u64_u64(0, 1, .{ .a = 27, .b = 28 }, 3);
    c_3_struct_u64_u64(0, 1, 2, .{ .a = 29, .b = 30 }, 4);
    c_4_struct_u64_u64(0, 1, 2, 3, .{ .a = 31, .b = 32 }, 5);
    c_5_struct_u64_u64(0, 1, 2, 3, 4, .{ .a = 33, .b = 34 }, 6);
    c_6_struct_u64_u64(0, 1, 2, 3, 4, 5, .{ .a = 35, .b = 36 }, 7);
    c_7_struct_u64_u64(0, 1, 2, 3, 4, 5, 6, .{ .a = 37, .b = 38 }, 8);
    c_8_struct_u64_u64(0, 1, 2, 3, 4, 5, 6, 7, .{ .a = 39, .b = 40 }, 9);
    c_test_struct_u64_u64();
}

const Struct_u64_u64_u64 = extern struct {
    a: u64,
    b: u64,
    c: u64,
};

export fn zig_ret_struct_u64_u64_u64() Struct_u64_u64_u64 {
    return .{ .a = 1, .b = 2, .c = 3 };
}
export fn zig_struct_u64_u64_u64(s: Struct_u64_u64_u64, i: usize) void {
    expect(s.a == 4) catch @panic("test failure");
    expect(s.b == 5) catch @panic("test failure");
    expect(s.c == 6) catch @panic("test failure");
    expect(i == 7) catch @panic("test failure");
}

extern fn c_ret_struct_u64_u64_u64() Struct_u64_u64_u64;
extern fn c_struct_u64_u64_u64(Struct_u64_u64_u64, usize) void;
extern fn c_test_struct_u64_u64_u64() void;

test "struct u64, u64, u64" {
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const s = c_ret_struct_u64_u64_u64();
    try expect(s.a == 8);
    try expect(s.b == 9);
    try expect(s.c == 10);
    c_struct_u64_u64_u64(.{ .a = 11, .b = 12, .c = 13 }, 14);
    c_test_struct_u64_u64_u64();
}

const Struct_u64_u64_u64_u64 = extern struct {
    a: u64,
    b: u64,
    c: u64,
    d: u64,
};

export fn zig_ret_struct_u64_u64_u64_u64() Struct_u64_u64_u64_u64 {
    return .{ .a = 1, .b = 2, .c = 3, .d = 4 };
}
export fn zig_struct_u64_u64_u64_u64(s: Struct_u64_u64_u64_u64, i: usize) void {
    expect(s.a == 5) catch @panic("test failure");
    expect(s.b == 6) catch @panic("test failure");
    expect(s.c == 7) catch @panic("test failure");
    expect(s.d == 8) catch @panic("test failure");
    expect(i == 9) catch @panic("test failure");
}

extern fn c_ret_struct_u64_u64_u64_u64() Struct_u64_u64_u64_u64;
extern fn c_struct_u64_u64_u64_u64(Struct_u64_u64_u64_u64, usize) void;
extern fn c_test_struct_u64_u64_u64_u64() void;

test "struct u64, u64, u64, u64" {
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const s = c_ret_struct_u64_u64_u64_u64();
    try expect(s.a == 10);
    try expect(s.b == 11);
    try expect(s.c == 12);
    try expect(s.d == 13);
    c_struct_u64_u64_u64_u64(.{ .a = 14, .b = 15, .c = 16, .d = 17 }, 18);
    c_test_struct_u64_u64_u64_u64();
}

const Struct_f32 = extern struct {
    a: f32,
};

export fn zig_ret_struct_f32() Struct_f32 {
    return .{ .a = 1 };
}
export fn zig_struct_f32(s: Struct_f32, i: usize) void {
    expect(s.a == 2) catch @panic("test failure");
    expect(i == 3) catch @panic("test failure");
}

extern fn c_ret_struct_f32() Struct_f32;
extern fn c_struct_f32(Struct_f32, usize) void;
extern fn c_test_struct_f32() void;

test "struct f32" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC32()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86 and builtin.os.tag == .windows) return error.SkipZigTest;

    const s = c_ret_struct_f32();
    try expect(s.a == 4);
    c_struct_f32(.{ .a = 5 }, 6);
    c_test_struct_f32();
}

const Struct_f32_f32 = extern struct {
    a: f32,
    b: f32,
};

export fn zig_ret_struct_f32_f32() Struct_f32_f32 {
    return .{ .a = 1, .b = 2 };
}
export fn zig_struct_f32_f32(s: Struct_f32_f32, i: usize) void {
    expect(s.a == 3) catch @panic("test failure");
    expect(s.b == 4) catch @panic("test failure");
    expect(i == 5) catch @panic("test failure");
}

extern fn c_ret_struct_f32_f32() Struct_f32_f32;
extern fn c_struct_f32_f32(Struct_f32_f32, usize) void;
extern fn c_test_struct_f32_f32() void;

test "struct f32, f32" {
    if (builtin.cpu.arch.isArm() and builtin.abi.float() == .soft) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isRiscv32()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86 and builtin.os.tag == .windows) return error.SkipZigTest;

    const s = c_ret_struct_f32_f32();
    try expect(s.a == 6);
    try expect(s.b == 7);
    c_struct_f32_f32(.{ .a = 8, .b = 9 }, 10);
    c_test_struct_f32_f32();
}

const Struct_f32_f32_f32 = extern struct {
    a: f32,
    b: f32,
    c: f32,
};

export fn zig_ret_struct_f32_f32_f32() Struct_f32_f32_f32 {
    return .{ .a = 1, .b = 2, .c = 3 };
}
export fn zig_struct_f32_f32_f32(s: Struct_f32_f32_f32, i: usize) void {
    expect(s.a == 4) catch @panic("test failure");
    expect(s.b == 5) catch @panic("test failure");
    expect(s.c == 6) catch @panic("test failure");
    expect(i == 7) catch @panic("test failure");
}

extern fn c_ret_struct_f32_f32_f32() Struct_f32_f32_f32;
extern fn c_struct_f32_f32_f32(Struct_f32_f32_f32, usize) void;
extern fn c_test_struct_f32_f32_f32() void;

test "struct f32, f32, f32" {
    if (builtin.cpu.arch.isArm() and builtin.abi.float() == .soft) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const s = c_ret_struct_f32_f32_f32();
    try expect(s.a == 8);
    try expect(s.b == 9);
    try expect(s.c == 10);
    c_struct_f32_f32_f32(.{ .a = 11, .b = 12, .c = 13 }, 14);
    c_test_struct_f32_f32_f32();
}

const Struct_f32_f32_f32_f32 = extern struct {
    a: f32,
    b: f32,
    c: f32,
    d: f32,
};

export fn zig_ret_struct_f32_f32_f32_f32() Struct_f32_f32_f32_f32 {
    return .{ .a = 1, .b = 2, .c = 3, .d = 4 };
}
export fn zig_struct_f32_f32_f32_f32(s: Struct_f32_f32_f32_f32, i: usize) void {
    expect(s.a == 5) catch @panic("test failure");
    expect(s.b == 6) catch @panic("test failure");
    expect(s.c == 7) catch @panic("test failure");
    expect(s.d == 8) catch @panic("test failure");
    expect(i == 9) catch @panic("test failure");
}

extern fn c_ret_struct_f32_f32_f32_f32() Struct_f32_f32_f32_f32;
extern fn c_struct_f32_f32_f32_f32(Struct_f32_f32_f32_f32, usize) void;
extern fn c_test_struct_f32_f32_f32_f32() void;

test "struct f32, f32, f32, f32" {
    if (builtin.cpu.arch.isArm() and builtin.abi.float() == .soft) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const s = c_ret_struct_f32_f32_f32_f32();
    try expect(s.a == 10);
    try expect(s.b == 11);
    try expect(s.c == 12);
    try expect(s.d == 13);
    c_struct_f32_f32_f32_f32(.{ .a = 14, .b = 15, .c = 16, .d = 17 }, 18);
    c_test_struct_f32_f32_f32_f32();
}

const Struct_f32_f32_f32_f32_f32 = extern struct {
    a: f32,
    b: f32,
    c: f32,
    d: f32,
    e: f32,
};

export fn zig_ret_struct_f32_f32_f32_f32_f32() Struct_f32_f32_f32_f32_f32 {
    return .{ .a = 1, .b = 2, .c = 3, .d = 4, .e = 5 };
}
export fn zig_struct_f32_f32_f32_f32_f32(s: Struct_f32_f32_f32_f32_f32, i: usize) void {
    expect(s.a == 6) catch @panic("test failure");
    expect(s.b == 7) catch @panic("test failure");
    expect(s.c == 8) catch @panic("test failure");
    expect(s.d == 9) catch @panic("test failure");
    expect(s.e == 10) catch @panic("test failure");
    expect(i == 11) catch @panic("test failure");
}

extern fn c_ret_struct_f32_f32_f32_f32_f32() Struct_f32_f32_f32_f32_f32;
extern fn c_struct_f32_f32_f32_f32_f32(Struct_f32_f32_f32_f32_f32, usize) void;
extern fn c_test_struct_f32_f32_f32_f32_f32() void;

test "struct f32, f32, f32, f32, f32" {
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const s = c_ret_struct_f32_f32_f32_f32_f32();
    try expect(s.a == 12);
    try expect(s.b == 13);
    try expect(s.c == 14);
    try expect(s.d == 15);
    try expect(s.e == 16);
    c_struct_f32_f32_f32_f32_f32(.{ .a = 17, .b = 18, .c = 19, .d = 20, .e = 21 }, 22);
    c_test_struct_f32_f32_f32_f32_f32();
}

const Struct_f32a8 = extern struct {
    a: f32 align(8),
};

export fn zig_ret_struct_f32a8() Struct_f32a8 {
    return .{ .a = 1.25 };
}
export fn zig_struct_f32a8(s: Struct_f32a8, f: f32) void {
    expect(s.a == 2.75) catch @panic("test failure");
    expect(f == 3.5) catch @panic("test failure");
}

extern fn c_ret_struct_f32a8() Struct_f32a8;
extern fn c_struct_f32a8(Struct_f32a8, f32) void;
extern fn c_test_struct_f32a8() void;

test "struct f32 align(8)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isRiscv32()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86) return error.SkipZigTest;

    const s = c_ret_struct_f32a8();
    try expect(s.a == 4.125);
    c_struct_f32a8(.{ .a = 5.375 }, 6.5);
    c_test_struct_f32a8();
}

const Struct_f32a8_f32a8 = extern struct {
    a: f32 align(8),
    b: f32 align(8),
};

export fn zig_ret_struct_f32a8_f32a8() Struct_f32a8_f32a8 {
    return .{ .a = 1.25, .b = 2.75 };
}
export fn zig_struct_f32a8_f32a8(s: Struct_f32a8_f32a8, f: f32) void {
    expect(s.a == 3.125) catch @panic("test failure");
    expect(s.b == 4.375) catch @panic("test failure");
    expect(f == 5.5) catch @panic("test failure");
}

extern fn c_ret_struct_f32a8_f32a8() Struct_f32a8_f32a8;
extern fn c_struct_f32a8_f32a8(Struct_f32a8_f32a8, f32) void;
extern fn c_test_struct_f32a8_f32a8() void;

test "struct f32 align(8), f32 align(8)" {
    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isRISCV()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86) return error.SkipZigTest;

    const s = c_ret_struct_f32a8_f32a8();
    try expect(s.a == 6.625);
    try expect(s.b == 7.875);
    c_struct_f32a8_f32a8(.{ .a = 8.0625, .b = 9.1875 }, 10.5);
    c_test_struct_f32a8_f32a8();
}

const Struct_f32f32_f32 = extern struct {
    a: extern struct { b: f32, c: f32 },
    d: f32,
};

export fn zig_ret_struct_f32f32_f32() Struct_f32f32_f32 {
    return .{ .a = .{ .b = 1.0, .c = 2.0 }, .d = 3.0 };
}
export fn zig_struct_f32f32_f32(s: Struct_f32f32_f32) void {
    expect(s.a.b == 1.0) catch @panic("test failure");
    expect(s.a.c == 2.0) catch @panic("test failure");
    expect(s.d == 3.0) catch @panic("test failure");
}

extern fn c_ret_struct_f32f32_f32() Struct_f32f32_f32;
extern fn c_struct_f32f32_f32(Struct_f32f32_f32) void;
extern fn c_test_struct_f32f32_f32() void;

test "struct {f32, f32}, f32" {
    if (builtin.cpu.arch.isArm() and builtin.abi.float() == .soft) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC32()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const s = c_ret_struct_f32f32_f32();
    try expect(s.a.b == 1.0);
    try expect(s.a.c == 2.0);
    try expect(s.d == 3.0);
    c_struct_f32f32_f32(.{ .a = .{ .b = 1.0, .c = 2.0 }, .d = 3.0 });
    c_test_struct_f32f32_f32();
}

const Struct_f32_f32f32 = extern struct {
    a: f32,
    b: extern struct { c: f32, d: f32 },
};

export fn zig_ret_struct_f32_f32f32() Struct_f32_f32f32 {
    return .{ .a = 1.0, .b = .{ .c = 2.0, .d = 3.0 } };
}
export fn zig_struct_f32_f32f32(s: Struct_f32_f32f32) void {
    expect(s.a == 1.0) catch @panic("test failure");
    expect(s.b.c == 2.0) catch @panic("test failure");
    expect(s.b.d == 3.0) catch @panic("test failure");
}

extern fn c_ret_struct_f32_f32f32() Struct_f32_f32f32;
extern fn c_struct_f32_f32f32(Struct_f32_f32f32) void;
extern fn c_test_struct_f32_f32f32() void;

test "struct f32, {f32, f32}" {
    if (builtin.cpu.arch.isArm() and builtin.abi.float() == .soft) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC32()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const s = c_ret_struct_f32_f32f32();
    try expect(s.a == 1.0);
    try expect(s.b.c == 2.0);
    try expect(s.b.d == 3.0);
    c_struct_f32_f32f32(.{ .a = 1.0, .b = .{ .c = 2.0, .d = 3.0 } });
    c_test_struct_f32_f32f32();
}

const Struct_f64 = extern struct {
    a: f64,
};

export fn zig_ret_struct_f64() Struct_f64 {
    return .{ .a = 1 };
}
export fn zig_struct_f64(s: Struct_f64, i: usize) void {
    expect(s.a == 2) catch @panic("test failure");
    expect(i == 3) catch @panic("test failure");
}

extern fn c_ret_struct_f64() Struct_f64;
extern fn c_struct_f64(Struct_f64, usize) void;
extern fn c_test_struct_f64() void;

test "struct f64" {
    if (builtin.cpu.arch.isArm() and builtin.abi.float() == .soft) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isRiscv32()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86 and builtin.os.tag == .windows) return error.SkipZigTest;

    const s = c_ret_struct_f64();
    try expect(s.a == 4);
    c_struct_f64(.{ .a = 5 }, 6);
    c_test_struct_f64();
}

const Struct_f64_f64 = extern struct {
    a: f64,
    b: f64,
};

export fn zig_ret_struct_f64_f64() Struct_f64_f64 {
    return .{ .a = 1, .b = 2 };
}
export fn zig_struct_f64_f64(s: Struct_f64_f64, i: usize) void {
    expect(s.a == 3) catch @panic("test failure");
    expect(s.b == 4) catch @panic("test failure");
    expect(i == 5) catch @panic("test failure");
}

extern fn c_ret_struct_f64_f64() Struct_f64_f64;
extern fn c_struct_f64_f64(Struct_f64_f64, usize) void;
extern fn c_test_struct_f64_f64() void;

test "struct f64, f64" {
    if (builtin.cpu.arch.isArm() and builtin.abi.float() == .soft) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC32()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const s = c_ret_struct_f64_f64();
    try expect(s.a == 6);
    try expect(s.b == 7);
    c_struct_f64_f64(.{ .a = 8, .b = 9 }, 10);
    c_test_struct_f64_f64();
}

const Struct_f64_f64_f64 = extern struct {
    a: f64,
    b: f64,
    c: f64,
};

export fn zig_ret_struct_f64_f64_f64() Struct_f64_f64_f64 {
    return .{ .a = 1, .b = 2, .c = 3 };
}
export fn zig_struct_f64_f64_f64(s: Struct_f64_f64_f64, i: usize) void {
    expect(s.a == 4) catch @panic("test failure");
    expect(s.b == 5) catch @panic("test failure");
    expect(s.c == 6) catch @panic("test failure");
    expect(i == 7) catch @panic("test failure");
}

extern fn c_ret_struct_f64_f64_f64() Struct_f64_f64_f64;
extern fn c_struct_f64_f64_f64(Struct_f64_f64_f64, usize) void;
extern fn c_test_struct_f64_f64_f64() void;

test "struct f64, f64, f64" {
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC32()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const s = c_ret_struct_f64_f64_f64();
    try expect(s.a == 8);
    try expect(s.b == 9);
    try expect(s.c == 10);
    c_struct_f64_f64_f64(.{ .a = 11, .b = 12, .c = 13 }, 14);
    c_test_struct_f64_f64_f64();
}

const Struct_f64_f64_f64_f64 = extern struct {
    a: f64,
    b: f64,
    c: f64,
    d: f64,
};

export fn zig_ret_struct_f64_f64_f64_f64() Struct_f64_f64_f64_f64 {
    return .{ .a = 1, .b = 2, .c = 3, .d = 4 };
}
export fn zig_struct_f64_f64_f64_f64(s: Struct_f64_f64_f64_f64, i: usize) void {
    expect(s.a == 5) catch @panic("test failure");
    expect(s.b == 6) catch @panic("test failure");
    expect(s.c == 7) catch @panic("test failure");
    expect(s.d == 8) catch @panic("test failure");
    expect(i == 9) catch @panic("test failure");
}

extern fn c_ret_struct_f64_f64_f64_f64() Struct_f64_f64_f64_f64;
extern fn c_struct_f64_f64_f64_f64(Struct_f64_f64_f64_f64, usize) void;
extern fn c_test_struct_f64_f64_f64_f64() void;

test "struct f64, f64, f64, f64" {
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC32()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const s = c_ret_struct_f64_f64_f64_f64();
    try expect(s.a == 10);
    try expect(s.b == 11);
    try expect(s.c == 12);
    try expect(s.d == 13);
    c_struct_f64_f64_f64_f64(.{ .a = 14, .b = 15, .c = 16, .d = 17 }, 18);
    c_test_struct_f64_f64_f64_f64();
}

const Struct_f64_f64_f64_f64_f64 = extern struct {
    a: f64,
    b: f64,
    c: f64,
    d: f64,
    e: f64,
};

export fn zig_ret_struct_f64_f64_f64_f64_f64() Struct_f64_f64_f64_f64_f64 {
    return .{ .a = 1, .b = 2, .c = 3, .d = 4, .e = 5 };
}
export fn zig_struct_f64_f64_f64_f64_f64(s: Struct_f64_f64_f64_f64_f64, i: usize) void {
    expect(s.a == 6) catch @panic("test failure");
    expect(s.b == 7) catch @panic("test failure");
    expect(s.c == 8) catch @panic("test failure");
    expect(s.d == 9) catch @panic("test failure");
    expect(s.e == 10) catch @panic("test failure");
    expect(i == 11) catch @panic("test failure");
}

extern fn c_ret_struct_f64_f64_f64_f64_f64() Struct_f64_f64_f64_f64_f64;
extern fn c_struct_f64_f64_f64_f64_f64(Struct_f64_f64_f64_f64_f64, usize) void;
extern fn c_test_struct_f64_f64_f64_f64_f64() void;

test "struct f64, f64, f64, f64, f64" {
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC32()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const s = c_ret_struct_f64_f64_f64_f64_f64();
    try expect(s.a == 12);
    try expect(s.b == 13);
    try expect(s.c == 14);
    try expect(s.d == 15);
    try expect(s.e == 16);
    c_struct_f64_f64_f64_f64_f64(.{ .a = 17, .b = 18, .c = 19, .d = 20, .e = 21 }, 22);
    c_test_struct_f64_f64_f64_f64_f64();
}

const Struct_u32_Union_u32_u32u32 = extern struct {
    a: u32,
    b: extern union {
        c: extern struct {
            d: u32,
            e: u32,
        },
    },
};

export fn zig_ret_struct_u32_union_u32_u32u32() Struct_u32_Union_u32_u32u32 {
    return .{ .a = 1, .b = .{ .c = .{ .d = 2, .e = 3 } } };
}
export fn zig_struct_u32_union_u32_u32u32(s: Struct_u32_Union_u32_u32u32) void {
    expect(s.a == 1) catch @panic("test failure");
    expect(s.b.c.d == 2) catch @panic("test failure");
    expect(s.b.c.e == 3) catch @panic("test failure");
}

extern fn c_ret_struct_u32_union_u32_u32u32() Struct_u32_Union_u32_u32u32;
extern fn c_struct_u32_union_u32_u32u32(Struct_u32_Union_u32_u32u32) void;
extern fn c_test_struct_u32_union_u32_u32u32() void;

test "struct{u32,union{u32,struct{u32,u32}}}" {
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .loongarch64) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const s = c_ret_struct_u32_union_u32_u32u32();
    try expect(s.a == 1);
    try expect(s.b.c.d == 2);
    try expect(s.b.c.e == 3);
    c_struct_u32_union_u32_u32u32(.{ .a = 1, .b = .{ .c = .{ .d = 2, .e = 3 } } });
    c_test_struct_u32_union_u32_u32u32();
}

const Struct_i32_i32 = extern struct {
    a: i32,
    b: i32,
};
extern fn c_mut_struct_i32_i32(Struct_i32_i32) Struct_i32_i32;
extern fn c_struct_i32_i32(Struct_i32_i32) void;

test "struct i32 i32" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isRiscv32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86 and builtin.os.tag == .windows) return error.SkipZigTest;

    const s: Struct_i32_i32 = .{
        .a = 1,
        .b = 2,
    };
    const mut_res = c_mut_struct_i32_i32(s);
    try expect(s.a == 1);
    try expect(s.b == 2);
    try expect(mut_res.a == 101);
    try expect(mut_res.b == 252);
    c_struct_i32_i32(s);
}

export fn zig_struct_i32_i32(s: Struct_i32_i32) void {
    expect(s.a == 1) catch @panic("test failure: zig_struct_i32_i32 1");
    expect(s.b == 2) catch @panic("test failure: zig_struct_i32_i32 2");
}

const BigStruct = extern struct {
    a: u64,
    b: u64,
    c: u64,
    d: u64,
    e: u8,
};
extern fn c_big_struct(BigStruct) void;

test "big struct" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const s = BigStruct{
        .a = 1,
        .b = 2,
        .c = 3,
        .d = 4,
        .e = 5,
    };
    c_big_struct(s);
}

export fn zig_big_struct(x: BigStruct) void {
    expect(x.a == 1) catch @panic("test failure: zig_big_struct 1");
    expect(x.b == 2) catch @panic("test failure: zig_big_struct 2");
    expect(x.c == 3) catch @panic("test failure: zig_big_struct 3");
    expect(x.d == 4) catch @panic("test failure: zig_big_struct 4");
    expect(x.e == 5) catch @panic("test failure: zig_big_struct 5");
}

const BigUnion = extern union {
    a: BigStruct,
};
extern fn c_big_union(BigUnion) void;

test "big union" {
    if (builtin.cpu.arch.isPowerPC32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const x = BigUnion{
        .a = BigStruct{
            .a = 1,
            .b = 2,
            .c = 3,
            .d = 4,
            .e = 5,
        },
    };
    c_big_union(x);
}

export fn zig_big_union(x: BigUnion) void {
    expect(x.a.a == 1) catch @panic("test failure: zig_big_union a");
    expect(x.a.b == 2) catch @panic("test failure: zig_big_union b");
    expect(x.a.c == 3) catch @panic("test failure: zig_big_union c");
    expect(x.a.d == 4) catch @panic("test failure: zig_big_union d");
    expect(x.a.e == 5) catch @panic("test failure: zig_big_union e");
}

const MedStructMixed = extern struct {
    a: u32,
    b: f32,
    c: f32,
    d: u32 = 0,
};
extern fn c_med_struct_mixed(MedStructMixed) void;
extern fn c_ret_med_struct_mixed() MedStructMixed;

test "medium struct of ints and floats" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const s = MedStructMixed{
        .a = 1234,
        .b = 100.0,
        .c = 1337.0,
    };
    c_med_struct_mixed(s);
    const s2 = c_ret_med_struct_mixed();
    try expect(s2.a == 1234);
    try expect(s2.b == 100.0);
    try expect(s2.c == 1337.0);
}

export fn zig_med_struct_mixed(x: MedStructMixed) void {
    expect(x.a == 1234) catch @panic("test failure");
    expect(x.b == 100.0) catch @panic("test failure");
    expect(x.c == 1337.0) catch @panic("test failure");
}

const SmallPackedStruct = packed struct(u8) {
    a: u2,
    b: u2,
    c: u2,
    d: u2,
};
extern fn c_small_packed_struct(SmallPackedStruct) void;
extern fn c_ret_small_packed_struct() SmallPackedStruct;

export fn zig_small_packed_struct(x: SmallPackedStruct) void {
    expect(x.a == 0) catch @panic("test failure");
    expect(x.b == 1) catch @panic("test failure");
    expect(x.c == 2) catch @panic("test failure");
    expect(x.d == 3) catch @panic("test failure");
}

test "small packed struct" {
    const s = SmallPackedStruct{ .a = 0, .b = 1, .c = 2, .d = 3 };
    c_small_packed_struct(s);
    const s2 = c_ret_small_packed_struct();
    try expect(s2.a == 0);
    try expect(s2.b == 1);
    try expect(s2.c == 2);
    try expect(s2.d == 3);
}

const BigPackedStruct = packed struct(u128) {
    a: u64,
    b: u64,
};
extern fn c_big_packed_struct(BigPackedStruct) void;
extern fn c_ret_big_packed_struct() BigPackedStruct;

export fn zig_big_packed_struct(x: BigPackedStruct) void {
    expect(x.a == 1) catch @panic("test failure");
    expect(x.b == 2) catch @panic("test failure");
}

test "big packed struct" {
    if (!have_i128) return error.SkipZigTest;

    const s = BigPackedStruct{ .a = 1, .b = 2 };
    c_big_packed_struct(s);
    const s2 = c_ret_big_packed_struct();
    try expect(s2.a == 1);
    try expect(s2.b == 2);
}

const SplitStructInt = extern struct {
    a: u64,
    b: u8,
    c: u32,
};
extern fn c_split_struct_ints(SplitStructInt) void;

test "split struct of ints" {
    if (builtin.cpu.arch == .x86) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const s = SplitStructInt{
        .a = 1234,
        .b = 100,
        .c = 1337,
    };
    c_split_struct_ints(s);
}

export fn zig_split_struct_ints(x: SplitStructInt) void {
    expect(x.a == 1234) catch @panic("test failure");
    expect(x.b == 100) catch @panic("test failure");
    expect(x.c == 1337) catch @panic("test failure");
}

const SplitStructMixed = extern struct {
    a: u64,
    b: u8,
    c: f32,
};
extern fn c_split_struct_mixed(SplitStructMixed) void;
extern fn c_ret_split_struct_mixed() SplitStructMixed;

test "split struct of ints and floats" {
    if (builtin.cpu.arch == .x86) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const s = SplitStructMixed{
        .a = 1234,
        .b = 100,
        .c = 1337.0,
    };
    c_split_struct_mixed(s);
    const s2 = c_ret_split_struct_mixed();
    try expect(s2.a == 1234);
    try expect(s2.b == 100);
    try expect(s2.c == 1337.0);
}

export fn zig_split_struct_mixed(x: SplitStructMixed) void {
    expect(x.a == 1234) catch @panic("test failure");
    expect(x.b == 100) catch @panic("test failure");
    expect(x.c == 1337.0) catch @panic("test failure");
}

extern fn c_big_struct_both(BigStruct) BigStruct;

test "sret and byval together" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const s = BigStruct{
        .a = 1,
        .b = 2,
        .c = 3,
        .d = 4,
        .e = 5,
    };
    const y = c_big_struct_both(s);
    try expect(y.a == 10);
    try expect(y.b == 11);
    try expect(y.c == 12);
    try expect(y.d == 13);
    try expect(y.e == 14);
}

export fn zig_big_struct_both(x: BigStruct) BigStruct {
    expect(x.a == 30) catch @panic("test failure");
    expect(x.b == 31) catch @panic("test failure");
    expect(x.c == 32) catch @panic("test failure");
    expect(x.d == 33) catch @panic("test failure");
    expect(x.e == 34) catch @panic("test failure");
    const s = BigStruct{
        .a = 20,
        .b = 21,
        .c = 22,
        .d = 23,
        .e = 24,
    };
    return s;
}

export fn zig_ret_bool() bool {
    return true;
}
export fn zig_ret_u8() u8 {
    return 0xff;
}
export fn zig_ret_u16() u16 {
    return 0xffff;
}
export fn zig_ret_u32() u32 {
    return 0xffffffff;
}
export fn zig_ret_u64() u64 {
    return 0xffffffffffffffff;
}
export fn zig_ret_i8() i8 {
    return -1;
}
export fn zig_ret_i16() i16 {
    return -1;
}
export fn zig_ret_i32() i32 {
    return -1;
}
export fn zig_ret_i64() i64 {
    return -1;
}

export fn zig_ret_med_struct_mixed() MedStructMixed {
    return .{
        .a = 1234,
        .b = 100.0,
        .c = 1337.0,
    };
}

export fn zig_ret_split_struct_mixed() SplitStructMixed {
    return .{
        .a = 1234,
        .b = 100,
        .c = 1337.0,
    };
}

extern fn c_ret_bool() bool;
extern fn c_ret_u8() u8;
extern fn c_ret_u16() u16;
extern fn c_ret_u32() u32;
extern fn c_ret_u64() u64;
extern fn c_ret_i8() i8;
extern fn c_ret_i16() i16;
extern fn c_ret_i32() i32;
extern fn c_ret_i64() i64;

test "integer return types" {
    try expect(c_ret_bool() == true);

    try expect(c_ret_u8() == 0xff);
    try expect(c_ret_u16() == 0xffff);
    try expect(c_ret_u32() == 0xffffffff);
    try expect(c_ret_u64() == 0xffffffffffffffff);

    try expect(c_ret_i8() == -1);
    try expect(c_ret_i16() == -1);
    try expect(c_ret_i32() == -1);
    try expect(c_ret_i64() == -1);
}

const StructWithArray = extern struct {
    a: i32,
    padding: [4]u8,
    b: i64,
};
extern fn c_struct_with_array(StructWithArray) void;
extern fn c_ret_struct_with_array() StructWithArray;

test "Struct with array as padding." {
    if (builtin.cpu.arch == .x86) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    c_struct_with_array(.{ .a = 1, .padding = undefined, .b = 2 });

    const x = c_ret_struct_with_array();
    try expect(x.a == 4);
    try expect(x.b == 155);
}

const FloatArrayStruct = extern struct {
    origin: extern struct {
        x: f64,
        y: f64,
    },
    size: extern struct {
        width: f64,
        height: f64,
    },
};

extern fn c_float_array_struct(FloatArrayStruct) void;
extern fn c_ret_float_array_struct() FloatArrayStruct;

test "Float array like struct" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    c_float_array_struct(.{
        .origin = .{
            .x = 5,
            .y = 6,
        },
        .size = .{
            .width = 7,
            .height = 8,
        },
    });

    const x = c_ret_float_array_struct();
    try expect(x.origin.x == 1);
    try expect(x.origin.y == 2);
    try expect(x.size.width == 3);
    try expect(x.size.height == 4);
}

//=== Helpers for struct test ===//
pub inline fn expectOk(c_err: c_int) !void {
    if (c_err != 0) {
        std.debug.print("ABI mismatch on field v{d}.\n", .{c_err});
        return error.TestExpectedEqual;
    }
}

/// Tests for Double + Char struct
const DC = extern struct { v1: f64, v2: u8 };
test "DC: Zig passes to C" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isRISCV()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    try expectOk(c_assert_DC(.{ .v1 = -0.25, .v2 = 15 }));
}
test "DC: Zig returns to C" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isRISCV()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    try expectOk(c_assert_ret_DC());
}
test "DC: C passes to Zig" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isRISCV()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    try expectOk(c_send_DC());
}
test "DC: C returns to Zig" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isRISCV()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    try expectEqual(DC{ .v1 = -0.25, .v2 = 15 }, c_ret_DC());
}

pub extern fn c_assert_DC(lv: DC) c_int;
pub extern fn c_assert_ret_DC() c_int;
pub extern fn c_send_DC() c_int;
pub extern fn c_ret_DC() DC;
pub export fn zig_assert_DC(lv: DC) c_int {
    var err: c_int = 0;
    if (lv.v1 != -0.25) err = 1;
    if (lv.v2 != 15) err = 2;
    if (err != 0) std.debug.print("Received {}", .{lv});
    return err;
}
pub export fn zig_ret_DC() DC {
    return .{ .v1 = -0.25, .v2 = 15 };
}

/// Tests for Char + Float + FloatRect struct
const CFF = extern struct { v1: u8, v2: f32, v3: f32 };

test "CFF: Zig passes to C" {
    if (builtin.target.cpu.arch == .x86) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    try expectOk(c_assert_CFF(.{ .v1 = 39, .v2 = 0.875, .v3 = 1.0 }));
}
test "CFF: Zig returns to C" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    try expectOk(c_assert_ret_CFF());
}
test "CFF: C passes to Zig" {
    if (builtin.target.cpu.arch == .x86) return error.SkipZigTest;
    if (builtin.cpu.arch.isRISCV() and builtin.mode != .Debug) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    try expectOk(c_send_CFF());
}
test "CFF: C returns to Zig" {
    if (builtin.cpu.arch.isRISCV() and builtin.mode != .Debug) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    try expectEqual(CFF{ .v1 = 39, .v2 = 0.875, .v3 = 1.0 }, c_ret_CFF());
}
pub extern fn c_assert_CFF(lv: CFF) c_int;
pub extern fn c_assert_ret_CFF() c_int;
pub extern fn c_send_CFF() c_int;
pub extern fn c_ret_CFF() CFF;
pub export fn zig_assert_CFF(lv: CFF) c_int {
    var err: c_int = 0;
    if (lv.v1 != 39) err = 1;
    if (lv.v2 != 0.875) err = 2;
    if (lv.v3 != 1.0) err = 3;
    if (err != 0) std.debug.print("Received {}", .{lv});
    return err;
}
pub export fn zig_ret_CFF() CFF {
    return .{ .v1 = 39, .v2 = 0.875, .v3 = 1.0 };
}

/// Tests for Pointer + Double struct
const PD = extern struct { v1: ?*anyopaque, v2: f64 };

test "PD: Zig passes to C" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86 and builtin.os.tag == .windows) return error.SkipZigTest;
    try expectOk(c_assert_PD(.{ .v1 = null, .v2 = 0.5 }));
}
test "PD: Zig returns to C" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    try expectOk(c_assert_ret_PD());
}
test "PD: C passes to Zig" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86 and builtin.os.tag == .windows) return error.SkipZigTest;
    try expectOk(c_send_PD());
}
test "PD: C returns to Zig" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    try expectEqual(PD{ .v1 = null, .v2 = 0.5 }, c_ret_PD());
}
pub extern fn c_assert_PD(lv: PD) c_int;
pub extern fn c_assert_ret_PD() c_int;
pub extern fn c_send_PD() c_int;
pub extern fn c_ret_PD() PD;
pub export fn zig_c_assert_PD(lv: PD) c_int {
    var err: c_int = 0;
    if (lv.v1 != null) err = 1;
    if (lv.v2 != 0.5) err = 2;
    if (err != 0) std.debug.print("Received {}", .{lv});
    return err;
}
pub export fn zig_ret_PD() PD {
    return .{ .v1 = null, .v2 = 0.5 };
}
pub export fn zig_assert_PD(lv: PD) c_int {
    var err: c_int = 0;
    if (lv.v1 != null) err = 1;
    if (lv.v2 != 0.5) err = 2;
    if (err != 0) std.debug.print("Received {}", .{lv});
    return err;
}

const ByRef = extern struct {
    val: c_int,
    arr: [15]c_int,
};
extern fn c_modify_by_ref_param(ByRef) ByRef;

test "C function modifies by ref param" {
    if (builtin.cpu.arch.isPowerPC32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const res = c_modify_by_ref_param(.{ .val = 1, .arr = undefined });
    try expect(res.val == 42);
}

const ByVal = extern struct {
    origin: extern struct {
        x: c_ulong,
        y: c_ulong,
        z: c_ulong,
    },
    size: extern struct {
        width: c_ulong,
        height: c_ulong,
        depth: c_ulong,
    },
};

extern fn c_func_ptr_byval(*anyopaque, *anyopaque, ByVal, c_ulong, *anyopaque, c_ulong) void;
test "C function that takes byval struct called via function pointer" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    var fn_ptr = &c_func_ptr_byval;
    _ = &fn_ptr;
    fn_ptr(
        @as(*anyopaque, @ptrFromInt(1)),
        @as(*anyopaque, @ptrFromInt(2)),
        ByVal{
            .origin = .{ .x = 9, .y = 10, .z = 11 },
            .size = .{ .width = 12, .height = 13, .depth = 14 },
        },
        @as(c_ulong, 3),
        @as(*anyopaque, @ptrFromInt(4)),
        @as(c_ulong, 5),
    );
}

extern fn c_f16(f16) f16;
test "f16 bare" {
    if (builtin.cpu.arch == .x86_64) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS()) return error.SkipZigTest;
    if (builtin.cpu.arch.isRISCV()) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch.isWasm()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;

    if (builtin.cpu.arch.isArm()) return error.SkipZigTest;

    const a = c_f16(12);
    try expect(a == 34);
}

const f16_struct = extern struct {
    a: f16,
};
extern fn c_f16_struct(f16_struct) f16_struct;
test "f16 struct" {
    if (builtin.target.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.target.cpu.arch.isPowerPC32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isArm() and builtin.mode != .Debug) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86 and builtin.os.tag == .windows) return error.SkipZigTest;

    const a = c_f16_struct(.{ .a = 12 });
    try expect(a.a == 34);
}

extern fn c_f80(f80) f80;
test "f80 bare" {
    if (!have_f80) return error.SkipZigTest;

    const a = c_f80(12.34);
    try expect(@as(f64, @floatCast(a)) == 56.78);
}

const f80_struct = extern struct {
    a: f80,
};
extern fn c_f80_struct(f80_struct) f80_struct;
test "f80 struct" {
    if (!have_f80) return error.SkipZigTest;

    const a = c_f80_struct(.{ .a = 12.34 });
    try expect(@as(f64, @floatCast(a.a)) == 56.78);
}

const f80_extra_struct = extern struct {
    a: f80,
    b: c_int,
};
extern fn c_f80_extra_struct(f80_extra_struct) f80_extra_struct;
test "f80 extra struct" {
    if (!have_f80) return error.SkipZigTest;

    const a = c_f80_extra_struct(.{ .a = 12.34, .b = 42 });
    try expect(@as(f64, @floatCast(a.a)) == 56.78);
    try expect(a.b == 24);
}

export fn zig_f128(x: f128) f128 {
    expect(x == 12) catch @panic("test failure");
    return 34;
}
extern fn c_f128(f128) f128;
test "f128 bare" {
    if (!have_f128) return error.SkipZigTest;

    const a = c_f128(12.34);
    try expect(@as(f64, @floatCast(a)) == 56.78);
}

const f128_struct = extern struct {
    a: f128,
};
export fn zig_f128_struct(a: f128_struct) f128_struct {
    expect(a.a == 12345) catch @panic("test failure");
    return .{ .a = 98765 };
}
extern fn c_f128_struct(f128_struct) f128_struct;
test "f128 struct" {
    if (!have_f128) return error.SkipZigTest;

    const a = c_f128_struct(.{ .a = 12.34 });
    try expect(@as(f64, @floatCast(a.a)) == 56.78);

    const b = c_f128_f128_struct(.{ .a = 12.34, .b = 87.65 });
    try expect(@as(f64, @floatCast(b.a)) == 56.78);
    try expect(@as(f64, @floatCast(b.b)) == 43.21);
}

const f128_f128_struct = extern struct {
    a: f128,
    b: f128,
};
export fn zig_f128_f128_struct(a: f128_f128_struct) f128_f128_struct {
    expect(a.a == 13) catch @panic("test failure");
    expect(a.b == 57) catch @panic("test failure");
    return .{ .a = 24, .b = 68 };
}
extern fn c_f128_f128_struct(f128_f128_struct) f128_f128_struct;
test "f128 f128 struct" {
    if (!have_f128) return error.SkipZigTest;

    const a = c_f128_struct(.{ .a = 12.34 });
    try expect(@as(f64, @floatCast(a.a)) == 56.78);

    const b = c_f128_f128_struct(.{ .a = 12.34, .b = 87.65 });
    try expect(@as(f64, @floatCast(b.a)) == 56.78);
    try expect(@as(f64, @floatCast(b.b)) == 43.21);
}

// The stdcall attribute on C functions is ignored when compiled on non-x86
const stdcall_callconv: std.builtin.CallingConvention = if (builtin.cpu.arch == .x86) .{ .x86_stdcall = .{} } else .c;

extern fn stdcall_scalars(i8, i16, i32, f32, f64) callconv(stdcall_callconv) void;
test "Stdcall ABI scalars" {
    stdcall_scalars(1, 2, 3, 4.0, 5.0);
}

const Coord2 = extern struct {
    x: i16,
    y: i16,
};

extern fn stdcall_coord2(Coord2, Coord2, Coord2) callconv(stdcall_callconv) Coord2;
test "Stdcall ABI structs" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;
    if (builtin.cpu.arch == .x86 and builtin.os.tag == .windows) return error.SkipZigTest;

    const res = stdcall_coord2(
        .{ .x = 0x1111, .y = 0x2222 },
        .{ .x = 0x3333, .y = 0x4444 },
        .{ .x = 0x5555, .y = 0x6666 },
    );
    try expect(res.x == 123);
    try expect(res.y == 456);
}

extern fn stdcall_big_union(BigUnion) callconv(stdcall_callconv) void;
test "Stdcall ABI big union" {
    if (builtin.cpu.arch.isPowerPC32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    const x = BigUnion{
        .a = BigStruct{
            .a = 1,
            .b = 2,
            .c = 3,
            .d = 4,
            .e = 5,
        },
    };
    stdcall_big_union(x);
}

extern fn c_explict_win64(ByRef) callconv(.{ .x86_64_win = .{} }) ByRef;
test "explicit Win64 calling convention" {
    if (builtin.cpu.arch != .x86_64) return error.SkipZigTest;

    const res = c_explict_win64(.{ .val = 1, .arr = undefined });
    try expect(res.val == 42);
}

extern fn c_explict_sys_v(ByRef) callconv(.{ .x86_64_sysv = .{} }) ByRef;
test "explicit SysV calling convention" {
    if (builtin.cpu.arch != .x86_64) return error.SkipZigTest;

    const res = c_explict_sys_v(.{ .val = 1, .arr = undefined });
    try expect(res.val == 42);
}

const byval_tail_callsite_attr = struct {
    const struct_Point = extern struct {
        x: f64,
        y: f64,
    };
    const struct_Size = extern struct {
        width: f64,
        height: f64,
    };
    const struct_Rect = extern struct {
        origin: struct_Point,
        size: struct_Size,
    };

    const Point = extern struct {
        x: f64,
        y: f64,
    };

    const Size = extern struct {
        width: f64,
        height: f64,
    };

    const MyRect = extern struct {
        origin: Point,
        size: Size,

        fn run(self: MyRect) f64 {
            return c_byval_tail_callsite_attr(cast(self));
        }

        fn cast(self: MyRect) struct_Rect {
            const ptr: *const struct_Rect = @ptrCast(&self);
            return ptr.*;
        }

        extern fn c_byval_tail_callsite_attr(struct_Rect) f64;
    };
};

test "byval tail callsite attribute" {
    if (builtin.cpu.arch.isMIPS64()) return error.SkipZigTest;
    if (builtin.cpu.arch.isPowerPC32()) return error.SkipZigTest;
    if (builtin.cpu.arch.isLoongArch()) return error.SkipZigTest;
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest;

    // Originally reported at https://github.com/ziglang/zig/issues/16290
    // the bug was that the extern function had the byval attribute, but
    // zig did not put the byval attribute at the callsite. Some LLVM optimization
    // passes would then pass undefined for that parameter.
    var v: byval_tail_callsite_attr.MyRect = .{
        .origin = .{ .x = 1, .y = 2 },
        .size = .{ .width = 3, .height = 4 },
    };
    try expect(v.run() == 3.0);
}

test "x86 fastcall calling convention" {
    if (builtin.cpu.arch != .x86 or builtin.os.tag != .windows or builtin.abi != .msvc) return error.SkipZigTest;

    const static = struct {
        const fastcall: std.builtin.CallingConvention = .{ .x86_fastcall = .{} };

        extern fn c_fastcall_check(a: c_int, b: f32, c: *anyopaque, d: f64, e: c_int) callconv(fastcall) void;
        export fn zig_fastcall_check(a: c_int, b: f32, c: *anyopaque, d: f64, e: c_int) callconv(fastcall) void {
            if (a != 1) @panic("test failure");
            if (b != 2.0) @panic("test failure");
            if (@intFromPtr(c) != 3) @panic("test failure");
            if (d != 4.0) @panic("test failure");
            if (e != 5) @panic("test failure");
        }

        const SRet = extern struct {
            a: i32,
            b: i32,
            c: i32,
        };
        extern fn c_fastcall_sret() callconv(fastcall) SRet;
        export fn zig_fastcall_sret() callconv(fastcall) SRet {
            return .{
                .a = 1,
                .b = 2,
                .c = 3,
            };
        }

        const NoSRet = extern struct {
            a: i8,
            b: i16,
        };
        extern fn c_fastcall_no_sret() callconv(fastcall) NoSRet;
        export fn zig_fastcall_no_sret() callconv(fastcall) NoSRet {
            return .{
                .a = 1,
                .b = 2,
            };
        }

        const NoSRetF32F32 = extern struct {
            a: f32,
            b: f32,
        };
        extern fn c_fastcall_no_sret_f32_f32() callconv(fastcall) NoSRetF32F32;
        export fn zig_fastcall_no_sret_f32_f32() callconv(fastcall) NoSRetF32F32 {
            return .{
                .a = 1,
                .b = 2,
            };
        }

        const NoSRetF64 = extern struct {
            a: f64,
        };
        extern fn c_fastcall_no_sret_f64() callconv(fastcall) NoSRetF64;
        export fn zig_fastcall_no_sret_f64() callconv(fastcall) NoSRetF64 {
            return .{
                .a = 1,
            };
        }

        extern fn c_fastcall_ret_f32() callconv(fastcall) f32;
        export fn zig_fastcall_ret_f32() callconv(fastcall) f32 {
            return 1;
        }

        extern fn c_fastcall_ret_f64() callconv(fastcall) f64;
        export fn zig_fastcall_ret_f64() callconv(fastcall) f64 {
            return 1;
        }

        extern fn run_c_fastcall_tests() void;
    };

    static.c_fastcall_check(1, 2.0, @ptrFromInt(3), 4.0, 5);

    {
        const s = static.c_fastcall_sret();
        try expect(s.a == 1);
        try expect(s.b == 2);
        try expect(s.c == 3);
    }
    {
        const s = static.c_fastcall_no_sret();
        try expect(s.a == 1);
        try expect(s.b == 2);
    }
    {
        const s = static.c_fastcall_no_sret_f32_f32();
        try expect(s.a == 1);
        try expect(s.b == 2);
    }
    {
        const s = static.c_fastcall_no_sret_f64();
        try expect(s.a == 1);
    }
    {
        const s = static.c_fastcall_ret_f32();
        try expect(s == 1);
    }
    {
        const s = static.c_fastcall_ret_f64();
        try expect(s == 1);
    }

    static.run_c_fastcall_tests();
}

test "x86 vectorcall calling convention" {
    if (builtin.cpu.arch != .x86 or builtin.os.tag != .windows or builtin.abi != .msvc) return error.SkipZigTest;

    const static = struct {
        extern fn c_vectorcall_check(a: c_int, b: f32, c: f64, d: *anyopaque, e: f32, f: f64, g: f64, h: f32, i: f32, j: c_int) callconv(.{ .x86_vectorcall = .{} }) void;
        export fn zig_vectorcall_check(a: c_int, b: f32, c: f64, d: *anyopaque, e: f32, f: f64, g: f64, h: f32, i: f32, j: c_int) callconv(.{ .x86_vectorcall = .{} }) void {
            if (a != 1) @panic("test failure");
            if (b != 2.0) @panic("test failure");
            if (c != 3.0) @panic("test failure");
            if (@intFromPtr(d) != 4) @panic("test failure");
            if (e != 5.0) @panic("test failure");
            if (f != 6.0) @panic("test failure");
            if (g != 7.0) @panic("test failure");
            if (h != 8.0) @panic("test failure");
            if (i != 9.0) @panic("test failure");
            if (j != 10) @panic("test failure");
        }
    };
    static.c_vectorcall_check(1, 2.0, 3.0, @ptrFromInt(4), 5.0, 6.0, 7.0, 8.0, 9.0, 10);
}

extern fn c_win64_varargs_u64_f64_u64_f64(...) void;
extern fn c_win64_varargs_f64_u64_f64_u64(...) void;

test "win64 varargs" {
    if (builtin.cpu.arch != .x86_64 or builtin.os.tag != .windows) return error.SkipZigTest;

    const Opv = extern struct {};
    c_win64_varargs_u64_f64_u64_f64(
        @as(Opv, .{}),
        @as(f32, 1),
        @as(Opv, .{}),
        @as(f32, 2.0),
        @as(Opv, .{}),
        @as(f64, 3),
        @as(Opv, .{}),
        @as(f64, 4.0),
        @as(Opv, .{}),
    );
    c_win64_varargs_f64_u64_f64_u64(
        @as(Opv, .{}),
        @as(f32, 5),
        @as(Opv, .{}),
        @as(f32, 6.0),
        @as(Opv, .{}),
        @as(f64, 7),
        @as(Opv, .{}),
        @as(f64, 8.0),
        @as(Opv, .{}),
    );
}

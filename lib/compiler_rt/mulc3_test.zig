const std = @import("std");
const math = std.math;
const expect = std.testing.expect;

const Complex = @import("../compiler_rt.zig").Complex;
const impl = @import("mulc3.zig");
const mul_cf16 = impl.mul_cf16;
const mul_cf32 = impl.mul_cf32;
const mul_cf64 = impl.mul_cf64;
const mul_cf80 = impl.mul_cf80;
const mul_cf128 = impl.mul_cf128;

test "mulc3" {
    try testMul(f16, mul_cf16);
    try testMul(f32, mul_cf32);
    try testMul(f64, mul_cf64);
    try testMul(f80, mul_cf80);
    try testMul(f128, mul_cf128);
}

fn testMul(comptime T: type, comptime f: fn (Complex(T), Complex(T)) Complex(T)) !void {
    {
        const result = f(.{ .real = 1.0, .imag = 0.0 }, .{ .real = -1.0, .imag = 0.0 });
        try expect(result.real == -1.0);
        try expect(math.isPositiveZero(result.imag));
    }
    {
        const result = f(.{ .real = 1.0, .imag = 0.0 }, .{ .real = -4.0, .imag = 0.0 });
        try expect(result.real == -4.0);
        try expect(math.isPositiveZero(result.imag));
    }
    {
        // if one operand is an infinity and the other operand is a nonzero finite number or an infinity,
        // then the result of the * operator is an infinity;
        const result = f(.{ .real = math.inf(T), .imag = -math.inf(T) }, .{ .real = 1.0, .imag = 0.0 });
        try expect(math.isPositiveInf(result.real));
        try expect(math.isNegativeInf(result.imag));
    }
    {
        // if one operand is an infinity and the other operand is a nonzero finite number or an infinity,
        // then the result of the * operator is an infinity;
        const result = f(.{ .real = math.inf(T), .imag = -1.0 }, .{ .real = 1.0, .imag = math.inf(T) });
        try expect(math.isPositiveInf(result.real));
        try expect(math.isPositiveInf(result.imag));
    }
}

const std = @import("std");
const math = std.math;
const expect = std.testing.expect;

const Complex = @import("../compiler_rt.zig").Complex;

const impl = @import("divc3.zig");
const div_cf16 = impl.div_cf16;
const div_cf32 = impl.div_cf32;
const div_cf64 = impl.div_cf64;
const div_cf80 = impl.div_cf80;
const div_cf128 = impl.div_cf128;

test "divc3" {
    try testDiv(f16, div_cf16);
    try testDiv(f32, div_cf32);
    try testDiv(f64, div_cf64);
    try testDiv(f80, div_cf80);
    try testDiv(f128, div_cf128);
}

fn testDiv(comptime T: type, comptime f: fn (Complex(T), Complex(T)) Complex(T)) !void {
    {
        const result = f(.{ .real = 1.0, .imag = 0.0 }, .{ .real = -1.0, .imag = 0.0 });
        try expect(result.real == -1.0);
        try expect(math.isNegativeZero(result.imag));
    }
    {
        const result = f(.{ .real = 1.0, .imag = 0.0 }, .{ .real = -4.0, .imag = 0.0 });
        try expect(result.real == -0.25);
        try expect(math.isNegativeZero(result.imag));
    }
    {
        // if the first operand is an infinity and the second operand is a finite number, then the
        // resultult of the / operator is an infinity;
        const result = f(.{ .real = -math.inf(T), .imag = 0.0 }, .{ .real = -4.0, .imag = 1.0 });
        try expect(math.isPositiveInf(result.real));
        try expect(math.isPositiveInf(result.imag));
    }
    {
        // if the first operand is a finite number and the second operand is an infinity, then the
        // result of the / operator is a zero;
        const result = f(.{ .real = 17.2, .imag = 0.0 }, .{ .real = -math.inf(T), .imag = 0.0 });
        try expect(math.isNegativeZero(result.real));
        try expect(math.isNegativeZero(result.imag));
    }
    {
        // if the first operand is a nonzero finite number or an infinity and the second operand is
        // a zero, then the result of the / operator is an infinity
        const result = f(.{ .real = 1.1, .imag = 0.1 }, .{ .real = 0.0, .imag = 0.0 });
        try expect(math.isPositiveInf(result.real));
        try expect(math.isPositiveInf(result.imag));
    }
}

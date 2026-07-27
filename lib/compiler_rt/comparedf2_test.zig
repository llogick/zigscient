// Ported from:
//
// https://github.com/llvm/llvm-project/commit/d674d96bc56c0f377879d01c9d8dfdaaa7859cdb/compiler-rt/test/builtins/Unit/comparedf2_test.c

const std = @import("std");
const builtin = @import("builtin");

const compiler_rt = @import("../compiler_rt.zig");

const impl = @import("comparef.zig");
const Order = impl.Order;
const cmp_f64 = impl.cmp_f64;
const unord_f64 = impl.unord_f64;

const arguments = [_]f64{
    std.math.nan(f64),
    -std.math.inf(f64),
    -0x1.fffffffffffffp1023,
    -0x1.0000000000001p0 - 0x1.0000000000000p0,
    -0x1.fffffffffffffp-1,
    -0x1.0000000000000p-1022,
    -0x0.fffffffffffffp-1022,
    -0x0.0000000000001p-1022,
    -0.0,
    0.0,
    0x0.0000000000001p-1022,
    0x0.fffffffffffffp-1022,
    0x1.0000000000000p-1022,
    0x1.fffffffffffffp-1,
    0x1.0000000000000p0,
    0x1.0000000000001p0,
    0x1.fffffffffffffp1023,
    std.math.inf(f64),
};

test "compare f64" {
    for (arguments[0..], 0..) |arg_i, i| {
        for (arguments[0..], 0..) |arg_j, j| {
            const expected_unord = i == 0 or j == 0;
            const expected_order: ?Order = if (expected_unord) null else switch (std.math.order(
                if (i >= 9) i - 1 else i,
                if (j >= 9) j - 1 else j,
            )) {
                .lt => .lt,
                .eq => .eq,
                .gt => .gt,
            };
            try std.testing.expect(expected_order == cmp_f64(arg_i, arg_j));
            try std.testing.expect(expected_unord == unord_f64(arg_i, arg_j));
        }
    }
}

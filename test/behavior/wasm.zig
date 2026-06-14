const std = @import("std");
const expect = std.testing.expect;
const builtin = @import("builtin");

test "memory size and grow" {
    var prev = @wasmMemorySize(0);
    _ = &prev;
    try expect(prev == @wasmMemoryGrow(0, 1));
    try expect(prev + 1 == @wasmMemorySize(0));
}

test "asm .i32.add" {
    const a: u32 = std.math.maxInt(u32);
    const b: u32 = 3;
    const result = asm (
        \\ local.get %[a]
        \\ local.get %[b]
        \\ i32.add
        \\ local.set %[ret]
        : [ret] "=r" (-> u32),
        : [a] "r" (a),
          [b] "r" (b),
    );

    try expect(result == 2);
}

test "asm .i64.clz" {
    const a: u64 = 1;
    const result = asm (
        \\ local.get %[a]
        \\ i64.clz
        \\ local.set %[ret]
        : [ret] "=r" (-> u64),
        : [a] "r" (a),
    );

    try expect(result == 63);
}

test "asm .i32.const" {
    const result = asm (
        \\ i32.const 12
        \\ local.set %[ret]
        : [ret] "=r" (-> u32),
    );

    try expect(result == 12);
}

test "asm .i64.const" {
    const result = asm (
        \\ i64.const 42
        \\ local.set %[ret]
        : [ret] "=r" (-> u64),
    );

    try expect(result == 42);
}

test "asm .f32.const" {
    const result = asm (
        \\ f32.const 1.5
        \\ local.set %[ret]
        : [ret] "=r" (-> f32),
    );

    try expect(result == 1.5);
}

test "asm .f64.const" {
    const result = asm (
        \\ f64.const 2.25
        \\ local.set %[ret]
        : [ret] "=r" (-> f64),
    );

    try expect(result == 2.25);
}

test "asm .local.get" {
    const a: u32 = 77;
    const result = asm (
        \\ local.get %[a]
        \\ local.set %[ret]
        : [ret] "=r" (-> u32),
        : [a] "r" (a),
    );

    try expect(result == 77);
}

test "asm .local.set" {
    const result = asm (
        \\ i32.const 55
        \\ local.set %[ret]
        : [ret] "=r" (-> u32),
    );

    try expect(result == 55);
}

test "asm .local.tee" {
    const a: u32 = 3;
    const result = asm (
        \\ local.get %[a]
        \\ local.tee %[ret]
        \\ drop
        : [ret] "=r" (-> u32),
        : [a] "r" (a),
    );

    try expect(result == 3);
}

test "asm .memory.copy" {
    var src: [8]u8 = .{ 1, 2, 3, 4, 5, 6, 7, 8 };
    var dst: [8]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0 };

    asm volatile (
        \\ local.get %[dst]
        \\ local.get %[src]
        \\ i32.const 8
        \\ memory.copy 0, 0
        :
        : [dst] "r" (@intFromPtr(&dst)),
          [src] "r" (@intFromPtr(&src)),
    );

    try std.testing.expectEqualSlices(u8, &src, &dst);
}

test "asm .memory.fill" {
    var buf: [8]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0 };

    asm volatile (
        \\ local.get %[dst]
        \\ i32.const 2
        \\ i32.const 8
        \\ memory.fill 0
        :
        : [dst] "r" (@intFromPtr(&buf)),
    );

    try std.testing.expectEqualSlices(u8, &.{ 2, 2, 2, 2, 2, 2, 2, 2 }, &buf);
}

test "asm .i64.load and .i64.store" {
    var slot: u64 = 0;
    const value: u64 = 0x4444;

    const result = asm (
        \\ local.get %[ptr]
        \\ local.get %[value]
        \\ i64.store 0:p2align=0
        \\ local.get %[ptr]
        \\ i64.load 0
        \\ local.set %[ret]
        : [ret] "=r" (-> u64),
        : [ptr] "r" (@intFromPtr(&slot)),
          [value] "r" (value),
    );

    try expect(result == value);
    try expect(slot == value);
}

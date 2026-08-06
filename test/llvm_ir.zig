pub fn addCases(cases: *tests.LlvmIrContext) void {
    cases.addMatches("nonnull ptr load",
        \\export fn entry(ptr: *i16) i16 {
        \\    return ptr.*;
        \\}
    , &.{
        "ptr nonnull",
        "load i16, ptr %0",
    }, .{});

    cases.addMatches("nonnull ptr store",
        \\export fn entry(ptr: *i16) void {
        \\    ptr.* = 42;
        \\}
    , &.{
        "ptr nonnull",
        "store i16 42, ptr %0",
    }, .{});

    cases.addMatches("unused acquire atomic ptr load",
        \\export fn entry(ptr: *i16) void {
        \\    _ = @atomicLoad(i16, ptr, .acquire);
        \\}
    , &.{
        "load atomic i16, ptr %0 acquire",
    }, .{});

    cases.addMatches("unused unordered atomic volatile ptr load",
        \\export fn entry(ptr: *volatile i16) void {
        \\    _ = @atomicLoad(i16, ptr, .unordered);
        \\}
    , &.{
        "load atomic volatile i16, ptr %0 unordered",
    }, .{});

    cases.addMatches("unused volatile ptr load",
        \\export fn entry(ptr: *volatile i16) void {
        \\    _ = ptr.*;
        \\}
    , &.{
        "load volatile i16, ptr %0",
    }, .{});

    cases.addMatches("dead volatile ptr store",
        \\export fn entry(ptr: *volatile i16) void {
        \\    ptr.* = 123;
        \\    ptr.* = 321;
        \\}
    , &.{
        "store volatile i16 123, ptr %0",
        "store volatile i16 321, ptr %0",
    }, .{});

    cases.addMatches("unused volatile slice load",
        \\export fn entry(ptr: *volatile i16) void {
        \\    entry2(ptr[0..1]);
        \\}
        \\fn entry2(ptr: []volatile i16) void {
        \\    _ = ptr[0];
        \\}
    , &.{
        "load volatile i16, ptr",
    }, .{});

    cases.addMatches("dead volatile slice store",
        \\export fn entry(ptr: *volatile i16) void {
        \\    entry2(ptr[0..1]);
        \\}
        \\fn entry2(ptr: []volatile i16) void {
        \\    ptr[0] = 123;
        \\    ptr[0] = 321;
        \\}
    , &.{
        "store volatile i16 123, ptr",
        "store volatile i16 321, ptr",
    }, .{});

    cases.addMatches("allowzero ptr load",
        \\export fn entry(ptr: *allowzero i16) i16 {
        \\    return ptr.*;
        \\}
    , &.{
        "null_pointer_is_valid",
        "load i16, ptr %0",
    }, .{});

    cases.addMatches("allowzero ptr store",
        \\export fn entry(ptr: *allowzero i16) void {
        \\    ptr.* = 42;
        \\}
    , &.{
        "null_pointer_is_valid",
        "store i16 42, ptr %0",
    }, .{});

    cases.addMatches("allowzero slice load",
        \\export fn entry(ptr: *allowzero i16) i16 {
        \\    return entry2(ptr[0..1]);
        \\}
        \\fn entry2(ptr: []allowzero i16) i16 {
        \\    return ptr[0];
        \\}
    , &.{
        "null_pointer_is_valid",
        "load i16, ptr",
    }, .{});

    cases.addMatches("allowzero slice store",
        \\export fn entry(ptr: *allowzero i16) void {
        \\    entry2(ptr[0..1]);
        \\}
        \\fn entry2(ptr: []allowzero i16) void {
        \\    ptr[0] = 42;
        \\}
    , &.{
        "null_pointer_is_valid",
        "store i16 42, ptr",
    }, .{});

    cases.addMatches("load and store bool",
        \\export fn foo(a: *bool, b: *align(2) bool) void {
        \\    const tmp = a.*;
        \\    a.* = b.*;
        \\    b.* = tmp;
        \\}
    , &.{
        // TODO: this should all be one multiline string literal, but `-femit-llvm-ir` is currently
        // emitting CRLF on Windows, which is a pain to handle here. In future that option will emit
        // unoptimized LLVM IR emitted directly from Zig, so that bug will go away.
        "  %3 = load i8, ptr %0, align 1",
        "  %4 = trunc nuw i8 %3 to i1",
        "  %5 = load i8, ptr %1, align 2",
        "  %6 = trunc nuw i8 %5 to i1",
        "  %7 = zext i1 %6 to i8",
        "  store i8 %7, ptr %0, align 1",
        "  %8 = zext i1 %4 to i8",
        "  store i8 %8, ptr %1, align 2",
    }, .{ .strip = true });
}

const std = @import("std");
const tests = @import("tests.zig");

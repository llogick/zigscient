const std = @import("../std.zig");
const Allocator = std.mem.Allocator;
const Smith = std.testing.Smith;

const oracle = @import("parser_generated_oracle.zig");

test "fuzz std.zig.Ast.parse() against generated oracle" {
    try std.testing.fuzz({}, fuzzAgainstOracle, .{});
}

fn fuzzAgainstOracle(_: void, smith: *Smith) !void {
    var buffer: [1 << 14]u8 = undefined;
    const len = smith.slice(buffer[0 .. buffer.len - 1]);
    buffer[len] = 0;
    const source = buffer[0..len :0];

    checkAgainstOracle(source) catch |err| switch (err) {
        error.MaxDepth => return error.SkipZigTest,
        else => |e| return e,
    };
}

test "max depth" {
    try std.testing.expectError(error.MaxDepth, checkAgainstOracle("((((("));
    _ = checkAgainstOracle("((((") catch |err| switch (err) {
        error.MaxDepth => try std.testing.expect(false),
        else => |e| return e,
    };
}

// Found using AFL++
test "operator whitespace" {
    try checkAgainstOracle(
        \\test {
        \\    _!= 0;
        \\}
    );
    try checkAgainstOracle(
        \\test{{\\
        \\*0;}}
    );
}

// Found using AFL++
test "doc comment or division operator" {
    try checkAgainstOracle("0=0///\n0");
}

// Found using AFL++
test "double ampersand" {
    try checkAgainstOracle("0=0&&0"); // error
    try checkAgainstOracle("test{&&0;}"); // ok
}

// Found using AFL++
test "newline required before doc comment not at start of file" {
    try checkAgainstOracle("0,///\n0"); // error
    try checkAgainstOracle("///\n0"); // ok
    try checkAgainstOracle(" ///\n0"); // ok
    try checkAgainstOracle("\n///\n0"); // ok
    try checkAgainstOracle("///"); // error
    try checkAgainstOracle("///\n//!");
    try checkAgainstOracle("///\ntest {}");
    try checkAgainstOracle("///\ncomptime 0");
}

// Found using AFL++
test "extra capture in for loop" {
    try checkAgainstOracle("for(0)|t,r|0");
}

// Found using AFL++
test "expression nesting" {
    try checkAgainstOracle("test{*comptime 0 == 0;}");
}

// Found using AFL++
test "comptime fn" {
    try checkAgainstOracle("comptime fn()0");
}

// Found using AFL++
test "return asterisk" {
    try checkAgainstOracle("test{return*!0;}");
}

// Found using AFL++
test "fn container field" {
    try checkAgainstOracle("fn()0");
}

// Found using AFL++
test "at newline string" {
    try checkAgainstOracle(
        \\@
        \\""
    );
}

// Found using AFL++
test "string lit" {
    try checkAgainstOracle(
        \\"\\"
    );
}

// Found using AFL++
test "dot question" {
    try checkAgainstOracle("0. ?");
}

// Found using AFL++
test "volatile const" {
    try checkAgainstOracle("*volatile\nconst\n0");
}

// Found using AFL++
test "addrspace align" {
    try checkAgainstOracle("*addrspace(0) align(0) 0");
    try checkAgainstOracle("*align(0) addrspace(0) 0");
    try checkAgainstOracle("[*]addrspace(0) align(0) 0");
    try checkAgainstOracle("[*]align(0) addrspace(0) 0");
}

// Found using AFL++
test "catch capture whitespace" {
    try checkAgainstOracle("test{0 catch |h|0;}");
}

// Found using AFL++
test "byte order mark" {
    // https://en.wikipedia.org/wiki/Byte_order_mark
    try checkAgainstOracle("\xef\xbb\xbf");
    try checkAgainstOracle("\xef\xbb\xbf///\n0");
}

// Found using AFL++
test "nosuspend multi assign" {
    try checkAgainstOracle("test{nosuspend*0,var _=0;}");
}

// Found using AFL++
test "bin op at end of file" {
    try checkAgainstOracle(
        \\test {
        \\    _ = 00
        \\|
    );
}

// Found using AFL++
test "resume block chained compare ops" {
    try checkAgainstOracle("test{resume{0 > 0;} > 0 > 0;}");
}

// Found using AFL++
test "for multiassign" {
    try checkAgainstOracle("test{for(0)|t|0,const w=0;}");
}

fn checkAgainstOracle(source: [:0]const u8) !void {
    var fba_buf: [1 << 18]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&fba_buf);

    const expected = try oracle.parse(source);

    // It is important to disable recovery for fuzz testing.
    // Consider the case where there is a parse error right at the beginning of the file,
    // followed by a valid declaration with a million nested parens. The oracle will not
    // skip this input due to the max depth being exceeded since the oracle hits a parse
    // error right away and does no recovery. However, std.zig.Ast.parse() does recovery
    // by default and will hit a stack overflow rather than returning after the parser error.
    // Stack overflows are not interesting and we do not want the fuzzer to be able to find them.
    const ast = try std.zig.Ast.parse(fba.allocator(), source, .{ .recover = false });

    errdefer logBadSource(source, ast);
    try std.testing.expectEqual(expected, ast.errors.len == 0);
}

fn logBadSource(source: []const u8, ast: std.zig.Ast) void {
    @disableInstrumentation();
    var buf: [256]u8 = undefined;
    const ls = std.debug.lockStderr(&buf);
    defer std.debug.unlockStderr();
    logBadSourceInner(source, ls.terminal(), ast) catch {};
}

fn logBadSourceInner(source: []const u8, t: std.Io.Terminal, ast: std.zig.Ast) std.Io.Writer.Error!void {
    @disableInstrumentation();
    try logSourceInner(source, t);
    const w = t.writer;

    try w.writeAll("=== Parse Errors ===\n");
    for (ast.errors) |err| {
        const loc = ast.tokenLocation(0, err.token);
        try w.print("{}:{}: ", .{ loc.line + 1, loc.column + 1 });
        try ast.renderError(err, w);
        try w.writeByte('\n');
    }
}

pub fn logSource(source: []const u8) void {
    @disableInstrumentation();
    var buf: [256]u8 = undefined;
    const ls = std.debug.lockStderr(&buf);
    defer std.debug.unlockStderr();
    logSourceInner(source, ls.terminal()) catch {};
}

fn logSourceInner(source: []const u8, t: std.Io.Terminal) std.Io.Writer.Error!void {
    @disableInstrumentation();
    const w = t.writer;

    t.setColor(.dim) catch {};
    try w.writeAll("=== Source ===\n");
    t.setColor(.reset) catch {};

    var line: usize = 1;
    try w.print("{: >5} ", .{line});
    for (source) |c| switch (c) {
        ' '...0x7e => try w.writeByte(c),
        '\n' => {
            line += 1;
            try w.print("\n{: >5} ", .{line});
        },
        '\r' => {
            t.setColor(.cyan) catch {};
            try w.writeAll("\\r");
            t.setColor(.reset) catch {};
        },
        '\t' => {
            t.setColor(.cyan) catch {};
            try w.writeAll("\\t");
            t.setColor(.reset) catch {};
        },
        else => {
            t.setColor(.cyan) catch {};
            try w.print("\\x{x:0>2}", .{c});
            t.setColor(.reset) catch {};
        },
    };
    try w.writeByte('\n');
}

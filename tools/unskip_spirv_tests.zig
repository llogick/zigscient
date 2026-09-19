const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Ast = std.zig.Ast;

const usage =
    \\Usage: unskip_spirv_tests <zig> <test_runner> <test_cmd> [test/behavior/*.zig ...]
    \\
    \\For example:
    \\zig run tools/unskip_spirv_tests.zig -- zig-out/bin/zig \
    \\    ../zig-spirv-test-executor/src/test_runner.zig \
    \\    ../zig-spirv-test-executor/zig-out/bin/zig-spirv-test-executor [files...]
    \\
    \\Runs every behavior test that is skipped on stage2_spirv in isolation and
    \\removes the skip if the test passes.
    \\
;

const Test = struct {
    body: Ast.Node.Index,
    name: []const u8,
    skip: ?Ast.Node.Index,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    var args = try init.minimal.args.iterateAllocator(arena);
    _ = args.skip();
    const zig = args.next() orelse std.process.fatal(usage, .{});
    const test_runner = args.next() orelse std.process.fatal(usage, .{});
    const test_cmd = args.next() orelse std.process.fatal(usage, .{});

    var files: std.ArrayList([]const u8) = .empty;
    while (args.next()) |path| try files.append(arena, path);

    if (files.items.len == 0) {
        var dir = try Io.Dir.openDir(.cwd(), io, "test/behavior", .{ .iterate = true });
        defer dir.close(io);

        var it = dir.iterate();
        while (try it.next(io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".zig")) continue;
            const path = try std.fs.path.join(arena, &.{ "test/behavior", entry.name });
            const source = try Io.Dir.readFileAlloc(.cwd(), io, path, arena, .unlimited);
            if (std.mem.find(u8, source, "stage2_spirv") != null) {
                try files.append(arena, path);
            }
        }
    }

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const progress = std.Progress.start(io, .{ .estimated_total_items = files.items.len });
    const cache_dir = init.environ_map.get("ZIG_LOCAL_CACHE_DIR") orelse ".zig-cache";
    const variant_dir = try std.fs.path.join(arena, &.{ cache_dir, "unskip" });
    try Io.Dir.createDirPath(.cwd(), io, variant_dir);

    var failures: std.array_hash_map.String(std.ArrayList([]const u8)) = .empty;
    var total_removed: usize = 0;
    var files_changed: usize = 0;
    for (files.items) |path| {
        const basename = std.fs.path.basename(path);
        const source = try Io.Dir.readFileAlloc(.cwd(), io, path, arena, .unlimited);
        const ast = try Ast.parse(arena, try arena.dupeSentinel(u8, source, 0), .{});
        if (ast.errors.len != 0) std.process.fatal("{s}: parse error", .{path});

        var tests: std.ArrayList(Test) = .empty;
        var skips: usize = 0;
        for (ast.rootDecls()) |decl| {
            if (ast.nodeTag(decl) != .test_decl) continue;
            const name_token, const body = ast.nodeData(decl).opt_token_and_node;
            const token = name_token.unwrap() orelse continue;
            const name = if (ast.tokenTag(token) == .string_literal)
                try std.zig.string_literal.parseAlloc(arena, ast.tokenSlice(token))
            else
                ast.tokenSlice(token);

            var buffer: [2]Ast.Node.Index = undefined;
            const skip: ?Ast.Node.Index = for (ast.blockStatements(&buffer, body) orelse &.{}) |statement| {
                const if_full = ast.fullIf(statement) orelse continue;
                if (ast.nodeTag(if_full.ast.cond_expr) != .equal_equal) continue;
                _, const rhs = ast.nodeData(if_full.ast.cond_expr).node_and_node;
                if (!std.mem.eql(u8, ast.getNodeSource(rhs), ".stage2_spirv")) continue;
                if (ast.nodeTag(if_full.ast.then_expr) != .@"return") continue;
                const value = ast.nodeData(if_full.ast.then_expr).opt_node.unwrap() orelse continue;
                if (!std.mem.eql(u8, ast.getNodeSource(value), "error.SkipZigTest")) continue;
                break statement;
            } else null;
            skips += @intFromBool(skip != null);

            try tests.append(arena, .{ .body = body, .name = name, .skip = skip });
        }

        if (skips == 0) {
            progress.completeOne();
            continue;
        }

        const file_node = progress.start(basename, skips);
        defer file_node.end();
        const variant_path = try std.fs.path.join(arena, &.{ variant_dir, basename });

        var removed: Ast.Render.Fixups = .{};
        for (tests.items) |candidate| {
            const skip = candidate.skip orelse continue;
            const test_node = file_node.start(candidate.name, 0);
            defer test_node.end();

            var fixups: Ast.Render.Fixups = .{};
            try fixups.omit_nodes.put(arena, skip, {});
            for (tests.items) |other| {
                if (other.body == candidate.body) continue;
                try fixups.replace_nodes_with_string.put(arena, other.body, "{ return error.SkipZigTest; }");
            }

            var variant: Io.Writer.Allocating = .init(arena);
            try ast.render(arena, &variant.writer, fixups);
            try Io.Dir.writeFile(.cwd(), io, .{ .sub_path = variant_path, .data = variant.written() });

            const signature: []const u8 = signature: {
                const result = std.process.run(arena, io, .{
                    .argv = &.{
                        zig,              "test",          variant_path,
                        "--test-runner",  test_runner,     "-target",
                        "spirv64-vulkan", "-mcpu",         "vulkan_v1_2+variable_pointers+int64",
                        "-fno-llvm",      "--zig-lib-dir", "lib",
                        "--test-cmd",     test_cmd,        "--test-cmd-bin",
                    },
                    .timeout = .{ .duration = .{ .raw = .fromSeconds(120), .clock = .awake } },
                    .progress_node = test_node,
                }) catch |err| switch (err) {
                    error.Timeout => break :signature "timeout",
                    else => |e| return e,
                };

                if (result.term.success()) {
                    try removed.omit_nodes.put(arena, skip, {});
                    std.debug.print("{s}: removed skip for {s}\n", .{ basename, candidate.name });
                    continue;
                }

                const output = try std.mem.concat(arena, u8, &.{ result.stdout, result.stderr });
                var lines = std.mem.splitScalar(u8, output, '\n');
                while (lines.next()) |line| {
                    const rest = std.mem.cutPrefix(u8, line, "error: line ") orelse continue;
                    const colon = std.mem.findScalar(u8, rest, ':') orelse continue;
                    if (!allDigits(rest[0..colon])) continue;
                    break :signature try normalize(arena, "spirv-val: ", rest[colon + 1 ..]);
                }
                lines.reset();

                while (lines.next()) |line| {
                    const rest = std.mem.cutPrefix(u8, line, "thread ") orelse continue;
                    const panic = std.mem.find(u8, rest, " panic: ") orelse continue;
                    if (std.mem.findScalar(u8, rest[0..panic], ' ') != null) continue;
                    break :signature try normalize(arena, "panic: ", rest[panic + " panic: ".len ..]);
                }
                lines.reset();

                while (lines.next()) |line| {
                    const marker = std.mem.find(u8, line, ": error: ") orelse continue;
                    const location = line[0..marker];
                    const line_colon = std.mem.findScalarLast(u8, location, ':') orelse continue;
                    const file_colon = std.mem.findScalarLast(u8, location[0..line_colon], ':') orelse continue;
                    if (std.mem.findScalar(u8, location[0..file_colon], ' ') != null) continue;
                    if (!allDigits(location[file_colon + 1 .. line_colon])) continue;
                    if (!allDigits(location[line_colon + 1 ..])) continue;
                    const message = line[marker + ": error: ".len ..];
                    break :signature try normalize(arena, "compile error: ", message);
                }
                lines.reset();

                while (lines.next()) |line| {
                    const rest = std.mem.cutPrefix(u8, line, "error: ") orelse continue;
                    break :signature try normalize(arena, "error: ", rest);
                }

                if (std.mem.trim(u8, output, &std.ascii.whitespace).len > 0) {
                    break :signature "unknown failure (no error: line found)";
                }
                break :signature "no output";
            };

            const gop = try failures.getOrPut(arena, signature);
            if (!gop.found_existing) gop.value_ptr.* = .empty;
            const failed_test = try std.fmt.allocPrint(arena, "{s} :: {s}", .{ basename, candidate.name });
            try gop.value_ptr.append(arena, failed_test);
        }

        std.debug.print("{s}: {d}/{d} skips removed\n", .{ basename, removed.omit_nodes.count(), skips });
        Io.Dir.deleteFile(.cwd(), io, variant_path) catch {};
        if (removed.omit_nodes.count() == 0) continue;

        var final: Io.Writer.Allocating = .init(arena);
        try ast.render(arena, &final.writer, removed);
        const rendered = try Ast.parse(arena, try arena.dupeSentinel(u8, final.written(), 0), .{});
        const formatted = try rendered.renderAlloc(arena);
        try Io.Dir.writeFile(.cwd(), io, .{ .sub_path = path, .data = formatted });
        total_removed += removed.omit_nodes.count();
        files_changed += 1;
    }

    progress.end();

    try stdout.print("\nDone: removed {d} spirv skips across {d} files\n", .{ total_removed, files_changed });
    if (failures.count() > 0) {
        var total_failures: usize = 0;
        for (failures.values()) |failed_tests| total_failures += failed_tests.items.len;
        try stdout.print("\nMost common blockers ({d} failing attempts, {d} unique signatures):\n", .{
            total_failures,
            failures.count(),
        });

        const Ctx = struct {
            failed_tests: []const std.ArrayList([]const u8),

            pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
                return ctx.failed_tests[a].items.len > ctx.failed_tests[b].items.len;
            }
        };
        failures.sort(Ctx{ .failed_tests = failures.values() });

        for (failures.keys()[0..@min(failures.count(), 30)], failures.values()) |signature, failed_tests| {
            const count = failed_tests.items.len;
            const percent = @as(f64, @floatFromInt(count)) * 100 / @as(f64, @floatFromInt(total_failures));
            try stdout.print("{d:4}  ({d:5.1}%)  {s}\n", .{ count, percent, signature });
            for (failed_tests.items) |failed_test| try stdout.print("      {s}\n", .{failed_test});
        }
    }
    try stdout.flush();
}

fn allDigits(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

fn normalize(arena: Allocator, prefix: []const u8, message: []const u8) ![]u8 {
    const source = try arena.dupeSentinel(u8, std.mem.trim(u8, message, &std.ascii.whitespace), 0);
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, prefix);
    var tokenizer: std.zig.Tokenizer = .init(source);
    var end: usize = 0;
    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) break;
        try out.appendSlice(arena, source[end..token.loc.start]);
        end = token.loc.end;
        const text = source[token.loc.start..token.loc.end];
        try out.appendSlice(arena, switch (token.tag) {
            .number_literal => "<n>",
            .char_literal, .string_literal => "<str>",
            .identifier => if (token.loc.start > 0 and source[token.loc.start - 1] == '%') "<id>" else text,
            else => text,
        });
    }
    try out.appendSlice(arena, source[end..]);
    return out.items[0..@min(out.items.len, prefix.len + 200)];
}

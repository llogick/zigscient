const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;
const Preprocessor = @import("preprocessor");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    const zig_src_mingw_lib_path = args[1];

    const mingw_include_path = try Dir.path.join(arena, &.{
        zig_src_mingw_lib_path, "def-include",
    });
    const mingw_libcommon_path = try Dir.path.join(arena, &.{
        zig_src_mingw_lib_path, "lib-common",
    });

    var mingw_libcommon_dir = Dir.cwd().openDir(io, mingw_libcommon_path, .{ .iterate = true }) catch |err| {
        std.log.err("unable to open directory {s}: {t}", .{ mingw_libcommon_path, err });
        std.process.exit(1);
    };
    defer mingw_libcommon_dir.close(io);

    var walker = try mingw_libcommon_dir.walk(arena);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;

        var fail = false;
        for (&targets) |*target| {
            var target_arena: std.heap.ArenaAllocator = .init(init.gpa);
            defer target_arena.deinit();

            const pp_arena = target_arena.allocator();
            const file_path = try Dir.path.join(pp_arena, &.{ mingw_libcommon_path, entry.path });

            const aro = pp: {
                const target_triple = try target.zigTriple(pp_arena);
                const target_arg = try std.fmt.allocPrint(pp_arena, "--target={s}", .{target_triple});
                const result = std.process.run(pp_arena, io, .{
                    .argv = &.{
                        "arocc",
                        "-E",
                        target_arg,
                        "--no-line-commands",
                        "-nostdinc",
                        "-I",
                        mingw_include_path,
                        file_path,
                    },
                }) catch |err| {
                    std.log.err("unable to execute arocc: {t}", .{err});
                    std.process.exit(1);
                };
                if (result.term.exited != 0) {
                    std.log.err("error executing arocc: {s}", .{result.stderr});
                    std.process.exit(result.term.exited);
                }
                break :pp result.stdout;
            };

            const native = pp: {
                var aw: Io.Writer.Allocating = .init(pp_arena);
                errdefer aw.deinit();

                var pp: Preprocessor = .{
                    .io = io,
                    .arena = pp_arena,
                    .include_dir = mingw_include_path,
                    .target = target,
                };

                pp.preprocess(file_path) catch |err| {
                    std.log.err("error preprocessing file {s} for target {t}: {t}", .{ entry.path, target.cpu.arch, err });
                    fail = true;
                    continue;
                };
                pp.prettyPrintTokens(&aw.writer) catch |err| {
                    std.log.err("error printing tokens for file {s} for target {t}: {t}", .{ entry.path, target.cpu.arch, err });
                    fail = true;
                    continue;
                };

                break :pp try aw.toOwnedSliceSentinel(0);
            };

            try std.testing.expectEqualStrings(aro, native);
        }

        if (fail) std.process.exit(1);
    }
}

const targets = [_]std.Target{
    .{
        .ofmt = .coff,
        .abi = .gnu,
        .os = .{ .tag = .windows, .version_range = .default(.thumb, .windows, .gnu) },
        .cpu = .{ .arch = .thumb, .model = .generic(.thumb), .features = .empty },
    },
    .{
        .ofmt = .coff,
        .abi = .gnu,
        .os = .{ .tag = .windows, .version_range = .default(.aarch64, .windows, .gnu) },
        .cpu = .{ .arch = .aarch64, .model = .generic(.aarch64), .features = .empty },
    },
    .{
        .ofmt = .coff,
        .abi = .gnu,
        .os = .{ .tag = .windows, .version_range = .default(.x86, .windows, .gnu) },
        .cpu = .{ .arch = .x86, .model = .generic(.x86), .features = .empty },
    },
    .{
        .ofmt = .coff,
        .abi = .gnu,
        .os = .{ .tag = .windows, .version_range = .default(.x86_64, .windows, .gnu) },
        .cpu = .{ .arch = .x86_64, .model = .generic(.x86_64), .features = .empty },
    },
};

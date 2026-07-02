const builtin = @import("builtin");

const std = @import("std");
const Allocator = std.mem.Allocator;
const Color = std.zig.Color;
const Configuration = std.Build.Configuration;
const Io = std.Io;
const Step = std.Build.Step;
const assert = std.debug.assert;
const fatal = std.process.fatal;
const log = std.log;
const mem = std.mem;
const process = std.process;
const Serialize = std.Build.Serialize;

pub const root = @import("@build");
pub const dependencies = @import("@dependencies");

pub const std_options: std.Options = .{
    .side_channels_mitigations = .none,
    .http_disable_tls = true,
};

pub fn main(init: process.Init.Minimal) !void {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    // The configurer is always short-lived because all it does is serialize
    // the configuration, which is picked up by a separate maker process.
    var threaded: std.Io.Threaded = .init(arena, .{
        .environ = init.environ,
        .argv0 = .init(init.args),
    });
    defer threaded.deinit();
    const io = threaded.io();

    const args = try init.args.toSlice(arena);

    var arg_i: usize = 1; // Skip own executable name.

    const zig_exe = expectArgOrFatal(args, &arg_i, "--zig");
    const build_root_sub_path = expectArgOrFatal(args, &arg_i, "--build-root");

    var graph: std.Build.Graph = .{
        .io = io,
        .arena = arena,
        .environ_map = try init.environ.createMap(arena),
        // TODO get this from parent process instead
        .host = .{
            .query = .{},
            .result = try std.zig.system.resolveTargetQuery(io, .{}),
        },
        .generated_files = .empty,
        .zig_exe = zig_exe,

        // Created before running the user's configure script so that some things
        // can be added during script execution such as strings.
        //
        // Use of arena here is load-bearing because `std.Build.dupe` is
        // implemented by string internment, and then returning the interned
        // slice. When the string bytes array is reallocated, that reference
        // must stay alive.
        .wip_configuration = .init(arena),
    };
    assert(try graph.wip_configuration.addString("") == .empty);
    assert(try graph.wip_configuration.addString("root") == .root);

    const cwd: Io.Dir = .cwd();

    const build_root: std.Build.Cache.Path = .{
        .root_dir = .{
            .handle = try cwd.openDir(io, build_root_sub_path, .{}),
            .path = build_root_sub_path,
        },
    };

    const builder = try std.Build.create(&graph, build_root, dependencies.root_deps);

    var color: Color = .auto;

    while (nextArg(args, &arg_i)) |arg| {
        if (mem.cutPrefix(u8, arg, "-D")) |option_contents| {
            if (option_contents.len == 0)
                fatalWithHint("expected option name after '-D'", .{});
            if (mem.indexOfScalar(u8, option_contents, '=')) |name_end| {
                const option_name = option_contents[0..name_end];
                const option_value = option_contents[name_end + 1 ..];
                if (try builder.addUserInputOption(option_name, option_value))
                    fatal("  access the help menu with 'zig build -h'", .{});
            } else {
                if (try builder.addUserInputFlag(option_contents))
                    fatal("  access the help menu with 'zig build -h'", .{});
            }
        } else if (mem.cutPrefix(u8, arg, "-fsys=")) |name| {
            try graph.system_integration_options.put(arena, name, .user_enabled);
        } else if (mem.cutPrefix(u8, arg, "-fno-sys=")) |name| {
            try graph.system_integration_options.put(arena, name, .user_disabled);
        } else if (mem.eql(u8, arg, "--release")) {
            graph.release_mode = .any;
        } else if (mem.cutPrefix(u8, arg, "--release=")) |rest| {
            graph.release_mode = std.meta.stringToEnum(std.Build.ReleaseMode, rest) orelse {
                fatalWithHint("expected --release=[off|any|fast|safe|small]; found: {s}", .{arg});
            };
        } else if (mem.cutPrefix(u8, arg, "--color=")) |rest| {
            color = std.meta.stringToEnum(Color, rest) orelse
                fatalWithHint("expected --color=[auto|on|off]; found: {s}", .{arg});
        } else if (mem.eql(u8, arg, "--system")) {
            // The usage text shows another argument after this parameter
            // but it is handled by the parent process. The build runner
            // only sees this flag.
            graph.system_package_mode = true;
        } else if (mem.eql(u8, arg, "--verbose")) {
            graph.verbose = true;
        } else if (mem.cutPrefix(u8, arg, "--cache-poison=")) |rest| {
            graph.cache_poison = std.meta.stringToEnum(std.Build.Graph.CachePoison, rest) orelse
                fatalWithHint("expected --cache-poison=[pure|poisoned|disallowed|ignored]; found: {s}", .{arg});
        } else if (mem.eql(u8, arg, "--search-prefix")) {
            try graph.search_prefixes.append(arena, nextArgOrFatal(args, &arg_i));
        } else {
            fatalWithHint("unrecognized argument: {s}", .{arg});
        }
    }

    const NO_COLOR = std.zig.EnvVar.NO_COLOR.isSet(&graph.environ_map);
    const CLICOLOR_FORCE = std.zig.EnvVar.CLICOLOR_FORCE.isSet(&graph.environ_map);

    graph.stderr_mode = switch (color) {
        .auto => try .detect(io, .stderr(), NO_COLOR, CLICOLOR_FORCE),
        .on => .escape_codes,
        .off => .no_color,
    };

    builder.runPackageScript(root);

    if (builder.validateUserInputDidItFail()) {
        fatal("  access the help menu with 'zig build -h'", .{});
    }

    try Serialize.packageOptions(builder, &graph.wip_configuration);
    try Serialize.systemIntegrationOptions(&graph, &graph.wip_configuration);

    builder.serializeConfigurationExiting();
}

fn nextArg(args: []const [:0]const u8, idx: *usize) ?[:0]const u8 {
    if (idx.* >= args.len) return null;
    defer idx.* += 1;
    return args[idx.*];
}

fn nextArgOrFatal(args: []const [:0]const u8, idx: *usize) [:0]const u8 {
    return nextArg(args, idx) orelse {
        fatalWithHint("expected argument after {q}", .{args[idx.* - 1]});
    };
}

fn expectArgOrFatal(args: []const [:0]const u8, index_ptr: *usize, first: []const u8) []const u8 {
    const next_arg = nextArg(args, index_ptr) orelse fatal("missing {q} argument", .{first});
    if (!mem.eql(u8, first, next_arg)) fatal("expected {q} instead of {q}", .{ first, next_arg });
    const arg = nextArg(args, index_ptr) orelse fatal("expected argument after {q}", .{first});
    return arg;
}

fn fatalWithHint(comptime f: []const u8, args: anytype) noreturn {
    log.info("to access the help menu: zig build -h", .{});
    fatal(f, args);
}

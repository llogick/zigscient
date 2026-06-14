const builtin = @import("builtin");

const std = @import("std");
const Allocator = std.mem.Allocator;
const Color = std.zig.Color;
const Configuration = std.Build.Configuration;
const File = std.Io.File;
const Io = std.Io;
const Step = std.Build.Step;
const Writer = std.Io.Writer;
const assert = std.debug.assert;
const fatal = std.process.fatal;
const fmt = std.fmt;
const log = std.log;
const mem = std.mem;
const process = std.process;

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

    try builder.runBuild(root);

    if (builder.validateUserInputDidItFail()) {
        fatal("  access the help menu with 'zig build -h'", .{});
    }

    try serializePackageOptions(builder, &graph.wip_configuration);
    try serializeSystemIntegrationOptions(&graph, &graph.wip_configuration);

    var stdout_buffer: [1024]u8 = undefined;
    var file_writer = Io.File.stdout().writerStreaming(io, &stdout_buffer);
    serialize(builder, &graph.wip_configuration, &file_writer.interface) catch |err| switch (err) {
        error.WriteFailed => fatal("failed to write configuration output: {t}", .{file_writer.err.?}),
        error.OutOfMemory => |e| return e,
    };
    file_writer.flush() catch |err| fatal("failed to write configuration output: {t}", .{err});

    // This executable is short-lived and run in Debug mode, so we'd rather
    // have `zig build` run faster than catch resource leaks in the user's
    // build.zig script (or, frankly, this configure runner), therefore we call
    // exit directly here rather than cleanExit.
    process.exit(0);
}

const Serialize = struct {
    arena: Allocator,
    wc: *Configuration.Wip,
    module_map: std.array_hash_map.Auto(*std.Build.Module, Configuration.Module.Index) = .empty,
    package_map: std.array_hash_map.Auto(*std.Build, Configuration.Package.Index) = .empty,
    /// Index corresponds to `Configuration.steps` index.
    step_map: std.array_hash_map.Auto(*Step, void) = .empty,

    fn builderToPackage(s: *Serialize, b: *std.Build) !Configuration.Package.Index {
        if (b.pkg_hash.len == 0) return .root;
        const arena = s.arena;
        const wc = s.wc;
        const gop = try s.package_map.getOrPut(arena, b);
        if (!gop.found_existing) {
            gop.value_ptr.* = try wc.addExtra(Configuration.Package, .{
                .hash = try wc.addString(b.pkg_hash),
                .dep_prefix = try wc.addString(b.dep_prefix),
                .root_path = try wc.addString(try b.root.toString(arena)),
            });
        }
        return gop.value_ptr.*;
    }

    fn addOptionalLazyPathEnum(s: *Serialize, lp: ?std.Build.LazyPath) !Configuration.LazyPath.OptionalIndex {
        const wc = s.wc;
        return @enumFromInt(switch (lp orelse return .none) {
            .src_path => |src_path| i: {
                const sub_path = try wc.addString(src_path.sub_path);
                break :i try wc.addExtraErased(Configuration.LazyPath.SourcePath, .{
                    .owner = try s.builderToPackage(src_path.owner),
                    .sub_path = sub_path,
                });
            },
            .generated => |generated| i: {
                const sub_path = try wc.addString(generated.sub_path);
                break :i try wc.addExtraErased(Configuration.LazyPath.Generated, .{
                    .flags = .{ .up = @intCast(generated.up) },
                    .index = generated.index,
                    .sub_path = sub_path,
                });
            },
            .cwd_relative => |cwd_relative_sub_path| i: {
                const sub_path = try wc.addString(cwd_relative_sub_path);
                break :i try wc.addExtraErased(Configuration.LazyPath.Relative, .{
                    .flags = .{ .base = .cwd },
                    .sub_path = sub_path,
                });
            },
            .relative => |relative| i: {
                break :i try wc.addExtraErased(Configuration.LazyPath.Relative, .{
                    .flags = .{ .base = relative.base },
                    .sub_path = try wc.addString(relative.sub_path),
                });
            },
            .dependency => |dependency| i: {
                const sub_path = try wc.addString(dependency.sub_path);
                break :i try wc.addExtraErased(Configuration.LazyPath.SourcePath, .{
                    .owner = try s.builderToPackage(dependency.dependency.builder),
                    .sub_path = sub_path,
                });
            },
        });
    }

    fn addOptionalLazyPath(s: *Serialize, lp: ?std.Build.LazyPath) !?Configuration.LazyPath.Index {
        return (try addOptionalLazyPathEnum(s, lp)).unwrap();
    }

    fn addLazyPath(s: *Serialize, lp: std.Build.LazyPath) !Configuration.LazyPath.Index {
        return @enumFromInt(@intFromEnum(try addOptionalLazyPathEnum(s, lp)));
    }

    fn addOptionalSemVer(s: *Serialize, sem_ver: ?std.SemanticVersion) !?Configuration.String {
        return if (sem_ver) |sv| try s.wc.addSemVer(sv) else null;
    }

    fn addOptionalString(s: *Serialize, opt_slice: ?[]const u8) !?Configuration.String {
        return if (opt_slice) |slice| try s.wc.addString(slice) else null;
    }

    fn addSystemLib(s: *Serialize, sl: *const std.Build.Module.SystemLib) !Configuration.SystemLib.Index {
        const wc = s.wc;
        return try wc.addDeduped(Configuration.SystemLib, .{
            .flags = .{
                .needed = sl.needed,
                .weak = sl.weak,
                .use_pkg_config = sl.use_pkg_config,
                .preferred_link_mode = sl.preferred_link_mode,
                .search_strategy = sl.search_strategy,
            },
            .name = try wc.addString(sl.name),
        });
    }

    fn addCSourceFile(s: *Serialize, csf: *const std.Build.Module.CSourceFile) !Configuration.CSourceFile.Index {
        const wc = s.wc;
        const args = try initStringList(s, csf.flags);
        return try wc.addExtra(Configuration.CSourceFile, .{
            .flags = .{
                .args_len = @intCast(args.len),
                .lang = .init(csf.language),
            },
            .file = try addLazyPath(s, csf.file),
            .args = .{ .slice = args },
        });
    }

    fn addCSourceFiles(s: *Serialize, csf: *const std.Build.Module.CSourceFiles) !Configuration.CSourceFiles.Index {
        const wc = s.wc;
        const sub_paths = try initStringList(s, csf.files);
        const args = try initStringList(s, csf.flags);
        return try wc.addExtra(Configuration.CSourceFiles, .{
            .flags = .{
                .args_len = @intCast(args.len),
                .lang = .init(csf.language),
            },
            .root = try addLazyPath(s, csf.root),
            .sub_paths = .{ .slice = sub_paths },
            .args = .{ .slice = args },
        });
    }

    fn addRcSourceFile(s: *Serialize, rsf: *const std.Build.Module.RcSourceFile) !Configuration.RcSourceFile.Index {
        const wc = s.wc;
        const include_paths = try initLazyPathList(s, rsf.include_paths);
        const args = try initStringList(s, rsf.flags);
        return try wc.addExtra(Configuration.RcSourceFile, .{
            .flags = .{
                .args_len = @intCast(args.len),
                .include_paths = include_paths.len != 0,
            },
            .file = try addLazyPath(s, rsf.file),
            .include_paths = .{ .slice = include_paths },
            .args = .{ .slice = args },
        });
    }

    fn addEnvironMap(s: *Serialize, opt_map: ?*std.process.Environ.Map) !?Configuration.EnvironMap.Index {
        const wc = s.wc;
        const map = opt_map orelse return null;
        return try wc.addDeduped(Configuration.EnvironMap, .{
            .keys = try wc.addStringList(map.array_hash_map.keys()),
            .values = try wc.addStringList(map.array_hash_map.values()),
        });
    }

    fn initArgsList(s: *Serialize, args: []const Step.Run.Arg) ![]const Configuration.Step.Run.Arg.Index {
        const wc = s.wc;
        const result = try s.arena.alloc(Configuration.Step.Run.Arg.Index, args.len);
        for (result, args) |*dest, src| {
            dest.* = try wc.addExtra(Configuration.Step.Run.Arg, switch (src) {
                .artifact => |a| .{
                    .flags = .{
                        .tag = .artifact,
                        .prefix = a.prefix.len != 0,
                        .suffix = false,
                        .basename = false,
                        .path = false,
                        .producer = true,
                        .generated = false,
                        .dep_file = false,
                    },
                    .prefix = .{ .value = if (a.prefix.len != 0) try wc.addString(a.prefix) else null },
                    .suffix = .{ .value = null },
                    .basename = .{ .value = null },
                    .path = .{ .value = null },
                    .producer = .{ .value = stepIndex(s, &a.artifact.step) },
                    .generated = .{ .value = null },
                },
                .lazy_path => |a| .{
                    .flags = .{
                        .tag = .path_file,
                        .prefix = a.prefix.len != 0,
                        .suffix = false,
                        .basename = false,
                        .path = true,
                        .producer = false,
                        .generated = false,
                        .dep_file = false,
                    },
                    .prefix = .{ .value = if (a.prefix.len != 0) try wc.addString(a.prefix) else null },
                    .suffix = .{ .value = null },
                    .basename = .{ .value = null },
                    .path = .{ .value = try addLazyPath(s, a.lazy_path) },
                    .producer = .{ .value = null },
                    .generated = .{ .value = null },
                },
                .decorated_directory => |a| .{
                    .flags = .{
                        .tag = .path_directory,
                        .prefix = a.prefix.len != 0,
                        .suffix = a.suffix.len != 0,
                        .basename = false,
                        .path = true,
                        .producer = false,
                        .generated = false,
                        .dep_file = false,
                    },
                    .prefix = .{ .value = if (a.prefix.len != 0) try wc.addString(a.prefix) else null },
                    .suffix = .{ .value = if (a.suffix.len != 0) try wc.addString(a.suffix) else null },
                    .basename = .{ .value = null },
                    .path = .{ .value = try addLazyPath(s, a.lazy_path) },
                    .producer = .{ .value = null },
                    .generated = .{ .value = null },
                },
                .file_content => |a| .{
                    .flags = .{
                        .tag = .file_content,
                        .prefix = a.prefix.len != 0,
                        .suffix = false,
                        .basename = false,
                        .path = true,
                        .producer = false,
                        .generated = false,
                        .dep_file = false,
                    },
                    .prefix = .{ .value = if (a.prefix.len != 0) try wc.addString(a.prefix) else null },
                    .suffix = .{ .value = null },
                    .basename = .{ .value = null },
                    .path = .{ .value = try addLazyPath(s, a.lazy_path) },
                    .producer = .{ .value = null },
                    .generated = .{ .value = null },
                },
                .bytes => |a| .{
                    .flags = .{
                        .tag = .string,
                        .prefix = true,
                        .suffix = false,
                        .basename = false,
                        .path = false,
                        .producer = false,
                        .generated = false,
                        .dep_file = false,
                    },
                    .prefix = .{ .value = try wc.addString(a) },
                    .suffix = .{ .value = null },
                    .basename = .{ .value = null },
                    .path = .{ .value = null },
                    .producer = .{ .value = null },
                    .generated = .{ .value = null },
                },
                .output_file, .output_file_dep => |a, tag| .{
                    .flags = .{
                        .tag = .output_file,
                        .prefix = a.prefix.len != 0,
                        .suffix = false,
                        .basename = a.basename.len != 0,
                        .path = false,
                        .producer = false,
                        .generated = true,
                        .dep_file = tag == .output_file_dep,
                    },
                    .prefix = .{ .value = if (a.prefix.len != 0) try wc.addString(a.prefix) else null },
                    .suffix = .{ .value = null },
                    .basename = .{ .value = if (a.basename.len != 0) try wc.addString(a.basename) else null },
                    .path = .{ .value = null },
                    .producer = .{ .value = null },
                    .generated = .{ .value = a.generated_file },
                },
                .output_directory => |a| .{
                    .flags = .{
                        .tag = .output_directory,
                        .prefix = a.prefix.len != 0,
                        .suffix = false,
                        .basename = a.basename.len != 0,
                        .path = false,
                        .producer = false,
                        .generated = true,
                        .dep_file = false,
                    },
                    .prefix = .{ .value = if (a.prefix.len != 0) try wc.addString(a.prefix) else null },
                    .suffix = .{ .value = null },
                    .basename = .{ .value = if (a.basename.len != 0) try wc.addString(a.basename) else null },
                    .path = .{ .value = null },
                    .producer = .{ .value = null },
                    .generated = .{ .value = a.generated_file },
                },
                .passthru => .{
                    .flags = .{
                        .tag = .passthru,
                        .prefix = false,
                        .suffix = false,
                        .basename = false,
                        .path = false,
                        .producer = false,
                        .generated = false,
                        .dep_file = false,
                    },
                    .prefix = .{ .value = null },
                    .suffix = .{ .value = null },
                    .basename = .{ .value = null },
                    .path = .{ .value = null },
                    .producer = .{ .value = null },
                    .generated = .{ .value = null },
                },
            });
        }
        return result;
    }

    fn initIncludeDirList(
        s: *Serialize,
        list: []const std.Build.Module.IncludeDir,
    ) ![]const Configuration.Module.IncludeDir {
        const result = try s.arena.alloc(Configuration.Module.IncludeDir, list.len);
        for (result, list) |*dest, src| dest.* = switch (src) {
            .path => |lp| .{ .path = try addLazyPath(s, lp) },
            .path_system => |lp| .{ .path_system = try addLazyPath(s, lp) },
            .path_after => |lp| .{ .path_after = try addLazyPath(s, lp) },
            .framework_path => |lp| .{ .framework_path = try addLazyPath(s, lp) },
            .framework_path_system => |lp| .{ .framework_path_system = try addLazyPath(s, lp) },
            .embed_path => |lp| .{ .embed_path = try addLazyPath(s, lp) },
            .other_step => |cs| .{ .path = try addLazyPath(s, cs.installed_headers_include_tree.?.getDirectory()) },
            .config_header_step => |chs| .{ .config_header_step = stepIndex(s, &chs.step) },
        };
        return result;
    }

    fn initLazyPathList(s: *Serialize, list: []const std.Build.LazyPath) ![]const Configuration.LazyPath.Index {
        const result = try s.arena.alloc(Configuration.LazyPath.Index, list.len);
        for (result, list) |*dest, src| dest.* = try addLazyPath(s, src);
        return result;
    }

    fn initStringList(s: *Serialize, list: []const []const u8) ![]const Configuration.String {
        const wc = s.wc;
        const result = try s.arena.alloc(Configuration.String, list.len);
        for (result, list) |*dest, src| dest.* = try wc.addString(src);
        return result;
    }

    fn initCopyList(s: *Serialize, list: []const Step.WriteFile.Copy) ![]const Configuration.Step.WriteFile.Copy {
        const result = try s.arena.alloc(Configuration.Step.WriteFile.Copy, list.len);
        for (result, list) |*dest, src| dest.* = .{
            .sub_path = src.sub_path,
            .src_file = try s.addLazyPath(src.src_file),
        };
        return result;
    }

    fn initOptionalStringList(s: *Serialize, list: []const ?[]const u8) ![]const Configuration.OptionalString {
        const wc = s.wc;
        const result = try s.arena.alloc(Configuration.OptionalString, list.len);
        for (result, list) |*dest, src| dest.* = try wc.addOptionalString(src);
        return result;
    }

    fn addModule(s: *Serialize, m: *std.Build.Module) !Configuration.Module.Index {
        if (s.module_map.get(m)) |index| return index;

        const wc = s.wc;
        const arena = s.arena;

        const rpaths = try arena.alloc(Configuration.Module.RPath, m.rpaths.items.len);
        for (rpaths, m.rpaths.items) |*dest, src| dest.* = switch (src) {
            .lazy_path => |lp| .{ .lazy_path = try addLazyPath(s, lp) },
            .special => |slice| .{ .special = try wc.addString(slice) },
        };

        const link_objects = try arena.alloc(Configuration.Module.LinkObject, m.link_objects.items.len);
        for (link_objects, m.link_objects.items) |*dest, *src| dest.* = switch (src.*) {
            .static_path => |lp| .{ .static_path = try addLazyPath(s, lp) },
            .other_step => |cs| .{ .other_step = stepIndex(s, &cs.step) },
            .system_lib => |*sl| .{ .system_lib = try addSystemLib(s, sl) },
            .assembly_file => |lp| .{ .assembly_file = try addLazyPath(s, lp) },
            .c_source_file => |csf| .{ .c_source_file = try addCSourceFile(s, csf) },
            .c_source_files => |csf| .{ .c_source_files = try addCSourceFiles(s, csf) },
            .win32_resource_file => |wrf| .{ .win32_resource_file = try addRcSourceFile(s, wrf) },
        };

        const frameworks = try arena.alloc(Configuration.Module.Framework, m.frameworks.entries.len);
        for (frameworks, m.frameworks.keys(), m.frameworks.values()) |*dest, name, options| dest.* = .{
            .flags = .{
                .needed = options.needed,
                .weak = options.weak,
            },
            .name = try wc.addString(name),
        };

        const lib_paths = try initLazyPathList(s, m.lib_paths.items);
        const c_macros = try initStringList(s, m.c_macros.items);
        const export_symbol_names = try initStringList(s, m.export_symbol_names);

        const module_index: Configuration.Module.Index = try wc.addExtra(Configuration.Module, .{
            .flags = .{
                .optimize = .init(m.optimize),
                .strip = .init(m.strip),
                .unwind_tables = .init(m.unwind_tables),
                .dwarf_format = .init(m.dwarf_format),
                .single_threaded = .init(m.single_threaded),
                .stack_protector = .init(m.stack_protector),
                .stack_check = .init(m.stack_check),
                .sanitize_c = .init(m.sanitize_c),
                .sanitize_thread = .init(m.sanitize_thread),
                .fuzz = .init(m.fuzz),
                .code_model = m.code_model,
                .c_macros = c_macros.len != 0,
                .include_dirs = m.include_dirs.items.len != 0,
                .lib_paths = lib_paths.len != 0,
                .rpaths = rpaths.len != 0,
                .frameworks = frameworks.len != 0,
                .link_objects = link_objects.len != 0,
                .export_symbol_names = export_symbol_names.len != 0,
            },
            .flags2 = .{
                .valgrind = .init(m.valgrind),
                .pic = .init(m.pic),
                .red_zone = .init(m.red_zone),
                .omit_frame_pointer = .init(m.omit_frame_pointer),
                .error_tracing = .init(m.error_tracing),
                .link_libc = .init(m.link_libc),
                .link_libcpp = .init(m.link_libcpp),
                .no_builtin = .init(m.no_builtin),
            },
            .owner = try s.builderToPackage(m.owner),
            .root_source_file = try s.addOptionalLazyPathEnum(m.root_source_file),
            .import_table = .invalid,
            .resolved_target = try addOptionalResolvedTarget(wc, m.resolved_target),
            .c_macros = .{ .slice = c_macros },
            .lib_paths = .{ .slice = lib_paths },
            .export_symbol_names = .{ .slice = export_symbol_names },
            .include_dirs = .init(try s.initIncludeDirList(m.include_dirs.items)),
            .rpaths = .init(rpaths),
            .link_objects = .init(link_objects),
            .frameworks = .{ .slice = frameworks },
        });

        // The import table is the only place that modules can form dependency
        // loops. Therefore, we populate the module indexes only after adding
        // the module to module_map.
        try s.module_map.putNoClobber(arena, m, module_index);

        var imports = try std.MultiArrayList(Configuration.ImportTable.Import).initCapacity(arena, m.import_table.entries.len);
        imports.len = m.import_table.entries.len;
        for (
            imports.items(.name),
            imports.items(.module),
            m.import_table.keys(),
            m.import_table.values(),
        ) |*dest_name, *dest_module, src_name, src_module| {
            dest_name.* = try wc.addString(src_name);
            dest_module.* = try addModule(s, src_module);
        }

        comptime assert(std.mem.eql(u8, @typeInfo(Configuration.Module).@"struct".field_names[2], "import_table"));
        comptime assert(@typeInfo(Configuration.Module).@"struct".field_types[2] == Configuration.ImportTable.Index);
        assert(wc.extra.items[@intFromEnum(module_index) + 2] == @intFromEnum(Configuration.ImportTable.Index.invalid));
        const import_table_index = try wc.addDeduped(Configuration.ImportTable, .{
            .imports = .{ .mal = imports },
        });
        wc.extra.items[@intFromEnum(module_index) + 2] = @intFromEnum(import_table_index);

        return module_index;
    }

    fn stepIndex(s: *const Serialize, step: *Step) Configuration.Step.Index {
        return @enumFromInt(s.step_map.getIndex(step).?);
    }
};

fn serialize(b: *std.Build, wc: *Configuration.Wip, writer: *Io.Writer) !void {
    const graph = b.graph;
    const arena = graph.arena;
    const gpa = wc.gpa;

    var s: Serialize = .{ .wc = wc, .arena = arena };

    // Starting from all top-level steps in `b`, traverse the entire step graph
    // and add all step dependencies implied by module graphs.
    const top_level_steps = b.top_level_steps.values();
    try s.step_map.ensureUnusedCapacity(arena, top_level_steps.len);
    for (top_level_steps) |tls| {
        s.step_map.putAssumeCapacityNoClobber(&tls.step, {});
    }
    {
        while (wc.steps.items.len < s.step_map.count()) {
            const step = s.step_map.keys()[wc.steps.items.len];

            // Set up any implied dependencies for this step. It's important that we do this first, so
            // that the loop below discovers steps implied by the module graph.
            try createModuleDependenciesForStep(step);

            try s.step_map.ensureUnusedCapacity(arena, step.dependencies.items.len);
            for (step.dependencies.items) |other_step| {
                s.step_map.putAssumeCapacity(other_step, {});
            }

            // Add and then de-duplicate dependencies.
            const dep_steps = try arena.alloc(Configuration.Step.Index, step.dependencies.items.len);
            for (dep_steps, step.dependencies.items) |*dest, src|
                dest.* = @enumFromInt(s.step_map.getIndex(src).?);

            const deps: Configuration.Deps.Index = try wc.addDeduped(Configuration.Deps, .{
                .steps = .{ .slice = dep_steps },
            });

            try wc.steps.ensureTotalCapacity(gpa, s.step_map.entries.capacity);
            wc.steps.appendAssumeCapacity(.{
                .name = try wc.addString(step.name),
                .owner = try s.builderToPackage(step.owner),
                .deps = deps,
                .max_rss = .fromBytes(step.max_rss),
                .extended = @enumFromInt(switch (step.tag) {
                    .top_level => e: {
                        const top_level: *Step.TopLevel = @fieldParentPtr("step", step);
                        break :e try wc.addExtraErased(Configuration.Step.TopLevel, .{
                            .description = try wc.addString(top_level.description),
                        });
                    },
                    .compile => e: {
                        const c: *Step.Compile = @fieldParentPtr("step", step);
                        const exec_cmd_args: []const ?[]const u8 = c.exec_cmd_args orelse &.{};
                        const installed_headers: []u32 = try arena.alloc(u32, c.installed_headers.items.len);
                        for (installed_headers, c.installed_headers.items) |*dst, src| switch (src) {
                            .file => |file| {
                                dst.* = try wc.addExtraErased(Configuration.Step.Compile.InstalledHeader.File, .{
                                    .source = try s.addLazyPath(file.source),
                                    .dest_sub_path = try wc.addString(file.dest_rel_path),
                                });
                            },
                            .directory => |directory| {
                                const include_extensions = directory.options.include_extensions orelse &.{};
                                dst.* = try wc.addExtraErased(Configuration.Step.Compile.InstalledHeader.Directory, .{
                                    .flags = .{
                                        .include_extensions = include_extensions.len != 0,
                                        .exclude_extensions = directory.options.exclude_extensions.len != 0,
                                    },
                                    .source = try s.addLazyPath(directory.source),
                                    .dest_sub_path = try wc.addString(directory.dest_rel_path),
                                    .exclude_extensions = .{ .slice = try s.initStringList(directory.options.exclude_extensions) },
                                    .include_extensions = .{ .slice = try s.initStringList(include_extensions) },
                                });
                            },
                        };

                        break :e try wc.addExtraErased(Configuration.Step.Compile, .{
                            .flags = .{
                                .filters_len = c.filters.len != 0,
                                .exec_cmd_args_len = exec_cmd_args.len != 0,
                                .installed_headers_len = installed_headers.len != 0,
                                .force_undefined_symbols_len = c.force_undefined_symbols.entries.len != 0,

                                .verbose_link = c.verbose_link,
                                .verbose_cc = c.verbose_cc,
                                .rdynamic = c.rdynamic,
                                .import_memory = c.import_memory,
                                .export_memory = c.export_memory,
                                .import_symbols = c.import_symbols,
                                .import_table = c.import_table,
                                .export_table = c.export_table,
                                .shared_memory = c.shared_memory,
                                .link_eh_frame_hdr = c.link_eh_frame_hdr,
                                .link_emit_relocs = c.link_emit_relocs,
                                .link_function_sections = c.link_function_sections,
                                .link_data_sections = c.link_data_sections,
                                .linker_dynamicbase = c.linker_dynamicbase,
                                .link_z_notext = c.link_z_notext,
                                .link_z_relro = c.link_z_relro,
                                .link_z_lazy = c.link_z_lazy,
                                .link_z_defs = c.link_z_defs,
                                .headerpad_max_install_names = c.headerpad_max_install_names,
                                .dead_strip_dylibs = c.dead_strip_dylibs,
                                .force_load_objc = c.force_load_objc,
                                .discard_local_symbols = c.discard_local_symbols,
                                .mingw_unicode_entry_point = c.mingw_unicode_entry_point,
                            },
                            .flags2 = .{
                                .pie = .init(c.pie),
                                .formatted_panics = .init(c.formatted_panics),
                                .bundle_compiler_rt = .init(c.bundle_compiler_rt),
                                .bundle_ubsan_rt = .init(c.bundle_ubsan_rt),
                                .each_lib_rpath = .init(c.each_lib_rpath),
                                .link_gc_sections = .init(c.link_gc_sections),
                                .linker_allow_shlib_undefined = .init(c.linker_allow_shlib_undefined),
                                .linker_allow_undefined_version = .init(c.linker_allow_undefined_version),
                                .linker_enable_new_dtags = .init(c.linker_enable_new_dtags),
                                .dll_export_fns = .init(c.dll_export_fns),
                                .use_llvm = .init(c.use_llvm),
                                .use_lld = .init(c.use_lld),
                                .use_new_linker = .init(c.use_new_linker),
                                .allow_so_scripts = .init(c.allow_so_scripts),
                                .sanitize_coverage_trace_pc_guard = .init(c.sanitize_coverage_trace_pc_guard),
                                .linkage = .init(c.linkage),
                            },
                            .flags3 = .{
                                .is_linking_libc = c.is_linking_libc,
                                .is_linking_libcpp = c.is_linking_libcpp,
                                .version = c.version != null,
                                .compress_debug_sections = c.compress_debug_sections,
                                .initial_memory = c.initial_memory != null,
                                .max_memory = c.max_memory != null,
                                .kind = c.kind,
                                .global_base = c.global_base != null,
                                .test_runner = if (c.test_runner) |tr| switch (tr.mode) {
                                    .simple => .simple,
                                    .server => .server,
                                } else .default,
                                .wasi_exec_model = .init(c.wasi_exec_model),
                                .win32_manifest = c.win32_manifest != null,
                                .win32_module_definition = c.win32_module_definition != null,
                                .zig_lib_dir = c.zig_lib_dir != null,
                                .rc_includes = c.rc_includes,
                                .image_base = c.image_base != null,
                                .build_id = .init(c.build_id),
                                .entry = switch (c.entry) {
                                    .default => .default,
                                    .disabled => .disabled,
                                    .enabled => .enabled,
                                    .symbol_name => .symbol_name,
                                },
                                .lto = .init(c.lto),
                                .subsystem = .init(c.subsystem),
                            },
                            .flags4 = .{
                                .libc_file = c.libc_file != null,
                                .link_z_common_page_size = c.link_z_common_page_size != null,
                                .link_z_max_page_size = c.link_z_max_page_size != null,
                                .pagezero_size = c.pagezero_size != null,
                                .stack_size = c.stack_size != null,
                                .headerpad_size = c.headerpad_size != null,
                                .error_limit = c.error_limit != null,
                                .install_name = c.install_name != null,
                                .entitlements = c.entitlements != null,
                                .expect_errors = if (c.expect_errors) |x| switch (x) {
                                    .contains => .contains,
                                    .exact => .exact,
                                    .starts_with => .starts_with,
                                    .stderr_contains => .stderr_contains,
                                } else .none,
                                .linker_script = c.linker_script != null,
                                .version_script = c.version_script != null,
                                .emit_directory = c.emit_directory != .none,
                                .generated_docs = c.generated_docs != .none,
                                .generated_asm = c.generated_asm != .none,
                                .generated_bin = c.generated_bin != .none,
                                .generated_pdb = c.generated_pdb != .none,
                                .generated_implib = c.generated_implib != .none,
                                .generated_llvm_bc = c.generated_llvm_bc != .none,
                                .generated_llvm_ir = c.generated_llvm_ir != .none,
                                .generated_h = c.generated_h != .none,
                                .incremental = .init(c.incremental),
                            },
                            .root_module = try s.addModule(c.root_module),
                            .root_name = try wc.addString(c.name),
                            .linker_script = .{ .value = try s.addOptionalLazyPath(c.linker_script) },
                            .version_script = .{ .value = try s.addOptionalLazyPath(c.version_script) },
                            .zig_lib_dir = .{ .value = try s.addOptionalLazyPath(c.zig_lib_dir) },
                            .libc_file = .{ .value = try s.addOptionalLazyPath(c.libc_file) },
                            .win32_manifest = .{ .value = try s.addOptionalLazyPath(c.win32_manifest) },
                            .win32_module_definition = .{ .value = try s.addOptionalLazyPath(c.win32_module_definition) },
                            .entitlements = .{ .value = try s.addOptionalLazyPath(c.entitlements) },
                            .version = .{ .value = try s.addOptionalSemVer(c.version) },
                            .install_name = .{ .value = try s.addOptionalString(c.install_name) },
                            .initial_memory = .{ .value = c.initial_memory },
                            .max_memory = .{ .value = c.max_memory },
                            .global_base = .{ .value = c.global_base },
                            .image_base = .{ .value = c.image_base },
                            .link_z_common_page_size = .{ .value = c.link_z_common_page_size },
                            .link_z_max_page_size = .{ .value = c.link_z_max_page_size },
                            .pagezero_size = .{ .value = c.pagezero_size },
                            .stack_size = .{ .value = c.stack_size },
                            .headerpad_size = .{ .value = c.headerpad_size },
                            .error_limit = .{ .value = c.error_limit },
                            .entry = .{ .value = switch (c.entry) {
                                .symbol_name => |name| try wc.addString(name),
                                .default, .disabled, .enabled => null,
                            } },
                            .build_id = .{ .value = if (c.build_id) |id| switch (id) {
                                .hexstring => |*hexstring| try wc.addString(hexstring.toSlice()),
                                .none, .fast, .uuid, .sha1, .md5 => null,
                            } else null },
                            .filters = .{ .slice = try s.initStringList(c.filters) },
                            .exec_cmd_args = .{ .slice = try s.initOptionalStringList(exec_cmd_args) },
                            .installed_headers = .initErased(installed_headers),
                            .force_undefined_symbols = .{ .slice = try s.initStringList(c.force_undefined_symbols.keys()) },
                            .expect_errors = .{ .u = if (c.expect_errors) |x| switch (x) {
                                .contains => |slice| .{ .contains = try wc.addString(slice) },
                                .exact => |exact| .{ .exact = .{ .slice = try s.initStringList(exact) } },
                                .starts_with => |slice| .{ .starts_with = try wc.addString(slice) },
                                .stderr_contains => |slice| .{ .stderr_contains = try wc.addString(slice) },
                            } else .none },
                            .test_runner = .{ .u = if (c.test_runner) |tr| switch (tr.mode) {
                                .simple => .{ .simple = try s.addLazyPath(tr.path) },
                                .server => .{ .server = try s.addLazyPath(tr.path) },
                            } else .default },

                            .emit_directory = .{ .value = c.emit_directory.unwrap() },
                            .generated_docs = .{ .value = c.generated_docs.unwrap() },
                            .generated_asm = .{ .value = c.generated_asm.unwrap() },
                            .generated_bin = .{ .value = c.generated_bin.unwrap() },
                            .generated_pdb = .{ .value = c.generated_pdb.unwrap() },
                            .generated_implib = .{ .value = c.generated_implib.unwrap() },
                            .generated_llvm_bc = .{ .value = c.generated_llvm_bc.unwrap() },
                            .generated_llvm_ir = .{ .value = c.generated_llvm_ir.unwrap() },
                            .generated_h = .{ .value = c.generated_h.unwrap() },
                        });
                    },
                    .install_artifact => e: {
                        const ia: *Step.InstallArtifact = @fieldParentPtr("step", step);
                        break :e try wc.addExtraErased(Configuration.Step.InstallArtifact, .{
                            .flags = .{
                                .dylib_symlinks = ia.dylib_symlinks,
                                .bin_dir = ia.dest_dir != null,
                                .implib_dir = ia.implib_dir != null,
                                .pdb_dir = ia.pdb_dir != null,
                                .h_dir = ia.h_dir != null,
                                .bin_sub_path = ia.dest_sub_path != null,
                            },
                            .bin_dir = .{ .value = try addInstallDirDefaultNull(wc, ia.dest_dir) },
                            .implib_dir = .{ .value = try addInstallDirDefaultNull(wc, ia.implib_dir) },
                            .pdb_dir = .{ .value = try addInstallDirDefaultNull(wc, ia.pdb_dir) },
                            .h_dir = .{ .value = try addInstallDirDefaultNull(wc, ia.h_dir) },
                            .bin_sub_path = .{ .value = try s.addOptionalString(ia.dest_sub_path) },
                        });
                    },
                    .install_file => e: {
                        const sif: *Step.InstallFile = @fieldParentPtr("step", step);
                        break :e try wc.addExtraErased(Configuration.Step.InstallFile, .{
                            .source = try s.addLazyPath(sif.source),
                            .dest_dir = try addInstallDir(wc, sif.dir),
                            .dest_sub_path = try wc.addString(sif.dest_rel_path),
                        });
                    },
                    .install_dir => e: {
                        const sid: *Step.InstallDir = @fieldParentPtr("step", step);
                        const dest_sub_path: ?[]const u8 = if (sid.options.install_subdir.len != 0)
                            sid.options.install_subdir
                        else
                            null;
                        const include_extensions = sid.options.include_extensions orelse &.{};
                        break :e try wc.addExtraErased(Configuration.Step.InstallDir, .{
                            .flags = .{
                                .dest_sub_path = dest_sub_path != null,
                                .exclude_extensions = sid.options.exclude_extensions.len != 0,
                                .include_extensions = include_extensions.len != 0,
                                .include_extensions_active = sid.options.include_extensions != null,
                                .blank_extensions = sid.options.blank_extensions.len != 0,
                            },
                            .source_dir = try s.addLazyPath(sid.options.source_dir),
                            .dest_dir = try addInstallDir(wc, sid.options.install_dir),
                            .dest_sub_path = .{ .value = try s.addOptionalString(dest_sub_path) },
                            .exclude_extensions = .{ .slice = try s.initStringList(sid.options.exclude_extensions) },
                            .include_extensions = .{ .slice = try s.initStringList(include_extensions) },
                            .blank_extensions = .{ .slice = try s.initStringList(sid.options.blank_extensions) },
                        });
                    },
                    .fail => e: {
                        const sf: *Step.Fail = @fieldParentPtr("step", step);
                        break :e try wc.addExtraErased(Configuration.Step.Fail, .{
                            .msg = sf.error_msg,
                        });
                    },
                    .find_program => e: {
                        const fp: *Step.FindProgram = @fieldParentPtr("step", step);
                        break :e try wc.addExtraErased(Configuration.Step.FindProgram, .{
                            .names = fp.names,
                            .found_path = fp.found_path,
                        });
                    },
                    .fmt => e: {
                        const sf: *Step.Fmt = @fieldParentPtr("step", step);
                        break :e try wc.addExtraErased(Configuration.Step.Fmt, .{
                            .flags = .{
                                .paths = sf.paths.len != 0,
                                .exclude_paths = sf.exclude_paths.len != 0,
                                .check = sf.check,
                            },
                            .paths = .{ .slice = try s.initLazyPathList(sf.paths) },
                            .exclude_paths = .{ .slice = try s.initLazyPathList(sf.exclude_paths) },
                        });
                    },
                    .translate_c => e: {
                        const tc: *Step.TranslateC = @fieldParentPtr("step", step);

                        const system_libs = try arena.alloc(Configuration.SystemLib.Index, tc.system_libs.items.len);
                        for (system_libs, tc.system_libs.items) |*dest, *src| dest.* = try s.addSystemLib(src);

                        break :e try wc.addExtraErased(Configuration.Step.TranslateC, .{
                            .flags = .{
                                .include_dirs = tc.include_dirs.items.len != 0,
                                .system_libs = system_libs.len != 0,
                                .c_macros = tc.c_macros.items.len != 0,
                                .link_libc = tc.link_libc,
                                .optimize = .init(tc.optimize),
                            },
                            .src_path = try s.addLazyPath(tc.source),
                            .output_file = tc.output_file,
                            .include_dirs = .init(try s.initIncludeDirList(tc.include_dirs.items)),
                            .system_libs = .{ .slice = system_libs },
                            .c_macros = .{ .slice = tc.c_macros.items },
                            .target = try addOptionalResolvedTarget(wc, tc.target),
                        });
                    },
                    .write_file => e: {
                        const wf: *Step.WriteFile = @fieldParentPtr("step", step);

                        const directories = try arena.alloc(
                            Configuration.Step.WriteFile.Directory,
                            wf.directories.items.len,
                        );
                        for (directories, wf.directories.items) |*dest, src| dest.* = .{
                            .sub_path = src.sub_path,
                            .src_path = try s.addLazyPath(src.src_path),
                            .exclude_extensions = src.exclude_extensions,
                            .include_extensions = src.include_extensions,
                        };

                        break :e try wc.addExtraErased(Configuration.Step.WriteFile, .{
                            .flags = .{
                                .embeds = wf.embeds.items.len != 0,
                                .copies = wf.copies.items.len != 0,
                                .directories = directories.len != 0,
                                .mode = switch (wf.mode) {
                                    .whole_cached => .whole_cached,
                                    .tmp => .tmp,
                                    .mutate => .mutate,
                                },
                            },
                            .generated_directory = wf.generated_directory,
                            .embeds = .{ .slice = wf.embeds.items },
                            .copies = .{ .slice = try s.initCopyList(wf.copies.items) },
                            .directories = .{ .slice = directories },
                            .mutate_path = .{ .value = switch (wf.mode) {
                                .mutate => |lp| try s.addLazyPath(lp),
                                .whole_cached, .tmp => null,
                            } },
                        });
                    },
                    .update_source_files => e: {
                        const usf: *Step.UpdateSourceFiles = @fieldParentPtr("step", step);
                        break :e try wc.addExtraErased(Configuration.Step.UpdateSourceFiles, .{
                            .flags = .{
                                .embeds = usf.embeds.items.len != 0,
                                .copies = usf.copies.items.len != 0,
                            },
                            .embeds = .{ .slice = usf.embeds.items },
                            .copies = .{ .slice = try s.initCopyList(usf.copies.items) },
                        });
                    },
                    .run => e: {
                        const run: *Step.Run = @fieldParentPtr("step", step);
                        var expect_stderr_exact: ?Configuration.Bytes = null;
                        var expect_stdout_exact: ?Configuration.Bytes = null;
                        var expect_stderr_match: std.ArrayList(Configuration.Bytes) = .empty;
                        var expect_stdout_match: std.ArrayList(Configuration.Bytes) = .empty;
                        var expect_term: ?struct {
                            status: Configuration.Step.Run.ExpectTermStatus,
                            value: u32,
                        } = null;
                        switch (run.stdio) {
                            .check => |checks| for (checks.items) |check| switch (check) {
                                .expect_stderr_exact => |bytes| expect_stderr_exact = try wc.addBytes(bytes),
                                .expect_stdout_exact => |bytes| expect_stdout_exact = try wc.addBytes(bytes),
                                .expect_stderr_match => |bytes| {
                                    try expect_stderr_match.append(arena, try wc.addBytes(bytes));
                                },
                                .expect_stdout_match => |bytes| {
                                    try expect_stdout_match.append(arena, try wc.addBytes(bytes));
                                },
                                .expect_term => |t| expect_term = switch (t) {
                                    .exited => |x| .{ .status = .exited, .value = x },
                                    .signal => |x| .{ .status = .signal, .value = @intFromEnum(x) },
                                    .stopped => |x| .{ .status = .stopped, .value = @intFromEnum(x) },
                                    .unknown => |x| .{ .status = .unknown, .value = x },
                                },
                            },
                            else => {},
                        }

                        break :e try wc.addExtraErased(Configuration.Step.Run, .{
                            .flags = .{
                                .disable_zig_progress = run.disable_zig_progress,
                                .skip_foreign_checks = run.skip_foreign_checks,
                                .failing_to_execute_foreign_is_an_error = run.failing_to_execute_foreign_is_an_error,
                                .has_side_effects = run.has_side_effects,
                                .test_runner_mode = run.test_runner_mode,
                                .color = run.color,
                                .stdio = switch (run.stdio) {
                                    .infer_from_args => .infer_from_args,
                                    .inherit => .inherit,
                                    .check => .check,
                                    .zig_test => .zig_test,
                                },
                                .stdin = switch (run.stdin) {
                                    .none => .none,
                                    .bytes => .bytes,
                                    .lazy_path => .lazy_path,
                                },
                                .stdout_trim_whitespace = if (run.captured_stdout) |cs| cs.trim_whitespace else .none,
                                .stderr_trim_whitespace = if (run.captured_stderr) |cs| cs.trim_whitespace else .none,
                                .stdio_limit = run.stdio_limit != .unlimited,
                                .producer = run.producer != null,
                                .cwd = run.cwd != null,
                                .captured_stdout = run.captured_stdout != null,
                                .captured_stderr = run.captured_stderr != null,
                                .environ_map = run.environ_map != null,
                            },
                            .flags2 = .{
                                .expect_stderr_exact = expect_stderr_exact != null,
                                .expect_stdout_exact = expect_stdout_exact != null,
                                .expect_stderr_match = expect_stderr_match.items.len != 0,
                                .expect_stdout_match = expect_stdout_match.items.len != 0,
                                .expect_term = expect_term != null,
                                .expect_term_status = if (expect_term) |t| t.status else .exited,
                            },
                            .file_inputs = .{ .slice = try s.initLazyPathList(run.file_inputs.items) },
                            .args = .{ .slice = try s.initArgsList(run.argv.items) },
                            .cwd = .{ .value = try s.addOptionalLazyPath(run.cwd) },
                            .captured_stdout = .{ .value = if (run.captured_stdout) |cs| .{
                                .basename = try wc.addString(cs.output.basename),
                                .generated_file = cs.output.generated_file,
                            } else null },
                            .captured_stderr = .{ .value = if (run.captured_stderr) |cs| .{
                                .basename = try wc.addString(cs.output.basename),
                                .generated_file = cs.output.generated_file,
                            } else null },
                            .environ_map = .{ .value = try s.addEnvironMap(run.environ_map) },
                            .expect_term_value = .{ .value = if (expect_term) |t| t.value else null },
                            .stdio_limit = .{ .value = run.stdio_limit.toInt64() },
                            .producer = .{ .value = if (run.producer) |cs| s.stepIndex(&cs.step) else null },
                            .expect_stderr_exact = .{ .value = if (expect_stderr_exact) |bytes| bytes else null },
                            .expect_stdout_exact = .{ .value = if (expect_stdout_exact) |bytes| bytes else null },
                            .expect_stderr_match = .{ .slice = expect_stderr_match.items },
                            .expect_stdout_match = .{ .slice = expect_stdout_match.items },
                            .stdin = .{ .u = switch (run.stdin) {
                                .none => .none,
                                .bytes => |bytes| .{ .bytes = try wc.addBytes(bytes) },
                                .lazy_path => |lp| .{ .lazy_path = try s.addLazyPath(lp) },
                            } },
                        });
                    },
                    .check_file => e: {
                        const cf: *Step.CheckFile = @fieldParentPtr("step", step);
                        break :e try wc.addExtraErased(Configuration.Step.CheckFile, .{
                            .flags = .{
                                .expected_exact = cf.expected_exact != null,
                                .expected_matches = cf.expected_matches.len != 0,
                                .max_bytes = cf.max_bytes != null,
                            },
                            .file = try s.addLazyPath(cf.file),
                            .expected_exact = .{ .value = cf.expected_exact },
                            .expected_matches = .{ .slice = cf.expected_matches },
                            .max_bytes = .{ .value = cf.max_bytes },
                        });
                    },
                    .config_header => e: {
                        const ch: *Step.ConfigHeader = @fieldParentPtr("step", step);
                        const lazy_path: ?std.Build.LazyPath = ch.style.getPath();
                        const pairs = try arena.alloc(Configuration.Step.ConfigHeader.Value.Pair, ch.values.count());
                        for (pairs, ch.values.keys(), ch.values.values()) |*pair, key, value| pair.* = .{
                            .key = try wc.addString(key),
                            .index = switch (value) {
                                .undef => .undef,
                                .defined => .defined,
                                .boolean => |x| switch (x) {
                                    false => .bool_false,
                                    true => .bool_true,
                                },
                                .int => |x| switch (x) {
                                    0 => .int_0,
                                    1 => .int_1,
                                    else => try wc.addExtra(Configuration.Step.ConfigHeader.Value, .initSigned(x)),
                                },
                                .ident => |x| try wc.addExtra(Configuration.Step.ConfigHeader.Value, .{
                                    .flags = .{
                                        .tag = .ident,
                                        .small = 0,
                                    },
                                    .i64 = .{ .value = null },
                                    .u64 = .{ .value = null },
                                    .ident = .{ .value = try wc.addString(x) },
                                    .string = .{ .value = null },
                                }),
                                .string => |x| try wc.addExtra(Configuration.Step.ConfigHeader.Value, .{
                                    .flags = .{
                                        .tag = .string,
                                        .small = 0,
                                    },
                                    .i64 = .{ .value = null },
                                    .u64 = .{ .value = null },
                                    .ident = .{ .value = null },
                                    .string = .{ .value = try wc.addString(x) },
                                }),
                            },
                        };
                        break :e try wc.addExtraErased(Configuration.Step.ConfigHeader, .{
                            .flags = .{
                                .template_file = lazy_path != null,
                                .style = .init(ch.style),
                                .input_size_limit = ch.input_size_limit != null,
                                .include_guard = ch.include_guard != .none,
                            },
                            .template_file = .{ .value = try s.addOptionalLazyPath(lazy_path) },
                            .generated_dir = ch.generated_dir,
                            .input_size_limit = .{ .value = ch.input_size_limit },
                            .include_path = try wc.addString(ch.include_path),
                            .include_guard = .{ .value = ch.include_guard.unwrap() },
                            .values = .{ .slice = pairs },
                        });
                    },
                    .obj_copy => e: {
                        const oc: *Step.ObjCopy = @fieldParentPtr("step", step);

                        const debug_basename: ?Configuration.String = if (oc.debug_file) |df|
                            df.basename.unwrap()
                        else
                            null;

                        const debug_file: ?Configuration.GeneratedFileIndex = if (oc.debug_file) |df|
                            df.output_file
                        else
                            null;

                        const add_sections = try arena.alloc(
                            Configuration.Step.ObjCopy.AddSection,
                            oc.add_sections.items.len,
                        );
                        for (add_sections, oc.add_sections.items) |*dest, src| dest.* = .{
                            .section_name = src.section_name,
                            .file_path = try s.addLazyPath(src.file_path),
                        };

                        break :e try wc.addExtraErased(Configuration.Step.ObjCopy, .{
                            .flags = .{
                                .basename = oc.basename != .none,
                                .debug_file = debug_file != null,
                                .debug_basename = debug_basename != null,
                                .format = .init(oc.format),
                                .strip = oc.strip,
                                .compress_debug = oc.compress_debug,
                                .only_section = oc.only_section != .none,
                                .pad_to = oc.pad_to != null,
                                .add_section = add_sections.len != 0,
                                .update_section = oc.update_sections.items.len != 0,
                            },
                            .input_file = try s.addLazyPath(oc.input_file),
                            .output_file = oc.output_file,
                            .basename = .{ .value = oc.basename.unwrap() },
                            .debug_file = .{ .value = debug_file },
                            .debug_basename = .{ .value = debug_basename },
                            .only_section = .{ .value = oc.only_section.unwrap() },
                            .pad_to = .{ .value = oc.pad_to },
                            .add_section = .{ .slice = add_sections },
                            .update_section = .{ .slice = oc.update_sections.items },
                        });
                    },
                    .options => e: {
                        const so: *Step.Options = @fieldParentPtr("step", step);

                        const args = try arena.alloc(Configuration.Step.Options.Arg, so.args.items.len);
                        for (args, so.args.items) |*dest, src| dest.* = .{
                            .name = src.name,
                            .path = try s.addLazyPath(src.path),
                        };

                        break :e try wc.addExtraErased(Configuration.Step.Options, .{
                            .flags = .{
                                .args = so.args.items.len != 0,
                            },
                            .generated_file = so.generated_file,
                            .contents = try wc.addBytes(so.contents.items),
                            .args = .{ .slice = args },
                        });
                    },
                }),
            });
        }
    }

    try wc.unlazy_deps.ensureUnusedCapacity(gpa, graph.needed_lazy_dependencies.keys().len);
    for (graph.needed_lazy_dependencies.keys()) |k| {
        wc.unlazy_deps.appendAssumeCapacity(try wc.addString(k));
    }

    try wc.write(writer, .{
        .default_step = s.stepIndex(b.default_step),
        .generated_files_len = @intCast(graph.generated_files.items.len),
        .poisoned = switch (graph.cache_poison) {
            .pure, .disallowed, .ignored => false,
            .poisoned => true,
        },
    });
}

fn addOptionalResolvedTarget(
    wc: *Configuration.Wip,
    optional_resolved_target: ?std.Build.ResolvedTarget,
) !Configuration.ResolvedTarget.OptionalIndex {
    const resolved_target = optional_resolved_target orelse return .none;
    return .init(try wc.addDeduped(Configuration.ResolvedTarget, .{
        .query = try wc.addTargetQuery(&resolved_target.query),
        .result = try wc.addTarget(resolved_target.result),
    }));
}

fn addInstallDir(wc: *Configuration.Wip, install_dir: ?std.Build.InstallDir) !Configuration.InstallDestDir {
    switch (install_dir orelse return .none) {
        .prefix => return .prefix,
        .lib => return .lib,
        .bin => return .bin,
        .header => return .header,
        .custom => |sub_path| return .initCustom(try wc.addString(sub_path)),
    }
}

fn addInstallDirDefaultNull(wc: *Configuration.Wip, install_dir: ?std.Build.InstallDir) !?Configuration.InstallDestDir {
    return try addInstallDir(wc, install_dir orelse return null);
}

/// If the given `Step` is a `Step.Compile`, adds any dependencies for that step which
/// are implied by the module graph rooted at `step.cast(Step.Compile).?.root_module`.
fn createModuleDependenciesForStep(step: *Step) Allocator.Error!void {
    const root_module = if (step.cast(Step.Compile)) |cs| root: {
        break :root cs.root_module;
    } else return; // not a compile step so no module dependencies

    // Starting from `root_module`, discover all modules in this graph.
    const modules = root_module.getGraph().modules;

    // For each of those modules, set up the implied step dependencies.
    for (modules) |mod| {
        if (mod.root_source_file) |lp| lp.addStepDependencies(step);
        for (mod.include_dirs.items) |include_dir| switch (include_dir) {
            .path,
            .path_system,
            .path_after,
            .framework_path,
            .framework_path_system,
            .embed_path,
            => |lp| lp.addStepDependencies(step),

            .other_step => |other| {
                other.getEmittedIncludeTree().addStepDependencies(step);
                step.dependOn(&other.step);
            },

            .config_header_step => |other| step.dependOn(&other.step),
        };
        for (mod.lib_paths.items) |lp| lp.addStepDependencies(step);
        for (mod.rpaths.items) |rpath| switch (rpath) {
            .lazy_path => |lp| lp.addStepDependencies(step),
            .special => {},
        };
        for (mod.link_objects.items) |link_object| switch (link_object) {
            .static_path,
            .assembly_file,
            => |lp| lp.addStepDependencies(step),
            .other_step => |other| step.dependOn(&other.step),
            .system_lib => {},
            .c_source_file => |source| source.file.addStepDependencies(step),
            .c_source_files => |source_files| source_files.root.addStepDependencies(step),
            .win32_resource_file => |rc_source| {
                rc_source.file.addStepDependencies(step);
                for (rc_source.include_paths) |lp| lp.addStepDependencies(step);
            },
        };
    }
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

const ErrorStyle = enum {
    verbose,
    minimal,
    verbose_clear,
    minimal_clear,
    fn verboseContext(s: ErrorStyle) bool {
        return switch (s) {
            .verbose, .verbose_clear => true,
            .minimal, .minimal_clear => false,
        };
    }
    fn clearOnUpdate(s: ErrorStyle) bool {
        return switch (s) {
            .verbose, .minimal => false,
            .verbose_clear, .minimal_clear => true,
        };
    }
};
const MultilineErrors = enum { indent, newline, none };
const Summary = enum { all, new, failures, line, none };

fn fatalWithHint(comptime f: []const u8, args: anytype) noreturn {
    log.info("to access the help menu: zig build -h", .{});
    fatal(f, args);
}

fn serializeSystemIntegrationOptions(graph: *std.Build.Graph, wc: *Configuration.Wip) Allocator.Error!void {
    const gpa = wc.gpa;

    var bad = false;
    try wc.system_integrations.ensureTotalCapacityPrecise(gpa, graph.system_integration_options.entries.len);
    for (graph.system_integration_options.keys(), graph.system_integration_options.values()) |k, v| {
        wc.system_integrations.appendAssumeCapacity(.{
            .name = try wc.addString(k),
            .status = switch (v) {
                .user_disabled, .user_enabled => x: {
                    // The user tried to enable or disable a system library integration, but
                    // the configure script did not recognize that option.
                    log.err("system integration name not recognized by configure script: {s}", .{k});
                    bad = true;
                    break :x .disabled;
                },
                .declared_disabled => .disabled,
                .declared_enabled => .enabled,
            },
        });
    }
    if (bad) {
        log.info("help menu contains available options: zig build -h", .{});
        process.exit(1);
    }
}

fn serializePackageOptions(b: *std.Build, wc: *Configuration.Wip) Allocator.Error!void {
    const gpa = wc.gpa;

    try wc.available_options.ensureTotalCapacityPrecise(gpa, b.available_options_map.count());
    for (b.available_options_map.keys(), b.available_options_map.values()) |name, *opt| {
        wc.available_options.appendAssumeCapacity(.{
            .name = try wc.addString(name),
            .description = try wc.addString(opt.description),
            .type = opt.type_id,
            .enum_options = if (opt.enum_options) |enum_vals| .init(try wc.addStringList(enum_vals)) else .none,
        });
    }
}

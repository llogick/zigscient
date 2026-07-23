//! Holds a build.zig's Configuration and Build(Compilation)

/// FlatUri path to a `build.zig`
flat_uri: FlatUri,
/// Explicitly specified path to builtin.zig
builtin_uri: ?FlatUri = null,
/// options loaded from a zls.build.json
options: ?std.json.Parsed(BuildOptions) = null,
build: Build = .{},
configuration: Configuration = .{},

pub const Configuration = struct {
    mutex: std.Io.Mutex = .init,
    loader_state: LoaderState = .ready,
    version: u32 = 0,
    config: ?std.json.Parsed(Config) = null,
    cfg_file_path: ?[]const u8 = null,
    roots: Roots = .init,

    pub fn release(cfg: *Configuration, io: std.Io) void {
        cfg.mutex.unlock(io);
    }
};

pub const Roots = struct {
    /// The user selected index within map.keys()
    index: u32 = 0,
    tailor_run_state: enum {
        pending,
        success,
        failure,
    } = .pending,
    info_file_path: ?[]const u8 = null,
    map: std.AutoArrayHashMapUnmanaged(u32, BldDoc.CompileStep),

    pub const init: Roots = .{ .map = .empty };

    pub fn deinit(roots: *Roots, allocator: std.mem.Allocator) void {
        var map = roots.map;
        for (map.values()) |*value| {
            allocator.free(value.name);
            if (value.args) |args| {
                for (args) |arg| allocator.free(arg);
                allocator.free(args);
            }
            for (value.mods.items) |item| {
                allocator.free(item.name);
                allocator.free(item.path);
            }
            value.mods.deinit(allocator);
        }
        map.deinit(allocator);
        if (roots.info_file_path) |ifp| allocator.free(ifp);
    }
};

pub const CompileStep = struct {
    name: []const u8,
    args: ?[]const []const u8 = null,
    mods: std.ArrayList(NamePathPair) = .empty,

    pub const NamePathPair = struct {
        name: []const u8,
        path: []const u8,
    };
};

pub const Build = struct {
    mutex: std.Io.Mutex = .init,
    arena_instance: std.heap.ArenaAllocator = undefined,
    state: ?*CompilationState = null,
    compilation: ?*Compilation = null,
    args: []const []const u8 = undefined,
    has_completed_once: bool = false,
};

const LoaderState = enum {
    ready,
    running,
    running_but_result_already_outdated,
};

pub fn getConfiguration(self: *BldDoc, io: std.Io) *Configuration {
    self.configuration.mutex.lockUncancelable(io);
    return &self.configuration;
}

/// Usage example:
/// ```zig
/// const package_uris: std.ArrayList([]const u8) = .empty;
/// defer {
///     for (package_uris) |uri| allocator.free(uri);
///     package_uris.deinit(allocator);
/// }
/// const success = try build_file.collectBuildConfigPackageUris(allocator, &package_uris);
/// ```
pub fn collectBuildConfigPackageUris(
    self: *BldDoc,
    io: std.Io,
    allocator: std.mem.Allocator,
    package_uris: *std.ArrayList(FlatUri),
) error{OutOfMemory}!bool {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const cfg = self.getConfiguration(io);
    defer cfg.release(io);
    const build_config = cfg.config orelse return false;

    try package_uris.ensureUnusedCapacity(allocator, build_config.value.modules.len);
    for (build_config.value.modules) |module| {
        package_uris.appendAssumeCapacity(try uri_util.fromPath(allocator, module.path));
    }
    return true;
}

/// Usage example:
/// ```zig
/// const include_paths: std.ArrayList([]u8) = .empty;
/// defer {
///     for (include_paths) |path| allocator.free(path);
///     include_paths.deinit(allocator);
/// }
/// const success = try build_file.collectBuildConfigIncludePaths(allocator, &include_paths);
/// ```
pub fn collectBuildConfigIncludePaths(
    self: *BldDoc,
    io: std.Io,
    allocator: std.mem.Allocator,
    include_paths: *std.ArrayList([]const u8),
) error{OutOfMemory}!bool {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const build_config = self.tryLockConfig(io) orelse return false;
    defer self.unlockConfig(io);

    try include_paths.ensureUnusedCapacity(allocator, build_config.include_dirs.len);
    for (build_config.include_dirs) |include_path| {
        const absolute_path = if (std.fs.path.isAbsolute(include_path))
            try allocator.dupe(u8, include_path)
        else blk: {
            const build_file_dir = std.fs.path.dirname(self.uri).?;
            const build_file_path = uri_util.toFsPath(allocator, build_file_dir) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => continue,
            };
            defer allocator.free(build_file_path);
            break :blk try std.fs.path.join(allocator, &.{ build_file_path, include_path });
        };

        include_paths.appendAssumeCapacity(absolute_path);
    }
    return true;
}

pub fn triggerTailorRun(self: *BldDoc, ds: *DocumentStore) std.Io.Cancelable!void {
    self.runTailor(ds) catch |err| switch (err) {
        error.Canceled => |e| return e,
        else => |e| {
            log.err("Failed to extract full compile steps info for {q} : {t}", .{ self.flat_uri, e });
            return;
        },
    };
}

pub fn runTailor(build_file: *BldDoc, ds: *DocumentStore) !void {
    if (!std.process.can_spawn) return;
    if (ds.config.bss_check != .success) return;

    const io = ds.io;
    const self_file_path = ds.config.self_file_path orelse return;

    const config = build_file.getConfiguration(io);
    defer config.release(io);

    if (config.roots.tailor_run_state != .pending) return;
    errdefer config.roots.tailor_run_state = .failure;

    const map = config.roots.map;
    if (!(config.roots.index < map.count())) return error.RequestedRootIndexOOB;
    const step_index = map.keys()[config.roots.index];

    std.debug.assert(ds.config.zig_exe_path != null);
    std.debug.assert(ds.config.global_cache_dir != null);
    std.debug.assert(ds.config.zig_lib_dir != null);

    var arena_state = std.heap.ArenaAllocator.init(ds.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const build_file_path = try uri_util.toFsPath(arena, build_file.flat_uri);
    const cwd = std.fs.path.dirname(build_file_path).?;
    var args: std.ArrayList([]const u8) = .empty;

    try args.appendSlice(arena, &.{
        self_file_path,
        "maker",
        "build",
        try arena.print("--zig-lib={s}", .{ds.config.zig_lib_dir.?.path.?}),
        try arena.print("--zig={s}", .{ds.config.zig_exe_path.?}),
        try arena.print("--global-cache={s}", .{ds.config.global_cache_dir.?.path.?}),
        try arena.print("--seed=0x{x}", .{@import("compiler").randInt(io, u32)}),
        "--zigscient",
        try arena.print("{s}{}", .{ lsp_server.Maker.step_index_arg_prefix, step_index }),
    });

    var token = ds.notifyProgressStart(.tlr_progress, build_file.flat_uri);
    defer if (token) |t| {
        ds.notifyProgressEnd(t, .success);
        token = null;
    };
    errdefer if (token) |t| {
        ds.notifyProgressEnd(t, .failure);
        token = null;
    };

    const tailor_run_result = blk: {
        const tracy_zone2 = tracy.trace(@src());
        defer tracy_zone2.end();
        break :blk try std.process.run(
            arena,
            io,
            .{
                .argv = args.items,
                .cwd = .{ .path = cwd },
                .reserve_amount = 1024 * 1024,
            },
        );
    };

    const is_ok = switch (tailor_run_result.term) {
        .exited => |exit_code| exit_code == 0,
        else => false,
    };

    if (!is_ok) {
        const joined = try std.mem.join(arena, " ", args.items);

        log.err(
            "Failed to compile {q} from {q}\nDIR: {s}\nCMD: {s}\nERR:\n{s}",
            .{ map.values()[config.roots.index].name, build_file.flat_uri, cwd, joined, tailor_run_result.stderr },
        );

        return error.RunFailed;
    }

    const parse_options: std.json.ParseOptions = .{
        // We ignore unknown fields so people can roll
        // their own build runners in libraries with
        // the only requirement being general adherence
        // to the BuildConfig type
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    };
    const json = std.json.parseFromSlice(
        lsp_server.Maker.CompileStepsInfo,
        arena,
        tailor_run_result.stdout,
        parse_options,
    ) catch return error.InvalidBuildConfig;
    defer json.deinit();

    for (json.value.compile_steps_info) |csi| {
        const cs = config.roots.map.getPtr(@backingInt(csi.index)) orelse {
            log.debug("runTailor: received data for an inactive compile step index: {}", .{csi.index});
            continue;
        };

        if (cs.args) |prev_args| {
            for (prev_args) |prev_arg| ds.allocator.free(prev_arg);
        }
        var new_args: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (new_args.items) |new_arg| ds.allocator.free(new_arg);
            new_args.deinit(ds.allocator);
        }
        for (csi.args) |new_arg| try new_args.append(ds.allocator, try ds.allocator.dupe(u8, new_arg));
        cs.args = try new_args.toOwnedSlice(ds.allocator);

        for (cs.mods.items) |mod| {
            ds.allocator.free(mod.name);
            ds.allocator.free(mod.path);
        }
        cs.mods.items.len = 0;

        for (csi.mods) |mod| {
            try cs.mods.append(ds.allocator, .{ .name = try ds.allocator.dupe(u8, mod.name), .path = try ds.allocator.dupe(u8, mod.path) });
        }
    }

    config.roots.tailor_run_state = .success;

    for (ds.workspaces.items) |wrkspc_item| {
        if (std.mem.eql(u8, build_file.flat_uri, wrkspc_item.build_file_uri orelse continue)) {
            ds.wait_group.async(ds.io, BldDoc.triggerRedoCompilation, .{ build_file, ds });
            break;
        }
    }
}

pub fn triggerRedoCompilation(self: *BldDoc, ds: *DocumentStore) std.Io.Cancelable!void {
    self.redoCompilation(ds) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        error.OutOfMemory => @panic("OOM"),
    };
}

fn redoCompilation(self: *BldDoc, ds: *DocumentStore) error{ Canceled, OutOfMemory }!void {
    self.destroyCompilation(ds, !ds.config.disable_compilations);
    if (ds.config.disable_compilations) return;
    try self.initCompilation(ds);
}

fn destroyCompilation(self: *BldDoc, ds: *DocumentStore, do_retain_capacity: bool) void {
    self.build.mutex.lockUncancelable(ds.io);
    defer self.build.mutex.unlock(ds.io);
    if (self.build.compilation) |comp| {
        log.info("Destroying the Compilation for {q}", .{self.flat_uri});
        comp.destroy();
    }
    if (self.build.state) |state| {
        ds.diagnostics_collection.clearErrorBundle(self.build.state.?.diag_tag);
        state.deinit(ds.allocator);
        self.build.state = null;
    }
    self.build.compilation = null;
    _ = self.build.arena_instance.reset(if (do_retain_capacity) .retain_capacity else .free_all);
    self.build.has_completed_once = false;
}

fn initCompilation(self: *BldDoc, ds: *DocumentStore) error{ Canceled, OutOfMemory }!void {
    if (ds.config.bss_check != .success) return;

    const cfg = self.getConfiguration(ds.io);
    defer cfg.release(ds.io);

    const roots_count = cfg.roots.map.count();
    if (roots_count == 0 or !(cfg.roots.index < roots_count)) return;
    const cs = cfg.roots.map.values()[cfg.roots.index];

    var cleanup: bool = false;
    defer if (cleanup) {
        self.destroyCompilation(ds, false);
        log.err("Failed to create a compilation for: {s}", .{self.flat_uri});
    };

    const arena = self.build.arena_instance.allocator();
    var args_dups: std.ArrayList([]const u8) = .empty;
    const proj_path = pp: {
        const fs_path = uri_util.toFsPath(arena, self.flat_uri) catch return;
        const proj_path = std.fs.path.dirname(fs_path).?;
        break :pp proj_path;
    };

    const args = cs.args orelse return;
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--listen")) continue;
        try args_dups.append(arena, try arena.dupe(u8, arg));
    }
    try args_dups.appendSlice(arena, &.{
        "-fincremental",
        "-fno-emit-bin",
        "-fno-emit-asm",
        "-fno-emit-llvm-ir",
        "-fno-emit-llvm-bc",
        "-fno-emit-h",
        "-fno-emit-docs",
        "-fno-emit-implib",
        "-fno-llvm",
    });
    self.build.args = try args_dups.toOwnedSlice(arena);

    log.info("Creating a Compilation for: {s}\n{s}", .{ self.flat_uri, try std.json.Stringify.valueAlloc(arena, self.build.args, .{}) });

    self.build.state = try arena.create(CompilationState);
    const cs_ptr = self.build.state.?;
    cs_ptr.* = .{};
    cs_ptr.*.project_root_path = proj_path;
    cs_ptr.*.io_impl = switch (build_options.io_mode) {
        .threaded => .init(compiler.globals.root_gpa, .{
            .stack_size = compiler.thread_stack_size,

            .argv0 = .init(compiler.globals.init.args),
            .environ = compiler.globals.init.environ,
        }),
        .evented => try .init(compiler.globals.root_gpa, .{
            .argv0 = .init(compiler.globals.init.args),
            .environ = compiler.globals.init.environ,

            .backing_allocator_needs_mutex = false,
        }),
    };
    cs_ptr.*.io = cs_ptr.*.io_impl.io();

    var hasher: std.hash.Wyhash = .init(@intFromPtr(cs_ptr));
    hasher.update(proj_path);
    std.hash.autoHash(&hasher, cs_ptr);
    cs_ptr.*.diag_tag = @fromBackingInt(@intCast(@as(u32, @truncate(hasher.final()))));

    const gpa = switch (build_options.io_mode) {
        .threaded => compiler.globals.root_gpa,
        .evented => cs_ptr.*.io_impl.allocator(),
    };

    const cmd = self.build.args[1];
    const arg_mode: compiler.ArgMode =
        if (std.mem.eql(u8, cmd, "build-exe")) .{ .build = .Exe } //
        else if (std.mem.eql(u8, cmd, "build-lib")) .{ .build = .Lib } //
        else if (std.mem.eql(u8, cmd, "build-obj")) .{ .build = .Obj } //
        else {
            log.err("initCompilation: unknown cmd: {s}", .{cmd});
            return;
        };
    buildOutputType(
        gpa,
        arena,
        cs_ptr.*.io,
        self.build.args,
        arg_mode,
        ds.config.environ_map,
        self.build.state.?,
        ds,
        &self.build,
    ) catch |err| switch (err) {
        error.Canceled, error.OutOfMemory => |e| return e,
        else => cleanup = true,
    };
}

pub fn deinit(self: *BldDoc, allocator: std.mem.Allocator) void {
    allocator.free(self.flat_uri);
    if (self.configuration.config) |cfg| cfg.deinit();
    if (self.builtin_uri) |builtin_uri| allocator.free(builtin_uri);
    if (self.options) |opts| opts.deinit();

    if (self.build.compilation) |comp| {
        comp.destroy();
        if (self.build.state) |state| {
            state.deinit(allocator);
            self.build.state = null;
        }
    }
    self.build.arena_instance.deinit();

    if (self.configuration.cfg_file_path) |cfp| allocator.free(cfp);
    self.configuration.roots.deinit(allocator);
}

const BldDoc = @This();

const build_options = @import("build_options");
const lsp_server = @import("lsp-server");
const std = @import("std");
const uri_util = @import("uri.zig");
const BuildOptions = @import("BuildOptions.zig");
const Config = @import("build_runner/shared.zig").BuildConfig;
const DocumentStore = @import("DocumentStore.zig");
const DiagnosticsCollection = @import("DiagnosticsCollection.zig");
const tracy = @import("tracy");

const log = std.log.scoped(.ls_bdoc);

pub const FlatUri = []const u8;

/// Compiler and Compilation declarations
pub const compiler = @import("compiler");
pub const Compilation = compiler.Compilation;
const CompilationState = compiler.CompilationState;
const buildOutputType = compiler.buildOutputType;

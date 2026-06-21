//! read and resolve configuration options.

const std = @import("std");
const builtin = @import("builtin");

const zig_info = @import("zig_info.zig");
const Settings = @import("Settings.zig");

const known_folders = @import("known-folders");
const tracy = @import("tracy");

const log = std.log.scoped(.lspc_config);

pub const Manager = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    environ_map: *std.process.Environ.Map,
    config: Settings,
    self_file_path: ?[]const u8,
    zig_exe: ?struct {
        /// Same as `Manager.config.zig_exe_path.?`
        path: []const u8,
        version: std.SemanticVersion,
        env: zig_info.ZigEnv,
    },
    zig_lib_dir: ?std.Build.Cache.Directory,
    global_cache_dir: ?std.Build.Cache.Directory,
    wasi_preopens: switch (builtin.os.tag) {
        .wasi => std.process.Preopens,
        else => void,
    },
    /// Build System Support check
    bss_check: BssCheckState,
    impl: struct {
        is_dirty: bool,
        configs: std.EnumArray(Tag, UnresolvedConfig),
        /// Every changed configuration will increase the amount of memory
        /// allocated by the arena. This is unlikely to cause high memory
        /// consumption since the user is probably not going set settings
        /// often in one session.
        arena: std.heap.ArenaAllocator.State,
    },

    pub const BssCheckState = enum {
        failure,
        /// Check hasn't been performed yet
        pending,
        /// Minimum requirements to read Configuration met
        partial,
        /// Can read Configuration and make steps
        success,
    };

    pub fn init(
        io: std.Io,
        allocator: std.mem.Allocator,
        environ_map: *std.process.Environ.Map,
        self_file_path: ?[]const u8,
    ) error{ OutOfMemory, Unexpected }!Manager {
        var arena_allocator: std.heap.ArenaAllocator = .init(allocator);
        errdefer arena_allocator.deinit();
        return .{
            .io = io,
            .allocator = allocator,
            .environ_map = environ_map,
            .self_file_path = self_file_path,
            .zig_exe = null,
            .zig_lib_dir = null,
            .global_cache_dir = null,
            .bss_check = .pending,
            .wasi_preopens = switch (builtin.os.tag) {
                .wasi => try std.process.Preopens.init(arena_allocator.allocator()),
                else => {},
            },
            .config = .{},
            .impl = .{
                .is_dirty = true,
                .configs = .initFill(.{}),
                .arena = arena_allocator.state,
            },
        };
    }

    pub fn deinit(manager: *Manager) void {
        const io = manager.io;
        const allocator = manager.allocator;
        if (builtin.os.tag != .wasi) {
            if (manager.zig_lib_dir) |*zig_lib_dir| zig_lib_dir.handle.close(io);
            if (manager.global_cache_dir) |*global_cache_dir| global_cache_dir.handle.close(io);
        }
        manager.impl.arena.promote(allocator).deinit();
        manager.* = undefined;
    }

    /// Defines independent configuration option providers. Ordered in increasing priority.
    pub const Tag = enum {
        /// Configuration provided when the server has been created (`main.zig`).
        frontend,
        /// `initializationOptions` during `initialize`
        lsp_initialization,
        /// `workspace/didChangeConfiguration` or `workspace/configuration`
        lsp_configuration,
    };

    /// Does not resolve or validate config options until `resolveConfiguration` has been called.
    pub fn setConfiguration(
        manager: *Manager,
        tag: Tag,
        config: *const UnresolvedConfig,
    ) error{OutOfMemory}!void {
        var arena_allocator: std.heap.ArenaAllocator = manager.impl.arena.promote(manager.allocator);
        defer manager.impl.arena = arena_allocator.state;

        var duped: UnresolvedConfig = .{};
        inline for (comptime std.meta.fieldNames(UnresolvedConfig), comptime std.meta.fieldTypes(UnresolvedConfig)) |field_name, field_type| {
            @field(duped, field_name) = try option.dupe(field_type, @field(config, field_name), arena_allocator.allocator());
        }
        manager.impl.configs.set(tag, duped);
        manager.impl.is_dirty = true;
    }

    /// Does not resolve or validate config options until `resolveConfiguration` has been called.
    pub fn setConfiguration2(
        manager: *Manager,
        tag: Tag,
        config: *const Settings,
    ) error{OutOfMemory}!void {
        var cfg: UnresolvedConfig = .{};
        inline for (comptime std.meta.fieldNames(Settings)) |field_name| {
            @field(cfg, field_name) = @field(config, field_name);
        }
        try manager.setConfiguration(tag, &cfg);
    }

    pub const ResolveConfigurationResult = struct {
        did_change: DidConfigChange,
        messages: [][]const u8,

        pub fn deinit(result: *ResolveConfigurationResult, allocator: std.mem.Allocator) void {
            for (result.messages) |msg| allocator.free(msg);
            allocator.free(result.messages);
            result.* = undefined;
        }
    };

    pub fn resolveConfiguration(
        manager: *Manager,
        result_allocator: std.mem.Allocator,
    ) error{ Canceled, OutOfMemory }!ResolveConfigurationResult {
        if (!manager.impl.is_dirty) {
            return .{
                .did_change = .{},
                .messages = &.{},
            };
        }

        var arena_allocator: std.heap.ArenaAllocator = manager.impl.arena.promote(manager.allocator);
        const arena = arena_allocator.allocator();
        defer manager.impl.arena = arena_allocator.state;

        const io = manager.io;

        var config: Settings = .{
            .zig_lib_path = if (builtin.os.tag == .wasi) "/lib" else null,
            .global_cache_path = if (builtin.os.tag == .wasi) "/cache" else null,
        };
        for (manager.impl.configs.values) |unresolved_config| {
            inline for (comptime std.meta.fieldNames(UnresolvedConfig)) |field_name| {
                if (@field(unresolved_config, field_name)) |new_value| {
                    @field(config, field_name) = new_value;
                }
            }
        }

        var messages: std.ArrayList([]const u8) = .empty;
        defer {
            for (messages.items) |msg| result_allocator.free(msg);
            messages.deinit(result_allocator);
        }

        try validateConfiguration(io, result_allocator, &config, &messages);

        if (config.zig_exe_path == null) blk: {
            if (!std.process.can_spawn) break :blk;
            const zig_exe_path = try zig_info.findZig(io, manager.allocator, manager.environ_map) orelse break :blk;
            defer manager.allocator.free(zig_exe_path);
            config.zig_exe_path = try arena.dupe(u8, zig_exe_path);
        }

        if (config.zig_exe_path) |exe_path| unresolved_zig: {
            if (!std.process.can_spawn) break :unresolved_zig;

            const zig_env = try zig_info.getZigEnv(io, manager.allocator, arena, exe_path) orelse break :unresolved_zig;

            const zig_version = std.SemanticVersion.parse(zig_env.version) catch |err| {
                log.err("zig env returned a zig version that is an invalid semantic version: {}", .{err});
                break :unresolved_zig;
            };

            manager.zig_exe = .{
                .path = exe_path,
                .version = zig_version,
                .env = zig_env,
            };
        }

        if (config.zig_lib_path == null) blk: {
            if (!std.process.can_spawn) break :blk;
            const zig_exe = manager.zig_exe orelse break :blk;
            const zig_lib_dir = zig_exe.env.lib_dir orelse break :blk;

            if (std.fs.path.isAbsolute(zig_lib_dir)) {
                config.zig_lib_path = try arena.dupe(u8, zig_lib_dir);
            } else {
                const cwd = std.process.currentPathAlloc(io, manager.allocator) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => |e| {
                        log.err("failed to resolve current working directory: {}", .{e});
                        break :blk;
                    },
                };
                defer manager.allocator.free(cwd);
                config.zig_lib_path = try std.fs.path.join(arena, &.{ cwd, zig_lib_dir });
            }
        }

        for (
            [_]*?[]const u8{ &config.zig_lib_path, &config.global_cache_path },
            [_]*?std.Build.Cache.Directory{ &manager.zig_lib_dir, &manager.global_cache_dir },
            [_]enum { open, create }{ .open, .create },
            [_][]const u8{ "zig library", "global cache" },
        ) |opt_path, result_dir, action, name| {
            const path = opt_path.* orelse continue;
            if (builtin.target.os.tag == .wasi) {
                // TODO The path could be a subdirectory of a preopen directory
                const resource = manager.wasi_preopens.get(path) orelse {
                    log.warn("failed to resolve '{s}' WASI preopen", .{path});
                    opt_path.* = null;
                    continue;
                };
                switch (resource) {
                    .dir => |dir| {
                        result_dir.* = .{ .handle = dir, .path = path };
                        continue;
                    },
                    .file => {
                        log.err("failed to resolve {s} directory '{s}': {}", .{ name, path, std.Io.File.OpenError.NotDir });
                        opt_path.* = null;
                        continue;
                    },
                }
            } else {
                const dir = switch (action) {
                    .open => std.Io.Dir.cwd().openDir(io, path, .{}),
                    .create => std.Io.Dir.cwd().createDirPathOpen(io, path, .{}),
                } catch |err| switch (err) {
                    error.Canceled => return error.Canceled,
                    else => {
                        log.err("failed to {t} {s} directory '{s}': {}", .{ action, name, path, err });
                        opt_path.* = null;
                        continue;
                    },
                };
                result_dir.* = .{ .handle = dir, .path = path };
                continue;
            }
            comptime unreachable;
        }

        brunner: {
            if (!std.process.can_spawn or builtin.is_test) break :brunner;
            const zig_exe = manager.zig_exe orelse break :brunner;
            manager.bss_check = if (@import("build_runner/check.zig").isBuildRunnerSupported(zig_exe.version)) .partial else .failure;
            if (manager.bss_check == .partial and manager.self_file_path != null) manager.bss_check = .success;
        }

        if (config.builtin_path == null) blk: {
            if (!std.process.can_spawn) break :blk;
            const zig_exe = manager.zig_exe orelse break :blk;
            const global_cache_dir = manager.global_cache_dir orelse break :blk;

            const argv = [_][]const u8{
                zig_exe.path,
                "build-exe",
                "--show-builtin",
            };

            const run_result = std.process.run(
                manager.allocator,
                io,
                .{
                    .argv = &argv,
                    .reserve_amount = 16 * 1024 * 1024,
                },
            ) catch |err| switch (err) {
                error.Canceled => return error.Canceled,
                else => {
                    const args = std.mem.join(manager.allocator, " ", &argv) catch break :blk;
                    log.err("failed to run command '{s}': {}", .{ args, err });
                    break :blk;
                },
            };
            defer manager.allocator.free(run_result.stdout);
            defer manager.allocator.free(run_result.stderr);

            global_cache_dir.handle.writeFile(io, .{
                .sub_path = "default_builtin_source.zig",
                .data = run_result.stdout,
            }) catch |err| switch (err) {
                error.Canceled => return error.Canceled,
                else => {
                    log.err("failed to write file '{f}default_builtin_source.zig': {}", .{ global_cache_dir, err });
                    break :blk;
                },
            };

            config.builtin_path = try global_cache_dir.join(arena, &.{"default_builtin_source.zig"});
        }

        var did_change: DidConfigChange = .{};

        inline for (comptime std.meta.fieldNames(Settings), comptime std.meta.fieldTypes(Settings)) |field_name, field_type| {
            const old_value = &@field(manager.config, field_name);
            const new_value = @field(config, field_name);

            const is_eql = option.eql(field_type, old_value.*, new_value);
            @field(did_change, field_name) = !is_eql;

            if (!is_eql) {
                old_value.* = try option.dupe(field_type, new_value, arena_allocator.allocator());
            }
        }

        manager.impl.is_dirty = false;
        return .{
            .did_change = did_change,
            .messages = try messages.toOwnedSlice(result_allocator),
        };
    }

    fn validateConfiguration(
        io: std.Io,
        allocator: std.mem.Allocator,
        config: *Settings,
        messages: *std.ArrayList([]const u8),
    ) error{ Canceled, OutOfMemory }!void {
        if (builtin.os.tag == .wasi) return;

        var values: [file_system_config_options.len]*?[]const u8 = undefined;
        inline for (file_system_config_options, &values) |file_config, *value| {
            value.* = &@field(config, file_config.name);
        }

        for (file_system_config_options, &values) |file_config, value| {
            const is_ok = if (value.*) |path| ok: {
                // Convert `""` to `null`
                if (path.len == 0) {
                    // Thank you Visual Studio Trash Code
                    value.* = null;
                    break :ok true;
                }

                if (!std.fs.path.isAbsolute(path)) {
                    try messages.ensureUnusedCapacity(allocator, 1);
                    messages.appendAssumeCapacity(try std.fmt.allocPrint(
                        allocator,
                        "config option '{s}': expected absolute path but got '{s}'",
                        .{ file_config.name, path },
                    ));
                    break :ok false;
                }

                switch (file_config.kind) {
                    .file => {
                        const file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch |err| switch (err) {
                            error.Canceled => return error.Canceled,
                            else => {
                                if (file_config.is_accessible) {
                                    try messages.ensureUnusedCapacity(allocator, 1);
                                    messages.appendAssumeCapacity(try std.fmt.allocPrint(
                                        allocator,
                                        "config option '{s}': invalid file path '{s}': {}",
                                        .{ file_config.name, path, err },
                                    ));
                                    break :ok false;
                                }
                                break :ok true;
                            },
                        };
                        defer file.close(io);

                        const stat = file.stat(io) catch |err| switch (err) {
                            error.Canceled => return error.Canceled,
                            else => {
                                try messages.ensureUnusedCapacity(allocator, 1);
                                messages.appendAssumeCapacity(try std.fmt.allocPrint(
                                    allocator,
                                    "config option '{s}': failed to access '{s}': {}",
                                    .{ file_config.name, path, err },
                                ));
                                break :ok true;
                            },
                        };
                        switch (stat.kind) {
                            .directory => {
                                try messages.ensureUnusedCapacity(allocator, 1);
                                messages.appendAssumeCapacity(try std.fmt.allocPrint(
                                    allocator,
                                    "config option '{s}': expected file path but '{s}' is a directory",
                                    .{ file_config.name, path },
                                ));
                                break :ok false;
                            },
                            .file => {},
                            // are there file kinds that should warn?
                            // what about symlinks?
                            else => {},
                        }
                        break :ok true;
                    },
                    .directory => {
                        var dir = std.Io.Dir.openDirAbsolute(io, path, .{}) catch |err| switch (err) {
                            error.Canceled => return error.Canceled,
                            else => {
                                if (file_config.is_accessible) {
                                    try messages.ensureUnusedCapacity(allocator, 1);
                                    messages.appendAssumeCapacity(try std.fmt.allocPrint(
                                        allocator,
                                        "config option '{s}': invalid directory path '{s}': {}",
                                        .{ file_config.name, path, err },
                                    ));
                                    break :ok false;
                                }
                                break :ok true;
                            },
                        };
                        defer dir.close(io);
                        const stat = dir.stat(io) catch |err| switch (err) {
                            error.Canceled => return error.Canceled,
                            else => {
                                log.err("failed to get stat of '{s}': {}", .{ path, err });
                                break :ok true;
                            },
                        };
                        switch (stat.kind) {
                            .file => {
                                try messages.ensureUnusedCapacity(allocator, 1);
                                messages.appendAssumeCapacity(try std.fmt.allocPrint(
                                    allocator,
                                    "config option '{s}': expected directory path but '{s}' is a file",
                                    .{ file_config.name, path },
                                ));
                                break :ok false;
                            },
                            .directory => {},
                            // are there file kinds that should warn?
                            // what about symlinks?
                            else => {},
                        }
                        break :ok true;
                    },
                }
            } else true;

            if (!is_ok) {
                value.* = null;
            }
        }
    }
};

/// Helper functions to manage a single config option.
pub const option = struct {
    fn free(comptime T: type, value: T, allocator: std.mem.Allocator) void {
        const val = switch (@typeInfo(T)) {
            .optional => if (value) |val| val else return,
            else => value,
        };
        switch (@typeInfo(@TypeOf(val))) {
            .pointer => switch (@TypeOf(val)) {
                []const []const u8 => {
                    for (val) |str| allocator.free(str);
                    allocator.free(val);
                },
                []const u8 => allocator.free(val),
                else => comptime unreachable,
            },
            .bool, .int, .float, .@"enum" => {},
            else => comptime unreachable,
        }
    }

    fn dupe(comptime T: type, value: T, allocator: std.mem.Allocator) error{OutOfMemory}!T {
        const val = switch (@typeInfo(T)) {
            .optional => if (value) |val| val else return null,
            else => value,
        };
        switch (@TypeOf(val)) {
            []const []const u8 => {
                const copy = try allocator.alloc([]const u8, val.len);
                @memset(copy, "");
                errdefer {
                    for (copy) |str| allocator.free(str);
                    allocator.free(copy);
                }
                for (copy, val) |*duped, original| duped.* = try allocator.dupe(u8, original);
                return copy;
            },
            []const u8 => return try allocator.dupe(u8, val),
            else => return val,
        }
    }

    fn eql(comptime T: type, a: T, b: T) bool {
        const a_val, const b_val = switch (@typeInfo(T)) {
            .optional => blk: {
                if (a == null and b == null) return true;
                if ((a == null) != (b == null)) return false;
                break :blk .{ a.?, b.? };
            },
            else => .{ a, b },
        };

        switch (@TypeOf(a_val)) {
            []const []const u8 => {
                if (a_val.len != b_val.len) return false;
                for (a_val, b_val) |a_elem, b_elem| if (!std.mem.eql(u8, a_elem, b_elem)) return false;
                return true;
            },
            []const u8 => return std.mem.eql(u8, a_val, b_val),
            else => return a_val == b_val,
        }
    }
};

pub const FileConfigInfo = struct {
    name: []const u8,
    kind: enum { file, directory },
    is_accessible: bool,
};

/// A list of config options that represent file system paths.
pub const file_system_config_options: []const FileConfigInfo = &.{
    .{ .name = "zig_exe_path", .kind = .file, .is_accessible = true },
    .{ .name = "builtin_path", .kind = .file, .is_accessible = true },
    .{ .name = "zig_lib_path", .kind = .directory, .is_accessible = true },
    .{ .name = "global_cache_path", .kind = .directory, .is_accessible = false },
};

comptime {
    skip: for (std.meta.fieldNames(Settings)) |field_name| {
        @setEvalBranchQuota(2_000);
        if (std.mem.find(u8, field_name, "path") == null) continue;

        for (file_system_config_options) |file_config| {
            if (std.mem.eql(u8, file_config.name, field_name)) continue :skip;
        }

        @compileError(std.fmt.comptimePrint(
            \\config option '{s}' contains the word 'path'.
            \\Please add config option validation checks below if necessary.
            \\If not necessary, just add a check above to ignore this error.
            \\
        , .{field_name}));
    }
}

/// The same struct as `Settings` but every field is optional.
pub const UnresolvedConfig = blk: {
    const struct_info: std.lang.Type.Struct = @typeInfo(Settings).@"struct";
    var field_types: [struct_info.field_names.len]type = undefined;
    var field_attrs: [struct_info.field_names.len]std.lang.Type.Struct.FieldAttributes = undefined;
    for (&field_types, &field_attrs, struct_info.field_types) |*ty, *attr, field_type| {
        ty.* = if (@typeInfo(field_type) != .optional) ?field_type else field_type;
        attr.* = .{ .default_value_ptr = &@as(ty.*, null) };
    }
    break :blk @Struct(.auto, null, std.meta.fieldNames(Settings), &field_types, &field_attrs);
};

/// A packed struct where every field name is copied from `Settings` but the field type is `bool`.
pub const DidConfigChange = @Struct(
    .@"packed",
    null,
    std.meta.fieldNames(Settings),
    &@splat(bool),
    &@splat(.{ .default_value_ptr = &false }),
);

// TODO

const LoadConfigResult = union(enum) {
    success: struct {
        config: Settings,
        config_arena: std.heap.ArenaAllocator.State,
        /// file path of the config.json
        path: []const u8,
    },
    failure: struct {
        /// `null` indicates that the error has already been logged
        error_bundle: ?std.zig.ErrorBundle,

        pub fn toMessage(self: @This(), allocator: std.mem.Allocator) error{OutOfMemory}!?[]u8 {
            const error_bundle = self.error_bundle orelse return null;
            var aw: std.Io.Writer.Allocating = .init(allocator);
            defer aw.deinit();
            error_bundle.renderToWriter(.{}, &aw.writer) catch |err| switch (err) {
                error.WriteFailed => return error.OutOfMemory,
            };
            return try aw.toOwnedSlice();
        }
    },
    not_found,

    pub fn deinit(self: *LoadConfigResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .success => |*config_with_path| {
                config_with_path.config_arena.promote(allocator).deinit();
                allocator.free(config_with_path.path);
            },
            .failure => |*payload| {
                if (payload.error_bundle) |*error_bundle| error_bundle.deinit(allocator);
            },
            .not_found => {},
        }
    }
};

fn loadConfigFromFile(io: std.Io, allocator: std.mem.Allocator, file_path: []const u8) error{ Canceled, OutOfMemory }!LoadConfigResult {
    const file_buf = std.Io.Dir.cwd().readFileAlloc(io, file_path, allocator, .limited(16 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return .not_found,
        error.Canceled, error.OutOfMemory => |e| return e,
        else => {
            log.warn("Error while reading configuration file: {}", .{err});
            return .{ .failure = .{ .error_bundle = null } };
        },
    };
    defer allocator.free(file_buf);

    const parse_options: std.json.ParseOptions = .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    };
    var parse_diagnostics: std.json.Diagnostics = .{};

    var scanner: std.json.Scanner = .initCompleteInput(allocator, file_buf);
    defer scanner.deinit();
    scanner.enableDiagnostics(&parse_diagnostics);

    var arena_allocator: std.heap.ArenaAllocator = .init(allocator);
    errdefer arena_allocator.deinit();

    @setEvalBranchQuota(10000);
    const config = std.json.parseFromTokenSourceLeaky(
        Settings,
        arena_allocator.allocator(),
        &scanner,
        parse_options,
    ) catch |err| {
        var eb: std.zig.ErrorBundle.Wip = undefined;
        try eb.init(allocator);
        errdefer eb.deinit();

        const src_path = try eb.addString(file_path);
        const msg = try eb.addString(@errorName(err));

        const src_loc = try eb.addSourceLocation(.{
            .src_path = src_path,
            .line = @intCast(parse_diagnostics.getLine()),
            .column = @intCast(parse_diagnostics.getColumn()),
            .span_start = @intCast(parse_diagnostics.getByteOffset()),
            .span_main = @intCast(parse_diagnostics.getByteOffset()),
            .span_end = @intCast(parse_diagnostics.getByteOffset()),
        });
        try eb.addRootErrorMessage(.{
            .msg = msg,
            .src_loc = src_loc,
        });

        return .{ .failure = .{ .error_bundle = try eb.toOwnedBundle("") } };
    };

    return .{ .success = .{
        .config = config,
        .config_arena = arena_allocator.state,
        .path = try allocator.dupe(u8, file_path),
    } };
}

pub fn loadConfigFromSystem(io: std.Io, allocator: std.mem.Allocator, environ_map: *const std.process.Environ.Map) error{ Canceled, OutOfMemory }!LoadConfigResult {
    if (builtin.target.os.tag == .wasi) return .not_found;

    for (
        [_]known_folders.KnownFolder{ .local_configuration, .global_configuration },
    ) |folder| {
        const folder_path = try known_folders.getPath(io, allocator, environ_map, folder) orelse continue;
        defer allocator.free(folder_path);

        for ([_][]const u8{
            "zls",
            "",
        }) |sub| {
            const config_path = try std.fs.path.join(allocator, &.{ folder_path, sub, "zls.json" });
            defer allocator.free(config_path);

            const result = try loadConfigFromFile(io, allocator, config_path);
            switch (result) {
                .success, .failure => return result,
                .not_found => continue,
            }
        }
    }

    return .not_found;
}
const Server = @import("Server.zig");
const DocumentStore = @import("DocumentStore.zig");
const build_options = @import("build_options");
const build_runner_shared = @import("build_runner/shared.zig");
const BuildOnSaveSupport = build_runner_shared.BuildOnSaveSupport;

pub fn loadConfiguration(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ_map: *const std.process.Environ.Map,
    server: *Server,
    maybe_config_path: ?[]const u8,
) error{ Canceled, OutOfMemory }!void {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    var config_arena: std.heap.ArenaAllocator = .init(allocator);
    defer config_arena.deinit();
    var config: Settings = .{};

    blk: {
        var config_result = if (maybe_config_path) |config_path|
            try loadConfigFromFile(io, allocator, config_path)
        else
            try loadConfigFromSystem(io, allocator, environ_map);
        defer config_result.deinit(allocator);

        switch (config_result) {
            .success => |*config_with_path| {
                log.info("$ Loaded {q}.", .{config_with_path.path});
                config = config_with_path.config;
                config_arena.state = config_with_path.config_arena;
                config_with_path.config_arena = .{};
            },
            .failure => |payload| {
                const message = try payload.toMessage(allocator) orelse break :blk;
                defer allocator.free(message);
                server.showMessage(.Error, "Failed to load configuration options:\n{s}", .{message});
            },
            .not_found => {},
        }
    }

    if (config.global_cache_path == null) blk: {
        if (builtin.target.os.tag == .wasi) {
            // will default to `/cache`
            break :blk;
        }

        const cache_dir_path = try known_folders.getPath(io, allocator, environ_map, .cache) orelse {
            server.showMessage(.Error, "Failed to resolve global cache directory", .{});
            break :blk;
        };
        defer allocator.free(cache_dir_path);

        config.global_cache_path = try std.fs.path.join(config_arena.allocator(), &.{ cache_dir_path, "zig" });
    }

    try server.config_manager.setConfiguration2(.frontend, &config);
}

pub fn resolveConfiguration(server: *Server) error{ Canceled, OutOfMemory }!void {
    var result = try server.config_manager.resolveConfiguration(server.allocator);
    defer result.deinit(server.allocator);

    for (result.messages) |msg| {
        server.showMessage(.Error, "{s}", .{msg});
    }

    inline for (comptime std.meta.fieldNames(Settings)) |field_name| {
        if (@field(result.did_change, field_name)) {
            const new_value = @field(server.config_manager.config, field_name);
            log.info("$ {s} -> [{f}]", .{ field_name, std.json.fmt(new_value, .{}) });
        }
    }

    const new_zig_exe_path: bool = result.did_change.zig_exe_path;
    const new_zig_lib_path: bool = result.did_change.zig_lib_path;
    // const new_enable_build_on_save: bool = result.did_change.enable_build_on_save;
    // const new_build_on_save_args: bool = result.did_change.build_on_save_args;
    const new_force_autofix: bool = result.did_change.force_autofix;
    const disable_compilations_did_change: bool = result.did_change.disable_compilations;

    server.document_store.config = Server.createDocumentStoreConfig(server.config_manager);

    // if (BuildOnSaveSupport.isSupportedComptime() and
    //     // If the client supports the `workspace/configuration` request, defer
    //     // build on save initialization until after we have received workspace
    //     // configuration from the server
    //     (!server.client_capabilities.supports_configuration or server.status == .initialized))
    // {
    //     const should_restart =
    //         new_zig_exe_path or
    //         new_zig_lib_path or
    //         new_build_runner_path or
    //         new_enable_build_on_save or
    //         new_build_on_save_args;

    //     for (server.workspaces.items) |*workspace| {
    //         try workspace.refreshBuildOnSave(.{
    //             .server = server,
    //             .restart = should_restart,
    //         });
    //     }
    // }

    if (server.status == .initialized and DocumentStore.supports_build_system) {
        if (new_zig_exe_path or new_zig_lib_path) {
            for (server.document_store.build_files.keys()) |build_file_uri| {
                server.document_store.invalidateBuildFile(build_file_uri);
            }
            // for (server.workspaces.items) |*wrkspc| {
            //     wrkspc.configuration.reload(server, wrkspc) catch |err| {
            //         std.log.err("Failed to reload configuration for workspace {q} : {t}", .{ wrkspc.uri, err });
            //     };
            // }
        }
        if (disable_compilations_did_change) {
            for (server.workspaces.items) |*wrkspc| {
                const bld_doc_uri = wrkspc.build_file_uri orelse continue;
                const bld_doc = server.document_store.getBuildFile(bld_doc_uri) orelse continue;
                try bld_doc.triggerRedoCompilation(&server.document_store);
            }
        }
    }

    if (server.status == .initialized and
        (new_zig_exe_path or new_zig_lib_path) and
        server.client_capabilities.supports_publish_diagnostics)
    {
        for (server.document_store.handles.values()) |handle| {
            if (!handle.isLspSynced()) continue;
            server.generateDiagnostics(handle);
        }
    }

    // <---------------------------------------------------------->
    //  don't modify config options after here, only show messages
    // <---------------------------------------------------------->

    check: {
        if (!std.process.can_spawn) break :check;
        if (server.status != .initialized) break :check;

        // TODO there should a way to suppress this message
        if (server.config_manager.zig_exe == null) {
            server.showMessage(.Warning, "zig executable could not be found", .{});
        } else if (server.config_manager.zig_lib_dir == null) {
            server.showMessage(.Warning, "zig standard library directory could not be resolved", .{});
        }
    }

    check: {
        if (server.status != .initialized) break :check;

        switch (server.config_manager.bss_check) {
            .pending, .success => break :check,
            .partial => {
                server.showMessage(
                    .Warning,
                    "Zigscient: Build System: Could not determine path to self; Only minimal Build System support available.",
                    .{},
                );
            },
            .failure => {
                const zig_version = server.config_manager.zig_exe.?.version;

                server.showMessage(
                    .Warning,
                    "Zigscient: Build System: Unsupported Zig version: `{f}` . Minimum supported Zig version {q} .",
                    .{ zig_version, build_options.minimum_runtime_zig_version_string },
                );
            },
        }
    }

    if (server.config_manager.config.enable_build_on_save orelse false) {
        if (!BuildOnSaveSupport.isSupportedComptime()) {
            // This message is not very helpful but it relatively uncommon to happen anyway.
            log.info("'enable_build_on_save' is ignored because build-on-save is not supported by this build of the server.", .{});
        } else if (server.status == .initialized and (server.config_manager.config.zig_exe_path == null or server.config_manager.zig_lib_dir == null)) {
            log.warn("'enable_build_on_save' is ignored because Zig could not be found", .{});
        } else if (server.status == .initialized and !server.client_capabilities.supports_publish_diagnostics) {
            log.warn("'enable_build_on_save' is ignored because it is not supported by {s}", .{server.client_capabilities.client_name orelse "your editor"});
        } else if (server.status == .initialized and server.config_manager.bss_check != .success) {
            log.warn("'enable_build_on_save' is ignored because the Build System check failed", .{});
        } else if (server.status == .initialized and server.config_manager.zig_exe != null) {
            switch (BuildOnSaveSupport.isSupportedRuntime(server.config_manager.zig_exe.?.version)) {
                .supported => {},
                .invalid_linux_kernel_version => |*utsname_release| log.warn("Build-On-Save cannot run in watch mode because the Linux version '{s}' could not be parsed", .{std.mem.sliceTo(utsname_release, 0)}),
                .unsupported_linux_kernel_version => |kernel_version| log.warn("Build-On-Save cannot run in watch mode because it is not supported by Linux '{f}' (requires at least {f})", .{ kernel_version, BuildOnSaveSupport.minimum_linux_version }),
                .unsupported_zig_version => log.warn("Build-On-Save cannot run in watch mode because it is not supported on {t} by Zig {f} (requires at least {f})", .{ builtin.os.tag, server.resolved_config.zig_runtime_version.?, BuildOnSaveSupport.minimum_zig_version }),
                .unsupported_os => log.warn("Build-On-Save cannot run in watch mode because it is not supported on {t}", .{builtin.os.tag}),
            }
        }
    }

    if (new_force_autofix) {
        switch (server.autofixWorkaround()) {
            .none => {},
            .unavailable => {
                log.warn("`force_autofix` is ignored because it is not supported by {s}", .{server.client_capabilities.client_name orelse "your editor"});
            },
            .on_save, .will_save_wait_until => |workaround| {
                log.info("Autofix workaround enabled: '{t}'", .{workaround});
            },
        }
    }
}

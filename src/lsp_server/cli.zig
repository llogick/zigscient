const builtin = @import("builtin");
const ls_kit = @import("lsp-server");
const known_folders = @import("known-folders");

const std = @import("std");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.ls_cli);

const usage =
    \\Zigscient - A Zig Language Server
    \\
    \\Commands:
    \\  help, --help,             Print this help and exit
    \\  version, --version        Print version and exit
    \\  env
    \\
    \\General Options:
    \\  --config-path [path]      Set path to the 'zls.json' settings file
    \\  --log-level [enum]        The Log Level to be used.
    \\                              Supported Values:
    \\                                err
    \\                                warn
    \\                                info (default)
    \\                                debug
    \\
    \\Advanced Options:
    \\  --enable-stderr-logs      Write log message to stderr
    \\  --disable-lsp-logs        Disable LSP 'window/logMessage' messages
    \\
;

pub const Options = struct {
    argv0: []const u8 = undefined,
    settings_file_path: ?[]const u8 = null,
    enable_logging_to_stderr: bool = false,
    disable_logging_to_jsonio: bool = false,
    log_level: ?std.log.Level = null,

    pub fn deinit(self: Options, allocator: std.mem.Allocator) void {
        allocator.free(self.argv0);
        if (self.settings_file_path) |path| allocator.free(path);
    }

    const ErrSet = std.mem.Allocator.Error || std.Io.File.Writer.Error;

    pub fn parseArgs(
        io: std.Io,
        allocator: std.mem.Allocator,
        environ_map: *const std.process.Environ.Map,
        args: std.process.Args,
    ) ErrSet!Options {
        var options: Options = .{};
        errdefer options.deinit(allocator);

        var args_it = try args.iterateAllocator(allocator);
        defer args_it.deinit();

        const argv0 = args_it.next() orelse "";
        options.argv0 = try allocator.dupe(u8, argv0);

        var arg_index: u32 = 0;
        while (args_it.next()) |arg| : (arg_index += 1) {
            if (arg_index == 0) {
                if ((std.mem.eql(u8, arg, "help")) or
                    std.mem.eql(u8, arg, "-h") or
                    std.mem.eql(u8, arg, "--help"))
                {
                    try std.Io.File.stderr().writeStreamingAll(io, usage);
                    std.process.exit(0);
                } else if ((std.mem.eql(u8, arg, "version")) or std.mem.eql(u8, arg, "--version")) {
                    try std.Io.File.stdout().writeStreamingAll(io, ls_kit.build_options.version_string ++ "\n");
                    std.process.exit(0);
                } else if (std.mem.eql(u8, arg, "env")) {
                    try cmdEnv(io, allocator, environ_map, argv0);
                }
            }

            if (std.mem.eql(u8, arg, "--config-path")) {
                const path = args_it.next() orelse {
                    log.err("Expected configuration file path after --config-path argument.", .{});
                    std.process.exit(1);
                };
                if (options.settings_file_path) |prev_fp| allocator.free(prev_fp);
                options.settings_file_path = try allocator.dupe(u8, path);
            } else if (std.mem.eql(u8, arg, "--log-level")) {
                const log_level_name = args_it.next() orelse {
                    log.err("Expected argument after --log-level", .{});
                    std.process.exit(1);
                };
                options.log_level = std.meta.stringToEnum(std.log.Level, log_level_name) orelse {
                    log.err("Invalid --log-level argument. Expected one of {{'debug', 'info', 'warn', 'err'}} but got '{s}'", .{log_level_name});
                    std.process.exit(1);
                };
            } else if (std.mem.eql(u8, arg, "--enable-stderr-logs")) {
                options.enable_logging_to_stderr = true;
            } else if (std.mem.eql(u8, arg, "--disable-lsp-logs")) {
                options.disable_logging_to_jsonio = true;
            } else {
                log.err("Unrecognized argument: '{s}'", .{arg});
                std.process.exit(1);
            }
        }

        if (builtin.target.os.tag != .wasi and try std.Io.File.stdin().isTty(io)) {
            log.warn(
                \\
                \\A Zig language server that provides IDE-like features to editors.
                \\
                \\Should be used via an editor plugin rather than invoked directly.
                \\
            , .{});
            options.disable_logging_to_jsonio = true;
            options.enable_logging_to_stderr = true;
        }

        return options;
    }
};

/// Output format of the `env` subcmd
const Env = struct {
    argv0: []const u8,
    /// Project version. Guaranteed to be a [semantic version](https://semver.org/).
    ///
    /// The semantic version can have one of the following formats:
    /// - `MAJOR.MINOR.PATCH` is a tagged release
    /// - `MAJOR.MINOR.PATCH-dev.COMMIT_HEIGHT+SHORT_COMMIT_HASH` is a development build
    /// - `MAJOR.MINOR.PATCH-dev` is a development build where the exact version could not be resolved.
    ///
    version: []const u8,
    minimum_runtime_zig_version: []const u8,
    /// Path to a `zls.json` config file. Will be resolved by looking in the local configuration directory and then falling back to the global directory.
    /// Can be null if no `zls.json` was found in the global/local config directory.
    settings_file_path: ?[]const u8,
    /// Path to a global configuration directory relative to which configuration files will be searched.
    /// Not `null` unless [known-folders](https://github.com/ziglibs/known-folders) was unable to find a global configuration directory.
    global_config_dir: ?[]const u8,
    /// Path to a user specific configuration directory relative to which configuration files will be searched.
    /// Not `null` unless [known-folders](https://github.com/ziglibs/known-folders) was unable to find a local configuration directory.
    local_config_dir: ?[]const u8,
    global_cache_dir: ?[]const u8,
};

fn cmdEnv(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ_map: *const std.process.Environ.Map,
    argv0: []const u8,
) (std.mem.Allocator.Error || std.Io.File.Writer.Error)!noreturn {
    const global_cache_dir = known_folders.getPath(io, allocator, environ_map, .cache) catch |err| switch (err) {
        error.Canceled, error.OutOfMemory => |e| return e,
    };
    defer if (global_cache_dir) |path| allocator.free(path);

    const global_config_dir = known_folders.getPath(io, allocator, environ_map, .global_configuration) catch |err| switch (err) {
        error.Canceled, error.OutOfMemory => |e| return e,
    };
    defer if (global_config_dir) |path| allocator.free(path);

    const local_config_dir = known_folders.getPath(io, allocator, environ_map, .local_configuration) catch |err| switch (err) {
        error.Canceled, error.OutOfMemory => |e| return e,
    };
    defer if (local_config_dir) |path| allocator.free(path);

    var config_result = try ls_kit.settings_handler.loadConfigFromSystem(io, allocator, environ_map);
    defer config_result.deinit(allocator);

    const settings_file_path: ?[]const u8 = switch (config_result) {
        .success => |config_with_path| config_with_path.path,
        .failure => |payload| blk: {
            const message = try payload.toMessage(allocator) orelse break :blk null;
            defer allocator.free(message);
            log.err("Failed to load configuration options.", .{});
            log.err("{s}", .{message});
            break :blk null;
        },
        .not_found => null,
    };

    var buffer: [1024 * 4]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(io, &buffer);
    const writer = &file_writer.interface;

    const env: Env = .{
        .argv0 = argv0,
        .version = ls_kit.build_options.version_string,
        .minimum_runtime_zig_version = ls_kit.build_options.minimum_runtime_zig_version_string,
        .settings_file_path = settings_file_path,
        .global_config_dir = global_config_dir,
        .local_config_dir = local_config_dir,
        .global_cache_dir = global_cache_dir,
    };
    std.json.Stringify.value(env, .{ .whitespace = .indent_2 }, writer) catch return file_writer.err.?;
    writer.writeAll("\n") catch return file_writer.err.?;
    writer.flush() catch return file_writer.err.?;

    std.process.exit(0);
}

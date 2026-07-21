//! A thread-safe container for all document related state like zig source files including `build.zig`.

const std = @import("std");
const builtin = @import("builtin");
const lsp_server = @import("lsp-server");
const URI = @import("uri.zig");
const analysis = @import("analysis.zig");
const offsets = @import("offsets.zig");
const log = std.log.scoped(.lspc_store);
const lsp = @import("lsp");
const Ast = std.zig.Ast;
const extd_zccs = @import("extended-zccs");
const BuildAssociatedConfig = @import("BuildOptions.zig");
const BuildConfig = @import("build_runner/shared.zig").BuildConfig;
const tracy = @import("tracy");
const DocumentScope = @import("DocumentScope.zig");
const DiagnosticsCollection = @import("DiagnosticsCollection.zig");
const Server = @import("Server.zig");
pub const Handle = @import("ZigDoc.zig");
pub const BldDoc = @import("BldDoc.zig");
/// window/workDoneProgress Notification Data
const ProgressNotification = struct {
    /// Prefix with "s2c-wdp-" (see Server.handleResponse). A suffix of "-{count}" will be added to it
    id: []const u8,
    title: []const u8,
};

const DocumentStore = @This();

io: std.Io,
allocator: std.mem.Allocator,
workspaces: *std.ArrayList(Server.Workspace),
/// the DocumentStore assumes that `config` is not modified while calling one of its functions.
config: Settings,
mutex: std.Io.Mutex = .init,
wait_group: if (supports_build_system) std.Io.Group else void = if (supports_build_system) .init else {},
tailor_run_group: if (supports_build_system) std.Io.Group else void = if (supports_build_system) .init else {},
handles: std.StringArrayHashMapUnmanaged(*Handle) = .empty,
build_files: if (supports_build_system) std.StringArrayHashMapUnmanaged(*BldDoc) else void = if (supports_build_system) .empty else {},
diagnostics_collection: *DiagnosticsCollection,
transport: ?*lsp.Transport = null,
lsp_capabilities: struct {
    supports_work_done_progress: bool = false,
    supports_semantic_tokens_refresh: bool = false,
    supports_inlay_hints_refresh: bool = false,
} = .{},
progress_notifications: [@typeInfo(ProgressNotificationIndex).@"enum".field_names.len]ProgressNotification = .{
    .{
        .id = "s2c-wdp-config",
        .title = "Retrieving Configuration",
    },
    .{
        .id = "s2c-wdp-tailor",
        .title = "Preparing Build",
    },
    .{
        .id = "s2c-wdp-compilations",
        .title = "Updating Compilation",
    },
},
// Keep in sync with the `progress_notifications` field
const ProgressNotificationIndex = enum {
    cfg_progress,
    tlr_progress,
    compilation_progress,
};

pub const Uri = []const u8;

pub const Hasher = std.crypto.auth.siphash.SipHash128(1, 3);
pub const Hash = [Hasher.mac_length]u8;

pub const supports_build_system = std.process.can_spawn;

pub fn computeHash(bytes: []const u8) Hash {
    var hasher: Hasher = .init(&@splat(0));
    hasher.update(bytes);
    var hash: Hash = undefined;
    hasher.final(&hash);
    return hash;
}

// TODO this shouldn't be a thing -- just take a pointer to the Server's cfg
pub const Settings = struct {
    self_file_path: ?[]const u8,
    zig_exe_path: ?[]const u8,
    zig_lib_dir: ?std.Build.Cache.Directory,
    builtin_path: ?[]const u8,
    bss_check: lsp_server.settings_handler.Manager.BssCheckState,
    environ_map: *std.process.Environ.Map,
    global_cache_dir: ?std.Build.Cache.Directory,
    wasi_preopens: switch (builtin.os.tag) {
        .wasi => std.process.Preopens,
        else => void,
    },
    disable_notifications: bool,
    disable_compilations: bool,
};

pub fn deinit(self: *DocumentStore) void {
    if (supports_build_system) {
        self.wait_group.cancel(self.io);
        self.tailor_run_group.cancel(self.io);
    }

    for (self.handles.keys(), self.handles.values()) |uri, handle| {
        handle.deinit();
        self.allocator.destroy(handle);
        self.allocator.free(uri);
    }
    self.handles.deinit(self.allocator);

    if (supports_build_system) {
        for (self.build_files.values()) |build_file| {
            build_file.deinit(self.allocator);
            self.allocator.destroy(build_file);
        }
        self.build_files.deinit(self.allocator);
    }

    self.* = undefined;
}

/// Returns a handle to the given document
/// **Thread safe** takes a shared lock
/// This function does not protect against data races from modifying the Handle
pub fn getHandle(self: *DocumentStore, uri: Uri) ?*Handle {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    return self.handles.get(uri);
}

fn readFile(self: *DocumentStore, uri: Uri) error{ Canceled, OutOfMemory }!?[:0]u8 {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const file_path = URI.toFsPath(self.allocator, uri) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    defer self.allocator.free(file_path);

    if (!std.fs.path.isAbsolute(file_path)) {
        log.err("file path is not absolute '{s}'", .{file_path});
        return null;
    }

    const dir, const sub_path = blk: {
        if (builtin.target.cpu.arch.isWasm() and !builtin.link_libc) {
            for (self.config.wasi_preopens.map.keys()[3..], 3..) |name, i| {
                const preopen_dir: std.Io.Dir = .{ .handle = @intCast(i) };
                const preopen_path = std.mem.trimEnd(u8, name, "/");

                if (!std.mem.startsWith(u8, file_path, preopen_path)) continue;
                if (!std.mem.startsWith(u8, file_path[preopen_path.len..], "/")) continue;

                break :blk .{ preopen_dir, std.mem.trimStart(u8, file_path[preopen_path.len..], "/") };
            }
        }
        break :blk .{ std.Io.Dir.cwd(), file_path };
    };

    return dir.readFileAllocOptions(
        self.io,
        sub_path,
        self.allocator,
        .limited(std.zig.max_src_size),
        .of(u8),
        0,
    ) catch |err| switch (err) {
        error.Canceled, error.OutOfMemory => |e| return e,
        else => {
            log.err("failed to read document '{s}': {}", .{ file_path, err });
            return null;
        },
    };
}

/// Returns a handle to the given document
/// Will load the document from disk if it hasn't been already
/// **Thread safe** takes an exclusive lock
/// This function does not protect against data races from modifying the Handle
pub fn getOrLoadHandle(self: *DocumentStore, uri: Uri) error{ Canceled, OutOfMemory }!?*Handle {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    if (self.getHandle(uri)) |handle| return handle;
    const file_contents = try self.readFile(uri) orelse return null;
    return try self.createAndStoreDocument(uri, file_contents, false);
}

/// **Thread safe** takes a shared lock
/// This function does not protect against data races from modifying the BldDoc
pub fn getBuildFile(self: *DocumentStore, uri: Uri) ?*BldDoc {
    comptime std.debug.assert(supports_build_system);
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    return self.build_files.get(uri);
}

/// invalidates any pointers into `DocumentStore.build_files`
/// **Thread safe** takes an exclusive lock
/// This function does not protect against data races from modifying the BldDoc
fn getOrLoadBuildFile(self: *DocumentStore, uri: Uri) error{ Canceled, OutOfMemory }!*BldDoc {
    comptime std.debug.assert(supports_build_system);

    if (self.getBuildFile(uri)) |build_file| return build_file;

    const new_build_file: *BldDoc = blk: {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);

        const gop = try self.build_files.getOrPut(self.allocator, uri);
        if (gop.found_existing) return gop.value_ptr.*;
        errdefer self.build_files.swapRemoveAt(gop.index);

        gop.value_ptr.* = try self.allocator.create(BldDoc);
        errdefer self.allocator.destroy(gop.value_ptr.*);

        gop.value_ptr.*.* = try self.createBuildFile(uri);
        gop.key_ptr.* = gop.value_ptr.*.flat_uri;
        break :blk gop.value_ptr.*;
    };

    // this code path is only reached when the build file is new

    self.invalidateBuildFile(new_build_file.flat_uri);

    return new_build_file;
}

/// Opens a document that is synced over the LSP protocol (`textDocument/didOpen`).
/// **Not thread safe**
pub fn openLspSyncedDocument(self: *DocumentStore, uri: Uri, text: []const u8) error{ Canceled, OutOfMemory }!void {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    if (self.handles.get(uri)) |handle| {
        if (handle.isLspSynced()) {
            log.warn("Document already open: {s}", .{uri});
        }
    }

    const duped_text = try self.allocator.dupeSentinel(u8, text, 0);
    _ = try self.createAndStoreDocument(uri, duped_text, true);
}

/// Closes a document that has been synced over the LSP protocol (`textDocument/didClose`).
/// **Not thread safe**
pub fn closeLspSyncedDocument(self: *DocumentStore, uri: Uri) void {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const kv = self.handles.fetchSwapRemove(uri) orelse {
        log.warn("Document not found: {s}", .{uri});
        return;
    };
    if (!kv.value.isLspSynced()) {
        log.warn("Document already closed: {s}", .{uri});
    }

    self.allocator.free(kv.key);
    kv.value.deinit();
    self.allocator.destroy(kv.value);
}

/// Updates a document that is synced over the LSP protocol (`textDocument/didChange`).
/// Takes ownership of `new_text` which has to be allocated with this DocumentStore's allocator.
/// **Not thread safe**
pub fn refreshLspSyncedDocument(self: *DocumentStore, uri: Uri, new_text: [:0]const u8) error{ Canceled, OutOfMemory }!void {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    if (self.handles.get(uri)) |old_handle| {
        if (!old_handle.isLspSynced()) {
            log.warn("Document modified without being opened: {s}", .{uri});
        }
    } else {
        log.warn("Document modified without being opened: {s}", .{uri});
    }

    _ = try self.createAndStoreDocument(uri, new_text, true);
}

/// Refreshes a document from the file system, unless said document is synced over the LSP protocol.
/// **Not thread safe**
pub fn refreshDocumentFromFileSystem(self: *DocumentStore, uri: Uri, should_delete: bool) error{ Canceled, OutOfMemory }!bool {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    if (should_delete) {
        const index = self.handles.getIndex(uri) orelse return false;
        const handle = self.handles.values()[index];
        if (handle.isLspSynced()) return false;

        self.handles.swapRemoveAt(index);
        const handle_uri = handle.uri;
        handle.deinit();
        self.allocator.destroy(handle);
        self.allocator.free(handle_uri);
    } else {
        if (self.handles.get(uri)) |handle| {
            if (handle.isLspSynced()) return false;
        } else return false;
        const file_contents = try self.readFile(uri) orelse return false;
        _ = try self.createAndStoreDocument(uri, file_contents, false);
    }

    return true;
}

/// Invalidates a build files.
/// **Thread safe** takes a shared lock
pub fn invalidateBuildFile(self: *DocumentStore, build_file_uri: Uri) void {
    comptime std.debug.assert(supports_build_system);

    if (self.config.bss_check != .success) return;
    if (self.config.zig_exe_path == null) return;
    if (self.config.global_cache_dir == null) return;
    if (self.config.zig_lib_dir == null) return;

    const build_file = self.getBuildFile(build_file_uri) orelse return;

    self.wait_group.async(self.io, invalidateBuildFileWorker, .{ self, build_file });
}

pub fn sendMessageToClient(
    io: std.Io,
    allocator: std.mem.Allocator,
    transport: *lsp.Transport,
    message: anytype,
) !void {
    const json_message = try std.json.Stringify.valueAlloc(
        allocator,
        message,
        .{ .emit_null_optional_fields = false },
    );
    defer allocator.free(json_message);

    try transport.writeJsonMessageUncancelable(io, json_message);
}

pub fn notifyProgressStart(
    self: *DocumentStore,
    progress_notification_id: ProgressNotificationIndex,
    message: []const u8,
) ?lsp.types.ProgressToken {
    if (!self.lsp_capabilities.supports_work_done_progress) return null;
    if (self.config.disable_notifications) return null;

    const transport = self.transport orelse return null;
    const pn = self.progress_notifications[@backingInt(progress_notification_id)];

    const global = struct {
        var work_done_progress_token_count: std.atomic.Value(i32) = .init(0);
    };
    const token_id = global.work_done_progress_token_count.fetchAdd(1, .acq_rel);

    // freed in notifyProgressEnd
    const token_string = std.fmt.allocPrint(self.allocator, "{s}-{d}", .{ pn.id, token_id }) catch return null;
    const token: lsp.types.ProgressToken = .{ .string = token_string };

    sendMessageToClient(self.io, self.allocator, transport, .{
        .jsonrpc = "2.0",
        .id = token_string,
        .method = "window/workDoneProgress/create",
        .params = lsp.types.window.work_done_progress.CreateParams{
            .token = token,
        },
    }) catch |err| switch (err) {
        error.Canceled => comptime unreachable,
        else => |e| {
            log.err("WorkDoneProgress: Failed to send a CreateParams message: {}", .{e});
            return null;
        },
    };

    sendMessageToClient(self.io, self.allocator, transport, .{
        .jsonrpc = "2.0",
        .method = "$/progress",
        .params = .{
            .token = token,
            .value = lsp.types.window.work_done_progress.Begin{
                .title = pn.title,
                .message = message,
            },
        },
    }) catch |err| switch (err) {
        error.Canceled => comptime unreachable,
        else => |e| {
            log.err("WorkDoneProgress: Failed to send a Begin message: {}", .{e});
            return null;
        },
    };
    return token;
}

const EndStatus = enum { success, failure };

pub fn notifyProgressEnd(
    self: *DocumentStore,
    token: lsp.types.ProgressToken,
    status: EndStatus,
) void {
    if (!self.lsp_capabilities.supports_work_done_progress) return;
    if (self.config.disable_notifications) return;

    const transport = self.transport orelse return;

    const message = switch (status) {
        .failure => "Failure",
        .success => "Success",
    };

    defer self.allocator.free(token.string);
    sendMessageToClient(self.io, self.allocator, transport, .{
        .jsonrpc = "2.0",
        .method = "$/progress",
        .params = .{
            .token = token,
            .value = lsp.types.window.work_done_progress.End{
                .message = message,
            },
        },
    }) catch |err| switch (err) {
        error.Canceled => comptime unreachable,
        else => |e| {
            log.err("WorkDoneProgress: Failed to send an End message: {}", .{e});
            return;
        },
    };
}

fn invalidateBuildFileWorker(self: *DocumentStore, build_file: *BldDoc) std.Io.Cancelable!void {
    {
        try build_file.configuration.mutex.lock(self.io);
        defer build_file.configuration.mutex.unlock(self.io);

        switch (build_file.configuration.loader_state) {
            .ready => build_file.configuration.loader_state = .running,
            .running => {
                build_file.configuration.loader_state = .running_but_result_already_outdated;
                return;
            },
            .running_but_result_already_outdated => return,
        }
    }

    var token = self.notifyProgressStart(.cfg_progress, build_file.flat_uri);
    errdefer if (token) |t| self.notifyProgressEnd(t, .failure);

    while (true) {
        build_file.configuration.version += 1;
        const new_version = build_file.configuration.version;

        const roots = loadBuildConfiguration(self, build_file, new_version) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            error.NewConfigurationSameAsOldConfiguration => {
                build_file.configuration.mutex.lockUncancelable(self.io);
                defer build_file.configuration.mutex.unlock(self.io);
                build_file.configuration.loader_state = .ready;
                if (token) |t| self.notifyProgressEnd(t, .success);
                token = null;
                return;
            },
            else => |e| {
                if (e != error.RunFailed) { // already logged
                    log.err("Failed to load build configuration for {q} : {t}", .{ build_file.flat_uri, e });
                }
                if (token) |t| self.notifyProgressEnd(t, .failure);
                build_file.configuration.mutex.lockUncancelable(self.io);
                defer build_file.configuration.mutex.unlock(self.io);
                build_file.configuration.loader_state = .ready;
                return;
            },
        };

        build_file.configuration.mutex.lockUncancelable(self.io);
        switch (build_file.configuration.loader_state) {
            .ready => unreachable,
            .running => {
                var old_roots = build_file.configuration.roots;
                build_file.configuration.roots = roots;
                build_file.configuration.loader_state = .ready;
                build_file.configuration.mutex.unlock(self.io);

                old_roots.deinit(self.allocator);
                if (token) |t| self.notifyProgressEnd(t, .success);
                token = null;
                break;
            },
            .running_but_result_already_outdated => {
                var old_roots = build_file.configuration.roots;
                build_file.configuration.roots = roots;
                build_file.configuration.loader_state = .running;
                build_file.configuration.mutex.unlock(self.io);

                old_roots.deinit(self.allocator);
                continue;
            },
        }
    }

    const old_cancel_protect = self.io.swapCancelProtection(.blocked);
    defer _ = self.io.swapCancelProtection(old_cancel_protect);

    blk: {
        const bf_handle = (self.getOrLoadHandle(build_file.flat_uri) catch break :blk) orelse {
            log.err("Failed to getHandle for: '{s}'", .{build_file.flat_uri});
            break :blk;
        };
        bf_handle.handleRootIdComment(self, true) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            error.OutOfMemory => @panic("OOM"),
        };
    }

    if (self.transport) |transport| {
        if (self.lsp_capabilities.supports_semantic_tokens_refresh) {
            sendMessageToClient(
                self.io,
                self.allocator,
                transport,
                lsp.TypedJsonRPCRequest(?void){
                    .id = .{ .string = "semantic_tokens_refresh" },
                    .method = "workspace/semanticTokens/refresh",
                    .params = @as(?void, null),
                },
            ) catch |err| switch (err) {
                error.Canceled => comptime unreachable,
                else => {},
            };
        }
        if (self.lsp_capabilities.supports_inlay_hints_refresh) {
            sendMessageToClient(
                self.io,
                self.allocator,
                transport,
                lsp.TypedJsonRPCRequest(?void){
                    .id = .{ .string = "inlay_hints_refresh" },
                    .method = "workspace/inlayHint/refresh",
                    .params = @as(?void, null),
                },
            ) catch |err| switch (err) {
                error.Canceled => comptime unreachable,
                else => {},
            };
        }
    }
}

pub fn isBuildFile(uri: Uri) bool {
    return std.mem.endsWith(u8, uri, "/build.zig");
}

pub fn isBuildZonFile(uri: Uri) bool {
    return std.mem.endsWith(u8, uri, "/build.zig.zon");
}

pub fn isBuiltinFile(uri: Uri) bool {
    return std.mem.endsWith(u8, uri, "/builtin.zig");
}

pub fn isInStd(uri: Uri) bool {
    // TODO: Better logic for detecting std or subdirectories?
    return std.mem.indexOf(u8, uri, "/std/") != null;
}

/// looks for a `zls.build.json` file in the build file directory
/// has to be freed with `json_compat.parseFree`
fn loadBuildAssociatedConfiguration(io: std.Io, allocator: std.mem.Allocator, build_file: BldDoc) !std.json.Parsed(BuildAssociatedConfig) {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const build_file_path = try URI.toFsPath(allocator, build_file.flat_uri);
    defer allocator.free(build_file_path);
    const config_file_path = try std.fs.path.resolve(allocator, &.{ build_file_path, "..", "zls.build.json" });
    defer allocator.free(config_file_path);

    const file_buf = try std.Io.Dir.cwd().readFileAlloc(
        io,
        config_file_path,
        allocator,
        .limited(16 * 1024 * 1024),
    );
    defer allocator.free(file_buf);

    return try std.json.parseFromSlice(
        BuildAssociatedConfig,
        allocator,
        file_buf,
        .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
    );
}

fn appendBuildOptions(
    self: *DocumentStore,
    arena: std.mem.Allocator,
    build_file_uri: []const u8,
    args: *std.ArrayList([]const u8),
) error{OutOfMemory}!void {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    if (self.getBuildFile(build_file_uri)) |build_file| blk: {
        const build_config = build_file.options orelse break :blk;
        const build_options = build_config.value.build_options orelse break :blk;

        try args.ensureUnusedCapacity(arena, build_options.len);
        for (build_options) |option| {
            args.appendAssumeCapacity(try option.formatParam(arena));
        }
    }
}

/// Runs the build.zig and extracts include directories and packages
fn loadBuildConfiguration(
    self: *DocumentStore,
    build_file: *BldDoc,
    build_file_version: u32,
) !BldDoc.Roots {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    std.debug.assert(self.config.bss_check == .success);
    std.debug.assert(self.config.zig_exe_path != null);
    std.debug.assert(self.config.global_cache_dir != null and self.config.global_cache_dir.?.path != null);
    std.debug.assert(self.config.zig_lib_dir != null and self.config.zig_lib_dir.?.path != null);

    const io = self.io;

    var arena_state = std.heap.ArenaAllocator.init(self.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const build_file_path = try URI.toFsPath(arena, build_file.flat_uri);
    const cwd = std.fs.path.dirname(build_file_path).?;
    var args: std.ArrayList([]const u8) = .empty;

    try args.appendSlice(arena, &.{
        self.config.self_file_path.?,
        "maker",
        "build",
        try arena.print("--zig-lib={s}", .{self.config.zig_lib_dir.?.path.?}),
        try arena.print("--zig={s}", .{self.config.zig_exe_path.?}),
        try arena.print("--global-cache={s}", .{self.config.global_cache_dir.?.path.?}),
        try arena.print("--seed=0x{x}", .{@import("compiler").randInt(io, u32)}),
        "--print-configuration-path",
    });

    try self.appendBuildOptions(arena, build_file.flat_uri, &args);

    const get_cfg_path_run_result = blk: {
        const tracy_zone2 = tracy.trace(@src());
        defer tracy_zone2.end();
        break :blk try std.process.run(
            arena,
            io,
            .{
                .argv = args.items,
                .cwd = .{ .path = cwd },
                .reserve_amount = 1024 * 4,
            },
        );
    };

    const is_ok = switch (get_cfg_path_run_result.term) {
        .exited => |exit_code| exit_code == 0,
        else => false,
    };

    const diagnostic_tag: DiagnosticsCollection.Tag = tag: {
        var hasher: std.hash.Wyhash = .init(47); // Chosen by the following prompt: Pwease give a wandom nyumbew
        hasher.update(build_file.flat_uri);
        break :tag @fromBackingInt(@intCast(@as(u32, @truncate(hasher.final()))));
    };

    if (!is_ok) {
        const joined = try std.mem.join(arena, " ", args.items);

        log.err(
            "Failed to get configuration path for {q}\nDIR: {s}\nCMD: {s}\nERR:\n{s}",
            .{ build_file.flat_uri, cwd, joined, get_cfg_path_run_result.stderr },
        );

        const error_bundle = try @import("features/diagnostics.zig").getErrorBundleFromStderr(
            arena,
            get_cfg_path_run_result.stderr,
            false,
            .{ .dynamic = .{ .document_store = self, .base_path = cwd } },
        );

        try self.diagnostics_collection.pushErrorBundle(diagnostic_tag, build_file_version, cwd, error_bundle);
        try self.diagnostics_collection.publishDiagnostics();
        return error.RunFailed;
    } else {
        try self.diagnostics_collection.pushErrorBundle(diagnostic_tag, build_file_version, null, .empty);
        try self.diagnostics_collection.publishDiagnostics();
    }

    const path = try std.fs.path.resolve(self.allocator, &.{ cwd, std.mem.trimEnd(u8, get_cfg_path_run_result.stdout, " \r\n") });
    log.debug("cfg file: {q}, prev: {?q}", .{ path, build_file.configuration.cfg_file_path });
    if (build_file.configuration.cfg_file_path) |cfg_path| {
        if (std.mem.eql(u8, path, cfg_path)) {
            self.allocator.free(path);
            return error.NewConfigurationSameAsOldConfiguration;
        }
        self.allocator.free(cfg_path);
    }
    build_file.configuration.cfg_file_path = path;

    const roots_info_file_path = try std.fs.path.resolve(self.allocator, &.{
        cwd,
        ".zig-cache",
        try std.fmt.allocPrint(arena, "{s}.txt", .{std.fs.path.basename(path)}),
    });
    errdefer self.allocator.free(roots_info_file_path);
    // TODO if file exists no need to redo

    const serialized = c: {
        var file = std.Io.Dir.openFile(.cwd(), io, path, .{}) catch |err| {
            log.err("Failed to open configuration file {q} : {t}", .{ path, err });
            return err;
        };
        defer file.close(self.io);
        break :c std.Build.Configuration.loadFile(arena, io, file) catch |err| {
            log.err("Failed to load configuration file {q}: {t}", .{ path, err });
            return err;
        };
    };

    var roots: BldDoc.Roots = .init;
    errdefer roots.deinit(self.allocator);
    var roots_info: std.ArrayList(u8) = .empty;
    try roots_info.appendSlice(arena, "Basic Project Configuration Overview\n    Available root IDs are listed under their corresponding Compile Step, eg `ID [N]`.\n");

    var stack: std.array_list.Managed(StackItem) = .init(arena);
    const c = &serialized;
    // var top_level_steps: std.StringArrayHashMapUnmanaged(Configuration.Step.Index) = .empty;
    for (c.steps, 0..) |*conf_step, step_index_usize| {
        if (conf_step.owner != .root) continue;
        if (conf_step.flags(c).tag != .top_level) continue;

        try stack.append(.{ .step = @fromBackingInt(@intCast(step_index_usize)), .dep_index = 0, .depth = 0 });

        // Process the graph using the stack
        while (stack.items.len > 0) {
            var current = &stack.items[stack.items.len - 1];
            const step = current.step.ptr(c);
            const deps = step.deps.slice(c);

            // First time seeing this step at this depth
            if (current.dep_index == 0) {
                const name = step.name.slice(c);
                const step_flags = step.flags(c);

                const indent = max_spaces[0..@min(current.depth * 4, max_spaces.len)];
                const sub_indent = max_spaces[0..@min((current.depth + 1) * 4, max_spaces.len)];

                switch (step_flags.tag) {
                    .top_level => {
                        try roots_info.print(arena, "{s}{s}{q} - {q} ({t})\n", .{
                            if (current.depth == 0) "\n" else "",
                            indent,
                            name,
                            step.extended.get(c.extra).top_level.description.slice(c),
                            step_flags.tag,
                        });
                    },
                    .compile => {
                        const compile = step.extended.get(c.extra).compile;
                        const rm = compile.root_module.get(c);
                        var rsf_path: [:0]const u8 = "";
                        if (rm.root_source_file.unwrap()) |rsf| {
                            rsf_path = switch (rsf.get(c)) {
                                .source_path => |sp| sp.sub_path.slice(c),
                                else => "%pending%",
                            };
                        }
                        try roots_info.print(arena, "{s}{q} - {q} ({t} {t})\n", .{
                            indent,
                            compile.root_name.slice(c),
                            name,
                            step_flags.tag,
                            compile.flags3.kind,
                        });
                        const root_index = roots.map.count();
                        const gop = try roots.map.getOrPut(self.allocator, @backingInt(current.step));
                        try roots_info.print(arena, "{s}ID [{}]\n", .{ sub_indent, if (gop.found_existing) gop.index else root_index });
                        var mods: std.ArrayList(BldDoc.CompileStep.NamePathPair) = .empty;
                        if (!gop.found_existing)
                            try mods.append(self.allocator, .{
                                .name = try self.allocator.dupe(u8, "root"),
                                .path = try std.fs.path.resolve(self.allocator, &.{ cwd, rsf_path }),
                            });
                        try roots_info.print(arena, "{s}-> root={q}\n", .{ sub_indent, rsf_path });
                        const imports = rm.import_table.get(c).imports;
                        for (imports.mal.items(.name), imports.mal.items(.module)) |import_name, other_mod_idx| {
                            const other_mod: std.Build.Configuration.Module = other_mod_idx.get(c);
                            if (other_mod.root_source_file.unwrap()) |rsf| {
                                rsf_path = switch (rsf.get(c)) {
                                    .source_path => |sp| if (other_mod.owner == .root) sp.sub_path.slice(c) else "%pending%",
                                    else => "%pending%",
                                };
                            } else rsf_path = "";
                            const mod_import_name = import_name.slice(c);
                            if (!gop.found_existing)
                                try mods.append(self.allocator, .{
                                    .name = try self.allocator.dupe(u8, mod_import_name),
                                    .path = try std.fs.path.resolve(self.allocator, &.{ cwd, rsf_path }),
                                });
                            try roots_info.print(arena, "{s}-> {s}={q}\n", .{ sub_indent, mod_import_name, rsf_path });
                        }
                        if (!gop.found_existing) gop.value_ptr.* = .{
                            .name = try self.allocator.dupe(u8, compile.root_name.slice(c)),
                            .mods = mods,
                        };
                    },
                    else => try roots_info.print(arena, "{s}{q} ({t})\n", .{
                        indent,
                        name,
                        step_flags.tag,
                    }),
                }
            }

            // Find the next valid dependency to process
            var found_next_dep = false;
            if (!(current.depth != 0 and step.flags(c).tag == .top_level)) while (current.dep_index < deps.len) {
                const dep = deps[current.dep_index];
                current.dep_index += 1; // Advance for the next iteration

                const dep_step = dep.ptr(c);
                if (dep_step.owner != .root) continue;

                // Push the dependency to the stack to process it next
                try stack.append(.{
                    .step = dep,
                    .dep_index = 0,
                    .depth = current.depth + 1,
                });
                found_next_dep = true;
                break;
            };

            // If no more dependencies, pop this step off the stack
            if (!found_next_dep) {
                _ = stack.pop();
            }
        }
    }

    blk: {
        const file = std.Io.Dir.createFileAbsolute(io, roots_info_file_path, .{}) catch |err| {
            log.err("Failed to open {q} for writing: {t}", .{ roots_info_file_path, err });
            break :blk;
        };
        defer file.close(io);
        var fw = file.writer(io, &.{});
        fw.interface.writeAll(roots_info.items) catch {
            log.err("Failed to write roots info to {q}: {t}", .{ roots_info_file_path, fw.err.? });
            break :blk;
        };
        roots.info_file_path = roots_info_file_path;
    }
    return roots;
}

const StackItem = struct {
    step: std.Build.Configuration.Step.Index,
    dep_index: u32,
    depth: u32,
};
const max_spaces: [64]u8 = @splat(' ');

/// Checks if the build.zig file is accessible in dir.
pub fn buildDotZigExists(io: std.Io, dir_path: []const u8) std.Io.Cancelable!bool {
    var dir = std.Io.Dir.openDirAbsolute(io, dir_path, .{}) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        else => return false,
    };
    defer dir.close(io);
    dir.access(io, "build.zig", .{}) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        else => return false,
    };
    return true;
}

fn triggerGetOrLoadHandle(self: *DocumentStore, uri: Uri) std.Io.Cancelable!void {
    _ = self.getOrLoadHandle(uri) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        error.OutOfMemory => @panic("OOM"),
    };
}

fn triggerGetOrLoadBuildFile(self: *DocumentStore, uri: Uri) std.Io.Cancelable!void {
    _ = self.getOrLoadBuildFile(uri) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        error.OutOfMemory => @panic("OOM"),
    };
}

pub fn findBuildZig(io: std.Io, allocator: std.mem.Allocator, uri: []const u8) !?[]const u8 {
    const path = try URI.toFsPath(allocator, uri);
    defer allocator.free(path);

    var it = std.Io.Dir.path.componentIterator(path);
    _ = it.last();
    var did_check_root = false;
    while (true) {
        const dir_path = if (it.previous()) |comp| comp.path else blk: {
            if (did_check_root) break :blk null;
            did_check_root = true;
            break :blk it.root();
        } orelse break;
        if (!try buildDotZigExists(io, dir_path)) continue;

        const joined = try std.Io.Dir.path.join(allocator, &.{ dir_path, "build.zig" });
        defer allocator.free(joined);

        return try URI.fromPath(allocator, joined);
    }

    return null;
}

/// Walk down the tree towards the uri. When we hit `build.zig` files
/// add them to the list of potential build files.
/// `build.zig` files higher in the filesystem have precedence.
/// See `Handle.getAssociatedBuildFileUri`.
/// Caller owns returned memory.
pub fn collectPotentialBuildFiles(self: *DocumentStore, uri: Uri) error{ Canceled, OutOfMemory }![]*BldDoc {
    if (isInStd(uri)) return &.{};

    var potential_build_files: std.ArrayList(*BldDoc) = .empty;
    errdefer potential_build_files.deinit(self.allocator);

    const path = URI.toFsPath(self.allocator, uri) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return &.{},
    };
    defer self.allocator.free(path);

    var current_path: []const u8 = path;
    while (std.fs.path.dirname(current_path)) |potential_root_path| : (current_path = potential_root_path) {
        if (!try buildDotZigExists(self.io, potential_root_path)) continue;

        const build_path = try std.fs.path.join(self.allocator, &.{ potential_root_path, "build.zig" });
        defer self.allocator.free(build_path);

        try potential_build_files.ensureUnusedCapacity(self.allocator, 1);

        const build_file_uri = try URI.fromPath(self.allocator, build_path);
        defer self.allocator.free(build_file_uri);

        const build_file = try self.getOrLoadBuildFile(build_file_uri);
        potential_build_files.appendAssumeCapacity(build_file);
    }
    // The potential build files that come first should have higher priority.
    //
    // `build.zig` files that are higher up in the filesystem are more likely
    // to be the `build.zig` of the entire project/package instead of just a
    // sub-project/package.
    std.mem.reverse(*BldDoc, potential_build_files.items);

    return try potential_build_files.toOwnedSlice(self.allocator);
}

fn createBuildFile(self: *DocumentStore, uri: Uri) error{ Canceled, OutOfMemory }!BldDoc {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    var build_file: BldDoc = .{
        .flat_uri = try self.allocator.dupe(u8, uri),
        .build = .{ .arena_instance = .init(self.allocator) },
        .configuration = .{},
    };

    errdefer build_file.deinit(self.allocator);

    if (loadBuildAssociatedConfiguration(self.io, self.allocator, build_file)) |cfg| {
        build_file.options = cfg;

        if (cfg.value.roots_index) |roots_index| build_file.configuration.roots.index = roots_index;
        if (cfg.value.relative_builtin_path) |relative_builtin_path| blk: {
            const build_file_path = URI.toFsPath(self.allocator, build_file.flat_uri) catch break :blk;
            const absolute_builtin_path = try std.fs.path.resolve(self.allocator, &.{ build_file_path, "..", relative_builtin_path });
            defer self.allocator.free(absolute_builtin_path);
            build_file.builtin_uri = try URI.fromPath(self.allocator, absolute_builtin_path);
        }
    } else |err| switch (err) {
        error.Canceled => return error.Canceled,
        error.FileNotFound => {},
        else => {
            log.debug("Failed to load config associated with build file {s} (error: {})", .{ build_file.flat_uri, err });
        },
    }

    log.info("Loaded build file '{s}'", .{build_file.flat_uri});

    return build_file;
}

/// Returns whether the `Uri` is a dependency of the given `BldDoc`.
/// May return `null` to indicate an inconclusive result because
/// the required build config has not been resolved yet.
///
/// invalidates any pointers into `build_files`
/// **Thread safe** takes an exclusive lock
pub fn uriAssociatedWithBuild(
    self: *DocumentStore,
    build_file: *BldDoc,
    uri: Uri,
) error{ Canceled, OutOfMemory }!?bool {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    var checked_uris: std.StringHashMapUnmanaged(void) = .empty;
    defer checked_uris.deinit(self.allocator);

    var package_uris: std.ArrayList(Uri) = .empty;
    defer {
        for (package_uris.items) |package_uri| self.allocator.free(package_uri);
        package_uris.deinit(self.allocator);
    }
    const success = try build_file.collectBuildConfigPackageUris(self.io, self.allocator, &package_uris);
    if (!success) return null;

    for (package_uris.items) |package_uri| {
        if (try self.uriInImports(&checked_uris, build_file.flat_uri, package_uri, uri))
            return true;
    }

    return false;
}

/// invalidates any pointers into `DocumentStore.build_files`
/// **Thread safe** takes an exclusive lock
fn uriInImports(
    self: *DocumentStore,
    checked_uris: *std.StringHashMapUnmanaged(void),
    build_file_uri: Uri,
    source_uri: Uri,
    uri: Uri,
) error{ Canceled, OutOfMemory }!bool {
    if (std.mem.eql(u8, uri, source_uri)) return true;
    if (isInStd(source_uri)) return false;

    const gop = try checked_uris.getOrPut(self.allocator, source_uri);
    if (gop.found_existing) return false;

    const handle = try self.getOrLoadHandle(source_uri) orelse {
        errdefer std.debug.assert(checked_uris.remove(source_uri));
        gop.key_ptr.* = try self.allocator.dupe(u8, source_uri);
        return false;
    };
    gop.key_ptr.* = handle.uri;

    if (try handle.getAssociatedBuildFileUri(self)) |associated_build_file_uri| {
        return std.mem.eql(u8, associated_build_file_uri, build_file_uri);
    }

    for (try handle.getImportUris()) |import_uri| {
        if (try self.uriInImports(checked_uris, build_file_uri, import_uri, uri))
            return true;
    }

    return false;
}

/// takes ownership of the `text` passed in.
/// **Thread safe** takes an exclusive lock
fn createAndStoreDocument(
    self: *DocumentStore,
    uri: Uri,
    text: [:0]const u8,
    lsp_synced: bool,
) error{ Canceled, OutOfMemory }!*Handle {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const old_cancel_protect = self.io.swapCancelProtection(.blocked);
    defer _ = self.io.swapCancelProtection(old_cancel_protect);

    var new_handle = Handle.init(self, uri, text, lsp_synced) catch |err| {
        self.allocator.free(text);
        return err;
    };
    errdefer new_handle.deinit();

    new_handle.mtime = stat: {
        const now: std.Io.Timestamp = .now(self.io, .real);
        const file_path = URI.toFsPath(self.allocator, uri) catch break :stat now;
        defer self.allocator.free(file_path);
        if (!std.fs.path.isAbsolute(file_path)) {
            log.err("stat: path is not absolute '{s}'", .{file_path});
            break :stat now;
        }
        const file = std.Io.Dir.openFileAbsolute(self.io, file_path, .{}) catch break :stat now;
        defer file.close(self.io);
        const stat = file.stat(self.io) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            else => break :stat now,
        };
        break :stat stat.mtime;
    };

    try self.mutex.lock(self.io);
    defer self.mutex.unlock(self.io);

    const gop = try self.handles.getOrPut(self.allocator, uri);
    errdefer if (!gop.found_existing) std.debug.assert(self.handles.swapRemove(uri));

    if (gop.found_existing) {
        if (lsp_synced) {
            new_handle.impl.associated_build_file = gop.value_ptr.*.impl.associated_build_file;
            gop.value_ptr.*.impl.associated_build_file = .init;
            new_handle.computed_data = gop.value_ptr.*.computed_data;
            gop.value_ptr.*.computed_data = .{};
            new_handle.uri = gop.key_ptr.*;
            gop.value_ptr.*.deinit();
            gop.value_ptr.*.* = new_handle;
        } else {
            // TODO prevent concurrent `createAndStoreDocument` invocations from racing each other
            new_handle.deinit();
        }
    } else {
        gop.key_ptr.* = try self.allocator.dupe(u8, uri);
        errdefer self.allocator.free(gop.key_ptr.*);

        gop.value_ptr.* = try self.allocator.create(Handle);
        errdefer self.allocator.destroy(gop.value_ptr.*);

        if (!isBuildFile(uri) and !isBuiltinFile(uri) and !isInStd(uri)) {
            new_handle.closest_build_file_uri = findBuildZig(self.io, self.allocator, uri) catch null;
            if (new_handle.closest_build_file_uri) |bzfuri| self.wait_group.concurrent(self.io, triggerGetOrLoadHandle, .{ self, bzfuri }) catch {}; // This would trigger getOrLoadBuildFile too
        }

        new_handle.uri = gop.key_ptr.*;
        gop.value_ptr.*.* = new_handle;
    }

    if (supports_build_system and isBuildFile(uri) and !isInStd(uri)) {
        self.wait_group.concurrent(self.io, triggerGetOrLoadBuildFile, .{ self, gop.key_ptr.* }) catch {
            _ = try self.getOrLoadBuildFile(gop.key_ptr.*);
        };
    }

    return gop.value_ptr.*;
}

pub const CImportHandle = struct {
    /// the `@cImport` node
    node: Ast.Node.Index,
    /// hash of c source file
    hash: Hash,
    /// c source file
    source: []const u8,
};

/// collects every file uri the given handle depends on
/// includes imports, cimports & packages
/// **Thread safe** takes a shared lock
pub fn collectDependencies(
    store: *DocumentStore,
    allocator: std.mem.Allocator,
    handle: *Handle,
    dependencies: *std.ArrayList(Uri),
) error{ Canceled, OutOfMemory }!void {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const import_uris = try handle.getImportUris();

    try dependencies.ensureUnusedCapacity(allocator, import_uris.len);
    for (import_uris) |uri| {
        dependencies.appendAssumeCapacity(try allocator.dupe(u8, uri));
    }

    if (supports_build_system) no_build_file: {
        const build_file_uri = try handle.getAssociatedBuildFileUri(store) orelse break :no_build_file;
        const build_file = store.getBuildFile(build_file_uri) orelse break :no_build_file;
        _ = try build_file.collectBuildConfigPackageUris(store.io, allocator, dependencies);
    }
}

/// returns `true` if all include paths could be collected
/// may return `false` because include paths from a build.zig may not have been resolved already
/// **Thread safe** takes a shared lock
pub fn collectIncludeDirs(
    store: *DocumentStore,
    allocator: std.mem.Allocator,
    handle: *Handle,
    include_dirs: *std.ArrayList([]const u8),
) error{ Canceled, OutOfMemory }!bool {
    comptime std.debug.assert(supports_build_system);

    var arena_allocator: std.heap.ArenaAllocator = .init(allocator);
    defer arena_allocator.deinit();

    const target_info: std.Target = .{
        .cpu = .{
            .arch = builtin.cpu.arch,
            .model = undefined,
            .features = undefined,
        },
        .os = builtin.target.os,
        .abi = .none,
        .ofmt = comptime std.Target.ObjectFormat.default(builtin.os.tag, builtin.cpu.arch),
        .dynamic_linker = std.Target.DynamicLinker.none,
    };
    const arena_allocator_allocator = arena_allocator.allocator();
    const native_paths: std.zig.system.NativePaths = try .detect(arena_allocator_allocator, store.io, &target_info, @constCast(store.config.environ_map));

    try include_dirs.ensureUnusedCapacity(allocator, native_paths.include_dirs.items.len);
    for (native_paths.include_dirs.items) |native_include_dir| {
        include_dirs.appendAssumeCapacity(try allocator.dupe(u8, native_include_dir));
    }

    const collected_all = switch (try handle.getAssociatedBuildFileUri2(store)) {
        .none => true,
        .unresolved => false,
        .resolved => |build_file| try build_file.collectBuildConfigIncludePaths(store.io, allocator, include_dirs),
    };

    return collected_all;
}

/// returns `true` if all c macro definitions could be collected
/// may return `false` because macros from a build.zig may not have been resolved already
/// **Thread safe** takes a shared lock
pub fn collectCMacros(
    store: *DocumentStore,
    allocator: std.mem.Allocator,
    handle: *Handle,
    c_macros: *std.ArrayList([]const u8),
) error{ Canceled, OutOfMemory }!bool {
    comptime std.debug.assert(supports_build_system);

    const collected_all = switch (try handle.getAssociatedBuildFileUri2(store)) {
        .none => true,
        .unresolved => false,
        .resolved => |build_file| blk: {
            const build_config = build_file.tryLockConfig(store.io) orelse break :blk false;
            defer build_file.unlockConfig(store.io);

            try c_macros.ensureUnusedCapacity(allocator, build_config.c_macros.len);
            for (build_config.c_macros) |c_macro| {
                c_macros.appendAssumeCapacity(try allocator.dupe(u8, c_macro));
            }
            break :blk true;
        },
    };

    return collected_all;
}

fn publishCimportDiagnostics(self: *DocumentStore, handle: *Handle) (std.mem.Allocator.Error || std.Io.File.Writer.Error)!void {
    var wip: std.zig.ErrorBundle.Wip = undefined;
    try wip.init(self.allocator);
    defer wip.deinit();

    const src_path = try wip.addString("");

    for (handle.cimports.items(.hash), handle.cimports.items(.node)) |hash, node| {
        const result = blk: {
            try self.mutex.lock(self.io);
            defer self.mutex.unlock(self.io);
            break :blk self.cimports.get(hash) orelse continue;
        };
        const error_bundle: std.zig.ErrorBundle = switch (result) {
            .success => continue,
            .failure => |bundle| bundle,
        };

        if (error_bundle.errorMessageCount() == 0) continue;

        const loc = offsets.nodeToLoc(&handle.tree, node);
        const source_loc = std.zig.findLineColumn(handle.tree.source, loc.start);

        // assert that the `@intCast` below is safe
        comptime std.debug.assert(std.zig.max_src_size <= std.math.maxInt(u32));

        const src_loc = try wip.addSourceLocation(.{
            .src_path = src_path,
            .line = @intCast(source_loc.line),
            .column = @intCast(source_loc.column),
            .span_start = @intCast(loc.start),
            .span_main = @intCast(loc.start),
            .span_end = @intCast(loc.end),
            .source_line = try wip.addString(source_loc.source_line),
        });

        for (error_bundle.getMessages()) |err_msg_index| {
            const err_msg = error_bundle.getErrorMessage(err_msg_index);
            const msg = error_bundle.nullTerminatedString(err_msg.msg);

            try wip.addRootErrorMessage(.{
                .msg = try wip.addString(msg),
                .src_loc = src_loc,
            });
        }
    }

    {
        var error_bundle = try wip.toOwnedBundle("");
        errdefer error_bundle.deinit(self.allocator);

        try self.diagnostics_collection.pushSingleDocumentDiagnostics(
            .cimport,
            handle.uri,
            .{ .error_bundle = error_bundle },
        );
    }
    try self.diagnostics_collection.publishDiagnostics();
}

/// takes the string inside a @import() node (without the quotation marks)
/// and returns it's uri
/// caller owns the returned memory
/// **Thread safe** takes a shared lock
pub fn uriFromImportStr(self: *DocumentStore, allocator: std.mem.Allocator, handle: *Handle, import_str: []const u8) error{ Canceled, OutOfMemory }!?Uri {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    if (std.mem.eql(u8, import_str, "std")) {
        const zig_lib_dir = self.config.zig_lib_dir orelse return null;

        const std_path = try zig_lib_dir.join(allocator, &.{ "std", "std.zig" });
        defer allocator.free(std_path);

        return try URI.fromPath(allocator, std_path);
    }

    if (std.mem.eql(u8, import_str, "builtin")) {
        if (supports_build_system) {
            if (try handle.getAssociatedBuildFileUri(self)) |build_file_uri| {
                const build_file = self.getBuildFile(build_file_uri).?;
                if (build_file.builtin_uri) |builtin_uri| {
                    return try allocator.dupe(u8, builtin_uri);
                }
            }
        }
        if (self.config.builtin_path) |builtin_path| {
            return try URI.fromPath(allocator, builtin_path);
        }
        return null;
    }

    if (supports_build_system) {
        if (isBuildFile(handle.uri)) blk: {
            // NOTE deps_build_roots are currently not available in the serialized configuration
            // const build_file = self.getBuildFile(handle.uri) orelse break :blk;
            // const build_config = build_file.tryLockConfig(self.io) orelse break :blk;
            // defer build_file.unlockConfig(self.io);

            // for (build_config.deps_build_roots) |dep_build_root| {
            //     if (std.mem.eql(u8, import_str, dep_build_root.name)) {
            //         return try URI.fromPath(allocator, dep_build_root.path);
            //     }
            // }
            break :blk;
        } else {
            closest: {
                const closest_build_zig_uri = handle.closest_build_file_uri orelse break :closest;
                const build_file = self.getBuildFile(closest_build_zig_uri) orelse break :closest;
                const build_cfg = build_file.getConfiguration(self.io);
                defer build_cfg.release(self.io);

                const roots_count = build_cfg.roots.map.count();
                if (roots_count == 0) break :closest;
                if (!(build_file.configuration.roots.index < roots_count)) {
                    log.err("root_id > roots.len; using id 0", .{});
                    build_file.configuration.roots.index = 0;
                }

                const cs = build_cfg.roots.map.values()[build_cfg.roots.index];
                for (cs.mods.items) |mod| {
                    if (std.mem.eql(u8, import_str, mod.name)) {
                        return if (!std.mem.endsWith(u8, mod.path, "%pending%")) try URI.fromPath(allocator, mod.path) else null;
                    }
                }
            }

            // gamba
            for (self.workspaces.items) |wrkspc| search_wrkspc: {
                const wrkspc_bld_fl_uri = wrkspc.build_file_uri orelse break :search_wrkspc;
                const build_file = self.getBuildFile(wrkspc_bld_fl_uri) orelse break :search_wrkspc;
                const build_cfg = build_file.getConfiguration(self.io);
                defer build_cfg.release(self.io);

                const roots_count = build_cfg.roots.map.count();
                if (roots_count == 0) break :search_wrkspc;
                if (!(build_file.configuration.roots.index < roots_count)) {
                    log.err("root_id > roots.len; using id 0", .{});
                    build_file.configuration.roots.index = 0;
                }

                const cs = build_cfg.roots.map.values()[build_cfg.roots.index];
                for (cs.mods.items) |mod| {
                    if (std.mem.eql(u8, import_str, mod.name)) {
                        return if (!std.mem.endsWith(u8, mod.path, "%pending%")) try URI.fromPath(allocator, mod.path) else null;
                    }
                }
            }

            // legacy way
            // if (try handle.getAssociatedBuildFileUri(self)) |build_file_uri| blk: {
            //     const build_file = self.getBuildFile(build_file_uri).?;
            //     const build_config = build_file.tryLockConfig(self.io) orelse break :blk;
            //     defer build_file.unlockConfig(self.io);

            //     if (build_config.roots.len != 0) {
            //         if (!(build_file.roots_index < build_config.roots.len)) {
            //             log.err("root_id > roots.len; using id 0", .{});
            //             build_file.roots_index = 0;
            //         }

            //         for (build_config.roots[build_file.roots_index].mods) |mod| {
            //             if (std.mem.eql(u8, import_str, mod.name)) {
            //                 return try URI.fromPath(allocator, mod.path);
            //             }
            //         }
            //     }

            //     for (build_config.packages) |pkg| {
            //         if (std.mem.eql(u8, import_str, pkg.name)) {
            //             return try URI.fromPath(allocator, pkg.path);
            //         }
            //     }
            // }
        }
    }

    return if (std.mem.endsWith(u8, import_str, ".zig") or std.mem.endsWith(u8, import_str, ".zon"))
        try uriFromFileImportStr(allocator, handle, import_str)
    else
        null;
}

pub fn uriFromFileImportStr(allocator: std.mem.Allocator, handle: *Handle, import_str: []const u8) error{OutOfMemory}!?Uri {
    const base_path = URI.toFsPath(allocator, handle.uri) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    defer allocator.free(base_path);

    const joined_path = try std.fs.path.resolve(allocator, &.{ base_path, "..", import_str });
    defer allocator.free(joined_path);

    return try URI.fromPath(allocator, joined_path);
}

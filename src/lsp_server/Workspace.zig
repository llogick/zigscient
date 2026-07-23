uri: types.URI,
build_file_uri: ?types.URI = null,
build_on_save: if (BuildOnSaveSupport.isSupportedComptime()) ?BuildOnSave else void,
build_on_save_mode: if (BuildOnSaveSupport.isSupportedComptime()) ?enum { watch, manual } else void,

pub fn init(
    server: *Server,
    uri: types.URI,
) error{ OutOfMemory, Canceled }!Workspace {
    var w: Workspace = .{
        .uri = try server.allocator.dupe(u8, uri),
        .build_on_save = if (BuildOnSaveSupport.isSupportedComptime()) null else {},
        .build_on_save_mode = if (BuildOnSaveSupport.isSupportedComptime()) null else {},
    };

    blk: {
        var arena_state = std.heap.ArenaAllocator.init(server.allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        const dir_path = uri_util.toFsPath(arena, uri) catch break :blk;
        if (try DocumentStore.buildDotZigExists(server.io, dir_path)) {
            const bf_path = try std.fs.path.join(arena, &.{ dir_path, "build.zig" });
            const bf_uri = try uri_util.fromPath(server.allocator, bf_path);
            w.build_file_uri = bf_uri;
            _ = try server.document_store.getOrLoadHandle(bf_uri);
        }
    }

    return w;
}

pub fn deinit(workspace: *Workspace, allocator: std.mem.Allocator) void {
    if (BuildOnSaveSupport.isSupportedComptime()) {
        if (workspace.build_on_save) |*build_on_save| build_on_save.deinit();
    }
    allocator.free(workspace.uri);
    if (workspace.build_file_uri) |bfuri| allocator.free(bfuri);
}

pub fn sendManualWatchUpdate(workspace: *Workspace) void {
    comptime std.debug.assert(BuildOnSaveSupport.isSupportedComptime());

    const build_on_save = if (workspace.build_on_save) |*build_on_save| build_on_save else return;
    const mode = workspace.build_on_save_mode orelse return;
    if (mode != .manual) return;

    build_on_save.sendManualWatchUpdate();
}

pub fn refreshBuildOnSave(workspace: *Workspace, args: struct {
    server: *Server,
    /// Whether the build on save process should be restarted if it is already running.
    restart: bool,
}) error{ Canceled, OutOfMemory }!void {
    comptime std.debug.assert(BuildOnSaveSupport.isSupportedComptime());

    const config = &args.server.config_manager.config;

    if (args.server.config_manager.zig_exe) |zig_exe| {
        workspace.build_on_save_mode = switch (BuildOnSaveSupport.isSupportedRuntime(zig_exe.version)) {
            .supported => .watch,
            // If if build on save has been explicitly enabled, fallback to the implementation with manual updates
            else => if (config.enable_build_on_save orelse false) .manual else null,
        };
    } else {
        workspace.build_on_save_mode = null;
    }

    const build_on_save_supported = workspace.build_on_save_mode != null;
    const build_on_save_wanted = config.enable_build_on_save orelse true;
    const enable = build_on_save_supported and build_on_save_wanted;

    if (workspace.build_on_save) |*build_on_save| {
        if (enable and !args.restart) return;
        log.debug("stopped Build-On-Save for '{s}'", .{workspace.uri});
        build_on_save.deinit();
        workspace.build_on_save = null;
    }

    if (!enable) return;

    const zig_exe_path = config.zig_exe_path orelse return;
    const zig_lib_path = config.zig_lib_path orelse return;
    const build_runner_path = config.build_runner_path orelse return;

    const workspace_path = uri_util.toFsPath(args.server.allocator, workspace.uri) catch |err| {
        log.err("failed to parse URI '{s}': {}", .{ workspace.uri, err });
        return;
    };
    defer args.server.allocator.free(workspace_path);

    std.debug.assert(workspace.build_on_save == null);
    workspace.build_on_save = BuildOnSave.init(.{
        .io = args.server.io,
        .allocator = args.server.allocator,
        .workspace_path = workspace_path,
        .build_on_save_args = config.build_on_save_args,
        .check_step_only = config.enable_build_on_save == null,
        .zig_exe_path = zig_exe_path,
        .zig_lib_path = zig_lib_path,
        .build_runner_path = build_runner_path,
        .collection = &args.server.diagnostics_collection,
        .document_store = &args.server.document_store,
    }) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        else => {
            log.err("failed to initilize Build-On-Save for '{s}': {}", .{ workspace.uri, err });
            return;
        },
    };

    log.info("trying to start Build-On-Save for '{s}'", .{workspace.uri});
}

const Workspace = @This();

const std = @import("std");
const lsp_server = @import("lsp-server");
const Server = lsp_server.Server;
const DocumentStore = lsp_server.DocumentStore;
const lsp = lsp_server.lsp;
const types = lsp.types;
const diagnostics_gen = lsp_server.diagnostics;
const uri_util = lsp_server.uri_util;

const build_runner_shared = @import("build_runner/shared.zig");
const BuildOnSave = diagnostics_gen.BuildOnSave;
const BuildOnSaveSupport = build_runner_shared.BuildOnSaveSupport;

const log = std.log.scoped(.ls_workspace);

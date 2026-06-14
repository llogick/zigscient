rev: u32 = 0,
mutex: std.Io.Mutex = .init,
cond: std.Io.Condition = .init,
ref_count: std.atomic.Value(u32) = .init(1),
result: enum {
    pending,
    success,
    failure,
    no_build_zig,
} = .pending,
path: ?[]const u8 = null,
options: ?std.json.Parsed(BuildOptions) = null,
selected_compile_step_index: u32 = 0,
// data

const StackItem = struct {
    step: std.Build.Configuration.Step.Index,
    dep_index: u32,
    depth: u32,
};
const max_spaces: [64]u8 = @splat(' ');

pub fn reload(p: *ParsedConfiguration, s: *Server, w: *Workspace) error{ OutOfMemory, Canceled }!void {
    const zig_exe = s.config_manager.zig_exe orelse return;
    if (!@import("build_runner/check.zig").isBuildRunnerSupported(zig_exe.version)) {
        log.debug("Workspaces: Skipping (Re)Load Configuration: Unsupported zig version {f}", .{zig_exe.version});
        return;
    }

    try p.mutex.lock(s.io);
    defer p.mutex.unlock(s.io);

    if (p.result == .no_build_zig) return;

    var arena_state = std.heap.ArenaAllocator.init(s.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const dir_path = uri_util.toFsPath(arena, w.uri) catch return;
    if (!try DocumentStore.buildDotZigExists(s.io, dir_path)) {
        p.result = .no_build_zig;
        return;
    }

    var args: std.ArrayList([]const u8) = .empty;
    try args.appendSlice(arena, &.{ zig_exe.path, "build", "--print-configuration-path" });
    if (s.config_manager.zig_lib_dir) |zig_lib_dir| if (zig_lib_dir.path) |zig_lib_dir_path| try args.appendSlice(arena, &.{ "--zig-lib-dir", zig_lib_dir_path });

    const run_result = std.process.run(arena, s.io, .{
        .argv = args.items,
        .cwd = .{ .path = dir_path },
        .reserve_amount = 1024 * 4,
    }) catch |err| switch (err) {
        error.Canceled => |e| return e,
        else => |e| {
            log.err("Failed to run {q} : {t}", .{ "zig build --print-configuration-path", e });
            return;
        },
    };

    const diagnostic_tag: DiagnosticsCollection.Tag = tag: {
        var hasher: std.hash.Wyhash = .init(47); // Chosen by the following prompt: Pwease give a wandom nyumbew
        hasher.update(dir_path);
        break :tag @enumFromInt(@as(u32, @truncate(hasher.final())));
    };

    p.rev += 1;

    if (switch (run_result.term) {
        .exited => |exit_code| exit_code == 0,
        else => false,
    }) {
        try s.diagnostics_collection.pushErrorBundle(diagnostic_tag, p.rev, null, .empty);
        s.diagnostics_collection.publishDiagnostics() catch |err| {
            std.log.err("Failed to push diagnostics for workspace {q}: {t}", .{ dir_path, err });
        };
    } else {
        const joined = try std.mem.join(arena, " ", args.items);

        log.err(
            "Failed to obtain configuration for workspace {q}\nDIR: {s}\nCMD: {s}\nERR:\n{s}",
            .{ w.uri, dir_path, joined, run_result.stderr },
        );

        const error_bundle = try @import("features/diagnostics.zig").getErrorBundleFromStderr(
            arena,
            run_result.stderr,
            false,
            .{ .dynamic = .{ .document_store = &s.document_store, .base_path = dir_path } },
        );

        try s.diagnostics_collection.pushErrorBundle(diagnostic_tag, p.rev, dir_path, error_bundle);
        s.diagnostics_collection.publishDiagnostics() catch |err| {
            std.log.err("Failed to push diagnostics for workspace {q}: {t}", .{ dir_path, err });
        };
        return;
    }

    const path = try std.fs.path.resolve(s.allocator, &.{ dir_path, std.mem.trimEnd(u8, run_result.stdout, " \r\n") });
    if (p.path) |cfg_path| {
        if (std.mem.eql(u8, path, cfg_path)) {
            s.allocator.free(path);
            return;
        }
        s.allocator.free(cfg_path);
    }
    p.path = path;

    const serialized = c: {
        var file = std.Io.Dir.openFile(.cwd(), s.io, path, .{}) catch |err| {
            log.err("Failed to open configuration file {q} : {t}", .{ path, err });
            return;
        };
        defer file.close(s.io);
        break :c std.Build.Configuration.loadFile(arena, s.io, file) catch |err| {
            log.err("Failed to load configuration file {q}: {t}", .{ path, err });
            return;
        };
    };

    var stack: std.array_list.Managed(StackItem) = .init(arena);
    const c = &serialized;
    // var top_level_steps: std.StringArrayHashMapUnmanaged(Configuration.Step.Index) = .empty;
    for (c.steps, 0..) |*conf_step, step_index_usize| {
        if (conf_step.owner != .root) continue;

        const step_index: std.Build.Configuration.Step.Index = @enumFromInt(step_index_usize);
        const flags = conf_step.flags(c);
        if (flags.tag != .top_level) continue;

        try stack.append(.{ .step = step_index, .dep_index = 0, .depth = 0 });

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
                        if (current.depth == 0) log.err(" ", .{});
                        log.err("{s}{}: {q} - {q} ({t})", .{
                            indent,
                            @intFromEnum(current.step),
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
                                .relative => |rp| rp.sub_path.slice(c),
                                .generated => |gp| if (gp.sub_path != .empty) gp.sub_path.slice(c) else "%gen%",
                            };
                        }
                        log.err("{s}{}: {q} - {q} ({t} {t})", .{
                            indent,
                            @intFromEnum(current.step),
                            compile.root_name.slice(c),
                            name,
                            step_flags.tag,
                            compile.flags3.kind,
                        });
                        log.err("{s}-> root={q}", .{ sub_indent, rsf_path });
                        const imports = rm.import_table.get(c).imports;
                        for (imports.mal.items(.name), imports.mal.items(.module)) |import_name, other_mod_idx| {
                            const other_mod: std.Build.Configuration.Module = other_mod_idx.get(c);
                            if (other_mod.root_source_file.unwrap()) |rsf| {
                                rsf_path = switch (rsf.get(c)) {
                                    .source_path => |sp| sp.sub_path.slice(c),
                                    .relative => |rp| rp.sub_path.slice(c),
                                    .generated => |gp| if (gp.sub_path != .empty) gp.sub_path.slice(c) else "%gen%",
                                };
                            } else rsf_path = "";
                            log.err("{s}-> {s}={q}", .{ sub_indent, import_name.slice(c), rsf_path });
                        }
                    },
                    else => log.err("{s}{}: {q} ({t})", .{
                        indent,
                        @intFromEnum(current.step),
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
    log.info("Loaded configuration for workspace {q}", .{w.uri});

    // const bf_path = try std.fs.path.join(arena, &.{ dir_path, "build.zig" });
    // const bf_uri = try uri_util.fromPath(s.allocator, bf_path);
    // errdefer s.allocator.free(bf_uri);
    // w.build_file_uri = bf_uri;
    // _ = try s.document_store.getOrLoadHandle(bf_uri);
}

const ParsedConfiguration = @This();

const std = @import("std");
const lsp_server = @import("lsp-server");
const Server = lsp_server.Server;
const DocumentStore = lsp_server.DocumentStore;
const lsp = lsp_server.lsp;
const types = lsp.types;
const diagnostics_gen = lsp_server.diagnostics;
const uri_util = lsp_server.uri_util;

const Workspace = @import("Workspace.zig");
const BuildOptions = @import("BuildOptions.zig");
const DiagnosticsCollection = @import("DiagnosticsCollection.zig");
const build_runner_shared = @import("build_runner/shared.zig");

const log = std.log.scoped(.lspc_configuration);

//! A thread-safe container for all document related state like zig source files including `build.zig`.

const std = @import("std");
const builtin = @import("builtin");
const URI = @import("uri.zig");
const analysis = @import("analysis.zig");
const offsets = @import("offsets.zig");
const log = std.log.scoped(.store);
const lsp = @import("lsp");
const Ast = std.zig.Ast;
const extd_zccs = @import("extended-zccs");
const BuildAssociatedConfig = @import("BuildAssociatedConfig.zig");
const BuildConfig = @import("build_runner/shared.zig").BuildConfig;
const tracy = @import("tracy");
const translate_c = @import("translate_c.zig");
const DocumentScope = @import("DocumentScope.zig");
const DiagnosticsCollection = @import("DiagnosticsCollection.zig");
const Server = @import("Server.zig");

const DocumentStore = @This();

io: std.Io,
allocator: std.mem.Allocator,
workspaces: *std.ArrayList(Server.Workspace),
/// the DocumentStore assumes that `config` is not modified while calling one of its functions.
config: Config,
mutex: std.Io.Mutex = .init,
wait_group: if (supports_build_system) std.Io.Group else void = if (supports_build_system) .init else {},
handles: std.StringArrayHashMapUnmanaged(*Handle) = .empty,
build_files: if (supports_build_system) std.StringArrayHashMapUnmanaged(*BuildFile) else void = if (supports_build_system) .empty else {},
cimports: if (supports_build_system) std.AutoArrayHashMapUnmanaged(Hash, translate_c.Result) else void = if (supports_build_system) .empty else {},
diagnostics_collection: *DiagnosticsCollection,
builds_in_progress: std.atomic.Value(i32) = .init(0),
transport: ?*lsp.Transport = null,
lsp_capabilities: struct {
    supports_work_done_progress: bool = false,
    supports_semantic_tokens_refresh: bool = false,
    supports_inlay_hints_refresh: bool = false,
} = .{},

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

pub const Config = struct {
    environ_map: *const std.process.Environ.Map,
    zig_exe_path: ?[]const u8,
    zig_lib_dir: ?std.Build.Cache.Directory,
    build_runner_path: ?[]const u8,
    builtin_path: ?[]const u8,
    global_cache_dir: ?std.Build.Cache.Directory,
    wasi_preopens: switch (builtin.os.tag) {
        .wasi => std.process.Preopens,
        else => void,
    },
};

/// Represents a `build.zig`
pub const BuildFile = struct {
    uri: Uri,
    /// this build file may have an explicitly specified path to builtin.zig
    builtin_uri: ?Uri = null,
    /// config options extracted from zls.build.json
    build_associated_config: ?std.json.Parsed(BuildAssociatedConfig) = null,
    roots_index: u32 = 0,
    impl: struct {
        mutex: std.Io.Mutex = .init,
        build_runner_state: BuildRunnerState = .idle,
        version: u32 = 0,
        /// contains information extracted from running build.zig with a custom build runner
        /// e.g. include paths & packages
        /// TODO this field should not be nullable, callsites should await the build config to be resolved
        /// and then continue instead of dealing with missing information.
        config: ?std.json.Parsed(BuildConfig) = null,
    } = .{},

    const BuildRunnerState = enum {
        idle,
        running,
        running_but_already_invalidated,
    };

    pub fn tryLockConfig(self: *BuildFile, io: std.Io) ?BuildConfig {
        self.impl.mutex.lockUncancelable(io);
        return if (self.impl.config) |cfg| cfg.value else {
            self.impl.mutex.unlock(io);
            return null;
        };
    }

    pub fn unlockConfig(self: *BuildFile, io: std.Io) void {
        self.impl.mutex.unlock(io);
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
        self: *BuildFile,
        io: std.Io,
        allocator: std.mem.Allocator,
        package_uris: *std.ArrayList(Uri),
    ) error{OutOfMemory}!bool {
        const tracy_zone = tracy.trace(@src());
        defer tracy_zone.end();

        const build_config = self.tryLockConfig(io) orelse return false;
        defer self.unlockConfig(io);

        try package_uris.ensureUnusedCapacity(allocator, build_config.packages.len);
        for (build_config.packages) |package| {
            package_uris.appendAssumeCapacity(try URI.fromPath(allocator, package.path));
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
        self: *BuildFile,
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
                const build_file_path = URI.toFsPath(allocator, build_file_dir) catch |err| switch (err) {
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

    fn deinit(self: *BuildFile, allocator: std.mem.Allocator) void {
        allocator.free(self.uri);
        if (self.impl.config) |cfg| cfg.deinit();
        if (self.builtin_uri) |builtin_uri| allocator.free(builtin_uri);
        if (self.build_associated_config) |cfg| cfg.deinit();
    }
};

/// Represents a Zig source file.
pub const Handle = struct {
    uri: Uri,
    /// Custom AST with extra data. Must be freed with .deinit
    ast: extd_zccs.Ast,
    /// std.zig.Ast compatible mapping of the custom AST ('ast`)
    /// Never .deinit directly
    tree: Ast,
    /// Contains one entry for every cimport in the document
    cimports: std.MultiArrayList(CImportHandle),

    // Set by the main thread / read by server.generateDiagnostics and AstCheck
    change_pending: std.atomic.Value(bool) = .init(false),

    /// First build.zig up the dir tree
    closest_build_file_uri: ?[]const u8 = null,

    /// private field
    impl: struct {
        /// @bitCast from/to `Status`
        status: std.atomic.Value(u32),
        store: *DocumentStore,

        lock: std.Io.Mutex = .init,
        /// See `getLazy`
        lazy_condition: std.Io.Condition = .init,

        import_uris: ?[]Uri = null,
        document_scope: DocumentScope = undefined,
        zzoiir: ZirOrZoir = undefined,

        associated_build_file: union(enum) {
            /// The initial state. The associated build file (build.zig) is resolved lazily.
            init,
            /// The associated build file (build.zig) has been requested but has not yet been resolved.
            unresolved: struct {
                /// The build files are ordered in decreasing priority.
                potential_build_files: []const *BuildFile,
                /// to avoid checking build files multiple times, a bitset stores whether or
                /// not the build file should be skipped because it has previously been
                /// found to be "unassociated" with the handle.
                has_been_checked: std.DynamicBitSetUnmanaged,

                fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                    allocator.free(self.potential_build_files);
                    self.has_been_checked.deinit(allocator);
                    self.* = undefined;
                }
            },
            /// The Handle has no associated build file (build.zig).
            none,
            /// The associated build file (build.zig) has been successfully resolved.
            resolved: *BuildFile,
        } = .init,
    },

    const ZirOrZoir = union(Ast.Mode) {
        zig: std.zig.Zir,
        zon: std.zig.Zoir,
    };

    const Status = packed struct(u32) {
        /// `true` if the document has been directly opened by the client i.e. with `textDocument/didOpen`
        /// `false` indicates the document only exists because it is a dependency of another document
        /// or has been closed with `textDocument/didClose`.
        lsp_synced: bool = false,
        /// true if a thread has acquired the permission to compute the `DocumentScope`
        /// all other threads will wait until the given thread has computed the `DocumentScope` before reading it.
        has_document_scope_lock: bool = false,
        /// true if `handle.impl.document_scope` has been set
        has_document_scope: bool = false,
        /// true if a thread has acquired the permission to compute the `std.zig.Zir` or `std.zig.Zoir`
        has_zzoiir_lock: bool = false,
        /// all other threads will wait until the given thread has computed the `std.zig.Zir` or `std.zig.Zoir` before reading it.
        /// true if `handle.impl.zir` has been set
        has_zzoiir: bool = false,
        _: u27 = 0,
    };

    /// Takes ownership of `text` on success.
    pub fn init(
        store: *DocumentStore,
        uri: Uri,
        text: [:0]const u8,
        lsp_synced: bool,
    ) error{OutOfMemory}!Handle {
        const kind: extd_zccs.Ast.Kind = if (std.mem.eql(u8, std.fs.path.extension(uri), ".zon")) .zon else .zig;

        const allocator = store.allocator;

        var custom_ast = try createAst(allocator, text, kind, lsp_synced);
        errdefer custom_ast.destroy();

        const std_ast = custom_ast.toStdAst();

        var cimports = try collectCIncludes(allocator, &std_ast);
        errdefer cimports.deinit(allocator);

        return .{
            .uri = uri,
            .ast = custom_ast,
            .tree = std_ast,
            .cimports = cimports,
            .impl = .{
                .status = .init(@bitCast(Status{
                    .lsp_synced = lsp_synced,
                })),
                .store = store,
            },
        };
    }

    fn deinitAstDeps(self: *Handle) void {
        const status = self.getStatus();

        const allocator = self.impl.store.allocator;

        if (status.has_zzoiir) switch (self.tree.mode) {
            .zig => self.impl.zzoiir.zig.deinit(allocator),
            .zon => self.impl.zzoiir.zon.deinit(allocator),
        };
        if (status.has_document_scope) self.impl.document_scope.deinit(allocator);

        if (self.impl.import_uris) |import_uris| {
            for (import_uris) |uri| allocator.free(uri);
            allocator.free(import_uris);
            self.impl.import_uris = null;
        }

        for (self.cimports.items(.source)) |source| allocator.free(source);
        self.cimports.deinit(allocator);
    }

    /// Caller must free `Handle.uri` if needed.
    fn deinit(self: *Handle) void {
        const tracy_zone = tracy.trace(@src());
        defer tracy_zone.end();

        const allocator = self.ast.gpa;

        self.deinitAstDeps();
        self.ast.destroy();

        switch (self.impl.associated_build_file) {
            .init, .none, .resolved => {},
            .unresolved => |*payload| payload.deinit(allocator),
        }

        if (self.closest_build_file_uri) |cbfuri| allocator.free(cbfuri);

        self.* = undefined;
    }

    pub fn getImportUris(self: *Handle) error{OutOfMemory}![]const Uri {
        const store = self.impl.store;
        const allocator = store.allocator;
        const io = store.io;

        self.impl.lock.lockUncancelable(io);
        defer self.impl.lock.unlock(io);

        if (self.impl.import_uris) |import_uris| return import_uris;

        var imports = try analysis.collectImports(allocator, &self.tree);

        var i: usize = 0;
        errdefer {
            // only free the uris
            for (imports.items[0..i]) |uri| allocator.free(uri);
            imports.deinit(allocator);
        }

        // Convert to URIs
        while (i < imports.items.len) {
            const import_str = imports.items[i];
            if (!std.mem.endsWith(u8, import_str, ".zig")) {
                _ = imports.swapRemove(i);
                continue;
            }
            // The raw import strings are owned by the document and do not need to be freed here.
            imports.items[i] = try uriFromFileImportStr(allocator, self, import_str) orelse {
                _ = imports.swapRemove(i);
                continue;
            };
            i += 1;
        }

        self.impl.import_uris = try imports.toOwnedSlice(allocator);
        return self.impl.import_uris.?;
    }

    pub fn getDocumentScope(self: *Handle) error{OutOfMemory}!DocumentScope {
        if (self.getStatus().has_document_scope) return self.impl.document_scope;
        return try self.getLazy(DocumentScope, "document_scope", struct {
            fn create(handle: *Handle, allocator: std.mem.Allocator) error{OutOfMemory}!DocumentScope {
                var document_scope: DocumentScope = try .init(allocator, &handle.tree);
                errdefer document_scope.deinit(allocator);

                // remove unused capacity
                document_scope.extra.shrinkAndFree(allocator, document_scope.extra.items.len);
                try document_scope.declarations.setCapacity(allocator, document_scope.declarations.len);
                try document_scope.scopes.setCapacity(allocator, document_scope.scopes.len);

                return document_scope;
            }
        });
    }

    /// Asserts that `getDocumentScope` has been previously called on `handle`.
    pub fn getDocumentScopeCached(self: *Handle) DocumentScope {
        if (builtin.mode == .Debug) {
            std.debug.assert(self.getStatus().has_document_scope);
        }
        return self.impl.document_scope;
    }

    pub fn getZir(self: *Handle) error{OutOfMemory}!std.zig.Zir {
        std.debug.assert(self.tree.mode == .zig);
        const zir_or_zoir = try self.getZirOrZoir();
        return zir_or_zoir.zig;
    }

    pub fn getZoir(self: *Handle) error{OutOfMemory}!std.zig.Zoir {
        std.debug.assert(self.tree.mode == .zon);
        const zir_or_zoir = try self.getZirOrZoir();
        return zir_or_zoir.zon;
    }

    fn getZirOrZoir(self: *Handle) error{OutOfMemory}!ZirOrZoir {
        if (self.getStatus().has_zzoiir) return self.impl.zzoiir;
        return try self.getLazy(ZirOrZoir, "zzoiir", struct {
            fn create(handle: *Handle, allocator: std.mem.Allocator) error{OutOfMemory}!ZirOrZoir {
                switch (handle.tree.mode) {
                    .zig => {
                        const tracy_zone = tracy.traceNamed(@src(), "AstGen.generate");
                        defer tracy_zone.end();

                        var zir = try extd_zccs.AstCheck.generate(allocator, handle.tree, &handle.change_pending);
                        errdefer zir.deinit(allocator);

                        return .{ .zig = zir };
                    },
                    .zon => {
                        const tracy_zone = tracy.traceNamed(@src(), "ZonGen.generate");
                        defer tracy_zone.end();

                        const zoir = try std.zig.ZonGen.generate(allocator, handle.tree, .{});

                        return .{ .zon = zoir };
                    },
                }
            }
        });
    }

    /// Returns the associated build file (build.zig) of the handle.
    ///
    /// `DocumentStore.build_files` is guaranteed to contain this Uri.
    /// Uri memory managed by its build_file
    pub fn getAssociatedBuildFileUri(self: *Handle, document_store: *DocumentStore) error{ Canceled, OutOfMemory }!?Uri {
        comptime std.debug.assert(supports_build_system);
        switch (try self.getAssociatedBuildFileUri2(document_store)) {
            .none,
            .unresolved,
            => return null,
            .resolved => |build_file| return build_file.uri,
        }
    }

    /// Returns the associated build file (build.zig) of the handle.
    ///
    /// `DocumentStore.build_files` is guaranteed to contain this Uri.
    /// Uri memory managed by its build_file
    pub fn getAssociatedBuildFileUri2(self: *Handle, document_store: *DocumentStore) error{ Canceled, OutOfMemory }!union(enum) {
        /// The Handle has no associated build file (build.zig).
        none,
        /// The associated build file (build.zig) has not been resolved yet.
        unresolved,
        /// The associated build file (build.zig) has been successfully resolved.
        resolved: *BuildFile,
    } {
        comptime std.debug.assert(supports_build_system);

        try self.impl.lock.lock(document_store.io);
        defer self.impl.lock.unlock(document_store.io);

        const unresolved = switch (self.impl.associated_build_file) {
            .init => blk: {
                const potential_build_files = try document_store.collectPotentialBuildFiles(self.uri);
                errdefer document_store.allocator.free(potential_build_files);

                if (potential_build_files.len == 0) {
                    self.impl.associated_build_file = .none;
                    return .none;
                }

                var has_been_checked: std.DynamicBitSetUnmanaged = try .initEmpty(document_store.allocator, potential_build_files.len);
                errdefer has_been_checked.deinit(document_store.allocator);

                self.impl.associated_build_file = .{ .unresolved = .{
                    .has_been_checked = has_been_checked,
                    .potential_build_files = potential_build_files,
                } };

                break :blk &self.impl.associated_build_file.unresolved;
            },
            .unresolved => |*unresolved| unresolved,
            .none => return .none,
            .resolved => |build_file| return .{ .resolved = build_file },
        };

        // special case when there is only one potential build file
        if (unresolved.potential_build_files.len == 1) {
            const build_file = unresolved.potential_build_files[0];
            log.debug("Resolved build file of '{s}' as '{s}'", .{ self.uri, build_file.uri });
            unresolved.deinit(document_store.allocator);
            self.impl.associated_build_file = .{ .resolved = build_file };
            return .{ .resolved = build_file };
        }

        var has_missing_build_config = false;

        var it = unresolved.has_been_checked.iterator(.{
            .kind = .unset,
            .direction = .reverse,
        });
        while (it.next()) |i| {
            const build_file = unresolved.potential_build_files[i];
            const is_associated = try document_store.uriAssociatedWithBuild(build_file, self.uri) orelse {
                has_missing_build_config = true;
                continue;
            };

            if (!is_associated) {
                // the build file should be skipped in future calls.
                unresolved.has_been_checked.set(i);
                continue;
            }

            log.debug("Resolved build file of '{s}' as '{s}'", .{ self.uri, build_file.uri });
            unresolved.deinit(document_store.allocator);
            self.impl.associated_build_file = .{ .resolved = build_file };
            return .{ .resolved = build_file };
        }

        if (has_missing_build_config) {
            // when build configs are missing we keep the state at .unresolved so that
            // future calls will retry until all build config are resolved.
            // Then will have a conclusive result on whether or not there is a associated build file.
            return .unresolved;
        }

        unresolved.deinit(document_store.allocator);
        self.impl.associated_build_file = .none;
        return .none;
    }

    fn getLazy(
        self: *Handle,
        comptime T: type,
        comptime name: []const u8,
        comptime Context: type,
    ) error{OutOfMemory}!T {
        @branchHint(.cold);
        const tracy_zone = tracy.traceNamed(@src(), "getLazy(" ++ name ++ ")");
        defer tracy_zone.end();

        const has_data_field_name = "has_" ++ name;
        const has_lock_field_name = "has_" ++ name ++ "_lock";

        const io = self.impl.store.io;

        self.impl.lock.lockUncancelable(io);
        defer self.impl.lock.unlock(io);

        while (true) {
            const status = self.getStatus();
            if (@field(status, has_data_field_name)) break;
            if (@field(status, has_lock_field_name) or
                self.impl.status.bitSet(@bitOffsetOf(Status, has_lock_field_name), .release) != 0)
            {
                // another thread is currently computing the data
                self.impl.lazy_condition.waitUncancelable(io, &self.impl.lock);
                continue;
            }
            defer self.impl.lazy_condition.broadcast(io);

            @field(self.impl, name) = try Context.create(self, self.impl.store.allocator);
            errdefer comptime unreachable;

            const old_has_data = self.impl.status.bitSet(@bitOffsetOf(Status, has_data_field_name), .release);
            std.debug.assert(old_has_data == 0); // race condition
        }
        return @field(self.impl, name);
    }

    fn getStatus(self: *const Handle) Status {
        return @bitCast(self.impl.status.load(.acquire));
    }

    pub fn isLspSynced(self: *const Handle) bool {
        return self.getStatus().lsp_synced;
    }

    /// returns the previous value
    fn setLspSynced(self: *Handle, lsp_synced: bool) bool {
        if (lsp_synced) {
            return self.impl.status.bitSet(@offsetOf(Handle.Status, "lsp_synced"), .release) == 1;
        } else {
            return self.impl.status.bitReset(@offsetOf(Handle.Status, "lsp_synced"), .release) == 1;
        }
    }

    pub fn setChangePending(self: *Handle, value: bool) void {
        self.change_pending.store(value, .release);
    }

    pub fn getChangePending(self: *const Handle) bool {
        return self.change_pending.load(.acquire);
    }

    fn createAst(allocator: std.mem.Allocator, new_text: [:0]const u8, kind: extd_zccs.Ast.Kind, is_lsp_synced: bool) error{OutOfMemory}!extd_zccs.Ast {
        const tracy_zone_inner = tracy.traceNamed(@src(), "createAst");
        defer tracy_zone_inner.end();

        var custom_ast = try extd_zccs.Ast.createFromBytesSlice(
            allocator,
            new_text,
            kind,
            if (is_lsp_synced) .extended else .standard,
        );
        errdefer custom_ast.deinit(allocator);

        return custom_ast;
    }

    pub fn applyContentChanges(
        self: *Handle,
        content_changes: []const lsp.types.TextDocument.ContentChangeEvent,
        encoding: offsets.Encoding,
        diagnostics_collection: *DiagnosticsCollection,
    ) error{ OutOfMemory, InternalError }!void {
        const tracy_zone = tracy.trace(@src());
        defer tracy_zone.end();

        const prev_bytes_len = self.ast.bytes.items.len;

        // lowest and highest indexes affected by the change(s)
        var idx_lo: u32, //
        var idx_hi: u32, //
        const last_full_text_index //
        = blk: {
            var i: u32 = @intCast(content_changes.len);
            while (i != 0) {
                i -= 1;
                switch (content_changes[i]) {
                    .text_document_content_change_partial => |pcc| {
                        if (pcc.rangeLength) |rl| if (rl != self.ast.bytes.items.len - 1) continue;
                        // sometimes partial masks a whole
                        const loc = offsets.rangeToLoc(self.ast.bytes.items, pcc.range, encoding);
                        if (loc.start != 0 and loc.end != self.ast.bytes.items.len - 1) continue;
                        try self.ast.bytes.replaceRange(self.ast.gpa, 0, self.ast.bytes.items.len - 1, pcc.text);
                        break :blk .{ 0, @intCast(@max(self.ast.bytes.items.len - 1, prev_bytes_len - 1)), i };
                    },
                    .text_document_content_change_whole_document => |content_change| {
                        try self.ast.bytes.replaceRange(self.ast.gpa, 0, self.ast.bytes.items.len - 1, content_change.text);
                        break :blk .{ 0, @intCast(@max(self.ast.bytes.items.len - 1, prev_bytes_len - 1)), i };
                    },
                }
            }
            break :blk .{ @intCast(self.ast.bytes.items.len - 1), 0, null };
        };

        // don't even bother applying changes before a full text change
        const changes = content_changes[if (last_full_text_index) |index| index + 1 else 0..];

        for (changes) |item| {
            const content_change = item.text_document_content_change_partial;

            const loc = offsets.rangeToLoc(self.ast.bytes.items, content_change.range, encoding);

            if (loc.start < idx_lo) idx_lo = @intCast(loc.start);
            const upper_index: u32 = @intCast(loc.end);
            if (idx_hi < upper_index) idx_hi = upper_index;

            try self.ast.bytes.replaceRange(self.ast.gpa, loc.start, loc.end - loc.start, content_change.text);
        }

        std.debug.assert(self.ast.bytes.items[self.ast.bytes.items.len - 1] == 0);

        if (self.ast.bytes.items.len > std.zig.max_src_size) {
            log.err("change document '{s}' failed: text size ({d}) is above maximum length ({d})", .{
                self.uri,
                self.ast.bytes.items.len,
                std.zig.max_src_size,
            });
            return error.InternalError;
        }

        try self.ast.update(@intCast(prev_bytes_len), idx_lo, idx_hi);

        self.deinitAstDeps();

        self.impl.status = .init(@bitCast(Status{ .lsp_synced = self.isLspSynced() }));
        self.tree = self.ast.toStdAst();
        self.cimports = try collectCIncludes(self.ast.gpa, &self.tree);

        var arena_state = std.heap.ArenaAllocator.init(self.ast.gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        for (diagnostics_collection.tag_set.values()) |entry| {
            if (entry.error_bundle.errorMessageCount() == 0) continue;
            const eb = entry.error_bundle;
            for (eb.getMessages()) |message_index| {
                const message = eb.getErrorMessage(message_index);
                if (message.src_loc == .none) continue;

                const loc = eb.getSourceLocation(message.src_loc);
                const path = eb.nullTerminatedString(loc.src_path);
                const uri = try DiagnosticsCollection.pathToUri(
                    arena,
                    entry.error_bundle_src_base_path,
                    path,
                ) orelse continue;
                if (!std.mem.eql(u8, self.uri, uri)) continue;
                if (last_full_text_index) |_| {
                    // clear the error by setting it's src_loc to .none/0
                    @constCast(entry.error_bundle.extra)[@intFromEnum(message.src_loc)] = 0;
                    continue;
                }
                for (changes) |change| {
                    const ptdc = change.text_document_content_change_partial;
                    if (ptdc.range.start.line > loc.line) continue;
                    if (ptdc.range.end.line < loc.line) {
                        const num_affected_lines: u32 = @intCast(ptdc.range.end.line - ptdc.range.start.line);
                        const num_new_lines: u32 = @intCast(std.mem.count(u8, ptdc.text, "\n"));
                        if (num_new_lines == num_affected_lines) continue;
                        var new_loc = loc;
                        if (num_new_lines == 0) new_loc.line -= num_affected_lines else new_loc.line += if (num_new_lines > num_affected_lines)
                            (num_new_lines - num_affected_lines)
                        else
                            (num_affected_lines - num_new_lines);
                        setExtra(&entry.error_bundle, @intFromEnum(message.src_loc), new_loc);
                    }
                }
            }
        }
    }

    // IF this handle is also a BuildFile scan for `$ls root_id N` and apply
    pub fn handleRootIdComment(handle: *Handle, ds: *DocumentStore, send_notification: bool) void {
        if (handle.tree.errors.len != 0) return;
        const build_file = ds.getBuildFile(handle.uri) orelse return;

        var send_noti: bool = send_notification;

        switch_roots_index: {
            const ttags = handle.tree.tokens.items(.tag);
            var tok_i: u32 = 0;
            while (tok_i < ttags.len) : (tok_i += 1) {
                if (ttags[tok_i] != .keyword_fn) continue;
                if (tok_i + 10 > ttags.len) break :switch_roots_index;
                tok_i += 1;
                if (ttags[tok_i] != .identifier) continue;
                if (!std.mem.eql(u8, "build", handle.tree.tokenSlice(tok_i))) continue;
                while (tok_i < ttags.len - 1 and ttags[tok_i] != .r_brace) tok_i += 1;
                const src_i = handle.tree.tokens.items(.start)[tok_i];
                const source = handle.tree.source;
                if (src_i + 20 > source.len) break :switch_roots_index;
                _ = std.mem.indexOf(u8, source[0 .. src_i + 20], "//") orelse break :switch_roots_index;
                const lsm_i = std.mem.indexOf(u8, source[0 .. src_i + 20], "$ls") orelse break :switch_roots_index;
                var tokenizer: std.zig.Tokenizer = .{ .buffer = source, .index = lsm_i + 3 };
                var tok = tokenizer.next();
                if (tok.tag != .identifier and !std.mem.eql(u8, "root_id", source[tok.loc.start..tok.loc.end])) break :switch_roots_index;
                tok = tokenizer.next();
                if (tok.tag != .number_literal) break :switch_roots_index;
                var roots_index = std.fmt.parseInt(u32, source[tok.loc.start..tok.loc.end], 10) catch break :switch_roots_index;
                const config = build_file.tryLockConfig(ds.io) orelse break :switch_roots_index;
                defer build_file.unlockConfig(ds.io);
                if (!(roots_index < config.roots.len)) {
                    log.err("{s}: roots_index > roots.len; using id 0", .{handle.uri});
                    roots_index = 0;
                }
                if (build_file.roots_index == roots_index) return;
                build_file.roots_index = roots_index;
                send_noti = true;
            }
        }

        if (!send_noti) return;

        roots_index_msg: {
            const config = build_file.tryLockConfig(ds.io) orelse break :roots_index_msg;
            defer build_file.unlockConfig(ds.io);
            if (config.roots.len == 0) return;

            const message = std.fmt.allocPrint(
                ds.allocator,
                "Using CompileStep \"{s}\" (`roots_index {}`) to resolve module imports for documents with build file {s} .",
                .{
                    config.roots[build_file.roots_index].name,
                    build_file.roots_index,
                    handle.uri,
                },
            ) catch break :roots_index_msg;
            defer ds.allocator.free(message);

            sendMessageToClient(
                ds.io,
                ds.allocator,
                ds.transport.?,
                lsp.TypedJsonRPCNotification(lsp.types.window.ShowMessageParams){
                    .method = "window/showMessage",
                    .params = lsp.types.window.ShowMessageParams{ .type = .Info, .message = message },
                },
            ) catch {};
        }
    }
};

fn setExtra(wip: *const std.zig.ErrorBundle, index: usize, extra: anytype) void {
    const fields = @typeInfo(@TypeOf(extra)).@"struct".fields;
    var i = index;
    inline for (fields) |field| {
        @constCast(wip.extra)[i] = switch (field.type) {
            u32 => @field(extra, field.name),
            std.zig.ErrorBundle.MessageIndex => @intFromEnum(@field(extra, field.name)),
            std.zig.ErrorBundle.SourceLocationIndex => @intFromEnum(@field(extra, field.name)),
            else => @compileError("bad field type"),
        };
        i += 1;
    }
}

pub fn deinit(self: *DocumentStore) void {
    if (supports_build_system) {
        self.wait_group.cancel(self.io);
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

        for (self.cimports.values()) |*result| {
            result.deinit(self.allocator);
        }
        self.cimports.deinit(self.allocator);
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
/// This function does not protect against data races from modifying the BuildFile
pub fn getBuildFile(self: *DocumentStore, uri: Uri) ?*BuildFile {
    comptime std.debug.assert(supports_build_system);
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    return self.build_files.get(uri);
}

/// invalidates any pointers into `DocumentStore.build_files`
/// **Thread safe** takes an exclusive lock
/// This function does not protect against data races from modifying the BuildFile
fn getOrLoadBuildFile(self: *DocumentStore, uri: Uri) error{ Canceled, OutOfMemory }!*BuildFile {
    comptime std.debug.assert(supports_build_system);

    if (self.getBuildFile(uri)) |build_file| return build_file;

    const new_build_file: *BuildFile = blk: {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);

        const gop = try self.build_files.getOrPut(self.allocator, uri);
        if (gop.found_existing) return gop.value_ptr.*;
        errdefer self.build_files.swapRemoveAt(gop.index);

        gop.value_ptr.* = try self.allocator.create(BuildFile);
        errdefer self.allocator.destroy(gop.value_ptr.*);

        gop.value_ptr.*.* = try self.createBuildFile(uri);
        gop.key_ptr.* = gop.value_ptr.*.uri;
        break :blk gop.value_ptr.*;
    };

    // this code path is only reached when the build file is new

    self.invalidateBuildFile(new_build_file.uri);

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

    const duped_text = try self.allocator.dupeZ(u8, text);
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

    if (self.config.zig_exe_path == null) return;
    if (self.config.build_runner_path == null) return;
    if (self.config.global_cache_dir == null) return;
    if (self.config.zig_lib_dir == null) return;

    const build_file = self.getBuildFile(build_file_uri) orelse return;

    self.wait_group.async(self.io, invalidateBuildFileWorker, .{ self, build_file });
}

const progress_token = "buildProgressToken";

fn sendMessageToClient(
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

fn notifyBuildStart(self: *DocumentStore) void {
    if (!self.lsp_capabilities.supports_work_done_progress) return;

    const transport = self.transport orelse return;

    // Atomicity note: We do not actually care about memory surrounding the
    // counter, we only care about the counter itself. We only need to ensure
    // we aren't double entering/exiting
    const prev = self.builds_in_progress.fetchAdd(1, .monotonic);
    if (prev != 0) return;

    sendMessageToClient(self.io, self.allocator, transport, .{
        .jsonrpc = "2.0",
        .id = "progress",
        .method = "window/workDoneProgress/create",
        .params = lsp.types.window.work_done_progress.CreateParams{
            .token = .{ .string = progress_token },
        },
    }) catch |err| switch (err) {
        error.Canceled => comptime unreachable,
        else => |e| {
            log.err("Failed to send create work message: {}", .{e});
            return;
        },
    };

    sendMessageToClient(self.io, self.allocator, transport, .{
        .jsonrpc = "2.0",
        .method = "$/progress",
        .params = .{
            .token = progress_token,
            .value = lsp.types.window.work_done_progress.Begin{
                .title = "Loading build configuration",
            },
        },
    }) catch |err| switch (err) {
        error.Canceled => comptime unreachable,
        else => |e| {
            log.err("Failed to send progress start message: {}", .{e});
            return;
        },
    };
}

const EndStatus = enum { success, failed };

fn notifyBuildEnd(self: *DocumentStore, status: EndStatus) void {
    if (!self.lsp_capabilities.supports_work_done_progress) return;

    const transport = self.transport orelse return;

    // Atomicity note: We do not actually care about memory surrounding the
    // counter, we only care about the counter itself. We only need to ensure
    // we aren't double entering/exiting
    const prev = self.builds_in_progress.fetchSub(1, .monotonic);
    if (prev != 1) return;

    const message = switch (status) {
        .failed => "Failed",
        .success => "Success",
    };

    sendMessageToClient(self.io, self.allocator, transport, .{
        .jsonrpc = "2.0",
        .method = "$/progress",
        .params = .{
            .token = progress_token,
            .value = lsp.types.window.work_done_progress.End{
                .message = message,
            },
        },
    }) catch |err| switch (err) {
        error.Canceled => comptime unreachable,
        else => |e| {
            log.err("Failed to send progress end message: {}", .{e});
            return;
        },
    };
}

fn invalidateBuildFileWorker(self: *DocumentStore, build_file: *BuildFile) std.Io.Cancelable!void {
    {
        try build_file.impl.mutex.lock(self.io);
        defer build_file.impl.mutex.unlock(self.io);

        switch (build_file.impl.build_runner_state) {
            .idle => build_file.impl.build_runner_state = .running,
            .running => {
                build_file.impl.build_runner_state = .running_but_already_invalidated;
                return;
            },
            .running_but_already_invalidated => return,
        }
    }

    self.notifyBuildStart();

    while (true) {
        build_file.impl.version += 1;
        const new_version = build_file.impl.version;

        const build_config = loadBuildConfiguration(self, build_file.uri, new_version) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            else => |e| {
                if (e != error.RunFailed) { // already logged
                    log.err("Failed to load build configuration for {s} (error: {})", .{ build_file.uri, e });
                }
                self.notifyBuildEnd(.failed);
                build_file.impl.mutex.lockUncancelable(self.io);
                defer build_file.impl.mutex.unlock(self.io);
                build_file.impl.build_runner_state = .idle;
                return;
            },
        };

        build_file.impl.mutex.lockUncancelable(self.io);
        switch (build_file.impl.build_runner_state) {
            .idle => unreachable,
            .running => {
                var old_config = build_file.impl.config;
                build_file.impl.config = build_config;
                build_file.impl.build_runner_state = .idle;
                build_file.impl.mutex.unlock(self.io);

                if (old_config) |*config| config.deinit();
                self.notifyBuildEnd(.success);
                break;
            },
            .running_but_already_invalidated => {
                build_file.impl.build_runner_state = .running;
                build_file.impl.mutex.unlock(self.io);

                build_config.deinit();
                continue;
            },
        }
    }

    const old_cancel_protect = self.io.swapCancelProtection(.blocked);
    blk: {
        const bf_handle = (self.getOrLoadHandle(build_file.uri) catch break :blk) orelse {
            log.err("Failed to getHandle for: '{s}'", .{build_file.uri});
            break :blk;
        };
        bf_handle.handleRootIdComment(self, true);
    }
    _ = self.io.swapCancelProtection(old_cancel_protect);

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

pub fn isBuiltinFile(uri: Uri) bool {
    return std.mem.endsWith(u8, uri, "/builtin.zig");
}

pub fn isInStd(uri: Uri) bool {
    // TODO: Better logic for detecting std or subdirectories?
    return std.mem.indexOf(u8, uri, "/std/") != null;
}

/// looks for a `zls.build.json` file in the build file directory
/// has to be freed with `json_compat.parseFree`
fn loadBuildAssociatedConfiguration(io: std.Io, allocator: std.mem.Allocator, build_file: BuildFile) !std.json.Parsed(BuildAssociatedConfig) {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const build_file_path = try URI.toFsPath(allocator, build_file.uri);
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

fn prepareBuildRunnerArgs(self: *DocumentStore, build_file_uri: []const u8) error{OutOfMemory}![][]const u8 {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const base_args = &[_][]const u8{
        self.config.zig_exe_path.?,
        "build",
        "--build-runner",
        self.config.build_runner_path.?,
        "--zig-lib-dir",
        self.config.zig_lib_dir.?.path orelse ".",
    };

    var args: std.ArrayList([]const u8) = try .initCapacity(self.allocator, base_args.len);
    errdefer {
        for (args.items) |arg| self.allocator.free(arg);
        args.deinit(self.allocator);
    }

    for (base_args) |arg| {
        args.appendAssumeCapacity(try self.allocator.dupe(u8, arg));
    }

    if (self.getBuildFile(build_file_uri)) |build_file| blk: {
        const build_config = build_file.build_associated_config orelse break :blk;
        const build_options = build_config.value.build_options orelse break :blk;

        try args.ensureUnusedCapacity(self.allocator, build_options.len);
        for (build_options) |option| {
            args.appendAssumeCapacity(try option.formatParam(self.allocator));
        }
    }

    return try args.toOwnedSlice(self.allocator);
}

/// Runs the build.zig and extracts include directories and packages
fn loadBuildConfiguration(self: *DocumentStore, build_file_uri: Uri, build_file_version: u32) !std.json.Parsed(BuildConfig) {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    std.debug.assert(self.config.zig_exe_path != null);
    std.debug.assert(self.config.build_runner_path != null);
    std.debug.assert(self.config.global_cache_dir != null);
    std.debug.assert(self.config.zig_lib_dir != null);

    const build_file_path = try URI.toFsPath(self.allocator, build_file_uri);
    defer self.allocator.free(build_file_path);

    const cwd = std.fs.path.dirname(build_file_path).?;

    const args = try self.prepareBuildRunnerArgs(build_file_uri);
    defer {
        for (args) |arg| self.allocator.free(arg);
        self.allocator.free(args);
    }

    const zig_run_result = blk: {
        const tracy_zone2 = tracy.trace(@src());
        defer tracy_zone2.end();
        break :blk try std.process.run(
            self.allocator,
            self.io,
            .{
                .argv = args,
                .cwd = .{ .path = cwd },
                .stderr_limit = .limited(16 * 1024 * 1024),
                .stdout_limit = .limited(16 * 1024 * 1024),
            },
        );
    };
    defer self.allocator.free(zig_run_result.stdout);
    defer self.allocator.free(zig_run_result.stderr);

    const is_ok = switch (zig_run_result.term) {
        .exited => |exit_code| exit_code == 0,
        else => false,
    };

    const diagnostic_tag: DiagnosticsCollection.Tag = tag: {
        var hasher: std.hash.Wyhash = .init(47); // Chosen by the following prompt: Pwease give a wandom nyumbew
        hasher.update(build_file_uri);
        break :tag @enumFromInt(@as(u32, @truncate(hasher.final())));
    };

    if (!is_ok) {
        const joined = try std.mem.join(self.allocator, " ", args);
        defer self.allocator.free(joined);

        log.err(
            "Failed to execute build runner to collect build configuration, command:\ncd {s};{s}\nError: {s}",
            .{ cwd, joined, zig_run_result.stderr },
        );

        var error_bundle = try @import("features/diagnostics.zig").getErrorBundleFromStderr(
            self.allocator,
            zig_run_result.stderr,
            false,
            .{ .dynamic = .{ .document_store = self, .base_path = cwd } },
        );
        defer error_bundle.deinit(self.allocator);

        try self.diagnostics_collection.pushErrorBundle(diagnostic_tag, build_file_version, cwd, error_bundle);
        try self.diagnostics_collection.publishDiagnostics();
        return error.RunFailed;
    } else {
        try self.diagnostics_collection.pushErrorBundle(diagnostic_tag, build_file_version, null, .empty);
        try self.diagnostics_collection.publishDiagnostics();
    }

    const parse_options: std.json.ParseOptions = .{
        // We ignore unknown fields so people can roll
        // their own build runners in libraries with
        // the only requirement being general adherence
        // to the BuildConfig type
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    };
    const build_config = std.json.parseFromSlice(
        BuildConfig,
        self.allocator,
        zig_run_result.stdout,
        parse_options,
    ) catch return error.InvalidBuildConfig;
    errdefer build_config.deinit();

    for (build_config.value.packages) |*pkg| {
        pkg.path = try std.fs.path.resolve(build_config.arena.allocator(), &.{ build_file_path, "..", pkg.path });
    }

    return build_config;
}

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
        else => {},
    };
}

pub fn findBuildZig(io: std.Io, allocator: std.mem.Allocator, uri: []const u8) !?[]const u8 {
    const fss = "file://";
    const low_idx = if (std.mem.startsWith(u8, uri, fss)) fss.len else 0;
    const min_i = @max(low_idx, std.fs.path.diskDesignator(uri).len);
    var i: usize = uri.len -| std.fs.path.basename(uri).len;
    if (i <= min_i) return null;
    while (true) {
        if (i <= min_i)
            return null;

        const potential_root_path = uri[low_idx..i];

        i -= 1;
        while (i > min_i and !std.fs.path.isSep(uri[i])) : (i -= 1) {}

        if (!std.fs.path.isAbsolute(potential_root_path)) continue;

        var dir = try std.Io.Dir.openDirAbsolute(io, potential_root_path, .{});
        defer dir.close(io);
        if (dir.access(io, "build.zig", .{})) {
            // found a build.zig file
            const path = try std.fs.path.join(allocator, &.{ potential_root_path, "build.zig" });
            defer allocator.free(path);
            return try URI.fromPath(
                allocator,
                path,
            );
        } else |_| continue;
    }
}

/// Walk down the tree towards the uri. When we hit `build.zig` files
/// add them to the list of potential build files.
/// `build.zig` files higher in the filesystem have precedence.
/// See `Handle.getAssociatedBuildFileUri`.
/// Caller owns returned memory.
fn collectPotentialBuildFiles(self: *DocumentStore, uri: Uri) error{ Canceled, OutOfMemory }![]*BuildFile {
    if (isInStd(uri)) return &.{};

    var potential_build_files: std.ArrayList(*BuildFile) = .empty;
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
    std.mem.reverse(*BuildFile, potential_build_files.items);

    return try potential_build_files.toOwnedSlice(self.allocator);
}

fn createBuildFile(self: *DocumentStore, uri: Uri) error{ Canceled, OutOfMemory }!BuildFile {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    var build_file: BuildFile = .{
        .uri = try self.allocator.dupe(u8, uri),
    };

    errdefer build_file.deinit(self.allocator);

    if (loadBuildAssociatedConfiguration(self.io, self.allocator, build_file)) |cfg| {
        build_file.build_associated_config = cfg;

        if (cfg.value.roots_index) |roots_index| build_file.roots_index = roots_index;
        if (cfg.value.relative_builtin_path) |relative_builtin_path| blk: {
            const build_file_path = URI.toFsPath(self.allocator, build_file.uri) catch break :blk;
            const absolute_builtin_path = try std.fs.path.resolve(self.allocator, &.{ build_file_path, "..", relative_builtin_path });
            defer self.allocator.free(absolute_builtin_path);
            build_file.builtin_uri = try URI.fromPath(self.allocator, absolute_builtin_path);
        }
    } else |err| switch (err) {
        error.Canceled => return error.Canceled,
        error.FileNotFound => {},
        else => {
            log.debug("Failed to load config associated with build file {s} (error: {})", .{ build_file.uri, err });
        },
    }

    log.info("Loaded build file '{s}'", .{build_file.uri});

    return build_file;
}

/// Returns whether the `Uri` is a dependency of the given `BuildFile`.
/// May return `null` to indicate an inconclusive result because
/// the required build config has not been resolved yet.
///
/// invalidates any pointers into `build_files`
/// **Thread safe** takes an exclusive lock
fn uriAssociatedWithBuild(
    self: *DocumentStore,
    build_file: *BuildFile,
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
        if (try self.uriInImports(&checked_uris, build_file.uri, package_uri, uri))
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
    _ = self.io.swapCancelProtection(old_cancel_protect);

    var new_handle = Handle.init(self, uri, text, lsp_synced) catch |err| {
        self.allocator.free(text);
        return err;
    };
    errdefer new_handle.deinit();

    if (supports_build_system and isBuildFile(uri) and !isInStd(uri)) {
        _ = try self.getOrLoadBuildFile(uri);
    }

    try self.mutex.lock(self.io);
    defer self.mutex.unlock(self.io);

    const gop = try self.handles.getOrPut(self.allocator, uri);
    errdefer if (!gop.found_existing) std.debug.assert(self.handles.swapRemove(uri));

    if (gop.found_existing) {
        if (lsp_synced) {
            new_handle.impl.associated_build_file = gop.value_ptr.*.impl.associated_build_file;
            gop.value_ptr.*.impl.associated_build_file = .init;

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
            if (new_handle.closest_build_file_uri) |bzfuri| self.wait_group.async(self.io, triggerGetOrLoadHandle, .{ self, bzfuri }); // This would trigger getOrLoadBuildFile too
        }

        new_handle.uri = gop.key_ptr.*;
        gop.value_ptr.*.* = new_handle;
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

/// Collects all `@cImport` nodes and converts them into c source code if possible
/// Caller owns returned memory.
fn collectCIncludes(allocator: std.mem.Allocator, tree: *const Ast) error{OutOfMemory}!std.MultiArrayList(CImportHandle) {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const cimport_nodes = try analysis.collectCImportNodes(allocator, tree);
    defer allocator.free(cimport_nodes);

    var sources: std.MultiArrayList(CImportHandle) = .empty;
    try sources.ensureTotalCapacity(allocator, cimport_nodes.len);
    errdefer {
        for (sources.items(.source)) |source| {
            allocator.free(source);
        }
        sources.deinit(allocator);
    }

    for (cimport_nodes) |node| {
        const c_source = translate_c.convertCInclude(allocator, tree, node) catch |err| switch (err) {
            error.Unsupported => continue,
            error.OutOfMemory => return error.OutOfMemory,
        };

        sources.appendAssumeCapacity(.{
            .node = node,
            .hash = computeHash(c_source),
            .source = c_source,
        });
    }

    return sources;
}

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

    try dependencies.ensureUnusedCapacity(allocator, import_uris.len + handle.cimports.len);
    for (import_uris) |uri| {
        dependencies.appendAssumeCapacity(try allocator.dupe(u8, uri));
    }

    if (supports_build_system) {
        try store.mutex.lock(store.io);
        defer store.mutex.unlock(store.io);
        for (handle.cimports.items(.hash)) |hash| {
            const result = store.cimports.get(hash) orelse continue;
            switch (result) {
                .success => |uri| dependencies.appendAssumeCapacity(try allocator.dupe(u8, uri)),
                .failure => continue,
            }
        }
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

/// returns the document behind `@cImport()` where `node` is the `cImport` node
/// if a cImport can't be translated e.g. requires computing a
/// comptime value `resolveCImport` will return null
/// returned memory is owned by DocumentStore
/// **Thread safe** takes an exclusive lock
pub fn resolveCImport(self: *DocumentStore, handle: *Handle, node: Ast.Node.Index) error{ Canceled, OutOfMemory }!?Uri {
    comptime std.debug.assert(supports_build_system);

    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    if (self.config.zig_exe_path == null) return null;
    if (self.config.zig_lib_dir == null) return null;
    if (self.config.global_cache_dir == null) return null;

    // TODO regenerate cimports if the header files gets modified

    const index = std.mem.findScalar(Ast.Node.Index, handle.cimports.items(.node), node) orelse return null;
    const hash: Hash = handle.cimports.items(.hash)[index];
    const source = handle.cimports.items(.source)[index];

    {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        if (self.cimports.get(hash)) |result| {
            switch (result) {
                .success => |uri| return uri,
                .failure => return null,
            }
        }
    }

    var include_dirs: std.ArrayList([]const u8) = .empty;
    defer {
        for (include_dirs.items) |path| {
            self.allocator.free(path);
        }
        include_dirs.deinit(self.allocator);
    }

    const collected_all_include_dirs = self.collectIncludeDirs(self.allocator, handle, &include_dirs) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        else => {
            log.err("failed to resolve include paths: {}", .{err});
            return null;
        },
    };

    var c_macros: std.ArrayList([]const u8) = .empty;
    defer {
        for (c_macros.items) |c_macro| {
            self.allocator.free(c_macro);
        }
        c_macros.deinit(self.allocator);
    }

    const collected_all_c_macros = self.collectCMacros(self.allocator, handle, &c_macros) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        else => {
            log.err("failed to resolve include paths: {}", .{err});
            return null;
        },
    };

    const maybe_result = translate_c.translate(
        self.io,
        self.allocator,
        self.config,
        include_dirs.items,
        c_macros.items,
        source,
    ) catch |err| switch (err) {
        error.Canceled, error.OutOfMemory => |e| return e,
        else => |e| {
            log.err("failed to translate cimport: {}", .{e});
            return null;
        },
    };
    var result = maybe_result orelse return null;

    if (result == .failure and (!collected_all_include_dirs or !collected_all_c_macros)) {
        result.deinit(self.allocator);
        return null;
    }

    {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        const gop = self.cimports.getOrPutValue(self.allocator, hash, result) catch |err| {
            result.deinit(self.allocator);
            return err;
        };
        if (gop.found_existing) {
            result.deinit(self.allocator);
            result = gop.value_ptr.*;
        }
    }

    self.publishCimportDiagnostics(handle) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        else => {
            log.err("failed to publish cImport diagnostics: {}", .{err});
        },
    };

    switch (result) {
        .success => |uri| {
            log.debug("Translated cImport into {s}", .{uri});
            return uri;
        },
        .failure => return null,
    }
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
    } else if (std.mem.eql(u8, import_str, "builtin")) {
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
    } else if (!std.mem.endsWith(u8, import_str, ".zig")) {
        if (!supports_build_system) return null;

        if (isBuildFile(handle.uri)) blk: {
            const build_file = self.getBuildFile(handle.uri) orelse break :blk;
            const build_config = build_file.tryLockConfig(self.io) orelse break :blk;
            defer build_file.unlockConfig(self.io);

            for (build_config.deps_build_roots) |dep_build_root| {
                if (std.mem.eql(u8, import_str, dep_build_root.name)) {
                    return try URI.fromPath(allocator, dep_build_root.path);
                }
            }
        } else {
            closest: {
                const closest_build_zig_uri = handle.closest_build_file_uri orelse break :closest;
                const build_file = self.getBuildFile(closest_build_zig_uri) orelse break :closest;
                const build_config = build_file.tryLockConfig(self.io) orelse break :closest;
                defer build_file.unlockConfig(self.io);

                if (build_config.roots.len == 0) break :closest;
                if (!(build_file.roots_index < build_config.roots.len)) {
                    log.err("root_id > roots.len; using id 0", .{});
                    build_file.roots_index = 0;
                }

                for (build_config.roots[build_file.roots_index].mods) |mod| {
                    if (std.mem.eql(u8, import_str, mod.name)) {
                        return try URI.fromPath(allocator, mod.path);
                    }
                }
            }

            // gamba
            for (self.workspaces.items) |wrkspc| search_wrkspc: {
                const wrkspc_bld_fl_uri = wrkspc.build_file_uri orelse break :search_wrkspc;
                const build_file = self.getBuildFile(wrkspc_bld_fl_uri) orelse break :search_wrkspc;
                const build_config = build_file.tryLockConfig(self.io) orelse break :search_wrkspc;
                defer build_file.unlockConfig(self.io);

                if (build_config.roots.len == 0) break :search_wrkspc;
                if (!(build_file.roots_index < build_config.roots.len)) {
                    log.err("root_id > roots.len; using id 0", .{});
                    build_file.roots_index = 0;
                }

                for (build_config.roots[build_file.roots_index].mods) |mod| {
                    if (std.mem.eql(u8, import_str, mod.name)) {
                        return try URI.fromPath(allocator, mod.path);
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
        return null;
    } else {
        return try uriFromFileImportStr(allocator, handle, import_str);
    }
}

fn uriFromFileImportStr(allocator: std.mem.Allocator, handle: *Handle, import_str: []const u8) error{OutOfMemory}!?Uri {
    const base_path = URI.toFsPath(allocator, handle.uri) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    defer allocator.free(base_path);

    const joined_path = try std.fs.path.resolve(allocator, &.{ base_path, "..", import_str });
    defer allocator.free(joined_path);

    return try URI.fromPath(allocator, joined_path);
}

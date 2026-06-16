//! Represents a .zig or .zon source file.

/// The document's uri.
uri: Uri,
/// The version number of this document.
version: i32 = 0,
/// Custom AST with extra data. Must be freed with .deinit
ast: extd_zccs.Ast,
/// std.zig.Ast compatible mapping of the custom AST ('ast`)
/// Never .deinit directly
tree: Ast,

// Set by the main thread / read by server.generateDiagnostics and AstCheck
change_pending: std.atomic.Value(bool) = .init(false),

/// First build.zig up the dir tree
closest_build_file_uri: ?[]const u8 = null,

mtime: std.Io.Timestamp = .{ .nanoseconds = 0 },

computed_data: struct {
    lock: std.Io.RwLock = .init,
    build: ?*BldDoc.Build = null,
    type_decls: std.AutoHashMapUnmanaged(Ast.Node.Index, struct {
        ty: Compilation.Type,
        tid: Compilation.Zcu.PerThread.Id,
    }) = .empty,
    air: std.AutoHashMapUnmanaged(Ast.Node.Index, struct {
        air: Compilation.Zcu.Air,
        tid: Compilation.Zcu.PerThread.Id,
    }) = .empty,
} = .{},

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
            potential_build_files: []const *BldDoc,
            /// to avoid checking build files multiple times, a bitset stores whether or
            /// not the build file should be skipped because it has previously been
            /// found to be "unassociated" with the zig_doc.
            has_been_checked: std.DynamicBitSetUnmanaged,

            fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                allocator.free(self.potential_build_files);
                self.has_been_checked.deinit(allocator);
                self.* = undefined;
            }
        },
        /// The ZigDoc has no associated build file (build.zig).
        none,
        /// The associated build file (build.zig) has been successfully resolved.
        resolved: *BldDoc,
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
    /// true if `zig_doc.impl.document_scope` has been set
    has_document_scope: bool = false,
    /// true if a thread has acquired the permission to compute the `std.zig.Zir` or `std.zig.Zoir`
    has_zzoiir_lock: bool = false,
    /// all other threads will wait until the given thread has computed the `std.zig.Zir` or `std.zig.Zoir` before reading it.
    /// true if `zig_doc.impl.zir` has been set
    has_zzoiir: bool = false,
    _: u27 = 0,
};

/// Takes ownership of `text` on success.
pub fn init(
    store: *DocumentStore,
    uri: Uri,
    text: [:0]const u8,
    lsp_synced: bool,
) error{OutOfMemory}!ZigDoc {
    const kind: extd_zccs.Ast.Kind = if (std.mem.eql(u8, std.fs.path.extension(uri), ".zon")) .zon else .zig;

    const allocator = store.allocator;

    var custom_ast = try createAst(allocator, text, kind, lsp_synced);
    errdefer custom_ast.destroy();

    const std_ast = custom_ast.toStdAst();

    return .{
        .uri = uri,
        .ast = custom_ast,
        .tree = std_ast,
        .impl = .{
            .status = .init(@bitCast(Status{
                .lsp_synced = lsp_synced,
            })),
            .store = store,
        },
    };
}

fn deinitAstDeps(self: *ZigDoc) void {
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
}

/// Caller must free `ZigDoc.uri` if needed.
pub fn deinit(self: *ZigDoc) void {
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

    self.computed_data.type_decls.deinit(allocator);
    var val_it = self.computed_data.air.valueIterator();
    while (val_it.next()) |val| val.air.deinit(allocator);
    self.computed_data.air.deinit(allocator);

    self.* = undefined;
}

pub fn getImportUris(self: *ZigDoc) error{OutOfMemory}![]const Uri {
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
        imports.items[i] = try DocumentStore.uriFromFileImportStr(allocator, self, import_str) orelse {
            _ = imports.swapRemove(i);
            continue;
        };
        i += 1;
    }

    self.impl.import_uris = try imports.toOwnedSlice(allocator);
    return self.impl.import_uris.?;
}

pub fn getDocumentScope(self: *ZigDoc) error{OutOfMemory}!DocumentScope {
    if (self.getStatus().has_document_scope) return self.impl.document_scope;
    return try self.getLazy(DocumentScope, "document_scope", struct {
        fn create(zig_doc: *ZigDoc, allocator: std.mem.Allocator) error{OutOfMemory}!DocumentScope {
            var document_scope: DocumentScope = try .init(allocator, &zig_doc.tree);
            errdefer document_scope.deinit(allocator);

            // remove unused capacity
            document_scope.extra.shrinkAndFree(allocator, document_scope.extra.items.len);
            try document_scope.declarations.setCapacity(allocator, document_scope.declarations.len);
            try document_scope.scopes.setCapacity(allocator, document_scope.scopes.len);

            return document_scope;
        }
    });
}

/// Asserts that `getDocumentScope` has been previously called on `zig_doc`.
pub fn getDocumentScopeCached(self: *ZigDoc) DocumentScope {
    if (builtin.mode == .Debug) {
        std.debug.assert(self.getStatus().has_document_scope);
    }
    return self.impl.document_scope;
}

pub fn getZir(self: *ZigDoc) error{OutOfMemory}!std.zig.Zir {
    std.debug.assert(self.tree.mode == .zig);
    const zir_or_zoir = try self.getZirOrZoir();
    return zir_or_zoir.zig;
}

pub fn getZoir(self: *ZigDoc) error{OutOfMemory}!std.zig.Zoir {
    std.debug.assert(self.tree.mode == .zon);
    const zir_or_zoir = try self.getZirOrZoir();
    return zir_or_zoir.zon;
}

fn getZirOrZoir(self: *ZigDoc) error{OutOfMemory}!ZirOrZoir {
    if (self.getStatus().has_zzoiir) return self.impl.zzoiir;
    return try self.getLazy(ZirOrZoir, "zzoiir", struct {
        fn create(zig_doc: *ZigDoc, allocator: std.mem.Allocator) error{OutOfMemory}!ZirOrZoir {
            switch (zig_doc.tree.mode) {
                .zig => {
                    const tracy_zone = tracy.traceNamed(@src(), "AstGen.generate");
                    defer tracy_zone.end();

                    var zir = try extd_zccs.AstCheck.generate(allocator, zig_doc.tree, &zig_doc.change_pending);
                    errdefer zir.deinit(allocator);

                    return .{ .zig = zir };
                },
                .zon => {
                    const tracy_zone = tracy.traceNamed(@src(), "ZonGen.generate");
                    defer tracy_zone.end();

                    const zoir = try std.zig.ZonGen.generate(allocator, zig_doc.tree, .{});

                    return .{ .zon = zoir };
                },
            }
        }
    });
}

/// Returns the associated build file (build.zig) of the zig_doc.
///
/// `DocumentStore.build_files` is guaranteed to contain this Uri.
/// Uri memory managed by its build_file
pub fn getAssociatedBuildFileUri(self: *ZigDoc, document_store: *DocumentStore) error{ Canceled, OutOfMemory }!?Uri {
    comptime std.debug.assert(std.process.can_spawn);
    switch (try self.getAssociatedBuildFileUri2(document_store)) {
        .none,
        .unresolved,
        => return null,
        .resolved => |build_file| return build_file.flat_uri,
    }
}

/// Returns the associated build file (build.zig) of the zig_doc.
///
/// `DocumentStore.build_files` is guaranteed to contain this Uri.
/// Uri memory managed by its build_file
pub fn getAssociatedBuildFileUri2(self: *ZigDoc, document_store: *DocumentStore) error{ Canceled, OutOfMemory }!union(enum) {
    /// The ZigDoc has no associated build file (build.zig).
    none,
    /// The associated build file (build.zig) has not been resolved yet.
    unresolved,
    /// The associated build file (build.zig) has been successfully resolved.
    resolved: *BldDoc,
} {
    comptime std.debug.assert(std.process.can_spawn);

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
        log.debug("Resolved build file of '{s}' as '{s}'", .{ self.uri, build_file.flat_uri });
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

        log.debug("Resolved build file of '{s}' as '{s}'", .{ self.uri, build_file.flat_uri });
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
    self: *ZigDoc,
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

fn getStatus(self: *const ZigDoc) Status {
    return @bitCast(self.impl.status.load(.acquire));
}

pub fn isLspSynced(self: *const ZigDoc) bool {
    return self.getStatus().lsp_synced;
}

/// returns the previous value
pub fn setLspSynced(self: *ZigDoc, lsp_synced: bool) bool {
    if (lsp_synced) {
        return self.impl.status.bitSet(@offsetOf(ZigDoc.Status, "lsp_synced"), .release) == 1;
    } else {
        return self.impl.status.bitReset(@offsetOf(ZigDoc.Status, "lsp_synced"), .release) == 1;
    }
}

pub fn setChangePending(self: *ZigDoc, value: bool) void {
    self.change_pending.store(value, .release);
}

pub fn getChangePending(self: *const ZigDoc) bool {
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
    self: *ZigDoc,
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

// IF this zig_doc is also a BldDoc scan for `$ls root_id N` and apply
pub fn handleRootIdComment(zig_doc: *ZigDoc, ds: *DocumentStore, send_notification: bool) error{ Canceled, OutOfMemory }!void {
    if (zig_doc.tree.errors.len != 0) return;

    const build_file = ds.getBuildFile(zig_doc.uri) orelse return;
    const config = build_file.getConfiguration(ds.io);
    defer config.release(ds.io);

    var send_noti: bool = send_notification;

    switch_roots_index: {
        const ttags = zig_doc.tree.tokens.items(.tag);
        var tok_i: u32 = 0;
        while (tok_i < ttags.len) : (tok_i += 1) {
            if (ttags[tok_i] != .keyword_fn) continue;
            if (tok_i + 10 > ttags.len) break :switch_roots_index;
            tok_i += 1;
            if (ttags[tok_i] != .identifier) continue;
            if (!std.mem.eql(u8, "build", zig_doc.tree.tokenSlice(tok_i))) continue;
            while (tok_i < ttags.len - 1 and ttags[tok_i] != .r_brace) tok_i += 1;
            const src_i = zig_doc.tree.tokens.items(.start)[tok_i];
            const source = zig_doc.tree.source;
            if (src_i + 20 > source.len) break :switch_roots_index;
            _ = std.mem.indexOf(u8, source[0 .. src_i + 20], "//") orelse break :switch_roots_index;
            const lsm_i = std.mem.indexOf(u8, source[0 .. src_i + 20], "$ls") orelse break :switch_roots_index;
            var tokenizer: std.zig.Tokenizer = .{ .buffer = source, .index = lsm_i + 3 };
            var tok = tokenizer.next();
            if (tok.tag != .identifier and !std.mem.eql(u8, "root_id", source[tok.loc.start..tok.loc.end])) break :switch_roots_index;
            tok = tokenizer.next();
            if (tok.tag != .number_literal) break :switch_roots_index;
            var roots_index = std.fmt.parseInt(u32, source[tok.loc.start..tok.loc.end], 10) catch break :switch_roots_index;
            if (!(roots_index < config.roots.map.count())) {
                log.err("{s}: roots_index > roots.len; using id 0", .{zig_doc.uri});
                roots_index = 0;
            }
            if (config.roots.index == roots_index) return;
            build_file.configuration.roots.index = roots_index;
            config.roots.tailor_run_state = .pending;
            send_noti = true;
        }
    }

    if (config.roots.tailor_run_state == .pending) ds.tailor_run_group.async(ds.io, BldDoc.triggerTailorRun, .{ build_file, ds });

    if (!send_noti or ds.config.disable_notifications) return;

    roots_index_msg: {
        if (!(config.roots.index < config.roots.map.count())) return;
        const compile_step = config.roots.map.values()[config.roots.index];
        const message = std.fmt.allocPrint(
            ds.allocator,
            "Using CompileStep \"{s}\" (`roots_index {}`) to resolve module imports for documents with build file {s} .",
            .{
                compile_step.name,
                config.roots.index,
                zig_doc.uri,
            },
        ) catch break :roots_index_msg;
        defer ds.allocator.free(message);

        DocumentStore.sendMessageToClient(
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

fn setExtra(wip: *const std.zig.ErrorBundle, index: usize, extra: anytype) void {
    const extra_info = @typeInfo(@TypeOf(extra)).@"struct";
    const field_names = extra_info.field_names;
    const field_types = extra_info.field_types;
    var i = index;
    inline for (field_names, field_types) |field_name, field_type| {
        @constCast(wip.extra)[i] = switch (field_type) {
            u32 => @field(extra, field_name),
            std.zig.ErrorBundle.MessageIndex => @intFromEnum(@field(extra, field_name)),
            std.zig.ErrorBundle.SourceLocationIndex => @intFromEnum(@field(extra, field_name)),
            else => @compileError("bad field type"),
        };
        i += 1;
    }
}

const std = @import("std");
const Ast = std.zig.Ast;
pub const Uri = []const u8;
const extd_zccs = @import("extended-zccs");
const BldDoc = @import("BldDoc.zig");
const DocumentStore = @import("DocumentStore.zig");
const DocumentScope = @import("DocumentScope.zig");
const ZigDoc = @This();
const tracy = @import("tracy");
const analysis = @import("analysis.zig");
const log = std.log.scoped(.lspc_store);
const builtin = @import("builtin");
const lsp = @import("lsp");
const offsets = @import("offsets.zig");
const DiagnosticsCollection = @import("DiagnosticsCollection.zig");

/// Compiler and Compilation declarations
pub const compiler = @import("compiler");
pub const Compilation = compiler.Compilation;
const CompilationState = compiler.CompilationState;
const buildOutputType = compiler.buildOutputType;

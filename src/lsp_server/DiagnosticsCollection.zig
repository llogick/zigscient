const std = @import("std");
const lsp = @import("lsp");
const tracy = @import("tracy");
const offsets = @import("offsets.zig");
const URI = @import("uri.zig");
const DocumentStore = @import("DocumentStore.zig");

io: std.Io,
allocator: std.mem.Allocator,
mutex: std.Io.Mutex = .init,
tag_set: std.AutoArrayHashMapUnmanaged(Tag, struct {
    version: u32 = 0,
    error_bundle_src_base_path: ?[]const u8 = null,
    /// Used to store diagnostics from `pushErrorBundle`
    error_bundle: std.zig.ErrorBundle = .empty,
    /// Used to store diagnostics from `pushSingleDocumentDiagnostics`
    diagnostics_set: std.StringArrayHashMapUnmanaged(struct {
        arena: std.heap.ArenaAllocator.State = .{},
        diagnostics: []lsp.types.Diagnostic = &.{},
        error_bundle: std.zig.ErrorBundle = .empty,
    }) = .empty,
}) = .empty,
outdated_files: std.StringArrayHashMapUnmanaged(void) = .empty,
transport: ?*lsp.Transport = null,
offset_encoding: offsets.Encoding = .@"utf-16",

const DiagnosticsCollection = @This();

/// Diagnostics with different tags are treated independently.
/// This enables the DiagnosticsCollection to differentiate syntax level errors from build-on-save errors.
/// Build on Save diagnostics have an tag that is the hash of the build step and the path to the `build.zig`
pub const Tag = enum(u32) {
    /// - `std.zig.Ast.parse`
    /// - ast-check
    /// - warn_style
    parse,
    /// errors from `@cImport`
    cimport,
    /// errors from compilation.update()
    /// - Build On Save
    /// - Build Runner
    _,
};

pub fn deinit(collection: *DiagnosticsCollection) void {
    for (collection.tag_set.values()) |*entry| {
        entry.error_bundle.deinit(collection.allocator);
        if (entry.error_bundle_src_base_path) |src_path| collection.allocator.free(src_path);
        for (entry.diagnostics_set.keys(), entry.diagnostics_set.values()) |uri, *lsp_diagnostic| {
            collection.allocator.free(uri);
            lsp_diagnostic.arena.promote(collection.allocator).deinit();
            lsp_diagnostic.error_bundle.deinit(collection.allocator);
        }
        entry.diagnostics_set.deinit(collection.allocator);
    }
    collection.tag_set.deinit(collection.allocator);
    for (collection.outdated_files.keys()) |uri| collection.allocator.free(uri);
    collection.outdated_files.deinit(collection.allocator);
    collection.* = undefined;
}

pub fn pushSingleDocumentDiagnostics(
    collection: *DiagnosticsCollection,
    tag: Tag,
    document_uri: []const u8,
    /// LSP and ErrorBundle will not override each other.
    ///
    /// Takes ownership on success.
    diagnostics: union(enum) {
        lsp: struct {
            arena: std.heap.ArenaAllocator.State,
            diagnostics: []lsp.types.Diagnostic,
        },
        error_bundle: std.zig.ErrorBundle,
    },
) error{OutOfMemory}!void {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    collection.mutex.lockUncancelable(collection.io);
    defer collection.mutex.unlock(collection.io);

    const gop_tag = try collection.tag_set.getOrPutValue(collection.allocator, tag, .{});

    {
        try collection.outdated_files.ensureUnusedCapacity(collection.allocator, 1);
        const duped_uri = try collection.allocator.dupe(u8, document_uri);
        if (collection.outdated_files.fetchPutAssumeCapacity(duped_uri, {})) |_| collection.allocator.free(duped_uri);
    }

    try gop_tag.value_ptr.diagnostics_set.ensureUnusedCapacity(collection.allocator, 1);
    const duped_uri = try collection.allocator.dupe(u8, document_uri);
    const gop_file = gop_tag.value_ptr.diagnostics_set.getOrPutAssumeCapacity(duped_uri);
    if (gop_file.found_existing) {
        collection.allocator.free(duped_uri);
    } else {
        gop_file.value_ptr.* = .{};
    }

    errdefer comptime unreachable;

    switch (diagnostics) {
        .lsp => |data| {
            if (gop_file.found_existing) gop_file.value_ptr.arena.promote(collection.allocator).deinit();
            gop_file.value_ptr.arena = data.arena;
            gop_file.value_ptr.diagnostics = data.diagnostics;
        },
        .error_bundle => |error_bundle| {
            if (gop_file.found_existing) gop_file.value_ptr.error_bundle.deinit(collection.allocator);
            gop_file.value_ptr.error_bundle = error_bundle;
        },
    }
}

pub fn clearDiagnosticsTagForHandle(
    collection: *DiagnosticsCollection,
    tag: Tag,
    document_uri: []const u8,
) void {
    var tag_set = collection.tag_set.getPtr(tag) orelse return;
    var entry = tag_set.diagnostics_set.fetchSwapRemove(document_uri) orelse return;
    entry.value.arena.promote(collection.allocator).deinit();
    entry.value.error_bundle.deinit(collection.allocator);
    collection.allocator.free(entry.key);
}

pub fn pushErrorBundle(
    collection: *DiagnosticsCollection,
    /// All changes will affect diagnostics with the same tag.
    tag: Tag,
    /// * If the `version` is greater than the old version, all diagnostics get removed and the errors from `error_bundle` get added and the `version` is updated.
    /// * If the `version` is equal   to   the old version, the errors from `error_bundle` get added.
    /// * If the `version` is less    than the old version, the errors from `error_bundle` are ignored.
    version: u32,
    /// Used to resolve relative `std.zig.ErrorBundle.SourceLocation.src_path`
    ///
    /// The current implementation assumes that the base path is always the same for the same tag.
    src_base_path: ?[]const u8,
    error_bundle: std.zig.ErrorBundle,
) error{OutOfMemory}!void {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    var new_error_bundle: std.zig.ErrorBundle.Wip = undefined;
    try new_error_bundle.init(collection.allocator);
    defer new_error_bundle.deinit();

    collection.mutex.lockUncancelable(collection.io);
    defer collection.mutex.unlock(collection.io);

    const gop = try collection.tag_set.getOrPutValue(collection.allocator, tag, .{});
    const version_order = std.math.order(version, gop.value_ptr.version);

    switch (version_order) {
        .lt => return, // Ignore outdated diagnostics
        .eq => {},
        .gt => gop.value_ptr.version = version,
    }

    if (error_bundle.errorMessageCount() == 0 and gop.value_ptr.error_bundle.errorMessageCount() == 0) return;

    if (error_bundle.errorMessageCount() != 0) {
        try collectUrisFromErrorBundle(collection.allocator, error_bundle, src_base_path, &collection.outdated_files);
        try new_error_bundle.addBundleAsRoots(error_bundle);
    }

    if (version_order == .gt) {
        try collectUrisFromErrorBundle(
            collection.allocator,
            gop.value_ptr.error_bundle,
            gop.value_ptr.error_bundle_src_base_path,
            &collection.outdated_files,
        );
    } else {
        if (gop.value_ptr.error_bundle.errorMessageCount() != 0) {
            try new_error_bundle.addBundleAsRoots(gop.value_ptr.error_bundle);
        }
    }

    const compile_log_text = if (error_bundle.errorMessageCount() == 0) "" else error_bundle.getCompileLogOutput();

    var owned_error_bundle = try new_error_bundle.toOwnedBundle(compile_log_text);
    errdefer owned_error_bundle.deinit(collection.allocator);

    const duped_error_bundle_src_base_path = if (src_base_path) |base_path| try collection.allocator.dupe(u8, base_path) else null;
    errdefer if (duped_error_bundle_src_base_path) |base_path| collection.allocator.free(base_path);

    errdefer comptime unreachable;

    gop.value_ptr.error_bundle.deinit(collection.allocator);
    gop.value_ptr.error_bundle = owned_error_bundle;

    if (duped_error_bundle_src_base_path) |base_path| {
        if (gop.value_ptr.error_bundle_src_base_path) |old_base_path| {
            collection.allocator.free(old_base_path);
            gop.value_ptr.error_bundle_src_base_path = null;
        }
        gop.value_ptr.error_bundle_src_base_path = base_path;
    }
}

pub fn collectNotVisibleErrMessages(
    collection: *DiagnosticsCollection,
    ds: *DocumentStore,
    /// All changes will affect diagnostics with the same tag.
    tag: Tag,
    /// * If the `version` is greater than the old version, all diagnostics get removed and the errors from `error_bundle` get added and the `version` is updated.
    /// * If the `version` is equal   to   the old version, the errors from `error_bundle` get added.
    /// * If the `version` is less    than the old version, the errors from `error_bundle` are ignored.
    version: u32,
    /// Used to resolve relative `std.zig.ErrorBundle.SourceLocation.src_path`
    ///
    /// The current implementation assumes that the base path is always the same for the same tag.
    src_base_path: ?[]const u8,
    eb: std.zig.ErrorBundle,
) error{OutOfMemory}!void {
    var arena_state = std.heap.ArenaAllocator.init(collection.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Iterate over Messages, checking if the target uri matches a currently LspSynced document
    // If NOT: iterate over the reference-trace for that Message, looking for the first LspSynced document
    // and surface the original error in that document/location
    if (eb.errorMessageCount() != 0) for (eb.getMessages()) |message_index| {
        const message = eb.getErrorMessage(message_index);
        if (message.src_loc == .none) continue;

        // call local extraData instead of getSourceLocation to get the .end index as well
        const location = errbExtraData(
            eb,
            ErrorBundle.SourceLocation,
            @intFromEnum(message.src_loc),
        );

        // Surface
        // src/blah.zig:1:1: error: unable to load 'blah.zig': FileNotFound
        // src/main.zig:2:22: note: file imported here
        const eb_message = eb.nullTerminatedString(message.msg);
        if (std.mem.startsWith(u8, eb_message, "unable to load") and std.mem.endsWith(u8, eb_message, "FileNotFound")) unable_to_load: {
            const eb_notes = eb.getNotes(message_index);
            if (eb_notes.len == 0) break :unable_to_load;
            const eb_note = eb.getErrorMessage(eb_notes[0]);
            if (eb_note.src_loc == .none) break :unable_to_load;
            const eb_note_message = eb.nullTerminatedString(eb_note.msg);
            if (!std.mem.eql(u8, eb_note_message, "file imported here")) break :unable_to_load;
            const eb_note_src_loc = eb.getSourceLocation(eb_note.src_loc);
            const eb_note_src_path = eb.nullTerminatedString(eb_note_src_loc.src_path);
            var wip_eb: ErrorBundle.Wip = undefined;
            try wip_eb.init(arena);
            try wip_eb.addRootErrorMessage(.{
                .msg = try wip_eb.addString(try std.fmt.allocPrint(arena, "[!] {s}", .{eb_message})),
                .src_loc = try wip_eb.addSourceLocation(
                    .{
                        .src_path = try wip_eb.addString(eb_note_src_path),
                        .line = eb_note_src_loc.line,
                        .column = eb_note_src_loc.column,
                        .span_start = eb_note_src_loc.span_start,
                        .span_main = eb_note_src_loc.span_main,
                        .span_end = eb_note_src_loc.span_end,
                        .source_line = 0,
                    },
                ),
                .notes_len = 0,
            });
            try collection.pushErrorBundle(
                tag,
                version,
                src_base_path,
                try wip_eb.toOwnedBundle(""),
            );
            continue;
        }

        if (location.data.reference_trace_len == 0) continue;

        const path = eb.nullTerminatedString(location.data.src_path);
        const uri = try DiagnosticsCollection.pathToUri(
            arena,
            src_base_path,
            path,
        ) orelse continue;

        const target_uri_is_open_in_editor = if (ds.getHandle(uri)) |doc| doc.isLspSynced() else false;
        if (target_uri_is_open_in_editor) continue;

        var wip_eb: ErrorBundle.Wip = undefined;
        try wip_eb.init(arena);

        var notes: std.ArrayList(ErrorBundle.MessageIndex) = .empty;
        try notes.append(arena, try wip_eb.addErrorMessage(.{
            .msg = try wip_eb.addString(eb.nullTerminatedString(location.data.source_line)),
            .src_loc = try addOtherSourceLocation(&wip_eb, eb, message.src_loc),
        }));

        var reference_index = location.end;
        for (0..location.data.reference_trace_len) |_| {
            const reference = errbExtraData(
                eb,
                ErrorBundle.ReferenceTrace,
                reference_index,
            );
            reference_index = reference.end;
            if (reference.data.src_loc == .none) break;

            const ref_location = eb.getSourceLocation(reference.data.src_loc);
            const ref_path = eb.nullTerminatedString(ref_location.src_path);
            const ref_uri = try DiagnosticsCollection.pathToUri(
                arena,
                src_base_path,
                ref_path,
            ) orelse continue;

            try notes.append(arena, try wip_eb.addErrorMessage(.{
                .msg = try wip_eb.addString(eb.nullTerminatedString(reference.data.decl_name)),
                .src_loc = try addOtherSourceLocation(&wip_eb, eb, reference.data.src_loc),
            }));

            const ref_uri_is_open_in_editor = if (ds.getHandle(ref_uri)) |doc| doc.isLspSynced() else false;
            if (!ref_uri_is_open_in_editor) continue;

            try wip_eb.addRootErrorMessage(.{
                .msg = try wip_eb.addString(
                    try std.fmt.allocPrint(
                        arena,
                        "[!] {s}",
                        .{
                            eb.nullTerminatedString(message.msg),
                        },
                    ),
                ),
                .src_loc = try wip_eb.addSourceLocation(
                    .{
                        .src_path = try wip_eb.addString(ref_path),
                        .line = ref_location.line,
                        .column = ref_location.column,
                        .span_start = ref_location.span_start,
                        .span_main = ref_location.span_main,
                        .span_end = ref_location.span_end,
                        .source_line = try wip_eb.addString(eb.nullTerminatedString(ref_location.source_line)),
                        // The following four values are tailored as such that DiagnosticsCollection.errorBundleSourceLocationToRange
                        // will emit a lsp.types.Range that underlines line:0 to line:column . See the ^ fn for more info
                        // .span_start = 0,
                        // .span_main = ref_location.column,
                        // .span_end = ref_location.column,
                        // .source_line = 0,
                    },
                ),
                .notes_len = @intCast(notes.items.len),
            });

            // Maybe surface the error in more places
            // if (std.mem.find(u8, eb.nullTerminatedString(reference.data.decl_name), "__anon_")) |_| continue;

            const notes_start = try wip_eb.reserveNotes(@intCast(notes.items.len));
            @memcpy(wip_eb.extra.items[notes_start..][0..notes.items.len], @as([]const u32, @ptrCast(notes.items)));

            try collection.pushErrorBundle(
                tag,
                version,
                src_base_path,
                try wip_eb.toOwnedBundle(""),
            );

            break;
        }
    };
}

pub fn clearErrorBundle(collection: *DiagnosticsCollection, tag: Tag) void {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    collection.mutex.lockUncancelable(collection.io);
    defer collection.mutex.unlock(collection.io);

    const item = collection.tag_set.getPtr(tag) orelse return;

    collectUrisFromErrorBundle(
        collection.allocator,
        item.error_bundle,
        item.error_bundle_src_base_path,
        &collection.outdated_files,
    ) catch |err| switch (err) {
        error.OutOfMemory => return,
    };

    if (item.error_bundle_src_base_path) |base_path| {
        collection.allocator.free(base_path);
        item.error_bundle_src_base_path = null;
    }
    item.error_bundle.deinit(collection.allocator);
    item.error_bundle = .empty;
}

pub fn clearSingleDocumentDiagnostics(collection: *DiagnosticsCollection, document_uri: []const u8) void {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    collection.mutex.lockUncancelable(collection.io);
    defer collection.mutex.unlock(collection.io);

    for (collection.tag_set.values()) |*item| {
        var kv = item.diagnostics_set.fetchSwapRemove(document_uri) orelse continue;
        kv.value.arena.promote(collection.allocator).deinit();
        kv.value.error_bundle.deinit(collection.allocator);

        const gop = collection.outdated_files.getOrPut(collection.allocator, kv.key) catch {
            collection.allocator.free(kv.key);
            continue;
        };
        if (gop.found_existing) collection.allocator.free(kv.key);
    }
}

fn collectUrisFromErrorBundle(
    allocator: std.mem.Allocator,
    error_bundle: std.zig.ErrorBundle,
    src_base_path: ?[]const u8,
    uri_set: *std.StringArrayHashMapUnmanaged(void),
) error{OutOfMemory}!void {
    if (error_bundle.errorMessageCount() == 0) return;
    for (error_bundle.getMessages()) |msg_index| {
        const err = error_bundle.getErrorMessage(msg_index);
        if (err.src_loc == .none) continue;
        const src_loc = error_bundle.getSourceLocation(err.src_loc);
        const src_path = error_bundle.nullTerminatedString(src_loc.src_path);

        try uri_set.ensureUnusedCapacity(allocator, 1);
        const uri = try pathToUri(allocator, src_base_path, src_path) orelse continue;
        if (uri_set.fetchPutAssumeCapacity(uri, {})) |_| {
            allocator.free(uri);
        }
    }
}

pub fn pathToUri(allocator: std.mem.Allocator, base_path: ?[]const u8, src_path: []const u8) error{OutOfMemory}!?[]const u8 {
    if (std.fs.path.isAbsolute(src_path)) {
        return try URI.fromPath(allocator, src_path);
    }
    const base = base_path orelse return null;
    const absolute_src_path = try std.fs.path.join(allocator, &.{ base, src_path });
    defer allocator.free(absolute_src_path);

    return try URI.fromPath(allocator, absolute_src_path);
}

pub fn publishDiagnostics(collection: *DiagnosticsCollection) (std.mem.Allocator.Error || std.Io.File.Writer.Error)!void {
    const transport = collection.transport orelse return;
    const io = collection.io;

    var arena_allocator: std.heap.ArenaAllocator = .init(collection.allocator);
    defer arena_allocator.deinit();

    while (true) {
        const json_message = blk: {
            try collection.mutex.lock(io);
            defer collection.mutex.unlock(io);

            const entry = collection.outdated_files.pop() orelse break;
            defer collection.allocator.free(entry.key);
            const document_uri = entry.key;

            _ = arena_allocator.reset(.retain_capacity);

            var diagnostics: std.ArrayList(lsp.types.Diagnostic) = .empty;
            try collection.collectLspDiagnosticsForDocument(document_uri, collection.offset_encoding, arena_allocator.allocator(), &diagnostics);

            const notification: lsp.TypedJsonRPCNotification(lsp.types.publish_diagnostics.Params) = .{
                .method = "textDocument/publishDiagnostics",
                .params = .{
                    .uri = document_uri,
                    .diagnostics = diagnostics.items,
                },
            };

            // TODO make the diagnostics serializable without requiring the mutex to be locked
            break :blk try std.json.Stringify.valueAlloc(collection.allocator, notification, .{ .emit_null_optional_fields = false });
        };
        defer collection.allocator.free(json_message);

        const old_cancel_protect = io.swapCancelProtection(.blocked);
        defer _ = io.swapCancelProtection(old_cancel_protect);

        try transport.writeJsonMessageUncancelable(io, json_message);
    }
}

fn collectLspDiagnosticsForDocument(
    collection: *DiagnosticsCollection,
    document_uri: []const u8,
    offset_encoding: offsets.Encoding,
    arena: std.mem.Allocator,
    diagnostics: *std.ArrayList(lsp.types.Diagnostic),
) error{OutOfMemory}!void {
    for (collection.tag_set.values()) |entry| {
        if (entry.diagnostics_set.get(document_uri)) |per_document| {
            try diagnostics.appendSlice(arena, per_document.diagnostics);

            try convertErrorBundleToLSPDiangostics(
                per_document.error_bundle,
                null,
                document_uri,
                offset_encoding,
                arena,
                diagnostics,
                true,
            );
        }

        try convertErrorBundleToLSPDiangostics(
            entry.error_bundle,
            entry.error_bundle_src_base_path,
            document_uri,
            offset_encoding,
            arena,
            diagnostics,
            false,
        );
    }
}

pub const collectLspDiagnosticsForDocumentTesting = if (@import("builtin").is_test) collectLspDiagnosticsForDocument else {};

fn convertErrorBundleToLSPDiangostics(
    eb: std.zig.ErrorBundle,
    error_bundle_src_base_path: ?[]const u8,
    document_uri: []const u8,
    offset_encoding: offsets.Encoding,
    arena: std.mem.Allocator,
    diagnostics: *std.ArrayList(lsp.types.Diagnostic),
    is_single_document: bool,
) error{OutOfMemory}!void {
    if (eb.errorMessageCount() == 0) return; // `getMessages` can't be called on an empty ErrorBundle
    for (eb.getMessages()) |msg_index| {
        const err = eb.getErrorMessage(msg_index);
        if (err.src_loc == .none) continue;

        const src_loc = eb.getSourceLocation(err.src_loc);
        const src_path = eb.nullTerminatedString(src_loc.src_path);

        if (!is_single_document) {
            const uri = try pathToUri(arena, error_bundle_src_base_path, src_path) orelse continue;
            if (!std.mem.eql(u8, document_uri, uri)) continue;
        }

        const src_range = errorBundleSourceLocationToRange(eb, src_loc, offset_encoding);

        const eb_notes = eb.getNotes(msg_index);
        const relatedInformation = if (eb_notes.len == 0) null else blk: {
            const lsp_notes = try arena.alloc(lsp.types.Diagnostic.RelatedInformation, eb_notes.len);
            for (lsp_notes, eb_notes) |*lsp_note, eb_note_index| {
                const eb_note = eb.getErrorMessage(eb_note_index);
                if (eb_note.src_loc == .none) continue;

                const note_src_loc = eb.getSourceLocation(eb_note.src_loc);
                const note_src_path = eb.nullTerminatedString(note_src_loc.src_path);
                const note_src_range = errorBundleSourceLocationToRange(eb, note_src_loc, offset_encoding);

                const note_uri = if (is_single_document)
                    document_uri
                else
                    try pathToUri(arena, error_bundle_src_base_path, note_src_path) orelse continue;

                lsp_note.* = .{
                    .location = .{
                        .uri = note_uri,
                        .range = note_src_range,
                    },
                    .message = eb.nullTerminatedString(eb_note.msg),
                };
            }
            break :blk lsp_notes;
        };

        var tags: std.ArrayList(lsp.types.Diagnostic.Tag) = .empty;

        var message: []const u8 = eb.nullTerminatedString(err.msg);

        if (std.mem.startsWith(u8, message, "unused ")) {
            try tags.append(arena, .Unnecessary);
        }
        if (std.mem.eql(u8, message, "found compile log statement")) {
            message = try std.fmt.allocPrint(arena, "{s}\n\nCompile Log Output:\n{s}", .{ message, eb.getCompileLogOutput() });
        }

        try diagnostics.append(arena, .{
            .range = src_range,
            .severity = .Error,
            .source = "zigscient",
            .message = message,
            .tags = if (tags.items.len != 0) tags.items else null,
            .relatedInformation = relatedInformation,
        });
    }
}

fn errorBundleSourceLocationToRange(
    error_bundle: std.zig.ErrorBundle,
    src_loc: std.zig.ErrorBundle.SourceLocation,
    offset_encoding: offsets.Encoding,
) lsp.types.Range {
    // We assume that the span is inside of the source line
    const source_line_range_utf8: lsp.types.Range = .{
        .start = .{ .line = 0, .character = src_loc.column - (src_loc.span_main - src_loc.span_start) },
        .end = .{ .line = 0, .character = src_loc.column + (src_loc.span_end - src_loc.span_main) },
    };

    if (src_loc.source_line == 0) {
        // Without the source line it is not possible to figure out the precise character value
        // The result will be incorrect if the line contains non-ascii characters
        return .{
            .start = .{ .line = src_loc.line, .character = source_line_range_utf8.start.character },
            .end = .{ .line = src_loc.line, .character = source_line_range_utf8.end.character },
        };
    }

    const source_line = error_bundle.nullTerminatedString(src_loc.source_line);
    const source_line_range = offsets.convertRangeEncoding(source_line, source_line_range_utf8, .@"utf-8", offset_encoding);

    return .{
        .start = .{ .line = src_loc.line, .character = source_line_range.start.character },
        .end = .{ .line = src_loc.line, .character = source_line_range.end.character },
    };
}

test errorBundleSourceLocationToRange {
    var eb = try createTestingErrorBundle(&.{
        .{
            .message = "First Error",
            .source_location = .{
                .src_path = "",
                .line = 2,
                .column = 6,
                .span_start = 14,
                .span_main = 14,
                .span_end = 17,
                .source_line = "const foo = 5",
            },
        },
        .{
            .message = "Second Error",
            .source_location = .{
                .src_path = "",
                .line = 1,
                .column = 4,
                .span_start = 20,
                .span_main = 23,
                .span_end = 25,
                .source_line = null,
            },
        },
    }, "");
    defer eb.deinit(std.testing.allocator);

    const src_loc0 = eb.getSourceLocation(eb.getErrorMessage(eb.getMessages()[0]).src_loc);
    const src_loc1 = eb.getSourceLocation(eb.getErrorMessage(eb.getMessages()[1]).src_loc);

    try std.testing.expectEqual(lsp.types.Range{
        .start = .{ .line = 2, .character = 6 },
        .end = .{ .line = 2, .character = 9 },
    }, errorBundleSourceLocationToRange(eb, src_loc0, .@"utf-8"));

    try std.testing.expectEqual(lsp.types.Range{
        .start = .{ .line = 1, .character = 1 },
        .end = .{ .line = 1, .character = 6 },
    }, errorBundleSourceLocationToRange(eb, src_loc1, .@"utf-8"));
}

test DiagnosticsCollection {
    var arena_allocator: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_allocator.deinit();

    const arena = arena_allocator.allocator();

    var collection: DiagnosticsCollection = .{
        .io = std.testing.io,
        .allocator = std.testing.allocator,
    };
    defer collection.deinit();

    try std.testing.expectEqual(0, collection.outdated_files.count());

    var eb1 = try createTestingErrorBundle(&.{.{ .message = "Living For The City" }}, "");
    defer eb1.deinit(std.testing.allocator);
    var eb2 = try createTestingErrorBundle(&.{.{ .message = "You Haven't Done Nothin'" }}, "");
    defer eb2.deinit(std.testing.allocator);
    var eb3 = try createTestingErrorBundle(&.{.{ .message = "As" }}, "");
    defer eb3.deinit(std.testing.allocator);

    const uri = try URI.fromPath(std.testing.allocator, testing_src_path);
    defer std.testing.allocator.free(uri);

    {
        try collection.pushErrorBundle(.parse, 1, null, eb1);
        try std.testing.expectEqual(1, collection.outdated_files.count());
        try std.testing.expectEqualStrings(uri, collection.outdated_files.keys()[0]);

        var diagnostics: std.ArrayList(lsp.types.Diagnostic) = .empty;
        try collection.collectLspDiagnosticsForDocument(uri, .@"utf-8", arena, &diagnostics);

        try std.testing.expectEqual(1, diagnostics.items.len);
        try std.testing.expectEqual(lsp.types.Diagnostic.Severity.Error, diagnostics.items[0].severity);
        try std.testing.expectEqualStrings("Living For The City", diagnostics.items[0].message);
        try std.testing.expectEqual(null, diagnostics.items[0].relatedInformation);
    }

    {
        try collection.pushErrorBundle(.parse, 0, null, eb2);

        var diagnostics: std.ArrayList(lsp.types.Diagnostic) = .empty;
        try collection.collectLspDiagnosticsForDocument(uri, .@"utf-8", arena, &diagnostics);

        try std.testing.expectEqual(1, diagnostics.items.len);
        try std.testing.expectEqualStrings("Living For The City", diagnostics.items[0].message);
    }

    {
        try collection.pushErrorBundle(.parse, 2, null, eb2);

        var diagnostics: std.ArrayList(lsp.types.Diagnostic) = .empty;
        try collection.collectLspDiagnosticsForDocument(uri, .@"utf-8", arena, &diagnostics);

        try std.testing.expectEqual(1, diagnostics.items.len);
        try std.testing.expectEqualStrings("You Haven't Done Nothin'", diagnostics.items[0].message);
    }

    {
        try collection.pushErrorBundle(.parse, 3, null, .empty);

        var diagnostics: std.ArrayList(lsp.types.Diagnostic) = .empty;
        try collection.collectLspDiagnosticsForDocument(uri, .@"utf-8", arena, &diagnostics);

        try std.testing.expectEqual(0, diagnostics.items.len);
    }

    {
        try collection.pushErrorBundle(@enumFromInt(16), 4, null, eb2);
        try collection.pushErrorBundle(@enumFromInt(17), 4, null, eb3);

        var diagnostics: std.ArrayList(lsp.types.Diagnostic) = .empty;
        try collection.collectLspDiagnosticsForDocument(uri, .@"utf-8", arena, &diagnostics);

        try std.testing.expectEqual(2, diagnostics.items.len);
        try std.testing.expectEqualStrings("You Haven't Done Nothin'", diagnostics.items[0].message);
        try std.testing.expectEqualStrings("As", diagnostics.items[1].message);
    }
}

test "DiagnosticsCollection - compile_log_text" {
    var collection: DiagnosticsCollection = .{
        .io = std.testing.io,
        .allocator = std.testing.allocator,
    };
    defer collection.deinit();

    var eb = try createTestingErrorBundle(&.{.{ .message = "found compile log statement" }}, "@as(comptime_int, 7)\n@as(comptime_int, 13)");
    defer eb.deinit(std.testing.allocator);

    const uri = try URI.fromPath(std.testing.allocator, testing_src_path);
    defer std.testing.allocator.free(uri);

    try collection.pushErrorBundle(.parse, 1, null, eb);
    try std.testing.expectEqual(1, collection.outdated_files.count());
    try std.testing.expectEqualStrings(uri, collection.outdated_files.keys()[0]);

    var arena_allocator: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_allocator.deinit();

    const arena = arena_allocator.allocator();

    var diagnostics: std.ArrayListUnmanaged(lsp.types.Diagnostic) = .empty;
    try collection.collectLspDiagnosticsForDocument(uri, .@"utf-8", arena, &diagnostics);

    try std.testing.expectEqual(1, diagnostics.items.len);
    try std.testing.expectEqual(lsp.types.Diagnostic.Severity.Error, diagnostics.items[0].severity);
    try std.testing.expectEqualStrings(
        \\found compile log statement
        \\
        \\Compile Log Output:
        \\@as(comptime_int, 7)
        \\@as(comptime_int, 13)
    , diagnostics.items[0].message);
    try std.testing.expectEqual(null, diagnostics.items[0].relatedInformation);
}

const testing_src_path = switch (@import("builtin").os.tag) {
    .windows => "C:\\sample.zig",
    else => "/sample.zig",
};

fn createTestingErrorBundle(
    messages: []const struct {
        message: []const u8,
        count: u32 = 1,
        source_location: struct {
            src_path: []const u8,
            line: u32,
            column: u32,
            span_start: u32,
            span_main: u32,
            span_end: u32,
            source_line: ?[]const u8,
        } = .{ .src_path = testing_src_path, .line = 0, .column = 0, .span_start = 0, .span_main = 0, .span_end = 0, .source_line = "" },
    },
    compile_log_text: []const u8,
) error{OutOfMemory}!std.zig.ErrorBundle {
    var eb: std.zig.ErrorBundle.Wip = undefined;
    try eb.init(std.testing.allocator);
    errdefer eb.deinit();

    for (messages) |msg| {
        try eb.addRootErrorMessage(.{
            .msg = try eb.addString(msg.message),
            .count = msg.count,
            .src_loc = try eb.addSourceLocation(.{
                .src_path = try eb.addString(msg.source_location.src_path),
                .line = msg.source_location.line,
                .column = msg.source_location.column,
                .span_start = msg.source_location.span_start,
                .span_main = msg.source_location.span_main,
                .span_end = msg.source_location.span_end,
                .source_line = if (msg.source_location.source_line) |source_line| try eb.addString(source_line) else 0,
            }),
        });
    }

    return eb.toOwnedBundle(compile_log_text);
}

// --- The following functions borrowed from std.zig.ErrorBundle

const ErrorBundle = std.zig.ErrorBundle;

/// Returns the requested data, as well as the new index which is at the start of the
/// trailers for the object.
fn errbExtraData(eb: ErrorBundle, comptime T: type, index: usize) struct { data: T, end: usize } {
    const MessageIndex = ErrorBundle.MessageIndex;
    const SourceLocationIndex = ErrorBundle.SourceLocationIndex;
    const field_names = @typeInfo(T).@"struct".field_names;
    const field_types = @typeInfo(T).@"struct".field_types;
    var i: usize = index;
    var result: T = undefined;
    inline for (field_names, field_types) |field_name, field_type| {
        @field(result, field_name) = switch (field_type) {
            u32 => eb.extra[i],
            MessageIndex => @as(MessageIndex, @enumFromInt(eb.extra[i])),
            SourceLocationIndex => @as(SourceLocationIndex, @enumFromInt(eb.extra[i])),
            else => @compileError("bad field type"),
        };
        i += 1;
    }
    return .{
        .data = result,
        .end = i,
    };
}

fn addOtherSourceLocation(
    wip: *ErrorBundle.Wip,
    other: ErrorBundle,
    index: ErrorBundle.SourceLocationIndex,
) !ErrorBundle.SourceLocationIndex {
    if (index == .none) return .none;
    const other_sl = other.getSourceLocation(index);

    var ref_traces: std.ArrayList(ErrorBundle.ReferenceTrace) = .empty;
    defer ref_traces.deinit(wip.gpa);

    if (other_sl.reference_trace_len > 0) {
        var ref_index = errbExtraData(other, ErrorBundle.SourceLocation, @intFromEnum(index)).end;
        for (0..other_sl.reference_trace_len) |_| {
            const other_ref_trace_ed = errbExtraData(other, ErrorBundle.ReferenceTrace, ref_index);
            const other_ref_trace = other_ref_trace_ed.data;
            ref_index = other_ref_trace_ed.end;

            const ref_trace: ErrorBundle.ReferenceTrace = if (other_ref_trace.src_loc == .none) .{
                // sentinel ReferenceTrace does not store a string index in decl_name
                .decl_name = other_ref_trace.decl_name,
                .src_loc = .none,
            } else .{
                .decl_name = try wip.addString(other.nullTerminatedString(other_ref_trace.decl_name)),
                .src_loc = try addOtherSourceLocation(wip, other, other_ref_trace.src_loc),
            };
            try ref_traces.append(wip.gpa, ref_trace);
        }
    }

    const src_loc = try wip.addSourceLocation(.{
        .src_path = try wip.addString(other.nullTerminatedString(other_sl.src_path)),
        .line = other_sl.line,
        .column = other_sl.column,
        .span_start = other_sl.span_start,
        .span_main = other_sl.span_main,
        .span_end = other_sl.span_end,
        .source_line = if (other_sl.source_line != 0)
            try wip.addString(other.nullTerminatedString(other_sl.source_line))
        else
            0,
        .reference_trace_len = other_sl.reference_trace_len,
    });

    for (ref_traces.items) |ref_trace| {
        try wip.addReferenceTrace(ref_trace);
    }

    return src_loc;
}

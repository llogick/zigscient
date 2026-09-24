//! Implementation of [`textDocument/hover`](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_hover)

const std = @import("std");
const Ast = std.zig.Ast;

pub const compiler = @import("compiler");
pub const Compilation = compiler.Compilation;

const Aira = @import("../Aira.zig");

const ast = @import("../ast.zig");
const types = @import("lsp").types;
const offsets = @import("../offsets.zig");
const tracy = @import("tracy");

const Analyser = @import("../analysis.zig");
const DocumentStore = @import("../DocumentStore.zig");
const uri = @import("../uri.zig");

const builtins_data = @import("version_data");

const Builder = struct {
    ds: *DocumentStore,
    asta: *Analyser,
    zdoc: *DocumentStore.Handle,
    markup_kind: types.MarkupKind,
    offset_encoding: offsets.Encoding,
};

fn hoverSymbol(
    b: *Builder,
    arena: std.mem.Allocator,
    param_decl_handle: Analyser.DeclWithHandle,
) Analyser.Error!?[]const u8 {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    var doc_strings: std.ArrayList([]const u8) = .empty;

    var decl_handle: Analyser.DeclWithHandle = param_decl_handle;
    var maybe_resolved_type = try param_decl_handle.resolveType(b.asta);

    while (true) {
        if (try decl_handle.docComments(arena)) |doc_string| {
            try doc_strings.append(arena, doc_string);
        }
        if (decl_handle.decl != .ast_node) break;
        decl_handle = try b.asta.resolveVarDeclAlias(.{
            .node_handle = .of(decl_handle.decl.ast_node, decl_handle.handle),
            .container_type = decl_handle.container_type,
        }) orelse break;
        maybe_resolved_type = maybe_resolved_type orelse try decl_handle.resolveType(b.asta);
    }

    const tree = &decl_handle.handle.tree;
    const def_str = switch (decl_handle.decl) {
        .ast_node => |node| switch (tree.nodeTag(node)) {
            .global_var_decl,
            .local_var_decl,
            .aligned_var_decl,
            .simple_var_decl,
            => try Analyser.getVariableSignature(
                arena,
                tree,
                tree.fullVarDecl(node).?,
                true,
            ),
            .container_field,
            .container_field_init,
            .container_field_align,
            => Analyser.getContainerFieldSignature(tree, tree.fullContainerField(node).?) orelse return null,
            .fn_proto,
            .fn_proto_multi,
            .fn_proto_one,
            .fn_proto_simple,
            .fn_decl,
            => def: {
                var buf: [1]Ast.Node.Index = undefined;
                const fn_proto = tree.fullFnProto(&buf, node).?;
                if (fn_proto.name_token) |fname_tok| {
                    if (b.ds.getBuildFile(decl_handle.handle.uri)) |build_file| blk: {
                        if (tree.tokens.items(.tag)[fname_tok] != .identifier) break :blk;
                        const name = tree.tokenSlice(fname_tok);
                        if (!std.mem.eql(u8, name, "build")) break :blk;
                        const build_config = build_file.getConfiguration(b.ds.io);
                        defer build_config.release(b.ds.io);
                        var aw: std.Io.Writer.Allocating = .init(arena);
                        errdefer aw.deinit();
                        aw.writer.writeAll("```\n") catch break :blk;
                        const roots_count = build_config.roots.map.count();
                        if (roots_count == 0) {
                            aw.writer.print("No Configuration Information available.\n\n", .{}) catch break :blk;
                        } else if (!(build_config.roots.index < roots_count)) {
                            aw.writer.print("Error: root_id {} is not within range of 0..{}\n\n", .{ build_config.roots.index, roots_count }) catch break :blk;
                        } else {
                            const compile_step = build_config.roots.map.values()[build_config.roots.index];
                            const is_valid_cs_index = build_config.roots.index < roots_count;
                            if (!is_valid_cs_index) {
                                aw.writer.print("Current root_id > roots.len => defaulting to root_id 0\n\nModules:\n\n", .{}) catch break :blk;
                                build_config.roots.index = 0;
                            } else aw.writer.print("### root_id: ```{}, \"{s}\"```\n\n", .{ build_config.roots.index, compile_step.name }) catch break :blk;
                            if (is_valid_cs_index) for (compile_step.mods.items) |mod| {
                                aw.writer.print(" * `{s}` [{s}]({s})\n", .{ mod.name, mod.path, try uri.fromPath(arena, mod.path) }) catch break :blk;
                            };
                            if (build_config.roots.info_file_path) |rifp| aw.writer.print("\n### See [List of all roots]({s}#L{d})\n", .{ try uri.fromPath(arena, rifp), 0 }) catch break :blk;
                        }
                        aw.writer.writeAll("```zig\n\n") catch break :blk;
                        aw.writer.writeAll(Analyser.getFunctionSignature(tree, fn_proto)) catch break :blk;
                        break :def try aw.toOwnedSlice();
                    }
                }
                break :def Analyser.getFunctionSignature(tree, fn_proto);
            },
            else => unreachable,
        },
        .function_parameter => |payload| ast.paramSlice(tree, payload.get(tree).?, false),
        .optional_payload,
        .error_union_payload,
        .error_union_error,
        .for_loop_payload,
        .assign_destructure,
        .switch_payload,
        .switch_inline_tag_payload,
        .label,
        .error_token,
        => tree.tokenSlice(decl_handle.nameToken()),
    };

    return try hoverSymbolResolvedType(
        b,
        arena,
        def_str,
        &doc_strings,
        maybe_resolved_type,
        decl_handle,
    );
}

fn hoverSymbolResolvedType(
    b: *Builder,
    arena: std.mem.Allocator,
    def_str: []const u8,
    doc_strings: *std.ArrayList([]const u8),
    resolved_type_maybe: ?Analyser.Type,
    maybe_decl_handle: ?Analyser.DeclWithHandle,
) Analyser.Error!?[]const u8 {
    var referenced: Analyser.ReferencedType.Set = .empty;
    var resolved_type_strings: std.ArrayList([]const u8) = .empty;
    var has_more = false;

    if (resolved_type_maybe) |resolved_type| {
        if (try resolved_type.docComments(arena)) |doc|
            try doc_strings.append(arena, doc);
        const typeof = try resolved_type.typeOf(b.asta);
        var possible_types: Analyser.Type.ArraySet = .empty;
        has_more = try typeof.getAllTypesWithHandlesArraySet(b.asta, &possible_types);
        for (possible_types.keys()) |ty| {
            try resolved_type_strings.append(
                arena,
                try ty.stringifyTypeVal(b.asta, .{
                    .referenced = &referenced,
                    .truncate_container_decls = possible_types.count() > 1,
                }),
            );
        }
    }

    if (maybe_decl_handle != null) interned: {
        const node = switch (maybe_decl_handle.?.decl) {
            .ast_node => |n| n,
            .assign_destructure => |a| a.getVarDeclNode(&maybe_decl_handle.?.handle.tree),
            else => break :interned,
        };
        var aira: Aira = try Aira.init(b.ds, maybe_decl_handle.?.handle, node) orelse break :interned;
        defer aira.deinit();
        const inst = try aira.resolveNode(node) orelse break :interned;
        var ares = Aira.resolveInst(aira.air, inst) orelse break :interned;
        switch (ares.inst_tag) {
            .alloc,
            .ptr_cast,
            .dbg_var_ptr,
            => ares.ip_index = aira.deref(ares.ip_index) orelse ares.ip_index,
            .call => ares.ip_index = aira.resolveFnRetTy(ares.ip_index) orelse break :interned,
            else => {},
        }
        resolved_type_strings.clearRetainingCapacity();
        const type_slice = try aira.typeSlice(arena, ares.ip_index);
        try resolved_type_strings.append(arena, type_slice);

        ares.ip_index = aira.derefOrUnwrap(ares.ip_index);

        const src_node_info = aira.resolveSrcNode(ares.ip_index);
        if (src_node_info) |_| blk: {
            const zdoc = try b.ds.getOrLoadHandle(src_node_info.?.zdoc_uri) orelse break :blk;
            referenced.clearRetainingCapacity();
            try referenced.put(arena, .of(
                short: {
                    const end = std.mem.find(u8, type_slice, "(") orelse type_slice.len;
                    const bgn = if (std.mem.findLast(u8, type_slice[0..end], ".")) |di| di + 1 else 0;
                    break :short if (bgn < end) type_slice[bgn..end] else type_slice;
                },
                zdoc,
                zdoc.tree.firstToken(src_node_info.?.src_node),
            ), {});
            if (src_node_info.?.is_reified) Aira.dumpFields(arena, aira.active.pt, ares.ip_index, doc_strings);
        }
    }

    const referenced_types: []const Analyser.ReferencedType = referenced.keys();

    return try hoverSymbolResolved(
        arena,
        b.markup_kind,
        doc_strings.items,
        def_str,
        resolved_type_strings.items,
        has_more,
        referenced_types,
    );
}

fn hoverSymbolResolved(
    arena: std.mem.Allocator,
    markup_kind: types.MarkupKind,
    doc_strings: []const []const u8,
    def_str: []const u8,
    resolved_type_strings: []const []const u8,
    has_more: bool,
    referenced_types: []const Analyser.ReferencedType,
) error{OutOfMemory}![]const u8 {
    var output: std.ArrayList(u8) = .empty;

    if (markup_kind == .markdown) {
        try output.print(arena, "```zig\n{s}\n```", .{def_str});
        for (resolved_type_strings) |resolved_type_str|
            try output.print(arena, "\n```zig\n({s})\n```", .{resolved_type_str});
        if (resolved_type_strings.len == 0)
            try output.appendSlice(arena, "\n```zig\n(unknown)\n```");
        if (has_more)
            try output.print(arena, "\n```txt\n(...)\n```", .{});
        if (referenced_types.len > 0)
            try output.print(arena, "\n\n" ++ "Go to ", .{});
        for (referenced_types, 0..) |ref, index| {
            if (index > 0)
                try output.print(arena, " | ", .{});
            const source_index = ref.handle.tree.tokenStart(ref.token);
            const line = 1 + std.mem.count(u8, ref.handle.tree.source[0..source_index], "\n");
            try output.print(arena, "[{s}]({s}#L{d})", .{ ref.str, ref.handle.uri, line });
        }
    } else {
        try output.print(arena, "{s}", .{def_str});
        for (resolved_type_strings) |resolved_type_str|
            try output.print(arena, "\n({s})", .{resolved_type_str});
        if (resolved_type_strings.len == 0)
            try output.appendSlice(arena, "\n(unknown)");
        if (has_more)
            try output.print(arena, "\n(...)", .{});
    }

    if (doc_strings.len > 0) {
        try output.appendSlice(arena, "\n\n");
        for (doc_strings, 0..) |doc, i| {
            try output.appendSlice(arena, doc);
            if (i != doc_strings.len - 1) try output.appendSlice(arena, "\n");
        }
    }

    return output.items;
}

fn hoverDefinitionLabel(
    b: *Builder,
    arena: std.mem.Allocator,
    pos_index: usize,
    loc: offsets.Loc,
) Analyser.Error!?types.Hover {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const name = offsets.locToSlice(b.zdoc.tree.source, loc);
    const decl = (try Analyser.lookupLabel(b.zdoc, name, pos_index)) orelse return null;

    return .{
        .contents = .{
            .markup_content = .{
                .kind = b.markup_kind,
                .value = (try hoverSymbol(b, arena, decl)) orelse return null,
            },
        },
        .range = offsets.locToRange(b.zdoc.tree.source, loc, b.offset_encoding),
    };
}

fn hoverDefinitionBuiltin(
    b: *Builder,
    arena: std.mem.Allocator,
    name_loc: offsets.Loc,
) error{OutOfMemory}!?types.Hover {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const name = offsets.locToSlice(b.zdoc.tree.source, name_loc);

    var contents: std.ArrayList(u8) = .empty;

    const builtin = builtins_data.builtins.get(name) orelse return null;
    const signature = try Analyser.renderBuiltinFunctionSignature(
        arena,
        name,
        builtin,
        builtin.parameters.len > 3,
    );

    switch (b.markup_kind) {
        .plaintext, .unknown_value => {
            try contents.print(arena,
                \\{s}
                \\{s}
            , .{ signature, builtin.documentation });
        },
        .markdown => {
            try contents.print(arena,
                \\```zig
                \\{s}
                \\```
                \\{s}
            , .{ signature, builtin.documentation });
        },
    }

    return .{
        .contents = .{
            .markup_content = .{
                .kind = b.markup_kind,
                .value = contents.items,
            },
        },
        .range = offsets.locToRange(b.zdoc.tree.source, name_loc, b.offset_encoding),
    };
}

fn hoverDefinitionGlobal(
    b: *Builder,
    arena: std.mem.Allocator,
    source_index: usize,
) Analyser.Error!?types.Hover {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const name_token, const name_loc = offsets.identifierTokenAndLocFromIndex(&b.zdoc.tree, source_index) orelse return null;
    const name = offsets.locToSlice(b.zdoc.tree.source, name_loc);
    const hover_text = blk: {
        const is_escaped_identifier = b.zdoc.tree.source[b.zdoc.tree.tokenStart(name_token)] == '@';
        if (!is_escaped_identifier) {
            if (std.mem.eql(u8, name, "_")) return null;
            if (try b.asta.resolvePrimitive(name)) |ip_index| {
                const resolved_type_str = try std.fmt.allocPrint(arena, "{f}", .{b.asta.ip.typeOf(ip_index).fmt(b.asta.ip)});
                break :blk try hoverSymbolResolved(arena, b.markup_kind, &.{}, name, &.{resolved_type_str}, false, &.{});
            }
        }
        const decl = (try b.asta.lookupSymbolGlobal(b.zdoc, name, source_index)) orelse return null;
        const basic_info = (try hoverSymbol(b, arena, decl)) orelse return null;

        const nav_info = try lookupNav(b.ds, arena, b.zdoc, source_index, b.markup_kind) orelse "";
        const extra_info = if (nav_info.len != 0) try std.fmt.allocPrint(arena, "{s}" ++ "\n" ++ "{s}", .{ basic_info, nav_info }) else basic_info;

        const air = try getAirSlice(b.ds, arena, decl) orelse "";
        const full_info = if (air.len != 0) try std.fmt.allocPrint(arena, "{s}" ++ "\n" ++ "```\n\n{s}\n```", .{ extra_info, air }) else extra_info;
        break :blk full_info;
    };

    return .{
        .contents = .{
            .markup_content = .{
                .kind = b.markup_kind,
                .value = hover_text,
            },
        },
        .range = offsets.tokenToRange(&b.zdoc.tree, name_token, b.offset_encoding),
    };
}

fn hoverDefinitionStructInit(
    analyser: *Analyser,
    arena: std.mem.Allocator,
    handle: *DocumentStore.Handle,
    source_index: usize,
    markup_kind: types.MarkupKind,
    offset_encoding: offsets.Encoding,
) Analyser.Error!?types.Hover {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const token = offsets.sourceIndexToTokenIndex(&handle.tree, source_index).pickPreferred(&.{.period}, &handle.tree) orelse return null;
    if (token + 1 >= handle.tree.tokens.len) return null;
    if (handle.tree.tokenTag(token + 1) != .l_brace) return null;

    const resolved_type = try analyser.resolveStructInitType(handle, source_index) orelse return null;

    var doc_strings: std.ArrayList([]const u8) = .empty;
    if (try resolved_type.docComments(arena)) |doc|
        try doc_strings.append(arena, doc);

    var referenced: Analyser.ReferencedType.Set = .empty;
    const def_str = try resolved_type.stringifyTypeOf(analyser, .{
        .referenced = &referenced,
        .truncate_container_decls = false,
    });
    const referenced_types: []const Analyser.ReferencedType = referenced.keys();

    return .{
        .contents = .{
            .markup_content = .{
                .kind = markup_kind,
                .value = try hoverSymbolResolved(arena, markup_kind, doc_strings.items, def_str, &.{"type"}, false, referenced_types),
            },
        },
        .range = offsets.tokenToRange(&handle.tree, token, offset_encoding),
    };
}

fn hoverDefinitionEnumLiteral(
    b: *Builder,
    arena: std.mem.Allocator,
    source_index: usize,
) Analyser.Error!?types.Hover {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const name_token, const name_loc = offsets.identifierTokenAndLocFromIndex(&b.zdoc.tree, source_index) orelse {
        return try hoverDefinitionStructInit(b.asta, arena, b.zdoc, source_index, b.markup_kind, b.offset_encoding);
    };
    const name = offsets.locToSlice(b.zdoc.tree.source, name_loc);
    const decl = (try b.asta.getSymbolEnumLiteral(b.zdoc, source_index, name)) orelse return null;

    return .{
        .contents = .{
            .markup_content = .{
                .kind = b.markup_kind,
                .value = (try hoverSymbol(b, arena, decl)) orelse return null,
            },
        },
        .range = offsets.tokenToRange(&b.zdoc.tree, name_token, b.offset_encoding),
    };
}

fn hoverDefinitionFieldAccess(
    b: *Builder,
    arena: std.mem.Allocator,
    source_index: usize,
    loc: offsets.Loc,
) Analyser.Error!?types.Hover {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    var decls: std.ArrayList(Analyser.DeclWithHandle) = .empty;
    var tys: std.ArrayList(Analyser.Type) = .empty;
    const highlight_loc = try b.asta.getSymbolFieldAccessesHighlight(
        arena,
        b.zdoc,
        source_index,
        loc,
        &decls,
        &tys,
    ) orelse return null;

    var content: std.ArrayList([]const u8) = try .initCapacity(arena, decls.items.len + tys.items.len);

    for (decls.items) |decl| {
        content.appendAssumeCapacity(try hoverSymbol(b, arena, decl) orelse continue);
    }
    for (tys.items) |ty| {
        const def_str = offsets.locToSlice(b.zdoc.tree.source, highlight_loc);
        var doc_strings: std.ArrayList([]const u8) = .empty;
        content.appendAssumeCapacity(try hoverSymbolResolvedType(
            b,
            arena,
            def_str,
            &doc_strings,
            ty,
            null,
        ) orelse continue);
    }

    return .{
        .contents = .{ .markup_content = .{
            .kind = b.markup_kind,
            .value = switch (content.items.len) {
                0 => return null,
                1 => content.items[0],
                else => try std.mem.join(arena, "\n\n", content.items),
            },
        } },
        .range = offsets.locToRange(b.zdoc.tree.source, highlight_loc, b.offset_encoding),
    };
}

fn hoverNumberLiteral(
    handle: *DocumentStore.Handle,
    token_index: Ast.TokenIndex,
    arena: std.mem.Allocator,
    markup_kind: types.MarkupKind,
) error{OutOfMemory}!?[]const u8 {
    const tree = &handle.tree;
    // number literals get tokenized separately from their minus sign
    const is_negative = tree.tokenTag(token_index -| 1) == .minus;
    const num_slice = tree.tokenSlice(token_index);
    const number = blk: {
        if (tree.tokenTag(token_index) == .char_literal) {
            switch (std.zig.parseCharLiteral(num_slice)) {
                .success => |value| break :blk value,
                else => return null,
            }
        }
        switch (std.zig.parseNumberLiteral(num_slice)) {
            .int => |value| break :blk value,
            else => return null,
        }
    };

    switch (markup_kind) {
        .markdown => return try std.fmt.allocPrint(arena,
            \\| Base | {[value]s:<[count]} |
            \\| ---- | {[dash]s:-<[count]} |
            \\| BIN  | {[sign]s}0b{[number]b:<[len]} |
            \\| OCT  | {[sign]s}0o{[number]o:<[len]} |
            \\| DEC  | {[sign]s}{[number]d:<[len]}   |
            \\| HEX  | {[sign]s}0x{[number]X:<[len]} |
        , .{
            .sign = if (is_negative) "-" else "",
            .dash = "-",
            .value = "Value",
            .number = number,
            .count = @max(@bitSizeOf(@TypeOf(number)) - @clz(number) + "0x".len + @intFromBool(is_negative), "Value".len),
            .len = @max(@bitSizeOf(@TypeOf(number)) - @clz(number), "Value".len - "0x".len),
        }),
        .plaintext, .unknown_value => return try std.fmt.allocPrint(
            arena,
            \\BIN: {[sign]s}0b{[number]b}
            \\OCT: {[sign]s}0o{[number]o}
            \\DEC: {[sign]s}{[number]d}
            \\HEX: {[sign]s}0x{[number]X}
        ,
            .{ .sign = if (is_negative) "-" else "", .number = number },
        ),
    }
}

fn hoverDefinitionNumberLiteral(
    b: *Builder,
    arena: std.mem.Allocator,
    source_index: usize,
) error{OutOfMemory}!?types.Hover {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const tree = &b.zdoc.tree;
    const token_index = offsets.sourceIndexToTokenIndex(tree, source_index).pickPreferred(&.{ .number_literal, .char_literal }, tree) orelse return null;
    const num_loc = offsets.tokenToLoc(tree, token_index);
    const hover_text = (try hoverNumberLiteral(b.zdoc, token_index, arena, b.markup_kind)) orelse return null;

    return .{
        .contents = .{ .markup_content = .{
            .kind = b.markup_kind,
            .value = hover_text,
        } },
        .range = offsets.locToRange(b.zdoc.tree.source, num_loc, b.offset_encoding),
    };
}

fn hoverKeyword(
    b: *Builder,
    arena: std.mem.Allocator,
    token_index: Ast.TokenIndex,
) error{OutOfMemory}!?types.Hover {
    const tree = &b.zdoc.tree;

    switch (tree.tokenTag(token_index)) {
        else => return null,
        .keyword_enum,
        .keyword_union,
        .keyword_struct,
        => {},
    }

    const nodes = try ast.nodesOverlappingIndex(arena, tree, tree.tokenStart(token_index));
    if (nodes.len == 0) return null;

    b.zdoc.computed_data.lock.lockSharedUncancelable(b.ds.io);
    defer b.zdoc.computed_data.lock.unlockShared(b.ds.io);

    const args = b.zdoc.computed_data.type_decls.get(nodes[0]) orelse return null;
    const build = b.zdoc.computed_data.build orelse return null;

    if (!build.mutex.tryLock()) return null;
    defer build.mutex.unlock(b.ds.io);

    if (!build.has_completed_once) return null;

    const zcu = build.compilation.?.zcu orelse return null;

    const active = zcu.activate(args.tid);
    defer active.deactivate();

    std.debug.assert(switch (active.pt.zcu.intern_pool.indexToKey(args.ty.toIntern())) {
        .enum_type,
        .union_type,
        .struct_type,
        => true,
        else => false,
    });

    var output: std.ArrayList(u8) = .empty;

    if (b.markup_kind == .markdown) {
        try output.print(arena, "```zig\n", .{});
    }

    try output.print(arena,
        \\size: {}
        \\align({t})
        \\fqn: {f}
    , .{
        args.ty.abiSize(active.pt.zcu),
        args.ty.abiAlignment(active.pt.zcu),
        args.ty.fmt(active.pt),
    });

    if (b.markup_kind == .markdown) {
        try output.print(arena, "\n```\n", .{});
    }

    return .{
        .contents = .{ .markup_content = .{
            .kind = b.markup_kind,
            .value = output.items,
        } },
        .range = offsets.locToRange(b.zdoc.tree.source, offsets.tokenToLoc(tree, token_index), b.offset_encoding),
    };
}

pub fn hover(
    ds: *DocumentStore,
    analyser: *Analyser,
    arena: std.mem.Allocator,
    handle: *DocumentStore.Handle,
    source_index: usize,
    markup_kind: types.MarkupKind,
    offset_encoding: offsets.Encoding,
) Analyser.Error!?types.Hover {
    const pos_context = try Analyser.getPositionContext(arena, &handle.tree, source_index, true);

    var b: Builder = .{
        .ds = ds,
        .asta = analyser,
        .zdoc = handle,
        .markup_kind = markup_kind,
        .offset_encoding = offset_encoding,
    };

    const response = switch (pos_context) {
        .builtin => |loc| try hoverDefinitionBuiltin(&b, arena, loc),
        .var_access, .test_doctest_name => try hoverDefinitionGlobal(&b, arena, source_index),
        .field_access => |loc| try hoverDefinitionFieldAccess(&b, arena, source_index, loc),
        .label_access, .label_decl => |loc| try hoverDefinitionLabel(&b, arena, source_index, loc),
        .enum_literal => try hoverDefinitionEnumLiteral(&b, arena, source_index),
        .number_literal, .char_literal => try hoverDefinitionNumberLiteral(&b, arena, source_index),
        .keyword => |token_index| try hoverKeyword(&b, arena, token_index),
        else => null,
    };

    return response;
}

fn lookupNav(
    ds: *DocumentStore,
    arena: std.mem.Allocator,
    handle: *DocumentStore.Handle,
    source_index: usize,
    markup_kind: types.MarkupKind,
    // offset_encoding: offsets.Encoding,
) Analyser.Error!?[]const u8 {
    const tree = &handle.tree;
    // this can't tell the diff between the fn decl and it's first param
    const nodes = try ast.nodesOverlappingIndex(arena, tree, source_index);
    if (nodes.len == 0) return null;
    // for (nodes) |node| std.log.err("ntag: {t}", .{tree.nodeTag(node)});

    handle.computed_data.lock.lockSharedUncancelable(ds.io);
    defer handle.computed_data.lock.unlockShared(ds.io);

    const build = handle.computed_data.build orelse return null;
    const compilation = build.compilation orelse return null;

    if (!compilation.mutex.tryLock()) return null;
    defer compilation.mutex.unlock(ds.io);

    if (!build.has_completed_once) return null;

    const zcu = compilation.zcu orelse return null;

    const ip = zcu.intern_pool;
    const Ip = Compilation.InternPool;
    const Zcu = Compilation.Zcu;

    for (ip.locals, 0..) |_, tid| {
        const navs = ip.getLocalShared(@fromBackingInt(@intCast(tid))).navs.acquire();
        const nav_reprs = navs.view();
        if (nav_reprs.len == 0) continue;
        for (
            nav_reprs.items(.analysis_zir_index),
            // nav_reprs.items(.bits),
            0..,
        ) |opt_zir_index, index| {
            const zir_index = opt_zir_index.unwrap() orelse continue;
            const resolved = zir_index.resolveFull(&ip) orelse continue;
            // std.log.err("got resolved", .{});
            const file = zcu.fileByIndex(resolved.file);
            // std.log.err("got file", .{});
            const file_uri = file.uri_slice orelse continue;
            if (!std.mem.eql(u8, handle.uri, file_uri)) continue;
            // std.log.err("got match uri", .{});
            const zir = file.zir orelse continue;
            // std.log.err("got zir", .{});
            if (zir.instructions.ptrs.len == 0 or zir.instructions.capacity == 0) continue;
            if (zir.instructions.items(.tag)[@backingInt(resolved.inst)] != .declaration) continue;
            const zir_decl = zir.getDeclaration(resolved.inst);
            const src_node = zir_decl.src_node;
            // std.log.err("src_node {} vs nodes[0] {}", .{ src_node, nodes[0] });
            if (src_node != nodes[0]) continue;
            const nav: Ip.Nav = nav_reprs.get(index).unpack();
            const resolved_nav = nav.resolved orelse return null;

            var output: std.ArrayList(u8) = .empty;

            if (markup_kind == .markdown) {
                try output.print(arena, "```zig\n\n", .{});
            }

            const active = zcu.activate(@fromBackingInt(@intCast(tid)));
            defer active.deactivate();

            const val = Zcu.Value.fromInterned(resolved_nav.value);

            try output.print(arena, "fqn: {f}\n", .{nav.fqn.fmt(&ip)});
            try output.print(arena, "val: {f}\n", .{val.fmtValue(active.pt)});
            try output.print(arena, "typ: {f}\n", .{val.typeOf(zcu).fmt(active.pt)});

            if (markup_kind == .markdown) {
                try output.print(arena, "```\n", .{});
            }
            return output.items;
        }
    }
    return null;
}

fn getAirSlice(
    ds: *DocumentStore,
    arena: std.mem.Allocator,
    decl: Analyser.DeclWithHandle,
) Analyser.Error!?[]const u8 {
    decl.handle.computed_data.lock.lockSharedUncancelable(ds.io);
    defer decl.handle.computed_data.lock.unlockShared(ds.io);

    const build = decl.handle.computed_data.build orelse return null;

    if (!build.mutex.tryLock()) return null;
    defer build.mutex.unlock(ds.io);

    if (!build.has_completed_once) return null;

    const tree = &decl.handle.tree;
    var buf: [1]Ast.Node.Index = undefined;
    const node = switch (decl.decl) {
        .ast_node => |node| switch (tree.nodeTag(node)) {
            else => return null,
            .fn_proto,
            .fn_proto_multi,
            .fn_proto_one,
            .fn_proto_simple,
            .fn_decl,
            => tree.fullFnProto(&buf, node).?.ast.proto_node,
        },
        else => return null,
    };

    const args = decl.handle.computed_data.air.get(node) orelse return null;
    const zcu = build.compilation.?.zcu orelse return null;

    const active = zcu.activate(args.tid);
    defer active.deactivate();

    var aw: std.Io.Writer.Allocating = .init(arena);
    errdefer aw.deinit();

    args.air.write(&aw.writer, active.pt, null) catch return null;
    return try aw.toOwnedSlice();
}

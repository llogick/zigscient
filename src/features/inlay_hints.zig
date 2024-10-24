//! Implementation of [`textDocument/inlayHint`](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_inlayHint)

const std = @import("std");
const zig_builtin = @import("builtin");
const Ast = std.zig.Ast;
const log = std.log.scoped(._inlay_hint);

const DocumentStore = @import("../DocumentStore.zig");
const Analyser = @import("../analysis.zig");
const types = @import("lsp").types;
const offsets = @import("../offsets.zig");
const tracy = @import("tracy");
const ast = @import("../ast.zig");
const Config = @import("../Config.zig");

const data = @import("version_data");

/// don't show inlay hints for builtin functions whose parameter names carry no
/// meaningful information or are trivial deductible based on the builtin name.
const excluded_builtins_set = blk: {
    @setEvalBranchQuota(2000);
    break :blk std.StaticStringMap(void).initComptime(.{
        .{"addrSpaceCast"},
        .{"addWithOverflow"},
        .{"alignCast"},
        .{"alignOf"},
        .{"as"},
        // .{"atomicLoad"},
        // .{"atomicRmw"},
        // .{"atomicStore"},
        .{"bitCast"},
        .{"bitOffsetOf"},
        .{"bitSizeOf"},
        .{"branchHint"},
        .{"breakpoint"}, // no parameters
        // .{"mulAdd"},
        .{"byteSwap"},
        .{"bitReverse"},
        .{"offsetOf"},
        // .{"call"},
        .{"cDefine"},
        .{"cImport"},
        .{"cInclude"},
        .{"clz"},
        // .{"cmpxchgStrong"},
        // .{"cmpxchgWeak"},
        // .{"compileError"},
        .{"compileLog"}, // variadic
        .{"constCast"},
        .{"ctz"},
        .{"cUndef"},
        // .{"cVaArg"},
        // .{"cVaCopy"},
        // .{"cVaEnd"},
        // .{"cVaStart"},
        .{"divExact"},
        .{"divFloor"},
        .{"divTrunc"},
        .{"embedFile"},
        .{"enumFromInt"},
        .{"errorFromInt"},
        .{"errorName"},
        .{"errorReturnTrace"}, // no parameters
        .{"errorCast"},
        // .{"export"},
        // .{"extern"},
        // .{"fence"},
        // .{"field"},
        // .{"fieldParentPtr"},
        .{"floatCast"},
        .{"floatFromInt"},
        .{"frameAddress"}, // no parameters
        // .{"hasDecl"},
        // .{"hasField"},
        .{"import"},
        .{"inComptime"}, // no parameters
        .{"intCast"},
        .{"intFromBool"},
        .{"intFromEnum"},
        .{"intFromError"},
        .{"intFromFloat"},
        .{"intFromPtr"},
        .{"max"},
        // .{"memcpy"},
        // .{"memset"},
        .{"min"},
        // .{"wasmMemorySize"},
        // .{"wasmMemoryGrow"},
        .{"mod"},
        .{"mulWithOverflow"},
        // .{"panic"},
        .{"popCount"},
        // .{"prefetch"},
        .{"ptrCast"},
        .{"ptrFromInt"},
        .{"rem"},
        .{"returnAddress"}, // no parameters
        // .{"select"},
        // .{"setAlignStack"},
        .{"setEvalBranchQuota"},
        .{"setFloatMode"},
        .{"setRuntimeSafety"},
        // .{"shlExact"},
        // .{"shlWithOverflow"},
        // .{"shrExact"},
        // .{"shuffle"},
        .{"sizeOf"},
        // .{"splat"},
        // .{"reduce"},
        .{"src"}, // no parameters
        .{"sqrt"},
        .{"sin"},
        .{"cos"},
        .{"tan"},
        .{"exp"},
        .{"exp2"},
        .{"log"},
        .{"log2"},
        .{"log10"},
        .{"abs"},
        .{"floor"},
        .{"ceil"},
        .{"trunc"},
        .{"round"},
        .{"subWithOverflow"},
        .{"tagName"},
        .{"This"}, // no parameters
        .{"trap"}, // no parameters
        .{"truncate"},
        .{"Type"},
        .{"typeInfo"},
        .{"typeName"},
        .{"TypeOf"}, // variadic
        // .{"unionInit"},
        // .{"Vector"},
        .{"volatileCast"},
        // .{"workGroupId"},
        // .{"workGroupSize"},
        // .{"workItemId"},
    });
};

pub const InlayHint = struct {
    index: usize,
    label: []const u8,
    kind: types.InlayHintKind,
    tooltip: ?types.MarkupContent,

    fn lessThan(_: void, lhs: InlayHint, rhs: InlayHint) bool {
        return lhs.index < rhs.index;
    }
};

const Builder = struct {
    arena: std.mem.Allocator,
    analyser: *Analyser,
    config: *const Config,
    handle: *DocumentStore.Handle,
    hints: std.ArrayListUnmanaged(InlayHint) = .{},
    hover_kind: types.MarkupKind,

    fn appendParameterHint(self: *Builder, token_index: Ast.TokenIndex, label: []const u8, tooltip: []const u8, tooltip_noalias: bool, tooltip_comptime: bool) !void {
        // adding tooltip_noalias & tooltip_comptime to InlayHint should be enough
        const tooltip_text = blk: {
            if (tooltip.len == 0) break :blk "";
            const prefix = if (tooltip_noalias) if (tooltip_comptime) "noalias comptime " else "noalias " else if (tooltip_comptime) "comptime " else "";

            if (self.hover_kind == .markdown) {
                break :blk try std.fmt.allocPrint(self.arena, "```zig\n{s}{s}\n```", .{ prefix, tooltip });
            }

            break :blk try std.fmt.allocPrint(self.arena, "{s}{s}", .{ prefix, tooltip });
        };

        try self.hints.append(self.arena, .{
            .index = offsets.tokenToIndex(self.handle.tree, token_index),
            .label = try std.fmt.allocPrint(self.arena, "{s} :", .{label}),
            .kind = .Parameter,
            .tooltip = .{
                .kind = self.hover_kind,
                .value = tooltip_text,
            },
        });
    }

    fn getInlayHints(self: *Builder, offset_encoding: offsets.Encoding) error{OutOfMemory}![]types.InlayHint {
        std.mem.sort(InlayHint, self.hints.items, {}, InlayHint.lessThan);

        var last_index: usize = 0;
        var last_position: types.Position = .{ .line = 0, .character = 0 };

        const converted_hints = try self.arena.alloc(types.InlayHint, self.hints.items.len);
        for (converted_hints, self.hints.items) |*converted_hint, hint| {
            const position = offsets.advancePosition(
                self.handle.tree.source,
                last_position,
                last_index,
                hint.index,
                offset_encoding,
            );
            defer last_index = hint.index;
            defer last_position = position;
            converted_hint.* = types.InlayHint{
                .position = position,
                .label = .{ .string = hint.label },
                .kind = hint.kind,
                .tooltip = if (hint.tooltip) |tooltip| .{ .MarkupContent = tooltip } else null,
                .paddingLeft = false,
                .paddingRight = hint.kind == .Parameter,
            };
        }
        return converted_hints;
    }
};

/// writes parameter hints into `builder.hints`
fn writeCallHint(
    builder: *Builder,
    /// The function call.
    call: Ast.full.Call,
) !void {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const handle = builder.handle;
    const tree = handle.tree;

    const ty = try builder.analyser.resolveTypeOfNode(.{ .node = call.ast.fn_expr, .handle = handle }) orelse return;
    const fn_ty = try builder.analyser.resolveFuncProtoOfCallable(ty) orelse return;
    const fn_node = fn_ty.data.other; // this assumes that function types can only be Ast nodes

    var buffer: [1]Ast.Node.Index = undefined;
    const fn_proto = fn_node.handle.tree.fullFnProto(&buffer, fn_node.node).?;

    var params = try std.ArrayListUnmanaged(Ast.full.FnProto.Param).initCapacity(builder.arena, fn_proto.ast.params.len);
    defer params.deinit(builder.arena);

    const fnh_ast = fn_node.handle.tree;
    const fnh_ast_ttags = fnh_ast.tokens.items(.tag);

    var it = fn_proto.iterate(&fnh_ast);
    while (ast.nextFnParam(&it)) |param| {
        try params.append(builder.arena, param);
    }

    const has_self_param = call.ast.params.len + 1 == params.items.len and
        try builder.analyser.isInstanceCall(handle, call, fn_ty);

    const parameters = params.items[@intFromBool(has_self_param)..];
    const arguments = call.ast.params;
    const min_len = @min(parameters.len, arguments.len);
    for (parameters[0..min_len], arguments[0..min_len]) |param, arg| {
        const hint = if (param.type_expr != 0) blk: {
            const f_tok_i = fnh_ast.firstToken(param.type_expr);
            break :blk switch (fnh_ast_ttags[f_tok_i]) {
                .keyword_struct,
                .keyword_union, // FLLW-UP Consider including `(..)`
                .keyword_enum,
                .keyword_fn,
                => fnh_ast.tokenSlice(f_tok_i),
                else => offsets.nodeToSlice(
                    fnh_ast,
                    param.type_expr,
                ),
            };
        } else offsets.identifierTokenToNameSlice(
            fnh_ast,
            param.name_token orelse continue,
        );

        const no_alias = if (param.comptime_noalias) |t| fnh_ast_ttags[t] == .keyword_noalias or fnh_ast_ttags[t - 1] == .keyword_noalias else false;
        const comp_time = if (param.comptime_noalias) |t| fnh_ast_ttags[t] == .keyword_comptime or fnh_ast_ttags[t - 1] == .keyword_comptime else false;

        const tooltip = if (param.anytype_ellipsis3) |token|
            if (fnh_ast_ttags[token] == .keyword_anytype) "anytype" else ""
        else
            offsets.nodeToSlice(fn_node.handle.tree, param.type_expr);

        try builder.appendParameterHint(
            tree.firstToken(arg),
            hint,
            tooltip,
            no_alias,
            comp_time,
        );
    }
}

/// takes parameter nodes from the ast and function parameter names from `Builtin.arguments` and writes parameter hints into `builder.hints`
fn writeBuiltinHint(builder: *Builder, parameters: []const Ast.Node.Index, arguments: []const []const u8) !void {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const handle = builder.handle;
    const tree = handle.tree;

    const len = @min(arguments.len, parameters.len);
    for (arguments[0..len], parameters[0..len]) |arg, parameter| {
        if (arg.len == 0) continue;

        const colonIndex = std.mem.indexOfScalar(u8, arg, ':');
        const type_expr: []const u8 = if (colonIndex) |index| arg[index + 1 ..] else &.{};

        var maybe_label: ?[]const u8 = null;
        var no_alias = false;
        var comp_time = false;

        var it = std.mem.splitScalar(u8, arg[0 .. colonIndex orelse arg.len], ' ');
        while (it.next()) |item| {
            if (item.len == 0) continue;
            maybe_label = item;

            no_alias = no_alias or std.mem.eql(u8, item, "noalias");
            comp_time = comp_time or std.mem.eql(u8, item, "comptime");
        }

        const label = maybe_label orelse return;
        if (label.len == 0 or std.mem.eql(u8, label, "...")) return;

        try builder.appendParameterHint(
            tree.firstToken(parameter),
            std.mem.trim(u8, type_expr, " \t\r\n"),
            label,
            no_alias,
            comp_time,
        );
    }
}

fn typeStrOfNode(builder: *Builder, node: Ast.Node.Index) !?[]const u8 {
    const resolved_type = try builder.analyser.resolveTypeOfNode(.{ .handle = builder.handle, .node = node }) orelse return null;

    const type_str: []const u8 = try std.fmt.allocPrint(
        builder.arena,
        "{}",
        .{resolved_type.fmt(builder.analyser, .{ .truncate_container_decls = true })},
    );
    if (type_str.len == 0) return null;

    return type_str;
}

fn typeStrOfToken(builder: *Builder, token: Ast.TokenIndex) !?[]const u8 {
    const things = try builder.analyser.lookupSymbolGlobal(
        builder.handle,
        offsets.tokenToSlice(builder.handle.tree, token),
        offsets.tokenToIndex(builder.handle.tree, token),
    ) orelse return null;
    const resolved_type = try things.resolveType(builder.analyser) orelse return null;

    const type_str: []const u8 = try std.fmt.allocPrint(
        builder.arena,
        "{}",
        .{resolved_type.fmt(builder.analyser, .{ .truncate_container_decls = true })},
    );
    if (type_str.len == 0) return null;

    return type_str;
}

/// Append a hint in the form `: hint`
fn appendTypeHintString(builder: *Builder, type_token_index: Ast.TokenIndex, hint: []const u8) !void {
    const name = offsets.tokenToSlice(builder.handle.tree, type_token_index);
    if (std.mem.eql(u8, name, "_")) {
        return;
    }

    try builder.hints.append(builder.arena, .{
        .index = offsets.tokenToLoc(builder.handle.tree, type_token_index).end,
        .label = try std.fmt.allocPrint(builder.arena, ": {s}", .{hint}),
        // TODO: Implement on-hover stuff.
        .tooltip = null,
        .kind = .Type,
    });
}

fn inferAppendTypeStr(builder: *Builder, token: Ast.TokenIndex) !void {
    const type_str = try typeStrOfToken(builder, token) orelse return;
    try appendTypeHintString(builder, token, type_str);
}

fn writeForCaptureHint(builder: *Builder, for_node: Ast.Node.Index) !void {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    const tree = builder.handle.tree;
    const full_for = ast.fullFor(tree, for_node).?;
    const token_tags = tree.tokens.items(.tag);
    var capture_token = full_for.payload_token;
    for (full_for.ast.inputs) |_| {
        if (capture_token + 1 >= tree.tokens.len) break;
        const capture_is_ref = token_tags[capture_token] == .asterisk;
        const name_token = capture_token + @intFromBool(capture_is_ref);
        capture_token = name_token + 2;

        if (try typeStrOfToken(builder, name_token)) |type_str| {
            try appendTypeHintString(builder, name_token, type_str);
        }
    }
}

/// takes a Ast.full.Call (a function call), analysis its function expression, finds its declaration and writes parameter hints into `builder.hints`
fn writeCallNodeHint(builder: *Builder, call: Ast.full.Call) !void {
    const tracy_zone = tracy.trace(@src());
    defer tracy_zone.end();

    if (call.ast.params.len == 0) return;
    if (builder.config.inlay_hints_exclude_single_argument and call.ast.params.len == 1) return;

    const handle = builder.handle;
    const tree = handle.tree;
    const node_tags = tree.nodes.items(.tag);

    switch (node_tags[call.ast.fn_expr]) {
        .identifier, .field_access => try writeCallHint(builder, call),
        else => {
            log.debug("cannot deduce fn expression with tag '{}'", .{node_tags[call.ast.fn_expr]});
        },
    }
}

fn writeNodeInlayHint(
    builder: *Builder,
    tree: Ast,
    node: Ast.Node.Index,
) error{OutOfMemory}!void {
    const node_tags = tree.nodes.items(.tag);
    const main_tokens = tree.nodes.items(.main_token);
    const token_tags = tree.tokens.items(.tag);

    const tag = node_tags[node];

    switch (tag) {
        .call_one,
        .call_one_comma,
        .async_call_one,
        .async_call_one_comma,
        .call,
        .call_comma,
        .async_call,
        .async_call_comma,
        => {
            if (!builder.config.inlay_hints_show_parameter_name) return;

            var params: [1]Ast.Node.Index = undefined;
            const call = tree.fullCall(&params, node).?;
            try writeCallNodeHint(builder, call);
        },
        .local_var_decl,
        .simple_var_decl,
        .global_var_decl,
        .aligned_var_decl,
        => {
            if (!builder.config.inlay_hints_show_variable_type_hints) return;
            const var_decl = builder.handle.tree.fullVarDecl(node).?;
            if (var_decl.ast.type_node != 0) return;

            try appendTypeHintString(
                builder,
                var_decl.ast.mut_token + 1,
                try typeStrOfNode(builder, node) orelse return,
            );
        },
        .assign => {
            const ndata = tree.nodes.items(.data)[node];
            if (ndata.lhs == 0) return;
            const decl = Analyser.DeclWithHandle{ .decl = .{ .ast_node = ndata.lhs }, .handle = builder.handle };
            const ty = try decl.resolveType(builder.analyser) orelse return;
            const type_str: []const u8 = try std.fmt.allocPrint(
                builder.arena,
                "{}",
                .{ty.fmt(builder.analyser, .{ .truncate_container_decls = true })},
            );
            if (type_str.len != 0)
                try appendTypeHintString(
                    builder,
                    tree.lastToken(ndata.lhs),
                    type_str,
                );
        },
        .assign_destructure => {
            if (!builder.config.inlay_hints_show_variable_type_hints) return;
            const dat = tree.nodes.items(.data);
            const lhs_count = tree.extra_data[dat[node].lhs];
            const lhs_exprs = tree.extra_data[dat[node].lhs + 1 ..][0..lhs_count];

            for (lhs_exprs) |lhs_node| {
                const var_decl = tree.fullVarDecl(lhs_node) orelse continue;
                if (var_decl.ast.type_node != 0) continue;
                try inferAppendTypeStr(builder, var_decl.ast.mut_token + 1);
            }
        },
        .if_simple,
        .@"if",
        => {
            if (!builder.config.inlay_hints_show_variable_type_hints) return;
            const full_if = builder.handle.tree.fullIf(node).?;
            if (full_if.payload_token) |token| try inferAppendTypeStr(builder, token);
            if (full_if.error_token) |token| try inferAppendTypeStr(builder, token);
        },
        .for_simple,
        .@"for",
        => {
            if (!builder.config.inlay_hints_show_variable_type_hints) return;
            try writeForCaptureHint(builder, node);
        },
        .while_simple,
        .while_cont,
        .@"while",
        => {
            if (!builder.config.inlay_hints_show_variable_type_hints) return;
            const full_while = builder.handle.tree.fullWhile(node).?;
            if (full_while.payload_token) |token| try inferAppendTypeStr(builder, token);
            if (full_while.error_token) |token| try inferAppendTypeStr(builder, token);
        },
        .switch_case_one,
        .switch_case_inline_one,
        .switch_case,
        .switch_case_inline,
        => {
            if (!builder.config.inlay_hints_show_variable_type_hints) return;
            const full_case = builder.handle.tree.fullSwitchCase(node).?;
            if (full_case.payload_token) |token| try inferAppendTypeStr(builder, token);
        },
        .@"catch" => {
            if (!builder.config.inlay_hints_show_variable_type_hints) return;

            const catch_token = main_tokens[node] + 2;
            if (catch_token < tree.tokens.len and
                token_tags[catch_token - 1] == .pipe and
                token_tags[catch_token] == .identifier)
            {
                try inferAppendTypeStr(builder, catch_token);
            }
        },
        .builtin_call_two,
        .builtin_call_two_comma,
        .builtin_call,
        .builtin_call_comma,
        => {
            if (!builder.config.inlay_hints_show_parameter_name or !builder.config.inlay_hints_show_builtin) return;

            const name = tree.tokenSlice(main_tokens[node]);
            if (name.len < 2 or excluded_builtins_set.has(name[1..])) return;

            var buffer: [2]Ast.Node.Index = undefined;
            const params = ast.builtinCallParams(tree, node, &buffer).?;

            if (params.len == 0) return;

            if (data.builtins.get(name)) |builtin| {
                try writeBuiltinHint(builder, params, builtin.arguments);
            }
        },
        .struct_init_one,
        .struct_init_one_comma,
        .struct_init_dot_two,
        .struct_init_dot_two_comma,
        .struct_init_dot,
        .struct_init_dot_comma,
        .struct_init,
        .struct_init_comma,
        => {
            if (!builder.config.inlay_hints_show_struct_literal_field_type) return;
            var buffer: [2]Ast.Node.Index = undefined;
            const struct_init = tree.fullStructInit(&buffer, node).?;
            for (struct_init.ast.fields) |value_node| { // the node of `value` in `.name = value`
                const name_token = tree.firstToken(value_node) - 2; // math our way two token indexes back to get the `name`
                if (token_tags[name_token] != .identifier) continue; // cause: `.{ .name =<insert dot here> .some`
                const name_loc = offsets.tokenToLoc(tree, name_token);
                const name = offsets.identifierTokenToNameSlice(tree, name_token);
                const decl = (try builder.analyser.getSymbolEnumLiteral(builder.arena, builder.handle, name_loc.start, name)) orelse continue;
                const ty = try decl.resolveType(builder.analyser) orelse continue;
                const type_str: []const u8 = try std.fmt.allocPrint(
                    builder.arena,
                    "{}",
                    .{ty.fmt(builder.analyser, .{ .truncate_container_decls = true })},
                );
                if (type_str.len == 0) continue;
                try appendTypeHintString(
                    builder,
                    name_token,
                    type_str,
                );
            }
        },
        // .field_access => {
        //     const last_tok = tree.lastToken(node);
        //     if (!(last_tok < token_tags.len - 1)) return;
        //     switch (token_tags[last_tok + 1]) {
        //         // Play with these two
        //         // .equal_equal,
        //         // .bang_equal,
        //         => {},
        //         // .equal, // wrong -- see the `.assign` switch case ^
        //         else => return,
        //     }
        //     const decl = Analyser.DeclWithHandle{ .decl = .{ .ast_node = node }, .handle = builder.handle };
        //     const ty = try decl.resolveType(builder.analyser) orelse return;
        //     const type_str: []const u8 = try std.fmt.allocPrint(
        //         builder.arena,
        //         "{}",
        //         .{ty.fmt(builder.analyser, .{ .truncate_container_decls = true })},
        //     );
        //     if (type_str.len != 0)
        //         try appendTypeHintString(
        //             builder,
        //             last_tok,
        //             type_str,
        //         );
        // },
        else => {},
    }
}

/// creates a list of `InlayHint`'s from the given document
/// only parameter hints are created
/// only hints in the given loc are created
pub fn writeRangeInlayHint(
    arena: std.mem.Allocator,
    config: Config,
    analyser: *Analyser,
    handle: *DocumentStore.Handle,
    loc: offsets.Loc,
    hover_kind: types.MarkupKind,
    offset_encoding: offsets.Encoding,
) error{OutOfMemory}![]types.InlayHint {
    var builder: Builder = .{
        .arena = arena,
        .analyser = analyser,
        .config = &config,
        .handle = handle,
        .hover_kind = hover_kind,
    };

    const nodes = try ast.nodesAtLoc(arena, handle.tree, loc);

    for (nodes) |child| {
        try writeNodeInlayHint(&builder, handle.tree, child);
        try ast.iterateChildrenRecursive(handle.tree, child, &builder, error{OutOfMemory}, writeNodeInlayHint);
    }

    return try builder.getInlayHints(offset_encoding);
}

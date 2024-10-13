//! Abstract Syntax Tree for Zig source code.
//! For Zig syntax, the root node is at nodes[0] and contains the list of
//! sub-nodes.
//! For Zon syntax, the root node is at nodes[0] and contains lhs as the node
//! index of the main expression.

/// Reference to externally-owned data.
source: [:0]const u8,

tokens: std.zig.Ast.TokenList.Slice,
/// The root AST node is assumed to be index 0. Since there can be no
/// references to the root node, this means 0 is available to indicate null.
nodes: std.zig.Ast.NodeList.Slice,
extra_data: []std.zig.Ast.Node.Index,
nstates: Parse.States,

errors: []const std.zig.Ast.Error,

pub fn deinit(tree: *Ast, gpa: Allocator) void {
    tree.tokens.deinit(gpa);
    tree.nodes.deinit(gpa);
    gpa.free(tree.extra_data);
    gpa.free(tree.errors);
    tree.nstates.deinit(gpa);
    tree.* = undefined;
}

pub const Mode = enum { zig, zon };

pub const ReusableTokens = union(enum) {
    none,
    full: *std.zig.Ast.TokenList,
    some: struct {
        tokens: *std.zig.Ast.TokenList,
        start_source_index: usize,
    },
};

pub const ReusableNodes = union(enum) {
    none,
    span: struct {
        scratch: *std.ArrayListUnmanaged(std.zig.Ast.Node.Index),
        nstates: *Parse.States,
        nodes: *std.zig.Ast.NodeList,
        xdata: *std.ArrayListUnmanaged(std.zig.Ast.Node.Index),
        // errors: *std.ArrayListUnmanaged(std.zig.Ast.Error),
        start_token_index: u32,
        stop_token_index: u32,
        tokens_delta: *const Delta,
        lowst_node_state: Parse.State,
        start_node_state: Parse.State,
        root_decl_index: usize,
        len_diffs: struct {
            nodes_len: usize,
            xdata_len: usize,
        },
        existing_tree: *std.zig.Ast,
        existing_tree_nstates: *Parse.States,
    },
    some: struct {
        scratch: *std.ArrayListUnmanaged(std.zig.Ast.Node.Index),
        nstates: *Parse.States,
        nodes: *std.zig.Ast.NodeList,
        xdata: *std.ArrayListUnmanaged(std.zig.Ast.Node.Index),
        // errors: *std.ArrayListUnmanaged(std.zig.Ast.Error),
        start_token_index: u32,
    },
};

pub const ReusableData = struct {
    tokens: ReusableTokens = .none,
    nodes: ReusableNodes = .none,
};

pub const Delta = struct {
    op: enum {
        nop,
        add,
        sub,
    },
    value: u32,
};

/// Result should be freed with tree.deinit() when there are
/// no more references to any of the tokens or nodes.
pub fn parse(
    gpa: Allocator,
    source: [:0]const u8,
    mode: Mode,
    reusable_data: *const ReusableData,
) !Ast {
    var tokens, const src_idx = switch (reusable_data.*.tokens) {
        .none => .{ std.zig.Ast.TokenList{}, 0 },
        .full => .{ reusable_data.tokens.full.*, 0 },
        .some => .{ reusable_data.tokens.some.tokens.*, reusable_data.tokens.some.start_source_index },
    };
    errdefer if (reusable_data.nodes != .span) tokens.deinit(gpa);

    if (reusable_data.*.tokens != .full) {
        // Empirically, the zig std lib has an 8:1 ratio of source bytes to token count.
        const estimated_token_count = source.len / 8;
        try tokens.ensureTotalCapacity(gpa, estimated_token_count);

        var tokenizer: std.zig.Tokenizer = .{
            .buffer = source,
            .index = src_idx,
        };

        while (true) {
            const token = tokenizer.next();
            try tokens.append(gpa, .{
                .tag = token.tag,
                .start = @as(u32, @intCast(token.loc.start)),
            });
            if (token.tag == .eof) break;
        }
    }

    const nodes: std.zig.Ast.NodeList, //
    const extra_data: std.ArrayListUnmanaged(std.zig.Ast.Node.Index), //
    const scratch: std.ArrayListUnmanaged(std.zig.Ast.Node.Index), //
    // const errors: std.ArrayListUnmanaged(std.zig.Ast.Error), //
    const nstates: States, const tok_i =
        switch (reusable_data.*.nodes) {
        .none => .{
            .{},
            .{},
            .{},
            // .{},
            .{},
            0,
        },
        .span => |rd| .{
            rd.nodes.*,
            rd.xdata.*,
            rd.scratch.*,
            // rd.errors.*,
            rd.nstates.*,
            rd.start_token_index,
        },
        .some => |rd| .{
            rd.nodes.*,
            rd.xdata.*,
            rd.scratch.*,
            // rd.errors.*,
            rd.nstates.*,
            rd.start_token_index,
        },
    };

    var parser: Parse = .{
        .source = source,
        .gpa = gpa,
        .token_tags = tokens.items(.tag),
        .token_starts = tokens.items(.start),
        .errors = .{},
        .nodes = nodes,
        .extra_data = extra_data,
        .scratch = scratch,
        .nstates = nstates,
        .tok_i = tok_i,
    };
    errdefer if (reusable_data.nodes != .span) parser.nstates.deinit(gpa);
    defer if (reusable_data.nodes != .span) {
        parser.errors.deinit(gpa);
        parser.nodes.deinit(gpa);
        parser.extra_data.deinit(gpa);
        parser.scratch.deinit(gpa);
    };

    // Empirically, Zig source code has a 2:1 ratio of tokens to AST nodes.
    // Make sure at least 1 so we can use appendAssumeCapacity on the root node below.
    const estimated_node_count = (tokens.len + 2) / 2;
    if (tok_i == 0) try parser.nodes.ensureTotalCapacity(gpa, estimated_node_count);

    const base_nodes_len = parser.nodes.len;
    const base_xdata_len = parser.extra_data.items.len;
    std.log.debug("pnl1: {}", .{base_nodes_len});

    const cutoff_tok_i = if (reusable_data.*.nodes == .span) reusable_data.*.nodes.span.stop_token_index else 0;

    switch (mode) {
        .zig => {
            try parser.parseRoot(cutoff_tok_i);
        },
        .zon => try parser.parseZon(),
    }

    const reparsed_nodes_len = parser.nodes.len;
    const reparsed_xdata_len = parser.extra_data.items.len;

    std.log.debug("pnl2: {}", .{reparsed_nodes_len});

    if (reusable_data.*.nodes == .span) {
        // std.log.debug("is span", .{});
        // errdefer std.log.debug("ERROR span", .{});
        const tree = reusable_data.*.nodes.span.existing_tree;
        const mod_node_state = reusable_data.*.nodes.span.start_node_state;
        const existing_root_decls = tree.*.rootDecls();
        const root_decls_len = existing_root_decls.len;

        const cnl = parser.nodes.len;
        const cxl = parser.extra_data.items.len;

        const new_nodes_len = parser.nodes.len + reusable_data.*.nodes.span.len_diffs.nodes_len;
        try parser.nodes.ensureTotalCapacity(gpa, new_nodes_len);
        parser.nodes.len = new_nodes_len;

        const new_xdata_len = parser.extra_data.items.len + reusable_data.*.nodes.span.len_diffs.xdata_len - root_decls_len;
        try parser.extra_data.ensureTotalCapacity(gpa, new_xdata_len);
        parser.extra_data.items.len = new_xdata_len;

        @memcpy(
            parser.nodes.items(.tag)[cnl..],
            tree.*.nodes.items(.tag)[mod_node_state.nodes_len..tree.nodes.items(.tag).len],
        );
        @memcpy(
            parser.nodes.items(.data)[cnl..],
            tree.*.nodes.items(.data)[mod_node_state.nodes_len..tree.nodes.items(.data).len],
        );
        @memcpy(
            parser.nodes.items(.main_token)[cnl..],
            tree.*.nodes.items(.main_token)[mod_node_state.nodes_len..tree.nodes.items(.main_token).len],
        );
        @memcpy(
            parser.extra_data.items[cxl..],
            tree.*.extra_data[mod_node_state.xdata_len .. tree.*.extra_data.len - root_decls_len],
        );

        // XXX If no new nodes look into reusing current tree's datas
        const delta_nodes_len = reparsed_nodes_len - base_nodes_len;
        const num_affected_nodes = mod_node_state.nodes_len - reusable_data.*.nodes.span.lowst_node_state.nodes_len;
        // std.log.debug(
        //     \\
        //     \\delta_nodes_len:    {}
        //     \\num_affected_nodes: {}
        // , .{
        //     delta_nodes_len,
        //     num_affected_nodes,
        // });

        const nodes_delta: Delta = if (delta_nodes_len == num_affected_nodes) .{
            .op = .nop,
            .value = 0,
        } else if (delta_nodes_len > num_affected_nodes) .{
            .op = .add,
            .value = @intCast(delta_nodes_len - num_affected_nodes),
        } else .{
            .op = .sub,
            .value = @intCast(num_affected_nodes - delta_nodes_len),
        };

        // std.log.debug("nodes_delta: {}", .{nodes_delta});

        const delta_xdata_len = reparsed_xdata_len - base_xdata_len;
        const num_affected_xdata = mod_node_state.xdata_len - reusable_data.*.nodes.span.lowst_node_state.xdata_len;

        const xdata_delta: Delta = if (delta_xdata_len == num_affected_xdata) .{
            .op = .nop,
            .value = 0,
        } else if (delta_xdata_len > num_affected_xdata) .{
            .op = .add,
            .value = @intCast(delta_xdata_len - num_affected_xdata),
        } else .{
            .op = .sub,
            .value = @intCast(num_affected_xdata - delta_xdata_len),
        };

        // std.log.debug("xdata_delta: {}", .{xdata_delta});

        // for (parser.extra_data.items[cxl..]) |*xdata| {
        //     if (xdata.* == 0) continue;
        //     xdata.* = switch (nodes_delta.op) {
        //         .add => xdata.* + nodes_delta.value,
        //         .sub => xdata.* - nodes_delta.value,
        //         else => continue,
        //     };
        // }

        // if (nodes_delta.op != .nop or xdata_delta.op != .nop) {
        const tokens_delta = reusable_data.*.nodes.span.tokens_delta.*;
        // const ndatas_idx = switch (nodes_delta.op) {
        //     .add => cnl + nodes_delta.value,
        //     .sub => cnl - nodes_delta.value,
        //     .nop => cnl,
        // };
        const ctx: AdjustDatasContext = .{
            .parser = &parser,
            .ndatas_idx = cnl,
            .nodes_delta = nodes_delta,
            .xdata_delta = xdata_delta,
            .token_delta = tokens_delta,
        };
        ctx.adjustDatas();

        for (existing_root_decls[reusable_data.nodes.span.root_decl_index..]) |erd| {
            // std.log.debug("readding: {}", .{erd});
            const new_idx = switch (nodes_delta.op) {
                .add => erd + nodes_delta.value,
                .sub => erd - nodes_delta.value,
                else => erd,
            };
            // if (!(new_idx < parser.nodes.len)) std.log.debug("===========   AAAAAAAAAAAAAAAAAAAAAA    {}", .{new_idx});
            // std.log.debug("readded: {}", .{new_idx});
            try parser.scratch.append(gpa, new_idx);
            var erd_nstate: Parse.State = reusable_data.nodes.span.existing_tree_nstates.get(erd) orelse {
                // std.log.debug("where's nstate: {}", .{erd});
                continue;
            };
            erd_nstate.nodes_len = switch (ctx.nodes_delta.op) {
                .add => erd_nstate.nodes_len + ctx.nodes_delta.value,
                .sub => erd_nstate.nodes_len - ctx.nodes_delta.value,
                else => erd_nstate.nodes_len,
            };
            erd_nstate.xdata_len = switch (ctx.xdata_delta.op) {
                .add => erd_nstate.xdata_len + ctx.xdata_delta.value,
                .sub => erd_nstate.xdata_len - ctx.xdata_delta.value,
                else => erd_nstate.xdata_len,
            };
            erd_nstate.token_ind = switch (ctx.token_delta.op) {
                .add => erd_nstate.token_ind + ctx.token_delta.value,
                .sub => erd_nstate.token_ind - ctx.token_delta.value,
                else => erd_nstate.token_ind,
            };
            try parser.nstates.put(gpa, new_idx, erd_nstate);
        }

        const root_decls = try parser.listToSpan(parser.scratch.items); // try root_members.toSpan(p);
        parser.nodes.items(.data)[0] = .{
            .lhs = root_decls.start,
            .rhs = root_decls.end,
        };

        parser.scratch.deinit(gpa);

        if (tokens_delta.op != .nop) {
            const mtoks = parser.nodes.items(.main_token);
            for (mtoks[cnl..]) |*mtok| {
                mtok.* = switch (tokens_delta.op) {
                    .add => mtok.* + tokens_delta.value,
                    .sub => mtok.* - tokens_delta.value,
                    else => unreachable,
                };
            }
        }

        // for (tree.errors) |ast_err| {
        //     var adjusted_tok_i = ast_err.token;
        //     ctx.adjustTokenIndex(&adjusted_tok_i);
        //     if (adjusted_tok_i < cutoff_tok_i) continue;
        //     var new_ast_err = ast_err;
        //     new_ast_err.token = adjusted_tok_i;
        //     try parser.errors.append(gpa, new_ast_err);
        // }

        // std.log.debug(
        //     \\
        //     \\t_delta: {any}
        //     \\
        //     \\o_toksl: {any}
        //     \\n_toksl: {any}
        //     \\
        //     \\o_nodes: {any}
        //     \\n_nodes: {any}
        //     \\
        //     \\cxd.len: {any}
        //     \\nxd.len: {any}
        //     \\rds.len: {any}
        //     \\
        //     \\rootdcl: {any}
        //     \\scratch: {any}
        // , .{
        //     reusable_data.nodes.span.tokens_delta,
        //     tree.tokens.items(.tag).len,
        //     parser.token_tags.len,
        //     tree.nodes.items(.tag).len,
        //     parser.nodes.len,
        //     tree.*.extra_data.len,
        //     parser.extra_data.items.len,
        //     root_decls_len,
        //     tree.*.rootDecls(),
        //     parser.extra_data.items[root_decls.start..root_decls.end],
        // });
    }

    // TODO experiment with compacting the MultiArrayList slices here
    return Ast{
        .source = source,
        .tokens = tokens.toOwnedSlice(),
        .nodes = parser.nodes.toOwnedSlice(),
        .extra_data = try parser.extra_data.toOwnedSlice(gpa),
        .nstates = parser.nstates,
        .errors = try parser.errors.toOwnedSlice(gpa),
    };
}

const AdjustDatasContext = struct {
    parser: *Parse,
    ndatas_idx: usize,
    nodes_delta: Delta,
    xdata_delta: Delta,
    token_delta: Delta,

    fn adjustDatas(ctx: *const AdjustDatasContext) void {
        const ntags = ctx.*.parser.nodes.items(.tag);
        const datas = ctx.*.parser.nodes.items(.data);
        const xdata = ctx.*.parser.extra_data.items;
        for (ntags[ctx.*.ndatas_idx..], ctx.*.ndatas_idx..) |tag, idx| {
            switch (tag) { // Keep in sync with Ast.Tag
                // sub_list[lhs...rhs]
                .root => {},
                // `usingnamespace lhs;`. rhs unused. main_token is `usingnamespace`.
                .@"usingnamespace" => ctx.adjustNdataIndex(&datas[idx].lhs),
                // lhs is test name token (must be string literal or identifier), if any.
                // rhs is the body node.
                .test_decl => {
                    ctx.adjustTokenIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // lhs is the index into extra_data.
                // rhs is the initialization expression, if any.
                // main_token is `var` or `const`.
                .global_var_decl => {
                    ctx.adjustXdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);

                    ctx.adjustNdataIndex(&xdata[datas[idx].lhs]);
                },
                // `var a: x align(y) = rhs`
                // lhs is the index into extra_data.
                // main_token is `var` or `const`.
                .local_var_decl => {
                    ctx.adjustXdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);

                    ctx.adjustNdataIndex(&xdata[datas[idx].lhs]);
                },
                // `var a: lhs = rhs`. lhs and rhs may be unused.
                // Can be local or global.
                // main_token is `var` or `const`.
                .simple_var_decl => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `var a align(lhs) = rhs`. lhs and rhs may be unused.
                // Can be local or global.
                // main_token is `var` or `const`.
                .aligned_var_decl => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // lhs is the identifier token payload if any,
                // rhs is the deferred expression.
                .@"errdefer" => {
                    ctx.adjustTokenIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // lhs is unused.
                // rhs is the deferred expression.
                .@"defer" => {
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // lhs catch rhs
                // lhs catch |err| rhs
                // main_token is the `catch` keyword.
                // payload is determined by looking at the next token after the `catch` keyword.
                .@"catch" => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `lhs.a`. main_token is the dot. rhs is the identifier token index.
                .field_access => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustTokenIndex(&datas[idx].rhs);
                },
                // `lhs.?`. main_token is the dot. rhs is the `?` token index.
                .unwrap_optional => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustTokenIndex(&datas[idx].rhs);
                },
                // `lhs == rhs`. main_token is op.
                .equal_equal,
                // `lhs != rhs`. main_token is op.
                .bang_equal,
                // `lhs < rhs`. main_token is op.
                .less_than,
                // `lhs > rhs`. main_token is op.
                .greater_than,
                // `lhs <= rhs`. main_token is op.
                .less_or_equal,
                // `lhs >= rhs`. main_token is op.
                .greater_or_equal,
                // `lhs *= rhs`. main_token is op.
                .assign_mul,
                // `lhs /= rhs`. main_token is op.
                .assign_div,
                // `lhs %= rhs`. main_token is op.
                .assign_mod,
                // `lhs += rhs`. main_token is op.
                .assign_add,
                // `lhs -= rhs`. main_token is op.
                .assign_sub,
                // `lhs <<= rhs`. main_token is op.
                .assign_shl,
                // `lhs <<|= rhs`. main_token is op.
                .assign_shl_sat,
                // `lhs >>= rhs`. main_token is op.
                .assign_shr,
                // `lhs &= rhs`. main_token is op.
                .assign_bit_and,
                // `lhs ^= rhs`. main_token is op.
                .assign_bit_xor,
                // `lhs |= rhs`. main_token is op.
                .assign_bit_or,
                // `lhs *%= rhs`. main_token is op.
                .assign_mul_wrap,
                // `lhs +%= rhs`. main_token is op.
                .assign_add_wrap,
                // `lhs -%= rhs`. main_token is op.
                .assign_sub_wrap,
                // `lhs *|= rhs`. main_token is op.
                .assign_mul_sat,
                // `lhs +|= rhs`. main_token is op.
                .assign_add_sat,
                // `lhs -|= rhs`. main_token is op.
                .assign_sub_sat,
                // `lhs = rhs`. main_token is op.
                .assign,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `a, b, ... = rhs`. main_token is op. lhs is index into `extra_data`
                // of an lhs elem count followed by an array of that many `Node.Index`,
                // with each node having one of the following types:
                // * `global_var_decl`
                // * `local_var_decl`
                // * `simple_var_decl`
                // * `aligned_var_decl`
                // * Any expression node
                // The first 3 types correspond to a `var` or `const` lhs node (note
                // that their `rhs` is always 0). An expression node corresponds to a
                // standard assignment LHS (which must be evaluated as an lvalue).
                // There may be a preceding `comptime` token, which does not create a
                // corresponding `comptime` node so must be manually detected.
                .assign_destructure => {
                    ctx.adjustXdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);

                    const elem_count = xdata[datas[idx].lhs];
                    for (xdata[datas[idx].lhs + 1 ..][0..elem_count]) |*value| ctx.adjustNdataIndex(value);
                },
                // `lhs || rhs`. main_token is the `||`.
                .merge_error_sets,
                // `lhs * rhs`. main_token is the `*`.
                .mul,
                // `lhs / rhs`. main_token is the `/`.
                .div,
                // `lhs % rhs`. main_token is the `%`.
                .mod,
                // `lhs ** rhs`. main_token is the `**`.
                .array_mult,
                // `lhs *% rhs`. main_token is the `*%`.
                .mul_wrap,
                // `lhs *| rhs`. main_token is the `*|`.
                .mul_sat,
                // `lhs + rhs`. main_token is the `+`.
                .add,
                // `lhs - rhs`. main_token is the `-`.
                .sub,
                // `lhs ++ rhs`. main_token is the `++`.
                .array_cat,
                // `lhs +% rhs`. main_token is the `+%`.
                .add_wrap,
                // `lhs -% rhs`. main_token is the `-%`.
                .sub_wrap,
                // `lhs +| rhs`. main_token is the `+|`.
                .add_sat,
                // `lhs -| rhs`. main_token is the `-|`.
                .sub_sat,
                // `lhs << rhs`. main_token is the `<<`.
                .shl,
                // `lhs <<| rhs`. main_token is the `<<|`.
                .shl_sat,
                // `lhs >> rhs`. main_token is the `>>`.
                .shr,
                // `lhs & rhs`. main_token is the `&`.
                .bit_and,
                // `lhs ^ rhs`. main_token is the `^`.
                .bit_xor,
                // `lhs | rhs`. main_token is the `|`.
                .bit_or,
                // `lhs orelse rhs`. main_token is the `orelse`.
                .@"orelse",
                // `lhs and rhs`. main_token is the `and`.
                .bool_and,
                // `lhs or rhs`. main_token is the `or`.
                .bool_or,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `op lhs`. rhs unused. main_token is op.
                .bool_not,
                // `op lhs`. rhs unused. main_token is op.
                .negation,
                // `op lhs`. rhs unused. main_token is op.
                .bit_not,
                // `op lhs`. rhs unused. main_token is op.
                .negation_wrap,
                // `op lhs`. rhs unused. main_token is op.
                .address_of,
                // `op lhs`. rhs unused. main_token is op.
                .@"try",
                // `op lhs`. rhs unused. main_token is op.
                .@"await",
                // `?lhs`. rhs unused. main_token is the `?`.
                .optional_type,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                },
                // `[lhs]rhs`.
                .array_type,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `[lhs:a]b`. `ArrayTypeSentinel[rhs]`.
                .array_type_sentinel => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustXdataIndex(&datas[idx].rhs);

                    const ats: *std.zig.Ast.Node.ArrayTypeSentinel = @ptrCast(&xdata[datas[idx].rhs]);
                    ctx.adjustNdataIndex(&ats.sentinel);
                    ctx.adjustNdataIndex(&ats.elem_type);
                },
                // `[*]align(lhs) rhs`. lhs can be omitted.
                // `*align(lhs) rhs`. lhs can be omitted.
                // `[]rhs`.
                // main_token is the asterisk if a single item pointer or the lbracket
                // if a slice, many-item pointer, or C-pointer
                // main_token might be a ** token, which is shared with a parent/child
                // pointer type and may require special handling.
                .ptr_type_aligned,
                // `[*:lhs]rhs`. lhs can be omitted.
                // `*rhs`.
                // `[:lhs]rhs`.
                // main_token is the asterisk if a single item pointer or the lbracket
                // if a slice, many-item pointer, or C-pointer
                // main_token might be a ** token, which is shared with a parent/child
                // pointer type and may require special handling.
                .ptr_type_sentinel,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // lhs is index into ptr_type. rhs is the element type expression.
                // main_token is the asterisk if a single item pointer or the lbracket
                // if a slice, many-item pointer, or C-pointer
                // main_token might be a ** token, which is shared with a parent/child
                // pointer type and may require special handling.
                .ptr_type => {
                    ctx.adjustXdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);

                    const pt: *std.zig.Ast.Node.PtrType = @ptrCast(&xdata[datas[idx].lhs]);
                    ctx.adjustNdataIndex(&pt.align_node);
                    ctx.adjustNdataIndex(&pt.addrspace_node);
                },
                // lhs is index into ptr_type_bit_range. rhs is the element type expression.
                // main_token is the asterisk if a single item pointer or the lbracket
                // if a slice, many-item pointer, or C-pointer
                // main_token might be a ** token, which is shared with a parent/child
                // pointer type and may require special handling.
                .ptr_type_bit_range,
                => {
                    ctx.adjustXdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);

                    const pt: *std.zig.Ast.Node.PtrTypeBitRange = @ptrCast(&xdata[datas[idx].rhs]);
                    ctx.adjustNdataIndex(&pt.align_node);
                    ctx.adjustNdataIndex(&pt.addrspace_node);
                    ctx.adjustNdataIndex(&pt.bit_range_start);
                    ctx.adjustNdataIndex(&pt.bit_range_end);
                },
                // `lhs[rhs..]`
                // main_token is the lbracket.
                .slice_open => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `lhs[b..c]`. rhs is index into Slice
                // main_token is the lbracket.
                .slice => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustXdataIndex(&datas[idx].rhs);

                    const st: *std.zig.Ast.Node.Slice = @ptrCast(&xdata[datas[idx].rhs]);
                    ctx.adjustNdataIndex(&st.start);
                    ctx.adjustNdataIndex(&st.end);
                },
                // `lhs[b..c :d]`. rhs is index into SliceSentinel. Slice end "c" can be omitted.
                // main_token is the lbracket.
                .slice_sentinel,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustXdataIndex(&datas[idx].rhs);

                    const st: *std.zig.Ast.Node.SliceSentinel = @ptrCast(&xdata[datas[idx].rhs]);
                    ctx.adjustNdataIndex(&st.start);
                    ctx.adjustNdataIndex(&st.end);
                    ctx.adjustNdataIndex(&st.sentinel);
                },
                // `lhs.*`. rhs is unused.
                .deref => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                },
                // `lhs[rhs]`.
                .array_access => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `lhs{rhs}`. rhs can be omitted.
                .array_init_one,
                // `lhs{rhs,}`. rhs can *not* be omitted
                .array_init_one_comma,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `.{lhs, rhs}`. lhs and rhs can be omitted.
                .array_init_dot_two,
                // Same as `array_init_dot_two` except there is known to be a trailing comma
                // before the final rbrace.
                .array_init_dot_two_comma,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `.{a, b}`. `sub_list[lhs..rhs]`.
                .array_init_dot,
                // Same as `array_init_dot` except there is known to be a trailing comma
                // before the final rbrace.
                .array_init_dot_comma,
                => {
                    ctx.adjustXdataIndex(&datas[idx].lhs);
                    ctx.adjustXdataIndex(&datas[idx].rhs);

                    for (xdata[datas[idx].lhs..datas[idx].rhs]) |*value| ctx.adjustNdataIndex(value);
                },
                // `lhs{a, b}`. `sub_range_list[rhs]`. lhs can be omitted which means `.{a, b}`.
                .array_init,
                // Same as `array_init` except there is known to be a trailing comma
                // before the final rbrace.
                .array_init_comma,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustXdataIndex(&datas[idx].rhs);

                    const sr: *std.zig.Ast.Node.SubRange = @ptrCast(&xdata[datas[idx].rhs]);
                    ctx.adjustXdataIndex(&sr.start);
                    ctx.adjustXdataIndex(&sr.end);
                    for (xdata[sr.start..sr.end]) |*value| ctx.adjustNdataIndex(value);
                },
                // `lhs{.a = rhs}`. rhs can be omitted making it empty.
                // main_token is the lbrace.
                .struct_init_one,
                // `lhs{.a = rhs,}`. rhs can *not* be omitted.
                // main_token is the lbrace.
                .struct_init_one_comma,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `.{.a = lhs, .b = rhs}`. lhs and rhs can be omitted.
                // main_token is the lbrace.
                // No trailing comma before the rbrace.
                .struct_init_dot_two,
                // Same as `struct_init_dot_two` except there is known to be a trailing comma
                // before the final rbrace.
                .struct_init_dot_two_comma,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `.{.a = b, .c = d}`. `sub_list[lhs..rhs]`.
                // main_token is the lbrace.
                .struct_init_dot,
                // Same as `struct_init_dot` except there is known to be a trailing comma
                // before the final rbrace.
                .struct_init_dot_comma,
                => {
                    ctx.adjustXdataIndex(&datas[idx].lhs);
                    ctx.adjustXdataIndex(&datas[idx].rhs);

                    for (xdata[datas[idx].lhs..datas[idx].rhs]) |*value| ctx.adjustNdataIndex(value);
                },
                // `lhs{.a = b, .c = d}`. `sub_range_list[rhs]`.
                // lhs can be omitted which means `.{.a = b, .c = d}`.
                // main_token is the lbrace.
                .struct_init,
                // Same as `struct_init` except there is known to be a trailing comma
                // before the final rbrace.
                .struct_init_comma,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustXdataIndex(&datas[idx].rhs);

                    const sr: *std.zig.Ast.Node.SubRange = @ptrCast(&xdata[datas[idx].rhs]);
                    ctx.adjustXdataIndex(&sr.start);
                    ctx.adjustXdataIndex(&sr.end);
                    for (xdata[sr.start..sr.end]) |*value| ctx.adjustNdataIndex(value);
                },
                // `lhs(rhs)`. rhs can be omitted.
                // main_token is the lparen.
                .call_one,
                // `lhs(rhs,)`. rhs can be omitted.
                // main_token is the lparen.
                .call_one_comma,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `async lhs(rhs)`. rhs can be omitted.
                .async_call_one,
                // `async lhs(rhs,)`.
                .async_call_one_comma,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `lhs(a, b, c)`. `SubRange[rhs]`.
                // main_token is the `(`.
                .call,
                // `lhs(a, b, c,)`. `SubRange[rhs]`.
                // main_token is the `(`.
                .call_comma,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustXdataIndex(&datas[idx].rhs);

                    // xdata SR
                    const sr: *std.zig.Ast.Node.SubRange = @ptrCast(&xdata[datas[idx].rhs]);
                    ctx.adjustXdataIndex(&sr.start);
                    ctx.adjustXdataIndex(&sr.end);
                    for (xdata[sr.start..sr.end]) |*value| ctx.adjustNdataIndex(value);
                },
                // `async lhs(a, b, c)`. `SubRange[rhs]`.
                // main_token is the `(`.
                .async_call,
                // `async lhs(a, b, c,)`. `SubRange[rhs]`.
                // main_token is the `(`.
                .async_call_comma,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustXdataIndex(&datas[idx].rhs);

                    // xdata SR
                    const sr: *std.zig.Ast.Node.SubRange = @ptrCast(&xdata[datas[idx].rhs]);
                    ctx.adjustXdataIndex(&sr.start);
                    ctx.adjustXdataIndex(&sr.end);
                    for (xdata[sr.start..sr.end]) |*value| ctx.adjustNdataIndex(value);
                },
                // `switch(lhs) {}`. `SubRange[rhs]`.
                // `main_token` is the identifier of a preceding label, if any; otherwise `switch`.
                .@"switch",
                // Same as switch except there is known to be a trailing comma
                // before the final rbrace
                .switch_comma,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustXdataIndex(&datas[idx].rhs);

                    const sr: *std.zig.Ast.Node.SubRange = @ptrCast(&xdata[datas[idx].rhs]);
                    ctx.adjustXdataIndex(&sr.start);
                    ctx.adjustXdataIndex(&sr.end);
                    for (xdata[sr.start..sr.end]) |*value| ctx.adjustNdataIndex(value);
                },
                // `lhs => rhs`. If lhs is omitted it means `else`.
                // main_token is the `=>`
                .switch_case_one,
                // Same ast `switch_case_one` but the case is inline
                .switch_case_inline_one,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `a, b, c => rhs`. `SubRange[lhs]`.
                // main_token is the `=>`
                .switch_case,
                // Same ast `switch_case` but the case is inline
                .switch_case_inline,
                => {
                    ctx.adjustXdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);

                    // xdata SR
                    const sr: *std.zig.Ast.Node.SubRange = @ptrCast(&xdata[datas[idx].lhs]);
                    ctx.adjustXdataIndex(&sr.start);
                    ctx.adjustXdataIndex(&sr.end);
                    for (xdata[sr.start..sr.end]) |*value| ctx.adjustNdataIndex(value);
                },
                // `lhs...rhs`.
                .switch_range,
                // `while (lhs) rhs`.
                // `while (lhs) |x| rhs`.
                .while_simple,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `while (lhs) : (a) b`. `WhileCont[rhs]`.
                // `while (lhs) : (a) b`. `WhileCont[rhs]`.
                .while_cont => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustXdataIndex(&datas[idx].rhs);

                    const sr: *std.zig.Ast.Node.WhileCont = @ptrCast(&xdata[datas[idx].rhs]);
                    ctx.adjustNdataIndex(&sr.cont_expr);
                    ctx.adjustNdataIndex(&sr.then_expr);
                },
                // `while (lhs) : (a) b else c`. `While[rhs]`.
                // `while (lhs) |x| : (a) b else c`. `While[rhs]`.
                // `while (lhs) |x| : (a) b else |y| c`. `While[rhs]`.
                // The cont expression part `: (a)` may be omitted.
                .@"while" => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustXdataIndex(&datas[idx].rhs);

                    const sr: *std.zig.Ast.Node.While = @ptrCast(&xdata[datas[idx].rhs]);
                    ctx.adjustNdataIndex(&sr.cont_expr);
                    ctx.adjustNdataIndex(&sr.else_expr);
                    ctx.adjustNdataIndex(&sr.then_expr);
                },
                // `for (lhs) rhs`.
                .for_simple => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `for (lhs[0..inputs]) lhs[inputs + 1] else lhs[inputs + 2]`. `For[rhs]`.
                .@"for" => {
                    ctx.adjustXdataIndex(&datas[idx].lhs);

                    const extra = @as(std.zig.Ast.Node.For, @bitCast(datas[idx].rhs));
                    for (xdata[datas[idx].lhs..][0 .. extra.inputs + 1 + @intFromBool(extra.has_else)]) |*value| ctx.adjustNdataIndex(value);
                },
                // `lhs..rhs`. rhs can be omitted.
                .for_range,
                // `if (lhs) rhs`.
                // `if (lhs) |a| rhs`.
                .if_simple,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `if (lhs) a else b`. `If[rhs]`.
                // `if (lhs) |x| a else b`. `If[rhs]`.
                // `if (lhs) |x| a else |y| b`. `If[rhs]`.
                .@"if" => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustXdataIndex(&datas[idx].rhs);

                    const nif: *std.zig.Ast.Node.If = @ptrCast(&xdata[datas[idx].rhs]);
                    ctx.adjustNdataIndex(&nif.else_expr);
                    ctx.adjustNdataIndex(&nif.then_expr);
                },
                // `suspend lhs`. lhs can be omitted. rhs is unused.
                .@"suspend",
                // `resume lhs`. rhs is unused.
                .@"resume",
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                },
                // `continue :lhs rhs`
                // both lhs and rhs may be omitted.
                .@"continue",
                // `break :lhs rhs`
                // both lhs and rhs may be omitted.
                .@"break",
                => {
                    ctx.adjustTokenIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `return lhs`. lhs can be omitted. rhs is unused.
                .@"return" => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                },
                // `fn (a: lhs) rhs`. lhs can be omitted.
                // anytype and ... parameters are omitted from the AST tree.
                // main_token is the `fn` keyword.
                // extern function declarations use this tag.
                .fn_proto_simple => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `fn (a: b, c: d) rhs`. `sub_range_list[lhs]`.
                // anytype and ... parameters are omitted from the AST tree.
                // main_token is the `fn` keyword.
                // extern function declarations use this tag.
                .fn_proto_multi => {
                    ctx.adjustXdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);

                    // xdata SR
                    const sr: *std.zig.Ast.Node.SubRange = @ptrCast(&xdata[datas[idx].lhs]);
                    ctx.adjustXdataIndex(&sr.start);
                    ctx.adjustXdataIndex(&sr.end);
                    for (xdata[sr.start..sr.end]) |*value| ctx.adjustNdataIndex(value);
                },
                // `fn (a: b) addrspace(e) linksection(f) callconv(g) rhs`. `FnProtoOne[lhs]`.
                // zero or one parameters.
                // anytype and ... parameters are omitted from the AST tree.
                // main_token is the `fn` keyword.
                // extern function declarations use this tag.
                .fn_proto_one => {
                    ctx.adjustXdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);

                    const fnp1: *std.zig.Ast.Node.FnProtoOne = @ptrCast(&xdata[datas[idx].lhs]);
                    ctx.adjustNdataIndex(&fnp1.param);
                    ctx.adjustNdataIndex(&fnp1.align_expr);
                    ctx.adjustNdataIndex(&fnp1.addrspace_expr);
                    ctx.adjustNdataIndex(&fnp1.section_expr);
                    ctx.adjustNdataIndex(&fnp1.callconv_expr);
                },
                // `fn (a: b, c: d) addrspace(e) linksection(f) callconv(g) rhs`. `FnProto[lhs]`.
                // anytype and ... parameters are omitted from the AST tree.
                // main_token is the `fn` keyword.
                // extern function declarations use this tag.
                .fn_proto => {
                    ctx.adjustXdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);

                    const fnp: *std.zig.Ast.Node.FnProto = @ptrCast(&xdata[datas[idx].lhs]);
                    ctx.adjustXdataIndex(&fnp.params_start);
                    ctx.adjustXdataIndex(&fnp.params_end);
                    for (xdata[fnp.params_start..fnp.params_end]) |*value| ctx.adjustNdataIndex(value);
                    ctx.adjustNdataIndex(&fnp.align_expr);
                    ctx.adjustNdataIndex(&fnp.addrspace_expr);
                    ctx.adjustNdataIndex(&fnp.section_expr);
                    ctx.adjustNdataIndex(&fnp.callconv_expr);
                },
                // lhs is the fn_proto.
                // rhs is the function body block.
                // Note that extern function declarations use the fn_proto tags rather
                // than this one.
                .fn_decl => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `anyframe->rhs`. main_token is `anyframe`. `lhs` is arrow token index.
                .anyframe_type => {
                    ctx.adjustTokenIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // Both lhs and rhs unused.
                .anyframe_literal,
                // Both lhs and rhs unused.
                .char_literal,
                // Both lhs and rhs unused.
                .number_literal,
                // Both lhs and rhs unused.
                .unreachable_literal,
                // Both lhs and rhs unused.
                // Most identifiers will not have explicit AST nodes, however for expressions
                // which could be one of many different kinds of AST nodes, there will be an
                // identifier AST node for it.
                .identifier,
                => {},
                // lhs is the dot token index, rhs unused, main_token is the identifier.
                .enum_literal => {
                    ctx.adjustTokenIndex(&datas[idx].lhs);
                },
                // main_token is the string literal token
                // Both lhs and rhs unused.
                .string_literal => {},
                // main_token is the first token index (redundant with lhs)
                // lhs is the first token index; rhs is the last token index.
                // Could be a series of multiline_string_literal_line tokens, or a single
                // string_literal token.
                .multiline_string_literal => {
                    ctx.adjustTokenIndex(&datas[idx].lhs);
                    ctx.adjustTokenIndex(&datas[idx].rhs);
                },
                // `(lhs)`. main_token is the `(`; rhs is the token index of the `)`.
                .grouped_expression => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustTokenIndex(&datas[idx].rhs);
                },
                // `@a(lhs, rhs)`. lhs and rhs may be omitted.
                // main_token is the builtin token.
                .builtin_call_two,
                // Same as builtin_call_two but there is known to be a trailing comma before the rparen.
                .builtin_call_two_comma,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `@a(b, c)`. `sub_list[lhs..rhs]`.
                // main_token is the builtin token.
                .builtin_call,
                // Same as builtin_call but there is known to be a trailing comma before the rparen.
                .builtin_call_comma,
                => {
                    ctx.adjustXdataIndex(&datas[idx].lhs);
                    ctx.adjustXdataIndex(&datas[idx].rhs);
                    for (xdata[datas[idx].lhs..datas[idx].rhs]) |*value| ctx.adjustNdataIndex(value);
                },
                // `error{a, b}`.
                // rhs is the rbrace, lhs is unused.
                .error_set_decl => {
                    ctx.adjustTokenIndex(&datas[idx].rhs);
                },
                // `struct {}`, `union {}`, `opaque {}`, `enum {}`. `extra_data[lhs..rhs]`.
                // main_token is `struct`, `union`, `opaque`, `enum` keyword.
                .container_decl,
                // Same as ContainerDecl but there is known to be a trailing comma
                // or semicolon before the rbrace.
                .container_decl_trailing,
                => {
                    ctx.adjustXdataIndex(&datas[idx].lhs);
                    ctx.adjustXdataIndex(&datas[idx].rhs);
                    for (xdata[datas[idx].lhs..datas[idx].rhs]) |*value| ctx.adjustNdataIndex(value);
                },
                // `struct {lhs, rhs}`, `union {lhs, rhs}`, `opaque {lhs, rhs}`, `enum {lhs, rhs}`.
                // lhs or rhs can be omitted.
                // main_token is `struct`, `union`, `opaque`, `enum` keyword.
                .container_decl_two,
                // Same as ContainerDeclTwo except there is known to be a trailing comma
                // or semicolon before the rbrace.
                .container_decl_two_trailing,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `struct(lhs)` / `union(lhs)` / `enum(lhs)`. `SubRange[rhs]`.
                .container_decl_arg,
                // Same as container_decl_arg but there is known to be a trailing
                // comma or semicolon before the rbrace.
                .container_decl_arg_trailing,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustXdataIndex(&datas[idx].rhs);
                    const head = xdata[datas[idx].rhs];
                    const tail = xdata[datas[idx].rhs + 1];
                    for (xdata[head..tail]) |*value| ctx.adjustNdataIndex(value);
                },
                // `union(enum) {}`. `sub_list[lhs..rhs]`.
                // Note that tagged unions with explicitly provided enums are represented
                // by `container_decl_arg`.
                .tagged_union,
                // Same as tagged_union but there is known to be a trailing comma
                // or semicolon before the rbrace.
                .tagged_union_trailing,
                => {
                    ctx.adjustXdataIndex(&datas[idx].lhs);
                    ctx.adjustXdataIndex(&datas[idx].rhs);
                    for (xdata[datas[idx].lhs..datas[idx].rhs]) |*value| ctx.adjustNdataIndex(value);
                },
                // `union(enum) {lhs, rhs}`. lhs or rhs may be omitted.
                // Note that tagged unions with explicitly provided enums are represented
                // by `container_decl_arg`.
                .tagged_union_two,
                // Same as tagged_union_two but there is known to be a trailing comma
                // or semicolon before the rbrace.
                .tagged_union_two_trailing,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `union(enum(lhs)) {}`. `SubRange[rhs]`.
                .tagged_union_enum_tag,
                // Same as tagged_union_enum_tag but there is known to be a trailing comma
                // or semicolon before the rbrace.
                .tagged_union_enum_tag_trailing,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustXdataIndex(&datas[idx].rhs);
                    const head = xdata[datas[idx].rhs];
                    const tail = xdata[datas[idx].rhs + 1];
                    for (xdata[head..tail]) |*value| ctx.adjustNdataIndex(value);
                },
                // `a: lhs = rhs,`. lhs and rhs can be omitted.
                // main_token is the field name identifier.
                // lastToken() does not include the possible trailing comma.
                .container_field_init,
                // `a: lhs align(rhs),`. rhs can be omitted.
                // main_token is the field name identifier.
                // lastToken() does not include the possible trailing comma.
                .container_field_align,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `a: lhs align(c) = d,`. `container_field_list[rhs]`.
                // main_token is the field name identifier.
                // lastToken() does not include the possible trailing comma.
                .container_field => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustXdataIndex(&datas[idx].rhs);

                    const cf: *std.zig.Ast.Node.ContainerField = @ptrCast(&xdata[datas[idx].lhs]);
                    ctx.adjustNdataIndex(&cf.align_expr);
                    ctx.adjustNdataIndex(&cf.value_expr);
                },
                // `comptime lhs`. rhs unused.
                .@"comptime",
                // `nosuspend lhs`. rhs unused.
                .@"nosuspend",
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                },
                // `{lhs rhs}`. rhs or lhs can be omitted.
                // main_token points at the lbrace.
                .block_two,
                // Same as block_two but there is known to be a semicolon before the rbrace.
                .block_two_semicolon,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
                // `{}`. `sub_list[lhs..rhs]`.
                // main_token points at the lbrace.
                .block,
                // Same as block but there is known to be a semicolon before the rbrace.
                .block_semicolon,
                => {
                    ctx.adjustXdataIndex(&datas[idx].lhs);
                    ctx.adjustXdataIndex(&datas[idx].rhs);

                    for (xdata[datas[idx].lhs..datas[idx].rhs]) |*value| ctx.adjustNdataIndex(value);
                },
                // `asm(lhs)`. rhs is the token index of the rparen.
                .asm_simple => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustTokenIndex(&datas[idx].rhs);
                },
                // `asm(lhs, a)`. `Asm[rhs]`.
                .@"asm" => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustXdataIndex(&datas[idx].rhs);

                    const fasm: *std.zig.Ast.Node.Asm = @ptrCast(&xdata[datas[idx].rhs]);
                    ctx.adjustXdataIndex(&fasm.items_start);
                    ctx.adjustXdataIndex(&fasm.items_end);
                    for (xdata[fasm.items_start..fasm.items_end]) |*value| ctx.adjustNdataIndex(value);
                    ctx.adjustTokenIndex(&fasm.rparen);
                },
                // `[a] "b" (c)`. lhs is 0, rhs is token index of the rparen.
                // `[a] "b" (-> lhs)`. rhs is token index of the rparen.
                // main_token is `a`.
                .asm_output,
                // `[a] "b" (lhs)`. rhs is token index of the rparen.
                // main_token is `a`.
                .asm_input,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustTokenIndex(&datas[idx].rhs);
                },
                // `error.a`. lhs is token index of `.`. rhs is token index of `a`.
                .error_value => {
                    ctx.adjustTokenIndex(&datas[idx].lhs);
                    ctx.adjustTokenIndex(&datas[idx].rhs);
                },
                // `lhs!rhs`. main_token is the `!`.
                .error_union,
                => {
                    ctx.adjustNdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);
                },
            }
        }
    }

    fn adjustNdataIndex(ctx: *const AdjustDatasContext, data_idx: *std.zig.Ast.Node.Index) void {
        if (data_idx.* == 0) return;
        data_idx.* = switch (ctx.nodes_delta.op) {
            .add => data_idx.* + ctx.nodes_delta.value,
            .sub => data_idx.* - ctx.nodes_delta.value,
            else => return,
        };
    }

    fn adjustXdataIndex(ctx: *const AdjustDatasContext, data_idx: *std.zig.Ast.Node.Index) void {
        if (data_idx.* == 0) return;
        data_idx.* = switch (ctx.xdata_delta.op) {
            .add => data_idx.* + ctx.xdata_delta.value,
            .sub => data_idx.* - ctx.xdata_delta.value,
            else => return,
        };
    }

    /// Sometimes a node's lhs or rhs is a token idex
    fn adjustTokenIndex(ctx: *const AdjustDatasContext, data_idx: *std.zig.Ast.Node.Index) void {
        if (data_idx.* == 0) return;
        data_idx.* = switch (ctx.token_delta.op) {
            .add => data_idx.* + ctx.token_delta.value,
            .sub => data_idx.* - ctx.token_delta.value,
            else => return,
        };
    }
};

pub fn nodeHasErrors(
    std_ast: std.zig.Ast,
    f_tok_i: std.zig.Ast.TokenIndex,
    l_tok_i: std.zig.Ast.TokenIndex,
) bool {
    for (std_ast.errors) |ast_err| {
        if (ast_err.token < f_tok_i) continue;
        if (ast_err.token < l_tok_i + 1) return true;
    }
    return false;
}

const std = @import("std");
const testing = std.testing;
const Ast = @This();
const Allocator = std.mem.Allocator;
const Parse = @import("Parse.zig");
pub const State = Parse.State;
pub const States = Parse.States;

test {
    testing.refAllDecls(@This());
}

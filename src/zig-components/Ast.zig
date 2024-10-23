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
    // std.log.debug("parse rd: {}", .{reusable_data});
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

    // Preserve to be reused with .nodes = .some
    errdefer {
        if (reusable_data.nodes == .span) reusable_data.nodes.span.scratch.* = parser.scratch;
    }
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

    // XXX technically no longer needed -- remove later on
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
            const new_idx = switch (nodes_delta.op) {
                .add => erd + nodes_delta.value,
                .sub => erd - nodes_delta.value,
                else => erd,
            };
            try parser.scratch.append(gpa, new_idx);
            var erd_nstate: Parse.State = reusable_data.nodes.span.existing_tree_nstates.get(erd) orelse continue;
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

        const root_decls = try parser.listToSpan(parser.scratch.items);
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

                    const gvd: *std.zig.Ast.Node.GlobalVarDecl = @ptrCast(&xdata[datas[idx].lhs]);
                    ctx.adjustNdataIndex(&gvd.type_node);
                    ctx.adjustNdataIndex(&gvd.align_node);
                    ctx.adjustNdataIndex(&gvd.addrspace_node);
                    ctx.adjustNdataIndex(&gvd.section_node);
                },
                // `var a: x align(y) = rhs`
                // lhs is the index into extra_data.
                // main_token is `var` or `const`.
                .local_var_decl => {
                    ctx.adjustXdataIndex(&datas[idx].lhs);
                    ctx.adjustNdataIndex(&datas[idx].rhs);

                    const lvd: *std.zig.Ast.Node.LocalVarDecl = @ptrCast(&xdata[datas[idx].lhs]);
                    ctx.adjustNdataIndex(&lvd.type_node);
                    ctx.adjustNdataIndex(&lvd.align_node);
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

                    const cda: *std.zig.Ast.Node.SubRange = @ptrCast(&xdata[datas[idx].rhs]);
                    ctx.adjustXdataIndex(&cda.start);
                    ctx.adjustXdataIndex(&cda.end);
                    for (xdata[cda.start..cda.end]) |*value| ctx.adjustNdataIndex(value);
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

                    const sr: *std.zig.Ast.Node.SubRange = @ptrCast(&xdata[datas[idx].rhs]);
                    ctx.adjustXdataIndex(&sr.start);
                    ctx.adjustXdataIndex(&sr.end);
                    for (xdata[sr.start..sr.end]) |*value| ctx.adjustNdataIndex(value);
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

                    const cf: *std.zig.Ast.Node.ContainerField = @ptrCast(&xdata[datas[idx].rhs]);
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

fn nodeHasErrors(
    std_ast: *std.zig.Ast,
    f_tok_i: std.zig.Ast.TokenIndex,
    l_tok_i: std.zig.Ast.TokenIndex,
) bool {
    for (std_ast.errors) |ast_err| {
        if (ast_err.token < f_tok_i) continue;
        if (ast_err.token < l_tok_i + 1) return true;
    }
    return false;
}

const TextAndTokenIndices = struct {
    txt_idx_lo: u32,
    txt_idx_hi: u32,
    tok_idx_lo: u32,
    tok_idx_hi: u32,

    pub const default: @This() = .{
        .txt_idx_lo = 0,
        .txt_idx_hi = 0,
        .tok_idx_lo = 0,
        .tok_idx_hi = 0,
    };
};

fn getTextAndTokenIndices(
    std_ast: *StdAst,
    content_changes: *const ContentChanges,
) ?TextAndTokenIndices {
    if (std_ast.source.len < 20 or std_ast.tokens.len < 20) return null;

    var result: TextAndTokenIndices = .default;

    const tok_starts = std_ast.tokens.items(.start);
    const tok_tags = std_ast.tokens.items(.tag);

    var txt_idx_lo = content_changes.idx_lo;
    // Always retokenize whole line(s), because .comment(s)
    while (txt_idx_lo != 0 and std_ast.source[txt_idx_lo] != '\n') txt_idx_lo -= 1;
    while (txt_idx_lo != 0 and std_ast.source[txt_idx_lo] == ' ') txt_idx_lo -= 1;

    result.txt_idx_lo = txt_idx_lo;
    result.tok_idx_lo = offsets.sourceIndexToTokenIndex(std_ast.*, txt_idx_lo);
    // std.log.debug(
    //     \\
    //     \\txt idx lo {}
    //     \\tok idx lo {} tag {}
    // , .{
    //     text_idx_lo,
    //     tok_i,
    //     tok_tags[tok_i],
    // });

    // Doc comments $#^@$
    // Have ample room in case a broken doc comment got tokenized, eg
    // /
    // /! many words that are tokenized as identifiers and also can be valid keywords ...
    // if (tok_i < 100) tok_i = 0 else tok_i -= 50;

    while (result.tok_idx_lo != 0 and switch (tok_tags[result.tok_idx_lo]) {
        .invalid,
        .number_literal,
        => true,
        else => false,
    }) result.tok_idx_lo -= 1;

    // Have at least N bytes of text -- not worth doing .full if less + enforces bounds safety
    // if ((content_changes.idx_hi <= content_changes.idx_lo) or
    //     (content_changes.text.len < 150) or
    //     (tok_tags.len < 100)
    //     // !(content_changes.idx_hi < std_ast.source.len - 20) or
    //     // !(content_changes.idx_hi < (content_changes.text.len - 20)))
    // )
    // {
    //     var tokens = try std_ast.tokens.toMultiArrayList().clone(gpa);
    //     tokens.len = tok_i;

    //     break :reuse .{
    //         .tokens = .{
    //             .some = .{
    //                 .tokens = &tokens,
    //                 .start_source_index = if (tok_i == 0) 0 else tok_starts[tok_i],
    //             },
    //         },
    //         .nodes = .none,
    //     };
    // }

    var txt_idx_hi = content_changes.idx_hi;
    const max_txt_idx = std_ast.source.len - 1;
    result.tok_idx_hi = result.tok_idx_lo;
    if (!(txt_idx_hi < max_txt_idx)) result.tok_idx_hi = @intCast(tok_tags.len - 1) else {
        // Always retokenize whole line(s), because .comment(s)
        while (txt_idx_hi < max_txt_idx and std_ast.source[txt_idx_hi] != '\n') txt_idx_hi += 1;
        while (txt_idx_hi < max_txt_idx and std_ast.source[txt_idx_hi] == ' ') txt_idx_hi += 1;
        // while (text_idx_hi < content_changes.text.len - 1 and switch(content_changes.text[text_idx_hi]) {
        //     ' ', '\n' => true,
        //     else => false,
        // }) text_idx_hi += 1;
        // std.log.debug("affected text span: {s}", .{std_ast.source[text_idx_lo..text_idx_hi]});

        result.tok_idx_hi = offsets.sourceIndexToTokenIndex(std_ast.*, txt_idx_hi);

        // std.log.debug(
        //     \\
        //     \\txt idx hi {}
        //     \\tok idx hi {} tag {}
        //     \\span       {s}
        // , .{
        //     text_idx_hi,
        //     upper_tok_i,
        //     tok_tags[upper_tok_i],
        //     std_ast.source[text_idx_lo..text_idx_hi],
        // });

        // See "Doc comments" above
        // NB: tok_tags.len - 2 to get the .eof in so it gets copied
        // if (upper_tok_i < tok_tags.len - 52) upper_tok_i += 50 else upper_tok_i = @intCast(tok_tags.len - 2);

        while ((result.tok_idx_hi != tok_tags.len - 1) and switch (tok_tags[result.tok_idx_hi]) {
            .invalid,
            .number_literal,
            => true,
            else => false,
        }) result.tok_idx_hi += 1;
    }
    // Always grab one extra token in case the tokens within the affected area got converted to comments
    if (result.tok_idx_hi < tok_tags.len - 2) result.tok_idx_hi += 1;

    result.txt_idx_hi = tok_starts[result.tok_idx_hi];

    return result;
}

fn genTokenList(
    gpa: Allocator,
    std_ast: *StdAst,
    new_source: [:0]const u8,
    indices: *const TextAndTokenIndices,
    tokens_delta: *Delta,
) !StdAst.TokenList {
    const thead_indices = std_ast.tokens.items(.start);
    const ttags = std_ast.tokens.items(.tag);

    var new_tokens = StdAst.TokenList{};
    try new_tokens.ensureTotalCapacity(gpa, ttags.len);
    errdefer new_tokens.deinit(gpa);

    new_tokens.len = indices.tok_idx_lo;
    @memcpy(
        new_tokens.items(.start)[0..indices.tok_idx_lo],
        thead_indices[0..indices.tok_idx_lo],
    );
    @memcpy(
        new_tokens.items(.tag)[0..indices.tok_idx_lo],
        ttags[0..indices.tok_idx_lo],
    );

    // // Add existing tokens
    // for (
    //     tok_starts[0..tok_i],
    //     tok_tags[0..tok_i],
    //     // 0..,
    // ) |
    //     start,
    //     tag,
    //     // idx,
    // | {
    //     // std.log.debug("copying: {}: {}, {}", .{ idx, start, tag });
    //     try new_tokens.append(gpa, .{ .start = start, .tag = tag });
    // }

    const text_delta: struct {
        op: enum {
            add,
            sub,
        },
        value: u32,
    } = if (new_source.len > std_ast.source.len) .{
        .op = .add,
        .value = @intCast(new_source.len - std_ast.source.len),
    } else .{
        .op = .sub,
        .value = @intCast(std_ast.source.len - new_source.len),
    };

    const start_source_index = if (indices.tok_idx_lo == 0) 0 else offsets.tokenToLoc(std_ast.*, indices.tok_idx_lo - 1).end;

    // std.log.debug("ssi: `{c}`", .{text[start_source_index]});

    // std.log.debug(
    //     \\
    //     \\tok.i:{} {}
    //     \\upt.i:{} {}
    //     \\old.len  {}
    //     \\new.len  {}
    //     \\dlt.val  {}
    //     \\low.ind  {}
    //     \\hgh.ind  {}
    // , .{
    //     tok_i,
    //     tok_tags[tok_i],
    //     upper_tok_i,
    //     tok_tags[upper_tok_i],
    //     std_ast.source.len,
    //     text.len,
    //     text_delta.value,
    //     start_source_index,
    //     upper_source_index,
    // });

    var tokenizer: std.zig.Tokenizer = .{
        .buffer = new_source,
        .index = start_source_index,
    };

    // std.log.debug("tokenizer: {}", .{tokenizer.index});

    const reused_tokens_len = new_tokens.len;
    // std;
    while (true) {
        const token = tokenizer.next();
        // if (token.tag == .eof) @panic("brah");
        // std.log.debug("newtok: {}", .{token});
        if ((token.loc.start >= switch (text_delta.op) {
            .add => indices.txt_idx_hi + text_delta.value,
            .sub => indices.txt_idx_hi - text_delta.value,
        })) break;
        // std.log.debug("adding: {}", .{token});
        try new_tokens.append(gpa, .{
            .tag = token.tag,
            .start = @as(u32, @intCast(token.loc.start)),
        });
    }
    const base_affected_tokens_len = indices.tok_idx_hi - indices.tok_idx_lo;
    const new_affected_tokens_len: usize = new_tokens.len - reused_tokens_len;

    tokens_delta.* = if (new_affected_tokens_len == base_affected_tokens_len) .{
        .op = .nop,
        .value = 0,
    } else if (new_affected_tokens_len > base_affected_tokens_len) .{
        .op = .add,
        .value = @intCast(new_affected_tokens_len - base_affected_tokens_len),
    } else .{
        .op = .sub,
        .value = @intCast(base_affected_tokens_len - new_affected_tokens_len),
    };

    // std.log.debug(
    //     \\
    //     \\"tokens_delta: {}"
    //     \\"text   delta  {}"
    // , .{
    //     tokens_delta,
    //     text_delta,
    // });

    const cnti = new_tokens.len;
    const num_to_copy = ttags.len - indices.tok_idx_hi;

    try new_tokens.ensureTotalCapacity(gpa, new_tokens.capacity + num_to_copy);
    new_tokens.len += num_to_copy;
    // std.log.debug(
    //     \\
    //     \\ntl: {} vs ttl {}
    //     \\slc: {} vs slc {}
    // , .{
    //     new_tokens.len,
    //     tok_starts.len,
    //     new_tokens.len - cnti,
    //     tok_tags.len - upper_tok_i,
    // });

    @memcpy(new_tokens.items(.start)[cnti..], thead_indices[indices.tok_idx_hi..]);
    @memcpy(new_tokens.items(.tag)[cnti..], ttags[indices.tok_idx_hi..]);

    // std.log.debug("copied_ttag: {any}", .{new_tokens.items(.tag)[cnti..]});

    for (new_tokens.items(.start)[cnti..]) |*start| {
        // std.log.debug("old start idx: {}", .{start.*});
        const new_start: u32 = switch (text_delta.op) {
            .add => start.* + text_delta.value,
            .sub => start.* - text_delta.value,
        };
        // std.log.debug("new start idx: {}", .{new_start});
        start.* = new_start;
    }

    return new_tokens;
}

// Result should be freed with .deinit() when there are
// no more references to any of the tokens or nodes.
pub fn derive(
    gpa: Allocator,
    std_ast: *StdAst,
    nstates: Parse.States,
    content_changes: *const ContentChanges,
) !Ast {
    return custom_ast: {
        const reusable_data: ReusableData = reuse: {
            const root_decls = std_ast.rootDecls();
            if (root_decls.len < 2) break :reuse .{};

            const indices = getTextAndTokenIndices(
                std_ast,
                content_changes,
            ) orelse break :reuse .{};

            var tokens_delta: Delta = undefined;
            var tokens = try genTokenList(
                gpa,
                std_ast,
                content_changes.text,
                &indices,
                &tokens_delta,
            );
            defer tokens.deinit(gpa);

            var parser: Parse = .{
                .source = content_changes.text,
                .gpa = gpa,
                .token_starts = tokens.items(.start),
                .token_tags = tokens.items(.tag),
                .errors = .empty,
                .nodes = .empty,
                .extra_data = .empty,
                .scratch = .empty,
                .nstates = .empty,
                .tok_i = 0,
            };

            const null_node_state: Parse.State = .zero;

            // std.log.debug("root decls len: {any}", .{std_ast.rootDecls().len});
            // std.log.debug("root decls: {any}", .{std_ast.rootDecls()});
            // std.log.debug("nstates   : {any}", .{nstates.keys()});
            // std.log.debug("std_ast.errors: {any}", .{std_ast.errors});

            for (root_decls, 0..) |root_decl, idx| {
                const f_tok_i = std_ast.firstToken(root_decl);
                const l_tok_i = ast.lastToken(std_ast.*, root_decl);
                const node_loc = offsets.tokensToLoc(std_ast.*, f_tok_i, l_tok_i);
                // std.log.debug(
                //     \\
                //     \\rd.id: {}     f_tok_i {}       l_tok_i {}     has_errors {}
                //     \\rd.loc: {}
                // , .{
                //     idx,
                //     f_tok_i,
                //     l_tok_i,
                //     node_loc,
                //     CustomAst.nodeHasErrors(std_ast, f_tok_i, l_tok_i),
                // });
                if (!nodeHasErrors(std_ast, f_tok_i, l_tok_i) and
                    node_loc.end < indices.txt_idx_lo and
                    idx != root_decls.len - 1 // an error in a 'would be node' at the very end of the document, eg 'test }'
                ) continue;
                const prev_node_idx = if (idx < 2) 0 else idx - 2;

                // std.log.debug(
                //     \\rd1 nidx: {}      f_to_i: {}      l_tok_i: {}
                //     \\prv nidx: {}      f_to_i: x      l_tok_i: x
                // , .{
                //     root_decls[idx],
                //     f_tok_i,
                //     l_tok_i,
                //     root_decls[prev_node_idx],
                // });
                // std.log.debug("1st tok of affn: {}", .{std_ast.firstToken(root_decls[idx])});
                const prev_node_state = if (indices.tok_idx_lo == 0 or prev_node_idx == 0) null_node_state else nstates.get(root_decls[prev_node_idx]) orelse break;
                if (!(prev_node_state.token_ind < tokens.len)) break;

                try parser.nodes.setCapacity(gpa, std_ast.nodes.len);
                errdefer parser.nodes.deinit(gpa);
                parser.nodes.len = prev_node_state.nodes_len;

                const new_nodes_tags = parser.nodes.items(.tag);
                @memcpy(new_nodes_tags, std_ast.nodes.items(.tag)[0..new_nodes_tags.len]);

                const new_nodes_data = parser.nodes.items(.data);
                @memcpy(new_nodes_data, std_ast.nodes.items(.data)[0..new_nodes_data.len]);

                const new_nodes_mtok = parser.nodes.items(.main_token);
                @memcpy(new_nodes_mtok, std_ast.nodes.items(.main_token)[0..new_nodes_mtok.len]);

                try parser.extra_data.ensureUnusedCapacity(gpa, std_ast.extra_data.len);
                errdefer parser.extra_data.deinit(gpa);
                parser.extra_data.items.len = prev_node_state.xdata_len;
                @memcpy(parser.extra_data.items, std_ast.extra_data[0..parser.extra_data.items.len]);

                try parser.scratch.ensureUnusedCapacity(gpa, root_decls.len);
                errdefer parser.scratch.deinit(gpa);

                if (prev_node_state.token_ind != 0) for (root_decls[0 .. prev_node_idx + 1]) |value| parser.scratch.appendAssumeCapacity(value);
                const fallback_scratch_len = parser.scratch.items.len;

                if (prev_node_state.token_ind != 0) for (nstates.keys()) |key| {
                    if (key < root_decls[prev_node_idx + 1]) {
                        try parser.nstates.put(gpa, key, nstates.get(key).?);
                    }
                };
                errdefer parser.nstates.deinit(gpa);

                parser.tok_i = prev_node_state.token_ind;

                reuse_upper_nodes: {
                    if (true) break :reuse_upper_nodes; // XXX DISABLED UNTIL EXTENSIVE TESTING IS DONE
                    if (idx + 2 > root_decls.len) break :reuse_upper_nodes;
                    for (root_decls[idx + 1 ..], idx + 1..) |root_decl2, idx2| {
                        const rd2_first_tok_idx = std_ast.firstToken(root_decl2);
                        const rd2_last_tok_idx = ast.lastToken(std_ast.*, root_decl2);
                        // std.log.debug("rd2tag: {}", .{tok_tags[rd2_first_tok_idx]});
                        // std.log.debug(
                        //     \\
                        //     \\rd2nidx    {}
                        //     \\rd2tokidx  f: {}  l: {}
                        //     \\uppidx    {}
                        //     \\errors    {any}
                        // , .{
                        //     root_decls[idx2],
                        //     rd2_first_tok_idx,
                        //     rd2_last_tok_idx,
                        //     upper_tok_i,
                        //     std_ast.errors,
                        // });

                        if (rd2_first_tok_idx < indices.tok_idx_hi or nodeHasErrors(std_ast, rd2_first_tok_idx, rd2_last_tok_idx)) continue;
                        if (std_ast.errors.len != 0 and (rd2_first_tok_idx < std_ast.errors[std_ast.errors.len - 1].token)) continue;
                        if (idx2 - idx < 2) continue;

                        const mod_node_state = nstates.get(root_decls[idx2 - 1]) orelse break;

                        const stop_token_index = switch (tokens_delta.op) {
                            .add => rd2_first_tok_idx + tokens_delta.value,
                            .sub => rd2_first_tok_idx - tokens_delta.value,
                            else => rd2_first_tok_idx,
                        };

                        // std.log.debug("affected nodes: {any}", .{root_decls[prev_node_idx..idx2]});

                        // std.log.debug(
                        //     \\
                        //     \\rd2_tok_idx    {}
                        //     \\upp_tok_idx    {}
                        //     \\stp_tok_idx    {}
                        //     \\
                        //     \\lo_nde_stat    idx: {}     {}
                        //     \\curr_n_stat    idx: {}     {}
                        //     \\
                        //     \\modf_n_stat    idx: {}     {}
                        // , .{
                        //     rd2_first_tok_idx,
                        //     upper_tok_i,
                        //     stop_token_index,
                        //     prev_node_idx,
                        //     prev_node_state,
                        //     idx2,
                        //     std_ast_nstates.get(root_decls[idx2]) orelse break,
                        //     idx2 - 1,
                        //     mod_node_state,
                        // });

                        const custom_ast = run(
                            &parser,
                            gpa,
                            std_ast,
                            .{ .span = .{
                                .tokens = &tokens,
                                .low_node_state = prev_node_state,
                                .mod_node_state = mod_node_state,
                                .existing_nstates = &nstates,
                                .tokens_delta = &tokens_delta,
                                .root_decl_idx_hi = idx2,
                                .cutoff_tok_i = stop_token_index,
                            } },
                        ) catch |err| switch (err) {
                            error.OvershotCutOff => {
                                // Reset and reuse only the lower portions
                                parser.tok_i = prev_node_state.token_ind;
                                parser.nodes.len = prev_node_state.nodes_len;
                                parser.extra_data.items.len = prev_node_state.xdata_len;
                                parser.scratch.items.len = fallback_scratch_len;
                                parser.nstates.clearRetainingCapacity();
                                for (nstates.keys()) |key| {
                                    if (key < root_decls[prev_node_idx + 1]) {
                                        try parser.nstates.put(gpa, key, nstates.get(key).?);
                                    }
                                }
                                break :reuse_upper_nodes;
                            },
                            else => |e| return e,
                        };
                        parser.scratch.deinit(gpa);
                        return custom_ast;
                    }
                }
                defer parser.scratch.deinit(gpa);
                return run(
                    &parser,
                    gpa,
                    std_ast,
                    .{ .toks = &tokens },
                ) catch |err| switch (err) {
                    error.OutOfMemory => |e| return e,
                    error.OvershotCutOff => unreachable,
                };
            }

            break :reuse .{ // TODO make completions work here
                .tokens = .{
                    .full = &tokens,
                },
                .nodes = .none,
            };
        };

        break :custom_ast parse(
            gpa,
            content_changes.text,
            .zig,
            &reusable_data,
        ) catch |err| switch (err) {
            error.OutOfMemory => |e| return e,
            error.OvershotCutOff => unreachable,
        };
    };
}

const Ast = @This();

const std = @import("std");
const testing = std.testing;
const StdAst = std.zig.Ast;
const Allocator = std.mem.Allocator;

const Parse = @import("Parse.zig");
const ast = @import("../ast.zig");
const offsets = @import("../offsets.zig");
const ContentChanges = @import("../diff.zig").ContentChanges;

pub const State = Parse.State;
pub const States = Parse.States;

test {
    testing.refAllDecls(@This());
}

const ParserRunContext = union(enum) {
    toks: *StdAst.TokenList,
    span: struct {
        tokens: *StdAst.TokenList,
        low_node_state: Parse.State,
        mod_node_state: Parse.State,
        existing_nstates: *const Parse.States,
        tokens_delta: *const Delta,
        root_decl_idx_hi: usize,
        cutoff_tok_i: u32,
    },
};

fn run(
    parser: *Parse,
    gpa: Allocator,
    std_ast: *StdAst,
    run_ctx: ParserRunContext,
) !Ast {
    // Empirically, Zig source code has a 2:1 ratio of tokens to AST nodes.
    // Make sure at least 1 so we can use appendAssumeCapacity on the root node below.
    const estimated_node_count = (parser.token_tags.len + 2) / 2;
    if (parser.tok_i == 0) try parser.nodes.ensureTotalCapacity(gpa, estimated_node_count);

    const base_nodes_len = parser.nodes.len;
    const base_xdata_len = parser.extra_data.items.len;
    std.log.debug("pnl1: {}", .{base_nodes_len});

    const cutoff_tok_i = if (run_ctx == .toks) 0 else run_ctx.span.cutoff_tok_i;

    try parser.parseRoot(cutoff_tok_i);

    const reparsed_nodes_len = parser.nodes.len;
    const reparsed_xdata_len = parser.extra_data.items.len;

    std.log.debug("pnl2: {}", .{reparsed_nodes_len});

    if (run_ctx == .toks) return Ast{
        .source = parser.source,
        .tokens = run_ctx.toks.toOwnedSlice(),
        .nodes = parser.nodes.toOwnedSlice(),
        .extra_data = try parser.extra_data.toOwnedSlice(gpa),
        .nstates = parser.nstates,
        .errors = try parser.errors.toOwnedSlice(gpa),
    };

    const sd = run_ctx.span;

    const tree = std_ast;
    const existing_root_decls = tree.*.rootDecls();
    const root_decls_len = existing_root_decls.len;

    const cnl = parser.nodes.len;
    const cxl = parser.extra_data.items.len;

    const new_nodes_len = parser.nodes.len + (tree.nodes.len - sd.mod_node_state.nodes_len);
    try parser.nodes.ensureTotalCapacity(gpa, new_nodes_len);
    parser.nodes.len = new_nodes_len;

    const new_xdata_len = parser.extra_data.items.len + (tree.extra_data.len - sd.mod_node_state.xdata_len - root_decls_len);
    try parser.extra_data.ensureTotalCapacity(gpa, new_xdata_len);
    parser.extra_data.items.len = new_xdata_len;

    @memcpy(
        parser.nodes.items(.tag)[cnl..],
        tree.*.nodes.items(.tag)[sd.mod_node_state.nodes_len..tree.nodes.items(.tag).len],
    );
    @memcpy(
        parser.nodes.items(.data)[cnl..],
        tree.*.nodes.items(.data)[sd.mod_node_state.nodes_len..tree.nodes.items(.data).len],
    );
    @memcpy(
        parser.nodes.items(.main_token)[cnl..],
        tree.*.nodes.items(.main_token)[sd.mod_node_state.nodes_len..tree.nodes.items(.main_token).len],
    );
    @memcpy(
        parser.extra_data.items[cxl..],
        tree.*.extra_data[sd.mod_node_state.xdata_len .. tree.*.extra_data.len - root_decls_len],
    );

    // XXX If no new nodes look into reusing current tree's datas
    const delta_nodes_len = reparsed_nodes_len - base_nodes_len;
    const num_affected_nodes = sd.mod_node_state.nodes_len - sd.low_node_state.nodes_len;
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
    const num_affected_xdata = sd.mod_node_state.xdata_len - sd.low_node_state.xdata_len;

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

    const ctx: AdjustDatasContext = .{
        .parser = parser,
        .ndatas_idx = cnl,
        .nodes_delta = nodes_delta,
        .xdata_delta = xdata_delta,
        .token_delta = sd.tokens_delta.*,
    };
    ctx.adjustDatas();

    for (existing_root_decls[sd.root_decl_idx_hi..]) |erd| {
        const new_idx = switch (nodes_delta.op) {
            .add => erd + nodes_delta.value,
            .sub => erd - nodes_delta.value,
            else => erd,
        };
        try parser.scratch.append(gpa, new_idx);
        var erd_nstate: Parse.State = sd.existing_nstates.get(erd) orelse continue;

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

    const root_decls = try parser.listToSpan(parser.scratch.items);
    parser.nodes.items(.data)[0] = .{
        .lhs = root_decls.start,
        .rhs = root_decls.end,
    };

    if (sd.tokens_delta.op != .nop) {
        const mtoks = parser.nodes.items(.main_token);
        for (mtoks[cnl..]) |*mtok| {
            mtok.* = switch (sd.tokens_delta.op) {
                .add => mtok.* + sd.tokens_delta.value,
                .sub => mtok.* - sd.tokens_delta.value,
                else => unreachable,
            };
        }
    }

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

    return Ast{
        .source = parser.source,
        .tokens = sd.tokens.toOwnedSlice(),
        .nodes = parser.nodes.toOwnedSlice(),
        .extra_data = try parser.extra_data.toOwnedSlice(gpa),
        .nstates = parser.nstates,
        .errors = try parser.errors.toOwnedSlice(gpa),
    };
}

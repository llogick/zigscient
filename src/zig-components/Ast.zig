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
    full: *std.zig.Ast.NodeList,
    some: struct {
        scratch: *std.ArrayListUnmanaged(std.zig.Ast.Node.Index),
        nstates: *Parse.States,
        nodes: *std.zig.Ast.NodeList,
        xdata: *std.ArrayListUnmanaged(std.zig.Ast.Node.Index),
        start_token_index: u32,
    },
};

pub const ReusableData = struct {
    tokens: ReusableTokens = .none,
    nodes: ReusableNodes = .none,
};

/// Result should be freed with tree.deinit() when there are
/// no more references to any of the tokens or nodes.
pub fn parse(
    gpa: Allocator,
    source: [:0]const u8,
    mode: Mode,
    reusable_data: ReusableData,
) Allocator.Error!Ast {
    var tokens, const src_idx = switch (reusable_data.tokens) {
        .none => .{ std.zig.Ast.TokenList{}, 0 },
        .full => .{ reusable_data.tokens.full.*, 0 },
        .some => .{ reusable_data.tokens.some.tokens.*, reusable_data.tokens.some.start_source_index },
    };
    defer tokens.deinit(gpa);

    if (reusable_data.tokens != .full) {
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
    const nstates: States, const tok_i =
        switch (reusable_data.nodes) {
        .none,
        .full, // TODO
        => .{
            .{},
            .{},
            .{},
            .{},
            0,
        },
        .some => |rd| .{
            rd.nodes.*,
            rd.xdata.*,
            rd.scratch.*,
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
    errdefer parser.nstates.deinit(gpa);
    defer parser.errors.deinit(gpa);
    defer parser.nodes.deinit(gpa);
    defer parser.extra_data.deinit(gpa);
    defer parser.scratch.deinit(gpa);

    // Empirically, Zig source code has a 2:1 ratio of tokens to AST nodes.
    // Make sure at least 1 so we can use appendAssumeCapacity on the root node below.
    const estimated_node_count = (tokens.len + 2) / 2;
    try parser.nodes.ensureTotalCapacity(gpa, estimated_node_count);

    switch (mode) {
        .zig => try parser.parseRoot(),
        .zon => try parser.parseZon(),
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

const std = @import("std");
const testing = std.testing;
const Ast = @This();
const Allocator = std.mem.Allocator;
const Parse = @import("Parse.zig");
pub const States = Parse.States;

test {
    testing.refAllDecls(@This());
}

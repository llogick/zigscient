//! Abstract Syntax Tree for Zig source code.
//! For Zig syntax, the root node is at nodes[0] and contains the list of
//! sub-nodes.
//! For Zon syntax, the root node is at nodes[0] and contains lhs as the node
//! index of the main expression.

gpa: Allocator,

/// Source bytes
bytes: std.ArrayListUnmanaged(u8),

/// Convenience mapping into 'bytes'. ReadOnly
source: [:0]const u8,

tokens: TokenList.Slice,
/// The root AST node is assumed to be index 0. Since there can be no
/// references to the root node, this means 0 is available to indicate null.
nodes: NodeList.Slice,
xtra_data: std.ArrayListUnmanaged(u32),
extra_data: []std.zig.Ast.Node.Index,
kind: Kind = .zig,
mode: Mode = .standard,
states: Parse.InternalStates,

errors: []const std.zig.Ast.Error,

pub const ByteOffset = u32;

pub const TokenInfo = struct {
    tag: std.zig.Token.Tag,
    start: ByteOffset,
};
pub const Node = std.zig.Ast.Node;

pub const TokenList = std.MultiArrayList(TokenInfo);
pub const NodeList = std.MultiArrayList(Node);

/// IMPORTANT: Result is invalidated by every .update()
pub fn toStdAst(self: *const Ast) std.zig.Ast {
    return .{
        .source = self.source,
        .mode = self.kind,
        .tokens = .{
            .ptrs = self.tokens.ptrs[0..2].*,
            .len = self.tokens.len,
            .capacity = self.tokens.capacity,
        },
        .nodes = .{
            .ptrs = self.nodes.ptrs,
            .len = self.nodes.len,
            .capacity = self.nodes.capacity,
        },
        .extra_data = self.xtra_data.items[0..],
        .errors = @ptrCast(self.errors),
    };
}

fn deinitNodesAndRelatedData(ast: *Ast) void {
    const gpa = ast.gpa;
    ast.nodes.deinit(gpa);
    ast.xtra_data.deinit(gpa);
    gpa.free(ast.errors);
    ast.states.deinit(gpa);
}

fn deinitAllButSourceBytes(ast: *Ast) void {
    const gpa = ast.gpa;
    ast.tokens.deinit(gpa);
    ast.deinitNodesAndRelatedData();
}

pub fn destroy(ast: *Ast) void {
    const gpa = ast.gpa;
    ast.deinitAllButSourceBytes();
    ast.bytes.deinit(gpa);
    ast.* = undefined;
}

pub const Kind = std.zig.Ast.Mode; // enum { zig, zon };
pub const Mode = enum { standard, extended };
/// Result shall be freed with .deinit(), takes ownership of the slice
pub fn createFromBytesSlice(gpa: Allocator, source: [:0]const u8, kind: Kind, mode: Mode) Allocator.Error!Ast {
    var bytes: std.ArrayListUnmanaged(u8) = try .initCapacity(gpa, source.len + 1);
    errdefer bytes.deinit(gpa);

    bytes.appendSliceAssumeCapacity(source);
    bytes.items.len += 1;
    bytes.items[bytes.items.len - 1] = 0x00;

    defer gpa.free(source);
    return createFromBytesArray(gpa, bytes, kind, mode);
}

/// Result shall be freed with .deinit(), takes ownership of the array
pub fn createFromBytesArray(gpa: Allocator, bytes: std.ArrayListUnmanaged(u8), kind: Kind, mode: Mode) Allocator.Error!Ast {
    var tokens: TokenList = .empty;
    defer tokens.deinit(gpa);

    std.debug.assert(bytes.items[bytes.items.len - 1] == 0x00);

    const source = bytes.items[0 .. bytes.items.len - 1 :0];

    // Empirically, the zig std lib has an 8:1 ratio of source bytes to token count.
    const estimated_token_count = source.len / 8;
    try tokens.ensureTotalCapacity(gpa, estimated_token_count);

    var tokenizer = Tokenizer.init(source);
    while (true) {
        const token = tokenizer.next();
        try tokens.append(gpa, .{
            .tag = token.tag,
            .start = @intCast(token.loc.start),
        });
        if (token.tag == .eof) break;
    }

    var parser: Parse = .{
        .gpa = gpa,
        .mode = mode,
        .source = source,
        .token_starts = tokens.items(.start),
        .token_tags = tokens.items(.tag),
        .errors = .{},
        .nodes = .{},
        .extra_data = .{},
        .scratch = .{},
        .states = .{},
        .tok_i = 0,
    };

    errdefer parser.states.deinit(gpa);

    defer parser.errors.deinit(gpa);
    defer parser.nodes.deinit(gpa);
    defer parser.scratch.deinit(gpa);

    // Empirically, Zig source code has a 2:1 ratio of tokens to AST nodes.
    // Make sure at least 1 so we can use appendAssumeCapacity on the root node below.
    const estimated_node_count = (tokens.len + 2) / 2;
    try parser.nodes.ensureTotalCapacity(gpa, estimated_node_count);

    switch (kind) {
        .zig => try parser.parseRoot(),
        .zon => try parser.parseZon(),
    }
    const errors = try parser.errors.toOwnedSlice(gpa);
    errdefer gpa.free(errors);

    const ast: Ast = .{
        .gpa = gpa,
        .bytes = bytes,
        .source = source,
        .kind = kind,
        .mode = mode,
        .tokens = tokens.toOwnedSlice(),
        .nodes = parser.nodes.toOwnedSlice(),
        .xtra_data = parser.extra_data,
        .extra_data = parser.extra_data.items[0..],
        .errors = errors,
        .states = parser.states,
    };

    return ast;
}

pub fn sourceIndexToTokenIndex(tree: *Ast, source_index: usize) std.zig.Ast.TokenIndex {
    const tokens_start = tree.tokens.items(.start);

    // at which point to stop dividing and just iterate
    // good results w/ 256 as well, anything lower/higher and the cost of
    // dividing overruns the cost of iterating and vice versa
    const threshold = 336;

    var upper_index: std.zig.Ast.TokenIndex = @intCast(tokens_start.len - 1); // The Ast always has a .eof token
    var lower_index: std.zig.Ast.TokenIndex = 0;
    while (upper_index - lower_index > threshold) {
        const mid = lower_index + (upper_index - lower_index) / 2;
        if (tokens_start[mid] < source_index) {
            lower_index = mid;
        } else {
            upper_index = mid;
        }
    }

    while (upper_index > 0) : (upper_index -= 1) {
        const token_start = tokens_start[upper_index];
        if (token_start > source_index) continue; // checking for equality here is suboptimal
        // Handle source_index being > than the last possible token_start (max_token_start < source_index < tree.source.len)
        if (upper_index == tokens_start.len - 1) break;
        // Check if source_index is within current token
        // (`token_start - 1` to include it's loc.start source_index and avoid the equality part of the check)
        const is_within_current_token = (source_index > (token_start - 1)) and (source_index < tokens_start[upper_index + 1]);
        if (!is_within_current_token) upper_index += 1; // gone 1 past
        break;
    }

    std.debug.assert(upper_index < tree.tokens.len);
    return upper_index;
}

fn replaceMalRange(
    gpa: Allocator,
    comptime T: type,
    dst_mal: *std.MultiArrayList(T),
    start: usize,
    len: usize,
    src_mal: *std.MultiArrayList(T),
) Allocator.Error!void {
    const Elem = switch (@typeInfo(T)) {
        .@"struct" => T,
        else => @compileError(
            \\This fn only supports structs,
            \\see MultiArrayList.Elem on how to implement support for tagged unions.
        ),
    };

    if ((len < src_mal.len) and ((dst_mal.len + (src_mal.len - len)) > dst_mal.capacity))
        try dst_mal.ensureUnusedCapacity(gpa, @max(dst_mal.len + (src_mal.len - len), 4096));

    var dst_slices = dst_mal.slice();
    const src_slices = src_mal.slice();
    const fields = std.meta.fields(Elem);

    if (len == src_mal.len) {
        inline for (fields, 0..) |_, field_index| {
            const dst_field_slice = dst_slices.items(@enumFromInt(field_index));
            const src_field_slice = src_slices.items(@enumFromInt(field_index));
            @memcpy(dst_field_slice[start..][0..src_field_slice.len], src_field_slice);
        }
    } else if (len < src_mal.len) {
        const xtra_len = src_mal.len - len;
        const prev_len = dst_slices.len;
        // std.log.debug("mal xtra_len: {}, prev_len: {}", .{ xtra_len, prev_len });
        dst_slices.len += xtra_len;
        inline for (fields, 0..) |_, field_index| {
            const dst_field_slice = dst_slices.items(@enumFromInt(field_index));
            const src_field_slice = src_slices.items(@enumFromInt(field_index));
            const dst = dst_field_slice[start + len + xtra_len ..];
            const src = dst_field_slice[start + len .. prev_len];
            if (@intFromPtr(dst.ptr) <= @intFromPtr(src.ptr))
                std.mem.copyForwards(@typeInfo(Elem).@"struct".fields[field_index].type, dst, src)
            else
                std.mem.copyBackwards(@typeInfo(Elem).@"struct".fields[field_index].type, dst, src);
            @memcpy(dst_field_slice[start..][0..src_mal.len], src_field_slice);
            // if (field_index == 0) std.log.debug("new range: {any}", .{dst_field_slice[start..][0..src_mal.len]});
        }
    } else {
        const shrink_len = len - src_mal.len;
        inline for (fields, 0..) |_, field_index| {
            const dst_field_slice = dst_slices.items(@enumFromInt(field_index));
            const src_field_slice = src_slices.items(@enumFromInt(field_index));
            @memcpy(dst_field_slice[start..][0..src_mal.len], src_field_slice);
            const to_move = dst_field_slice[start + len ..];
            const dst = dst_field_slice[start + len - shrink_len ..][0..to_move.len];
            if (@intFromPtr(dst.ptr) <= @intFromPtr(to_move.ptr))
                std.mem.copyForwards(@typeInfo(Elem).@"struct".fields[field_index].type, dst, to_move)
            else
                std.mem.copyBackwards(@typeInfo(Elem).@"struct".fields[field_index].type, dst, to_move);
        }
        dst_slices.len -= shrink_len;
    }

    dst_mal.len = dst_slices.len;
}

const AffectedIndices = struct {
    byt_idx_lo: u32,
    byt_idx_hi: u32,
    tok_idx_lo: u32,
    tok_idx_hi: u32,

    pub const default: @This() = .{
        .byt_idx_lo = 0,
        .byt_idx_hi = 0,
        .tok_idx_lo = 0,
        .tok_idx_hi = 0,
    };
};

// .. a bit fancy, a bit taxing on debug builds, but lessens noise
fn Delta() type {
    return struct {
        op: enum {
            add,
            sub,
            nop,
        } = .nop,
        value: u32 = 0,

        const Self = @This();

        pub fn init(current_value: u32, prev_value: u32) Self {
            return if (current_value > prev_value) .{ // addition is most likely in source code
                .op = .add,
                .value = @intCast(current_value - prev_value),
            } else if (current_value < prev_value) .{ // followed by subtraction (deletion)
                .op = .sub,
                .value = @intCast(prev_value - current_value),
            } else .{ // equal lens (same len rename/replace case)
                .op = .nop,
                .value = 0,
            };
        }

        pub fn applyTo(self: *const Self, value: u32) u32 {
            return switch (self.op) {
                .add => value + self.value,
                .sub => value - self.value,
                .nop => value,
            };
        }
    };
}

/// Updates tokens in-place
fn updateTokens(
    ast: *Ast,
    prev_bytes_len: u32,
    bytes_idx_lo: u32,
    bytes_idx_hi: u32,
) !?AffectedIndices {
    if (ast.bytes.items.len < 20 or ast.tokens.len < 20) return null;

    var result: AffectedIndices = .{
        .byt_idx_lo = bytes_idx_lo,
        .byt_idx_hi = bytes_idx_hi,
        .tok_idx_lo = undefined,
        .tok_idx_hi = undefined,
    };
    // std.log.debug("bytes_idx lo: {}, hi: {}", .{ bytes_idx_lo, bytes_idx_hi });

    const bytes_delta: Delta() = .init(@intCast(ast.bytes.items.len), prev_bytes_len);
    std.log.debug("bytes delta: {}", .{bytes_delta});

    // Always retokenize whole line(s), because .comment(s)

    // Whenever deleteing at a line's end the '\n' char floats back to byt_idx_lo, ie
    // `const a = 1;^`                      =>         `const a = 1^`
    // removed ----^^---- new line char     =>         byt_idx_lo -^- new line char
    if (ast.bytes.items[result.byt_idx_lo] == '\n' and result.byt_idx_lo > 0) result.byt_idx_lo -= 1; // skip it
    // Find the previous '\n'
    while (result.byt_idx_lo != 0 and ast.bytes.items[result.byt_idx_lo] != '\n') result.byt_idx_lo -= 1; // beginning of retok range

    // Grab the token; sourceIndexToTokenIndex always returns the prev token if source_index between tokens
    result.tok_idx_lo = ast.sourceIndexToTokenIndex(result.byt_idx_lo);
    // if !=0 => we've grabbed the last token on the prev line
    if (result.tok_idx_lo != 0 and result.tok_idx_lo < ast.tokens.len - 1) result.tok_idx_lo += 1; // first lower range affected token (to replace)

    const start_source_index = if (result.tok_idx_lo == 0) 0 else result.byt_idx_lo;

    // std.log.debug("tiltag: {}", .{ast.tokens.items(.tag)[result.tok_idx_lo]});

    // byt_idx_hi is the upper boundary of the bytes that were replaced;
    // depending on the replacement bytes range, larger/smaller/eq,
    // calculate where it floated to
    var upper_tokenize_byt_idx = bytes_delta.applyTo(result.byt_idx_hi);

    // upper_tokenize_byt_idx might be in the middle of a line =>
    // more bytes to retokenize which will affect more tokens =>
    // use the diff to adjust result.byt_idx_hi as the source_index for the upper, tokens affected, boundary
    const prev_upper_tokenize_byt_idx: u32 = upper_tokenize_byt_idx;

    const max_byte_idx = ast.bytes.items.len - 1;
    // Find the next '\n'
    while (upper_tokenize_byt_idx < max_byte_idx and ast.bytes.items[upper_tokenize_byt_idx] != '\n') upper_tokenize_byt_idx += 1; // upper boundary of retok range

    // result.byt_idx_hi adjusted to the end of the line to retokenize
    result.byt_idx_hi += upper_tokenize_byt_idx - prev_upper_tokenize_byt_idx;
    // Grab the token
    result.tok_idx_hi = ast.sourceIndexToTokenIndex(result.byt_idx_hi);
    // Find the next token that is on a _new line_, it will be the upper boundary of tokens to replace
    while (ast.tokens.items(.start)[result.tok_idx_hi] < result.byt_idx_hi and result.tok_idx_hi < ast.tokens.len - 1) result.tok_idx_hi += 1;

    // std.log.debug("tihtag: {}", .{ast.tokens.items(.tag)[result.tok_idx_hi]});
    // std.log.debug("result: {}", .{result});

    var new_tokens: TokenList = .empty;
    try new_tokens.ensureTotalCapacity(ast.gpa, ast.tokens.len); // an overkill in 90%+ of the cases, but better than realloc'ing
    defer new_tokens.deinit(ast.gpa);

    // std.log.debug("ssr: {} esr: {}\n{s}\n{any}", .{
    //     start_source_index,
    //     upper_tokenize_byt_idx,
    //     ast.bytes.items[start_source_index..upper_tokenize_byt_idx],
    //     ast.tokens.items(.tag)[result.tok_idx_lo..result.tok_idx_hi],
    // });

    var tokenizer: Tokenizer = .{
        .buffer = ast.source,
        .index = start_source_index,
    };

    while (true) {
        const token = tokenizer.next();
        // std.log.debug("newtok: {}", .{token});
        if (token.tag == .eof or (token.loc.start > upper_tokenize_byt_idx)) {
            // std.log.debug("break@: {}", .{token});
            break;
        }
        // std.log.debug("adding: {}", .{token});
        try new_tokens.append(ast.gpa, .{
            .tag = token.tag,
            .start = @as(u32, @intCast(token.loc.start)),
        });
    }

    var tokens = ast.tokens.toMultiArrayList();
    const prev_tokens_len: u32 = @intCast(tokens.len);
    const tokens_range_len = result.tok_idx_hi - result.tok_idx_lo;
    // std.log.debug("ctok_len: {}, tk_range_len: {}, new_tokens_len: {}", .{ prev_tokens_len, tokens_range_len, new_tokens.len });

    try replaceMalRange(
        ast.gpa,
        TokenInfo,
        &tokens,
        result.tok_idx_lo,
        tokens_range_len,
        &new_tokens,
    );

    const tokens_delta: Delta() = .init(@intCast(tokens.len), prev_tokens_len);
    // std.log.debug("tok_delta: {}", .{tokens_delta});

    // We've modified tokens => tok_idx_hi might've flown off to a new place
    result.tok_idx_hi = tokens_delta.applyTo(result.tok_idx_hi);
    // switch first, iterate after
    switch (bytes_delta.op) {
        .add => for (tokens.items(.start)[result.tok_idx_hi..]) |*start| {
            start.* += bytes_delta.value;
        },
        .sub => for (tokens.items(.start)[result.tok_idx_hi..]) |*start| {
            start.* -= bytes_delta.value;
        },
        .nop => {},
    }

    ast.*.tokens = tokens.toOwnedSlice();

    return result;
}

pub fn update(
    ast: *Ast,
    prev_bytes_len: u32,
    bytes_idx_lo: u32,
    bytes_idx_hi: u32,
) Allocator.Error!void {
    ast.source = ast.bytes.items[0 .. ast.bytes.items.len - 1 :0];
    if (try ast.updateTokens(prev_bytes_len, bytes_idx_lo, bytes_idx_hi)) |affected_indices| {
        // std.log.debug("{any}", .{result});
        if (ast.kind == .zig) reuse: {
            // if (!ast.initial_brace_matching_done) try reuseRootDecls else try doComplexReparse();
            // try ast.reuseRootDecls(affected_indices);
            if (!(try ast.reuseRootDecls(affected_indices))) break :reuse;
            return;
        }
        try ast.recreateNodes();
        return;
    }
    ast.deinitAllButSourceBytes();
    ast.* = try createFromBytesArray(ast.gpa, ast.bytes, ast.kind, ast.mode);
}

fn reuseRootDecls(ast: *Ast, indices: AffectedIndices) Allocator.Error!bool {
    // if (true) return false;
    if (ast.*.states.items.len < 2) return false; // Nothing to reuse
    const root_decl_idx = for (ast.*.states.items, 0..) |state, root_decl_idx| {
        const aft = state.range.aft;
        if (indices.tok_idx_lo > aft.token_idx and aft.errors_len == 0) continue;
        if (root_decl_idx == 0) return false;
        // std.log.debug("affected root_decl_idx: {} state:\n{}", .{ root_decl_idx, state });
        break root_decl_idx - 1;
    } else return false;

    const gpa = ast.gpa;

    const state = ast.states.items[root_decl_idx];
    if (!(state.range.pre.token_idx < ast.tokens.len)) return false; // XXX is this really a possibility?

    var scratch: std.ArrayListUnmanaged(std.zig.Ast.Node.Index) = try .initCapacity(gpa, ast.states.items.len);
    ast.states.items.len = root_decl_idx;
    for (ast.*.states.items) |pstate| scratch.appendAssumeCapacity(pstate.node_idx);

    ast.nodes.len = state.range.pre.nodes_len;
    ast.xtra_data.items.len = state.range.pre.xdata_len;

    var parser: Parse = .{
        .gpa = gpa,
        .mode = ast.mode,
        .source = ast.source,
        .token_starts = ast.tokens.items(.start),
        .token_tags = ast.tokens.items(.tag),
        .errors = .{},
        .nodes = ast.nodes.toMultiArrayList(),
        .extra_data = ast.xtra_data,
        .scratch = scratch,
        .states = ast.states,
        .tok_i = state.range.pre.token_idx,
        .field_state = state.range.pre.field_state,
        .last_field = state.range.pre.last_field,
    };

    defer parser.errors.deinit(gpa);
    defer parser.scratch.deinit(gpa);

    switch (ast.kind) {
        .zig => try parser.parseRoot(),
        .zon => try parser.parseZon(),
    }

    gpa.free(ast.*.errors);

    const errors = try parser.errors.toOwnedSlice(gpa);
    errdefer gpa.free(errors);

    ast.*.nodes = parser.nodes.toOwnedSlice();
    ast.*.xtra_data = parser.extra_data;
    ast.*.extra_data = parser.extra_data.items[0..];
    ast.*.errors = errors;
    ast.*.states = parser.states;

    return true;
}

fn recreateNodes(ast: *Ast) Allocator.Error!void {
    const gpa = ast.gpa;

    ast.*.nodes.deinit(ast.gpa);
    ast.*.xtra_data.deinit(gpa);
    gpa.free(ast.*.errors);
    ast.*.states.deinit(ast.*.gpa);

    var parser: Parse = .{
        .gpa = gpa,
        .mode = ast.mode,
        .source = ast.source,
        .token_starts = ast.tokens.items(.start),
        .token_tags = ast.tokens.items(.tag),
        .errors = .{},
        .nodes = .{},
        .extra_data = .{},
        .scratch = .{},
        .states = .empty,
        .tok_i = 0,
    };
    defer parser.errors.deinit(gpa);
    defer parser.nodes.deinit(gpa);
    defer parser.scratch.deinit(gpa);

    // Empirically, Zig source code has a 2:1 ratio of tokens to AST nodes.
    // Make sure at least 1 so we can use appendAssumeCapacity on the root node below.
    const estimated_node_count = (ast.tokens.len + 2) / 2;
    try parser.nodes.ensureTotalCapacity(gpa, estimated_node_count);

    switch (ast.kind) {
        .zig => try parser.parseRoot(),
        .zon => try parser.parseZon(),
    }

    const errors = try parser.errors.toOwnedSlice(gpa);
    errdefer gpa.free(errors);

    ast.*.nodes = parser.nodes.toOwnedSlice();
    ast.*.xtra_data = parser.extra_data;
    ast.*.extra_data = parser.extra_data.items[0..];
    ast.*.errors = errors;
    ast.*.states = parser.states;
}

const Ast = @This();

const std = @import("std");
const testing = std.testing;
const StdAst = std.zig.Ast;
const Allocator = std.mem.Allocator;
const Tokenizer = std.zig.Tokenizer;
const Parse = @import("Parse.zig");
const offsets = @import("../offsets.zig");
const ContentChanges = @import("../diff.zig").ContentChanges;

const build_info = @import("builtin");

pub const runtime_safety = switch (build_info.mode) {
    .Debug, .ReleaseSafe => true,
    .ReleaseFast, .ReleaseSmall => false,
};

// We cannot manipulate token tags in safety builds because AstGen does its own tokenization
// calling std.zig.Ast.tokenslice fn which includes a `assert(token.tag == token_tag);`
const I_have_deleted_the_assert_Zig014dir_lib_std_zig_Ast_tokenSlice_fn_line198 = false;
const allowed_to_manipulate_token_tags = !runtime_safety or I_have_deleted_the_assert_Zig014dir_lib_std_zig_Ast_tokenSlice_fn_line198;

test {
    testing.refAllDecls(@This());
}

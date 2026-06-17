const std = @import("std");
const Tokenizer = @import("./Tokenizer.zig");
const Allocator = std.mem.Allocator;
const Token = Tokenizer.Token;
const mem = std.mem;
const assert = std.debug.assert;

test {
    _ = Tokenizer;
}

const TokenList = std.MultiArrayList(Token);
const RawTokenList = std.ArrayList(Token);

const ExpandBuf = std.ArrayList(Token);

const Preprocessor = @This();
const DefineMap = std.StringArrayHashMapUnmanaged(Macro);

const GeneratedTokens = std.ArrayList(u8);

const MacroArgument = []const Token;

pub const Source = struct {
    pub const generated: Source.Id = std.math.maxInt(usize);
    pub const Id = usize;
    id: Id = generated,
    path: []const u8,
    buf: []const u8,
};

sources: std.StringArrayHashMapUnmanaged(Source) = .empty,

arena: Allocator,
io: std.Io,
include_dir: []const u8,

top_expansion_buf: ExpandBuf = .empty,
add_expansion_nl: usize = 0,
token_buf: RawTokenList = .empty,
generated_tokens: GeneratedTokens = .empty,
generated_line: u32 = 1,
defines: DefineMap = .empty,
tokens: TokenList = .empty,
target: *const std.Target,

const Macro = struct {
    param: []const u8,
    tokens: []const Token,
    is_func: bool,
};

const IfContext = struct {
    const Backing = u2;
    const Nesting = enum(Backing) {
        until_else,
        until_endif,
        until_endif_seen_else,
    };

    const buf_size_bits = @bitSizeOf(Backing) * 256;
    kind: [buf_size_bits / std.mem.byte_size_in_bits]u8,
    level: u8,

    fn get(self: *const IfContext) Nesting {
        return @enumFromInt(std.mem.readPackedInt(Backing, &self.kind, @as(usize, self.level) * 2, .native));
    }

    fn set(self: *IfContext, context: Nesting) void {
        std.mem.writePackedInt(Backing, &self.kind, @as(usize, self.level) * 2, @intFromEnum(context), .native);
    }

    fn increment(self: *IfContext) void {
        self.level += 1;
    }

    fn decrement(self: *IfContext) void {
        self.level -= 1;
    }

    const default: IfContext = .{ .kind = @splat(0xFF), .level = 0 };
};

fn addToken(pp: *Preprocessor, tok: Token) !void {
    try pp.tokens.append(pp.arena, tok);
}

fn addTokenAssumeCapacity(pp: *Preprocessor, tok: Token) void {
    pp.tokens.appendAssumeCapacity(tok);
}

fn defineBuiltins(pp: *Preprocessor) !void {
    var buf: [5]u8 = undefined;
    var val = std.fmt.bufPrint(&buf, "{d}", .{pp.target.cTypeBitSize(.longdouble)}) catch unreachable;
    try pp.defineBuiltinValue("__SIZEOF_LONG_DOUBLE__", val, .pp_num);
    val = std.fmt.bufPrint(&buf, "{d}", .{pp.target.cTypeBitSize(.double)}) catch unreachable;
    try pp.defineBuiltinValue("__SIZEOF_DOUBLE__", val, .pp_num);

    if (pp.target.abi.isGnu()) {
        try pp.defineBuiltinValue("__cdecl", "__attribute__((__cdecl__))", .identifier);
    }

    const arch = switch (pp.target.cpu.arch) {
        .aarch64 => "__aarch64__",
        .x86 => "__i386__",
        .x86_64 => "__x86_64__",
        .arm, .thumb => "__arm__",
        else => return error.ArchitectureNotSupported,
    };
    try pp.defineBuiltin(arch);
}

fn defineBuiltinValue(pp: *Preprocessor, name: []const u8, value: []const u8, id: Token.Id) !void {
    const start = pp.generated_tokens.items.len;
    try pp.generated_tokens.appendSlice(pp.arena, value);
    const end = pp.generated_tokens.items.len;

    const token_list = try pp.arena.alloc(Token, 1);
    token_list[0] = .{ .source = Source.generated, .id = id, .start = @intCast(start), .end = @intCast(end) };
    try pp.defines.putNoClobber(pp.arena, name, .{
        .is_func = false,
        .param = "",
        .tokens = token_list,
    });
}

fn defineBuiltin(pp: *Preprocessor, name: []const u8) !void {
    return pp.defines.putNoClobber(pp.arena, name, .{
        .tokens = &.{},
        .param = "",
        .is_func = false,
    });
}

pub fn preprocess(pp: *Preprocessor, file_path: []const u8) !void {
    const source = try pp.addSourceFromPath(file_path);
    try pp.preprocessFile(source);
}

fn preprocessFile(pp: *Preprocessor, src: Source) !void {
    try pp.defineBuiltins();
    const eof = try pp.preprocessFileExtra(src);
    try pp.addToken(eof);
}

fn preprocessFileExtra(pp: *Preprocessor, src: Source) !Token {
    var tokenizer: Tokenizer = .init(src.buf, src.id);
    var if_context: IfContext = .default;

    while (true) {
        var tok = tokenizer.next();
        switch (tok.id) {
            .hash => {
                const directive = tokenizer.nextNoWS();
                switch (directive.id) {
                    .keyword_define => try pp.define(&tokenizer),
                    .keyword_if => {
                        if_context.increment();
                        if (try pp.expr(&tokenizer)) {
                            if_context.set(.until_endif);
                        } else {
                            if_context.set(.until_else);
                            try pp.skip(&tokenizer, .until_else);
                        }
                    },
                    .keyword_ifdef => {
                        if_context.increment();
                        const macro_name = pp.expectMacroName(&tokenizer);
                        skipToNl(&tokenizer);
                        if (pp.defines.get(macro_name) != null) {
                            if_context.set(.until_endif);
                        } else {
                            if_context.set(.until_else);
                            try pp.skip(&tokenizer, .until_else);
                        }
                    },
                    .keyword_ifndef => {
                        if_context.increment();
                        const macro_name = pp.expectMacroName(&tokenizer);
                        skipToNl(&tokenizer);
                        if (pp.defines.get(macro_name) == null) {
                            if_context.set(.until_endif);
                        } else {
                            if_context.set(.until_else);
                            try pp.skip(&tokenizer, .until_else);
                        }
                    },
                    .keyword_elif => {
                        assert(if_context.level > 0);
                        switch (if_context.get()) {
                            .until_else => if (try pp.expr(&tokenizer)) {
                                if_context.set(.until_endif);
                            } else {
                                try pp.skip(&tokenizer, .until_else);
                            },
                            .until_endif => try pp.skip(&tokenizer, .until_endif),
                            .until_endif_seen_else => unreachable, //elif after endif
                        }
                    },
                    .keyword_else => {
                        skipToNl(&tokenizer);
                        assert(if_context.level > 0);
                        switch (if_context.get()) {
                            .until_else => if_context.set(.until_endif_seen_else),
                            .until_endif => try pp.skip(&tokenizer, .until_endif),
                            .until_endif_seen_else => unreachable, // else after else
                        }
                    },
                    .keyword_endif => {
                        skipToNl(&tokenizer);
                        assert(if_context.level > 0);
                        if_context.decrement();
                    },
                    .keyword_undef => {
                        const macro_name = tokenizer.nextNoWS();
                        assert(macro_name.id == .identifier);
                        pp.undefineMacro(macro_name);
                        skipToNl(&tokenizer);
                    },
                    .keyword_include => {
                        try pp.include(&tokenizer);
                        continue;
                    },
                    .keyword_defined, .keyword_error => {},
                    else => unreachable,
                }
                tok.id = .nl;
                try pp.addToken(tok);
            },
            .whitespace, .nl => try pp.addToken(tok),
            .eof => {
                assert(if_context.level == 0);
                return tok;
            },
            else => try pp.expandMacro(&tokenizer, tok),
        }
    }
}

fn include(pp: *Preprocessor, tokenizer: *Tokenizer) anyerror!void {
    const first = tokenizer.nextNoWS();
    const src = try findIncludeSource(pp, tokenizer, first);

    _ = try pp.preprocessFileExtra(src);
    if (pp.tokens.items(.id)[pp.tokens.len - 1] != .nl) {
        try pp.addToken(.{ .id = .nl, .source = Source.generated });
    }
}

fn findIncludeSource(
    pp: *Preprocessor,
    tokenizer: *Tokenizer,
    first: Token,
) !Source {
    const filename_tok = first;
    skipToNl(tokenizer);
    const tok_slice = pp.expandToken(filename_tok);
    assert(tok_slice.len >= 3);
    const filename = tok_slice[1 .. tok_slice.len - 1];
    return (try pp.findInclude(filename, first)) orelse @panic("include not found");
}

fn expectMacroName(pp: *const Preprocessor, tokenizer: *Tokenizer) []const u8 {
    const macro_name = tokenizer.nextNoWS();
    assert(macro_name.id.isMacroIdentifier());
    return pp.expandToken(macro_name);
}

fn skipToNl(tokenizer: *Tokenizer) void {
    while (true) {
        const tok = tokenizer.next();
        if (tok.id == .nl or tok.id == .eof) return;
        if (tok.id == .whitespace) continue;
    }
}

fn define(pp: *Preprocessor, tokenizer: *Tokenizer) !void {
    const macro_name = tokenizer.nextNoWS();
    assert(macro_name.id == .identifier);

    const first = tokenizer.nextNoWS();
    switch (first.id) {
        .nl, .eof => return pp.defineMacro(macro_name, .{
            .is_func = false,
            .tokens = &.{},
            .param = "",
        }),
        .l_paren => return pp.defineFn(tokenizer, macro_name),
        else => {},
    }
}

fn defineMacro(pp: *Preprocessor, tok: Token, macro: Macro) !void {
    const token_value = pp.expandToken(tok);
    try pp.defines.putNoClobber(pp.arena, token_value, macro);
}

fn undefineMacro(pp: *Preprocessor, tok: Token) void {
    const token_value = pp.expandToken(tok);
    _ = pp.defines.orderedRemove(token_value);
}

fn defineFn(
    pp: *Preprocessor,
    tokenizer: *Tokenizer,
    macro_name: Token,
) !void {
    var tok = tokenizer.nextNoWS();
    assert(tok.id == .identifier);
    const param = pp.expandToken(tok);
    tok = tokenizer.nextNoWS();
    assert(tok.id == .r_paren);

    pp.token_buf.items.len = 0;
    var need_ws = false;
    while (true) {
        tok = tokenizer.next();
        switch (tok.id) {
            .nl, .eof => break,
            .whitespace => need_ws = pp.token_buf.items.len != 0,
            .hash => unreachable,
            .hash_hash => {
                need_ws = false;
                try pp.token_buf.append(pp.arena, tok);
            },
            else => {
                if (need_ws) {
                    need_ws = false;
                    try pp.token_buf.append(pp.arena, .{ .id = .whitespace, .source = Source.generated });
                }

                if (tok.id.isMacroIdentifier()) {
                    tok.id = .identifier;
                    const s = pp.expandToken(tok);
                    if (mem.eql(u8, param, s)) {
                        tok.id = .macro_param;
                        tok.end = 0;
                    }
                }
                try pp.token_buf.append(pp.arena, tok);
            },
        }
    }

    const token_list = try pp.arena.dupe(Token, pp.token_buf.items);
    try pp.defineMacro(macro_name, .{
        .tokens = token_list,
        .is_func = true,
        .param = param,
    });
}

fn expandToken(pp: *const Preprocessor, tok: Token) []const u8 {
    return switch (tok.source) {
        Source.generated => pp.generated_tokens.items,
        else => blk: {
            const src = pp.sources.values()[tok.source];
            break :blk src.buf;
        },
    }[@intCast(tok.start)..@intCast(tok.end)];
}

fn skip(
    pp: *Preprocessor,
    tokenizer: *Tokenizer,
    cont: IfContext.Nesting,
) !void {
    var ifs_seen: u32 = 0;
    var line_start = true;
    while (tokenizer.index < tokenizer.buf.len) {
        if (line_start) {
            const tokenizer_bkp = tokenizer.*;
            const hash = tokenizer.nextNoWS();
            if (hash.id == .nl) continue;
            line_start = false;
            if (hash.id != .hash) continue;
            const directive = tokenizer.nextNoWS();
            switch (directive.id) {
                .keyword_else => {
                    if (ifs_seen != 0) continue;
                    assert(cont != .until_endif_seen_else); // else after else;
                    tokenizer.* = tokenizer_bkp;
                    return;
                },
                .keyword_elif => {
                    if (ifs_seen != 0 or cont == .until_endif) continue;
                    assert(cont != .until_endif_seen_else); // elif after else;
                    tokenizer.* = tokenizer_bkp;
                    return;
                },
                .keyword_endif => {
                    if (ifs_seen == 0) {
                        tokenizer.* = tokenizer_bkp;
                        return;
                    }
                    ifs_seen -= 1;
                },
                .keyword_if, .keyword_ifdef, .keyword_ifndef => ifs_seen += 1,
                else => {},
            }
        } else if (tokenizer.buf[tokenizer.index] == '\n') {
            line_start = true;
            tokenizer.index += 1;
            try pp.addToken(.{ .id = .nl, .source = Source.generated });
        } else {
            line_start = false;
            tokenizer.index += 1;
        }
    }
}

fn ensureUnusedTokenCapacity(pp: *Preprocessor, capacity: usize) !void {
    try pp.tokens.ensureUnusedCapacity(pp.arena, capacity);
}

fn expr(pp: *Preprocessor, tokenizer: *Tokenizer) !bool {
    const token_state = pp.tokens.len;
    defer pp.tokens.len = token_state;

    pp.top_expansion_buf.items.len = 0;
    while (true) {
        const tok = tokenizer.next();
        switch (tok.id) {
            .nl, .eof => break,
            .whitespace => if (pp.top_expansion_buf.items.len == 0) continue,
            else => {},
        }
        try pp.top_expansion_buf.append(pp.arena, tok);
    } else unreachable;
    if (pp.top_expansion_buf.items.len != 0) {
        try pp.expandMacroExhaustive(tokenizer, &pp.top_expansion_buf, 0, pp.top_expansion_buf.items.len, false, .expr);
    }
    try pp.ensureUnusedTokenCapacity(pp.top_expansion_buf.items.len);
    var i: usize = 0;
    const items = pp.top_expansion_buf.items;
    while (i < items.len) : (i += 1) {
        var tok = items[i];
        switch (tok.id) {
            .string_literal,
            .semicolon,
            .hash_hash,
            => unreachable,
            .whitespace => continue,
            else => if (tok.id == .keyword_defined) {
                i += try pp.handleKeywordDefined(&tok, items[i + 1 ..]);
            },
        }
        pp.addTokenAssumeCapacity(tok);
    }

    try pp.addToken(.{ .id = .eof, .source = Source.generated });
    return pp.evalExpression(token_state);
}

fn handleKeywordDefined(
    pp: *Preprocessor,
    macro_tok: *Token,
    tokens: []const Token,
) !usize {
    assert(macro_tok.id == .keyword_defined);
    var it = TokenIterator.init(tokens);

    _ = it.expectNoWS(.l_paren);
    const second = it.expectNoWS(.identifier);
    _ = it.expectNoWS(.r_paren);

    macro_tok.id = if (pp.defines.contains(pp.expandToken(second))) .one else .zero;

    return it.i;
}

const TokenIterator = struct {
    toks: []const Token,
    i: usize,

    fn init(toks: []const Token) TokenIterator {
        return .{ .toks = toks, .i = 0 };
    }

    fn nextNoWS(self: *TokenIterator) ?Token {
        while (self.i < self.toks.len) : (self.i += 1) {
            const tok = self.toks[self.i];
            if (tok.id == .whitespace) continue;

            self.i += 1;
            return tok;
        }
        return null;
    }

    fn expectNext(self: *TokenIterator) Token {
        assert(self.i < self.toks.len);
        const t = self.toks[self.i];
        self.i += 1;
        return t;
    }

    fn expectNoWS(self: *TokenIterator, expected: Token.Id) Token {
        if (self.nextNoWS()) |tok| {
            if (tok.id != expected) {
                std.debug.panic("expected token {any} but got {any}\n", .{ expected, tok.id });
            }
            return tok;
        }
        std.debug.panic("expected token {any} but got null\n", .{expected});
    }
};

fn expandMacro(pp: *Preprocessor, tokenizer: *Tokenizer, tok: Token) !void {
    if (!tok.id.isMacroIdentifier()) {
        return pp.addToken(tok);
    }
    pp.top_expansion_buf.items.len = 0;
    try pp.top_expansion_buf.append(pp.arena, tok);
    try pp.expandMacroExhaustive(tokenizer, &pp.top_expansion_buf, 0, 1, true, .non_expr);
    try pp.addTokensFromExpandBuf(pp.top_expansion_buf.items, .{ .id = .nl, .source = Source.generated });
}

fn addTokensFromExpandBuf(pp: *Preprocessor, tokens: []Token, tokenizer_nl: Token) !void {
    try pp.ensureUnusedTokenCapacity(tokens.len);
    for (tokens) |tok| {
        pp.addTokenAssumeCapacity(tok);
    }
    try pp.ensureUnusedTokenCapacity(pp.add_expansion_nl);
    while (pp.add_expansion_nl > 0) : (pp.add_expansion_nl -= 1) {
        pp.addTokenAssumeCapacity(tokenizer_nl);
    }
}

const EvalContext = enum {
    expr,
    non_expr,
};

fn expandMacroExhaustive(
    pp: *Preprocessor,
    tokenizer: *Tokenizer,
    buf: *ExpandBuf,
    start_idx: usize,
    end_idx: usize,
    extend_buf: bool,
    eval_ctx: EvalContext,
) !void {
    var moving_end_idx = end_idx;
    var advance_index: usize = 0;
    var do_rescan = true;
    while (do_rescan) {
        do_rescan = false;
        var idx: usize = start_idx + advance_index;
        while (idx < moving_end_idx) {
            const macro_tok = buf.items[idx];
            if (macro_tok.id == .keyword_defined and eval_ctx == .expr) {
                idx += 1;
                var it = TokenIterator.init(buf.items[idx..moving_end_idx]);
                if (it.nextNoWS()) |tok| {
                    switch (tok.id) {
                        .l_paren => {
                            _ = it.nextNoWS();
                            _ = it.nextNoWS();
                        },
                        else => {},
                    }
                }
                idx += it.i;
                continue;
            }
            if (!macro_tok.id.isMacroIdentifier()) {
                idx += 1;
                continue;
            }
            const expanded = pp.expandToken(macro_tok);
            const macro = pp.defines.getPtr(expanded) orelse {
                idx += 1;
                continue;
            };

            if (macro.is_func) {
                var macro_scan_idx = idx;
                const arg = try pp.collectMacroArgument(
                    tokenizer,
                    buf,
                    &macro_scan_idx,
                    &moving_end_idx,
                    extend_buf,
                );
                const expanded_arg = arg: {
                    var expand_buf: ExpandBuf = .empty;
                    errdefer expand_buf.deinit(pp.arena);
                    try expand_buf.appendSlice(pp.arena, arg);
                    try pp.expandMacroExhaustive(tokenizer, &expand_buf, 0, expand_buf.items.len, false, eval_ctx);
                    break :arg try expand_buf.toOwnedSlice(pp.arena);
                };

                const res = try pp.expandFuncMacro(macro, arg, expanded_arg);
                const tokens_added = res.items.len;
                const tokens_removed = macro_scan_idx - idx + 1;
                try buf.replaceRange(pp.arena, idx, tokens_removed, res.items);

                moving_end_idx += tokens_added;
                moving_end_idx -|= tokens_removed;
                idx += tokens_added;
                do_rescan = true;
            } else {
                var res = try pp.expandObjMacro(macro);
                defer res.deinit(pp.arena);
                var increment_idx_by = res.items.len;

                for (res.items, 0..) |*tok, i| {
                    if (i < increment_idx_by and pp.defines.contains(pp.expandToken(tok.*))) {
                        increment_idx_by = i;
                    }
                }
                try buf.replaceRange(pp.arena, idx, 1, res.items);
                idx += res.items.len;
                moving_end_idx = moving_end_idx + res.items.len - 1;
                do_rescan = true;
            }
            if (idx - start_idx == advance_index + 1 and !do_rescan) {
                advance_index += 1;
            }
        }
    }
    buf.items.len = moving_end_idx;
}

fn collectMacroArgument(
    pp: *Preprocessor,
    tokenizer: *Tokenizer,
    buf: *ExpandBuf,
    start_idx: *usize,
    end_idx: *usize,
    extend_buf: bool,
) !MacroArgument {
    var parens: u32 = 0;
    var argument: std.ArrayList(Token) = .empty;
    defer argument.deinit(pp.arena);

    while (true) {
        const tok = try nextBufToken(pp, tokenizer, buf, start_idx, end_idx, extend_buf);
        switch (tok.id) {
            .nl, .whitespace => {},
            .l_paren => break,
            else => unreachable,
        }
    }

    while (true) {
        const tok = try nextBufToken(pp, tokenizer, buf, start_idx, end_idx, extend_buf);
        switch (tok.id) {
            .l_paren => {
                try argument.append(pp.arena, tok);
                parens += 1;
            },
            .r_paren => {
                if (parens == 0) {
                    return try argument.toOwnedSlice(pp.arena);
                } else {
                    try argument.append(pp.arena, tok);
                    parens -= 1;
                }
            },
            .nl, .whitespace => try argument.append(pp.arena, .{ .id = .whitespace, .source = Source.generated }),
            .eof => unreachable,
            else => try argument.append(pp.arena, tok),
        }
    }
}

fn expandObjMacro(pp: *Preprocessor, simple_macro: *const Macro) !ExpandBuf {
    var buf: ExpandBuf = .empty;
    errdefer buf.deinit(pp.arena);
    try buf.appendSlice(pp.arena, simple_macro.tokens);
    return buf;
}

fn expandFuncMacro(
    pp: *Preprocessor,
    func_macro: *const Macro,
    arg: MacroArgument,
    expanded_arg: MacroArgument,
) !ExpandBuf {
    var buf: ExpandBuf = .empty;
    errdefer buf.deinit(pp.arena);
    try buf.ensureTotalCapacity(pp.arena, func_macro.tokens.len);

    var tok_i: usize = 0;
    while (tok_i < func_macro.tokens.len) : (tok_i += 1) {
        const tok = func_macro.tokens[tok_i];
        switch (tok.id) {
            .hash_hash => while (tok_i + 1 < func_macro.tokens.len) {
                tok_i += 1;
                const tok_next = func_macro.tokens[tok_i];
                const next = switch (tok_next.id) {
                    .whitespace => continue,
                    .hash_hash => continue,
                    .macro_param => arg,
                    else => &[1]Token{tok_next},
                };
                try pp.pasteTokens(&buf, next);
                if (next.len != 0) break;
            },
            .macro_param => {
                try buf.appendSlice(pp.arena, expanded_arg);
            },
            else => try buf.append(pp.arena, tok),
        }
    }

    return buf;
}

fn pasteTokens(
    pp: *Preprocessor,
    lhs_toks: *ExpandBuf,
    rhs_toks: []const Token,
) !void {
    const lhs = while (lhs_toks.pop()) |lhs| {
        if (lhs.id != .whitespace) break lhs;
    } else {
        return lhs_toks.appendSlice(pp.arena, rhs_toks);
    };

    var rhs_rest: u32 = 1;
    const rhs = for (rhs_toks) |rhs| {
        if (rhs.id != .whitespace) break rhs;
        rhs_rest += 1;
    } else {
        return lhs_toks.appendAssumeCapacity(lhs);
    };

    const start = pp.generated_tokens.items.len;
    const end = start + pp.expandToken(lhs).len + pp.expandToken(rhs).len;
    try pp.generated_tokens.ensureTotalCapacity(pp.arena, end + 1);
    pp.generated_tokens.appendSliceAssumeCapacity(pp.expandToken(lhs));
    pp.generated_tokens.appendSliceAssumeCapacity(pp.expandToken(rhs));
    pp.generated_tokens.appendAssumeCapacity('\n');

    var tmp_tokenizer: Tokenizer = .{
        .index = @intCast(start),
        .buf = pp.generated_tokens.items,
        .source = Source.generated,
    };
    const pasted_token = tmp_tokenizer.nextNoWS();
    const next = tmp_tokenizer.nextNoWS();

    try lhs_toks.append(pp.arena, pp.makeGeneratedToken(start, end, pasted_token.id));
    assert(next.id == .nl or next.id == .eof);

    return lhs_toks.appendSlice(pp.arena, rhs_toks[rhs_rest..]);
}

fn nextBufToken(
    pp: *Preprocessor,
    tokenizer: *Tokenizer,
    buf: *ExpandBuf,
    start_idx: *usize,
    end_idx: *usize,
    extend_buf: bool,
) !Token {
    start_idx.* += 1;
    if (start_idx.* == buf.items.len and start_idx.* >= end_idx.*) {
        if (extend_buf) {
            const tok = tokenizer.next();
            if (tok.id == .nl) pp.add_expansion_nl += 1;

            end_idx.* += 1;
            try buf.append(pp.arena, tok);
            return tok;
        }
        return .{ .id = .eof, .source = Source.generated };
    }

    return buf.items[start_idx.*];
}

fn makeGeneratedToken(
    pp: *Preprocessor,
    start: usize,
    end: usize,
    id: Token.Id,
) Token {
    const pasted_token: Token = .{
        .id = id,
        .source = Source.generated,
        .start = @intCast(start),
        .end = @intCast(end),
    };
    pp.generated_line += 1;
    return pasted_token;
}

fn findInclude(
    pp: *Preprocessor,
    filename: []const u8,
    includer_token: Token,
) !?Source {
    const other_file = pp.sources.values()[includer_token.source].path;
    const dir = std.fs.path.dirname(other_file) orelse ".";
    if (try pp.checkIncludeDir(filename, dir)) |res| return res;

    return pp.checkIncludeDir(filename, pp.include_dir);
}

fn checkIncludeDir(
    pp: *Preprocessor,
    include_path: []const u8,
    include_dir: []const u8,
) !?Source {
    const format = "{s}{c}{s}";
    var bfa_buf: [1024]u8 = undefined;
    var bfa_state: std.heap.BufferFirstAllocator = .init(&bfa_buf, pp.arena);
    const bfa = bfa_state.allocator();
    const header_path = try std.fmt.allocPrint(bfa, format, .{
        include_dir,
        std.fs.path.sep,
        include_path,
    });
    defer bfa.free(header_path);

    return pp.addSourceFromPath(header_path) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        else => return null,
    };
}

pub fn addSourceFromPath(pp: *Preprocessor, path: []const u8) !Source {
    if (pp.sources.get(path)) |src| return src;
    try pp.sources.ensureUnusedCapacity(pp.arena, 1);

    const contents = try std.Io.Dir.cwd().readFileAlloc(pp.io, path, pp.arena, .limited(std.math.maxInt(u32)));
    const duped_path = try pp.arena.dupe(u8, path);

    const src: Source = .{
        .buf = contents,
        .path = duped_path,
        .id = pp.sources.count(),
    };

    pp.sources.putAssumeCapacityNoClobber(duped_path, src);
    return src;
}

fn evalExpression(
    pp: *Preprocessor,
    start: usize,
) !bool {
    const s = pp.tokens.slice();
    const len = s.len - start;
    const ss = s.subslice(start, len);

    const ids: []Token.Id = ss.items(.id);
    const starts: []u32 = ss.items(.start);
    const ends: []u32 = ss.items(.end);
    const srcs: []usize = ss.items(.source);

    var toks = try pp.arena.alloc(Token, len);
    defer pp.arena.free(toks);

    for (0..len) |i| {
        toks[i] = .{
            .id = ids[i],
            .source = srcs[i],
            .start = starts[i],
            .end = ends[i],
        };
    }

    return pp.evaluateExpressionTokens(toks);
}

fn evaluateExpressionTokens(
    pp: *const Preprocessor,
    toks: []const Token,
) bool {
    var it = TokenIterator.init(toks);

    const left = evalToken(&it);
    assert(!left.id.isInfix());

    const op = evalToken(&it);
    if (op.id == .eof) return left.id == .one;

    assert(op.id.isInfix());
    const right = evalToken(&it);

    return pp.evalInfix(left, op, right);
}

fn evalToken(it: *TokenIterator) Token {
    const tok = it.expectNext();
    if (tok.id != .bang) {
        return tok;
    }

    var op = it.expectNext();
    const flipped: Token.Id = switch (op.id) {
        .one => .zero,
        .zero => .one,
        else => unreachable,
    };
    op.id = flipped;
    return op;
}

fn evalInfix(
    pp: *const Preprocessor,
    left: Token,
    op: Token,
    right: Token,
) bool {
    switch (op.id) {
        .pipe_pipe => return (left.id == .one) or (right.id == .one),
        .equal_equal => {
            switch (left.id) {
                .one, .zero => {
                    assert(right.id == .one or right.id == .zero);
                    return left.id == right.id;
                },
                .pp_num => {
                    assert(right.id == .pp_num);
                    const lval = pp.expandToken(left);
                    const rval = pp.expandToken(right);
                    return std.mem.eql(u8, lval, rval);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

pub fn prettyPrintTokens(pp: *Preprocessor, w: *std.Io.Writer) !void {
    const tok_ids = pp.tokens.items(.id);
    var i: usize = 0;
    var last_nl = true;
    outer: while (true) : (i += 1) {
        const cur: Token = pp.tokens.get(i);
        switch (cur.id) {
            .eof => {
                if (!last_nl) try w.writeByte('\n');
                try w.flush();
                return;
            },
            .nl => {
                var newlines: u32 = 0;
                for (tok_ids[i..], i..) |id, j| {
                    if (id == .nl) {
                        newlines += 1;
                    } else if (id == .eof) {
                        if (!last_nl) try w.writeByte('\n');
                        try w.flush();
                        return;
                    } else if (id != .whitespace) {
                        if (newlines < 2) break;

                        i = @intCast((j - 1) - @intFromBool(tok_ids[j - 1] == .whitespace));
                        if (!last_nl) try w.writeAll("\n");
                        continue :outer;
                    }
                }
                last_nl = true;
                try w.writeAll("\n");
            },
            .whitespace => {
                try w.writeByte(' ');
                last_nl = false;
            },
            else => {
                const slice = pp.expandToken(cur);
                try w.writeAll(slice);
                last_nl = false;
            },
        }
    }
}

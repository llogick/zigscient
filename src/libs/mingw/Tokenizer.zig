const std = @import("std");
const assert = std.debug.assert;
const Source = @import("Preprocessor.zig").Source;

const Tokenizer = @This();

pub fn init(buf: []const u8, source: Source.Id) Tokenizer {
    return .{ .buf = buf, .source = source };
}

buf: []const u8,
index: u32 = 0,
source: Source.Id,

pub const Token = struct {
    pub const Id = enum {
        bang,
        eof,
        equal_equal,
        hash,
        hash_hash,
        macro_param,
        identifier,
        keyword_if,
        keyword_ifndef,
        keyword_ifdef,
        keyword_define,
        keyword_endif,
        keyword_defined,
        keyword_include,
        keyword_elif,
        keyword_else,
        keyword_undef,
        keyword_error,
        l_paren,
        nl,
        pp_num,
        pipe_pipe,
        r_paren,
        semicolon,
        string_literal,
        whitespace,
        one,
        zero,

        pub fn isInfix(id: Id) bool {
            switch (id) {
                .pipe_pipe, .equal_equal => return true,
                else => return false,
            }
        }

        pub fn isMacroIdentifier(id: Id) bool {
            switch (id) {
                .keyword_if,
                .keyword_ifndef,
                .keyword_ifdef,
                .keyword_define,
                .keyword_endif,
                .keyword_defined,
                .keyword_include,
                .keyword_elif,
                .keyword_else,
                .keyword_undef,
                .keyword_error,
                .identifier,
                => return true,
                else => return false,
            }
        }
    };

    const all_kws = std.StaticStringMap(Id).initComptime(.{
        .{ "define", .keyword_define },
        .{ "defined", .keyword_defined },
        .{ "else", .keyword_else },
        .{ "endif", .keyword_endif },
        .{ "if", .keyword_if },
        .{ "elif", .keyword_elif },
        .{ "ifdef", .keyword_ifdef },
        .{ "ifndef", .keyword_ifndef },
        .{ "include", .keyword_include },
        .{ "undef", .keyword_undef },
        .{ "error", .keyword_error },
    });

    id: Id,
    source: Source.Id,
    start: u32 = 0,
    end: u32 = 0,

    fn getTokenId(str: []const u8) Id {
        return all_kws.get(str) orelse .identifier;
    }
};

pub fn next(self: *Tokenizer) Token {
    var state: enum {
        start,
        cr,
        string_literal,
        identifier,
        equal,
        slash,
        line_comment,
        hash,
        pipe,
        pp_num,
    } = .start;

    const start = self.index;
    var id: Token.Id = .eof;

    while (self.index < self.buf.len) : (self.index += 1) {
        const c = self.buf[self.index];
        switch (state) {
            .start => switch (c) {
                '\r' => {
                    id = .nl;
                    state = .cr;
                },
                '\n' => {
                    id = .nl;
                    self.index += 1;
                    break;
                },
                '!' => {
                    id = .bang;
                    self.index += 1;
                    break;
                },
                '"' => {
                    id = .string_literal;
                    state = .string_literal;
                },
                '|' => state = .pipe,
                '=' => state = .equal,
                '(' => {
                    id = .l_paren;
                    self.index += 1;
                    break;
                },
                ')' => {
                    id = .r_paren;
                    self.index += 1;
                    break;
                },
                ';' => {
                    id = .semicolon;
                    self.index += 1;
                    break;
                },
                '/' => state = .slash,
                '#' => state = .hash,
                '0'...'9' => state = .pp_num,
                ' ' => {
                    id = .whitespace;
                    self.index += 1;
                    break;
                },
                else => state = .identifier,
            },
            .cr => switch (c) {
                '\n' => {
                    self.index += 1;
                    break;
                },
                else => break,
            },
            .pipe => switch (c) {
                '|' => {
                    id = .pipe_pipe;
                    self.index += 1;
                    break;
                },
                else => unreachable,
            },
            .hash => switch (c) {
                '#' => {
                    id = .hash_hash;
                    self.index += 1;
                    break;
                },
                else => {
                    id = .hash;
                    break;
                },
            },
            .string_literal => switch (c) {
                '"' => {
                    self.index += 1;
                    break;
                },
                else => {},
            },
            .identifier => switch (c) {
                'a'...'z', 'A'...'Z', '_', '0'...'9' => {},
                else => {
                    id = Token.getTokenId(self.buf[start..self.index]);
                    break;
                },
            },
            .equal => switch (c) {
                '=' => {
                    id = .equal_equal;
                    self.index += 1;
                    break;
                },
                else => unreachable,
            },
            .slash => switch (c) {
                '/' => state = .line_comment,
                else => {
                    id = .identifier;
                    break;
                },
            },
            .line_comment => switch (c) {
                '\n' => {
                    self.index -= 1;
                    state = .start;
                },
                else => {},
            },
            .pp_num => switch (c) {
                '0'...'9' => {},
                else => {
                    id = .pp_num;
                    break;
                },
            },
        }
    } else if (self.index == self.buf.len) {
        switch (state) {
            .start, .line_comment, .cr => {},
            .identifier => id = Token.getTokenId(self.buf[start..self.index]),
            .hash => id = .hash,
            .pp_num => id = .pp_num,
            else => unreachable,
        }
    }

    return .{
        .id = id,
        .start = start,
        .end = self.index,
        .source = self.source,
    };
}

pub fn nextNoWS(self: *Tokenizer) Token {
    var tok = self.next();
    while (tok.id == .whitespace) tok = self.next();
    return tok;
}

fn expectToken(expected: Token.Id, actual: Token) !void {
    try std.testing.expectEqual(expected, actual.id);
}

fn testToken(buf: []const u8, expected: Token.Id) !void {
    var tokenizer = Tokenizer.init(buf, Source.generated);
    const t = tokenizer.next();
    try expectToken(expected, t);
    try expectToken(.eof, tokenizer.next());
}

test "tokens" {
    try testToken("TEST", .identifier);
    try testToken("__x86_64__", .identifier);
    try testToken("122", .pp_num);
    try testToken("==", .equal_equal);
    try testToken("#", .hash);
    try testToken("##", .hash_hash);
    try testToken("undef", .keyword_undef);
    try testToken("||", .pipe_pipe);
    try testToken("!", .bang);
    try testToken("else", .keyword_else);
    try testToken("endif", .keyword_endif);
    try testToken("include", .keyword_include);
    try testToken("define", .keyword_define);
    try testToken("defined", .keyword_defined);
    try testToken("if", .keyword_if);
    try testToken("ifdef", .keyword_ifdef);
    try testToken("ifndef", .keyword_ifndef);
    try testToken("(", .l_paren);
    try testToken("\n", .nl);
    try testToken("\r", .nl);
    try testToken("\r\n", .nl);
    try testToken("5", .pp_num);
    try testToken(")", .r_paren);
    try testToken("\"str\"", .string_literal);
    try testToken(" ", .whitespace);
}

fn expectTokens(contents: []const u8, expected_tokens: []const Token.Id) !void {
    var tokenizer: Tokenizer = .init(contents, Source.generated);
    var i: usize = 0;
    while (i < expected_tokens.len) {
        const token = tokenizer.next();
        if (token.id == .whitespace) continue;
        const expected_token_id = expected_tokens[i];
        i += 1;
        if (!std.meta.eql(token.id, expected_token_id)) {
            std.debug.print("expected {s}, found {s}\n", .{ @tagName(expected_token_id), @tagName(token.id) });
            return error.TokensDoNotEqual;
        }
    }
    const last_token = tokenizer.next();
    try std.testing.expect(last_token.id == .eof);
}

test "preprocessor keywords" {
    try expectTokens(
        \\#if
        \\#ifndef
        \\#ifdef
        \\#define
        \\#endif
        \\defined
        \\#include
        \\#elif
        \\#else
        \\#undef
        \\#error
    , &.{
        .hash,
        .keyword_if,
        .nl,
        .hash,
        .keyword_ifndef,
        .nl,
        .hash,
        .keyword_ifdef,
        .nl,
        .hash,
        .keyword_define,
        .nl,
        .hash,
        .keyword_endif,
        .nl,
        .keyword_defined,
        .nl,
        .hash,
        .keyword_include,
        .nl,
        .hash,
        .keyword_elif,
        .nl,
        .hash,
        .keyword_else,
        .nl,
        .hash,
        .keyword_undef,
        .nl,
        .hash,
        .keyword_error,
    });
}

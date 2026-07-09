//! Example usage:
//! zig build gen-parser-oracle
//! zig build check-parser-oracle

// This program implements a subset of the PEG grammar definition
// in the peg(1) man page.
//
// It generates a recursive descent parser that returns true if a given input is
// matched by the grammar. This generated parser is used as an oracle for fuzz testing.

const std = @import("std");
const assert = std.debug.assert;
const Io = std.Io;
const mem = std.mem;
const Allocator = mem.Allocator;
const log = std.log;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    const grammar_path = args[1];
    const out_path = args[2];
    const check = args.len > 3 and mem.eql(u8, args[3], "--check");

    const grammar = try Io.Dir.cwd().readFileAlloc(io, grammar_path, gpa, .unlimited);
    defer gpa.free(grammar);

    var parser: Parser = .init(gpa, grammar);
    defer parser.deinit();

    const root = try parser.parseGrammar() orelse {
        log.err("Invalid grammar", .{});
        return;
    };

    var buffer: Io.Writer.Allocating = .init(gpa);
    defer buffer.deinit();

    var g: Generator = .init(&buffer.writer, &parser);
    try g.genRoot(root);

    const generated = try buffer.toOwnedSliceSentinel(0);
    defer gpa.free(generated);

    // Parse the generated Zig code and render it in the canonical format
    var tree = try std.zig.Ast.parse(gpa, generated, .{});
    defer tree.deinit(gpa);

    if (tree.errors.len != 0) {
        // This should never be reached, but helps a lot when debugging this script.
        try std.zig.printAstErrorsToStderr(gpa, io, tree, "generated", .auto);
        return error.ParseError;
    }

    if (check) {
        const current = try Io.Dir.cwd().readFileAlloc(io, out_path, gpa, .unlimited);
        defer gpa.free(current);
        var aw: Io.Writer.Allocating = .init(gpa);
        defer aw.deinit();
        try tree.render(gpa, &aw.writer, .{});
        if (!mem.eql(u8, current, aw.written())) {
            std.log.err("grammar.peg modified without regenerating oracle", .{});
            std.log.info("Run zig build gen-parser-oracle to regenerate", .{});
            std.process.exit(1);
        }
    } else {
        var out_file = try Io.Dir.cwd().createFile(io, out_path, .{});
        defer out_file.close(io);
        var out_buffer: [4096]u8 = undefined;
        var out_writer = out_file.writer(io, &out_buffer);
        const out = &out_writer.interface;

        try tree.render(gpa, out, .{});
        try out.flush();
    }
}

const Generator = struct {
    w: *Io.Writer,
    p: *const Parser,
    /// Suffix for generated identifiers, incremented for each nested scope to avoid shadowing,
    /// Decremented at end of each generated scope to give smaller git diffs when regenerating
    /// lib/std/zig/parser_generated_oracle.zig.
    suffix: usize,

    fn init(w: *Io.Writer, p: *const Parser) Generator {
        return .{ .w = w, .p = p, .suffix = 0 };
    }

    const Error = Io.Writer.Error;
    const Node = Parser.Node;

    fn genRoot(g: *Generator, node: Node.Index) Error!void {
        try g.w.writeAll(
            \\//! This file is generated, do not edit manually! To generate, run:
            \\//! zig build gen-parser-oracle
            \\
            \\const std = @import("std");
            \\
            \\const Error = error{MaxDepth};
            \\const max_depth = 5;
            \\
            \\/// Returns true if the input source is in the language defined by
            \\/// the grammar.
            \\/// Returns error.MaxDepth if more than `max_depth` levels of recursion/iteration are reached.
            \\pub fn parse(source: []const u8) Error!bool {
            \\    var p: Parser = .{ .source = source, .i = 0, .depths = @splat(1) };
            \\    return p.parseRoot();
            \\}
        );

        const defs = g.p.getExtra(node.get(g.p).root);

        // This enum exists to minimize git diffs in the generated oracle when
        // the grammar is modified. It allows mapping from def name (stable) to
        // def index (unstable).
        try g.w.writeAll("const Def = enum {");
        for (defs) |n| {
            const def = n.get(g.p).def;
            const id = def.id.get(g.p).id;
            try g.w.print("def{s},", .{id});
        }
        try g.w.writeAll("};");

        try g.w.print(
            \\const Parser = struct {{
            \\    source: []const u8,
            \\    i: usize,
            \\    depths: [{d}]u8,
        , .{defs.len});
        for (defs) |def| {
            try g.genDef(def);
        }
        try g.w.writeAll("};");
    }

    fn genDef(g: *Generator, node: Node.Index) Error!void {
        const def = node.get(g.p).def;
        const id = def.id.get(g.p).id;
        assert(g.suffix == 0);
        try g.w.print("pub fn parse{s}(p: *Parser) Error!bool {{", .{id});
        try g.w.print(
            \\const def_index = @intFromEnum(Def.def{s});
            \\if (p.depths[def_index] > max_depth) return error.MaxDepth;
            \\p.depths[def_index] += 1;
            \\defer p.depths[def_index] -= 1;
        , .{id});
        try g.w.writeAll("return ");
        try g.genExpr(def.expr);
        try g.w.writeAll(";}");
    }

    fn genExpr(g: *Generator, node: Node.Index) Error!void {
        const suffix = g.suffix;
        g.suffix += 1;
        defer g.suffix -= 1;
        try g.w.print(
            \\blk_{d}: {{
            \\const pos_{d} = p.i;
        , .{ suffix, suffix });
        for (g.p.getExtra(node.get(g.p).expr)) |seq| {
            try g.w.writeAll("if (");
            try g.genSeq(seq);
            try g.w.print(") break :blk_{d} true;", .{suffix});
            try g.w.print("p.i = pos_{d};", .{suffix});
        }
        try g.w.print("break :blk_{d} false; }}", .{suffix});
    }

    fn genSeq(g: *Generator, node: Node.Index) Error!void {
        const items = g.p.getExtra(node.get(g.p).seq);
        for (items, 0..) |item, i| {
            if (i > 0) try g.w.writeAll(" and ");
            try g.genNode(item);
        }
    }

    fn genNode(g: *Generator, node: Node.Index) Error!void {
        const suffix = g.suffix;
        g.suffix += 1;
        defer g.suffix -= 1;
        switch (node.get(g.p)) {
            .id => |id| try g.w.print("try p.parse{s}()", .{id}),
            .expr => try g.genExpr(node),
            .@"&" => |child| {
                // XXX forbid unbounded lookahead
                try g.w.print(
                    \\blk_{d}: {{
                    \\const pos_{d} = p.i;
                    \\const match_{d} = 
                , .{ suffix, suffix, suffix });
                try g.genNode(child);
                try g.w.print(
                    \\;
                    \\p.i = pos_{d};
                    \\    break :blk_{d} match_{d};
                    \\}}
                , .{ suffix, suffix, suffix });
            },
            .@"!" => |child| {
                // XXX forbid unbounded lookahead
                try g.w.print(
                    \\blk_{d}: {{
                    \\const pos_{d} = p.i;
                    \\const match_{d} = 
                , .{ suffix, suffix, suffix });
                try g.genNode(child);
                try g.w.print(
                    \\;
                    \\p.i = pos_{d};
                    \\    break :blk_{d} !match_{d};
                    \\}}
                , .{ suffix, suffix, suffix });
            },
            .@"?" => |child| {
                try g.w.writeAll("(");
                try g.genNode(child);
                try g.w.writeAll(" or true )");
            },
            .@"*" => |child| {
                try g.w.print(
                    \\blk_{d}: {{
                    \\var i_{d}: usize = 0;
                    \\while (
                , .{ suffix, suffix });
                try g.genNode(child);
                try g.w.print(
                    \\) {{
                    \\  if (i_{d} > max_depth) return error.MaxDepth;
                    \\  i_{d} += 1;
                    \\}}
                    \\break :blk_{d} true; }}
                , .{ suffix, suffix, suffix });
            },
            .@"+" => |child| {
                try g.w.print(
                    \\blk_{d}: {{
                    \\var match_{d} = false;
                    \\var i_{d}: usize = 0;
                    \\while (
                , .{ suffix, suffix, suffix });
                try g.genNode(child);
                try g.w.print(
                    \\) {{
                    \\  match_{d} = true;
                    \\  if (i_{d} > max_depth) return error.MaxDepth;
                    \\  i_{d} += 1;
                    \\}}
                    \\break :blk_{d} match_{d}; }}
                , .{ suffix, suffix, suffix, suffix, suffix });
            },
            .@"." => {
                try g.w.print(
                    \\blk_{d}: {{
                    \\    if (p.i < p.source.len) {{
                    \\        p.i += 1;
                    \\        break :blk_{d} true;
                    \\    }}
                    \\    break :blk_{d} false;
                    \\}}
                , .{ suffix, suffix, suffix });
            },
            .literal => |literal| {
                const bytes = g.p.strings.items[literal.off..][0..literal.len];
                try g.w.print(
                    \\blk_{d}: {{
                    \\if (std.mem.startsWith(u8, p.source[p.i..], "
                , .{suffix});
                try std.zig.stringEscape(bytes, g.w);
                try g.w.print(
                    \\")) {{
                    \\p.i += {d};
                    \\    break :blk_{d} true;
                    \\}}
                    \\break :blk_{d} false;
                    \\}}
                , .{ bytes.len, suffix, suffix });
            },
            .class => |ranges| {
                try g.w.writeAll("(p.i < p.source.len and switch (p.source[p.i]) {");
                for (g.p.getExtra(ranges)) |n| {
                    const range = n.get(g.p).range;
                    try g.w.writeAll("'");
                    try std.zig.charEscape(range.start, g.w);
                    try g.w.writeAll("'...'");
                    try std.zig.charEscape(range.end, g.w);
                    try g.w.writeAll("',");
                }
                try g.w.print(
                    \\=> blk_{d}: {{ p.i += 1; break :blk_{d} true; }},
                    \\else => false,
                    \\}})
                , .{ suffix, suffix });
            },
            .sof => try g.w.writeAll("(p.i == 0)"),
            else => unreachable,
        }
    }
};

/// Parser implements a subset of the PEG grammar definition.
/// We don't bother implementing the Action, BEGIN, and END rules
/// and also omit unneeded character escape sequences.
///
/// The full PEG grammar found in the peg(1) man page:
///
/// Grammar         <- Spacing Definition+ EndOfFile
///
/// Definition      <- Identifier LEFTARROW Expression
/// Expression      <- Sequence ( SLASH Sequence )*
/// Sequence        <- Prefix*
/// Prefix          <- AND Action
///                  / ( AND / NOT )? Suffix
/// Suffix          <- Primary ( QUERY / STAR / PLUS )?
/// Primary         <- Identifier !LEFTARROW
///                  / OPEN Expression CLOSE
///                  / Literal
///                  / Class
///                  / DOT
///                  / Action
///                  / BEGIN
///                  / END
///
/// Identifier      <- < IdentStart IdentCont* > Spacing
/// IdentStart      <- [a-zA-Z_]
/// IdentCont       <- IdentStart / [0-9]
/// Literal         <- ['] < ( !['] Char  )* > ['] Spacing
///                  / ["] < ( !["] Char  )* > ["] Spacing
/// Class           <- '[' < ( !']' Range )* > ']' Spacing
/// Range           <- Char '-' Char / Char
/// Char            <- '\\' [abefnrtv'"\[\]\\]
///                  / '\\' [0-3][0-7][0-7]
///                  / '\\' [0-7][0-7]?
///                  / '\\' '-'
///                  / !'\\' .
/// LEFTARROW       <- '<-' Spacing
/// SLASH           <- '/' Spacing
/// AND             <- '&' Spacing
/// NOT             <- '!' Spacing
/// QUERY           <- '?' Spacing
/// STAR            <- '*' Spacing
/// PLUS            <- '+' Spacing
/// OPEN            <- '(' Spacing
/// CLOSE           <- ')' Spacing
/// DOT             <- '.' Spacing
/// Spacing         <- ( Space / Comment )*
/// Comment         <- '#' ( !EndOfLine . )* EndOfLine
/// Space           <- ' ' / '\t' / EndOfLine
/// EndOfLine       <- '\r\n' / '\n' / '\r'
/// EndOfFile       <- !.
/// Action          <- '{' < [^}]* > '}' Spacing
/// BEGIN           <- '<' Spacing
/// END             <- '>' Spacing
const Parser = struct {
    gpa: Allocator,
    /// PEG grammar source
    source: []const u8,
    /// Current index into source
    i: u32,
    nodes: std.ArrayList(Node),
    extra: std.ArrayList(Node.Index),
    strings: std.ArrayList(u8),

    const Node = union(enum) {
        /// Slice into extra
        root: Slice,
        def: struct {
            id: Index,
            expr: Index,
        },
        /// Slice into Parser.source
        id: []const u8,
        /// Slice into extra
        expr: Slice,
        /// Slice into extra
        seq: Slice,
        @"&": Index,
        @"!": Index,
        @"?": Index,
        @"*": Index,
        @"+": Index,
        @".",
        /// Slice into strings
        literal: Slice,
        /// Slice into extra
        class: Slice,
        range: struct {
            start: u8,
            end: u8,
        },
        /// Start of file
        sof,

        const Index = enum(u32) {
            _,

            fn get(index: Index, p: *const Parser) Node {
                return p.nodes.items[@intFromEnum(index)];
            }
        };

        const Slice = struct {
            off: u32,
            len: u32,
        };
    };

    fn init(gpa: Allocator, source: []const u8) Parser {
        return .{
            .gpa = gpa,
            .source = source,
            .i = 0,
            .nodes = .empty,
            .extra = .empty,
            .strings = .empty,
        };
    }

    fn deinit(p: *Parser) void {
        p.nodes.deinit(p.gpa);
        p.extra.deinit(p.gpa);
        p.strings.deinit(p.gpa);
    }

    // Grammar         <- Spacing Definition+ EndOfFile
    // EndOfFile       <- !.
    fn parseGrammar(p: *Parser) !?Node.Index {
        var scratch: std.ArrayList(Node.Index) = .empty;
        defer scratch.deinit(p.gpa);
        _ = p.eatSpacing();
        while (try p.parseDefinition()) |def| {
            try scratch.append(p.gpa, def);
        }
        if (scratch.items.len == 0) return null;
        if (p.peek() != null) return null;
        const defs = try p.addExtra(scratch.items);
        return try p.addNode(.{ .root = defs });
    }

    // Definition      <- Identifier LEFTARROW Expression
    fn parseDefinition(p: *Parser) !?Node.Index {
        const id = try p.parseIdentifier() orelse return null;
        if (!p.eatLeftArrow()) return null;
        const expr = try p.parseExpression() orelse return null;
        return try p.addNode(.{ .def = .{
            .id = id,
            .expr = expr,
        } });
    }

    // Expression      <- Sequence ( SLASH Sequence )*
    fn parseExpression(p: *Parser) error{OutOfMemory}!?Node.Index {
        var scratch: std.ArrayList(Node.Index) = .empty;
        defer scratch.deinit(p.gpa);
        while (try p.parseSequence()) |seq| {
            try scratch.append(p.gpa, seq);
            if (!p.eatSlash()) break;
        }
        if (scratch.items.len == 0) return null;
        const seqs = try p.addExtra(scratch.items);
        return try p.addNode(.{ .expr = seqs });
    }

    // Sequence        <- Prefix*
    fn parseSequence(p: *Parser) !?Node.Index {
        var scratch: std.ArrayList(Node.Index) = .empty;
        defer scratch.deinit(p.gpa);
        while (try p.parsePrefix()) |primary| {
            try scratch.append(p.gpa, primary);
        }
        const primaries = try p.addExtra(scratch.items);
        return try p.addNode(.{ .seq = primaries });
    }

    // Prefix          <- AND Action
    //                  / ( AND / NOT )? Suffix
    fn parsePrefix(p: *Parser) !?Node.Index {
        if (p.eatAnd()) {
            // We only support a single hardcoded "start of file" Action
            if (p.eat('{')) {
                // Action          <- '{' < [^}]* > '}' Spacing
                if (std.mem.startsWith(u8, p.source[p.i..], " (yy->__pos == 0) }")) {
                    while (!p.eat('}')) p.i += 1;
                    _ = p.eatSpacing();
                    return try p.addNode(.sof);
                }
                return null;
            }
            const suffix = try p.parseSuffix() orelse return null;
            return try p.addNode(.{ .@"&" = suffix });
        }
        if (p.eatNot()) {
            const suffix = try p.parseSuffix() orelse return null;
            return try p.addNode(.{ .@"!" = suffix });
        }
        return try p.parseSuffix();
    }

    // Suffix          <- Primary ( QUERY / STAR / PLUS )?
    fn parseSuffix(p: *Parser) !?Node.Index {
        const primary = try p.parsePrimary() orelse return null;
        if (p.eatQuery()) {
            return try p.addNode(.{ .@"?" = primary });
        }
        if (p.eatStar()) {
            return try p.addNode(.{ .@"*" = primary });
        }
        if (p.eatPlus()) {
            return try p.addNode(.{ .@"+" = primary });
        }
        return primary;
    }

    // Primary         <- Identifier !LEFTARROW
    //                  / OPEN Expression CLOSE
    //                  / Literal
    //                  / Class
    //                  / DOT
    //                  / Action
    //                  / BEGIN
    //                  / END
    fn parsePrimary(p: *Parser) !?Node.Index {
        const init_pos = p.savePos();
        if (try p.parseIdentifier()) |id| {
            const pos = p.savePos();
            if (!p.eatLeftArrow()) {
                p.restorePos(pos);
                return id;
            }
        }
        p.restorePos(init_pos);
        if (p.eatOpen()) if (try p.parseExpression()) |expr| if (p.eatClose()) return expr;
        p.restorePos(init_pos);
        if (try p.parseLiteral()) |literal| return literal;
        p.restorePos(init_pos);
        if (try p.parseClass()) |class| return class;
        p.restorePos(init_pos);
        if (p.eatDot()) return try p.addNode(.@".");
        // We don't implement Action, BEGIN, and END.
        return null;
    }

    // Identifier      <- < IdentStart IdentCont* > Spacing
    // IdentStart      <- [a-zA-Z_]
    // IdentCont       <- IdentStart / [0-9]
    fn parseIdentifier(p: *Parser) !?Node.Index {
        const start = p.i;
        switch (p.next() orelse return null) {
            'a'...'z', 'A'...'Z', '_' => {},
            else => return null,
        }
        while (p.peek()) |cont| {
            switch (cont) {
                'a'...'z', 'A'...'Z', '_', '0'...'9' => p.i += 1,
                else => break,
            }
        }
        const id = p.source[start..p.i];
        _ = p.eatSpacing();
        return try p.addNode(.{ .id = id });
    }

    // Literal         <- ['] < ( !['] Char  )* > ['] Spacing
    //                  / ["] < ( !["] Char  )* > ["] Spacing
    fn parseLiteral(p: *Parser) !?Node.Index {
        const quote: u8 = if (p.eat('\'')) '\'' else if (p.eat('"')) '"' else return null;
        const off = p.strings.items.len;
        while (!p.eat(quote)) {
            const byte = p.parseChar() orelse return null;
            try p.strings.append(p.gpa, byte);
        }
        _ = p.eatSpacing();
        return try p.addNode(.{ .literal = .{
            .off = @intCast(off),
            .len = @intCast(p.strings.items.len - off),
        } });
    }

    // Class           <- '[' < ( !']' Range )* > ']' Spacing
    fn parseClass(p: *Parser) !?Node.Index {
        var scratch: std.ArrayList(Node.Index) = .empty;
        defer scratch.deinit(p.gpa);
        if (!p.eat('[')) return null;
        while (!p.eat(']')) {
            const range = try p.parseRange() orelse return null;
            try scratch.append(p.gpa, range);
        }
        _ = p.eatSpacing();
        const ranges = try p.addExtra(scratch.items);
        return try p.addNode(.{ .class = ranges });
    }

    // Range           <- Char '-' Char / Char
    fn parseRange(p: *Parser) !?Node.Index {
        const start = p.parseChar() orelse return null;
        const end = blk: {
            if (p.eat('-')) {
                break :blk p.parseChar() orelse return null;
            }
            break :blk start;
        };
        return try p.addNode(.{ .range = .{
            .start = start,
            .end = end,
        } });
    }

    // Char            <- '\\' [abefnrtv'"\[\]\\]
    //                  / '\\' [0-3][0-7][0-7]
    //                  / '\\' [0-7][0-7]?
    //                  / '\\' '-'
    //                  / !'\\' .
    fn parseChar(p: *Parser) ?u8 {
        if (p.eat('\\')) {
            const c = p.next() orelse return null;
            return switch (c) {
                // Only the escape sequences actually used in the Zig grammar are implemented
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                '\'' => '\'',
                '"' => '"',
                '[' => '[',
                ']' => ']',
                '\\' => '\\',
                '-' => '-',
                '0'...'7' => {
                    // octal
                    if (c <= '3') {
                        const c2 = p.next() orelse return null;
                        if (c2 < '0' or c2 > '7') return null;
                        const c3 = p.next() orelse return null;
                        if (c3 < '0' or c3 > '7') return null;
                        return (c - '0') * 8 * 8 + (c2 - '0') * 8 + (c3 - '0');
                    } else {
                        if (p.peek()) |c2| {
                            if (c2 >= '0' and c2 <= '7') {
                                p.i += 1;
                                return (c - '0') * 8 + (c2 - '0');
                            }
                        }
                        return (c - '0');
                    }
                },
                else => null,
            };
        } else {
            return p.next();
        }
    }

    // LEFTARROW       <- '<-' Spacing
    fn eatLeftArrow(p: *Parser) bool {
        return p.eat('<') and p.eat('-') and p.eatSpacing();
    }

    // SLASH           <- '/' Spacing
    fn eatSlash(p: *Parser) bool {
        return p.eat('/') and p.eatSpacing();
    }

    // AND             <- '&' Spacing
    fn eatAnd(p: *Parser) bool {
        return p.eat('&') and p.eatSpacing();
    }

    // NOT             <- '!' Spacing
    fn eatNot(p: *Parser) bool {
        return p.eat('!') and p.eatSpacing();
    }

    // QUERY           <- '?' Spacing
    fn eatQuery(p: *Parser) bool {
        return p.eat('?') and p.eatSpacing();
    }

    // STAR            <- '*' Spacing
    fn eatStar(p: *Parser) bool {
        return p.eat('*') and p.eatSpacing();
    }

    // PLUS            <- '+' Spacing
    fn eatPlus(p: *Parser) bool {
        return p.eat('+') and p.eatSpacing();
    }

    // OPEN            <- '(' Spacing
    fn eatOpen(p: *Parser) bool {
        return p.eat('(') and p.eatSpacing();
    }

    // CLOSE           <- ')' Spacing
    fn eatClose(p: *Parser) bool {
        return p.eat(')') and p.eatSpacing();
    }

    // DOT             <- '.' Spacing
    fn eatDot(p: *Parser) bool {
        return p.eat('.') and p.eatSpacing();
    }

    // Spacing         <- ( Space / Comment )*
    fn eatSpacing(p: *Parser) bool {
        while (p.eatSpace() or p.eatComment()) {}
        return true;
    }

    // Comment         <- '#' ( !EndOfLine . )* EndOfLine
    fn eatComment(p: *Parser) bool {
        if (!p.eat('#')) return false;
        while (!p.eatEndOfLine()) p.i += 1;
        return true;
    }

    // Space           <- ' ' / '\t' / EndOfLine
    fn eatSpace(p: *Parser) bool {
        return p.eat(' ') or p.eat('\t') or p.eatEndOfLine();
    }

    // EndOfLine       <- '\r\n' / '\n' / '\r'
    fn eatEndOfLine(p: *Parser) bool {
        return p.eat('\n');
    }

    fn peek(p: *Parser) ?u8 {
        if (p.i < p.source.len) {
            return p.source[p.i];
        }
        return null;
    }

    fn next(p: *Parser) ?u8 {
        if (p.i < p.source.len) {
            defer p.i += 1;
            return p.source[p.i];
        }
        return null;
    }

    fn eat(p: *Parser, byte: u8) bool {
        if (p.i < p.source.len and p.source[p.i] == byte) {
            p.i += 1;
            return true;
        }
        return false;
    }

    fn addNode(p: *Parser, node: Node) !Node.Index {
        try p.nodes.append(p.gpa, node);
        return @enumFromInt(p.nodes.items.len - 1);
    }

    fn addExtra(p: *Parser, nodes: []const Node.Index) !Node.Slice {
        const off = p.extra.items.len;
        try p.extra.appendSlice(p.gpa, nodes);
        return .{ .off = @intCast(off), .len = @intCast(p.extra.items.len - off) };
    }

    const Pos = struct {
        i: u32,
        nodes_len: u32,
        extra_len: u32,
        strings_len: u32,
    };

    fn savePos(p: *const Parser) Pos {
        return .{
            .i = p.i,
            .nodes_len = @intCast(p.nodes.items.len),
            .extra_len = @intCast(p.extra.items.len),
            .strings_len = @intCast(p.strings.items.len),
        };
    }

    fn restorePos(p: *Parser, pos: Pos) void {
        assert(p.i >= pos.i);
        p.i = pos.i;
        p.nodes.shrinkRetainingCapacity(pos.nodes_len);
        p.extra.shrinkRetainingCapacity(pos.extra_len);
        p.strings.shrinkRetainingCapacity(pos.strings_len);
    }

    fn getExtra(p: *const Parser, s: Node.Slice) []const Node.Index {
        return p.extra.items[s.off..][0..s.len];
    }
};

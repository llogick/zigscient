//! Use `fromSlice`/`fromSliceNoAlloc` to parse a ZON string into a Zig value. Human readable
//! errors are written to an out parameter.
//!
//! If your data is already available in tree form, consider `fromZoir`/`fromZoirNoAlloc`.
//!
//! To parse into an existing value, see the `updateFrom*` variants. For lower level control over
//! parsing, see `std.zig.ZonGen`. For importing ZON at compile time, use `@import`.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Ast = std.zig.Ast;
const Zoir = std.zig.Zoir;
const ZonGen = std.zig.ZonGen;
const TokenIndex = std.zig.Ast.TokenIndex;
const Base = std.zig.number_literal.Base;
const StrLitErr = std.zig.string_literal.Error;
const NumberLiteralError = std.zig.number_literal.Error;
const assert = std.debug.assert;
const ArrayList = std.ArrayList;
const ArenaAllocator = std.heap.ArenaAllocator;

/// Rename when adding or removing support for a type.
const valid_types = {};

/// Errors encountered while parsing ZON. See `log` and `fatal` for reporting errors to the user.
pub const Diagnostics = struct {
    errors: []const Error,

    /// Log the failure with `std.log.err`.
    pub fn log(self: *const Diagnostics, path: []const u8) void {
        std.log.err("{f}", .{self.fmt(path)});
    }

    test log {
        const gpa = std.testing.allocator;
        var arena_allocator: ArenaAllocator = .init(gpa);
        defer arena_allocator.deinit();
        const arena = arena_allocator.allocator();
        var diagnostics: Diagnostics = undefined;

        const MyType = struct {
            foo: u32,
            bar: u32,
        };

        const parsed: MyType = fromSliceNoAlloc(MyType, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ .foo = 1, .bar = 2 }",
            .diagnostics = &diagnostics,
        }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ParseZon => b: {
                diagnostics.log("input.zon");
                break :b .{ .foo = 0, .bar = 0 };
            },
        };
        _ = parsed;
    }

    /// Log the failure with `std.log.err`, and then terminate the process with exit code 1.
    pub fn fatal(self: *const Diagnostics, path: []const u8) noreturn {
        std.process.fatal("{f}", .{self.fmt(path)});
    }

    test fatal {
        const gpa = std.testing.allocator;
        var arena_allocator: ArenaAllocator = .init(gpa);
        defer arena_allocator.deinit();
        const arena = arena_allocator.allocator();
        var diagnostics: Diagnostics = undefined;

        const MyType = struct {
            foo: u32,
            bar: u32,
        };

        const parsed = fromSliceNoAlloc(MyType, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ .foo = 1, .bar = 2 }",
            .diagnostics = &diagnostics,
        }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ParseZon => diagnostics.fatal("input.zon"),
        };
        _ = parsed;
    }

    /// Formats a human readable description of any errors.
    pub fn fmt(self: *const Diagnostics, path: []const u8) Formatter {
        return .{
            .errors = self.errors,
            .path = path,
        };
    }

    fn astLoc(
        ast: *const Ast,
        maybe_token: Ast.OptionalTokenIndex,
        node_or_offset: u32,
    ) Ast.Location {
        if (maybe_token.unwrap()) |token| {
            var loc = ast.tokenLocation(0, token);
            loc.column += node_or_offset;
            return loc;
        } else {
            const ast_node: Ast.Node.Index = @fromBackingInt(@intCast(node_or_offset));
            const token = ast.nodeMainToken(ast_node);
            return ast.tokenLocation(0, token);
        }
    }

    pub const Formatter = struct {
        path: []const u8,
        errors: []const Error,

        pub fn format(self: *const @This(), w: *std.Io.Writer) std.Io.Writer.Error!void {
            for (self.errors) |e| {
                try w.print("{s}:", .{self.path});
                try w.print("{d}:{d}: error: {s}\n", .{
                    e.loc.line + 1,
                    e.loc.column + 1,
                    e.msg,
                });

                for (e.notes) |note| {
                    try w.print("{s}:", .{self.path});
                    try w.print("{d}:{d}: note: {s}\n", .{
                        note.loc.line + 1,
                        note.loc.column + 1,
                        note.msg,
                    });
                }
            }
        }
    };

    pub const Error = struct {
        msg: []const u8,
        loc: Ast.Location,
        token: Ast.OptionalTokenIndex,
        /// If `token == .none`, this is an `Ast.Node.Index`.
        /// Otherwise, this is a byte offset into `token`.
        node_or_offset: u32,
        notes: []Note,

        const Options = struct {
            msg: []const u8,
            token: Ast.OptionalTokenIndex,
            node_or_offset: u32,
            notes: []Note,
        };

        fn init(ast: *const Ast, options: Error.Options) Error {
            return .{
                .msg = options.msg,
                .loc = astLoc(ast, options.token, options.node_or_offset),
                .token = options.token,
                .node_or_offset = options.node_or_offset,
                .notes = options.notes,
            };
        }
    };

    pub const Note = struct {
        msg: []const u8,
        loc: Ast.Location,
        token: Ast.OptionalTokenIndex,
        /// If `token == .none`, this is an `Ast.Node.Index`.
        /// Otherwise, this is a byte offset into `token`.
        node_or_offset: u32,

        const Options = struct {
            msg: []const u8,
            token: Ast.OptionalTokenIndex,
            node_or_offset: u32,
        };

        fn init(ast: *const Ast, options: Note.Options) @This() {
            return .{
                .msg = options.msg,
                .loc = astLoc(ast, options.token, options.node_or_offset),
                .token = options.token,
                .node_or_offset = options.node_or_offset,
            };
        }
    };
};

pub const Options = struct {
    /// Used for scratch allocations.
    gpa: Allocator,
    /// Used for allocating diagnostics and results.
    arena: Allocator,
    /// The ZON source to parse.
    source: [:0]const u8,
    /// Initialized by the callee with a human readable description of any parse errors that
    /// occured.
    diagnostics: *Diagnostics,
    /// If true, unknown fields do not error.
    ignore_unknown_fields: bool = false,
};

/// Parses the given slice as ZON, writing any errors to `options.diagnostics`.
pub fn fromSlice(T: type, options: Options) error{ OutOfMemory, ParseZon }!T {
    var value: T = undefined;
    try fromSliceInner(T, &value, false, options);
    return value;
}

test fromSlice {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    const TextureOptions = struct {
        const AddressMode = enum { clamp, reflect, wrap, zero };
        address_mode: struct { u: AddressMode = .wrap, v: AddressMode = .wrap },
        mipmaps: bool = true,
        premultiply: bool = true,
    };

    const source =
        \\.{
        \\    .address_mode = .{ .u = .clamp },
        \\    .mipmaps = false,
        \\}
    ;

    var diagnostics: Diagnostics = undefined;
    const options = fromSlice(TextureOptions, .{
        .gpa = gpa,
        .arena = arena,
        .source = source,
        .diagnostics = &diagnostics,
    }) catch |err| switch (err) {
        error.OutOfMemory => return err,
        error.ParseZon => {
            diagnostics.log("texture_options.zon");
            return err;
        },
    };

    try std.testing.expectEqualDeep(TextureOptions{
        .address_mode = .{ .u = .clamp, .v = .wrap },
        .mipmaps = false,
        .premultiply = true,
    }, options);
}

/// Like `fromSlice` but the result type may not contain pointers, allowing it to outlive
/// `options.arena`.
pub fn fromSliceNoAlloc(T: type, options: Options) error{ OutOfMemory, ParseZon }!T {
    comptime assert(!requiresAllocator(T));
    return fromSlice(T, options);
}

/// Similar to `fromSlice`, but updates the existing contents of `value` in place. Fields
/// unspecified by ZON are left unchanged.
///
/// Assumes that `value` points to a fully initialized value prior to this call. Slices and untagged
/// unions are replaced in their entirey when specified. On error, `value` remains valid, but may be
/// partially updated.
pub fn updateFromSlice(
    T: type,
    value: *T,
    options: Options,
) error{ OutOfMemory, ParseZon }!void {
    try fromSliceInner(T, value, true, options);
}

test updateFromSlice {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    const MyTextEditorConfig = struct {
        indentation: enum { spaces, tabs },
        columns: []const u16,
        dark_mode: enum { auto, dark, light },
        theme: []const u8,
    };

    const global_config =
        \\.{
        \\    .indentation = .spaces,
        \\    .columns = .{ 100 },
        \\    .dark_mode = .dark,
        \\}
    ;
    const project_config =
        \\.{
        \\    .indentation = .tabs,
        \\}
    ;

    var config: MyTextEditorConfig = .{
        .indentation = .spaces,
        .columns = &.{},
        .dark_mode = .auto,
        .theme = "default",
    };

    var diagnostics: Diagnostics = undefined;
    updateFromSlice(MyTextEditorConfig, &config, .{
        .gpa = gpa,
        .arena = arena,
        .source = global_config,
        .diagnostics = &diagnostics,
    }) catch |err| switch (err) {
        error.OutOfMemory => return err,
        error.ParseZon => {
            diagnostics.log("global_config.zon");
            return err;
        },
    };
    updateFromSlice(MyTextEditorConfig, &config, .{
        .gpa = gpa,
        .arena = arena,
        .source = project_config,
        .diagnostics = &diagnostics,
    }) catch |err| switch (err) {
        error.OutOfMemory => return err,
        error.ParseZon => {
            diagnostics.log("project_config.zon");
            return err;
        },
    };

    try std.testing.expectEqualDeep(MyTextEditorConfig{
        .indentation = .tabs,
        .columns = &.{100},
        .dark_mode = .dark,
        .theme = "default",
    }, config);
}

/// Like `updateFromSlice` but the `T` may not contain pointers, allowing `value` to outlive
/// `options.arena`.
pub fn updateFromSliceNoAlloc(
    T: type,
    value: *T,
    options: Options,
) error{ OutOfMemory, ParseZon }!void {
    comptime assert(!requiresAllocator(T));
    try fromSliceInner(T, value, true, options);
}

fn fromSliceInner(
    T: type,
    value: *T,
    initialized: bool,
    options: Options,
) error{ OutOfMemory, ParseZon }!void {
    var errors: std.ArrayList(Diagnostics.Error) = .empty;
    defer options.diagnostics.* = .{ .errors = errors.items };

    var ast = try std.zig.Ast.parse(options.gpa, options.source, .{ .mode = .zon });
    defer ast.deinit(options.gpa);

    var zoir = try ZonGen.generate(options.gpa, ast, .{ .parse_str_lits = false });
    defer zoir.deinit(options.gpa);

    try inner(T, value, initialized, .{
        .arena = options.arena,
        .ast = &ast,
        .zoir = &zoir,
        .node = .root,
        .errors = &errors,
        .ignore_unknown_fields = options.ignore_unknown_fields,
    });
}

pub const FromZoirOptions = struct {
    /// Used for allocating diagnostics and results.
    arena: Allocator,
    /// The AST for this ZON value.
    ast: *const Ast,
    /// The zig object intermediate representation of this ZON value.
    zoir: *const Zoir,
    /// The node to start parsing at.
    node: Zoir.Node.Index = .root,
    /// Initialized by the callee with a human readable description of any parse errors that
    /// occured.
    diagnostics: *Diagnostics,
    /// If true, unknown fields do not error.
    ignore_unknown_fields: bool = false,
};

/// Like `fromSlice`, but operates on `Zoir` instead of ZON source.
pub fn fromZoir(T: type, options: FromZoirOptions) error{ OutOfMemory, ParseZon }!T {
    var value: T = undefined;
    try fromZoirInner(T, &value, false, options);
    return value;
}

/// Like `fromSliceNoAlloc`, but operates on `Zoir` instead of ZON source.
pub fn fromZoirNoAlloc(T: type, options: FromZoirOptions) error{ OutOfMemory, ParseZon }!T {
    comptime assert(!requiresAllocator(T));
    return fromZoir(T, options);
}

/// Like `updateFromSlice`, but operates on `Zoir` instead of ZON source.
pub fn updateFromZoir(
    T: type,
    value: *T,
    options: FromZoirOptions,
) error{ OutOfMemory, ParseZon }!void {
    return fromZoirInner(T, value, true, options);
}

/// Like `updateFromSliceNoAlloc`, but operates on `Zoir` instead of ZON source.
pub fn updateFromZoirNoAlloc(
    T: type,
    value: *T,
    options: FromZoirOptions,
) error{ OutOfMemory, ParseZon }!void {
    comptime assert(!requiresAllocator(T));
    return updateFromZoir(T, value, options);
}

fn fromZoirInner(
    T: type,
    value: *T,
    initialized: bool,
    options: FromZoirOptions,
) error{ OutOfMemory, ParseZon }!void {
    var errors: std.ArrayList(Diagnostics.Error) = .empty;
    defer options.diagnostics.* = .{ .errors = errors.items };
    return inner(T, value, initialized, .{
        .arena = options.arena,
        .ast = options.ast,
        .zoir = options.zoir,
        .errors = &errors,
        .ignore_unknown_fields = options.ignore_unknown_fields,
    });
}

const InnerOptions = struct {
    arena: Allocator,
    ast: *const Ast,
    zoir: *const Zoir,
    node: Zoir.Node.Index = .root,
    errors: *std.ArrayList(Diagnostics.Error),
    ignore_unknown_fields: bool,
};

fn inner(
    T: type,
    value: *T,
    initialized: bool,
    options: InnerOptions,
) error{ OutOfMemory, ParseZon }!void {
    comptime assert(canParseType(T));

    if (options.zoir.hasCompileErrors()) {
        for (options.zoir.compile_errors) |e| {
            var notes: std.ArrayList(Diagnostics.Note) = .empty;
            for (e.getNotes(options.zoir)) |note| {
                try notes.append(options.arena, .init(options.ast, .{
                    .msg = try options.arena.dupe(u8, note.msg.get(options.zoir)),
                    .token = note.token,
                    .node_or_offset = note.node_or_offset,
                }));
            }
            try options.errors.append(options.arena, .init(options.ast, .{
                .msg = try options.arena.dupe(u8, e.msg.get(options.zoir)),
                .token = e.token,
                .node_or_offset = e.node_or_offset,
                .notes = notes.items,
            }));
        }
        return error.ParseZon;
    }

    var parser: Parser = .{
        .arena = options.arena,
        .ast = options.ast,
        .zoir = options.zoir,
        .ignore_unknown_fields = options.ignore_unknown_fields,
        .errors = options.errors,
    };

    try parser.parseExprInto(options.node, value, initialized);
}

fn requiresAllocator(T: type) bool {
    _ = valid_types;
    return switch (@typeInfo(T)) {
        .pointer => true,
        .array => |array| return array.len > 0 and requiresAllocator(array.child),
        .@"struct" => |@"struct"| inline for (@"struct".field_types) |field_type| {
            if (requiresAllocator(field_type)) {
                break true;
            }
        } else false,
        .@"union" => |@"union"| inline for (@"union".field_types) |field_type| {
            if (requiresAllocator(field_type)) {
                break true;
            }
        } else false,
        .optional => |optional| requiresAllocator(optional.child),
        .vector => |vector| return vector.len > 0 and requiresAllocator(vector.child),
        else => false,
    };
}

const Parser = struct {
    arena: Allocator,
    ast: *const Ast,
    zoir: *const Zoir,
    errors: *std.ArrayList(Diagnostics.Error),
    ignore_unknown_fields: bool,

    const ParseExprError = error{ ParseZon, OutOfMemory };

    fn parseExprInto(
        self: *Parser,
        node: Zoir.Node.Index,
        out: anytype,
        initialized: bool,
    ) ParseExprError!void {
        return self.parseExprIntoInner(node, out, initialized) catch |err| switch (err) {
            error.WrongType => return self.failExpectedType(@TypeOf(out.*), node),
            else => |e| return e,
        };
    }

    const ParseExprInnerError = error{ ParseZon, OutOfMemory, WrongType };

    fn parseExprIntoInner(
        self: *@This(),
        node: Zoir.Node.Index,
        out: anytype,
        initialized: bool,
    ) ParseExprInnerError!void {
        if (@TypeOf(out.*) == Zoir.Node.Index) {
            out.* = node;
            return;
        }

        switch (@typeInfo(@TypeOf(out.*))) {
            .optional => |optional| if (node.get(self.zoir) == .null) {
                out.* = null;
            } else if (initialized and out.* != null) {
                try self.parseExprIntoInner(node, &out.*.?, true);
            } else {
                var some: optional.child = undefined;
                try self.parseExprIntoInner(node, &some, false);
                out.* = some;
            },
            .bool => out.* = try self.parseBool(node),
            .int => out.* = try self.parseInt(@TypeOf(out.*), node),
            .float => out.* = try self.parseFloat(@TypeOf(out.*), node),
            .@"enum" => out.* = try self.parseEnumLiteral(@TypeOf(out.*), node),
            .pointer => |pointer| switch (pointer.size) {
                .one => {
                    // Get a pointer to update
                    const new = b: {
                        // If the existing value is initialized and non const, use it
                        if (initialized and !pointer.attrs.@"const") break :b out.*;
                        // Otherwise, allocate new memory
                        const new = try self.arena.alignedCreate(
                            pointer.child,
                            if (pointer.attrs.@"align") |a| .fromByteUnits(a) else null,
                        );
                        // If the original value was initialized, dupe it into the new memory
                        if (initialized) new.* = out.*.*;
                        break :b new;
                    };
                    try self.parseExprIntoInner(
                        node,
                        new,
                        initialized,
                    );
                    out.* = new;
                },
                .slice => {
                    // Slices are replaced wholesale since ZON doesn't have syntax for specifying
                    // just a part of a slice.
                    const new = b: {
                        const new = try self.parseSlicePointer(@TypeOf(out.*), node);
                        break :b new;
                    };
                    out.* = new;
                },
                else => comptime unreachable,
            },
            .array => try self.parseArrayInto(node, out),
            .vector => try self.parseVectorInto(node, out),
            .@"struct" => |@"struct"| if (@"struct".is_tuple)
                try self.parseTupleInto(node, out)
            else
                try self.parseStructInto(node, out, initialized),
            .@"union" => try self.parseUnionInto(node, out, initialized),

            else => comptime unreachable,
        }
    }

    /// Prints a message of the form `expected T` where T is first converted to a ZON type. For
    /// example, `**?**u8` becomes `?u8`, and types that involve user specified type names are just
    /// referred to by the type of container.
    fn failExpectedType(
        self: Parser,
        T: type,
        node: Zoir.Node.Index,
    ) error{ ParseZon, OutOfMemory } {
        @branchHint(.cold);
        return self.failExpectedTypeInner(T, false, node);
    }

    fn failExpectedTypeInner(
        self: Parser,
        T: type,
        opt: bool,
        node: Zoir.Node.Index,
    ) error{ ParseZon, OutOfMemory } {
        _ = valid_types;
        switch (@typeInfo(T)) {
            .@"struct" => |@"struct"| if (@"struct".is_tuple) {
                if (opt) {
                    return self.failNode(node, "expected optional tuple");
                } else {
                    return self.failNode(node, "expected tuple");
                }
            } else {
                if (opt) {
                    return self.failNode(node, "expected optional struct");
                } else {
                    return self.failNode(node, "expected struct");
                }
            },
            .@"union" => if (opt) {
                return self.failNode(node, "expected optional union");
            } else {
                return self.failNode(node, "expected union");
            },
            .array => if (opt) {
                return self.failNode(node, "expected optional array");
            } else {
                return self.failNode(node, "expected array");
            },
            .pointer => |pointer| switch (pointer.size) {
                .one => return self.failExpectedTypeInner(pointer.child, opt, node),
                .slice => {
                    if (pointer.child == u8 and
                        pointer.attrs.@"const" and
                        (pointer.sentinel() == null or pointer.sentinel() == 0) and
                        (pointer.attrs.@"align" == null or pointer.attrs.@"align" == 1))
                    {
                        if (opt) {
                            return self.failNode(node, "expected optional string");
                        } else {
                            return self.failNode(node, "expected string");
                        }
                    } else {
                        if (opt) {
                            return self.failNode(node, "expected optional array");
                        } else {
                            return self.failNode(node, "expected array");
                        }
                    }
                },
                else => comptime unreachable,
            },
            .vector, .bool, .int, .float => if (opt) {
                return self.failNodeFmt(node, "expected type '{s}'", .{@typeName(?T)});
            } else {
                return self.failNodeFmt(node, "expected type '{s}'", .{@typeName(T)});
            },
            .@"enum" => if (opt) {
                return self.failNode(node, "expected optional enum literal");
            } else {
                return self.failNode(node, "expected enum literal");
            },
            .optional => |optional| {
                return self.failExpectedTypeInner(optional.child, true, node);
            },
            else => comptime unreachable,
        }
    }

    fn parseBool(self: Parser, node: Zoir.Node.Index) !bool {
        switch (node.get(self.zoir)) {
            .true => return true,
            .false => return false,
            else => return error.WrongType,
        }
    }

    fn parseInt(self: Parser, T: type, node: Zoir.Node.Index) !T {
        switch (node.get(self.zoir)) {
            .int_literal => |int| switch (int) {
                .small => |val| return std.math.cast(T, val) orelse
                    self.failCannotRepresent(T, node),
                .big => |val| return val.toInt(T) catch
                    self.failCannotRepresent(T, node),
            },
            .float_literal => |val| return intFromFloatExact(T, val) orelse
                self.failCannotRepresent(T, node),

            .char_literal => |val| return std.math.cast(T, val) orelse
                self.failCannotRepresent(T, node),
            else => return error.WrongType,
        }
    }

    fn parseFloat(self: Parser, T: type, node: Zoir.Node.Index) !T {
        switch (node.get(self.zoir)) {
            .int_literal => |int| switch (int) {
                .small => |val| return @floatFromInt(val),
                .big => |val| return val.toFloat(T, .nearest_even)[0],
            },
            .float_literal => |val| return @floatCast(val),
            .pos_inf => return std.math.inf(T),
            .neg_inf => return -std.math.inf(T),
            .nan => return std.math.nan(T),
            .char_literal => |val| return @floatFromInt(val),
            else => return error.WrongType,
        }
    }

    fn parseEnumLiteral(self: Parser, T: type, node: Zoir.Node.Index) !T {
        switch (node.get(self.zoir)) {
            .enum_literal => |field_name| {
                // Create a comptime string map for the enum fields
                const enum_info = @typeInfo(T).@"enum";
                comptime var kvs_list: [enum_info.field_names.len]struct { []const u8, T } = undefined;
                inline for (enum_info.field_names, enum_info.field_values, 0..) |enum_field_name, enum_field_value, i| {
                    kvs_list[i] = .{ enum_field_name, @fromBackingInt(@intCast(enum_field_value)) };
                }
                const enum_tags = std.StaticStringMap(T).initComptime(kvs_list);

                // Get the tag if it exists
                const field_name_str = field_name.get(self.zoir);
                return enum_tags.get(field_name_str) orelse
                    self.failUnexpected(T, "enum literal", node, null, field_name_str);
            },
            else => return error.WrongType,
        }
    }

    fn parseSlicePointer(self: *Parser, T: type, node: Zoir.Node.Index) ParseExprInnerError!T {
        switch (node.get(self.zoir)) {
            .string_literal => return self.parseString(T, node),
            .array_literal => |nodes| return self.parseSlice(T, nodes),
            .empty_literal => return self.parseSlice(T, .{ .start = node, .len = 0 }),
            else => return error.WrongType,
        }
    }

    fn parseString(self: *Parser, T: type, node: Zoir.Node.Index) ParseExprInnerError!T {
        const ast_node = node.getAstNode(self.zoir);
        const pointer = @typeInfo(T).pointer;
        var size_hint = ZonGen.strLitSizeHint(self.ast, ast_node);
        if (pointer.sentinel() != null) size_hint += 1;

        var aw: std.Io.Writer.Allocating = .init(self.arena);
        try aw.ensureUnusedCapacity(size_hint);
        defer aw.deinit();
        const result = ZonGen.parseStrLit(self.ast, ast_node, &aw.writer) catch return error.OutOfMemory;
        switch (result) {
            .success => {},
            .failure => |err| {
                const token = self.ast.nodeMainToken(ast_node);
                const raw_string = self.ast.tokenSlice(token);
                return self.failTokenFmt(token, @intCast(err.offset()), "{f}", .{err.fmt(raw_string)});
            },
        }

        if (pointer.child != u8 or
            pointer.size != .slice or
            !pointer.attrs.@"const" or
            (pointer.sentinel() != null and pointer.sentinel() != 0) or
            (pointer.attrs.@"align" != null and pointer.attrs.@"align" != 1))
        {
            return error.WrongType;
        }

        if (pointer.sentinel() != null) {
            return aw.toOwnedSliceSentinel(0);
        } else {
            return aw.toOwnedSlice();
        }
    }

    fn parseSlice(self: *Parser, T: type, nodes: Zoir.Node.Index.Range) !T {
        const pointer = @typeInfo(T).pointer;

        // Make sure we're working with a slice
        switch (pointer.size) {
            .slice => {},
            .one, .many, .c => comptime unreachable,
        }

        // Allocate the slice
        const slice = try self.arena.allocWithOptions(
            pointer.child,
            nodes.len,
            .fromByteUnitsOptional(pointer.attrs.@"align"),
            pointer.sentinel(),
        );

        // Parse the elements and return the slice
        for (slice, 0..) |*elem, i| {
            try self.parseExprInto(nodes.at(@intCast(i)), elem, false);
        }

        return slice;
    }

    fn parseArrayInto(self: *Parser, node: Zoir.Node.Index, out: anytype) !void {
        const nodes: Zoir.Node.Index.Range = switch (node.get(self.zoir)) {
            .array_literal => |nodes| nodes,
            .empty_literal => .{ .start = node, .len = 0 },
            else => return error.WrongType,
        };

        const array = @typeInfo(@TypeOf(out.*)).array;

        // Check if the size matches
        if (nodes.len < array.len) {
            return self.failNodeFmt(
                node,
                "expected {} array elements; found {}",
                .{ array.len, nodes.len },
            );
        } else if (nodes.len > array.len) {
            return self.failNodeFmt(
                nodes.at(array.len),
                "index {} outside of array of length {}",
                .{ array.len, array.len },
            );
        }

        // Parse the elements and return the array
        for (out, 0..) |*elem, i| {
            try self.parseExprInto(nodes.at(@intCast(i)), elem, false);
        }

        if (array.sentinel()) |s| {
            out[array.len] = s;
        }
    }

    fn parseVectorInto(self: *Parser, node: Zoir.Node.Index, out: anytype) !void {
        const vector = @typeInfo(@TypeOf(out.*)).vector;
        var array: [vector.len]vector.child = undefined;
        try self.parseArrayInto(node, &array);
        out.* = array;
    }

    fn parseStructInto(
        self: *Parser,
        node: Zoir.Node.Index,
        out: anytype,
        initialized: bool,
    ) !void {
        const repr = node.get(self.zoir);
        const fields: @FieldType(Zoir.Node, "struct_literal") = switch (repr) {
            .struct_literal => |nodes| nodes,
            .empty_literal => .{ .names = &.{}, .vals = .{ .start = node, .len = 0 } },
            else => return error.WrongType,
        };

        const info = @typeInfo(@TypeOf(out.*)).@"struct";

        // Build a map from field name to index.
        // The special value `comptime_field` indicates that this is actually a comptime field.
        const comptime_field = std.math.maxInt(usize);
        const field_indices: std.StaticStringMap(usize) = comptime b: {
            var kvs_list: [info.field_names.len]struct { []const u8, usize } = undefined;
            for (&kvs_list, info.field_names, info.field_attrs, 0..) |*kv, field_name, field_attrs, i| {
                kv.* = .{ field_name, if (field_attrs.@"comptime") comptime_field else i };
            }
            break :b .initComptime(kvs_list);
        };

        // Parse the struct
        var field_found: [info.field_names.len]bool = @splat(false);
        for (0..fields.names.len) |i| {
            const name = fields.names[i].get(self.zoir);
            const field_index = field_indices.get(name) orelse {
                if (self.ignore_unknown_fields) continue;
                return self.failUnexpected(@TypeOf(out.*), "field", node, i, name);
            };
            if (field_index == comptime_field) {
                return self.failComptimeField(node, i);
            }

            // Mark the field as found. Assert that the found array is not zero length to satisfy
            // the type checker (it can't be since we made it into an iteration of this loop.)
            if (field_found.len == 0) unreachable;
            field_found[field_index] = true;

            switch (field_index) {
                inline 0...(info.field_names.len - 1) => |j| {
                    if (info.field_attrs[j].@"comptime") unreachable;
                    try self.parseExprInto(
                        fields.vals.at(@intCast(i)),
                        &@field(out, info.field_names[j]),
                        initialized,
                    );
                },
                else => unreachable, // Can't be out of bounds
            }
        }

        // Fill in any missing default fields
        if (!initialized) {
            inline for (field_found, 0..) |found, i| {
                if (!found) {
                    const field_attrs = info.field_attrs[i];
                    if (field_attrs.defaultValue(info.field_types[i])) |default| {
                        @field(out, info.field_names[i]) = default;
                    } else {
                        return self.failNodeFmt(
                            node,
                            "missing required field {s}",
                            .{info.field_names[i]},
                        );
                    }
                }
            }
        }
    }

    fn parseTupleInto(self: *Parser, node: Zoir.Node.Index, out: anytype) !void {
        const nodes: Zoir.Node.Index.Range = switch (node.get(self.zoir)) {
            .array_literal => |nodes| nodes,
            .empty_literal => .{ .start = node, .len = 0 },
            else => return error.WrongType,
        };

        const info = @typeInfo(@TypeOf(out.*)).@"struct";

        if (nodes.len > info.field_names.len) {
            return self.failNodeFmt(
                nodes.at(info.field_names.len),
                "index {} outside of tuple length {}",
                .{ info.field_names.len, info.field_names.len },
            );
        }

        inline for (0..info.field_names.len) |i| {
            // Check if we're out of bounds
            if (i >= nodes.len) {
                if (info.field_attrs[i].defaultValue(info.field_types[i])) |default| {
                    @field(out.*, info.field_names[i]) = default;
                } else {
                    return self.failNodeFmt(node, "missing tuple field with index {}", .{i});
                }
            } else {
                if (info.field_attrs[i].@"comptime") {
                    return self.failComptimeField(node, i);
                } else {
                    try self.parseExprInto(nodes.at(i), &out[i], false);
                }
            }
        }
    }

    fn parseUnionInto(
        self: *Parser,
        node: Zoir.Node.Index,
        out: anytype,
        initialized: bool,
    ) !void {
        const @"union" = @typeInfo(@TypeOf(out.*)).@"union";

        if (@"union".field_names.len == 0) comptime unreachable;

        // Gather info on the fields
        const field_indices = b: {
            comptime var kvs_list: [@"union".field_names.len]struct {
                []const u8,
                usize,
            } = undefined;
            inline for (@"union".field_names, 0..) |field_name, i| {
                kvs_list[i] = .{ field_name, i };
            }
            break :b std.StaticStringMap(usize).initComptime(kvs_list);
        };

        // Parse the union
        switch (node.get(self.zoir)) {
            .enum_literal => |field_name| {
                // The union must be tagged for an enum literal to coerce to it
                if (@"union".tag_type == null) {
                    return error.WrongType;
                }

                // Get the index of the named field. We don't use `parseEnum` here as
                // the order of the enum and the order of the union might not match!
                const field_index = b: {
                    const field_name_str = field_name.get(self.zoir);
                    break :b field_indices.get(field_name_str) orelse
                        return self.failUnexpected(
                            @TypeOf(out.*),
                            "field",
                            node,
                            null,
                            field_name_str,
                        );
                };

                // Initialize the union from the given field.
                switch (field_index) {
                    inline 0...@"union".field_names.len - 1 => |i| {
                        // Fail if the field is not void
                        if (@"union".field_types[i] != void)
                            return self.failNode(node, "expected union");

                        // Instantiate the union
                        out.* = @unionInit(@TypeOf(out.*), @"union".field_names[i], {});
                    },
                    else => unreachable, // Can't be out of bounds
                }
            },
            .struct_literal => |struct_fields| {
                if (struct_fields.names.len != 1) {
                    return error.WrongType;
                }

                // Fill in the field we found
                const field_name = struct_fields.names[0];
                const field_name_str = field_name.get(self.zoir);
                const field_val = struct_fields.vals.at(0);
                const field_index = field_indices.get(field_name_str) orelse
                    return self.failUnexpected(@TypeOf(out.*), "field", node, 0, field_name_str);

                switch (field_index) {
                    inline 0...@"union".field_names.len - 1 => |i| {
                        if (@"union".field_types[i] == void) {
                            return self.failNode(field_val, "expected type 'void'");
                        } else {
                            const field_initialized = b: {
                                if (!initialized) break :b false;
                                if (@"union".tag_type == null) break :b false;
                                const tag = @field(@"union".tag_type.?, @"union".field_names[i]);
                                if (out.* != tag) break :b false;
                                break :b true;
                            };
                            if (!field_initialized) {
                                out.* = @unionInit(
                                    @TypeOf(out.*),
                                    @"union".field_names[i],
                                    undefined,
                                );
                            }
                            try self.parseExprInto(
                                field_val,
                                &@field(out.*, @"union".field_names[i]),
                                field_initialized,
                            );
                        }
                    },
                    else => unreachable, // Can't be out of bounds
                }
            },
            else => return error.WrongType,
        }
    }

    fn failTokenFmt(
        self: Parser,
        token: Ast.TokenIndex,
        offset: u32,
        comptime fmt: []const u8,
        args: anytype,
    ) error{ OutOfMemory, ParseZon } {
        @branchHint(.cold);
        return self.failTokenFmtNote(token, offset, fmt, args, &.{});
    }

    fn failTokenFmtNote(
        self: Parser,
        token: Ast.TokenIndex,
        offset: u32,
        comptime fmt: []const u8,
        args: anytype,
        notes: []Diagnostics.Note,
    ) error{ OutOfMemory, ParseZon } {
        @branchHint(.cold);
        comptime assert(args.len > 0);
        try self.errors.append(self.arena, .init(self.ast, .{
            .token = .fromToken(token),
            .node_or_offset = offset,
            .msg = try std.fmt.allocPrint(self.arena, fmt, args),
            .notes = notes,
        }));
        return error.ParseZon;
    }

    fn failNodeFmt(
        self: Parser,
        node: Zoir.Node.Index,
        comptime fmt: []const u8,
        args: anytype,
    ) error{ OutOfMemory, ParseZon } {
        @branchHint(.cold);
        const token = self.ast.nodeMainToken(node.getAstNode(self.zoir));
        return self.failTokenFmt(token, 0, fmt, args);
    }

    fn failToken(
        self: Parser,
        failure: Diagnostics.Error,
    ) error{ OutOfMemory, ParseZon } {
        @branchHint(.cold);
        try self.errors.append(self.arena, failure);
        return error.ParseZon;
    }

    fn failNode(
        self: Parser,
        node: Zoir.Node.Index,
        msg: []const u8,
    ) error{ OutOfMemory, ParseZon } {
        @branchHint(.cold);
        const token = self.ast.nodeMainToken(node.getAstNode(self.zoir));
        return self.failToken(.init(self.ast, .{
            .token = .fromToken(token),
            .node_or_offset = 0,
            .msg = msg,
            .notes = &.{},
        }));
    }

    fn failCannotRepresent(
        self: Parser,
        T: type,
        node: Zoir.Node.Index,
    ) error{ OutOfMemory, ParseZon } {
        @branchHint(.cold);
        return self.failNodeFmt(node, "type '{s}' cannot represent value", .{@typeName(T)});
    }

    fn failUnexpected(
        self: Parser,
        T: type,
        item_kind: []const u8,
        node: Zoir.Node.Index,
        field: ?usize,
        name: []const u8,
    ) error{ OutOfMemory, ParseZon } {
        @branchHint(.cold);
        const token = if (field) |f| b: {
            var buf: [2]Ast.Node.Index = undefined;
            const struct_init = self.ast.fullStructInit(&buf, node.getAstNode(self.zoir)).?;
            const field_node = struct_init.ast.fields[f];
            break :b self.ast.firstToken(field_node) - 2;
        } else self.ast.nodeMainToken(node.getAstNode(self.zoir));
        switch (@typeInfo(T)) {
            inline .@"struct", .@"union", .@"enum" => |info| {
                var notes: std.ArrayList(Diagnostics.Note) = .empty;
                if (info.field_names.len == 0) {
                    try notes.append(self.arena, .init(self.ast, .{
                        .token = .fromToken(token),
                        .node_or_offset = 0,
                        .msg = "none expected",
                    }));
                } else {
                    var aw: std.Io.Writer.Allocating = .init(self.arena);
                    aw.writer.writeAll("supported: ") catch return error.OutOfMemory;
                    inline for (info.field_names, 0..) |field_name, i| {
                        if (i != 0) aw.writer.writeAll(", ") catch return error.OutOfMemory;
                        aw.writer.print("'{f}'", .{std.zig.fmtIdFlags(field_name, .{
                            .allow_primitive = true,
                            .allow_underscore = true,
                        })}) catch return error.OutOfMemory;
                    }
                    try notes.append(self.arena, .init(self.ast, .{
                        .token = .fromToken(token),
                        .node_or_offset = 0,
                        .msg = try aw.toOwnedSlice(),
                    }));
                }
                return self.failTokenFmtNote(
                    token,
                    0,
                    "unexpected {s} '{s}'",
                    .{ item_kind, name },
                    notes.items,
                );
            },
            else => comptime unreachable,
        }
    }

    // Technically we could do this if we were willing to do a deep equal to verify
    // the value matched, but doing so doesn't seem to support any real use cases
    // so isn't worth the complexity at the moment.
    fn failComptimeField(
        self: Parser,
        node: Zoir.Node.Index,
        field: usize,
    ) error{ OutOfMemory, ParseZon } {
        @branchHint(.cold);
        const ast_node = node.getAstNode(self.zoir);
        var buf: [2]Ast.Node.Index = undefined;
        const token = if (self.ast.fullStructInit(&buf, ast_node)) |struct_init| b: {
            const field_node = struct_init.ast.fields[field];
            break :b self.ast.firstToken(field_node);
        } else b: {
            const array_init = self.ast.fullArrayInit(&buf, ast_node).?;
            const value_node = array_init.ast.elements[field];
            break :b self.ast.firstToken(value_node);
        };
        return self.failToken(.init(self.ast, .{
            .token = .fromToken(token),
            .node_or_offset = 0,
            .msg = "cannot initialize comptime field",
            .notes = &.{},
        }));
    }
};

fn intFromFloatExact(T: type, value: anytype) ?T {
    const max: @TypeOf(value) = @floatFromInt(std.math.maxInt(T));
    const min: @TypeOf(value) = @floatFromInt(std.math.minInt(T));
    if (value > max or value < min) {
        return null;
    }

    if (std.math.isNan(value) or std.math.trunc(value) != value) {
        return null;
    }

    return @intFromFloat(value);
}

fn canParseType(T: type) bool {
    comptime return canParseTypeInner(T, &.{}, false);
}

fn canParseTypeInner(
    T: type,
    /// Visited structs and unions, to avoid infinite recursion.
    /// Tracking more types is unnecessary, and a little complex due to optional nesting.
    visited: []const type,
    parent_is_optional: bool,
) bool {
    return switch (@typeInfo(T)) {
        .bool,
        .int,
        .float,
        .null,
        .@"enum",
        => true,

        .noreturn,
        .void,
        .type,
        .undefined,
        .error_union,
        .error_set,
        .@"fn",
        .frame,
        .@"anyframe",
        .@"opaque",
        .spirv,
        .comptime_int,
        .comptime_float,
        .enum_literal,
        => false,

        .pointer => |pointer| switch (pointer.size) {
            .one => canParseTypeInner(pointer.child, visited, parent_is_optional),
            .slice => canParseTypeInner(pointer.child, visited, false),
            .many, .c => false,
        },

        .optional => |optional| if (parent_is_optional)
            false
        else
            canParseTypeInner(optional.child, visited, true),

        .array => |array| canParseTypeInner(array.child, visited, false),
        .vector => |vector| canParseTypeInner(vector.child, visited, false),

        .@"struct" => |@"struct"| {
            for (visited) |V| if (T == V) return true;
            const new_visited = visited ++ .{T};
            for (@"struct".field_types, @"struct".field_attrs) |field_type, field_attrs| {
                if (!field_attrs.@"comptime" and !canParseTypeInner(field_type, new_visited, false)) {
                    return false;
                }
            }
            return true;
        },
        .@"union" => |@"union"| {
            for (visited) |V| if (T == V) return true;
            const new_visited = visited ++ .{T};
            for (@"union".field_types) |field_type| {
                if (field_type != void and !canParseTypeInner(field_type, new_visited, false)) {
                    return false;
                }
            }
            return true;
        },
    };
}

test "std.zon parse canParseType" {
    try std.testing.expect(!comptime canParseType(void));
    try std.testing.expect(!comptime canParseType(struct { f: [*]u8 }));
    try std.testing.expect(!comptime canParseType(struct { error{foo} }));
    try std.testing.expect(!comptime canParseType(union(enum) { a: void, b: [*c]u8 }));
    try std.testing.expect(!comptime canParseType(@Vector(0, [*c]u8)));
    try std.testing.expect(!comptime canParseType(*?[*c]u8));
    try std.testing.expect(comptime canParseType(enum(u8) { _ }));
    try std.testing.expect(comptime canParseType(union { foo: void }));
    try std.testing.expect(comptime canParseType(union(enum) { foo: void }));
    try std.testing.expect(!comptime canParseType(comptime_float));
    try std.testing.expect(!comptime canParseType(comptime_int));
    try std.testing.expect(comptime canParseType(struct { comptime foo: ??u8 = null }));
    try std.testing.expect(!comptime canParseType(@TypeOf(.foo)));
    try std.testing.expect(comptime canParseType(?u8));
    try std.testing.expect(comptime canParseType(*?*u8));
    try std.testing.expect(comptime canParseType(?struct {
        foo: ?struct {
            ?union(enum) {
                a: ?@Vector(0, ?*u8),
            },
            ?struct {
                f: ?[]?u8,
            },
        },
    }));
    try std.testing.expect(!comptime canParseType(??u8));
    try std.testing.expect(!comptime canParseType(?*?u8));
    try std.testing.expect(!comptime canParseType(*?*?*u8));
    try std.testing.expect(!comptime canParseType(struct { x: comptime_int = 2 }));
    try std.testing.expect(!comptime canParseType(struct { x: comptime_float = 2 }));
    try std.testing.expect(comptime canParseType(struct { comptime x: @TypeOf(.foo) = .foo }));
    try std.testing.expect(!comptime canParseType(struct { comptime_int }));
    const Recursive = struct { foo: ?*@This() };
    try std.testing.expect(comptime canParseType(Recursive));

    // Make sure we validate nested optional before we early out due to already having seen
    // a type recursion!
    try std.testing.expect(!comptime canParseType(struct {
        add_to_visited: ?u8,
        retrieve_from_visited: ??u8,
    }));
}

test "std.zon requiresAllocator" {
    try std.testing.expect(!requiresAllocator(u8));
    try std.testing.expect(!requiresAllocator(f32));
    try std.testing.expect(!requiresAllocator(enum { foo }));
    try std.testing.expect(!requiresAllocator(struct { f32 }));
    try std.testing.expect(!requiresAllocator(struct { x: f32 }));
    try std.testing.expect(!requiresAllocator([0][]const u8));
    try std.testing.expect(!requiresAllocator([2]u8));
    try std.testing.expect(!requiresAllocator(union { x: f32, y: f32 }));
    try std.testing.expect(!requiresAllocator(union(enum) { x: f32, y: f32 }));
    try std.testing.expect(!requiresAllocator(?f32));
    try std.testing.expect(!requiresAllocator(void));
    try std.testing.expect(!requiresAllocator(@TypeOf(null)));
    try std.testing.expect(!requiresAllocator(@Vector(3, u8)));
    try std.testing.expect(!requiresAllocator(@Vector(0, *const u8)));

    try std.testing.expect(requiresAllocator([]u8));
    try std.testing.expect(requiresAllocator(*struct { u8, u8 }));
    try std.testing.expect(requiresAllocator([1][]const u8));
    try std.testing.expect(requiresAllocator(struct { x: i32, y: []u8 }));
    try std.testing.expect(requiresAllocator(union { x: i32, y: []u8 }));
    try std.testing.expect(requiresAllocator(union(enum) { x: i32, y: []u8 }));
    try std.testing.expect(requiresAllocator(?[]u8));
    try std.testing.expect(requiresAllocator(@Vector(3, *const u8)));
}

test "std.zon ast errors" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;
    try std.testing.expectError(
        error.ParseZon,
        fromSliceNoAlloc(struct {}, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{.x = 1 .y = 2}",
            .diagnostics = &diagnostics,
        }),
    );
    try std.testing.expectFmt(
        \\input.zon:1:13: error: expected ',' after initializer
        \\
    , "{f}", .{diagnostics.fmt("input.zon")});
}

test "std.zon comments" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    try std.testing.expectEqual(@as(u8, 10), fromSliceNoAlloc(u8, .{
        .gpa = gpa,
        .arena = arena,
        .source =
        \\// comment
        \\10 // comment
        \\// comment
        ,
        .diagnostics = &diagnostics,
    }));

    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(u8, .{
            .gpa = gpa,
            .arena = arena,
            .source =
            \\//! comment
            \\10 // comment
            \\// comment
            ,
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected expression, found 'a document comment'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }
}

test "std.zon failure/oom formatting" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    try std.testing.expectError(error.OutOfMemory, fromSlice([]const u8, .{
        .gpa = .failing,
        .arena = arena,
        .source = "\"foo\"",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectFmt(
        \\
    , "{f}", .{diagnostics.fmt("input.zon")});
}

test "std.zon fromSlice syntax error" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;
    try std.testing.expectError(
        error.ParseZon,
        fromSliceNoAlloc(u8, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{",
            .diagnostics = &diagnostics,
        }),
    );
    try std.testing.expectFmt(
        \\input.zon:1:3: error: expected expression, found 'EOF'
        \\
    , "{f}", .{diagnostics.fmt("input.zon")});
}

test "std.zon optional" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    // Basic usage
    {
        const none = try fromSliceNoAlloc(?u32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "null",
            .diagnostics = &diagnostics,
        });
        try std.testing.expect(none == null);
        const some = try fromSliceNoAlloc(?u32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "1",
            .diagnostics = &diagnostics,
        });
        try std.testing.expect(some.? == 1);
    }

    // Deep free
    {
        const none = try fromSlice(?[]const u8, .{
            .gpa = gpa,
            .arena = arena,
            .source = "null",
            .diagnostics = &diagnostics,
        });
        try std.testing.expect(none == null);
        const some = try fromSlice(?[]const u8, .{
            .gpa = gpa,
            .arena = arena,
            .source = "\"foo\"",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqualStrings("foo", some.?);
    }
}

test "std.zon unions" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    // Unions
    {
        const Tagged = union(enum) { x: f32, @"y y": bool, z, @"z z" };
        const Untagged = union { x: f32, @"y y": bool, z: void, @"z z": void };

        const tagged_x = try fromSliceNoAlloc(Tagged, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{.x = 1.5}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(Tagged{ .x = 1.5 }, tagged_x);
        const tagged_y = try fromSliceNoAlloc(Tagged, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{.@\"y y\" = true}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(Tagged{ .@"y y" = true }, tagged_y);
        const tagged_z_shorthand = try fromSliceNoAlloc(Tagged, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".z",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(@as(Tagged, .z), tagged_z_shorthand);
        const tagged_zz_shorthand = try fromSliceNoAlloc(Tagged, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".@\"z z\"",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(@as(Tagged, .@"z z"), tagged_zz_shorthand);

        const untagged_x = try fromSliceNoAlloc(Untagged, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{.x = 1.5}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expect(untagged_x.x == 1.5);
        const untagged_y = try fromSliceNoAlloc(Untagged, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{.@\"y y\" = true}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expect(untagged_y.@"y y");
    }

    // Deep free
    {
        const Union = union(enum) { bar: []const u8, baz: bool };

        const noalloc = try fromSlice(Union, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{.baz = false}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(Union{ .baz = false }, noalloc);

        const alloc = try fromSlice(Union, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{.bar = \"qux\"}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqualDeep(Union{ .bar = "qux" }, alloc);
    }

    // Unknown field
    {
        const Union = union { x: f32, y: f32 };
        try std.testing.expectError(
            error.ParseZon,
            fromSlice(Union, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{.z=2.5}",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:4: error: unexpected field 'z'
            \\input.zon:1:4: note: supported: 'x', 'y'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Explicit void field
    {
        const Union = union(enum) { x: void };
        try std.testing.expectError(
            error.ParseZon,
            fromSlice(Union, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{.x=1}",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:6: error: expected type 'void'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Extra field
    {
        const Union = union { x: f32, y: bool };
        try std.testing.expectError(
            error.ParseZon,
            fromSlice(Union, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{.x = 1.5, .y = true}",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:2: error: expected union
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // No fields
    {
        const Union = union { x: f32, y: bool };
        try std.testing.expectError(
            error.ParseZon,
            fromSlice(Union, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{}",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:2: error: expected union
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Enum literals cannot coerce into untagged unions
    {
        const Union = union { x: void };
        try std.testing.expectError(error.ParseZon, fromSlice(Union, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".x",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:2: error: expected union
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Unknown field for enum literal coercion
    {
        const Union = union(enum) { x: void };
        try std.testing.expectError(error.ParseZon, fromSlice(Union, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".y",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:2: error: unexpected field 'y'
            \\input.zon:1:2: note: supported: 'x'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Non void field for enum literal coercion
    {
        const Union = union(enum) { x: f32 };
        try std.testing.expectError(error.ParseZon, fromSlice(Union, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".x",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:2: error: expected union
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }
}

test "std.zon structs" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    // Structs (various sizes tested since they're parsed differently)
    {
        const Vec0 = struct {};
        const Vec1 = struct { x: f32 };
        const Vec2 = struct { x: f32, y: f32 };
        const Vec3 = struct { x: f32, y: f32, z: f32 };

        const zero = try fromSliceNoAlloc(Vec0, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(Vec0{}, zero);

        const one = try fromSliceNoAlloc(Vec1, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{.x = 1.2}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(Vec1{ .x = 1.2 }, one);

        const two = try fromSliceNoAlloc(Vec2, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{.x = 1.2, .y = 3.4}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(Vec2{ .x = 1.2, .y = 3.4 }, two);

        const three = try fromSliceNoAlloc(Vec3, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{.x = 1.2, .y = 3.4, .z = 5.6}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(Vec3{ .x = 1.2, .y = 3.4, .z = 5.6 }, three);
    }

    // Deep free (structs and arrays)
    {
        const Foo = struct { bar: []const u8, baz: []const []const u8 };

        const parsed = try fromSlice(Foo, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{.bar = \"qux\", .baz = .{\"a\", \"b\"}}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqualDeep(Foo{ .bar = "qux", .baz = &.{ "a", "b" } }, parsed);
    }

    // Unknown field
    {
        const Vec2 = struct { x: f32, y: f32 };
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc(Vec2, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{.x=1.5, .z=2.5}",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:12: error: unexpected field 'z'
            \\input.zon:1:12: note: supported: 'x', 'y'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Duplicate field
    {
        const Vec2 = struct { x: f32, y: f32 };
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc(Vec2, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{.x=1.5, .x=2.5, .x=3.5}",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:4: error: duplicate struct field name
            \\input.zon:1:12: note: duplicate name here
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Ignore unknown fields
    {
        const Vec2 = struct { x: f32, y: f32 = 2.0 };
        const parsed = try fromSliceNoAlloc(Vec2, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ .x = 1.0, .z = 3.0 }",
            .ignore_unknown_fields = true,
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(Vec2{ .x = 1.0, .y = 2.0 }, parsed);
    }

    // Unknown field when struct has no fields (regression test)
    {
        const Vec2 = struct {};
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc(Vec2, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{.x=1.5, .z=2.5}",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:4: error: unexpected field 'x'
            \\input.zon:1:4: note: none expected
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Missing field
    {
        const Vec2 = struct { x: f32, y: f32 };
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc(Vec2, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{.x=1.5}",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:2: error: missing required field y
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Default field
    {
        const Vec2 = struct { x: f32, y: f32 = 1.5 };
        const parsed = try fromSliceNoAlloc(Vec2, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{.x = 1.2}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(Vec2{ .x = 1.2, .y = 1.5 }, parsed);
    }

    // Comptime field
    {
        const Vec2 = struct { x: f32, comptime y: f32 = 1.5 };
        const parsed = try fromSliceNoAlloc(Vec2, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{.x = 1.2}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(Vec2{ .x = 1.2, .y = 1.5 }, parsed);
    }

    // Comptime field assignment
    {
        const Vec2 = struct { x: f32, comptime y: f32 = 1.5 };
        const parsed = fromSliceNoAlloc(Vec2, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{.x = 1.2, .y = 1.5}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectError(error.ParseZon, parsed);
        try std.testing.expectFmt(
            \\input.zon:1:18: error: cannot initialize comptime field
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Enum field (regression test, we were previously getting the field name in an
    // incorrect way that broke for enum values)
    {
        const Vec0 = struct { x: enum { x } };
        const parsed = try fromSliceNoAlloc(Vec0, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ .x = .x }",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(Vec0{ .x = .x }, parsed);
    }

    // Enum field and struct field with @
    {
        const Vec0 = struct { @"x x": enum { @"x x" } };
        const parsed = try fromSliceNoAlloc(Vec0, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ .@\"x x\" = .@\"x x\" }",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(Vec0{ .@"x x" = .@"x x" }, parsed);
    }

    // Type expressions are not allowed
    {
        // Structs
        {
            const parsed = fromSliceNoAlloc(struct {}, .{
                .gpa = gpa,
                .arena = arena,
                .source = "Empty{}",
                .diagnostics = &diagnostics,
            });
            try std.testing.expectError(error.ParseZon, parsed);
            try std.testing.expectFmt(
                \\input.zon:1:1: error: types are not available in ZON
                \\input.zon:1:1: note: replace the type with '.'
                \\
            , "{f}", .{diagnostics.fmt("input.zon")});
        }

        // Arrays
        {
            const parsed = fromSliceNoAlloc([3]u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = "[3]u8{1, 2, 3}",
                .diagnostics = &diagnostics,
            });
            try std.testing.expectError(error.ParseZon, parsed);
            try std.testing.expectFmt(
                \\input.zon:1:1: error: types are not available in ZON
                \\input.zon:1:1: note: replace the type with '.'
                \\
            , "{f}", .{diagnostics.fmt("input.zon")});
        }

        // Slices
        {
            const parsed = fromSlice([]u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = "[]u8{1, 2, 3}",
                .diagnostics = &diagnostics,
            });
            try std.testing.expectError(error.ParseZon, parsed);
            try std.testing.expectFmt(
                \\input.zon:1:1: error: types are not available in ZON
                \\input.zon:1:1: note: replace the type with '.'
                \\
            , "{f}", .{diagnostics.fmt("input.zon")});
        }

        // Tuples
        {
            const parsed = fromSliceNoAlloc(struct { u8, u8, u8 }, .{
                .gpa = gpa,
                .arena = arena,
                .source = "Tuple{1, 2, 3}",
                .diagnostics = &diagnostics,
            });
            try std.testing.expectError(error.ParseZon, parsed);
            try std.testing.expectFmt(
                \\input.zon:1:1: error: types are not available in ZON
                \\input.zon:1:1: note: replace the type with '.'
                \\
            , "{f}", .{diagnostics.fmt("input.zon")});
        }

        // Nested
        {
            const parsed = fromSliceNoAlloc(struct {}, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{ .x = Tuple{1, 2, 3} }",
                .diagnostics = &diagnostics,
            });
            try std.testing.expectError(error.ParseZon, parsed);
            try std.testing.expectFmt(
                \\input.zon:1:9: error: types are not available in ZON
                \\input.zon:1:9: note: replace the type with '.'
                \\
            , "{f}", .{diagnostics.fmt("input.zon")});
        }
    }
}

test "std.zon tuples" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    // Structs (various sizes tested since they're parsed differently)
    {
        const Tuple0 = struct {};
        const Tuple1 = struct { f32 };
        const Tuple2 = struct { f32, bool };
        const Tuple3 = struct { f32, bool, u8 };

        const zero = try fromSliceNoAlloc(Tuple0, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(Tuple0{}, zero);

        const one = try fromSliceNoAlloc(Tuple1, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{1.2}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(Tuple1{1.2}, one);

        const two = try fromSliceNoAlloc(Tuple2, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{1.2, true}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(Tuple2{ 1.2, true }, two);

        const three = try fromSliceNoAlloc(Tuple3, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{1.2, false, 3}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(Tuple3{ 1.2, false, 3 }, three);
    }

    // Deep free
    {
        const Tuple = struct { []const u8, []const u8 };
        const parsed = try fromSlice(Tuple, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{\"hello\", \"world\"}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqualDeep(Tuple{ "hello", "world" }, parsed);
    }

    // Extra field
    {
        const Tuple = struct { f32, bool };
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc(Tuple, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{0.5, true, 123}",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:14: error: index 2 outside of tuple length 2
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Extra field
    {
        const Tuple = struct { f32, bool };
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc(Tuple, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{0.5}",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:2: error: missing tuple field with index 1
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Tuple with unexpected field names
    {
        const Tuple = struct { f32 };
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc(Tuple, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{.foo = 10.0}",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:2: error: expected tuple
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Struct with missing field names
    {
        const Struct = struct { foo: f32 };
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc(Struct, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{10.0}",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:2: error: expected struct
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Comptime field
    {
        const Vec2 = struct { f32, comptime f32 = 1.5 };
        const parsed = try fromSliceNoAlloc(Vec2, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ 1.2 }",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(Vec2{ 1.2, 1.5 }, parsed);
    }

    // Comptime field assignment
    {
        const Vec2 = struct { f32, comptime f32 = 1.5 };
        const parsed = fromSliceNoAlloc(Vec2, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ 1.2, 1.5}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectError(error.ParseZon, parsed);
        try std.testing.expectFmt(
            \\input.zon:1:9: error: cannot initialize comptime field
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }
}

// Test sizes 0 to 3 since small sizes get parsed differently
test "std.zon arrays and slices" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    // Literals
    {
        // Arrays
        {
            const zero = try fromSliceNoAlloc([0]u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{}",
                .diagnostics = &diagnostics,
            });
            try std.testing.expectEqualSlices(u8, &@as([0]u8, .{}), &zero);

            const one = try fromSliceNoAlloc([1]u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{'a'}",
                .diagnostics = &diagnostics,
            });
            try std.testing.expectEqualSlices(u8, &@as([1]u8, .{'a'}), &one);

            const two = try fromSliceNoAlloc([2]u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{'a', 'b'}",
                .diagnostics = &diagnostics,
            });
            try std.testing.expectEqualSlices(u8, &@as([2]u8, .{ 'a', 'b' }), &two);

            const two_comma = try fromSliceNoAlloc([2]u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{'a', 'b',}",
                .diagnostics = &diagnostics,
            });
            try std.testing.expectEqualSlices(u8, &@as([2]u8, .{ 'a', 'b' }), &two_comma);

            const three = try fromSliceNoAlloc([3]u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{'a', 'b', 'c'}",
                .diagnostics = &diagnostics,
            });
            try std.testing.expectEqualSlices(u8, &.{ 'a', 'b', 'c' }, &three);

            const sentinel = try fromSliceNoAlloc([3:'z']u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{'a', 'b', 'c'}",
                .diagnostics = &diagnostics,
            });
            const expected_sentinel: [3:'z']u8 = .{ 'a', 'b', 'c' };
            try std.testing.expectEqualSlices(u8, &expected_sentinel, &sentinel);
        }

        // Slice literals
        {
            const zero = try fromSlice([]const u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{}",
                .diagnostics = &diagnostics,
            });
            try std.testing.expectEqualSlices(u8, @as([]const u8, &.{}), zero);

            const one = try fromSlice([]u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{'a'}",
                .diagnostics = &diagnostics,
            });
            try std.testing.expectEqualSlices(u8, &.{'a'}, one);

            const two = try fromSlice([]const u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{'a', 'b'}",
                .diagnostics = &diagnostics,
            });
            try std.testing.expectEqualSlices(u8, &.{ 'a', 'b' }, two);

            const two_comma = try fromSlice([]const u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{'a', 'b',}",
                .diagnostics = &diagnostics,
            });
            try std.testing.expectEqualSlices(u8, &.{ 'a', 'b' }, two_comma);

            const three = try fromSlice([]u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{'a', 'b', 'c'}",
                .diagnostics = &diagnostics,
            });
            try std.testing.expectEqualSlices(u8, &.{ 'a', 'b', 'c' }, three);

            const sentinel = try fromSlice([:'z']const u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{'a', 'b', 'c'}",
                .diagnostics = &diagnostics,
            });
            const expected_sentinel: [:'z']const u8 = &.{ 'a', 'b', 'c' };
            try std.testing.expectEqualSlices(u8, expected_sentinel, sentinel);
        }
    }

    // Deep free
    {
        // Arrays
        {
            const parsed = try fromSlice([1][]const u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{\"abc\"}",
                .diagnostics = &diagnostics,
            });
            const expected: [1][]const u8 = .{"abc"};
            try std.testing.expectEqualDeep(expected, parsed);
        }

        // Slice literals
        {
            const parsed = try fromSlice([]const []const u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{\"abc\"}",
                .diagnostics = &diagnostics,
            });
            const expected: []const []const u8 = &.{"abc"};
            try std.testing.expectEqualDeep(expected, parsed);
        }
    }

    // Sentinels and alignment
    {
        // Arrays
        {
            const sentinel = try fromSliceNoAlloc([1:2]u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{1}",
                .diagnostics = &diagnostics,
            });
            try std.testing.expectEqual(@as(usize, 1), sentinel.len);
            try std.testing.expectEqual(@as(u8, 1), sentinel[0]);
            try std.testing.expectEqual(@as(u8, 2), sentinel[1]);
        }

        // Slice literals
        {
            const sentinel = try fromSlice([:2]align(4) u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{1}",
                .diagnostics = &diagnostics,
            });
            try std.testing.expectEqual(@as(usize, 1), sentinel.len);
            try std.testing.expectEqual(@as(u8, 1), sentinel[0]);
            try std.testing.expectEqual(@as(u8, 2), sentinel[1]);
        }
    }

    // Expect 0 find 3
    {
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc([0]u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{'a', 'b', 'c'}",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:3: error: index 0 outside of array of length 0
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Expect 1 find 2
    {
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc([1]u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{'a', 'b'}",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:8: error: index 1 outside of array of length 1
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Expect 2 find 1
    {
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc([2]u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{'a'}",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:2: error: expected 2 array elements; found 1
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Expect 3 find 0
    {
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc([3]u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{}",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:2: error: expected 3 array elements; found 0
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Wrong inner type
    {
        // Array
        {
            try std.testing.expectError(
                error.ParseZon,
                fromSliceNoAlloc([3]bool, .{
                    .gpa = gpa,
                    .arena = arena,
                    .source = ".{'a', 'b', 'c'}",
                    .diagnostics = &diagnostics,
                }),
            );
            try std.testing.expectFmt(
                \\input.zon:1:3: error: expected type 'bool'
                \\
            , "{f}", .{diagnostics.fmt("input.zon")});
        }

        // Slice
        {
            try std.testing.expectError(
                error.ParseZon,
                fromSlice([]bool, .{
                    .gpa = gpa,
                    .arena = arena,
                    .source = ".{'a', 'b', 'c'}",
                    .diagnostics = &diagnostics,
                }),
            );
            try std.testing.expectFmt(
                \\input.zon:1:3: error: expected type 'bool'
                \\
            , "{f}", .{diagnostics.fmt("input.zon")});
        }
    }

    // Complete wrong type
    {
        // Array
        {
            try std.testing.expectError(
                error.ParseZon,
                fromSliceNoAlloc([3]u8, .{
                    .gpa = gpa,
                    .arena = arena,
                    .source = "'a'",
                    .diagnostics = &diagnostics,
                }),
            );
            try std.testing.expectFmt(
                \\input.zon:1:1: error: expected array
                \\
            , "{f}", .{diagnostics.fmt("input.zon")});
        }

        // Slice
        {
            try std.testing.expectError(
                error.ParseZon,
                fromSlice([]u8, .{ .gpa = gpa, .arena = arena, .source = "'a'", .diagnostics = &diagnostics }),
            );
            try std.testing.expectFmt(
                \\input.zon:1:1: error: expected array
                \\
            , "{f}", .{diagnostics.fmt("input.zon")});
        }
    }

    // Address of is not allowed (indirection for slices in ZON is implicit)
    {
        try std.testing.expectError(
            error.ParseZon,
            fromSlice([]u8, .{ .gpa = gpa, .arena = arena, .source = "  &.{'a', 'b', 'c'}", .diagnostics = &diagnostics }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:3: error: pointers are not available in ZON
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }
}

test "std.zon string literal" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    // Basic string literal
    {
        const parsed = try fromSlice([]const u8, .{
            .gpa = gpa,
            .arena = arena,
            .source = "\"abc\"",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqualStrings(@as([]const u8, "abc"), parsed);
    }

    // String literal with escape characters
    {
        const parsed = try fromSlice([]const u8, .{
            .gpa = gpa,
            .arena = arena,
            .source = "\"ab\\nc\"",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqualStrings(@as([]const u8, "ab\nc"), parsed);
    }

    // String literal with embedded null
    {
        const parsed = try fromSlice([]const u8, .{
            .gpa = gpa,
            .arena = arena,
            .source = "\"ab\\x00c\"",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqualStrings(@as([]const u8, "ab\x00c"), parsed);
    }

    // Passing string literal to a mutable slice
    {
        {
            try std.testing.expectError(
                error.ParseZon,
                fromSlice([]u8, .{ .gpa = gpa, .arena = arena, .source = "\"abcd\"", .diagnostics = &diagnostics }),
            );
            try std.testing.expectFmt(
                \\input.zon:1:1: error: expected array
                \\
            , "{f}", .{diagnostics.fmt("input.zon")});
        }

        {
            try std.testing.expectError(
                error.ParseZon,
                fromSlice([]u8, .{ .gpa = gpa, .arena = arena, .source = "\\\\abcd", .diagnostics = &diagnostics }),
            );
            try std.testing.expectFmt(
                \\input.zon:1:1: error: expected array
                \\
            , "{f}", .{diagnostics.fmt("input.zon")});
        }
    }

    // Passing string literal to a array
    {
        {
            var ast = try std.zig.Ast.parse(gpa, "\"abcd\"", .{ .mode = .zon });
            defer ast.deinit(gpa);
            var zoir = try ZonGen.generate(gpa, ast, .{ .parse_str_lits = false });
            defer zoir.deinit(gpa);
            try std.testing.expectError(
                error.ParseZon,
                fromSliceNoAlloc([4:0]u8, .{
                    .gpa = gpa,
                    .arena = arena,
                    .source = "\"abcd\"",
                    .diagnostics = &diagnostics,
                }),
            );
            try std.testing.expectFmt(
                \\input.zon:1:1: error: expected array
                \\
            , "{f}", .{diagnostics.fmt("input.zon")});
        }

        {
            try std.testing.expectError(
                error.ParseZon,
                fromSliceNoAlloc([4:0]u8, .{
                    .gpa = gpa,
                    .arena = arena,
                    .source = "\\\\abcd",
                    .diagnostics = &diagnostics,
                }),
            );
            try std.testing.expectFmt(
                \\input.zon:1:1: error: expected array
                \\
            , "{f}", .{diagnostics.fmt("input.zon")});
        }
    }

    // Zero terminated slices
    {
        {
            const parsed: [:0]const u8 = try fromSlice([:0]const u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = "\"abc\"",
                .diagnostics = &diagnostics,
            });
            try std.testing.expectEqualStrings("abc", parsed);
            try std.testing.expectEqual(@as(u8, 0), parsed[3]);
        }

        {
            const parsed: [:0]const u8 = try fromSlice([:0]const u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = "\\\\abc",
                .diagnostics = &diagnostics,
            });
            try std.testing.expectEqualStrings("abc", parsed);
            try std.testing.expectEqual(@as(u8, 0), parsed[3]);
        }
    }

    // Other value terminated slices
    {
        {
            try std.testing.expectError(
                error.ParseZon,
                fromSlice([:1]const u8, .{ .gpa = gpa, .arena = arena, .source = "\"foo\"", .diagnostics = &diagnostics }),
            );
            try std.testing.expectFmt(
                \\input.zon:1:1: error: expected array
                \\
            , "{f}", .{diagnostics.fmt("input.zon")});
        }

        {
            try std.testing.expectError(
                error.ParseZon,
                fromSlice([:1]const u8, .{ .gpa = gpa, .arena = arena, .source = "\\\\foo", .diagnostics = &diagnostics }),
            );
            try std.testing.expectFmt(
                \\input.zon:1:1: error: expected array
                \\
            , "{f}", .{diagnostics.fmt("input.zon")});
        }
    }

    // Expecting string literal, getting something else
    {
        try std.testing.expectError(
            error.ParseZon,
            fromSlice([]const u8, .{ .gpa = gpa, .arena = arena, .source = "true", .diagnostics = &diagnostics }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected string
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Expecting string literal, getting an incompatible tuple
    {
        try std.testing.expectError(
            error.ParseZon,
            fromSlice([]const u8, .{ .gpa = gpa, .arena = arena, .source = ".{false}", .diagnostics = &diagnostics }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:3: error: expected type 'u8'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Invalid string literal
    {
        try std.testing.expectError(
            error.ParseZon,
            fromSlice([]const i8, .{ .gpa = gpa, .arena = arena, .source = "\"\\a\"", .diagnostics = &diagnostics }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:3: error: invalid escape character: 'a'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Slice wrong child type
    {
        {
            try std.testing.expectError(
                error.ParseZon,
                fromSlice([]const i8, .{ .gpa = gpa, .arena = arena, .source = "\"a\"", .diagnostics = &diagnostics }),
            );
            try std.testing.expectFmt(
                \\input.zon:1:1: error: expected array
                \\
            , "{f}", .{diagnostics.fmt("input.zon")});
        }

        {
            try std.testing.expectError(
                error.ParseZon,
                fromSlice([]const i8, .{ .gpa = gpa, .arena = arena, .source = "\\\\a", .diagnostics = &diagnostics }),
            );
            try std.testing.expectFmt(
                \\input.zon:1:1: error: expected array
                \\
            , "{f}", .{diagnostics.fmt("input.zon")});
        }
    }

    // Bad alignment
    {
        {
            try std.testing.expectError(
                error.ParseZon,
                fromSlice([]align(2) const u8, .{
                    .gpa = gpa,
                    .arena = arena,
                    .source = "\"abc\"",
                    .diagnostics = &diagnostics,
                }),
            );
            try std.testing.expectFmt(
                \\input.zon:1:1: error: expected array
                \\
            , "{f}", .{diagnostics.fmt("input.zon")});
        }

        {
            try std.testing.expectError(
                error.ParseZon,
                fromSlice([]align(2) const u8, .{
                    .gpa = gpa,
                    .arena = arena,
                    .source = "\\\\abc",
                    .diagnostics = &diagnostics,
                }),
            );
            try std.testing.expectFmt(
                \\input.zon:1:1: error: expected array
                \\
            , "{f}", .{diagnostics.fmt("input.zon")});
        }
    }

    // Multi line strings
    inline for (.{ []const u8, [:0]const u8 }) |String| {
        // Nested
        {
            const S = struct {
                message: String,
                message2: String,
                message3: String,
            };
            const parsed = try fromSlice(S, .{
                .gpa = gpa,
                .arena = arena,
                .source =
                \\.{
                \\    .message =
                \\        \\hello, world!
                \\
                \\        \\this is a multiline string!
                \\        \\
                \\        \\...
                \\
                \\    ,
                \\    .message2 =
                \\        \\this too...sort of.
                \\    ,
                \\    .message3 =
                \\        \\
                \\        \\and this.
                \\}
                ,
                .diagnostics = &diagnostics,
            });
            try std.testing.expectEqualStrings(
                "hello, world!\nthis is a multiline string!\n\n...",
                parsed.message,
            );
            try std.testing.expectEqualStrings("this too...sort of.", parsed.message2);
            try std.testing.expectEqualStrings("\nand this.", parsed.message3);
        }
    }
}

test "std.zon enum literals" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    const Enum = enum {
        foo,
        bar,
        baz,
        @"ab\nc",
    };

    // Tags that exist
    try std.testing.expectEqual(Enum.foo, try fromSliceNoAlloc(Enum, .{
        .gpa = gpa,
        .arena = arena,
        .source = ".foo",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(Enum.bar, try fromSliceNoAlloc(Enum, .{
        .gpa = gpa,
        .arena = arena,
        .source = ".bar",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(Enum.baz, try fromSliceNoAlloc(Enum, .{
        .gpa = gpa,
        .arena = arena,
        .source = ".baz",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(
        Enum.@"ab\nc",
        try fromSliceNoAlloc(Enum, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".@\"ab\\nc\"",
            .diagnostics = &diagnostics,
        }),
    );

    // Bad tag
    {
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc(Enum, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".qux",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:2: error: unexpected enum literal 'qux'
            \\input.zon:1:2: note: supported: 'foo', 'bar', 'baz', '@"ab\nc"'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Bad tag that's too long for parser
    {
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc(Enum, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".@\"foobarbaz\"",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:2: error: unexpected enum literal 'foobarbaz'
            \\input.zon:1:2: note: supported: 'foo', 'bar', 'baz', '@"ab\nc"'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Bad type
    {
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc(Enum, .{
                .gpa = gpa,
                .arena = arena,
                .source = "true",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected enum literal
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Test embedded nulls in an identifier
    {
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc(Enum, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".@\"\\x00\"",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:2: error: identifier cannot contain null bytes
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }
}

test "std.zon parse bool" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    // Correct bools
    try std.testing.expectEqual(true, try fromSliceNoAlloc(bool, .{
        .gpa = gpa,
        .arena = arena,
        .source = "true",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(false, try fromSliceNoAlloc(bool, .{
        .gpa = gpa,
        .arena = arena,
        .source = "false",
        .diagnostics = &diagnostics,
    }));

    // Errors
    {
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc(bool, .{
                .gpa = gpa,
                .arena = arena,
                .source = " foo",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:2: error: invalid expression
            \\input.zon:1:2: note: ZON allows identifiers 'true', 'false', 'null', 'inf', and 'nan'
            \\input.zon:1:2: note: precede identifier with '.' for an enum literal
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(bool, .{
            .gpa = gpa,
            .arena = arena,
            .source = "123",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected type 'bool'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }
}

test "std.zon intFromFloatExact" {
    // Valid conversions
    try std.testing.expectEqual(@as(u8, 10), intFromFloatExact(u8, @as(f32, 10.0)).?);
    try std.testing.expectEqual(@as(i8, -123), intFromFloatExact(i8, @as(f64, @as(f64, -123.0))).?);
    try std.testing.expectEqual(@as(i16, 45), intFromFloatExact(i16, @as(f128, @as(f128, 45.0))).?);
    try std.testing.expectEqual(@as(u128, 67), intFromFloatExact(u128, @as(f128, @as(f128, 67.0))).?);

    // Out of range
    try std.testing.expectEqual(@as(?u4, null), intFromFloatExact(u4, @as(f32, 16.0)));
    try std.testing.expectEqual(@as(?i4, null), intFromFloatExact(i4, @as(f64, -17.0)));
    try std.testing.expectEqual(@as(?u8, null), intFromFloatExact(u8, @as(f128, -2.0)));

    // Not a whole number
    try std.testing.expectEqual(@as(?u8, null), intFromFloatExact(u8, @as(f32, 0.5)));
    try std.testing.expectEqual(@as(?i8, null), intFromFloatExact(i8, @as(f64, 0.01)));

    // Infinity and NaN
    try std.testing.expectEqual(@as(?u8, null), intFromFloatExact(u8, std.math.inf(f32)));
    try std.testing.expectEqual(@as(?u8, null), intFromFloatExact(u8, -std.math.inf(f32)));
    try std.testing.expectEqual(@as(?u8, null), intFromFloatExact(u8, std.math.nan(f32)));
}

test "std.zon parse int" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    // Test various numbers and types
    try std.testing.expectEqual(@as(u8, 10), try fromSliceNoAlloc(u8, .{
        .gpa = gpa,
        .arena = arena,
        .source = "10",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(i16, 24), try fromSliceNoAlloc(i16, .{
        .gpa = gpa,
        .arena = arena,
        .source = "24",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(i14, -4), try fromSliceNoAlloc(i14, .{
        .gpa = gpa,
        .arena = arena,
        .source = "-4",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(i32, -123), try fromSliceNoAlloc(i32, .{
        .gpa = gpa,
        .arena = arena,
        .source = "-123",
        .diagnostics = &diagnostics,
    }));

    // Test limits
    try std.testing.expectEqual(@as(i8, 127), try fromSliceNoAlloc(i8, .{
        .gpa = gpa,
        .arena = arena,
        .source = "127",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(i8, -128), try fromSliceNoAlloc(i8, .{
        .gpa = gpa,
        .arena = arena,
        .source = "-128",
        .diagnostics = &diagnostics,
    }));

    // Test characters
    try std.testing.expectEqual(@as(u8, 'a'), try fromSliceNoAlloc(u8, .{
        .gpa = gpa,
        .arena = arena,
        .source = "'a'",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(u8, 'z'), try fromSliceNoAlloc(u8, .{
        .gpa = gpa,
        .arena = arena,
        .source = "'z'",
        .diagnostics = &diagnostics,
    }));

    // Test big integers
    try std.testing.expectEqual(
        @as(u65, 36893488147419103231),
        try fromSliceNoAlloc(u65, .{
            .gpa = gpa,
            .arena = arena,
            .source = "36893488147419103231",
            .diagnostics = &diagnostics,
        }),
    );
    try std.testing.expectEqual(
        @as(u65, 36893488147419103231),
        try fromSliceNoAlloc(u65, .{
            .gpa = gpa,
            .arena = arena,
            .source = "368934_881_474191032_31",
            .diagnostics = &diagnostics,
        }),
    );
    try std.testing.expectEqual(
        @as(u128, 340282366920938463463374607431768211455),
        try fromSliceNoAlloc(u128, .{
            .gpa = gpa,
            .arena = arena,
            .source = "340282366920938463463374607431768211455",
            .diagnostics = &diagnostics,
        }),
    );

    // Test big integer limits
    try std.testing.expectEqual(
        @as(i66, 36893488147419103231),
        try fromSliceNoAlloc(i66, .{
            .gpa = gpa,
            .arena = arena,
            .source = "36893488147419103231",
            .diagnostics = &diagnostics,
        }),
    );
    try std.testing.expectEqual(
        @as(i66, -36893488147419103232),
        try fromSliceNoAlloc(i66, .{
            .gpa = gpa,
            .arena = arena,
            .source = "-36893488147419103232",
            .diagnostics = &diagnostics,
        }),
    );
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(i66, .{
            .gpa = gpa,
            .arena = arena,
            .source = "36893488147419103232",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:1: error: type 'i66' cannot represent value
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(i66, .{
            .gpa = gpa,
            .arena = arena,
            .source = "-36893488147419103233",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:1: error: type 'i66' cannot represent value
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Test parsing whole number floats as integers
    try std.testing.expectEqual(@as(i8, -1), try fromSliceNoAlloc(i8, .{
        .gpa = gpa,
        .arena = arena,
        .source = "-1.0",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(i8, 123), try fromSliceNoAlloc(i8, .{
        .gpa = gpa,
        .arena = arena,
        .source = "123.0",
        .diagnostics = &diagnostics,
    }));

    // Test non-decimal integers
    try std.testing.expectEqual(@as(i16, 0xff), try fromSliceNoAlloc(i16, .{
        .gpa = gpa,
        .arena = arena,
        .source = "0xff",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(i16, -0xff), try fromSliceNoAlloc(i16, .{
        .gpa = gpa,
        .arena = arena,
        .source = "-0xff",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(i16, 0o77), try fromSliceNoAlloc(i16, .{
        .gpa = gpa,
        .arena = arena,
        .source = "0o77",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(i16, -0o77), try fromSliceNoAlloc(i16, .{
        .gpa = gpa,
        .arena = arena,
        .source = "-0o77",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(i16, 0b11), try fromSliceNoAlloc(i16, .{
        .gpa = gpa,
        .arena = arena,
        .source = "0b11",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(i16, -0b11), try fromSliceNoAlloc(i16, .{
        .gpa = gpa,
        .arena = arena,
        .source = "-0b11",
        .diagnostics = &diagnostics,
    }));

    // Test non-decimal big integers
    try std.testing.expectEqual(@as(u65, 0x1ffffffffffffffff), try fromSliceNoAlloc(u65, .{
        .gpa = gpa,
        .arena = arena,
        .source = "0x1ffffffffffffffff",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(i66, 0x1ffffffffffffffff), try fromSliceNoAlloc(i66, .{
        .gpa = gpa,
        .arena = arena,
        .source = "0x1ffffffffffffffff",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(i66, -0x1ffffffffffffffff), try fromSliceNoAlloc(i66, .{
        .gpa = gpa,
        .arena = arena,
        .source = "-0x1ffffffffffffffff",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(u65, 0x1ffffffffffffffff), try fromSliceNoAlloc(u65, .{
        .gpa = gpa,
        .arena = arena,
        .source = "0o3777777777777777777777",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(i66, 0x1ffffffffffffffff), try fromSliceNoAlloc(i66, .{
        .gpa = gpa,
        .arena = arena,
        .source = "0o3777777777777777777777",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(i66, -0x1ffffffffffffffff), try fromSliceNoAlloc(i66, .{
        .gpa = gpa,
        .arena = arena,
        .source = "-0o3777777777777777777777",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(u65, 0x1ffffffffffffffff), try fromSliceNoAlloc(u65, .{
        .gpa = gpa,
        .arena = arena,
        .source = "0b11111111111111111111111111111111111111111111111111111111111111111",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(i66, 0x1ffffffffffffffff), try fromSliceNoAlloc(i66, .{
        .gpa = gpa,
        .arena = arena,
        .source = "0b11111111111111111111111111111111111111111111111111111111111111111",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(i66, -0x1ffffffffffffffff), try fromSliceNoAlloc(i66, .{
        .gpa = gpa,
        .arena = arena,
        .source = "-0b11111111111111111111111111111111111111111111111111111111111111111",
        .diagnostics = &diagnostics,
    }));

    // Number with invalid character in the middle
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(u8, .{
            .gpa = gpa,
            .arena = arena,
            .source = "32a32",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:3: error: invalid digit 'a' for decimal base
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Failing to parse as int
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(u8, .{
            .gpa = gpa,
            .arena = arena,
            .source = "true",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected type 'u8'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Failing because an int is out of range
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(u8, .{
            .gpa = gpa,
            .arena = arena,
            .source = "256",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:1: error: type 'u8' cannot represent value
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Failing because a negative int is out of range
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(i8, .{
            .gpa = gpa,
            .arena = arena,
            .source = "-129",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:1: error: type 'i8' cannot represent value
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Failing because an unsigned int is negative
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(u8, .{
            .gpa = gpa,
            .arena = arena,
            .source = "-1",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:1: error: type 'u8' cannot represent value
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Failing because a float is non-whole
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(u8, .{
            .gpa = gpa,
            .arena = arena,
            .source = "1.5",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:1: error: type 'u8' cannot represent value
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Failing because a float is negative
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(u8, .{
            .gpa = gpa,
            .arena = arena,
            .source = "-1.0",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:1: error: type 'u8' cannot represent value
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Negative integer zero
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(i8, .{
            .gpa = gpa,
            .arena = arena,
            .source = "-0",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:2: error: integer literal '-0' is ambiguous
            \\input.zon:1:2: note: use '0' for an integer zero
            \\input.zon:1:2: note: use '-0.0' for a floating-point signed zero
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Negative integer zero casted to float
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(f32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "-0",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:2: error: integer literal '-0' is ambiguous
            \\input.zon:1:2: note: use '0' for an integer zero
            \\input.zon:1:2: note: use '-0.0' for a floating-point signed zero
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Negative float 0 is allowed
    try std.testing.expect(
        std.math.isNegativeZero(try fromSliceNoAlloc(f32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "-0.0",
            .diagnostics = &diagnostics,
        })),
    );
    try std.testing.expect(std.math.isPositiveZero(try fromSliceNoAlloc(f32, .{
        .gpa = gpa,
        .arena = arena,
        .source = "0.0",
        .diagnostics = &diagnostics,
    })));

    // Double negation is not allowed
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(i8, .{
            .gpa = gpa,
            .arena = arena,
            .source = "--2",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected number or 'inf' after '-'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    {
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc(f32, .{
                .gpa = gpa,
                .arena = arena,
                .source = "--2.0",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected number or 'inf' after '-'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Invalid int literal
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(u8, .{
            .gpa = gpa,
            .arena = arena,
            .source = "0xg",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:3: error: invalid digit 'g' for hex base
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Notes on invalid int literal
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(u8, .{
            .gpa = gpa,
            .arena = arena,
            .source = "0123",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:1: error: number '0123' has leading zero
            \\input.zon:1:1: note: use '0o' prefix for octal literals
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }
}

test "std.zon negative char" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(f32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "-'a'",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected number or 'inf' after '-'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(i16, .{
            .gpa = gpa,
            .arena = arena,
            .source = "-'a'",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected number or 'inf' after '-'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }
}

test "std.zon parse float" {
    if (builtin.cpu.arch == .x86) return error.SkipZigTest;

    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    // Test decimals
    try std.testing.expectEqual(@as(f16, 0.5), try fromSliceNoAlloc(f16, .{
        .gpa = gpa,
        .arena = arena,
        .source = "0.5",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(
        @as(f32, 123.456),
        try fromSliceNoAlloc(f32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "123.456",
            .diagnostics = &diagnostics,
        }),
    );
    try std.testing.expectEqual(
        @as(f64, -123.456),
        try fromSliceNoAlloc(f64, .{
            .gpa = gpa,
            .arena = arena,
            .source = "-123.456",
            .diagnostics = &diagnostics,
        }),
    );
    try std.testing.expectEqual(@as(f128, 42.5), try fromSliceNoAlloc(f128, .{
        .gpa = gpa,
        .arena = arena,
        .source = "42.5",
        .diagnostics = &diagnostics,
    }));

    // Test whole numbers with and without decimals
    try std.testing.expectEqual(@as(f16, 5.0), try fromSliceNoAlloc(f16, .{
        .gpa = gpa,
        .arena = arena,
        .source = "5.0",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(f16, 5.0), try fromSliceNoAlloc(f16, .{
        .gpa = gpa,
        .arena = arena,
        .source = "5",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(f32, -102), try fromSliceNoAlloc(f32, .{
        .gpa = gpa,
        .arena = arena,
        .source = "-102.0",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(f32, -102), try fromSliceNoAlloc(f32, .{
        .gpa = gpa,
        .arena = arena,
        .source = "-102",
        .diagnostics = &diagnostics,
    }));

    // Test characters and negated characters
    try std.testing.expectEqual(@as(f32, 'a'), try fromSliceNoAlloc(f32, .{
        .gpa = gpa,
        .arena = arena,
        .source = "'a'",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(f32, 'z'), try fromSliceNoAlloc(f32, .{
        .gpa = gpa,
        .arena = arena,
        .source = "'z'",
        .diagnostics = &diagnostics,
    }));

    // Test big integers
    try std.testing.expectEqual(
        @as(f32, 36893488147419103231.0),
        try fromSliceNoAlloc(f32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "36893488147419103231",
            .diagnostics = &diagnostics,
        }),
    );
    try std.testing.expectEqual(
        @as(f32, -36893488147419103231.0),
        try fromSliceNoAlloc(f32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "-36893488147419103231",
            .diagnostics = &diagnostics,
        }),
    );
    try std.testing.expectEqual(@as(f128, 0x1ffffffffffffffff), try fromSliceNoAlloc(f128, .{
        .gpa = gpa,
        .arena = arena,
        .source = "0x1ffffffffffffffff",
        .diagnostics = &diagnostics,
    }));
    try std.testing.expectEqual(@as(f32, @floatFromInt(0x1ffffffffffffffff)), try fromSliceNoAlloc(f32, .{
        .gpa = gpa,
        .arena = arena,
        .source = "0x1ffffffffffffffff",
        .diagnostics = &diagnostics,
    }));

    // Exponents, underscores
    try std.testing.expectEqual(
        @as(f32, 123.0E+77),
        try fromSliceNoAlloc(f32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "12_3.0E+77",
            .diagnostics = &diagnostics,
        }),
    );

    // Hexadecimal
    try std.testing.expectEqual(
        @as(f32, 0x103.70p-5),
        try fromSliceNoAlloc(f32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "0x103.70p-5",
            .diagnostics = &diagnostics,
        }),
    );
    try std.testing.expectEqual(
        @as(f32, -0x103.70),
        try fromSliceNoAlloc(f32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "-0x103.70",
            .diagnostics = &diagnostics,
        }),
    );
    try std.testing.expectEqual(
        @as(f32, 0x1234_5678.9ABC_CDEFp-10),
        try fromSliceNoAlloc(f32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "0x1234_5678.9ABC_CDEFp-10",
            .diagnostics = &diagnostics,
        }),
    );

    // inf, nan
    try std.testing.expect(std.math.isPositiveInf(try fromSliceNoAlloc(f32, .{
        .gpa = gpa,
        .arena = arena,
        .source = "inf",
        .diagnostics = &diagnostics,
    })));
    try std.testing.expect(std.math.isNegativeInf(try fromSliceNoAlloc(f32, .{
        .gpa = gpa,
        .arena = arena,
        .source = "-inf",
        .diagnostics = &diagnostics,
    })));
    try std.testing.expect(std.math.isNan(try fromSliceNoAlloc(f32, .{
        .gpa = gpa,
        .arena = arena,
        .source = "nan",
        .diagnostics = &diagnostics,
    })));

    // Negative nan not allowed
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(f32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "-nan",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected number or 'inf' after '-'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // nan as int not allowed
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(i8, .{
            .gpa = gpa,
            .arena = arena,
            .source = "nan",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected type 'i8'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // nan as int not allowed
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(i8, .{
            .gpa = gpa,
            .arena = arena,
            .source = "nan",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected type 'i8'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // inf as int not allowed
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(i8, .{
            .gpa = gpa,
            .arena = arena,
            .source = "inf",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected type 'i8'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // -inf as int not allowed
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(i8, .{
            .gpa = gpa,
            .arena = arena,
            .source = "-inf",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected type 'i8'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Bad identifier as float
    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(f32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "foo",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:1: error: invalid expression
            \\input.zon:1:1: note: ZON allows identifiers 'true', 'false', 'null', 'inf', and 'nan'
            \\input.zon:1:1: note: precede identifier with '.' for an enum literal
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    {
        try std.testing.expectError(error.ParseZon, fromSliceNoAlloc(f32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "-foo",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected number or 'inf' after '-'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Non float as float
    {
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc(f32, .{
                .gpa = gpa,
                .arena = arena,
                .source = "\"foo\"",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected type 'f32'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }
}

test "std.zon free on error" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    // Test freeing partially allocated structs
    {
        const Struct = struct {
            x: []const u8,
            y: []const u8,
            z: bool,
        };
        try std.testing.expectError(error.ParseZon, fromSlice(Struct, .{
            .gpa = gpa,
            .arena = arena,
            .source =
            \\.{
            \\    .x = "hello",
            \\    .y = "world",
            \\    .z = "fail",
            \\}
            ,
            .diagnostics = &diagnostics,
        }));
    }

    // Test freeing partially allocated tuples
    {
        const Struct = struct {
            []const u8,
            []const u8,
            bool,
        };
        try std.testing.expectError(error.ParseZon, fromSlice(Struct, .{
            .gpa = gpa,
            .arena = arena,
            .source =
            \\.{
            \\    "hello",
            \\    "world",
            \\    "fail",
            \\}
            ,
            .diagnostics = &diagnostics,
        }));
    }

    // Test freeing structs with missing fields
    const Struct = struct {
        x: []const u8,
        y: bool,
    };
    try std.testing.expectError(error.ParseZon, fromSlice(Struct, .{
        .gpa = gpa,
        .arena = arena,
        .source =
        \\.{
        \\    .x = "hello",
        \\}
        ,
        .diagnostics = &diagnostics,
    }));

    // Test freeing partially allocated arrays
    try std.testing.expectError(error.ParseZon, fromSlice([3][]const u8, .{
        .gpa = gpa,
        .arena = arena,
        .source =
        \\.{
        \\    "hello",
        \\    false,
        \\    false,
        \\}
        ,
        .diagnostics = &diagnostics,
    }));

    // Test freeing partially allocated slices
    try std.testing.expectError(error.ParseZon, fromSlice([][]const u8, .{
        .gpa = gpa,
        .arena = arena,
        .source =
        \\.{
        \\    "hello",
        \\    "world",
        \\    false,
        \\}
        ,
        .diagnostics = &diagnostics,
    }));

    // We can parse types that can't be freed, as long as they contain no allocations, e.g. untagged
    // unions.
    try std.testing.expectEqual(
        @as(f32, 1.5),
        (try fromSliceNoAlloc(union { x: f32 }, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ .x = 1.5 }",
            .diagnostics = &diagnostics,
        })).x,
    );

    // We can also parse types that can't be freed if it's impossible for an error to occur after
    // the allocation, as is the case here.
    {
        const result = try fromSlice(union { x: []const u8 }, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ .x = \"foo\" }",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqualStrings("foo", result.x);
    }
}

test "std.zon vector" {
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest; // https://github.com/ziglang/zig/issues/15330
    if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .s390x) return error.SkipZigTest; // https://github.com/ziglang/zig/issues/25957

    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    // Passing cases
    try std.testing.expectEqual(
        @Vector(0, bool){},
        try fromSliceNoAlloc(@Vector(0, bool), .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{}",
            .diagnostics = &diagnostics,
        }),
    );
    try std.testing.expectEqual(
        @Vector(3, bool){ true, false, true },
        try fromSliceNoAlloc(@Vector(3, bool), .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{true, false, true}",
            .diagnostics = &diagnostics,
        }),
    );

    try std.testing.expectEqual(
        @Vector(0, f32){},
        try fromSliceNoAlloc(@Vector(0, f32), .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{}",
            .diagnostics = &diagnostics,
        }),
    );
    try std.testing.expectEqual(
        @Vector(3, f32){ 1.5, 2.5, 3.5 },
        try fromSliceNoAlloc(@Vector(3, f32), .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{1.5, 2.5, 3.5}",
            .diagnostics = &diagnostics,
        }),
    );

    try std.testing.expectEqual(
        @Vector(0, u8){},
        try fromSliceNoAlloc(@Vector(0, u8), .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{}",
            .diagnostics = &diagnostics,
        }),
    );
    try std.testing.expectEqual(
        @Vector(3, u8){ 2, 4, 6 },
        try fromSliceNoAlloc(@Vector(3, u8), .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{2, 4, 6}",
            .diagnostics = &diagnostics,
        }),
    );

    {
        try std.testing.expectEqual(
            @Vector(0, *const u8){},
            try fromSlice(@Vector(0, *const u8), .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{}",
                .diagnostics = &diagnostics,
            }),
        );
        const pointers = try fromSlice(@Vector(3, *const u8), .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{2, 4, 6}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqualDeep(@Vector(3, *const u8){ &2, &4, &6 }, pointers);
    }

    {
        try std.testing.expectEqual(
            @Vector(0, ?*const u8){},
            try fromSlice(@Vector(0, ?*const u8), .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{}",
                .diagnostics = &diagnostics,
            }),
        );
        const pointers = try fromSlice(@Vector(3, ?*const u8), .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{2, null, 6}",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqualDeep(@Vector(3, ?*const u8){ &2, null, &6 }, pointers);
    }

    // Too few fields
    {
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc(@Vector(2, f32), .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{0.5}",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:2: error: expected 2 array elements; found 1
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Too many fields
    {
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc(@Vector(2, f32), .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{0.5, 1.5, 2.5}",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:13: error: index 2 outside of array of length 2
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Wrong type fields
    {
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc(@Vector(3, f32), .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{0.5, true, 2.5}",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:8: error: expected type 'f32'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Wrong type
    {
        try std.testing.expectError(
            error.ParseZon,
            fromSliceNoAlloc(@Vector(3, u8), .{
                .gpa = gpa,
                .arena = arena,
                .source = "true",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected type '@Vector(3, u8)'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Elements should get freed on error
    {
        try std.testing.expectError(
            error.ParseZon,
            fromSlice(@Vector(3, *u8), .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{1, true, 3}",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:6: error: expected type 'u8'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }
}

test "std.zon add pointers" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    // Primitive with varying levels of pointers
    {
        const result = try fromSlice(*u32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "10",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(@as(u32, 10), result.*);
    }

    {
        const result = try fromSlice(**u32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "10",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(@as(u32, 10), result.*.*);
    }

    {
        const result = try fromSlice(***u32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "10",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(@as(u32, 10), result.*.*.*);
    }

    // Primitive optional with varying levels of pointers
    {
        const some = try fromSlice(?*u32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "10",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(@as(u32, 10), some.?.*);

        const none = try fromSlice(?*u32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "null",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(null, none);
    }

    {
        const some = try fromSlice(*?u32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "10",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(@as(u32, 10), some.*.?);

        const none = try fromSlice(*?u32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "null",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(null, none.*);
    }

    {
        const some = try fromSlice(?**u32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "10",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(@as(u32, 10), some.?.*.*);

        const none = try fromSlice(?**u32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "null",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(null, none);
    }

    {
        const some = try fromSlice(*?*u32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "10",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(@as(u32, 10), some.*.?.*);

        const none = try fromSlice(*?*u32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "null",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(null, none.*);
    }

    {
        const some = try fromSlice(**?u32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "10",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(@as(u32, 10), some.*.*.?);

        const none = try fromSlice(**?u32, .{
            .gpa = gpa,
            .arena = arena,
            .source = "null",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(null, none.*.*);
    }

    // Pointer to an array
    {
        const result = try fromSlice(*[3]u8, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ 1, 2, 3 }",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual([3]u8{ 1, 2, 3 }, result.*);
    }

    // A complicated type with nested internal pointers and string allocations
    {
        const Inner = struct {
            f1: *const ?*const []const u8,
            f2: *const ?*const []const u8,
        };
        const Outer = struct {
            f1: *const ?*const Inner,
            f2: *const ?*const Inner,
        };
        const expected: Outer = .{
            .f1 = &&.{
                .f1 = &null,
                .f2 = &&"foo",
            },
            .f2 = &null,
        };

        const found = try fromSlice(?*Outer, .{
            .gpa = gpa,
            .arena = arena,
            .source =
            \\.{
            \\    .f1 = .{
            \\        .f1 = null,
            \\        .f2 = "foo",
            \\    },
            \\    .f2 = null,
            \\}
            ,
            .diagnostics = &diagnostics,
        });

        try std.testing.expectEqualDeep(expected, found.?.*);
    }

    // Test that optional types are flattened correctly in errors
    {
        try std.testing.expectError(
            error.ParseZon,
            fromSlice(*const ?*const u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = "true",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected type '?u8'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    {
        try std.testing.expectError(
            error.ParseZon,
            fromSlice(*const ?*const f32, .{
                .gpa = gpa,
                .arena = arena,
                .source = "true",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected type '?f32'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    {
        try std.testing.expectError(
            error.ParseZon,
            fromSlice(*const ?*const @Vector(3, u8), .{
                .gpa = gpa,
                .arena = arena,
                .source = "true",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected type '?@Vector(3, u8)'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    {
        try std.testing.expectError(
            error.ParseZon,
            fromSlice(*const ?*const bool, .{
                .gpa = gpa,
                .arena = arena,
                .source = "10",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected type '?bool'
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    {
        try std.testing.expectError(
            error.ParseZon,
            fromSlice(*const ?*const struct { a: i32 }, .{
                .gpa = gpa,
                .arena = arena,
                .source = "true",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected optional struct
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    {
        try std.testing.expectError(
            error.ParseZon,
            fromSlice(*const ?*const struct { i32 }, .{
                .gpa = gpa,
                .arena = arena,
                .source = "true",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected optional tuple
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    {
        try std.testing.expectError(
            error.ParseZon,
            fromSlice(*const ?*const union { x: void }, .{
                .gpa = gpa,
                .arena = arena,
                .source = "true",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected optional union
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    {
        try std.testing.expectError(
            error.ParseZon,
            fromSlice(*const ?*const [3]u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = "true",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected optional array
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    {
        try std.testing.expectError(
            error.ParseZon,
            fromSlice(?[3]u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = "true",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected optional array
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    {
        try std.testing.expectError(
            error.ParseZon,
            fromSlice(*const ?*const []u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = "true",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected optional array
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    {
        try std.testing.expectError(
            error.ParseZon,
            fromSlice(?[]u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = "true",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected optional array
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    {
        try std.testing.expectError(
            error.ParseZon,
            fromSlice(*const ?*const []const u8, .{
                .gpa = gpa,
                .arena = arena,
                .source = "true",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected optional string
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    {
        try std.testing.expectError(
            error.ParseZon,
            fromSlice(*const ?*const enum { foo }, .{
                .gpa = gpa,
                .arena = arena,
                .source = "true",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectFmt(
            \\input.zon:1:1: error: expected optional enum literal
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }
}

test "std.zon stop on node" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    {
        const Vec2 = struct {
            x: Zoir.Node.Index,
            y: f32,
        };

        var ast = try std.zig.Ast.parse(gpa, ".{ .x = 1.5, .y = 2.5 }", .{ .mode = .zon });
        defer ast.deinit(gpa);

        var zoir = try ZonGen.generate(gpa, ast, .{ .parse_str_lits = false });
        defer zoir.deinit(gpa);

        const result = try fromZoirNoAlloc(Vec2, .{
            .arena = arena,
            .ast = &ast,
            .zoir = &zoir,
            .diagnostics = &diagnostics,
        });

        try std.testing.expectEqual(result.y, 2.5);
        try std.testing.expectEqual(Zoir.Node{ .float_literal = 1.5 }, result.x.get(&zoir));
    }

    {
        var ast = try std.zig.Ast.parse(gpa, "1.23", .{ .mode = .zon });
        defer ast.deinit(gpa);

        var zoir = try ZonGen.generate(gpa, ast, .{ .parse_str_lits = false });
        defer zoir.deinit(gpa);

        const result = try fromZoirNoAlloc(Zoir.Node.Index, .{
            .arena = arena,
            .ast = &ast,
            .zoir = &zoir,
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(Zoir.Node{ .float_literal = 1.23 }, result.get(&zoir));
    }
}

test "std.zon no alloc" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    try std.testing.expectEqual(
        [3]u8{ 1, 2, 3 },
        try fromSliceNoAlloc([3]u8, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ 1, 2, 3 }",
            .diagnostics = &diagnostics,
        }),
    );

    const Nested = struct { u8, u8, struct { u8, u8 } };

    var ast = try std.zig.Ast.parse(gpa, ".{ 1, 2, .{ 3, 4 } }", .{ .mode = .zon });
    defer ast.deinit(gpa);

    var zoir = try ZonGen.generate(gpa, ast, .{ .parse_str_lits = false });
    defer zoir.deinit(gpa);

    try std.testing.expectEqual(
        Nested{ 1, 2, .{ 3, 4 } },
        try fromZoirNoAlloc(Nested, .{
            .arena = arena,
            .ast = &ast,
            .zoir = &zoir,
            .diagnostics = &diagnostics,
        }),
    );
}

test "std.zon aligned pointers" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    const n: u8 align(8) = 10;
    const Foo = struct {
        inner: *align(8) const u8,
    };

    const expected: Foo = .{
        .inner = &n,
    };
    const found = try fromSlice(Foo, .{
        .gpa = gpa,
        .arena = arena,
        .source = ".{ .inner = 10 }",
        .diagnostics = &diagnostics,
    });
    try std.testing.expectEqualDeep(expected.inner, found.inner);
}

test "std.zon update basic" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    const Vector = struct { x: f32, y: f32, z: f32 };
    const MyStruct = struct {
        foo: u32 = 123,
        bar: bool,
        baz: struct {
            a: [2]u32,
            b: enum { c, d } = .d,
        },
        ptr: *Vector,
        optional: ?u32 = null,
        str: []const u8,
    };

    var v1: Vector = .{ .x = 1, .y = 2, .z = 3 };
    var expected: MyStruct = .{
        .foo = 10,
        .bar = true,
        .baz = .{ .a = .{ 1, 2 }, .b = .c },
        .ptr = &v1,
        .str = "hello, world",
    };
    var v2: Vector = .{ .x = 1, .y = 2, .z = 3 };
    var found: MyStruct = .{
        .foo = 10,
        .bar = true,
        .baz = .{ .a = .{ 1, 2 }, .b = .c },
        .ptr = &v2,
        .str = "hello, world",
    };

    try updateFromSlice(MyStruct, &found, .{
        .gpa = gpa,
        .arena = arena,
        .source = ".{}",
        .diagnostics = &diagnostics,
    });
    try std.testing.expectEqualDeep(expected, found);

    try updateFromSlice(MyStruct, &found, .{
        .gpa = gpa,
        .arena = arena,
        .source = ".{ .bar = false }",
        .diagnostics = &diagnostics,
    });
    expected.bar = false;
    try std.testing.expectEqualDeep(expected, found);

    try updateFromSlice(MyStruct, &found, .{
        .gpa = gpa,
        .arena = arena,
        .source = ".{ .baz = .{ .a = .{ 2, 4 } } }",
        .diagnostics = &diagnostics,
    });
    expected.baz.a[0] = 2;
    expected.baz.a[1] = 4;
    try std.testing.expectEqualDeep(expected, found);

    try updateFromSlice(MyStruct, &found, .{
        .gpa = gpa,
        .arena = arena,
        .source = ".{ .foo = 11, .baz = .{ .b = .d } }",
        .diagnostics = &diagnostics,
    });
    expected.foo = 11;
    expected.baz.b = .d;
    try std.testing.expectEqualDeep(expected, found);

    try updateFromSlice(MyStruct, &found, .{
        .gpa = gpa,
        .arena = arena,
        .source = ".{ .optional = 10 }",
        .diagnostics = &diagnostics,
    });
    expected.optional = 10;
    try std.testing.expectEqualDeep(expected, found);

    try updateFromSlice(MyStruct, &found, .{
        .gpa = gpa,
        .arena = arena,
        .source = ".{ .optional = null }",
        .diagnostics = &diagnostics,
    });
    expected.optional = null;
    try std.testing.expectEqualDeep(expected, found);

    try updateFromSlice(MyStruct, &found, .{
        .gpa = gpa,
        .arena = arena,
        .source = ".{ .ptr = .{ .x = 10, .y = 20, .z = 30 } }",
        .diagnostics = &diagnostics,
    });
    expected.ptr.x = 10;
    expected.ptr.y = 20;
    expected.ptr.z = 30;
    try std.testing.expectEqualDeep(expected, found);

    try updateFromSlice(MyStruct, &found, .{
        .gpa = gpa,
        .arena = arena,
        .source = ".{ .str = \"foo\" }",
        .diagnostics = &diagnostics,
    });
    expected.str = "foo";
    try std.testing.expectEqualDeep(expected, found);
}

test "std.zon update optionals" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    const MyStruct = struct {
        foo: ?struct { bar: u32 = 1, baz: u32 = 2, qux: u32 },
    };

    // Updating an optional that starts out null should fill in any default fields we left off
    {
        var expected: MyStruct = .{ .foo = null };
        var found = expected;
        try updateFromSliceNoAlloc(MyStruct, &found, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ .foo = .{ .qux = 3 } }",
            .diagnostics = &diagnostics,
        });
        expected.foo = .{ .qux = 3 };
        try std.testing.expectEqual(expected, found);
    }

    // Updating an optional that starts out null should error if we leave off required fields.
    {
        var found: MyStruct = .{ .foo = null };
        try std.testing.expectError(error.ParseZon, updateFromSliceNoAlloc(MyStruct, &found, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ .foo = .{} }",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:12: error: missing required field qux
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Updating an optional that starts out non-null should preserve any values we leave off. It's
    // also okay to leave off required fields since they were already set.
    {
        var expected: MyStruct = .{
            .foo = .{ .bar = 10, .baz = 20, .qux = 30 },
        };
        var found = expected;
        try updateFromSliceNoAlloc(MyStruct, &found, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ .foo = .{ .baz = 200 } }",
            .diagnostics = &diagnostics,
        });
        expected.foo.?.baz = 200;
        try std.testing.expectEqual(expected, found);
    }
}

test "std.zon update optional pointers" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    const MyStruct = struct {
        foo: ?*const struct { bar: u32 = 1, baz: u32 = 2, qux: u32 },
    };

    // Just a smoke test since its the combination of behavior we've already tested separately
    {
        var expected: MyStruct = .{ .foo = null };
        var found = expected;
        try updateFromSlice(MyStruct, &found, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ .foo = .{ .qux = 3 } }",
            .diagnostics = &diagnostics,
        });
        expected.foo = &.{ .qux = 3 };
        try std.testing.expectEqualDeep(expected, found);
    }
}

test "std.zon update pointers" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    // Updating a pointer should leave fields we don't specify unchanged
    {
        const MyStruct = struct {
            foo: *struct { bar: u32 = 10, baz: u32 = 20, qux: u32 },
        };
        var ptr: @typeInfo(@FieldType(MyStruct, "foo")).pointer.child = .{ .qux = 3 };
        var expected: MyStruct = .{ .foo = &ptr };
        var found = expected;
        try updateFromSlice(MyStruct, &found, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ .foo = .{ .bar = 100 } }",
            .diagnostics = &diagnostics,
        });
        expected.foo.bar = 100;
        try std.testing.expectEqualDeep(expected, found);
    }

    // Same thing, but for const pointers
    {
        const MyStruct = struct {
            foo: *const struct { bar: u32 = 10, baz: u32 = 20, qux: u32 },
        };
        var expected: MyStruct = .{ .foo = &.{ .qux = 3 } };
        var found = expected;
        try updateFromSlice(MyStruct, &found, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ .foo = .{ .bar = 100 } }",
            .diagnostics = &diagnostics,
        });
        expected.foo = &.{ .bar = 100, .baz = 20, .qux = 3 };
        try std.testing.expectEqualDeep(expected, found);
    }
}

test "std.zon update unions" {
    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    const MyUnion = union(enum) {
        none: void,
        foo: struct { bar: u32 = 10, baz: u32 = 20, qux: u32 },
    };

    // Updating a union to a new field should fill in any default sub-fields we left off
    {
        var expected: MyUnion = .none;
        var found = expected;
        try updateFromSliceNoAlloc(MyUnion, &found, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ .foo = .{ .qux = 3 } }",
            .diagnostics = &diagnostics,
        });
        expected = .{ .foo = .{ .qux = 3 } };
        try std.testing.expectEqual(expected, found);
    }

    // Updating a union to a new field should error if we leave off required sub-fields
    {
        var found: MyUnion = .none;
        try std.testing.expectError(error.ParseZon, updateFromSliceNoAlloc(MyUnion, &found, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ .foo = .{} }",
            .diagnostics = &diagnostics,
        }));
        try std.testing.expectFmt(
            \\input.zon:1:12: error: missing required field qux
            \\
        , "{f}", .{diagnostics.fmt("input.zon")});
    }

    // Updating a union should preseve any sub-fields that we left off. It's also okay to leave off
    // required fields since they were already set.
    {
        var expected: MyUnion = .{
            .foo = .{ .bar = 10, .baz = 20, .qux = 30 },
        };
        var found = expected;
        try updateFromSliceNoAlloc(MyUnion, &found, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ .foo = .{ .baz = 200 } }",
            .diagnostics = &diagnostics,
        });
        expected.foo.baz = 200;
        try std.testing.expectEqual(expected, found);
    }
}

test "std.zon variants" {
    // Just a smoke test, we don't need to test each variant thoroughly because they all call into
    // the same code.

    const gpa = std.testing.allocator;
    var arena_allocator: ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();
    var diagnostics: Diagnostics = undefined;

    const Struct = struct { a: u32, b: u32 };
    const start: Struct = .{ .a = 10, .b = 20 };
    const end: Struct = .{ .a = 100, .b = 20 };

    // Update
    {
        var ast = try std.zig.Ast.parse(gpa, ".{ .a = 100 }", .{ .mode = .zon });
        defer ast.deinit(gpa);
        const zoir = try ZonGen.generate(gpa, ast, .{ .parse_str_lits = false });
        defer zoir.deinit(gpa);

        var curr = start;
        try updateFromSliceNoAlloc(Struct, &curr, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ .a = 100 }",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(end, curr);

        curr = start;
        try updateFromSlice(Struct, &curr, .{
            .gpa = gpa,
            .arena = arena,
            .source = ".{ .a = 100 }",
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(end, curr);

        curr = start;
        try updateFromZoirNoAlloc(Struct, &curr, .{
            .arena = arena,
            .ast = &ast,
            .zoir = &zoir,
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(end, curr);

        curr = start;
        try updateFromZoir(Struct, &curr, .{
            .arena = arena,
            .ast = &ast,
            .zoir = &zoir,
            .diagnostics = &diagnostics,
        });
        try std.testing.expectEqual(end, curr);
    }

    // From
    {
        var ast = try std.zig.Ast.parse(gpa, ".{ .a = 100, .b = 20 }", .{ .mode = .zon });
        defer ast.deinit(gpa);
        const zoir = try ZonGen.generate(gpa, ast, .{ .parse_str_lits = false });
        defer zoir.deinit(gpa);

        try std.testing.expectEqual(
            end,
            try fromSliceNoAlloc(Struct, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{ .a = 100, .b = 20 }",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectEqual(
            end,
            try fromSlice(Struct, .{
                .gpa = gpa,
                .arena = arena,
                .source = ".{ .a = 100, .b = 20 }",
                .diagnostics = &diagnostics,
            }),
        );
        try std.testing.expectEqual(
            try fromZoirNoAlloc(Struct, .{
                .arena = arena,
                .ast = &ast,
                .zoir = &zoir,
                .diagnostics = &diagnostics,
            }),
            end,
        );
        try std.testing.expectEqual(
            try fromZoir(Struct, .{
                .arena = arena,
                .ast = &ast,
                .zoir = &zoir,
                .diagnostics = &diagnostics,
            }),
            end,
        );
    }
}

test {
    _ = Diagnostics;
}

const std = @import("std");
const lsp_server = @import("lsp-server");

const helper = @import("../helper.zig");
const Context = @import("../context.zig").Context;
const ErrorBuilder = @import("../ErrorBuilder.zig");

const types = lsp_server.lsp.types;
const offsets = lsp_server.offsets;

const allocator: std.mem.Allocator = std.testing.allocator;

test "none" {
    try testDiagnostics("", &.{}, .{});
}

test "ast error" {
    try testDiagnostics(
        \\const foo
    , &.{
        .{
            .range = .{
                .start = .{ .line = 0, .character = 9 },
                .end = .{ .line = 0, .character = 9 },
            },
            .severity = .Error,
            .source = "zigscient",
            .message = "expected ';' after declaration",
        },
    }, .{});
}

test "ast-check" {
    try testDiagnostics(
        \\test {
        \\    const foo = undefined;
        \\}
    , &.{
        .{
            .range = .{
                .start = .{ .line = 1, .character = 10 },
                .end = .{ .line = 1, .character = 13 },
            },
            .severity = .Error,
            .tags = &.{.Unnecessary},
            .source = "zigscient",
            .message = "unused local constant",
        },
    }, .{});

    try testDiagnostics(
        \\test {
        \\    var foo = undefined;
        \\}
    , &.{
        .{
            .range = .{
                .start = .{ .line = 1, .character = 8 },
                .end = .{ .line = 1, .character = 11 },
            },
            .severity = .Error,
            .tags = &.{.Unnecessary},
            .source = "zigscient",
            .message = "unused local variable",
        },
    }, .{});
}

test "warn style" {
    try testDiagnostics(
        \\const foo = @import("./foo");
    , &.{
        .{
            .range = .{
                .start = .{ .line = 0, .character = 20 },
                .end = .{ .line = 0, .character = 27 },
            },
            .code = .{ .string = "dot_slash_import" },
            .severity = .Hint,
            .source = "zigscient",
            .message = "A ./ is not needed in imports",
        },
    }, .{ .warn_style = true });
    try testDiagnostics(
        \\fn Foo() void {}
        \\fn bar() type {}
    , &.{
        .{
            .range = .{
                .start = .{ .line = 0, .character = 3 },
                .end = .{ .line = 0, .character = 6 },
            },
            .code = .{ .string = "naming style" },
            .severity = .Hint,
            .source = "zigscient",
            .message = "Functions should be camelCase",
        },
        .{
            .range = .{
                .start = .{ .line = 1, .character = 3 },
                .end = .{ .line = 1, .character = 6 },
            },
            .code = .{ .string = "naming style" },
            .severity = .Hint,
            .source = "zigscient",
            .message = "Type functions should be PascalCase",
        },
    }, .{ .warn_style = true });
}

test "highlight global var decls" {
    try testDiagnostics(
        \\var foo: u32 = undefined;
    , &.{
        .{
            .range = .{
                .start = .{ .line = 0, .character = 0 },
                .end = .{ .line = 0, .character = 3 },
            },
            .code = .{ .string = "highlight_global_var_declarations" },
            .severity = .Hint,
            .source = "zigscient",
            .message = "Global var declaration",
        },
    }, .{ .highlight_global_var_declarations = true });
}

test "autofix comment" {
    try testDiagnostics(
        \\test {
        \\    const foo = undefined;
        \\    _ = foo; // autofix
        \\}
    , &.{
        .{
            .range = .{
                .start = .{ .line = 2, .character = 8 },
                .end = .{ .line = 2, .character = 11 },
            },
            .severity = .Information,
            .source = "zigscient",
            .message = "auto discard for unused variable",
            .relatedInformation = &.{
                .{
                    .location = .{
                        .uri = "file:///test.zig",
                        .range = .{
                            .start = .{ .line = 1, .character = 10 },
                            .end = .{ .line = 1, .character = 13 },
                        },
                    },
                    .message = "variable declared here",
                },
            },
        },
    }, .{ .autofix = true });
}

fn testDiagnostics(
    source: []const u8,
    expected_diagnostics: []const types.Diagnostic,
    options: struct {
        warn_style: bool = false,
        highlight_global_var_declarations: bool = false,
        autofix: bool = false,
    },
) !void {
    var context: Context = try .init();
    defer context.deinit();

    const uri = try context.addDocument(.{
        .uri = "file:///test.zig",
        .source = source,
    });

    context.server.config_manager.config.warn_style = options.warn_style;
    context.server.config_manager.config.highlight_global_var_declarations = options.highlight_global_var_declarations;
    context.server.client_capabilities.supports_code_action_fixall = options.autofix;
    context.server.client_capabilities.supports_publish_diagnostics = true;
    try lsp_server.diagnostics.generateDiagnostics(context.server, context.server.document_store.getHandle(uri).?);

    var actual_diagnostics: std.ArrayList(types.Diagnostic) = .empty;

    try context.server.diagnostics_collection.collectLspDiagnosticsForDocumentTesting(
        uri,
        .@"utf-8",
        context.arena.allocator(),
        &actual_diagnostics,
    );

    try lsp_server.testing.expectEqual(expected_diagnostics, actual_diagnostics.items);
}

pub const build_options = @import("build_options");

pub const cli = @import("cli.zig");
pub const Logger = @import("Logger.zig");

pub const Analyser = @import("analysis.zig");
pub const BuildOptions = @import("BuildOptions.zig");
pub const Settings = @import("Settings.zig");
pub const Server = @import("Server.zig");
pub const DocumentStore = @import("DocumentStore.zig");
pub const DocumentScope = @import("DocumentScope.zig");
pub const ZigDoc = @import("ZigDoc.zig");
pub const BldDoc = @import("BldDoc.zig");
pub const DiagnosticsCollection = @import("DiagnosticsCollection.zig");
pub const Maker = @import("Maker");

pub const ast = @import("ast.zig");
pub const print_ast = @import("print_ast.zig");
pub const analyser = @import("analyser/analyser.zig");
pub const settings_handler = @import("settings_handler.zig");
pub const diff = @import("diff.zig");
pub const offsets = @import("offsets.zig");
pub const snippets = @import("snippets.zig");
pub const testing = @import("testing.zig");
pub const uri_util = @import("uri.zig");

pub const code_actions = @import("features/code_actions.zig");
pub const completions = @import("features/completions.zig");
pub const diagnostics = @import("features/diagnostics.zig");
pub const document_symbol = @import("features/document_symbol.zig");
pub const folding_range = @import("features/folding_range.zig");
pub const goto = @import("features/goto.zig");
pub const hover = @import("features/hover.zig");
pub const inlay_hints = @import("features/inlay_hints.zig");
pub const references = @import("features/references.zig");
pub const selection_range = @import("features/selection_range.zig");
pub const semantic_tokens = @import("features/semantic_tokens.zig");
pub const signature_help = @import("features/signature_help.zig");

pub const lsp = @import("lsp");

comptime {
    const std = @import("std");
    std.testing.refAllDecls(@This());

    std.testing.refAllDecls(@import("build_runner/check.zig"));
    std.testing.refAllDecls(@import("build_runner/shared.zig"));
}

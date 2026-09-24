const std = @import("std");
const Ast = std.zig.Ast;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const compiler = @import("compiler");
const Compilation = compiler.Compilation;
const InternPool = Compilation.InternPool;
const Type = Compilation.Type;
const Zcu = Compilation.Zcu;
const Air = Compilation.Air;

const Asta = @import("analysis.zig");
const ZigDoc = @import("ZigDoc.zig");
const DocumentStore = @import("DocumentStore.zig");
const tree_util = @import("offsets.zig");

const Aira = @This();

const ErrSet = error{OutOfMemory};

const Result = struct {
    inst_tag: Air.Inst.Tag,
    ip_index: InternPool.Index,
};

ds: *DocumentStore,
zdoc: *ZigDoc,
air: Air,
active: Zcu.Active,

pub fn init(ds: *DocumentStore, zdoc: *ZigDoc, node: Ast.Node.Index) ErrSet!?Aira {
    if (ds.config.disable_aira) return null;
    const doc_scope = try zdoc.getDocumentScope();
    const fn_scope = Asta.innermostScopeAtIndexWithTag(
        doc_scope,
        zdoc.tree.tokens.items(.start)[zdoc.tree.firstToken(node)],
        .initOne(.function),
    ).unwrap() orelse return null;
    const fn_node = doc_scope.getScopeAstNode(fn_scope) orelse return null;

    var buf: [1]Ast.Node.Index = undefined;
    const fn_proto_node = zdoc.tree.fullFnProto(&buf, fn_node).?.ast.proto_node;

    var cleanup: bool = false;

    zdoc.computed_data.lock.lockSharedUncancelable(ds.io);
    defer if (cleanup) zdoc.computed_data.lock.unlockShared(ds.io);

    const build = zdoc.computed_data.build orelse {
        cleanup = true;
        return null;
    };

    if (!build.mutex.tryLock()) {
        cleanup = true;
        return null;
    }
    defer if (cleanup) build.mutex.unlock(ds.io);

    if (!build.has_completed_once) {
        cleanup = true;
        return null;
    }

    const args = zdoc.computed_data.air.get(fn_proto_node) orelse {
        cleanup = true;
        return null;
    };
    const zcu = build.compilation.?.zcu orelse {
        cleanup = true;
        return null;
    };

    return .{
        .ds = ds,
        .zdoc = zdoc,
        .air = args.air,
        .active = zcu.activate(args.tid),
    };
}

pub fn deinit(aira: *Aira) void {
    aira.active.deactivate();
    aira.zdoc.computed_data.build.?.mutex.unlock(aira.ds.io);
    aira.zdoc.computed_data.lock.unlockShared(aira.ds.io);
}

pub fn resolveNode(
    aira: *Aira,
    node: Ast.Node.Index,
) ErrSet!?Air.Inst.Index {
    const tree = aira.zdoc.tree;
    return switch (tree.nodeTag(node)) {
        .global_var_decl,
        .local_var_decl,
        .aligned_var_decl,
        .simple_var_decl,
        => try resolveVarDecl(aira, node),
        .assign_destructure => matchTreeDataIndex(@backingInt(node), aira.air, aira.air.getMainBody()),
        else => null,
    };
}

pub fn resolveVarDecl(
    aira: *Aira,
    node: Ast.Node.Index,
) ErrSet!?Air.Inst.Index {
    const tree = aira.zdoc.tree;
    const full_var_decl = tree.fullVarDecl(node) orelse return null;

    const res = matchTreeDataIndex(
        @backingInt(full_var_decl.ast.init_node.unwrap() orelse node),
        aira.air,
        aira.air.getMainBody(),
    );
    return res;
}

fn matchTreeDataIndex(
    tree_data_index: u32,
    air: Air,
    instructions: []const Air.Inst.Index,
) ?Air.Inst.Index {
    for (instructions) |inst| {
        const tag = air.instructions.items(.tag)[@backingInt(inst)];
        switch (tag) {
            else => continue,
            .dbg_var_ptr,
            .dbg_var_val,
            // .dbg_arg_inline,
            => {
                const pl_op = air.instructions.items(.data)[@backingInt(inst)].pl_op;
                // TODO Check that the identifier matches as well
                // std.log.err("comparing: {} with {}", .{ pl_op.tree_data_index, @backingInt(node) });
                if (pl_op.tree_data_index == tree_data_index) {
                    // std.log.err("found a match! {}", .{pl_op.tree_data_index});
                    return inst;
                }
            },
            .loop,
            .block,
            => {
                if (matchTreeDataIndex(tree_data_index, air, air.unwrapBlock(inst).body)) |i| return i;
            },
            .dbg_inline_block => {
                if (matchTreeDataIndex(tree_data_index, air, air.unwrapDbgBlock(inst).body)) |i| return i;
            },
            .cond_br => {
                const cond_br = air.unwrapCondBr(inst);
                if (matchTreeDataIndex(tree_data_index, air, cond_br.then_body)) |i| return i;
                if (matchTreeDataIndex(tree_data_index, air, cond_br.else_body)) |i| return i;
            },
            .loop_switch_br,
            .switch_br,
            => {
                const switch_br = air.unwrapSwitch(inst);
                var it = switch_br.iterateCases();
                while (it.next()) |case| if (matchTreeDataIndex(tree_data_index, air, case.body)) |i| return i;
                if (matchTreeDataIndex(tree_data_index, air, it.elseBody())) |i| return i;
            },
        }
    }
    return null;
}

pub fn resolveInst(
    air: Air,
    instruction: Air.Inst.Index,
) ?Result {
    const tags = air.instructions.items(.tag);
    const data = air.instructions.items(.data);

    var inst = instruction;
    while (true) {
        const tag = tags[@backingInt(inst)];
        // std.log.err("tag: {t}", .{tags[@backingInt(inst)]});
        switch (tag) {
            else => return null,
            .dbg_var_ptr,
            .dbg_var_val,
            // .dbg_arg_inline,
            => |dbg_var_tag| {
                const operand = data[@backingInt(inst)].pl_op.operand;
                if (operand.toInterned()) |ip_index| {
                    return .{ .inst_tag = dbg_var_tag, .ip_index = ip_index };
                } else if (operand.toIndex()) |sub_inst| {
                    inst = sub_inst;
                    continue;
                } else {
                    return null;
                }
            },
            .alloc => return .{ .inst_tag = .alloc, .ip_index = data[@backingInt(inst)].ty.ip_index },
            .load => return .{ .inst_tag = .load, .ip_index = data[@backingInt(inst)].ty_op.ty.ip_index },
            .call => {
                const operand = data[@backingInt(inst)].pl_op.operand;
                return if (operand.toInterned()) |ip_index| return .{ .inst_tag = .call, .ip_index = ip_index } else null;
            },
            .block,
            .dbg_inline_block,
            => |block_tag| return .{ .inst_tag = block_tag, .ip_index = data[@backingInt(inst)].ty_pl.ty.ip_index },
            .ptr_cast => return .{ .inst_tag = .ptr_cast, .ip_index = data[@backingInt(inst)].ty_op.ty.ip_index },
        }
    }
}

fn toType(
    ip_index: InternPool.Index,
    pt: Zcu.PerThread,
) Type {
    const key = pt.zcu.intern_pool.indexToKey(ip_index);
    return Type.fromInterned(switch (key) {
        // not meaningful
        .undef,
        // values, not types
        .simple_value,
        .@"extern",
        .func,
        .int,
        .err,
        .error_union,
        .enum_literal,
        .enum_tag,
        .float,
        .ptr,
        .slice,
        .opt,
        .aggregate,
        .un,
        .bitpack,
        // memoization, not types
        .memoized_call,
        => key.typeOf(),
        else => ip_index,
    });
}

pub fn typeSlice(
    aira: *Aira,
    arena: Allocator,
    ip_index: InternPool.Index,
) ErrSet![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(arena);
    defer aw.deinit();
    toType(ip_index, aira.active.pt).print(&aw.writer, aira.active.pt, null) catch return "";
    return try aw.toOwnedSlice();
}

pub fn deref(
    aira: *Aira,
    ip_index: InternPool.Index,
) ?InternPool.Index {
    const ty = toType(ip_index, aira.active.pt);
    return if (ty.zigTypeTag(aira.active.pt.zcu) == .pointer) ty.childType(aira.active.pt.zcu).ip_index else null;
}

pub fn derefOrUnwrap(
    aira: *Aira,
    ip_index: InternPool.Index,
) InternPool.Index {
    var ty = Type.fromInterned(ip_index);
    while (switch (aira.active.pt.zcu.intern_pool.indexToKey(ty.ip_index)) {
        .ptr_type,
        .opt_type,
        => true,
        else => false,
    }) {
        ty = if (@backingInt(ty.ip_index) > InternPool.static_len) ty.childType(aira.active.pt.zcu) else ty;
    }
    return ty.ip_index;
}

pub fn resolveFnRetTy(
    aira: *Aira,
    ip_index: InternPool.Index,
) ?InternPool.Index {
    const ty = toType(ip_index, aira.active.pt);
    return switch (aira.active.pt.zcu.intern_pool.indexToKey(ty.ip_index)) {
        .func_type => |ft| ft.return_type,
        else => null,
    };
}

pub const SrcNodeInfo = struct {
    zdoc_uri: []const u8,
    src_node: Ast.Node.Index,
    is_reified: bool,
};

pub fn resolveSrcNode(
    aira: *Aira,
    ip_index: InternPool.Index,
) ?SrcNodeInfo {
    const pt = aira.active.pt;
    const ip = pt.zcu.intern_pool;

    var idx = ip_index;
    const key = ip.indexToKey(idx);
    const zir_index, const is_reified = sw: switch (key) {
        else => return null,
        .undef => {
            idx = key.typeOf();
            const itk = ip.indexToKey(idx);
            continue :sw itk;
        },
        .struct_type => |st| switch (st) {
            .declared => .{ ip.loadStructType(idx).zir_index, false },
            .reified => .{ st.reified.zir_index, true },
            else => return null,
        },
        .enum_type => |et| switch (et) {
            .declared => .{ ip.loadEnumType(idx).zir_index.unwrap() orelse return null, false },
            .reified => .{ et.reified.zir_index, true },
            else => return null,
        },
        .union_type => |ut| switch (ut) {
            .declared => .{ ip.loadUnionType(idx).zir_index, false },
            .reified => .{ ut.reified.zir_index, true },
            else => return null,
        },
    };

    const rez = zir_index.resolveFull(&ip) orelse return null;
    const file = pt.zcu.fileByIndex(rez.file);
    const src_node = file.zir.?.getTypeDeclSrcNode(rez.inst) orelse return null;
    if (!(@backingInt(src_node) < (file.getTree(aira.active.pt.zcu) catch return null).nodes.len)) return null;

    return .{
        .zdoc_uri = file.uri_slice.?,
        .src_node = src_node,
        .is_reified = is_reified,
    };
}

pub fn dumpFields(
    arena: Allocator,
    pt: Zcu.PerThread,
    ip_index: InternPool.Index,
    fields_info_out: *std.ArrayList([]const u8),
) void {
    var idx = ip_index;
    sw: switch (pt.zcu.intern_pool.indexToKey(idx)) {
        else => {},
        .struct_type => {
            fields_info_out.append(arena, "\n\nInterned fields:\n```zig") catch @panic("OOM");
            const let = pt.zcu.intern_pool.loadStructType(idx);
            for (let.field_names.get(&pt.zcu.intern_pool), let.field_types.get(&pt.zcu.intern_pool)) |field_name, field_type_index| {
                const ty = compiler.Compilation.Type.fromInterned(field_type_index);
                fields_info_out.append(arena, arena.print("{s} : {f}", .{ field_name.toSlice(&pt.zcu.intern_pool), ty.fmt(pt) }) catch @panic("OOM")) catch @panic("OOM");
                // std.log.err("{s} : {f}", .{ field_name.toSlice(&pt.zcu.intern_pool), ty.fmt(pt) });
            }
            fields_info_out.append(arena, "\n```\npub fn decls:\n```zig") catch @panic("OOM");
            const namespace = pt.zcu.namespacePtr(let.namespace);
            for (namespace.pub_decls.keys()) |key| {
                const nav = pt.zcu.intern_pool.getNav(key);
                const rez = nav.srcInst(&pt.zcu.intern_pool).resolveFull(&pt.zcu.intern_pool) orelse continue;
                const file = pt.zcu.fileByIndex(rez.file);
                const file_uri = file.uri_slice orelse continue;
                const decl = std.zig.Zir.getDeclaration(file.zir.?, rez.inst);
                const src_node = decl.src_node;
                const zdoc = (pt.zcu.lsp_document_store.?.getOrLoadHandle(file_uri) catch continue) orelse continue;
                if (@backingInt(src_node) < zdoc.tree.nodes.len) {
                    switch (zdoc.tree.nodeTag(src_node)) {
                        .fn_proto_simple,
                        .fn_proto_one,
                        .fn_proto_multi,
                        .fn_proto,
                        .fn_decl,
                        => {},
                        else => continue,
                    }
                    fields_info_out.append(arena, tree_util.nodeToSlice(&zdoc.tree, src_node)) catch @panic("OOM");
                }
            }
            fields_info_out.append(arena, "\n```") catch @panic("OOM");
        },
        .enum_type => {
            fields_info_out.append(arena, "\n\nInterned fields:\n```zig") catch @panic("OOM");
            const let = pt.zcu.intern_pool.loadEnumType(idx);
            for (let.field_names.get(&pt.zcu.intern_pool), 0..) |field_name, i| {
                const field_values = let.field_values.get(&pt.zcu.intern_pool);
                if (i < field_values.len) {
                    const val = compiler.Compilation.Value.fromInterned(field_values[i]);
                    fields_info_out.append(arena, arena.print("{s} = {f}", .{ field_name.toSlice(&pt.zcu.intern_pool), val.fmtValue(pt) }) catch @panic("OOM")) catch @panic("OOM");
                    // std.log.err("{s} = {f}", .{ field_name.toSlice(&pt.zcu.intern_pool), val.fmtValue(pt) });
                } else {
                    fields_info_out.append(arena, arena.print("{s}", .{field_name.toSlice(&pt.zcu.intern_pool)}) catch @panic("OOM")) catch @panic("OOM");
                    // std.log.err("{s}", .{field_name.toSlice(&pt.zcu.intern_pool)});
                }
            }
            fields_info_out.append(arena, "\n```\npub fn decls:\n```zig") catch @panic("OOM");
            const namespace = pt.zcu.namespacePtr(let.namespace);
            for (namespace.pub_decls.keys()) |key| {
                const nav = pt.zcu.intern_pool.getNav(key);
                const rez = nav.srcInst(&pt.zcu.intern_pool).resolveFull(&pt.zcu.intern_pool) orelse continue;
                const file = pt.zcu.fileByIndex(rez.file);
                const file_uri = file.uri_slice orelse continue;
                const decl = std.zig.Zir.getDeclaration(file.zir.?, rez.inst);
                const src_node = decl.src_node;
                const zdoc = (pt.zcu.lsp_document_store.?.getOrLoadHandle(file_uri) catch continue) orelse continue;
                if (@backingInt(src_node) < zdoc.tree.nodes.len) {
                    switch (zdoc.tree.nodeTag(src_node)) {
                        .fn_proto_simple,
                        .fn_proto_one,
                        .fn_proto_multi,
                        .fn_proto,
                        .fn_decl,
                        => {},
                        else => continue,
                    }
                    fields_info_out.append(arena, tree_util.nodeToSlice(&zdoc.tree, src_node)) catch @panic("OOM");
                }
            }
            fields_info_out.append(arena, "```") catch @panic("OOM");
        },
        .union_type => {
            const let = pt.zcu.intern_pool.loadUnionType(idx);
            idx = let.enum_tag_type;
            continue :sw pt.zcu.intern_pool.indexToKey(let.enum_tag_type);
        },
    }
}

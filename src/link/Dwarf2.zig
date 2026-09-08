lf: *link.File,
format: DW.Format,
endian: std.lang.Endian,
address_size: AddressSize,
const_pool: link.ConstPool,

units: []Unit,
/// Indices are `link.ConstPool.Index`.
consts: std.ArrayList(Const),
globals: std.array_hash_map.Auto(InternPool.Nav.Index, Global),
funcs: std.array_hash_map.Auto(InternPool.Nav.Index, Func),
decls: std.array_hash_map.Auto(InternPool.TrackedInst.Index, Decl),
pending_decl: struct { di: Decl.Index, instance: Decl.Instance },

debug_abbrev: Abbrev,
debug_addr: Addr,
frame: Frame,
debug_info: Info,
debug_line: Line,
debug_line_str: Str,
debug_rnglists: Rnglists,
debug_str: Str,
debug_str_offsets: StrOffsets,

pub const AddressSize = enum(u8) { @"32" = 4, @"64" = 8, _ };

pub const Unit = struct {
    alive: bool,
    dirs: std.array_hash_map.Auto(Unit.Index, void),
    files: std.array_hash_map.Auto(Zcu.File.Index, void),
    frame_ni: link.MappedFile.Node.Index.Optional,
    cie_ni: link.MappedFile.Node.Index.Optional,
    debug_info_ni: link.MappedFile.Node.Index.Optional,
    debug_info_header_ni: link.MappedFile.Node.Index.Optional,
    debug_info_footer_ni: link.MappedFile.Node.Index.Optional,
    debug_line_ni: link.MappedFile.Node.Index.Optional,
    debug_line_header_ni: link.MappedFile.Node.Index.Optional,
    debug_line_header_changed: bool,
    debug_rnglists_ni: link.MappedFile.Node.Index.Optional,
    debug_rnglists_offsets_table_offset: usize,
    debug_rnglists_end: usize,

    pub const Index = enum(u32) {
        _,

        pub fn mod(ui: Unit.Index, dwarf: *Dwarf) *Module {
            return dwarf.lf.comp.zcu.?.module_roots.keys()[@backingInt(ui)];
        }

        pub fn get(ui: Unit.Index, dwarf: *Dwarf) *Unit {
            return &dwarf.units[@backingInt(ui)];
        }
    };

    pub const DirIndex = enum(u32) {
        root = 0,
        _,

        fn get(di: DirIndex, unit: *Unit) Unit.Index {
            return unit.dirs.keys()[@backingInt(di)];
        }
    };

    pub const FileIndex = enum(u32) {
        root = 0,
        _,

        fn get(fi: FileIndex, unit: *Unit) Zcu.File.Index {
            return unit.files.keys()[@backingInt(fi)];
        }
    };

    fn deinit(unit: *Unit, gpa: std.mem.Allocator) void {
        unit.dirs.deinit(gpa);
        unit.files.deinit(gpa);
        unit.* = undefined;
    }

    fn getFile(
        unit: *Unit,
        gpa: std.mem.Allocator,
        ui: Unit.Index,
        zfi: Zcu.File.Index,
    ) std.mem.Allocator.Error!struct { DirIndex, FileIndex } {
        assert(unit.alive);
        try unit.dirs.ensureUnusedCapacity(gpa, 1);
        try unit.files.ensureUnusedCapacity(gpa, 1);
        const dir_gop = unit.dirs.getOrPutAssumeCapacity(ui);
        const file_gop = unit.files.getOrPutAssumeCapacity(zfi);
        if (!dir_gop.found_existing or !file_gop.found_existing) unit.debug_line_header_changed = true;
        return .{ @fromBackingInt(@intCast(dir_gop.index)), @fromBackingInt(@intCast(file_gop.index)) };
    }

    pub fn cleanDebugLineHeaderChanged(unit: *Unit) bool {
        defer unit.debug_line_header_changed = false;
        return unit.debug_line_header_changed;
    }
};

pub const Const = struct {
    debug_info_ni: link.MappedFile.Node.Index.Optional,

    pub fn get(cpi: link.ConstPool.Index, dwarf: *Dwarf) *Const {
        return &dwarf.consts.items[@backingInt(cpi)];
    }
};

pub const Global = struct {
    debug_info_ni: link.MappedFile.Node.Index.Optional,

    pub const Index = enum(u32) {
        _,

        pub fn nav(gi: Global.Index, dwarf: *Dwarf) InternPool.Nav.Index {
            return dwarf.globals.keys()[@backingInt(gi)];
        }

        pub fn get(gi: Global.Index, dwarf: *Dwarf) *Global {
            return &dwarf.globals.values()[@backingInt(gi)];
        }
    };
};

pub const Func = struct {
    state: State,
    fde_ni: link.MappedFile.Node.Index.Optional,
    debug_info_ni: link.MappedFile.Node.Index.Optional,
    debug_line_ni: link.MappedFile.Node.Index.Optional,

    pub const State = enum { unresolved, resolved };

    pub const Index = enum(u32) {
        _,

        pub fn nav(fi: Func.Index, dwarf: *Dwarf) InternPool.Nav.Index {
            return dwarf.funcs.keys()[@backingInt(fi)];
        }

        pub fn get(fi: Func.Index, dwarf: *Dwarf) *Func {
            return &dwarf.funcs.values()[@backingInt(fi)];
        }
    };
};

pub const Decl = struct {
    debug_info_ni: link.MappedFile.Node.Index.Optional,

    pub const Index = enum(u32) {
        _,

        pub fn srcInst(di: Decl.Index, dwarf: *Dwarf) InternPool.TrackedInst.Index {
            return dwarf.decls.keys()[@backingInt(di)];
        }

        pub fn get(di: Decl.Index, dwarf: *Dwarf) *Decl {
            return &dwarf.decls.values()[@backingInt(di)];
        }
    };

    const Instance = union(enum) {
        none,
        @"const": InternPool.Index,
        global: InternPool.Nav.Index,
    };
};

pub const Frame = struct {
    header: Header,

    pub const Header = struct {
        code_alignment_factor: u32,
        data_alignment_factor: i32,
        return_address_register: u32,
        initial_instructions: []const Cfa,
    };

    pub const Format = std.debug.Dwarf.Unwind.Section;
};

pub const Abbrev = struct {
    ni: link.MappedFile.Node.Index.Optional,
    end: usize,
    set: std.enums.EnumSet(AbbrevCode),
};

pub const Addr = struct {
    ni: link.MappedFile.Node.Index.Optional,
    pending_index: usize,
    map: std.array_hash_map.Auto(link.File.SymbolId, void),

    fn get(a: *Addr, gpa: std.mem.Allocator, si: link.File.SymbolId) std.mem.Allocator.Error!usize {
        const gop = try a.map.getOrPut(gpa, si);
        return gop.index;
    }

    fn tableOffset(dwarf: *Dwarf) usize {
        return dwarf.unitLengthSize() + 2 + 1 + 1;
    }

    pub fn size(a: *Addr, dwarf: *Dwarf) usize {
        return tableOffset(dwarf) + @backingInt(dwarf.address_size) * a.pending_index;
    }

    pub fn anyPending(a: *Addr) bool {
        return a.map.count() - a.pending_index > 0;
    }
};

pub const Info = struct {};

pub const Line = struct {
    header: Header,

    pub const Header = struct {
        minimum_instruction_length: u8,
        maximum_operations_per_instruction: u8,
        default_is_stmt: bool,
        line_base: i8,
        line_range: u8,
        opcode_base: u8,
    };
};

pub const Str = struct {
    ni: link.MappedFile.Node.Index.Optional,
    end: usize,
    map: std.array_hash_map.Custom(usize, void, Context, true),

    fn get(
        s: *Str,
        gpa: std.mem.Allocator,
        mf: *link.MappedFile,
        str: []const u8,
    ) link.MappedFile.Error!usize {
        const ni = s.ni.unwrap().?;
        const slice = ni.sliceConst(mf);
        const gop = try s.map.getOrPutContextAdapted(
            gpa,
            str,
            Adapter{ .slice = slice },
            .{ .slice = slice },
        );
        if (!gop.found_existing) {
            gop.key_ptr.* = s.end;
            try ni.ensureMinimumSize(gpa, mf, s.end + str.len + 1);
            const slice_mut = ni.slice(mf);
            @memcpy(slice_mut[s.end..][0..str.len], str);
            s.end += str.len;
            slice_mut[s.end] = 0;
            s.end += 1;
        }
        return gop.key_ptr.*;
    }

    const Context = struct {
        slice: []const u8,
        pub fn hash(context: Context, offset: usize) u32 {
            return @truncate(std.hash.Wyhash.hash(0, std.mem.sliceTo(context.slice[offset..], 0)));
        }
        pub fn eql(_: Context, lhs_offset: usize, rhs_offset: usize) bool {
            return lhs_offset == rhs_offset;
        }
    };

    const Adapter = struct {
        slice: []const u8,
        pub fn hash(_: Adapter, key: []const u8) u32 {
            return @truncate(std.hash.Wyhash.hash(0, key));
        }
        pub fn eql(adapter: Adapter, key: []const u8, rhs_offset: usize, _: usize) bool {
            return std.mem.startsWith(u8, adapter.slice[rhs_offset..], key) and
                adapter.slice[rhs_offset + key.len] == 0;
        }
    };
};

pub const Rnglists = struct {
    fn tableOffset(dwarf: *Dwarf) usize {
        return dwarf.unitLengthSize() + 2 + 1 + 1 + 4;
    }

    pub fn size(dwarf: *Dwarf, ui: Unit.Index) usize {
        return ui.get(dwarf).debug_rnglists_end + 1;
    }
};

pub const StrOffsets = struct {
    ni: link.MappedFile.Node.Index.Optional,
    pending_index: usize,
    map: std.array_hash_map.Auto(usize, void),

    fn get(
        so: *StrOffsets,
        dwarf: *Dwarf,
        s: *Str,
        mf: *link.MappedFile,
        str: []const u8,
    ) link.Error!usize {
        const comp = dwarf.lf.comp;
        try so.map.ensureUnusedCapacity(comp.gpa, 1);
        const offset = s.get(comp.gpa, mf, str) catch |err| switch (err) {
            else => |e| return e,
            error.MappedFileIo => return comp.link_diags.fail("failed to write output file: {t}", .{
                mf.io_err.?,
            }),
        };
        const gop = so.map.getOrPutAssumeCapacity(offset);
        return gop.index;
    }

    fn tableOffset(dwarf: *Dwarf) usize {
        return dwarf.unitLengthSize() + 2 + 2;
    }

    pub fn size(so: *StrOffsets, dwarf: *Dwarf) usize {
        return tableOffset(dwarf) + dwarf.secOffsetSize() * so.pending_index;
    }

    pub fn anyPending(so: *StrOffsets) bool {
        return so.map.count() - so.pending_index > 0;
    }
};

pub const SharedSection = enum { debug_abbrev, debug_line_str, debug_str };

pub const Loc = union(enum) {
    empty,
    addr_sym: struct {
        si: link.File.SymbolId,
        offset: usize = 0,
    },
    deref: *const Loc,
    constu: u64,
    consts: i64,
    plus: Bin,
    reg: u32,
    breg: u32,
    push_object_address,
    call: struct {
        args: []const Loc = &.{},
        node: link.MappedFile.Node.Index,
    },
    form_tls_address: *const Loc,
    implicit_value: []const u8,
    stack_value: *const Loc,
    implicit_pointer: struct {
        node: link.MappedFile.Node.Index,
        offset: i65 = 0,
    },
    addrx_sym: link.File.SymbolId,
    constx_sym: link.File.SymbolId,
    wasm_ext: union(enum) {
        local: u32,
        global: u32,
        operand_stack: u32,
    },

    pub const Bin = struct { *const Loc, *const Loc };

    fn getConst(loc: Loc, comptime Int: type) ?Int {
        return switch (loc) {
            .constu => |constu| std.math.cast(Int, constu),
            .consts => |consts| std.math.cast(Int, consts),
            else => null,
        };
    }

    fn getBaseReg(loc: Loc) ?u32 {
        return switch (loc) {
            .breg => |breg| breg,
            else => null,
        };
    }

    fn writeReg(reg: u32, op0: u8, opx: u8, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (std.math.cast(u5, reg)) |small_reg| {
            try writer.writeByte(op0 + small_reg);
        } else {
            try writer.writeByte(opx);
            try writer.writeUleb128(reg);
        }
    }

    fn write(loc: Loc, writer: union(enum) {
        io: *std.Io.Writer,
        mf: *link.MappedFile.Node.Writer,
    }, dwarf: *Dwarf) link.EmitError!void {
        const w = switch (writer) {
            .io => |w| w,
            .mf => |nw| &nw.interface,
        };
        switch (loc) {
            .empty => {},
            .addr_sym => |sym| {
                try w.writeByte(DW.OP.addr);
                switch (writer) {
                    .io => try dwarf.addrPlaceholder(w),
                    .mf => |nw| try dwarf.addrSym(nw, sym.si, sym.offset),
                }
            },
            .deref => |addr| {
                try addr.write(writer, dwarf);
                try w.writeByte(DW.OP.deref);
            },
            .constu => |constu| if (std.math.cast(u5, constu)) |lit| {
                try w.writeByte(@as(u8, DW.OP.lit0) + lit);
            } else if (std.math.cast(u8, constu)) |const1u| {
                try w.writeAll(&.{ DW.OP.const1u, const1u });
            } else if (std.math.cast(u16, constu)) |const2u| {
                try w.writeByte(DW.OP.const2u);
                try w.writeInt(u16, const2u, dwarf.endian);
            } else if (std.math.cast(u21, constu)) |const3u| {
                try w.writeByte(DW.OP.constu);
                try w.writeUleb128(const3u);
            } else if (std.math.cast(u32, constu)) |const4u| {
                try w.writeByte(DW.OP.const4u);
                try w.writeInt(u32, const4u, dwarf.endian);
            } else if (std.math.cast(u49, constu)) |const7u| {
                try w.writeByte(DW.OP.constu);
                try w.writeUleb128(const7u);
            } else {
                try w.writeByte(DW.OP.const8u);
                try w.writeInt(u64, constu, dwarf.endian);
            },
            .consts => |consts| if (std.math.cast(i8, consts)) |const1s| {
                try w.writeAll(&.{ DW.OP.const1s, @bitCast(const1s) });
            } else if (std.math.cast(i16, consts)) |const2s| {
                try w.writeByte(DW.OP.const2s);
                try w.writeInt(i16, const2s, dwarf.endian);
            } else if (std.math.cast(i21, consts)) |const3s| {
                try w.writeByte(DW.OP.consts);
                try w.writeSleb128(const3s);
            } else if (std.math.cast(i32, consts)) |const4s| {
                try w.writeByte(DW.OP.const4s);
                try w.writeInt(i32, const4s, dwarf.endian);
            } else if (std.math.cast(i49, consts)) |const7s| {
                try w.writeByte(DW.OP.consts);
                try w.writeSleb128(const7s);
            } else {
                try w.writeByte(DW.OP.const8s);
                try w.writeInt(i64, consts, dwarf.endian);
            },
            .plus => |plus| done: {
                if (plus[0].getConst(u0)) |_| {
                    try plus[1].write(writer, dwarf);
                    break :done;
                }
                if (plus[1].getConst(u0)) |_| {
                    try plus[0].write(writer, dwarf);
                    break :done;
                }
                if (plus[0].getBaseReg()) |breg| {
                    if (plus[1].getConst(i65)) |offset| {
                        try writeReg(breg, DW.OP.breg0, DW.OP.bregx, w);
                        try w.writeSleb128(offset);
                        break :done;
                    }
                }
                if (plus[1].getBaseReg()) |breg| {
                    if (plus[0].getConst(i65)) |offset| {
                        try writeReg(breg, DW.OP.breg0, DW.OP.bregx, w);
                        try w.writeSleb128(offset);
                        break :done;
                    }
                }
                if (plus[0].getConst(u64)) |uconst| {
                    try plus[1].write(writer, dwarf);
                    try w.writeByte(DW.OP.plus_uconst);
                    try w.writeUleb128(uconst);
                    break :done;
                }
                if (plus[1].getConst(u64)) |uconst| {
                    try plus[0].write(writer, dwarf);
                    try w.writeByte(DW.OP.plus_uconst);
                    try w.writeUleb128(uconst);
                    break :done;
                }
                try plus[0].write(writer, dwarf);
                try plus[1].write(writer, dwarf);
                try w.writeByte(DW.OP.plus);
            },
            .reg => |reg| try writeReg(reg, DW.OP.reg0, DW.OP.regx, w),
            .breg => |breg| {
                try writeReg(breg, DW.OP.breg0, DW.OP.bregx, w);
                try w.writeSleb128(0);
            },
            .push_object_address => try w.writeByte(DW.OP.push_object_address),
            .call => |call| {
                for (call.args) |arg| try arg.write(writer, dwarf);
                try w.writeByte(DW.OP.call_ref);
                switch (writer) {
                    .io => try dwarf.secOffsetPlaceholder(w),
                    .mf => |nw| try dwarf.secOffset(nw, call.node, 0),
                }
            },
            .form_tls_address => |addr| {
                try addr.write(writer, dwarf);
                try w.writeByte(DW.OP.form_tls_address);
            },
            .implicit_value => |value| {
                try w.writeByte(DW.OP.implicit_value);
                try w.writeUleb128(value.len);
                try w.writeAll(value);
            },
            .stack_value => |value| {
                try value.write(writer, dwarf);
                try w.writeByte(DW.OP.stack_value);
            },
            .implicit_pointer => |implicit_pointer| {
                try w.writeByte(DW.OP.implicit_pointer);
                switch (writer) {
                    .io => try dwarf.secOffsetPlaceholder(w),
                    .mf => |nw| try dwarf.secOffset(nw, implicit_pointer.node, 0),
                }
                try w.writeSleb128(implicit_pointer.offset);
            },
            .addrx_sym => |si| {
                try w.writeByte(DW.OP.addrx);
                try dwarf.addrxSym(w, si);
            },
            .constx_sym => |si| {
                try w.writeByte(DW.OP.constx);
                try dwarf.addrxSym(w, si);
            },
            .wasm_ext => |wasm_ext| {
                try w.writeByte(DW.OP.WASM_location);
                switch (wasm_ext) {
                    .local => |local| {
                        try w.writeByte(DW.OP.WASM_local);
                        try w.writeUleb128(local);
                    },
                    .global => |global| if (std.math.cast(u21, global)) |global_u21| {
                        try w.writeByte(DW.OP.WASM_global);
                        try w.writeUleb128(global_u21);
                    } else {
                        try w.writeByte(DW.OP.WASM_global_u32);
                        try w.writeInt(u32, global, dwarf.endian);
                    },
                    .operand_stack => |operand_stack| {
                        try w.writeByte(DW.OP.WASM_operand_stack);
                        try w.writeUleb128(operand_stack);
                    },
                }
            },
        }
    }
};

pub const Cfa = union(enum) {
    nop,
    advance_loc: u32,
    offset: RegOff,
    rel_offset: RegOff,
    restore: u32,
    undefined: u32,
    same_value: u32,
    register: [2]u32,
    remember_state,
    restore_state,
    def_cfa: RegOff,
    def_cfa_register: u32,
    def_cfa_offset: i64,
    adjust_cfa_offset: i64,
    def_cfa_expression: Loc,
    expression: RegExpr,
    val_offset: RegOff,
    val_expression: RegExpr,
    escape: []const u8,

    const RegOff = struct { reg: u32, off: i64 };
    const RegExpr = struct { reg: u32, expr: Loc };

    fn write(cfa: Cfa, wip_func: *WipFunc) link.EmitError!void {
        const df_nw = &wip_func.fde_writer;
        const df_w = &df_nw.interface;
        switch (cfa) {
            .nop => try df_w.writeByte(DW.CFA.nop),
            .advance_loc => |loc| {
                const delta =
                    @divExact(loc - wip_func.cfi.loc, wip_func.dwarf.frame.header.code_alignment_factor);
                if (delta == 0) {} else if (std.math.cast(u6, delta)) |small_delta|
                    try df_w.writeByte(@as(u8, DW.CFA.advance_loc) + small_delta)
                else if (std.math.cast(u8, delta)) |ubyte_delta|
                    try df_w.writeAll(&.{ DW.CFA.advance_loc1, ubyte_delta })
                else if (std.math.cast(u16, delta)) |uhalf_delta| {
                    try df_w.writeByte(DW.CFA.advance_loc2);
                    try df_w.writeInt(u16, uhalf_delta, wip_func.dwarf.endian);
                } else if (std.math.cast(u32, delta)) |uword_delta| {
                    try df_w.writeByte(DW.CFA.advance_loc4);
                    try df_w.writeInt(u32, uword_delta, wip_func.dwarf.endian);
                }
                wip_func.cfi.loc = loc;
            },
            .offset, .rel_offset => |reg_off| {
                const factored_off = @divExact(reg_off.off - switch (cfa) {
                    else => unreachable,
                    .offset => 0,
                    .rel_offset => wip_func.cfi.cfa.off,
                }, wip_func.dwarf.frame.header.data_alignment_factor);
                if (std.math.cast(u63, factored_off)) |unsigned_off| {
                    if (std.math.cast(u6, reg_off.reg)) |small_reg| {
                        try df_w.writeByte(@as(u8, DW.CFA.offset) + small_reg);
                    } else {
                        try df_w.writeByte(DW.CFA.offset_extended);
                        try df_w.writeUleb128(reg_off.reg);
                    }
                    try df_w.writeUleb128(unsigned_off);
                } else {
                    try df_w.writeByte(DW.CFA.offset_extended_sf);
                    try df_w.writeUleb128(reg_off.reg);
                    try df_w.writeSleb128(factored_off);
                }
            },
            .restore => |reg| if (std.math.cast(u6, reg)) |small_reg|
                try df_w.writeByte(@as(u8, DW.CFA.restore) + small_reg)
            else {
                try df_w.writeByte(DW.CFA.restore_extended);
                try df_w.writeUleb128(reg);
            },
            .undefined => |reg| {
                try df_w.writeByte(DW.CFA.undefined);
                try df_w.writeUleb128(reg);
            },
            .same_value => |reg| {
                try df_w.writeByte(DW.CFA.same_value);
                try df_w.writeUleb128(reg);
            },
            .register => |regs| if (regs[0] != regs[1]) {
                try df_w.writeByte(DW.CFA.register);
                for (regs) |reg| try df_w.writeUleb128(reg);
            } else {
                try df_w.writeByte(DW.CFA.same_value);
                try df_w.writeUleb128(regs[0]);
            },
            .remember_state => try df_w.writeByte(DW.CFA.remember_state),
            .restore_state => try df_w.writeByte(DW.CFA.restore_state),
            .def_cfa, .def_cfa_register, .def_cfa_offset, .adjust_cfa_offset => {
                const reg_off: RegOff = switch (cfa) {
                    else => unreachable,
                    .def_cfa => |reg_off| reg_off,
                    .def_cfa_register => |reg| .{ .reg = reg, .off = wip_func.cfi.cfa.off },
                    .def_cfa_offset => |off| .{ .reg = wip_func.cfi.cfa.reg, .off = off },
                    .adjust_cfa_offset => |off| .{
                        .reg = wip_func.cfi.cfa.reg,
                        .off = wip_func.cfi.cfa.off + off,
                    },
                };
                const changed_reg = reg_off.reg != wip_func.cfi.cfa.reg;
                const unsigned_off = std.math.cast(u63, reg_off.off);
                if (reg_off.off == wip_func.cfi.cfa.off) {
                    if (changed_reg) {
                        try df_w.writeByte(DW.CFA.def_cfa_register);
                        try df_w.writeUleb128(reg_off.reg);
                    }
                } else if (switch (wip_func.dwarf.frame.header.data_alignment_factor) {
                    0 => unreachable,
                    1 => unsigned_off != null,
                    else => |data_alignment_factor| @rem(reg_off.off, data_alignment_factor) != 0,
                }) {
                    try df_w.writeByte(if (changed_reg) DW.CFA.def_cfa else DW.CFA.def_cfa_offset);
                    if (changed_reg) try df_w.writeUleb128(reg_off.reg);
                    try df_w.writeUleb128(unsigned_off.?);
                } else {
                    try df_w.writeByte(if (changed_reg) DW.CFA.def_cfa_sf else DW.CFA.def_cfa_offset_sf);
                    if (changed_reg) try df_w.writeUleb128(reg_off.reg);
                    try df_w.writeSleb128(
                        @divExact(reg_off.off, wip_func.dwarf.frame.header.data_alignment_factor),
                    );
                }
                wip_func.cfi.cfa = reg_off;
            },
            .def_cfa_expression => |expr| {
                try df_w.writeByte(DW.CFA.def_cfa_expression);
                try wip_func.dwarf.exprLoc(df_nw, expr);
            },
            .expression => |reg_expr| {
                try df_w.writeByte(DW.CFA.expression);
                try df_w.writeUleb128(reg_expr.reg);
                try wip_func.dwarf.exprLoc(df_nw, reg_expr.expr);
            },
            .val_offset => |reg_off| {
                const factored_off =
                    @divExact(reg_off.off, wip_func.dwarf.frame.header.data_alignment_factor);
                if (std.math.cast(u63, factored_off)) |unsigned_off| {
                    try df_w.writeByte(DW.CFA.val_offset);
                    try df_w.writeUleb128(reg_off.reg);
                    try df_w.writeUleb128(unsigned_off);
                } else {
                    try df_w.writeByte(DW.CFA.val_offset_sf);
                    try df_w.writeUleb128(reg_off.reg);
                    try df_w.writeSleb128(factored_off);
                }
            },
            .val_expression => |reg_expr| {
                try df_w.writeByte(DW.CFA.val_expression);
                try df_w.writeUleb128(reg_expr.reg);
                try wip_func.dwarf.exprLoc(df_nw, reg_expr.expr);
            },
            .escape => |bytes| try df_w.writeAll(bytes),
        }
    }
};

pub const WipFunc = struct {
    dwarf: *Dwarf,
    unit: Unit.Index,
    func: InternPool.Index,
    func_si: link.File.SymbolId,
    cfi: struct {
        loc: u32,
        cfa: Cfa.RegOff,
    },
    frame_format: Frame.Format,
    fde_writer: link.MappedFile.Node.Writer,
    frame_func_length: struct { offset: usize, size: AddressSize },

    pub const Debug = struct {
        wip_func: WipFunc,
        pt: Zcu.PerThread,
        is_empty: bool,
        empty_abbrev_code: AbbrevCode,
        blocks: std.ArrayList(struct {
            abbrev_code_offset: usize,
            low_pc: usize,
            high_pc_offset: usize,
        }),
        info_writer: link.MappedFile.Node.Writer,
        info_func_length_offset: usize,
        line_writer: link.MappedFile.Node.Writer,

        pub fn init(debug: *Debug, pt: Zcu.PerThread) void {
            debug.pt = pt;
            debug.is_empty = true;
            debug.blocks = .empty;
        }

        pub fn deinit(debug: *Debug) void {
            const gpa = debug.pt.zcu.gpa;
            debug.line_writer.deinit();
            debug.info_writer.deinit();
            debug.blocks.deinit(gpa);
            debug.wip_func.deinit();
            debug.* = undefined;
        }

        pub fn genDebugFrame(debug: *Debug, loc: u32, cfa: Cfa) link.Error!void {
            return debug.wip_func.genDebugFrame(loc, cfa);
        }

        pub fn startDebugInfo(debug: *Debug) link.Error!void {
            debug.startDebugInfoInner() catch |err| switch (err) {
                else => |e| return e,
                error.WriteFailed => return debug.wip_func.dwarf.reportWriteError(&debug.info_writer),
            };
        }
        fn startDebugInfoInner(debug: *Debug) link.EmitError!void {
            const dwarf = debug.wip_func.dwarf;
            const pt = debug.pt;
            const zcu = pt.zcu;
            const ip = &zcu.intern_pool;
            const func = zcu.funcInfo(debug.wip_func.func);
            const nav = ip.getNav(func.owner_nav);
            const func_type = ip.indexToKey(func.ty).func_type;
            const inst_info = nav.srcInst(ip).resolveFull(ip).?;
            const zf = zcu.fileByIndex(inst_info.file);
            const target = &zf.mod.?.resolved_target.result;
            const decl = zf.zir.?.getDeclaration(inst_info.inst);
            const di_nw = &debug.info_writer;
            const di_w = &di_nw.interface;
            const parent_ty: Type = .fromInterned(ip.namespacePtr(switch (func.generic_owner) {
                else => |generic_owner| ip.getNav(zcu.funcInfo(generic_owner).owner_nav),
                .none => nav,
            }.analysis.?.namespace).owner_type);
            if (func.generic_owner != .none or parent_ty.getCaptures(zcu).len > 0) {
                debug.empty_abbrev_code = .decl_instance_empty_func;
                try dwarf.abbrevCode(di_nw, .decl_instance_func);
                try dwarf.refType(pt, di_nw, parent_ty);
                try dwarf.secOffset(di_nw, try dwarf.getConstDecl(pt, debug.wip_func.func), 0);
            } else {
                debug.empty_abbrev_code = .decl_empty_func;
                try dwarf.abbrevCode(di_nw, .decl_func);
                try dwarf.refType(pt, di_nw, parent_ty);
                try di_w.writeInt(u32, decl.src_line + 1, dwarf.endian);
                try di_w.writeUleb128(decl.src_column + 1);
                try di_w.writeByte(if (decl.is_pub) DW.ACCESS.public else DW.ACCESS.private);
                try dwarf.strx(di_nw, nav.name.toSlice(ip));
            }
            try dwarf.strx(di_nw, switch (decl.linkage) {
                .normal => nav.fqn,
                .@"extern", .@"export" => nav.name,
            }.toSlice(ip));
            try dwarf.refType(pt, di_nw, .fromInterned(func_type.return_type));
            try dwarf.addrxSym(di_w, debug.wip_func.func_si);
            debug.info_func_length_offset = di_w.end;
            try di_w.writeInt(u32, undefined, dwarf.endian);
            try di_w.writeUleb128(
                target_info.minFunctionAlignment(target).max(nav.resolved.?.@"align").toByteUnits().?,
            );
            try di_w.writeAll(&.{
                @intFromBool(decl.linkage != .normal),
                @intFromBool(Type.fromInterned(func_type.return_type).isNoReturn(zcu)),
            });
        }

        pub fn startDebugLine(debug: *Debug) link.Error!void {
            debug.startDebugLineInner() catch |err| switch (err) {
                else => |e| return e,
                error.WriteFailed => return debug.wip_func.dwarf.reportWriteError(&debug.line_writer),
            };
        }
        fn startDebugLineInner(debug: *Debug) link.EmitError!void {
            const dwarf = debug.wip_func.dwarf;
            const zcu = debug.pt.zcu;
            const ip = &zcu.intern_pool;
            const func = zcu.funcInfo(debug.wip_func.func);
            const inst_info = ip.getNav(func.owner_nav).srcInst(ip).resolveFull(ip).?;
            const zf = zcu.fileByIndex(inst_info.file);
            const decl = zf.zir.?.getDeclaration(inst_info.inst);
            const dl_nw = &debug.line_writer;
            const dl_w = &dl_nw.interface;
            try dl_w.writeByte(DW.LNS.extended_op);
            if (zcu.comp.config.incremental) {
                try dl_w.writeUleb128(1 + dwarf.secOffsetSize());
                try dl_w.writeByte(DW.LNE.ZIG_set_decl);
                try dwarf.secOffset(dl_nw, debug.info_writer.ni, 0);

                try dl_w.writeByte(DW.LNS.set_column);
                try dl_w.writeUleb128(func.lbrace_column + 1);

                try debug.advanceLineAndPc(func.lbrace_line, 0, false);
            } else {
                try dl_w.writeUleb128(1 + @backingInt(dwarf.address_size));
                try dl_w.writeByte(DW.LNE.set_address);
                try dwarf.addrSym(dl_nw, debug.wip_func.func_si, 0);

                const ui = dwarf.getUnit(zf.mod.?);
                _, const fi = try ui.get(dwarf).getFile(zcu.gpa, ui, inst_info.file);
                try dl_w.writeByte(DW.LNS.set_file);
                try dl_w.writeUleb128(@backingInt(fi));

                try dl_w.writeByte(DW.LNS.set_column);
                try dl_w.writeUleb128(func.lbrace_column + 1);

                try debug.advanceLineAndPc(decl.src_line + func.lbrace_line, 0, false);
            }
        }

        pub fn finish(debug: *Debug, func_length: u64) link.Error!void {
            const di_nw = &debug.info_writer;
            debug.finishDebugInfo(func_length) catch |err| switch (err) {
                else => |e| return e,
                error.WriteFailed => return debug.wip_func.dwarf.reportWriteError(di_nw),
            };
            debug.finishDebugLine() catch |err| switch (err) {
                else => |e| return e,
                error.WriteFailed => return debug.wip_func.dwarf.reportWriteError(di_nw),
            };
        }
        fn finishDebugInfo(debug: *Debug, func_length: u64) link.EmitError!void {
            const dwarf = debug.wip_func.dwarf;
            const di_nw = &debug.info_writer;
            const di_w = &di_nw.interface;
            std.mem.writeInt(
                u32,
                di_w.buffered()[debug.info_func_length_offset..][0..4],
                @intCast(func_length),
                dwarf.endian,
            );
            if (debug.is_empty) std.leb.writeUnsignedFixed(
                AbbrevCode.decl_size,
                di_w.buffered()[0..AbbrevCode.decl_size],
                @intCast(try dwarf.refAbbrevCode(di_nw.mf, debug.empty_abbrev_code)),
            ) else try di_w.writeUleb128(@backingInt(AbbrevCode.null));
            try dwarf.genDebugInfoPadding(di_w, di_w.unusedCapacityLen());
        }
        fn finishDebugLine(debug: *Debug) link.EmitError!void {
            const dl_w = &debug.line_writer.interface;
            try genDebugLinePadding(dl_w, dl_w.unusedCapacityLen());
        }

        pub const LocalVarTag = enum { arg, local_var };
        pub fn genLocalVarDebugInfo(
            debug: *Debug,
            tag: LocalVarTag,
            opt_name: ?[]const u8,
            ty: Type,
            loc: Loc,
        ) link.Error!void {
            return debug.genLocalVarDebugInfoInner(tag, opt_name, ty, loc) catch |err| switch (err) {
                else => |e| e,
                error.WriteFailed => return debug.wip_func.dwarf.reportWriteError(&debug.info_writer),
            };
        }
        fn genLocalVarDebugInfoInner(
            debug: *Debug,
            tag: LocalVarTag,
            opt_name: ?[]const u8,
            ty: Type,
            loc: Loc,
        ) link.EmitError!void {
            const dwarf = debug.wip_func.dwarf;
            const di_nw = &debug.info_writer;
            try dwarf.abbrevCode(di_nw, switch (tag) {
                .arg => if (opt_name) |_| .arg else .unnamed_arg,
                .local_var => if (opt_name) |_| .local_var else unreachable,
            });
            if (opt_name) |name| try dwarf.strx(di_nw, name);
            try dwarf.refType(debug.pt, di_nw, ty);
            try dwarf.exprLoc(di_nw, loc);
            debug.is_empty = false;
        }

        pub const LocalConstTag = enum { comptime_arg, local_const };
        pub fn genLocalConstDebugInfo(
            debug: *Debug,
            tag: LocalConstTag,
            opt_name: ?[]const u8,
            val: Value,
        ) link.Error!void {
            return debug.genLocalConstDebugInfoInner(tag, opt_name, val) catch |err| switch (err) {
                else => |e| e,
                error.WriteFailed => return debug.wip_func.dwarf.reportWriteError(&debug.info_writer),
            };
        }
        fn genLocalConstDebugInfoInner(
            debug: *Debug,
            tag: LocalConstTag,
            opt_name: ?[]const u8,
            val: Value,
        ) link.EmitError!void {
            const dwarf = debug.wip_func.dwarf;
            const pt = debug.pt;
            const zcu = debug.pt.zcu;
            const ty = val.typeOf(zcu);
            const ty_class = ty.classify(zcu);
            const di_nw = &debug.info_writer;
            try dwarf.abbrevCode(di_nw, switch (tag) {
                .comptime_arg => if (opt_name) |_| switch (ty_class) {
                    .no_possible_value => unreachable,
                    .one_possible_value => .comptime_arg,
                    .runtime => .comptime_arg_fully_runtime,
                    .partially_comptime => .comptime_arg_partially_comptime,
                    .fully_comptime => .comptime_arg_fully_comptime,
                } else switch (ty_class) {
                    .no_possible_value => unreachable,
                    .one_possible_value => .unnamed_comptime_arg,
                    .runtime => .unnamed_comptime_arg_fully_runtime,
                    .partially_comptime => .unnamed_comptime_arg_partially_comptime,
                    .fully_comptime => .unnamed_comptime_arg_fully_comptime,
                },
                .local_const => if (opt_name) |_| switch (ty_class) {
                    .no_possible_value => unreachable,
                    .one_possible_value => .local_const,
                    .runtime => .local_const_fully_runtime,
                    .partially_comptime => .local_const_partially_comptime,
                    .fully_comptime => .local_const_fully_comptime,
                } else unreachable,
            });
            if (opt_name) |name| try dwarf.strx(di_nw, name);
            try dwarf.refType(pt, di_nw, ty);
            if (ty_class.hasRuntimeBits()) try dwarf.blockConst(pt, di_nw, val);
            if (ty_class.comptimeOnly()) try dwarf.refConst(pt, di_nw, val);
            debug.is_empty = false;
        }

        pub fn genVarArgsDebugInfo(debug: *Debug) link.Error!void {
            return debug.genVarArgsDebugInfoInner() catch |err| switch (err) {
                else => |e| e,
                error.WriteFailed => return debug.wip_func.dwarf.reportWriteError(&debug.info_writer),
            };
        }
        fn genVarArgsDebugInfoInner(debug: *Debug) link.EmitError!void {
            try debug.wip_func.dwarf.abbrevCode(&debug.info_writer, .is_var_args);
            debug.is_empty = false;
        }

        pub fn advanceLineAndPc(
            debug: *Debug,
            delta_line: i33,
            delta_pc: u64,
            end: bool,
        ) link.Error!void {
            return debug.advanceLineAndPcInner(delta_line, delta_pc, end) catch |err| switch (err) {
                error.WriteFailed => return debug.wip_func.dwarf.reportWriteError(&debug.line_writer),
            };
        }
        fn advanceLineAndPcInner(
            debug: *Debug,
            delta_line: i33,
            delta_pc: u64,
            end: bool,
        ) std.Io.Writer.Error!void {
            const dl_w = &debug.line_writer.interface;

            const header = debug.wip_func.dwarf.debug_line.header;
            assert(header.maximum_operations_per_instruction == 1);
            const delta_op: u64 = 0;

            const remaining_delta_line: i9 = @intCast(if (delta_line < header.line_base or
                delta_line - header.line_base >= header.line_range)
            remaining: {
                assert(delta_line != 0);
                try dl_w.writeByte(DW.LNS.advance_line);
                try dl_w.writeSleb128(delta_line);
                break :remaining 0;
            } else delta_line);

            const op_advance = @divExact(delta_pc, header.minimum_instruction_length) *
                header.maximum_operations_per_instruction + delta_op;
            const max_op_advance: u9 = (std.math.maxInt(u8) - header.opcode_base) / header.line_range;
            const remaining_op_advance: u8 = @intCast(if (end or
                op_advance >= 2 * max_op_advance)
            remaining: {
                if (op_advance == max_op_advance) {
                    try dl_w.writeByte(DW.LNS.const_add_pc);
                } else if (op_advance != 0) {
                    try dl_w.writeByte(DW.LNS.advance_pc);
                    try dl_w.writeUleb128(op_advance);
                } else assert(end);
                break :remaining 0;
            } else if (op_advance >= max_op_advance) remaining: {
                try dl_w.writeByte(DW.LNS.const_add_pc);
                break :remaining op_advance - max_op_advance;
            } else op_advance);

            if (remaining_delta_line != 0 or remaining_op_advance != 0) {
                assert(!end);
                try dl_w.writeByte(@intCast((remaining_delta_line - header.line_base) +
                    (header.line_range * remaining_op_advance) + header.opcode_base));
            } else if (end) {
                try dl_w.writeByte(DW.LNS.extended_op);
                try dl_w.writeUleb128(1);
                try dl_w.writeByte(DW.LNE.end_sequence);
            } else try dl_w.writeByte(DW.LNS.copy);
        }

        pub fn setColumn(debug: *Debug, column: u32) link.Error!void {
            return debug.setColumnInner(column) catch |err| switch (err) {
                error.WriteFailed => return debug.wip_func.dwarf.reportWriteError(&debug.line_writer),
            };
        }
        fn setColumnInner(debug: *Debug, column: u32) std.Io.Writer.Error!void {
            const dl_w = &debug.line_writer.interface;
            try dl_w.writeByte(DW.LNS.set_column);
            try dl_w.writeUleb128(column + 1);
        }

        pub fn negateStmt(debug: *Debug) link.Error!void {
            return debug.negateStmtInner() catch |err| switch (err) {
                error.WriteFailed => return debug.wip_func.dwarf.reportWriteError(&debug.line_writer),
            };
        }
        fn negateStmtInner(debug: *Debug) std.Io.Writer.Error!void {
            try debug.line_writer.interface.writeByte(DW.LNS.negate_stmt);
        }

        pub fn setPrologueEnd(debug: *Debug) link.Error!void {
            return debug.setPrologueEndInner() catch |err| switch (err) {
                error.WriteFailed => return debug.wip_func.dwarf.reportWriteError(&debug.line_writer),
            };
        }
        fn setPrologueEndInner(debug: *Debug) std.Io.Writer.Error!void {
            try debug.line_writer.interface.writeByte(DW.LNS.set_prologue_end);
        }

        pub fn setEpilogueBegin(debug: *Debug) link.Error!void {
            return debug.setEpilogueBeginInner() catch |err| switch (err) {
                error.WriteFailed => return debug.wip_func.dwarf.reportWriteError(&debug.line_writer),
            };
        }
        fn setEpilogueBeginInner(debug: *Debug) std.Io.Writer.Error!void {
            try debug.line_writer.interface.writeByte(DW.LNS.set_epilogue_begin);
        }

        pub fn enterBlock(debug: *Debug, code_offset: usize) link.Error!void {
            return debug.enterBlockInner(code_offset) catch |err| switch (err) {
                else => |e| e,
                error.WriteFailed => return debug.wip_func.dwarf.reportWriteError(&debug.info_writer),
            };
        }
        fn enterBlockInner(debug: *Debug, code_offset: usize) link.EmitError!void {
            const dwarf = debug.wip_func.dwarf;
            const block = try debug.blocks.addOne(dwarf.lf.comp.gpa);

            const di_nw = &debug.info_writer;
            const di_w = &di_nw.interface;
            block.abbrev_code_offset = di_w.end;
            try dwarf.abbrevCode(di_nw, .block);
            block.low_pc = code_offset;
            try dwarf.addrSym(di_nw, debug.wip_func.func_si, code_offset);
            block.high_pc_offset = di_w.end;
            try di_w.writeInt(u32, 0, dwarf.endian);
            debug.is_empty = true;
        }

        pub fn leaveBlock(debug: *Debug, code_offset: usize) link.Error!void {
            return debug.leaveBlockInner(code_offset) catch |err| switch (err) {
                else => |e| e,
                error.WriteFailed => return debug.wip_func.dwarf.reportWriteError(&debug.info_writer),
            };
        }
        fn leaveBlockInner(debug: *Debug, code_offset: usize) link.EmitError!void {
            const dwarf = debug.wip_func.dwarf;
            const block = debug.blocks.pop().?;

            const di_nw = &debug.info_writer;
            const di_w = &di_nw.interface;
            const block_size = comptime uleb128Size(@backingInt(AbbrevCode.block));
            if (debug.is_empty) std.leb.writeUnsignedFixed(
                block_size,
                di_w.buffered()[block.abbrev_code_offset..][0..block_size],
                @intCast(try dwarf.refAbbrevCode(di_nw.mf, .empty_block)),
            ) else try di_w.writeUleb128(@backingInt(AbbrevCode.null));
            std.mem.writeInt(
                u32,
                di_nw.interface.buffered()[block.high_pc_offset..][0..4],
                @intCast(code_offset - block.low_pc),
                dwarf.endian,
            );
            debug.is_empty = false;
        }

        pub fn enterInlineFunc(
            debug: *Debug,
            func: InternPool.Index,
            code_offset: usize,
            line: u32,
            column: u32,
        ) link.Error!void {
            return debug.enterInlineFuncInner(
                func,
                code_offset,
                line,
                column,
            ) catch |err| switch (err) {
                else => |e| e,
                error.WriteFailed => return debug.wip_func.dwarf.reportWriteError(&debug.info_writer),
            };
        }
        fn enterInlineFuncInner(
            debug: *Debug,
            func: InternPool.Index,
            code_offset: usize,
            line: u32,
            column: u32,
        ) link.EmitError!void {
            const dwarf = debug.wip_func.dwarf;
            const pt = debug.pt;
            const zcu = pt.zcu;
            const block = try debug.blocks.addOne(zcu.gpa);

            const di_nw = &debug.info_writer;
            const di_w = &di_nw.interface;
            block.abbrev_code_offset = di_w.end;
            try dwarf.abbrevCode(di_nw, .inlined_func);
            try dwarf.refConst(pt, di_nw, .fromInterned(func));
            try di_w.writeUleb128((if (zcu.comp.config.incremental)
                0
            else
                zcu.navSrcLine(zcu.funcInfo(debug.wip_func.func).owner_nav) + 1) + line);
            try di_w.writeUleb128(column + 1);
            block.low_pc = code_offset;
            try dwarf.addrSym(di_nw, debug.wip_func.func_si, code_offset);
            block.high_pc_offset = di_w.end;
            try di_w.writeInt(u32, 0, dwarf.endian);
            try debug.setInlineFunc(func);
            debug.is_empty = true;
        }

        pub fn leaveInlineFunc(
            debug: *Debug,
            func: InternPool.Index,
            code_offset: usize,
        ) link.Error!void {
            return debug.leaveInlineFuncInner(func, code_offset) catch |err| switch (err) {
                else => |e| e,
                error.WriteFailed => return debug.wip_func.dwarf.reportWriteError(&debug.info_writer),
            };
        }
        fn leaveInlineFuncInner(
            debug: *Debug,
            func: InternPool.Index,
            code_offset: usize,
        ) link.EmitError!void {
            const dwarf = debug.wip_func.dwarf;
            const block = debug.blocks.pop().?;

            const di_nw = &debug.info_writer;
            const di_w = &di_nw.interface;
            const inlined_func_size = comptime uleb128Size(@backingInt(AbbrevCode.inlined_func));
            if (debug.is_empty) std.leb.writeUnsignedFixed(
                inlined_func_size,
                di_w.buffered()[block.abbrev_code_offset..][0..inlined_func_size],
                @intCast(try dwarf.refAbbrevCode(di_nw.mf, .empty_inlined_func)),
            ) else try di_w.writeUleb128(@backingInt(AbbrevCode.null));
            std.mem.writeInt(
                u32,
                di_w.buffered()[block.high_pc_offset..][0..4],
                @intCast(code_offset - block.low_pc),
                dwarf.endian,
            );
            try debug.setInlineFunc(func);
            debug.is_empty = false;
        }

        pub fn setInlineFunc(debug: *Debug, func: InternPool.Index) link.Error!void {
            return debug.setInlineFuncInner(func) catch |err| switch (err) {
                else => |e| e,
                error.WriteFailed => return debug.wip_func.dwarf.reportWriteError(&debug.line_writer),
            };
        }
        fn setInlineFuncInner(debug: *Debug, func: InternPool.Index) link.EmitError!void {
            const zcu = debug.pt.zcu;
            const ip = &zcu.intern_pool;
            const dwarf = debug.wip_func.dwarf;
            if (debug.wip_func.func == func) return;

            const dl_nw = &debug.line_writer;
            const dl_w = &dl_nw.interface;
            const new_owner_nav = zcu.funcInfo(func).owner_nav;
            if (zcu.comp.config.incremental) {
                const new_func = try dwarf.getFunc(new_owner_nav);
                try dl_w.writeByte(DW.LNS.extended_op);
                try dl_w.writeUleb128(1 + dwarf.secOffsetSize());
                try dl_w.writeByte(DW.LNE.ZIG_set_decl);
                try dwarf.secOffset(dl_nw, new_func.get(dwarf).debug_info_ni.unwrap().?, 0);
                return;
            }

            const old_owner_nav = zcu.funcInfo(debug.wip_func.func).owner_nav;
            const old_inst_info = ip.getNav(old_owner_nav).srcInst(ip).resolveFull(ip).?;
            const old_zf = zcu.fileByIndex(old_inst_info.file);
            const new_inst_info = ip.getNav(new_owner_nav).srcInst(ip).resolveFull(ip).?;
            const new_zf = zcu.fileByIndex(new_inst_info.file);
            if (old_inst_info.file != new_inst_info.file) {
                const new_ui = dwarf.getUnit(new_zf.mod.?);
                _, const new_fi =
                    try debug.wip_func.unit.get(dwarf).getFile(zcu.gpa, new_ui, new_inst_info.file);

                try dl_w.writeByte(DW.LNS.set_file);
                try dl_w.writeUleb128(@backingInt(new_fi));
            }

            const old_src_line: i33 = old_zf.zir.?.getDeclaration(old_inst_info.inst).src_line;
            const new_src_line: i33 = new_zf.zir.?.getDeclaration(new_inst_info.inst).src_line;
            if (new_src_line != old_src_line) {
                try dl_w.writeByte(DW.LNS.advance_line);
                try dl_w.writeSleb128(new_src_line - old_src_line);
            }

            debug.wip_func.func = func;
        }
    };

    pub fn deinit(wip_func: *WipFunc) void {
        wip_func.fde_writer.deinit();
        wip_func.* = undefined;
    }

    pub fn genDebugFrameHeader(wip_func: *WipFunc) link.Error!void {
        wip_func.genDebugFrameHeaderInner() catch |err| switch (err) {
            else => |e| return e,
            error.WriteFailed => return wip_func.dwarf.reportWriteError(&wip_func.fde_writer),
        };
    }
    fn genDebugFrameHeaderInner(wip_func: *WipFunc) link.EmitError!void {
        const dwarf = wip_func.dwarf;
        const df_nw = &wip_func.fde_writer;
        const df_w = &df_nw.interface;
        try dwarf.genUnitLength(df_w);
        switch (wip_func.frame_format) {
            .eh_frame => {
                try df_w.writeInt(u32, undefined, dwarf.endian);
                {
                    const offset = df_w.end;
                    try df_w.writeInt(u32, 0, dwarf.endian);
                    if (dwarf.lf.cast(.elf2)) |elf| try elf.addReloc(
                        @bitCast(df_nw.ni),
                        offset,
                        wip_func.func_si,
                        0,
                        .rel32(elf),
                    ) else unreachable;
                }
                wip_func.frame_func_length = .{ .offset = df_w.end, .size = .@"32" };
                try df_w.writeInt(u32, undefined, dwarf.endian);
                try df_w.writeUleb128(0);
            },
            .debug_frame => {
                try dwarf.secOffset(df_nw, wip_func.unit.get(dwarf).cie_ni.unwrap().?, 0);
                try dwarf.addrSym(df_nw, wip_func.func_si, 0);
                wip_func.frame_func_length = .{ .offset = df_w.end, .size = dwarf.address_size };
                try dwarf.addrPlaceholder(df_w);
            },
        }
    }

    pub fn genDebugFrame(wip_func: *WipFunc, loc: u32, cfa: Cfa) link.Error!void {
        return wip_func.genDebugFrameInner(loc, cfa) catch |err| switch (err) {
            else => |e| return e,
            error.WriteFailed => return wip_func.dwarf.reportWriteError(&wip_func.fde_writer),
        };
    }
    fn genDebugFrameInner(wip_func: *WipFunc, loc: u32, cfa: Cfa) link.EmitError!void {
        const loc_cfa: Cfa = .{ .advance_loc = loc };
        try loc_cfa.write(wip_func);
        try cfa.write(wip_func);
    }

    pub fn finishDebugFrameFde(wip_func: *WipFunc, func_length: u64) void {
        const dwarf = wip_func.dwarf;
        const df_w = &wip_func.fde_writer.interface;
        switch (wip_func.frame_func_length.size) {
            _ => unreachable,
            .@"32" => std.mem.writeInt(
                u32,
                df_w.buffered()[wip_func.frame_func_length.offset..][0..4],
                @intCast(func_length),
                dwarf.endian,
            ),
            .@"64" => std.mem.writeInt(
                u64,
                df_w.buffered()[wip_func.frame_func_length.offset..][0..8],
                func_length,
                dwarf.endian,
            ),
        }
        @memset(df_w.unusedCapacitySlice(), DW.CFA.nop);
    }
};

pub fn init(lf: *link.File, format: DW.Format) Dwarf {
    const target = &lf.comp.root_mod.resolved_target.result;
    return .{
        .lf = lf,
        .format = format,
        .address_size = switch (target.ptrBitWidth()) {
            0...32 => .@"32",
            33...64 => .@"64",
            else => unreachable,
        },
        .endian = target.cpu.arch.endian(),
        .const_pool = .empty,

        .units = &.{},
        .consts = .empty,
        .globals = .empty,
        .funcs = .empty,
        .decls = .empty,
        .pending_decl = .{ .di = undefined, .instance = .none },

        .debug_abbrev = .{
            .ni = .none,
            .end = 0,
            .set = .empty,
        },
        .debug_addr = .{
            .ni = .none,
            .pending_index = 0,
            .map = .empty,
        },
        .frame = .{
            .header = if (target.cpu.arch == .x86_64 and target.ofmt == .elf) header: {
                dev.checkAny(&.{ .llvm_backend, .x86_64_backend });
                const Register = @import("../codegen/x86_64/bits.zig").Register;
                break :header comptime .{
                    .code_alignment_factor = 1,
                    .data_alignment_factor = -8,
                    .return_address_register = Register.rip.dwarfNum(),
                    .initial_instructions = &.{
                        .{ .def_cfa = .{ .reg = Register.rsp.dwarfNum(), .off = 8 } },
                        .{ .offset = .{ .reg = Register.rip.dwarfNum(), .off = -8 } },
                    },
                };
            } else .{
                .code_alignment_factor = undefined,
                .data_alignment_factor = undefined,
                .return_address_register = undefined,
                .initial_instructions = &.{},
            },
        },
        .debug_info = .{},
        .debug_line = .{
            .header = switch (target.cpu.arch) {
                .x86_64, .aarch64 => .{
                    .minimum_instruction_length = 1,
                    .maximum_operations_per_instruction = 1,
                    .default_is_stmt = true,
                    .line_base = -5,
                    .line_range = 14,
                    .opcode_base = DW.LNS.set_isa + 1,
                },
                else => .{
                    .minimum_instruction_length = 1,
                    .maximum_operations_per_instruction = 1,
                    .default_is_stmt = true,
                    .line_base = 0,
                    .line_range = 1,
                    .opcode_base = DW.LNS.set_isa + 1,
                },
            },
        },
        .debug_line_str = .{
            .ni = .none,
            .end = 0,
            .map = .empty,
        },
        .debug_rnglists = .{},
        .debug_str = .{
            .ni = .none,
            .end = 0,
            .map = .empty,
        },
        .debug_str_offsets = .{
            .ni = .none,
            .pending_index = 0,
            .map = .empty,
        },
    };
}

pub fn deinit(dwarf: *Dwarf) void {
    const gpa = dwarf.lf.comp.gpa;
    dwarf.const_pool.deinit(gpa);
    for (dwarf.units) |*unit| unit.deinit(gpa);
    gpa.free(dwarf.units);
    dwarf.consts.deinit(gpa);
    dwarf.globals.deinit(gpa);
    dwarf.funcs.deinit(gpa);
    dwarf.decls.deinit(gpa);
    dwarf.debug_addr.map.deinit(gpa);
    dwarf.debug_line_str.map.deinit(gpa);
    dwarf.debug_str.map.deinit(gpa);
    dwarf.debug_str_offsets.map.deinit(gpa);
    dwarf.* = undefined;
}

pub fn initUnits(dwarf: *Dwarf, gpa: std.mem.Allocator, units_len: usize) std.mem.Allocator.Error!void {
    assert(dwarf.units.len == 0);
    dwarf.units = try gpa.alloc(Unit, units_len);
    @memset(dwarf.units, .{
        .alive = false,
        .dirs = .empty,
        .files = .empty,
        .frame_ni = .none,
        .cie_ni = .none,
        .debug_info_ni = .none,
        .debug_info_header_ni = .none,
        .debug_info_footer_ni = .none,
        .debug_line_ni = .none,
        .debug_line_header_ni = .none,
        .debug_line_header_changed = false,
        .debug_rnglists_ni = .none,
        .debug_rnglists_offsets_table_offset = undefined,
        .debug_rnglists_end = undefined,
    });
}
pub fn updateUnits(dwarf: *Dwarf, zcu: *Zcu) std.mem.Allocator.Error!bool {
    var units_changed = false;
    for (zcu.module_roots.values(), dwarf.units, 0..) |root, *unit, ui| {
        const root_zfi = root.unwrap() orelse continue; // non-zig
        const alive = zcu.alive_files.contains(root_zfi);
        if (unit.alive == alive) continue; // unchanged
        unit.alive = alive;
        units_changed = true;
        if (!alive) continue; // unreferenced
        assert(zcu.fileByIndex(root_zfi).mod != null);
        const root_di, const root_fi = try unit.getFile(
            zcu.gpa,
            @fromBackingInt(@intCast(ui)),
            root_zfi,
        );
        assert(root_di == .root and root_fi == .root);
    }
    return units_changed;
}

pub fn getUnit(dwarf: *Dwarf, mod: *Module) Unit.Index {
    return @fromBackingInt(@intCast(dwarf.lf.comp.zcu.?.module_roots.getIndex(mod).?));
}

pub fn getConst(dwarf: *Dwarf, pt: Zcu.PerThread, val: Value) link.Error!link.ConstPool.Index {
    assert(val.typeOf(pt.zcu).comptimeOnly(pt.zcu));
    return dwarf.const_pool.get(pt, dwarf.constPoolUser(), val.toIntern());
}

pub fn getGlobal(dwarf: *Dwarf, nav: InternPool.Nav.Index) link.Error!Global.Index {
    const comp = dwarf.lf.comp;
    const global_gop = try dwarf.globals.getOrPut(comp.gpa, nav);
    if (!global_gop.found_existing) global_gop.value_ptr.* = .{
        .debug_info_ni = .none,
    };
    const gi: Global.Index = @fromBackingInt(@intCast(global_gop.index));
    if (global_gop.value_ptr.debug_info_ni != .none) return gi;
    const mod = comp.zcu.?.navFileScope(nav).mod.?;
    assert(!mod.strip);
    if (dwarf.lf.cast(.elf2)) |elf| {
        try elf.nodes.ensureUnusedCapacity(comp.gpa, 1);
        try elf.dwarf_globals.append(comp.gpa, .{
            .debug_info_first_target_reloc = .none,
            .debug_info_first_node_reloc = .none,
            .debug_info_first_symbol_reloc = .none,
        });
        const unit = dwarf.getUnit(mod).get(dwarf);
        global_gop.value_ptr.debug_info_ni = .wrap(elf.addNodeAssumeCapacity(
            unit.debug_info_ni.unwrap().?.addFloatingChild(comp.gpa, &elf.mf, .{
                .enable_next_moved = true,
            }) catch |err| switch (err) {
                else => |e| return e,
                error.MappedFileIo => return comp.link_diags.fail("failed to write output file: {t}", .{
                    elf.mf.io_err.?,
                }),
            },
            .{ .global_debug_info = gi },
        ));
    } else unreachable;
    return gi;
}
pub fn getGlobalIfExists(dwarf: *Dwarf, nav: InternPool.Nav.Index) ?Global.Index {
    return @fromBackingInt(@intCast(dwarf.globals.getIndex(nav) orelse return null));
}

pub fn getFunc(dwarf: *Dwarf, nav: InternPool.Nav.Index) link.Error!Func.Index {
    const comp = dwarf.lf.comp;
    const gpa = comp.gpa;
    const func_gop = try dwarf.funcs.getOrPut(gpa, nav);
    if (!func_gop.found_existing) func_gop.value_ptr.* = .{
        .state = .unresolved,
        .fde_ni = .none,
        .debug_info_ni = .none,
        .debug_line_ni = .none,
    };
    const fi: Func.Index = @fromBackingInt(@intCast(func_gop.index));
    if (func_gop.value_ptr.debug_info_ni != .none) return fi;
    const mod = comp.zcu.?.navFileScope(nav).mod.?;
    if (dwarf.lf.cast(.elf2)) |elf| {
        try elf.nodes.ensureUnusedCapacity(gpa, 1);
        try elf.dwarf_funcs.append(gpa, .{
            .frame_fde_first_symbol_reloc = .none,
            .frame_fde_first_node_reloc = .none,
            .debug_info_first_target_reloc = .none,
            .debug_info_first_symbol_reloc = .none,
            .debug_info_first_node_reloc = .none,
            .debug_line_first_symbol_reloc = .none,
            .debug_line_first_node_reloc = .none,
        });
        if (mod.strip) return fi;
        const unit = dwarf.getUnit(mod).get(dwarf);
        func_gop.value_ptr.debug_info_ni = .wrap(elf.addNodeAssumeCapacity(
            unit.debug_info_ni.unwrap().?.addFloatingChild(gpa, &elf.mf, .{
                .enable_next_moved = true,
            }) catch |err| switch (err) {
                else => |e| return e,
                error.MappedFileIo => return comp.link_diags.fail("failed to write output file: {t}", .{
                    elf.mf.io_err.?,
                }),
            },
            .{ .func_debug_info = fi },
        ));
    } else unreachable;
    return fi;
}
pub fn getFuncIfExists(dwarf: *Dwarf, nav: InternPool.Nav.Index) ?Func.Index {
    return @fromBackingInt(@intCast(dwarf.funcs.getIndex(nav) orelse return null));
}

fn getConstDeclInst(dwarf: *Dwarf, @"const": InternPool.Index) union(enum) {
    @"const": InternPool.Index,
    src_inst: InternPool.TrackedInst.Index,
} {
    const zcu = dwarf.lf.comp.zcu.?;
    const ip = &zcu.intern_pool;
    switch (ip.indexToKey(@"const")) {
        else => unreachable,
        .struct_type, .union_type, .enum_type, .opaque_type => |container, tag| switch (container) {
            .declared => |declared| switch (declared.captures.owned.len) {
                0 => return .{ .@"const" = @"const" },
                else => return .{ .src_inst = src_inst: switch (tag) {
                    else => unreachable,
                    .struct_type => {
                        const loaded_struct = ip.loadStructType(@"const");
                        break :src_inst ip.getNav(loaded_struct.name_nav.unwrap() orelse
                            break :src_inst loaded_struct.zir_index).srcInst(ip);
                    },
                    .union_type => {
                        const loaded_union = ip.loadUnionType(@"const");
                        break :src_inst ip.getNav(loaded_union.name_nav.unwrap() orelse
                            break :src_inst loaded_union.zir_index).srcInst(ip);
                    },
                    .enum_type => {
                        const loaded_enum = ip.loadEnumType(@"const");
                        break :src_inst ip.getNav(loaded_enum.name_nav.unwrap() orelse
                            break :src_inst loaded_enum.zir_index.unwrap().?).srcInst(ip);
                    },
                    .opaque_type => {
                        const loaded_opaque = ip.loadOpaqueType(@"const");
                        break :src_inst ip.getNav(loaded_opaque.name_nav.unwrap() orelse
                            break :src_inst loaded_opaque.zir_index).srcInst(ip);
                    },
                } },
            },
            .reified => |reified| {
                assert(reified.zir_index.resolve(ip).? != .main_struct_inst);
                return .{ .src_inst = reified.zir_index };
            },
            .generated_union_tag => unreachable,
        },
        .func => |func| switch (func.generic_owner) {
            else => |generic_owner| return .{ .@"const" = generic_owner },
            .none => {
                const owner_nav = ip.getNav(func.owner_nav);
                return switch (Type.fromInterned(
                    ip.namespacePtr(owner_nav.analysis.?.namespace).owner_type,
                ).getCaptures(zcu).len) {
                    0 => .{ .@"const" = @"const" },
                    else => .{ .src_inst = owner_nav.srcInst(ip) },
                };
            },
        },
    }
}
pub fn getConstDecl(
    dwarf: *Dwarf,
    pt: Zcu.PerThread,
    instance_const: InternPool.Index,
) link.Error!link.MappedFile.Node.Index {
    switch (dwarf.getConstDeclInst(instance_const)) {
        .@"const" => |@"const"| {
            const cpi = try dwarf.getConst(pt, .fromInterned(@"const"));
            return Const.get(cpi, dwarf).debug_info_ni.unwrap().?;
        },
        .src_inst => |src_inst| return dwarf.getDecl(pt, src_inst, .{ .@"const" = instance_const }),
    }
}
pub fn getGlobalDecl(
    dwarf: *Dwarf,
    pt: Zcu.PerThread,
    instance_global: InternPool.Nav.Index,
) link.Error!link.MappedFile.Node.Index {
    const ip = &pt.zcu.intern_pool;
    return dwarf.getDecl(pt, ip.getNav(instance_global).srcInst(ip), .{ .global = instance_global });
}
fn getDecl(
    dwarf: *Dwarf,
    pt: Zcu.PerThread,
    inst: InternPool.TrackedInst.Index,
    instance: Decl.Instance,
) link.Error!link.MappedFile.Node.Index {
    const comp = dwarf.lf.comp;
    const gpa = comp.gpa;
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const decl_gop = try dwarf.decls.getOrPut(gpa, inst);
    if (!decl_gop.found_existing) decl_gop.value_ptr.* = .{
        .debug_info_ni = .none,
    };
    const di: Decl.Index = @fromBackingInt(@intCast(decl_gop.index));
    if (decl_gop.value_ptr.debug_info_ni.unwrap()) |debug_info_ni| return debug_info_ni;
    dwarf.pending_decl = .{ .di = di, .instance = instance };
    const debug_info_ni = if (dwarf.lf.cast(.elf2)) |elf| debug_info_ni: {
        try elf.nodes.ensureUnusedCapacity(gpa, 1);
        try elf.dwarf_decls.putNoClobber(gpa, di, .{
            .debug_info_first_target_reloc = .none,
            .debug_info_first_node_reloc = .none,
        });
        const unit = dwarf.getUnit(zcu.fileByIndex(di.srcInst(dwarf).resolveFile(ip)).mod.?).get(dwarf);
        const debug_info_ni = elf.addNodeAssumeCapacity(
            unit.debug_info_ni.unwrap().?.addFloatingChild(gpa, &elf.mf, .{
                .enable_next_moved = true,
            }) catch |err| switch (err) {
                else => |e| return e,
                error.MappedFileIo => return comp.link_diags.fail("failed to write output file: {t}", .{
                    elf.mf.io_err.?,
                }),
            },
            .{ .decl_debug_info = di },
        );
        break :debug_info_ni debug_info_ni;
    } else unreachable;
    decl_gop.value_ptr.debug_info_ni = .wrap(debug_info_ni);
    return debug_info_ni;
}
pub fn getDeclIfExists(dwarf: *Dwarf, inst: InternPool.TrackedInst.Index) ?Decl.Index {
    return @fromBackingInt(@intCast(dwarf.decls.getIndex(inst) orelse return null));
}

pub fn unitLengthSize(dwarf: *Dwarf) usize {
    return switch (dwarf.format) {
        .@"32" => 4,
        .@"64" => 4 + 8,
    };
}
fn genUnitLength(dwarf: *Dwarf, w: *std.Io.Writer) std.Io.Writer.Error!void {
    switch (dwarf.format) {
        .@"32" => try w.writeInt(u32, undefined, dwarf.endian),
        .@"64" => {
            try w.writeInt(u32, std.math.maxInt(u32), dwarf.endian);
            try w.writeInt(u64, undefined, dwarf.endian);
        },
    }
}
pub fn updateUnitLength(dwarf: *Dwarf, header: []u8, unit_length: u64) void {
    switch (dwarf.format) {
        .@"32" => std.mem.writeInt(u32, header[0..4], @intCast(unit_length - 4), dwarf.endian),
        .@"64" => std.mem.writeInt(u64, header[4..12], unit_length - 12, dwarf.endian),
    }
}

pub fn genUnitPadding(dwarf: *Dwarf, w: *std.Io.Writer) std.Io.Writer.Error!void {
    try dwarf.genUnitLength(w);
    try w.writeInt(u16, 0, dwarf.endian);
}

pub fn genDebugAddrHeader(dwarf: *Dwarf, dah_w: *std.Io.Writer) std.Io.Writer.Error!void {
    try dwarf.genUnitLength(dah_w);
    try dah_w.writeInt(u16, 5, dwarf.endian);
    try dah_w.writeAll(&.{ @backingInt(dwarf.address_size), 0 });
    assert(dah_w.end == Addr.tableOffset(dwarf));
}

pub fn genPendingDebugAddr(dwarf: *Dwarf, da_nw: *link.MappedFile.Node.Writer) link.Error!void {
    da_nw.interface.end = dwarf.debug_addr.size(dwarf);
    for (dwarf.debug_addr.map.keys()[dwarf.debug_addr.pending_index..]) |si| {
        dwarf.addrSym(da_nw, si, 0) catch |err| switch (err) {
            else => |e| return e,
            error.WriteFailed => return dwarf.reportWriteError(da_nw),
        };
        dwarf.debug_addr.pending_index += 1;
    }
}

pub const EhFrameHdr = extern struct {
    version: u8,
    eh_frame_ptr_enc: std.dwarf.EH.PE,
    fde_count_enc: std.dwarf.EH.PE,
    table_enc: std.dwarf.EH.PE,
    eh_frame_ptr: u32,
};
pub fn genEhFrameHdr(
    dwarf: *Dwarf,
    eh_frame_hdr_ai: link.File.AtomId,
    eh_frame_hdr: *EhFrameHdr,
    eh_frame_si: link.File.SymbolId,
) link.Error!void {
    eh_frame_hdr.* = .{
        .version = 1,
        .eh_frame_ptr_enc = .{ .type = .sdata4, .rel = .pcrel },
        .fde_count_enc = .omit,
        .table_enc = .omit,
        .eh_frame_ptr = undefined,
    };
    if (dwarf.lf.cast(.elf2)) |elf| try elf.addReloc(
        eh_frame_hdr_ai,
        @offsetOf(EhFrameHdr, "eh_frame_ptr"),
        eh_frame_si,
        0,
        .rel32(elf),
    ) else unreachable;
}

pub fn genDebugFrameCie(
    dwarf: *Dwarf,
    df_w: *std.Io.Writer,
    /// `null` means to generate an architecture-agnostic padding cie
    arch: ?std.Target.Cpu.Arch,
    format: Frame.Format,
) std.Io.Writer.Error!void {
    try dwarf.genUnitLength(df_w);
    switch (format) {
        .eh_frame => try df_w.writeInt(u32, 0, dwarf.endian),
        .debug_frame => switch (dwarf.format) {
            .@"32" => try df_w.writeInt(u32, std.math.maxInt(u32), dwarf.endian),
            .@"64" => try df_w.writeInt(u64, std.math.maxInt(u64), dwarf.endian),
        },
    }
    try df_w.writeByte(if (arch) |_| switch (format) {
        .eh_frame => 1,
        .debug_frame => 4,
    } else 0);
    switch (arch orelse return) {
        else => unreachable,
        .x86_64 => {
            dev.checkAny(&.{ .llvm_backend, .x86_64_backend });
            const Register = @import("../codegen/x86_64/bits.zig").Register;
            switch (format) {
                .eh_frame => try df_w.writeAll("zR\x00"),
                .debug_frame => try df_w.writeAll("\x00" ++ .{ @backingInt(dwarf.address_size), 0 }),
            }
            try df_w.writeUleb128(dwarf.frame.header.code_alignment_factor);
            try df_w.writeSleb128(dwarf.frame.header.data_alignment_factor);
            switch (format) {
                .eh_frame => try df_w.writeByte(@intCast(dwarf.frame.header.return_address_register)),
                .debug_frame => try df_w.writeUleb128(dwarf.frame.header.return_address_register),
            }
            switch (format) {
                .eh_frame => {
                    try df_w.writeUleb128(1);
                    try df_w.writeByte(@bitCast(@as(DW.EH.PE, .{ .type = .sdata4, .rel = .pcrel })));
                },
                .debug_frame => {},
            }
            try df_w.writeByte(DW.CFA.def_cfa_sf);
            try df_w.writeUleb128(Register.rsp.dwarfNum());
            try df_w.writeSleb128(-1);
            try df_w.writeByte(@as(u8, DW.CFA.offset) + Register.rip.dwarfNum());
            try df_w.writeUleb128(1);
        },
    }
    @memset(df_w.unusedCapacitySlice(), DW.CFA.nop);
}

pub fn updateEhFrameFde(dwarf: *Dwarf, fde: []u8, fde_offset: u64) void {
    const cie_pointer_offset = dwarf.unitLengthSize();
    std.mem.writeInt(
        u32,
        fde[cie_pointer_offset..][0..4],
        @intCast(fde_offset + cie_pointer_offset),
        dwarf.endian,
    );
}

pub fn genDebugInfoHeader(
    dwarf: *Dwarf,
    zcu: *Zcu,
    mod: *Module,
    unit: *Unit,
    dih_nw: *link.MappedFile.Node.Writer,
) link.EmitError!void {
    const comp = zcu.comp;
    const dih_w = &dih_nw.interface;
    if (!unit.alive) return dwarf.genUnitPadding(dih_w);
    try dwarf.genUnitLength(dih_w);
    try dih_w.writeInt(u16, 5, dwarf.endian);
    try dih_w.writeAll(&.{ DW.UT.compile, @backingInt(dwarf.address_size) });
    try dwarf.secOffset(dih_nw, dwarf.debug_abbrev.ni.unwrap().?, 0);
    const compile_unit_offset = dih_w.end;
    try dwarf.abbrevCode(dih_nw, .compile_unit);
    try dih_w.writeByte(DW.LANG.Zig);
    try dwarf.secOffset(
        dih_nw,
        dwarf.getUnit(zcu.root_mod).get(dwarf).debug_info_header_ni.unwrap().?,
        compile_unit_offset,
    );
    try dwarf.secOffset(dih_nw, unit.debug_line_header_ni.unwrap().?, 0);
    try dwarf.secOffset(dih_nw, dwarf.debug_addr.ni.unwrap().?, Addr.tableOffset(dwarf));
    try dwarf.secOffset(dih_nw, unit.debug_rnglists_ni.unwrap().?, Rnglists.tableOffset(dwarf));
    try dwarf.secOffset(dih_nw, dwarf.debug_str_offsets.ni.unwrap().?, StrOffsets.tableOffset(dwarf));
    try dwarf.strx1(dih_nw, "zig " ++ @import("build_options").version);
    const root_dir_path = try mod.root.toAbsolute(&comp.dirs, comp.gpa);
    defer comp.gpa.free(root_dir_path);
    try dwarf.strp(&dwarf.debug_line_str, dih_nw, root_dir_path);
    try dwarf.strp(&dwarf.debug_line_str, dih_nw, mod.root_src_path);
    try dih_w.writeUleb128(0);
    const module_offset = dih_w.end;
    try dwarf.abbrevCode(dih_nw, .module);
    try dwarf.strx(dih_nw, mod.fully_qualified_name);
    try dih_w.writeUleb128(0);
    try dwarf.genModuleDependency(
        dih_nw,
        "builtin",
        zcu.builtin_modules.get(mod.getBuiltinOptions(comp.config).hash()).?,
        module_offset,
    );
    try dwarf.genModuleDependency(dih_nw, "root", zcu.root_mod, module_offset);
    try dwarf.genModuleDependency(dih_nw, "std", zcu.std_mod, module_offset);
    for (mod.deps.keys(), mod.deps.values()) |name, dep|
        try dwarf.genModuleDependency(dih_nw, name, dep, module_offset);
    for ([2]AbbrevCode{ .pad_1, .pad_n }) |pad| _ = try dwarf.refAbbrevCode(dih_nw.mf, pad);
    try dwarf.genDebugInfoPadding(dih_w, dih_w.unusedCapacityLen());
}

fn genModuleDependency(
    dwarf: *Dwarf,
    di_nw: *link.MappedFile.Node.Writer,
    name: []const u8,
    dep: *Module,
    module_offset: usize,
) link.EmitError!void {
    const dep_unit = dwarf.getUnit(dep).get(dwarf);
    if (!dep_unit.alive) return;
    try dwarf.abbrevCode(di_nw, .module_dependency);
    try dwarf.strx(di_nw, name);
    try dwarf.secOffset(di_nw, dep_unit.debug_info_header_ni.unwrap().?, module_offset);
}

pub fn genDebugInfoPadding(dwarf: *Dwarf, di_w: *std.Io.Writer, size: u64) std.Io.Writer.Error!void {
    switch (size) {
        0 => {},
        1 => try di_w.writeUleb128(dwarf.refAbbrevCodeIfExists(.pad_1).?),
        else => {
            const abbrev_code_offset = di_w.end;
            try di_w.writeUleb128(dwarf.refAbbrevCodeIfExists(.pad_n).?);
            const abbrev_code_size = di_w.end - abbrev_code_offset;
            var block_len_size: u5 = 1;
            while (true) switch (std.math.order(
                size - abbrev_code_size - block_len_size,
                @as(u64, 1) << 7 * block_len_size,
            )) {
                .lt => break try di_w.writeUleb128(size - abbrev_code_size - block_len_size),
                .eq => {
                    // no length will ever work, so undercount and futz with
                    // the leb encoding to make up the missing byte
                    block_len_size += 1;
                    std.leb.writeUnsignedExtended(
                        try di_w.writableSlice(block_len_size),
                        size - abbrev_code_size - block_len_size,
                    );
                    break;
                },
                .gt => block_len_size += 1,
            };
        },
    }
}

pub fn genDebugLineHeader(
    dwarf: *Dwarf,
    unit: *Unit,
    dlh_nw: *link.MappedFile.Node.Writer,
    zcu: *Zcu,
) link.EmitError!void {
    const comp = zcu.comp;
    const dlh_w = &dlh_nw.interface;
    try dwarf.genUnitLength(dlh_w);
    try dlh_w.writeInt(u16, 5, dwarf.endian);
    try dlh_w.writeAll(&.{ @backingInt(dwarf.address_size), 0 });
    const header_length_offset = dlh_w.end;
    switch (dwarf.format) {
        .@"32" => try dlh_w.writeInt(u32, undefined, dwarf.endian),
        .@"64" => try dlh_w.writeInt(u64, undefined, dwarf.endian),
    }
    const header_start = dlh_w.end;
    const StandardOpcode = DeclValEnum(DW.LNS);
    try dlh_w.writeAll(&.{
        dwarf.debug_line.header.minimum_instruction_length,
        dwarf.debug_line.header.maximum_operations_per_instruction,
        @intFromBool(dwarf.debug_line.header.default_is_stmt),
        @bitCast(dwarf.debug_line.header.line_base),
        dwarf.debug_line.header.line_range,
        dwarf.debug_line.header.opcode_base,
    });
    try dlh_w.writeAll(std.enums.EnumArray(StandardOpcode, u8).init(.{
        .extended_op = undefined,
        .copy = 0,
        .advance_pc = 1,
        .advance_line = 1,
        .set_file = 1,
        .set_column = 1,
        .negate_stmt = 0,
        .set_basic_block = 0,
        .const_add_pc = 0,
        .fixed_advance_pc = 1,
        .set_prologue_end = 0,
        .set_epilogue_begin = 0,
        .set_isa = 1,
    }).values[1..dwarf.debug_line.header.opcode_base]);
    try dlh_w.writeByte(1);
    try dlh_w.writeUleb128(DW.LNCT.path);
    try dlh_w.writeUleb128(DW.FORM.line_strp);
    const dir_count = unit.dirs.count();
    const directory_index_form: DeclValEnum(DW.FORM) = if (dir_count <= 1 << 8)
        .data1
    else if (dir_count <= 1 << 16)
        .data2
    else
        .udata;
    try dlh_w.writeUleb128(dir_count);
    for (unit.dirs.keys()) |ui| {
        const root_dir_path = try ui.mod(dwarf).root.toAbsolute(&zcu.comp.dirs, comp.gpa);
        defer comp.gpa.free(root_dir_path);
        try dwarf.strp(&dwarf.debug_line_str, dlh_nw, root_dir_path);
    }
    try dlh_w.writeByte(5);
    try dlh_w.writeUleb128(DW.LNCT.path);
    try dlh_w.writeUleb128(DW.FORM.line_strp);
    try dlh_w.writeUleb128(DW.LNCT.directory_index);
    try dlh_w.writeUleb128(@backingInt(directory_index_form));
    try dlh_w.writeUleb128(DW.LNCT.timestamp);
    try dlh_w.writeUleb128(DW.FORM.data8);
    try dlh_w.writeUleb128(DW.LNCT.size);
    try dlh_w.writeUleb128(DW.FORM.data8);
    try dlh_w.writeUleb128(DW.LNCT.LLVM_source);
    try dlh_w.writeUleb128(DW.FORM.line_strp);
    try dlh_w.writeUleb128(unit.files.count());
    for (unit.files.keys()) |zfi| {
        const zf = zcu.fileByIndex(zfi);
        try dwarf.strp(&dwarf.debug_line_str, dlh_nw, zf.sub_file_path);
        const di =
            if (zcu.alive_files.contains(zfi)) unit.dirs.getIndex(dwarf.getUnit(zf.mod.?)).? else 0;
        switch (directory_index_form) {
            else => unreachable,
            .data1 => try dlh_w.writeByte(@intCast(di)),
            .data2 => try dlh_w.writeInt(u16, @intCast(di), dwarf.endian),
            .udata => try dlh_w.writeUleb128(di),
        }
        try dlh_w.writeInt(i64, @truncate(zf.stat.mtime.nanoseconds), dwarf.endian);
        try dlh_w.writeInt(u64, zf.stat.size, dwarf.endian);
        try dwarf.strp(&dwarf.debug_line_str, dlh_nw, if (zf.is_builtin) zf.source.? else "");
    }
    switch (dwarf.format) {
        .@"32" => std.mem.writeInt(
            u32,
            dlh_w.buffer[header_length_offset..][0..4],
            @intCast(dlh_w.end - header_start),
            dwarf.endian,
        ),
        .@"64" => std.mem.writeInt(
            u64,
            dlh_w.buffer[header_length_offset..][0..8],
            dlh_w.end - header_start,
            dwarf.endian,
        ),
    }
    try genDebugLinePadding(dlh_w, dlh_w.unusedCapacityLen());
}

pub fn genDebugLinePadding(dl_w: *std.Io.Writer, size: u64) std.Io.Writer.Error!void {
    switch (size) {
        0 => {},
        1 => try dl_w.writeByte(DW.LNS.const_add_pc),
        2 => try dl_w.writeAll(&.{ DW.LNS.negate_stmt, DW.LNS.negate_stmt }),
        else => {
            const extended_op_offset = dl_w.end;
            try dl_w.writeByte(DW.LNS.extended_op);
            const extended_op_size = dl_w.end - extended_op_offset;
            var op_len_size: u5 = 1;
            while (true) switch (std.math.order(
                size - extended_op_size - op_len_size,
                @as(u64, 1) << 7 * op_len_size,
            )) {
                .lt => break try dl_w.writeUleb128(size - extended_op_size - op_len_size),
                .eq => {
                    // no length will ever work, so undercount and futz with
                    // the leb encoding to make up the missing byte
                    op_len_size += 1;
                    std.leb.writeUnsignedExtended(
                        try dl_w.writableSlice(op_len_size),
                        size - extended_op_size - op_len_size,
                    );
                    break;
                },
                .gt => op_len_size += 1,
            };
            try dl_w.writeByte(DW.LNE.padding);
        },
    }
}

pub fn genDebugRnglistsHeader(
    dwarf: *Dwarf,
    unit: *Unit,
    drh_nw: *link.MappedFile.Node.Writer,
) std.Io.Writer.Error!void {
    const drh_w = &drh_nw.interface;
    try dwarf.genUnitLength(drh_w);
    try drh_w.writeInt(u16, 5, dwarf.endian);
    try drh_w.writeAll(&.{ @backingInt(dwarf.address_size), 0 });
    try drh_w.writeInt(u32, 1, dwarf.endian);
    assert(drh_w.end == Rnglists.tableOffset(dwarf));
    switch (dwarf.format) {
        .@"32" => try drh_w.writeInt(u32, 4, dwarf.endian),
        .@"64" => try drh_w.writeInt(u64, 8, dwarf.endian),
    }
    unit.debug_rnglists_end = drh_w.end;
    try drh_w.writeByte(DW.RLE.end_of_list);
}

pub fn genDebugRnglistsRange(
    dwarf: *Dwarf,
    unit: *Unit,
    dr_nw: *link.MappedFile.Node.Writer,
    func_si: link.File.SymbolId,
    func_length: u64,
) link.EmitError!void {
    const dr_w = &dr_nw.interface;
    dr_w.end = unit.debug_rnglists_end;
    try dr_w.writeByte(DW.RLE.startx_length);
    try dwarf.addrxSym(dr_w, func_si);
    try dr_w.writeUleb128(func_length);
    unit.debug_rnglists_end = dr_w.end;
    try dr_w.writeByte(DW.RLE.end_of_list);
}

pub fn genDebugStrOffsetsHeader(dwarf: *Dwarf, dsoh_w: *std.Io.Writer) std.Io.Writer.Error!void {
    try dwarf.genUnitLength(dsoh_w);
    try dsoh_w.writeInt(u16, 5, dwarf.endian);
    try dsoh_w.writeInt(u16, 0, dwarf.endian);
    assert(dsoh_w.end == StrOffsets.tableOffset(dwarf));
}

pub fn genPendingDebugStrOffsets(dwarf: *Dwarf, dso_nw: *link.MappedFile.Node.Writer) link.Error!void {
    const debug_str_ni = dwarf.debug_str.ni.unwrap().?;
    dso_nw.interface.end = dwarf.debug_str_offsets.size(dwarf);
    for (dwarf.debug_str_offsets.map.keys()[dwarf.debug_str_offsets.pending_index..]) |offset| {
        dwarf.secOffset(dso_nw, debug_str_ni, offset) catch |err| switch (err) {
            else => |e| return e,
            error.WriteFailed => return dwarf.reportWriteError(dso_nw),
        };
        dwarf.debug_str_offsets.pending_index += 1;
    }
}

pub fn updateExtern(
    dwarf: *Dwarf,
    pt: Zcu.PerThread,
    di_nw: *link.MappedFile.Node.Writer,
    arch: std.Target.Cpu.Arch,
    si: link.File.SymbolId,
    global: InternPool.Nav.Index,
) link.Error!void {
    dwarf.updateExternInner(pt, di_nw, arch, si, global) catch |err| switch (err) {
        else => |e| return e,
        error.WriteFailed => return dwarf.reportWriteError(di_nw),
    };
}
fn updateExternInner(
    dwarf: *Dwarf,
    pt: Zcu.PerThread,
    di_nw: *link.MappedFile.Node.Writer,
    arch: std.Target.Cpu.Arch,
    si: link.File.SymbolId,
    global: InternPool.Nav.Index,
) link.EmitError!void {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const nav = ip.getNav(global);
    log.debug("updateExtern({f})", .{nav.fqn.fmt(ip)});
    const nav_align, const nav_const, const nav_threadlocal, const nav_extern = nav_resolved: {
        const nav_resolved = nav.resolved.?;
        break :nav_resolved .{
            nav_resolved.@"align",
            nav_resolved.@"const",
            nav_resolved.@"threadlocal",
            ip.indexToKey(nav_resolved.value).@"extern",
        };
    };
    const inst_info = nav.srcInst(ip).resolveFull(ip).?;
    const decl = switch (nav_extern.source) {
        .builtin => undefined,
        .syntax => zcu.fileByIndex(inst_info.file).zir.?.getDeclaration(inst_info.inst),
    };
    const maybe_func_type = switch (ip.indexToKey(nav_extern.ty)) {
        .func_type => |func_type| func_type,
        else => null,
    };
    const is_empty = if (maybe_func_type) |func_type| func_type.param_types.len == 0 and
        !func_type.is_var_args else undefined;
    const di_w = &di_nw.interface;
    switch (nav_extern.source) {
        .builtin => {
            try dwarf.abbrevCode(di_nw, if (maybe_func_type) |_|
                if (is_empty) .builtin_extern_empty_func else .builtin_extern_func
            else
                .builtin_extern_var);
            try dwarf.refType(pt, di_nw, .fromInterned(zcu.fileRootType(inst_info.file)));
        },
        .syntax => if (maybe_func_type) |_| {
            try dwarf.abbrevCode(
                di_nw,
                if (is_empty) .decl_extern_empty_func else .decl_extern_func,
            );
            try dwarf.refType(pt, di_nw, .fromInterned(zcu.fileRootType(inst_info.file)));
            try di_w.writeInt(u32, decl.src_line + 1, dwarf.endian);
            try di_w.writeUleb128(decl.src_column + 1);
            try di_w.writeByte(if (decl.is_pub) DW.ACCESS.public else DW.ACCESS.private);
            try dwarf.strx(di_nw, nav.name.toSlice(ip));
        } else {
            try dwarf.abbrevCode(di_nw, .decl_var);
            try dwarf.refType(pt, di_nw, .fromInterned(zcu.fileRootType(inst_info.file)));
            try di_w.writeInt(u32, decl.src_line + 1, dwarf.endian);
            try di_w.writeUleb128(decl.src_column + 1);
            try di_w.writeByte(if (decl.is_pub) DW.ACCESS.public else DW.ACCESS.private);
            try dwarf.strx(di_nw, nav.name.toSlice(ip));
        },
    }
    try dwarf.strx(di_nw, nav_extern.name.toSlice(ip));
    if (maybe_func_type) |func_type| {
        try dwarf.refType(pt, di_nw, .fromInterned(func_type.return_type));
        try dwarf.addrSym(di_nw, si, 0);
        try di_w.writeByte(@intFromBool(Type.fromInterned(func_type.return_type).isNoReturn(zcu)));
        for (func_type.param_types.get(ip)) |param_type| {
            try dwarf.abbrevCode(di_nw, .extern_param);
            try dwarf.refType(pt, di_nw, .fromInterned(param_type));
        }
        if (func_type.is_var_args) try dwarf.abbrevCode(di_nw, .is_var_args);
        if (!is_empty) try di_w.writeUleb128(@backingInt(AbbrevCode.null));
    } else {
        const addr: Loc = .{ .addr_sym = .{ .si = si } };
        const loc: Loc = if (nav_threadlocal) switch (arch) {
            .x86_64 => .{ .form_tls_address = &addr },
            else => unreachable,
        } else addr;
        const type_offset = di_w.end;
        if (nav_const)
            try dwarf.secOffsetPlaceholder(di_w)
        else
            try dwarf.refType(pt, di_nw, .fromInterned(nav_extern.ty));
        try dwarf.exprLoc(di_nw, loc);
        try di_w.writeUleb128(nav_align.toByteUnits() orelse
            Type.fromInterned(nav_extern.ty).abiAlignment(zcu).toByteUnits().?);
        switch (nav_extern.source) {
            .builtin => {},
            .syntax => try di_w.writeByte(@intFromBool(decl.linkage != .normal)),
        }
        if (nav_const) {
            try dwarf.secOffsetFinish(di_nw, type_offset, di_nw.ni, di_w.end);
            try dwarf.abbrevCode(di_nw, .is_const);
            try dwarf.refType(pt, di_nw, .fromInterned(nav_extern.ty));
        }
    }
    try dwarf.genDebugInfoPadding(di_w, di_w.unusedCapacityLen());
}

pub fn updateGlobal(
    dwarf: *Dwarf,
    pt: Zcu.PerThread,
    di_nw: *link.MappedFile.Node.Writer,
    arch: std.Target.Cpu.Arch,
    si: link.File.SymbolId,
    global: InternPool.Nav.Index,
) link.Error!void {
    const ip = &pt.zcu.intern_pool;
    log.debug("updateGlobal({f})", .{ip.getNav(global).fqn.fmt(ip)});
    dwarf.updateGlobalInner(pt, di_nw, arch, si, global) catch |err| switch (err) {
        else => |e| return e,
        error.WriteFailed => return dwarf.reportWriteError(di_nw),
    };
}
fn updateGlobalInner(
    dwarf: *Dwarf,
    pt: Zcu.PerThread,
    di_nw: *link.MappedFile.Node.Writer,
    arch: std.Target.Cpu.Arch,
    si: link.File.SymbolId,
    global: InternPool.Nav.Index,
) link.EmitError!void {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const nav = ip.getNav(global);
    const nav_ty: Type, const nav_align, const nav_const, const nav_threadlocal = nav_resolved: {
        const nav_resolved = nav.resolved.?;
        break :nav_resolved .{
            .fromInterned(nav_resolved.type),
            nav_resolved.@"align",
            nav_resolved.@"const",
            nav_resolved.@"threadlocal",
        };
    };
    const inst_info = nav.srcInst(ip).resolveFull(ip).?;
    const decl = zcu.fileByIndex(inst_info.file).zir.?.getDeclaration(inst_info.inst);
    switch (decl.kind) {
        .unnamed_test, .@"test", .decltest, .@"comptime" => unreachable,
        .@"const" => assert(nav_const),
        .@"var" => assert(!nav_const),
    }
    const parent_ty: Type = .fromInterned(ip.namespacePtr(nav.analysis.?.namespace).owner_type);
    const di_w = &di_nw.interface;
    if (parent_ty.getCaptures(zcu).len > 0) {
        try dwarf.abbrevCode(di_nw, .decl_instance_var);
        try dwarf.refType(pt, di_nw, parent_ty);
        try dwarf.secOffset(di_nw, try dwarf.getGlobalDecl(pt, global), 0);
    } else {
        const parent_ni = try dwarf.getConstDecl(pt, parent_ty.toIntern());
        try dwarf.abbrevCode(di_nw, .decl_var);
        try dwarf.secOffset(di_nw, parent_ni, 0);
        try di_w.writeInt(u32, decl.src_line + 1, dwarf.endian);
        try di_w.writeUleb128(decl.src_column + 1);
        try di_w.writeByte(if (decl.is_pub) DW.ACCESS.public else DW.ACCESS.private);
        try dwarf.strx(di_nw, nav.name.toSlice(ip));
    }
    try dwarf.strx(di_nw, switch (decl.linkage) {
        .normal => nav.fqn,
        .@"extern" => unreachable,
        .@"export" => nav.name,
    }.toSlice(ip));
    const addr: Loc = .{ .addr_sym = .{ .si = si } };
    const loc: Loc = if (nav_threadlocal) switch (arch) {
        .x86_64 => .{ .form_tls_address = &addr },
        else => unreachable,
    } else addr;
    const type_offset = di_w.end;
    if (nav_const) try dwarf.secOffsetPlaceholder(di_w) else try dwarf.refType(pt, di_nw, nav_ty);
    try dwarf.exprLoc(di_nw, loc);
    try di_w.writeUleb128(nav_align.toByteUnits() orelse nav_ty.abiAlignment(zcu).toByteUnits().?);
    try di_w.writeByte(@intFromBool(decl.linkage != .normal));
    if (nav_const) {
        try dwarf.secOffsetFinish(di_nw, type_offset, di_nw.ni, di_w.end);
        try dwarf.abbrevCode(di_nw, .is_const);
        try dwarf.refType(pt, di_nw, nav_ty);
    }
    try dwarf.genDebugInfoPadding(di_w, di_w.unusedCapacityLen());
}

pub fn updateComptimeGlobal(
    dwarf: *Dwarf,
    pt: Zcu.PerThread,
    global: InternPool.Nav.Index,
) link.Error!void {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const nav = ip.getNav(global);
    log.debug("updateComptimeGlobal({f})", .{nav.fqn.fmt(ip)});
    const inst_info = nav.srcInst(ip).resolveFull(ip).?;
    const nav_val: Value = .fromInterned(nav.resolved.?.value);
    const decl = zcu.fileByIndex(inst_info.file).zir.?.getDeclaration(inst_info.inst);
    switch (decl.kind) {
        .unnamed_test, .@"test", .decltest => return,
        .@"comptime", .@"const", .@"var" => {},
    }
    switch (ip.indexToKey(nav_val.toIntern())) {
        .int_type,
        .ptr_type,
        .array_type,
        .vector_type,
        .opt_type,
        .error_union_type,
        .anyframe_type,
        .simple_type,
        .tuple_type,
        .func_type,
        .error_set_type,
        .inferred_error_set_type,
        .spirv_type,
        .undef,
        .simple_value,
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
        => try dwarf.genComptimeGlobal(pt, global, &decl),
        .struct_type => {
            const loaded_struct = ip.loadStructType(nav_val.toIntern());
            if (loaded_struct.name_nav == global.toOptional()) {
                _ = try dwarf.const_pool.get(pt, dwarf.constPoolUser(), nav_val.toIntern());
            } else try dwarf.genComptimeGlobal(pt, global, &decl);
        },
        .enum_type => {
            const loaded_enum = ip.loadEnumType(nav_val.toIntern());
            if (loaded_enum.name_nav == global.toOptional()) {
                _ = try dwarf.const_pool.get(pt, dwarf.constPoolUser(), nav_val.toIntern());
            } else try dwarf.genComptimeGlobal(pt, global, &decl);
        },
        .union_type => {
            const loaded_union = ip.loadUnionType(nav_val.toIntern());
            if (loaded_union.name_nav == global.toOptional()) {
                _ = try dwarf.const_pool.get(pt, dwarf.constPoolUser(), nav_val.toIntern());
            } else try dwarf.genComptimeGlobal(pt, global, &decl);
        },
        .opaque_type => {
            const loaded_opaque = ip.loadOpaqueType(nav_val.toIntern());
            if (loaded_opaque.name_nav == global.toOptional()) {
                _ = try dwarf.const_pool.get(pt, dwarf.constPoolUser(), nav_val.toIntern());
            } else try dwarf.genComptimeGlobal(pt, global, &decl);
        },
        .@"extern" => unreachable,
        .func => |func| if (func.owner_nav == global) {
            _ = try dwarf.const_pool.get(pt, dwarf.constPoolUser(), nav_val.toIntern());
        } else try dwarf.genComptimeGlobal(pt, global, &decl),
        .memoized_call => unreachable, // not a value
    }
}
fn genComptimeGlobal(
    dwarf: *Dwarf,
    pt: Zcu.PerThread,
    global: InternPool.Nav.Index,
    decl: *const std.zig.Zir.Inst.Declaration.Unwrapped,
) link.Error!void {
    const gpa = pt.zcu.gpa;
    const gi = try dwarf.getGlobal(global);
    const debug_info_ni = gi.get(dwarf).debug_info_ni.unwrap().?;
    var di_nw: link.MappedFile.Node.Writer = undefined;
    if (dwarf.lf.cast(.elf2)) |elf| {
        try debug_info_ni.moved(gpa, &elf.mf);
        debug_info_ni.writer(gpa, &elf.mf, &di_nw);
        elf.resetNodeRelocs(debug_info_ni);
    } else unreachable;
    defer di_nw.deinit();
    dwarf.genComptimeGlobalInner(pt, &di_nw, global, decl) catch |err| switch (err) {
        else => |e| return e,
        error.WriteFailed => return dwarf.reportWriteError(&di_nw),
    };
}
fn genComptimeGlobalInner(
    dwarf: *Dwarf,
    pt: Zcu.PerThread,
    di_nw: *link.MappedFile.Node.Writer,
    global: InternPool.Nav.Index,
    decl: *const std.zig.Zir.Inst.Declaration.Unwrapped,
) link.EmitError!void {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const nav = ip.getNav(global);
    const nav_ty: Type, const nav_align, const nav_const, const nav_val: Value = nav_resolved: {
        const nav_resolved = nav.resolved.?;
        break :nav_resolved .{
            .fromInterned(nav_resolved.type),
            nav_resolved.@"align",
            nav_resolved.@"const",
            .fromInterned(nav_resolved.value),
        };
    };
    const nav_class = nav_ty.classify(zcu);
    const parent_ty: Type = .fromInterned(ip.namespacePtr(nav.analysis.?.namespace).owner_type);
    const di_w = &di_nw.interface;
    if (parent_ty.getCaptures(zcu).len > 0) {
        try dwarf.abbrevCode(di_nw, switch (nav_ty.toIntern()) {
            .type_type => .decl_instance_type,
            else => switch (nav_class) {
                .no_possible_value, .one_possible_value => .decl_instance_const,
                .runtime => .decl_instance_const_fully_runtime,
                .partially_comptime => .decl_instance_const_partially_comptime,
                .fully_comptime => .decl_instance_const_fully_comptime,
            },
        });
        try dwarf.refType(pt, di_nw, parent_ty);
        try dwarf.secOffset(di_nw, try dwarf.getGlobalDecl(pt, global), 0);
    } else {
        const parent_ni = try dwarf.getConstDecl(pt, parent_ty.toIntern());
        try dwarf.abbrevCode(di_nw, switch (nav_ty.toIntern()) {
            .type_type => .decl_type,
            else => switch (nav_class) {
                .no_possible_value, .one_possible_value => .decl_const,
                .runtime => .decl_const_fully_runtime,
                .partially_comptime => .decl_const_partially_comptime,
                .fully_comptime => .decl_const_fully_comptime,
            },
        });
        try dwarf.secOffset(di_nw, parent_ni, 0);
        try di_w.writeInt(u32, decl.src_line + 1, dwarf.endian);
        try di_w.writeUleb128(decl.src_column + 1);
        try di_w.writeByte(if (decl.is_pub) DW.ACCESS.public else DW.ACCESS.private);
        try dwarf.strx(di_nw, nav.name.toSlice(ip));
    }
    switch (nav_ty.toIntern()) {
        .type_type => try dwarf.refConst(pt, di_nw, nav_val),
        else => {
            try dwarf.strx(di_nw, switch (decl.linkage) {
                .normal => nav.fqn,
                .@"extern", .@"export" => nav.name,
            }.toSlice(ip));
            const type_offset = di_w.end;
            if (nav_const)
                try dwarf.secOffsetPlaceholder(di_w)
            else
                try dwarf.refType(pt, di_nw, nav_ty);
            try di_w.writeUleb128(nav_align.toByteUnits() orelse
                nav_ty.abiAlignment(zcu).toByteUnits().?);
            try di_w.writeByte(@intFromBool(decl.linkage != .normal));
            if (nav_class.hasRuntimeBits()) try dwarf.blockConst(pt, di_nw, nav_val);
            if (nav_class.comptimeOnly()) try dwarf.refConst(pt, di_nw, nav_val);
            if (nav_const) {
                try dwarf.secOffsetFinish(di_nw, type_offset, di_nw.ni, di_w.end);
                try dwarf.abbrevCode(di_nw, .is_const);
                try dwarf.refType(pt, di_nw, nav_ty);
            }
        },
    }
    try dwarf.genDebugInfoPadding(di_w, di_w.unusedCapacityLen());
}

pub fn addConst(
    dwarf: *Dwarf,
    cpi: link.ConstPool.Index,
    val: InternPool.Index,
    addConstNode: *const fn (
        lf: *link.File,
        ui: Unit.Index,
        cpi: link.ConstPool.Index,
    ) link.Error!link.MappedFile.Node.Index,
) link.Error!void {
    const zcu = dwarf.lf.comp.zcu.?;
    const ip = &zcu.intern_pool;
    assert(@backingInt(cpi) == dwarf.consts.items.len);
    dwarf.consts.appendAssumeCapacity(.{
        .debug_info_ni = debug_info_ni: switch (ip.indexToKey(val)) {
            else => try addConstNode(dwarf.lf, dwarf.getUnit(zcu.root_mod), cpi),
            .func => |func| {
                const fi = try dwarf.getFunc(func.owner_nav);
                break :debug_info_ni fi.get(dwarf).debug_info_ni.unwrap().?;
            },
            .@"extern" => |@"extern"| {
                const gi = try dwarf.getGlobal(@"extern".owner_nav);
                break :debug_info_ni gi.get(dwarf).debug_info_ni.unwrap().?;
            },
            .struct_type, .union_type, .enum_type, .opaque_type => |_, tag| {
                if (switch (tag) {
                    else => unreachable,
                    .struct_type => ip.loadStructType(val).name_nav,
                    .union_type => ip.loadUnionType(val).name_nav,
                    .enum_type => ip.loadEnumType(val).name_nav,
                    .opaque_type => ip.loadOpaqueType(val).name_nav,
                }.unwrap()) |name_nav| {
                    const name_gi = try dwarf.getGlobal(name_nav);
                    break :debug_info_ni name_gi.get(dwarf).debug_info_ni.unwrap().?;
                }
                const mod = zcu.fileByIndex(
                    Type.fromInterned(val).typeDeclInstAllowGeneratedTag(zcu).?.resolveFile(ip),
                ).mod.?;
                assert(!mod.strip);
                break :debug_info_ni try addConstNode(dwarf.lf, dwarf.getUnit(mod), cpi);
            },
        }.toOptional(),
    });
}

pub fn updateConst(
    dwarf: *Dwarf,
    pt: Zcu.PerThread,
    di_nw: *link.MappedFile.Node.Writer,
    val: InternPool.Index,
) link.Error!void {
    switch (val) {
        .generic_poison_type => log.debug("updateConst(anytype)", .{}),
        else => log.debug("updateConst({f})", .{Value.fromInterned(val).fmtValue(pt)}),
    }
    dwarf.updateConstInner(pt, di_nw, val) catch |err| switch (err) {
        else => |e| return e,
        error.WriteFailed => return dwarf.reportWriteError(di_nw),
    };
}
fn updateConstInner(
    dwarf: *Dwarf,
    pt: Zcu.PerThread,
    di_nw: *link.MappedFile.Node.Writer,
    @"const": InternPool.Index,
) link.EmitError!void {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const di_w = &di_nw.interface;
    switch (ip.indexToKey(@"const")) {
        .int_type => |int_type| {
            const ty: Type = .fromInterned(@"const");
            try dwarf.abbrevCode(di_nw, .numeric_type);
            var name_buf: [std.fmt.count("i{d}", .{std.math.maxInt(u16)})]u8 = undefined;
            try dwarf.strx(di_nw, std.mem.print(&name_buf, "{f}", .{
                ty.fmt(pt),
            }) catch unreachable);
            try di_w.writeByte(switch (int_type.signedness) {
                .signed => DW.ATE.signed,
                .unsigned => DW.ATE.unsigned,
            });
            try di_w.writeUleb128(int_type.bits);
            try di_w.writeUleb128(ty.abiSize(zcu));
            try di_w.writeUleb128(ty.abiAlignment(zcu).toByteUnits().?);
        },
        .ptr_type => |ptr_type| switch (ptr_type.flags.size) {
            .one, .many, .c => {
                const name = try zcu.gpa.print("{f}", .{Type.fromInterned(@"const").fmt(pt)});
                defer zcu.gpa.free(name);
                try dwarf.abbrevCode(di_nw, switch (ptr_type.sentinel) {
                    .none => .ptr_type,
                    else => .ptr_sentinel_type,
                });
                try dwarf.strx(di_nw, name);
                switch (ptr_type.sentinel) {
                    .none => {},
                    else => |sentinel| try dwarf.blockConst(pt, di_nw, .fromInterned(sentinel)),
                }
                try di_w.writeByte(@backingInt(ptr_type.flags.address_space));
                if (ptr_type.flags.alignment.toByteUnits()) |a| {
                    const type_offset = di_w.end;
                    try dwarf.secOffsetPlaceholder(di_w);
                    try dwarf.secOffsetFinish(di_nw, type_offset, di_nw.ni, di_w.end);
                    try dwarf.abbrevCode(di_nw, .is_aligned);
                    try di_w.writeUleb128(a);
                }
                if (ptr_type.flags.is_const) {
                    const type_offset = di_w.end;
                    try dwarf.secOffsetPlaceholder(di_w);
                    try dwarf.secOffsetFinish(di_nw, type_offset, di_nw.ni, di_w.end);
                    try dwarf.abbrevCode(di_nw, .is_const);
                }
                if (ptr_type.flags.is_volatile) {
                    const type_offset = di_w.end;
                    try dwarf.secOffsetPlaceholder(di_w);
                    try dwarf.secOffsetFinish(di_nw, type_offset, di_nw.ni, di_w.end);
                    try dwarf.abbrevCode(di_nw, .is_volatile);
                }
                try dwarf.refType(pt, di_nw, .fromInterned(ptr_type.child));
            },
            .slice => {
                const ty: Type = .fromInterned(@"const");
                const name = try zcu.gpa.print("{f}", .{ty.fmt(pt)});
                defer zcu.gpa.free(name);
                try dwarf.abbrevCode(di_nw, .generated_struct_type);
                try dwarf.strx(di_nw, name);
                try di_w.writeUleb128(ty.abiSize(zcu));
                try di_w.writeUleb128(ty.abiAlignment(zcu).toByteUnits().?);
                try dwarf.abbrevCode(di_nw, .generated_field);
                try dwarf.strx(di_nw, "ptr");
                const ptr_field_ty = ty.slicePtrFieldType(zcu);
                try dwarf.refType(pt, di_nw, ptr_field_ty);
                try di_w.writeUleb128(0);
                try dwarf.abbrevCode(di_nw, .generated_field);
                try dwarf.strx(di_nw, "len");
                const len_field_ty: Type = .usize;
                try dwarf.refType(pt, di_nw, len_field_ty);
                try di_w.writeUleb128(len_field_ty.abiAlignment(zcu).forward(ptr_field_ty.abiSize(zcu)));
                try di_w.writeUleb128(@backingInt(AbbrevCode.null));
            },
        },
        .array_type => |array_type| {
            const name = try zcu.gpa.print("{f}", .{Type.fromInterned(@"const").fmt(pt)});
            defer zcu.gpa.free(name);
            try dwarf.abbrevCode(
                di_nw,
                if (array_type.sentinel == .none) .array_type else .array_sentinel_type,
            );
            try dwarf.strx(di_nw, name);
            if (array_type.sentinel != .none)
                try dwarf.blockConst(pt, di_nw, .fromInterned(array_type.sentinel));
            try dwarf.refType(pt, di_nw, .fromInterned(array_type.child));
            try dwarf.abbrevCode(di_nw, .array_len);
            try dwarf.refType(pt, di_nw, .usize);
            try di_w.writeUleb128(array_type.len);
            try di_w.writeUleb128(@backingInt(AbbrevCode.null));
        },
        .vector_type => |vector_type| {
            const name = try zcu.gpa.print("{f}", .{Type.fromInterned(@"const").fmt(pt)});
            defer zcu.gpa.free(name);
            try dwarf.abbrevCode(di_nw, .vector_type);
            try dwarf.strx(di_nw, name);
            try dwarf.refType(pt, di_nw, .fromInterned(vector_type.child));
            try dwarf.abbrevCode(di_nw, .array_len);
            try dwarf.refType(pt, di_nw, .usize);
            try di_w.writeUleb128(vector_type.len);
            try di_w.writeUleb128(@backingInt(AbbrevCode.null));
        },
        .opt_type => |opt_child_type_index| {
            const opt_ty: Type = .fromInterned(@"const");
            const opt_child_ty: Type = .fromInterned(opt_child_type_index);
            const opt_repr = optRepr(opt_child_ty, zcu);
            const name = try zcu.gpa.print("{f}", .{opt_ty.fmt(pt)});
            defer zcu.gpa.free(name);
            try dwarf.abbrevCode(di_nw, .generated_union_type);
            try dwarf.strx(di_nw, name);
            try di_w.writeUleb128(opt_ty.abiSize(zcu));
            try di_w.writeUleb128(opt_ty.abiAlignment(zcu).toByteUnits().?);
            switch (opt_repr) {
                .opv_null => {
                    try dwarf.abbrevCode(di_nw, .generated_field);
                    try dwarf.strx(di_nw, "null");
                    try dwarf.refType(pt, di_nw, .null);
                    try di_w.writeUleb128(0);
                },
                .unpacked, .error_set, .pointer => {
                    try dwarf.abbrevCode(di_nw, .tagged_union);
                    const discr_offset = di_w.end;
                    try dwarf.secOffsetPlaceholder(di_w);
                    {
                        try dwarf.secOffsetFinish(di_nw, discr_offset, di_nw.ni, di_w.end);
                        try dwarf.abbrevCode(di_nw, .generated_field);
                        try dwarf.strx(di_nw, "has_value");
                        switch (opt_repr) {
                            .opv_null => unreachable,
                            .unpacked => {
                                try dwarf.refType(pt, di_nw, .bool);
                                try di_w.writeUleb128(if (opt_child_ty.hasRuntimeBits(zcu))
                                    opt_child_ty.abiSize(zcu)
                                else
                                    0);
                            },
                            .error_set => {
                                try dwarf.refType(pt, di_nw, try pt.intType(
                                    .unsigned,
                                    zcu.errorSetBits(),
                                ));
                                try di_w.writeUleb128(0);
                            },
                            .pointer => {
                                try dwarf.refType(pt, di_nw, .usize);
                                try di_w.writeUleb128(0);
                            },
                        }

                        try dwarf.abbrevCode(di_nw, .tagged_union_field);
                        try di_w.writeUleb128(DW.FORM.data1);
                        try di_w.writeByte(0);
                        {
                            try dwarf.abbrevCode(di_nw, .generated_field);
                            try dwarf.strx(di_nw, "null");
                            try dwarf.refType(pt, di_nw, .null);
                            try di_w.writeUleb128(0);
                        }
                        try di_w.writeUleb128(@backingInt(AbbrevCode.null));

                        try dwarf.abbrevCode(di_nw, .tagged_union_default_field);
                        {
                            try dwarf.abbrevCode(di_nw, .generated_field);
                            try dwarf.strx(di_nw, "?");
                            try dwarf.refType(pt, di_nw, opt_child_ty);
                            try di_w.writeUleb128(0);
                        }
                        try di_w.writeUleb128(@backingInt(AbbrevCode.null));
                    }
                    try di_w.writeUleb128(@backingInt(AbbrevCode.null));
                },
            }
            try di_w.writeUleb128(@backingInt(AbbrevCode.null));
        },
        .anyframe_type => unreachable,
        .error_union_type => |error_union_type| {
            const eu_ty: Type = .fromInterned(@"const");
            const eu_error_set_ty: Type = .fromInterned(error_union_type.error_set_type);
            const eu_payload_ty: Type = .fromInterned(error_union_type.payload_type);
            const eu_error_set_offset, const eu_payload_offset = switch (error_union_type.payload_type) {
                .generic_poison_type => .{ 0, 0 },
                else => .{
                    codegen.errUnionErrorOffset(eu_payload_ty, zcu),
                    codegen.errUnionPayloadOffset(eu_payload_ty, zcu),
                },
            };
            const name = try zcu.gpa.print("{f}", .{eu_ty.fmt(pt)});
            defer zcu.gpa.free(name);

            try dwarf.abbrevCode(di_nw, .generated_union_type);
            try dwarf.strx(di_nw, name);
            if (error_union_type.error_set_type != .generic_poison_type and
                error_union_type.payload_type != .generic_poison_type)
            {
                try di_w.writeUleb128(eu_ty.abiSize(zcu));
                try di_w.writeUleb128(eu_ty.abiAlignment(zcu).toByteUnits().?);
            } else {
                try di_w.writeUleb128(0);
                try di_w.writeUleb128(1);
            }
            {
                try dwarf.abbrevCode(di_nw, .tagged_union);
                const discr_offset = di_w.end;
                try dwarf.secOffsetPlaceholder(di_w);
                {
                    try dwarf.secOffsetFinish(di_nw, discr_offset, di_nw.ni, di_w.end);
                    try dwarf.abbrevCode(di_nw, .generated_field);
                    try dwarf.strx(di_nw, "is_error");
                    try dwarf.refType(pt, di_nw, try pt.intType(.unsigned, zcu.errorSetBits()));
                    try di_w.writeUleb128(eu_error_set_offset);

                    try dwarf.abbrevCode(di_nw, .tagged_union_field);
                    try di_w.writeUleb128(DW.FORM.udata);
                    try di_w.writeUleb128(0);
                    {
                        try dwarf.abbrevCode(di_nw, .generated_field);
                        try dwarf.strx(di_nw, "value");
                        try dwarf.refType(pt, di_nw, eu_payload_ty);
                        try di_w.writeUleb128(eu_payload_offset);
                    }
                    try di_w.writeUleb128(@backingInt(AbbrevCode.null));

                    try dwarf.abbrevCode(di_nw, .tagged_union_default_field);
                    {
                        try dwarf.abbrevCode(di_nw, .generated_field);
                        try dwarf.strx(di_nw, "error");
                        try dwarf.refType(pt, di_nw, eu_error_set_ty);
                        try di_w.writeUleb128(eu_error_set_offset);
                    }
                    try di_w.writeUleb128(@backingInt(AbbrevCode.null));
                }
                try di_w.writeUleb128(@backingInt(AbbrevCode.null));
            }
            try di_w.writeUleb128(@backingInt(AbbrevCode.null));
        },
        .simple_type => |simple_type| switch (simple_type) {
            .f16,
            .f32,
            .f64,
            .f80,
            .f128,
            .usize,
            .isize,
            .c_char,
            .c_short,
            .c_ushort,
            .c_int,
            .c_uint,
            .c_long,
            .c_ulong,
            .c_longlong,
            .c_ulonglong,
            .c_longdouble,
            .bool,
            => {
                const ty: Type = .fromInterned(@"const");
                try dwarf.abbrevCode(di_nw, .numeric_type);
                try dwarf.strx(di_nw, @tagName(simple_type));
                try di_w.writeByte(if (@"const" == .bool_type)
                    DW.ATE.boolean
                else if (ty.isRuntimeFloat())
                    DW.ATE.float
                else if (ty.isSignedInt(zcu))
                    DW.ATE.signed
                else if (ty.isUnsignedInt(zcu))
                    DW.ATE.unsigned
                else
                    unreachable);
                try di_w.writeUleb128(ty.bitSize(zcu));
                try di_w.writeUleb128(ty.abiSize(zcu));
                try di_w.writeUleb128(ty.abiAlignment(zcu).toByteUnits().?);
            },
            .generic_poison => {
                try dwarf.abbrevCode(di_nw, .void_type);
                try dwarf.strx(di_nw, "anytype");
            },
            .anyopaque,
            .void,
            .type,
            .comptime_int,
            .comptime_float,
            .noreturn,
            .null,
            .undefined,
            .enum_literal,
            => {
                const ty: Type = .fromInterned(@"const");
                try dwarf.abbrevCode(di_nw, .void_type);
                var name_buf: ["@TypeOf(undefined)".len]u8 = undefined;
                try dwarf.strx(di_nw, std.mem.print(&name_buf, "{f}", .{
                    ty.fmt(pt),
                }) catch unreachable);
            },
            .anyerror => {
                const global_error_set_names = ip.global_error_set.getNamesFromMainThread();
                try dwarf.abbrevCode(di_nw, if (global_error_set_names.len > 0)
                    .generated_enum_type
                else
                    .generated_empty_enum_type);
                try dwarf.strx(di_nw, "anyerror");
                try dwarf.refType(pt, di_nw, try pt.intType(.unsigned, zcu.errorSetBits()));
                for (global_error_set_names, 1..) |err_name, err_value| {
                    try dwarf.abbrevCode(di_nw, .enum_field);
                    try di_w.writeUleb128(DW.FORM.udata);
                    try di_w.writeUleb128(err_value);
                    try dwarf.strx(di_nw, err_name.toSlice(ip));
                }
                if (global_error_set_names.len > 0) try di_w.writeUleb128(@backingInt(AbbrevCode.null));
            },
            .adhoc_inferred_error_set => unreachable,
        },
        .tuple_type => |tuple_type| {
            const ty: Type = .fromInterned(@"const");
            const name = try zcu.gpa.print("{f}", .{ty.fmt(pt)});
            defer zcu.gpa.free(name);
            if (tuple_type.types.len == 0) {
                try dwarf.abbrevCode(di_nw, .generated_empty_struct_type);
                try dwarf.strx(di_nw, name);
                try di_w.writeByte(@intFromBool(false));
            } else {
                try dwarf.abbrevCode(di_nw, .generated_struct_type);
                try dwarf.strx(di_nw, name);
                try di_w.writeUleb128(ty.abiSize(zcu));
                try di_w.writeUleb128(ty.abiAlignment(zcu).toByteUnits().?);
                var field_byte_offset: u64 = 0;
                for (0..tuple_type.types.len) |field_index| {
                    const comptime_value = tuple_type.values.get(ip)[field_index];
                    const field_ty: Type = .fromInterned(tuple_type.types.get(ip)[field_index]);
                    const comptime_value_class = switch (comptime_value) {
                        .none => .no_possible_value,
                        else => field_ty.classify(zcu),
                    };
                    try dwarf.abbrevCode(di_nw, switch (comptime_value) {
                        .none => .field,
                        else => switch (comptime_value_class) {
                            .no_possible_value, .one_possible_value => .field_comptime,
                            .runtime => .field_comptime_fully_runtime,
                            .partially_comptime => .field_comptime_partially_comptime,
                            .fully_comptime => .field_comptime_fully_comptime,
                        },
                    });
                    var field_name_buf: [std.fmt.count("{d}", .{std.math.maxInt(u32)})]u8 = undefined;
                    try dwarf.strx(di_nw, std.mem.print(&field_name_buf, "{d}", .{
                        field_index,
                    }) catch unreachable);
                    try dwarf.refType(pt, di_nw, field_ty);
                    if (comptime_value == .none) {
                        const field_align = field_ty.abiAlignment(zcu);
                        field_byte_offset = field_align.forward(field_byte_offset);
                        try di_w.writeUleb128(field_byte_offset);
                        try di_w.writeUleb128(field_ty.abiAlignment(zcu).toByteUnits().?);
                        field_byte_offset += field_ty.abiSize(zcu);
                    }
                    if (comptime_value_class.hasRuntimeBits())
                        try dwarf.blockConst(pt, di_nw, .fromInterned(comptime_value));
                    if (comptime_value_class.comptimeOnly())
                        try dwarf.refConst(pt, di_nw, .fromInterned(comptime_value));
                }
                try di_w.writeUleb128(@backingInt(AbbrevCode.null));
            }
        },
        .struct_type => {
            const loaded_struct = ip.loadStructType(@"const");
            const src_inst = loaded_struct.zir_index.resolveFull(ip).?;
            const zf = zcu.fileByIndex(src_inst.file);
            const is_empty = loaded_struct.captures.len == 0 and loaded_struct.field_types.len == 0;
            if (src_inst.inst == .main_struct_inst) {
                assert(loaded_struct.captures.len == 0);
                const ui = dwarf.getUnit(zf.mod.?);
                _, const fi = try ui.get(dwarf).getFile(zcu.gpa, ui, src_inst.file);
                try dwarf.abbrevCode(di_nw, switch (loaded_struct.layout) {
                    .auto => if (is_empty) .empty_file else .file,
                    .@"extern", .@"packed" => unreachable,
                });
                try di_w.writeUleb128(@backingInt(fi));
                try dwarf.strx(di_nw, loaded_struct.name.toSlice(ip));
            } else if (loaded_struct.captures.len > 0 or loaded_struct.is_reified) {
                try dwarf.abbrevCode(di_nw, switch (loaded_struct.name_nav) {
                    else => if (is_empty) switch (loaded_struct.layout) {
                        .auto, .@"extern" => .decl_instance_empty_struct,
                        .@"packed" => .decl_instance_empty_packed_struct,
                    } else switch (loaded_struct.layout) {
                        .auto, .@"extern" => .decl_instance_struct,
                        .@"packed" => .decl_instance_packed_struct,
                    },
                    .none => if (is_empty) switch (loaded_struct.layout) {
                        .auto, .@"extern" => .type_decl_instance_empty_struct,
                        .@"packed" => .type_decl_instance_empty_packed_struct,
                    } else switch (loaded_struct.layout) {
                        .auto, .@"extern" => .type_decl_instance_struct,
                        .@"packed" => .type_decl_instance_packed_struct,
                    },
                });
                try dwarf.refType(pt, di_nw, .fromInterned(ip.namespacePtr(
                    ip.namespacePtr(loaded_struct.namespace).parent.unwrap().?,
                ).owner_type));
                try dwarf.secOffset(di_nw, try dwarf.getConstDecl(pt, @"const"), 0);
                if (loaded_struct.name_nav == .none)
                    try dwarf.strx(di_nw, loaded_struct.name.toSlice(ip));
            } else if (loaded_struct.name_nav.unwrap()) |name_ni| {
                const name_nav = ip.getNav(name_ni);
                const decl = zf.zir.?.getDeclaration(name_nav.srcInst(ip).resolve(ip).?);
                const parent_ni = try dwarf.getConstDecl(pt, ip.namespacePtr(
                    name_nav.analysis.?.namespace,
                ).owner_type);
                try dwarf.abbrevCode(di_nw, if (is_empty) switch (loaded_struct.layout) {
                    .auto, .@"extern" => .decl_empty_struct,
                    .@"packed" => .decl_empty_packed_struct,
                } else switch (loaded_struct.layout) {
                    .auto, .@"extern" => .decl_struct,
                    .@"packed" => .decl_packed_struct,
                });
                try dwarf.secOffset(di_nw, parent_ni, 0);
                try di_w.writeInt(u32, decl.src_line + 1, dwarf.endian);
                try di_w.writeUleb128(decl.src_column + 1);
                try di_w.writeByte(if (decl.is_pub) DW.ACCESS.public else DW.ACCESS.private);
                try dwarf.strx(di_nw, name_nav.name.toSlice(ip));
            } else {
                const decl = zf.zir.?.getStructDecl(src_inst.inst);
                const parent_ni = try dwarf.getConstDecl(pt, ip.namespacePtr(
                    ip.namespacePtr(loaded_struct.namespace).parent.unwrap().?,
                ).owner_type);
                try dwarf.abbrevCode(di_nw, if (is_empty) switch (loaded_struct.layout) {
                    .auto, .@"extern" => .type_decl_empty_struct,
                    .@"packed" => .type_decl_empty_packed_struct,
                } else switch (loaded_struct.layout) {
                    .auto, .@"extern" => .type_decl_struct,
                    .@"packed" => .type_decl_packed_struct,
                });
                try dwarf.secOffset(di_nw, parent_ni, 0);
                try di_w.writeInt(u32, decl.src_line + 1, dwarf.endian);
                try di_w.writeUleb128(decl.src_column + 1);
                try dwarf.strx(di_nw, loaded_struct.name.toSlice(ip));
            }
            switch (loaded_struct.layout) {
                .auto, .@"extern" => {
                    const ty: Type = .fromInterned(@"const");
                    try di_w.writeUleb128(ty.abiSize(zcu));
                    try di_w.writeUleb128(ty.abiAlignment(zcu).toByteUnits().?);
                    try dwarf.genCaptures(pt, di_nw, loaded_struct.captures);
                    for (0..loaded_struct.field_types.len) |field_index| {
                        const is_comptime = loaded_struct.field_is_comptime_bits.get(ip, field_index);
                        // TODO: we currently don't emit information about default values for
                        // non-`comptime` fields, because these default values are resolved at a
                        // separate time in the compiler frontend. To emit this information, the
                        // frontend needs to tell us when the default values are available: like
                        // how `Zcu.PerThread.ensureTypeLayoutUpToDate` enqueues a link task to
                        // indicate completion of the type's layout, a task should be enqueued
                        // by `Zcu.PerThread.ensureStructDefaultsUpToDate`, and upon receiving
                        // it we should patch the correct default field values in.
                        const field_default = if (is_comptime)
                            loaded_struct.field_defaults.getOrNone(ip, field_index)
                        else
                            .none;
                        assert(!(is_comptime and field_default == .none));
                        const field_ty: Type =
                            .fromInterned(loaded_struct.field_types.get(ip)[field_index]);
                        const field_default_class = switch (field_default) {
                            .none => .no_possible_value,
                            else => field_ty.classify(zcu),
                        };
                        try dwarf.abbrevCode(di_nw, if (is_comptime) switch (field_default_class) {
                            .no_possible_value, .one_possible_value => .field_comptime,
                            .runtime => .field_comptime_fully_runtime,
                            .partially_comptime => .field_comptime_partially_comptime,
                            .fully_comptime => .field_comptime_fully_comptime,
                        } else switch (field_default_class) {
                            .no_possible_value, .one_possible_value => .field,
                            .runtime => .field_default_fully_runtime,
                            .partially_comptime => .field_default_partially_comptime,
                            .fully_comptime => .field_default_fully_comptime,
                        });
                        try dwarf.strx(
                            di_nw,
                            loaded_struct.field_names.get(ip)[field_index].toSlice(ip),
                        );
                        try dwarf.refType(pt, di_nw, field_ty);
                        if (!is_comptime) {
                            try di_w.writeUleb128(loaded_struct.field_offsets.get(ip)[field_index]);
                            try di_w.writeUleb128(loaded_struct.field_aligns.getOrNone(
                                ip,
                                field_index,
                            ).toByteUnits() orelse field_ty.abiAlignment(zcu).toByteUnits().?);
                        }
                        if (field_default_class.hasRuntimeBits())
                            try dwarf.blockConst(pt, di_nw, .fromInterned(field_default));
                        if (field_default_class.comptimeOnly())
                            try dwarf.refConst(pt, di_nw, .fromInterned(field_default));
                    }
                },
                .@"packed" => {
                    try dwarf.refType(pt, di_nw, .fromInterned(loaded_struct.packed_backing_int_type));
                    try dwarf.genCaptures(pt, di_nw, loaded_struct.captures);
                    var field_bit_offset: u16 = 0;
                    for (0..loaded_struct.field_types.len) |field_index| {
                        try dwarf.abbrevCode(di_nw, .packed_field);
                        try dwarf.strx(
                            di_nw,
                            loaded_struct.field_names.get(ip)[field_index].toSlice(ip),
                        );
                        const field_ty: Type =
                            .fromInterned(loaded_struct.field_types.get(ip)[field_index]);
                        try dwarf.refType(pt, di_nw, field_ty);
                        try di_w.writeUleb128(field_bit_offset);
                        field_bit_offset += @intCast(field_ty.bitSize(zcu));
                    }
                },
            }
            if (!is_empty) try di_w.writeUleb128(@backingInt(AbbrevCode.null));
        },
        .union_type => {
            const loaded_union = ip.loadUnionType(@"const");
            const loaded_tag = ip.loadEnumType(loaded_union.enum_tag_type);
            const zfi = loaded_union.zir_index.resolveFile(ip);
            const zf = zcu.fileByIndex(zfi);
            const is_empty = loaded_union.captures.len == 0 and loaded_union.field_types.len == 0;
            if (loaded_union.captures.len > 0 or loaded_union.is_reified) {
                try dwarf.abbrevCode(di_nw, switch (loaded_union.name_nav) {
                    else => if (is_empty) switch (loaded_union.layout) {
                        .auto, .@"extern" => .decl_instance_empty_union,
                        .@"packed" => .decl_instance_empty_packed_union,
                    } else switch (loaded_union.layout) {
                        .auto, .@"extern" => .decl_instance_union,
                        .@"packed" => .decl_instance_packed_union,
                    },
                    .none => if (is_empty) switch (loaded_union.layout) {
                        .auto, .@"extern" => .type_decl_instance_empty_union,
                        .@"packed" => .type_decl_instance_empty_packed_union,
                    } else switch (loaded_union.layout) {
                        .auto, .@"extern" => .type_decl_instance_union,
                        .@"packed" => .type_decl_instance_packed_union,
                    },
                });
                try dwarf.refType(pt, di_nw, .fromInterned(ip.namespacePtr(
                    ip.namespacePtr(loaded_union.namespace).parent.unwrap().?,
                ).owner_type));
                try dwarf.secOffset(di_nw, try dwarf.getConstDecl(pt, @"const"), 0);
                if (loaded_union.name_nav == .none)
                    try dwarf.strx(di_nw, loaded_union.name.toSlice(ip));
            } else if (loaded_union.name_nav.unwrap()) |name_ni| {
                const name_nav = ip.getNav(name_ni);
                const decl = zf.zir.?.getDeclaration(name_nav.srcInst(ip).resolve(ip).?);
                const parent_ni = try dwarf.getConstDecl(pt, ip.namespacePtr(
                    name_nav.analysis.?.namespace,
                ).owner_type);
                try dwarf.abbrevCode(di_nw, if (is_empty) switch (loaded_union.layout) {
                    .auto, .@"extern" => .decl_empty_union,
                    .@"packed" => .decl_empty_packed_union,
                } else switch (loaded_union.layout) {
                    .auto, .@"extern" => .decl_union,
                    .@"packed" => .decl_packed_union,
                });
                try dwarf.secOffset(di_nw, parent_ni, 0);
                try di_w.writeInt(u32, decl.src_line + 1, dwarf.endian);
                try di_w.writeUleb128(decl.src_column + 1);
                try di_w.writeByte(if (decl.is_pub) DW.ACCESS.public else DW.ACCESS.private);
                try dwarf.strx(di_nw, name_nav.name.toSlice(ip));
            } else {
                const decl = zf.zir.?.getUnionDecl(loaded_union.zir_index.resolve(ip).?);
                const parent_ni = try dwarf.getConstDecl(pt, ip.namespacePtr(
                    ip.namespacePtr(loaded_union.namespace).parent.unwrap().?,
                ).owner_type);
                try dwarf.abbrevCode(di_nw, if (is_empty) switch (loaded_union.layout) {
                    .auto, .@"extern" => .type_decl_empty_union,
                    .@"packed" => .type_decl_empty_packed_union,
                } else switch (loaded_union.layout) {
                    .auto, .@"extern" => .type_decl_union,
                    .@"packed" => .type_decl_packed_union,
                });
                try dwarf.secOffset(di_nw, parent_ni, 0);
                try di_w.writeInt(u32, decl.src_line + 1, dwarf.endian);
                try di_w.writeUleb128(decl.src_column + 1);
                try dwarf.strx(di_nw, loaded_union.name.toSlice(ip));
            }
            switch (loaded_union.layout) {
                .auto, .@"extern" => {
                    const union_layout = Type.getUnionLayout(loaded_union, zcu);
                    try di_w.writeUleb128(union_layout.abi_size);
                    try di_w.writeUleb128(union_layout.abi_align.toByteUnits().?);
                    try dwarf.genCaptures(pt, di_nw, loaded_union.captures);
                    if (loaded_union.has_runtime_tag) {
                        try dwarf.abbrevCode(di_nw, .tagged_union);
                        const discr_offset = di_w.end;
                        try dwarf.secOffsetPlaceholder(di_w);
                        {
                            try dwarf.secOffsetFinish(di_nw, discr_offset, di_nw.ni, di_w.end);
                            try dwarf.abbrevCode(di_nw, .generated_field);
                            try dwarf.strx(di_nw, "tag");
                            try dwarf.refType(pt, di_nw, .fromInterned(loaded_union.enum_tag_type));
                            try di_w.writeUleb128(union_layout.tagOffset());

                            for (0..loaded_union.field_types.len) |field_index| {
                                try dwarf.abbrevCode(di_nw, .tagged_union_field);
                                try dwarf.enumConstValue(di_w, loaded_tag, field_index);
                                {
                                    try dwarf.abbrevCode(di_nw, .field);
                                    try dwarf.strx(
                                        di_nw,
                                        loaded_tag.field_names.get(ip)[field_index].toSlice(ip),
                                    );
                                    const field_ty: Type =
                                        .fromInterned(loaded_union.field_types.get(ip)[field_index]);
                                    try dwarf.refType(pt, di_nw, field_ty);
                                    try di_w.writeUleb128(union_layout.payloadOffset());
                                    try di_w.writeUleb128(loaded_union.field_aligns.getOrNone(
                                        ip,
                                        field_index,
                                    ).toByteUnits() orelse if (field_ty.isNoReturn(zcu))
                                        1
                                    else
                                        field_ty.abiAlignment(zcu).toByteUnits().?);
                                }
                                try di_w.writeUleb128(@backingInt(AbbrevCode.null));
                            }
                        }
                        try di_w.writeUleb128(@backingInt(AbbrevCode.null));
                    } else for (0..loaded_union.field_types.len) |field_index| {
                        try dwarf.abbrevCode(di_nw, .field);
                        try dwarf.strx(
                            di_nw,
                            loaded_tag.field_names.get(ip)[field_index].toSlice(ip),
                        );
                        const field_ty: Type =
                            .fromInterned(loaded_union.field_types.get(ip)[field_index]);
                        try dwarf.refType(pt, di_nw, field_ty);
                        try di_w.writeUleb128(0);
                        try di_w.writeUleb128(loaded_union.field_aligns.getOrNone(
                            ip,
                            field_index,
                        ).toByteUnits() orelse if (field_ty.isNoReturn(zcu))
                            1
                        else
                            field_ty.abiAlignment(zcu).toByteUnits().?);
                    }
                },
                .@"packed" => {
                    try dwarf.refType(pt, di_nw, .fromInterned(loaded_union.packed_backing_int_type));
                    for (0..loaded_union.field_types.len) |field_index| {
                        try dwarf.abbrevCode(di_nw, .packed_field);
                        try dwarf.strx(
                            di_nw,
                            loaded_tag.field_names.get(ip)[field_index].toSlice(ip),
                        );
                        try dwarf.refType(pt, di_nw, .fromInterned(
                            loaded_union.field_types.get(ip)[field_index],
                        ));
                        try di_w.writeUleb128(0);
                    }
                },
            }
            if (!is_empty) try di_w.writeUleb128(@backingInt(AbbrevCode.null));
        },
        .enum_type => {
            const loaded_enum = ip.loadEnumType(@"const");
            const is_empty = loaded_enum.captures.len == 0 and loaded_enum.field_names.len == 0;
            switch (loaded_enum.owner_union) {
                .none => {
                    const zfi = loaded_enum.zir_index.unwrap().?.resolveFile(ip);
                    const zf = zcu.fileByIndex(zfi);
                    const zir = &zf.zir.?;
                    if (loaded_enum.captures.len > 0 or loaded_enum.is_reified) {
                        try dwarf.abbrevCode(di_nw, switch (loaded_enum.name_nav) {
                            else => if (is_empty) .decl_instance_empty_enum else .decl_instance_enum,
                            .none => if (is_empty)
                                .type_decl_instance_empty_enum
                            else
                                .type_decl_instance_enum,
                        });
                        try dwarf.refType(pt, di_nw, .fromInterned(ip.namespacePtr(
                            ip.namespacePtr(loaded_enum.namespace).parent.unwrap().?,
                        ).owner_type));
                        try dwarf.secOffset(di_nw, try dwarf.getConstDecl(pt, @"const"), 0);
                        if (loaded_enum.name_nav == .none)
                            try dwarf.strx(di_nw, loaded_enum.name.toSlice(ip));
                    } else if (loaded_enum.name_nav.unwrap()) |name_ni| {
                        const name_nav = ip.getNav(name_ni);
                        const decl = zir.getDeclaration(name_nav.srcInst(ip).resolve(ip).?);
                        const parent_ni = try dwarf.getConstDecl(pt, ip.namespacePtr(
                            name_nav.analysis.?.namespace,
                        ).owner_type);
                        try dwarf.abbrevCode(
                            di_nw,
                            if (is_empty) .decl_empty_enum else .decl_enum,
                        );
                        try dwarf.secOffset(di_nw, parent_ni, 0);
                        try di_w.writeInt(u32, decl.src_line + 1, dwarf.endian);
                        try di_w.writeUleb128(decl.src_column + 1);
                        try di_w.writeByte(if (decl.is_pub) DW.ACCESS.public else DW.ACCESS.private);
                        try dwarf.strx(di_nw, name_nav.name.toSlice(ip));
                    } else {
                        const decl = zir.getEnumDecl(loaded_enum.zir_index.unwrap().?.resolve(ip).?);
                        const parent_ni = try dwarf.getConstDecl(pt, ip.namespacePtr(
                            ip.namespacePtr(loaded_enum.namespace).parent.unwrap().?,
                        ).owner_type);
                        try dwarf.abbrevCode(
                            di_nw,
                            if (is_empty) .type_decl_empty_enum else .type_decl_enum,
                        );
                        try dwarf.secOffset(di_nw, parent_ni, 0);
                        try di_w.writeInt(u32, decl.src_line + 1, dwarf.endian);
                        try di_w.writeUleb128(decl.src_column + 1);
                        try dwarf.strx(di_nw, loaded_enum.name.toSlice(ip));
                    }
                },
                else => {
                    try dwarf.abbrevCode(
                        di_nw,
                        if (is_empty) .generated_empty_enum_type else .generated_enum_type,
                    );
                    try dwarf.strx(di_nw, loaded_enum.fqn.toSlice(ip));
                },
            }
            try dwarf.refType(pt, di_nw, .fromInterned(loaded_enum.int_tag_type));
            try dwarf.genCaptures(pt, di_nw, loaded_enum.captures);
            for (0..loaded_enum.field_names.len) |field_index| {
                try dwarf.abbrevCode(di_nw, .enum_field);
                try dwarf.enumConstValue(di_w, loaded_enum, field_index);
                try dwarf.strx(di_nw, loaded_enum.field_names.get(ip)[field_index].toSlice(ip));
            }
            if (!is_empty) try di_w.writeUleb128(@backingInt(AbbrevCode.null));
        },
        // no defined size, so lowered the same as incomplete struct types
        .opaque_type => return dwarf.updateConstIncompleteInner(pt, di_nw, @"const"),
        .spirv_type => unreachable,
        .func_type => |func_type| {
            const is_empty = func_type.param_types.len == 0 and !func_type.is_var_args;
            const name = try zcu.gpa.print("{f}", .{Type.fromInterned(@"const").fmt(pt)});
            defer zcu.gpa.free(name);
            try dwarf.abbrevCode(di_nw, if (is_empty) .empty_func_type else .func_type);
            try dwarf.strx(di_nw, name);
            const cc: DW.CC = cc: {
                if (zcu.getTarget().cCallingConvention()) |cc| {
                    if (@as(std.lang.CallingConvention.Tag, cc) == func_type.cc) {
                        break :cc .normal;
                    }
                }
                // For better or worse, we try to match what Clang emits.
                break :cc switch (func_type.cc) {
                    .@"inline" => .nocall,
                    .async, .auto, .naked => .normal,
                    .x86_64_sysv => .LLVM_X86_64SysV,
                    .x86_64_win => .LLVM_Win64,
                    .x86_64_regcall_v3_sysv => .LLVM_X86RegCall,
                    .x86_64_regcall_v4_win => .LLVM_X86RegCall,
                    .x86_64_vectorcall => .LLVM_vectorcall,
                    .x86_sysv, .x86_win, .x86_mingw => .normal,
                    .x86_64_preserve_none => .LLVM_PreserveNone,
                    .x86_stdcall => .BORLAND_stdcall,
                    .x86_fastcall => .BORLAND_msfastcall,
                    .x86_thiscall => .BORLAND_thiscall,
                    .x86_thiscall_mingw => .BORLAND_thiscall,
                    .x86_regcall_v3 => .LLVM_X86RegCall,
                    .x86_regcall_v4_win => .LLVM_X86RegCall,
                    .x86_vectorcall => .LLVM_vectorcall,

                    .aarch64_aapcs => .normal,
                    .aarch64_aapcs_darwin => .normal,
                    .aarch64_aapcs_win => .normal,
                    .aarch64_vfabi => .LLVM_AAPCS,
                    .aarch64_vfabi_sve => .LLVM_AAPCS,
                    .aarch64_preserve_none => .LLVM_PreserveNone,

                    .arm_aapcs => .LLVM_AAPCS,
                    .arm_aapcs_vfp => .LLVM_AAPCS_VFP,

                    .riscv64_lp64_v,
                    .riscv32_ilp32_v,
                    => .LLVM_RISCVVectorCall,

                    .m68k_rtd => .LLVM_M68kRTD,

                    .sh_renesas => .GNU_renesas_sh,

                    .amdgcn_kernel => .LLVM_OpenCLKernel,
                    .nvptx_kernel,
                    .spirv_kernel,
                    => .nocall,

                    .x86_64_interrupt,
                    .x86_interrupt,
                    .arm_interrupt,
                    .mips64_interrupt,
                    .mips_interrupt,
                    .riscv64_interrupt,
                    .riscv32_interrupt,
                    .sh_interrupt,
                    .arc_interrupt,
                    .avr_builtin,
                    .avr_signal,
                    .avr_interrupt,
                    .csky_interrupt,
                    .m68k_interrupt,
                    .microblaze_interrupt,
                    .msp430_interrupt,
                    => .normal,

                    else => .nocall,
                };
            };
            try di_w.writeByte(@backingInt(cc));
            try dwarf.refType(pt, di_nw, .fromInterned(func_type.return_type));
            for (0..func_type.param_types.len) |param_index| {
                try dwarf.abbrevCode(di_nw, .unnamed_param);
                try dwarf.refType(pt, di_nw, .fromInterned(
                    func_type.param_types.get(ip)[param_index],
                ));
            }
            if (func_type.is_var_args) try dwarf.abbrevCode(di_nw, .is_var_args);
            if (!is_empty) try di_w.writeUleb128(@backingInt(AbbrevCode.null));
        },
        .error_set_type => |error_set_type| {
            const name = try zcu.gpa.print("{f}", .{Type.fromInterned(@"const").fmt(pt)});
            defer zcu.gpa.free(name);
            try dwarf.abbrevCode(
                di_nw,
                if (error_set_type.names.len > 0) .generated_enum_type else .generated_empty_enum_type,
            );
            try dwarf.strx(di_nw, name);
            try dwarf.refType(pt, di_nw, try pt.intType(.unsigned, zcu.errorSetBits()));
            for (0..error_set_type.names.len) |field_index| {
                const field_name = error_set_type.names.get(ip)[field_index];
                try dwarf.abbrevCode(di_nw, .enum_field);
                try di_w.writeUleb128(DW.FORM.udata);
                try di_w.writeUleb128(ip.getErrorValueIfExists(field_name).?);
                try dwarf.strx(di_nw, field_name.toSlice(ip));
            }
            if (error_set_type.names.len > 0) try di_w.writeUleb128(@backingInt(AbbrevCode.null));
        },
        .inferred_error_set_type => |func| {
            const name = try zcu.gpa.print("{f}", .{Type.fromInterned(@"const").fmt(pt)});
            defer zcu.gpa.free(name);
            try dwarf.abbrevCode(di_nw, .inferred_error_set_type);
            try dwarf.strx(di_nw, name);
            try dwarf.refType(pt, di_nw, switch (ies: {
                const fi = dwarf.getFuncIfExists(ip.indexToKey(func).func.owner_nav) orelse
                    break :ies .none;
                break :ies switch (fi.get(dwarf).state) {
                    .unresolved => .none,
                    .resolved => ip.funcIesResolvedUnordered(func),
                };
            }) {
                .none => .anyerror,
                else => |ies| .fromInterned(ies),
            });
        },

        .undef => |ty| {
            try dwarf.abbrevCode(di_nw, .undefined_comptime_value);
            try dwarf.refType(pt, di_nw, .fromInterned(ty));
        },
        .simple_value => |simple_value| switch (simple_value) {
            .void => unreachable, // opv state
            .true, .false => unreachable, // runtime bits
            .@"unreachable" => unreachable, // not a value
            .null => {
                // TODO: proper representation for this
                try dwarf.abbrevCode(di_nw, .undefined_comptime_value);
                try dwarf.refType(pt, di_nw, .null);
            },
        },
        .@"extern" => unreachable,
        .func => |func| {
            const func_type = ip.indexToKey(func.ty).func_type;
            const nav = ip.getNav(func.owner_nav);
            const inst_info = nav.srcInst(ip).resolveFull(ip).?;
            const zir = &zcu.fileByIndex(inst_info.file).zir.?;
            const decl = zir.getDeclaration(inst_info.inst);
            const is_empty = func_type.param_types.len == 0 and !func_type.is_var_args;
            const parent_ty: Type = .fromInterned(ip.namespacePtr(nav.analysis.?.namespace).owner_type);
            if (func.generic_owner != .none or parent_ty.getCaptures(zcu).len > 0) {
                try dwarf.abbrevCode(
                    di_nw,
                    if (is_empty) .decl_instance_empty_func_generic else .decl_instance_func_generic,
                );
                try dwarf.refType(pt, di_nw, parent_ty);
                try dwarf.secOffset(di_nw, try dwarf.getConstDecl(pt, @"const"), 0);
            } else {
                try dwarf.abbrevCode(
                    di_nw,
                    if (is_empty) .decl_empty_func_generic else .decl_func_generic,
                );
                try dwarf.refType(pt, di_nw, parent_ty);
                try di_w.writeInt(u32, decl.src_line + 1, dwarf.endian);
                try di_w.writeUleb128(decl.src_column + 1);
                try di_w.writeByte(if (decl.is_pub) DW.ACCESS.public else DW.ACCESS.private);
                try dwarf.strx(di_nw, nav.name.toSlice(ip));
            }
            try dwarf.refType(pt, di_nw, .fromInterned(func_type.return_type));
            for (
                zir.getParamBody(func.zir_body_inst.resolve(ip).?)[0..func_type.param_types.len],
                func_type.param_types.get(&zcu.intern_pool),
            ) |param_inst, param_ty| {
                switch (zir.getParamName(param_inst).?) {
                    .empty => try dwarf.abbrevCode(di_nw, .unnamed_param),
                    else => |param_name| {
                        try dwarf.abbrevCode(di_nw, .param);
                        try dwarf.strx(di_nw, zir.nullTerminatedString(param_name));
                    },
                }
                try dwarf.refType(pt, di_nw, .fromInterned(param_ty));
            }
            if (func_type.is_var_args) try dwarf.abbrevCode(di_nw, .is_var_args);
            if (!is_empty) try di_w.writeUleb128(@backingInt(AbbrevCode.null));
        },
        .int => |int| {
            var big_int_space: Value.BigIntSpace = undefined;
            try dwarf.abbrevCode(di_nw, .comptime_value);
            try dwarf.refType(pt, di_nw, .fromInterned(int.ty));
            try dwarf.bigIntConstValue(
                di_w,
                .fromInterned(int.ty),
                Value.fromInterned(@"const").toBigInt(&big_int_space, zcu),
            );
        },
        .bitpack => |bitpack| {
            var big_int_space: Value.BigIntSpace = undefined;
            const backing_int_val: Value = .fromInterned(bitpack.backing_int_val);
            try dwarf.abbrevCode(di_nw, .comptime_value);
            try dwarf.refType(pt, di_nw, .fromInterned(bitpack.ty));
            try dwarf.bigIntConstValue(
                di_w,
                backing_int_val.typeOf(zcu),
                backing_int_val.toBigInt(&big_int_space, zcu),
            );
        },
        .err => |err| {
            try dwarf.abbrevCode(di_nw, .comptime_value);
            try dwarf.refType(pt, di_nw, .fromInterned(err.ty));
            try di_w.writeUleb128(DW.FORM.udata);
            try di_w.writeUleb128(try pt.getErrorValue(err.name));
        },
        .error_union => |error_union| {
            try dwarf.abbrevCode(di_nw, .aggregate_undefined_comptime_value);
            try dwarf.refType(pt, di_nw, .fromInterned(error_union.ty));
            var err_buf: [4]u8 = undefined;
            const err_bytes = err_buf[0..@divCeil(zcu.errorSetBits(), 8)];
            const err_val = switch (error_union.val) {
                .err_name => |err_name| try pt.getErrorValue(err_name),
                .payload => 0,
            };
            switch (err_bytes.len) {
                else => unreachable,
                inline 0...4 => |len| std.mem.writeInt(
                    @Int(.unsigned, 8 * len),
                    err_bytes[0..len],
                    @intCast(err_val),
                    dwarf.endian,
                ),
            }
            {
                try dwarf.abbrevCode(di_nw, .comptime_value_field_runtime);
                try dwarf.strx(di_nw, "is_error");
                try di_w.writeUleb128(err_bytes.len);
                try di_w.writeAll(err_bytes);
            }
            payload_field: switch (error_union.val) {
                .err_name => {},
                .payload => |payload_val| {
                    const payload_ty: Type = .fromInterned(ip.typeOf(payload_val));
                    const payload_class = payload_ty.classify(zcu);
                    try dwarf.abbrevCode(di_nw, if (payload_class.comptimeOnly())
                        .comptime_value_field_comptime
                    else if (payload_class.hasRuntimeBits())
                        .comptime_value_field_runtime
                    else
                        break :payload_field);
                    try dwarf.strx(di_nw, "value");
                    if (payload_class.comptimeOnly())
                        try dwarf.refConst(pt, di_nw, .fromInterned(payload_val))
                    else if (payload_class.hasRuntimeBits())
                        try dwarf.blockConst(pt, di_nw, .fromInterned(payload_val))
                    else
                        unreachable;
                },
            }
            {
                try dwarf.abbrevCode(di_nw, .comptime_value_field_runtime);
                try dwarf.strx(di_nw, "error");
                try di_w.writeUleb128(err_bytes.len);
                try di_w.writeAll(err_bytes);
            }
            try di_w.writeUleb128(@backingInt(AbbrevCode.null));
        },
        .enum_literal => |enum_literal| {
            try dwarf.abbrevCode(di_nw, .comptime_value);
            try dwarf.refType(pt, di_nw, .enum_literal);
            try di_w.writeUleb128(DW.FORM.strx);
            try dwarf.strx(di_nw, enum_literal.toSlice(ip));
        },
        .enum_tag => |enum_tag| {
            var big_int_space: Value.BigIntSpace = undefined;
            const int = ip.indexToKey(enum_tag.int).int;
            try dwarf.abbrevCode(di_nw, .comptime_value);
            try dwarf.refType(pt, di_nw, .fromInterned(enum_tag.ty));
            try dwarf.bigIntConstValue(
                di_w,
                .fromInterned(int.ty),
                Value.fromInterned(@"const").toBigInt(&big_int_space, zcu),
            );
        },
        .float => |float| {
            try dwarf.abbrevCode(di_nw, .comptime_value);
            try dwarf.refType(pt, di_nw, .fromInterned(float.ty));
            switch (float.storage) {
                .f16 => |f16_val| {
                    try di_w.writeUleb128(DW.FORM.data2);
                    try di_w.writeInt(u16, @bitCast(f16_val), dwarf.endian);
                },
                .f32 => |f32_val| {
                    try di_w.writeUleb128(DW.FORM.data4);
                    try di_w.writeInt(u32, @bitCast(f32_val), dwarf.endian);
                },
                .f64 => |f64_val| {
                    try di_w.writeUleb128(DW.FORM.data8);
                    try di_w.writeInt(u64, @bitCast(f64_val), dwarf.endian);
                },
                .f80 => |f80_val| {
                    try di_w.writeUleb128(DW.FORM.block);
                    try di_w.writeUleb128(@divExact(80, 8));
                    try di_w.writeInt(u80, @bitCast(f80_val), dwarf.endian);
                },
                .f128 => |f128_val| {
                    try di_w.writeUleb128(DW.FORM.data16);
                    try di_w.writeInt(u128, @bitCast(f128_val), dwarf.endian);
                },
            }
        },
        .ptr => |ptr| {
            const Access = union(enum) {
                index: u64,
                field: InternPool.NullTerminatedString,
                synthetic_field: []const u8,
                tuple_index: u32,
            };
            var zero_bit_accesses: std.ArrayList(Access) = .empty;
            defer zero_bit_accesses.deinit(zcu.gpa);
            location: {
                var base_addr = ptr.base_addr;
                var byte_offset = ptr.byte_offset;
                const base_ni = while (true) {
                    const base_ptr, const access: Access = base_ptr_access: switch (base_addr) {
                        .nav => |ni| break (try dwarf.getGlobal(ni)).get(dwarf).debug_info_ni,
                        .comptime_alloc, .comptime_field => unreachable,
                        .uav => |uav| {
                            const uav_ty: Type = .fromInterned(ip.typeOf(uav.val));
                            if (uav_ty.classify(zcu) == .one_possible_value) {
                                try dwarf.abbrevCode(di_nw, if (zero_bit_accesses.items.len > 0)
                                    .aggregate_comptime_value
                                else
                                    .comptime_value);
                                try dwarf.refType(pt, di_nw, .fromInterned(ptr.ty));
                                try di_w.writeUleb128(DW.FORM.udata);
                                try di_w.writeUleb128(ip.indexToKey(uav.orig_ty)
                                    .ptr_type.flags.alignment.toByteUnits() orelse
                                    uav_ty.abiAlignment(zcu).toByteUnits().?);
                                break :location;
                            } else break Const.get(try dwarf.getConst(pt, .fromInterned(
                                uav.val,
                            )), dwarf).debug_info_ni;
                        },
                        .int => {
                            try dwarf.abbrevCode(di_nw, if (zero_bit_accesses.items.len > 0)
                                .aggregate_comptime_value
                            else
                                .comptime_value);
                            try dwarf.refType(pt, di_nw, .fromInterned(ptr.ty));
                            try di_w.writeUleb128(DW.FORM.udata);
                            try di_w.writeUleb128(byte_offset);
                            break :location;
                        },
                        .eu_payload => |eu_ptr| {
                            const base_ptr = ip.indexToKey(eu_ptr).ptr;
                            byte_offset += codegen.errUnionPayloadOffset(.fromInterned(ip.indexToKey(
                                ip.indexToKey(base_ptr.ty).ptr_type.child,
                            ).error_union_type.payload_type), zcu);
                            break :base_ptr_access .{ base_ptr, .{ .synthetic_field = "value" } };
                        },
                        .opt_payload => |opt_ptr| .{ ip.indexToKey(opt_ptr).ptr, .{
                            .synthetic_field = "?",
                        } },
                        .field => |field| {
                            const base_ptr = ip.indexToKey(field.base).ptr;
                            const agg_ty: Type =
                                .fromInterned(ip.indexToKey(base_ptr.ty).ptr_type.child);
                            break :base_ptr_access .{
                                base_ptr,
                                if (agg_ty.isSlice(zcu)) .{ .synthetic_field = switch (field.index) {
                                    Value.slice_ptr_index => "ptr",
                                    Value.slice_len_index => "len",
                                    else => unreachable,
                                } } else if (agg_ty.structFieldName(
                                    @intCast(field.index),
                                    zcu,
                                ).unwrap()) |field_name|
                                    .{ .field = field_name }
                                else
                                    .{ .tuple_index = @intCast(field.index) },
                            };
                        },
                        .arr_elem => |arr_elem| .{
                            ip.indexToKey(arr_elem.base).ptr,
                            .{ .index = arr_elem.index },
                        },
                    };
                    base_addr = base_ptr.base_addr;
                    byte_offset += base_ptr.byte_offset;
                    if (Type.fromInterned(
                        ip.indexToKey(base_ptr.ty).ptr_type.child,
                    ).hasRuntimeBits(zcu))
                        assert(access != .index)
                    else
                        try zero_bit_accesses.append(zcu.gpa, access);
                };
                try dwarf.abbrevCode(di_nw, if (zero_bit_accesses.items.len > 0)
                    .aggregate_location_comptime_value
                else
                    .location_comptime_value);
                try dwarf.refType(pt, di_nw, .fromInterned(ptr.ty));
                try dwarf.exprLoc(di_nw, .{ .implicit_pointer = .{
                    .node = base_ni.unwrap().?,
                    .offset = byte_offset,
                } });
            }
            if (zero_bit_accesses.items.len > 0) {
                for (zero_bit_accesses.items) |access| switch (access) {
                    .index => |index| {
                        try dwarf.abbrevCode(di_nw, .array_index);
                        try di_w.writeUleb128(index);
                    },
                    .field => |field| {
                        try dwarf.abbrevCode(di_nw, .access);
                        try dwarf.strx(di_nw, field.toSlice(ip));
                    },
                    .synthetic_field => |field| {
                        try dwarf.abbrevCode(di_nw, .access);
                        try dwarf.strx(di_nw, field);
                    },
                    .tuple_index => |index| {
                        try dwarf.abbrevCode(di_nw, .access);
                        var field_name_buf: [std.fmt.count("{d}", .{std.math.maxInt(u32)})]u8 =
                            undefined;
                        const field_name = std.mem.print(&field_name_buf, "{d}", .{index}) catch
                            unreachable;
                        try dwarf.strx(di_nw, field_name);
                    },
                };
                try di_w.writeUleb128(@backingInt(AbbrevCode.null));
            }
        },
        .slice => |slice| {
            try dwarf.abbrevCode(di_nw, .aggregate_undefined_comptime_value);
            try dwarf.refType(pt, di_nw, .fromInterned(slice.ty));
            {
                try dwarf.abbrevCode(di_nw, .comptime_value_field_comptime);
                try dwarf.strx(di_nw, "ptr");
                try dwarf.refConst(pt, di_nw, .fromInterned(slice.ptr));
            }
            {
                try dwarf.abbrevCode(di_nw, .comptime_value_field_runtime);
                try dwarf.strx(di_nw, "len");
                try dwarf.blockConst(pt, di_nw, .fromInterned(slice.len));
            }
            try di_w.writeUleb128(@backingInt(AbbrevCode.null));
        },
        .opt => |opt| {
            const opt_child_ty: Type = .fromInterned(ip.indexToKey(opt.ty).opt_type);
            try dwarf.abbrevCode(di_nw, .aggregate_undefined_comptime_value);
            try dwarf.refType(pt, di_nw, .fromInterned(opt.ty));
            {
                try dwarf.abbrevCode(di_nw, .comptime_value_field_runtime);
                try dwarf.strx(di_nw, "has_value");
                switch (optRepr(opt_child_ty, zcu)) {
                    .opv_null => try di_w.writeUleb128(0),
                    .unpacked => try dwarf.blockConst(pt, di_nw, .makeBool(opt.val != .none)),
                    .error_set, .pointer => try dwarf.blockConst(pt, di_nw, .fromInterned(@"const")),
                }
            }
            if (opt.val != .none) child_field: {
                const opt_child_class = opt_child_ty.classify(zcu);
                try dwarf.abbrevCode(di_nw, if (opt_child_class.comptimeOnly())
                    .comptime_value_field_comptime
                else if (opt_child_class.hasRuntimeBits())
                    .comptime_value_field_runtime
                else
                    break :child_field);
                try dwarf.strx(di_nw, "?");
                if (opt_child_class.comptimeOnly())
                    try dwarf.refConst(pt, di_nw, .fromInterned(opt.val))
                else if (opt_child_class.hasRuntimeBits())
                    try dwarf.blockConst(pt, di_nw, .fromInterned(opt.val))
                else
                    unreachable;
            }
            try di_w.writeUleb128(@backingInt(AbbrevCode.null));
        },
        .aggregate => |aggregate| {
            try dwarf.abbrevCode(di_nw, .aggregate_undefined_comptime_value);
            try dwarf.refType(pt, di_nw, .fromInterned(aggregate.ty));
            switch (ip.indexToKey(aggregate.ty)) {
                .struct_type => {
                    const loaded_struct = ip.loadStructType(aggregate.ty);
                    assert(loaded_struct.layout == .auto);
                    for (0..loaded_struct.field_types.len) |field_index| {
                        if (loaded_struct.field_is_comptime_bits.get(ip, field_index)) continue;
                        const field_ty: Type =
                            .fromInterned(loaded_struct.field_types.get(ip)[field_index]);
                        const field_class = field_ty.classify(zcu);
                        try dwarf.abbrevCode(di_nw, if (field_class.comptimeOnly())
                            .comptime_value_field_comptime
                        else if (field_class.hasRuntimeBits())
                            .comptime_value_field_runtime
                        else
                            continue);
                        try dwarf.strx(
                            di_nw,
                            loaded_struct.field_names.get(ip)[field_index].toSlice(ip),
                        );
                        const field_value: Value = .fromInterned(switch (aggregate.storage) {
                            .bytes => unreachable,
                            .elems => |elems| elems[field_index],
                            .repeated_elem => |repeated_elem| repeated_elem,
                        });
                        if (field_class.comptimeOnly())
                            try dwarf.refConst(pt, di_nw, field_value)
                        else if (field_class.hasRuntimeBits())
                            try dwarf.blockConst(pt, di_nw, field_value)
                        else
                            unreachable;
                    }
                },
                .tuple_type => |tuple_type| for (0..tuple_type.types.len) |field_index| {
                    if (tuple_type.values.get(ip)[field_index] != .none) continue;
                    const field_ty: Type = .fromInterned(tuple_type.types.get(ip)[field_index]);
                    const field_class = field_ty.classify(zcu);
                    try dwarf.abbrevCode(di_nw, if (field_class.comptimeOnly())
                        .comptime_value_field_comptime
                    else if (field_class.hasRuntimeBits())
                        .comptime_value_field_runtime
                    else
                        continue);
                    {
                        var field_name_buf: [std.fmt.count("{d}", .{std.math.maxInt(u32)})]u8 =
                            undefined;
                        const field_name = std.mem.print(&field_name_buf, "{d}", .{field_index}) catch
                            unreachable;
                        try dwarf.strx(di_nw, field_name);
                    }
                    const field_value: Value = .fromInterned(switch (aggregate.storage) {
                        .bytes => unreachable,
                        .elems => |elems| elems[field_index],
                        .repeated_elem => |repeated_elem| repeated_elem,
                    });
                    if (field_class.comptimeOnly())
                        try dwarf.refConst(pt, di_nw, field_value)
                    else if (field_class.hasRuntimeBits())
                        try dwarf.blockConst(pt, di_nw, field_value)
                    else
                        unreachable;
                },
                inline .array_type, .vector_type => |sequence_type| {
                    const child_ty: Type = .fromInterned(sequence_type.child);
                    const child_class = child_ty.classify(zcu);
                    for (switch (aggregate.storage) {
                        .bytes => unreachable,
                        .elems => |elems| elems,
                        .repeated_elem => |*repeated_elem| repeated_elem[0..1],
                    }) |elem| {
                        try dwarf.abbrevCode(di_nw, if (child_class.comptimeOnly())
                            .comptime_value_elem_comptime
                        else if (child_class.hasRuntimeBits())
                            .comptime_value_elem_runtime
                        else
                            break);
                        if (child_class.comptimeOnly())
                            try dwarf.refConst(pt, di_nw, .fromInterned(elem))
                        else if (child_class.hasRuntimeBits())
                            try dwarf.blockConst(pt, di_nw, .fromInterned(elem))
                        else
                            unreachable;
                    }
                },
                else => unreachable,
            }
            try di_w.writeUleb128(@backingInt(AbbrevCode.null));
        },
        .un => |un| {
            try dwarf.abbrevCode(di_nw, .aggregate_undefined_comptime_value);
            try dwarf.refType(pt, di_nw, .fromInterned(un.ty));
            {
                const loaded_union = ip.loadUnionType(un.ty);
                assert(loaded_union.layout == .auto);
                const field_index = zcu.unionTagFieldIndex(loaded_union, Value.fromInterned(un.tag)).?;
                const field_ty: Type = .fromInterned(loaded_union.field_types.get(ip)[field_index]);
                const field_class = field_ty.classify(zcu);
                const field_name =
                    ip.loadEnumType(loaded_union.enum_tag_type).field_names.get(ip)[field_index];
                try dwarf.abbrevCode(di_nw, if (field_class.comptimeOnly())
                    .comptime_value_field_comptime
                else if (field_class.hasRuntimeBits())
                    .comptime_value_field_runtime
                else
                    .access);
                try dwarf.strx(di_nw, field_name.toSlice(ip));
                if (field_class.comptimeOnly())
                    try dwarf.refConst(pt, di_nw, .fromInterned(un.val))
                else if (field_class.hasRuntimeBits())
                    try dwarf.blockConst(pt, di_nw, .fromInterned(un.val));
            }
            try di_w.writeUleb128(@backingInt(AbbrevCode.null));
        },

        .memoized_call => unreachable, // not a value
    }
    try dwarf.genDebugInfoPadding(di_w, di_w.unusedCapacityLen());
}

fn optRepr(opt_child_ty: Type, zcu: *const Zcu) enum { unpacked, opv_null, error_set, pointer } {
    if (opt_child_ty.isNoReturn(zcu)) return .opv_null;
    return switch (opt_child_ty.toIntern()) {
        .anyerror_type => .error_set,
        else => switch (zcu.intern_pool.indexToKey(opt_child_ty.toIntern())) {
            else => .unpacked,
            .error_set_type, .inferred_error_set_type => .error_set,
            .ptr_type => |ptr_type| if (ptr_type.flags.is_allowzero) .unpacked else .pointer,
        },
    };
}

pub fn updateConstIncomplete(
    dwarf: *Dwarf,
    pt: Zcu.PerThread,
    di_nw: *link.MappedFile.Node.Writer,
    val: InternPool.Index,
) link.Error!void {
    log.debug("updateConstIncomplete({f})", .{Value.fromInterned(val).fmtValue(pt)});
    dwarf.updateConstIncompleteInner(pt, di_nw, val) catch |err| switch (err) {
        else => |e| return e,
        error.WriteFailed => return dwarf.reportWriteError(di_nw),
    };
}
fn updateConstIncompleteInner(
    dwarf: *Dwarf,
    pt: Zcu.PerThread,
    di_nw: *link.MappedFile.Node.Writer,
    val: InternPool.Index,
) link.EmitError!void {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const di_w = &di_nw.interface;
    done: {
        const kind: enum { @"struct", @"union", @"enum" }, const zf, const src_line, const src_column, const is_reified, const captures, const name, const maybe_name_nav, const namespace = container: switch (ip.indexToKey(val)) {
            .struct_type => {
                const loaded_struct = ip.loadStructType(val);
                const src_inst = loaded_struct.zir_index.resolveFull(ip) orelse {
                    try dwarf.lostTracking(di_nw);
                    break :done;
                };
                const zf = zcu.fileByIndex(src_inst.file);
                switch (src_inst.inst) {
                    .main_struct_inst => {
                        const ui = dwarf.getUnit(zf.mod.?);
                        _, const fi = try ui.get(dwarf).getFile(zcu.gpa, ui, src_inst.file);
                        try dwarf.abbrevCode(di_nw, .empty_file);
                        try di_w.writeUleb128(@backingInt(fi));
                        try dwarf.strx(di_nw, loaded_struct.name.toSlice(ip));
                        try di_w.writeByte(@intFromBool(true));
                        break :done;
                    },
                    else => {
                        const zir = &zf.zir.?;
                        const data = zir.instructions.items(.data)[@backingInt(src_inst.inst)].extended;
                        const src_line, const src_column = src_loc: switch (data.opcode) {
                            else => unreachable,
                            .struct_decl => {
                                const decl = zir.getStructDecl(src_inst.inst);
                                break :src_loc .{ decl.src_line, decl.src_column };
                            },
                            .reify_struct => {
                                const decl = zir.extraData(
                                    std.zig.Zir.Inst.ReifyStruct,
                                    data.operand,
                                ).data;
                                break :src_loc .{ decl.src_line, decl.src_column };
                            },
                        };
                        break :container .{
                            .@"struct",
                            zf,
                            src_line,
                            src_column,
                            loaded_struct.is_reified,
                            loaded_struct.captures,
                            loaded_struct.name,
                            loaded_struct.name_nav,
                            loaded_struct.namespace,
                        };
                    },
                }
            },
            .union_type => {
                const loaded_union = ip.loadUnionType(val);
                const src_inst = loaded_union.zir_index.resolveFull(ip) orelse {
                    try dwarf.lostTracking(di_nw);
                    break :done;
                };
                const zf = zcu.fileByIndex(src_inst.file);
                const zir = &zf.zir.?;
                const data = zir.instructions.items(.data)[@backingInt(src_inst.inst)].extended;
                const src_line, const src_column = src_loc: switch (data.opcode) {
                    else => unreachable,
                    .union_decl => {
                        const decl = zir.getUnionDecl(src_inst.inst);
                        break :src_loc .{ decl.src_line, decl.src_column };
                    },
                    .reify_union => {
                        const decl = zir.extraData(std.zig.Zir.Inst.ReifyUnion, data.operand).data;
                        break :src_loc .{ decl.src_line, decl.src_column };
                    },
                };
                break :container .{
                    .@"union",
                    zf,
                    src_line,
                    src_column,
                    loaded_union.is_reified,
                    loaded_union.captures,
                    loaded_union.name,
                    loaded_union.name_nav,
                    loaded_union.namespace,
                };
            },
            .enum_type => {
                const loaded_enum = ip.loadEnumType(val);
                const zir_index = loaded_enum.zir_index.unwrap() orelse {
                    try dwarf.abbrevCode(di_nw, .generated_empty_struct_type);
                    try dwarf.strx(di_nw, loaded_enum.name.toSlice(ip));
                    try di_w.writeByte(@intFromBool(true));
                    break :done;
                };
                const src_inst = zir_index.resolveFull(ip) orelse {
                    try dwarf.lostTracking(di_nw);
                    break :done;
                };
                const zf = zcu.fileByIndex(src_inst.file);
                const zir = &zf.zir.?;
                const data = zir.instructions.items(.data)[@backingInt(src_inst.inst)].extended;
                const src_line, const src_column = src_loc: switch (data.opcode) {
                    else => unreachable,
                    .enum_decl => {
                        const decl = zir.getEnumDecl(src_inst.inst);
                        break :src_loc .{ decl.src_line, decl.src_column };
                    },
                    .reify_enum => {
                        const decl = zir.extraData(std.zig.Zir.Inst.ReifyEnum, data.operand).data;
                        break :src_loc .{ decl.src_line, decl.src_column };
                    },
                };
                break :container .{
                    .@"enum",
                    zf,
                    src_line,
                    src_column,
                    loaded_enum.is_reified,
                    loaded_enum.captures,
                    loaded_enum.name,
                    loaded_enum.name_nav,
                    loaded_enum.namespace,
                };
            },
            // always complete, but forwarded from `updateConstInner`
            .opaque_type => {
                const loaded_opaque = ip.loadOpaqueType(val);
                const src_inst = loaded_opaque.zir_index.resolveFull(ip) orelse {
                    try dwarf.lostTracking(di_nw);
                    break :done;
                };
                const zf = zcu.fileByIndex(src_inst.file);
                const decl = zf.zir.?.getOpaqueDecl(src_inst.inst);
                break :container .{
                    .@"struct",
                    zf,
                    decl.src_line,
                    decl.src_column,
                    false,
                    loaded_opaque.captures,
                    loaded_opaque.name,
                    loaded_opaque.name_nav,
                    loaded_opaque.namespace,
                };
            },
            else => |val_key| break :done switch (val_key.typeOf()) {
                .type_type => {
                    const name = try zcu.gpa.print("{f}", .{Type.fromInterned(val).fmt(pt)});
                    defer zcu.gpa.free(name);
                    try dwarf.abbrevCode(di_nw, .generated_empty_struct_type);
                    try dwarf.strx(di_nw, name);
                    try di_w.writeByte(@intFromBool(true));
                },
                else => |ty| {
                    try dwarf.abbrevCode(di_nw, .undefined_comptime_value);
                    try dwarf.refType(pt, di_nw, .fromInterned(ty));
                },
            },
        };
        if (captures.len > 0 or is_reified) {
            try dwarf.abbrevCode(di_nw, if (captures.len > 0) switch (kind) {
                .@"struct" => .decl_instance_incomplete_struct,
                .@"union" => .decl_instance_incomplete_union,
                .@"enum" => .decl_instance_incomplete_enum,
            } else switch (kind) {
                .@"struct" => .decl_instance_empty_incomplete_struct,
                .@"union" => .decl_instance_empty_incomplete_union,
                .@"enum" => .decl_instance_empty_incomplete_enum,
            });
            try dwarf.refType(pt, di_nw, .fromInterned(ip.namespacePtr(
                ip.namespacePtr(namespace).parent.unwrap().?,
            ).owner_type));
            try dwarf.secOffset(di_nw, try dwarf.getConstDecl(pt, val), 0);
        } else if (maybe_name_nav.unwrap()) |name_ni| {
            const name_nav = ip.getNav(name_ni);
            const decl = zf.zir.?.getDeclaration(name_nav.srcInst(ip).resolve(ip).?);
            const parent_ni =
                try dwarf.getConstDecl(pt, ip.namespacePtr(name_nav.analysis.?.namespace).owner_type);
            try dwarf.abbrevCode(di_nw, if (captures.len > 0) switch (kind) {
                .@"struct" => .decl_incomplete_struct,
                .@"union" => .decl_incomplete_union,
                .@"enum" => .decl_incomplete_enum,
            } else switch (kind) {
                .@"struct" => .decl_empty_incomplete_struct,
                .@"union" => .decl_empty_incomplete_union,
                .@"enum" => .decl_empty_incomplete_enum,
            });
            try dwarf.secOffset(di_nw, parent_ni, 0);
            try di_w.writeInt(u32, decl.src_line + 1, dwarf.endian);
            try di_w.writeUleb128(decl.src_column + 1);
            try di_w.writeByte(if (decl.is_pub) DW.ACCESS.public else DW.ACCESS.private);
            try dwarf.strx(di_nw, name_nav.name.toSlice(ip));
        } else {
            const parent_ni = try dwarf.getConstDecl(pt, ip.namespacePtr(
                ip.namespacePtr(namespace).parent.unwrap().?,
            ).owner_type);
            try dwarf.abbrevCode(di_nw, if (captures.len > 0) switch (kind) {
                .@"struct" => .type_decl_incomplete_struct,
                .@"union" => .type_decl_incomplete_union,
                .@"enum" => .type_decl_incomplete_enum,
            } else switch (kind) {
                .@"struct" => .type_decl_empty_incomplete_struct,
                .@"union" => .type_decl_empty_incomplete_union,
                .@"enum" => .type_decl_empty_incomplete_enum,
            });
            try dwarf.secOffset(di_nw, parent_ni, 0);
            try di_w.writeInt(u32, src_line + 1, dwarf.endian);
            try di_w.writeUleb128(src_column + 1);
            try dwarf.strx(di_nw, name.toSlice(ip));
        }
        try dwarf.genCaptures(pt, di_nw, captures);
        if (captures.len > 0) try di_w.writeByte(@backingInt(AbbrevCode.null));
    }
    try dwarf.genDebugInfoPadding(di_w, di_w.unusedCapacityLen());
}

fn genCaptures(
    dwarf: *Dwarf,
    pt: Zcu.PerThread,
    di_nw: *link.MappedFile.Node.Writer,
    captures: anytype,
) link.EmitError!void {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    for (captures.get(ip)) |capture| switch (capture.unwrap()) {
        .@"comptime" => |capture_val| {
            const ty: Type = .fromInterned(ip.typeOf(capture_val));
            const ty_class = ty.classify(zcu);
            try dwarf.abbrevCode(di_nw, switch (ty_class) {
                .no_possible_value => unreachable,
                .one_possible_value => .comptime_capture,
                .runtime => .comptime_capture_runtime,
                .partially_comptime => .comptime_capture_partially_comptime,
                .fully_comptime => .comptime_capture_fully_comptime,
            });
            try dwarf.refType(pt, di_nw, ty);
            if (ty_class.hasRuntimeBits()) try dwarf.blockConst(pt, di_nw, .fromInterned(capture_val));
            if (ty_class.comptimeOnly()) try dwarf.refConst(pt, di_nw, .fromInterned(capture_val));
        },
        .runtime => |capture_ty| {
            try dwarf.abbrevCode(di_nw, .runtime_capture);
            try dwarf.refType(pt, di_nw, .fromInterned(capture_ty));
        },
        .nav_val => |capture_nav| {
            const gi = try dwarf.getGlobal(capture_nav);
            try dwarf.abbrevCode(di_nw, .nav_capture);
            try dwarf.exprLoc(di_nw, .{ .implicit_pointer = .{
                .node = gi.get(dwarf).debug_info_ni.unwrap().?,
            } });
        },
        .nav_ref => |capture_nav| {
            const gi = try dwarf.getGlobal(capture_nav);
            try dwarf.abbrevCode(di_nw, .nav_capture);
            try dwarf.exprLoc(di_nw, .{ .stack_value = &.{ .implicit_pointer = .{
                .node = gi.get(dwarf).debug_info_ni.unwrap().?,
            } } });
        },
    };
}

pub fn genDecl(
    dwarf: *Dwarf,
    pt: Zcu.PerThread,
    di_nw: *link.MappedFile.Node.Writer,
    instance: Decl.Instance,
) link.Error!void {
    switch (instance) {
        .none => unreachable,
        .@"const" => |@"const"| log.debug("genDecl({f})", .{Value.fromInterned(@"const").fmtValue(pt)}),
        .global => |global| log.debug("genDecl({f})", .{
            pt.zcu.intern_pool.getNav(global).fqn.fmt(&pt.zcu.intern_pool),
        }),
    }
    dwarf.genDeclInner(pt, di_nw, instance) catch |err| switch (err) {
        else => |e| return e,
        error.WriteFailed => return dwarf.reportWriteError(di_nw),
    };
}
fn genDeclInner(
    dwarf: *Dwarf,
    pt: Zcu.PerThread,
    di_nw: *link.MappedFile.Node.Writer,
    instance: Decl.Instance,
) link.EmitError!void {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const di_w = &di_nw.interface;
    done: switch (instance) {
        .none => unreachable,
        .@"const" => |@"const"| {
            const kind: enum { @"struct", @"union", @"enum" }, const zf, const src_line, const src_column, const capture_names, const captures, const maybe_name_nav, const namespace = container: switch (ip.indexToKey(instance.@"const")) {
                else => unreachable,
                .struct_type => {
                    const loaded_struct = ip.loadStructType(@"const");
                    const src_inst = loaded_struct.zir_index.resolveFull(ip) orelse {
                        try dwarf.lostTracking(di_nw);
                        break :done;
                    };
                    const zf = zcu.fileByIndex(src_inst.file);
                    const zir = &zf.zir.?;
                    const inst = zir.instructions.get(@backingInt(src_inst.inst));
                    const src_line, const src_column, const capture_names = decl: switch (inst.tag) {
                        else => unreachable,
                        .struct_init, .struct_init_ref => {
                            const decl = zir.extraData(
                                std.zig.Zir.Inst.StructInit,
                                inst.data.pl_node.payload_index,
                            ).data;
                            break :decl .{ decl.src_line, decl.src_column, &.{} };
                        },
                        .struct_init_anon => {
                            const decl = zir.extraData(
                                std.zig.Zir.Inst.StructInitAnon,
                                inst.data.pl_node.payload_index,
                            ).data;
                            break :decl .{ decl.src_line, decl.src_column, &.{} };
                        },
                        .extended => switch (inst.data.extended.opcode) {
                            else => unreachable,
                            .struct_decl => {
                                const decl = zir.getStructDecl(src_inst.inst);
                                break :decl .{ decl.src_line, decl.src_column, decl.capture_names };
                            },
                            .reify_struct => {
                                const decl = zir.extraData(
                                    std.zig.Zir.Inst.ReifyStruct,
                                    inst.data.extended.operand,
                                ).data;
                                break :decl .{ decl.src_line, decl.src_column, &.{} };
                            },
                        },
                    };
                    break :container .{
                        .@"struct",
                        zf,
                        src_line,
                        src_column,
                        capture_names,
                        loaded_struct.captures,
                        loaded_struct.name_nav,
                        loaded_struct.namespace,
                    };
                },
                .union_type => {
                    const loaded_union = ip.loadUnionType(@"const");
                    const src_inst = loaded_union.zir_index.resolveFull(ip) orelse {
                        try dwarf.lostTracking(di_nw);
                        break :done;
                    };
                    const zf = zcu.fileByIndex(src_inst.file);
                    const zir = &zf.zir.?;
                    const inst = zir.instructions.get(@backingInt(src_inst.inst));
                    const src_line, const src_column, const capture_names = decl: switch (inst.tag) {
                        else => unreachable,
                        .extended => switch (inst.data.extended.opcode) {
                            else => unreachable,
                            .union_decl => {
                                const decl = zir.getUnionDecl(src_inst.inst);
                                break :decl .{ decl.src_line, decl.src_column, decl.capture_names };
                            },
                            .reify_union => {
                                const decl = zir.extraData(
                                    std.zig.Zir.Inst.ReifyUnion,
                                    inst.data.extended.operand,
                                ).data;
                                break :decl .{ decl.src_line, decl.src_column, &.{} };
                            },
                        },
                    };
                    break :container .{
                        .@"union",
                        zf,
                        src_line,
                        src_column,
                        capture_names,
                        loaded_union.captures,
                        loaded_union.name_nav,
                        loaded_union.namespace,
                    };
                },
                .enum_type => {
                    const loaded_enum = ip.loadEnumType(@"const");
                    const src_inst = loaded_enum.zir_index.unwrap().?.resolveFull(ip) orelse {
                        try dwarf.lostTracking(di_nw);
                        break :done;
                    };
                    const zf = zcu.fileByIndex(src_inst.file);
                    const zir = &zf.zir.?;
                    const inst = zir.instructions.get(@backingInt(src_inst.inst));
                    const src_line, const src_column, const capture_names = decl: switch (inst.tag) {
                        else => unreachable,
                        .extended => switch (inst.data.extended.opcode) {
                            else => unreachable,
                            .enum_decl => {
                                const decl = zir.getEnumDecl(src_inst.inst);
                                break :decl .{ decl.src_line, decl.src_column, decl.capture_names };
                            },
                            .reify_enum => {
                                const decl = zir.extraData(
                                    std.zig.Zir.Inst.ReifyEnum,
                                    inst.data.extended.operand,
                                ).data;
                                break :decl .{ decl.src_line, decl.src_column, &.{} };
                            },
                        },
                    };
                    break :container .{
                        .@"enum",
                        zf,
                        src_line,
                        src_column,
                        capture_names,
                        loaded_enum.captures,
                        loaded_enum.name_nav,
                        loaded_enum.namespace,
                    };
                },
                .opaque_type => {
                    const loaded_opaque = ip.loadOpaqueType(@"const");
                    const src_inst = loaded_opaque.zir_index.resolveFull(ip) orelse {
                        try dwarf.lostTracking(di_nw);
                        break :done;
                    };
                    const zf = zcu.fileByIndex(src_inst.file);
                    const decl = zf.zir.?.getOpaqueDecl(src_inst.inst);
                    break :container .{
                        .@"struct",
                        zf,
                        decl.src_line,
                        decl.src_column,
                        decl.capture_names,
                        loaded_opaque.captures,
                        loaded_opaque.name_nav,
                        loaded_opaque.namespace,
                    };
                },
                .func => |func| {
                    const owner_nav = ip.getNav(switch (func.generic_owner) {
                        else => |generic_owner| zcu.funcInfo(generic_owner).owner_nav,
                        .none => func.owner_nav,
                    });
                    const inst_info = owner_nav.srcInst(ip).resolveFull(ip).?;
                    const decl = zcu.fileByIndex(inst_info.file).zir.?.getDeclaration(inst_info.inst);
                    const parent_ni = try dwarf.getConstDecl(pt, ip.namespacePtr(
                        owner_nav.analysis.?.namespace,
                    ).owner_type);
                    try dwarf.abbrevCode(di_nw, .decl_specification_func);
                    try dwarf.secOffset(di_nw, parent_ni, 0);
                    try di_w.writeInt(u32, decl.src_line + 1, dwarf.endian);
                    try di_w.writeUleb128(decl.src_column + 1);
                    try di_w.writeByte(if (decl.is_pub) DW.ACCESS.public else DW.ACCESS.private);
                    try dwarf.strx(di_nw, owner_nav.name.toSlice(ip));
                    break :done;
                },
            };
            const zir = &zf.zir.?;
            if (maybe_name_nav.unwrap()) |name_ni| {
                const name_nav = ip.getNav(name_ni);
                const decl = zir.getDeclaration(name_nav.srcInst(ip).resolve(ip).?);
                const parent_ni = try dwarf.getConstDecl(pt, ip.namespacePtr(
                    name_nav.analysis.?.namespace,
                ).owner_type);
                try dwarf.abbrevCode(di_nw, if (captures.len > 0) switch (kind) {
                    .@"struct" => .decl_specification_struct,
                    .@"union" => .decl_specification_union,
                    .@"enum" => .decl_specification_enum,
                } else switch (kind) {
                    .@"struct" => .decl_specification_empty_struct,
                    .@"union" => .decl_specification_empty_union,
                    .@"enum" => .decl_specification_empty_enum,
                });
                try dwarf.secOffset(di_nw, parent_ni, 0);
                try di_w.writeInt(u32, decl.src_line + 1, dwarf.endian);
                try di_w.writeUleb128(decl.src_column + 1);
                try di_w.writeByte(if (decl.is_pub) DW.ACCESS.public else DW.ACCESS.private);
                try dwarf.strx(di_nw, name_nav.name.toSlice(ip));
            } else {
                const parent_ni = try dwarf.getConstDecl(pt, ip.namespacePtr(
                    ip.namespacePtr(namespace).parent.unwrap().?,
                ).owner_type);
                try dwarf.abbrevCode(di_nw, if (captures.len > 0) switch (kind) {
                    .@"struct" => .type_decl_specification_struct,
                    .@"union" => .type_decl_specification_union,
                    .@"enum" => .type_decl_specification_enum,
                } else switch (kind) {
                    .@"struct" => .type_decl_specification_empty_struct,
                    .@"union" => .type_decl_specification_empty_union,
                    .@"enum" => .type_decl_specification_empty_enum,
                });
                try dwarf.secOffset(di_nw, parent_ni, 0);
                try di_w.writeInt(u32, src_line + 1, dwarf.endian);
                try di_w.writeUleb128(src_column + 1);
            }
            for (capture_names, captures.get(ip)) |capture_name, capture| {
                try dwarf.abbrevCode(di_nw, .capture_specification);
                switch (capture.unwrap()) {
                    .@"comptime",
                    .runtime,
                    .nav_val,
                    => try dwarf.strx(di_nw, zir.nullTerminatedString(capture_name)),
                    .nav_ref => {
                        const capture_name_slice =
                            try zcu.gpa.print("&{s}", .{zir.nullTerminatedString(capture_name)});
                        defer zcu.gpa.free(capture_name_slice);
                        try dwarf.strx(di_nw, capture_name_slice);
                    },
                }
            }
            if (captures.len > 0) try di_w.writeUleb128(@backingInt(AbbrevCode.null));
        },
        .global => |global| {
            const nav = ip.getNav(global);
            const nav_const, const nav_ty = nav_resolved: {
                const nav_resolved = nav.resolved.?;
                break :nav_resolved .{ nav_resolved.@"const", nav_resolved.type };
            };
            const src_inst = nav.srcInst(ip).resolveFull(ip).?;
            const decl = zcu.fileByIndex(src_inst.file).zir.?.getDeclaration(src_inst.inst);
            const parent_ni = try dwarf.getConstDecl(pt, ip.namespacePtr(
                nav.analysis.?.namespace,
            ).owner_type);
            try dwarf.abbrevCode(di_nw, switch (nav_ty) {
                .type_type => .decl_specification_type,
                else => if (nav_const) .decl_specification_const else .decl_specification_var,
            });
            try dwarf.secOffset(di_nw, parent_ni, 0);
            try di_w.writeInt(u32, decl.src_line + 1, dwarf.endian);
            try di_w.writeUleb128(decl.src_column + 1);
            try di_w.writeByte(if (decl.is_pub) DW.ACCESS.public else DW.ACCESS.private);
            try dwarf.strx(di_nw, nav.name.toSlice(ip));
        },
    }
    try dwarf.genDebugInfoPadding(di_w, di_w.unusedCapacityLen());
}

pub fn updateLineNumber(
    dwarf: *Dwarf,
    mf: *link.MappedFile,
    inst: InternPool.TrackedInst.Index,
    line: u32,
) void {
    const di = dwarf.getDeclIfExists(inst) orelse return;
    const decl_ni = di.get(dwarf).debug_info_ni.unwrap().?;
    comptime assert(AbbrevCode.common_decl_attrs[0][1] == .ref_addr);
    comptime assert(AbbrevCode.common_decl_attrs[1][0] == .decl_line);
    comptime assert(AbbrevCode.common_decl_attrs[1][1] == .data4);
    std.mem.writeInt(
        u32,
        decl_ni.slice(mf)[AbbrevCode.decl_size + dwarf.secOffsetSize() ..][0..4],
        line + 1,
        dwarf.endian,
    );
}

pub fn lostTracking(dwarf: *Dwarf, di_nw: *link.MappedFile.Node.Writer) link.EmitError!void {
    try dwarf.abbrevCode(di_nw, .decl_lost);
}

fn refAbbrevCodeIfExists(
    dwarf: *Dwarf,
    abbrev_code: AbbrevCode,
) ?@typeInfo(AbbrevCode).@"enum".tag_type {
    assert(abbrev_code != .null);
    return if (dwarf.debug_abbrev.set.contains(abbrev_code)) @backingInt(abbrev_code) else null;
}
fn refAbbrevCode(
    dwarf: *Dwarf,
    mf: *link.MappedFile,
    abbrev_code: AbbrevCode,
) link.Error!@typeInfo(AbbrevCode).@"enum".tag_type {
    if (dwarf.refAbbrevCodeIfExists(abbrev_code)) |backing_int| {
        @branchHint(.likely);
        return backing_int;
    }
    const gpa = dwarf.lf.comp.gpa;
    const debug_abbrev_ni = dwarf.debug_abbrev.ni.unwrap().?;
    try debug_abbrev_ni.moved(gpa, mf);
    var da_nw: link.MappedFile.Node.Writer = undefined;
    debug_abbrev_ni.writer(gpa, mf, &da_nw);
    defer da_nw.deinit();
    dwarf.genDebugAbbrev(&da_nw, abbrev_code) catch |err| switch (err) {
        else => |e| return e,
        error.WriteFailed => return dwarf.reportWriteError(&da_nw),
    };
    dwarf.debug_abbrev.set.insert(abbrev_code);
    return dwarf.refAbbrevCodeIfExists(abbrev_code).?;
}
fn abbrevCode(
    dwarf: *Dwarf,
    nw: *link.MappedFile.Node.Writer,
    abbrev_code: AbbrevCode,
) link.EmitError!void {
    try nw.interface.writeUleb128(try dwarf.refAbbrevCode(nw.mf, abbrev_code));
}

fn genDebugAbbrev(
    dwarf: *Dwarf,
    da_nw: *link.MappedFile.Node.Writer,
    abbrev_code: AbbrevCode,
) link.EmitError!void {
    const abbrev = AbbrevCode.abbrevs.get(abbrev_code);
    const da_w = &da_nw.interface;
    da_w.end = dwarf.debug_abbrev.end;
    try da_w.writeUleb128(@backingInt(abbrev_code));
    try da_w.writeUleb128(@backingInt(abbrev.tag));
    try da_w.writeByte(if (abbrev.children) DW.CHILDREN.yes else DW.CHILDREN.no);
    for (abbrev.attrs) |*attr| {
        try da_w.writeUleb128(@backingInt(switch (attr[0]) {
            else => |at| at,
            .ZIG_call_line_relative => |at| if (dwarf.lf.comp.config.incremental) at else .call_line,
        }));
        try da_w.writeUleb128(@backingInt(attr[1]));
    }
    for (0..2) |_| try da_w.writeUleb128(0);
    dwarf.debug_abbrev.end = da_w.end;
}

fn secOffsetSize(dwarf: *Dwarf) usize {
    return switch (dwarf.format) {
        .@"32" => 4,
        .@"64" => 8,
    };
}
fn secOffset(
    dwarf: *Dwarf,
    nw: *link.MappedFile.Node.Writer,
    target_ni: link.MappedFile.Node.Index,
    addend: usize,
) link.EmitError!void {
    const offset = nw.interface.end;
    try dwarf.secOffsetPlaceholder(&nw.interface);
    try dwarf.secOffsetFinish(nw, offset, target_ni, addend);
}
fn secOffsetPlaceholder(dwarf: *Dwarf, w: *std.Io.Writer) std.Io.Writer.Error!void {
    @memset(try w.writableSlice(dwarf.secOffsetSize()), undefined);
}
fn secOffsetFinish(
    dwarf: *Dwarf,
    nw: *link.MappedFile.Node.Writer,
    offset: usize,
    target_ni: link.MappedFile.Node.Index,
    addend: usize,
) link.Error!void {
    if (dwarf.lf.cast(.elf2)) |elf| try elf.addNodeReloc(
        nw.ni,
        offset,
        target_ni,
        @bitCast(@as(u64, addend)),
        switch (dwarf.format) {
            .@"32" => .abs32,
            .@"64" => .abs64,
        },
    ) else unreachable;
}

fn addrPlaceholder(dwarf: *Dwarf, w: *std.Io.Writer) std.Io.Writer.Error!void {
    @memset(try w.writableSlice(@backingInt(dwarf.address_size)), undefined);
}
fn addrSym(
    dwarf: *Dwarf,
    nw: *link.MappedFile.Node.Writer,
    target_si: link.File.SymbolId,
    addend: usize,
) link.EmitError!void {
    const offset = nw.interface.end;
    try dwarf.addrPlaceholder(&nw.interface);
    if (dwarf.lf.cast(.elf2)) |elf| try elf.addReloc(
        @bitCast(nw.ni),
        offset,
        target_si,
        @bitCast(@as(u64, addend)),
        .absAddr(elf),
    ) else unreachable;
}
fn addrxSym(dwarf: *Dwarf, w: *std.Io.Writer, si: link.File.SymbolId) link.EmitError!void {
    try w.writeUleb128(try dwarf.debug_addr.get(dwarf.lf.comp.gpa, si));
}
fn addrx1Sym(dwarf: *Dwarf, w: *std.Io.Writer, si: link.File.SymbolId) link.EmitError!void {
    try w.writeByte(@intCast(try dwarf.debug_addr.get(dwarf.lf.comp.gpa, si)));
}
fn addrx2Sym(dwarf: *Dwarf, w: *std.Io.Writer, si: link.File.SymbolId) link.EmitError!void {
    try w.writeInt(u16, @intCast(try dwarf.debug_addr.get(dwarf.lf.comp.gpa, si)), dwarf.endian);
}
fn addrx3Sym(dwarf: *Dwarf, w: *std.Io.Writer, si: link.File.SymbolId) link.EmitError!void {
    try w.writeInt(u24, @intCast(try dwarf.debug_addr.get(dwarf.lf.comp.gpa, si)), dwarf.endian);
}
fn addrx4Sym(dwarf: *Dwarf, w: *std.Io.Writer, si: link.File.SymbolId) link.EmitError!void {
    try w.writeInt(u32, @intCast(try dwarf.debug_addr.get(dwarf.lf.comp.gpa, si)), dwarf.endian);
}

fn blockConst(
    dwarf: *Dwarf,
    pt: Zcu.PerThread,
    nw: *link.MappedFile.Node.Writer,
    val: Value,
) link.EmitError!void {
    const ty = val.typeOf(pt.zcu);
    const size = ty.abiSize(pt.zcu);
    try nw.interface.writeUleb128(size);
    const start = nw.interface.end;
    if (size > 0) try codegen.generateSymbol(dwarf.lf, pt, val, &nw.interface, .{
        .atom_index = @bitCast(nw.ni),
    });
    assert(start + size == nw.interface.end);
}

fn refType(
    dwarf: *Dwarf,
    pt: Zcu.PerThread,
    nw: *link.MappedFile.Node.Writer,
    ty: Type,
) link.EmitError!void {
    return dwarf.refConst(pt, nw, ty.toValue());
}
fn refConst(
    dwarf: *Dwarf,
    pt: Zcu.PerThread,
    nw: *link.MappedFile.Node.Writer,
    val: Value,
) link.EmitError!void {
    try dwarf.secOffset(nw, Const.get(try dwarf.getConst(pt, val), dwarf).debug_info_ni.unwrap().?, 0);
}

fn bigIntConstValue(
    dwarf: *Dwarf,
    di_w: *std.Io.Writer,
    ty: Type,
    big_int: std.math.big.int.Const,
) link.EmitError!void {
    const zcu = dwarf.lf.comp.zcu.?;
    const signedness = switch (ty.toIntern()) {
        .comptime_int_type => .signed,
        else => ty.intInfo(zcu).signedness,
    };
    const bits = @max(1, big_int.bitCountTwosCompForSignedness(signedness));
    if (bits <= 64) {
        try di_w.writeUleb128(@as(u13, switch (signedness) {
            .signed => DW.FORM.sdata,
            .unsigned => DW.FORM.udata,
        }));
        var bit: usize = 0;
        var carry: u1 = 1;
        for (try di_w.writableSlice(@divCeil(bits, 7))) |*byte| {
            const limb_bits = @typeInfo(std.math.big.Limb).int.bits;
            const limb_index = bit / limb_bits;
            const limb_shift: std.math.Log2Int(std.math.big.Limb) = @intCast(bit % limb_bits);
            const low_abs_part: u7 = @truncate(big_int.limbs[limb_index] >> limb_shift);
            const abs_part = if (limb_shift > limb_bits - 7 and
                limb_index + 1 < big_int.limbs.len)
            abs_part: {
                const high_abs_part: u7 = @truncate(big_int.limbs[limb_index + 1] << -%limb_shift);
                break :abs_part high_abs_part | low_abs_part;
            } else low_abs_part;
            const twos_comp_part = if (big_int.positive) abs_part else twos_comp_part: {
                const twos_comp_part, carry = @addWithOverflow(~abs_part, carry);
                break :twos_comp_part twos_comp_part;
            };
            bit += 7;
            byte.* = @as(u8, if (bit < bits) 0x80 else 0x00) | twos_comp_part;
        }
    } else {
        try di_w.writeUleb128(DW.FORM.block);
        const size = switch (ty.toIntern()) {
            .comptime_int_type => @divCeil(bits, 8),
            else => ty.abiSize(zcu),
        };
        try di_w.writeUleb128(size);
        big_int.writeTwosComplement(try di_w.writableSlice(@intCast(size)), dwarf.endian);
    }
}

fn enumConstValue(
    dwarf: *Dwarf,
    di_w: *std.Io.Writer,
    loaded_enum: InternPool.LoadedEnumType,
    field_index: usize,
) link.EmitError!void {
    const zcu = dwarf.lf.comp.zcu.?;
    var big_int_space: Value.BigIntSpace = undefined;
    try dwarf.bigIntConstValue(
        di_w,
        .fromInterned(loaded_enum.int_tag_type),
        if (loaded_enum.field_values.len > 0)
            Value.fromInterned(loaded_enum.field_values.get(&zcu.intern_pool)[field_index])
                .toBigInt(&big_int_space, zcu)
        else
            std.math.big.int.Mutable.init(&big_int_space.limbs, field_index).toConst(),
    );
}

fn exprLoc(dwarf: *Dwarf, nw: *link.MappedFile.Node.Writer, loc: Loc) link.EmitError!void {
    var buf: [@max(8, std.atomic.cache_line)]u8 = undefined;
    var dw: std.Io.Writer.Discarding = .init(&buf);
    try loc.write(.{ .io = &dw.writer }, dwarf);

    try nw.interface.writeUleb128(dw.fullCount());
    try loc.write(.{ .mf = nw }, dwarf);
}

fn strp(dwarf: *Dwarf, s: *Str, nw: *link.MappedFile.Node.Writer, str: []const u8) link.EmitError!void {
    const comp = dwarf.lf.comp;
    try dwarf.secOffset(nw, s.ni.unwrap().?, s.get(comp.gpa, nw.mf, str) catch |err| switch (err) {
        else => |e| return e,
        error.MappedFileIo => return comp.link_diags.fail("failed to write output file: {t}", .{
            nw.mf.io_err.?,
        }),
    });
}

fn strx(dwarf: *Dwarf, nw: *link.MappedFile.Node.Writer, str: []const u8) link.EmitError!void {
    try nw.interface.writeUleb128(try dwarf.debug_str_offsets.get(dwarf, &dwarf.debug_str, nw.mf, str));
}
fn strx1(dwarf: *Dwarf, nw: *link.MappedFile.Node.Writer, str: []const u8) link.EmitError!void {
    try nw.interface.writeByte(@intCast(
        try dwarf.debug_str_offsets.get(dwarf, &dwarf.debug_str, nw.mf, str),
    ));
}
fn strx2(dwarf: *Dwarf, nw: *link.MappedFile.Node.Writer, str: []const u8) link.EmitError!void {
    try nw.interface.writeInt(u16, @intCast(
        try dwarf.debug_str_offsets.get(dwarf, &dwarf.debug_str, nw.mf, str),
    ), dwarf.endian);
}
fn strx3(dwarf: *Dwarf, nw: *link.MappedFile.Node.Writer, str: []const u8) link.EmitError!void {
    try nw.interface.writeInt(u24, @intCast(
        try dwarf.debug_str_offsets.get(dwarf, &dwarf.debug_str, nw.mf, str),
    ), dwarf.endian);
}
fn strx4(dwarf: *Dwarf, nw: *link.MappedFile.Node.Writer, str: []const u8) link.EmitError!void {
    try nw.interface.writeInt(u32, @intCast(
        try dwarf.debug_str_offsets.get(dwarf, &dwarf.debug_str, nw.mf, str),
    ), dwarf.endian);
}

fn reportWriteError(dwarf: *Dwarf, nw: *const link.MappedFile.Node.Writer) link.Error {
    switch (nw.err.?) {
        else => |e| return e,
        error.MappedFileIo => return dwarf.lf.comp.link_diags.fail(
            "failed to write output file: {t}",
            .{nw.mf.io_err.?},
        ),
    }
}

fn constPoolUser(dwarf: *Dwarf) link.ConstPool.User {
    return if (dwarf.lf.cast(.elf2)) |elf| .{
        .elf2 = elf,
    } else unreachable;
}

fn DeclValEnum(comptime T: type) type {
    const decl_names = @typeInfo(T).@"struct".decl_names;
    @setEvalBranchQuota(10 * decl_names.len);
    var field_names: [decl_names.len][]const u8 = undefined;
    var fields_len = 0;
    var min_value: ?comptime_int = null;
    var max_value: ?comptime_int = null;
    for (decl_names) |decl_name| {
        if (std.mem.startsWith(u8, decl_name, "HP_") or
            std.mem.endsWith(u8, decl_name, "_user")) continue;
        const value = @field(T, decl_name);
        field_names[fields_len] = decl_name;
        fields_len += 1;
        if (min_value == null or min_value.? > value) min_value = value;
        if (max_value == null or max_value.? < value) max_value = value;
    }
    if (fields_len == 0) return enum {};
    const TagInt = std.math.IntFittingRange(min_value orelse 0, max_value orelse 0);
    var field_vals: [fields_len]TagInt = undefined;
    for (field_names[0..fields_len], &field_vals) |name, *val| val.* = @field(T, name);
    return @Enum(TagInt, .exhaustive, field_names[0..fields_len], &field_vals);
}

pub const AbbrevCode = enum {
    null,
    // padding codes must be one byte uleb128 values to function
    pad_1,
    pad_n,
    // decl, specification, and instance codes are assumed to all have the same uleb128 size
    decl_lost,
    decl_empty_incomplete_enum,
    decl_incomplete_enum,
    decl_empty_enum,
    decl_enum,
    type_decl_empty_incomplete_enum,
    type_decl_incomplete_enum,
    type_decl_empty_enum,
    type_decl_enum,
    decl_empty_incomplete_struct,
    decl_incomplete_struct,
    decl_empty_struct,
    decl_struct,
    type_decl_empty_incomplete_struct,
    type_decl_incomplete_struct,
    type_decl_empty_struct,
    type_decl_struct,
    decl_empty_packed_struct,
    decl_packed_struct,
    type_decl_empty_packed_struct,
    type_decl_packed_struct,
    decl_empty_incomplete_union,
    decl_incomplete_union,
    decl_empty_union,
    decl_union,
    type_decl_empty_incomplete_union,
    type_decl_incomplete_union,
    type_decl_empty_union,
    type_decl_union,
    decl_empty_packed_union,
    decl_packed_union,
    type_decl_empty_packed_union,
    type_decl_packed_union,
    decl_type,
    decl_const,
    decl_const_fully_runtime,
    decl_const_partially_comptime,
    decl_const_fully_comptime,
    decl_var,
    decl_empty_func,
    decl_func,
    decl_empty_func_generic,
    decl_func_generic,
    decl_extern_empty_func,
    decl_extern_func,
    decl_specification_empty_struct,
    decl_specification_struct,
    type_decl_specification_empty_struct,
    type_decl_specification_struct,
    decl_specification_empty_enum,
    decl_specification_enum,
    type_decl_specification_empty_enum,
    type_decl_specification_enum,
    decl_specification_empty_union,
    decl_specification_union,
    type_decl_specification_empty_union,
    type_decl_specification_union,
    decl_specification_type,
    decl_specification_const,
    decl_specification_var,
    decl_specification_func,
    decl_instance_empty_incomplete_enum,
    decl_instance_incomplete_enum,
    decl_instance_empty_enum,
    decl_instance_enum,
    type_decl_instance_empty_enum,
    type_decl_instance_enum,
    decl_instance_empty_incomplete_struct,
    decl_instance_incomplete_struct,
    decl_instance_empty_struct,
    decl_instance_struct,
    type_decl_instance_empty_struct,
    type_decl_instance_struct,
    decl_instance_empty_packed_struct,
    decl_instance_packed_struct,
    type_decl_instance_empty_packed_struct,
    type_decl_instance_packed_struct,
    decl_instance_empty_incomplete_union,
    decl_instance_incomplete_union,
    decl_instance_empty_union,
    decl_instance_union,
    type_decl_instance_empty_union,
    type_decl_instance_union,
    decl_instance_empty_packed_union,
    decl_instance_packed_union,
    type_decl_instance_empty_packed_union,
    type_decl_instance_packed_union,
    decl_instance_type,
    decl_instance_const,
    decl_instance_const_fully_runtime,
    decl_instance_const_partially_comptime,
    decl_instance_const_fully_comptime,
    decl_instance_var,
    decl_instance_empty_func,
    decl_instance_func,
    decl_instance_empty_func_generic,
    decl_instance_func_generic,
    // the rest are unrestricted other than empty variants must not be longer
    // than the non-empty variant, and so should appear first
    empty_file,
    file,
    access,
    enum_field,
    generated_field,
    field,
    field_default_fully_runtime,
    field_default_partially_comptime,
    field_default_fully_comptime,
    field_comptime,
    field_comptime_fully_runtime,
    field_comptime_partially_comptime,
    field_comptime_fully_comptime,
    packed_field,
    tagged_union,
    tagged_union_field,
    tagged_union_default_field,
    void_type,
    numeric_type,
    inferred_error_set_type,
    ptr_type,
    ptr_sentinel_type,
    is_aligned,
    is_const,
    is_volatile,
    array_type,
    array_sentinel_type,
    vector_type,
    array_index,
    array_len,
    empty_func_type,
    func_type,
    param,
    unnamed_param,
    is_var_args,
    generated_empty_enum_type,
    generated_enum_type,
    generated_empty_struct_type,
    generated_struct_type,
    generated_union_type,
    capture_specification,
    comptime_capture,
    comptime_capture_runtime,
    comptime_capture_partially_comptime,
    comptime_capture_fully_comptime,
    runtime_capture,
    nav_capture,
    builtin_extern_empty_func,
    builtin_extern_func,
    builtin_extern_var,
    empty_block,
    block,
    empty_inlined_func,
    inlined_func,
    arg,
    unnamed_arg,
    comptime_arg,
    comptime_arg_fully_runtime,
    comptime_arg_partially_comptime,
    comptime_arg_fully_comptime,
    unnamed_comptime_arg,
    unnamed_comptime_arg_fully_runtime,
    unnamed_comptime_arg_partially_comptime,
    unnamed_comptime_arg_fully_comptime,
    extern_param,
    local_var,
    local_const,
    local_const_fully_runtime,
    local_const_partially_comptime,
    local_const_fully_comptime,
    undefined_comptime_value,
    comptime_value,
    location_comptime_value,
    aggregate_undefined_comptime_value,
    aggregate_comptime_value,
    aggregate_location_comptime_value,
    comptime_value_field_runtime,
    comptime_value_field_comptime,
    comptime_value_elem_runtime,
    comptime_value_elem_comptime,
    // low-frequency should appear last
    compile_unit,
    module,
    module_dependency,

    const decl_size = uleb128Size(@backingInt(AbbrevCode.decl_func_generic));
    comptime {
        assert(uleb128Size(@backingInt(AbbrevCode.pad_1)) == 1);
        assert(uleb128Size(@backingInt(AbbrevCode.pad_n)) == 1);
        assert(uleb128Size(@backingInt(AbbrevCode.decl_lost)) == decl_size);
    }

    const Attr = struct {
        DeclValEnum(DW.AT),
        DeclValEnum(DW.FORM),
    };
    const common_decl_attrs = &[_]Attr{
        .{ .ZIG_parent, .ref_addr },
        .{ .decl_line, .data4 },
        .{ .decl_column, .udata },
    };
    const decl_attrs = common_decl_attrs ++ .{
        .{ .accessibility, .data1 },
        .{ .name, .strx },
    };
    const type_decl_attrs = common_decl_attrs ++ .{
        .{ .name, .strx },
    };
    const decl_specification_attrs = decl_attrs ++ &[_]Attr{
        .{ .declaration, .flag_present },
    };
    const type_decl_specification_attrs = common_decl_attrs ++ &[_]Attr{
        .{ .declaration, .flag_present },
    };
    const decl_instance_attrs = &[_]Attr{
        .{ .ZIG_parent, .ref_addr },
        .{ .specification, .ref_addr },
    };
    const type_decl_instance_attrs = decl_instance_attrs ++ .{
        .{ .name, .strx },
    };

    const abbrevs = std.EnumArray(AbbrevCode, struct {
        tag: DeclValEnum(DW.TAG),
        children: bool = false,
        attrs: []const Attr = &.{},
    }).init(.{
        .null = undefined,
        .pad_1 = .{
            .tag = .ZIG_padding,
        },
        .pad_n = .{
            .tag = .ZIG_padding,
            .attrs = &.{
                .{ .ZIG_padding, .block },
            },
        },
        .decl_lost = .{
            .tag = .ZIG_lost_declaration,
        },
        .decl_empty_incomplete_enum = .{
            .tag = .enumeration_type,
            .attrs = decl_attrs,
        },
        .decl_incomplete_enum = .{
            .tag = .enumeration_type,
            .children = true,
            .attrs = decl_attrs,
        },
        .decl_empty_enum = .{
            .tag = .enumeration_type,
            .attrs = decl_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .decl_enum = .{
            .tag = .enumeration_type,
            .children = true,
            .attrs = decl_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .type_decl_empty_incomplete_enum = .{
            .tag = .enumeration_type,
            .attrs = type_decl_attrs,
        },
        .type_decl_incomplete_enum = .{
            .tag = .enumeration_type,
            .children = true,
            .attrs = type_decl_attrs,
        },
        .type_decl_empty_enum = .{
            .tag = .enumeration_type,
            .attrs = type_decl_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .type_decl_enum = .{
            .tag = .enumeration_type,
            .children = true,
            .attrs = type_decl_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .decl_empty_incomplete_struct = .{
            .tag = .structure_type,
            .attrs = decl_attrs,
        },
        .decl_incomplete_struct = .{
            .tag = .structure_type,
            .children = true,
            .attrs = decl_attrs,
        },
        .decl_empty_struct = .{
            .tag = .structure_type,
            .attrs = decl_attrs ++ .{
                .{ .byte_size, .udata },
                .{ .alignment, .udata },
            },
        },
        .decl_struct = .{
            .tag = .structure_type,
            .children = true,
            .attrs = decl_attrs ++ .{
                .{ .byte_size, .udata },
                .{ .alignment, .udata },
            },
        },
        .type_decl_empty_incomplete_struct = .{
            .tag = .structure_type,
            .attrs = type_decl_attrs,
        },
        .type_decl_incomplete_struct = .{
            .tag = .structure_type,
            .children = true,
            .attrs = type_decl_attrs,
        },
        .type_decl_empty_struct = .{
            .tag = .structure_type,
            .attrs = type_decl_attrs ++ .{
                .{ .byte_size, .udata },
                .{ .alignment, .udata },
            },
        },
        .type_decl_struct = .{
            .tag = .structure_type,
            .children = true,
            .attrs = type_decl_attrs ++ .{
                .{ .byte_size, .udata },
                .{ .alignment, .udata },
            },
        },
        .decl_empty_packed_struct = .{
            .tag = .structure_type,
            .attrs = decl_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .decl_packed_struct = .{
            .tag = .structure_type,
            .children = true,
            .attrs = decl_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .type_decl_empty_packed_struct = .{
            .tag = .structure_type,
            .attrs = type_decl_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .type_decl_packed_struct = .{
            .tag = .structure_type,
            .children = true,
            .attrs = type_decl_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .decl_empty_incomplete_union = .{
            .tag = .union_type,
            .attrs = decl_attrs,
        },
        .decl_incomplete_union = .{
            .tag = .union_type,
            .children = true,
            .attrs = decl_attrs,
        },
        .decl_empty_union = .{
            .tag = .union_type,
            .attrs = decl_attrs ++ .{
                .{ .byte_size, .udata },
                .{ .alignment, .udata },
            },
        },
        .decl_union = .{
            .tag = .union_type,
            .children = true,
            .attrs = decl_attrs ++ .{
                .{ .byte_size, .udata },
                .{ .alignment, .udata },
            },
        },
        .type_decl_empty_incomplete_union = .{
            .tag = .union_type,
            .attrs = type_decl_attrs,
        },
        .type_decl_incomplete_union = .{
            .tag = .union_type,
            .children = true,
            .attrs = type_decl_attrs,
        },
        .type_decl_empty_union = .{
            .tag = .union_type,
            .attrs = type_decl_attrs ++ .{
                .{ .byte_size, .udata },
                .{ .alignment, .udata },
            },
        },
        .type_decl_union = .{
            .tag = .union_type,
            .children = true,
            .attrs = type_decl_attrs ++ .{
                .{ .byte_size, .udata },
                .{ .alignment, .udata },
            },
        },
        .decl_empty_packed_union = .{
            .tag = .union_type,
            .attrs = decl_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .decl_packed_union = .{
            .tag = .union_type,
            .children = true,
            .attrs = decl_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .type_decl_empty_packed_union = .{
            .tag = .union_type,
            .attrs = type_decl_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .type_decl_packed_union = .{
            .tag = .union_type,
            .children = true,
            .attrs = type_decl_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .decl_type = .{
            .tag = .imported_declaration,
            .attrs = decl_attrs ++ .{
                .{ .import, .ref_addr },
            },
        },
        .decl_const = .{
            .tag = .constant,
            .attrs = decl_attrs ++ .{
                .{ .linkage_name, .strx },
                .{ .type, .ref_addr },
                .{ .alignment, .udata },
                .{ .external, .flag },
            },
        },
        .decl_const_fully_runtime = .{
            .tag = .constant,
            .attrs = decl_attrs ++ .{
                .{ .linkage_name, .strx },
                .{ .type, .ref_addr },
                .{ .alignment, .udata },
                .{ .external, .flag },
                .{ .const_value, .block },
            },
        },
        .decl_const_partially_comptime = .{
            .tag = .constant,
            .attrs = decl_attrs ++ .{
                .{ .linkage_name, .strx },
                .{ .type, .ref_addr },
                .{ .alignment, .udata },
                .{ .external, .flag },
                .{ .const_value, .block },
                .{ .ZIG_comptime_value, .ref_addr },
            },
        },
        .decl_const_fully_comptime = .{
            .tag = .constant,
            .attrs = decl_attrs ++ .{
                .{ .linkage_name, .strx },
                .{ .type, .ref_addr },
                .{ .alignment, .udata },
                .{ .external, .flag },
                .{ .ZIG_comptime_value, .ref_addr },
            },
        },
        .decl_var = .{
            .tag = .variable,
            .attrs = decl_attrs ++ .{
                .{ .linkage_name, .strx },
                .{ .type, .ref_addr },
                .{ .location, .exprloc },
                .{ .alignment, .udata },
                .{ .external, .flag },
            },
        },
        .decl_empty_func = .{
            .tag = .subprogram,
            .attrs = decl_attrs ++ .{
                .{ .linkage_name, .strx },
                .{ .type, .ref_addr },
                .{ .low_pc, .addrx },
                .{ .high_pc, .data4 },
                .{ .alignment, .udata },
                .{ .external, .flag },
                .{ .noreturn, .flag },
            },
        },
        .decl_func = .{
            .tag = .subprogram,
            .children = true,
            .attrs = decl_attrs ++ .{
                .{ .linkage_name, .strx },
                .{ .type, .ref_addr },
                .{ .low_pc, .addrx },
                .{ .high_pc, .data4 },
                .{ .alignment, .udata },
                .{ .external, .flag },
                .{ .noreturn, .flag },
            },
        },
        .decl_empty_func_generic = .{
            .tag = .subprogram,
            .attrs = decl_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .decl_func_generic = .{
            .tag = .subprogram,
            .children = true,
            .attrs = decl_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .decl_extern_empty_func = .{
            .tag = .subprogram,
            .attrs = decl_attrs ++ .{
                .{ .linkage_name, .strx },
                .{ .type, .ref_addr },
                .{ .low_pc, .addr },
                .{ .external, .flag_present },
                .{ .noreturn, .flag },
            },
        },
        .decl_extern_func = .{
            .tag = .subprogram,
            .children = true,
            .attrs = decl_attrs ++ .{
                .{ .linkage_name, .strx },
                .{ .type, .ref_addr },
                .{ .low_pc, .addr },
                .{ .external, .flag_present },
                .{ .noreturn, .flag },
            },
        },
        .decl_specification_empty_struct = .{
            .tag = .structure_type,
            .attrs = decl_specification_attrs,
        },
        .decl_specification_struct = .{
            .tag = .structure_type,
            .children = true,
            .attrs = decl_specification_attrs,
        },
        .type_decl_specification_empty_struct = .{
            .tag = .structure_type,
            .attrs = type_decl_specification_attrs,
        },
        .type_decl_specification_struct = .{
            .tag = .structure_type,
            .children = true,
            .attrs = type_decl_specification_attrs,
        },
        .decl_specification_empty_enum = .{
            .tag = .enumeration_type,
            .attrs = decl_specification_attrs,
        },
        .decl_specification_enum = .{
            .tag = .enumeration_type,
            .children = true,
            .attrs = decl_specification_attrs,
        },
        .type_decl_specification_empty_enum = .{
            .tag = .enumeration_type,
            .attrs = type_decl_specification_attrs,
        },
        .type_decl_specification_enum = .{
            .tag = .enumeration_type,
            .children = true,
            .attrs = type_decl_specification_attrs,
        },
        .decl_specification_empty_union = .{
            .tag = .union_type,
            .attrs = decl_specification_attrs,
        },
        .decl_specification_union = .{
            .tag = .union_type,
            .children = true,
            .attrs = decl_specification_attrs,
        },
        .type_decl_specification_empty_union = .{
            .tag = .union_type,
            .attrs = type_decl_specification_attrs,
        },
        .type_decl_specification_union = .{
            .tag = .union_type,
            .children = true,
            .attrs = type_decl_specification_attrs,
        },
        .decl_specification_type = .{
            .tag = .imported_declaration,
            .attrs = decl_specification_attrs,
        },
        .decl_specification_const = .{
            .tag = .constant,
            .attrs = decl_specification_attrs,
        },
        .decl_specification_var = .{
            .tag = .variable,
            .attrs = decl_specification_attrs,
        },
        .decl_specification_func = .{
            .tag = .subprogram,
            .attrs = decl_specification_attrs,
        },
        .decl_instance_empty_incomplete_enum = .{
            .tag = .enumeration_type,
            .attrs = decl_instance_attrs,
        },
        .decl_instance_incomplete_enum = .{
            .tag = .enumeration_type,
            .children = true,
            .attrs = decl_instance_attrs,
        },
        .decl_instance_empty_enum = .{
            .tag = .enumeration_type,
            .attrs = decl_instance_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .decl_instance_enum = .{
            .tag = .enumeration_type,
            .children = true,
            .attrs = decl_instance_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .type_decl_instance_empty_enum = .{
            .tag = .enumeration_type,
            .attrs = type_decl_instance_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .type_decl_instance_enum = .{
            .tag = .enumeration_type,
            .children = true,
            .attrs = type_decl_instance_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .decl_instance_empty_incomplete_struct = .{
            .tag = .structure_type,
            .attrs = decl_instance_attrs,
        },
        .decl_instance_incomplete_struct = .{
            .tag = .structure_type,
            .children = true,
            .attrs = decl_instance_attrs,
        },
        .decl_instance_empty_struct = .{
            .tag = .structure_type,
            .attrs = decl_instance_attrs ++ .{
                .{ .byte_size, .udata },
                .{ .alignment, .udata },
            },
        },
        .decl_instance_struct = .{
            .tag = .structure_type,
            .children = true,
            .attrs = decl_instance_attrs ++ .{
                .{ .byte_size, .udata },
                .{ .alignment, .udata },
            },
        },
        .type_decl_instance_empty_struct = .{
            .tag = .structure_type,
            .attrs = type_decl_instance_attrs ++ .{
                .{ .byte_size, .udata },
                .{ .alignment, .udata },
            },
        },
        .type_decl_instance_struct = .{
            .tag = .structure_type,
            .children = true,
            .attrs = type_decl_instance_attrs ++ .{
                .{ .byte_size, .udata },
                .{ .alignment, .udata },
            },
        },
        .decl_instance_empty_packed_struct = .{
            .tag = .structure_type,
            .attrs = decl_instance_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .decl_instance_packed_struct = .{
            .tag = .structure_type,
            .children = true,
            .attrs = decl_instance_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .type_decl_instance_empty_packed_struct = .{
            .tag = .structure_type,
            .attrs = type_decl_instance_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .type_decl_instance_packed_struct = .{
            .tag = .structure_type,
            .children = true,
            .attrs = type_decl_instance_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .decl_instance_empty_incomplete_union = .{
            .tag = .union_type,
            .attrs = decl_instance_attrs,
        },
        .decl_instance_incomplete_union = .{
            .tag = .union_type,
            .children = true,
            .attrs = decl_instance_attrs,
        },
        .decl_instance_empty_union = .{
            .tag = .union_type,
            .attrs = decl_instance_attrs ++ .{
                .{ .byte_size, .udata },
                .{ .alignment, .udata },
            },
        },
        .decl_instance_union = .{
            .tag = .union_type,
            .children = true,
            .attrs = decl_instance_attrs ++ .{
                .{ .byte_size, .udata },
                .{ .alignment, .udata },
            },
        },
        .type_decl_instance_empty_union = .{
            .tag = .union_type,
            .attrs = type_decl_instance_attrs ++ .{
                .{ .byte_size, .udata },
                .{ .alignment, .udata },
            },
        },
        .type_decl_instance_union = .{
            .tag = .union_type,
            .children = true,
            .attrs = type_decl_instance_attrs ++ .{
                .{ .byte_size, .udata },
                .{ .alignment, .udata },
            },
        },
        .decl_instance_empty_packed_union = .{
            .tag = .union_type,
            .attrs = decl_instance_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .decl_instance_packed_union = .{
            .tag = .union_type,
            .children = true,
            .attrs = decl_instance_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .type_decl_instance_empty_packed_union = .{
            .tag = .union_type,
            .attrs = type_decl_instance_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .type_decl_instance_packed_union = .{
            .tag = .union_type,
            .children = true,
            .attrs = type_decl_instance_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .decl_instance_type = .{
            .tag = .imported_declaration,
            .attrs = decl_instance_attrs ++ .{
                .{ .import, .ref_addr },
            },
        },
        .decl_instance_const = .{
            .tag = .constant,
            .attrs = decl_instance_attrs ++ .{
                .{ .linkage_name, .strx },
                .{ .type, .ref_addr },
                .{ .alignment, .udata },
                .{ .external, .flag },
            },
        },
        .decl_instance_const_fully_runtime = .{
            .tag = .constant,
            .attrs = decl_instance_attrs ++ .{
                .{ .linkage_name, .strx },
                .{ .type, .ref_addr },
                .{ .alignment, .udata },
                .{ .external, .flag },
                .{ .const_value, .block },
            },
        },
        .decl_instance_const_partially_comptime = .{
            .tag = .constant,
            .attrs = decl_instance_attrs ++ .{
                .{ .linkage_name, .strx },
                .{ .type, .ref_addr },
                .{ .alignment, .udata },
                .{ .external, .flag },
                .{ .const_value, .block },
                .{ .ZIG_comptime_value, .ref_addr },
            },
        },
        .decl_instance_const_fully_comptime = .{
            .tag = .constant,
            .attrs = decl_instance_attrs ++ .{
                .{ .linkage_name, .strx },
                .{ .type, .ref_addr },
                .{ .alignment, .udata },
                .{ .external, .flag },
                .{ .ZIG_comptime_value, .ref_addr },
            },
        },
        .decl_instance_var = .{
            .tag = .variable,
            .attrs = decl_instance_attrs ++ .{
                .{ .linkage_name, .strx },
                .{ .type, .ref_addr },
                .{ .location, .exprloc },
                .{ .alignment, .udata },
                .{ .external, .flag },
            },
        },
        .decl_instance_empty_func = .{
            .tag = .subprogram,
            .attrs = decl_instance_attrs ++ .{
                .{ .linkage_name, .strx },
                .{ .type, .ref_addr },
                .{ .low_pc, .addrx },
                .{ .high_pc, .data4 },
                .{ .alignment, .udata },
                .{ .external, .flag },
                .{ .noreturn, .flag },
            },
        },
        .decl_instance_func = .{
            .tag = .subprogram,
            .children = true,
            .attrs = decl_instance_attrs ++ .{
                .{ .linkage_name, .strx },
                .{ .type, .ref_addr },
                .{ .low_pc, .addrx },
                .{ .high_pc, .data4 },
                .{ .alignment, .udata },
                .{ .external, .flag },
                .{ .noreturn, .flag },
            },
        },
        .decl_instance_empty_func_generic = .{
            .tag = .subprogram,
            .attrs = decl_instance_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .decl_instance_func_generic = .{
            .tag = .subprogram,
            .children = true,
            .attrs = decl_instance_attrs ++ .{
                .{ .type, .ref_addr },
            },
        },
        .empty_file = .{
            .tag = .structure_type,
            .attrs = &.{
                .{ .decl_file, .udata },
                .{ .name, .strx },
                .{ .declaration, .flag },
            },
        },
        .file = .{
            .tag = .structure_type,
            .children = true,
            .attrs = &.{
                .{ .decl_file, .udata },
                .{ .name, .strx },
                .{ .byte_size, .udata },
                .{ .alignment, .udata },
            },
        },
        .access = .{
            .tag = .member,
            .attrs = &.{
                .{ .name, .strx },
            },
        },
        .enum_field = .{
            .tag = .enumerator,
            .attrs = &.{
                .{ .const_value, .indirect },
                .{ .name, .strx },
            },
        },
        .generated_field = .{
            .tag = .member,
            .attrs = &.{
                .{ .name, .strx },
                .{ .type, .ref_addr },
                .{ .data_member_location, .udata },
                .{ .artificial, .flag_present },
            },
        },
        .field = .{
            .tag = .member,
            .attrs = &.{
                .{ .name, .strx },
                .{ .type, .ref_addr },
                .{ .data_member_location, .udata },
                .{ .alignment, .udata },
            },
        },
        .field_default_fully_runtime = .{
            .tag = .member,
            .attrs = &.{
                .{ .name, .strx },
                .{ .type, .ref_addr },
                .{ .data_member_location, .udata },
                .{ .alignment, .udata },
                .{ .default_value, .block },
            },
        },
        .field_default_partially_comptime = .{
            .tag = .member,
            .attrs = &.{
                .{ .name, .strx },
                .{ .type, .ref_addr },
                .{ .data_member_location, .udata },
                .{ .alignment, .udata },
                .{ .default_value, .block },
                .{ .ZIG_comptime_value, .ref_addr },
            },
        },
        .field_default_fully_comptime = .{
            .tag = .member,
            .attrs = &.{
                .{ .name, .strx },
                .{ .type, .ref_addr },
                .{ .data_member_location, .udata },
                .{ .alignment, .udata },
                .{ .ZIG_comptime_value, .ref_addr },
            },
        },
        .field_comptime = .{
            .tag = .member,
            .attrs = &.{
                .{ .const_expr, .flag_present },
                .{ .name, .strx },
                .{ .type, .ref_addr },
            },
        },
        .field_comptime_fully_runtime = .{
            .tag = .member,
            .attrs = &.{
                .{ .const_expr, .flag_present },
                .{ .name, .strx },
                .{ .type, .ref_addr },
                .{ .const_value, .block },
            },
        },
        .field_comptime_partially_comptime = .{
            .tag = .member,
            .attrs = &.{
                .{ .const_expr, .flag_present },
                .{ .name, .strx },
                .{ .type, .ref_addr },
                .{ .const_value, .block },
                .{ .ZIG_comptime_value, .ref_addr },
            },
        },
        .field_comptime_fully_comptime = .{
            .tag = .member,
            .attrs = &.{
                .{ .const_expr, .flag_present },
                .{ .name, .strx },
                .{ .type, .ref_addr },
                .{ .ZIG_comptime_value, .ref_addr },
            },
        },
        .packed_field = .{
            .tag = .member,
            .attrs = &.{
                .{ .name, .strx },
                .{ .type, .ref_addr },
                .{ .data_bit_offset, .udata },
            },
        },
        .tagged_union = .{
            .tag = .variant_part,
            .children = true,
            .attrs = &.{
                .{ .discr, .ref_addr },
            },
        },
        .tagged_union_field = .{
            .tag = .variant,
            .children = true,
            .attrs = &.{
                .{ .discr_value, .indirect },
            },
        },
        .tagged_union_default_field = .{
            .tag = .variant,
            .children = true,
        },
        .void_type = .{
            .tag = .unspecified_type,
            .attrs = &.{
                .{ .name, .strx },
            },
        },
        .numeric_type = .{
            .tag = .base_type,
            .attrs = &.{
                .{ .name, .strx },
                .{ .encoding, .data1 },
                .{ .bit_size, .udata },
                .{ .byte_size, .udata },
                .{ .alignment, .udata },
            },
        },
        .inferred_error_set_type = .{
            .tag = .typedef,
            .attrs = &.{
                .{ .name, .strx },
                .{ .type, .ref_addr },
            },
        },
        .ptr_type = .{
            .tag = .pointer_type,
            .attrs = &.{
                .{ .name, .strx },
                .{ .address_class, .data1 },
                .{ .type, .ref_addr },
            },
        },
        .ptr_sentinel_type = .{
            .tag = .pointer_type,
            .attrs = &.{
                .{ .name, .strx },
                .{ .ZIG_sentinel, .block },
                .{ .address_class, .data1 },
                .{ .type, .ref_addr },
            },
        },
        .is_aligned = .{
            .tag = .typedef,
            .attrs = &.{
                .{ .alignment, .udata },
                .{ .type, .ref_addr },
            },
        },
        .is_const = .{
            .tag = .const_type,
            .attrs = &.{
                .{ .type, .ref_addr },
            },
        },
        .is_volatile = .{
            .tag = .volatile_type,
            .attrs = &.{
                .{ .type, .ref_addr },
            },
        },
        .array_type = .{
            .tag = .array_type,
            .children = true,
            .attrs = &.{
                .{ .name, .strx },
                .{ .type, .ref_addr },
            },
        },
        .array_sentinel_type = .{
            .tag = .array_type,
            .children = true,
            .attrs = &.{
                .{ .name, .strx },
                .{ .ZIG_sentinel, .block },
                .{ .type, .ref_addr },
            },
        },
        .vector_type = .{
            .tag = .array_type,
            .children = true,
            .attrs = &.{
                .{ .name, .strx },
                .{ .type, .ref_addr },
                .{ .GNU_vector, .flag_present },
            },
        },
        .array_index = .{
            .tag = .subrange_type,
            .attrs = &.{
                .{ .lower_bound, .udata },
            },
        },
        .array_len = .{
            .tag = .subrange_type,
            .attrs = &.{
                .{ .type, .ref_addr },
                .{ .count, .udata },
            },
        },
        .empty_func_type = .{
            .tag = .subroutine_type,
            .attrs = &.{
                .{ .name, .strx },
                .{ .calling_convention, .data1 },
                .{ .type, .ref_addr },
            },
        },
        .func_type = .{
            .tag = .subroutine_type,
            .children = true,
            .attrs = &.{
                .{ .name, .strx },
                .{ .calling_convention, .data1 },
                .{ .type, .ref_addr },
            },
        },
        .param = .{
            .tag = .formal_parameter,
            .attrs = &.{
                .{ .name, .strx },
                .{ .type, .ref_addr },
            },
        },
        .unnamed_param = .{
            .tag = .formal_parameter,
            .attrs = &.{
                .{ .type, .ref_addr },
            },
        },
        .is_var_args = .{
            .tag = .unspecified_parameters,
        },
        .generated_empty_enum_type = .{
            .tag = .enumeration_type,
            .attrs = &.{
                .{ .name, .strx },
                .{ .type, .ref_addr },
            },
        },
        .generated_enum_type = .{
            .tag = .enumeration_type,
            .children = true,
            .attrs = &.{
                .{ .name, .strx },
                .{ .type, .ref_addr },
            },
        },
        .generated_empty_struct_type = .{
            .tag = .structure_type,
            .attrs = &.{
                .{ .name, .strx },
                .{ .declaration, .flag },
            },
        },
        .generated_struct_type = .{
            .tag = .structure_type,
            .children = true,
            .attrs = &.{
                .{ .name, .strx },
                .{ .byte_size, .udata },
                .{ .alignment, .udata },
            },
        },
        .generated_union_type = .{
            .tag = .union_type,
            .children = true,
            .attrs = &.{
                .{ .name, .strx },
                .{ .byte_size, .udata },
                .{ .alignment, .udata },
            },
        },
        .capture_specification = .{
            .tag = .template_value_parameter,
            .attrs = &.{
                .{ .name, .strx },
            },
        },
        .comptime_capture = .{
            .tag = .template_value_parameter,
            .attrs = &.{
                .{ .type, .ref_addr },
            },
        },
        .comptime_capture_runtime = .{
            .tag = .template_value_parameter,
            .attrs = &.{
                .{ .type, .ref_addr },
                .{ .const_value, .block },
            },
        },
        .comptime_capture_partially_comptime = .{
            .tag = .template_value_parameter,
            .attrs = &.{
                .{ .type, .ref_addr },
                .{ .const_value, .block },
                .{ .ZIG_comptime_value, .ref_addr },
            },
        },
        .comptime_capture_fully_comptime = .{
            .tag = .template_value_parameter,
            .attrs = &.{
                .{ .type, .ref_addr },
                .{ .ZIG_comptime_value, .ref_addr },
            },
        },
        .runtime_capture = .{
            .tag = .template_type_parameter,
            .attrs = &.{
                .{ .type, .ref_addr },
            },
        },
        .nav_capture = .{
            .tag = .template_value_parameter,
            .attrs = &.{
                .{ .location, .exprloc },
            },
        },
        .builtin_extern_empty_func = .{
            .tag = .subprogram,
            .attrs = &.{
                .{ .ZIG_parent, .ref_addr },
                .{ .linkage_name, .strx },
                .{ .type, .ref_addr },
                .{ .low_pc, .addr },
                .{ .external, .flag_present },
                .{ .noreturn, .flag },
            },
        },
        .builtin_extern_func = .{
            .tag = .subprogram,
            .children = true,
            .attrs = &.{
                .{ .ZIG_parent, .ref_addr },
                .{ .linkage_name, .strx },
                .{ .type, .ref_addr },
                .{ .low_pc, .addr },
                .{ .external, .flag_present },
                .{ .noreturn, .flag },
            },
        },
        .builtin_extern_var = .{
            .tag = .variable,
            .attrs = &.{
                .{ .ZIG_parent, .ref_addr },
                .{ .linkage_name, .strx },
                .{ .type, .ref_addr },
                .{ .location, .exprloc },
                .{ .alignment, .udata },
                .{ .external, .flag_present },
            },
        },
        .empty_block = .{
            .tag = .lexical_block,
            .attrs = &.{
                .{ .low_pc, .addr },
                .{ .high_pc, .data4 },
            },
        },
        .block = .{
            .tag = .lexical_block,
            .children = true,
            .attrs = &.{
                .{ .low_pc, .addr },
                .{ .high_pc, .data4 },
            },
        },
        .empty_inlined_func = .{
            .tag = .inlined_subroutine,
            .attrs = &.{
                .{ .abstract_origin, .ref_addr },
                .{ .ZIG_call_line_relative, .udata },
                .{ .call_column, .udata },
                .{ .low_pc, .addr },
                .{ .high_pc, .data4 },
            },
        },
        .inlined_func = .{
            .tag = .inlined_subroutine,
            .children = true,
            .attrs = &.{
                .{ .abstract_origin, .ref_addr },
                .{ .ZIG_call_line_relative, .udata },
                .{ .call_column, .udata },
                .{ .low_pc, .addr },
                .{ .high_pc, .data4 },
            },
        },
        .arg = .{
            .tag = .formal_parameter,
            .attrs = &.{
                .{ .name, .strx },
                .{ .type, .ref_addr },
                .{ .location, .exprloc },
            },
        },
        .unnamed_arg = .{
            .tag = .formal_parameter,
            .attrs = &.{
                .{ .type, .ref_addr },
                .{ .location, .exprloc },
            },
        },
        .comptime_arg = .{
            .tag = .formal_parameter,
            .attrs = &.{
                .{ .const_expr, .flag_present },
                .{ .name, .strx },
                .{ .type, .ref_addr },
            },
        },
        .comptime_arg_fully_runtime = .{
            .tag = .formal_parameter,
            .attrs = &.{
                .{ .const_expr, .flag_present },
                .{ .name, .strx },
                .{ .type, .ref_addr },
                .{ .const_value, .block },
            },
        },
        .comptime_arg_partially_comptime = .{
            .tag = .formal_parameter,
            .attrs = &.{
                .{ .const_expr, .flag_present },
                .{ .name, .strx },
                .{ .type, .ref_addr },
                .{ .const_value, .block },
                .{ .ZIG_comptime_value, .ref_addr },
            },
        },
        .comptime_arg_fully_comptime = .{
            .tag = .formal_parameter,
            .attrs = &.{
                .{ .const_expr, .flag_present },
                .{ .name, .strx },
                .{ .type, .ref_addr },
                .{ .ZIG_comptime_value, .ref_addr },
            },
        },
        .unnamed_comptime_arg = .{
            .tag = .formal_parameter,
            .attrs = &.{
                .{ .const_expr, .flag_present },
                .{ .type, .ref_addr },
            },
        },
        .unnamed_comptime_arg_fully_runtime = .{
            .tag = .formal_parameter,
            .attrs = &.{
                .{ .const_expr, .flag_present },
                .{ .type, .ref_addr },
                .{ .const_value, .block },
            },
        },
        .unnamed_comptime_arg_partially_comptime = .{
            .tag = .formal_parameter,
            .attrs = &.{
                .{ .const_expr, .flag_present },
                .{ .type, .ref_addr },
                .{ .const_value, .block },
                .{ .ZIG_comptime_value, .ref_addr },
            },
        },
        .unnamed_comptime_arg_fully_comptime = .{
            .tag = .formal_parameter,
            .attrs = &.{
                .{ .const_expr, .flag_present },
                .{ .type, .ref_addr },
                .{ .ZIG_comptime_value, .ref_addr },
            },
        },
        .extern_param = .{
            .tag = .formal_parameter,
            .attrs = &.{
                .{ .type, .ref_addr },
            },
        },
        .local_var = .{
            .tag = .variable,
            .attrs = &.{
                .{ .name, .strx },
                .{ .type, .ref_addr },
                .{ .location, .exprloc },
            },
        },
        .local_const = .{
            .tag = .constant,
            .attrs = &.{
                .{ .name, .strx },
                .{ .type, .ref_addr },
            },
        },
        .local_const_fully_runtime = .{
            .tag = .constant,
            .attrs = &.{
                .{ .name, .strx },
                .{ .type, .ref_addr },
                .{ .const_value, .block },
            },
        },
        .local_const_partially_comptime = .{
            .tag = .constant,
            .attrs = &.{
                .{ .name, .strx },
                .{ .type, .ref_addr },
                .{ .const_value, .block },
                .{ .ZIG_comptime_value, .ref_addr },
            },
        },
        .local_const_fully_comptime = .{
            .tag = .constant,
            .attrs = &.{
                .{ .name, .strx },
                .{ .type, .ref_addr },
                .{ .ZIG_comptime_value, .ref_addr },
            },
        },
        .undefined_comptime_value = .{
            .tag = .ZIG_comptime_value,
            .attrs = &.{
                .{ .type, .ref_addr },
            },
        },
        .aggregate_undefined_comptime_value = .{
            .tag = .ZIG_comptime_value,
            .children = true,
            .attrs = &.{
                .{ .type, .ref_addr },
            },
        },
        .comptime_value = .{
            .tag = .ZIG_comptime_value,
            .attrs = &.{
                .{ .type, .ref_addr },
                .{ .const_value, .indirect },
            },
        },
        .aggregate_comptime_value = .{
            .tag = .ZIG_comptime_value,
            .children = true,
            .attrs = &.{
                .{ .type, .ref_addr },
                .{ .const_value, .indirect },
            },
        },
        .location_comptime_value = .{
            .tag = .ZIG_comptime_value,
            .attrs = &.{
                .{ .type, .ref_addr },
                .{ .location, .exprloc },
            },
        },
        .aggregate_location_comptime_value = .{
            .tag = .ZIG_comptime_value,
            .children = true,
            .attrs = &.{
                .{ .type, .ref_addr },
                .{ .location, .exprloc },
            },
        },
        .comptime_value_field_runtime = .{
            .tag = .member,
            .attrs = &.{
                .{ .name, .strx },
                .{ .const_value, .block },
            },
        },
        .comptime_value_field_comptime = .{
            .tag = .member,
            .attrs = &.{
                .{ .name, .strx },
                .{ .ZIG_comptime_value, .ref_addr },
            },
        },
        .comptime_value_elem_runtime = .{
            .tag = .member,
            .attrs = &.{
                .{ .const_value, .block },
            },
        },
        .comptime_value_elem_comptime = .{
            .tag = .member,
            .attrs = &.{
                .{ .ZIG_comptime_value, .ref_addr },
            },
        },
        .compile_unit = .{
            .tag = .compile_unit,
            .children = true,
            .attrs = &.{
                .{ .language, .data1 },
                .{ .base_types, .ref_addr },
                .{ .stmt_list, .sec_offset },
                .{ .addr_base, .sec_offset },
                .{ .rnglists_base, .sec_offset },
                .{ .str_offsets_base, .sec_offset },
                .{ .producer, .strx1 },
                .{ .comp_dir, .line_strp },
                .{ .name, .line_strp },
                .{ .ranges, .rnglistx },
                .{ .use_UTF8, .flag_present },
            },
        },
        .module = .{
            .tag = .module,
            .children = true,
            .attrs = &.{
                .{ .name, .strx },
                .{ .ranges, .rnglistx },
            },
        },
        .module_dependency = .{
            .tag = .imported_module,
            .attrs = &.{
                .{ .name, .strx },
                .{ .import, .ref_addr },
            },
        },
    });
};

pub fn uleb128Size(value: anytype) u32 {
    var buf: [std.atomic.cache_line]u8 = undefined;
    var dw: std.Io.Writer.Discarding = .init(&buf);
    dw.writer.writeUleb128(value) catch unreachable;
    return @intCast(dw.fullCount());
}

pub fn sleb128Size(value: anytype) u32 {
    var buf: [std.atomic.cache_line]u8 = undefined;
    var dw: std.Io.Writer.Discarding = .init(&buf);
    dw.writer.writeSleb128(value) catch unreachable;
    return @intCast(dw.fullCount());
}

const assert = std.debug.assert;
const codegen = @import("../codegen.zig");
const Compilation = @import("../Compilation.zig");
const dev = @import("../dev.zig");
const DW = std.dwarf;
const Dwarf = @This();
const InternPool = @import("../InternPool.zig");
const link = @import("../link.zig");
const log = std.log.scoped(.dwarf);
const Module = @import("../Module.zig");
const std = @import("std");
const target_info = @import("../target.zig");
const Type = @import("../Type.zig");
const Value = @import("../Value.zig");
const Zcu = @import("../Zcu.zig");

const Elf = @This();

const builtin = @import("builtin");
const native_endian = builtin.cpu.arch.endian();

const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const log = std.log.scoped(.link);

const codegen = @import("../codegen.zig");
const Compilation = @import("../Compilation.zig");
const InternPool = @import("../InternPool.zig");
const link = @import("../link.zig");
const MappedFile = @import("MappedFile.zig");
const target_util = @import("../target.zig");
const tracy = @import("../tracy.zig");
const Type = @import("../Type.zig");
const Value = @import("../Value.zig");
const Zcu = @import("../Zcu.zig");

base: link.File,
options: link.File.OpenOptions,
mf: MappedFile,
ni: Node.Known,
nodes: std.MultiArrayList(Node),
shdrs: std.ArrayList(Section),
phdrs: std.ArrayList(MappedFile.Node.Index),
shndx: struct {
    got: Section.Index,
    /// Always `.UNDEF` on some targets (e.g. SPARC).
    got_plt: Section.Index,
    plt: Section.Index,
    /// Only created for x86 targets; `.UNDEF` everywhere else.
    plt_sec: Section.Index,
    dynsym: Section.Index,
    dynstr: Section.Index,
    dynamic: Section.Index,
    tdata: Section.Index,
    rela_dyn: Section.Index,
    rela_plt: Section.Index,
    // These sections are created only as needed, and are initially `.UNDEF`.
    init_array: Section.Index,
    fini_array: Section.Index,
    preinit_array: Section.Index,
},
symtab: std.ArrayList(Symbol),
globals: struct {
    strong_def: std.array_hash_map.Auto(String(.strtab), Symbol.Global),
    weak_def: std.array_hash_map.Auto(String(.strtab), Symbol.Global),
    strong_undef: std.array_hash_map.Auto(String(.strtab), Symbol.Global),
    weak_undef: std.array_hash_map.Auto(String(.strtab), Symbol.Global),
},
/// Key is the name of an undef global for which we have created a "copy relocation" (`R_*_COPY`).
copied_globals: std.array_hash_map.Auto(String(.strtab), struct {
    node: MappedFile.Node.Index,
    /// The index of this global's runtime relocation in `.rela.dyn`.
    rela_index: Section.RelaIndex,
}),
/// Key is the name of an undef global for which we would *like* to create a copy relocation
/// (`R_*_COPY`), but cannot because we have not seen an appropriate definition in a linked DSO yet.
///
/// Therefore, if, when scanning a DSO input, we discover a definition for one of these symbols, we
/// will remove it from this map and call `maybeAddCopyRelocation`.
want_copied_globals: std.array_hash_map.Auto(String(.strtab), void),
/// Key is a node which is a valid `Symbol.node` value, value is the name of the first global symbol
/// in that node. That symbol is the head of a linked list: see `Symbol.Global.next_in_node`.
///
/// Value is never `.empty`.
///
/// We use a separate hash map for this data rather than storing it in `navs` etc to save memory,
/// because the vast majority of nodes which can export global symbols actually will not.
node_global_symbols: std.array_hash_map.Auto(MappedFile.Node.Index, String(.strtab)),
/// Contains all globals symbols defined in any needed DSO. This map serves three purposes:
///
/// * If we discover an undefined reference to one of these symbols, we know whether the symbol has
///   type `STT_FUNC`, in which case we will create a PLT entry.
///
/// * If we discover a direct relocation (i.e. no GOT or PLT indirection) targeting one of these
///   symbols, we know whether the symbol has type `STT_OBJECT` and we know its size and alignment,
///   so we can emit a copy relocation for that symbol instead of using a text relocation.
///
/// * When emitting a dynamic executable, we can detect which undefined references are resolved by a
///   linked DSO, so can emit "undefined global symbol" errors for any other undefined references.
dso_globals: std.array_hash_map.Auto(String(.strtab), struct {
    type: std.elf.STT,
    size: u64,
    /// This is usually unnecessary, but if a symbol is given a copy relocation (`R_*_COPY`) and so
    /// becomes a part of the executable's address space despite being defined by a different DSO,
    /// we need to know its alignment requirement so that we don't break other code. This isn't
    /// actually stored on the symbol---instead we compute a maximum alignment from the alignment of
    /// the section containing the symbol, and the symbol's offset within the section. I know this
    /// sounds like a terrible hack, but it is *genuinely* how you're supposed to do this. Copy
    /// relocations suck.
    alignment: std.mem.Alignment,
}),
shstrtab: StringTable,
strtab: StringTable,
dynstr: StringTable,

/// Indices map 1--1 to indices into the actual `.got` section.
///
/// Value is the output relocation in `.rela.dyn` for the GOT entry.
got: std.array_hash_map.Auto(GotKey, Section.RelaIndex.Optional),
/// Key is the name of a global.
///
/// Indices map 1--1 to indices into the actual `.got.plt` section. These also equal indices into
/// the relocations in `.rela.plt`, because every PLT entry has one output relocation (if a runtime
/// relocation is no longer necessary, then neither is the corresponding PLT entry!).
///
/// PLT entries in this map may be "dead", meaning the PLT entry has been deemed unnecessary so is
/// available for reuse---see `Elf.pltEntryIsDead`. Such entries must not be targeted by relocs.
plt: std.array_hash_map.Auto(String(.strtab), void),
/// The `.plt` section contains zero or more symbol relocations starting at this index.
plt_first_symbol_reloc: SymbolReloc.Index,
/// The `.dynamic` section contains zero or more symbol relocations starting at this index.
dynamic_first_symbol_reloc: SymbolReloc.Index,

needed: std.array_hash_map.Auto(String(.dynstr), void),
inputs: std.ArrayList(struct {
    path: std.Build.Cache.Path,
    member: ?[]const u8,
    file_symbol: Symbol.LocalIndex,
}),
input_sections: std.ArrayList(InputSection),
input_section_pending_index: u32,
navs: std.array_hash_map.Auto(InternPool.Nav.Index, struct {
    lsi: Symbol.LocalIndex,
    /// The start index of the contiguous sequence of symbol relocations in this NAV.
    first_symbol_reloc: SymbolReloc.Index,
    /// The start index of the contiguous sequence of GOT relocations in this NAV.
    first_got_reloc: GotReloc.Index,
}),
uavs: std.array_hash_map.Auto(InternPool.Index, struct {
    lsi: Symbol.LocalIndex,
    /// The start index of the contiguous sequence of symbol relocations in this UAV.
    first_symbol_reloc: SymbolReloc.Index,
    // No `first_got_reloc` field because a UAV never contains GOT relocations.
}),
lazy: std.EnumArray(link.File.LazySymbol.Kind, struct {
    map: std.array_hash_map.Auto(InternPool.Index, struct {
        lsi: Symbol.LocalIndex,
        /// The start index of the contiguous sequence of symbol relocations in this lazy code/data.
        first_symbol_reloc: SymbolReloc.Index,
        /// The start index of the contiguous sequence of GOT relocations in this lazy code/data.
        first_got_reloc: GotReloc.Index,
    }),
    pending_index: u32,
}),
pending_uavs: std.ArrayList(Node.UavMapIndex),
symbol_relocs: std.ArrayList(SymbolReloc),
got_relocs: std.ArrayList(GotReloc),
/// Set of relocations which must be re-applied if the size of the TLS segment changes.
tls_size_symbol_relocs: std.array_hash_map.Auto(SymbolReloc.Index, void),
/// Index matches the index into `shdrs`.
section_by_name: std.array_hash_map.Auto(String(.shstrtab), void),
/// Key is the name of a global symbol which has been moved to a new symtab index. Any relocation
/// entries which target that symbol must be updated to reference the correct symbol index.
///
/// When emitting a relocatable (`ET_REL`), this refers to the index in `.symtab`. Otherwise, it
/// refers to the index in `.dynsym`.
changed_symtab_index: std.array_hash_map.Auto(String(.strtab), void),
/// Counts how many relocations are currently in `.rela.dyn` which would require a `DT_TEXTREL`
/// entry in the `.dynamic` section. This allows adding `DT_TEXTREL` to the output `.dynamic`
/// section in `flush` only when it is actually necessary. See also `nodeWantsDsoRelocation`.
textrel_count: u32,

const_prog_node: std.Progress.Node,
synth_prog_node: std.Progress.Node,
input_prog_node: std.Progress.Node,

const Error = link.Error || error{MappedFileIo};

const Node = union(enum) {
    file,
    ehdr,
    shdr,
    segment: u32,
    /// The section '.plt' may contain relocations via `elf.plt_first_symbol_reloc`.
    ///
    /// The section '.dynamic' may contain relocations via `elf.dynamic_first_symbol_reloc`.
    section: Section.Index,
    /// May contain relocations.
    input_section: InputSection.Index,
    /// Value is the name of a global which has an entry in `elf.copied_globals`, so, a global for
    /// which we have emitted a copy relocation.
    ///
    /// TODO it would be better to emit these into `.bss` or `.bss.rel.ro`, once we support those.
    ///
    /// TODO: currently, the `elf.copied_globals` entry may not be there---this case exists because
    /// `MappedFile` does not (yet?) support deleting nodes. See logic in `setGlobalSymbolValue`.
    copied_global: String(.strtab),
    /// May contain relocations.
    nav: NavMapIndex,
    /// May contain relocations.
    uav: UavMapIndex,
    /// May contain relocations.
    lazy_code: LazyMapRef.Index(.code),
    /// May contain relocations.
    lazy_const_data: LazyMapRef.Index(.const_data),

    pub const InputIndex = enum(u32) {
        _,

        pub fn path(ii: InputIndex, elf: *const Elf) std.Build.Cache.Path {
            return elf.inputs.items[@intFromEnum(ii)].path;
        }

        pub fn member(ii: InputIndex, elf: *const Elf) ?[]const u8 {
            return elf.inputs.items[@intFromEnum(ii)].member;
        }

        pub fn fileSymbol(ii: InputIndex, elf: *const Elf) Symbol.LocalIndex {
            return elf.inputs.items[@intFromEnum(ii)].file_symbol;
        }

        pub fn localSymbolRange(ii: InputIndex, elf: *Elf) [2]Symbol.LocalIndex {
            if (@intFromEnum(ii) + 1 < elf.inputs.items.len) {
                const next_ii: InputIndex = @enumFromInt(@intFromEnum(ii) + 1);
                return .{ ii.fileSymbol(elf), next_ii.fileSymbol(elf) };
            } else {
                const local_symbols_len = switch (elf.shdrPtr(.symtab)) {
                    inline else => |shdr| elf.targetLoad(&shdr.info),
                };
                return .{ ii.fileSymbol(elf), @enumFromInt(local_symbols_len) };
            }
        }
    };

    pub const NavMapIndex = enum(u32) {
        _,

        pub fn navIndex(nmi: NavMapIndex, elf: *const Elf) InternPool.Nav.Index {
            return elf.navs.keys()[@intFromEnum(nmi)];
        }

        pub fn symbol(nmi: NavMapIndex, elf: *const Elf) Symbol.LocalIndex {
            return elf.navs.values()[@intFromEnum(nmi)].lsi;
        }

        fn firstSymbolReloc(nmi: NavMapIndex, elf: *const Elf) SymbolReloc.Index {
            return elf.navs.values()[@intFromEnum(nmi)].first_symbol_reloc;
        }
        fn firstGotReloc(nmi: NavMapIndex, elf: *const Elf) GotReloc.Index {
            return elf.navs.values()[@intFromEnum(nmi)].first_got_reloc;
        }
    };

    pub const UavMapIndex = enum(u32) {
        _,

        pub fn uavValue(umi: UavMapIndex, elf: *const Elf) InternPool.Index {
            return elf.uavs.keys()[@intFromEnum(umi)];
        }

        pub fn symbol(umi: UavMapIndex, elf: *const Elf) Symbol.LocalIndex {
            return elf.uavs.values()[@intFromEnum(umi)].lsi;
        }

        fn firstSymbolReloc(umi: UavMapIndex, elf: *const Elf) SymbolReloc.Index {
            return elf.uavs.values()[@intFromEnum(umi)].first_symbol_reloc;
        }
        fn firstGotReloc(umi: UavMapIndex, elf: *const Elf) GotReloc.Index {
            _ = umi;
            _ = elf;
            return .none;
        }
    };

    pub const LazyMapRef = struct {
        kind: link.File.LazySymbol.Kind,
        index: u32,

        pub fn Index(comptime kind: link.File.LazySymbol.Kind) type {
            return enum(u32) {
                _,

                pub fn ref(lmi: @This()) LazyMapRef {
                    return .{ .kind = kind, .index = @intFromEnum(lmi) };
                }

                pub fn lazySymbol(lmi: @This(), elf: *const Elf) link.File.LazySymbol {
                    return lmi.ref().lazySymbol(elf);
                }

                pub fn symbol(lmi: @This(), elf: *const Elf) Symbol.LocalIndex {
                    return lmi.ref().symbol(elf);
                }

                fn firstSymbolReloc(lmi: @This(), elf: *const Elf) SymbolReloc.Index {
                    return elf.lazy.getPtrConst(kind).map.values()[@intFromEnum(lmi)].first_symbol_reloc;
                }
                fn firstGotReloc(lmi: @This(), elf: *const Elf) GotReloc.Index {
                    return elf.lazy.getPtrConst(kind).map.values()[@intFromEnum(lmi)].first_got_reloc;
                }
            };
        }

        pub fn lazySymbol(lmr: LazyMapRef, elf: *const Elf) link.File.LazySymbol {
            return .{ .kind = lmr.kind, .ty = elf.lazy.getPtrConst(lmr.kind).map.keys()[lmr.index] };
        }

        pub fn symbol(lmr: LazyMapRef, elf: *const Elf) Symbol.LocalIndex {
            return elf.lazy.getPtrConst(lmr.kind).map.values()[lmr.index].lsi;
        }
    };

    pub const Known = struct {
        comptime file: MappedFile.Node.Index = .root,
        comptime ehdr: MappedFile.Node.Index = @enumFromInt(1),
        comptime shdr: MappedFile.Node.Index = @enumFromInt(2),
        comptime rodata: MappedFile.Node.Index = @enumFromInt(3),
        comptime phdr: MappedFile.Node.Index = @enumFromInt(4),
        comptime text: MappedFile.Node.Index = @enumFromInt(5),
        comptime data: MappedFile.Node.Index = @enumFromInt(6),
        comptime data_rel_ro: MappedFile.Node.Index = @enumFromInt(7),

        tls: MappedFile.Node.Index,
    };

    comptime {
        if (!std.debug.runtime_safety) std.debug.assert(@sizeOf(Node) == 8);
    }

    /// In this linker implementation, `link.File.AtomId` is a type-erased `MappedFile.Node.Index`.
    fn toAtom(ni: MappedFile.Node.Index) link.File.AtomId {
        return @enumFromInt(@intFromEnum(ni));
    }
    /// In this linker implementation, `link.File.AtomId` is a type-erased `MappedFile.Node.Index`.
    fn fromAtom(atom: link.File.AtomId) MappedFile.Node.Index {
        return @enumFromInt(@intFromEnum(atom));
    }
};

const InputSection = struct {
    input: Node.InputIndex,
    file_location: MappedFile.Node.FileLocation,
    vaddr: u64,
    /// The node corresponding to this input section.
    node: MappedFile.Node.Index,
    /// The start index of the contiguous sequence of symbol relocations in this input section.
    first_symbol_reloc: SymbolReloc.Index,
    /// The start index of the contiguous sequence of GOT relocations in this input section.
    first_got_reloc: GotReloc.Index,

    const Index = enum(u32) {
        _,

        fn ptr(isi: InputSection.Index, elf: *Elf) *InputSection {
            return &elf.input_sections.items[@intFromEnum(isi)];
        }

        fn ptrConst(isi: InputSection.Index, elf: *const Elf) *const InputSection {
            return &elf.input_sections.items[@intFromEnum(isi)];
        }

        fn input(isi: InputSection.Index, elf: *const Elf) Node.InputIndex {
            return isi.ptrConst(elf).input;
        }

        fn fileLocation(isi: InputSection.Index, elf: *const Elf) MappedFile.Node.FileLocation {
            return isi.ptrConst(elf).file_location;
        }

        fn node(isi: InputSection.Index, elf: *const Elf) MappedFile.Node.Index {
            return isi.ptrConst(elf).node;
        }
    };
};

const Section = struct {
    /// The node corresponding to this section.
    ni: MappedFile.Node.Index,
    /// A symbol which is exactly at the start of this section.
    ///
    /// If the section does not have flag `std.elf.SHF.ALLOC`, this is `.null`.
    lsi: Symbol.LocalIndex,
    rela: union {
        /// This field is active if and only if this section is *not* a `SHT_RELA` section.
        ///
        /// This field's value refers to this section's corresponding relocation section, if it
        /// currently has one. If this section does not currently have a relocation section, the
        /// value is `.UNDEF`.
        ///
        /// This field is only ever non-`.UNDEF` when emitting a relocatable (`ET_REL`). While there
        /// are also output relocations in DSOs, they are all placed in the `.rela.dyn`
        /// (`elf.shdnx.rela_dyn`) and `.rela.plt` (`elf.shndx.rela_plt`) sections, rather than
        /// having separate relocation sections for each section.
        shndx: Section.Index,

        /// This field is active if and only if this section *is* a `SHT_RELA` section.
        ///
        /// This is the head of a single-linked list of free `ElfN.Rela` entries in this section.
        /// Entries in this list have `info.type` set to `R_*_NONE`, have `info.sym` set to 0, and
        /// have `offset` set to `@enumFromInt(next)` where `next` is `RelaIndex.Optional`. Also,
        /// `addend` is set to the length of the list starting from this point; so the last node in
        /// the list has `addend = 1`, the one before it has `addend = 2`, etc. This is so that the
        /// head node always contains the current length of the list.
        ///
        /// It would be okay to store these values (in the `offset` and `addend` fields) in the
        /// compiler's host endianness, because they will never be read by other tooling. However,
        /// we nonetheless use target endianness, because using host endianness would introduce an
        /// unnecessary dependency of the output binary on the compiler's host architecture.
        free_head: RelaIndex.Optional,
    },

    const RelaIndex = enum(u32) {
        none,
        _,

        const Optional = enum(u32) {
            none = std.math.maxInt(u32),
            _,

            fn unwrap(opt: RelaIndex.Optional) ?RelaIndex {
                return switch (opt) {
                    .none => null,
                    _ => @enumFromInt(@intFromEnum(opt)),
                };
            }
        };

        fn toOptional(i: RelaIndex) RelaIndex.Optional {
            return @enumFromInt(@intFromEnum(i));
        }
    };

    pub const Index = enum(Tag) {
        UNDEF = std.elf.SHN_UNDEF,
        LIVEPATCH = reserve(std.elf.SHN_LIVEPATCH),
        ABS = reserve(std.elf.SHN_ABS),
        COMMON = reserve(std.elf.SHN_COMMON),

        symtab = 1,
        shstrtab,
        strtab,
        rodata,
        text,
        data,
        data_rel_ro,

        _,

        pub const Tag = u32;

        pub const LORESERVE: Index = .fromSection(std.elf.SHN_LORESERVE);
        pub const HIRESERVE: Index = .fromSection(std.elf.SHN_HIRESERVE);
        comptime {
            assert(@intFromEnum(HIRESERVE) == std.math.maxInt(Tag));
        }

        fn reserve(sec: std.elf.Section) Tag {
            assert(sec >= std.elf.SHN_LORESERVE and sec <= std.elf.SHN_HIRESERVE);
            return @as(Tag, std.math.maxInt(Tag) - std.elf.SHN_HIRESERVE) + sec;
        }

        pub fn fromSection(sec: std.elf.Section) Index {
            return switch (sec) {
                std.elf.SHN_UNDEF...std.elf.SHN_LORESERVE - 1 => @enumFromInt(sec),
                std.elf.SHN_LORESERVE...std.elf.SHN_HIRESERVE => @enumFromInt(reserve(sec)),
            };
        }
        pub fn toSection(s: Index) ?std.elf.Section {
            return switch (@intFromEnum(s)) {
                std.elf.SHN_UNDEF...std.elf.SHN_LORESERVE - 1 => |sec| @intCast(sec),
                std.elf.SHN_LORESERVE...reserve(std.elf.SHN_LORESERVE) - 1 => null,
                reserve(std.elf.SHN_LORESERVE)...reserve(std.elf.SHN_HIRESERVE) => |sec| @intCast(
                    sec - reserve(std.elf.SHN_LORESERVE) + std.elf.SHN_LORESERVE,
                ),
            };
        }

        fn get(s: Index, elf: *Elf) *Section {
            return &elf.shdrs.items[@intFromEnum(s)];
        }

        fn name(s: Index, elf: *Elf) String(.shstrtab) {
            return switch (elf.shdrPtr(s)) {
                inline else => |shdr| @enumFromInt(elf.targetLoad(&shdr.name)),
            };
        }

        fn vaddr(s: Index, elf: *Elf) u64 {
            return switch (elf.shdrPtr(s)) {
                inline else => |shdr| elf.targetLoad(&shdr.addr),
            };
        }

        fn flags(s: Index, elf: *Elf) std.elf.SHF {
            return switch (elf.shdrPtr(s)) {
                inline else => |shdr| elf.targetLoad(&shdr.flags).shf,
            };
        }

        fn rename(shndx: Index, elf: *Elf, new_name: []const u8) Error!void {
            const shstrtab_entry = try elf.string(.shstrtab, new_name);
            switch (elf.shdrPtr(shndx)) {
                inline else => |shdr| elf.targetStore(&shdr.name, @intFromEnum(shstrtab_entry)),
            }
        }

        /// Asserts that `rela_shndx` is a `SHT_RELA` section and ensures that its node has enough
        /// unused space to hold `n` additional `ElfN.Rela` entries.
        fn relaEnsureAdditionalCapacity(rela_shndx: Index, elf: *Elf, n: usize) Error!void {
            const node = rela_shndx.get(elf).ni;
            const need_size: u64 = switch (elf.shdrPtr(rela_shndx)) {
                inline else => |shdr, class| need_size: {
                    assert(elf.targetLoad(&shdr.type) == .RELA);
                    const cur_size = elf.targetLoad(&shdr.size);
                    const ent_size = @sizeOf(class.ElfN().Rela);
                    assert(elf.targetLoad(&shdr.entsize) == ent_size);
                    const free_len: u32 = free_len: {
                        const opt_free_head = rela_shndx.get(elf).rela.free_head;
                        const free_head = opt_free_head.unwrap() orelse break :free_len 0;
                        const relas: []const class.ElfN().Rela = @ptrCast(@alignCast(
                            node.slice(&elf.mf)[0..@intCast(cur_size)],
                        ));
                        const free_len = elf.targetLoad(&relas[@intFromEnum(free_head)].addend);
                        assert(free_len > 0);
                        break :free_len @intCast(free_len);
                    };
                    const need_additional = n -| free_len;
                    break :need_size cur_size + need_additional * ent_size;
                },
            };
            try elf.ensureNodeSize(node, need_size);
        }

        /// Asserts that `rela_shndx` is a `SHT_RELA` section and deletes the `ElfN.Rela` entry at
        /// the given `index` in it. The entry is added to the free-list for reuse later. Asserts
        /// that the relocation entry at `index` is not already free.
        fn relaDeleteOne(rela_shndx: Index, elf: *Elf, index: RelaIndex) void {
            switch (elf.shdrPtr(rela_shndx)) {
                inline else => |shdr, class| {
                    assert(elf.targetLoad(&shdr.type) == .RELA);
                    assert(elf.targetLoad(&shdr.entsize) == @sizeOf(class.ElfN().Rela));
                    const relas: []class.ElfN().Rela = @ptrCast(@alignCast(
                        rela_shndx.get(elf).ni.slice(&elf.mf)[0..@intCast(elf.targetLoad(&shdr.size))],
                    ));
                    const opt_free_head = rela_shndx.get(elf).rela.free_head;
                    const old_free_len: u32 = free_len: {
                        const free_head = opt_free_head.unwrap() orelse break :free_len 0;
                        const free_len = elf.targetLoad(&relas[@intFromEnum(free_head)].addend);
                        assert(free_len > 0);
                        break :free_len @intCast(free_len);
                    };
                    const none_reloc_type = MachineRelocType.none(elf).unwrap(elf);
                    {
                        const old_type = elf.targetLoad(&relas[@intFromEnum(index)].info).type;
                        assert(old_type != none_reloc_type); // bug: `index` is already in the free-list
                    }
                    relas[@intFromEnum(index)] = .{
                        .offset = @intFromEnum(opt_free_head), // next
                        .info = .{
                            .type = @intCast(none_reloc_type),
                            .sym = 0,
                        },
                        .addend = @intCast(old_free_len + 1), // list length
                    };
                    if (elf.targetEndian() != native_endian) {
                        std.mem.byteSwapAllFields(class.ElfN().Rela, &relas[@intFromEnum(index)]);
                    }
                },
            }
            rela_shndx.get(elf).rela.free_head = index.toOptional();
        }

        /// Asserts that `rela_shndx` is a `SHT_RELA` section and adds a new `ElfN.Rela` entry to it
        /// with the given field values. Returns the index of the populated entry. Asserts that
        /// capacity for this operation was already guaranteed using `relaEnsureAdditionalCapacity`.
        fn relaAddOneAssumeCapacity(rela_shndx: Index, elf: *Elf, opts: struct {
            type: MachineRelocType,
            offset: u64,
            /// This is a raw `u32` because whether this is an index into `.symtab` (`Symbol.Index`)
            /// or an index into `.dynsym` is contextual.
            raw_sym_index: u32,
            addend: i64,
        }) RelaIndex {
            switch (elf.shdrPtr(rela_shndx)) {
                inline else => |shdr, class| {
                    assert(elf.targetLoad(&shdr.type) == .RELA);
                    const ent_size = @sizeOf(class.ElfN().Rela);
                    assert(elf.targetLoad(&shdr.entsize) == ent_size);
                    const new_index: RelaIndex = if (rela_shndx.get(elf).rela.free_head.unwrap()) |free_head| new_index: {
                        const relas: []class.ElfN().Rela = @ptrCast(@alignCast(
                            rela_shndx.get(elf).ni.slice(&elf.mf)[0..@intCast(elf.targetLoad(&shdr.size))],
                        ));
                        const next: RelaIndex.Optional = @enumFromInt(elf.targetLoad(
                            &relas[@intFromEnum(free_head)].offset,
                        ));
                        rela_shndx.get(elf).rela.free_head = next;

                        const old_free_len: u32 = @intCast(
                            elf.targetLoad(&relas[@intFromEnum(free_head)].addend),
                        );
                        const new_free_len: u32 = if (next.unwrap()) |i| @intCast(
                            elf.targetLoad(&relas[@intFromEnum(i)].addend),
                        ) else 0;
                        assert(new_free_len == old_free_len - 1);

                        break :new_index free_head;
                    } else new_index: {
                        const old_size = elf.targetLoad(&shdr.size);
                        const new_size = old_size + ent_size;
                        elf.targetStore(&shdr.size, new_size);
                        if (rela_shndx == elf.shndx.rela_dyn) {
                            elf.updateDynamicEntry(std.elf.DT_RELASZ, new_size);
                        } else if (rela_shndx == elf.shndx.rela_plt) {
                            elf.updateDynamicEntry(std.elf.DT_PLTRELSZ, new_size);
                        }
                        break :new_index @enumFromInt(@divExact(old_size, ent_size));
                    };
                    const relas: []class.ElfN().Rela = @ptrCast(@alignCast(
                        rela_shndx.get(elf).ni.slice(&elf.mf)[0..@intCast(elf.targetLoad(&shdr.size))],
                    ));
                    relas[@intFromEnum(new_index)] = .{
                        .offset = @intCast(opts.offset),
                        .info = .{
                            .type = @intCast(opts.type.unwrap(elf)),
                            .sym = @intCast(opts.raw_sym_index),
                        },
                        .addend = @intCast(opts.addend),
                    };
                    if (elf.targetEndian() != native_endian) {
                        std.mem.byteSwapAllFields(class.ElfN().Rela, &relas[@intFromEnum(new_index)]);
                    }
                    return new_index;
                },
            }
        }

        /// Asserts that `rela_shndx` is a `SHT_RELA` section and updates the `info.sym` field of
        /// the `ElfN.Rela` entry at the given index. As with `relaAddOneAssumeCapacity`, the symbol
        /// index is a raw `u32`, because it may be an index into `.symtab` or an index into
        /// `.dynsym`. Asserts that `index` is not in the free-list (i.e. is not deleted).
        fn relaUpdateSym(rela_shndx: Index, elf: *Elf, index: RelaIndex, raw_sym_index: u32) void {
            switch (elf.shdrPtr(rela_shndx)) {
                inline else => |shdr, class| {
                    assert(elf.targetLoad(&shdr.type) == .RELA);
                    assert(elf.targetLoad(&shdr.entsize) == @sizeOf(class.ElfN().Rela));
                    const relas: []class.ElfN().Rela = @ptrCast(@alignCast(
                        rela_shndx.get(elf).ni.slice(&elf.mf)[0..@intCast(elf.targetLoad(&shdr.size))],
                    ));
                    const rela_info = elf.targetLoad(&relas[@intFromEnum(index)].info);
                    {
                        const none_reloc_type = MachineRelocType.none(elf).unwrap(elf);
                        assert(rela_info.type != none_reloc_type); // bug: `index` is in the free-list
                    }
                    elf.targetStore(&relas[@intFromEnum(index)].info, .{
                        .type = rela_info.type,
                        .sym = @intCast(raw_sym_index),
                    });
                },
            }
        }

        /// Asserts that `rela_shndx` is a `SHT_RELA` section and updates the `offset` field of the
        /// `ElfN.Rela` entry at the given index. Asserts that `index` is not in the free-list (i.e.
        /// it is not deleted).
        fn relaSetOffset(rela_shndx: Index, elf: *Elf, index: RelaIndex, new_offset: u64) void {
            switch (elf.shdrPtr(rela_shndx)) {
                inline else => |shdr, class| {
                    assert(elf.targetLoad(&shdr.type) == .RELA);
                    assert(elf.targetLoad(&shdr.entsize) == @sizeOf(class.ElfN().Rela));
                    const relas: []class.ElfN().Rela = @ptrCast(@alignCast(
                        rela_shndx.get(elf).ni.slice(&elf.mf)[0..@intCast(elf.targetLoad(&shdr.size))],
                    ));
                    {
                        const rela_info = elf.targetLoad(&relas[@intFromEnum(index)].info);
                        const none_reloc_type = MachineRelocType.none(elf).unwrap(elf);
                        assert(rela_info.type != none_reloc_type); // bug: `index` is in the free-list
                    }
                    elf.targetStore(&relas[@intFromEnum(index)].offset, @intCast(new_offset));
                },
            }
        }

        /// Asserts that `rela_shndx` is a `SHT_RELA` section and updates the `offset` field of the
        /// `ElfN.Rela` entry at the given index, by subtracting `old_base` and adding `new_base`.
        /// Asserts that `index` is not in the free-list (i.e. it is not deleted).
        fn relaAdjustOffset(rela_shndx: Index, elf: *Elf, index: RelaIndex, old_base: u64, new_base: u64) void {
            switch (elf.shdrPtr(rela_shndx)) {
                inline else => |shdr, class| {
                    assert(elf.targetLoad(&shdr.type) == .RELA);
                    assert(elf.targetLoad(&shdr.entsize) == @sizeOf(class.ElfN().Rela));
                    const relas: []class.ElfN().Rela = @ptrCast(@alignCast(
                        rela_shndx.get(elf).ni.slice(&elf.mf)[0..@intCast(elf.targetLoad(&shdr.size))],
                    ));
                    {
                        const rela_info = elf.targetLoad(&relas[@intFromEnum(index)].info);
                        const none_reloc_type = MachineRelocType.none(elf).unwrap(elf);
                        assert(rela_info.type != none_reloc_type); // bug: `index` is in the free-list
                    }
                    const old_offset = elf.targetLoad(&relas[@intFromEnum(index)].offset);
                    elf.targetStore(&relas[@intFromEnum(index)].offset, @intCast(
                        old_offset - old_base + new_base,
                    ));
                },
            }
        }

        /// Asserts that `rela_shndx` is a `SHT_RELA` section, and asserts that `index` refers to an
        /// `R_*_RELATIVE` relocation inside of it; then, updates that relocation's addend (which is
        /// an address in this DSO without the runtime load offset applied) to the given value.
        fn relaSetRelativeOffset(rela_shndx: Index, elf: *Elf, index: RelaIndex, new_addend: u64) void {
            switch (elf.shdrPtr(rela_shndx)) {
                inline else => |shdr, class| {
                    assert(elf.targetLoad(&shdr.type) == .RELA);
                    assert(elf.targetLoad(&shdr.entsize) == @sizeOf(class.ElfN().Rela));
                    const relas: []class.ElfN().Rela = @ptrCast(@alignCast(
                        rela_shndx.get(elf).ni.slice(&elf.mf)[0..@intCast(elf.targetLoad(&shdr.size))],
                    ));
                    {
                        const rela_info = elf.targetLoad(&relas[@intFromEnum(index)].info);
                        const none_reloc_type = MachineRelocType.none(elf).unwrap(elf);
                        assert(rela_info.type != none_reloc_type); // bug: `index` is in the free-list
                    }
                    const unsigned: class.ElfN().Addr = @intCast(new_addend);
                    elf.targetStore(&relas[@intFromEnum(index)].addend, @bitCast(unsigned));
                },
            }
        }
    };
};

/// Identifies a single entry in the GOT.
const GotKey = union(enum) {
    /// The entry is a reserved word, initialized to zero. `initHeaders` will add as many of these
    /// as the target machine ABI requires.
    ///
    /// This `u32` value exists to allow reserving multiple words with distinct keys.
    reserved: u32,

    /// Value is the address of the given symbol.
    symbol: Symbol.Id,

    /// Value is the signed offset of the given symbol from the TLS pointer.
    tpoff: Symbol.Id,

    /// Value is the TLS module ID of the DSO we are creating.
    ///
    /// Used for the first of the two GOT entries generated by a TLSLD relocation.
    tlsld0,
    /// Value is always 0.
    ///
    /// Used for the second of the two GOT entries generated by a TLSLD relocation.
    tlsld1,

    /// Value is the TLS module ID for the given STT_TLS symbol.
    ///
    /// Used for the first of the two GOT entries generated by a TLSGD relocation.
    tlsgd0: Symbol.Id,
    /// Value is the offset of the given STT_TLS symbol from the base of the per-module TLS area.
    ///
    /// Used for the second of the two GOT entries generated by a TLSGD relocation.
    tlsgd1: Symbol.Id,
};

/// A relocation targeting a particular GOT entry.
const GotReloc = struct {
    /// The node containing this relocation. Possible values are:
    /// * An input section
    /// * A section
    /// * A NAV, UAV, or lazy code/data
    /// * `.none`, if this relocation was deleted (in which case it should be ignored)
    node: MappedFile.Node.Index,
    /// The offset of the relocation inside of `node`.
    offset: u64,
    target: GotKey,
    addend: i64,
    type: GotReloc.Type,

    const deleted: GotReloc = .{
        .node = .none,
        .offset = undefined,
        .target = undefined,
        .addend = undefined,
        .type = undefined,
    };

    const Type = enum(u8) {
        offset32,
        offset64,
        rel32,
        rel64,

        larch_rel32_hi20,
        larch_rel64_lo20,
        larch_rel64_hi12,
        larch_abs32_lo12,
        larch_abs32_hi20,
        larch_abs64_lo20,
        larch_abs64_hi12,

        sparc_10,
        sparc_13,
        sparc_22,
        sparc_ldm_hi22,
        sparc_ldm_lo10,
        sparc_op_hix22,
        sparc_op_lox10,
    };

    const Index = enum(u32) {
        none = std.math.maxInt(u32),
        _,

        fn get(index: GotReloc.Index, elf: *Elf) *GotReloc {
            return &elf.got_relocs.items[@intFromEnum(index)];
        }
    };

    fn apply(reloc: *const GotReloc, elf: *Elf) void {
        assert(elf.ehdrField(.type) != .REL);
        if (reloc.node == .none) return; // deleted
        if (reloc.node.hasMoved(&elf.mf) or elf.shndx.got.get(elf).ni.hasMoved(&elf.mf)) {
            // There's no point applying the relocation now, because it will be re-applied by
            // `flushMoved` at some point anyway.
            return;
        }
        const node_vaddr: u64 = switch (elf.getNode(reloc.node)) {
            .file => unreachable,
            .ehdr => unreachable,
            .shdr => unreachable,
            .segment => unreachable,
            .copied_global => unreachable,
            .section => |shndx| shndx.vaddr(elf),
            .input_section => |isi| isi.ptrConst(elf).vaddr,
            inline .nav,
            .uav,
            .lazy_code,
            .lazy_const_data,
            => |i| Symbol.Id.local(i.symbol(elf)).value(elf),
        };
        const dest_vaddr = node_vaddr + reloc.offset;
        const dest_slice = reloc.node.slice(&elf.mf)[@intCast(reloc.offset)..];
        const target_endian = elf.targetEndian();
        const got_vaddr = elf.shndx.got.vaddr(elf);
        const got_index: u64 = elf.got.getIndex(reloc.target).?;
        const got_offset: u64 = switch (elf.identClass()) {
            .NONE, _ => unreachable,
            inline else => |class| @sizeOf(class.ElfN().Addr) * got_index,
        };
        const addend: u64 = @bitCast(reloc.addend);
        switch (reloc.type) {
            .offset64 => std.mem.writeInt(
                u64,
                dest_slice[0..8],
                got_offset +% addend,
                target_endian,
            ),
            .offset32 => std.mem.writeInt(
                u32,
                dest_slice[0..4],
                @intCast(got_offset +% addend),
                target_endian,
            ),
            .rel64 => std.mem.writeInt(
                i64,
                dest_slice[0..8],
                @bitCast(got_vaddr +% got_offset +% addend -% dest_vaddr),
                target_endian,
            ),
            .rel32 => std.mem.writeInt(
                i32,
                dest_slice[0..4],
                @intCast(@as(i64, @bitCast(got_vaddr +% got_offset +% addend -% dest_vaddr))),
                target_endian,
            ),

            .larch_rel32_hi20 => {
                assert(elf.ehdrField(.machine) == .LOONGARCH);
                const target_value = got_vaddr +% got_offset +% addend;
                link.loongarch.writeJ20(dest_slice[0..4], link.loongarch.toPcalaHi20(target_value, dest_vaddr));
            },
            .larch_rel64_lo20 => {
                assert(elf.ehdrField(.machine) == .LOONGARCH);
                const target_value = got_vaddr +% got_offset +% addend;
                link.loongarch.writeJ20(dest_slice[0..4], link.loongarch.toPcala64Lo20(target_value, dest_vaddr));
            },
            .larch_rel64_hi12 => {
                assert(elf.ehdrField(.machine) == .LOONGARCH);
                const target_value = got_vaddr +% got_offset +% addend;
                link.loongarch.writeK12(dest_slice[0..4], link.loongarch.toPcala64Hi12(target_value, dest_vaddr));
            },
            .larch_abs32_lo12 => {
                assert(elf.ehdrField(.machine) == .LOONGARCH);
                const target_value = got_vaddr +% got_offset +% addend;
                link.loongarch.writeK12(dest_slice[0..4], @truncate(target_value));
            },
            .larch_abs32_hi20 => {
                assert(elf.ehdrField(.machine) == .LOONGARCH);
                const target_value = got_vaddr +% got_offset +% addend;
                link.loongarch.writeJ20(dest_slice[0..4], @truncate(target_value >> 12));
            },
            .larch_abs64_lo20 => {
                assert(elf.ehdrField(.machine) == .LOONGARCH);
                const target_value = got_vaddr +% got_offset +% addend;
                link.loongarch.writeJ20(dest_slice[0..4], @truncate(target_value >> 32));
            },
            .larch_abs64_hi12 => {
                assert(elf.ehdrField(.machine) == .LOONGARCH);
                const target_value = got_vaddr +% got_offset +% addend;
                link.loongarch.writeK12(dest_slice[0..4], @truncate(target_value >> 52));
            },

            .sparc_10 => {
                const dest_ptr: *link.sparc.reloc.Simm13 = @ptrCast(@alignCast(dest_slice));
                var result = elf.targetLoad(dest_ptr);
                result.simm13 = @as(u10, @truncate(got_offset));
                elf.targetStore(dest_ptr, result);
            },
            .sparc_13 => {
                const dest_ptr: *link.sparc.reloc.Simm13 = @ptrCast(@alignCast(dest_slice));
                var result = elf.targetLoad(dest_ptr);
                result.simm13 = @truncate(got_offset);
                elf.targetStore(dest_ptr, result);
            },
            .sparc_22 => {
                const dest_ptr: *link.sparc.reloc.Simm22 = @ptrCast(@alignCast(dest_slice));
                var result = elf.targetLoad(dest_ptr);
                result.simm22 = @truncate(got_offset >> 10);
                elf.targetStore(dest_ptr, result);
            },
            .sparc_ldm_hi22 => {
                const dest_ptr: *link.sparc.reloc.Simm22 = @ptrCast(@alignCast(dest_slice));
                var result = elf.targetLoad(dest_ptr);
                result.simm22 = @truncate((got_offset +% addend) >> 10);
                elf.targetStore(dest_ptr, result);
            },
            .sparc_ldm_lo10 => {
                const dest_ptr: *link.sparc.reloc.Simm13 = @ptrCast(@alignCast(dest_slice));
                var result = elf.targetLoad(dest_ptr);
                result.simm13 = @as(u10, @truncate(got_offset +% addend));
                elf.targetStore(dest_ptr, result);
            },
            .sparc_op_hix22 => {
                const dest_ptr: *link.sparc.reloc.Imm22 = @ptrCast(@alignCast(dest_slice));
                var result = elf.targetLoad(dest_ptr);
                result.imm22 = @truncate(got_offset >> 10);
                elf.targetStore(dest_ptr, result);
            },
            .sparc_op_lox10 => {
                const dest_ptr: *link.sparc.reloc.Imm13 = @ptrCast(@alignCast(dest_slice));
                var result = elf.targetLoad(dest_ptr);
                result.imm13 = @as(u10, @truncate(got_offset));
                elf.targetStore(dest_ptr, result);
            },
        }
    }
};

pub const MachineRelocType = union {
    AARCH64: std.elf.R_AARCH64,
    LOONGARCH: std.elf.R_LARCH,
    PPC64: std.elf.R_PPC64,
    RISCV: std.elf.R_RISCV,
    SPARC: std.elf.R_SPARC,
    X86_64: std.elf.R_X86_64,

    pub fn none(elf: *Elf) MachineRelocType {
        return switch (elf.ehdrField(.machine)) {
            else => unreachable,
            .AARCH64 => .{ .AARCH64 = .NONE },
            .LOONGARCH => .{ .LOONGARCH = .NONE },
            .PPC64 => .{ .PPC64 = .NONE },
            .RISCV => .{ .RISCV = .NONE },
            .SPARCV9 => .{ .SPARC = .NONE },
            .X86_64 => .{ .X86_64 = .NONE },
        };
    }
    pub fn copy(elf: *Elf) MachineRelocType {
        return switch (elf.ehdrField(.machine)) {
            else => unreachable,
            .AARCH64 => .{ .AARCH64 = .COPY },
            .LOONGARCH => .{ .LOONGARCH = .COPY },
            .PPC64 => .{ .PPC64 = .COPY },
            .RISCV => .{ .RISCV = .COPY },
            .SPARCV9 => .{ .SPARC = .COPY },
            .X86_64 => .{ .X86_64 = .COPY },
        };
    }
    pub fn relative(elf: *Elf) MachineRelocType {
        return switch (elf.ehdrField(.machine)) {
            else => unreachable,
            .AARCH64 => .{ .AARCH64 = .RELATIVE },
            .LOONGARCH => .{ .LOONGARCH = .RELATIVE },
            .PPC64 => .{ .PPC64 = .RELATIVE },
            .RISCV => .{ .RISCV = .RELATIVE },
            .SPARCV9 => .{ .SPARC = .RELATIVE },
            .X86_64 => .{ .X86_64 = .RELATIVE },
        };
    }
    pub fn jumpSlot(elf: *Elf) MachineRelocType {
        return switch (elf.ehdrField(.machine)) {
            else => unreachable,
            .AARCH64 => .{ .AARCH64 = .JUMP_SLOT },
            .LOONGARCH => .{ .LOONGARCH = .JUMP_SLOT },
            .PPC64 => .{ .PPC64 = .JMP_SLOT },
            .RISCV => .{ .RISCV = .JUMP_SLOT },
            .SPARCV9 => .{ .SPARC = .JMP_SLOT },
            .X86_64 => .{ .X86_64 = .JUMP_SLOT },
        };
    }
    pub fn globDat(elf: *Elf) MachineRelocType {
        return switch (elf.ehdrField(.machine)) {
            else => unreachable,
            .AARCH64 => .{ .AARCH64 = .GLOB_DAT },
            .LOONGARCH => .{ .LOONGARCH = if (elf.identClass() == .@"64") .@"64" else .@"32" },
            .PPC64 => .{ .PPC64 = .GLOB_DAT },
            .RISCV => .{ .RISCV = if (elf.identClass() == .@"64") .@"64" else .@"32" },
            .SPARCV9 => .{ .SPARC = .GLOB_DAT },
            .X86_64 => .{ .X86_64 = .GLOB_DAT },
        };
    }
    pub fn dtpOffAddr(elf: *Elf) MachineRelocType {
        return switch (elf.ehdrField(.machine)) {
            else => unreachable,
            .LOONGARCH => .{ .LOONGARCH = if (elf.identClass() == .@"64") .TLS_DTPREL64 else .TLS_DTPREL32 },
            .PPC64 => .{ .PPC64 = .DTPREL64 },
            .RISCV => .{ .RISCV = if (elf.identClass() == .@"64") .TLS_DTPREL64 else .TLS_DTPREL32 },
            .SPARCV9 => .{ .SPARC = if (elf.identClass() == .@"64") .TLS_DTPOFF64 else .TLS_DTPOFF32 },
            .X86_64 => .{ .X86_64 = if (elf.identClass() == .@"64") .DTPOFF64 else .DTPOFF32 },
        };
    }
    pub fn absAddr(elf: *Elf) MachineRelocType {
        return switch (elf.ehdrField(.machine)) {
            else => unreachable,
            .AARCH64 => .{ .AARCH64 = if (elf.identClass() == .@"64") .ABS64 else .P32_ABS32 },
            .LOONGARCH => .{ .LOONGARCH = if (elf.identClass() == .@"64") .@"64" else .@"32" },
            .PPC64 => .{ .PPC64 = .ADDR64 },
            .RISCV => .{ .RISCV = if (elf.identClass() == .@"64") .@"64" else .@"32" },
            .SPARCV9 => .{ .SPARC = if (elf.identClass() == .@"64") .@"64" else .@"32" },
            .X86_64 => .{ .X86_64 = if (elf.identClass() == .@"64") .@"64" else .@"32" },
        };
    }
    pub fn sizeAddr(elf: *Elf) MachineRelocType {
        return switch (elf.ehdrField(.machine)) {
            else => unreachable,
            .SPARCV9 => .{ .SPARC = if (elf.identClass() == .@"64") .SIZE64 else .SIZE32 },
            .X86_64 => .{ .X86_64 = .SIZE64 },
        };
    }

    pub fn wrap(int: u32, elf: *Elf) MachineRelocType {
        return switch (elf.ehdrField(.machine)) {
            else => unreachable,
            .SPARCV9 => .{ .SPARC = @enumFromInt(int) },
            inline .AARCH64,
            .LOONGARCH,
            .PPC64,
            .RISCV,
            .X86_64,
            => |machine| @unionInit(MachineRelocType, @tagName(machine), @enumFromInt(int)),
        };
    }
    pub fn unwrap(rt: MachineRelocType, elf: *Elf) u32 {
        return switch (elf.ehdrField(.machine)) {
            else => unreachable,
            .SPARCV9 => @intFromEnum(rt.SPARC),
            inline .AARCH64,
            .LOONGARCH,
            .PPC64,
            .RISCV,
            .X86_64,
            => |machine| @intFromEnum(@field(rt, @tagName(machine))),
        };
    }
};

/// A relocation targeting an arbitrary symbol with a fixed addend.
const SymbolReloc = struct {
    /// The node containing this relocation. Possible values are:
    /// * An input section
    /// * A section
    /// * A NAV, UAV, or lazy code/data
    node: MappedFile.Node.Index,
    /// The offset of the relocation inside of `node`.
    offset: u64,
    /// A symbol used to compute the relocated value. Precise meaning depends on `@"type"`.
    target: Symbol.Id,
    /// A signed constant used to compute the relocated value. Precise meaning depends on `@"type"`.
    addend: i64,
    /// Specifies how to apply the relocation.
    type: SymbolReloc.Type,
    /// Forms a linked list of all symbol relocations with the same `target`. This list exists so
    /// that all relocations targeting a particular symbol can be re-applied if that symbol moves.
    /// Doubly-linked so that relocations can be removed.
    next: SymbolReloc.Index,
    /// Back-reference in a doubly-linked list---see `next`.
    prev: SymbolReloc.Index,
    /// If this relocation has a corresponding output relocation, this is its index within the
    /// appropriate SHT_RELA section (see `relaSection`). If there is no output relocation
    /// corresponding to this relocation, this is `.none`.
    ///
    /// If we are producing a relocatable, this field is always populated, because all relocations
    /// are emitted as output relocations.
    ///
    /// If we are producing a DSO, this field is populated if this relocation requires a runtime
    /// relocation entry. The entry will be removed if we discover a definition which allows us to
    /// statically resolve the relocation.
    rela_index: Section.RelaIndex.Optional,

    /// Determines the section in which this relocation will be placed if it is outstanding.
    ///
    /// When producing a relocatable (ET_REL), the relocation section is `Section.rela.shndx` for
    /// the section of `node`, and this function asserts that the aforementioned `rela.shndx` field
    /// is populated.
    ///
    /// When producing a DSO, the relocation section is always `.rela.dyn`. It is not `.rela.plt`
    /// because relocations in the GOTPLT are handled specially, without `SymbolReloc` entries.
    fn relaSection(sr: *const SymbolReloc, elf: *Elf) Section.Index {
        const shndx = switch (elf.ehdrField(.type)) {
            .NONE, .CORE, _ => unreachable,
            .REL => elf.getNodeShndx(sr.node).get(elf).rela.shndx,
            .EXEC, .DYN => elf.shndx.rela_dyn,
        };
        assert(shndx != .UNDEF);
        return shndx;
    }

    const Index = enum(u32) {
        none = std.math.maxInt(u32),
        _,

        fn get(index: SymbolReloc.Index, elf: *Elf) *SymbolReloc {
            return &elf.symbol_relocs.items[@intFromEnum(index)];
        }
    };

    const Type = enum {
        /// This input relocation is being directly forwarded to an `ElfN.Rela` entry in the output
        /// file. `rela_index` is guaranteed to be populated. The ELF relocation type is available
        /// in the `ElfN.Rela` entry.
        ///
        /// If we are emitting a relocatable (`ET_REL`), all symbol relocs use this type (since we
        /// do not apply any relocations ourselves). Otherwise, no symbol relocs use this type.
        write_rela,

        /// Address relative to the DSO base. Like `.abs64` but does not emit `R_*_RELATIVE` relocs.
        ///
        /// This is only used targeting local symbols so can always be statically resolved.
        dsorel64,
        /// Address relative to the DSO base. Like `.abs32` but does not emit `R_*_RELATIVE` relocs.
        ///
        /// This is only used targeting local symbols so can always be statically resolved.
        dsorel32,

        abs8,
        abs16,
        abs32,
        abs32s,
        abs64,
        rel8,
        rel16,
        rel32,
        rel64,
        pltabs32,
        pltabs64,
        pltrel32,
        pltrel64,
        dtpoff32,
        dtpoff64,
        tpoff32,
        tpoff64,
        size32,
        size64,

        larch_abs32_lo12,
        larch_rel32_hi20,
        larch_rel64_lo20,
        larch_rel64_hi12,
        larch_branch_rel18,
        larch_branch_rel23,
        larch_branch_rel28,
        larch_call_rel38,
        larch_tpoff32_lo12,
        larch_tpoff32_hi20,
        larch_tpoff64_lo20,
        larch_tpoff64_hi12,

        sparc_wdisp30,
        sparc_pc10,
        sparc_pc22,
        sparc_wplt30,
        sparc_h44,
        sparc_m44,
        sparc_l44,
        sparc_ldo_hix22,
        sparc_ldo_lox10,
        sparc_le_hix22,
        sparc_le_lox10,

        fn dependsOnTlsSize(t: SymbolReloc.Type) bool {
            return switch (t) {
                .tpoff32,
                .tpoff64,
                => true,

                .larch_tpoff32_lo12,
                .larch_tpoff32_hi20,
                .larch_tpoff64_lo20,
                .larch_tpoff64_hi12,
                => true,

                .sparc_le_hix22,
                .sparc_le_lox10,
                => true,

                else => false,
            };
        }

        fn isAbsAddr(t: SymbolReloc.Type, elf: *const Elf) bool {
            return switch (elf.identClass()) {
                .NONE, _ => unreachable,
                .@"32" => switch (t) {
                    .abs32,
                    .pltabs32,
                    => true,
                    else => false,
                },
                .@"64" => switch (t) {
                    .abs64,
                    .pltabs64,
                    => true,
                    else => false,
                },
            };
        }
    };

    fn apply(reloc: *const SymbolReloc, elf: *Elf) void {
        assert(elf.ehdrField(.type) != .REL);
        assert(reloc.node != .none);

        if (reloc.node.hasMoved(&elf.mf) or reloc.target.hasMoved(elf)) {
            // There's no point applying the relocation now, because it will be re-applied by
            // `flushMoved` at some point anyway.
            return;
        }

        if (reloc.rela_index.unwrap()) |rela_index| switch (elf.classifySymbolValue(reloc.target)) {
            .static => unreachable,
            .dynamic => return, // the relocation happens at runtime
            .static_relative => {
                // We have emitted an R_*_RELATIVE relocation to help lower an abs32/abs64 reloc.
                // This is a simplified version of the general relocation handling logic, where we
                // know we're using '.abs64' or '.abs32' (matching the ELF ident class).
                const value = type: switch (reloc.type) {
                    .abs32,
                    .abs64,
                    => reloc.target.value(elf) +% @as(u64, @bitCast(reloc.addend)),
                    .pltabs32,
                    .pltabs64,
                    => value: {
                        const plt_index = switch (reloc.target.unwrap()) {
                            .local => continue :type .abs32,
                            .global => |name| elf.plt.getIndex(name) orelse continue :type .abs32,
                        };
                        if (elf.pltEntryIsDead(plt_index)) continue :type .abs32;
                        const plt_shndx: Section.Index, const plt_header_entries: u64, const plt_entry_size: u64 = switch (elf.ehdrField(.machine)) {
                            else => |machine| @panic(@tagName(machine)),
                            .SPARCV9 => .{ elf.shndx.plt, 4, 32 },
                            .X86_64 => .{ elf.shndx.plt_sec, 0, 16 },
                        };
                        const plt_entry = plt_shndx.vaddr(elf) +% (plt_header_entries + plt_index) * plt_entry_size;
                        break :value plt_entry +% @as(u64, @bitCast(reloc.addend));
                    },
                    else => unreachable,
                };
                elf.shndx.rela_dyn.relaSetRelativeOffset(elf, rela_index, value);
                return;
            },
        };
        const node_vaddr: u64 = switch (elf.getNode(reloc.node)) {
            .file => unreachable,
            .ehdr => unreachable,
            .shdr => unreachable,
            .segment => unreachable,
            .copied_global => unreachable,
            .section => |shndx| shndx.vaddr(elf),
            .input_section => |isi| isi.ptrConst(elf).vaddr,
            inline .nav,
            .uav,
            .lazy_code,
            .lazy_const_data,
            => |i| Symbol.Id.local(i.symbol(elf)).value(elf),
        };
        const dest_vaddr = node_vaddr + reloc.offset;
        const dest_slice = reloc.node.slice(&elf.mf)[@intCast(reloc.offset)..];
        const target_endian = elf.targetEndian();
        const sym_value: u64 = reloc.target.value(elf);
        const sym_size: u64 = switch (elf.symPtr(reloc.target.index(elf))) {
            inline else => |target_sym| elf.targetLoad(&target_sym.size),
        };
        const target_value = sym_value +% @as(u64, @bitCast(reloc.addend));
        type: switch (reloc.type) {
            .write_rela => unreachable,
            .abs64, .dsorel64 => std.mem.writeInt(
                u64,
                dest_slice[0..8],
                target_value,
                target_endian,
            ),
            .abs32, .dsorel32 => std.mem.writeInt(
                u32,
                dest_slice[0..4],
                @intCast(target_value),
                target_endian,
            ),
            .abs32s => std.mem.writeInt(
                i32,
                dest_slice[0..4],
                @intCast(@as(i64, @bitCast(target_value))),
                target_endian,
            ),
            .abs16 => std.mem.writeInt(
                u16,
                dest_slice[0..2],
                @intCast(target_value),
                target_endian,
            ),
            .abs8 => dest_slice[0] = @intCast(target_value),
            .rel64 => std.mem.writeInt(
                i64,
                dest_slice[0..8],
                @bitCast(target_value -% dest_vaddr),
                target_endian,
            ),
            .rel32 => std.mem.writeInt(
                i32,
                dest_slice[0..4],
                @intCast(@as(i64, @bitCast(target_value -% dest_vaddr))),
                target_endian,
            ),
            .rel16 => std.mem.writeInt(
                i16,
                dest_slice[0..2],
                @intCast(@as(i64, @bitCast(target_value -% dest_vaddr))),
                target_endian,
            ),
            .rel8 => dest_slice[0] = @bitCast(@as(i8, @intCast(@as(i64, @bitCast(target_value -% dest_vaddr))))),
            .pltabs64 => {
                const plt_index = switch (reloc.target.unwrap()) {
                    .local => continue :type .abs64,
                    .global => |name| elf.plt.getIndex(name) orelse continue :type .abs64,
                };
                if (elf.pltEntryIsDead(plt_index)) continue :type .abs64;
                const plt_shndx: Section.Index, const plt_header_entries: u64, const plt_entry_size: u64 = switch (elf.ehdrField(.machine)) {
                    else => |machine| @panic(@tagName(machine)),
                    .SPARCV9 => .{ elf.shndx.plt, 4, 32 },
                    .X86_64 => .{ elf.shndx.plt_sec, 0, 16 },
                };
                const plt_entry = plt_shndx.vaddr(elf) +% (plt_header_entries + plt_index) * plt_entry_size;
                std.mem.writeInt(
                    i64,
                    dest_slice[0..8],
                    @bitCast(plt_entry +% @as(u64, @bitCast(reloc.addend))),
                    target_endian,
                );
            },
            .pltabs32 => {
                const plt_index = switch (reloc.target.unwrap()) {
                    .local => continue :type .abs32,
                    .global => |name| elf.plt.getIndex(name) orelse continue :type .abs32,
                };
                if (elf.pltEntryIsDead(plt_index)) continue :type .abs32;
                const plt_shndx: Section.Index, const plt_header_entries: u64, const plt_entry_size: u64 = switch (elf.ehdrField(.machine)) {
                    else => |machine| @panic(@tagName(machine)),
                    .SPARCV9 => .{ elf.shndx.plt, 4, 32 },
                    .X86_64 => .{ elf.shndx.plt_sec, 0, 16 },
                };
                const plt_entry = plt_shndx.vaddr(elf) +% (plt_header_entries + plt_index) * plt_entry_size;
                std.mem.writeInt(
                    i32,
                    dest_slice[0..4],
                    @intCast(@as(i64, @bitCast(
                        plt_entry +% @as(u64, @bitCast(reloc.addend)),
                    ))),
                    target_endian,
                );
            },
            .pltrel64 => {
                const plt_index = switch (reloc.target.unwrap()) {
                    .local => continue :type .rel64,
                    .global => |name| elf.plt.getIndex(name) orelse continue :type .rel64,
                };
                if (elf.pltEntryIsDead(plt_index)) continue :type .rel64;
                const plt_shndx: Section.Index, const plt_header_entries: u64, const plt_entry_size: u64 = switch (elf.ehdrField(.machine)) {
                    else => |machine| @panic(@tagName(machine)),
                    .SPARCV9 => .{ elf.shndx.plt, 4, 32 },
                    .X86_64 => .{ elf.shndx.plt_sec, 0, 16 },
                };
                const plt_entry = plt_shndx.vaddr(elf) +% (plt_header_entries + plt_index) * plt_entry_size;
                std.mem.writeInt(
                    i64,
                    dest_slice[0..8],
                    @bitCast(plt_entry +% @as(u64, @bitCast(reloc.addend)) -% dest_vaddr),
                    target_endian,
                );
            },
            .pltrel32 => {
                const plt_index = switch (reloc.target.unwrap()) {
                    .local => continue :type .rel32,
                    .global => |name| elf.plt.getIndex(name) orelse continue :type .rel32,
                };
                if (elf.pltEntryIsDead(plt_index)) continue :type .rel32;
                const plt_shndx: Section.Index, const plt_header_entries: u64, const plt_entry_size: u64 = switch (elf.ehdrField(.machine)) {
                    else => |machine| @panic(@tagName(machine)),
                    .SPARCV9 => .{ elf.shndx.plt, 4, 32 },
                    .X86_64 => .{ elf.shndx.plt_sec, 0, 16 },
                };
                const plt_entry = plt_shndx.vaddr(elf) +% (plt_header_entries + plt_index) * plt_entry_size;
                std.mem.writeInt(
                    i32,
                    dest_slice[0..4],
                    @intCast(@as(i64, @bitCast(
                        plt_entry +% @as(u64, @bitCast(reloc.addend)) -% dest_vaddr,
                    ))),
                    target_endian,
                );
            },
            .size64 => std.mem.writeInt(
                u64,
                dest_slice[0..8],
                sym_size +% @as(u64, @bitCast(reloc.addend)),
                target_endian,
            ),
            .size32 => std.mem.writeInt(
                u32,
                dest_slice[0..4],
                @intCast(sym_size +% @as(u64, @bitCast(reloc.addend))),
                target_endian,
            ),
            .dtpoff64 => std.mem.writeInt(
                i64,
                dest_slice[0..8],
                @bitCast(target_value),
                target_endian,
            ),
            .dtpoff32 => std.mem.writeInt(
                i32,
                dest_slice[0..4],
                @intCast(@as(i64, @bitCast(target_value))),
                target_endian,
            ),
            .tpoff64 => {
                const tls_phndx = elf.getNode(elf.ni.tls).segment;
                const tls_size: u64 = switch (elf.phdrSlice()) {
                    inline else => |phdr| tls_size: {
                        assert(elf.targetLoad(&phdr[tls_phndx].type) == .TLS);
                        break :tls_size elf.targetLoad(&phdr[tls_phndx].memsz);
                    },
                };
                std.mem.writeInt(
                    i64,
                    dest_slice[0..8],
                    @bitCast(target_value -% tls_size),
                    target_endian,
                );
            },
            .tpoff32 => {
                const tls_phndx = elf.getNode(elf.ni.tls).segment;
                const tls_size: u64 = switch (elf.phdrSlice()) {
                    inline else => |phdr| tls_size: {
                        assert(elf.targetLoad(&phdr[tls_phndx].type) == .TLS);
                        break :tls_size elf.targetLoad(&phdr[tls_phndx].memsz);
                    },
                };
                std.mem.writeInt(
                    i32,
                    dest_slice[0..4],
                    @intCast(@as(i64, @bitCast(target_value -% tls_size))),
                    target_endian,
                );
            },

            .larch_abs32_lo12 => {
                assert(elf.ehdrField(.machine) == .LOONGARCH);
                link.loongarch.writeK12(dest_slice[0..4], @truncate(target_value));
            },
            .larch_rel32_hi20 => {
                assert(elf.ehdrField(.machine) == .LOONGARCH);
                link.loongarch.writeJ20(dest_slice[0..4], link.loongarch.toPcalaHi20(target_value, dest_vaddr));
            },
            .larch_rel64_lo20 => {
                assert(elf.ehdrField(.machine) == .LOONGARCH);
                link.loongarch.writeJ20(dest_slice[0..4], link.loongarch.toPcala64Lo20(target_value, dest_vaddr));
            },
            .larch_rel64_hi12 => {
                assert(elf.ehdrField(.machine) == .LOONGARCH);
                link.loongarch.writeK12(dest_slice[0..4], link.loongarch.toPcala64Hi12(target_value, dest_vaddr));
            },
            // TODO: handle bad alignment and overflow gracefully
            .larch_branch_rel18 => {
                assert(elf.ehdrField(.machine) == .LOONGARCH);
                const target_rel: i64 = @bitCast(target_value -% dest_vaddr);
                const slot_target: i16 = @intCast(@shrExact(target_rel, 2));
                link.loongarch.writeK16(dest_slice[0..4], @bitCast(slot_target));
            },
            .larch_branch_rel23 => {
                assert(elf.ehdrField(.machine) == .LOONGARCH);
                const target_rel: i64 = @bitCast(target_value -% dest_vaddr);
                const slot_target: i21 = @intCast(@shrExact(target_rel, 2));
                link.loongarch.writeD5K16(dest_slice[0..4], @bitCast(slot_target));
            },
            .larch_branch_rel28 => {
                assert(elf.ehdrField(.machine) == .LOONGARCH);
                const target_rel: i64 = @bitCast(target_value -% dest_vaddr);
                const slot_target: i26 = @intCast(@shrExact(target_rel, 2));
                link.loongarch.writeD10K16(dest_slice[0..4], @bitCast(slot_target));
            },
            .larch_call_rel38 => {
                assert(elf.ehdrField(.machine) == .LOONGARCH);
                const target_rel: i64 = @bitCast(target_value -% dest_vaddr);
                // We use i64 instead of i36 here because the allowed range is
                // [PC - 128 GiB - 0x20000, PC + 128GiB - 0x20000 - 4].
                // The intCast in writeJ20 will do the final check.
                const slot_target: i64 = @intCast(@shrExact(target_rel, 2));
                link.loongarch.writeJ20(dest_slice[0..4], @bitCast(@as(i20, @intCast((slot_target +% 0x8000) >> 16))));
                link.loongarch.writeK16(dest_slice[4..8], @bitCast(@as(i16, @truncate(slot_target))));
            },
            .larch_tpoff32_lo12 => {
                assert(elf.ehdrField(.machine) == .LOONGARCH);
                link.loongarch.writeK12(dest_slice[0..4], @truncate(target_value));
            },
            .larch_tpoff32_hi20 => {
                assert(elf.ehdrField(.machine) == .LOONGARCH);
                link.loongarch.writeJ20(dest_slice[0..4], @truncate(target_value >> 12));
            },
            .larch_tpoff64_lo20 => {
                assert(elf.ehdrField(.machine) == .LOONGARCH);
                link.loongarch.writeJ20(dest_slice[0..4], @truncate(target_value >> 32));
            },
            .larch_tpoff64_hi12 => {
                assert(elf.ehdrField(.machine) == .LOONGARCH);
                link.loongarch.writeK12(dest_slice[0..4], @truncate(target_value >> 52));
            },

            .sparc_wdisp30 => {
                const dest_ptr: *link.sparc.reloc.Disp30 = @ptrCast(@alignCast(dest_slice));
                var result = elf.targetLoad(dest_ptr);
                result.disp30 = @truncate((target_value -% dest_vaddr) >> 2);
                elf.targetStore(dest_ptr, result);
            },
            .sparc_pc10 => {
                const dest_ptr: *link.sparc.reloc.Simm13 = @ptrCast(@alignCast(dest_slice));
                var result = elf.targetLoad(dest_ptr);
                result.simm13 = @as(u10, @truncate(target_value -% dest_vaddr));
                elf.targetStore(dest_ptr, result);
            },
            .sparc_pc22 => {
                const dest_ptr: *link.sparc.reloc.Disp22 = @ptrCast(@alignCast(dest_slice));
                var result = elf.targetLoad(dest_ptr);
                result.disp22 = @truncate((target_value -% dest_vaddr) >> 10);
                elf.targetStore(dest_ptr, result);
            },
            .sparc_wplt30 => {
                const plt_index = switch (reloc.target.unwrap()) {
                    .local => continue :type .sparc_wdisp30,
                    .global => |name| elf.plt.getIndex(name) orelse continue :type .sparc_wdisp30,
                };
                if (elf.pltEntryIsDead(plt_index)) continue :type .sparc_wdisp30;
                const plt_entry = elf.shndx.plt.vaddr(elf) +% (4 + plt_index) * 32;
                const dest_ptr: *link.sparc.reloc.Disp30 = @ptrCast(@alignCast(dest_slice));
                var result = elf.targetLoad(dest_ptr);
                result.disp30 = @truncate((plt_entry +% @as(u64, @bitCast(reloc.addend)) -% dest_vaddr) >> 2);
                elf.targetStore(dest_ptr, result);
            },
            .sparc_h44 => {
                const dest_ptr: *link.sparc.reloc.Imm22 = @ptrCast(@alignCast(dest_slice));
                var result = elf.targetLoad(dest_ptr);
                result.imm22 = @truncate(target_value >> 22);
                elf.targetStore(dest_ptr, result);
            },
            .sparc_m44 => {
                const dest_ptr: *link.sparc.reloc.Imm10 = @ptrCast(@alignCast(dest_slice));
                var result = elf.targetLoad(dest_ptr);
                result.imm10 = @truncate(target_value >> 12);
                elf.targetStore(dest_ptr, result);
            },
            .sparc_l44 => {
                const dest_ptr: *link.sparc.reloc.Imm13 = @ptrCast(@alignCast(dest_slice));
                var result = elf.targetLoad(dest_ptr);
                result.imm13 = @as(u12, @truncate(target_value));
                elf.targetStore(dest_ptr, result);
            },
            .sparc_ldo_hix22 => {
                const dest_ptr: *link.sparc.reloc.Simm22 = @ptrCast(@alignCast(dest_slice));
                var result = elf.targetLoad(dest_ptr);
                result.simm22 = @truncate(target_value >> 10);
                elf.targetStore(dest_ptr, result);
            },
            .sparc_ldo_lox10 => {
                const dest_ptr: *link.sparc.reloc.Simm13 = @ptrCast(@alignCast(dest_slice));
                var result = elf.targetLoad(dest_ptr);
                result.simm13 = @as(u10, @truncate(target_value));
                elf.targetStore(dest_ptr, result);
            },
            .sparc_le_hix22 => {
                const tls_phndx = elf.getNode(elf.ni.tls).segment;
                const tls_size: u64 = switch (elf.phdrSlice()) {
                    inline else => |phdr| tls_size: {
                        assert(elf.targetLoad(&phdr[tls_phndx].type) == .TLS);
                        break :tls_size elf.targetLoad(&phdr[tls_phndx].memsz);
                    },
                };
                const dest_ptr: *link.sparc.reloc.Imm22 = @ptrCast(@alignCast(dest_slice));
                var result = elf.targetLoad(dest_ptr);
                result.imm22 = @truncate(~(target_value -% tls_size) >> 10);
                elf.targetStore(dest_ptr, result);
            },
            .sparc_le_lox10 => {
                const tls_phndx = elf.getNode(elf.ni.tls).segment;
                const tls_size: u64 = switch (elf.phdrSlice()) {
                    inline else => |phdr| tls_size: {
                        assert(elf.targetLoad(&phdr[tls_phndx].type) == .TLS);
                        break :tls_size elf.targetLoad(&phdr[tls_phndx].memsz);
                    },
                };
                const dest_ptr: *link.sparc.reloc.Simm13 = @ptrCast(@alignCast(dest_slice));
                var result = elf.targetLoad(dest_ptr);
                result.simm13 = @as(u13, 0b1110000000000) | @as(u10, @truncate(target_value -% tls_size));
                elf.targetStore(dest_ptr, result);
            },
        }
    }

    fn delete(reloc: *SymbolReloc, elf: *Elf, index: SymbolReloc.Index) void {
        assert(index.get(elf) == reloc);

        reloc.deleteOutputRel(elf);
        if (reloc.type.dependsOnTlsSize()) {
            assert(elf.tls_size_symbol_relocs.swapRemove(index));
        }

        switch (reloc.prev) {
            .none => {
                const target_ptr = reloc.target.index(elf).ptr(elf);
                assert(target_ptr.first_target_reloc == index);
                target_ptr.first_target_reloc = reloc.next;
            },
            else => |prev| prev.get(elf).next = reloc.next,
        }
        switch (reloc.next) {
            .none => {},
            else => |next| next.get(elf).prev = reloc.prev,
        }

        reloc.* = undefined;
    }

    /// If `reloc.rela_index` is populated, reset it to `.none` and delete the relocation, updating
    /// `elf.textrel_count` if necessary.
    fn deleteOutputRel(reloc: *SymbolReloc, elf: *Elf) void {
        const rela_index = reloc.rela_index.unwrap() orelse return;
        reloc.relaSection(elf).relaDeleteOne(elf, rela_index);
        switch (elf.ehdrField(.type)) {
            .NONE, .CORE, _ => unreachable,
            .REL => {},
            .EXEC, .DYN => switch (elf.nodeWantsDsoRelocation(reloc.node)) {
                .no => unreachable, // there *was* a dynamic relocation!
                .yes => {},
                .yes_textrel => elf.textrel_count -= 1,
            },
        }
        reloc.rela_index = .none;
    }
};

fn ensureUnusedSymbolCapacity(elf: *Elf, len: u32, kind: enum { all_local, maybe_global }) Error!void {
    const gpa = elf.base.comp.gpa;

    try elf.symtab.ensureUnusedCapacity(gpa, len);

    // If adding locals, we may need to move one global out of the way for each local. If adding
    // globals, they could all get demoted to STB_LOCAL, meaning we have to move N other globals
    // around to keep `.dynsym` compact. Either way, the maximum is N.
    try elf.changed_symtab_index.ensureUnusedCapacity(gpa, len);

    {
        // Ensure the symtab section's node is big enough
        const need_node_size: u64 = switch (elf.shdrPtr(.symtab)) {
            inline else => |shdr, class| elf.targetLoad(&shdr.size) + len * @sizeOf(class.ElfN().Sym),
        };
        try elf.ensureNodeSize(Section.Index.symtab.get(elf).ni, need_node_size);
    }

    switch (kind) {
        .all_local => {},
        .maybe_global => {
            try elf.globals.strong_def.ensureUnusedCapacity(gpa, len);
            try elf.globals.weak_def.ensureUnusedCapacity(gpa, len);
            try elf.globals.strong_undef.ensureUnusedCapacity(gpa, len);
            try elf.globals.weak_undef.ensureUnusedCapacity(gpa, len);

            try elf.node_global_symbols.ensureUnusedCapacity(gpa, len);

            if (elf.shndx.dynsym != .UNDEF) {
                // Ensure the `.dynsym` section's node is big enough
                const dynsym_need_size: u64 = switch (elf.shdrPtr(elf.shndx.dynsym)) {
                    inline else => |shdr, class| elf.targetLoad(&shdr.size) + len * @sizeOf(class.ElfN().Sym),
                };
                try elf.ensureNodeSize(elf.shndx.dynsym.get(elf).ni, dynsym_need_size);

                try elf.ensureUnusedPltCapacity(len);
            }
        },
    }
}
fn ensureUnusedPltCapacity(elf: *Elf, len: u32) Error!void {
    const gpa = elf.base.comp.gpa;

    try elf.shndx.rela_plt.relaEnsureAdditionalCapacity(elf, len);

    try elf.plt.ensureUnusedCapacity(gpa, len);
    const need_plt_capacity = elf.plt.count() + len;

    switch (elf.ehdrField(.machine)) {
        else => |machine| @panic(@tagName(machine)),
        .X86_64 => {
            // Ensure the `.plt` section's node is big enough
            const plt_need_size: usize = 16 * (1 + need_plt_capacity);
            try elf.ensureNodeSize(elf.shndx.plt.get(elf).ni, plt_need_size);

            // Ensure the `.got.plt` section's node is big enough
            const got_plt_need_size: usize = elf.targetPtrSize() * (3 + need_plt_capacity);
            try elf.ensureNodeSize(elf.shndx.got_plt.get(elf).ni, got_plt_need_size);

            // Ensure the `.plt.sec` section's node is big enough
            const plt_sec_need_size: usize = 16 * need_plt_capacity;
            try elf.ensureNodeSize(elf.shndx.plt_sec.get(elf).ni, plt_sec_need_size);
        },
        .LOONGARCH => {
            // Ensure the `.plt` section's node is big enough
            const plt_need_size: usize = 16 * (2 + need_plt_capacity);
            try elf.ensureNodeSize(elf.shndx.plt.get(elf).ni, plt_need_size);

            // Ensure the `.got.plt` section's node is big enough
            const got_plt_need_size: usize = elf.targetPtrSize() * (2 + need_plt_capacity);
            try elf.ensureNodeSize(elf.shndx.got_plt.get(elf).ni, got_plt_need_size);
        },
        .SPARCV9 => {
            // Ensure the `.plt` section's node is big enough
            const plt_need_size: usize = 32 * (4 + need_plt_capacity);
            try elf.ensureNodeSize(elf.shndx.plt.get(elf).ni, plt_need_size);
        },
    }
}
/// Given an index into the PLT, returns whether that PLT entry is dead, meaning it may be reused at
/// any time and must not be targeted by relocations. See also the doc comment on `Elf.plt`.
fn pltEntryIsDead(elf: *Elf, plt_index: usize) bool {
    assert(elf.shndx.plt != .UNDEF);
    assert(plt_index <= elf.plt.count());
    // We track which PLT entries are alive based on the relocation entries, since there is a 1-1
    // mapping between PLT entries and `.rela.plt` entries and the relocation entries already have
    // a free-list mechanism.
    switch (elf.shdrPtr(elf.shndx.rela_plt)) {
        inline else => |rela_shdr, class| {
            const size = elf.targetLoad(&rela_shdr.size);
            const relas: []class.ElfN().Rela = @ptrCast(@alignCast(
                elf.shndx.rela_plt.get(elf).ni.slice(&elf.mf)[0..@intCast(size)],
            ));
            const rel_type = elf.targetLoad(&relas[plt_index].info).type;
            return rel_type == MachineRelocType.none(elf).unwrap(elf);
        },
    }
}

const AddLocalSymbolOptions = struct {
    node: MappedFile.Node.Index,
    name: String(.strtab),
    value: u64,
    size: u64,
    type: std.elf.STT,
    shndx: Section.Index,
};
fn addLocalSymbolAssumeCapacity(elf: *Elf, opts: AddLocalSymbolOptions) Symbol.LocalIndex {
    switch (elf.shdrPtr(.symtab)) {
        inline else => |shdr, class| {
            const ent_size = @sizeOf(class.ElfN().Sym);

            // `shdr.info` stores the index of the first global symbol. We will replace it with our
            // new local symbol, and move the global symbol to a new index at the end of the symtab.
            const target_index: Symbol.Index = @enumFromInt(elf.targetLoad(&shdr.info));

            const old_size = elf.targetLoad(&shdr.size);
            const new_size = old_size + ent_size;

            assert(elf.symtab.items.len == @divExact(old_size, ent_size));

            elf.targetStore(&shdr.info, @intFromEnum(target_index) + 1);
            elf.targetStore(&shdr.size, new_size);

            const new_index: Symbol.Index = @enumFromInt(elf.symtab.items.len);
            elf.symtab.appendAssumeCapacity(undefined);

            const target_sym = @field(elf.symPtr(target_index), @tagName(class));

            if (target_index != new_index) {
                // Move the global at `target_index` to `new_index`. First the symtab entry...
                const new_sym = @field(elf.symPtr(new_index), @tagName(class));
                new_sym.* = target_sym.*;
                // ...then the `elf.symtab` metadata...
                new_index.ptr(elf).* = target_index.ptr(elf).*;
                // ...then update the `elf.globals` tracking.
                const global_name: String(.strtab) = @enumFromInt(elf.targetLoad(&new_sym.name));
                elf.globalByName(global_name).?.symtab_index = new_index;

                if (elf.ehdrField(.type) == .REL and target_index.ptr(elf).first_target_reloc != .none) {
                    // This symbol's index is changing, so queue an update of relocs targeting it.
                    elf.changed_symtab_index.putAssumeCapacity(global_name, {});
                }
            }

            target_index.ptr(elf).* = .{
                .node = opts.node,
                .first_target_reloc = .none,
            };

            target_sym.* = .{
                .name = @intFromEnum(opts.name),
                .value = @intCast(opts.value),
                .size = @intCast(opts.size),
                .info = .{ .type = opts.type, .bind = .LOCAL },
                .other = .{ .visibility = .DEFAULT },
                .shndx = opts.shndx.toSection().?,
            };
            if (elf.targetEndian() != native_endian) {
                std.mem.byteSwapAllFields(class.ElfN().Sym, target_sym);
            }

            return @enumFromInt(@intFromEnum(target_index));
        },
    }
}

const AddGlobalSymbolOptions = struct {
    const Name = struct {
        strtab: String(.strtab),
        dynstr: String(.dynstr),
        fn string(elf: *Elf, slice: []const u8) Error!Name {
            return .{
                .strtab = try elf.string(.strtab, slice),
                .dynstr = switch (elf.shndx.dynsym) {
                    .UNDEF => .empty,
                    else => try elf.string(.dynstr, slice),
                },
            };
        }
    };

    node: MappedFile.Node.Index,
    name: Name,
    lib_name: ?[]const u8 = null,
    value: u64,
    size: u64,
    type: std.elf.STT,
    bind: enum { strong, weak },
    visibility: std.elf.STV,
    shndx: Section.Index,
};
fn addGlobalSymbolAssumeCapacity(elf: *Elf, opts: AddGlobalSymbolOptions) error{MultipleDefinitions}!Symbol.Id {
    _ = opts.lib_name; // TODO

    if (elf.shndx.dynsym == .UNDEF) {
        assert(opts.name.dynstr == .empty);
    } else {
        assert(std.mem.eql(u8, opts.name.dynstr.slice(elf), opts.name.strtab.slice(elf)));
    }

    // We break from this `switch` only if this symbol name did not previously exist at all and so
    // we have added a new entry to one of the maps in `elf.globals`. In that case we actually need
    // a new symtab entry.
    const new_global_ptr: *Symbol.Global = if (opts.shndx != .UNDEF) switch (opts.bind) {
        .strong => new_global: {
            const gop = elf.globals.strong_def.getOrPutAssumeCapacity(opts.name.strtab);
            if (gop.found_existing) return error.MultipleDefinitions;
            const old_kv = elf.globals.weak_def.fetchSwapRemove(opts.name.strtab) orelse
                elf.globals.strong_undef.fetchSwapRemove(opts.name.strtab) orelse
                elf.globals.weak_undef.fetchSwapRemove(opts.name.strtab) orelse {
                // The symbol did not already exist, so we'll use the "new global" path.
                break :new_global gop.value_ptr;
            };
            gop.value_ptr.* = old_kv.value;
            elf.setGlobalSymbolValue(opts.name.strtab, gop.value_ptr, .{
                .node = opts.node,
                .value = opts.value,
                .size = opts.size,
                .type = opts.type,
                .shndx = opts.shndx,
            });
            elf.mergeGlobalSymbolVisibility(gop.value_ptr, opts.visibility, .strong);
            return .global(opts.name.strtab);
        },
        .weak => new_global: {
            if (elf.globals.strong_def.getPtr(opts.name.strtab)) |global| {
                // The existing definition holds, we just merge our visibility in.
                elf.mergeGlobalSymbolVisibility(global, opts.visibility, .strong);
                return .global(opts.name.strtab);
            }
            const gop = elf.globals.weak_def.getOrPutAssumeCapacity(opts.name.strtab);
            if (gop.found_existing) {
                // The existing definition holds, we just merge our visibility in.
                elf.mergeGlobalSymbolVisibility(gop.value_ptr, opts.visibility, .weak);
                return .global(opts.name.strtab);
            }
            const old_kv = elf.globals.strong_undef.fetchSwapRemove(opts.name.strtab) orelse
                elf.globals.weak_undef.fetchSwapRemove(opts.name.strtab) orelse {
                // The symbol did not already exist, so we'll use the "new global" path.
                break :new_global gop.value_ptr;
            };
            gop.value_ptr.* = old_kv.value;
            elf.setGlobalSymbolValue(opts.name.strtab, gop.value_ptr, .{
                .node = opts.node,
                .value = opts.value,
                .size = opts.size,
                .type = opts.type,
                .shndx = opts.shndx,
            });
            elf.mergeGlobalSymbolVisibility(gop.value_ptr, opts.visibility, .weak);
            return .global(opts.name.strtab);
        },
    } else switch (opts.bind) {
        .strong => new_global: {
            if (elf.globals.strong_def.getPtr(opts.name.strtab)) |global| {
                // The existing definition holds, we just merge our visibility in.
                elf.mergeGlobalSymbolVisibility(global, opts.visibility, .strong);
                return .global(opts.name.strtab);
            }
            if (elf.globals.weak_def.getPtr(opts.name.strtab)) |global| {
                // The existing definition holds, we just merge our visibility in.
                elf.mergeGlobalSymbolVisibility(global, opts.visibility, .weak);
                return .global(opts.name.strtab);
            }
            const gop = elf.globals.strong_undef.getOrPutAssumeCapacity(opts.name.strtab);
            if (gop.found_existing) {
                // The existing symbol is okay, we just merge our visibility in.
                elf.mergeGlobalSymbolVisibility(gop.value_ptr, opts.visibility, .strong);
                return .global(opts.name.strtab);
            }
            const old_kv = elf.globals.weak_undef.fetchSwapRemove(opts.name.strtab) orelse {
                // The symbol did not already exist, so we'll use the "new global" path.
                break :new_global gop.value_ptr;
            };
            gop.value_ptr.* = old_kv.value;
            elf.mergeGlobalSymbolVisibility(gop.value_ptr, opts.visibility, .strong);
            return .global(opts.name.strtab);
        },
        .weak => new_global: {
            if (elf.globals.strong_def.getPtr(opts.name.strtab) orelse
                elf.globals.strong_undef.getPtr(opts.name.strtab)) |global|
            {
                // The existing symbol is okay, we just merge our visibility in.
                elf.mergeGlobalSymbolVisibility(global, opts.visibility, .strong);
                return .global(opts.name.strtab);
            }
            if (elf.globals.weak_def.getPtr(opts.name.strtab)) |global| {
                // The existing symbol is okay, we just merge our visibility in.
                elf.mergeGlobalSymbolVisibility(global, opts.visibility, .weak);
                return .global(opts.name.strtab);
            }
            const gop = elf.globals.weak_undef.getOrPutAssumeCapacity(opts.name.strtab);
            if (gop.found_existing) {
                // The existing symbol is okay, we just merge our visibility in.
                elf.mergeGlobalSymbolVisibility(gop.value_ptr, opts.visibility, .weak);
                return .global(opts.name.strtab);
            }
            break :new_global gop.value_ptr;
        },
    };

    const force_local_bind: bool = switch (opts.visibility) {
        .HIDDEN, .INTERNAL => elf.ehdrField(.type) != .REL,
        .PROTECTED, .DEFAULT => false,
    };

    const bind: std.elf.STB = if (force_local_bind) b: {
        break :b .LOCAL;
    } else switch (opts.bind) {
        .strong => .GLOBAL,
        .weak => .WEAK,
    };

    const @"type": std.elf.STT = switch (opts.type) {
        .NOTYPE => if (elf.dso_globals.get(opts.name.strtab)) |dso_global| t: {
            break :t dso_global.type;
        } else .NOTYPE,
        else => |t| t,
    };

    const sym_index: Symbol.Index = @enumFromInt(elf.symtab.items.len);
    elf.symtab.appendAssumeCapacity(.{
        .node = opts.node,
        .first_target_reloc = .none,
    });
    switch (elf.shdrPtr(.symtab)) {
        inline else => |shdr, class| {
            const Sym = class.ElfN().Sym;
            // Increase the symtab size...
            const old_size = elf.targetLoad(&shdr.size);
            assert(old_size == @intFromEnum(sym_index) * @sizeOf(Sym));
            elf.targetStore(&shdr.size, old_size + @sizeOf(Sym));
            // ...then populate the newly-valid symbol pointer
            const sym = @field(elf.symPtr(sym_index), @tagName(class));
            sym.* = .{
                .name = @intFromEnum(opts.name.strtab),
                .value = @intCast(opts.value),
                .size = @intCast(opts.size),
                .info = .{ .type = @"type", .bind = bind },
                .other = .{ .visibility = opts.visibility },
                .shndx = opts.shndx.toSection().?,
            };
            if (elf.targetEndian() != native_endian) {
                std.mem.byteSwapAllFields(Sym, sym);
            }
        },
    }

    const old_head: String(.strtab) = old_head: {
        if (opts.node == .none) break :old_head .empty;
        const gop = elf.node_global_symbols.getOrPutAssumeCapacity(opts.node);
        const old_head: String(.strtab) = if (gop.found_existing) gop.value_ptr.* else .empty;
        gop.value_ptr.* = opts.name.strtab;
        break :old_head old_head;
    };

    new_global_ptr.* = .{
        .symtab_index = sym_index,
        .dynsym_index = dynsym_index: {
            if (elf.shndx.dynsym == .UNDEF) break :dynsym_index 0;
            if (force_local_bind) break :dynsym_index 0;
            switch (elf.shdrPtr(elf.shndx.dynsym)) {
                inline else => |shdr, class| {
                    const Sym = class.ElfN().Sym;
                    // Increase the dynamic symbol table size...
                    const old_size = elf.targetLoad(&shdr.size);
                    elf.targetStore(&shdr.size, old_size + @sizeOf(Sym));
                    const dynsym_index: u32 = @intCast(@divExact(old_size, @sizeOf(Sym)));
                    // ...then populate the newly-valid symbol pointer
                    const sym = @field(elf.dynsymPtr(dynsym_index), @tagName(class));
                    sym.* = .{
                        .name = @intFromEnum(opts.name.dynstr),
                        .value = @intCast(opts.value),
                        .size = @intCast(opts.size),
                        .info = .{ .type = @"type", .bind = bind },
                        .other = .{ .visibility = opts.visibility },
                        .shndx = opts.shndx.toSection().?,
                    };
                    if (elf.targetEndian() != native_endian) {
                        std.mem.byteSwapAllFields(Sym, sym);
                    }
                    break :dynsym_index dynsym_index;
                },
            }
        },
        .prev_in_node = .empty,
        .next_in_node = old_head,
    };

    if (old_head != .empty) {
        const old_head_ptr = elf.globalByName(old_head).?;
        assert(old_head_ptr.symtab_index.ptr(elf).node == opts.node);
        assert(old_head_ptr.prev_in_node == .empty);
        old_head_ptr.prev_in_node = opts.name.strtab;
    }

    if (force_local_bind) {
        elf.moveDemotedGlobal(new_global_ptr);
    }

    switch (@"type") {
        .FUNC, .GNU_IFUNC => if (elf.ehdrField(.type) != .REL and
            elf.classifySymbolValue(.global(opts.name.strtab)) == .dynamic)
        {
            // This STT_FUNC symbol might be defined externally, so it needs a PLT entry.
            elf.addPltEntry(opts.name.strtab, new_global_ptr.dynsym_index);
        },
        else => {},
    }

    return .global(opts.name.strtab);
}
fn setGlobalSymbolValue(
    elf: *Elf,
    global_name: String(.strtab),
    global_ptr: *Symbol.Global,
    new: struct {
        node: MappedFile.Node.Index,
        value: u64,
        size: u64,
        type: std.elf.STT,
        shndx: Section.Index,
    },
) void {
    assert(new.shndx != .UNDEF);
    const old_node = global_ptr.symtab_index.ptr(elf).node;
    if (old_node != .none) {
        if (global_ptr.next_in_node != .empty) {
            const next = elf.globalByName(global_ptr.next_in_node).?;
            assert(next.prev_in_node == global_name);
            assert(next.symtab_index.ptr(elf).node == old_node);
            next.prev_in_node = global_ptr.prev_in_node;
        }
        if (global_ptr.prev_in_node != .empty) {
            const prev = elf.globalByName(global_ptr.prev_in_node).?;
            assert(prev.next_in_node == global_name);
            assert(prev.symtab_index.ptr(elf).node == old_node);
            prev.next_in_node = global_ptr.next_in_node;
        } else {
            // We're the start of the linked list, so we need to change the head.
            if (global_ptr.next_in_node == .empty) {
                assert(elf.node_global_symbols.fetchSwapRemove(old_node).?.value == global_name);
            } else {
                elf.node_global_symbols.getPtr(old_node).?.* = global_ptr.next_in_node;
            }
        }
    } else {
        assert(global_ptr.next_in_node == .empty);
        assert(global_ptr.prev_in_node == .empty);
    }

    if (elf.copied_globals.fetchSwapRemove(global_name)) |copied_global_kv| {
        // This is a quite rare case: there was a definition for this symbol in a shared library
        // input, and we ended up emitting a copy relocation for it, but we've now got our *own*
        // definition which replaces it. We know that our definition cannot be preempted because we
        // are the executable (only executables can have copy relocations!), so we definitely do not
        // need the copy relocation.

        // All we actually need to do is remove the entry from `copied_globals` (already done), and
        // delete the actual `R_*_COPY` relocation. Of course, we also need to re-apply relocations
        // targeting this symbol, but we were going to do that at the end of this function anyway.
        elf.shndx.rela_dyn.relaDeleteOne(elf, copied_global_kv.value.rela_index);
        // TODO: once `MappedFile` has a way to delete a node (so it can re-use the space), we
        // should delete `copied_global_kv.value.node`, which is an "orphaned" `copied_global` node.
    } else {
        _ = elf.want_copied_globals.swapRemove(global_name);
    }

    global_ptr.symtab_index.ptr(elf).node = new.node;

    const old_head: String(.strtab) = old_head: {
        if (new.node == .none) break :old_head .empty;
        const gop = elf.node_global_symbols.getOrPutAssumeCapacity(new.node);
        const old_head: String(.strtab) = if (gop.found_existing) gop.value_ptr.* else .empty;
        gop.value_ptr.* = global_name;
        break :old_head old_head;
    };

    global_ptr.prev_in_node = .empty;
    global_ptr.next_in_node = old_head;

    if (old_head != .empty) {
        const old_head_ptr = elf.globalByName(old_head).?;
        assert(old_head_ptr.symtab_index.ptr(elf).node == new.node);
        assert(old_head_ptr.prev_in_node == .empty);
        old_head_ptr.prev_in_node = global_name;
    }

    // Now for the easy bit where we actually update the symtab entry.
    switch (elf.symPtr(global_ptr.symtab_index)) {
        inline else => |sym| {
            // Don't bother with `sym.value` here: it'll be updated by `flushMoved`.
            elf.targetStore(&sym.size, @intCast(new.size));
            elf.targetStore(&sym.shndx, new.shndx.toSection().?);
            const old_bind = elf.targetLoad(&sym.info).bind;
            elf.targetStore(&sym.info, .{
                .type = new.type,
                .bind = old_bind,
            });
        },
    }

    // ...and also the dynsym entry if there is one.
    if (global_ptr.dynsym_index != 0) switch (elf.dynsymPtr(global_ptr.dynsym_index)) {
        inline else => |sym| {
            // Don't bother with `sym.value` here: it'll be updated by `flushMoved`.
            elf.targetStore(&sym.size, @intCast(new.size));
            elf.targetStore(&sym.shndx, new.shndx.toSection().?);
            const old_bind = elf.targetLoad(&sym.info).bind;
            elf.targetStore(&sym.info, .{
                .type = new.type,
                .bind = old_bind,
            });
        },
    };

    // If this symbol was previously undefined, it may have had a PLT entry. If so, we now need to
    // delete its newly-unnecessary runtime relocation to avoid a runtime dynamic linker error.
    // This also allows the PLT entry to be reused---see `pltEntryIsDead`.
    if (elf.plt.getIndex(global_name)) |plt_index| {
        if (!elf.pltEntryIsDead(plt_index) and
            elf.classifySymbolValue(.global(global_name)) != .dynamic)
        {
            elf.shndx.rela_plt.relaDeleteOne(elf, @enumFromInt(plt_index));
            assert(elf.pltEntryIsDead(plt_index));
        }
    }

    // If this symbol was previously undefined, relocations targeting it may have been lowered to
    // runtime relocations which we have now discovered we do not need, so delete those.
    if (elf.shndx.dynamic != .UNDEF) {
        Symbol.Id.global(global_name).deleteDynamicTargetRelocs(elf);
    }

    // Finally, update the symbol value, re-applying target relocations. Also note that because we
    // possibly removed the PLT entry above, some relocations which were previously targeting the
    // PLT will now instead target the symbol itself.
    Symbol.Id.global(global_name).flushMoved(elf, new.value);
}
/// When the same global symbol appears in two inputs---even if one symbol is defined and the other
/// undefined---their visibility values are combined to determine the resulting visibility, which
/// can also affect the bind of the symbol we output.
fn mergeGlobalSymbolVisibility(elf: *Elf, global_ptr: *Symbol.Global, other_visibility: std.elf.STV, bind: enum { strong, weak }) void {
    const old_visibility: std.elf.STV = switch (elf.symPtr(global_ptr.symtab_index)) {
        inline else => |sym| elf.targetLoad(&sym.other).visibility,
    };
    // The combined visibility is essentially the "strictest" of the two, with most strict being
    // INTERNAL, followed by HIDDEN, PROTECTED, DEFAULT.
    const new_visibility: std.elf.STV, const newly_hidden: bool = switch (old_visibility) {
        .INTERNAL => .{ .INTERNAL, false },
        .HIDDEN => switch (other_visibility) {
            .INTERNAL => .{ .INTERNAL, false },
            .HIDDEN, .PROTECTED, .DEFAULT => .{ .HIDDEN, false },
        },
        .PROTECTED => switch (other_visibility) {
            .INTERNAL => .{ .INTERNAL, true },
            .HIDDEN => .{ .HIDDEN, true },
            .PROTECTED, .DEFAULT => .{ .PROTECTED, false },
        },
        .DEFAULT => switch (other_visibility) {
            .INTERNAL => .{ .INTERNAL, true },
            .HIDDEN => .{ .HIDDEN, true },
            .PROTECTED => .{ .PROTECTED, false },
            .DEFAULT => .{ .DEFAULT, false },
        },
    };
    // If the symbol is HIDDEN/INTERNAL and we're emitting an ELF module (executable or shared
    // object), then the symbol should have binding STB_LOCAL in the output. Therefore, if we are
    // putting the global in this state for the first time---let's call it "demoting" the global to
    // STB_LOCAL---we need to update its bind in the symtab.
    const demote_to_local = newly_hidden and elf.ehdrField(.type) != .REL;
    switch (elf.symPtr(global_ptr.symtab_index)) {
        inline else => |sym, class| {
            const old_info = elf.targetLoad(&sym.info);
            const new_info: class.ElfN().Sym.Info = .{
                .type = old_info.type,
                .bind = if (demote_to_local) b: {
                    assert(old_info.bind != .LOCAL);
                    break :b .LOCAL;
                } else if (old_info.bind == .LOCAL) .LOCAL else switch (bind) {
                    .strong => .GLOBAL,
                    .weak => .WEAK,
                },
            };
            elf.targetStore(&sym.other, .{ .visibility = new_visibility });
            elf.targetStore(&sym.info, new_info);
            // also update dynsym
            if (global_ptr.dynsym_index != 0) {
                const dynsym = @field(elf.dynsymPtr(global_ptr.dynsym_index), @tagName(class));
                elf.targetStore(&dynsym.other, .{ .visibility = new_visibility });
                elf.targetStore(&dynsym.info, new_info);
            }
        },
    }
    if (demote_to_local) {
        // When demoting a global to STB_LOCAL, we need to move its symtab index so that it is with
        // the STB_LOCAL symbols instead of the global symbols.
        elf.moveDemotedGlobal(global_ptr);
    }
}
/// If a symbol which was STB_GLOBAL/STB_WEAK becomes STB_LOCAL (see `mergeGlobalSymbolVisibility`),
/// the symbol must be moved from the "globals" part of the symtab to the "locals" part, because ELF
/// requires that all STB_LOCAL symbols in a symbol table appear before any global symbols.
fn moveDemotedGlobal(elf: *Elf, global_ptr: *Symbol.Global) void {
    assert(elf.ehdrField(.type) != .REL); // demotion only happens when emitting an ELF module
    switch (elf.shdrPtr(.symtab)) {
        inline else => |shdr, class| {
            // `shdr.info` stores the index of the first global symbol. We are going to swap the
            // demoted symbol with that first global symbol, then increment that start index.
            const dest_index: Symbol.Index = @enumFromInt(elf.targetLoad(&shdr.info));
            const src_index = global_ptr.symtab_index;

            // This global should currently be in the "global symbols" part of the symtab, since our
            // job is to move it *out* of that part:
            assert(@intFromEnum(src_index) >= @intFromEnum(dest_index));

            elf.targetStore(&shdr.info, @intFromEnum(dest_index) + 1);

            if (src_index != dest_index) {
                // The demoted global was not the first global in the symtab, so we need to swap it
                // to its new location.

                const src_sym_ptr = @field(elf.symPtr(src_index), @tagName(class));
                const dest_sym_ptr = @field(elf.symPtr(dest_index), @tagName(class));

                const this_name: String(.strtab) = @enumFromInt(elf.targetLoad(&src_sym_ptr.name));
                assert(elf.globalByName(this_name).? == global_ptr);

                const other_name: String(.strtab) = @enumFromInt(elf.targetLoad(&dest_sym_ptr.name));
                const other_global_ptr = elf.globalByName(other_name).?;
                assert(other_global_ptr.symtab_index == dest_index);

                // First swap the symtab entries...
                std.mem.swap(class.ElfN().Sym, src_sym_ptr, dest_sym_ptr);
                // ...then the `elf.symtab` metadata...
                std.mem.swap(Symbol, src_index.ptr(elf), dest_index.ptr(elf));
                // ...then update the `elf.globals` tracking.
                global_ptr.symtab_index = dest_index;
                other_global_ptr.symtab_index = src_index;
            }

            // We also need to get rid of the dynsym entry if there is one. To keep dynsym compact,
            // we'll move another symbol into its place just like we did above.
            if (global_ptr.dynsym_index != 0) {
                const dynsym_shdr = @field(elf.shdrPtr(elf.shndx.dynsym), @tagName(class));

                const ent_size = @sizeOf(class.ElfN().Sym);
                assert(elf.targetLoad(&dynsym_shdr.entsize) == ent_size);

                // We're going to decrease the size of `.dynsym`, thereby removing its last index.
                const old_size = elf.targetLoad(&dynsym_shdr.size);
                const new_size = old_size - ent_size;
                const remove_dynsym_index: u32 = @intCast(@divExact(new_size, ent_size));

                const free_dynsym_index = global_ptr.dynsym_index;
                global_ptr.dynsym_index = 0;

                if (free_dynsym_index != remove_dynsym_index) {
                    // The demoted global wasn't the last entry, so move whatever entry we just
                    // truncated out of dynsym into its place.

                    const src_dynsym_ptr = @field(elf.dynsymPtr(remove_dynsym_index), @tagName(class));
                    const dest_dynsym_ptr = @field(elf.dynsymPtr(free_dynsym_index), @tagName(class));

                    const moved_name_dynstr: String(.dynstr) = @enumFromInt(elf.targetLoad(&src_dynsym_ptr.name));
                    const moved_name = elf.stringExisting(.strtab, moved_name_dynstr.slice(elf));
                    const moved_global_ptr = elf.globalByName(moved_name).?;

                    dest_dynsym_ptr.* = src_dynsym_ptr.*;

                    assert(moved_global_ptr.dynsym_index == remove_dynsym_index);
                    moved_global_ptr.dynsym_index = free_dynsym_index;

                    // Since that symbol's dynsym index has changed, we'll have to update any
                    // relocation entries targeting it.
                    elf.changed_symtab_index.putAssumeCapacity(moved_name, {});
                }

                // Now that we've given that symbol a new home, actually decrease the section size.
                elf.targetStore(&dynsym_shdr.size, new_size);
            }
        },
    }
}
fn addPltEntry(elf: *Elf, global_name: String(.strtab), dynsym_index: u32) void {
    const target_endian = elf.targetEndian();

    // We use the existing free-list tracking of the `.rela.plt` section to also behave as a
    // free-list for the PLT itself---see `pltEntryIsDead` for details.
    const plt_index: u32 = @intFromEnum(elf.shndx.rela_plt.relaAddOneAssumeCapacity(elf, .{
        .type = .jumpSlot(elf),
        .offset = 0, // populated later
        .raw_sym_index = dynsym_index,
        .addend = 0,
    }));

    // Note that some architectures don't have .got.plt (e.g. SPARC), and so
    // these values actually refer to .plt.
    const got_plt_section, const got_plt_offset = switch (elf.ehdrField(.machine)) {
        else => |machine| @panic(@tagName(machine)),
        .LOONGARCH => .{ elf.shndx.got_plt, elf.targetPtrSize() * (2 + plt_index) },
        .SPARCV9 => .{ elf.shndx.plt, 32 * (4 + plt_index) },
        .X86_64 => .{ elf.shndx.got_plt, elf.targetPtrSize() * (3 + plt_index) },
    };

    // Now that we know the index, we can set the relocation's offset.
    elf.shndx.rela_plt.relaSetOffset(elf, @enumFromInt(plt_index), got_plt_section.vaddr(elf) + got_plt_offset);

    if (plt_index < elf.plt.count()) {
        // We reused a free entry, so we're already done!
        elf.plt.setKey(plt_index, global_name);
        return;
    }

    // We added a new entry, so we now need to extend the PLT sections.
    assert(plt_index == elf.plt.count());
    elf.plt.putAssumeCapacityNoClobber(global_name, {});

    switch (elf.ehdrField(.machine)) {
        else => |machine| @panic(@tagName(machine)),
        .X86_64 => {
            const plt_ni = elf.shndx.plt.get(elf).ni;
            const plt_addr = plt_addr: switch (elf.shdrPtr(elf.shndx.plt)) {
                inline else => |shdr| {
                    const old_size = 16 * (1 + plt_index);
                    assert(elf.targetLoad(&shdr.size) == old_size);
                    elf.targetStore(&shdr.size, old_size + 16);
                    const plt_slice = plt_ni.slice(&elf.mf)[old_size..][0..16];
                    @memcpy(plt_slice, &[16]u8{
                        0xf3, 0x0f, 0x1e, 0xfa, // endbr64
                        0x68, 0x00, 0x00, 0x00, 0x00, // push $0x0
                        0xe9, 0x00, 0x00, 0x00, 0x00, // jmp 0
                        0x66, 0x90, // xchg %ax,%ax
                    });
                    std.mem.writeInt(u32, plt_slice[5..][0..4], plt_index, target_endian);
                    std.mem.writeInt(
                        i32,
                        plt_slice[10..][0..4],
                        -@as(i32, @intCast(old_size + 14)),
                        target_endian,
                    );
                    break :plt_addr elf.targetLoad(&shdr.addr) + old_size;
                },
            };

            const got_plt_ni = elf.shndx.got_plt.get(elf).ni;
            switch (elf.shdrPtr(elf.shndx.got_plt)) {
                inline else => |shdr, class| {
                    assert(elf.targetLoad(&shdr.size) == got_plt_offset);
                    elf.targetStore(&shdr.size, got_plt_offset + @sizeOf(class.ElfN().Addr));
                    std.mem.writeInt(
                        class.ElfN().Addr,
                        got_plt_ni.slice(&elf.mf)[got_plt_offset..][0..@sizeOf(class.ElfN().Addr)],
                        @intCast(plt_addr),
                        target_endian,
                    );
                },
            }

            const plt_sec_ni = elf.shndx.plt_sec.get(elf).ni;
            switch (elf.shdrPtr(elf.shndx.plt_sec)) {
                inline else => |shdr| {
                    const old_size = 16 * plt_index;
                    elf.targetStore(&shdr.size, old_size + 16);
                    const plt_sec_slice = plt_sec_ni.slice(&elf.mf)[old_size..][0..16];
                    @memcpy(plt_sec_slice, &[16]u8{
                        0xf3, 0x0f, 0x1e, 0xfa, // endbr64
                        0xff, 0x25, 0x00, 0x00, 0x00, 0x00, // jmp *0x0(%rip)
                        0x66, 0x0f, 0x1f, 0x44, 0x00, 0x00, // nopw 0x0(%rax,%rax,1)
                    });
                    std.mem.writeInt(
                        i32,
                        plt_sec_slice[6..][0..4],
                        @intCast(@as(i64, @bitCast(
                            (got_plt_section.vaddr(elf) + got_plt_offset) -% (elf.targetLoad(&shdr.addr) + old_size + 10),
                        ))),
                        target_endian,
                    );
                },
            }
        },
        .LOONGARCH => {
            // add a .PLT entry, writing the template
            const plt_ni = elf.shndx.plt.get(elf).ni;
            const plt_addr, const plt_slice = plt_entry: switch (elf.shdrPtr(elf.shndx.plt)) {
                inline else => |shdr| {
                    const old_size = 16 * (1 + plt_index);
                    assert(elf.targetLoad(&shdr.size) == old_size);
                    elf.targetStore(&shdr.size, old_size + 16);
                    const plt_slice = plt_ni.slice(&elf.mf)[old_size..][0..16];
                    @memcpy(plt_slice, source: switch (elf.identClass()) {
                        .NONE, _ => unreachable,
                        inline .@"32", .@"64" => |elf_class| {
                            const ld_byte = if (elf_class == .@"64") 0xc0 else 0x80;
                            break :source &[16]u8{
                                0x1a, 0x00, 0x00, 0x0f, //    pcalau12i $t3, %pc_hi20(func@.got.plt)
                                0x28, ld_byte, 0x01, 0xef, // ld.w/d    $t3, $t3, %lo12(func@.got.plt)
                                0x4c, 0x00, 0x01, 0xed, //    jirl      $t1, $t3, 0
                                0x00, 0x2a, 0x00, 0x00, //    break
                            };
                        },
                    });
                    break :plt_entry .{ elf.targetLoad(&shdr.addr) + old_size, plt_slice };
                },
            };

            // add a .GOT.PLT entry, writing the address of the corresponding .PLT entry
            const got_plt_ni = elf.shndx.got_plt.get(elf).ni;
            switch (elf.shdrPtr(elf.shndx.got_plt)) {
                inline else => |shdr, class| {
                    assert(elf.targetLoad(&shdr.size) == got_plt_offset);
                    elf.targetStore(&shdr.size, got_plt_offset + @sizeOf(class.ElfN().Addr));
                    std.mem.writeInt(
                        class.ElfN().Addr,
                        got_plt_ni.slice(&elf.mf)[got_plt_offset..][0..@sizeOf(class.ElfN().Addr)],
                        @intCast(plt_addr),
                        target_endian,
                    );
                },
            }

            // relocate the PLT entry to point to the .GOT.PLT entry
            const got_plt_abs = got_plt_section.vaddr(elf) + got_plt_offset;
            // TODO: handle overflow gracefully
            link.loongarch.writeJ20(plt_slice[0..4], link.loongarch.toPcalaHi20(got_plt_abs, plt_addr));
            link.loongarch.writeK12(plt_slice[4..8], @truncate(got_plt_abs));
        },
        .SPARCV9 => {
            // add a .PLT entry, writing the template
            const plt_ni = elf.shndx.plt.get(elf).ni;
            switch (elf.shdrPtr(elf.shndx.plt)) {
                inline else => |shdr| {
                    assert(elf.targetLoad(&shdr.size) == got_plt_offset);
                    elf.targetStore(&shdr.size, got_plt_offset + 32);
                    const plt_slice: []u32 = @ptrCast(@alignCast(plt_ni.slice(&elf.mf)[got_plt_offset..][0..32]));
                    // sethi (. - .plt[0]), %g1
                    // ba,a %xcc, .plt[1]
                    // nop
                    // nop
                    // nop
                    // nop
                    // nop
                    // nop
                    @memcpy(plt_slice, &([2]u32{
                        // TODO: handle overflow gracefully
                        @bitCast(link.sparc.reloc.Imm22{
                            .imm22 = @truncate(got_plt_offset),
                            .b22_31 = 0b0000000011,
                        }),
                        @bitCast(link.sparc.reloc.Disp19{
                            .disp19 = @truncate((got_plt_offset + 4 - 32) >> 2),
                            .b19_31 = 0b1100001101000,
                        }),
                    } ++ @as([6]u32, @splat(0x01000000))));
                    if (elf.targetEndian() != native_endian) std.mem.byteSwapAllElements(u32, plt_slice);
                },
            }
        },
    }
}

const Symbol = struct {
    /// The node which this symbol's value is defined relative to. Possible values are:
    /// * `.none` for a SHN_ABS or SHN_UNDEF symbol
    /// * A section (the symbol's value is some vaddr in that section)
    /// * An input section (the symbol's value is some vaddr in that input section)
    /// * A NAV, UAV, or lazy code/data (the symbol's value is exactly the vaddr of that node)
    node: MappedFile.Node.Index,

    /// The head of a linked list of relocations targeting this symbol.
    first_target_reloc: SymbolReloc.Index,

    const Global = struct {
        /// The current index of the symtab entry for this global symbol.
        symtab_index: Symbol.Index,
        /// The current index of the dynsym entry for this global symbol. If the global has been
        /// demoted to STB_LOCAL, it does not have a dynsym entry and this field is set to 0.
        dynsym_index: u32,

        /// The next entry in a linked list of global symbols with the same `Symbol.node` value.
        ///
        /// If `node` is `.none`, this is `.empty`.
        next_in_node: String(.strtab),
        /// The previous entry in a linked list of global symbols with the same `Symbol.node` value.
        ///
        /// If `node` is `.none`, this is `.empty`.
        prev_in_node: String(.strtab),
    };

    /// An index directly into the symtab. These values are not stable (global symbols are sometimes
    /// moved to new locations in the symtab) and therefore should only be used ephemerally.
    ///
    /// Local symbols *do* have stable indices into the symtab; see `LocalIndex`.
    ///
    /// For a stable reference to an arbitrary symbol, see `Id`.
    const Index = enum(u32) {
        null = 0,
        _,

        fn ptr(si: Symbol.Index, elf: *Elf) *Symbol {
            return &elf.symtab.items[@intFromEnum(si)];
        }
    };

    /// A `LocalIndex` is a raw index into the symtab like `Index`, but it guarantees that the
    /// symbol in question has STB_LOCAL binding, which guarantees that its symtab index is stable
    /// so can be stored long-term without needing to be updated
    ///
    /// This is because symbols which have STB_LOCAL binding in the output file gain fixed symtab
    /// indices, thanks to a combination of a few factors:
    /// * We never remove STB_LOCAL symbols
    /// * There is no symbol ordering requirement *within* the leading range of STB_LOCAL symbols
    /// * A symbol visibility which demotes a global to STB_LOCAL binding can never be reverted by
    ///   a subsequent operation (different visibilities resolve to the "strictest" one)
    const LocalIndex = enum(u32) {
        null = 0,
        _,

        fn index(li: LocalIndex) Index {
            return @enumFromInt(@intFromEnum(li));
        }
    };

    /// Opaque, stable identifier for a symbol. Does not necessarily equal the index into the symtab.
    const Id = packed struct(u32) {
        kind: enum(u1) { local, global },
        raw: u31,

        const @"null": Symbol.Id = .local(.null);

        fn local(lsi: Symbol.LocalIndex) Symbol.Id {
            return .{ .kind = .local, .raw = @intCast(@intFromEnum(lsi)) };
        }
        fn global(name: String(.strtab)) Symbol.Id {
            return .{ .kind = .global, .raw = @intCast(@intFromEnum(name)) };
        }
        fn unwrap(s: Symbol.Id) union(enum) {
            local: Symbol.LocalIndex,
            global: String(.strtab),
        } {
            return switch (s.kind) {
                .local => .{ .local = @enumFromInt(s.raw) },
                .global => .{ .global = @enumFromInt(s.raw) },
            };
        }

        fn toTypeErased(s: Symbol.Id) link.File.SymbolId {
            return @enumFromInt(@as(u32, @bitCast(s)));
        }
        fn fromTypeErased(s: link.File.SymbolId) Symbol.Id {
            return @bitCast(@intFromEnum(s));
        }

        fn index(s: Symbol.Id, elf: *const Elf) Symbol.Index {
            return switch (s.unwrap()) {
                .local => |lsi| lsi.index(),
                .global => |name| elf.globalByName(name).?.symtab_index,
            };
        }

        /// Returns the value of this symbol, or 0 if it is undefined. If the symbol is an undefined
        /// global for which we have emitted a copy relocation, returns the virtual address of that
        /// copy relocation, which the symbol is guaranteed to resolve to at runtime.
        fn value(s: Symbol.Id, elf: *Elf) u64 {
            return switch (elf.symPtr(s.index(elf))) {
                inline else => |sym| elf.targetLoad(&sym.value),
            };
        }

        fn flushMoved(sym_id: Symbol.Id, elf: *Elf, new_value: u64) void {
            // Update the symbol value in `.symtab`
            const sym_index = sym_id.index(elf);
            switch (elf.symPtr(sym_index)) {
                inline else => |sym| elf.targetStore(&sym.value, @intCast(new_value)),
            }

            // Update the symbol value in `.dynsym` if applicable
            switch (sym_id.unwrap()) {
                .local => {},
                .global => |name| {
                    const g = elf.globalByName(name).?;
                    if (g.dynsym_index != 0) {
                        switch (elf.dynsymPtr(g.dynsym_index)) {
                            inline else => |sym| elf.targetStore(&sym.value, @intCast(new_value)),
                        }
                    }
                },
            }

            // Re-apply relocations targeting this symbol
            if (elf.ehdrField(.type) != .REL) {
                sym_id.applyTargetRelocs(elf);
            }

            // Update GOT entries targeting this symbol
            if (elf.got.getIndex(.{ .symbol = sym_id })) |got_index| {
                elf.updateGotEntry(got_index);
            }
            if (elf.got.getIndex(.{ .tpoff = sym_id })) |got_index| {
                elf.updateGotEntry(got_index);
            }
            if (elf.got.getIndex(.{ .tlsgd0 = sym_id })) |got_index| {
                elf.updateGotEntry(got_index);
                elf.updateGotEntry(got_index + 1); // tlsgd1
            }
        }

        fn applyTargetRelocs(sym_id: Symbol.Id, elf: *Elf) void {
            assert(elf.ehdrField(.type) != .REL);
            var ri = sym_id.index(elf).ptr(elf).first_target_reloc;
            while (ri != .none) {
                const reloc = ri.get(elf);
                assert(reloc.target == sym_id);
                reloc.apply(elf);
                ri = reloc.next;
            }
        }

        /// Scans through all relocations targeting `sym_id` and, for each one with a dynamic
        /// relocation entry, either deletes it or converts it to R_*_RELATIVE as required.
        ///
        /// Asserts we are creating a DSO.
        fn deleteDynamicTargetRelocs(sym_id: Symbol.Id, elf: *Elf) void {
            assert(elf.ehdrField(.type) != .REL);
            assert(elf.shndx.dynamic != .UNDEF);
            var ri = sym_id.index(elf).ptr(elf).first_target_reloc;
            while (ri != .none) {
                const reloc = ri.get(elf);
                assert(reloc.target == sym_id);
                reloc.deleteOutputRel(elf);
                ri = reloc.next;
            }
            switch (elf.classifySymbolValue(sym_id)) {
                .static => return,
                .static_relative => {},
                .dynamic => unreachable,
            }
            // We removed the symbol relocations, now add R_*_RELATIVE relocations where needed.
            ri = sym_id.index(elf).ptr(elf).first_target_reloc;
            while (ri != .none) {
                const reloc = ri.get(elf);
                ri = reloc.next;
                assert(reloc.target == sym_id);
                if (!reloc.type.isAbsAddr(elf)) continue;
                switch (elf.nodeWantsDsoRelocation(reloc.node)) {
                    .no => continue,
                    .yes_textrel => elf.textrel_count += 1,
                    .yes => {},
                }
                const node_vaddr: u64 = switch (elf.getNode(reloc.node)) {
                    .file => unreachable,
                    .ehdr => unreachable,
                    .shdr => unreachable,
                    .segment => unreachable,
                    .copied_global => unreachable,
                    .section => |shndx| shndx.vaddr(elf),
                    .input_section => |isi| isi.ptrConst(elf).vaddr,
                    inline .nav,
                    .uav,
                    .lazy_code,
                    .lazy_const_data,
                    => |i| Symbol.Id.local(i.symbol(elf)).value(elf),
                };
                // There is capacity for a relocation because we just deleted one earlier.
                reloc.rela_index = elf.shndx.rela_dyn.relaAddOneAssumeCapacity(elf, .{
                    .type = .relative(elf),
                    .offset = node_vaddr + reloc.offset,
                    .raw_sym_index = 0,
                    .addend = 0,
                }).toOptional();
            }
        }

        /// Returns `true` if the target of `s` has moved, meaning the symbol's value will change at
        /// some point due to a call to `flushMoved`.
        fn hasMoved(s: Symbol.Id, elf: *Elf) bool {
            const node = s.index(elf).ptr(elf).node;
            if (node != .none) {
                return node.hasMoved(&elf.mf);
            }
            switch (s.unwrap()) {
                .local => {},
                .global => |name| if (elf.copied_globals.getPtr(name)) |copied_global| {
                    return copied_global.node.hasMoved(&elf.mf);
                },
            }
            return false;
        }
    };
};

fn globalByName(elf: *const Elf, name: String(.strtab)) ?*Symbol.Global {
    if (elf.globals.strong_def.getPtr(name)) |ptr| return ptr;
    if (elf.globals.weak_def.getPtr(name)) |ptr| return ptr;
    if (elf.globals.strong_undef.getPtr(name)) |ptr| return ptr;
    if (elf.globals.weak_undef.getPtr(name)) |ptr| return ptr;
    return null;
}

fn classifySymbolValue(elf: *Elf, sym: Symbol.Id) enum {
    /// This symbol's value is guaranteed to equal `sym.value(elf)`.
    static,
    /// This symbol's value is an offset of `sym.value(elf)` from the runtime-known load address of
    /// this DSO (which is position-independent).
    static_relative,
    /// This symbol's definition does not necessarily come from this DSO, so is not known until RTLD
    /// runs. Therefore, a dynamic (runtime) relocation is necessary.
    dynamic,
} {
    const comp = elf.base.comp;

    const runtime_load_addr = switch (elf.ehdrField(.type)) {
        .NONE, .CORE, _ => unreachable,
        .REL => unreachable,
        .DYN => true,
        .EXEC => false,
    };

    if (elf.shndx.dynamic == .UNDEF) {
        // This is a static non-PIE executable---every symbol has a statically known value.
        return .static;
    }

    const shndx: Section.Index, const visibility: std.elf.STV = switch (elf.symPtr(sym.index(elf))) {
        inline else => |sym_ptr| .{
            .fromSection(elf.targetLoad(&sym_ptr.shndx)),
            elf.targetLoad(&sym_ptr.other).visibility,
        },
    };

    switch (sym.unwrap()) {
        .local => {
            assert(shndx != .UNDEF);
            assert(visibility == .DEFAULT);
        },
        .global => |name| if (visibility == .DEFAULT and comp.config.output_mode != .Exe) {
            // An unprotected symbol in a DSO which is not an executable is subject to runtime
            // preemption, so a dynamic relocation is required for it even if we have a definition.
            return .dynamic;
        } else if (elf.copied_globals.contains(name)) {
            // This becomes a locally-defined symbol in `.data`.
            return if (runtime_load_addr) .static_relative else .static;
        },
    }

    return switch (shndx) {
        .UNDEF => switch (visibility) {
            .DEFAULT => if (comp.config.link_mode == .static and comp.config.output_mode == .Exe) {
                assert(comp.config.pie); // non-PIE static exe should not have a `.dynamic` section
                // This is a static PIE---the only dynamic relocations are `R_*_RELATIVE`.
                return .static;
            } else .dynamic, // external symbol

            // If the symbol *cannot* be external, then there's no point making a dynamic relocation
            // now---if linking succeeds we won't need anything more than perhaps an `R_*_RELATIVE`.
            .INTERNAL, .HIDDEN, .PROTECTED => .static,
        },

        .ABS => .static,

        else => if (runtime_load_addr and
            shndx.flags(elf).ALLOC and
            !shndx.flags(elf).TLS)
        {
            return .static_relative;
        } else {
            return .static;
        },
    };
}

pub fn symbolForAtom(elf: *Elf, atom: link.File.AtomId) link.File.SymbolId {
    const lsi: Symbol.LocalIndex = switch (elf.getNode(Node.fromAtom(atom))) {
        .file,
        .ehdr,
        .shdr,
        .segment,
        .section,
        .input_section,
        .copied_global,
        => unreachable,

        inline .nav,
        .uav,
        .lazy_code,
        .lazy_const_data,
        => |i| i.symbol(elf),
    };
    const s: Symbol.Id = .local(lsi);
    return s.toTypeErased();
}
pub fn lazySymbol(elf: *Elf, lazy: link.File.LazySymbol) link.Error!link.File.SymbolId {
    const diags = &elf.base.comp.link_diags;
    return elf.lazySymbolInner(lazy) catch |err| switch (err) {
        error.MappedFileIo => return diags.fail("failed to write output file: {t}", .{elf.mf.io_err.?}),
        else => |e| return e,
    };
}
fn lazySymbolInner(elf: *Elf, lazy: link.File.LazySymbol) Error!link.File.SymbolId {
    const gpa = elf.base.comp.gpa;

    try elf.ensureUnusedSymbolCapacity(1, .all_local);
    try elf.nodes.ensureUnusedCapacity(gpa, 1);
    try elf.lazy.getPtr(lazy.kind).map.ensureUnusedCapacity(gpa, 1);

    const gop = elf.lazy.getPtr(lazy.kind).map.getOrPutAssumeCapacity(lazy.ty);
    if (!gop.found_existing) {
        const shndx: Section.Index, const sym_type: std.elf.STT = switch (lazy.kind) {
            .code => .{ .text, .FUNC },
            .const_data => .{ .rodata, .OBJECT },
        };
        const node = try elf.mf.addLastChildNode(gpa, shndx.get(elf).ni, .{});
        var name_buf: [64]u8 = undefined;
        const name = std.fmt.bufPrint(
            &name_buf,
            "__lazy_{t}_{d}",
            .{ lazy.kind, @intFromEnum(lazy.ty) },
        ) catch unreachable;
        gop.value_ptr.* = .{
            .lsi = elf.addLocalSymbolAssumeCapacity(.{
                .node = node,
                .name = try elf.string(.strtab, name),
                .value = 0,
                .size = 0,
                .type = sym_type,
                .shndx = shndx,
            }),
            .first_symbol_reloc = .none,
            .first_got_reloc = .none,
        };
        elf.nodes.appendAssumeCapacity(switch (lazy.kind) {
            .code => .{ .lazy_code = @enumFromInt(gop.index) },
            .const_data => .{ .lazy_const_data = @enumFromInt(gop.index) },
        });
        elf.synth_prog_node.increaseEstimatedTotalItems(1);
    }
    const s: Symbol.Id = .local(gop.value_ptr.lsi);
    return s.toTypeErased();
}
pub const ExternSymbolOpts = struct {
    name: []const u8,
    lib_name: ?[]const u8,
    type: std.elf.STT,
    linkage: std.lang.GlobalLinkage = .strong,
    visibility: std.lang.SymbolVisibility = .default,
};
pub fn externSymbol(elf: *Elf, opts: ExternSymbolOpts) link.Error!link.File.SymbolId {
    const diags = &elf.base.comp.link_diags;
    return (elf.externSymbolInner(opts) catch |err| switch (err) {
        error.MappedFileIo => return diags.fail("failed to write output file: {t}", .{elf.mf.io_err.?}),
        else => |e| return e,
    }).toTypeErased();
}
fn externSymbolInner(elf: *Elf, opts: ExternSymbolOpts) Error!Symbol.Id {
    try elf.ensureUnusedSymbolCapacity(1, .maybe_global);
    const symbol = elf.addGlobalSymbolAssumeCapacity(.{
        .node = .none,
        .name = try .string(elf, opts.name),
        .lib_name = opts.lib_name,
        .value = 0,
        .size = 0,
        .type = opts.type,
        .bind = switch (opts.linkage) {
            .internal => @panic("TODO internal extern symbol"),
            .strong => .strong,
            .weak => .weak,
            .link_once => return elf.base.comp.link_diags.fail("TODO(Elf2): link_once is not supported", .{}),
        },
        .visibility = switch (opts.visibility) {
            .default => .DEFAULT,
            .hidden => .HIDDEN,
            .protected => .PROTECTED,
        },
        .shndx = .UNDEF,
    }) catch |err| switch (err) {
        error.MultipleDefinitions => unreachable, // shndx is undef
    };
    return symbol;
}
pub fn addReloc(
    elf: *Elf,
    atom: link.File.AtomId,
    offset: u64,
    target: link.File.SymbolId,
    addend: i64,
    @"type": MachineRelocType,
) link.Error!void {
    const node: MappedFile.Node.Index = Node.fromAtom(atom);
    const diags = &elf.base.comp.link_diags;
    elf.ensureUnusedRelocCapacity(node, 1) catch |err| switch (err) {
        error.MappedFileIo => return diags.fail("failed to write output file: {t}", .{elf.mf.io_err.?}),
        else => |e| return e,
    };
    elf.addRelocAssumeCapacity(node, offset, .fromTypeErased(target), addend, @"type") catch |err| switch (err) {
        error.MappedFileIo => return diags.fail("failed to write output file: {t}", .{elf.mf.io_err.?}),
        else => |e| return e,
    };
}
pub fn navSymbol(elf: *Elf, nav_index: InternPool.Nav.Index) link.Error!link.File.SymbolId {
    const diags = &elf.base.comp.link_diags;
    const zcu = elf.base.comp.zcu.?;
    const ip = &zcu.intern_pool;
    const nav = ip.getNav(nav_index);
    if (nav.getExtern(ip)) |@"extern"| {
        return elf.externSymbol(.{
            .name = @"extern".name.toSlice(ip),
            .lib_name = @"extern".lib_name.toSlice(ip),
            .type = elf.navType(nav.resolved.?),
            .linkage = @"extern".linkage,
            .visibility = @"extern".visibility,
        });
    }
    const nmi = elf.navMapIndex(zcu, nav_index) catch |err| switch (err) {
        error.MappedFileIo => return diags.fail("failed to write output file: {t}", .{elf.mf.io_err.?}),
        else => |e| return e,
    };
    const s: Symbol.Id = .local(nmi.symbol(elf));
    return s.toTypeErased();
}
pub fn uavSymbol(
    elf: *Elf,
    uav_val: InternPool.Index,
    uav_align: InternPool.Alignment,
) link.Error!link.File.SymbolId {
    const diags = &elf.base.comp.link_diags;
    const umi = elf.uavMapIndex(uav_val, uav_align) catch |err| switch (err) {
        error.MappedFileIo => return diags.fail("failed to write output file: {t}", .{elf.mf.io_err.?}),
        else => |e| return e,
    };
    const s: Symbol.Id = .local(umi.symbol(elf));
    return s.toTypeErased();
}
pub fn getNavVAddr(
    elf: *Elf,
    pt: Zcu.PerThread,
    nav: InternPool.Nav.Index,
    reloc_info: link.File.RelocInfo,
) link.Error!u64 {
    _ = pt;
    return elf.getVAddr(reloc_info, try elf.navSymbol(nav));
}
pub fn getUavVAddr(
    elf: *Elf,
    uav_val: InternPool.Index,
    reloc_info: link.File.RelocInfo,
) link.Error!u64 {
    return elf.getVAddr(reloc_info, try elf.uavSymbol(uav_val, .none));
}
pub fn getVAddr(elf: *Elf, reloc_info: link.File.RelocInfo, target: link.File.SymbolId) link.Error!u64 {
    try elf.addReloc(
        reloc_info.parent.atom_index,
        reloc_info.offset,
        target,
        reloc_info.addend,
        .absAddr(elf),
    );
    return Symbol.Id.fromTypeErased(target).value(elf);
}
pub fn lowerUav(
    elf: *Elf,
    pt: Zcu.PerThread,
    uav_val: InternPool.Index,
    uav_align: InternPool.Alignment,
) link.Error!link.File.SymbolId {
    _ = pt;
    const diags = &elf.base.comp.link_diags;
    const umi = elf.uavMapIndex(uav_val, uav_align) catch |err| switch (err) {
        error.MappedFileIo => return diags.fail("failed to write output file: {t}", .{elf.mf.io_err.?}),
        else => |e| return e,
    };
    const s: Symbol.Id = .local(umi.symbol(elf));
    return s.toTypeErased();
}

const StringSection = enum {
    shstrtab,
    strtab,
    dynstr,
    fn shndx(s: StringSection, elf: *const Elf) Section.Index {
        return switch (s) {
            .strtab => .strtab,
            .shstrtab => .shstrtab,
            .dynstr => elf.shndx.dynstr,
        };
    }
};
fn String(section: StringSection) type {
    return enum(u32) {
        empty = 0,
        _,

        fn slice(str: @This(), elf: *Elf) [:0]const u8 {
            const section_node = section.shndx(elf).get(elf).ni;
            const overlong = section_node.sliceConst(&elf.mf)[@intFromEnum(str)..];
            return overlong[0..std.mem.findScalar(u8, overlong, 0).? :0];
        }
    };
}
fn string(elf: *Elf, comptime section: StringSection, key: []const u8) Error!String(section) {
    const st: *StringTable = &@field(elf, @tagName(section));
    return @enumFromInt(try st.get(elf, section.shndx(elf), key));
}
/// Like `string`, but asserts that the string is already in `section`.
fn stringExisting(elf: *Elf, comptime section: StringSection, key: []const u8) String(section) {
    const st: *StringTable = &@field(elf, @tagName(section));
    return @enumFromInt(st.getExisting(elf, section.shndx(elf), key));
}

const StringTable = struct {
    map: std.HashMapUnmanaged(u32, void, StringTable.Context, std.hash_map.default_max_load_percentage),

    const Context = struct {
        slice: []const u8,

        pub fn eql(_: Context, lhs_key: u32, rhs_key: u32) bool {
            return lhs_key == rhs_key;
        }

        pub fn hash(ctx: Context, key: u32) u64 {
            return std.hash_map.hashString(std.mem.sliceTo(ctx.slice[key..], 0));
        }
    };

    const Adapter = struct {
        slice: []const u8,

        pub fn eql(adapter: Adapter, lhs_key: []const u8, rhs_key: u32) bool {
            return std.mem.startsWith(u8, adapter.slice[rhs_key..], lhs_key) and
                adapter.slice[rhs_key + lhs_key.len] == 0;
        }

        pub fn hash(_: Adapter, key: []const u8) u64 {
            assert(std.mem.indexOfScalar(u8, key, 0) == null);
            return std.hash_map.hashString(key);
        }
    };

    fn getExisting(st: *StringTable, elf: *Elf, shndx: Section.Index, key: []const u8) u32 {
        if (key.len == 0) return 0;
        const slice_const = shndx.get(elf).ni.sliceConst(&elf.mf);
        const adapter: StringTable.Adapter = .{ .slice = slice_const };
        return st.map.getKeyAdapted(key, adapter).?;
    }

    fn get(st: *StringTable, elf: *Elf, shndx: Section.Index, key: []const u8) Error!u32 {
        // If we are in `initHeaders` the strtab might not be initalized yet, so we need to special
        // case the empty string.
        if (key.len == 0) return 0;

        const gpa = elf.base.comp.gpa;
        const ni = shndx.get(elf).ni;
        const slice_const = ni.sliceConst(&elf.mf);
        const gop = try st.map.getOrPutContextAdapted(
            gpa,
            key,
            StringTable.Adapter{ .slice = slice_const },
            .{ .slice = slice_const },
        );
        if (gop.found_existing) return gop.key_ptr.*;
        const old_size, const new_size = size: switch (elf.shdrPtr(shndx)) {
            inline else => |shdr| {
                const old_size: u32 = @intCast(elf.targetLoad(&shdr.size));
                const new_size: u32 = @intCast(old_size + key.len + 1);
                elf.targetStore(&shdr.size, new_size);
                break :size .{ old_size, new_size };
            },
        };
        if (shndx == elf.shndx.dynstr) {
            elf.updateDynamicEntry(std.elf.DT_STRSZ, new_size);
        }
        try elf.ensureNodeSize(ni, new_size);
        const slice = ni.slice(&elf.mf)[old_size..];
        @memcpy(slice[0..key.len], key);
        slice[key.len] = 0;
        gop.key_ptr.* = old_size;
        return old_size;
    }
};

const GotIndex = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn wrap(i: ?u32) GotIndex {
        const gi: GotIndex = @enumFromInt(i orelse return .none);
        assert(gi != .none);
        return gi;
    }
    pub fn unwrap(gi: GotIndex) ?u32 {
        return switch (gi) {
            _ => @intFromEnum(gi),
            .none => null,
        };
    }
};

pub fn open(
    arena: std.mem.Allocator,
    comp: *Compilation,
    path: std.Build.Cache.Path,
    options: link.File.OpenOptions,
) !*Elf {
    return create(arena, comp, path, options);
}
pub fn createEmpty(
    arena: std.mem.Allocator,
    comp: *Compilation,
    path: std.Build.Cache.Path,
    options: link.File.OpenOptions,
) !*Elf {
    return create(arena, comp, path, options);
}
fn create(
    arena: std.mem.Allocator,
    comp: *Compilation,
    path: std.Build.Cache.Path,
    options: link.File.OpenOptions,
) !*Elf {
    const io = comp.io;
    const target = &comp.root_mod.resolved_target.result;
    assert(target.ofmt == .elf);
    const class: std.elf.CLASS = switch (target.ptrBitWidth()) {
        0...32 => .@"32",
        33...64 => .@"64",
        else => return error.UnsupportedELFArchitecture,
    };
    const data: std.elf.DATA = switch (target.cpu.arch.endian()) {
        .little => .@"2LSB",
        .big => .@"2MSB",
    };
    const osabi: std.elf.OSABI = switch (target.os.tag) {
        else => if (target.abi.isGnu()) .GNU else .NONE,
        .freestanding, .other => .STANDALONE,
        .netbsd => .NETBSD,
        .illumos => .SOLARIS,
        .freebsd, .ps4 => .FREEBSD,
        .openbsd => .OPENBSD,
        .cuda => .CUDA,
        .amdhsa => .AMDGPU_HSA,
        .amdpal => .AMDGPU_PAL,
        .mesa3d => .AMDGPU_MESA3D,
    };
    const @"type": std.elf.ET = switch (comp.config.output_mode) {
        .Exe => if (comp.config.pie or target.os.tag == .haiku) .DYN else .EXEC,
        .Lib => switch (comp.config.link_mode) {
            .static => .REL,
            .dynamic => .DYN,
        },
        .Obj => .REL,
    };
    const machine = target.toElfMachine();
    const maybe_interp = switch (comp.config.link_mode) {
        .static => null,
        .dynamic => switch (comp.config.output_mode) {
            .Exe => target.dynamic_linker.get(),
            .Lib => if (comp.root_mod.resolved_target.is_explicit_dynamic_linker)
                target.dynamic_linker.get()
            else
                null,
            .Obj => null,
        },
    };

    const elf = try arena.create(Elf);
    const file = try path.root_dir.handle.createFile(io, path.sub_path, .{
        .read = true,
        .permissions = link.File.determinePermissions(comp.config.output_mode, comp.config.link_mode),
    });
    errdefer file.close(io);
    elf.* = .{
        .base = .{
            .tag = .elf2,

            .comp = comp,
            .emit = path,

            .file = file,
            .gc_sections = false,
            .print_gc_sections = false,
            .build_id = .none,
            .allow_shlib_undefined = false,
            .stack_size = 0,
        },
        .options = options,
        .mf = try .init(file, comp.gpa, io),
        .ni = .{
            .tls = .none,
        },
        .nodes = .empty,
        .shdrs = .empty,
        .phdrs = .empty,
        .shndx = .{
            .got = .UNDEF,
            .got_plt = .UNDEF,
            .plt = .UNDEF,
            .plt_sec = .UNDEF,
            .dynsym = .UNDEF,
            .dynstr = .UNDEF,
            .dynamic = .UNDEF,
            .tdata = .UNDEF,
            .rela_dyn = .UNDEF,
            .rela_plt = .UNDEF,
            .init_array = .UNDEF,
            .fini_array = .UNDEF,
            .preinit_array = .UNDEF,
        },
        .symtab = .empty,
        .globals = .{
            .strong_def = .empty,
            .weak_def = .empty,
            .strong_undef = .empty,
            .weak_undef = .empty,
        },
        .copied_globals = .empty,
        .want_copied_globals = .empty,
        .node_global_symbols = .empty,
        .dso_globals = .empty,
        .shstrtab = .{ .map = .empty },
        .strtab = .{ .map = .empty },
        .dynstr = .{ .map = .empty },
        .got = .empty,
        .plt = .empty,
        .plt_first_symbol_reloc = .none,
        .dynamic_first_symbol_reloc = .none,
        .needed = .empty,
        .inputs = .empty,
        .input_sections = .empty,
        .input_section_pending_index = 0,
        .navs = .empty,
        .uavs = .empty,
        .lazy = comptime .initFill(.{
            .map = .empty,
            .pending_index = 0,
        }),
        .pending_uavs = .empty,
        .symbol_relocs = .empty,
        .got_relocs = .empty,
        .tls_size_symbol_relocs = .empty,
        .section_by_name = .empty,
        .changed_symtab_index = .empty,
        .const_prog_node = .none,
        .synth_prog_node = .none,
        .input_prog_node = .none,
        .textrel_count = 0,
    };
    errdefer elf.deinit();

    try elf.initHeaders(class, data, osabi, @"type", machine, maybe_interp);
    return elf;
}

pub fn deinit(elf: *Elf) void {
    const gpa = elf.base.comp.gpa;
    elf.mf.deinit(gpa);
    elf.nodes.deinit(gpa);
    elf.shdrs.deinit(gpa);
    elf.phdrs.deinit(gpa);
    elf.symtab.deinit(gpa);
    elf.globals.strong_def.deinit(gpa);
    elf.globals.weak_def.deinit(gpa);
    elf.globals.strong_undef.deinit(gpa);
    elf.globals.weak_undef.deinit(gpa);
    elf.copied_globals.deinit(gpa);
    elf.want_copied_globals.deinit(gpa);
    elf.node_global_symbols.deinit(gpa);
    elf.dso_globals.deinit(gpa);
    elf.shstrtab.map.deinit(gpa);
    elf.strtab.map.deinit(gpa);
    elf.dynstr.map.deinit(gpa);
    elf.got.deinit(gpa);
    elf.plt.deinit(gpa);
    elf.needed.deinit(gpa);
    for (elf.inputs.items) |input| if (input.member) |m| gpa.free(m);
    elf.inputs.deinit(gpa);
    elf.input_sections.deinit(gpa);
    elf.navs.deinit(gpa);
    elf.uavs.deinit(gpa);
    for (&elf.lazy.values) |*lazy| lazy.map.deinit(gpa);
    elf.pending_uavs.deinit(gpa);
    elf.symbol_relocs.deinit(gpa);
    elf.got_relocs.deinit(gpa);
    elf.tls_size_symbol_relocs.deinit(gpa);
    elf.section_by_name.deinit(gpa);
    elf.changed_symtab_index.deinit(gpa);
    elf.* = undefined;
}

fn initHeaders(
    elf: *Elf,
    class: std.elf.CLASS,
    data: std.elf.DATA,
    osabi: std.elf.OSABI,
    @"type": std.elf.ET,
    machine: std.elf.EM,
    maybe_interp: ?[]const u8,
) !void {
    const comp = elf.base.comp;
    const gpa = comp.gpa;
    const have_dynamic_section = switch (@"type") {
        .NONE, .CORE, _ => unreachable,
        .REL => false,
        .EXEC => comp.config.link_mode == .dynamic,
        .DYN => true,
    };
    const addr_align: std.mem.Alignment = switch (class) {
        .NONE, _ => unreachable,
        .@"32" => .@"4",
        .@"64" => .@"8",
    };

    const init_plt_size: std.elf.Xword, const plt_align: std.mem.Alignment, const got_plt, const plt_sec =
        switch (machine) {
            else => @panic(@tagName(machine)),
            .LOONGARCH => .{ 16 * 2, .@"4", true, false },
            .SPARCV9 => .{ 32 * 4, .fromByteUnits(256), false, false },
            .X86_64 => .{ 16, .@"16", true, true },
        };

    const shnum: u32 = shnum: {
        var shnum: u32 = 1; // reserved ("null") shdr
        shnum += 1; // .symtab
        shnum += 1; // .shstrtab
        shnum += 1; // .strtab
        shnum += @intFromBool(maybe_interp != null); // .interp
        shnum += 1; // .rodata
        shnum += 1; // .text
        shnum += 1; // .data
        shnum += @intFromBool(comp.config.any_non_single_threaded); // .tdata
        shnum += 1; // .data.rel.ro
        if (have_dynamic_section) {
            shnum += 1; // .dynamic
            shnum += 1; // .dynstr
            shnum += 1; // .dynsym
            shnum += 1; // .rela.dyn
            shnum += 1; // .rela.plt
        }
        if (@"type" != .REL) {
            shnum += 1; // .got
            shnum += @intFromBool(got_plt); // .got.plt
            shnum += 1; // .plt
            shnum += @intFromBool(plt_sec); // .plt_sec
        }
        break :shnum shnum;
    };

    const phndx: struct {
        phdr: u32,
        interp: u32,
        rodata: u32,
        text: u32,
        data: u32,
        tls: u32,
        dynamic: u32,
        relro: u32,
        gnu_stack: u32,
    }, const phnum: u32 = ph: {
        switch (@"type") {
            .NONE, .CORE, _ => unreachable,
            .REL => break :ph .{ undefined, 0 },
            .EXEC, .DYN => {},
        }
        var phnum: u32 = 0;
        break :ph .{ .{
            .phdr = phndx: {
                defer phnum += 1;
                break :phndx phnum;
            },
            .interp = if (maybe_interp) |_| phndx: {
                defer phnum += 1;
                break :phndx phnum;
            } else undefined,
            .rodata = phndx: {
                defer phnum += 1;
                break :phndx phnum;
            },
            .text = phndx: {
                defer phnum += 1;
                break :phndx phnum;
            },
            .data = phndx: {
                defer phnum += 1;
                break :phndx phnum;
            },
            .tls = if (comp.config.any_non_single_threaded) phndx: {
                defer phnum += 1;
                break :phndx phnum;
            } else undefined,
            .dynamic = if (have_dynamic_section) phndx: {
                defer phnum += 1;
                break :phndx phnum;
            } else undefined,
            .relro = phndx: {
                defer phnum += 1;
                break :phndx phnum;
            },
            .gnu_stack = phndx: {
                defer phnum += 1;
                break :phndx phnum;
            },
        }, phnum };
    };

    const expected_nodes_len = 3 + // `.file`, `.ehdr`, and `.shdr` nodes
        (shnum - 1) + // -1 because the null shdr does not have a `.section` node
        (phnum -| 1); // -1 because the GNU_STACK phdr does not have a `.segment` node

    try elf.nodes.ensureTotalCapacity(gpa, expected_nodes_len);
    try elf.shdrs.ensureTotalCapacity(gpa, shnum);
    try elf.section_by_name.ensureUnusedCapacity(gpa, shnum);
    try elf.phdrs.resize(gpa, phnum);
    try elf.symtab.ensureTotalCapacity(gpa, 1);
    elf.nodes.appendAssumeCapacity(.file);

    switch (class) {
        .NONE, _ => unreachable,
        inline else => |ct_class| {
            const ElfN = ct_class.ElfN();
            assert(elf.ni.ehdr == try elf.mf.addOnlyChildNode(gpa, elf.ni.file, .{
                .size = @sizeOf(ElfN.Ehdr),
                .alignment = addr_align,
                .fixed = true,
            }));
            elf.nodes.appendAssumeCapacity(.ehdr);

            const ehdr: *ElfN.Ehdr = @ptrCast(@alignCast(elf.ni.ehdr.slice(&elf.mf)));
            ehdr.ident = .{
                .class = class,
                .data = data,
                .version = 1,
                .osabi = osabi,
                .abiversion = 0,
            };
            ehdr.type = @"type";
            ehdr.machine = machine;
            ehdr.version = 1;
            ehdr.entry = 0;
            ehdr.phoff = 0;
            ehdr.shoff = 0;
            ehdr.flags = switch (machine) {
                .LOONGARCH => e_flags: {
                    const target_cpu = &elf.base.comp.getTarget().cpu;
                    const e_flags: std.elf.loongarch.EFlags = .{
                        .base_abi_modifier = if (target_cpu.has(.loongarch, .d))
                            .d
                        else if (target_cpu.has(.loongarch, .f))
                            .f
                        else
                            .s,
                        .abi_extension = .base,
                        .abi_version = 1,
                    };
                    break :e_flags @bitCast(e_flags);
                },
                .SPARCV9 => e_flags: {
                    const e_flags: std.elf.sparc.EFlags = .{
                        .mm = .rmo,
                        .ext = .{
                            .@"32plus" = false,
                            .sun_us1 = false,
                            .hal_r1 = false,
                            .sun_us3 = false,
                            .le_data = false,
                        },
                    };
                    break :e_flags @bitCast(e_flags);
                },
                .X86_64 => 0,
                else => @panic(@tagName(machine)),
            };
            ehdr.ehsize = @sizeOf(ElfN.Ehdr);
            ehdr.phentsize = @sizeOf(ElfN.Phdr);
            ehdr.phnum = @min(phnum, std.elf.PN_XNUM);
            ehdr.shentsize = @sizeOf(ElfN.Shdr);
            ehdr.shnum = 1; // Only the null shdr initially---will be incremented by `addSection`
            ehdr.shstrndx = std.elf.SHN_UNDEF;
            if (elf.targetEndian() != native_endian) std.mem.byteSwapAllFields(ElfN.Ehdr, ehdr);
        },
    }

    assert(elf.ni.shdr == try elf.mf.addLastChildNode(gpa, elf.ni.file, .{
        .size = @as(u64, elf.ehdrField(.shentsize)) * @as(u64, elf.ehdrField(.shnum)),
        .alignment = elf.mf.flags.block_size,
        .moved = true,
        .resized = true,
    }));
    elf.nodes.appendAssumeCapacity(.shdr);

    const page_align: std.mem.Alignment = .fromByteUnits(switch (machine) {
        .BPF,
        .SPARCV9,
        => 0x100000,
        .AARCH64,
        .AMDGPU,
        .QDSP6,
        .MIPS,
        .PPC,
        .PPC64,
        .SPARC,
        .SPARC32PLUS,
        => 0x10000,
        .LOONGARCH,
        => 0x4000,
        .ARC_COMPACT2,
        .@"68K",
        => 0x2000,
        .MSP430,
        => 0x4,
        .AVR,
        => 0x1,
        else => 0x1000,
    });

    var ph_vaddr: u32 = if (@"type" != .REL) ph_vaddr: {
        assert(elf.ni.rodata == try elf.mf.addLastChildNode(gpa, elf.ni.file, .{
            .alignment = elf.mf.flags.block_size,
            .moved = true,
            .bubbles_moved = false,
        }));
        elf.nodes.appendAssumeCapacity(.{ .segment = phndx.rodata });
        elf.phdrs.items[phndx.rodata] = elf.ni.rodata;

        assert(elf.ni.phdr == try elf.mf.addOnlyChildNode(gpa, elf.ni.rodata, .{
            .size = elf.ehdrField(.phentsize) * elf.ehdrField(.phnum),
            .alignment = addr_align,
            .moved = true,
            .resized = true,
            .bubbles_moved = false,
        }));
        elf.nodes.appendAssumeCapacity(.{ .segment = phndx.phdr });
        elf.phdrs.items[phndx.phdr] = elf.ni.phdr;

        assert(elf.ni.text == try elf.mf.addLastChildNode(gpa, elf.ni.file, .{
            .alignment = elf.mf.flags.block_size,
            .moved = true,
            .bubbles_moved = false,
        }));
        elf.nodes.appendAssumeCapacity(.{ .segment = phndx.text });
        elf.phdrs.items[phndx.text] = elf.ni.text;

        assert(elf.ni.data == try elf.mf.addLastChildNode(gpa, elf.ni.file, .{
            .alignment = elf.mf.flags.block_size,
            .moved = true,
            .bubbles_moved = false,
        }));
        elf.nodes.appendAssumeCapacity(.{ .segment = phndx.data });
        elf.phdrs.items[phndx.data] = elf.ni.data;

        assert(elf.ni.data_rel_ro == try elf.mf.addOnlyChildNode(gpa, elf.ni.data, .{
            .alignment = elf.mf.flags.block_size,
            .moved = true,
            .bubbles_moved = false,
        }));
        elf.nodes.appendAssumeCapacity(.{ .segment = phndx.relro });
        elf.phdrs.items[phndx.relro] = elf.ni.data_rel_ro;

        elf.phdrs.items[phndx.gnu_stack] = .none;

        break :ph_vaddr switch (elf.ehdrField(.type)) {
            .NONE, .CORE, _ => unreachable,
            .REL, .DYN => 0,
            .EXEC => switch (machine) {
                .@"386" => 0x400000,
                .AARCH64, .X86_64 => 0x200000,
                .PPC, .PPC64 => 0x10000000,
                .S390 => 0x1000000,
                .SPARCV9 => 0x100000,
                else => 0x10000,
            },
        };
    } else undefined;
    switch (class) {
        .NONE, _ => unreachable,
        inline else => |ct_class| {
            const ElfN = ct_class.ElfN();
            const target_endian = elf.targetEndian();

            if (@"type" != .REL) {
                const phdr: []ElfN.Phdr = @ptrCast(@alignCast(elf.ni.phdr.slice(&elf.mf)));
                const ph_phdr = &phdr[phndx.phdr];
                ph_phdr.* = .{
                    .type = .PHDR,
                    .offset = 0,
                    .vaddr = 0,
                    .paddr = 0,
                    .filesz = 0,
                    .memsz = 0,
                    .flags = .{ .R = true },
                    .@"align" = @intCast(elf.ni.phdr.alignment(&elf.mf).toByteUnits()),
                };
                if (target_endian != native_endian) std.mem.byteSwapAllFields(ElfN.Phdr, ph_phdr);

                if (maybe_interp) |_| {
                    const ph_interp = &phdr[phndx.interp];
                    ph_interp.* = .{
                        .type = .INTERP,
                        .offset = 0,
                        .vaddr = 0,
                        .paddr = 0,
                        .filesz = 0,
                        .memsz = 0,
                        .flags = .{ .R = true },
                        .@"align" = 1,
                    };
                    if (target_endian != native_endian) std.mem.byteSwapAllFields(ElfN.Phdr, ph_interp);
                }

                _, const rodata_size = elf.ni.rodata.location(&elf.mf).resolve(&elf.mf);
                const ph_rodata = &phdr[phndx.rodata];
                ph_rodata.* = .{
                    .type = if (rodata_size == 0) .NULL else .LOAD,
                    .offset = 0,
                    .vaddr = ph_vaddr,
                    .paddr = ph_vaddr,
                    .filesz = @intCast(rodata_size),
                    .memsz = @intCast(rodata_size),
                    .flags = .{ .R = true },
                    .@"align" = @intCast(elf.ni.rodata.alignment(&elf.mf).max(page_align).toByteUnits()),
                };
                if (target_endian != native_endian) std.mem.byteSwapAllFields(ElfN.Phdr, ph_rodata);
                ph_vaddr += @intCast(rodata_size);

                _, const text_size = elf.ni.text.location(&elf.mf).resolve(&elf.mf);
                const ph_text = &phdr[phndx.text];
                ph_text.* = .{
                    .type = if (text_size == 0) .NULL else .LOAD,
                    .offset = 0,
                    .vaddr = ph_vaddr,
                    .paddr = ph_vaddr,
                    .filesz = @intCast(text_size),
                    .memsz = @intCast(text_size),
                    .flags = .{ .R = true, .X = true },
                    .@"align" = @intCast(elf.ni.text.alignment(&elf.mf).max(page_align).toByteUnits()),
                };
                if (target_endian != native_endian) std.mem.byteSwapAllFields(ElfN.Phdr, ph_text);
                ph_vaddr += @intCast(text_size);

                _, const data_size = elf.ni.data.location(&elf.mf).resolve(&elf.mf);
                const ph_data = &phdr[phndx.data];
                ph_data.* = .{
                    .type = if (data_size == 0) .NULL else .LOAD,
                    .offset = 0,
                    .vaddr = ph_vaddr,
                    .paddr = ph_vaddr,
                    .filesz = @intCast(data_size),
                    .memsz = @intCast(data_size),
                    .flags = .{ .R = true, .W = true },
                    .@"align" = @intCast(elf.ni.data.alignment(&elf.mf).max(page_align).toByteUnits()),
                };
                if (target_endian != native_endian) std.mem.byteSwapAllFields(ElfN.Phdr, ph_data);
                ph_vaddr += @intCast(data_size);

                if (comp.config.any_non_single_threaded) {
                    const ph_tls = &phdr[phndx.tls];
                    ph_tls.* = .{
                        .type = .TLS,
                        .offset = 0,
                        .vaddr = 0,
                        .paddr = 0,
                        .filesz = 0,
                        .memsz = 0,
                        .flags = .{ .R = true },
                        .@"align" = @intCast(elf.mf.flags.block_size.toByteUnits()),
                    };
                    if (target_endian != native_endian) std.mem.byteSwapAllFields(ElfN.Phdr, ph_tls);
                }

                if (have_dynamic_section) {
                    const ph_dynamic = &phdr[phndx.dynamic];
                    ph_dynamic.* = .{
                        .type = .DYNAMIC,
                        .offset = 0,
                        .vaddr = 0,
                        .paddr = 0,
                        .filesz = 0,
                        .memsz = 0,
                        .flags = .{ .R = true, .W = true },
                        .@"align" = @intCast(addr_align.toByteUnits()),
                    };
                    if (target_endian != native_endian) std.mem.byteSwapAllFields(ElfN.Phdr, ph_dynamic);
                }

                const ph_relro = &phdr[phndx.relro];
                ph_relro.* = .{
                    .type = .GNU_RELRO,
                    .offset = 0,
                    .vaddr = 0,
                    .paddr = 0,
                    .filesz = 0,
                    .memsz = 0,
                    .flags = .{ .R = true },
                    .@"align" = @intCast(elf.mf.flags.block_size.toByteUnits()),
                };
                if (target_endian != native_endian) std.mem.byteSwapAllFields(ElfN.Phdr, ph_relro);

                const ph_gnu_stack = &phdr[phndx.gnu_stack];
                ph_gnu_stack.* = .{
                    .type = .GNU_STACK,
                    .offset = 0,
                    .vaddr = 0,
                    .paddr = 0,
                    .filesz = 0,
                    .memsz = @intCast(elf.options.stack_size orelse 0),
                    .flags = .{ .R = true, .W = true },
                    .@"align" = 1,
                };
                if (target_endian != native_endian) std.mem.byteSwapAllFields(ElfN.Phdr, ph_gnu_stack);
            }

            const sh_undef: *ElfN.Shdr = @ptrCast(@alignCast(elf.ni.shdr.slice(&elf.mf)));
            sh_undef.* = .{
                .name = @intFromEnum(String(.shstrtab).empty),
                .type = .NULL,
                .flags = .{ .shf = .{} },
                .addr = 0,
                .offset = 0,
                .size = if (shnum < std.elf.SHN_LORESERVE) 0 else shnum,
                .link = 0,
                .info = if (phnum < std.elf.PN_XNUM) 0 else phnum,
                .addralign = 0,
                .entsize = 0,
            };
            if (target_endian != native_endian) std.mem.byteSwapAllFields(ElfN.Shdr, sh_undef);
            elf.shdrs.appendAssumeCapacity(.{ .lsi = .null, .ni = .none, .rela = .{ .shndx = .UNDEF } });

            elf.symtab.addOneAssumeCapacity().* = .{
                .node = .none,
                .first_target_reloc = .none,
            };
            assert(.symtab == try elf.addSection(elf.ni.file, .{
                .type = .SYMTAB,
                .size = @sizeOf(ElfN.Sym) * 1,
                .addralign = addr_align,
                .entsize = @sizeOf(ElfN.Sym),
                .node_align = elf.mf.flags.block_size,
                .info = 1, // index of first non-local symbol
            }));
            const symtab_null = @field(elf.symPtr(.null), @tagName(ct_class));
            symtab_null.* = .{
                .name = @intFromEnum(String(.strtab).empty),
                .value = 0,
                .size = 0,
                .info = .{ .type = .NOTYPE, .bind = .LOCAL },
                .other = .{ .visibility = .DEFAULT },
                .shndx = std.elf.SHN_UNDEF,
            };
            if (target_endian != native_endian) std.mem.byteSwapAllFields(ElfN.Sym, symtab_null);

            const ehdr = @field(elf.ehdrPtr(), @tagName(ct_class));
            ehdr.shstrndx = ehdr.shnum;
        },
    }
    assert(.shstrtab == try elf.addSection(elf.ni.file, .{
        .type = .STRTAB,
        .size = 1,
        .entsize = 1,
        .node_align = elf.mf.flags.block_size,
    }));
    Section.Index.get(.shstrtab, elf).ni.slice(&elf.mf)[0] = 0;

    try Section.Index.symtab.rename(elf, ".symtab");
    try Section.Index.shstrtab.rename(elf, ".shstrtab");

    assert(.strtab == try elf.addSection(elf.ni.file, .{
        .name = ".strtab",
        .type = .STRTAB,
        .size = 1,
        .entsize = 1,
        .node_align = elf.mf.flags.block_size,
    }));
    Section.Index.get(.strtab, elf).ni.slice(&elf.mf)[0] = 0;
    switch (elf.shdrPtr(.symtab)) {
        inline else => |shdr| elf.targetStore(&shdr.link, @intFromEnum(Section.Index.strtab)),
    }

    assert(.rodata == try elf.addSection(elf.ni.rodata, .{
        .name = ".rodata",
        .flags = .{ .ALLOC = true },
        .addralign = elf.mf.flags.block_size,
    }));
    assert(.text == try elf.addSection(elf.ni.text, .{
        .name = ".text",
        .flags = .{ .ALLOC = true, .EXECINSTR = true },
        .addralign = elf.mf.flags.block_size,
    }));
    assert(.data == try elf.addSection(elf.ni.data, .{
        .name = ".data",
        .flags = .{ .WRITE = true, .ALLOC = true },
        .addralign = elf.mf.flags.block_size,
    }));
    assert(.data_rel_ro == try elf.addSection(elf.ni.data_rel_ro, .{
        .name = ".data.rel.ro",
        .flags = .{ .WRITE = true, .ALLOC = true },
        .addralign = elf.mf.flags.block_size,
    }));
    if (@"type" != .REL) {
        elf.shndx.got = try elf.addSection(elf.ni.data_rel_ro, .{
            .name = ".got",
            .type = .PROGBITS,
            // Reserve space for the reserved words, populated later.
            .size = switch (machine) {
                else => @panic(@tagName(machine)),
                .X86_64 => 3 * elf.targetPtrSize(),
                .LOONGARCH,
                .SPARCV9,
                => elf.targetPtrSize(),
            },
            .flags = .{ .WRITE = true, .ALLOC = true },
            .addralign = addr_align,
            .entsize = @intCast(addr_align.toByteUnits()),
        });
        if (got_plt) elf.shndx.got_plt = try elf.addSection(
            if (elf.options.z_now) elf.ni.data_rel_ro else elf.ni.data,
            .{
                .name = ".got.plt",
                .type = .PROGBITS,
                .flags = .{ .WRITE = true, .ALLOC = true },
                .size = switch (machine) {
                    else => @panic(@tagName(machine)),
                    .@"386" => 3 * 4,
                    .X86_64 => 3 * 8,
                    .LOONGARCH => 2 * elf.targetPtrSize(),
                },
                .addralign = addr_align,
                .entsize = @intCast(addr_align.toByteUnits()),
            },
        );
        elf.shndx.plt = try elf.addSection(elf.ni.text, .{
            .name = ".plt",
            .type = .PROGBITS,
            .flags = .{
                .ALLOC = true,
                .EXECINSTR = true,
                .WRITE = switch (machine) {
                    .SPARCV9 => true,
                    else => false,
                },
            },
            .size = init_plt_size,
            .addralign = plt_align,
            .node_align = elf.mf.flags.block_size,
        });
        if (plt_sec) elf.shndx.plt_sec = try elf.addSection(elf.ni.text, .{
            .name = ".plt.sec",
            .flags = .{ .ALLOC = true, .EXECINSTR = true },
            .addralign = plt_align,
            .node_align = elf.mf.flags.block_size,
        });
        if (maybe_interp) |interp| {
            const interp_ni = try elf.mf.addLastChildNode(gpa, elf.ni.rodata, .{
                .size = interp.len + 1,
                .moved = true,
                .resized = true,
                .bubbles_moved = false,
            });
            elf.nodes.appendAssumeCapacity(.{ .segment = phndx.interp });
            elf.phdrs.items[phndx.interp] = interp_ni;

            const sec_interp_shndx = try elf.addSection(interp_ni, .{
                .name = ".interp",
                .type = .PROGBITS,
                .flags = .{ .ALLOC = true },
                .size = @intCast(interp.len + 1),
            });
            const sec_interp = sec_interp_shndx.get(elf).ni.slice(&elf.mf);
            @memcpy(sec_interp[0..interp.len], interp);
            sec_interp[interp.len] = 0;
        }
        if (have_dynamic_section) {
            const dynamic_ni = try elf.mf.addLastChildNode(gpa, elf.ni.data_rel_ro, .{
                .alignment = addr_align,
                .moved = true,
                .bubbles_moved = false,
            });
            elf.nodes.appendAssumeCapacity(.{ .segment = phndx.dynamic });
            elf.phdrs.items[phndx.dynamic] = dynamic_ni;

            const dynstr_shndx = try elf.addSection(elf.ni.rodata, .{
                .name = ".dynstr",
                .type = .STRTAB,
                .flags = .{ .ALLOC = true },
                .size = 1,
                .entsize = 1,
                .node_align = elf.mf.flags.block_size,
            });
            dynstr_shndx.get(elf).ni.slice(&elf.mf)[0] = 0;
            elf.shndx.dynstr = dynstr_shndx;

            switch (class) {
                .NONE, _ => unreachable,
                inline else => |ct_class| {
                    const Sym = ct_class.ElfN().Sym;
                    elf.shndx.dynsym = try elf.addSection(elf.ni.rodata, .{
                        .name = ".dynsym",
                        .type = .DYNSYM,
                        .flags = .{ .ALLOC = true },
                        .size = @sizeOf(Sym) * 1,
                        .link = dynstr_shndx.toSection().?,
                        .info = 1,
                        .addralign = addr_align,
                        .entsize = @sizeOf(Sym),
                        .node_align = elf.mf.flags.block_size,
                    });
                    const dynsym_null = @field(elf.dynsymPtr(0), @tagName(ct_class));
                    dynsym_null.* = .{
                        .name = @intFromEnum(String(.dynstr).empty),
                        .value = 0,
                        .size = 0,
                        .info = .{ .type = .NOTYPE, .bind = .LOCAL },
                        .other = .{ .visibility = .DEFAULT },
                        .shndx = std.elf.SHN_UNDEF,
                    };
                    if (elf.targetEndian() != native_endian) std.mem.byteSwapAllFields(
                        Sym,
                        dynsym_null,
                    );
                },
            }
            const rela_size: std.elf.Word = switch (class) {
                .NONE, _ => unreachable,
                inline else => |ct_class| @sizeOf(ct_class.ElfN().Rela),
            };
            elf.shndx.rela_dyn = try elf.addSection(elf.ni.rodata, .{
                .name = ".rela.dyn",
                .type = .RELA,
                .flags = .{ .ALLOC = true },
                .link = elf.shndx.dynsym.toSection().?,
                .addralign = addr_align,
                .entsize = rela_size,
                .node_align = elf.mf.flags.block_size,
            });
            elf.shndx.rela_plt = try elf.addSection(elf.ni.rodata, .{
                .name = ".rela.plt",
                .type = .RELA,
                .flags = .{ .ALLOC = true, .INFO_LINK = true },
                .link = elf.shndx.dynsym.toSection().?,
                .info = (if (got_plt) elf.shndx.got_plt else elf.shndx.plt).toSection().?,
                .addralign = addr_align,
                .entsize = rela_size,
                .node_align = elf.mf.flags.block_size,
            });
            elf.shndx.dynamic = try elf.addSection(dynamic_ni, .{
                .name = ".dynamic",
                .type = .DYNAMIC,
                .flags = .{ .ALLOC = true, .WRITE = true },
                .link = dynstr_shndx.toSection().?,
                .entsize = @intCast(addr_align.toByteUnits() * 2),
                .node_align = addr_align,
            });
            switch (machine) {
                else => @panic(@tagName(machine)),
                .X86_64 => {
                    const plt_ni = elf.shndx.plt.get(elf).ni;
                    const got_plt_sym: Symbol.Id = .local(elf.shndx.got_plt.get(elf).lsi);
                    @memcpy(plt_ni.slice(&elf.mf)[0..16], &[16]u8{
                        0xff, 0x35, 0x00, 0x00, 0x00, 0x00, // push 0x0(%rip)
                        0xff, 0x25, 0x00, 0x00, 0x00, 0x00, // jmp *0x0(%rip)
                        0x0f, 0x1f, 0x40, 0x00, // nopl 0x0(%rax)
                    });
                    elf.plt_first_symbol_reloc = @enumFromInt(elf.symbol_relocs.items.len);
                    try elf.ensureUnusedRelocCapacity(plt_ni, 2);
                    try elf.addSymbolRelocAssumeCapacity(
                        plt_ni,
                        2,
                        got_plt_sym,
                        8 * 1 - 4,
                        .rel32,
                    );
                    try elf.addSymbolRelocAssumeCapacity(
                        plt_ni,
                        8,
                        got_plt_sym,
                        8 * 2 - 4,
                        .rel32,
                    );
                },
                .LOONGARCH => {
                    const plt_ni = elf.shndx.plt.get(elf).ni;
                    const got_plt_sym: Symbol.Id = .local(elf.shndx.got_plt.get(elf).lsi);
                    @memcpy(plt_ni.slice(&elf.mf)[0..32], switch (class) {
                        .NONE, _ => unreachable,
                        .@"32" => &[32]u8{
                            0x1a, 0x00, 0x00, 0x0e, // pcalau12i $t2, %pc_hi20(.got.plt)
                            0x00, 0x11, 0x3d, 0xad, // sub.w     $t1, $t1, $t3
                            0x28, 0x80, 0x01, 0xcf, // ld.w      $t3, $t2, %lo12(.got.plt) # _dl_runtime_resolve
                            0x02, 0xbf, 0x51, 0xad, // addi.w    $t1, $t1, -44             # .plt entry
                            0x02, 0x80, 0x01, 0xcc, // addi.w    $t0, $t2, %lo12(.got.plt) # &.got.plt
                            0x00, 0x44, 0x89, 0xad, // srli.w    $t1, $t1, 2               # .plt entry offset
                            0x28, 0x80, 0x11, 0x8c, // ld.w      $t0, $t0, 4               # link map
                            0x4c, 0x00, 0x01, 0xe0, // jr        $t3
                        },
                        .@"64" => &[32]u8{
                            0x1a, 0x00, 0x00, 0x0e, // pcalau12i $t2, %pc_hi20(.got.plt)
                            0x00, 0x11, 0xbd, 0xad, // sub.d     $t1, $t1, $t3
                            0x28, 0xc0, 0x01, 0xcf, // ld.d      $t3, $t2, %lo12(.got.plt) # _dl_runtime_resolve
                            0x02, 0xff, 0x51, 0xad, // addi.d    $t1, $t1, -44             # .plt entry
                            0x02, 0xc0, 0x01, 0xcc, // addi.d    $t0, $t2, %lo12(.got.plt) # &.got.plt
                            0x00, 0x45, 0x05, 0xad, // srli.d    $t1, $t1, 1               # .plt entry offset
                            0x28, 0xc0, 0x21, 0x8c, // ld.d      $t0, $t0, 8               # link map
                            0x4c, 0x00, 0x01, 0xe0, // jr        $t3
                        },
                    });
                    elf.plt_first_symbol_reloc = @enumFromInt(elf.symbol_relocs.items.len);
                    try elf.ensureUnusedRelocCapacity(plt_ni, 3);
                    try elf.addSymbolRelocAssumeCapacity(plt_ni, 0, got_plt_sym, 0, .larch_rel32_hi20);
                    try elf.addSymbolRelocAssumeCapacity(plt_ni, 8, got_plt_sym, 0, .larch_abs32_lo12);
                    try elf.addSymbolRelocAssumeCapacity(plt_ni, 16, got_plt_sym, 0, .larch_abs32_lo12);
                },
                .SPARCV9 => {},
            }
        }
        if (comp.config.any_non_single_threaded) {
            elf.ni.tls = try elf.mf.addLastChildNode(gpa, elf.ni.rodata, .{
                .alignment = elf.mf.flags.block_size,
                .moved = true,
                .bubbles_moved = false,
            });
            elf.nodes.appendAssumeCapacity(.{ .segment = phndx.tls });
            elf.phdrs.items[phndx.tls] = elf.ni.tls;
        }

        // Populate reserved GOT words.
        switch (machine) {
            else => @panic(@tagName(machine)),
            .X86_64 => {
                try elf.got.ensureUnusedCapacity(gpa, 3);
                elf.got.putAssumeCapacityNoClobber(switch (have_dynamic_section) {
                    true => .{ .symbol = .local(elf.shndx.dynamic.get(elf).lsi) },
                    false => .{ .reserved = 0 },
                }, .none);
                elf.got.putAssumeCapacityNoClobber(.{ .reserved = 1 }, .none);
                elf.got.putAssumeCapacityNoClobber(.{ .reserved = 2 }, .none);
            },
            .LOONGARCH,
            .SPARCV9,
            => {
                try elf.got.ensureUnusedCapacity(gpa, 1);
                elf.got.putAssumeCapacityNoClobber(switch (have_dynamic_section) {
                    true => .{ .symbol = .local(elf.shndx.dynamic.get(elf).lsi) },
                    false => .{ .reserved = 0 },
                }, .none);
            },
        }
        switch (elf.shdrPtr(elf.shndx.got)) {
            inline else => |shdr, ct_class| {
                const Addr = ct_class.ElfN().Addr;
                assert(elf.targetLoad(&shdr.size) == elf.got.count() * @sizeOf(Addr));
            },
        }

        // Create any always-provided linker-defined symbols. The symbols marking the `INIT_ARRAY`/
        // `FINI_ARRAY`/`PREINIT_ARRAY` sections are instead created by `createInitFiniArraySection`
        // when needed (it seems to be legal to leave those undefined if the section doesn't exist).

        try elf.ensureUnusedSymbolCapacity(10, .maybe_global);
        // Despite the name, `__dso_handle` is necessary even in static binaries.
        _ = elf.addGlobalSymbolAssumeCapacity(.{
            .node = Section.Index.text.get(elf).ni,
            .name = try .string(elf, "__dso_handle"),
            .value = Section.Index.text.vaddr(elf),
            .size = 0,
            .type = .NOTYPE,
            .bind = .weak,
            .visibility = .HIDDEN,
            .shndx = .text,
        }) catch |err| switch (err) {
            error.MultipleDefinitions => unreachable, // no inputs are processed yet
        };
        _ = elf.addGlobalSymbolAssumeCapacity(.{
            .node = elf.shndx.plt.get(elf).ni,
            .name = try .string(elf, "_PROCEDURE_LINKAGE_TABLE_"),
            .value = elf.shndx.plt.vaddr(elf),
            .size = 0,
            .type = .NOTYPE,
            .bind = .strong,
            .visibility = .HIDDEN,
            .shndx = elf.shndx.plt,
        }) catch |err| switch (err) {
            error.MultipleDefinitions => unreachable, // no inputs are processed yet
        };
        _ = elf.addGlobalSymbolAssumeCapacity(.{
            .node = elf.shndx.got.get(elf).ni,
            .name = try .string(elf, "_GLOBAL_OFFSET_TABLE_"),
            .value = switch (machine) {
                .QDSP6, .@"386", .X86_64 => elf.shndx.got_plt.vaddr(elf),
                else => elf.shndx.got.vaddr(elf),
            },
            .size = 0,
            .type = .NOTYPE,
            .bind = .strong,
            .visibility = .HIDDEN,
            .shndx = elf.shndx.got,
        }) catch |err| switch (err) {
            error.MultipleDefinitions => unreachable, // no inputs are processed yet
        };
        _ = elf.addGlobalSymbolAssumeCapacity(.{
            .node = .none,
            .name = try .string(elf, "__init_array_start"),
            .value = 0,
            .size = 0,
            .type = .NOTYPE,
            .bind = .strong,
            .visibility = .HIDDEN,
            .shndx = .ABS,
        }) catch |err| switch (err) {
            error.MultipleDefinitions => unreachable, // no inputs are processed yet
        };
        _ = elf.addGlobalSymbolAssumeCapacity(.{
            .node = .none,
            .name = try .string(elf, "__init_array_end"),
            .value = 0,
            .size = 0,
            .type = .NOTYPE,
            .bind = .strong,
            .visibility = .HIDDEN,
            .shndx = .ABS,
        }) catch |err| switch (err) {
            error.MultipleDefinitions => unreachable, // no inputs are processed yet
        };
        _ = elf.addGlobalSymbolAssumeCapacity(.{
            .node = .none,
            .name = try .string(elf, "__fini_array_start"),
            .value = 0,
            .size = 0,
            .type = .NOTYPE,
            .bind = .strong,
            .visibility = .HIDDEN,
            .shndx = .ABS,
        }) catch |err| switch (err) {
            error.MultipleDefinitions => unreachable, // no inputs are processed yet
        };
        _ = elf.addGlobalSymbolAssumeCapacity(.{
            .node = .none,
            .name = try .string(elf, "__fini_array_end"),
            .value = 0,
            .size = 0,
            .type = .NOTYPE,
            .bind = .strong,
            .visibility = .HIDDEN,
            .shndx = .ABS,
        }) catch |err| switch (err) {
            error.MultipleDefinitions => unreachable, // no inputs are processed yet
        };
        _ = elf.addGlobalSymbolAssumeCapacity(.{
            .node = .none,
            .name = try .string(elf, "__preinit_array_start"),
            .value = 0,
            .size = 0,
            .type = .NOTYPE,
            .bind = .strong,
            .visibility = .HIDDEN,
            .shndx = .ABS,
        }) catch |err| switch (err) {
            error.MultipleDefinitions => unreachable, // no inputs are processed yet
        };
        _ = elf.addGlobalSymbolAssumeCapacity(.{
            .node = .none,
            .name = try .string(elf, "__preinit_array_end"),
            .value = 0,
            .size = 0,
            .type = .NOTYPE,
            .bind = .strong,
            .visibility = .HIDDEN,
            .shndx = .ABS,
        }) catch |err| switch (err) {
            error.MultipleDefinitions => unreachable, // no inputs are processed yet
        };
        if (have_dynamic_section) {
            _ = elf.addGlobalSymbolAssumeCapacity(.{
                .node = elf.shndx.dynamic.get(elf).ni,
                .name = try .string(elf, "_DYNAMIC"),
                .value = elf.shndx.dynamic.vaddr(elf),
                .size = 0,
                .type = .NOTYPE,
                .bind = .strong,
                .visibility = .HIDDEN,
                .shndx = elf.shndx.dynamic,
            }) catch |err| switch (err) {
                error.MultipleDefinitions => unreachable, // no inputs are processed yet
            };
        }
    } else {
        assert(maybe_interp == null);
        assert(!have_dynamic_section);
    }
    if (comp.config.any_non_single_threaded) elf.shndx.tdata = try elf.addSection(elf.ni.tls, .{
        .name = ".tdata",
        .flags = .{ .WRITE = true, .ALLOC = true, .TLS = true },
        .addralign = elf.mf.flags.block_size,
    });

    assert(elf.nodes.len == expected_nodes_len);
    assert(elf.shdrs.items.len == shnum);

    for (0..shnum) |shndx_raw| {
        const shndx: Section.Index = @enumFromInt(shndx_raw);
        elf.section_by_name.putAssumeCapacityNoClobber(shndx.name(elf), {});
    }
}

pub fn startProgress(elf: *Elf, prog_node: std.Progress.Node) void {
    prog_node.increaseEstimatedTotalItems(4);
    elf.const_prog_node = prog_node.start("Constants", elf.pending_uavs.items.len);
    elf.synth_prog_node = prog_node.start("Synthetics", count: {
        var count: usize = 0;
        for (&elf.lazy.values) |*lazy| count += lazy.map.count() - lazy.pending_index;
        break :count count;
    });
    elf.mf.update_prog_node = prog_node.start("Relocations", elf.mf.updates.items.len);
    elf.input_prog_node = prog_node.start(
        "Inputs",
        elf.input_sections.items.len - elf.input_section_pending_index,
    );
}

pub fn endProgress(elf: *Elf) void {
    elf.input_prog_node.end();
    elf.input_prog_node = .none;
    elf.mf.update_prog_node.end();
    elf.mf.update_prog_node = .none;
    elf.synth_prog_node.end();
    elf.synth_prog_node = .none;
    elf.const_prog_node.end();
    elf.const_prog_node = .none;
}

fn getNode(elf: *const Elf, ni: MappedFile.Node.Index) Node {
    return elf.nodes.get(@intFromEnum(ni));
}
/// Asserts that `ni` is a section, input section, copied global, NAV, UAV, or lazy code/data.
fn getNodeShndx(elf: *const Elf, ni: MappedFile.Node.Index) Section.Index {
    return switch (elf.getNode(ni)) {
        .file => unreachable,
        .ehdr => unreachable,
        .shdr => unreachable,
        .segment => unreachable,

        .section => |shndx| shndx,

        .input_section,
        .copied_global,
        .nav,
        .uav,
        .lazy_code,
        .lazy_const_data,
        => elf.getNode(ni.parent(&elf.mf)).section,
    };
}
fn computeNodeVAddr(elf: *Elf, ni: MappedFile.Node.Index) u64 {
    const parent_vaddr = switch (elf.getNode(ni.parent(&elf.mf))) {
        .file => return 0,
        .ehdr, .shdr => unreachable,
        .segment => |phndx| switch (elf.phdrSlice()) {
            inline else => |phdr| elf.targetLoad(&phdr[phndx].vaddr),
        },
        .section => |shndx| if (shndx == elf.shndx.tdata) 0 else shndx.vaddr(elf),
        .input_section => unreachable,
        .copied_global => unreachable,
        inline .nav, .uav, .lazy_code, .lazy_const_data => |i| Symbol.Id.local(i.symbol(elf)).value(elf),
    };
    const offset, _ = ni.location(&elf.mf).resolve(&elf.mf);
    return parent_vaddr + offset;
}

/// Deletes any existing relocations in the given node, and marks the start of the node's contiguous
/// sequence of relocations, so that the caller may append the node's updated relocations.
///
/// Asserts that `ni` must be a node which supports relocations (see `Elf.Node`). Does not support
/// the special-case sections '.plt' and '.dynamic'.
fn resetNodeRelocs(elf: *Elf, ni: MappedFile.Node.Index) void {
    const symbol_relocs: *SymbolReloc.Index, const got_relocs: ?*GotReloc.Index = switch (elf.getNode(ni)) {
        .file => unreachable, // cannot contain relocs
        .ehdr => unreachable, // cannot contain relocs
        .shdr => unreachable, // cannot contain relocs
        .segment => unreachable, // cannot contain relocs
        .section => unreachable, // cannot contain relocs (.plt and .dynamic unsupported)
        .copied_global => unreachable, // cannot contain relocs
        .input_section => |isi| .{
            &elf.input_sections.items[@intFromEnum(isi)].first_symbol_reloc,
            &elf.input_sections.items[@intFromEnum(isi)].first_got_reloc,
        },
        .nav => |nmi| .{
            &elf.navs.values()[@intFromEnum(nmi)].first_symbol_reloc,
            &elf.navs.values()[@intFromEnum(nmi)].first_got_reloc,
        },
        .uav => |umi| .{
            &elf.uavs.values()[@intFromEnum(umi)].first_symbol_reloc,
            null,
        },
        inline .lazy_code, .lazy_const_data => |lmi| .{
            &elf.lazy.getPtr(lmi.ref().kind).map.values()[lmi.ref().index].first_symbol_reloc,
            &elf.lazy.getPtr(lmi.ref().kind).map.values()[lmi.ref().index].first_got_reloc,
        },
    };

    if (symbol_relocs.* != .none) {
        for (
            elf.symbol_relocs.items[@intFromEnum(symbol_relocs.*)..],
            @intFromEnum(symbol_relocs.*)..,
        ) |*reloc, index| {
            if (reloc.node != ni) break;
            reloc.delete(elf, @enumFromInt(index));
        }
    }
    symbol_relocs.* = @enumFromInt(elf.symbol_relocs.items.len);

    if (got_relocs) |ptr| {
        if (ptr.* != .none) {
            for (elf.got_relocs.items[@intFromEnum(ptr.*)..]) |*reloc| {
                if (reloc.node != ni) break;
                reloc.* = .deleted;
            }
        }
        ptr.* = @enumFromInt(elf.got_relocs.items.len);
    }
}

/// Given that `node` has moved, updates all relocations in `node` as needed. In relocatables, this
/// means updating the relocations' offsets. In ELF modules, this means applying the relocations.
fn flushMovedNodeRelocs(
    elf: *Elf,
    node: MappedFile.Node.Index,
    node_vaddr: u64,
    first_symbol_reloc: SymbolReloc.Index,
    first_got_reloc: GotReloc.Index,
) void {
    if (first_symbol_reloc != .none) {
        for (elf.symbol_relocs.items[@intFromEnum(first_symbol_reloc)..]) |*reloc| {
            if (reloc.node != node) break;
            if (reloc.rela_index.unwrap()) |rela_index| {
                // The node has moved, so the offset of the relocation within the section might have
                // changed, so update the `offset` field of the `ElfN.Rela` entry.
                reloc.relaSection(elf).relaSetOffset(elf, rela_index, node_vaddr + reloc.offset);
            }
            reloc.apply(elf);
        }
    }

    if (first_got_reloc != .none) {
        for (elf.got_relocs.items[@intFromEnum(first_got_reloc)..]) |*reloc| {
            if (reloc.node != node) break;
            reloc.apply(elf);
        }
    }
}

fn identClass(elf: *const Elf) std.elf.CLASS {
    return @enumFromInt(elf.mf.memory_map.memory[std.elf.EI.CLASS]);
}
fn identData(elf: *const Elf) std.elf.DATA {
    return @enumFromInt(elf.mf.memory_map.memory[std.elf.EI.DATA]);
}

fn targetPtrSize(elf: *const Elf) u32 {
    return elf.identClass().size();
}
fn targetEndian(elf: *const Elf) std.lang.Endian {
    return elf.identData().endian();
}
fn targetLoad(elf: *const Elf, ptr: anytype) @typeInfo(@TypeOf(ptr)).pointer.child {
    const pointer_ty = @typeInfo(@TypeOf(ptr)).pointer;
    const Child = pointer_ty.child;
    const alignment = pointer_ty.attrs.@"align" orelse @alignOf(Child);
    return switch (@typeInfo(Child)) {
        else => @compileError(@typeName(Child)),
        .int => std.mem.toNative(Child, ptr.*, elf.targetEndian()),
        .@"enum" => |@"enum"| @enumFromInt(elf.targetLoad(@as(*align(alignment) @"enum".tag_type, @ptrCast(ptr)))),
        .@"struct" => |@"struct"| @bitCast(
            elf.targetLoad(@as(*align(alignment) @"struct".backing_integer.?, @ptrCast(ptr))),
        ),
    };
}
fn targetStore(elf: *const Elf, ptr: anytype, val: @typeInfo(@TypeOf(ptr)).pointer.child) void {
    const pointer_ty = @typeInfo(@TypeOf(ptr)).pointer;
    const Child = pointer_ty.child;
    const alignment = pointer_ty.attrs.@"align" orelse @alignOf(Child);
    return switch (@typeInfo(Child)) {
        else => @compileError(@typeName(Child)),
        .int => ptr.* = std.mem.nativeTo(Child, val, elf.targetEndian()),
        .@"enum" => |@"enum"| elf.targetStore(
            @as(*align(alignment) @"enum".tag_type, @ptrCast(ptr)),
            @intFromEnum(val),
        ),
        .@"struct" => |@"struct"| elf.targetStore(
            @as(*align(alignment) @"struct".backing_integer.?, @ptrCast(ptr)),
            @bitCast(val),
        ),
    };
}

const EhdrPtr = union(std.elf.CLASS) {
    NONE: noreturn,
    @"32": *std.elf.Elf32.Ehdr,
    @"64": *std.elf.Elf64.Ehdr,
};
fn ehdrPtr(elf: *Elf) EhdrPtr {
    const slice = elf.ni.ehdr.slice(&elf.mf);
    return switch (elf.identClass()) {
        .NONE, _ => unreachable,
        inline else => |class| @unionInit(
            EhdrPtr,
            @tagName(class),
            @ptrCast(@alignCast(slice)),
        ),
    };
}
fn ehdrField(
    elf: *Elf,
    comptime field: std.meta.FieldEnum(std.elf.Elf64.Ehdr),
) @FieldType(std.elf.Elf64.Ehdr, @tagName(field)) {
    return switch (elf.ehdrPtr()) {
        inline else => |ehdr| elf.targetLoad(&@field(ehdr, @tagName(field))),
    };
}

const PhdrSlice = union(std.elf.CLASS) {
    NONE: noreturn,
    @"32": []std.elf.Elf32.Phdr,
    @"64": []std.elf.Elf64.Phdr,
};
fn phdrSlice(elf: *Elf) PhdrSlice {
    assert(elf.ehdrField(.type) != .REL);
    const slice = elf.ni.phdr.slice(&elf.mf);
    return switch (elf.identClass()) {
        .NONE, _ => unreachable,
        inline else => |class| @unionInit(
            PhdrSlice,
            @tagName(class),
            @ptrCast(@alignCast(slice)),
        ),
    };
}

const ShdrPtr = union(std.elf.CLASS) {
    NONE: noreturn,
    @"32": *std.elf.Elf32.Shdr,
    @"64": *std.elf.Elf64.Shdr,
};
fn shdrPtr(elf: *Elf, shndx: Section.Index) ShdrPtr {
    const raw_slice = elf.ni.shdr.slice(&elf.mf);
    switch (elf.identClass()) {
        .NONE, _ => unreachable,
        inline else => |class| {
            const shdr_slice: []class.ElfN().Shdr = @ptrCast(@alignCast(raw_slice));
            const shdr_ptr = &shdr_slice[@intFromEnum(shndx)];
            return @unionInit(ShdrPtr, @tagName(class), shdr_ptr);
        },
    }
}

const SymPtr = union(std.elf.CLASS) {
    NONE: noreturn,
    @"32": *std.elf.Elf32.Sym,
    @"64": *std.elf.Elf64.Sym,
};
fn symPtr(elf: *Elf, index: Symbol.Index) SymPtr {
    const raw_slice = Section.Index.symtab.get(elf).ni.slice(&elf.mf);
    switch (elf.shdrPtr(.symtab)) {
        inline else => |shdr, class| {
            const size = elf.targetLoad(&shdr.size);
            const slice: []class.ElfN().Sym = @ptrCast(@alignCast(raw_slice[0..@intCast(size)]));
            return @unionInit(SymPtr, @tagName(class), &slice[@intFromEnum(index)]);
        },
    }
}
fn dynsymPtr(elf: *Elf, index: u32) SymPtr {
    const raw_slice = elf.shndx.dynsym.get(elf).ni.slice(&elf.mf);
    switch (elf.shdrPtr(elf.shndx.dynsym)) {
        inline else => |shdr, class| {
            const size = elf.targetLoad(&shdr.size);
            const slice: []class.ElfN().Sym = @ptrCast(@alignCast(raw_slice[0..@intCast(size)]));
            return @unionInit(SymPtr, @tagName(class), &slice[index]);
        },
    }
}

fn navType(elf: *const Elf, nav_resolved: InternPool.Nav.Resolved) std.elf.STT {
    const any_non_single_threaded = elf.base.comp.config.any_non_single_threaded;
    return if (any_non_single_threaded and nav_resolved.@"threadlocal")
        .TLS
    else if (elf.base.comp.zcu.?.intern_pool.isFunctionType(nav_resolved.type))
        .FUNC
    else
        .OBJECT;
}
fn mapInputSection(elf: *Elf, opts: struct {
    name: []const u8,
    flags: std.elf.SHF,
    addralign: std.elf.Xword,
    entsize: std.elf.Xword,
}) (Error || error{
    UnsupportedSectionFlags,
    TlsSectionUnavailable,
    StripSection,
    SectionFlagsConflict,
    SectionTypeConflict,
})!Section.Index {
    const gpa = elf.base.comp.gpa;
    if (opts.flags.INFO_LINK or
        opts.flags.LINK_ORDER or
        opts.flags.OS_NONCONFORMING or
        (opts.flags.EXECINSTR and opts.flags.WRITE) or
        (opts.flags.EXECINSTR and opts.flags.TLS))
    {
        return error.UnsupportedSectionFlags;
    }
    if (opts.flags.TLS and elf.ni.tls == .none) {
        assert(!elf.base.comp.config.any_non_single_threaded);
        return error.TlsSectionUnavailable;
    }

    if (elf.base.comp.config.debug_format == .strip and
        std.mem.startsWith(u8, opts.name, ".debug_") and
        !opts.flags.ALLOC)
    {
        return error.StripSection;
    }

    const name: []const u8 = switch (elf.ehdrField(.type)) {
        .NONE, .CORE, _ => unreachable,
        .REL => opts.name,
        .EXEC, .DYN => name: {
            if (std.mem.startsWith(u8, opts.name, ".text.")) break :name ".text";
            if (std.mem.startsWith(u8, opts.name, ".rodata.")) break :name ".rodata";
            if (std.mem.startsWith(u8, opts.name, ".data.")) break :name ".data";
            if (std.mem.startsWith(u8, opts.name, ".data.rel.ro.")) break :name ".data.rel.ro";
            if (std.mem.startsWith(u8, opts.name, ".tdata.")) break :name ".tdata";
            if (std.mem.startsWith(u8, opts.name, ".gcc_except_table.")) break :name ".gcc_except_table";
            // TODO: actually generate a bss section!
            if (std.mem.eql(u8, opts.name, ".bss")) break :name ".data";
            if (std.mem.startsWith(u8, opts.name, ".bss.")) break :name ".data";
            // TODO: actually generate a tbss section!
            if (std.mem.eql(u8, opts.name, ".tbss")) break :name ".tdata";
            if (std.mem.startsWith(u8, opts.name, ".tbss.")) break :name ".tdata";
            break :name opts.name;
        },
    };
    const existing_shndx: Section.Index = existing: {
        const name_shstrtab = try elf.string(.shstrtab, name);
        const gop = try elf.section_by_name.getOrPut(gpa, name_shstrtab);
        if (gop.found_existing) {
            break :existing @enumFromInt(gop.index);
        }
        errdefer assert(elf.section_by_name.pop().?.key == name_shstrtab);
        const parent_node: MappedFile.Node.Index = parent: {
            if (!opts.flags.ALLOC) break :parent elf.ni.file;
            if (opts.flags.EXECINSTR) break :parent elf.ni.text;
            if (opts.flags.TLS) break :parent elf.ni.tls;
            if (opts.flags.WRITE) break :parent elf.ni.data;
            break :parent elf.ni.rodata;
        };
        assert(gop.index == elf.shdrs.items.len);
        return elf.addSection(parent_node, .{
            .name = name,
            .type = .NULL, // because initial size is 0
            .flags = flags: {
                // We need to decompress the section for linking.
                var flags = opts.flags;
                flags.COMPRESSED = false;
                break :flags flags;
            },
            .node_align = .fromByteUnits(std.math.ceilPowerOfTwoAssert(
                usize,
                @intCast(@max(opts.addralign, 1)),
            )),
            .entsize = std.math.lossyCast(u32, opts.entsize),
        });
    };
    // Validate that the input is compatible with this section...
    switch (elf.shdrPtr(existing_shndx)) {
        inline else => |shdr| {
            const cur_flags = elf.targetLoad(&shdr.flags).shf;
            if (cur_flags.EXECINSTR != opts.flags.EXECINSTR or
                cur_flags.WRITE != opts.flags.WRITE or
                cur_flags.TLS != opts.flags.TLS)
            {
                return error.SectionFlagsConflict;
            }

            switch (elf.targetLoad(&shdr.type)) {
                .NULL, .PROGBITS => {},
                else => return error.SectionTypeConflict,
            }
        },
    }
    // ...then realign the section's node if necessary...
    if (opts.addralign > existing_shndx.get(elf).ni.alignment(&elf.mf).toByteUnits()) {
        const new_alignment: std.mem.Alignment = .fromByteUnits(
            std.math.ceilPowerOfTwoAssert(usize, @intCast(opts.addralign)),
        );
        try existing_shndx.get(elf).ni.realign(&elf.mf, gpa, new_alignment, .{ .set_alignment = true });
    }
    // ...and update the shdr as needed.
    switch (elf.shdrPtr(existing_shndx)) {
        inline else => |shdr| {
            // Combine the section flags.
            const cur_flags = elf.targetLoad(&shdr.flags).shf;
            elf.targetStore(&shdr.flags, .{ .shf = .{
                .EXECINSTR = cur_flags.EXECINSTR,
                .WRITE = cur_flags.WRITE,
                .TLS = cur_flags.TLS,
                .ALLOC = cur_flags.ALLOC or opts.flags.ALLOC,
                .STRINGS = cur_flags.STRINGS and opts.flags.STRINGS,
                .MERGE = cur_flags.MERGE and opts.flags.MERGE,
            } });
            // Increase addralign to the maximum of the current value and the new value---the node
            // alignment was already increased above.
            if (opts.addralign > elf.targetLoad(&shdr.addralign)) {
                elf.targetStore(&shdr.addralign, @intCast(opts.addralign));
            }
        },
    }
    return existing_shndx;
}
fn navMapIndex(elf: *Elf, zcu: *Zcu, nav_index: InternPool.Nav.Index) Error!Node.NavMapIndex {
    const gpa = zcu.gpa;
    const ip = &zcu.intern_pool;
    const nav = ip.getNav(nav_index);

    try elf.ensureUnusedSymbolCapacity(1, .all_local);
    try elf.nodes.ensureUnusedCapacity(gpa, 1);
    try elf.navs.ensureUnusedCapacity(gpa, 1);

    const nav_gop = elf.navs.getOrPutAssumeCapacity(nav_index);
    const nmi: Node.NavMapIndex = @enumFromInt(nav_gop.index);
    if (!nav_gop.found_existing) {
        const shndx: Section.Index = section: {
            if (nav.resolved.?.@"linksection".toSlice(ip)) |@"linksection"| {
                if (elf.mapInputSection(.{
                    .name = @"linksection",
                    .flags = .{
                        .ALLOC = true,
                        .EXECINSTR = ip.isFunctionType(nav.resolved.?.type),
                        .WRITE = !nav.resolved.?.@"const",
                        .TLS = elf.base.comp.config.any_non_single_threaded and
                            nav.resolved.?.@"threadlocal",
                    },
                    .addralign = 1,
                    .entsize = 0,
                })) |shndx| {
                    break :section shndx;
                } else |err| switch (err) {
                    error.StripSection,
                    error.TlsSectionUnavailable,
                    error.UnsupportedSectionFlags,
                    error.SectionTypeConflict,
                    error.SectionFlagsConflict,
                    => {}, // fall back to default behavior below

                    else => |e| return e,
                }
            }
            if (elf.base.comp.config.any_non_single_threaded and nav.resolved.?.@"threadlocal") {
                break :section elf.shndx.tdata;
            } else if (!nav.resolved.?.@"const") {
                break :section .data;
            } else if (ip.isFunctionType(nav.resolved.?.type)) {
                break :section .text;
            } else {
                break :section .data_rel_ro; // TODO: it would be better to use `.rodata` if the NAV value doesn't have relocs
            }
        };
        const alignment: InternPool.Alignment = switch (Type.fromInterned(nav.resolved.?.type).zigTypeTag(zcu)) {
            .@"fn" => a: {
                const mod = zcu.navFileScope(nav_index).mod.?;
                const target = &mod.resolved_target.result;
                const min = target_util.minFunctionAlignment(target);
                break :a switch (nav.resolved.?.@"align") {
                    else => |a| a.maxStrict(min),
                    .none => switch (mod.optimize_mode) {
                        .Debug,
                        .ReleaseSafe,
                        .ReleaseFast,
                        => target_util.defaultFunctionAlignment(target),
                        .ReleaseSmall => min,
                    }.maxStrict(Type.fromInterned(nav.resolved.?.type).abiAlignment(zcu)),
                };
            },
            else => switch (nav.resolved.?.@"align") {
                .none => Type.fromInterned(nav.resolved.?.type).abiAlignment(zcu),
                else => |a| a,
            },
        };
        const node = try elf.mf.addLastChildNode(gpa, shndx.get(elf).ni, .{
            .alignment = alignment.toStdMem(),
        });
        nav_gop.value_ptr.* = .{
            .lsi = elf.addLocalSymbolAssumeCapacity(.{
                .node = node,
                .name = try elf.string(.strtab, nav.fqn.toSlice(ip)),
                .value = 0,
                .size = 0,
                .type = elf.navType(nav.resolved.?),
                .shndx = shndx,
            }),
            .first_symbol_reloc = .none,
            .first_got_reloc = .none,
        };
        elf.nodes.appendAssumeCapacity(.{ .nav = nmi });
    }
    return nmi;
}

fn uavMapIndex(
    elf: *Elf,
    uav_val: InternPool.Index,
    uav_align: InternPool.Alignment,
) Error!Node.UavMapIndex {
    const gpa = elf.base.comp.gpa;
    const zcu = elf.base.comp.zcu.?;

    try elf.ensureUnusedSymbolCapacity(1, .all_local);
    try elf.nodes.ensureUnusedCapacity(gpa, 1);
    try elf.uavs.ensureUnusedCapacity(gpa, 1);
    try elf.pending_uavs.ensureUnusedCapacity(gpa, 1);

    const abi_align = Value.fromInterned(uav_val).typeOf(zcu).abiAlignment(zcu);
    const resolved_align: InternPool.Alignment = switch (uav_align) {
        .none => abi_align,
        else => |a| a.minStrict(abi_align),
    };

    const uav_gop = elf.uavs.getOrPutAssumeCapacity(uav_val);
    const umi: Node.UavMapIndex = @enumFromInt(uav_gop.index);
    if (!uav_gop.found_existing) {
        const shndx: Section.Index = .data_rel_ro; // TODO: it would be better to use `.rodata` if the UAV value doesn't have relocs
        const node = try elf.mf.addLastChildNode(gpa, shndx.get(elf).ni, .{
            .moved = true, // see assert at end of `flushUav`
            .alignment = resolved_align.toStdMem(),
        });
        var name_buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(
            &name_buf,
            "__anon_{d}",
            .{@intFromEnum(uav_val)},
        ) catch unreachable;
        uav_gop.value_ptr.* = .{
            .lsi = elf.addLocalSymbolAssumeCapacity(.{
                .node = node,
                .name = try elf.string(.strtab, name),
                .value = 0,
                .size = 0,
                .type = .OBJECT,
                .shndx = shndx,
            }),
            .first_symbol_reloc = .none,
        };
        elf.nodes.appendAssumeCapacity(.{ .uav = umi });
        elf.const_prog_node.increaseEstimatedTotalItems(1);
        elf.pending_uavs.appendAssumeCapacity(umi);
    } else {
        const node = uav_gop.value_ptr.lsi.index().ptr(elf).node;
        if (resolved_align.toStdMem().order(node.alignment(&elf.mf)).compare(.gt)) {
            try node.realign(&elf.mf, gpa, resolved_align.toStdMem(), .{ .set_alignment = true });
        }
    }
    return umi;
}

/// Internal error set used by input parsing functions `loadObject`, `loadArchive`, `loadDso`.
const LoadParseInputError = Error || Io.File.SeekError || Io.Reader.Error;

/// Returns `error.BadMagic` if a DSO or static archive has an incorrect magic number, which
/// indicates to the frontend that the input could be a GNU ld script instead.
pub fn loadInput(elf: *Elf, input: link.Input) (link.Error || error{BadMagic})!void {
    const diags = &elf.base.comp.link_diags;
    return elf.loadInputInner(input) catch |err| switch (err) {
        else => |e| return e,
        error.MappedFileIo => return diags.fail(
            "failed to write output file: {t}",
            .{elf.mf.io_err.?},
        ),
    };
}
fn loadInputInner(elf: *Elf, input: link.Input) (Error || error{BadMagic})!void {
    const comp = elf.base.comp;
    const diags = &comp.link_diags;
    const io = comp.io;
    var buf: [4096]u8 = undefined;
    switch (input) {
        .object => |object| {
            var fr = object.file.reader(io, &buf);
            elf.loadObject(object.path, null, &fr, .{
                .offset = fr.logicalPos(),
                .size = fr.getSize() catch |err| switch (err) {
                    error.Canceled => |e| return e,
                    else => |e| return diags.fail(
                        "failed to stat \"{f}\": {t}",
                        .{ object.path.fmtEscapeString(), e },
                    ),
                },
            }) catch |err| switch (err) {
                else => |e| return e,
                error.EndOfStream => return diags.failParse(
                    object.path,
                    "unexpected eof",
                    .{},
                ),
                error.AccessDenied, error.Unexpected, error.Unseekable => |e| return diags.fail(
                    "failed to read \"{f}\": {t}",
                    .{ object.path.fmtEscapeString(), e },
                ),
                error.ReadFailed => switch (fr.err.?) {
                    error.Canceled => |e| return e,
                    else => |e| return diags.fail(
                        "failed to read \"{f}\": {t}",
                        .{ object.path.fmtEscapeString(), e },
                    ),
                },
            };
        },
        .archive => |archive| {
            var fr = archive.file.reader(io, &buf);
            elf.loadArchive(archive.path, &fr) catch |err| switch (err) {
                else => |e| return e,
                error.EndOfStream => return diags.failParse(
                    archive.path,
                    "unexpected eof",
                    .{},
                ),
                error.AccessDenied, error.Unexpected, error.Unseekable => |e| return diags.fail(
                    "failed to read \"{f}\": {t}",
                    .{ archive.path.fmtEscapeString(), e },
                ),
                error.ReadFailed => switch (fr.err.?) {
                    error.Canceled => |e| return e,
                    else => |e| return diags.fail(
                        "failed to read \"{f}\": {t}",
                        .{ archive.path.fmtEscapeString(), e },
                    ),
                },
            };
        },
        .res => unreachable,
        .dso => |dso| {
            try elf.needed.ensureUnusedCapacity(elf.base.comp.gpa, 1);
            var fr = dso.file.reader(io, &buf);
            elf.loadDso(dso.path, &fr) catch |err| switch (err) {
                else => |e| return e,
                error.EndOfStream => return diags.failParse(
                    dso.path,
                    "unexpected eof",
                    .{},
                ),
                error.AccessDenied, error.Unexpected, error.Unseekable => |e| return diags.fail(
                    "failed to read \"{f}\": {t}",
                    .{ dso.path.fmtEscapeString(), e },
                ),
                error.ReadFailed => switch (fr.err.?) {
                    error.Canceled => |e| return e,
                    else => |e| return diags.fail(
                        "failed to read \"{f}\": {t}",
                        .{ dso.path.fmtEscapeString(), e },
                    ),
                },
            };
        },
        .dso_exact => |dso_exact| {
            log.debug("load dso_exact '{f}'", .{std.zig.fmtString(dso_exact.name)});
            if (elf.shndx.dynamic != .UNDEF) {
                try elf.needed.put(elf.base.comp.gpa, try elf.string(.dynstr, dso_exact.name), {});
            }
            // TODO: we need to get a resolved file path from the frontend, because we need to read
            // the shared object to discover symbol types.
        },
    }
}
fn loadArchive(elf: *Elf, path: std.Build.Cache.Path, fr: *Io.File.Reader) (LoadParseInputError || error{BadMagic})!void {
    const comp = elf.base.comp;
    const gpa = comp.gpa;
    const diags = &comp.link_diags;
    const r = &fr.interface;

    log.debug("loadArchive({f})", .{path.fmtEscapeString()});
    {
        const magic = r.take(std.elf.ARMAG.len) catch |err| switch (err) {
            error.ReadFailed => |e| return e,
            error.EndOfStream => return error.BadMagic,
        };
        if (!std.mem.eql(u8, magic, std.elf.ARMAG)) {
            return error.BadMagic;
        }
    }
    var strtab: std.Io.Writer.Allocating = .init(gpa);
    defer strtab.deinit();
    while (r.takeStruct(std.elf.ar_hdr, native_endian)) |header| {
        if (!std.mem.eql(u8, &header.ar_fmag, std.elf.ARFMAG))
            return diags.failParse(path, "bad file magic", .{});
        const offset = fr.logicalPos();
        const size = header.size() catch
            return diags.failParse(path, "bad member size", .{});
        if (std.mem.eql(u8, &header.ar_name, std.elf.STRNAME)) {
            strtab.clearRetainingCapacity();
            try strtab.ensureTotalCapacityPrecise(size);
            r.streamExact(&strtab.writer, size) catch |err| switch (err) {
                error.WriteFailed => return error.OutOfMemory,
                else => |e| return e,
            };
            continue;
        }
        load_object: {
            if (std.mem.eql(u8, &header.ar_name, std.elf.SYMNAME) or
                std.mem.eql(u8, &header.ar_name, std.elf.SYM64NAME) or
                std.mem.eql(u8, &header.ar_name, std.elf.SYMDEFNAME) or
                std.mem.eql(u8, &header.ar_name, std.elf.SYMDEFSORTEDNAME))
            {
                break :load_object;
            }
            const member = header.name() orelse member: {
                const strtab_offset = header.nameOffset() catch |err| switch (err) {
                    error.Overflow => break :member error.Overflow,
                    error.InvalidCharacter => break :load_object,
                } orelse break :load_object;
                const strtab_written = strtab.written();
                if (strtab_offset > strtab_written.len) break :member error.Overflow;
                const member = std.mem.sliceTo(strtab_written[strtab_offset..], '\n');
                break :member if (std.mem.endsWith(u8, member, "/"))
                    member[0 .. member.len - "/".len]
                else
                    member;
            } catch |err| switch (err) {
                error.Overflow => return diags.failParse(path, "bad member name offset", .{}),
            };
            try elf.loadObject(path, member, fr, .{ .offset = offset, .size = size });
        }
        try fr.seekTo(std.mem.alignForward(u64, offset + size, 2));
    } else |err| switch (err) {
        error.EndOfStream => if (!fr.atEnd()) return error.EndOfStream,
        else => |e| return e,
    }
}
fn fmtMemberString(member: ?[]const u8) std.fmt.Alt(?[]const u8, memberStringEscape) {
    return .{ .data = member };
}
fn memberStringEscape(member: ?[]const u8, w: *std.Io.Writer) std.Io.Writer.Error!void {
    try w.print("({f})", .{std.zig.fmtString(member orelse return)});
}
fn loadObject(
    elf: *Elf,
    path: std.Build.Cache.Path,
    member: ?[]const u8,
    fr: *Io.File.Reader,
    fl: MappedFile.Node.FileLocation,
) LoadParseInputError!void {
    const comp = elf.base.comp;
    const gpa = comp.gpa;
    const diags = &comp.link_diags;
    const r = &fr.interface;

    const input_index: Node.InputIndex = @enumFromInt(elf.inputs.items.len);
    log.debug("loadObject({f}{f})", .{ path.fmtEscapeString(), fmtMemberString(member) });
    elf.checkInputIdent(path, r) catch |err| switch (err) {
        else => |e| return e,
        error.BadMagic => return diags.failParse(
            path,
            "bad ELF magic",
            .{},
        ),
    };
    try elf.ensureUnusedSymbolCapacity(1, .all_local);
    try elf.inputs.ensureUnusedCapacity(gpa, 1);
    const file_symbol = elf.addLocalSymbolAssumeCapacity(.{
        .node = .none,
        .name = try elf.string(.strtab, std.fs.path.stem(member orelse path.sub_path)),
        .value = 0,
        .size = 0,
        .type = .FILE,
        .shndx = .ABS,
    });
    elf.inputs.addOneAssumeCapacity().* = .{
        .path = path,
        .member = if (member) |m| try gpa.dupe(u8, m) else null,
        .file_symbol = file_symbol,
    };
    const target_endian = elf.targetEndian();
    switch (elf.identClass()) {
        .NONE, _ => unreachable,
        inline else => |class| {
            const ElfN = class.ElfN();
            const ehdr = try r.peekStruct(ElfN.Ehdr, target_endian);
            if (ehdr.type != .REL) return diags.failParse(path, "unsupported object type", .{});
            if (ehdr.machine != elf.ehdrField(.machine))
                return diags.failParse(path, "bad machine", .{});
            if (ehdr.shoff == 0 or ehdr.shnum <= 1) return;
            if (ehdr.shoff + @as(u64, ehdr.shentsize) * @as(u64, ehdr.shnum) > fl.size)
                return diags.failParse(path, "bad section header location", .{});
            if (ehdr.shentsize < @sizeOf(ElfN.Shdr))
                return diags.failParse(path, "unsupported shentsize", .{});
            const sections = try gpa.alloc(struct { shdr: ElfN.Shdr, isi: ?InputSection.Index }, ehdr.shnum);
            defer gpa.free(sections);
            try fr.seekTo(fl.offset + ehdr.shoff);
            for (sections) |*section| {
                section.* = .{
                    .shdr = try r.peekStruct(ElfN.Shdr, target_endian),
                    .isi = null,
                };
                try r.discardAll(ehdr.shentsize);
                switch (section.shdr.type) {
                    .NULL, .NOBITS => {},
                    else => if (section.shdr.offset + section.shdr.size > fl.size)
                        return diags.failParse(path, "bad section location", .{}),
                }
            }
            const shstrtab = shstrtab: {
                if (ehdr.shstrndx == std.elf.SHN_UNDEF or ehdr.shstrndx >= ehdr.shnum)
                    return diags.failParse(path, "missing section names", .{});
                const shdr = &sections[ehdr.shstrndx].shdr;
                if (shdr.type != .STRTAB) return diags.failParse(path, "invalid shstrtab type", .{});
                const shstrtab = try gpa.alloc(u8, @intCast(shdr.size));
                errdefer gpa.free(shstrtab);
                try fr.seekTo(fl.offset + shdr.offset);
                try r.readSliceAll(shstrtab);
                break :shstrtab shstrtab;
            };
            defer gpa.free(shstrtab);
            try elf.nodes.ensureUnusedCapacity(gpa, ehdr.shnum - 1);
            try elf.input_sections.ensureUnusedCapacity(gpa, ehdr.shnum - 1);
            for (sections[1..]) |*section| {
                if (section.shdr.name >= shstrtab.len) continue;
                const name = std.mem.sliceTo(shstrtab[section.shdr.name..], 0);
                const opts: struct {
                    shndx: Section.Index,
                    has_file_bits: bool,
                    node_fixed: bool,
                } = switch (section.shdr.type) {
                    else => continue,
                    .PROGBITS, .NOBITS => opts: {
                        const shndx = elf.mapInputSection(.{
                            .name = name,
                            .flags = section.shdr.flags.shf,
                            .addralign = section.shdr.addralign,
                            .entsize = section.shdr.entsize,
                        }) catch |err| switch (err) {
                            error.StripSection => continue,
                            error.TlsSectionUnavailable => return diags.failParse(
                                path,
                                "thread-local storage section '{s}' is incompatible with '-fsingle-threaded'",
                                .{name},
                            ),
                            error.UnsupportedSectionFlags => if (!section.shdr.flags.shf.ALLOC) {
                                // It probably doesn't matter, just skip this section.
                                continue;
                            } else return diags.failParse(
                                path,
                                "unsupported flags for section '{s}'",
                                .{name},
                            ),
                            error.SectionTypeConflict => if (!section.shdr.flags.shf.ALLOC) {
                                // It probably doesn't matter, just skip this section.
                                continue;
                            } else return diags.failParse(
                                path,
                                "type of section '{s}' conflicts with other inputs",
                                .{name},
                            ),
                            error.SectionFlagsConflict => if (!section.shdr.flags.shf.ALLOC) {
                                // It probably doesn't matter, just skip this section.
                                continue;
                            } else return diags.failParse(
                                path,
                                "flags of section '{s}' conflict with other inputs",
                                .{name},
                            ),
                            else => |e| return e,
                        };
                        if (section.shdr.flags.shf.COMPRESSED) {
                            // SHF_COMPRESSED is only allowed on non-alloc sections.
                            if (section.shdr.flags.shf.ALLOC) return diags.failParse(
                                path,
                                "section '{s}' has conflicting flags SHF_ALLOC and SHF_COMPRESSED",
                                .{name},
                            );
                            // TODO: handle compressed input sections. We'll need to set a flag to
                            // indicate that `flushInputSection` needs to decompress the section.
                            // But because this section isn't SHF_ALLOC, it's probably okay to just
                            // skip it for now.
                            continue;
                        }
                        break :opts .{
                            .shndx = shndx,
                            .has_file_bits = section.shdr.type == .PROGBITS,
                            // For well-known sections, we know that it's fine to have e.g. random
                            // padding, so there's no need to make the sections fixed. For custom
                            // sections, however, we do want fixed nodes to avoid padding.
                            .node_fixed = shndx != .text and
                                shndx != .rodata and
                                shndx != .data and
                                shndx != .data_rel_ro and
                                shndx != elf.shndx.tdata,
                        };
                    },
                    inline .INIT_ARRAY, .FINI_ARRAY, .PREINIT_ARRAY => |@"type"| .{
                        .shndx = shndx: {
                            // TODO: the input section name may include a "priority" value between 1
                            // and 65535 which should affect the order we assemble input sections in
                            const init_fini_section_name: []const u8 = switch (@"type") {
                                .INIT_ARRAY => "init_array",
                                .FINI_ARRAY => "fini_array",
                                .PREINIT_ARRAY => "preinit_array",
                                else => comptime unreachable,
                            };
                            const shndx: *Section.Index = &@field(elf.shndx, init_fini_section_name);
                            const need_addralign: u8 = switch (class) {
                                .NONE, _ => unreachable,
                                .@"32" => 4,
                                .@"64" => 8,
                            };
                            if (section.shdr.addralign != need_addralign) {
                                return diags.failParse(path, "bad addralign on {t} shdr", .{@"type"});
                            }
                            if (shndx.* == .UNDEF) {
                                try elf.createInitFiniArraySection(shndx, init_fini_section_name, @"type");
                            }
                            switch (elf.shdrPtr(shndx.*)) {
                                inline else => |shdr| {
                                    const old_size = elf.targetLoad(&shdr.size);
                                    const new_size = old_size + section.shdr.size;
                                    elf.targetStore(&shdr.size, @intCast(new_size));
                                    elf.updateInitFiniArraySectionSize(shndx.*, init_fini_section_name, @"type", new_size);
                                },
                            }
                            break :shndx shndx.*;
                        },
                        .has_file_bits = true,
                        // This node must be fixed to prevent padding from being added between different
                        // INIT_ARRAY/FINI_ARRAY/PREINIT_ARRAY input sections.
                        .node_fixed = true,
                    },
                };
                const ni = try elf.mf.addLastChildNode(gpa, opts.shndx.get(elf).ni, .{
                    .size = section.shdr.size,
                    .alignment = .fromByteUnits(std.math.ceilPowerOfTwoAssert(
                        usize,
                        @intCast(@max(section.shdr.addralign, 1)),
                    )),
                    .moved = true, // see assert at end of `flushInputSection`
                    .fixed = opts.node_fixed,
                });
                elf.nodes.appendAssumeCapacity(.{
                    .input_section = @enumFromInt(elf.input_sections.items.len),
                });
                section.isi = @enumFromInt(elf.input_sections.items.len);
                elf.input_sections.addOneAssumeCapacity().* = .{
                    .input = input_index,
                    .file_location = .{
                        .offset = fl.offset + section.shdr.offset,
                        .size = if (opts.has_file_bits) section.shdr.size else 0,
                    },
                    // The section vaddr is initially 0, because the symbol addresses are
                    // zero-based. This will eventually be updated by `flushMoved`.
                    .vaddr = 0,
                    .node = ni,
                    .first_symbol_reloc = .none,
                    .first_got_reloc = .none,
                };
                elf.synth_prog_node.increaseEstimatedTotalItems(1);
            }
            var symmap: std.ArrayList(Symbol.Id) = .empty;
            defer symmap.deinit(gpa);
            for (sections[1..], 1..) |*symtab, symtab_shndx| switch (symtab.shdr.type) {
                else => {},
                .SYMTAB => {
                    if (symtab.shdr.entsize < @sizeOf(ElfN.Sym))
                        return diags.failParse(path, "unsupported symtab entsize", .{});
                    const strtab = strtab: {
                        if (symtab.shdr.link == std.elf.SHN_UNDEF or symtab.shdr.link >= ehdr.shnum)
                            return diags.failParse(path, "missing symbol names", .{});
                        const shdr = &sections[symtab.shdr.link].shdr;
                        if (shdr.type != .STRTAB)
                            return diags.failParse(path, "invalid strtab type", .{});
                        const strtab = try gpa.alloc(u8, @intCast(shdr.size));
                        errdefer gpa.free(strtab);
                        try fr.seekTo(fl.offset + shdr.offset);
                        try r.readSliceAll(strtab);
                        break :strtab strtab;
                    };
                    defer gpa.free(strtab);
                    const symnum = std.math.sub(u32, std.math.divExact(
                        u32,
                        @intCast(symtab.shdr.size),
                        @intCast(symtab.shdr.entsize),
                    ) catch return diags.failParse(
                        path,
                        "symtab section size (0x{x}) is not a multiple of entsize (0x{x})",
                        .{ symtab.shdr.size, symtab.shdr.entsize },
                    ), 1) catch continue;
                    symmap.clearRetainingCapacity();
                    try symmap.resize(gpa, symnum);
                    try elf.ensureUnusedSymbolCapacity(symnum, .maybe_global);
                    try fr.seekTo(fl.offset + symtab.shdr.offset + symtab.shdr.entsize);
                    for (symmap.items) |*si| {
                        si.* = .null;
                        const input_sym = try r.peekStruct(ElfN.Sym, target_endian);
                        try r.discardAll64(symtab.shdr.entsize);
                        if (input_sym.name >= strtab.len or input_sym.shndx >= ehdr.shnum) continue;

                        const name = std.mem.sliceTo(strtab[input_sym.name..], 0);

                        const sym_type: std.elf.STT = switch (input_sym.info.type) {
                            .NOTYPE, .OBJECT, .FUNC, .TLS => |t| t,
                            .SECTION => .NOTYPE,
                            .FILE, .COMMON, _ => continue,
                        };

                        if (input_sym.shndx == std.elf.SHN_UNDEF) switch (input_sym.info.bind) {
                            else => |bind| return diags.failParse(
                                path,
                                "symbol '{s}' has unsupported binding (0x{x})",
                                .{ name, bind },
                            ),
                            .LOCAL => continue,
                            .GLOBAL, .WEAK, .GNU_UNIQUE => |bind| {
                                si.* = elf.addGlobalSymbolAssumeCapacity(.{
                                    .node = .none,
                                    .name = try .string(elf, name),
                                    .value = input_sym.value,
                                    .size = input_sym.size,
                                    .type = sym_type,
                                    .bind = switch (bind) {
                                        .WEAK, .GNU_UNIQUE => .weak,
                                        .GLOBAL => .strong,
                                        else => unreachable,
                                    },
                                    .visibility = input_sym.other.visibility,
                                    .shndx = .UNDEF,
                                }) catch |err| switch (err) {
                                    error.MultipleDefinitions => unreachable, // shndx is .UNDEF
                                };
                                continue;
                            },
                        };

                        const input_section_node = (sections[input_sym.shndx].isi orelse continue).node(elf);

                        switch (input_sym.info.bind) {
                            else => |bind| return diags.failParse(
                                path,
                                "symbol '{s}' has unsupported binding (0x{x})",
                                .{ name, bind },
                            ),
                            .LOCAL => {
                                const lsi = elf.addLocalSymbolAssumeCapacity(.{
                                    .node = input_section_node,
                                    .name = try elf.string(.strtab, name),
                                    .value = input_sym.value,
                                    .size = input_sym.size,
                                    .type = sym_type,
                                    .shndx = elf.getNodeShndx(input_section_node),
                                });
                                si.* = .local(lsi);
                            },
                            .GLOBAL, .WEAK, .GNU_UNIQUE => |bind| {
                                si.* = elf.addGlobalSymbolAssumeCapacity(.{
                                    .node = input_section_node,
                                    .name = try .string(elf, name),
                                    .value = input_sym.value,
                                    .size = input_sym.size,
                                    .type = sym_type,
                                    .bind = switch (bind) {
                                        .WEAK, .GNU_UNIQUE => .weak,
                                        .GLOBAL => .strong,
                                        else => unreachable,
                                    },
                                    .visibility = input_sym.other.visibility,
                                    .shndx = elf.getNodeShndx(input_section_node),
                                }) catch |err| switch (err) {
                                    error.MultipleDefinitions => return diags.failParse(
                                        path,
                                        "multiple definitions of '{s}'",
                                        .{name},
                                    ),
                                };
                            },
                        }
                    }
                    for (sections[1..]) |*rel_sec| switch (rel_sec.shdr.type) {
                        else => {},
                        inline .REL, .RELA => |sht| {
                            if (rel_sec.shdr.link != symtab_shndx or rel_sec.shdr.info == std.elf.SHN_UNDEF or
                                rel_sec.shdr.info >= ehdr.shnum) continue;
                            const Rel = switch (sht) {
                                else => comptime unreachable,
                                .REL => ElfN.Rel,
                                .RELA => ElfN.Rela,
                            };
                            if (rel_sec.shdr.entsize < @sizeOf(Rel))
                                return diags.failParse(path, "unsupported rel entsize", .{});

                            const loc_sec = &sections[rel_sec.shdr.info];
                            const loc_node = (loc_sec.isi orelse continue).node(elf);
                            elf.resetNodeRelocs(loc_node);

                            const relnum = std.math.divExact(
                                u32,
                                @intCast(rel_sec.shdr.size),
                                @intCast(rel_sec.shdr.entsize),
                            ) catch return diags.failParse(
                                path,
                                "relocation section size (0x{x}) is not a multiple of entsize (0x{x})",
                                .{ rel_sec.shdr.size, rel_sec.shdr.entsize },
                            );
                            try elf.ensureUnusedRelocCapacity(loc_node, relnum);
                            try fr.seekTo(fl.offset + rel_sec.shdr.offset);
                            for (0..relnum) |_| {
                                const rel = try r.peekStruct(Rel, target_endian);
                                try r.discardAll64(rel_sec.shdr.entsize);
                                if (rel.info.sym == 0) continue;
                                if (rel.info.sym > symnum) return diags.failParse(
                                    path,
                                    "relocation target symbol index {d} exceeds symtab size",
                                    .{rel.info.sym},
                                );
                                const target = symmap.items[rel.info.sym - 1];
                                if (target == Symbol.Id.null) {
                                    // If this is not an SHF_ALLOC section, then let's let this
                                    // slide for now, because it probably doesn't affect the final
                                    // binary's functionality for this section to be a bit broken.
                                    if (!loc_sec.shdr.flags.shf.ALLOC) continue;
                                    return diags.failParse(
                                        path,
                                        "unsupported symbol at index {d} required for relocation",
                                        .{rel.info.sym},
                                    );
                                }
                                try elf.addRelocAssumeCapacity(
                                    loc_node,
                                    rel.offset - loc_sec.shdr.addr,
                                    target,
                                    rel.addend,
                                    .wrap(rel.info.type, elf),
                                );
                            }
                        },
                    };
                },
            };
        },
    }
}
fn loadDso(elf: *Elf, path: std.Build.Cache.Path, fr: *Io.File.Reader) (LoadParseInputError || error{BadMagic})!void {
    const comp = elf.base.comp;
    const gpa = comp.gpa;
    const diags = &comp.link_diags;
    const r = &fr.interface;

    log.debug("loadDso({f})", .{path.fmtEscapeString()});
    try elf.checkInputIdent(path, r);
    const target_endian = elf.targetEndian();
    switch (elf.identClass()) {
        .NONE, _ => unreachable,
        inline else => |class| {
            const ElfN = class.ElfN();
            const ehdr = try r.peekStruct(ElfN.Ehdr, target_endian);
            if (ehdr.type != .DYN) return diags.failParse(path, "unsupported dso type", .{});
            if (ehdr.machine != elf.ehdrField(.machine))
                return diags.failParse(path, "bad machine", .{});
            if (ehdr.shnum > 0) try fr.seekTo(ehdr.shoff);
            // We're going to need to know the alignment of every section later.
            const section_aligns = try gpa.alloc(std.mem.Alignment, ehdr.shnum);
            defer gpa.free(section_aligns);
            const dynamic_sh: ElfN.Shdr, const dynsym_sh: ElfN.Shdr = sh: {
                var dynamic_sh: ?ElfN.Shdr = null;
                var dynsym_sh: ?ElfN.Shdr = null;
                for (section_aligns) |*section_align| {
                    const sh = try r.peekStruct(ElfN.Shdr, target_endian);
                    try r.discardAll(ehdr.shentsize);
                    section_align.* = .fromByteUnits(std.math.ceilPowerOfTwoAssert(
                        usize,
                        @intCast(@max(sh.addralign, 1)),
                    ));
                    switch (sh.type) {
                        else => {},
                        .DYNAMIC => dynamic_sh = sh,
                        .DYNSYM => dynsym_sh = sh,
                    }
                }
                break :sh .{
                    dynamic_sh orelse return diags.failParse(path, "missing SHT_DYNAMIC section", .{}),
                    dynsym_sh orelse return diags.failParse(path, "missing SHT_DYNSYM section", .{}),
                };
            };
            const dynstr_sh: ElfN.Shdr = sh: {
                if (dynsym_sh.link >= ehdr.shnum) {
                    return diags.failParse(path, "bad dynamic string table section index", .{});
                }
                try fr.seekTo(ehdr.shoff + dynsym_sh.link * ehdr.shentsize);
                break :sh try r.peekStruct(ElfN.Shdr, target_endian);
            };

            if (dynamic_sh.entsize != @sizeOf(ElfN.Addr) * 2) {
                return diags.failParse(path, "bad dynamic section entsize", .{});
            }
            const dynnum = std.math.divExact(
                u32,
                @intCast(dynamic_sh.size),
                @sizeOf(ElfN.Addr) * 2,
            ) catch return diags.failParse(
                path,
                "dynamic section size (0x{x}) is not a multiple of entsize (0x{x})",
                .{ dynamic_sh.size, @sizeOf(ElfN.Addr) * 2 },
            );

            if (dynsym_sh.entsize < @sizeOf(ElfN.Sym)) {
                return diags.failParse(path, "bad dynsym entsize", .{});
            }
            const symnum = std.math.divExact(
                u32,
                @intCast(dynsym_sh.size),
                @intCast(dynsym_sh.entsize),
            ) catch return diags.failParse(
                path,
                "dynsym size (0x{x}) is not a multiple of entsize (0x{x})",
                .{ dynsym_sh.size, dynsym_sh.entsize },
            );

            const dynstr = try gpa.alloc(u8, @intCast(dynstr_sh.size));
            defer gpa.free(dynstr);
            try fr.seekTo(dynstr_sh.offset);
            try r.readSliceAll(dynstr);

            // Find the DT_SONAME dynamic entry so that it can become our DT_NEEDED entry.
            try fr.seekTo(dynamic_sh.offset);
            const soname: []const u8 = for (0..dynnum) |_| {
                const tag = try r.takeInt(ElfN.Addr, target_endian);
                const val = try r.takeInt(ElfN.Addr, target_endian);
                if (tag == std.elf.DT_SONAME) {
                    // val is a dynstr index
                    if (val >= dynstr.len) {
                        return diags.failParse(path, "bad soname string", .{});
                    }
                    break std.mem.sliceTo(dynstr[@intCast(val)..], 0);
                }
            } else std.fs.path.basename(path.sub_path);
            try elf.needed.put(gpa, try elf.string(.dynstr, soname), {});

            // Scan the symbol table and populate `elf.dso_globals`.
            const first_global = @min(dynsym_sh.info, symnum);
            try elf.dso_globals.ensureUnusedCapacity(gpa, symnum - first_global);
            try elf.ensureUnusedPltCapacity(symnum - first_global);
            try fr.seekTo(dynsym_sh.offset + first_global * dynsym_sh.entsize);
            for (first_global..symnum) |_| {
                const sym = try r.peekStruct(ElfN.Sym, target_endian);
                try r.discardAll(@intCast(dynsym_sh.entsize));

                switch (sym.info.bind) {
                    else => continue,
                    .GLOBAL, .WEAK, .GNU_UNIQUE => {},
                }
                // STV_HIDDEN/STV_INTERNAL symbols should be marked as STB_LOCAL and hence skipped
                // above, but we might as well double-check.
                switch (sym.other.visibility) {
                    .HIDDEN, .INTERNAL => continue,
                    .DEFAULT, .PROTECTED => {},
                }

                if (sym.shndx == std.elf.SHN_UNDEF) continue;
                if (sym.shndx >= ehdr.shnum) continue;

                if (sym.name >= dynstr.len) {
                    return diags.failParse(path, "bad symbol name string", .{});
                }

                // We need to guess the worst-case alignment of the symbol. Yes, I know this seems
                // insane---refer to the doc comment on `alignment` in `Elf.dso_globals`.
                const sym_align: std.mem.Alignment = switch (sym.value) {
                    0 => section_aligns[sym.shndx],
                    else => section_aligns[sym.shndx].min(@enumFromInt(@ctz(sym.value))),
                };

                const name = try elf.string(.strtab, std.mem.sliceTo(dynstr[sym.name..], 0));
                const gop = elf.dso_globals.getOrPutAssumeCapacity(name);

                if (gop.found_existing and gop.value_ptr.type != .NOTYPE) {
                    if (sym.size > gop.value_ptr.size or
                        sym_align.compare(.gt, gop.value_ptr.alignment))
                    {
                        gop.value_ptr.size = @max(gop.value_ptr.size, sym.size);
                        gop.value_ptr.alignment = gop.value_ptr.alignment.max(sym_align);
                        if (elf.copied_globals.get(name)) |copied_global| {
                            // We have a copy relocation for this global, but the amount of space we
                            // reserved for it could be too small or underaligned!
                            try copied_global.node.resize(&elf.mf, gpa, gop.value_ptr.size);
                            try copied_global.node.realign(&elf.mf, gpa, gop.value_ptr.alignment, .{ .set_alignment = true });
                            const global_ptr = elf.globalByName(name).?;
                            switch (elf.symPtr(global_ptr.symtab_index)) {
                                inline else => |sym_ptr| elf.targetStore(&sym_ptr.size, @intCast(gop.value_ptr.size)),
                            }
                            switch (elf.dynsymPtr(global_ptr.dynsym_index)) {
                                inline else => |dynsym_ptr| elf.targetStore(&dynsym_ptr.size, @intCast(gop.value_ptr.size)),
                            }
                        }
                    }
                    continue;
                }

                gop.value_ptr.* = .{
                    .type = sym.info.type,
                    .size = sym.size,
                    .alignment = sym_align,
                };

                // If there's already an undefined symbol by this name of type STT_NOTYPE, populate
                // its type now.
                const global_ptr = elf.globals.strong_undef.getPtr(name) orelse
                    elf.globals.weak_undef.getPtr(name) orelse
                    continue;

                if (global_ptr.dynsym_index == 0) continue;

                if (elf.want_copied_globals.swapRemove(name)) {
                    // We just found a DSO definition of a symbol for which we wanted a copy
                    // relocation, so add one if we can!
                    _ = try elf.maybeAddCopyRelocation(name);
                }

                const sym_ptr = @field(elf.symPtr(global_ptr.symtab_index), @tagName(class));
                errdefer comptime unreachable; // messing with the output file could invalidate `sym_ptr`

                switch (elf.targetLoad(&sym_ptr.other).visibility) {
                    .HIDDEN, .INTERNAL, .PROTECTED => continue,
                    .DEFAULT => {},
                }

                const cur_info = elf.targetLoad(&sym_ptr.info);
                if (cur_info.type == .NOTYPE) {
                    const new_type: std.elf.STT = switch (sym.info.type) {
                        .GNU_IFUNC => .FUNC,
                        else => |t| t,
                    };

                    elf.targetStore(&sym_ptr.info, .{
                        .bind = cur_info.bind,
                        .type = new_type,
                    });

                    const dynsym_ptr = @field(elf.dynsymPtr(global_ptr.dynsym_index), @tagName(class));
                    elf.targetStore(&dynsym_ptr.info, .{
                        .bind = elf.targetLoad(&dynsym_ptr.info).bind,
                        .type = new_type,
                    });

                    if (new_type == .FUNC) {
                        // We turned STT_NOTYPE into STT_FUNC, so we now need a PLT entry...
                        elf.addPltEntry(name, global_ptr.dynsym_index);
                        // ...and therefore, we need to re-apply that symbol's relocations, as
                        // some might be targeting its PLT entry.
                        Symbol.Id.global(name).applyTargetRelocs(elf);
                    }
                }
            }
        },
    }
}

/// Validates that the `std.elf.Ident` present at the start of `r` is a compatible link input.
///
/// Returns an error if it is incompatible, or if the ident is broken or missing---usually
/// `error.AlreadyReported`, but if the magic number is missing or incorrect, returns
/// `error.BadMagic` instead.
///
/// Does not advance the position of `r`. Requires `r` to have a 16-byte buffer.
fn checkInputIdent(
    elf: *const Elf,
    path: std.Build.Cache.Path,
    r: *Io.Reader,
) error{ BadMagic, EndOfStream, AlreadyReported, ReadFailed }!void {
    const diags = &elf.base.comp.link_diags;

    const magic = r.peek(std.elf.MAGIC.len) catch |err| switch (err) {
        error.ReadFailed => |e| return e,
        error.EndOfStream => return error.BadMagic,
    };
    if (!std.mem.eql(u8, magic, std.elf.MAGIC)) {
        return error.BadMagic;
    }

    const ident = try r.peekStructPointer(std.elf.Ident);
    const target: *const std.elf.Ident = @ptrCast(elf.mf.memory_map.memory[0..@sizeOf(std.elf.Ident)]);

    if (ident.class != target.class) return diags.failParse(
        path,
        "bad ELF class ({?s})",
        .{std.enums.tagName(std.elf.CLASS, ident.class)},
    );
    if (ident.data != target.data) return diags.failParse(
        path,
        "bad ELF data encoding ({?s})",
        .{std.enums.tagName(std.elf.DATA, ident.data)},
    );
    if (ident.version != target.version) return diags.failParse(
        path,
        "bad ELF version ({d})",
        .{ident.version},
    );

    // OSABI is a bit more complex. On Linux, `.NONE` and `.GNU` are both valid and both common.
    // It sounds reasonable to allow the value we chose *and* allow `.NONE`.
    const expect_abiversion: u8 = abiver: {
        if (ident.osabi == .NONE) break :abiver 0;
        if (ident.osabi == target.osabi) break :abiver target.abiversion;
        return diags.failParse(
            path,
            "bad ELF OS/ABI ({?s})",
            .{std.enums.tagName(std.elf.OSABI, ident.osabi)},
        );
    };
    if (ident.abiversion != expect_abiversion) return diags.failParse(
        path,
        "bad ELF ABI version ({d})",
        .{ident.abiversion},
    );
}

fn createInitFiniArraySection(
    elf: *Elf,
    shndx: *Section.Index,
    comptime name: []const u8,
    @"type": std.elf.SHT,
) Error!void {
    assert(shndx.* == .UNDEF);
    const gpa = elf.base.comp.gpa;
    const addr_align: std.mem.Alignment = switch (elf.identClass()) {
        .NONE, _ => unreachable,
        .@"32" => .@"4",
        .@"64" => .@"8",
    };
    assert(elf.section_by_name.count() == elf.shdrs.items.len);
    try elf.section_by_name.ensureUnusedCapacity(gpa, 1);
    shndx.* = try elf.addSection(elf.ni.data_rel_ro, .{
        .name = "." ++ name,
        .type = @"type",
        .flags = .{ .WRITE = true, .ALLOC = true },
        .node_align = addr_align,
    });
    elf.section_by_name.putAssumeCapacityNoClobber(shndx.name(elf), {});
    try elf.ensureUnusedSymbolCapacity(2, .maybe_global);
    // These symbols definitely already have strong definitions, because we added them alongside the
    // other linker-defined symbols, all the way back in `initHeaders`.
    const start_sym_name = try elf.string(.strtab, "__" ++ name ++ "_start");
    const end_sym_name = try elf.string(.strtab, "__" ++ name ++ "_end");
    elf.setGlobalSymbolValue(start_sym_name, elf.globals.strong_def.getPtr(start_sym_name).?, .{
        .node = shndx.get(elf).ni,
        .value = shndx.vaddr(elf),
        .size = 0,
        .type = .NOTYPE,
        .shndx = shndx.*,
    });
    elf.setGlobalSymbolValue(end_sym_name, elf.globals.strong_def.getPtr(end_sym_name).?, .{
        .node = shndx.get(elf).ni,
        .value = shndx.vaddr(elf),
        .size = 0,
        .type = .NOTYPE,
        .shndx = shndx.*,
    });
}
fn updateInitFiniArraySectionSize(
    elf: *Elf,
    shndx: Section.Index,
    comptime name: []const u8,
    @"type": std.elf.SHT,
    new_size: u64,
) void {
    if (elf.shndx.dynamic != .UNDEF) {
        const arraysz_dyn_key: u32 = switch (@"type") {
            .INIT_ARRAY => std.elf.DT_INIT_ARRAYSZ,
            .FINI_ARRAY => std.elf.DT_FINI_ARRAYSZ,
            .PREINIT_ARRAY => std.elf.DT_PREINIT_ARRAYSZ,
            else => unreachable,
        };
        elf.updateDynamicEntry(arraysz_dyn_key, new_size);
    }

    const end_vaddr: u64 = switch (elf.shdrPtr(shndx)) {
        inline else => |shdr| shndx.vaddr(elf) + elf.targetLoad(&shdr.size),
    };
    const end_sym_name = elf.stringExisting(.strtab, "__" ++ name ++ "_end");
    Symbol.Id.global(end_sym_name).flushMoved(elf, end_vaddr);
}

pub fn prelink(elf: *Elf, prog_node: std.Progress.Node) link.Error!void {
    _ = prog_node;
    const diags = &elf.base.comp.link_diags;
    elf.prelinkInner() catch |err| switch (err) {
        error.MappedFileIo => return diags.fail("failed to write output file: {t}", .{elf.mf.io_err.?}),
        else => |e| return e,
    };
}
fn prelinkInner(elf: *Elf) Error!void {
    const comp = elf.base.comp;
    const gpa = comp.gpa;

    if (comp.zcu != null and !comp.config.use_llvm) {
        // We're use self-hosted codegen---add an input representing the Zig "object".
        try elf.ensureUnusedSymbolCapacity(1, .all_local);
        try elf.inputs.ensureUnusedCapacity(gpa, 1);
        const zcu_name = try std.fmt.allocPrint(gpa, "{s}_zcu", .{
            std.fs.path.stem(elf.base.emit.sub_path),
        });
        defer gpa.free(zcu_name);
        const zcu_file_symbol = elf.addLocalSymbolAssumeCapacity(.{
            .node = .none,
            .name = try elf.string(.strtab, zcu_name),
            .value = 0,
            .size = 0,
            .type = .FILE,
            .shndx = .ABS,
        });
        elf.inputs.addOneAssumeCapacity().* = .{
            .path = elf.base.emit,
            .member = null,
            .file_symbol = zcu_file_symbol,
        };
    }

    const got_plt = switch (elf.ehdrField(.machine)) {
        .SPARCV9 => false,
        else => true,
    };

    if (elf.shndx.dynamic != .UNDEF) switch (elf.identClass()) {
        .NONE, _ => unreachable,
        inline else => |ct_class| {
            const ElfN = ct_class.ElfN();
            const flags: ElfN.Addr = if (elf.options.z_now) std.elf.DF_BIND_NOW else 0;
            const flags_1: ElfN.Addr = if (elf.options.z_now) std.elf.DF_1_NOW else 0;
            const rpath: String(.dynstr) = rpath: {
                var buf: std.ArrayList(u8) = .empty;
                defer buf.deinit(gpa);
                for (elf.options.rpath_list, 0..) |path, i| {
                    if (i > 0) try buf.append(gpa, ':');
                    try buf.appendSlice(gpa, path);
                }
                break :rpath try elf.string(.dynstr, buf.items);
            };
            // Static PIEs don't need a PLT, so we shouldn't emit the associated dynamic entries.
            const use_plt = !(comp.config.output_mode == .Exe and
                comp.config.link_mode == .static and
                comp.config.pie);
            const soname: ?String(.dynstr) = if (elf.options.soname) |soname_slice| str: {
                break :str try elf.string(.dynstr, soname_slice);
            } else null;
            const needed_len = elf.needed.count();
            const dynamic_len = needed_len + @intFromBool(elf.options.soname != null) +
                @intFromBool(rpath != .empty) +
                @intFromBool(flags != 0) + @intFromBool(flags_1 != 0) +
                @as(usize, @intFromBool(elf.shndx.init_array != .UNDEF)) * 2 +
                @as(usize, @intFromBool(elf.shndx.fini_array != .UNDEF)) * 2 +
                @as(usize, @intFromBool(elf.shndx.preinit_array != .UNDEF)) * 2 +
                @as(usize, @intFromBool(use_plt)) * 4 +
                @intFromBool(comp.config.output_mode == .Exe) + 8;
            const dynamic_size: u32 = @intCast(@sizeOf(ElfN.Addr) * 2 * dynamic_len);
            const dynamic_ni = elf.shndx.dynamic.get(elf).ni;
            try dynamic_ni.resize(&elf.mf, gpa, dynamic_size);
            switch (elf.shdrPtr(elf.shndx.dynamic)) {
                inline else => |shdr| elf.targetStore(&shdr.size, dynamic_size),
            }

            const dynamic_indices: struct {
                init_array: ?usize,
                fini_array: ?usize,
                preinit_array: ?usize,
                jmprel: ?usize,
                pltgot: ?usize,
            } = indices: {
                const sec_dynamic = dynamic_ni.slice(&elf.mf);
                const dynamic_entries: [][2]ElfN.Addr = @ptrCast(@alignCast(sec_dynamic));
                errdefer comptime unreachable; // don't invalidate `dynamic_entries`
                var dynamic_index: usize = 0;
                for (
                    dynamic_entries[dynamic_index..][0..needed_len],
                    elf.needed.keys(),
                ) |*dynamic_entry, needed| dynamic_entry.* = .{ std.elf.DT_NEEDED, @intFromEnum(needed) };
                dynamic_index += needed_len;
                if (soname) |soname_dynstr| {
                    dynamic_entries[dynamic_index] = .{ std.elf.DT_SONAME, @intFromEnum(soname_dynstr) };
                    dynamic_index += 1;
                }
                if (rpath != .empty) {
                    dynamic_entries[dynamic_index] = .{ std.elf.DT_RUNPATH, @intFromEnum(rpath) };
                    dynamic_index += 1;
                }
                if (flags != 0) {
                    dynamic_entries[dynamic_index] = .{ std.elf.DT_FLAGS, flags };
                    dynamic_index += 1;
                }
                if (flags_1 != 0) {
                    dynamic_entries[dynamic_index] = .{ std.elf.DT_FLAGS_1, flags_1 };
                    dynamic_index += 1;
                }
                if (comp.config.output_mode == .Exe) {
                    dynamic_entries[dynamic_index] = .{ std.elf.DT_DEBUG, 0 };
                    dynamic_index += 1;
                }
                const init_array_index: ?usize = if (elf.shndx.init_array != .UNDEF) i: {
                    dynamic_entries[dynamic_index..][0..2].* = .{
                        .{ std.elf.DT_INIT_ARRAY, 0 }, // reloc added below
                        .{ std.elf.DT_INIT_ARRAYSZ, elf.targetLoad(
                            &@field(elf.shdrPtr(elf.shndx.init_array), @tagName(ct_class)).size,
                        ) },
                    };
                    defer dynamic_index += 2;
                    break :i dynamic_index;
                } else null;
                const fini_array_index: ?usize = if (elf.shndx.fini_array != .UNDEF) i: {
                    dynamic_entries[dynamic_index..][0..2].* = .{
                        .{ std.elf.DT_FINI_ARRAY, 0 }, // reloc added below
                        .{ std.elf.DT_FINI_ARRAYSZ, elf.targetLoad(
                            &@field(elf.shdrPtr(elf.shndx.fini_array), @tagName(ct_class)).size,
                        ) },
                    };
                    defer dynamic_index += 2;
                    break :i dynamic_index;
                } else null;
                const preinit_array_index: ?usize = if (elf.shndx.preinit_array != .UNDEF) i: {
                    dynamic_entries[dynamic_index..][0..2].* = .{
                        .{ std.elf.DT_PREINIT_ARRAY, 0 }, // reloc added below
                        .{ std.elf.DT_PREINIT_ARRAYSZ, elf.targetLoad(
                            &@field(elf.shdrPtr(elf.shndx.preinit_array), @tagName(ct_class)).size,
                        ) },
                    };
                    defer dynamic_index += 2;
                    break :i dynamic_index;
                } else null;
                const jmprel_index: ?usize, const pltgot_index: ?usize = if (use_plt) i: {
                    dynamic_entries[dynamic_index..][0..4].* = .{
                        .{ std.elf.DT_JMPREL, 0 }, // reloc added below
                        .{ std.elf.DT_PLTGOT, 0 }, // reloc added below
                        .{ std.elf.DT_PLTRELSZ, elf.targetLoad(
                            &@field(elf.shdrPtr(elf.shndx.rela_plt), @tagName(ct_class)).size,
                        ) },
                        .{ std.elf.DT_PLTREL, std.elf.DT_RELA },
                    };
                    defer dynamic_index += 4;
                    break :i .{ dynamic_index, dynamic_index + 1 };
                } else .{ null, null };
                dynamic_entries[dynamic_index..][0..8].* = .{
                    .{ std.elf.DT_RELA, 0 }, // reloc added below
                    .{ std.elf.DT_RELASZ, elf.targetLoad(
                        &@field(elf.shdrPtr(elf.shndx.rela_dyn), @tagName(ct_class)).size,
                    ) },
                    .{ std.elf.DT_RELAENT, @sizeOf(ElfN.Rela) },
                    .{ std.elf.DT_SYMTAB, 0 }, // reloc added below
                    .{ std.elf.DT_SYMENT, @sizeOf(ElfN.Sym) },
                    .{ std.elf.DT_STRTAB, 0 }, // reloc added below
                    .{ std.elf.DT_STRSZ, elf.targetLoad(
                        &@field(elf.shdrPtr(elf.shndx.dynstr), @tagName(ct_class)).size,
                    ) },
                    .{ std.elf.DT_NULL, 0 },
                };
                dynamic_index += 8;
                assert(dynamic_index == dynamic_len);
                if (elf.targetEndian() != native_endian) for (dynamic_entries) |*dynamic_entry|
                    std.mem.byteSwapAllFields(@TypeOf(dynamic_entry.*), dynamic_entry);

                break :indices .{
                    .init_array = init_array_index,
                    .fini_array = fini_array_index,
                    .preinit_array = preinit_array_index,
                    .jmprel = jmprel_index,
                    .pltgot = pltgot_index,
                };
            };

            const dsorel: SymbolReloc.Type = switch (ct_class) {
                .NONE, _ => comptime unreachable,
                .@"32" => .dsorel32,
                .@"64" => .dsorel64,
            };

            elf.dynamic_first_symbol_reloc = @enumFromInt(elf.symbol_relocs.items.len);
            try elf.ensureUnusedRelocCapacity(dynamic_ni, 8);
            if (dynamic_indices.init_array) |index| try elf.addSymbolRelocAssumeCapacity(
                dynamic_ni,
                @sizeOf(ElfN.Addr) * (2 * index + 1),
                .local(elf.shndx.init_array.get(elf).lsi),
                0,
                dsorel,
            );
            if (dynamic_indices.fini_array) |index| try elf.addSymbolRelocAssumeCapacity(
                dynamic_ni,
                @sizeOf(ElfN.Addr) * (2 * index + 1),
                .local(elf.shndx.fini_array.get(elf).lsi),
                0,
                dsorel,
            );
            if (dynamic_indices.preinit_array) |index| try elf.addSymbolRelocAssumeCapacity(
                dynamic_ni,
                @sizeOf(ElfN.Addr) * (2 * index + 1),
                .local(elf.shndx.preinit_array.get(elf).lsi),
                0,
                dsorel,
            );
            if (dynamic_indices.jmprel) |index| try elf.addSymbolRelocAssumeCapacity(
                dynamic_ni,
                @sizeOf(ElfN.Addr) * (2 * index + 1),
                .local(elf.shndx.rela_plt.get(elf).lsi),
                0,
                dsorel,
            );
            if (dynamic_indices.pltgot) |index| try elf.addSymbolRelocAssumeCapacity(
                dynamic_ni,
                @sizeOf(ElfN.Addr) * (2 * index + 1),
                .local((if (got_plt) elf.shndx.got_plt else elf.shndx.plt).get(elf).lsi),
                0,
                dsorel,
            );
            try elf.addSymbolRelocAssumeCapacity(
                dynamic_ni,
                @sizeOf(ElfN.Addr) * (2 * (dynamic_len - 8) + 1),
                .local(elf.shndx.rela_dyn.get(elf).lsi),
                0,
                dsorel,
            );
            try elf.addSymbolRelocAssumeCapacity(
                dynamic_ni,
                @sizeOf(ElfN.Addr) * (2 * (dynamic_len - 5) + 1),
                .local(elf.shndx.dynsym.get(elf).lsi),
                0,
                dsorel,
            );
            try elf.addSymbolRelocAssumeCapacity(
                dynamic_ni,
                @sizeOf(ElfN.Addr) * (2 * (dynamic_len - 3) + 1),
                .local(elf.shndx.dynstr.get(elf).lsi),
                0,
                dsorel,
            );
        },
    };
}

fn addSection(elf: *Elf, segment_ni: MappedFile.Node.Index, opts: struct {
    name: []const u8 = "",
    type: std.elf.SHT = .NULL,
    flags: std.elf.SHF = .{},
    size: std.elf.Xword = 0,
    link: std.elf.Word = 0,
    info: std.elf.Word = 0,
    addralign: std.mem.Alignment = .@"1",
    entsize: std.elf.Word = 0,
    node_align: std.mem.Alignment = .@"1",
    fixed: bool = false,
}) Error!Section.Index {
    switch (opts.type) {
        .NULL => assert(opts.size == 0),
        .PROGBITS => assert(opts.size > 0),
        else => {},
    }
    if (opts.flags.ALLOC and elf.ehdrField(.type) != .REL) {
        assert(elf.getNode(segment_ni) == .segment);
    }
    const gpa = elf.base.comp.gpa;
    try elf.nodes.ensureUnusedCapacity(gpa, 1);
    try elf.shdrs.ensureUnusedCapacity(gpa, 1);
    if (opts.flags.ALLOC) try elf.ensureUnusedSymbolCapacity(1, .all_local);

    const shstrtab_entry = try elf.string(.shstrtab, opts.name);
    const shndx: Section.Index, const new_shdr_size = shndx: switch (elf.ehdrPtr()) {
        inline else => |ehdr, class| {
            const shndx, const shnum = alloc_shndx: switch (elf.targetLoad(&ehdr.shnum)) {
                1...std.elf.SHN_LORESERVE - 2 => |shndx| {
                    const shnum = shndx + 1;
                    elf.targetStore(&ehdr.shnum, shnum);
                    break :alloc_shndx .{ shndx, shnum };
                },
                std.elf.SHN_LORESERVE - 1 => |shndx| {
                    const shnum = shndx + 1;
                    elf.targetStore(&ehdr.shnum, 0);
                    elf.targetStore(&@field(elf.shdrPtr(.UNDEF), @tagName(class)).size, shnum);
                    break :alloc_shndx .{ shndx, shnum };
                },
                std.elf.SHN_LORESERVE...std.elf.SHN_HIRESERVE => unreachable,
                0 => {
                    const shnum_ptr = &@field(elf.shdrPtr(.UNDEF), @tagName(class)).size;
                    const shndx: u32 = @intCast(elf.targetLoad(shnum_ptr));
                    const shnum = shndx + 1;
                    elf.targetStore(shnum_ptr, shnum);
                    break :alloc_shndx .{ shndx, shnum };
                },
            };
            assert(shndx < @intFromEnum(Section.Index.LORESERVE));
            break :shndx .{ @enumFromInt(shndx), @as(u64, elf.targetLoad(&ehdr.shentsize)) * @as(u64, shnum) };
        },
    };
    try elf.ensureNodeSize(elf.ni.shdr, new_shdr_size);
    const ni = try elf.mf.addLastChildNode(gpa, switch (elf.ehdrField(.type)) {
        .NONE, .CORE, _ => unreachable,
        .REL => elf.ni.file,
        .EXEC, .DYN => segment_ni,
    }, .{
        .size = opts.size,
        .alignment = opts.addralign.max(opts.node_align),
        .fixed = opts.fixed,
        .resized = opts.size > 0,
    });
    const addr = elf.computeNodeVAddr(ni);
    const lsi: Symbol.LocalIndex = if (opts.flags.ALLOC) elf.addLocalSymbolAssumeCapacity(.{
        .node = ni,
        .name = .empty,
        .value = addr,
        .size = 0,
        .type = .SECTION,
        .shndx = shndx,
    }) else .null;
    elf.shdrs.appendAssumeCapacity(.{ .lsi = lsi, .ni = ni, .rela = switch (opts.type) {
        .REL => unreachable,
        .RELA => .{ .free_head = .none },
        else => .{ .shndx = .UNDEF },
    } });
    elf.nodes.appendAssumeCapacity(.{ .section = shndx });
    const offset = ni.fileLocation(&elf.mf, false).offset;
    switch (elf.shdrPtr(shndx)) {
        inline else => |shdr, class| {
            shdr.* = .{
                .name = @intFromEnum(shstrtab_entry),
                .type = opts.type,
                .flags = .{ .shf = opts.flags },
                .addr = @intCast(addr),
                .offset = @intCast(offset),
                .size = @intCast(opts.size),
                .link = opts.link,
                .info = opts.info,
                .addralign = @intCast(opts.addralign.toByteUnits()),
                .entsize = opts.entsize,
            };
            if (elf.targetEndian() != native_endian) std.mem.byteSwapAllFields(class.ElfN().Shdr, shdr);
        },
    }
    return shndx;
}

fn ensureUnusedRelocCapacity(elf: *Elf, node: MappedFile.Node.Index, len: usize) Error!void {
    if (len == 0) return;
    const gpa = elf.base.comp.gpa;
    try elf.symbol_relocs.ensureUnusedCapacity(gpa, len);
    try elf.got_relocs.ensureUnusedCapacity(gpa, len);
    const class = elf.identClass();
    switch (elf.ehdrField(.type)) {
        .NONE, .CORE, _ => unreachable,
        .REL => {
            const shndx = elf.getNodeShndx(node);
            if (shndx.get(elf).rela.shndx == .UNDEF) {
                var bfa_buf: [32]u8 = undefined;
                var bfa: std.heap.BufferFirstAllocator = .init(&bfa_buf, gpa);
                const allocator = bfa.allocator();

                const rela_name = try std.fmt.allocPrint(allocator, ".rela{s}", .{shndx.name(elf).slice(elf)});
                defer allocator.free(rela_name);

                assert(elf.section_by_name.count() == elf.shdrs.items.len);
                try elf.section_by_name.ensureUnusedCapacity(gpa, 1);
                const rela_shndx = try elf.addSection(.none, .{
                    .name = rela_name,
                    .type = .RELA,
                    .link = @intFromEnum(Section.Index.symtab),
                    .info = shndx.toSection().?,
                    .addralign = switch (class) {
                        .NONE, _ => unreachable,
                        .@"32" => .@"4",
                        .@"64" => .@"8",
                    },
                    .entsize = switch (class) {
                        .NONE, _ => unreachable,
                        inline else => |ct_class| @sizeOf(ct_class.ElfN().Rela),
                    },
                    .node_align = elf.mf.flags.block_size,
                });
                elf.section_by_name.putAssumeCapacityNoClobber(rela_shndx.name(elf), {});
                shndx.get(elf).rela.shndx = rela_shndx;
            }
            try shndx.get(elf).rela.shndx.relaEnsureAdditionalCapacity(elf, len);
        },
        .EXEC, .DYN => {
            try elf.tls_size_symbol_relocs.ensureUnusedCapacity(gpa, len);
            const new_got_entries = len * 2; // at worst, every reloc is a new TLSGD
            try elf.got.ensureUnusedCapacity(gpa, new_got_entries);
            const need_got_size = switch (class) {
                .NONE, _ => unreachable,
                inline else => |ct_class| (elf.got.count() + new_got_entries) * @sizeOf(ct_class.ElfN().Addr),
            };
            try elf.ensureNodeSize(elf.shndx.got.get(elf).ni, need_got_size);

            if (elf.shndx.dynamic != .UNDEF) {
                try elf.shndx.rela_dyn.relaEnsureAdditionalCapacity(elf, new_got_entries);
            }
        },
    }
}
/// Although this function requires a preceding call to `ensureUnusedRelocCapacity`, it is still
/// fallible, because there are some rare cases for which we cannot reserve capacity upfront.
fn addRelocAssumeCapacity(
    elf: *Elf,
    node: MappedFile.Node.Index,
    offset: u64,
    target: Symbol.Id,
    addend: i64,
    @"type": MachineRelocType,
) Error!void {
    assert(node != .none);
    switch (elf.ehdrField(.type)) {
        .NONE, .CORE, _ => unreachable,
        .REL => {
            const rela_shndx = elf.getNodeShndx(node).get(elf).rela.shndx;
            const rela_index = rela_shndx.relaAddOneAssumeCapacity(elf, .{
                .type = @"type",
                // This field needs to equal the offset into the section, which is *not* necessarily
                // the same thing as our `offset`, which is the offset into `node`. We could compute
                // the section offset now, but there's no point, because `flushMovedNodeRelocs` will
                // eventually do it for us anyway, so just init to 0.
                .offset = 0,
                .raw_sym_index = @intFromEnum(target.index(elf)),
                .addend = addend,
            });
            const ri: SymbolReloc.Index = @enumFromInt(elf.symbol_relocs.items.len);
            const next: SymbolReloc.Index = next: {
                const target_ptr = target.index(elf).ptr(elf);
                const next = target_ptr.first_target_reloc;
                target_ptr.first_target_reloc = ri;
                break :next next;
            };
            if (next != .none) {
                next.get(elf).prev = ri;
            }
            elf.symbol_relocs.appendAssumeCapacity(.{
                .node = node,
                .offset = offset,
                .type = .write_rela,
                .target = target,
                .addend = addend,
                .next = next,
                .prev = .none,
                .rela_index = rela_index.toOptional(),
            });
        },

        .DYN, .EXEC => switch (elf.ehdrField(.machine)) {
            else => |machine| @panic(@tagName(machine)),
            .X86_64 => switch (@"type".X86_64) {
                _,
                .NONE,
                .COPY,
                .GLOB_DAT,
                .JUMP_SLOT,
                .RELATIVE64,
                .RELATIVE,
                .IRELATIVE,
                .@"16",
                .PC16,
                .@"8",
                .PC8,
                .DTPMOD64,
                .GOTPLT64,
                => @panic("TODO: error for illegal or unsupported input relocation"),

                // TODO: the psABI links to https://www.fsfla.org/~lxoliva/writeups/TLS/RFC-TLSDESC-x86.txt
                .GOTPC32_TLSDESC => @panic("TODO: R_X86_64_GOTPC32_TLSDESC"),
                .TLSDESC_CALL => @panic("TODO: R_X86_64_TLSDESC_CALL"),
                .TLSDESC => @panic("TODO: R_X86_64_TLSDESC"),

                // Relocations targeting a symbol
                .@"64" => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .abs64),
                .@"32" => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .abs32),
                .@"32S" => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .abs32s),
                .PC64 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .rel64),
                .PC32 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .rel32),
                .PLT32 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .pltrel32),
                .SIZE64 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .size64),
                .SIZE32 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .size32),
                .DTPOFF64 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .dtpoff64),
                .DTPOFF32 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .dtpoff32),
                .TPOFF64 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .tpoff64),
                .TPOFF32 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .tpoff32),
                .GOTPC64 => {
                    const got_sym: Symbol.Id = .local(elf.shndx.got.get(elf).lsi);
                    try elf.addSymbolRelocAssumeCapacity(node, offset, got_sym, addend, .rel64);
                },
                .GOTPC32 => {
                    const got_sym: Symbol.Id = .local(elf.shndx.got.get(elf).lsi);
                    try elf.addSymbolRelocAssumeCapacity(node, offset, got_sym, addend, .rel32);
                },

                // TODO: these are the address of an arbitrary symbol (or PLT entry) relative to the
                // base of the GOT, which is quite annoying. Luckily, they seem to be rare, so I'm
                // probably just going to introduce a set (ArrayHashMap) of SymbolReloc.Index which
                // need to be re-applied whenever the GOT moves.
                .GOTOFF64 => @panic("TODO: R_X86_64_GOTOFF64"), // offset of symbol from GOT base
                .PLTOFF64 => @panic("TODO: R_X86_64_PLTOFF64"), // offset of PLT entry from GOT base (yes, I know, the name is stupid)

                // Relocations targeting a GOT entry
                .GOT64 => elf.addGotRelocAssumeCapacity(node, offset, .{ .symbol = target }, addend, .offset64),
                .GOT32 => elf.addGotRelocAssumeCapacity(node, offset, .{ .symbol = target }, addend, .offset32),
                .GOTPCREL64 => elf.addGotRelocAssumeCapacity(node, offset, .{ .symbol = target }, addend, .rel64),
                .GOTPCREL => elf.addGotRelocAssumeCapacity(node, offset, .{ .symbol = target }, addend, .rel32),
                // TODO: the next two are relaxable to non-GOT relocations, but I haven't figured
                // out how to represent relaxations yet. If we want to remove a `GotReloc` and add a
                // `SymbolReloc` at some point, we can't do that in `GotReloc.apply`, because that
                // function must be idempotent to ensure reproducible binaries. I think we would
                // need to do that as soon as the operation is known to be relaxable (e.g. because
                // we found a defininition for a non-preemptible symbol).
                .GOTPCRELX => elf.addGotRelocAssumeCapacity(node, offset, .{ .symbol = target }, addend, .rel32),
                .REX_GOTPCRELX => elf.addGotRelocAssumeCapacity(node, offset, .{ .symbol = target }, addend, .rel32),

                .TLSGD => elf.addGotRelocAssumeCapacity(node, offset, .{ .tlsgd0 = target }, addend, .rel32),
                .TLSLD => elf.addGotRelocAssumeCapacity(node, offset, .tlsld0, addend, .rel32),
                .GOTTPOFF => elf.addGotRelocAssumeCapacity(node, offset, .{ .tpoff = target }, addend, .rel32),
            },
            .LOONGARCH => switch (@"type".LOONGARCH) {
                else => std.debug.panic("TODO: unsupported input relocation, {t}", .{@"type".LOONGARCH}),
                _,
                .NONE,
                .COPY,
                .JUMP_SLOT,
                .RELATIVE,
                .IRELATIVE,
                => std.debug.panic("TODO: error for illegal or unsupported input relocation, {t}", .{@"type".LOONGARCH}),

                .RELAX => {}, // TODO: relaxation is not yet implemented

                // Relocations targeting a symbol
                .@"64" => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .abs64),
                .@"32" => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .abs32),
                .@"64_PCREL" => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .rel64),
                .@"32_PCREL" => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .rel32),

                .PCALA_LO12 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .larch_abs32_lo12),
                .PCALA_HI20 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .larch_rel32_hi20),
                .PCALA64_HI12 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .larch_rel64_hi12),
                .PCALA64_LO20 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .larch_rel64_lo20),

                .B16 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .larch_branch_rel18),
                .B21 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .larch_branch_rel23),
                .B26 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .larch_branch_rel28),
                .CALL36 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .larch_call_rel38),

                // Relocations targeting a TLS symbol
                .TLS_LE_LO12, .TLS_LE_LO12_R => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .larch_tpoff32_lo12),
                .TLS_LE_HI20, .TLS_LE_HI20_R => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .larch_tpoff32_hi20),
                .TLS_LE64_LO20 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .larch_tpoff64_lo20),
                .TLS_LE64_HI12 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .larch_tpoff64_hi12),
                .TLS_LE_ADD_R => {}, // TODO: relaxation is not yet implemented

                // Relocations targeting a GOT entry
                .GOT_PC_LO12 => elf.addGotRelocAssumeCapacity(node, offset, .{ .symbol = target }, addend, .larch_abs32_lo12),
                .GOT_PC_HI20 => elf.addGotRelocAssumeCapacity(node, offset, .{ .symbol = target }, addend, .larch_rel32_hi20),
                .GOT64_PC_LO20 => elf.addGotRelocAssumeCapacity(node, offset, .{ .symbol = target }, addend, .larch_rel64_lo20),
                .GOT64_PC_HI12 => elf.addGotRelocAssumeCapacity(node, offset, .{ .symbol = target }, addend, .larch_rel64_hi12),

                .GOT_LO12 => elf.addGotRelocAssumeCapacity(node, offset, .{ .symbol = target }, addend, .larch_abs32_lo12),
                .GOT_HI20 => elf.addGotRelocAssumeCapacity(node, offset, .{ .symbol = target }, addend, .larch_abs32_hi20),
                .GOT64_LO20 => elf.addGotRelocAssumeCapacity(node, offset, .{ .symbol = target }, addend, .larch_abs64_lo20),
                .GOT64_HI12 => elf.addGotRelocAssumeCapacity(node, offset, .{ .symbol = target }, addend, .larch_abs64_hi12),
            },
            .SPARCV9 => switch (@"type".SPARC) {
                _,
                .NONE,
                .COPY,
                .GLOB_DAT,
                .JMP_SLOT,
                .RELATIVE,
                .IRELATIVE,
                => std.debug.panic("TODO: error for illegal or unsupported input relocation, {t}", .{@"type".SPARC}),

                inline .WDISP22,
                .HI22,
                .@"22",
                .@"13",
                .LO10,
                .HIPLT22,
                .LOPLT10,
                .PCPLT22,
                .PCPLT10,
                .@"10",
                .@"11",
                .OLO10,
                .HH22,
                .HM10,
                .LM22,
                .PC_HH22,
                .PC_HM10,
                .PC_LM22,
                .WDISP16,
                .WDISP19,
                .@"7",
                .@"5",
                .@"6",
                .HIX22,
                .LOX10,
                .REGISTER,
                .TLS_GD_HI22,
                .TLS_GD_LO10,
                .TLS_IE_HI22,
                .TLS_IE_LO10,
                .TLS_DTPMOD32,
                .TLS_DTPMOD64,
                .H34,
                .WDISP10,
                => |t| @panic("TODO: " ++ @tagName(t)),

                // Relocations targeting a symbol
                .@"8" => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .abs8),
                .@"16" => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .abs16),
                .@"32" => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .abs32),
                .DISP8 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .rel8),
                .DISP16 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .rel16),
                .DISP32 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .rel32),
                .WDISP30 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .sparc_wdisp30),
                .PC10 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .sparc_pc10),
                .PC22 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .sparc_pc22),
                .WPLT30 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .sparc_wplt30),
                .UA32 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .abs32),
                .PLT32 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .pltabs32),
                .PCPLT32 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .pltrel32),
                .@"64" => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .abs64),
                .DISP64 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .rel64),
                .PLT64 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .pltabs64),
                .H44 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .sparc_h44),
                .M44 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .sparc_m44),
                .L44 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .sparc_l44),
                .UA64 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .abs64),
                .UA16 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .abs16),
                .TLS_GD_CALL, .TLS_LDM_CALL => try elf.addSymbolRelocAssumeCapacity(node, offset, try elf.externSymbolInner(.{
                    .lib_name = null,
                    .name = "__tls_get_addr",
                    .type = .FUNC,
                }), addend, .sparc_wplt30),
                .SIZE32 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .size32),
                .SIZE64 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .size64),

                // Relocations targeting a TLS symbol
                .TLS_LDO_HIX22 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .sparc_ldo_hix22),
                .TLS_LDO_LOX10 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .sparc_ldo_lox10),
                .TLS_LE_HIX22 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .sparc_le_hix22),
                .TLS_LE_LOX10 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .sparc_le_lox10),
                .TLS_DTPOFF32 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .dtpoff32),
                .TLS_DTPOFF64 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .dtpoff64),
                .TLS_TPOFF32 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .tpoff32),
                .TLS_TPOFF64 => try elf.addSymbolRelocAssumeCapacity(node, offset, target, addend, .tpoff64),
                // We currently do no relaxation, so nothing to do for these.
                .TLS_GD_ADD,
                .TLS_LDM_ADD,
                .TLS_LDO_ADD,
                .TLS_IE_LD,
                .TLS_IE_LDX,
                .TLS_IE_ADD,
                => {},

                // Relocations targeting a GOT entry
                .GOT10 => elf.addGotRelocAssumeCapacity(node, offset, .{ .symbol = target }, addend, .sparc_10),
                .GOT13 => elf.addGotRelocAssumeCapacity(node, offset, .{ .symbol = target }, addend, .sparc_13),
                .GOT22 => elf.addGotRelocAssumeCapacity(node, offset, .{ .symbol = target }, addend, .sparc_22),
                .TLS_LDM_HI22 => elf.addGotRelocAssumeCapacity(node, offset, .tlsld0, addend, .sparc_ldm_hi22),
                .TLS_LDM_LO10 => elf.addGotRelocAssumeCapacity(node, offset, .tlsld0, addend, .sparc_ldm_lo10),
                // These need similar handling to `R_X86_64_GOTOFF64`. No compiler seems to emit them though.
                .GOTDATA_HIX22 => @panic("TODO: R_SPARC_GOTDATA_HIX22"),
                .GOTDATA_LOX10 => @panic("TODO: R_SPARC_GOTDATA_LOX10"),
                .GOTDATA_OP_HIX22 => elf.addGotRelocAssumeCapacity(node, offset, .{ .symbol = target }, addend, .sparc_op_hix22),
                .GOTDATA_OP_LOX10 => elf.addGotRelocAssumeCapacity(node, offset, .{ .symbol = target }, addend, .sparc_op_lox10),
                // We currently do no relaxation, so nothing to do for this one.
                .GOTDATA_OP => {},
            },
        },
    }
}
fn addSymbolRelocAssumeCapacity(
    elf: *Elf,
    node: MappedFile.Node.Index,
    offset: u64,
    target: Symbol.Id,
    addend: i64,
    @"type": SymbolReloc.Type,
) Error!void {
    assert(elf.ehdrField(.type) != .REL);
    assert(node != .none);

    const rela_index: Section.RelaIndex.Optional = r: {
        // If we emit a runtime relocation entry, its `offset` is a virtual address, so we need to
        // determine the vaddr of `node`.
        const node_vaddr: u64 = switch (elf.getNode(node)) {
            .file => unreachable,
            .ehdr => unreachable,
            .shdr => unreachable,
            .segment => unreachable,
            .copied_global => unreachable,
            .section => |shndx| shndx.vaddr(elf),
            .input_section => |isi| isi.ptrConst(elf).vaddr,
            inline .nav,
            .uav,
            .lazy_code,
            .lazy_const_data,
            => |i| Symbol.Id.local(i.symbol(elf)).value(elf),
        };

        const rela_type: MachineRelocType = switch (elf.ehdrField(.machine)) {
            else => |machine| @panic(@tagName(machine)),
            .X86_64 => .{ .X86_64 = switch (@"type") {
                .write_rela => unreachable,
                .dsorel64, .dsorel32 => {
                    assert(target.unwrap() == .local);
                    break :r .none;
                },
                .abs64 => .@"64",
                .abs32 => .@"32",
                .abs16 => unreachable,
                .abs8 => unreachable,
                .abs32s => .@"32S",
                .rel64 => .PC64,
                .rel32 => .PC32,
                .rel16 => unreachable,
                .rel8 => unreachable,
                .pltabs64, .pltabs32, .pltrel64, .pltrel32 => break :r .none,
                .dtpoff64 => .DTPOFF64,
                .dtpoff32 => .DTPOFF32,
                .tpoff64 => .TPOFF64,
                .tpoff32 => .TPOFF32,
                .size64 => .SIZE64,
                .size32 => .SIZE32,

                .larch_abs32_lo12,
                .larch_rel32_hi20,
                .larch_rel64_lo20,
                .larch_rel64_hi12,
                .larch_branch_rel18,
                .larch_branch_rel23,
                .larch_branch_rel28,
                .larch_call_rel38,
                .larch_tpoff32_lo12,
                .larch_tpoff32_hi20,
                .larch_tpoff64_lo20,
                .larch_tpoff64_hi12,
                => unreachable,

                .sparc_wdisp30,
                .sparc_pc10,
                .sparc_pc22,
                .sparc_wplt30,
                .sparc_h44,
                .sparc_m44,
                .sparc_l44,
                .sparc_ldo_hix22,
                .sparc_ldo_lox10,
                .sparc_le_hix22,
                .sparc_le_lox10,
                => unreachable,
            } },
            .LOONGARCH => .{ .LOONGARCH = switch (@"type") {
                .write_rela => unreachable,
                .dsorel64, .dsorel32 => {
                    assert(target.unwrap() == .local);
                    break :r .none;
                },
                .abs64 => .@"64",
                .abs32 => .@"32",
                .abs32s => unreachable,
                .abs16 => unreachable,
                .abs8 => unreachable,
                .rel64 => .@"64_PCREL",
                .rel32 => .@"32_PCREL",
                .rel16 => unreachable,
                .rel8 => unreachable,
                .pltabs64, .pltabs32, .pltrel64, .pltrel32 => break :r .none,
                .dtpoff64 => .TLS_DTPREL64,
                .dtpoff32 => .TLS_DTPREL32,
                .tpoff64 => .TLS_TPREL64,
                .tpoff32 => .TLS_TPREL32,
                .size64 => unreachable,
                .size32 => unreachable,

                .larch_abs32_lo12 => .PCALA_LO12,
                .larch_rel32_hi20 => .PCALA_HI20,
                .larch_rel64_lo20 => .PCALA64_LO20,
                .larch_rel64_hi12 => .PCALA64_HI12,
                .larch_branch_rel18 => .B16,
                .larch_branch_rel23 => .B21,
                .larch_branch_rel28 => .B26,
                .larch_call_rel38 => .CALL36,
                .larch_tpoff32_lo12 => .TLS_LE_LO12,
                .larch_tpoff32_hi20 => .TLS_LE_HI20,
                .larch_tpoff64_lo20 => .TLS_LE64_LO20,
                .larch_tpoff64_hi12 => .TLS_LE64_HI12,

                .sparc_wdisp30,
                .sparc_pc10,
                .sparc_pc22,
                .sparc_wplt30,
                .sparc_h44,
                .sparc_m44,
                .sparc_l44,
                .sparc_ldo_hix22,
                .sparc_ldo_lox10,
                .sparc_le_hix22,
                .sparc_le_lox10,
                => unreachable,
            } },
            .SPARCV9 => .{ .SPARC = switch (@"type") {
                .write_rela => unreachable,
                .dsorel64, .dsorel32 => {
                    assert(target.unwrap() == .local);
                    break :r .none;
                },
                .abs64 => .@"64",
                .abs32 => .@"32",
                .abs32s => unreachable,
                .abs16 => .@"16",
                .abs8 => .@"8",
                .rel64 => .DISP64,
                .rel32 => .DISP32,
                .rel16 => .DISP16,
                .rel8 => .DISP8,
                .pltabs64, .pltabs32, .pltrel64, .pltrel32 => break :r .none,
                .dtpoff64 => .TLS_DTPOFF64,
                .dtpoff32 => .TLS_DTPOFF32,
                .tpoff64 => .TLS_TPOFF64,
                .tpoff32 => .TLS_TPOFF32,
                .size64 => .SIZE64,
                .size32 => .SIZE32,

                .larch_abs32_lo12,
                .larch_rel32_hi20,
                .larch_rel64_lo20,
                .larch_rel64_hi12,
                .larch_branch_rel18,
                .larch_branch_rel23,
                .larch_branch_rel28,
                .larch_call_rel38,
                .larch_tpoff32_lo12,
                .larch_tpoff32_hi20,
                .larch_tpoff64_lo20,
                .larch_tpoff64_hi12,
                => unreachable,

                .sparc_wdisp30 => .WDISP30,
                .sparc_pc10 => .PC10,
                .sparc_pc22 => .PC22,
                .sparc_wplt30 => .WPLT30,
                .sparc_h44 => .H44,
                .sparc_m44 => .M44,
                .sparc_l44 => .L44,
                .sparc_ldo_hix22 => .TLS_LDO_HIX22,
                .sparc_ldo_lox10 => .TLS_LDO_LOX10,
                .sparc_le_hix22 => .TLS_LE_HIX22,
                .sparc_le_lox10 => .TLS_LE_LOX10,
            } },
        };

        class: switch (elf.classifySymbolValue(target)) {
            .static => break :r .none,
            .static_relative => {
                if (!@"type".isAbsAddr(elf)) break :r .none;
                switch (elf.nodeWantsDsoRelocation(node)) {
                    .no => break :r .none,
                    .yes => {},
                    .yes_textrel => elf.textrel_count += 1,
                }
                break :r elf.shndx.rela_dyn.relaAddOneAssumeCapacity(elf, .{
                    .type = .relative(elf),
                    .offset = node_vaddr + offset,
                    .raw_sym_index = 0,
                    .addend = 0,
                }).toOptional();
            },
            .dynamic => dso_reloc: switch (elf.nodeWantsDsoRelocation(node)) {
                .no => break :r .none,
                .yes_textrel => if (try elf.maybeAddCopyRelocation(target.unwrap().global)) {
                    // We were able to use a copy relocation on this symbol to avoid a text relocation,
                    // which is apparently considered a good thing despite copy relocations being an
                    // abomination. (This is necessary for correctness in some cases, because e.g. a
                    // 32-bit runtime relocation on a 64-bit target will often cause rtld errors due to
                    // the DSOs being loaded too far apart.)
                    switch (elf.classifySymbolValue(target)) {
                        .dynamic => unreachable, // we just added a copy relocation
                        .static => continue :class .static,
                        .static_relative => continue :class .static_relative,
                    }
                } else {
                    // At least for now, our only choice is a text relocation.
                    elf.textrel_count += 1;
                    continue :dso_reloc .yes;
                },
                .yes => break :r elf.shndx.rela_dyn.relaAddOneAssumeCapacity(elf, .{
                    .type = rela_type,
                    .offset = node_vaddr + offset,
                    .raw_sym_index = elf.globalByName(target.unwrap().global).?.dynsym_index,
                    .addend = addend,
                }).toOptional(),
            },
        }
    };

    const ri: SymbolReloc.Index = @enumFromInt(elf.symbol_relocs.items.len);
    const target_ptr = target.index(elf).ptr(elf);
    const next = target_ptr.first_target_reloc;
    target_ptr.first_target_reloc = ri;
    if (next != .none) {
        next.get(elf).prev = ri;
    }
    elf.symbol_relocs.appendAssumeCapacity(.{
        .node = node,
        .offset = offset,
        .target = target,
        .addend = addend,
        .type = @"type",
        .next = next,
        .prev = .none,
        .rela_index = rela_index,
    });
    if (@"type".dependsOnTlsSize()) {
        elf.tls_size_symbol_relocs.putAssumeCapacityNoClobber(ri, {});
    }

    // Actually apply the new relocation!
    ri.get(elf).apply(elf);
}
fn addGotRelocAssumeCapacity(
    elf: *Elf,
    node: MappedFile.Node.Index,
    offset: u64,
    target: GotKey,
    addend: i64,
    @"type": GotReloc.Type,
) void {
    assert(elf.ehdrField(.type) != .REL);
    switch (elf.getNode(node)) {
        .input_section,
        .nav,
        .lazy_code,
        .lazy_const_data,
        => {},

        .section => unreachable, // cannot contain GOT relocs
        .uav => unreachable, // cannot contain GOT relocs

        .file => unreachable, // cannot contain relocs
        .ehdr => unreachable, // cannot contain relocs
        .shdr => unreachable, // cannot contain relocs
        .segment => unreachable, // cannot contain relocs
        .copied_global => unreachable, // cannot contain relocs
    }

    const gop = elf.got.getOrPutAssumeCapacity(target);
    if (!gop.found_existing) {
        gop.value_ptr.* = .none;
        const maybe_next_key: ?GotKey = switch (target) {
            .reserved => null,
            .tpoff => null,
            .symbol => null,
            .tlsld0 => .tlsld1,
            .tlsgd0 => |sym| .{ .tlsgd1 = sym },
            .tlsld1 => unreachable,
            .tlsgd1 => unreachable,
        };
        switch (elf.shdrPtr(elf.shndx.got)) {
            inline else => |got_shdr, class| {
                const Addr = class.ElfN().Addr;
                const old_size = elf.targetLoad(&got_shdr.size);
                const new_entry_count = @as(u32, 1) + @intFromBool(maybe_next_key != null);
                elf.targetStore(&got_shdr.size, @intCast(old_size + @sizeOf(Addr) * new_entry_count));
            },
        }
        if (maybe_next_key) |next_key| {
            elf.got.putAssumeCapacityNoClobber(next_key, .none);
            elf.updateGotEntry(gop.index);
            elf.updateGotEntry(gop.index + 1);
        } else {
            elf.updateGotEntry(gop.index);
        }
    }

    elf.got_relocs.appendAssumeCapacity(.{
        .node = node,
        .offset = offset,
        .target = target,
        .addend = addend,
        .type = @"type",
    });
}
fn updateGotEntry(elf: *Elf, got_index: usize) void {
    const entry_value: union(enum) {
        unsigned: u64,
        signed: i64,
        reloc: struct {
            type: MachineRelocType,
            dynsym_index: u32,
            addend: i64,
        },
    } = switch (elf.got.keys()[got_index]) {
        .reserved => .{ .unsigned = 0 },
        .tpoff => |sym_id| val: {
            // Only the executable's per-module TLS block is at a known offset from the TLS pointer.
            if (elf.base.comp.config.output_mode == .Exe and elf.classifySymbolValue(sym_id) != .dynamic) {
                const tls_phndx = elf.getNode(elf.ni.tls).segment;
                const tls_size: u64 = switch (elf.phdrSlice()) {
                    inline else => |phdr| tls_size: {
                        assert(elf.targetLoad(&phdr[tls_phndx].type) == .TLS);
                        break :tls_size elf.targetLoad(&phdr[tls_phndx].memsz);
                    },
                };
                const sym_value = sym_id.value(elf);
                break :val .{ .signed = @bitCast(sym_value -% tls_size) };
            }
            const reloc_type: MachineRelocType = switch (elf.ehdrField(.machine)) {
                else => |machine| @panic(@tagName(machine)),
                .LOONGARCH => .{ .LOONGARCH = if (elf.identClass() == .@"64") .TLS_TPREL64 else .TLS_TPREL32 },
                .SPARCV9 => .{ .SPARC = if (elf.identClass() == .@"64") .TLS_TPOFF64 else .TLS_TPOFF32 },
                .X86_64 => .{ .X86_64 = .TPOFF64 },
            };
            break :val switch (sym_id.unwrap()) {
                // For global symbols, just target the right dynsym with no addend.
                .global => |name| .{ .reloc = .{
                    .type = reloc_type,
                    .dynsym_index = elf.globalByName(name).?.dynsym_index,
                    .addend = 0,
                } },
                // For local symbols, target the null symbol (index 0) so we get the offset to the
                // base of our TLS block, and then use `addend` to offset to the right symbol.
                .local => .{ .reloc = .{
                    .type = reloc_type,
                    .dynsym_index = 0,
                    .addend = @intCast(sym_id.value(elf)),
                } },
            };
        },
        .symbol => |sym| switch (elf.classifySymbolValue(sym)) {
            .static => .{ .unsigned = sym.value(elf) },
            .static_relative => .{ .reloc = .{
                .type = .relative(elf),
                .dynsym_index = 0,
                .addend = @bitCast(sym.value(elf)),
            } },
            .dynamic => .{ .reloc = .{
                .type = .globDat(elf),
                .dynsym_index = elf.globalByName(sym.unwrap().global).?.dynsym_index,
                .addend = 0,
            } },
        },
        .tlsgd1 => |sym| switch (elf.classifySymbolValue(sym)) {
            .static => .{ .unsigned = sym.value(elf) },
            .static_relative => unreachable, // TLS variables should be in TLS sections, which do not return `.static_relative`
            .dynamic => .{ .reloc = .{
                .type = .dtpOffAddr(elf),
                .dynsym_index = elf.globalByName(sym.unwrap().global).?.dynsym_index,
                .addend = 0,
            } },
        },
        .tlsgd0 => |sym| switch (elf.base.comp.config.link_mode) {
            .static => val: {
                assert(elf.base.comp.config.output_mode == .Exe); // static libraries don't have GOTs
                break :val .{ .unsigned = 1 }; // TLS module ID for executable
            },
            .dynamic => .{ .reloc = .{
                .type = switch (elf.ehdrField(.machine)) {
                    else => |machine| @panic(@tagName(machine)),
                    .LOONGARCH => .{ .LOONGARCH = if (elf.identClass() == .@"64") .TLS_DTPMOD64 else .TLS_DTPMOD32 },
                    .SPARCV9 => .{ .SPARC = if (elf.identClass() == .@"64") .TLS_DTPMOD64 else .TLS_DTPMOD32 },
                    .X86_64 => .{ .X86_64 = .DTPMOD64 },
                },
                .dynsym_index = switch (elf.classifySymbolValue(sym)) {
                    .static, .static_relative => 0,
                    .dynamic => elf.globalByName(sym.unwrap().global).?.dynsym_index,
                },
                .addend = 0,
            } },
        },
        .tlsld0 => switch (elf.base.comp.config.link_mode) {
            .static => val: {
                assert(elf.base.comp.config.output_mode == .Exe); // static libraries don't have GOTs
                break :val .{ .unsigned = 1 }; // TLS module ID for executable
            },
            .dynamic => .{ .reloc = .{
                .type = switch (elf.ehdrField(.machine)) {
                    else => |machine| @panic(@tagName(machine)),
                    .LOONGARCH => .{ .LOONGARCH = if (elf.identClass() == .@"64") .TLS_DTPMOD64 else .TLS_DTPMOD32 },
                    .SPARCV9 => .{ .SPARC = if (elf.identClass() == .@"64") .TLS_DTPMOD64 else .TLS_DTPMOD32 },
                    .X86_64 => .{ .X86_64 = .DTPMOD64 },
                },
                .dynsym_index = 0,
                .addend = 0,
            } },
        },
        .tlsld1 => .{ .unsigned = 0 },
    };

    // First, write to the GOT itself. If we're planning to use a relocation, we'll just write zeroes.
    const got_entry_addr: u64 = switch (elf.shdrPtr(elf.shndx.got)) {
        inline else => |got_shdr, class| got_entry_addr: {
            const addr_size = @sizeOf(class.ElfN().Addr);
            const offset = got_index * addr_size;
            const entry_ptr: *class.ElfN().Addr = @ptrCast(@alignCast(
                elf.shndx.got.get(elf).ni.slice(&elf.mf)[offset..][0..addr_size],
            ));
            entry_ptr.* = switch (entry_value) {
                .unsigned => |x| @intCast(x),
                .signed => |x| switch (class) {
                    .NONE, _ => comptime unreachable,
                    .@"32" => @bitCast(@as(i32, @intCast(x))),
                    .@"64" => @bitCast(x),
                },
                .reloc => 0,
            };
            break :got_entry_addr elf.targetLoad(&got_shdr.addr) + offset;
        },
    };

    // Then, add or remove the relocation entry if needed.
    if (elf.shndx.dynamic == .UNDEF) {
        // There are no relocations in the output file, so there's no reloc to delete and we can't
        // add a reloc in any case. (If we *are* requesting a reloc, it'll be because the value of
        // this GOT entry is not yet known, e.g. because a symbol is currently undefined.)
        return;
    }
    if (elf.got.values()[got_index].unwrap()) |rela_index| {
        // Clear the old relocation entry (although we might immediately re-use it below).
        elf.shndx.rela_dyn.relaDeleteOne(elf, rela_index);
    }
    elf.got.values()[got_index] = switch (entry_value) {
        .unsigned, .signed => .none, // no relocation needed
        .reloc => |reloc| elf.shndx.rela_dyn.relaAddOneAssumeCapacity(elf, .{
            .type = reloc.type,
            .offset = got_entry_addr,
            .raw_sym_index = reloc.dynsym_index,
            .addend = reloc.addend,
        }).toOptional(),
    };
}

/// If `node` cannot contain runtime relocations, returns `.no`.
///
/// If `node` can contain runtime relocations, `returns `.yes_textrel` if such a relocation requires
/// the presence of a `DT_TEXTREL` dynamic entry, or `.yes` otherwise.
fn nodeWantsDsoRelocation(elf: *Elf, node: MappedFile.Node.Index) enum { yes, yes_textrel, no } {
    const shndx = elf.getNodeShndx(node);
    const shf: std.elf.SHF = switch (elf.shdrPtr(shndx)) {
        inline else => |shdr| elf.targetLoad(&shdr.flags).shf,
    };
    if (!shf.ALLOC) return .no;
    if (!shf.WRITE) return .yes_textrel;
    return .yes;
}

/// If the given undefined global could have a copy relocation, creates that relocation if it does
/// not already exist, and returns `true`.
///
/// Returns `false` iff a copy relocation cannot currently be created for the global. If it may be
/// possible in future, the symbol is added to `elf.want_copied_globals` so that the copy relocation
/// will be created if and when we discover a suitable definition in an input DSO.
///
/// If this function creates a new copy relocation, it will also update relocations targeting the
/// global where needed---the caller does not need to do this.
///
/// Asserts that `elf.shndx.dynamic != .UNDEF` and that `global_name` refers to an *undefined* global.
fn maybeAddCopyRelocation(elf: *Elf, global_name: String(.strtab)) Error!bool {
    assert(elf.shndx.dynamic != .UNDEF);

    const gpa = elf.base.comp.gpa;

    const global_ptr = elf.globals.strong_undef.getPtr(global_name) orelse
        elf.globals.weak_undef.getPtr(global_name).?;

    assert(global_ptr.dynsym_index != 0);

    // Only dynamic executables may contain `R_*_COPY` relocations.
    if (elf.shndx.dynamic == .UNDEF) return false;
    if (elf.base.comp.config.output_mode != .Exe) return false;

    const dso_global = elf.dso_globals.get(global_name) orelse {
        // We do not have a definition to provide the correct size for the symbol. If a definition
        // is discovered in a later DSO, we may at that point be able to add a copy relocation.
        try elf.want_copied_globals.put(gpa, global_name, {});
        return false;
    };

    if (dso_global.type != .OBJECT) return false;

    const gop = try elf.copied_globals.getOrPut(gpa, global_name);
    if (gop.found_existing) return true;
    errdefer assert(elf.copied_globals.pop().?.key == global_name);

    try elf.nodes.ensureUnusedCapacity(gpa, 1);
    const node = try elf.mf.addLastChildNode(gpa, Section.Index.data.get(elf).ni, .{
        .size = dso_global.size,
        .alignment = dso_global.alignment,
    });
    errdefer comptime unreachable;

    const vaddr = elf.computeNodeVAddr(node);
    elf.nodes.appendAssumeCapacity(.{ .copied_global = global_name });
    const rela_index = elf.shndx.rela_dyn.relaAddOneAssumeCapacity(elf, .{
        .type = .copy(elf),
        .offset = vaddr,
        .raw_sym_index = global_ptr.dynsym_index,
        .addend = 0,
    });
    gop.value_ptr.* = .{
        .node = node,
        .rela_index = rela_index,
    };

    switch (elf.symPtr(global_ptr.symtab_index)) {
        inline else => |sym| elf.targetStore(&sym.size, @intCast(dso_global.size)),
    }
    switch (elf.dynsymPtr(global_ptr.dynsym_index)) {
        inline else => |dynsym| elf.targetStore(&dynsym.size, @intCast(dso_global.size)),
    }

    // Because we now have a copy relocation, any dynamic relocations which target this symbol are
    // now incorrect, since we now own the canonical address of the symbol. So delete those relocs
    // and then update the symbol's address (and re-apply relocations targeting it of course).
    Symbol.Id.global(global_name).deleteDynamicTargetRelocs(elf);
    Symbol.Id.global(global_name).flushMoved(elf, vaddr);

    return true;
}

pub fn updateNav(elf: *Elf, pt: Zcu.PerThread, nav_index: InternPool.Nav.Index) link.Error!void {
    const diags = &elf.base.comp.link_diags;
    elf.updateNavInner(pt, nav_index) catch |err| switch (err) {
        error.MappedFileIo => return diags.fail("failed to write output file: {t}", .{elf.mf.io_err.?}),
        else => |e| return e,
    };
}
fn updateNavInner(elf: *Elf, pt: Zcu.PerThread, nav_index: InternPool.Nav.Index) Error!void {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;
    const ip = &zcu.intern_pool;

    const nav = ip.getNav(nav_index);
    if (ip.indexToKey(nav.resolved.?.value) == .@"extern") return;
    if (!Type.fromInterned(nav.resolved.?.type).hasRuntimeBits(zcu)) return;

    const nmi = try elf.navMapIndex(zcu, nav_index);
    const ni = nmi.symbol(elf).index().ptr(elf).node;
    elf.resetNodeRelocs(ni);

    // Ensure the NAV is marked as moved so that once we're done, `flushMoved` will eventually be
    // called to apply the NAV's new relocations.
    try ni.moved(gpa, &elf.mf);

    var nw: MappedFile.Node.Writer = undefined;
    ni.writer(&elf.mf, gpa, &nw);
    defer nw.deinit();
    codegen.generateSymbol(
        &elf.base,
        pt,
        .fromInterned(nav.resolved.?.value),
        &nw.interface,
        .{ .atom_index = Node.toAtom(ni) },
    ) catch |err| switch (err) {
        error.WriteFailed => return nw.err.?,
        else => |e| return e,
    };
    switch (elf.symPtr(nmi.symbol(elf).index())) {
        inline else => |sym| elf.targetStore(&sym.size, @intCast(nw.interface.end)),
    }
}

pub fn updateFunc(
    elf: *Elf,
    pt: Zcu.PerThread,
    func_index: InternPool.Index,
    mir: *const codegen.AnyMir,
) link.Error!void {
    const diags = &elf.base.comp.link_diags;
    elf.updateFuncInner(pt, func_index, mir) catch |err| switch (err) {
        error.MappedFileIo => return diags.fail("failed to write output file: {t}", .{elf.mf.io_err.?}),
        else => |e| return e,
    };
}
fn updateFuncInner(
    elf: *Elf,
    pt: Zcu.PerThread,
    func_index: InternPool.Index,
    mir: *const codegen.AnyMir,
) Error!void {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;
    const ip = &zcu.intern_pool;
    const func = zcu.funcInfo(func_index);
    const nav = ip.getNav(func.owner_nav);

    const nmi = try elf.navMapIndex(zcu, func.owner_nav);
    log.debug("updateFunc({f}) = {d}", .{ nav.fqn.fmt(ip), nmi.symbol(elf) });
    const ni = nmi.symbol(elf).index().ptr(elf).node;
    elf.resetNodeRelocs(ni);

    // Ensure the NAV is marked as moved so that once we're done, `flushMoved` will eventually be
    // called to apply the NAV's new relocations.
    try ni.moved(gpa, &elf.mf);

    var nw: MappedFile.Node.Writer = undefined;
    ni.writer(&elf.mf, gpa, &nw);
    defer nw.deinit();
    codegen.emitFunction(
        &elf.base,
        pt,
        func_index,
        Node.toAtom(ni),
        mir,
        &nw.interface,
        .none,
    ) catch |err| switch (err) {
        error.WriteFailed => return nw.err.?,
        else => |e| return e,
    };
    switch (elf.symPtr(nmi.symbol(elf).index())) {
        inline else => |sym| elf.targetStore(&sym.size, @intCast(nw.interface.end)),
    }
}

pub fn updateErrorData(elf: *Elf, pt: Zcu.PerThread) link.Error!void {
    const diags = &elf.base.comp.link_diags;
    elf.flushLazy(pt, .{
        .kind = .const_data,
        .index = @intCast(elf.lazy.getPtr(.const_data).map.getIndex(.anyerror_type) orelse return),
    }) catch |err| switch (err) {
        error.MappedFileIo => return diags.fail("failed to write output file: {t}", .{elf.mf.io_err.?}),
        else => |e| return e,
    };
}

pub fn flush(
    elf: *Elf,
    arena: std.mem.Allocator,
    tid: Zcu.PerThread.Id,
    prog_node: std.Progress.Node,
) link.Error!void {
    const comp = elf.base.comp;
    const diags = &comp.link_diags;
    _ = prog_node;
    _ = arena;

    if (comp.config.output_mode == .Exe) {
        var any_undef = false;
        for (elf.globals.strong_undef.keys()) |name| {
            if (elf.dso_globals.contains(name)) continue;
            any_undef = true;
            comp.link_diags.addError("undefined global symbol '{s}'", .{name.slice(elf)});
        }
        if (any_undef) return error.AlreadyReported;
    }

    elf.updateDynamicTextrel() catch |err| switch (err) {
        error.MappedFileIo => return diags.fail("failed to write output file: {t}", .{elf.mf.io_err.?}),
        else => |e| return e,
    };

    while (try elf.idle(tid)) {}

    const entry_addr: u64 = entry: {
        const sym_name_slice: []const u8 = name: switch (elf.options.entry) {
            .default => switch (comp.config.output_mode) {
                .Exe => continue :name .enabled,
                .Lib, .Obj => continue :name .disabled,
            },
            .disabled => break :entry 0,
            .enabled => "_start",
            .named => |named| named,
        };
        const sym_name_strtab = elf.string(.strtab, sym_name_slice) catch |err| switch (err) {
            error.MappedFileIo => return diags.fail("failed to write output file: {t}", .{elf.mf.io_err.?}),
            else => |e| return e,
        };
        if (elf.globalByName(sym_name_strtab) == null) break :entry 0;
        break :entry Symbol.Id.global(sym_name_strtab).value(elf);
    };
    switch (elf.ehdrPtr()) {
        inline else => |ehdr| elf.targetStore(&ehdr.entry, @intCast(entry_addr)),
    }

    elf.mf.flush() catch |err| switch (err) {
        error.MappedFileIo => return diags.fail("failed to write output file: {t}", .{elf.mf.io_err.?}),
        else => |e| return e,
    };
}
fn updateDynamicTextrel(elf: *Elf) Error!void {
    if (elf.shndx.dynamic == .UNDEF) return;
    const dynamic_ni = elf.shndx.dynamic.get(elf).ni;
    switch (elf.shdrPtr(elf.shndx.dynamic)) {
        inline else => |shdr, class| if (elf.textrel_count > 0) {
            const cur_size = elf.targetLoad(&shdr.size);
            const cur_entries: [][2]class.ElfN().Addr = @ptrCast(@alignCast(
                dynamic_ni.slice(&elf.mf)[0..@intCast(cur_size)],
            ));
            const has_textrel: bool = for (cur_entries) |*entry| {
                if (elf.targetLoad(&entry[0]) == std.elf.DT_TEXTREL) {
                    break true;
                }
            } else false;
            if (!has_textrel) {
                // Add a DT_TEXTREL entry before the final DT_NULL entry.
                const new_size = cur_size + @sizeOf([2]class.ElfN().Addr);
                try elf.ensureNodeSize(dynamic_ni, new_size);
                elf.targetStore(&shdr.size, new_size);
                const new_entries: [][2]class.ElfN().Addr = @ptrCast(@alignCast(
                    dynamic_ni.slice(&elf.mf)[0..@intCast(new_size)],
                ));
                const write_entries = new_entries[new_entries.len - 2 ..][0..2];
                assert(elf.targetLoad(&write_entries[0][0]) == std.elf.DT_NULL);
                write_entries.* = .{
                    .{ std.elf.DT_TEXTREL, 0 },
                    .{ std.elf.DT_NULL, 0 },
                };
                if (elf.targetEndian() != native_endian) {
                    std.mem.byteSwapAllElements([2]class.ElfN().Addr, write_entries);
                }
            }
        } else {
            // TODO: remove the DT_TEXTREL entry if there is one, because it's not necessary any
            // more. It won't cause any issues having it there, it's just inefficient.
        },
    }
}

pub fn idle(elf: *Elf, tid: Zcu.PerThread.Id) link.Error!bool {
    const comp = elf.base.comp;
    const diags = &comp.link_diags;
    task: {
        while (elf.pending_uavs.pop()) |umi| {
            const sub_prog_node = elf.idleProgNode(tid, elf.const_prog_node, .{ .uav = umi });
            defer sub_prog_node.end();
            elf.flushUav(.{ .zcu = comp.zcu.?, .tid = tid }, umi) catch |err| switch (err) {
                error.MappedFileIo => return diags.fail("failed to write output file: {t}", .{elf.mf.io_err.?}),
                else => |e| return e,
            };
            break :task;
        }
        var lazy_it = elf.lazy.iterator();
        while (lazy_it.next()) |lazy| if (lazy.value.pending_index < lazy.value.map.count()) {
            const pt: Zcu.PerThread = .{ .zcu = comp.zcu.?, .tid = tid };
            const lmr: Node.LazyMapRef = .{ .kind = lazy.key, .index = lazy.value.pending_index };
            lazy.value.pending_index += 1;
            const kind = switch (lmr.kind) {
                .code => "code",
                .const_data => "data",
            };
            var name: [std.Progress.Node.max_name_len]u8 = undefined;
            const sub_prog_node = elf.synth_prog_node.start(
                std.fmt.bufPrint(&name, "lazy {s} for {f}", .{
                    kind,
                    Type.fromInterned(lmr.lazySymbol(elf).ty).fmt(pt),
                }) catch &name,
                0,
            );
            defer sub_prog_node.end();
            elf.flushLazy(pt, lmr) catch |err| switch (err) {
                error.MappedFileIo => return diags.fail("failed to write output file: {t}", .{elf.mf.io_err.?}),
                else => |e| return e,
            };
            break :task;
        };
        if (elf.input_section_pending_index < elf.input_sections.items.len) {
            const isi: InputSection.Index = @enumFromInt(elf.input_section_pending_index);
            elf.input_section_pending_index += 1;
            const sub_prog_node = elf.idleProgNode(tid, elf.input_prog_node, elf.getNode(isi.node(elf)));
            defer sub_prog_node.end();
            elf.flushInputSection(isi) catch |err| switch (err) {
                error.MappedFileIo => return diags.fail("failed to write output file: {t}", .{elf.mf.io_err.?}),
                else => |e| return e,
            };
            break :task;
        }
        if (elf.changed_symtab_index.pop()) |kv| {
            const sub_prog_node = elf.mf.update_prog_node.start(kv.key.slice(elf), 0);
            defer sub_prog_node.end();

            const global_name = kv.key;
            const global = elf.globalByName(global_name).?;
            const sym_id: Symbol.Id = .global(global_name);
            const sym = global.symtab_index.ptr(elf);

            switch (elf.ehdrField(.type)) {
                .REL => {
                    // Index in `.symtab` has changed. Relocatables are easy, we just need to update
                    // all of the output relocations.
                    const symtab_index = @intFromEnum(global.symtab_index);
                    var ri = sym.first_target_reloc;
                    while (ri != .none) {
                        const reloc = ri.get(elf);
                        assert(reloc.target == sym_id);
                        // In relocatables, every symbol relocation has an output relocation.
                        const rela_index = reloc.rela_index.unwrap().?;
                        reloc.relaSection(elf).relaUpdateSym(elf, rela_index, symtab_index);
                        ri = reloc.next;
                    }
                },
                // For other `ET_*` values, the index in `.dynsym` has changed. There are a few
                // places we might have emitted output relocations, depending on whether or not the
                // symbol's value is statically known.
                else => switch (elf.classifySymbolValue(sym_id)) {
                    .static, .static_relative => {
                        // Since the symbol value is statically known, we definitely aren't emitting
                        // any relocation targeting it (we might have `R_*_RELATIVE` relocs but they
                        // don't care about the dynsym index). The only exception is a copy reloc
                        // could exist (and be the *reason* the symbol value is statically known).
                        if (elf.copied_globals.get(global_name)) |copied| {
                            elf.shndx.rela_dyn.relaUpdateSym(elf, copied.rela_index, global.dynsym_index);
                        }
                    },
                    .dynamic => {
                        assert(!elf.copied_globals.contains(global_name)); // value would be statically known

                        // Update symbol relocs:
                        var ri = sym.first_target_reloc;
                        while (ri != .none) {
                            const reloc = ri.get(elf);
                            assert(reloc.target == sym_id);
                            // There may or may not be a runtime relocation for this symbol reloc.
                            if (reloc.rela_index.unwrap()) |rela_index| {
                                elf.shndx.rela_dyn.relaUpdateSym(elf, rela_index, global.dynsym_index);
                            }
                            ri = reloc.next;
                        }

                        // Update the PLT entry's reloc if there is one:
                        if (elf.plt.getIndex(global_name)) |plt_index| {
                            // PLT indices exactly match `.rela.plt` relocation indices.
                            elf.shndx.rela_plt.relaUpdateSym(elf, @enumFromInt(plt_index), global.dynsym_index);
                        }

                        // Update relocs for any relevant GOT entries:
                        if (elf.got.getIndex(.{ .symbol = sym_id })) |got_index| {
                            elf.updateGotEntry(got_index);
                        }
                        if (elf.got.getIndex(.{ .tpoff = sym_id })) |got_index| {
                            elf.updateGotEntry(got_index);
                        }
                        if (elf.got.getIndex(.{ .tlsgd0 = sym_id })) |got_index| {
                            elf.updateGotEntry(got_index);
                            elf.updateGotEntry(got_index + 1); // tlsgd1
                        }
                    },
                },
            }

            break :task;
        }
        while (elf.mf.updates.pop()) |ni| {
            const clean_moved = ni.cleanMoved(&elf.mf);
            const clean_resized = ni.cleanResized(&elf.mf);
            if (clean_moved or clean_resized) {
                const sub_prog_node = elf.idleProgNode(tid, elf.mf.update_prog_node, elf.getNode(ni));
                defer sub_prog_node.end();
                if (clean_moved) try elf.flushMoved(ni);
                if (clean_resized) try elf.flushResized(ni);
                break :task;
            } else elf.mf.update_prog_node.completeOne();
        }
    }
    if (elf.pending_uavs.items.len > 0) return true;
    for (&elf.lazy.values) |lazy| if (lazy.map.count() > lazy.pending_index) return true;
    if (elf.input_sections.items.len > elf.input_section_pending_index) return true;
    if (elf.changed_symtab_index.count() > 0) return true;
    if (elf.mf.updates.items.len > 0) return true;
    return false;
}

fn idleProgNode(
    elf: *Elf,
    tid: Zcu.PerThread.Id,
    prog_node: std.Progress.Node,
    node: Node,
) std.Progress.Node {
    var name: [std.Progress.Node.max_name_len]u8 = undefined;
    return prog_node.start(name: switch (node) {
        else => |tag| @tagName(tag),
        .section => |shndx| shndx.name(elf).slice(elf),
        .input_section => |isi| {
            const ii = isi.input(elf);
            break :name std.fmt.bufPrint(&name, "{f}{f} {s}", .{
                ii.path(elf).fmtEscapeString(),
                fmtMemberString(ii.member(elf)),
                elf.getNode(isi.node(elf).parent(&elf.mf)).section.name(elf).slice(elf),
            }) catch &name;
        },
        .nav => |nmi| {
            const ip = &elf.base.comp.zcu.?.intern_pool;
            break :name ip.getNav(nmi.navIndex(elf)).fqn.toSlice(ip);
        },
        .uav => |umi| std.fmt.bufPrint(&name, "{f}", .{
            Value.fromInterned(umi.uavValue(elf)).fmtValue(.{ .zcu = elf.base.comp.zcu.?, .tid = tid }),
        }) catch &name,
    }, 0);
}

fn flushUav(
    elf: *Elf,
    pt: Zcu.PerThread,
    umi: Node.UavMapIndex,
) Error!void {
    const comp = elf.base.comp;
    const gpa = comp.gpa;

    const uav_val = umi.uavValue(elf);
    const ni = umi.symbol(elf).index().ptr(elf).node;
    elf.resetNodeRelocs(ni);

    var nw: MappedFile.Node.Writer = undefined;
    ni.writer(&elf.mf, gpa, &nw);
    defer nw.deinit();
    codegen.generateSymbol(
        &elf.base,
        pt,
        .fromInterned(uav_val),
        &nw.interface,
        .{ .atom_index = Node.toAtom(ni) },
    ) catch |err| switch (err) {
        error.WriteFailed => return nw.err.?,
        else => |e| return e,
    };
    switch (elf.symPtr(umi.symbol(elf).index())) {
        inline else => |sym| elf.targetStore(&sym.size, @intCast(nw.interface.end)),
    }
    // The UAV should already be considered to have moved, because it is created as moved and
    // pending calls to `flushUav` always happen before pending calls to `flushMoved`.
    assert(ni.hasMoved(&elf.mf));
}

fn flushLazy(elf: *Elf, pt: Zcu.PerThread, lmr: Node.LazyMapRef) Error!void {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;

    const lazy = lmr.lazySymbol(elf);
    const ni = lmr.symbol(elf).index().ptr(elf).node;
    elf.resetNodeRelocs(ni);

    // Ensure the lazy node is marked as moved so that once we're done, `flushMoved` will eventually
    // be called to apply the lazy node's new relocations.
    try ni.moved(gpa, &elf.mf);

    var required_alignment: InternPool.Alignment = .none;
    var nw: MappedFile.Node.Writer = undefined;
    ni.writer(&elf.mf, gpa, &nw);
    defer nw.deinit();
    codegen.generateLazySymbol(
        &elf.base,
        pt,
        lazy,
        &required_alignment,
        &nw.interface,
        .none,
        .{ .atom_index = Node.toAtom(ni) },
    ) catch |err| switch (err) {
        error.WriteFailed => return nw.err.?,
        else => |e| return e,
    };
    switch (elf.symPtr(lmr.symbol(elf).index())) {
        inline else => |sym| elf.targetStore(&sym.size, @intCast(nw.interface.end)),
    }
}

fn flushInputSection(elf: *Elf, isi: InputSection.Index) Error!void {
    const file_loc = isi.fileLocation(elf);
    if (file_loc.size == 0) return;
    const comp = elf.base.comp;
    const io = comp.io;
    const gpa = comp.gpa;
    const diags = &comp.link_diags;
    const ii = isi.input(elf);
    const path = ii.path(elf);
    const file = path.root_dir.handle.openFile(io, path.sub_path, .{}) catch |err| switch (err) {
        error.Canceled => |e| return e,
        else => |e| return diags.fail("failed to open input file \"{f}\": {t}", .{ path.fmtEscapeString(), e }),
    };
    defer file.close(io);
    var fr = file.reader(io, &.{});
    fr.seekTo(file_loc.offset) catch |err| switch (err) {
        error.Canceled => |e| return e,
        else => |e| return diags.fail("failed to read input section '{s}' from \"{f}{f}\": {t}", .{
            elf.getNode(isi.node(elf).parent(&elf.mf)).section.name(elf).slice(elf),
            path.fmtEscapeString(),
            fmtMemberString(ii.member(elf)),
            e,
        }),
    };
    var nw: MappedFile.Node.Writer = undefined;
    isi.node(elf).writer(&elf.mf, gpa, &nw);
    defer nw.deinit();
    const n_bytes = nw.interface.sendFileAll(&fr, .limited(@intCast(file_loc.size))) catch |err| switch (err) {
        error.ReadFailed => return diags.fail("failed to read input section '{s}' from \"{f}{f}\": {t}", .{
            elf.getNode(isi.node(elf).parent(&elf.mf)).section.name(elf).slice(elf),
            path.fmtEscapeString(),
            fmtMemberString(ii.member(elf)),
            fr.err orelse (fr.seek_err orelse fr.size_err.?),
        }),
        error.WriteFailed => return nw.err.?,
    };
    if (n_bytes != file_loc.size) return diags.fail("failed to read input section '{s}' from \"{f}{f}\": unexpected eof", .{
        elf.getNode(isi.node(elf).parent(&elf.mf)).section.name(elf).slice(elf),
        path.fmtEscapeString(),
        fmtMemberString(ii.member(elf)),
    });
    // The input section should already be considered to have moved, because it is created as moved
    // and pending calls to `flushInputSection` always happen before pending calls to `flushMoved`.
    assert(isi.node(elf).hasMoved(&elf.mf));
}

fn flushFileOffset(elf: *Elf, ni: MappedFile.Node.Index) void {
    switch (elf.getNode(ni)) {
        else => unreachable,
        .ehdr => assert(ni.fileLocation(&elf.mf, false).offset == 0),
        .shdr => switch (elf.ehdrPtr()) {
            inline else => |ehdr| elf.targetStore(
                &ehdr.shoff,
                @intCast(ni.fileLocation(&elf.mf, false).offset),
            ),
        },
        .segment => |phndx| {
            switch (elf.phdrSlice()) {
                inline else => |phdr, class| {
                    const ph = &phdr[phndx];
                    elf.targetStore(&ph.offset, @intCast(ni.fileLocation(&elf.mf, false).offset));
                    if (elf.targetLoad(&ph.type) == .PHDR) {
                        @field(elf.ehdrPtr(), @tagName(class)).phoff = ph.offset;
                    }
                },
            }
            var child_it = ni.children(&elf.mf);
            while (child_it.next()) |child_ni| elf.flushFileOffset(child_ni);
        },
        .section => |shndx| switch (elf.shdrPtr(shndx)) {
            inline else => |shdr| elf.targetStore(&shdr.offset, @intCast(
                ni.fileLocation(&elf.mf, false).offset,
            )),
        },
    }
}

fn flushMoved(elf: *Elf, ni: MappedFile.Node.Index) std.mem.Allocator.Error!void {
    const trace = tracy.trace(@src());
    defer trace.end();
    switch (elf.getNode(ni)) {
        .file => unreachable,
        .ehdr, .shdr => elf.flushFileOffset(ni),
        .segment => |phndx| {
            elf.flushFileOffset(ni);
            switch (elf.phdrSlice()) {
                inline else => |phdr| {
                    const ph = &phdr[phndx];
                    switch (elf.targetLoad(&ph.type)) {
                        else => unreachable,
                        .NULL, .LOAD => return,

                        .DYNAMIC,
                        .INTERP,
                        .PHDR,
                        .TLS,
                        .GNU_RELRO,
                        => {},
                    }
                    elf.targetStore(&ph.vaddr, @intCast(elf.computeNodeVAddr(ni)));
                    ph.paddr = ph.vaddr;
                },
            }
        },
        .section => |shndx| {
            elf.flushFileOffset(ni);
            const addr = elf.computeNodeVAddr(ni);
            const old_addr: u64, const flags: std.elf.SHF = switch (elf.shdrPtr(shndx)) {
                inline else => |shdr| .{
                    elf.targetLoad(&shdr.addr),
                    elf.targetLoad(&shdr.flags).shf,
                },
            };

            if (flags.ALLOC) {
                switch (elf.shdrPtr(shndx)) {
                    inline else => |shdr| elf.targetStore(&shdr.addr, @intCast(addr)),
                }

                // Update global symbols targeting this section
                if (elf.node_global_symbols.get(ni)) |first_name| {
                    assert(first_name != .empty);
                    var name = first_name;
                    while (name != .empty) {
                        const old_sym_addr = Symbol.Id.global(name).value(elf);
                        Symbol.Id.global(name).flushMoved(
                            elf,
                            old_sym_addr - old_addr + addr,
                        );
                        name = elf.globalByName(name).?.next_in_node;
                    }
                }

                Symbol.Id.local(shndx.get(elf).lsi).flushMoved(elf, addr);
            }

            if (shndx == elf.shndx.got) {
                const rela_dyn_shndx = elf.shndx.rela_dyn;
                for (elf.got.values()) |opt_rela_index| {
                    const rela_index = opt_rela_index.unwrap() orelse continue;
                    rela_dyn_shndx.relaAdjustOffset(elf, rela_index, old_addr, addr);
                }
                for (elf.got_relocs.items) |*reloc| {
                    reloc.apply(elf);
                }
            } else if (shndx == elf.shndx.plt) {
                elf.flushMovedNodeRelocs(ni, addr, elf.plt_first_symbol_reloc, .none);
                elf.flushMovedPltSection(.plt, old_addr, addr);
            } else if (shndx == elf.shndx.got_plt) {
                elf.flushMovedPltSection(.got_plt, old_addr, addr);
            } else if (shndx == elf.shndx.plt_sec) {
                elf.flushMovedPltSection(.plt_sec, old_addr, addr);
            } else if (shndx == elf.shndx.dynamic) {
                elf.flushMovedNodeRelocs(ni, addr, elf.dynamic_first_symbol_reloc, .none);
            }
        },
        .input_section => |isi| {
            const old_section_addr = isi.ptr(elf).vaddr;
            const new_section_addr = elf.computeNodeVAddr(ni);
            isi.ptr(elf).vaddr = new_section_addr;

            // Update local symbols
            const ii = isi.input(elf);
            var lsi, const end_lsi = ii.localSymbolRange(elf);
            while (lsi != end_lsi) : (lsi = @enumFromInt(@intFromEnum(lsi) + 1)) {
                if (lsi.index().ptr(elf).node != ni) continue;
                const visibility: std.elf.STV = switch (elf.symPtr(lsi.index())) {
                    inline else => |sym| elf.targetLoad(&sym.other).visibility,
                };
                switch (visibility) {
                    .HIDDEN, .INTERNAL => {
                        // This is actually a global symbol which got demoted to STB_LOCAL due
                        // to its visibility. It will be handled in the global symbols pass
                        // below; don't touch it now.
                        continue;
                    },
                    .PROTECTED => unreachable, // not allowed for an STB_LOCAL symbol
                    .DEFAULT => {},
                }
                const old_sym_addr = Symbol.Id.local(lsi).value(elf);
                Symbol.Id.local(lsi).flushMoved(
                    elf,
                    old_sym_addr - old_section_addr + new_section_addr,
                );
            }

            // Update global symbols
            if (elf.node_global_symbols.get(ni)) |first_name| {
                assert(first_name != .empty);
                var name = first_name;
                while (name != .empty) {
                    const old_sym_addr = Symbol.Id.global(name).value(elf);
                    Symbol.Id.global(name).flushMoved(
                        elf,
                        old_sym_addr - old_section_addr + new_section_addr,
                    );
                    name = elf.globalByName(name).?.next_in_node;
                }
            }

            elf.flushMovedNodeRelocs(
                ni,
                new_section_addr,
                isi.ptrConst(elf).first_symbol_reloc,
                isi.ptrConst(elf).first_got_reloc,
            );
        },
        .copied_global => |global_name| {
            const copied_global = elf.copied_globals.getPtr(global_name) orelse {
                // TODO: this node is orphaned, which is possible because `MappedFile` does not yet
                // support deleting nodes. See logic in `setGlobalSymbolValue`.
                return;
            };
            assert(copied_global.node == ni);

            const new_addr = elf.computeNodeVAddr(ni);
            elf.shndx.rela_dyn.relaSetOffset(elf, copied_global.rela_index, new_addr);

            Symbol.Id.global(global_name).flushMoved(elf, new_addr);
        },
        inline .nav, .uav, .lazy_code, .lazy_const_data => |mi| {
            const new_addr = elf.computeNodeVAddr(ni);
            Symbol.Id.local(mi.symbol(elf)).flushMoved(elf, new_addr);
            if (elf.node_global_symbols.get(ni)) |first_name| {
                assert(first_name != .empty);
                var name = first_name;
                while (name != .empty) {
                    Symbol.Id.global(name).flushMoved(elf, new_addr);
                    name = elf.globalByName(name).?.next_in_node;
                }
            }
            elf.flushMovedNodeRelocs(
                ni,
                new_addr,
                mi.firstSymbolReloc(elf),
                mi.firstGotReloc(elf),
            );
        },
    }
    try ni.childrenMoved(elf.base.comp.gpa, &elf.mf);
}

fn flushResized(elf: *Elf, ni: MappedFile.Node.Index) std.mem.Allocator.Error!void {
    const trace = tracy.trace(@src());
    defer trace.end();
    _, const size = ni.location(&elf.mf).resolve(&elf.mf);
    switch (elf.getNode(ni)) {
        .file => {},
        .ehdr => unreachable,
        .shdr => {},
        .segment => |phndx| switch (elf.phdrSlice()) {
            inline else => |phdr| {
                assert(elf.phdrs.items[phndx] == ni);
                const ph = &phdr[phndx];
                elf.targetStore(&ph.filesz, @intCast(size));
                if (size > elf.targetLoad(&ph.memsz)) {
                    switch (elf.targetLoad(&ph.type)) {
                        else => unreachable,
                        .NULL => if (size > 0) elf.targetStore(&ph.type, .LOAD),
                        .LOAD => if (size == 0) elf.targetStore(&ph.type, .NULL),
                        .DYNAMIC, .INTERP, .PHDR, std.elf.PT.GNU_RELRO => {
                            elf.targetStore(&ph.memsz, @intCast(size));
                            return;
                        },
                        .TLS => {
                            elf.targetStore(&ph.memsz, @intCast(size));
                            // TPOFF relocations care about the size of the TLS segment. Re-apply
                            // those, and also update any GOT entries from GOTTPOFF relocations.
                            for (elf.tls_size_symbol_relocs.keys()) |reloc| {
                                reloc.get(elf).apply(elf);
                            }
                            for (elf.got.keys(), 0..) |got_key, got_index| {
                                switch (got_key) {
                                    .reserved,
                                    .symbol,
                                    .tlsld0,
                                    .tlsld1,
                                    .tlsgd0,
                                    .tlsgd1,
                                    => {
                                        @branchHint(.likely);
                                        continue;
                                    },

                                    .tpoff => elf.updateGotEntry(got_index),
                                }
                            }
                            return ni.childrenMoved(elf.base.comp.gpa, &elf.mf);
                        },
                    }
                    const memsz = ni.alignment(&elf.mf).forward(@intCast(size * 4));
                    elf.targetStore(&ph.memsz, @intCast(memsz));
                    var vaddr = elf.targetLoad(&ph.vaddr);
                    var new_phndx = phndx;
                    for (phdr[phndx + 1 ..], phndx + 1..) |*next_ph, next_phndx| {
                        switch (elf.targetLoad(&next_ph.type)) {
                            else => unreachable,
                            .NULL, .LOAD => {},
                            .DYNAMIC, .INTERP, .PHDR, .TLS, .GNU_RELRO, .GNU_STACK => break,
                        }
                        const next_vaddr = elf.targetLoad(&next_ph.vaddr);
                        if (vaddr + memsz <= next_vaddr) break;
                        vaddr = next_vaddr + elf.targetLoad(&next_ph.memsz);
                        std.mem.swap(@TypeOf(ph.*), &phdr[new_phndx], next_ph);
                        const next_ni = elf.phdrs.items[next_phndx];
                        elf.phdrs.items[new_phndx] = next_ni;
                        elf.nodes.items(.data)[@intFromEnum(next_ni)] = .{ .segment = new_phndx };
                        new_phndx = @intCast(next_phndx);
                    }
                    if (new_phndx != phndx) {
                        const new_ph = &phdr[new_phndx];
                        elf.targetStore(&new_ph.vaddr, vaddr);
                        new_ph.paddr = new_ph.vaddr;
                        elf.phdrs.items[new_phndx] = ni;
                        elf.nodes.items(.data)[@intFromEnum(ni)] = .{ .segment = new_phndx };
                        try ni.childrenMoved(elf.base.comp.gpa, &elf.mf);
                    }
                }
            },
        },
        .section => |shndx| switch (elf.shdrPtr(shndx)) {
            inline else => |shdr| {
                switch (elf.targetLoad(&shdr.type)) {
                    else => unreachable,

                    .NULL => if (size > 0) elf.targetStore(&shdr.type, .PROGBITS),
                    .PROGBITS => if (size == 0) elf.targetStore(&shdr.type, .NULL),

                    .INIT_ARRAY,
                    .FINI_ARRAY,
                    .PREINIT_ARRAY,
                    .STRTAB,
                    .SYMTAB,
                    .DYNAMIC,
                    .REL,
                    .RELA,
                    .DYNSYM,
                    => return,
                }
                if (shndx != elf.shndx.plt and
                    shndx != elf.shndx.got and
                    shndx != elf.shndx.got_plt)
                {
                    elf.targetStore(&shdr.size, @intCast(size));
                }
            },
        },
        .copied_global, .input_section, .nav, .uav, .lazy_code, .lazy_const_data => {},
    }
}
fn updateDynamicEntry(elf: *Elf, key: u32, new_val: u64) void {
    switch (elf.shdrPtr(elf.shndx.dynamic)) {
        inline else => |shdr, class| {
            const dynamic_size = elf.targetLoad(&shdr.size);
            const dynamic_entries: [][2]class.ElfN().Addr = @ptrCast(@alignCast(
                elf.shndx.dynamic.get(elf).ni.slice(&elf.mf)[0..@intCast(dynamic_size)],
            ));
            for (dynamic_entries) |*dynamic_entry| {
                if (elf.targetLoad(&dynamic_entry[0]) == key) {
                    elf.targetStore(&dynamic_entry[1], @intCast(new_val));
                }
            }
        },
    }
}
fn flushMovedPltSection(elf: *Elf, which: enum { plt, plt_sec, got_plt }, old_addr: u64, addr: u64) void {
    const target_endian = elf.targetEndian();
    switch (elf.ehdrField(.machine)) {
        else => |machine| @panic(@tagName(machine)),
        .X86_64 => {
            switch (which) {
                .plt => return,
                .plt_sec => {
                    // Re-apply all PLT relocations. If a symbol is in the PLT then the majority of
                    // its relocations are probably going through the PLT, so we don't bother with
                    // specific tracking for PLT relocations---instead just re-apply all relocations
                    // targeting symbols with PLT entries.
                    for (elf.plt.keys()) |name| {
                        Symbol.Id.global(name).applyTargetRelocs(elf);
                    }
                    // We also need to update all of the references from `.plt.sec` to `.got.plt`.
                    // However, if there's also a flush pending for `.got.plt`, don't bother doing
                    // this now, because we'll do it when `.got.plt` is flushed anyway.
                    if (elf.shndx.got_plt.get(elf).ni.hasMoved(&elf.mf)) {
                        return;
                    }
                    // Exit this `switch` to update those references.
                },
                .got_plt => {
                    // Update the offsets of the relocation entries in `.rela.plt`.
                    const rela_plt_shndx = elf.shndx.rela_plt;
                    for (0..elf.plt.count()) |plt_index| {
                        if (elf.pltEntryIsDead(plt_index)) continue;
                        rela_plt_shndx.relaAdjustOffset(elf, @enumFromInt(plt_index), old_addr, addr);
                    }
                    // We also need to update all of the references from `.plt.sec` to `.got.plt`.
                    // However, if there's also a flush pending for `.plt.sec`, don't bother doing
                    // this now, because we'll do it when `.plt.sec` is flushed anyway.
                    if (elf.shndx.plt_sec.get(elf).ni.hasMoved(&elf.mf)) {
                        return;
                    }
                    // Exit this `switch` to update those references.
                },
            }
            // We are updating the references from `.plt.sec` to `.got.plt`.
            const got_plt_addr = elf.shndx.got_plt.vaddr(elf);
            const plt_sec_addr = elf.shndx.plt_sec.vaddr(elf);
            const plt_sec_slice = elf.shndx.plt_sec.get(elf).ni.slice(&elf.mf);
            switch (elf.identClass()) {
                .NONE, _ => unreachable,
                inline else => |class| {
                    const Addr = class.ElfN().Addr;
                    for (0..elf.plt.count()) |plt_index| {
                        const plt_sec_offset = 16 * plt_index;
                        const got_plt_offset = @sizeOf(Addr) * (3 + plt_index);
                        std.mem.writeInt(
                            i32,
                            plt_sec_slice[plt_sec_offset + 6 ..][0..4],
                            @intCast(@as(i64, @bitCast(
                                (got_plt_addr + got_plt_offset) -% (plt_sec_addr + plt_sec_offset + 10),
                            ))),
                            target_endian,
                        );
                    }
                },
            }
        },
        .LOONGARCH => {
            switch (which) {
                .plt => {
                    // We also need to update all of the references from `.plt` to `.got.plt`.
                    // However, if there's also a flush pending for `.got.plt`, don't bother doing
                    // this now, because we'll do it when `.got.plt` is flushed anyway.
                    if (elf.shndx.got_plt.get(elf).ni.hasMoved(&elf.mf)) {
                        return;
                    }
                    // Exit this `switch` to update those references.
                },
                .plt_sec => unreachable,
                .got_plt => {
                    // Update the offsets of the relocation entries in `.rela.plt`.
                    const rela_plt_shndx = elf.shndx.rela_plt;
                    for (0..elf.plt.count()) |plt_index| {
                        if (elf.pltEntryIsDead(plt_index)) continue;
                        rela_plt_shndx.relaAdjustOffset(elf, @enumFromInt(plt_index), old_addr, addr);
                    }
                    // We also need to update all of the references from `.plt` to `.got.plt`.
                    // However, if there's also a flush pending for `.plt`, don't bother doing
                    // this now, because we'll do it when `.plt` is flushed anyway.
                    if (elf.shndx.plt.get(elf).ni.hasMoved(&elf.mf)) {
                        return;
                    }
                    // Exit this `switch` to update those references.
                },
            }
            // We are updating the references from `.plt` to `.got.plt`.
            const got_plt_addr = elf.shndx.got_plt.vaddr(elf);
            const plt_addr = elf.shndx.plt.vaddr(elf);
            const plt_slice = elf.shndx.plt.get(elf).ni.slice(&elf.mf);
            switch (elf.identClass()) {
                .NONE, _ => unreachable,
                inline else => |class| {
                    const Addr = class.ElfN().Addr;
                    for (0..elf.plt.count()) |plt_index| {
                        const plt_offset = 16 * plt_index;
                        const got_plt_offset = @sizeOf(Addr) * (2 + plt_index);
                        const target_slice = plt_slice[plt_offset..];

                        const got_plt_abs: u64 = got_plt_addr + got_plt_offset;
                        // TODO: handle overflow gracefully
                        link.loongarch.writeJ20(target_slice[0..4], link.loongarch.toPcalaHi20(got_plt_abs, plt_addr + plt_offset));
                        link.loongarch.writeK12(target_slice[4..8], @truncate(got_plt_abs));
                    }
                },
            }
        },
        .SPARCV9 => switch (which) {
            .plt => {
                // Update the offsets of the relocation entries in `.rela.plt`.
                const rela_plt_shndx = elf.shndx.rela_plt;
                for (0..elf.plt.count()) |plt_index| {
                    if (elf.pltEntryIsDead(plt_index)) continue;
                    rela_plt_shndx.relaAdjustOffset(elf, @enumFromInt(plt_index), old_addr, addr);
                }
            },
            .plt_sec, .got_plt => unreachable,
        },
    }
}

pub fn updateExports(
    elf: *Elf,
    pt: Zcu.PerThread,
    exported: Zcu.Exported,
    export_indices: []const Zcu.Export.Index,
) link.Error!void {
    const diags = &elf.base.comp.link_diags;
    return elf.updateExportsInner(pt, exported, export_indices) catch |err| switch (err) {
        else => |e| return e,
        error.MappedFileIo => return diags.fail("failed to write output file: {t}", .{elf.mf.io_err.?}),
    };
}
fn updateExportsInner(
    elf: *Elf,
    pt: Zcu.PerThread,
    exported: Zcu.Exported,
    export_indices: []const Zcu.Export.Index,
) Error!void {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;

    switch (exported) {
        .nav => |nav| log.debug("updateExports({f})", .{ip.getNav(nav).fqn.fmt(ip)}),
        .uav => |uav| log.debug("updateExports(@as({f}, {f}))", .{
            Type.fromInterned(ip.typeOf(uav)).fmt(pt),
            Value.fromInterned(uav).fmtValue(pt),
        }),
    }
    try elf.ensureUnusedSymbolCapacity(@intCast(export_indices.len), .maybe_global);
    const exported_lsi: Symbol.LocalIndex, const @"type": std.elf.STT = switch (exported) {
        .nav => |nav| .{
            (try elf.navMapIndex(zcu, nav)).symbol(elf),
            elf.navType(ip.getNav(nav).resolved.?),
        },
        .uav => |uav| .{ (try elf.uavMapIndex(uav, .none)).symbol(elf), .OBJECT },
    };
    while (try elf.idle(pt.tid)) {}
    const value: u64 = Symbol.Id.local(exported_lsi).value(elf);
    const size: u64, const shndx: Section.Index = switch (elf.symPtr(exported_lsi.index())) {
        inline else => |exported_sym| .{
            elf.targetLoad(&exported_sym.size),
            .fromSection(elf.targetLoad(&exported_sym.shndx)),
        },
    };
    for (export_indices) |export_index| {
        const @"export" = export_index.ptr(zcu);
        const name = @"export".opts.name.toSlice(ip);
        _ = elf.addGlobalSymbolAssumeCapacity(.{
            .node = .none,
            .name = try .string(elf, name),
            .value = value,
            .size = @intCast(size),
            .type = @"type",
            .bind = switch (@"export".opts.linkage) {
                .internal => @panic("TODO internal linkage"),
                .strong => .strong,
                .weak => .weak,
                .link_once => return elf.base.comp.link_diags.fail("TODO(Elf2): link_once is not supported", .{}),
            },
            .visibility = switch (@"export".opts.visibility) {
                .default => .DEFAULT,
                .hidden => .HIDDEN,
                .protected => .PROTECTED,
            },
            .shndx = shndx,
        }) catch |err| switch (err) {
            error.MultipleDefinitions => {
                // HACK: because we currently don't/can't delete these exports, we would typically
                // get these errors on every non-initial incremental update. Hack around that by
                // only emitting this error if the symbol we're conflicting with comes from an input
                // section (as opposed to the ZCU).
                const conflicting_global = elf.globalByName(try elf.string(.strtab, name)).?;
                const conflicting_node = conflicting_global.symtab_index.ptr(elf).node;
                if (elf.getNode(conflicting_node) == .input_section) {
                    return elf.base.comp.link_diags.fail(
                        "multiple definitions of '{s}'",
                        .{name},
                    );
                }
            },
        };
    }
}

pub fn deleteExport(elf: *Elf, exported: Zcu.Exported, name: InternPool.NullTerminatedString) void {
    _ = elf;
    _ = exported;
    _ = name;
}

pub fn dump(elf: *Elf, w: *Io.Writer, tid: Zcu.PerThread.Id) !link.File.DumpResult {
    if (elf.options.enable_link_snapshots) {
        try elf.printNode(tid, w, .root, 0);
        return .enabled;
    }
    return .disabled;
}

pub fn printNode(
    elf: *Elf,
    tid: Zcu.PerThread.Id,
    w: *Io.Writer,
    ni: MappedFile.Node.Index,
    indent: usize,
) Io.Writer.Error!void {
    const node = elf.getNode(ni);
    try w.splatByteAll(' ', indent);
    try w.writeAll(@tagName(node));
    switch (node) {
        else => {},
        .segment => |phndx| switch (elf.phdrSlice()) {
            inline else => |phdr| {
                const ph = &phdr[phndx];
                try w.writeByte('(');
                const pt = elf.targetLoad(&ph.type);
                if (std.enums.tagName(std.elf.PT, pt)) |pt_name|
                    try w.writeAll(pt_name)
                else inline for (@typeInfo(std.elf.PT).@"enum".decl_names) |decl_name| {
                    const decl_val = @field(std.elf.PT, decl_name);
                    if (@TypeOf(decl_val) != std.elf.PT) continue;
                    if (pt == @field(std.elf.PT, decl_name)) break try w.writeAll(decl_name);
                } else try w.print("0x{x}", .{pt});
                try w.writeAll(", ");
                const pf = elf.targetLoad(&ph.flags);
                if (pf.R) try w.writeByte('R');
                if (pf.W) try w.writeByte('W');
                if (pf.X) try w.writeByte('X');
                try w.writeByte(')');
            },
        },
        .section => |shndx| try w.print("({s})", .{shndx.name(elf).slice(elf)}),
        .input_section => |isi| {
            const ii = isi.input(elf);
            try w.print("({f}{f}, {s})", .{
                ii.path(elf).fmtEscapeString(),
                fmtMemberString(ii.member(elf)),
                elf.getNode(isi.node(elf).parent(&elf.mf)).section.name(elf).slice(elf),
            });
        },
        .copied_global => |name| try w.print("(copy:{s})", .{name.slice(elf)}),
        .nav => |nmi| {
            const zcu = elf.base.comp.zcu.?;
            const ip = &zcu.intern_pool;
            const nav = ip.getNav(nmi.navIndex(elf));
            try w.print("({f}, {f})", .{
                Type.fromInterned(ip.typeOf(nav.resolved.?.value)).fmt(.{ .zcu = zcu, .tid = tid }),
                nav.fqn.fmt(ip),
            });
        },
        .uav => |umi| {
            const zcu = elf.base.comp.zcu.?;
            const val: Value = .fromInterned(umi.uavValue(elf));
            try w.print("({f}, {f})", .{
                val.typeOf(zcu).fmt(.{ .zcu = zcu, .tid = tid }),
                val.fmtValue(.{ .zcu = zcu, .tid = tid }),
            });
        },
        inline .lazy_code, .lazy_const_data => |lmi| try w.print("({f})", .{
            Type.fromInterned(lmi.lazySymbol(elf).ty).fmt(.{
                .zcu = elf.base.comp.zcu.?,
                .tid = tid,
            }),
        }),
    }
    {
        const mf_node = &elf.mf.nodes.items[@intFromEnum(ni)];
        const off, const size = mf_node.location().resolve(&elf.mf);
        try w.print(" index={d} offset=0x{x} size=0x{x} align=0x{x}{s}{s}{s}{s}\n", .{
            @intFromEnum(ni),
            off,
            size,
            mf_node.flags.alignment.toByteUnits(),
            if (mf_node.flags.fixed) " fixed" else "",
            if (mf_node.flags.moved) " moved" else "",
            if (mf_node.flags.resized) " resized" else "",
            if (mf_node.flags.has_content) " has_content" else "",
        });
    }
    var leaf = true;
    var child_it = ni.children(&elf.mf);
    while (child_it.next()) |child_ni| {
        leaf = false;
        try elf.printNode(tid, w, child_ni, indent + 1);
    }
    if (!leaf) return;
    const file_loc = ni.fileLocation(&elf.mf, false);
    var address = file_loc.offset;
    if (file_loc.size == 0) {
        try w.splatByteAll(' ', indent + 1);
        try w.print("{x:0>8}\n", .{address});
        return;
    }
    const line_len = 0x10;
    var line_it = std.mem.window(
        u8,
        elf.mf.memory_map.memory[@intCast(file_loc.offset)..][0..@intCast(file_loc.size)],
        line_len,
        line_len,
    );
    while (line_it.next()) |line_bytes| : (address += line_len) {
        try w.splatByteAll(' ', indent + 1);
        try w.print("{x:0>8}  ", .{address});
        for (line_bytes) |byte| try w.print("{x:0>2} ", .{byte});
        try w.splatByteAll(' ', 3 * (line_len - line_bytes.len) + 1);
        for (line_bytes) |byte| try w.writeByte(if (std.ascii.isPrint(byte)) byte else '.');
        try w.writeByte('\n');
    }
}

fn ensureNodeSize(
    elf: *Elf,
    node: MappedFile.Node.Index,
    need_size: u64,
) Error!void {
    _, const node_size = node.location(&elf.mf).resolve(&elf.mf);
    if (need_size <= node_size) return;
    const gpa = elf.base.comp.gpa;
    const new_size = need_size + need_size / MappedFile.growth_factor;
    try node.resize(&elf.mf, gpa, new_size);
}

const MachO = @This();

base: link.File,
options: link.File.OpenOptions,

const_prog_node: std.Progress.Node,
synth_prog_node: std.Progress.Node,
input_prog_node: std.Progress.Node,

mf: MappedFile,
nodes: std.MultiArrayList(Node),

node: struct {
    macho: MappedFile.Node.Index,
    header: MappedFile.Node.Index,
    symtab: MappedFile.Node.Index,
    strtab: MappedFile.Node.Index,
},

lc: struct {
    offsets: std.ArrayList(u32),
    pagezero: LoadCommand,
    symtab: LoadCommand,
    entry_point: ?LoadCommand,
},
/// Does not contain an entry for the `__PAGEZERO` segment.
segments: std.MultiArrayList(struct {
    lc: LoadCommand,
    node: MappedFile.Node.Index,
}),
sections: std.MultiArrayList(struct {
    lc: LoadCommand,
    node: MappedFile.Node.Index,
    first_symbol: Symbol.Index.Optional,
    index: u8,
}),
/// Accessed with `Segment.NameAdapter` using `[]const u8` keys.
segments_by_name: std.array_hash_map.Custom(void, void, void, true),
/// Accessed with `Section.NameAdapter` using `Section.NameAdapter.SegmentAndSection`.
sections_by_name: std.array_hash_map.Custom(void, void, void, true),

/// Accessed with `String.Adapter` using `[]const u8` keys.
strtab: std.array_hash_map.Custom(String, void, void, true),

symtab: std.ArrayList(Symbol),

sections_changed_index: std.array_hash_map.Auto(Section, void),

const Error = link.Error || error{MappedFileIo};

/// Stable reference to a particular load command (or `std.macho.section_64`, despite those not
/// technically being load commands). Underlying value is an index into `MachO.lc.offsets`.
const LoadCommand = enum(u32) {
    _,
    fn offset(lc: LoadCommand, macho: *const MachO) u32 {
        return macho.lc.offsets.items[@backingInt(lc)];
    }
    fn ptrConst(lc: LoadCommand, macho: *const MachO, comptime Cmd: type) *align(8) const Cmd {
        return @ptrCast(@alignCast(
            macho.node.header.sliceConst(&macho.mf)[lc.offset(macho)..][0..@sizeOf(Cmd)],
        ));
    }
    fn ptr(lc: LoadCommand, macho: *MachO, comptime Cmd: type) *align(8) Cmd {
        return @ptrCast(@alignCast(
            macho.node.header.slice(&macho.mf)[lc.offset(macho)..][0..@sizeOf(Cmd)],
        ));
    }
};

/// Stable reference to a segment defined by a `std.macho.segment_command_64` load command.
///
/// This type is backed by `u8` instead of a larger type because Mach-O itself uses 8-bit indices to
/// refer to sections, so the limitation exists regardless.
const Segment = enum(u8) {
    _,

    fn lc(seg: Segment, macho: *const MachO) LoadCommand {
        return macho.segments.items(.lc)[@backingInt(seg)];
    }
    fn lcPtrConst(seg: Segment, macho: *const MachO) *const std.macho.segment_command_64 {
        return seg.lc(macho).ptrConst(macho, std.macho.segment_command_64);
    }
    fn lcPtr(seg: Segment, macho: *MachO) *std.macho.segment_command_64 {
        return seg.lc(macho).ptr(macho, std.macho.segment_command_64);
    }

    fn name(seg: Segment, macho: *const MachO) []const u8 {
        return std.mem.sliceTo(&seg.lcPtrConst(macho).segname, 0);
    }

    fn vaddr(seg: Segment, macho: *const MachO) u64 {
        return macho.targetLoad(&seg.lcPtrConst(macho).vmaddr);
    }

    fn node(seg: Segment, macho: *const MachO) MappedFile.Node.Index {
        return macho.segments.items(.node)[@backingInt(seg)];
    }

    const NameAdapter = struct {
        macho: *const MachO,
        pub fn eql(ctx: NameAdapter, a_seg_name: []const u8, _: void, b_seg_raw: usize) bool {
            const b_seg: Segment = @fromBackingInt(@intCast(b_seg_raw));
            return std.mem.eql(u8, a_seg_name, b_seg.name(ctx.macho));
        }
        pub fn hash(ctx: NameAdapter, a_seg_name: []const u8) u32 {
            _ = ctx;
            return std.array_hash_map.hashString(a_seg_name);
        }
    };
};

/// Stable reference to a section defined by a `std.macho.section_64` in the load commands.
///
/// This type is backed by `u8` instead of a larger type because Mach-O itself uses 8-bit indices to
/// refer to sections, so the limitation exists regardless.
///
/// However, the backing integer of a `Section` is *not* the same as the section index, because
/// section indices can change. For the index of a section, see `Section.index`.
const Section = enum(u8) {
    _,

    fn lc(sect: Section, macho: *const MachO) LoadCommand {
        return macho.sections.items(.lc)[@backingInt(sect)];
    }
    fn lcPtrConst(sect: Section, macho: *const MachO) *const std.macho.section_64 {
        return sect.lc(macho).ptrConst(macho, std.macho.section_64);
    }
    fn lcPtr(sect: Section, macho: *MachO) *std.macho.section_64 {
        return sect.lc(macho).ptr(macho, std.macho.section_64);
    }

    fn name(sect: Section, macho: *const MachO) []const u8 {
        return std.mem.sliceTo(&sect.lcPtrConst(macho).sectname, 0);
    }

    fn segmentName(sect: Section, macho: *const MachO) []const u8 {
        return std.mem.sliceTo(&sect.lcPtrConst(macho).segname, 0);
    }

    fn node(sect: Section, macho: *const MachO) MappedFile.Node.Index {
        return macho.sections.items(.node)[@backingInt(sect)];
    }

    /// Returns this section's index in the Mach-O file. Section indices are implicitly assigned
    /// based on the order of load commands, so this value may change in response to segments or
    /// sections being added. When this value changes for a  given `Section`, it is added to
    /// `MachO.sections_changed_index`, so that references to the section index can be updated.
    fn index(sect: Section, macho: *const MachO) u8 {
        return macho.sections.items(.index)[@backingInt(sect)];
    }

    /// Returns the head of a linked list of symbols defined relative to this section.
    fn firstSymbol(sect: Section, macho: *MachO) *Symbol.Index.Optional {
        return &macho.sections.items(.first_symbol)[@backingInt(sect)];
    }

    const NameAdapter = struct {
        macho: *const MachO,
        const SegmentAndSection = struct {
            segment: []const u8,
            section: []const u8,
        };
        pub fn eql(ctx: NameAdapter, a_name: SegmentAndSection, _: void, b_sect_raw: usize) bool {
            const b_sect: Section = @fromBackingInt(@intCast(b_sect_raw));
            return std.mem.eql(u8, a_name.segment, b_sect.segmentName(ctx.macho)) and
                std.mem.eql(u8, a_name.section, b_sect.name(ctx.macho));
        }
        pub fn hash(ctx: NameAdapter, a_name: SegmentAndSection) u32 {
            _ = ctx;
            var h: std.hash.Wyhash = .init(a_name.section.len);
            h.update(a_name.section);
            h.update(a_name.segment);
            return @truncate(h.final());
        }
    };
};

const Symbol = struct {
    next_in_section: Symbol.Index.Optional,

    const Index = enum(u32) {
        _,
        fn ptr(i: Index, macho: *MachO) *Symbol {
            return &macho.symtab.items[@backingInt(i)];
        }
        fn nlist(i: Index, macho: *MachO) *std.macho.nlist_64 {
            return &macho.nlistSlice()[@backingInt(i)];
        }
        const Optional = enum(u32) {
            none = std.math.maxInt(u32),
            _,
            fn unwrap(o: Optional) ?Index {
                return switch (o) {
                    .none => null,
                    _ => @fromBackingInt(@backingInt(o)),
                };
            }
            fn wrap(i: Index) Optional {
                return @bitCast(i);
            }
        };
    };
};

const Node = union(enum) {
    macho,
    /// Contains the `mach_header_64` structure and all load commands. Inside of the `.segment` node for the `__TEXT` segment.
    macho_header,

    symtab,
    strtab,

    segment: Segment,
    section: Section,
};
fn getNode(macho: *const MachO, ni: MappedFile.Node.Index) Node {
    return macho.nodes.get(@backingInt(ni));
}

pub fn open(
    arena: Allocator,
    comp: *Compilation,
    path: std.Build.Cache.Path,
    options: link.File.OpenOptions,
) !*MachO {
    return create(arena, comp, path, options);
}
pub fn createEmpty(
    arena: Allocator,
    comp: *Compilation,
    path: std.Build.Cache.Path,
    options: link.File.OpenOptions,
) !*MachO {
    return create(arena, comp, path, options);
}
fn create(
    arena: Allocator,
    comp: *Compilation,
    path: std.Build.Cache.Path,
    options: link.File.OpenOptions,
) !*MachO {
    const io = comp.io;

    const macho = try arena.create(MachO);
    const file = try path.root_dir.handle.createFile(io, path.sub_path, .{
        .read = true,
        .permissions = link.File.determinePermissions(comp.config.output_mode, comp.config.link_mode),
    });

    macho.* = .{
        .base = .{
            .tag = .macho2,

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

        .const_prog_node = .none,
        .synth_prog_node = .none,
        .input_prog_node = .none,

        .mf = try .init(file, comp.gpa, io),
        .nodes = .empty,

        .node = undefined,
        .lc = .{
            .offsets = .empty,
            .pagezero = undefined,
            .symtab = undefined,
            .entry_point = null,
        },
        .segments = .empty,
        .sections = .empty,
        .segments_by_name = .empty,
        .sections_by_name = .empty,

        .strtab = .empty,
        .symtab = .empty,

        .sections_changed_index = .empty,
    };
    errdefer macho.deinit();

    try macho.initInner();

    return macho;
}
fn initInner(macho: *MachO) !void {
    const comp = macho.base.comp;
    const gpa = comp.gpa;

    macho.node.macho = .root;
    try macho.nodes.append(gpa, .macho);

    const arch: enum { aarch64, x86_64 } = switch (comp.getTarget().cpu.arch) {
        .aarch64 => .aarch64,
        .x86_64 => .x86_64,
        else => |arch| std.debug.panic("TODO: unsupported target arch {t}", .{arch}),
    };

    const mach_header_64 = std.macho.mach_header_64;

    // The `__TEXT` segment is special because it contains the mach header and load commands, so we
    // must create the text segment node before we can actually call `addSegment`.
    const text_seg_node = try macho.node.macho.addOnlyHeaderChild(gpa, &macho.mf, .{
        .alignment = macho.mf.flags.block_size.max(macho.targetPageAlign()),
        .moved = true, // required by `addSegment`
        .bubbles_moved = false,
    });
    try macho.nodes.append(gpa, .{ .segment = undefined }); // populated by `addSegment`

    macho.node.header = try text_seg_node.addOnlyHeaderChild(gpa, &macho.mf, .{
        .size = @sizeOf(mach_header_64),
        .alignment = .@"8",
    });
    try macho.nodes.append(gpa, .macho_header);

    const mach_header: *mach_header_64 = @ptrCast(@alignCast(
        macho.node.header.slice(&macho.mf)[0..@sizeOf(mach_header_64)],
    ));
    mach_header.* = .{
        .cputype = switch (arch) {
            .aarch64 => std.macho.CPU_TYPE_ARM64,
            .x86_64 => std.macho.CPU_TYPE_X86_64,
        },
        .cpusubtype = switch (arch) {
            .aarch64 => std.macho.CPU_SUBTYPE_ARM_ALL,
            .x86_64 => std.macho.CPU_SUBTYPE_X86_64_ALL,
        },
        .filetype = switch (comp.config.output_mode) {
            .Exe => std.macho.MH_EXECUTE,
            .Lib => switch (comp.config.link_mode) {
                .static => std.macho.MH_OBJECT,
                .dynamic => std.macho.MH_DYLIB,
            },
            .Obj => std.macho.MH_OBJECT,
        },
        .ncmds = 0,
        .sizeofcmds = 0,
        .flags = std.macho.MH_DYLDLINK | std.macho.MH_PIE,
    };
    if (macho.targetEndian() != std.lang.Endian.native) {
        std.mem.byteSwapAllFields(mach_header_64, mach_header);
    }

    // The "__LINKEDIT" segment is special in that it needs to be at the end of the Mach-O file, so
    // like "__TEXT", we'll construct its node here instead of in `addSegment`.
    const linkedit_seg_node = try macho.node.macho.addFooterChildBefore(gpa, &macho.mf, .none, .{
        .alignment = macho.mf.flags.block_size.max(macho.targetPageAlign()),
        .moved = true, // required by `addSegment`
        .bubbles_moved = false,
    });
    try macho.nodes.append(gpa, .{ .segment = undefined }); // populated by `addSegment`

    // The "__PAGEZERO" segment must come before any other segment load commands. It is inaccessible
    // and occupies 4 GiB (apparently to catch invalid 32-bit pointer accesses).
    macho.lc.pagezero = try macho.appendSimpleLoadCommand(std.macho.segment_command_64, .{
        .cmdsize = @sizeOf(std.macho.segment_command_64),
        .segname = "__PAGEZERO\x00\x00\x00\x00\x00\x00".*,
        .vmaddr = 0,
        .vmsize = 0x1_0000_0000,
        .fileoff = 0,
        .filesize = 0,
        .maxprot = .{},
        .initprot = .{},
        .nsects = 0,
        .flags = 0,
    });
    const text_seg = try macho.addSegment(.{
        .name = "__TEXT",
        .prot = .{ .READ = true, .EXEC = true },
        .existing_node = text_seg_node,
    });
    const data_seg = try macho.addSegment(.{
        .name = "__DATA",
        .prot = .{ .READ = true, .WRITE = true },
    });
    const linkedit_seg = try macho.addSegment(.{
        .name = "__LINKEDIT",
        .prot = .{ .READ = true },
        .existing_node = linkedit_seg_node,
    });

    _ = try macho.addSection(.{
        .segment = text_seg,
        .name = "__text",
        .@"align" = .@"4",
        .flags = .{ .some_instructions = true },
    });
    _ = try macho.addSection(.{
        .segment = text_seg,
        .name = "__const",
        .@"align" = .@"2",
        .flags = .{},
    });
    _ = try macho.addSection(.{
        .segment = data_seg,
        .name = "__data",
        .@"align" = .@"2",
        .flags = .{},
    });

    macho.node.symtab = try linkedit_seg.node(macho).addFloatingChild(gpa, &macho.mf, .{
        .alignment = macho.mf.flags.block_size.max(.of(std.macho.nlist_64)),
        .moved = true, // so that `symoff` in the symtab load command will be set
    });
    try macho.nodes.append(gpa, .symtab);

    macho.node.strtab = try linkedit_seg.node(macho).addFloatingChild(gpa, &macho.mf, .{
        .alignment = macho.mf.flags.block_size,
        .moved = true, // so that `stroff` in the symtab load command will be set
    });
    try macho.nodes.append(gpa, .strtab);

    try macho.node.strtab.ensureMinimumSize(gpa, &macho.mf, 1);
    macho.node.strtab.slice(&macho.mf)[0] = 0;

    _ = try macho.appendSimpleLoadCommand(std.macho.dyld_info_command, .{});

    macho.lc.symtab = try macho.appendSimpleLoadCommand(std.macho.symtab_command, .{
        .symoff = 0,
        .nsyms = 0,
        .stroff = 0,
        .strsize = 1, // empty string (null terminator)
    });

    const want_dyld_path: bool = switch (comp.config.output_mode) {
        .Obj => false,
        .Lib => switch (comp.config.link_mode) {
            .static => false,
            .dynamic => comp.root_mod.resolved_target.is_explicit_dynamic_linker,
        },
        .Exe => true,
    };
    if (want_dyld_path) {
        if (comp.getTarget().dynamic_linker.get()) |dyld_path| {
            const cmd = try macho.appendLoadCommand(std.macho.dylinker_command, .{
                .cmd = .LOAD_DYLINKER,
                .cmdsize = std.mem.alignForward(u32, @intCast(
                    @sizeOf(std.macho.dylinker_command) + dyld_path.len + 1,
                ), 8),
                .name = @sizeOf(std.macho.dylinker_command),
            });
            @memcpy(cmd.trailing[0..dyld_path.len], dyld_path);
            @memset(cmd.trailing[dyld_path.len..], 0);
        }
    }

    switch (comp.config.output_mode) {
        .Obj, .Lib => {},
        .Exe => macho.lc.entry_point = try macho.appendSimpleLoadCommand(std.macho.entry_point_command, .{
            .entryoff = 0,
            .stacksize = macho.options.stack_size orelse 0,
        }),
    }

    _ = try macho.appendSimpleLoadCommand(std.macho.uuid_command, .{
        .uuid = @splat(0),
    });

    try macho.addSimpleSymbol("some_function", 0x1234, "__TEXT", "__text");
    try macho.addSimpleSymbol("my_cool_data", 0x5678, "__DATA", "__data");

    try macho.updateSegmentLoadAddresses();
}
/// TODO: this function doesn't actually do anything particularly useful, it's just a placeholder
/// for actual symbol creation logic so that we can test adding stuff to the symtab.
fn addSimpleSymbol(
    macho: *MachO,
    name: []const u8,
    value: u64,
    segment_name: []const u8,
    section_name: []const u8,
) Error!void {
    const gpa = macho.base.comp.gpa;
    try macho.symtab.ensureUnusedCapacity(gpa, 1);
    try macho.node.symtab.ensureMinimumSize(gpa, &macho.mf, (macho.symtab.items.len + 1) * @sizeOf(std.macho.nlist_64));

    const strx = try macho.string(name);
    const section = macho.sectionByName(segment_name, section_name).?;

    const symtab_ptr = macho.lc.symtab.ptr(macho, std.macho.symtab_command);
    assert(macho.targetLoad(&symtab_ptr.nsyms) == macho.symtab.items.len);
    macho.targetStore(&symtab_ptr.nsyms, @intCast(macho.symtab.items.len + 1));

    const sym_index: Symbol.Index = @fromBackingInt(@intCast(macho.symtab.items.len));
    macho.symtab.appendAssumeCapacity(.{
        .next_in_section = section.firstSymbol(macho).*,
    });
    section.firstSymbol(macho).* = .wrap(sym_index);

    sym_index.nlist(macho).* = .{
        .n_strx = @backingInt(strx),
        .n_type = .{ .bits = .{
            .ext = true,
            .type = .sect,
            .pext = false,
            .is_stab = 0,
        } },
        .n_sect = section.index(macho),
        .n_desc = .{
            .arm_thumb_def = false,
            .referenced_dynamically = false,
            .discarded_or_no_dead_strip = false,
            .weak_ref = false,
            .weak_def_or_ref_to_weak = false,
            .symbol_resolver = false,
            .alt_entry = false,
        },
        .n_value = value,
    };
    if (macho.targetEndian() != std.lang.Endian.native) {
        std.mem.byteSwapAllFields(std.macho.nlist_64, sym_index.nlist(macho));
    }
}

fn addSegment(macho: *MachO, opts: struct {
    name: []const u8,
    prot: std.macho.vm_prot_t,
    /// The caller is allowed to create the section's node themselves, in which case it is passed in
    /// here. The caller must initialize the `MachO.nodes` entry to `.{ .segment = undefined }`, and
    /// the node must be created with the option `.moved = true`.
    existing_node: ?MappedFile.Node.Index = null,
}) Error!Segment {
    const gpa = macho.base.comp.gpa;

    const segment_command_64 = std.macho.segment_command_64;

    // We limit the number of segments to 255, because there can only be 255 *sections*, so there's
    // no need to allow more. See corresponding check in `addSection`.
    if (macho.segments.len == 255) {
        return macho.base.comp.link_diags.fail("maximum segment count exceeded", .{});
    }

    try macho.nodes.ensureUnusedCapacity(gpa, 1);
    try macho.segments.ensureUnusedCapacity(gpa, 1);
    try macho.segments_by_name.ensureUnusedCapacity(gpa, 1);

    const root_ni: MappedFile.Node.Index = .root;

    const lc = try macho.appendSimpleLoadCommand(std.macho.segment_command_64, .{
        .cmdsize = @sizeOf(segment_command_64),
        .segname = name: {
            var name: [16]u8 = undefined;
            @memcpy(name[0..opts.name.len], opts.name);
            @memset(name[opts.name.len..], 0);
            break :name name;
        },
        .vmaddr = 0,
        .vmsize = 0,
        .fileoff = 0, // to be set by `flushMoved`
        .filesize = 0,
        .maxprot = opts.prot,
        .initprot = opts.prot,
        .nsects = 0,
        .flags = 0,
    });

    const segment: Segment = @fromBackingInt(@intCast(macho.segments.len));
    const segment_node: MappedFile.Node.Index = node: {
        if (opts.existing_node) |node| {
            assert(node.hasMoved(&macho.mf)); // so that `fileoff` will be set
            assert(macho.nodes.items(.tags)[@backingInt(node)] == .segment);
            macho.nodes.set(@backingInt(node), .{ .segment = segment });
            break :node node;
        }
        const node = try root_ni.addFloatingChild(gpa, &macho.mf, .{
            .alignment = macho.mf.flags.block_size.max(macho.targetPageAlign()),
            .moved = true, // so that `fileoff` will be set
            .bubbles_moved = false,
        });
        macho.nodes.appendAssumeCapacity(.{ .segment = segment });
        break :node node;
    };
    macho.segments.appendAssumeCapacity(.{
        .lc = lc,
        .node = segment_node,
    });

    {
        const gop = macho.segments_by_name.getOrPutAssumeCapacityAdapted(
            opts.name,
            @as(Segment.NameAdapter, .{ .macho = macho }),
        );
        assert(!gop.found_existing);
        assert(gop.index == @backingInt(segment));
    }

    return segment;
}

const String = enum(u32) {
    empty = 0,
    _,
    fn slice(s: String, macho: *const MachO) [:0]const u8 {
        const overlong = macho.node.strtab.slice(&macho.mf)[@backingInt(s)..];
        return overlong[0..std.mem.findScalar(u8, overlong, 0).? :0];
    }

    const Adapter = struct {
        macho: *const MachO,
        pub fn eql(ctx: Adapter, lhs_slice: []const u8, rhs: String, _: usize) bool {
            const macho = ctx.macho;
            return std.mem.eql(u8, lhs_slice, rhs.slice(macho));
        }
        pub fn hash(ctx: Adapter, s: []const u8) u32 {
            _ = ctx;
            return std.array_hash_map.hashString(s);
        }
    };
};

fn string(macho: *MachO, slice: []const u8) Error!String {
    const gpa = macho.base.comp.gpa;

    const old_strsize = macho.targetLoad(
        &macho.lc.symtab.ptr(macho, std.macho.symtab_command).strsize,
    );
    try macho.node.strtab.ensureMinimumSize(gpa, &macho.mf, old_strsize + slice.len + 1);

    try macho.strtab.ensureUnusedCapacity(gpa, 1);

    errdefer comptime unreachable;

    const adapter: String.Adapter = .{ .macho = macho };
    const gop = macho.strtab.getOrPutAssumeCapacityAdapted(slice, adapter);
    if (!gop.found_existing) {
        macho.targetStore(
            &macho.lc.symtab.ptr(macho, std.macho.symtab_command).strsize,
            @intCast(old_strsize + slice.len + 1),
        );
        gop.key_ptr.* = @fromBackingInt(old_strsize);
        const dest_slice = macho.node.strtab.slice(&macho.mf)[old_strsize..];
        @memcpy(dest_slice[0..slice.len], slice);
        dest_slice[slice.len] = 0;
    }
    return gop.key_ptr.*;
}

fn nlistSlice(macho: *MachO) []std.macho.nlist_64 {
    const nsyms = macho.targetLoad(
        &macho.lc.symtab.ptr(macho, std.macho.symtab_command).nsyms,
    );
    return @ptrCast(@alignCast(
        macho.node.symtab.slice(&macho.mf)[0 .. nsyms * @sizeOf(std.macho.nlist_64)],
    ));
}

fn updateSegmentLoadAddresses(macho: *MachO) Allocator.Error!void {
    // TODO: this segment load address allocation logic is bad because it moves segments quite
    // frequently. We should avoid that by introducing padding between segments so that they have
    // space to grow in-place. We could also consider allowing a segment which can't fit to jump
    // over another segment, like in `Elf2.allocateSegmentLoadAddress`.
    var cur_addr: u64 = start_addr: {
        const pagezero_ptr = macho.lc.pagezero.ptr(macho, std.macho.segment_command_64);
        assert(macho.targetLoad(&pagezero_ptr.vmaddr) == 0);
        break :start_addr macho.targetLoad(&pagezero_ptr.vmsize);
    };
    for (0..macho.segments.len) |segment_raw| {
        const segment: Segment = @fromBackingInt(@intCast(segment_raw));

        _, const size: u64 = segment.node(macho).location(&macho.mf).resolve(&macho.mf);
        const cmd_ptr = segment.lcPtr(macho);

        macho.targetStore(&cmd_ptr.vmsize, size);

        const old_addr = macho.targetLoad(&cmd_ptr.vmaddr);
        if (old_addr >= cur_addr) {
            cur_addr = old_addr;
        } else {
            macho.targetStore(&cmd_ptr.vmaddr, cur_addr);
            try segment.node(macho).childrenMoved(macho.base.comp.gpa, &macho.mf);
        }

        cur_addr = macho.targetPageAlign().forward(cur_addr + size);
    }
}

/// Like `appendLoadCommand`, but asserts that `cmd.cmdsize` exactly equals `@sizeOf(Cmd)` and does
/// not return the (empty) trailing slice.
fn appendSimpleLoadCommand(
    macho: *MachO,
    comptime Cmd: type,
    cmd: Cmd,
) Error!LoadCommand {
    comptime assert(@sizeOf(Cmd) % 8 == 0);
    assert(cmd.cmdsize == @sizeOf(Cmd));
    return (try macho.appendLoadCommand(Cmd, cmd)).lc;
}

/// Asserts that the first two fields of `Cmd` are `cmd: LC` and `cmdsize: u32`, and that the value
/// of `lc.cmdsize` is 8-byte aligned.
fn appendLoadCommand(
    macho: *MachO,
    comptime Cmd: type,
    cmd: Cmd,
) Error!struct {
    lc: LoadCommand,
    trailing: []u8,
} {
    const gpa = macho.base.comp.gpa;

    try macho.lc.offsets.ensureUnusedCapacity(gpa, 1);

    comptime {
        const s = @typeInfo(Cmd).@"struct";
        assert(s.layout == .@"extern");
        // First field of load command should be `cmd: LC`
        assert(std.mem.eql(u8, s.field_names[0], "cmd"));
        assert(s.field_types[0] == std.macho.LC);
        // Second field of load command should be `cmdsize: u32`
        assert(std.mem.eql(u8, s.field_names[1], "cmdsize"));
        assert(s.field_types[1] == u32);
    }

    const cmd_size = @as(*const std.macho.load_command, @ptrCast(&cmd)).cmdsize;
    assert(cmd_size % 8 == 0);

    const mach_header_64 = std.macho.mach_header_64;
    const old_cmds_size: u32 = size: {
        const mach_header: *const mach_header_64 = @ptrCast(@alignCast(
            macho.node.header.sliceConst(&macho.mf)[0..@sizeOf(mach_header_64)],
        ));
        break :size macho.targetLoad(&mach_header.sizeofcmds);
    };
    const new_cmds_size = old_cmds_size + cmd_size;
    try macho.node.header.ensureMinimumSize(gpa, &macho.mf, @sizeOf(mach_header_64) + new_cmds_size);

    const header_slice = macho.node.header.slice(&macho.mf);
    const mach_header: *mach_header_64 = @ptrCast(@alignCast(
        header_slice[0..@sizeOf(mach_header_64)],
    ));
    macho.targetStore(&mach_header.sizeofcmds, new_cmds_size);
    macho.targetStore(&mach_header.ncmds, macho.targetLoad(&mach_header.ncmds) + 1);

    const cmd_slice: []align(8) u8 = @alignCast(
        header_slice[@sizeOf(mach_header_64) + old_cmds_size ..][0..cmd_size],
    );

    const cmd_ptr: *Cmd = @ptrCast(cmd_slice[0..@sizeOf(Cmd)]);
    cmd_ptr.* = cmd;
    if (macho.targetEndian() != std.lang.Endian.native) {
        std.mem.byteSwapAllFields(Cmd, cmd_ptr);
    }

    const lc: LoadCommand = @fromBackingInt(@intCast(macho.lc.offsets.items.len));
    macho.lc.offsets.appendAssumeCapacity(@sizeOf(mach_header_64) + old_cmds_size);

    return .{ .lc = lc, .trailing = cmd_slice[@sizeOf(Cmd)..] };
}

fn addSection(macho: *MachO, opts: struct {
    name: []const u8,
    segment: Segment,
    @"align": MappedFile.Alignment,
    /// This matches the layout of `std.macho.section_64.flags`.
    flags: packed struct(u32) {
        _unused0: u10 = 0,
        some_instructions: bool = false,
        _unused1: u21 = 0,
    },
}) Error!Section {
    const gpa = macho.base.comp.gpa;

    const mach_header_64 = std.macho.mach_header_64;
    const segment_command_64 = std.macho.segment_command_64;
    const section_64 = std.macho.section_64;

    // Check if we can actually fit another section. The limit is 255 because Mach-O implicitly
    // assigns 8-bit indices to sections starting from 1 (0 is reserved).
    if (macho.sections.len == 255) {
        return macho.base.comp.link_diags.fail("maximum section count exceeded", .{});
    }

    const old_cmds_size: u32 = size: {
        const mach_header: *const mach_header_64 = @ptrCast(@alignCast(
            macho.node.header.sliceConst(&macho.mf)[0..@sizeOf(mach_header_64)],
        ));
        break :size macho.targetLoad(&mach_header.sizeofcmds);
    };
    const new_cmds_size = old_cmds_size + @sizeOf(section_64);
    try macho.node.header.ensureMinimumSize(gpa, &macho.mf, @sizeOf(mach_header_64) + new_cmds_size);

    try macho.nodes.ensureUnusedCapacity(gpa, 1);
    try macho.lc.offsets.ensureUnusedCapacity(gpa, 1);
    try macho.sections.ensureUnusedCapacity(gpa, 1);
    try macho.sections_by_name.ensureUnusedCapacity(gpa, 1);

    const section: Section = @fromBackingInt(@intCast(macho.sections.len));
    const section_node = try opts.segment.node(macho).addFloatingChild(gpa, &macho.mf, .{
        .alignment = opts.@"align",
        .moved = true, // so that `offset` will be set
    });
    macho.nodes.appendAssumeCapacity(.{ .section = section });
    macho.sections.appendAssumeCapacity(.{
        .lc = @fromBackingInt(@intCast(macho.lc.offsets.items.len)),
        .node = section_node,
        .first_symbol = .none,
        .index = undefined, // populated later
    });

    {
        const adapter: Section.NameAdapter = .{ .macho = macho };
        const key: Section.NameAdapter.SegmentAndSection = .{
            .segment = opts.segment.name(macho),
            .section = opts.name,
        };
        const gop = macho.sections_by_name.getOrPutAssumeCapacityAdapted(key, adapter);
        assert(!gop.found_existing);
        assert(gop.index == @backingInt(section));
    }

    const header_slice = macho.node.header.slice(&macho.mf);

    {
        const mach_header: *mach_header_64 = @ptrCast(@alignCast(
            header_slice[0..@sizeOf(mach_header_64)],
        ));
        macho.targetStore(&mach_header.sizeofcmds, new_cmds_size);
    }

    const seg_cmd = opts.segment.lcPtr(macho);
    const old_nsects = macho.targetLoad(&seg_cmd.nsects);
    const old_cmdsize = macho.targetLoad(&seg_cmd.cmdsize);
    assert(old_cmdsize == @sizeOf(segment_command_64) + old_nsects * @sizeOf(section_64));
    const new_cmdsize = old_cmdsize + @sizeOf(section_64);
    macho.targetStore(&seg_cmd.cmdsize, new_cmdsize);
    macho.targetStore(&seg_cmd.nsects, old_nsects + 1);

    const seg_cmd_off = opts.segment.lc(macho).offset(macho);
    const offset = seg_cmd_off + old_cmdsize;

    // Shift forward every load command which comes after this segment command, to make space
    // for the new `section_64` (and update the offsets in `macho.lc.offsets` accordingly).
    @memmove(
        header_slice[seg_cmd_off + new_cmdsize .. @sizeOf(mach_header_64) + new_cmds_size],
        header_slice[seg_cmd_off + old_cmdsize .. @sizeOf(mach_header_64) + old_cmds_size],
    );
    for (macho.lc.offsets.items) |*other_off| {
        if (other_off.* >= offset) {
            other_off.* += @sizeOf(section_64);
        }
    }
    // Only now do we append our *own* offset (otherwise the above loop would have changed it!).
    macho.lc.offsets.appendAssumeCapacity(offset);

    // Increment the index of every section after where we've inserted ourselves.
    {
        var new_section_index: u8 = 1;
        try macho.sections_changed_index.ensureUnusedCapacity(gpa, macho.sections.len);
        for (0..macho.sections.len) |other_section_raw| {
            const other_section: Section = @fromBackingInt(@intCast(other_section_raw));
            if (other_section == section) continue;
            if (other_section.lc(macho).offset(macho) > offset) {
                macho.sections.items(.index)[@backingInt(other_section)] += 1;
                if (other_section.firstSymbol(macho).* != .none) {
                    macho.sections_changed_index.putAssumeCapacity(other_section, {});
                }
            } else {
                new_section_index += 1;
            }
        }
        macho.sections.items(.index)[@backingInt(section)] = new_section_index;
    }

    // Write the new `section_64`.
    const section_cmd: *section_64 = @ptrCast(@alignCast(
        header_slice[offset..][0..@sizeOf(section_64)],
    ));
    section_cmd.* = .{
        .sectname = name: {
            var name: [16]u8 = undefined;
            @memcpy(name[0..opts.name.len], opts.name);
            @memset(name[opts.name.len..], 0);
            break :name name;
        },
        .segname = seg_cmd.segname,
        .addr = 0,
        .size = 0,
        .offset = 0,
        .@"align" = opts.@"align".toLog2Units(),
        .reloff = 0,
        .nreloc = 0,
        .flags = @bitCast(opts.flags),
    };
    if (macho.targetEndian() != std.lang.Endian.native) {
        std.mem.byteSwapAllFields(section_64, section_cmd);
    }

    return section;
}

fn segmentByName(macho: *const MachO, name: []const u8) ?Segment {
    const adapter: Segment.NameAdapter = .{ .macho = macho };
    if (macho.segments_by_name.getIndexAdapted(name, adapter)) |segment_raw| {
        return @fromBackingInt(@intCast(segment_raw));
    } else {
        return null;
    }
}

fn sectionByName(macho: *const MachO, segment_name: []const u8, section_name: []const u8) ?Section {
    const adapter: Section.NameAdapter = .{ .macho = macho };
    const key: Section.NameAdapter.SegmentAndSection = .{
        .segment = segment_name,
        .section = section_name,
    };
    if (macho.sections_by_name.getIndexAdapted(key, adapter)) |section_raw| {
        return @fromBackingInt(@intCast(section_raw));
    } else {
        return null;
    }
}

fn targetEndian(macho: *const MachO) std.lang.Endian {
    _ = macho;
    return .little;
}
fn targetPageAlign(macho: *const MachO) MappedFile.Alignment {
    _ = macho;
    return .fromByteUnits(0x4000);
}
fn targetLoad(macho: *const MachO, ptr: anytype) @typeInfo(@TypeOf(ptr)).pointer.child {
    const pointer_ty = @typeInfo(@TypeOf(ptr)).pointer;
    const Child = pointer_ty.child;
    const alignment = pointer_ty.attrs.@"align" orelse @alignOf(Child);
    return switch (@typeInfo(Child)) {
        else => @compileError(@typeName(Child)),
        .int => std.mem.toNative(Child, ptr.*, macho.targetEndian()),
        .@"enum" => |@"enum"| @fromBackingInt(macho.targetLoad(@as(*align(alignment) const @"enum".tag_type, @ptrCast(ptr)))),
        .@"struct" => |@"struct"| @bitCast(
            macho.targetLoad(@as(*align(alignment) @"struct".backing_integer.?, @ptrCast(ptr))),
        ),
    };
}
fn targetStore(macho: *const MachO, ptr: anytype, val: @typeInfo(@TypeOf(ptr)).pointer.child) void {
    const pointer_ty = @typeInfo(@TypeOf(ptr)).pointer;
    const Child = pointer_ty.child;
    const alignment = pointer_ty.attrs.@"align" orelse @alignOf(Child);
    return switch (@typeInfo(Child)) {
        else => @compileError(@typeName(Child)),
        .int => ptr.* = std.mem.nativeTo(Child, val, macho.targetEndian()),
        .@"enum" => |@"enum"| macho.targetStore(
            @as(*align(alignment) @"enum".tag_type, @ptrCast(ptr)),
            @backingInt(val),
        ),
        .@"struct" => |@"struct"| macho.targetStore(
            @as(*align(alignment) @"struct".backing_integer.?, @ptrCast(ptr)),
            @bitCast(val),
        ),
    };
}

pub fn deinit(macho: *MachO) void {
    const gpa = macho.base.comp.gpa;
    macho.mf.deinit(gpa);
    macho.nodes.deinit(gpa);
    macho.segments.deinit(gpa);
    macho.sections.deinit(gpa);
    macho.segments_by_name.deinit(gpa);
    macho.sections_by_name.deinit(gpa);
    macho.strtab.deinit(gpa);
    macho.symtab.deinit(gpa);
    macho.sections_changed_index.deinit(gpa);
    macho.* = undefined;
}

pub fn startProgress(macho: *MachO, prog_node: std.Progress.Node) void {
    prog_node.increaseEstimatedTotalItems(4);
    macho.const_prog_node = prog_node.start("Constants", 0);
    macho.synth_prog_node = prog_node.start("Synthetics", 0);
    macho.input_prog_node = prog_node.start("Inputs", 0);
    macho.mf.update_prog_node = prog_node.start("Relocations", macho.mf.updates.items.len);
}
pub fn endProgress(macho: *MachO) void {
    macho.const_prog_node.end();
    macho.const_prog_node = .none;
    macho.synth_prog_node.end();
    macho.synth_prog_node = .none;
    macho.input_prog_node.end();
    macho.input_prog_node = .none;
    macho.mf.update_prog_node.end();
    macho.mf.update_prog_node = .none;
}

pub fn navSymbol(macho: *MachO, nav_id: InternPool.Nav.Index) link.Error!link.File.SymbolId {
    _ = macho;
    _ = nav_id;
    @panic("TODO");
}
pub fn uavSymbol(
    macho: *MachO,
    pt: Zcu.PerThread,
    uav_val: InternPool.Index,
    uav_align: InternPool.Alignment,
) link.Error!link.File.SymbolId {
    _ = macho;
    _ = pt;
    _ = uav_val;
    _ = uav_align;
    @panic("TODO");
}
pub fn relocSymAddr(
    macho: *MachO,
    reloc_info: link.File.RelocInfo,
) link.Error!void {
    _ = macho;
    _ = reloc_info;
    @panic("TODO");
}

pub fn loadInput(macho: *MachO, input: link.Input) link.Error!void {
    const diags = &macho.base.comp.link_diags;
    macho.loadInputInner(input) catch |err| switch (err) {
        error.MappedFileIo => return diags.fail("failed to write output file: {t}", .{macho.mf.io_err.?}),
        else => |e| return e,
    };
}
fn loadInputInner(macho: *MachO, input: link.Input) Error!void {
    switch (input) {
        .res => unreachable,
        .object => @panic("TODO(MachO2): load object"),
        .archive => @panic("TODO(MachO2): load archive"),
        .dso => @panic("TODO(MachO2): load dso"),
        .tbd => |tbd| {
            log.debug("load tbd {qf}", .{tbd.path.fmtEscapeString()});

            // TODO: obviously this is completely wrong, we need to parse the tbd to determine the
            // dylib install name; but for now this lets us link libSystem
            const prefix = "/usr/lib/";
            const name = std.fs.path.stem(tbd.path.sub_path);
            const suffix = ".dylib";

            const cmd = try macho.appendLoadCommand(std.macho.dylib_command, .{
                .cmd = .LOAD_DYLIB,
                .cmdsize = std.mem.alignForward(u32, @intCast(
                    @sizeOf(std.macho.dylib_command) + prefix.len + name.len + suffix.len + 1,
                ), 8),
                .dylib = .{
                    .name = @sizeOf(std.macho.dylib_command),
                    .timestamp = 0,
                    .current_version = 0,
                    .compatibility_version = 0,
                },
            });
            @memcpy(cmd.trailing[0..prefix.len], prefix);
            @memcpy(cmd.trailing[prefix.len..][0..name.len], name);
            @memcpy(cmd.trailing[prefix.len + name.len ..][0..suffix.len], suffix);
            @memset(cmd.trailing[prefix.len + name.len + suffix.len ..], 0);
        },
    }
}
pub fn setDarwinSdkVersion(macho: *MachO, sdk_version: link.DarwinSdkVersion) link.Error!void {
    const comp = macho.base.comp;
    const diags = &comp.link_diags;
    const target = comp.getTarget();

    const os_min_version: link.DarwinSdkVersion = .{
        .major = @intCast(target.os.version_range.semver.min.major),
        .minor = @intCast(target.os.version_range.semver.min.minor),
        .patch = @intCast(target.os.version_range.semver.min.patch),
    };

    _ = macho.appendSimpleLoadCommand(std.macho.version_min_command, .{
        .cmd = switch (target.os.tag) {
            .macos => .VERSION_MIN_MACOSX,
            .ios => .VERSION_MIN_IPHONEOS,
            .tvos => .VERSION_MIN_TVOS,
            .watchos => .VERSION_MIN_WATCHOS,
            .maccatalyst, .driverkit, .visionos => |os_tag| std.debug.panic(
                "TODO(MachO2): sdk version for '{t}'",
                .{os_tag},
            ),
            else => unreachable,
        },
        .version = @backingInt(os_min_version),
        .sdk = @backingInt(sdk_version),
    }) catch |err| switch (err) {
        error.MappedFileIo => return diags.fail("failed to write output file: {t}", .{macho.mf.io_err.?}),
        else => |e| return e,
    };
}
pub fn prelink(macho: *MachO, prog_node: std.Progress.Node) link.Error!void {
    _ = macho;
    _ = prog_node;
}
pub fn flush(
    macho: *MachO,
    arena: Allocator,
    tid: Zcu.PerThread.Id,
    prog_node: std.Progress.Node,
) link.Error!void {
    const diags = &macho.base.comp.link_diags;
    _ = arena;
    _ = prog_node;

    try macho.updateSegmentLoadAddresses();
    while (try macho.idle(tid)) {}

    if (macho.lc.entry_point) |entry_point_lc| {
        // TODO: actually find the entry point.
        // For now, we just set the entry point to the start of the "__TEXT,__text" section.
        const entry_node = macho.sectionByName("__TEXT", "__text").?.node(macho);
        const entry_file_off: u64, _ = entry_node.location(&macho.mf).resolve(&macho.mf);
        const entry_point_ptr = entry_point_lc.ptr(macho, std.macho.entry_point_command);
        macho.targetStore(&entry_point_ptr.entryoff, @intCast(entry_file_off));
    }

    macho.mf.flush() catch |err| switch (err) {
        error.MappedFileIo => return diags.fail("failed to write output file: {t}", .{macho.mf.io_err.?}),
        else => |e| return e,
    };

    if (macho.options.enable_link_snapshots)
        macho.dumpStderr(tid) catch |err|
            return diags.fail("dumping link snapshot failed: {t}", .{err});
}
pub fn updateErrorData(macho: *MachO, pt: Zcu.PerThread) link.Error!void {
    _ = macho;
    _ = pt;
    @panic("TODO");
}
pub fn idle(macho: *MachO, tid: Zcu.PerThread.Id) link.Error!bool {
    _ = tid;

    macho.mf.nodes_lock.lock();
    defer macho.mf.nodes_lock.unlock();

    task: {
        if (macho.sections_changed_index.pop()) |kv| {
            const section = kv.key;
            var sym_it = section.firstSymbol(macho).*;
            while (sym_it.unwrap()) |sym| : (sym_it = sym.ptr(macho).next_in_section) {
                macho.targetStore(&sym.nlist(macho).n_sect, section.index(macho));
            }
            break :task;
        }

        while (macho.mf.updates.pop()) |ni| {
            const clean_moved = ni.cleanMoved(&macho.mf);
            const clean_resized = ni.cleanResized(&macho.mf);
            const clean_next_moved = ni.cleanNextMoved(&macho.mf);
            if (!clean_moved and !clean_resized and !clean_next_moved) continue;

            const sub_prog_node = macho.mf.update_prog_node.start(@tagName(macho.getNode(ni)), 0);
            defer sub_prog_node.end();

            if (clean_moved) try macho.flushMoved(ni);
            if (clean_resized) try macho.flushResized(ni);

            break :task;
        }
    }

    return macho.sections_changed_index.count() > 0 or
        macho.mf.updates.items.len > 0;
}
fn flushMoved(macho: *MachO, ni: MappedFile.Node.Index) link.Error!void {
    macho.flushMachOFileOffset(ni);
    switch (macho.getNode(ni)) {
        .macho => unreachable,
        .macho_header => {},
        .segment => return, // segments don't bubble moved
        .section => |section| {
            const segment_vaddr: u64 = macho.getNode(ni.parent(&macho.mf).unwrap().?).segment.vaddr(macho);
            const section_offset = ni.location(&macho.mf).resolve(&macho.mf)[0];
            macho.targetStore(&section.lcPtr(macho).addr, segment_vaddr + section_offset);
        },
        .symtab => {},
        .strtab => {},
    }
    try ni.childrenMoved(macho.base.comp.gpa, &macho.mf);
}
fn flushMachOFileOffset(macho: *MachO, ni: MappedFile.Node.Index) void {
    const offset = ni.fileLocation(&macho.mf, false).offset;
    switch (macho.getNode(ni)) {
        .macho => unreachable,
        .macho_header => {
            assert(offset == 0);
        },
        .segment => |segment| {
            macho.targetStore(&segment.lcPtr(macho).fileoff, @intCast(offset));
            var child_oni = ni.first(&macho.mf);
            while (child_oni.unwrap()) |child_ni| : (child_oni = child_ni.next(&macho.mf)) {
                macho.flushMachOFileOffset(child_ni);
            }
        },
        .section => |section| {
            macho.targetStore(&section.lcPtr(macho).offset, @intCast(offset));
        },
        .symtab => {
            const symtab_cmd = macho.lc.symtab.ptr(macho, std.macho.symtab_command);
            macho.targetStore(&symtab_cmd.symoff, @intCast(offset));
        },
        .strtab => {
            const symtab_cmd = macho.lc.symtab.ptr(macho, std.macho.symtab_command);
            macho.targetStore(&symtab_cmd.stroff, @intCast(offset));
        },
    }
}
fn flushResized(macho: *MachO, ni: MappedFile.Node.Index) link.Error!void {
    const size = ni.location(&macho.mf).resolve(&macho.mf)[1];
    switch (macho.getNode(ni)) {
        .macho => {},
        .macho_header => {},
        .segment => |segment| {
            macho.targetStore(&segment.lcPtr(macho).filesize, size);
        },
        .section => |section| {
            macho.targetStore(&section.lcPtr(macho).size, size);
        },
        .symtab, .strtab => {
            // Don't modify the symtab load command's `nsyms` or `strsize` field here; we only do
            // that when we actually add strings or symbols.
        },
    }
}

pub fn updateFunc(
    macho: *MachO,
    pt: Zcu.PerThread,
    func_index: InternPool.Index,
    mir: *const codegen.AnyMir,
) link.Error!void {
    _ = macho;
    _ = pt;
    _ = func_index;
    _ = mir;
    @panic("TODO");
}
pub fn updateNav(macho: *MachO, pt: Zcu.PerThread, nav_index: InternPool.Nav.Index) link.Error!void {
    _ = macho;
    _ = pt;
    _ = nav_index;
    @panic("TODO");
}
pub fn updateExports(
    macho: *MachO,
    pt: Zcu.PerThread,
    export_indices: []const Zcu.Export.Index,
) link.Error!void {
    _ = macho;
    _ = pt;
    _ = export_indices;
    @panic("TODO");
}

fn dumpStderr(macho: *MachO, tid: Zcu.PerThread.Id) Io.File.Writer.Error!void {
    const comp = macho.base.comp;
    const io = comp.io;
    var buffer: [512]u8 = undefined;
    const stderr = try io.lockStderr(&buffer, null);
    defer io.unlockStderr();
    const w = &stderr.file_writer.interface;
    _ = macho.dump(w, tid) catch |err| switch (err) {
        error.WriteFailed => return stderr.file_writer.err.?,
    };
}

pub fn dump(macho: *MachO, w: *Io.Writer, tid: Zcu.PerThread.Id) !link.File.DumpResult {
    if (macho.options.enable_link_snapshots) {
        try macho.printNode(tid, w, .root, 0);
        return .enabled;
    }
    return .disabled;
}
fn printNode(
    macho: *const MachO,
    tid: Zcu.PerThread.Id,
    w: *Io.Writer,
    ni: MappedFile.Node.Index,
    indent: usize,
) Io.Writer.Error!void {
    const node = macho.getNode(ni);
    try w.splatByteAll(' ', indent);
    switch (node) {
        .macho => try w.writeAll("macho"),
        .macho_header => try w.writeAll("macho_header"),
        .section => |section| try w.print("section({q})", .{section.name(macho)}),
        .segment => |segment| try w.print("segment({q})", .{segment.name(macho)}),
        .symtab => try w.writeAll("symtab"),
        .strtab => try w.writeAll("strtab"),
    }
    {
        const mf_node = &macho.mf.nodes.items[@backingInt(ni)];
        const off, const size = mf_node.location().resolve(&macho.mf);
        try w.print(" index={d} offset=0x{x} size=0x{x} align=0x{x} {t}{s}{s}{s}{s}{s}{s}\n", .{
            @backingInt(ni),
            off,
            size,
            mf_node.flags.alignment.toByteUnits(),
            mf_node.flags.position,
            if (mf_node.flags.bubbles_moved) " bubbles_moved" else "",
            if (mf_node.flags.moved) " moved" else "",
            if (mf_node.flags.resized) " resized" else "",
            if (mf_node.flags.enable_next_moved) " enable_next_moved" else "",
            if (mf_node.flags.next_moved) " next_moved" else "",
            if (mf_node.flags.has_content) " has_content" else "",
        });
    }
    if (ni.first(&macho.mf).unwrap()) |first_ni| {
        // non-leaf, just print children
        var child_ni = first_ni;
        while (true) {
            try macho.printNode(tid, w, child_ni, indent + 1);
            child_ni = child_ni.next(&macho.mf).unwrap() orelse break;
        }
        return;
    }
    const start_address: usize, const end_address: usize = file_loc: {
        const file_loc = ni.fileLocation(&macho.mf, false);
        break :file_loc .{ @intCast(file_loc.offset), @intCast(file_loc.offset + file_loc.size) };
    };
    var address = start_address;
    const line_len = 0x10;
    while (true) : (address = @min(std.mem.alignForward(usize, address + 1, line_len), end_address)) {
        try w.splatByteAll(' ', indent + 1);
        try w.print("{x:0>8}", .{address});
        if (address == end_address) break try w.writeByte('\n');
        try w.splatByteAll(' ', 2);
        const start_byte_address = std.mem.alignBackward(usize, address, line_len);
        const end_byte_address = start_byte_address + line_len;
        for (start_byte_address..end_byte_address) |byte_address|
            if (byte_address < start_address or byte_address >= end_address)
                try w.splatByteAll(' ', 3)
            else
                try w.print("{x:0>2} ", .{macho.mf.memory_map.memory[byte_address]});
        try w.writeByte(' ');
        for (start_byte_address..@min(end_address, end_byte_address)) |byte_address|
            try w.writeByte(if (byte_address < start_address or byte_address >= end_address) ' ' else char: {
                const byte = macho.mf.memory_map.memory[byte_address];
                break :char if (std.ascii.isPrint(byte)) byte else '.';
            });
        try w.writeByte('\n');
    }
}

const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.link);
const Allocator = std.mem.Allocator;
const Io = std.Io;

const link = @import("../link.zig");
const codegen = @import("../codegen.zig");
const Compilation = @import("../Compilation.zig");
const InternPool = @import("../InternPool.zig");
const MappedFile = @import("MappedFile.zig");
const Zcu = @import("../Zcu.zig");

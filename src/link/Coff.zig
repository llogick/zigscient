const Coff = @This();

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
const Type = @import("../Type.zig");
const Value = @import("../Value.zig");
const Zcu = @import("../Zcu.zig");
const ModuleDefinition = @import("../libs/mingw/def.zig").ModuleDefinition;
const implib = @import("../libs/mingw/implib.zig");
const Path = std.Build.Cache.Path;

base: link.File,
options: link.File.OpenOptions,
mf: MappedFile,
nodes: std.MultiArrayList(Node),
members: std.ArrayList(Member),
pending_members: std.array_hash_map.Auto(Member.Index, void),
lib_string_table: std.ArrayList(String),
lib_string_len: u32,
long_names_table: LongNamesTable,
import_table: ImportTable,
export_table: ExportTable,
symbol_table: SymbolTable,
inputs: std.array_hash_map.Custom(std.Build.Cache.Path, void, std.Build.Cache.Path.TableAdapter, false),
input_archives: std.ArrayList(InputArchive),
input_archive_members: std.ArrayList(InputArchive.Member),
input_archive_symbols: std.ArrayList(InputArchive.Member.Symbol),
input_archive_symbol_indices: std.array_hash_map.Auto(String, InputArchive.SearchList),
pending_input: ?InputArchive.Member.Index,
pending_default_libs: std.ArrayList(struct {
    path: []const u8,
    ioi: InputObject.Index,
}),
alternate_names: std.array_hash_map.Auto(String, String),
input_objects: std.ArrayList(InputObject),
input_symbols: std.ArrayList(struct { si: Symbol.Index, name: String }),
input_sections: std.ArrayList(Node.InputSection),
input_section_pending_index: u32,
inputs_complete: bool,
exports_complete: bool,
pending_special_symbol: SpecialSymbol,
strings: std.HashMapUnmanaged(
    u32,
    void,
    std.hash_map.StringIndexContext,
    std.hash_map.default_max_load_percentage,
),
string_bytes: std.ArrayList(u8),
section_table: std.array_hash_map.Auto(String, Section),
pseudo_section_table: std.array_hash_map.Auto(String, Symbol.Index),
object_section_table: std.array_hash_map.Auto(String, Symbol.Index),
section_merges: std.array_hash_map.Auto(String, String),
section_merge_pending_index: u32,
symbols: std.ArrayList(Symbol),
globals: std.array_hash_map.Auto(String, Global),
global_pending_index: u32,
navs: std.array_hash_map.Auto(InternPool.Nav.Index, Symbol.Index),
uavs: std.array_hash_map.Auto(InternPool.Index, Symbol.Index),
lazy: std.EnumArray(link.File.LazySymbol.Kind, struct {
    map: std.array_hash_map.Auto(InternPool.Index, Symbol.Index),
    pending_index: u32,
}),
pending_uavs: std.array_hash_map.Auto(Node.UavMapIndex, struct {
    alignment: InternPool.Alignment,
}),
relocs: std.ArrayList(Reloc),
first_free_reloc: Reloc.Index,
last_free_reloc: Reloc.Index,
const_prog_node: std.Progress.Node,
synth_prog_node: std.Progress.Node,
symbol_prog_node: std.Progress.Node,
member_prog_node: std.Progress.Node,
input_prog_node: std.Progress.Node,

pub const default_file_alignment: u16 = 0x200;
pub const default_size_of_stack_reserve: u32 = 0x1000000;
pub const default_size_of_stack_commit: u32 = 0x1000;
pub const default_size_of_heap_reserve: u32 = 0x100000;
pub const default_size_of_heap_commit: u32 = 0x1000;

pub const imp_prefix = "__imp_";

const header_name_max_len = @typeInfo(@FieldType(std.coff.SectionHeader, "name")).array.len;

const Error = link.Error || error{MappedFileIo};
const LoadInputError = Error ||
    Io.File.SeekError ||
    Io.File.Reader.SizeError ||
    Io.Reader.Error ||
    MappedFile.Error;

/// This is the start of a Portable Executable (PE) file.
/// It starts with a MS-DOS header followed by a MS-DOS stub program.
/// This data does not change so we include it as follows in all binaries.
///
/// In this context,
/// A "paragraph" is 16 bytes.
/// A "page" is 512 bytes.
/// A "long" is 4 bytes.
/// A "word" is 2 bytes.
pub const msdos_stub: [120]u8 = .{
    'M', 'Z', // Magic number. Stands for Mark Zbikowski (designer of the MS-DOS executable format).
    0x78, 0x00, // Number of bytes in the last page. This matches the size of this entire MS-DOS stub.
    0x01, 0x00, // Number of pages.
    0x00, 0x00, // Number of entries in the relocation table.
    0x04, 0x00, // The number of paragraphs taken up by the header. 4 * 16 = 64, which matches the header size (all bytes before the MS-DOS stub program).
    0x00, 0x00, // The number of paragraphs required by the program.
    0x00, 0x00, // The number of paragraphs requested by the program.
    0x00, 0x00, // Initial value for SS (relocatable segment address).
    0x00, 0x00, // Initial value for SP.
    0x00, 0x00, // Checksum.
    0x00, 0x00, // Initial value for IP.
    0x00, 0x00, // Initial value for CS (relocatable segment address).
    0x40, 0x00, // Absolute offset to relocation table. 64 matches the header size (all bytes before the MS-DOS stub program).
    0x00, 0x00, // Overlay number. Zero means this is the main executable.
}
    // Reserved words.
    ++ .{
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x00,
    }
    // OEM-related fields.
    ++ .{
        0x00, 0x00, // OEM identifier.
        0x00, 0x00, // OEM information.
    }
    // Reserved words.
    ++ .{
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x00,
    }
    // Address of the PE header (a long). This matches the size of this entire MS-DOS stub, so that's the address of what's after this MS-DOS stub.
    ++ .{ 0x78, 0x00, 0x00, 0x00 }
    // What follows is a 16-bit x86 MS-DOS program of 7 instructions that prints the bytes after these instructions and then exits.
    ++ .{
        // Set the value of the data segment to the same value as the code segment.
        0x0e, // push cs
        0x1f, // pop ds
        // Set the DX register to the address of the message.
        // If you count all bytes of these 7 instructions you get 14, so that's the address of what's after these instructions.
        0xba, 14, 0x00, // mov dx, 14
        // Set AH to the system call code for printing a message.
        0xb4, 0x09, // mov ah, 0x09
        // Perform the system call to print the message.
        0xcd, 0x21, // int 0x21
        // Set AH to 0x4c which is the system call code for exiting, and set AL to 0x01 which is the exit code.
        0xb8, 0x01, 0x4c, // mov ax, 0x4c01
        // Peform the system call to exit the program with exit code 1.
        0xcd, 0x21, // int 0x21
    }
    // Message to print.
    ++ "This program cannot be run in DOS mode.".*
    // Message terminators.
    ++ .{
        '$', // We do not pass a length to the print system call; the string is terminated by this character.
        0x00, 0x00, // Terminating zero bytes.
    };

pub const Node = union(enum) {
    file,
    header,
    /// Images and archives only.
    signature,
    /// Archives only.
    archive_member_header: Member.Index,
    archive_member: Member.Index,

    coff_header,

    /// Image only
    optional_header,
    data_directories,

    section_table,

    /// Archives and objects only
    symbol_table,
    string_table,
    relocation_table: Symbol.SectionNumber,
    relocation_table_entry: Reloc.Index,

    image_section: Symbol.Index,

    /// Images only
    import_directory_table,
    import_lookup_table: ImportTable.Index,
    import_address_table: ImportTable.Index,
    import_hint_name_table: ImportTable.Index,

    /// Images only
    export_directory_table,
    export_address_table,
    export_name_pointer_table,
    export_ordinal_table,
    export_name_table,

    pseudo_section: PseudoSectionMapIndex,
    object_section: ObjectSectionMapIndex,
    input_section: InputSection.Index,
    import_thunk: GlobalMapIndex,
    nav: NavMapIndex,
    uav: UavMapIndex,
    lazy_code: LazyMapRef.Index(.code),
    lazy_const_data: LazyMapRef.Index(.const_data),
    builtin: Symbol.Index,

    /// Takes the place of a known node index when that node is not present in the output
    placeholder,

    pub const PseudoSectionMapIndex = enum(u32) {
        _,

        pub fn name(psmi: PseudoSectionMapIndex, coff: *const Coff) String {
            return coff.pseudo_section_table.keys()[@intFromEnum(psmi)];
        }

        pub fn symbol(psmi: PseudoSectionMapIndex, coff: *const Coff) Symbol.Index {
            return coff.pseudo_section_table.values()[@intFromEnum(psmi)];
        }
    };

    pub const ObjectSectionMapIndex = enum(u32) {
        _,

        pub fn name(osmi: ObjectSectionMapIndex, coff: *const Coff) String {
            return coff.object_section_table.keys()[@intFromEnum(osmi)];
        }

        pub fn symbol(osmi: ObjectSectionMapIndex, coff: *const Coff) Symbol.Index {
            return coff.object_section_table.values()[@intFromEnum(osmi)];
        }
    };

    pub const GlobalMapIndex = enum(u32) {
        none,
        _,

        pub fn wrap(i: ?u32) GlobalMapIndex {
            return @enumFromInt((i orelse return .none) + 1);
        }

        pub fn unwrap(gmi: GlobalMapIndex) ?u32 {
            return switch (gmi) {
                .none => null,
                _ => @intFromEnum(gmi) - 1,
            };
        }

        pub fn name(gmi: GlobalMapIndex, coff: *const Coff) String {
            return coff.globals.keys()[gmi.unwrap().?];
        }

        pub fn symbol(gmi: GlobalMapIndex, coff: *const Coff) Symbol.Index {
            return coff.globals.values()[gmi.unwrap().?].si;
        }

        pub fn libName(gmi: GlobalMapIndex, coff: *const Coff) String.Optional {
            return coff.globals.values()[gmi.unwrap().?].lib_name;
        }
    };

    pub const NavMapIndex = enum(u32) {
        _,

        pub fn navIndex(nmi: NavMapIndex, coff: *const Coff) InternPool.Nav.Index {
            return coff.navs.keys()[@intFromEnum(nmi)];
        }

        pub fn symbol(nmi: NavMapIndex, coff: *const Coff) Symbol.Index {
            return coff.navs.values()[@intFromEnum(nmi)];
        }
    };

    pub const UavMapIndex = enum(u32) {
        _,

        pub fn uavValue(umi: UavMapIndex, coff: *const Coff) InternPool.Index {
            return coff.uavs.keys()[@intFromEnum(umi)];
        }

        pub fn symbol(umi: UavMapIndex, coff: *const Coff) Symbol.Index {
            return coff.uavs.values()[@intFromEnum(umi)];
        }
    };

    const InputSection = struct {
        ioi: InputObject.Index,
        si: Symbol.Index,
        comdat_si: Symbol.Index,
        file_location: MappedFile.Node.FileLocation,
        first_li: Node.InputSection.LocalIndex,
        crc: u32,

        pub const Index = enum(u32) {
            _,

            pub fn inputSection(isi: Index, coff: *const Coff) *InputSection {
                return &coff.input_sections.items[@intFromEnum(isi)];
            }

            pub fn input(isi: Index, coff: *const Coff) InputObject.Index {
                return coff.input_sections.items[@intFromEnum(isi)].ioi;
            }

            pub fn fileLocation(isi: Index, coff: *const Coff) MappedFile.Node.FileLocation {
                return coff.input_sections.items[@intFromEnum(isi)].file_location;
            }

            pub fn symbol(isi: Index, coff: *const Coff) Symbol.Index {
                return coff.input_sections.items[@intFromEnum(isi)].si;
            }

            pub fn firstSymbol(isi: Index, coff: *const Coff) LocalIndex {
                return coff.input_sections.items[@intFromEnum(isi)].first_li;
            }
        };

        const LocalIndex = enum(u32) {
            _,

            pub fn name(isli: LocalIndex, coff: *const Coff) String {
                return coff.input_symbols.items[@intFromEnum(isli)].name;
            }
        };
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

                pub fn lazySymbol(lmi: @This(), coff: *const Coff) link.File.LazySymbol {
                    return lmi.ref().lazySymbol(coff);
                }

                pub fn symbol(lmi: @This(), coff: *const Coff) Symbol.Index {
                    return lmi.ref().symbol(coff);
                }
            };
        }

        pub fn lazySymbol(lmr: LazyMapRef, coff: *const Coff) link.File.LazySymbol {
            return .{ .kind = lmr.kind, .ty = coff.lazy.getPtrConst(lmr.kind).map.keys()[lmr.index] };
        }

        pub fn symbol(lmr: LazyMapRef, coff: *const Coff) Symbol.Index {
            return coff.lazy.getPtrConst(lmr.kind).map.values()[lmr.index];
        }
    };

    pub const Tag = @typeInfo(Node).@"union".tag_type.?;

    const known_count = @typeInfo(@TypeOf(known)).@"struct".field_names.len;
    const known = known: {
        const Known = enum {
            file,
            header,
            signature,
            first_linker_member_header,
            first_linker_member,
            second_linker_member_header,
            second_linker_member,
            longnames_member_header,
            longnames_member,
            zcu_member_header,
            zcu_member,
            coff_header,
            optional_header,
            data_directories,
            section_table,
        };
        var mut_known: std.enums.EnumFieldStruct(Known, MappedFile.Node.Index, null) = undefined;
        const info = @typeInfo(Known).@"enum";
        for (info.field_names, info.field_values) |field_name, field_value|
            @field(mut_known, field_name) = @enumFromInt(field_value);
        break :known mut_known;
    };

    comptime {
        if (!std.debug.runtime_safety) std.debug.assert(@sizeOf(Node) == 8);
    }
};

pub const InputArchive = struct {
    path: std.Build.Cache.Path,

    const Index = enum(u32) {
        _,

        pub fn path(iai: InputArchive.Index, coff: *Coff) std.Build.Cache.Path {
            return coff.input_archives.items[@intFromEnum(iai)].path;
        }
    };

    pub const Member = struct {
        iai: InputArchive.Index,
        name: String,
        content: union(enum) {
            // This range includes the member header
            object: MappedFile.Node.FileLocation,
            import: struct {
                symbol_name: String,
                lib_name: String,
                // Either ordinal or hint, depending on value of name_type
                import_ordinal_hint: u16,
                type: std.coff.ImportType,
                name_type: std.coff.ImportNameType,
            },
        },
        flags: packed struct {
            // Set if an attempt was made to load this member
            is_loaded: bool,
        },

        const Index = enum(u32) {
            _,

            pub fn member(iami: InputArchive.Member.Index, coff: *Coff) *InputArchive.Member {
                return &coff.input_archive_members.items[@intFromEnum(iami)];
            }
        };

        pub const Symbol = struct {
            iami: InputArchive.Member.Index,
            // Set to its own index to indicate its the last in the list
            next: InputArchive.Member.Symbol.Index,

            const Index = enum(u32) {
                _,
            };
        };
    };

    pub const SearchList = struct {
        first: InputArchive.Member.Symbol.Index,
        last: InputArchive.Member.Symbol.Index,
    };
};

pub const InputObject = struct {
    path: std.Build.Cache.Path,
    member_name: ?[]const u8,
    source_name: String.Optional,

    pub const Index = enum(u32) {
        _,

        pub fn path(ioi: Index, coff: *const Coff) std.Build.Cache.Path {
            return coff.input_objects.items[@intFromEnum(ioi)].path;
        }

        pub fn memberName(ioi: Index, coff: *const Coff) ?[]const u8 {
            return coff.input_objects.items[@intFromEnum(ioi)].member_name;
        }
    };
};

pub const Member = struct {
    kind: std.coff.ArchiveMemberHeader.Kind,
    header_ni: MappedFile.Node.Index,
    content_ni: MappedFile.Node.Index,
    first_linker_indices: std.array_hash_map.Auto(struct {
        mi: Member.Index,
        name: String,
    }, FirstLinkerIndex),

    pub const Index = enum(u16) {
        first,
        second,
        longnames,
        _,

        const known_count = @typeInfo(Index).@"enum".field_names.len;

        pub fn get(member_index: Member.Index, coff: *Coff) *Member {
            return &coff.members.items[@intFromEnum(member_index)];
        }
    };

    pub const FirstLinkerIndex = enum(u32) {
        _,
    };

    pub fn headerPtr(member: *Member, coff: *Coff) *std.coff.ArchiveMemberHeader {
        return @ptrCast(@alignCast(member.header_ni.slice(&coff.mf)));
    }

    /// Sets `name` as the name field of this member's header, either directly (if it's short enough),
    /// or by creating an entry in the longnames member and storing a reference to that entry.
    pub fn initHeader(member: *Member, coff: *Coff, name: []const u8, timestamp: u32) !void {
        const max_name_len = @typeInfo(@FieldType(std.coff.ArchiveMemberHeader, "name")).array.len;
        const opt_name_offset = if (name.len >= max_name_len) offset: {
            const gpa = coff.base.comp.gpa;
            const entries_ctx = LongNamesTable.Adapter{ .coff = coff };
            const gop = try coff.long_names_table.entries.getOrPutAdapted(
                gpa,
                name,
                entries_ctx,
            );

            if (!gop.found_existing) {
                errdefer _ = coff.export_table.entries.pop();

                _, const old_size = Node.known.longnames_member.location(&coff.mf).resolve(&coff.mf);
                const new_size = old_size + name.len + 1;
                assert(new_size < comptime try std.math.powi(u64, 10, max_name_len - 1));

                try Node.known.longnames_member.resize(&coff.mf, gpa, new_size);
                const name_table_slice = Node.known.longnames_member.slice(&coff.mf);
                const name_slice = name_table_slice[@intCast(old_size)..][0 .. name.len + 1];
                @memcpy(name_slice[0..name.len], name);
                name_slice[name.len] = 0;

                gop.value_ptr.* = .{
                    .offset = old_size,
                    .len = name.len,
                };
            }

            break :offset gop.value_ptr.offset;
        } else null;

        const header = member.headerPtr(coff);
        if (opt_name_offset) |name_offset| {
            header.name[0] = '/';
            storeHeaderDecimalStr(header.name[1..], name_offset);
        } else {
            @memcpy(header.name[0..name.len], name);
            header.name[name.len] = '/';
            const padding = max_name_len - name.len - 1;
            @memset(header.name[max_name_len - padding ..], ' ');
        }

        storeHeaderDecimalStr(&header.date, timestamp);

        // Matching the Microsoft behaviour of emitting blanks for these fields
        header.user_id = @splat(' ');
        header.group_id = @splat(' ');

        // file_mode is actually octal, but we only ever write 0 to it
        storeHeaderDecimalStr(&header.file_mode, 0);
        if (!member.content_ni.hasResized(&coff.mf))
            storeHeaderDecimalStr(
                &header.size,
                member.content_ni.location(&coff.mf).resolve(&coff.mf)[1],
            );

        @memcpy(&header.end_of_header, std.coff.archive_end_of_header);
    }

    pub fn storeHeaderDecimalStr(field_ptr: anytype, value: u64) void {
        const array_info = @typeInfo(@typeInfo(@TypeOf(field_ptr)).pointer.child).array;
        assert(array_info.child == u8);
        assert(value < comptime try std.math.powi(u64, 10, array_info.len));
        _ = std.fmt.printInt(field_ptr, value, 10, .lower, .{
            .width = array_info.len,
            .alignment = .left,
            .fill = ' ',
        });
    }

    pub fn loadHeaderDecimalStr(field_ptr: anytype, value: u64) void {
        const array_info = @typeInfo(@typeInfo(@TypeOf(field_ptr)).pointer.child).array;
        assert(array_info.child == u8);
        assert(value < comptime try std.math.powi(u64, 10, array_info.len));
        _ = std.fmt.printInt(field_ptr, value, 10, .lower, .{
            .width = array_info.len,
            .alignment = .left,
            .fill = ' ',
        });
    }
};

pub const LongNamesTable = struct {
    ni: MappedFile.Node.Index = .none,
    entries: std.array_hash_map.Auto(void, Entry),

    pub const Entry = struct {
        offset: u64,
        len: u64,
    };

    const Adapter = struct {
        coff: *Coff,

        pub fn eql(adapter: Adapter, lhs_key: []const u8, _: void, rhs_index: usize) bool {
            assert(adapter.coff.isArchive());
            const longnames_slice = Node.known.longnames_member.slice(&adapter.coff.mf);
            const rhs = adapter.coff.long_names_table.entries.values()[rhs_index];
            return std.mem.eql(u8, longnames_slice[@intCast(rhs.offset)..][0..@intCast(rhs.len)], lhs_key);
        }

        pub fn hash(_: Adapter, key: []const u8) u32 {
            assert(std.mem.indexOfScalar(u8, key, 0) == null);
            return std.array_hash_map.hashString(key);
        }
    };
};

pub const SymbolTable = struct {
    ni: MappedFile.Node.Index,
    strings_ni: MappedFile.Node.Index,
    strings: std.array_hash_map.Auto(String, StringIndex),
    symbols: std.array_hash_map.Auto(Symbol.Index, SymbolTable.Index),
    pending_symbol_index: u32,

    // Resizing the symbol table node has the result of accumulating padding
    // between the last symbol in the symbol table node and the start of the
    // string table node, due to the shifting method when resizing the parent in MappedFile.
    // The spec requires the string table begin immediately after the last symbol,
    // so we compact the symbol table node and move the string table back if needed.
    pending_shrink: bool,

    pub const StringIndex = enum(u32) {
        _,
    };

    pub const SymbolName = union(enum) {
        short: []const u8,
        long: StringIndex,

        pub fn store(name: SymbolName, coff: *const Coff, field: *[8]u8) void {
            switch (name) {
                .short => |s| {
                    @memcpy(field[0..s.len], s);
                    @memset(field[s.len..], 0);
                },
                .long => |l| {
                    @memset(field[0..4], 0);
                    std.mem.writePackedInt(u32, field[4..], 0, @intFromEnum(l), coff.targetEndian());
                },
            }
        }
    };

    // Symbol.Index does not map 1:1 with SymbolTable.Index:
    //  - Not all symbols need a symbol table entry
    //  - A variable number of auxiliary entries may trail each symbol
    pub const Index = enum(u32) {
        none,
        _,

        pub fn wrap(i: u32) Index {
            return @enumFromInt(i + 1);
        }

        pub fn unwrap(sti: Index) ?u32 {
            return switch (sti) {
                .none => null,
                _ => @intFromEnum(sti) - 1,
            };
        }
    };
};

pub const ExportTable = struct {
    ni: MappedFile.Node.Index,
    export_directory_table_ni: MappedFile.Node.Index,
    export_address_table_si: Symbol.Index,
    name_pointer_table_ni: MappedFile.Node.Index,
    ordinal_table_ni: MappedFile.Node.Index,
    name_table_ni: MappedFile.Node.Index,
    entries: std.array_hash_map.Auto(void, Entry),
    pending_sort: bool = false,

    pub const Entry = struct {
        si: Symbol.Index,
        name_index: u32,
        name_len: u32,
        export_address_table_ri: Reloc.Index,
    };

    const Adapter = struct {
        coff: *Coff,

        pub fn eql(adapter: Adapter, lhs_key: []const u8, _: void, rhs_index: usize) bool {
            const coff = adapter.coff;
            const name_table_slice = coff.export_table.name_table_ni.slice(&coff.mf);
            const rhs = coff.export_table.entries.values()[rhs_index];
            return std.mem.eql(u8, name_table_slice[rhs.name_index..][0..rhs.name_len], lhs_key);
        }

        pub fn hash(_: Adapter, key: []const u8) u32 {
            assert(std.mem.indexOfScalar(u8, key, 0) == null);
            return std.array_hash_map.hashString(key);
        }
    };

    pub const Ordinal = enum(u16) {
        _,

        pub fn get(export_index: ExportTable.Ordinal, coff: *Coff) *Entry {
            return &coff.export_table.entries.values()[@intFromEnum(export_index)];
        }
    };
};

pub const ImportTable = struct {
    ni: MappedFile.Node.Index,
    entries: std.array_hash_map.Auto(void, Entry),
    iat_symbol_indices: std.array_hash_map.Auto(struct {
        iti: ImportTable.Index,
        name: String.Optional,
        // If name == .none this is the ordinal, otherwise the hint
        ordinal_hint: u16,
    }, u32),

    pub const Entry = struct {
        import_lookup_table_ni: MappedFile.Node.Index,
        import_address_table_si: Symbol.Index,
        import_hint_name_table_ni: MappedFile.Node.Index,
        // All .iat_ptr globals that reference this table.
        // This is separate from `iat_symbol_indices` because multiple symbols
        // can reference to the same iat entry, after name demangling.
        import_address_table_symbols: std.ArrayList(Symbol.Index),
        len: u32,
        hint_name_len: u32,
    };

    const Adapter = struct {
        coff: *Coff,

        pub fn eql(adapter: Adapter, lhs_key: []const u8, _: void, rhs_index: usize) bool {
            const coff = adapter.coff;
            const dll_name = coff.import_table.entries.values()[rhs_index]
                .import_hint_name_table_ni.sliceConst(&coff.mf);
            return std.mem.startsWith(u8, dll_name, lhs_key) and
                std.mem.startsWith(u8, dll_name[lhs_key.len..], ".dll\x00");
        }

        pub fn hash(_: Adapter, key: []const u8) u32 {
            assert(std.mem.indexOfScalar(u8, key, 0) == null);
            return std.array_hash_map.hashString(key);
        }
    };

    pub const Index = enum(u32) {
        _,

        pub fn get(import_index: ImportTable.Index, coff: *Coff) *Entry {
            return &coff.import_table.entries.values()[@intFromEnum(import_index)];
        }
    };
};

pub const String = enum(u32) {
    @".data" = 0,
    @".idata" = 6,
    @".rdata" = 13,
    @".text" = 20,
    @".tls$" = 26,
    @".edata" = 32,
    @".ctors" = 39,
    @".ctors$ZZZ" = 46,
    @".dtors" = 57,
    @".dtors$ZZZ" = 64,
    @".bss" = 75,
    @".fptable" = 80,
    @".tls" = 89,
    @".thunks" = 94,
    _,

    pub const Optional = enum(u32) {
        @".data" = @intFromEnum(String.@".data"),
        @".idata" = @intFromEnum(String.@".idata"),
        @".rdata" = @intFromEnum(String.@".rdata"),
        @".text" = @intFromEnum(String.@".text"),
        @".tls$" = @intFromEnum(String.@".tls$"),
        @".edata" = @intFromEnum(String.@".edata"),
        @".ctors" = @intFromEnum(String.@".ctors"),
        @".ctors$ZZZ" = @intFromEnum(String.@".ctors$ZZZ"),
        @".dtors" = @intFromEnum(String.@".dtors"),
        @".dtors$ZZZ" = @intFromEnum(String.@".dtors$ZZZ"),
        @".bss" = @intFromEnum(String.@".bss"),
        @".fptable" = @intFromEnum(String.@".fptable"),
        @".tls" = @intFromEnum(String.@".tls"),
        @".thunks" = @intFromEnum(String.@".thunks"),
        none = std.math.maxInt(u32),
        _,

        pub fn unwrap(os: String.Optional) ?String {
            return switch (os) {
                else => |s| @enumFromInt(@intFromEnum(s)),
                .none => null,
            };
        }

        pub fn toSlice(os: String.Optional, coff: *Coff) ?[:0]const u8 {
            return (os.unwrap() orelse return null).toSlice(coff);
        }
    };

    pub fn toSlice(s: String, coff: *Coff) [:0]const u8 {
        const slice = coff.string_bytes.items[@intFromEnum(s)..];
        return slice[0..std.mem.indexOfScalar(u8, slice, 0).? :0];
    }

    pub fn toOptional(s: String) String.Optional {
        return @enumFromInt(@intFromEnum(s));
    }
};

pub const Section = struct {
    si: Symbol.Index,
    relocation_table_ni: MappedFile.Node.Index,

    pub const RelocationIndex = enum(u16) {
        none,
        _,

        pub fn wrap(i: ?u16) RelocationIndex {
            return @enumFromInt((i orelse return .none) + 1);
        }

        pub fn unwrap(sri: RelocationIndex) ?u16 {
            return switch (sri) {
                .none => null,
                _ => @intFromEnum(sri) - 1,
            };
        }

        pub fn entry(
            sri: RelocationIndex,
            coff: *Coff,
            sn: Symbol.SectionNumber,
        ) ?*align(2) std.coff.Relocation {
            if (sri == .none) return null;
            const table_slice = sn.section(coff).relocation_table_ni.slice(&coff.mf);
            return @ptrCast(@alignCast(&table_slice[@as(u32, sri.unwrap().?) * std.coff.Relocation.sizeOf()]));
        }
    };
};

pub const Global = struct {
    si: Symbol.Index,
    lib_name: String.Optional,
};

pub const WeakExternalStrat = enum(u3) {
    none,
    no_library,
    library,
    alias,
    anti_dependency,

    pub fn fromFlag(flag: std.coff.WeakExternalFlag) WeakExternalStrat {
        return switch (flag) {
            .SEARCH_NOLIBRARY => .no_library,
            .SEARCH_LIBRARY => .library,
            .SEARCH_ALIAS => .alias,
            .ANTI_DEPENDENCY => .anti_dependency,
            _ => unreachable,
        };
    }
};

const SpecialSymbol = enum {
    entry,
    tls,
    none,
};

pub const Symbol = struct {
    ni: MappedFile.Node.Index,
    rva: u32,
    value: std.meta.BareUnion(Symbol.Value),
    extra: std.meta.BareUnion(Symbol.Extra),
    flags: packed struct(u16) {
        value_tag: ValueTag,
        extra_tag: ExtraTag,
        type: Symbol.Type,
        dll_storage_class: DllStorageClass,
        weak_external_strat: WeakExternalStrat,
        _: u5 = 0,
    },
    /// Relocations contained within this symbol
    loc_relocs: Reloc.Index,
    /// Relocations targeting this symbol
    target_relocs: Reloc.Index,
    section_number: SectionNumber,
    gmi: Node.GlobalMapIndex,

    pub const DllStorageClass = enum(u2) {
        default,
        dllimport,
        dllexport,
    };

    pub const Type = enum(u2) {
        unknown,
        code,
        data,
    };

    const ValueTag = enum(u2) {
        none,
        node_offset,
        weak_alias_si,
        weak_alias_name,
    };

    pub const Value = union(ValueTag) {
        none,
        /// The offset of the symbol within its node. Used with symbols that
        /// don't create their own nodes: .input_section, .import_address_table
        /// Images only.
        node_offset: u32,
        /// Images: the weak alias that should replace this symbol if it is not resolved.
        /// Objects: he target of a weak external that hasn't been assigned an sti yet.
        /// Globals only.
        weak_alias_si: Symbol.Index,
        /// For weak externals that have an alias that is also an undef
        /// external, this is the name of the alias global that should
        /// be generated and resolved if this symbol is not resolved.
        /// Globals only, images only.
        weak_alias_name: String,
    };

    const ExtraTag = enum(u2) {
        size,
        isli,
        next_alias_si,
    };

    pub const Extra = union(ExtraTag) {
        // The size of the symbol
        size: u32,
        /// Only valid when .ni == .input_section and .value_tag == .node_offset
        isli: Node.InputSection.LocalIndex,
        /// The next symbol in the list of aliases of this symbol.
        next_alias_si: Symbol.Index,
    };

    pub fn setValue(sym: *Symbol, value: Symbol.Value) void {
        sym.flags.value_tag = std.meta.activeTag(value);
        sym.value = switch (sym.flags.value_tag) {
            inline else => |t| @unionInit(
                @FieldType(Symbol, "value"),
                @tagName(t),
                @field(value, @tagName(t)),
            ),
        };
    }

    pub fn setExtra(sym: *Symbol, extra: Symbol.Extra) void {
        sym.flags.extra_tag = std.meta.activeTag(extra);
        sym.extra = switch (sym.flags.extra_tag) {
            inline else => |t| @unionInit(
                @FieldType(Symbol, "extra"),
                @tagName(t),
                @field(extra, @tagName(t)),
            ),
        };
    }

    pub fn nodeOffset(sym: *const Symbol, coff: *Coff) u32 {
        return switch (sym.flags.value_tag) {
            .node_offset => offset: {
                assert(switch (coff.getNode(sym.ni)) {
                    // Separate nodes are not created for these entries per-symbol
                    .input_section, .import_address_table => true,
                    else => false,
                });
                break :offset sym.value.node_offset;
            },
            else => 0,
        };
    }

    pub fn size(sym: *const Symbol) u32 {
        return if (sym.flags.extra_tag == .size) sym.extra.size else 0;
    }

    pub const SectionNumber = enum(i16) {
        UNDEFINED = 0,
        ABSOLUTE = -1,
        DEBUG = -2,
        _,

        fn toIndex(sn: SectionNumber) u15 {
            return @intCast(@intFromEnum(sn) - 1);
        }

        fn hasIndex(sn: SectionNumber) bool {
            return @intFromEnum(sn) > 0;
        }

        pub fn symbol(sn: SectionNumber, coff: *const Coff) Symbol.Index {
            return sn.section(coff).si;
        }

        pub fn name(sn: SectionNumber, coff: *const Coff) String {
            return coff.section_table.keys()[sn.toIndex()];
        }

        pub fn section(sn: SectionNumber, coff: *const Coff) *Section {
            return &coff.section_table.values()[sn.toIndex()];
        }

        pub fn header(sn: SectionNumber, coff: *Coff) *std.coff.SectionHeader {
            return &coff.sectionTableSlice()[sn.toIndex()];
        }
    };

    pub const Index = enum(u32) {
        null,
        bss,
        data,
        rdata,
        text,
        _,

        const known_count = @typeInfo(Index).@"enum".field_names.len;

        pub fn get(si: Symbol.Index, coff: *Coff) *Symbol {
            return &coff.symbols.items[@intFromEnum(si)];
        }

        pub fn unwrap(si: Symbol.Index) ?Symbol.Index {
            if (si == .null) return null;
            return si;
        }

        pub fn node(si: Symbol.Index, coff: *Coff) MappedFile.Node.Index {
            const ni = si.get(coff).ni;
            assert(ni != .none);
            return ni;
        }

        pub fn sti(si: Symbol.Index, coff: *Coff) SymbolTable.Index {
            assert(!coff.isImage());
            return coff.symbol_table.symbols.get(si) orelse .none;
        }

        pub fn next(si: Symbol.Index) Symbol.Index {
            return @enumFromInt(@intFromEnum(si) + 1);
        }

        pub fn knownString(si: Symbol.Index) String.Optional {
            return switch (si) {
                .null, _ => .none,
                inline else => |tag| @field(String.Optional, "." ++ @tagName(tag)),
            };
        }

        pub fn flushMoved(si: Symbol.Index, coff: *Coff) !void {
            const sym = si.get(coff);
            sym.rva = coff.computeNodeRva(sym.ni) + sym.nodeOffset(coff);
            try si.applyLocationRelocs(coff);
            try si.applyTargetRelocs(coff, .none);

            var alias_sym = sym;
            while (alias_sym.flags.extra_tag == .next_alias_si) {
                const alias_si = alias_sym.extra.next_alias_si;
                alias_sym = alias_si.get(coff);
                assert(alias_sym.ni == sym.ni);
                alias_sym.rva = sym.rva;
                try alias_si.applyTargetRelocs(coff, .none);
            }
        }

        pub fn flushSymbolTableIndex(si: Symbol.Index, coff: *Coff) void {
            const sym = si.get(coff);
            const index = si.sti(coff).unwrap().?;
            var ri = sym.target_relocs;
            while (ri != .none) {
                const reloc = ri.get(coff);
                assert(reloc.target == si);
                if (reloc.sri.entry(coff, reloc.loc.get(coff).section_number)) |entry|
                    coff.targetStore(&entry.symbol_table_index, index);
                ri = reloc.next;
            }
        }

        pub fn applyLocationRelocs(si: Symbol.Index, coff: *Coff) !void {
            const sym = si.get(coff);
            switch (sym.loc_relocs) {
                .none => {},
                else => |loc_relocs| {
                    for (coff.relocs.items[@intFromEnum(loc_relocs)..]) |*reloc| {
                        if (reloc.loc != si) break;
                        if (reloc.sri.entry(coff, sym.section_number)) |entry| coff.targetStore(
                            &entry.virtual_address,
                            @intCast(coff.computeSymbolSectionOffset(sym, .image) + reloc.offset),
                        );
                        try reloc.apply(coff);
                    }
                },
            }
        }

        pub fn applyTargetRelocs(si: Symbol.Index, coff: *Coff, end: Reloc.Index) !void {
            const sym = si.get(coff);

            var ri = sym.target_relocs;
            while (ri != end) {
                const reloc = ri.get(coff);
                assert(reloc.target == si);
                try reloc.apply(coff);
                ri = reloc.next;
            }
        }

        pub fn deleteLocationRelocs(si: Symbol.Index, coff: *Coff) void {
            const sym = si.get(coff);
            switch (sym.loc_relocs) {
                .none => {},
                else => |loc_relocs| {
                    for (coff.relocs.items[@intFromEnum(loc_relocs)..]) |*reloc| {
                        if (reloc.loc != si) break;
                        reloc.delete(coff);
                    }
                    sym.loc_relocs = .none;
                },
            }
        }
    };

    comptime {
        if (!std.debug.runtime_safety) std.debug.assert(@sizeOf(Symbol) == 32);
    }
};

pub const Reloc = extern struct {
    offset: u64,
    addend: i64,
    type: Reloc.Type,
    sri: Section.RelocationIndex,
    prev: Reloc.Index,
    next: Reloc.Index,
    loc: Symbol.Index,
    target: Symbol.Index,
    flags: packed struct(u8) {
        /// Indicates the addend is not known and should be recovered from the location itself.
        /// COFF relocation tables don't encode the addend, only the location.
        recover_addend: bool,
        /// Set if this reloc is in the free list.
        /// When set, `prev` / `next` refer to other relocs in the free list.
        /// All other fields are undefined.
        free: bool,
        _: u6 = 0,
    },

    pub const Type = extern union {
        AMD64: std.coff.IMAGE.REL.AMD64,
        ARM: std.coff.IMAGE.REL.ARM,
        ARM64: std.coff.IMAGE.REL.ARM64,
        SH: std.coff.IMAGE.REL.SH,
        PPC: std.coff.IMAGE.REL.PPC,
        I386: std.coff.IMAGE.REL.I386,
        IA64: std.coff.IMAGE.REL.IA64,
        MIPS: std.coff.IMAGE.REL.MIPS,
        M32R: std.coff.IMAGE.REL.M32R,
        u16: u16,
    };

    pub const Index = enum(u32) {
        none = std.math.maxInt(u32),
        _,

        pub fn wrap(i: ?u32) Reloc.Index {
            return @enumFromInt((i orelse return .none) + 1);
        }

        pub fn get(ri: Reloc.Index, coff: *Coff) *Reloc {
            return &coff.relocs.items[@intFromEnum(ri)];
        }
    };

    pub fn apply(reloc: *Reloc, coff: *Coff) !void {
        const loc_sym = reloc.loc.get(coff);
        switch (loc_sym.ni) {
            .none => return,
            else => |ni| if (ni.hasMoved(&coff.mf)) return,
        }

        const loc_slice = loc_sym.ni.slice(&coff.mf)[@intCast(reloc.offset)..];
        const target_endian = coff.targetEndian();
        const target_machine = coff.targetLoad(&coff.headerPtr().machine);

        if (!coff.isImage()) {
            assert(!reloc.flags.recover_addend);
            switch (target_machine) {
                else => |machine| @panic(@tagName(machine)),
                .AMD64 => switch (reloc.type.AMD64) {
                    else => |kind| @panic(@tagName(kind)),
                    .ABSOLUTE => {},
                    .ADDR64 => std.mem.writeInt(
                        u64,
                        loc_slice[0..8],
                        @intCast(reloc.addend),
                        target_endian,
                    ),
                    .ADDR32,
                    .ADDR32NB,
                    .SECREL,
                    => std.mem.writeInt(
                        u32,
                        loc_slice[0..4],
                        @intCast(reloc.addend),
                        target_endian,
                    ),
                    .REL32,
                    .REL32_1,
                    .REL32_2,
                    .REL32_3,
                    .REL32_4,
                    .REL32_5,
                    => std.mem.writeInt(
                        i32,
                        loc_slice[0..4],
                        @intCast(reloc.addend),
                        target_endian,
                    ),
                },
                .I386 => switch (reloc.type.I386) {
                    else => |kind| @panic(@tagName(kind)),
                    .ABSOLUTE => {},
                    .DIR16,
                    => std.mem.writeInt(
                        u16,
                        loc_slice[0..2],
                        @intCast(reloc.addend),
                        target_endian,
                    ),
                    .REL16,
                    => std.mem.writeInt(
                        i16,
                        loc_slice[0..2],
                        @intCast(reloc.addend),
                        target_endian,
                    ),
                    .DIR32,
                    .DIR32NB,
                    .SECREL,
                    => std.mem.writeInt(
                        u32,
                        loc_slice[0..4],
                        @intCast(reloc.addend),
                        target_endian,
                    ),
                    .REL32,
                    => std.mem.writeInt(
                        i32,
                        loc_slice[0..4],
                        @intCast(reloc.addend),
                        target_endian,
                    ),
                },
            }

            return;
        } else if (reloc.flags.recover_addend) {
            reloc.flags.recover_addend = false;
            reloc.addend = switch (target_machine) {
                else => |machine| @panic(@tagName(machine)),
                .AMD64 => switch (reloc.type.AMD64) {
                    else => |kind| @panic(@tagName(kind)),
                    .ABSOLUTE => 0,
                    .ADDR64 => @bitCast(std.mem.readInt(
                        u64,
                        loc_slice[0..8],
                        target_endian,
                    )),
                    .ADDR32,
                    .ADDR32NB,
                    .SECREL,
                    .REL32,
                    .REL32_1,
                    .REL32_2,
                    .REL32_3,
                    .REL32_4,
                    .REL32_5,
                    => std.mem.readInt(
                        i32,
                        loc_slice[0..4],
                        target_endian,
                    ),
                },
                .I386 => switch (reloc.type.I386) {
                    else => |kind| @panic(@tagName(kind)),
                    .ABSOLUTE => 0,
                    .DIR16,
                    .REL16,
                    => std.mem.readInt(
                        i16,
                        loc_slice[0..2],
                        target_endian,
                    ),
                    .DIR32,
                    .DIR32NB,
                    .SECREL,
                    .REL32,
                    => std.mem.readInt(
                        i32,
                        loc_slice[0..4],
                        target_endian,
                    ),
                },
            };
        }

        const target_sym = reloc.target.get(coff);
        const is_abs = switch (target_sym.ni) {
            .none => if (target_sym.section_number == .ABSOLUTE) true else return,
            else => |ni| if (ni.hasMoved(&coff.mf)) return else false,
        };

        const target_rva = target_sym.rva +% @as(u64, @bitCast(reloc.addend));
        if (is_abs) {
            switch (target_machine) {
                else => |machine| @panic(@tagName(machine)),
                .AMD64 => switch (reloc.type.AMD64) {
                    // TODO: Could wait to report these later, in reportUndefs -> reportRelocErrs,
                    //       so that this function doesn't return an err
                    else => |kind| return coff.base.comp.link_diags.fail(
                        "absolute symbol '{s}' targeted by invalid relocation type: {t}",
                        .{ target_sym.gmi.name(coff).toSlice(coff), kind },
                    ),
                    .ABSOLUTE => {},
                    .ADDR64 => std.mem.writeInt(
                        u64,
                        loc_slice[0..8],
                        target_rva,
                        target_endian,
                    ),
                    .ADDR32 => std.mem.writeInt(
                        u32,
                        loc_slice[0..4],
                        @intCast(target_rva),
                        target_endian,
                    ),
                },
                .I386 => switch (reloc.type.I386) {
                    else => |kind| return coff.base.comp.link_diags.fail(
                        "absolute symbol '{s}' targeted by invalid relocation type: {t}",
                        .{ target_sym.gmi.name(coff).toSlice(coff), kind },
                    ),
                    .ABSOLUTE => {},
                    .DIR16 => std.mem.writeInt(
                        u16,
                        loc_slice[0..2],
                        @intCast(target_rva),
                        target_endian,
                    ),
                    .DIR32 => std.mem.writeInt(
                        u32,
                        loc_slice[0..4],
                        @intCast(target_rva),
                        target_endian,
                    ),
                },
            }
        } else {
            switch (target_machine) {
                else => |machine| @panic(@tagName(machine)),
                .AMD64 => switch (reloc.type.AMD64) {
                    else => |kind| @panic(@tagName(kind)),
                    .ABSOLUTE => {},
                    .ADDR64 => std.mem.writeInt(
                        u64,
                        loc_slice[0..8],
                        coff.optionalHeaderField(.image_base) + target_rva,
                        target_endian,
                    ),
                    .ADDR32 => std.mem.writeInt(
                        u32,
                        loc_slice[0..4],
                        @intCast(coff.optionalHeaderField(.image_base) + target_rva),
                        target_endian,
                    ),
                    .ADDR32NB => std.mem.writeInt(
                        u32,
                        loc_slice[0..4],
                        @intCast(target_rva),
                        target_endian,
                    ),
                    .REL32 => std.mem.writeInt(
                        i32,
                        loc_slice[0..4],
                        @intCast(@as(i64, @bitCast(target_rva -% (loc_sym.rva + reloc.offset + 4)))),
                        target_endian,
                    ),
                    .REL32_1 => std.mem.writeInt(
                        i32,
                        loc_slice[0..4],
                        @intCast(@as(i64, @bitCast(target_rva -% (loc_sym.rva + reloc.offset + 5)))),
                        target_endian,
                    ),
                    .REL32_2 => std.mem.writeInt(
                        i32,
                        loc_slice[0..4],
                        @intCast(@as(i64, @bitCast(target_rva -% (loc_sym.rva + reloc.offset + 6)))),
                        target_endian,
                    ),
                    .REL32_3 => std.mem.writeInt(
                        i32,
                        loc_slice[0..4],
                        @intCast(@as(i64, @bitCast(target_rva -% (loc_sym.rva + reloc.offset + 7)))),
                        target_endian,
                    ),
                    .REL32_4 => std.mem.writeInt(
                        i32,
                        loc_slice[0..4],
                        @intCast(@as(i64, @bitCast(target_rva -% (loc_sym.rva + reloc.offset + 8)))),
                        target_endian,
                    ),
                    .REL32_5 => std.mem.writeInt(
                        i32,
                        loc_slice[0..4],
                        @intCast(@as(i64, @bitCast(target_rva -% (loc_sym.rva + reloc.offset + 9)))),
                        target_endian,
                    ),
                    .SECREL => std.mem.writeInt(
                        u32,
                        loc_slice[0..4],
                        @intCast(coff.computeSymbolSectionOffset(target_sym, .pseudo) + reloc.addend),
                        target_endian,
                    ),
                },
                .I386 => switch (reloc.type.I386) {
                    else => |kind| @panic(@tagName(kind)),
                    .ABSOLUTE => {},
                    .DIR16 => std.mem.writeInt(
                        u16,
                        loc_slice[0..2],
                        @intCast(coff.optionalHeaderField(.image_base) + target_rva),
                        target_endian,
                    ),
                    .REL16 => std.mem.writeInt(
                        i16,
                        loc_slice[0..2],
                        @intCast(@as(i64, @bitCast(target_rva -% (loc_sym.rva + reloc.offset + 2)))),
                        target_endian,
                    ),
                    .DIR32 => std.mem.writeInt(
                        u32,
                        loc_slice[0..4],
                        @intCast(coff.optionalHeaderField(.image_base) + target_rva),
                        target_endian,
                    ),
                    .DIR32NB => std.mem.writeInt(
                        u32,
                        loc_slice[0..4],
                        @intCast(target_rva),
                        target_endian,
                    ),
                    .REL32 => std.mem.writeInt(
                        i32,
                        loc_slice[0..4],
                        @intCast(@as(i64, @bitCast(target_rva -% (loc_sym.rva + reloc.offset + 4)))),
                        target_endian,
                    ),
                    .SECREL => std.mem.writeInt(
                        u32,
                        loc_slice[0..4],
                        @intCast(coff.computeSymbolSectionOffset(target_sym, .pseudo) + reloc.addend),
                        target_endian,
                    ),
                },
            }
        }
    }

    pub fn delete(reloc: *Reloc, coff: *Coff) void {
        if (reloc.sri != .none) {
            // TODO: Need to remove this from the COFF relocation table (maybe removeswap?)
            // TODO: If this was the last reloc causing something to be in the symbol table, we should remove
            //       the symbol table entry (and unset sti). That will require flushSymbolTableIndex on the
            //       swapped symbol if we exchange indices
            @panic("TODO implement symbol table reloc deletions");
        }

        switch (reloc.prev) {
            .none => {
                const target = reloc.target.get(coff);
                assert(target.target_relocs.get(coff) == reloc);
                target.target_relocs = reloc.next;
            },
            else => |prev| prev.get(coff).next = reloc.next,
        }
        switch (reloc.next) {
            .none => {},
            else => |next| next.get(coff).prev = reloc.prev,
        }

        reloc.* = undefined;
        reloc.flags = .{
            .recover_addend = false,
            .free = true,
        };

        const ri: Reloc.Index = .wrap(@intCast(reloc - coff.relocs.items.ptr));
        if (coff.last_free_reloc == .none) {
            assert(coff.first_free_reloc == .none);
            coff.first_free_reloc = ri;
            coff.last_free_reloc = ri;
        } else {
            coff.last_free_reloc.get(coff).next = ri;
            reloc.prev = coff.last_free_reloc;
            reloc.next = .none;
            coff.last_free_reloc = ri;
        }
    }

    comptime {
        if (!std.debug.runtime_safety) std.debug.assert(@sizeOf(Reloc) == 40);
    }
};

pub fn open(
    arena: std.mem.Allocator,
    comp: *Compilation,
    path: std.Build.Cache.Path,
    options: link.File.OpenOptions,
) !*Coff {
    return create(arena, comp, path, options);
}
pub fn createEmpty(
    arena: std.mem.Allocator,
    comp: *Compilation,
    path: std.Build.Cache.Path,
    options: link.File.OpenOptions,
) !*Coff {
    return create(arena, comp, path, options);
}
fn create(
    arena: std.mem.Allocator,
    comp: *Compilation,
    path: std.Build.Cache.Path,
    options: link.File.OpenOptions,
) !*Coff {
    const target = &comp.root_mod.resolved_target.result;
    assert(target.ofmt == .coff);
    if (target.cpu.arch.endian() != comptime targetEndian(undefined))
        return error.UnsupportedCOFFArchitecture;
    const machine = target.toCoffMachine();
    const timestamp: u32 = 0;
    const major_subsystem_version = options.major_subsystem_version orelse 6;
    const minor_subsystem_version = options.minor_subsystem_version orelse 0;
    const magic: std.coff.OptionalHeader.Magic = switch (target.ptrBitWidth()) {
        0...32 => .PE32,
        33...64 => .@"PE32+",
        else => return error.UnsupportedCOFFArchitecture,
    };
    const section_align: std.mem.Alignment = switch (machine) {
        .AMD64, .I386 => @enumFromInt(12),
        .SH3, .SH3DSP, .SH4, .SH5 => @enumFromInt(12),
        .MIPS16, .MIPSFPU, .MIPSFPU16, .WCEMIPSV2 => @enumFromInt(12),
        .POWERPC, .POWERPCFP => @enumFromInt(12),
        .ALPHA, .ALPHA64 => @enumFromInt(13),
        .IA64 => @enumFromInt(13),
        .ARM => @enumFromInt(12),
        else => return error.UnsupportedCOFFArchitecture,
    };

    const io = comp.io;

    const coff = try arena.create(Coff);
    const file = try path.root_dir.handle.createFile(io, path.sub_path, .{
        .read = true,
        .permissions = link.File.determinePermissions(comp.config.output_mode, comp.config.link_mode),
    });
    errdefer file.close(io);
    coff.* = .{
        .base = .{
            .tag = .coff2,

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
        .nodes = .empty,
        .members = .empty,
        .pending_members = .empty,
        .lib_string_table = .empty,
        .lib_string_len = 0,
        .long_names_table = .{
            .entries = .empty,
        },
        .import_table = .{
            .ni = .none,
            .entries = .empty,
            .iat_symbol_indices = .empty,
        },
        .export_table = .{
            .ni = .none,
            .export_directory_table_ni = .none,
            .export_address_table_si = .null,
            .name_pointer_table_ni = .none,
            .ordinal_table_ni = .none,
            .name_table_ni = .none,
            .entries = .empty,
        },
        .symbol_table = .{
            .ni = .none,
            .strings_ni = .none,
            .strings = .empty,
            .symbols = .empty,
            .pending_symbol_index = 0,
            .pending_shrink = false,
        },
        .inputs = .empty,
        .input_archives = .empty,
        .input_archive_members = .empty,
        .input_archive_symbols = .empty,
        .input_archive_symbol_indices = .empty,
        .pending_input = null,
        .pending_default_libs = .empty,
        .alternate_names = .empty,
        .input_objects = .empty,
        .input_symbols = .empty,
        .input_sections = .empty,
        .input_section_pending_index = 0,
        .inputs_complete = false,
        .exports_complete = false,
        .pending_special_symbol = .entry,
        .strings = .empty,
        .string_bytes = .empty,
        .section_table = .empty,
        .pseudo_section_table = .empty,
        .object_section_table = .empty,
        .section_merges = .empty,
        .section_merge_pending_index = 0,
        .symbols = .empty,
        .globals = .empty,
        .global_pending_index = 0,
        .navs = .empty,
        .uavs = .empty,
        .lazy = .initFill(.{
            .map = .empty,
            .pending_index = 0,
        }),
        .pending_uavs = .empty,
        .relocs = .empty,
        .first_free_reloc = .none,
        .last_free_reloc = .none,
        .const_prog_node = .none,
        .synth_prog_node = .none,
        .symbol_prog_node = .none,
        .member_prog_node = .none,
        .input_prog_node = .none,
    };
    errdefer coff.deinit();

    {
        const strings = std.enums.values(String);
        try coff.strings.ensureTotalCapacityContext(comp.gpa, @intCast(strings.len), .{
            .bytes = &coff.string_bytes,
        });
        for (strings) |string| assert(try coff.getOrPutString(@tagName(string)) == string);
    }

    try coff.initHeaders(
        machine,
        timestamp,
        major_subsystem_version,
        minor_subsystem_version,
        magic,
        if (options.subsystem) |s| switch (s) {
            .console => .WINDOWS_CUI,
            .windows => .WINDOWS_GUI,
            else => return error.UnsupportedCOFFSubsystem,
        } else .WINDOWS_CUI,
        section_align,
        std.fs.path.basename(path.sub_path),
    );
    try coff.initBuiltins();
    return coff;
}

pub fn deinit(coff: *Coff) void {
    const gpa = coff.base.comp.gpa;
    coff.mf.deinit(gpa);
    coff.nodes.deinit(gpa);
    coff.pending_members.deinit(gpa);
    coff.lib_string_table.deinit(gpa);
    coff.long_names_table.entries.deinit(gpa);
    coff.import_table.entries.deinit(gpa);
    coff.import_table.iat_symbol_indices.deinit(gpa);
    coff.export_table.entries.deinit(gpa);
    coff.symbol_table.strings.deinit(gpa);
    coff.symbol_table.symbols.deinit(gpa);
    coff.inputs.deinit(gpa);
    coff.input_archives.deinit(gpa);
    coff.input_archive_members.deinit(gpa);
    coff.input_archive_symbols.deinit(gpa);
    coff.input_archive_symbol_indices.deinit(gpa);
    for (coff.pending_default_libs.items) |l| gpa.free(l.path);
    coff.pending_default_libs.deinit(gpa);
    coff.alternate_names.deinit(gpa);
    coff.input_objects.deinit(gpa);
    coff.input_symbols.deinit(gpa);
    coff.input_sections.deinit(gpa);
    coff.strings.deinit(gpa);
    coff.string_bytes.deinit(gpa);
    coff.section_table.deinit(gpa);
    coff.pseudo_section_table.deinit(gpa);
    coff.object_section_table.deinit(gpa);
    coff.symbols.deinit(gpa);
    coff.globals.deinit(gpa);
    coff.navs.deinit(gpa);
    coff.uavs.deinit(gpa);
    for (&coff.lazy.values) |*lazy| lazy.map.deinit(gpa);
    coff.pending_uavs.deinit(gpa);
    coff.relocs.deinit(gpa);
    coff.* = undefined;
}

fn isImage(coff: *const Coff) bool {
    const comp = coff.base.comp;
    return switch (comp.config.output_mode) {
        .Exe => true,
        .Lib => switch (comp.config.link_mode) {
            .static => false,
            .dynamic => true,
        },
        .Obj => false,
    };
}

fn isArchive(coff: *const Coff) bool {
    const comp = coff.base.comp;
    return switch (comp.config.output_mode) {
        .Exe => false,
        .Lib => switch (comp.config.link_mode) {
            .static => true,
            .dynamic => false,
        },
        .Obj => false,
    };
}

fn isExe(coff: *const Coff) bool {
    return coff.base.comp.config.output_mode == .Exe;
}

fn isObj(coff: *const Coff) bool {
    return coff.base.comp.config.output_mode == .Obj;
}

fn hasCoffHeader(coff: *const Coff) bool {
    return coff.base.comp.zcu != null or !coff.isArchive();
}

fn sectionParent(coff: *Coff) MappedFile.Node.Index {
    assert(coff.hasCoffHeader());
    return if (coff.isArchive()) Node.known.zcu_member else Node.known.file;
}

fn initHeaders(
    coff: *Coff,
    machine: std.coff.IMAGE.FILE.MACHINE,
    timestamp: u32,
    major_subsystem_version: u16,
    minor_subsystem_version: u16,
    magic: std.coff.OptionalHeader.Magic,
    subsystem: std.coff.Subsystem,
    section_align: std.mem.Alignment,
    file_name: []const u8,
) !void {
    const comp = coff.base.comp;
    const gpa = comp.gpa;
    const target_endian = coff.targetEndian();
    const file_align: std.mem.Alignment = comptime .fromByteUnits(default_file_alignment);
    const is_image = coff.isImage();
    const is_archive = coff.isArchive();
    const target = &comp.root_mod.resolved_target.result;
    const optional_header_size: u16 = if (is_image) switch (magic) {
        _ => unreachable,
        inline else => |ct_magic| @sizeOf(@field(std.coff.OptionalHeader, @tagName(ct_magic))),
    } else 0;
    const data_directories_size: u16 = if (is_image)
        @sizeOf(std.coff.ImageDataDirectory) * std.coff.IMAGE.DIRECTORY_ENTRY.len
    else
        0;

    var expected_nodes_len: usize = Node.known_count;
    if (coff.hasCoffHeader()) {
        // Sections
        expected_nodes_len += 4;

        if (is_image) {
            // Pseudo-sections and import / export table
            expected_nodes_len += 9;
            if (comp.config.link_libc and target.abi == .msvc)
                expected_nodes_len += 1;
        } else
        // Symbol table
        expected_nodes_len += 2;

        // TLS section
        if (comp.config.any_non_single_threaded) {
            if (!is_image) expected_nodes_len += 1;
            expected_nodes_len += 1;
        }
    }
    defer assert(coff.nodes.len == expected_nodes_len);

    try coff.nodes.ensureTotalCapacity(gpa, expected_nodes_len);
    coff.nodes.appendAssumeCapacity(.file);

    const header_ni = Node.known.header;
    assert(header_ni == try coff.mf.addOnlyChildNode(gpa, Node.known.file, .{
        .alignment = coff.mf.flags.block_size,
        .fixed = true,
    }));
    coff.nodes.appendAssumeCapacity(.header);

    const signature_ni = Node.known.signature;
    assert(signature_ni == try coff.mf.addLastChildNode(gpa, if (is_image or !is_archive) header_ni else Node.known.file, .{
        .size = if (is_image)
            msdos_stub.len + std.coff.pe_signature.len
        else if (is_archive)
            std.coff.archive_signature.len
        else
            0,
        .alignment = .@"4",
        .fixed = true,
    }));
    coff.nodes.appendAssumeCapacity(.signature);

    const signature_slice = signature_ni.slice(&coff.mf);
    if (is_image) {
        @memcpy(signature_slice[0..msdos_stub.len], &msdos_stub);
        @memcpy(signature_slice[signature_slice.len - std.coff.pe_signature.len ..], std.coff.pe_signature);
    } else if (is_archive) {
        @memcpy(signature_slice, std.coff.archive_signature);
    }

    const opt_coff_parent_ni = if (is_archive) parent: {
        const initial_member_count = Member.Index.known_count + @intFromBool(comp.zcu != null);
        try coff.members.ensureTotalCapacity(gpa, initial_member_count);

        assert(Member.Index.first == try coff.addMemberAssumeCapacity(.first_linker, @sizeOf(u32)));
        coff.targetStore(coff.firstLinkerMemberNumSymbolsPtr(), 0);

        assert(Member.Index.second == try coff.addMemberAssumeCapacity(.second_linker, 2 * @sizeOf(u32)));
        coff.targetStore(coff.secondLinkerMemberNumMembersPtr(), 0);
        coff.targetStore(coff.secondLinkerMemberNumSymbolsPtr(), 0);

        assert(Member.Index.longnames == try coff.addMemberAssumeCapacity(.longnames, 0));

        const first_linker_member = Member.Index.first.get(coff);
        const second_linker_member = Member.Index.second.get(coff);
        const longnames_member = Member.Index.longnames.get(coff);

        try first_linker_member.initHeader(coff, "", timestamp);
        try second_linker_member.initHeader(coff, "", timestamp);
        try longnames_member.initHeader(coff, "/", timestamp);

        if (comp.zcu) |zcu| {
            const zcu_mi = try coff.addMemberAssumeCapacity(.coff, @sizeOf(std.coff.Header));
            const zcu_member = zcu_mi.get(coff);
            try zcu_member.initHeader(coff, zcu.main_mod.fully_qualified_name, timestamp);

            break :parent zcu_member.content_ni;
        }

        // These placeholder nodes are placed before the first member - if there are
        // no other members then the last linker member (longnames) needs to expand
        // to fill the padding at the end of the file.
        assert(Node.known.zcu_member_header == try coff.mf.addNodeAfter(gpa, Node.known.header, .{}));
        assert(Node.known.zcu_member == try coff.mf.addNodeAfter(gpa, Node.known.header, .{}));
        coff.nodes.appendAssumeCapacity(.placeholder);
        coff.nodes.appendAssumeCapacity(.placeholder);

        break :parent null;
    } else parent: {
        // TODO: Not ideal to have this many placeholder nodes - use two distinct `Node.known` types?
        while (true) {
            const placeholder_ni = try coff.mf.addLastChildNode(gpa, Node.known.file, .{});
            coff.nodes.appendAssumeCapacity(.placeholder);
            if (placeholder_ni == Node.known.zcu_member) break;
        }

        break :parent Node.known.header;
    };

    const coff_parent_ni = opt_coff_parent_ni orelse {
        // If we're not generating any code, no more known nodes are used
        while (coff.nodes.len < Node.known_count) {
            _ = try coff.mf.addNodeAfter(gpa, Node.known.header, .{});
            coff.nodes.appendAssumeCapacity(.placeholder);
        }

        return;
    };

    const coff_header_ni = Node.known.coff_header;
    assert(coff_header_ni == try coff.mf.addLastChildNode(gpa, coff_parent_ni, .{
        .size = @sizeOf(std.coff.Header),
        .alignment = .@"4",
        .fixed = true,
    }));
    coff.nodes.appendAssumeCapacity(.coff_header);
    {
        const coff_header = coff.headerPtr();
        coff_header.* = .{
            .machine = machine,
            .number_of_sections = 0,
            .time_date_stamp = timestamp,
            .pointer_to_symbol_table = 0,
            .number_of_symbols = 0,
            .size_of_optional_header = optional_header_size + data_directories_size,
            .flags = .{
                .RELOCS_STRIPPED = is_image,
                .EXECUTABLE_IMAGE = is_image,
                .DEBUG_STRIPPED = true,
                .@"32BIT_MACHINE" = magic == .PE32,
                .LARGE_ADDRESS_AWARE = magic == .@"PE32+",
                .DLL = comp.config.output_mode == .Lib and comp.config.link_mode == .dynamic,
            },
        };
        if (target_endian != native_endian) std.mem.byteSwapAllFields(std.coff.Header, coff_header);
    }

    const optional_header_ni = Node.known.optional_header;
    assert(optional_header_ni == try coff.mf.addLastChildNode(gpa, coff_parent_ni, .{
        .size = optional_header_size,
        .alignment = .@"4",
        .fixed = true,
    }));
    coff.nodes.appendAssumeCapacity(.optional_header);
    if (is_image) {
        coff.targetStore(&coff.optionalHeaderStandardPtr().magic, magic);
        switch (coff.optionalHeaderPtr()) {
            .PE32 => |optional_header| {
                optional_header.* = .{
                    .standard = .{
                        .magic = .PE32,
                        .major_linker_version = 0,
                        .minor_linker_version = 0,
                        .size_of_code = 0,
                        .size_of_initialized_data = 0,
                        .size_of_uninitialized_data = 0,
                        .address_of_entry_point = 0,
                        .base_of_code = 0,
                    },
                    .base_of_data = 0,
                    .image_base = switch (coff.base.comp.config.output_mode) {
                        .Exe => 0x400000,
                        .Lib => switch (coff.base.comp.config.link_mode) {
                            .static => 0,
                            .dynamic => 0x10000000,
                        },
                        .Obj => 0,
                    },
                    .section_alignment = @intCast(section_align.toByteUnits()),
                    .file_alignment = @intCast(file_align.toByteUnits()),
                    .major_operating_system_version = 6,
                    .minor_operating_system_version = 0,
                    .major_image_version = 0,
                    .minor_image_version = 0,
                    .major_subsystem_version = major_subsystem_version,
                    .minor_subsystem_version = minor_subsystem_version,
                    .win32_version_value = 0,
                    .size_of_image = 0,
                    .size_of_headers = 0,
                    .checksum = 0,
                    .subsystem = subsystem,
                    .dll_flags = .{
                        .HIGH_ENTROPY_VA = true,
                        .DYNAMIC_BASE = true,
                        .TERMINAL_SERVER_AWARE = true,
                        .NX_COMPAT = true,
                    },
                    .size_of_stack_reserve = default_size_of_stack_reserve,
                    .size_of_stack_commit = default_size_of_stack_commit,
                    .size_of_heap_reserve = default_size_of_heap_reserve,
                    .size_of_heap_commit = default_size_of_heap_commit,
                    .loader_flags = 0,
                    .number_of_rva_and_sizes = std.coff.IMAGE.DIRECTORY_ENTRY.len,
                };
                if (target_endian != native_endian)
                    std.mem.byteSwapAllFields(std.coff.OptionalHeader.PE32, optional_header);
            },
            .@"PE32+" => |optional_header| {
                optional_header.* = .{
                    .standard = .{
                        .magic = .@"PE32+",
                        .major_linker_version = 0,
                        .minor_linker_version = 0,
                        .size_of_code = 0,
                        .size_of_initialized_data = 0,
                        .size_of_uninitialized_data = 0,
                        .address_of_entry_point = 0,
                        .base_of_code = 0,
                    },
                    .image_base = switch (coff.base.comp.config.output_mode) {
                        .Exe => 0x140000000,
                        .Lib => switch (coff.base.comp.config.link_mode) {
                            .static => 0,
                            .dynamic => 0x180000000,
                        },
                        .Obj => 0,
                    },
                    .section_alignment = @intCast(section_align.toByteUnits()),
                    .file_alignment = @intCast(file_align.toByteUnits()),
                    .major_operating_system_version = 6,
                    .minor_operating_system_version = 0,
                    .major_image_version = 0,
                    .minor_image_version = 0,
                    .major_subsystem_version = major_subsystem_version,
                    .minor_subsystem_version = minor_subsystem_version,
                    .win32_version_value = 0,
                    .size_of_image = 0,
                    .size_of_headers = 0,
                    .checksum = 0,
                    .subsystem = subsystem,
                    .dll_flags = .{
                        .HIGH_ENTROPY_VA = true,
                        .DYNAMIC_BASE = true,
                        .TERMINAL_SERVER_AWARE = true,
                        .NX_COMPAT = true,
                    },
                    .size_of_stack_reserve = default_size_of_stack_reserve,
                    .size_of_stack_commit = default_size_of_stack_commit,
                    .size_of_heap_reserve = default_size_of_heap_reserve,
                    .size_of_heap_commit = default_size_of_heap_commit,
                    .loader_flags = 0,
                    .number_of_rva_and_sizes = std.coff.IMAGE.DIRECTORY_ENTRY.len,
                };
                if (target_endian != native_endian)
                    std.mem.byteSwapAllFields(std.coff.OptionalHeader.@"PE32+", optional_header);
            },
        }
    }

    const data_directories_ni = Node.known.data_directories;
    assert(data_directories_ni == try coff.mf.addLastChildNode(gpa, coff_parent_ni, .{
        .size = data_directories_size,
        .alignment = .@"4",
        .fixed = true,
    }));
    coff.nodes.appendAssumeCapacity(.data_directories);
    if (is_image) {
        const data_directories = coff.dataDirectorySlice();
        @memset(data_directories, .{ .virtual_address = 0, .size = 0 });
        if (target_endian != native_endian) std.mem.byteSwapAllFields(
            [std.coff.IMAGE.DIRECTORY_ENTRY.len]std.coff.ImageDataDirectory,
            data_directories,
        );
    }

    const section_table_ni = Node.known.section_table;
    assert(section_table_ni == try coff.mf.addLastChildNode(gpa, coff_parent_ni, .{
        .alignment = .@"4",
        .fixed = true,
    }));
    coff.nodes.appendAssumeCapacity(.section_table);

    assert(coff.nodes.len == Node.known_count);

    if (!is_image) {
        // TODO: These two nodes could be inside one movable node?
        coff.symbol_table.ni = try coff.mf.addLastChildNode(gpa, coff_parent_ni, .{
            .alignment = .@"2",
            .fixed = true,
            .moved = true,
        });
        coff.nodes.appendAssumeCapacity(.symbol_table);

        coff.symbol_table.strings_ni = try coff.mf.addLastChildNode(gpa, coff_parent_ni, .{
            .size = @sizeOf(u32),
            .fixed = true,
            .resized = true,
        });
        coff.nodes.appendAssumeCapacity(.string_table);
        coff.targetStore(coff.symbolTableStringLenPtr(), @sizeOf(u32));
    }

    try coff.symbols.ensureTotalCapacity(gpa, Symbol.Index.known_count);
    assert(coff.addSymbolAssumeCapacity() == .null);

    // TODO: How do we tell MappedFile not to allocate physical space for .bss?
    // TODO: Could have a node flag 'virtual' that can never have slice* or fileLocation called on it
    // TODO: Instead of it's own section, place .bss as a pseudo-section at the end of .text in the extra space
    assert(try coff.addSection(.@".bss", .{
        .CNT_UNINITIALIZED_DATA = true,
        .MEM_READ = true,
        .MEM_WRITE = true,
    }) == .bss);
    assert(try coff.addSection(.@".data", .{
        .CNT_INITIALIZED_DATA = true,
        .MEM_READ = true,
        .MEM_WRITE = true,
    }) == .data);
    assert(try coff.addSection(.@".rdata", .{
        .CNT_INITIALIZED_DATA = true,
        .MEM_READ = true,
    }) == .rdata);
    assert(try coff.addSection(.@".text", .{
        .CNT_CODE = true,
        .MEM_EXECUTE = true,
        .MEM_READ = true,
    }) == .text);

    if (is_image) {
        if (comp.config.link_libc and target.abi == .msvc) {
            // This section contains a function pointer table used by control flow guard:
            // https://learn.microsoft.com/en-us/windows/win32/secbp/control-flow-guard
            // The page containing it is set to PAGE_READONLY during startup, so this can't
            // be merged into .data this protection would overlap writable memory.
            _ = try coff.addSection(.@".fptable", .{
                .CNT_INITIALIZED_DATA = true,
                .MEM_READ = true,
                .MEM_WRITE = true,
            });
        }

        // TODO: Lazily initialize this instead, avoid the extra logic for this in flushMoved / flushResized
        coff.import_table.ni = try coff.mf.addLastChildNode(
            gpa,
            (try coff.objectSectionMapIndex(
                .@".idata",
                coff.mf.flags.block_size,
                .{ .read = true, .initialized = true },
            )).symbol(coff).node(coff),
            .{ .alignment = .@"4" },
        );
        coff.nodes.appendAssumeCapacity(.import_directory_table);

        coff.export_table.ni = (try coff.pseudoSectionMapIndex(
            .@".edata",
            .of(std.coff.ExportDirectoryTable),
            .{ .read = true, .initialized = true },
        )).symbol(coff).node(coff);

        coff.export_table.export_directory_table_ni = try coff.mf.addLastChildNode(
            gpa,
            coff.export_table.ni,
            .{
                .size = @sizeOf(std.coff.ExportDirectoryTable) + file_name.len + 1,
                .moved = true,
                .fixed = true,
            },
        );
        coff.nodes.appendAssumeCapacity(.export_directory_table);

        const name_index = @sizeOf(std.coff.ExportDirectoryTable);
        const table_slice = coff.export_table.export_directory_table_ni.slice(&coff.mf);
        @memcpy(table_slice[name_index..][0..file_name.len], file_name[0..file_name.len]);
        @memset(table_slice[name_index + file_name.len ..], 0);

        const export_address_table_ni = try coff.mf.addLastChildNode(gpa, coff.export_table.ni, .{
            .alignment = .of(std.coff.ExportAddressTableEntry),
            .moved = true,
        });
        coff.nodes.appendAssumeCapacity(.export_address_table);

        try coff.symbols.ensureUnusedCapacity(gpa, 1);
        coff.export_table.export_address_table_si = coff.addSymbolAssumeCapacity();

        const export_address_table_sym = coff.export_table.export_address_table_si.get(coff);
        export_address_table_sym.ni = export_address_table_ni;
        assert(export_address_table_sym.loc_relocs == .none);
        export_address_table_sym.loc_relocs = @enumFromInt(coff.relocs.items.len);
        export_address_table_sym.section_number =
            coff.getNode(coff.export_table.ni).pseudo_section.symbol(coff).get(coff).section_number;

        coff.export_table.name_pointer_table_ni = try coff.mf.addLastChildNode(gpa, coff.export_table.ni, .{
            .alignment = .of(std.coff.ExportNamePointerTableEntry),
            .moved = true,
        });
        coff.nodes.appendAssumeCapacity(.export_name_pointer_table);

        coff.export_table.ordinal_table_ni = try coff.mf.addLastChildNode(gpa, coff.export_table.ni, .{
            .alignment = .of(std.coff.ExportOrdinalTableEntry),
            .moved = true,
        });
        coff.nodes.appendAssumeCapacity(.export_ordinal_table);

        coff.export_table.name_table_ni = try coff.mf.addLastChildNode(gpa, coff.export_table.ni, .{
            .alignment = .of(u8),
            .moved = true,
        });
        coff.nodes.appendAssumeCapacity(.export_name_table);

        const export_directory_table = coff.exportDirectoryTable();
        export_directory_table.* = .{
            .flags = 0,
            .time_date_stamp = timestamp,
            .major_version = 0,
            .minor_version = 0,
            .name_rva = 0,
            .ordinal_base = 1,
            .number_of_entries = 0,
            .number_of_names = 0,
            .export_address_table_rva = 0,
            .name_pointer_table_rva = 0,
            .ordinal_table_rva = 0,
        };
        if (target_endian != native_endian)
            std.mem.byteSwapAllFields(std.coff.ExportDirectoryTable, export_directory_table);
    }

    if (comp.config.any_non_single_threaded) {
        if (!is_image)
            _ = try coff.addSection(.@".tls$", .{
                .CNT_INITIALIZED_DATA = true,
                .MEM_READ = true,
                .MEM_WRITE = true,
            });

        // While tls variables allocated at runtime are writable, the template itself is not.
        // In images, the template is in a .tls pseudo section in .rdata.
        // In objects / archives, this section is part of the above .tls$ section. The suffix
        // is maintained so merging can occur with other input tls symbols when linked later.
        _ = try coff.pseudoSectionMapIndex(
            if (is_image) .@".tls" else .@".tls$",
            coff.mf.flags.block_size,
            .{ .read = true, .write = !is_image, .initialized = true },
        );
    }
}

pub fn initBuiltins(coff: *Coff) !void {
    const comp = coff.base.comp;
    const gpa = comp.gpa;
    const target = &comp.root_mod.resolved_target.result;
    if (coff.isImage()) {
        const si = try coff.globalSymbol(.{ .name = "__ImageBase", .type = .data });
        const sym = si.get(coff);
        sym.ni = Node.known.header;
    }

    defer coff.flushSectionMerges() catch unreachable;
    if (coff.isImage() and target.isMinGW() and comp.config.link_libc) {
        try coff.symbols.ensureUnusedCapacity(gpa, 8);
        try coff.globals.ensureUnusedCapacity(gpa, 2);
        try coff.nodes.ensureUnusedCapacity(gpa, 8);
        try coff.section_merges.ensureUnusedCapacity(gpa, 2);

        const lists: []const struct { global: []const u8, start: String, end: String } = &.{
            .{ .global = "__CTOR_LIST__", .start = .@".ctors", .end = .@".ctors$ZZZ" },
            .{ .global = "__DTOR_LIST__", .start = .@".dtors", .end = .@".dtors$ZZZ" },
        };

        // We need to explicitly merge these into .rdata as in objects they can be marked
        // as MEM_WRITE, and would have mismatced section flags.
        try coff.section_merges.put(gpa, .@".ctors", .@".rdata");
        try coff.section_merges.put(gpa, .@".dtors", .@".rdata");

        for (lists) |list| {
            const addr_info = coff.targetAddrInfo();

            // Any .(c|d)tor$(.*) input sections will merge in between these sections
            const start_osmi = try coff.objectSectionMapIndex(
                list.start,
                addr_info.alignment,
                .{ .read = true, .initialized = true },
            );
            const end_osmi = try coff.objectSectionMapIndex(
                list.end,
                addr_info.alignment,
                .{ .read = true, .initialized = true },
            );

            // Additional nodes are used here, instead of just adding the sentinel
            // directly to the section data, since once input sections are added
            // as children, they would overwrite that data.
            const start_sym = start_osmi.symbol(coff).get(coff);
            const list_len_si = try coff.globalSymbol(.{ .name = list.global, .type = .data });
            const list_len_sym = list_len_si.get(coff);
            list_len_sym.setExtra(.{ .size = addr_info.size });
            list_len_sym.ni = try coff.mf.addFirstChildNode(gpa, start_sym.ni, .{
                .size = addr_info.size,
                .fixed = true,
            });
            coff.nodes.appendAssumeCapacity(.{ .builtin = list_len_si });
            list_len_sym.section_number = start_sym.section_number;

            const start_slice = list_len_sym.ni.slice(&coff.mf);
            switch (addr_info.magic) {
                _ => unreachable,
                inline .PE32, .@"PE32+" => |t| {
                    const addr: *TargetAddr(t) = @ptrCast(@alignCast(start_slice));
                    // For __CTOR_LIST__ -1 indicates that the list is null terminated.
                    // For __DTOR_LIST__, this value is ignored, the list is always null terminated
                    coff.targetStore(addr, std.math.maxInt(TargetAddr(t)));
                },
            }

            const end_sym = end_osmi.symbol(coff).get(coff);
            const list_end_si = coff.addSymbolAssumeCapacity();
            const list_end_sym = list_end_si.get(coff);
            list_end_sym.setExtra(.{ .size = addr_info.size });
            list_end_sym.ni = try coff.mf.addFirstChildNode(gpa, end_sym.ni, .{
                .size = addr_info.size,
                .fixed = true,
            });
            coff.nodes.appendAssumeCapacity(.{ .builtin = list_end_si });
            list_end_sym.section_number = start_sym.section_number;

            @memset(list_end_sym.ni.slice(&coff.mf), 0);

            try list_len_si.flushMoved(coff);
            try list_end_si.flushMoved(coff);
        }
    }
}

pub fn startProgress(coff: *Coff, prog_node: std.Progress.Node) void {
    prog_node.increaseEstimatedTotalItems(3);
    coff.const_prog_node = prog_node.start("Constants", coff.pending_uavs.count());
    coff.synth_prog_node = prog_node.start("Synthetics", count: {
        var count =
            coff.globals.count() - coff.global_pending_index +
            coff.section_merges.count() - coff.section_merge_pending_index;

        for (&coff.lazy.values) |*lazy| count += lazy.map.count() - lazy.pending_index;
        break :count count;
    });
    if (!isImage(coff)) {
        prog_node.increaseEstimatedTotalItems(2);
        coff.symbol_prog_node = prog_node.start(
            "Symbols",
            coff.symbol_table.symbols.count() - coff.symbol_table.pending_symbol_index,
        );
        coff.member_prog_node = prog_node.start("Members", coff.pending_members.count());
    }
    coff.input_prog_node = prog_node.start(
        "Inputs",
        coff.input_sections.items.len - coff.input_section_pending_index,
    );
    coff.mf.update_prog_node = prog_node.start("Relocations", coff.mf.updates.items.len);
}

pub fn endProgress(coff: *Coff) void {
    coff.mf.update_prog_node.end();
    coff.mf.update_prog_node = .none;
    coff.input_prog_node.end();
    coff.input_prog_node = .none;
    if (!coff.isImage()) {
        coff.member_prog_node.end();
        coff.member_prog_node = .none;
        coff.symbol_prog_node.end();
        coff.symbol_prog_node = .none;
    }
    coff.synth_prog_node.end();
    coff.synth_prog_node = .none;
    coff.const_prog_node.end();
    coff.const_prog_node = .none;
}

fn getNode(coff: *const Coff, ni: MappedFile.Node.Index) Node {
    return coff.nodes.get(@intFromEnum(ni));
}
fn computeNodeRva(coff: *Coff, ni: MappedFile.Node.Index) u32 {
    const parent_rva = parent_rva: {
        const parent_si = switch (coff.getNode(ni.parent(&coff.mf))) {
            .file,
            .header,
            .signature,
            .archive_member_header,
            .archive_member,
            .coff_header,
            .optional_header,
            .data_directories,
            .section_table,
            .export_name_table,
            .placeholder,
            .symbol_table,
            .string_table,
            .relocation_table,
            .relocation_table_entry,
            .input_section,
            .builtin,
            => unreachable,
            .image_section => |si| si,
            .import_directory_table => break :parent_rva coff.targetLoad(
                &coff.dataDirectoryPtr(.IMPORT).virtual_address,
            ),
            .import_lookup_table => |import_index| break :parent_rva coff.targetLoad(
                &coff.importDirectoryEntryPtr(import_index).import_lookup_table_rva,
            ),
            .import_address_table => |import_index| break :parent_rva coff.targetLoad(
                &coff.importDirectoryEntryPtr(import_index).import_address_table_rva,
            ),
            .import_hint_name_table => |import_index| break :parent_rva coff.targetLoad(
                &coff.importDirectoryEntryPtr(import_index).name_rva,
            ),
            .export_directory_table => break :parent_rva coff.targetLoad(
                &coff.dataDirectoryPtr(.EXPORT).virtual_address,
            ),
            .export_address_table => break :parent_rva coff.targetLoad(
                &coff.exportDirectoryTable().export_address_table_rva,
            ),
            .export_name_pointer_table => break :parent_rva coff.targetLoad(
                &coff.exportDirectoryTable().name_pointer_table_rva,
            ),
            .export_ordinal_table => break :parent_rva coff.targetLoad(
                &coff.exportDirectoryTable().ordinal_table_rva,
            ),
            inline .pseudo_section,
            .object_section,
            .import_thunk,
            .nav,
            .uav,
            .lazy_code,
            .lazy_const_data,
            => |mi| mi.symbol(coff),
        };
        break :parent_rva parent_si.get(coff).rva;
    };
    const offset, _ = ni.location(&coff.mf).resolve(&coff.mf);
    return @intCast(parent_rva + offset);
}

fn computeSymbolSectionOffset(
    coff: *Coff,
    sym: *const Symbol,
    relative_to: enum { image, pseudo },
) u32 {
    var section_offset: u32 = sym.nodeOffset(coff);
    var parent_ni = sym.ni;
    while (true) {
        const offset, _ = parent_ni.location(&coff.mf).resolve(&coff.mf);
        section_offset += @intCast(offset);
        parent_ni = parent_ni.parent(&coff.mf);
        switch (coff.getNode(parent_ni)) {
            else => unreachable,
            .image_section => break,
            .pseudo_section => if (relative_to == .pseudo) break,
            .object_section,
            => {},
        }
    }

    return section_offset;
}

pub inline fn targetEndian(_: *const Coff) std.lang.Endian {
    return .little;
}

fn targetAddrInfo(coff: *Coff) struct {
    size: u8,
    alignment: std.mem.Alignment,
    magic: std.coff.OptionalHeader.Magic,
} {
    const magic = coff.targetLoad(&coff.optionalHeaderStandardPtr().magic);
    switch (magic) {
        _ => unreachable,
        .PE32 => return .{ .size = 4, .alignment = .@"4", .magic = magic },
        .@"PE32+" => return .{ .size = 8, .alignment = .@"8", .magic = magic },
    }
}

fn TargetAddr(comptime magic: std.coff.OptionalHeader.Magic) type {
    return switch (magic) {
        _ => comptime unreachable,
        .PE32 => u32,
        .@"PE32+" => u64,
    };
}

fn targetLoad(coff: *const Coff, ptr: anytype) @typeInfo(@TypeOf(ptr)).pointer.child {
    const Child = @typeInfo(@TypeOf(ptr)).pointer.child;
    return switch (@typeInfo(Child)) {
        else => @compileError(@typeName(Child)),
        .int => std.mem.toNative(Child, ptr.*, coff.targetEndian()),
        .@"enum" => |@"enum"| @enumFromInt(coff.targetLoad(@as(*@"enum".tag_type, @ptrCast(ptr)))),
        .@"struct" => |@"struct"| @bitCast(
            coff.targetLoad(@as(*@"struct".backing_integer.?, @ptrCast(ptr))),
        ),
    };
}
fn targetStore(coff: *const Coff, ptr: anytype, val: @typeInfo(@TypeOf(ptr)).pointer.child) void {
    const Child = @typeInfo(@TypeOf(ptr)).pointer.child;
    return switch (@typeInfo(Child)) {
        else => @compileError(@typeName(Child)),
        .int => ptr.* = std.mem.nativeTo(Child, val, coff.targetEndian()),
        .@"enum" => |@"enum"| coff.targetStore(
            @as(*@"enum".tag_type, @ptrCast(ptr)),
            @intFromEnum(val),
        ),
        .@"struct" => |@"struct"| coff.targetStore(
            @as(*@"struct".backing_integer.?, @ptrCast(ptr)),
            @bitCast(val),
        ),
    };
}

pub fn headerPtr(coff: *Coff) *std.coff.Header {
    assert(coff.hasCoffHeader());
    return @ptrCast(@alignCast(Node.known.coff_header.slice(&coff.mf)));
}

pub fn firstLinkerMemberNumSymbolsPtr(coff: *Coff) *u32 {
    assert(coff.isArchive());
    return @ptrCast(@alignCast(Node.known.first_linker_member.slice(&coff.mf)));
}

pub fn firstLinkerMemberOffsetsSlice(coff: *Coff) []u32 {
    const len = std.mem.toNative(u32, coff.firstLinkerMemberNumSymbolsPtr().*, .big);
    return @ptrCast(@alignCast(Node.known.first_linker_member.slice(&coff.mf)[@sizeOf(u32)..][0 .. len * @sizeOf(u32)]));
}

pub fn secondLinkerMemberNumMembersPtr(coff: *Coff) *align(2) u32 {
    assert(coff.isArchive());
    return @ptrCast(@alignCast(Node.known.second_linker_member.slice(&coff.mf)));
}

pub fn secondLinkerMemberOffsetsSlice(coff: *Coff) []align(2) u32 {
    const num_members = coff.targetLoad(coff.secondLinkerMemberNumMembersPtr());
    return @ptrCast(@alignCast(
        Node.known.second_linker_member.slice(&coff.mf)[@sizeOf(u32)..][0 .. num_members * @sizeOf(u32)],
    ));
}

pub fn secondLinkerMemberNumSymbolsPtr(coff: *Coff) *align(2) u32 {
    const num_members = coff.targetLoad(coff.secondLinkerMemberNumMembersPtr());
    return @ptrCast(@alignCast(
        Node.known.second_linker_member.slice(&coff.mf)[(1 + num_members) * @sizeOf(u32) ..],
    ));
}

pub fn secondLinkerMemberIndicesSlice(coff: *Coff) []u16 {
    const num_members = coff.targetLoad(coff.secondLinkerMemberNumMembersPtr());
    const num_symbols = coff.targetLoad(coff.secondLinkerMemberNumSymbolsPtr());
    return @ptrCast(@alignCast(
        Node.known.second_linker_member.slice(&coff.mf)[(2 + num_members) * @sizeOf(u32) ..][0 .. num_symbols * @sizeOf(u16)],
    ));
}

pub fn secondLinkerMemberStringsSlice(coff: *Coff) []u8 {
    const num_members = coff.targetLoad(coff.secondLinkerMemberNumMembersPtr());
    const num_symbols = coff.targetLoad(coff.secondLinkerMemberNumSymbolsPtr());
    return @ptrCast(@alignCast(
        Node.known.second_linker_member.slice(&coff.mf)[(2 + num_members) * @sizeOf(u32) + num_symbols * @sizeOf(u16) ..],
    ));
}

pub fn optionalHeaderStandardPtr(coff: *Coff) *std.coff.OptionalHeader {
    return @ptrCast(@alignCast(
        Node.known.optional_header.slice(&coff.mf)[0..@sizeOf(std.coff.OptionalHeader)],
    ));
}

pub const OptionalHeaderPtr = union(std.coff.OptionalHeader.Magic) {
    PE32: *std.coff.OptionalHeader.PE32,
    @"PE32+": *std.coff.OptionalHeader.@"PE32+",
};
pub fn optionalHeaderPtr(coff: *Coff) OptionalHeaderPtr {
    assert(coff.isImage());
    const slice = Node.known.optional_header.slice(&coff.mf);
    return switch (coff.targetLoad(&coff.optionalHeaderStandardPtr().magic)) {
        _ => unreachable,
        inline else => |magic| @unionInit(
            OptionalHeaderPtr,
            @tagName(magic),
            @ptrCast(@alignCast(slice)),
        ),
    };
}
pub fn optionalHeaderField(
    coff: *Coff,
    comptime field: std.meta.FieldEnum(std.coff.OptionalHeader.@"PE32+"),
) @FieldType(std.coff.OptionalHeader.@"PE32+", @tagName(field)) {
    assert(coff.isImage());
    return switch (coff.optionalHeaderPtr()) {
        inline else => |optional_header| coff.targetLoad(&@field(optional_header, @tagName(field))),
    };
}

pub fn dataDirectorySlice(
    coff: *Coff,
) *[std.coff.IMAGE.DIRECTORY_ENTRY.len]std.coff.ImageDataDirectory {
    assert(coff.isImage());
    return @ptrCast(@alignCast(Node.known.data_directories.slice(&coff.mf)));
}
pub fn dataDirectoryPtr(
    coff: *Coff,
    entry: std.coff.IMAGE.DIRECTORY_ENTRY,
) *std.coff.ImageDataDirectory {
    return &coff.dataDirectorySlice()[@intFromEnum(entry)];
}

pub fn sectionTableSlice(coff: *Coff) []std.coff.SectionHeader {
    return @ptrCast(@alignCast(
        Node.known.section_table.slice(&coff.mf)[0 .. coff.section_table.count() * @sizeOf(std.coff.SectionHeader)],
    ));
}

pub fn symbolTableEntryStoragePtr(coff: *Coff, index: u32) *[std.coff.Symbol.sizeOf()]u8 {
    assert(!coff.isImage());
    const offset = index * std.coff.Symbol.sizeOf();
    return @ptrCast(@alignCast(coff.symbol_table.ni.slice(&coff.mf)[offset..][0..std.coff.Symbol.sizeOf()]));
}

pub fn symbolTableEntryPtr(coff: *Coff, sti: SymbolTable.Index) ?*align(2) std.coff.Symbol {
    if (sti.unwrap()) |index|
        return @ptrCast(@alignCast(symbolTableEntryStoragePtr(coff, index)))
    else
        return null;
}

pub fn symbolTableSectionAuxEntryPtr(coff: *Coff, sti: SymbolTable.Index) ?*align(2) std.coff.SectionDefinition {
    if (symbolTableEntryPtr(coff, sti)) |entry| {
        assert(entry.storage_class == .STATIC and entry.number_of_aux_symbols == 1);
        return @ptrCast(@alignCast(symbolTableEntryStoragePtr(coff, sti.unwrap().? + 1)));
    } else {
        return null;
    }
}

pub fn symbolTableWeakExternalAuxEntryPtr(coff: *Coff, sti: SymbolTable.Index) ?*align(2) std.coff.WeakExternalDefinition {
    if (symbolTableEntryPtr(coff, sti)) |entry| {
        assert(entry.storage_class == .WEAK_EXTERNAL and entry.number_of_aux_symbols == 1);
        return @ptrCast(@alignCast(symbolTableEntryStoragePtr(coff, sti.unwrap().? + 1)));
    } else {
        return null;
    }
}

pub fn symbolTableStringLenPtr(coff: *Coff) *align(1) u32 {
    return @ptrCast(@alignCast(coff.symbol_table.strings_ni.slice(&coff.mf)[0..@sizeOf(u32)]));
}

pub fn importDirectoryTableSlice(coff: *Coff) []std.coff.ImportDirectoryEntry {
    assert(coff.isImage());
    return @ptrCast(@alignCast(coff.import_table.ni.slice(&coff.mf)));
}
pub fn importDirectoryEntryPtr(
    coff: *Coff,
    import_index: ImportTable.Index,
) *std.coff.ImportDirectoryEntry {
    return &coff.importDirectoryTableSlice()[@intFromEnum(import_index)];
}

pub fn exportDirectoryTable(coff: *Coff) *std.coff.ExportDirectoryTable {
    return @ptrCast(@alignCast(coff.export_table.export_directory_table_ni.slice(&coff.mf)));
}

pub fn exportNamePointerTableSlice(coff: *Coff) []std.coff.ExportNamePointerTableEntry {
    const debug = coff.export_table.name_pointer_table_ni.slice(&coff.mf);
    _ = debug;

    return @ptrCast(@alignCast(coff.export_table.name_pointer_table_ni.slice(&coff.mf)));
}

pub fn exportOrdinalTableSlice(coff: *Coff) []std.coff.ExportOrdinalTableEntry {
    return @ptrCast(@alignCast(coff.export_table.ordinal_table_ni.slice(&coff.mf)));
}

fn addSymbolAssumeCapacity(coff: *Coff) Symbol.Index {
    defer coff.symbols.addOneAssumeCapacity().* = .{
        .ni = .none,
        .rva = 0,
        .value = .{ .none = {} },
        .extra = .{ .size = 0 },
        .flags = .{
            .value_tag = .none,
            .extra_tag = .size,
            .type = .unknown,
            .dll_storage_class = .default,
            .weak_external_strat = .none,
        },
        .loc_relocs = .none,
        .target_relocs = .none,
        .section_number = .UNDEFINED,
        .gmi = .none,
    };
    return @enumFromInt(coff.symbols.items.len);
}

fn initSymbolAssumeCapacity(coff: *Coff) !Symbol.Index {
    const si = coff.addSymbolAssumeCapacity();
    return si;
}

fn getOrPutString(coff: *Coff, string: []const u8) !String {
    try coff.ensureUnusedStringCapacity(string.len);
    return coff.getOrPutStringAssumeCapacity(string);
}
fn getOrPutOptionalString(coff: *Coff, string: ?[]const u8) !String.Optional {
    return (try coff.getOrPutString(string orelse return .none)).toOptional();
}
fn getString(coff: *Coff, string: []const u8) String.Optional {
    if (coff.strings.getKeyAdapted(
        string,
        std.hash_map.StringIndexAdapter{ .bytes = &coff.string_bytes },
    )) |key|
        return @as(String, @enumFromInt(key)).toOptional()
    else
        return .none;
}

/// If the name does not fit in the symbol header, adds it to the symbol table string table.
/// If the caller knows this name already has a String associated with it, they can avoid
/// a redundant call to `getOrPutString` by specifying `opt_string`.
/// The lifetime of the return value matches that of `name`.
fn getOrPutSymbolName(coff: *Coff, name: []const u8, opt_string: ?String) !SymbolTable.SymbolName {
    assert(!coff.isImage());
    const gpa = coff.base.comp.gpa;

    return if (name.len > header_name_max_len) name: {
        const string = opt_string orelse try coff.getOrPutString(name);
        const string_gop = try coff.symbol_table.strings.getOrPut(gpa, string);
        if (!string_gop.found_existing) {
            const string_index = coff.symbol_table.strings_ni.location(&coff.mf).resolve(&coff.mf)[1];
            string_gop.value_ptr.* = @enumFromInt(string_index);

            try coff.symbol_table.strings_ni.resize(&coff.mf, gpa, string_index + name.len + 1);
            const slice = coff.symbol_table.strings_ni.slice(&coff.mf);
            @memcpy(slice[@intCast(string_index)..][0..name.len], name);
            slice[@intCast(string_index + name.len)] = 0;
        }

        break :name .{ .long = string_gop.value_ptr.* };
    } else .{ .short = name };
}

/// `len` does not include null terminators
fn ensureUnusedStringCapacity(coff: *Coff, len: usize) !void {
    const gpa = coff.base.comp.gpa;
    try coff.strings.ensureUnusedCapacityContext(gpa, 1, .{ .bytes = &coff.string_bytes });
    try coff.string_bytes.ensureUnusedCapacity(gpa, len + 1);
}

/// `total_len` includes null terminators
fn ensureManyUnusedStringCapacity(coff: *Coff, num_strings: u32, total_len: usize) !void {
    const gpa = coff.base.comp.gpa;
    try coff.strings.ensureUnusedCapacityContext(gpa, num_strings, .{ .bytes = &coff.string_bytes });
    try coff.string_bytes.ensureUnusedCapacity(gpa, total_len + num_strings);
}

fn getOrPutStringAssumeCapacity(coff: *Coff, string: []const u8) String {
    const gop = coff.strings.getOrPutAssumeCapacityAdapted(
        string,
        std.hash_map.StringIndexAdapter{ .bytes = &coff.string_bytes },
    );
    if (!gop.found_existing) {
        gop.key_ptr.* = @intCast(coff.string_bytes.items.len);
        gop.value_ptr.* = {};
        coff.string_bytes.appendSliceAssumeCapacity(string);
        coff.string_bytes.appendAssumeCapacity(0);
    }
    return @enumFromInt(gop.key_ptr.*);
}

const GlobalOptions = struct {
    name: []const u8,
    lib_name: ?[]const u8 = null,
    type: Symbol.Type = .unknown,
    dll_storage_class: Symbol.DllStorageClass = .default,
};

fn getOrPutGlobalSymbol(
    coff: *Coff,
    opts: GlobalOptions,
) !std.array_hash_map.Auto(String, Global).GetOrPutResult {
    const comp = coff.base.comp;
    const gpa = comp.gpa;
    try coff.symbols.ensureUnusedCapacity(gpa, 1);

    const lib_name: String.Optional = if (opts.lib_name) |lib_name| lib_name: {
        const is_libc = std.zig.target.isLibCLibName(&comp.root_mod.resolved_target.result, lib_name);
        if (is_libc) {
            // This is guaranteed by Sema.handleExternLibName
            if (!comp.config.link_libc) unreachable;

            // TODO: The user has requested this symbol come from libc, but this logic allows
            //       it to come from anywhere. We need to know what inputs are libc inputs,
            //       and set a flag to only search them for this symbol.
            break :lib_name .none;
        }

        break :lib_name (try coff.getOrPutString(lib_name)).toOptional();
    } else .none;

    const sym_gop = try coff.globals.getOrPut(gpa, try coff.getOrPutString(opts.name));
    if (!sym_gop.found_existing) {
        const si = coff.addSymbolAssumeCapacity();
        const sym = si.get(coff);
        sym.gmi = .wrap(@intCast(sym_gop.index));
        sym.flags.type = opts.type;
        sym.flags.dll_storage_class = opts.dll_storage_class;
        sym_gop.value_ptr.* = .{
            .si = si,
            .lib_name = lib_name,
        };
        coff.synth_prog_node.increaseEstimatedTotalItems(1);

        log.debug("globalSymbol({s}, {?s}) = {d}", .{ opts.name, opts.lib_name, si });
    }

    return sym_gop;
}

fn getDefinedGlobal(coff: *Coff, name: []const u8) Symbol.Index {
    if (coff.globals.get(
        coff.getString(name).unwrap() orelse return .null,
    )) |global| if (global.si.get(coff).ni != .none) return global.si;
    return .null;
}

pub fn globalSymbol(coff: *Coff, opts: GlobalOptions) !Symbol.Index {
    const gop = try coff.getOrPutGlobalSymbol(opts);
    return gop.value_ptr.si;
}

pub fn pendingSymbolTableEntry(coff: *Coff, si: Symbol.Index) !void {
    assert(!coff.isImage());
    const sym = si.get(coff);

    assert(sym.ni != .none or sym.gmi != .none);
    const gpa = coff.base.comp.gpa;
    const gop = try coff.symbol_table.symbols.getOrPut(gpa, si);
    if (!gop.found_existing) {
        coff.symbol_prog_node.increaseEstimatedTotalItems(1);
        gop.value_ptr.* = .none;
    }
}

fn navSection(
    coff: *Coff,
    zcu: *Zcu,
    nav_resolved: @typeInfo(@FieldType(InternPool.Nav, "resolved")).optional.child,
) !Symbol.Index {
    const ip = &zcu.intern_pool;
    const default: String, const attributes: ObjectSectionAttributes =
        if (nav_resolved.@"threadlocal" and coff.base.comp.config.any_non_single_threaded) .{
            .@".tls$", .{ .read = true, .write = true, .initialized = true },
        } else if (ip.isFunctionType(nav_resolved.type)) .{
            .@".text", .{ .read = true, .execute = true },
        } else if (nav_resolved.@"const") .{
            .@".rdata", .{ .read = true, .initialized = true },
        } else .{
            .@".data", .{ .read = true, .write = true, .initialized = true },
        };

    return (try coff.objectSectionMapIndex(
        (try coff.getOrPutOptionalString(nav_resolved.@"linksection".toSlice(ip))).unwrap() orelse default,
        switch (nav_resolved.@"linksection") {
            .none => coff.mf.flags.block_size,
            else => switch (nav_resolved.@"align") {
                .none => Type.fromInterned(ip.typeOf(nav_resolved.value)).abiAlignment(zcu),
                else => |alignment| alignment,
            }.toStdMem(),
        },
        attributes,
    )).symbol(coff);
}
fn navMapIndex(coff: *Coff, zcu: *Zcu, nav_index: InternPool.Nav.Index) !Node.NavMapIndex {
    const gpa = zcu.gpa;
    try coff.symbols.ensureUnusedCapacity(gpa, 1);
    const sym_gop = try coff.navs.getOrPut(gpa, nav_index);
    if (!sym_gop.found_existing) sym_gop.value_ptr.* = coff.addSymbolAssumeCapacity();
    return @enumFromInt(sym_gop.index);
}
pub fn navSymbol(coff: *Coff, zcu: *Zcu, nav_index: InternPool.Nav.Index) !Symbol.Index {
    const ip = &zcu.intern_pool;
    const nav = ip.getNav(nav_index);
    if (nav.getExtern(ip)) |@"extern"| return coff.globalSymbol(.{
        .name = @"extern".name.toSlice(ip),
        .lib_name = @"extern".lib_name.toSlice(ip),
        // TODO: Threadlocal as well?
        .type = if (ip.isFunctionType(nav.resolved.?.type)) .code else .data,
        .dll_storage_class = if (@"extern".is_dll_import) .dllimport else .default,
    });
    const nmi = try coff.navMapIndex(zcu, nav_index);
    return nmi.symbol(coff);
}

fn uavMapIndex(coff: *Coff, uav_val: InternPool.Index) !Node.UavMapIndex {
    const gpa = coff.base.comp.gpa;
    try coff.symbols.ensureUnusedCapacity(gpa, 1);
    const sym_gop = try coff.uavs.getOrPut(gpa, uav_val);
    if (!sym_gop.found_existing) sym_gop.value_ptr.* = coff.addSymbolAssumeCapacity();
    return @enumFromInt(sym_gop.index);
}
pub fn uavSymbol(coff: *Coff, uav_val: InternPool.Index) !Symbol.Index {
    const umi = try coff.uavMapIndex(uav_val);
    return umi.symbol(coff);
}

pub fn lazySymbol(coff: *Coff, lazy: link.File.LazySymbol) !Symbol.Index {
    const gpa = coff.base.comp.gpa;
    try coff.symbols.ensureUnusedCapacity(gpa, 1);
    const sym_gop = try coff.lazy.getPtr(lazy.kind).map.getOrPut(gpa, lazy.ty);
    if (!sym_gop.found_existing) {
        sym_gop.value_ptr.* = try coff.initSymbolAssumeCapacity();
        coff.synth_prog_node.increaseEstimatedTotalItems(1);
    }
    return sym_gop.value_ptr.*;
}

pub fn getNavVAddr(
    coff: *Coff,
    pt: Zcu.PerThread,
    nav: InternPool.Nav.Index,
    reloc_info: link.File.RelocInfo,
) link.Error!u64 {
    return coff.getVAddr(reloc_info, try coff.navSymbol(pt.zcu, nav));
}

pub fn getUavVAddr(
    coff: *Coff,
    uav: InternPool.Index,
    reloc_info: link.File.RelocInfo,
) link.Error!u64 {
    return coff.getVAddr(reloc_info, try coff.uavSymbol(uav));
}

pub fn getVAddr(coff: *Coff, reloc_info: link.File.RelocInfo, target_si: Symbol.Index) link.Error!u64 {
    try coff.addReloc(
        @enumFromInt(@intFromEnum(reloc_info.parent.atom_index)),
        reloc_info.offset,
        target_si,
        .{ .known = reloc_info.addend },
        switch (coff.targetLoad(&coff.headerPtr().machine)) {
            else => unreachable,
            .AMD64 => .{ .AMD64 = .ADDR64 },
            .I386 => .{ .I386 = .DIR32 },
        },
    );

    var vaddr: u64 = target_si.get(coff).rva;
    if (coff.isImage()) vaddr += coff.optionalHeaderField(.image_base);
    return vaddr;
}

/// Caller guarantees there is capacity for one member and two nodes
fn addMemberAssumeCapacity(coff: *Coff, kind: std.coff.ArchiveMemberHeader.Kind, size: u64) !Member.Index {
    const comp = coff.base.comp;
    const gpa = comp.gpa;

    // TODO: These two nodes could to be inside a movable node if kind == .coff|.import
    const header_ni = try coff.mf.addLastChildNode(gpa, Node.known.file, .{
        .size = @sizeOf(std.coff.ArchiveMemberHeader),
        .alignment = .@"2",
        .fixed = true,
        .moved = true,
    });

    const content_ni = try coff.mf.addLastChildNode(gpa, Node.known.file, .{
        // The actual alignment required by the spec is 2, but  to allow aligned access to
        // the various COFF data structures in-place during linking we overalign
        .alignment = switch (kind) {
            .coff => .@"4",
            else => .@"2",
        },
        .size = size,
        .resized = size > 0,
        .fixed = true,
    });

    const mi: Member.Index = @enumFromInt(coff.members.items.len);
    coff.members.appendAssumeCapacity(.{
        .kind = kind,
        .header_ni = header_ni,
        .content_ni = content_ni,
        .first_linker_indices = .empty,
    });

    coff.nodes.appendAssumeCapacity(.{ .archive_member_header = mi });
    coff.nodes.appendAssumeCapacity(.{ .archive_member = mi });

    switch (kind) {
        .first_linker, .second_linker, .longnames => {},
        else => {
            const new_num_members = coff.members.items.len - Member.Index.known_count;
            coff.targetStore(
                coff.secondLinkerMemberNumMembersPtr(),
                @intCast(new_num_members),
            );

            const old_size = Node.known.second_linker_member.location(&coff.mf).resolve(&coff.mf)[1];
            const old_header_size = new_num_members * @sizeOf(u32);
            const trailing_size: usize = @intCast(old_size - old_header_size);
            try Node.known.second_linker_member.resize(&coff.mf, gpa, old_size + @sizeOf(u32));

            const slice = Node.known.second_linker_member.slice(&coff.mf);
            @memmove(
                slice[old_header_size + @sizeOf(u32) ..][0..trailing_size],
                slice[old_header_size..][0..trailing_size],
            );

            // Offset will be written by flushMoved on header_ni
        },
    }

    switch (kind) {
        .first_linker,
        .longnames,
        .import,
        => {},
        .second_linker,
        .coff,
        => {
            try coff.pending_members.ensureTotalCapacity(
                gpa,
                coff.pending_members.capacity() + 1,
            );
            coff.member_prog_node.increaseEstimatedTotalItems(1);
        },
    }

    return mi;
}

fn appendMemberSymbolString(
    coff: *Coff,
    strings_ni: MappedFile.Node.Index,
    new_size: u64,
    name: []const u8,
    offset: u64,
) !void {
    try strings_ni.resize(&coff.mf, coff.base.comp.gpa, new_size);
    const name_slice = strings_ni.slice(&coff.mf)[offset..][0 .. name.len + 1];
    @memcpy(name_slice[0..name.len], name);
    name_slice[name.len] = 0;
}

fn ensureMemberSymbol(coff: *Coff, mi: Member.Index, name: String) !void {
    const gpa = coff.base.comp.gpa;
    const member = mi.get(coff);
    assert(member.kind == .coff);

    const gop = try member.first_linker_indices.getOrPut(gpa, .{ .mi = mi, .name = name });
    if (gop.found_existing) return;

    const mfli: Member.FirstLinkerIndex = blk: {
        const num_symbols_ptr = coff.firstLinkerMemberNumSymbolsPtr();
        const num_symbols = std.mem.toNative(u32, num_symbols_ptr.*, .big);
        num_symbols_ptr.* = std.mem.nativeTo(u32, num_symbols + 1, .big);
        break :blk @enumFromInt(num_symbols);
    };

    gop.value_ptr.* = mfli;

    // Linker member fields are not modeled as nodes because MappedFile
    // can't guarantee that they will be tightly packed after resizing

    const name_slice = name.toSlice(coff);
    const new_string_table_size: u32 = @intCast(coff.lib_string_len + name_slice.len + 1);
    defer coff.lib_string_len = new_string_table_size;

    {
        const old_header_size: usize = @intCast(@sizeOf(u32) + @intFromEnum(mfli) * @sizeOf(u32));
        const new_header_size: usize = @intCast(old_header_size + @sizeOf(u32));
        try Node.known.first_linker_member.resize(&coff.mf, gpa, new_header_size + new_string_table_size);

        const slice = Node.known.first_linker_member.slice(&coff.mf);
        @memmove(slice[new_header_size..][0..coff.lib_string_len], slice[old_header_size..][0..coff.lib_string_len]);
        @memcpy(slice[new_header_size + coff.lib_string_len ..][0..name_slice.len], name_slice[0..name_slice.len]);
        slice[new_header_size + coff.lib_string_len + name_slice.len] = 0;

        // New offset entry is written in flushMember
    }

    {
        const num_members = coff.targetLoad(coff.secondLinkerMemberNumMembersPtr());
        const old_header_size = 2 * @sizeOf(u32) + num_members * @sizeOf(u32) + @intFromEnum(mfli) * @sizeOf(u16);
        const new_header_size = old_header_size + @sizeOf(u16);
        try Node.known.second_linker_member.resize(&coff.mf, gpa, new_header_size + new_string_table_size);

        const old_needs_sort = coff.pending_members.get(Member.Index.second) != null;
        const needs_sort = old_needs_sort or (if (coff.lib_string_table.items.len > 0)
            std.mem.lessThan(
                u8,
                name_slice,
                coff.lib_string_table.items[coff.lib_string_table.items.len - 1].toSlice(coff),
            )
        else
            false);

        try coff.lib_string_table.append(gpa, name);

        const slice = Node.known.second_linker_member.slice(&coff.mf);
        coff.targetStore(coff.secondLinkerMemberNumSymbolsPtr(), @intFromEnum(mfli) + 1);
        if (!needs_sort) {
            @memmove(slice[new_header_size..][0..coff.lib_string_len], slice[old_header_size..][0..coff.lib_string_len]);
            @memcpy(slice[new_header_size + coff.lib_string_len ..][0..name_slice.len], name_slice[0..name_slice.len]);
            slice[new_header_size + coff.lib_string_len + name_slice.len] = 0;
        } else if (!old_needs_sort) {
            // The entire string table is rebuilt in flushMember after sorting
            coff.pending_members.putAssumeCapacity(Member.Index.second, {});
        }

        // Indices in this table are 1-based
        const index_ptr: *u16 = @ptrCast(@alignCast(slice[old_header_size..]));
        coff.targetStore(index_ptr, @intCast(@intFromEnum(mi) - Member.Index.known_count + 1));
    }

    coff.pending_members.putAssumeCapacity(mi, {});
    coff.member_prog_node.increaseEstimatedTotalItems(1);
}

fn flushSymbolTableEntry(coff: *Coff, index: u32, pt: Zcu.PerThread) !void {
    assert(!coff.isImage());
    const gpa = coff.base.comp.gpa;

    const si = coff.symbol_table.symbols.keys()[index];
    const sti = &coff.symbol_table.symbols.values()[index];

    const sym = si.get(coff);
    assert(sym.ni != .none or sym.gmi != .none);

    const entry = coff.symbolTableEntryPtr(sti.*) orelse entry: {
        var buf: [15]u8 = undefined;
        const symbol_name, const num_aux_symbols: u8, const complex_type: std.coff.ComplexType =
            if (sym.gmi != .none) blk: {
                const name = sym.gmi.name(coff);
                break :blk .{
                    try coff.getOrPutSymbolName(name.toSlice(coff), name),
                    @intFromBool(sym.flags.weak_external_strat != .none),
                    if (Symbol.Index.text.get(coff).section_number == sym.section_number)
                        .FUNCTION
                    else
                        .NULL,
                };
            } else blk: switch (coff.getNode(sym.ni)) {
                .image_section => .{
                    try coff.getOrPutSymbolName(&sym.section_number.header(coff).name, null),
                    1,
                    .NULL,
                },
                .nav => |nmi| {
                    const zcu = coff.base.comp.zcu.?;
                    const ip = &zcu.intern_pool;
                    const nav = ip.getNav(nmi.navIndex(coff));
                    break :blk .{
                        try coff.getOrPutSymbolName(nav.fqn.toSlice(ip), null),
                        0,
                        if (ip.isFunctionType(nav.resolved.?.type)) .FUNCTION else .NULL,
                    };
                },
                .uav => |umi| {
                    var w = Io.Writer.fixed(&buf);
                    w.print("__anon_{x}", .{umi.uavValue(coff)}) catch unreachable;
                    break :blk .{
                        try coff.getOrPutSymbolName(w.buffered(), null),
                        0,
                        .NULL,
                    };
                },
                inline .lazy_code, .lazy_const_data => |mi, tag| {
                    const lazy_sym = mi.lazySymbol(coff);
                    const name = try std.fmt.allocPrint(gpa, "__lazy_{s}_{f}", .{
                        @tagName(lazy_sym.kind),
                        Type.fromInterned(lazy_sym.ty).fmt(pt),
                    });
                    defer gpa.free(name);

                    const string = try coff.getOrPutString(name);
                    break :blk .{
                        try coff.getOrPutSymbolName(string.toSlice(coff), string),
                        0,
                        if (tag == .lazy_code) .FUNCTION else .NULL,
                    };
                },
                else => {
                    log.err("TODO implement symbol table init for {s} ({d})", .{ @tagName(coff.getNode(sym.ni)), si });
                    unreachable;
                },
            };

        const old_num_symbols = coff.targetLoad(&coff.headerPtr().number_of_symbols);
        const new_num_symbols = old_num_symbols + 1 + num_aux_symbols;
        coff.targetStore(&coff.headerPtr().number_of_symbols, new_num_symbols);

        try coff.symbol_table.ni.resize(&coff.mf, gpa, new_num_symbols * std.coff.Symbol.sizeOf());

        sti.* = .wrap(old_num_symbols);
        si.flushSymbolTableIndex(coff);

        const entry = coff.symbolTableEntryPtr(sti.*).?;
        symbol_name.store(coff, &entry.name);

        entry.section_number = @enumFromInt(@intFromEnum(sym.section_number));
        entry.type = .{
            .complex_type = complex_type,
            .base_type = .NULL,
        };

        entry.storage_class = if (sym.gmi != .none)
            .EXTERNAL
        else if (sym.flags.extra_tag == .next_alias_si) storage: {
            var alias_sym = sym;
            const weak_external = while (alias_sym.flags.extra_tag == .next_alias_si) {
                const alias_si = alias_sym.extra.next_alias_si;
                alias_sym = alias_si.get(coff);
                assert(alias_sym.ni == sym.ni);
                if (alias_sym.flags.weak_external_strat != .none)
                    break true;
            } else false;
            break :storage if (weak_external) .EXTERNAL else .STATIC;
        } else .STATIC;

        entry.number_of_aux_symbols = num_aux_symbols;
        if (coff.targetEndian() != native_endian)
            std.mem.byteSwapAllFieldsAligned(std.coff.Symbol, .@"2", entry);

        if (num_aux_symbols > 0) aux_init: {
            if (sym.gmi != .none) {
                entry.section_number = .UNDEFINED;
                entry.storage_class = .WEAK_EXTERNAL;

                const tag_index = sym.value.weak_alias_si.sti(coff).unwrap().?;
                const aux_ptr = coff.symbolTableWeakExternalAuxEntryPtr(sti.*).?;
                aux_ptr.* = .{
                    .tag_index = tag_index,
                    .flag = switch (sym.flags.weak_external_strat) {
                        .none => unreachable,
                        .no_library => .SEARCH_NOLIBRARY,
                        .library => .SEARCH_LIBRARY,
                        .alias => .SEARCH_ALIAS,
                        .anti_dependency => .ANTI_DEPENDENCY,
                    },
                    .unused = @splat(0),
                };
                if (coff.targetEndian() != native_endian)
                    std.mem.byteSwapAllFieldsAligned(std.coff.WeakExternalDefinition, .@"2", aux_ptr);

                break :aux_init;
            } else switch (coff.getNode(sym.ni)) {
                .image_section => |sec_si| {
                    assert(si == sec_si);
                    const header = sym.section_number.header(coff);
                    const aux_ptr = coff.symbolTableSectionAuxEntryPtr(sti.*).?;
                    aux_ptr.* = .{
                        .length = @intCast(sym.ni.location(&coff.mf).resolve(&coff.mf)[1]),
                        .number_of_relocations = header.number_of_relocations,
                        .number_of_linenumbers = header.number_of_linenumbers,
                        .checksum = 0,
                        .number = 0,
                        .selection = .NONE,
                        .unused = @splat(0),
                    };
                    if (coff.targetEndian() != native_endian)
                        std.mem.byteSwapAllFieldsAligned(std.coff.SectionDefinition, .@"2", aux_ptr);

                    break :aux_init;
                },
                else => {},
            }

            unreachable;
        }

        break :entry entry;
    };

    coff.targetStore(&entry.value, switch (sym.section_number) {
        .UNDEFINED => if (entry.storage_class == .WEAK_EXTERNAL) 0 else sym.size(),
        .ABSOLUTE,
        .DEBUG,
        => unreachable,
        else => switch (coff.getNode(sym.ni)) {
            .image_section => 0,
            else => coff.computeSymbolSectionOffset(sym, .image),
        },
    });

    log.debug("flushSymbolTableEntry({d}) = {d}", .{ si, sti.* });
}

fn flushInputMember(coff: *Coff, iami: InputArchive.Member.Index) !void {
    const member = iami.member(coff);
    assert(!member.flags.is_loaded);
    defer member.flags.is_loaded = true;
    switch (member.content) {
        .import => unreachable,
        .object => |file_location| {
            if (file_location.size == 0) return;
            const comp = coff.base.comp;
            const io = comp.io;
            const path = member.iai.path(coff);
            const file = try path.root_dir.handle.openFile(io, path.sub_path, .{});
            defer file.close(io);
            var buffer: [4096]u8 = undefined;
            var fr = file.reader(io, &buffer);
            const offset = file_location.offset + @sizeOf(std.coff.ArchiveMemberHeader);
            try fr.seekTo(offset);
            log.debug("flushInputMember({f}({s}))", .{ path, member.name.toSlice(coff) });
            try coff.loadObject(path, member.name.toSlice(coff), &fr, .{
                .offset = offset,
                .size = file_location.size,
            });
        },
    }
}

fn flushInputSection(coff: *Coff, isi: Node.InputSection.Index) !void {
    const file_loc = isi.fileLocation(coff);
    if (file_loc.size == 0) return;
    const comp = coff.base.comp;
    const io = comp.io;
    const gpa = comp.gpa;
    const ioi = isi.input(coff);
    const path = ioi.path(coff);
    const file = try path.root_dir.handle.openFile(io, path.sub_path, .{});
    defer file.close(io);
    var fr = file.reader(io, &.{});
    try fr.seekTo(file_loc.offset);
    var nw: MappedFile.Node.Writer = undefined;
    const si = isi.symbol(coff);
    si.node(coff).writer(&coff.mf, gpa, &nw);
    defer nw.deinit();
    log.debug("flushInputSection({f}{f}, {s}, {d}, n{d})", .{
        path,
        fmtMemberNameString(ioi.memberName(coff)),
        si.get(coff).section_number.name(coff).toSlice(coff),
        si,
        si.node(coff),
    });
    if (try nw.interface.sendFileAll(&fr, .limited(@intCast(file_loc.size))) != file_loc.size)
        return error.EndOfStream;
    try si.applyLocationRelocs(coff);
}

fn addSection(coff: *Coff, name: String, flags: std.coff.SectionHeader.Flags) !Symbol.Index {
    assert(coff.hasCoffHeader());

    const gpa = coff.base.comp.gpa;
    try coff.nodes.ensureUnusedCapacity(gpa, 1);
    try coff.section_table.ensureUnusedCapacity(gpa, 1);
    try coff.symbols.ensureUnusedCapacity(gpa, 1);
    if (!isImage(coff)) try coff.symbol_table.symbols.ensureUnusedCapacity(gpa, 1);

    const coff_header = coff.headerPtr();
    const section_index = coff.targetLoad(&coff_header.number_of_sections);
    const section_table_len = section_index + 1;
    coff.targetStore(&coff_header.number_of_sections, section_table_len);
    try Node.known.section_table.resize(
        &coff.mf,
        gpa,
        @sizeOf(std.coff.SectionHeader) * section_table_len,
    );

    const ni = try coff.mf.addLastChildNode(gpa, coff.sectionParent(), .{
        .alignment = coff.mf.flags.block_size,
        .moved = true,
        .bubbles_moved = false,
    });

    const si = coff.addSymbolAssumeCapacity();
    coff.section_table.putAssumeCapacity(name, .{
        .si = si,
        .relocation_table_ni = .none,
    });
    coff.nodes.appendAssumeCapacity(.{ .image_section = si });
    const section_table = coff.sectionTableSlice();

    const virtual_size, const rva = if (coff.isImage()) block: {
        const virtual_size = coff.optionalHeaderField(.section_alignment);
        const rva: u32 = switch (section_index) {
            0 => @intCast(Node.known.header.location(&coff.mf).resolve(&coff.mf)[1]),
            else => coff.section_table.values()[section_index - 1].si.get(coff).rva +
                coff.targetLoad(&section_table[section_index - 1].virtual_size),
        };

        break :block .{ virtual_size, rva };
    } else .{ 0, 0 };

    {
        const sym = si.get(coff);
        sym.ni = ni;
        sym.rva = rva;
        sym.section_number = @enumFromInt(section_table_len);
    }
    const section = &section_table[section_index];
    section.* = .{
        .name = undefined,
        .virtual_size = virtual_size,
        .virtual_address = rva,
        .size_of_raw_data = 0,
        .pointer_to_raw_data = 0,
        .pointer_to_relocations = 0,
        .pointer_to_linenumbers = 0,
        .number_of_relocations = 0,
        .number_of_linenumbers = 0,
        .flags = flags,
    };
    if (coff.targetEndian() != native_endian)
        std.mem.byteSwapAllFields(std.coff.SectionHeader, section);

    const name_slice = name.toSlice(coff);
    if (coff.isImage()) {
        @memcpy(section.name[0..name_slice.len], name_slice);
        @memset(section.name[name_slice.len..], 0);
        switch (coff.optionalHeaderPtr()) {
            inline else => |optional_header| coff.targetStore(
                &optional_header.size_of_image,
                @intCast(rva + virtual_size),
            ),
        }
    } else {
        (try coff.getOrPutSymbolName(name_slice, name)).store(coff, &section.name);
        try coff.pendingSymbolTableEntry(si);
    }

    return si;
}

const ObjectSectionAttributes = packed struct {
    read: bool = false,
    write: bool = false,
    execute: bool = false,
    shared: bool = false,
    nopage: bool = false,
    nocache: bool = false,
    discard: bool = false,
    remove: bool = false,
    initialized: bool = false,
    uninitialized: bool = false,

    pub fn fromFlags(flags: std.coff.SectionHeader.Flags) ObjectSectionAttributes {
        return .{
            .read = flags.MEM_READ,
            .write = flags.MEM_WRITE,
            .execute = flags.MEM_EXECUTE,
            .shared = flags.MEM_SHARED,
            .nopage = flags.MEM_NOT_PAGED,
            .nocache = flags.MEM_NOT_CACHED,
            .discard = flags.MEM_DISCARDABLE,
            .remove = flags.LNK_REMOVE,
            .initialized = flags.CNT_INITIALIZED_DATA,
            .uninitialized = flags.CNT_UNINITIALIZED_DATA,
        };
    }

    pub fn asFlags(attr: ObjectSectionAttributes) std.coff.SectionHeader.Flags {
        return .{
            .MEM_READ = attr.read,
            .MEM_WRITE = attr.write,
            .MEM_EXECUTE = attr.execute,
            .MEM_SHARED = attr.shared,
            .MEM_NOT_PAGED = attr.nopage,
            .MEM_NOT_CACHED = attr.nocache,
            .MEM_DISCARDABLE = attr.discard,
            .LNK_REMOVE = attr.remove,
            .CNT_INITIALIZED_DATA = attr.uninitialized,
            .CNT_UNINITIALIZED_DATA = attr.uninitialized,
        };
    }
};

fn pseudoSectionMapIndex(
    coff: *Coff,
    name: String,
    alignment: std.mem.Alignment,
    attributes: ObjectSectionAttributes,
) !Node.PseudoSectionMapIndex {
    const gpa = coff.base.comp.gpa;
    const pseudo_section_gop = try coff.pseudo_section_table.getOrPut(gpa, name);
    const psmi: Node.PseudoSectionMapIndex = @enumFromInt(pseudo_section_gop.index);
    const parent_sn = if (!pseudo_section_gop.found_existing) sn: {
        const effective_name = coff.section_merges.get(name) orelse name;
        const parent = if (coff.section_table.get(effective_name)) |existing_sec|
            existing_sec.si
        else if (coff.isImage()) parent: {
            const parent: Symbol.Index = if (attributes.uninitialized)
                .bss
            else if (attributes.execute)
                .text
            else if (attributes.write)
                .data
            else
                .rdata;

            break :parent parent;
        } else try coff.addSection(effective_name, attributes.asFlags());

        try coff.nodes.ensureUnusedCapacity(gpa, 1);
        try coff.symbols.ensureUnusedCapacity(gpa, 1);
        const ni = try coff.mf.addLastChildNode(gpa, parent.node(coff), .{ .alignment = alignment });
        const si = coff.addSymbolAssumeCapacity();
        pseudo_section_gop.value_ptr.* = si;
        const sym = si.get(coff);
        sym.ni = ni;
        sym.rva = coff.computeNodeRva(ni);
        sym.section_number = parent.get(coff).section_number;
        assert(sym.loc_relocs == .none);
        sym.loc_relocs = @enumFromInt(coff.relocs.items.len);
        coff.nodes.appendAssumeCapacity(.{ .pseudo_section = psmi });
        break :sn sym.section_number;
    } else pseudo_section_gop.value_ptr.get(coff).section_number;

    try coff.verifyParentSectionAttributes(
        parent_sn,
        name,
        .pseudo,
        .fromFlags(parent_sn.header(coff).flags),
        attributes,
    );

    return psmi;
}

fn objectSectionParentName(coff: *Coff, name: []const u8) []const u8 {
    // In images we want to sort object sections into the final root section name.
    // Otherwise, we want to keep the full name so that this sort can occur correctly when
    // the object is finally linked into an image.
    return if (coff.isImage())
        name[0 .. std.mem.indexOfScalar(u8, name, '$') orelse name.len]
    else
        name;
}

fn objectSectionMapIndex(
    coff: *Coff,
    name: String,
    alignment: std.mem.Alignment,
    attributes: ObjectSectionAttributes,
) !Node.ObjectSectionMapIndex {
    const gpa = coff.base.comp.gpa;
    const name_slice = name.toSlice(coff);
    // TODO: Should this be a section merge instead?
    const effective_attributes = if (coff.isImage() and std.mem.startsWith(u8, name_slice, ".tls")) attr: {
        // In images, the .tls section is a read-only template
        var attr = attributes;
        attr.write = false;
        break :attr attr;
    } else attributes;

    const object_section_gop = try coff.object_section_table.getOrPut(gpa, name);
    const osmi: Node.ObjectSectionMapIndex = @enumFromInt(object_section_gop.index);
    const sym = if (!object_section_gop.found_existing) sym: {
        try coff.ensureUnusedStringCapacity(name_slice.len);
        const parent_name = coff.getOrPutStringAssumeCapacity(coff.objectSectionParentName(name_slice));
        const parent = (try coff.pseudoSectionMapIndex(parent_name, alignment, effective_attributes)).symbol(coff);
        try coff.nodes.ensureUnusedCapacity(gpa, 1);
        try coff.symbols.ensureUnusedCapacity(gpa, 1);
        const parent_ni = parent.node(coff);
        var prev_ni: MappedFile.Node.Index = .none;
        var next_it = parent_ni.children(&coff.mf);
        while (next_it.next()) |next_ni| switch (std.mem.order(
            u8,
            name_slice,
            coff.getNode(next_ni).object_section.name(coff).toSlice(coff),
        )) {
            .lt => break,
            .eq => unreachable,
            .gt => prev_ni = next_ni,
        };
        const ni = switch (prev_ni) {
            .none => try coff.mf.addFirstChildNode(gpa, parent_ni, .{
                .alignment = alignment,
                .fixed = true,
            }),
            else => try coff.mf.addNodeAfter(gpa, prev_ni, .{
                .alignment = alignment,
                .fixed = true,
            }),
        };
        const si = coff.addSymbolAssumeCapacity();
        object_section_gop.value_ptr.* = si;
        const sym = si.get(coff);
        sym.ni = ni;
        sym.rva = coff.computeNodeRva(ni);
        sym.section_number = parent.get(coff).section_number;
        assert(sym.loc_relocs == .none);
        sym.loc_relocs = @enumFromInt(coff.relocs.items.len);
        coff.nodes.appendAssumeCapacity(.{ .object_section = osmi });
        break :sym sym;
    } else object_section_gop.value_ptr.get(coff);

    const parent_ni = sym.ni.parent(&coff.mf);
    const parent_alignment = parent_ni.alignment(&coff.mf);
    if (alignment.compare(.gt, parent_alignment)) {
        log.debug("realignParent({s}, {d}) {d}->{d}", .{ name.toSlice(coff), parent_ni, parent_alignment, alignment });
        try parent_ni.realign(&coff.mf, gpa, alignment, .{ .set_alignment = true });
    }

    const old_alignment = sym.ni.alignment(&coff.mf);
    if (alignment.compare(.gt, old_alignment)) {
        log.debug("realignObject({s}) {d}->{d}", .{ name.toSlice(coff), old_alignment, alignment });
        try sym.ni.realign(&coff.mf, gpa, alignment, .{ .set_alignment = true });
    }

    try coff.verifyParentSectionAttributes(
        sym.section_number,
        name,
        .object,
        .fromFlags(sym.section_number.header(coff).flags),
        effective_attributes,
    );

    return osmi;
}

fn verifyParentSectionAttributes(
    coff: *Coff,
    parent: Symbol.SectionNumber,
    child_name: String,
    child_kind: enum { pseudo, object },
    parent_attrs: ObjectSectionAttributes,
    child_attrs: ObjectSectionAttributes,
) !void {
    if (parent_attrs == child_attrs) return;

    const was_merged = switch (child_kind) {
        .pseudo => coff.section_merges.contains(child_name),
        .object => if (coff.getString(
            coff.objectSectionParentName(child_name.toSlice(coff)),
        ).unwrap()) |pseudo_name|
            coff.section_merges.contains(pseudo_name)
        else
            false,
    };

    // The section was intentionally merged by the user or builtin rule
    if (was_merged) return;

    const BackingT = @typeInfo(ObjectSectionAttributes).@"struct".backing_integer.?;
    const num_notes = @popCount(@as(BackingT, @bitCast(parent_attrs)) ^ @as(BackingT, @bitCast(child_attrs)));
    var err = try coff.base.comp.link_diags.addErrorWithNotes(num_notes);
    try err.addMsg("{t} section '{s}' was placed in parent section '{s}' with mismatched flags", .{
        child_kind,
        child_name.toSlice(coff),
        parent.name(coff).toSlice(coff),
    });

    inline for (comptime std.meta.fieldNames(ObjectSectionAttributes)) |field| {
        if (@field(child_attrs, field) != @field(parent_attrs, field)) {
            err.addNote("flags.{s} was {d} in {s}, but {d} in {s}", .{
                field,
                @intFromBool(@field(child_attrs, field)),
                child_name.toSlice(coff),
                @intFromBool(@field(parent_attrs, field)),
                parent.name(coff).toSlice(coff),
            });
        }
    }

    return error.AlreadyReported;
}

const RelocAddend = union(enum) {
    known: i64,
    /// Relocs tables in input objects don't include the addend.
    /// The value needs to be recovered from the reloc location.
    pending: void,
};

// TODO: There should be an API where the caller can indicate how many contiguous relocs they need
//       and it should attempt to allocate these from from the free list if available. We can cache
//       the run length of each segment on Reloc when `free` is set.
pub fn addReloc(
    coff: *Coff,
    loc_si: Symbol.Index,
    offset: u64,
    target_si: Symbol.Index,
    addend: RelocAddend,
    @"type": Reloc.Type,
) link.Error!void {
    const diags = &coff.base.comp.link_diags;
    try coff.ensureUnusedRelocCapacity(loc_si, 1);
    coff.addRelocAssumeCapacity(loc_si, offset, target_si, addend, @"type") catch |err| switch (err) {
        error.MappedFileIo => return diags.fail(
            "failed to write output file: {t}",
            .{coff.mf.io_err.?},
        ),
        else => |e| return e,
    };
}

fn ensureUnusedRelocCapacity(coff: *Coff, loc_si: Symbol.Index, len: usize) !void {
    const gpa = coff.base.comp.gpa;
    try coff.relocs.ensureUnusedCapacity(gpa, len);
    if (isImage(coff)) return;
    switch (loc_si.get(coff).section_number) {
        .UNDEFINED, .ABSOLUTE, .DEBUG => {},
        else => |loc_sn| {
            const section = loc_sn.section(coff);
            if (section.relocation_table_ni == .none)
                try coff.nodes.ensureUnusedCapacity(gpa, 1);
        },
    }
}

fn addRelocAssumeCapacity(
    coff: *Coff,
    loc_si: Symbol.Index,
    offset: u64,
    target_si: Symbol.Index,
    addend: RelocAddend,
    @"type": Reloc.Type,
) !void {
    const gpa = coff.base.comp.gpa;
    const target = target_si.get(coff);

    const ri: Reloc.Index = @enumFromInt(coff.relocs.items.len);
    log.debug("addReloc({d}@{d}+0x{x} -> {d}@{d}+0x{x}{s}) = {d}", .{
        loc_si,
        loc_si.get(coff).section_number,
        offset,
        target_si,
        target_si.get(coff).section_number,
        if (addend == .pending) 0 else addend.known,
        if (addend == .pending) "p" else "k",
        ri,
    });

    const sri: Section.RelocationIndex = if (isImage(coff))
        .none
    else switch (loc_si.get(coff).section_number) {
        .UNDEFINED,
        .ABSOLUTE,
        .DEBUG,
        => .none,
        else => |loc_sn| sri: {
            // The target may not have a node yet, or it could be an extern that will never
            // have a node. In that case, flushGlobal will create the symbol table entry.
            const existing_sti = target_si.sti(coff);
            const sti: SymbolTable.Index = if (existing_sti != .none)
                existing_sti
            else if (target.ni != .none) sti: {
                try coff.pendingSymbolTableEntry(target_si);
                break :sti .none;
            } else .none;

            const sri: Section.RelocationIndex = blk: {
                const section = loc_sn.section(coff);
                const header = loc_sn.header(coff);
                const old_num_relocations = coff.targetLoad(&header.number_of_relocations);
                const new_num_relocations = old_num_relocations + 1;
                const new_size = @as(u32, new_num_relocations) * std.coff.Relocation.sizeOf();

                coff.targetStore(&header.number_of_relocations, new_num_relocations);
                if (coff.symbolTableSectionAuxEntryPtr(loc_sn.symbol(coff).sti(coff))) |aux_ptr|
                    coff.targetStore(&aux_ptr.number_of_relocations, new_num_relocations);

                if (section.relocation_table_ni == .none) {
                    section.relocation_table_ni = try coff.mf.addLastChildNode(
                        gpa,
                        coff.sectionParent(),
                        .{
                            .size = new_size,
                            .alignment = .@"2",
                            .moved = true,
                            .resized = true,
                        },
                    );
                    coff.nodes.appendAssumeCapacity(.{ .relocation_table = loc_sn });
                } else {
                    try section.relocation_table_ni.resize(&coff.mf, gpa, new_size);
                }

                // TODO: These need to allocate from a free list, once deleting relocs from the table is supported
                break :blk .wrap(old_num_relocations);
            };

            const entry = sri.entry(coff, loc_sn).?;
            if (sti.unwrap()) |index| coff.targetStore(&entry.symbol_table_index, index);

            // applyLocationRelocs updates `virtual_address`
            // flushSymbolTableIndex updates `symbol_table_index`
            coff.targetStore(&entry.type, @"type".u16);

            break :sri sri;
        },
    };

    coff.relocs.addOneAssumeCapacity().* = .{
        .type = @"type",
        .prev = .none,
        .next = target.target_relocs,
        .loc = loc_si,
        .target = target_si,
        .sri = sri,
        .offset = offset,
        .addend = if (addend == .pending) 0 else addend.known,
        .flags = .{
            .recover_addend = addend == .pending,
            .free = false,
        },
    };
    switch (target.target_relocs) {
        .none => {},
        else => |target_ri| target_ri.get(coff).prev = ri,
    }
    target.target_relocs = ri;
}

fn failLoadInput(
    coff: *Coff,
    err: LoadInputError,
    fr: *Io.File.Reader,
    path: std.Build.Cache.Path,
) link.Error {
    const diags = &coff.base.comp.link_diags;
    switch (err) {
        else => |e| return e,
        error.MappedFileIo => return diags.fail(
            "failed to write output file: {t}",
            .{coff.mf.io_err.?},
        ),
        error.EndOfStream => return diags.failParse(
            path,
            "unexpected eof",
            .{},
        ),
        error.AccessDenied,
        error.Unexpected,
        error.Unseekable,
        => |e| return diags.fail(
            "failed to read \"{f}\": {t}",
            .{ path.fmtEscapeString(), e },
        ),
        error.PermissionDenied,
        error.SystemResources,
        error.Streaming,
        => |e| return diags.fail(
            "failed to stat \"{f}\": {t}",
            .{ path.fmtEscapeString(), e },
        ),
        error.ReadFailed => switch (fr.err.?) {
            error.Canceled => |e| return e,
            else => |e| return diags.fail(
                "failed to read \"{f}\": {t}",
                .{ path.fmtEscapeString(), e },
            ),
        },
    }
}

pub fn loadInput(coff: *Coff, input: link.Input) link.Error!void {
    const comp = coff.base.comp;
    const io = comp.io;

    const path = input.path() orelse unreachable;
    const gop = try coff.inputs.getOrPut(comp.gpa, path);
    if (gop.found_existing) return;
    errdefer _ = coff.inputs.swapRemove(path);

    var buf: [4096]u8 = undefined;
    switch (input) {
        .object => |object| {
            var fr = object.file.reader(io, &buf);
            coff.loadObject(object.path, null, &fr, .{
                .offset = fr.logicalPos(),
                .size = fr.getSize() catch |err|
                    return coff.failLoadInput(err, &fr, object.path),
            }) catch |err| return coff.failLoadInput(err, &fr, object.path);
        },
        .archive => |archive| {
            var fr = archive.file.reader(io, &buf);
            coff.loadArchive(archive.path, &fr) catch |err|
                return coff.failLoadInput(err, &fr, archive.path);
        },
        .res => |res| {
            var fr = res.file.reader(io, &buf);
            coff.loadRes(res.path, &fr) catch |err|
                return coff.failLoadInput(err, &fr, res.path);
        },
        .dso => |dso| {
            var fr = dso.file.reader(io, &buf);
            coff.loadDll(dso.path, &fr) catch |err|
                return coff.failLoadInput(err, &fr, dso.path);
        },
        .dso_exact => unreachable,
    }
}

fn fmtMemberNameString(memberName: ?[]const u8) std.fmt.Alt(?[]const u8, memberNameStringEscape) {
    return .{ .data = memberName };
}

fn memberNameStringEscape(memberName: ?[]const u8, w: *std.Io.Writer) std.Io.Writer.Error!void {
    try w.print("({f})", .{std.zig.fmtString(memberName orelse return)});
}

fn inputSectionHeaderNameSlice(
    coff: *Coff,
    header: *const std.coff.SectionHeader,
    string_table: []const u8,
    path: std.Build.Cache.Path,
    section_i: usize,
) ![]const u8 {
    const diags = &coff.base.comp.link_diags;
    return if (header.name[0] == '/') name: {
        const offset_str = std.mem.sliceTo(header.name[1..], 0);
        const name_offset = std.fmt.parseUnsigned(u24, offset_str, 10) catch
            return diags.failParse(path, "ill-formed section name in section {d}: '{s}'", .{
                section_i,
                header.name[0 .. offset_str.len + 1],
            });

        if (name_offset > string_table.len)
            return diags.failParse(path, "out-of-bounds section name offset in section {d}: {d}", .{ section_i, name_offset });

        break :name std.mem.sliceTo(string_table[name_offset..], 0);
    } else std.mem.sliceTo(&header.name, 0);
}

fn loadObject(
    coff: *Coff,
    path: std.Build.Cache.Path,
    member_name: ?[]const u8,
    fr: *Io.File.Reader,
    fl: MappedFile.Node.FileLocation,
) LoadInputError!void {
    const comp = coff.base.comp;
    const gpa = comp.gpa;
    const diags = &comp.link_diags;
    const r = &fr.interface;
    const target = &comp.root_mod.resolved_target.result;
    const target_endian = coff.targetEndian();
    const is_archive = coff.isArchive();
    assert(!coff.isObj());
    // We want to evaluate new merges as we see them in .drectve sections to avoid redundant work
    assert(coff.section_merge_pending_index == coff.section_merges.count());

    log.debug("loadObject({f}{f})", .{ path.fmtEscapeString(), fmtMemberNameString(member_name) });

    const header = try r.peekStruct(std.coff.Header, .little);
    if (header.machine != target.toCoffMachine())
        return diags.failParse(path, "machine mismatch: expected {t}, found {t}", .{
            target.toCoffMachine(),
            header.machine,
        });
    if (header.number_of_sections == 0) return;
    if (@sizeOf(std.coff.Header) + @as(usize, header.number_of_sections) * @sizeOf(std.coff.SectionHeader) > fl.size)
        return diags.failParse(path, "invalid section table", .{});
    const unexpected_header_flags: []const std.meta.FieldEnum(std.coff.Header.Flags) = &.{
        .RELOCS_STRIPPED,
        .EXECUTABLE_IMAGE,
        .AGGRESSIVE_WS_TRIM,
        .RESERVED,
        .BYTES_REVERSED_LO,
        .DLL,
        .BYTES_REVERSED_HI,
    };
    inline for (unexpected_header_flags) |flag|
        if (@field(header.flags, @tagName(flag)))
            return diags.failParse(path, "unexpected flag set: {t}", .{flag});

    if (header.size_of_optional_header != 0)
        return diags.failParse(path, "unexpected optional header", .{});

    const symbol_table_len = header.number_of_symbols * std.coff.Symbol.sizeOf();
    const symbol_table_end = header.pointer_to_symbol_table + symbol_table_len;
    // String table length (which includes the length field) immediately trails the symbol table
    if (symbol_table_end + @sizeOf(u32) > fl.size)
        return diags.failParse(path, "bad symbol table location", .{});

    try fr.seekTo(fl.offset + symbol_table_end);
    const string_table_len = try r.peekInt(u32, target_endian);
    if (string_table_len < @sizeOf(u32) or
        symbol_table_end + string_table_len > fl.size)
        return diags.failParse(path, "bad string table length: 0x{x}", .{string_table_len});

    const ioi: InputObject.Index = @enumFromInt(coff.input_objects.items.len);
    try coff.input_objects.ensureUnusedCapacity(gpa, 1);
    const input = coff.input_objects.addOneAssumeCapacity();
    input.* = .{
        .path = path,
        .member_name = if (member_name) |m| try gpa.dupe(u8, m) else null,
        .source_name = .none,
    };

    const string_table = string_table: {
        const string_table = try gpa.alloc(u8, string_table_len);
        errdefer gpa.free(string_table);
        try r.readSliceAll(string_table);
        break :string_table string_table;
    };
    defer gpa.free(string_table);

    try coff.ensureManyUnusedStringCapacity(
        header.number_of_sections + header.number_of_symbols,
        header.number_of_sections * 9 +
            header.number_of_symbols * 9 +
            string_table_len - @sizeOf(u32),
    );

    const PendingSymbolIndex = enum(u32) {
        none,
        _,

        pub fn wrap(i: ?u32) @This() {
            return @enumFromInt((i orelse return .none) + 1);
        }

        pub fn unwrap(i: @This()) ?u32 {
            return switch (i) {
                .none => null,
                _ => @intFromEnum(i) - 1,
            };
        }
    };

    const PendingInputSection = struct {
        header: std.coff.SectionHeader,
        name: String,
        si: Symbol.Index,
        parent_si: Symbol.Index,
        psi: PendingSymbolIndex,
        num_symbols: u32,
        comdat: std.coff.ComdatSelection,
        comdat_psi: PendingSymbolIndex,
        comdat_crc: u32,
        comdat_association: Symbol.SectionNumber,
        comdat_result: union(enum) {
            pending,
            // Root of the association chain
            pending_association: Symbol.SectionNumber,
            include,
            skip,
        },
    };

    const sections: []PendingInputSection = if (coff.isImage()) sections: {
        const sections = try gpa.alloc(PendingInputSection, header.number_of_sections);
        errdefer gpa.free(sections);

        try fr.seekTo(fl.offset + @sizeOf(std.coff.Header));
        for (sections, 0..) |*section, section_i| {
            section.* = .{
                .header = try r.takeStruct(std.coff.SectionHeader, target_endian),
                .name = undefined,
                .si = .null,
                .parent_si = .null,
                .psi = .none,
                .num_symbols = 0,
                .comdat = .NONE,
                .comdat_psi = .none,
                .comdat_crc = 0,
                .comdat_association = .UNDEFINED,
                .comdat_result = .pending,
            };

            const section_name_slice = if (section.header.name[0] == '/') name: {
                const offset_str = std.mem.sliceTo(section.header.name[1..], 0);
                const name_offset = std.fmt.parseUnsigned(u24, offset_str, 10) catch
                    return diags.failParse(path, "ill-formed section name offset in section {d}: '{s}'", .{
                        section_i,
                        section.header.name[0 .. offset_str.len + 1],
                    });

                if (name_offset > string_table.len)
                    return diags.failParse(
                        path,
                        "out-of-bounds section name offset in section {d}: {d}",
                        .{ section_i, name_offset },
                    );

                break :name std.mem.sliceTo(string_table[name_offset..], 0);
            } else std.mem.sliceTo(&section.header.name, 0);
            section.name = coff.getOrPutStringAssumeCapacity(section_name_slice);

            if (section.header.pointer_to_linenumbers +
                @as(u32, section.header.number_of_linenumbers) * std.coff.LineNumber.sizeOf() > fl.size)
                return diags.failParse(path, "bad line numbers location in section {d} `{s}`", .{
                    section_i,
                    section_name_slice,
                });

            if (section.header.pointer_to_relocations +
                @as(u32, section.header.number_of_relocations) * std.coff.Relocation.sizeOf() > fl.size)
                return diags.failParse(path, "bad relocations location in section {d} `{s}`", .{
                    section_i,
                    section_name_slice,
                });

            if (section.header.pointer_to_raw_data + section.header.size_of_raw_data > fl.size)
                return diags.failParse(path, "bad raw data location in section {d} `{s}`", .{
                    section_i,
                    section_name_slice,
                });
        }

        break :sections sections;
    } else &.{};
    defer gpa.free(sections);

    const mi = if (is_archive) mi: {
        try coff.nodes.ensureUnusedCapacity(gpa, 2);
        try coff.members.ensureUnusedCapacity(gpa, 1);
        const path_str = try path.toString(gpa);
        defer gpa.free(path_str);

        const mi = try coff.addMemberAssumeCapacity(.coff, fl.size);
        const member = mi.get(coff);
        try member.initHeader(coff, path_str, header.time_date_stamp);

        {
            // TODO: This should be deferred to an idle task (but resize it here!)
            var nw: MappedFile.Node.Writer = undefined;
            member.content_ni.writer(&coff.mf, gpa, &nw);
            defer nw.deinit();

            try fr.seekTo(fl.offset);
            const written = nw.interface.sendFileAll(fr, .limited64(fl.size)) catch |err| switch (err) {
                error.WriteFailed => return nw.err.?,
                else => |e| return e,
            };

            if (written != fl.size) return error.EndOfStream;
        }

        break :mi mi;
    } else undefined;

    try fr.seekTo(fl.offset + header.pointer_to_symbol_table);
    const symbol_size = std.coff.Symbol.sizeOf();

    const PendingSymbol = struct {
        name: String,
        value: union(enum) {
            // Size of the section
            section: u32,
            // If section is absolute, the symbol value.
            // Otherwise, offset within the section.
            static: u32,
            // If section is undefined, the symbol size.
            // If section is absolute, the symbol value.
            // Otherwise offset within the section.
            external: u32,
            // The index of the target symbol of this weak external
            weak_external: u32,
            // Trails .weak_external
            weak_external_aux: WeakExternalStrat,
        },
        section_number: Symbol.SectionNumber,
        si: Symbol.Index,
        // If a weak external targets this symbol, the index of the weak external
        weak_external_psi: PendingSymbolIndex,
    };

    var num_global_symbols: u32 = 0;
    var pending_symbols: std.array_hash_map.Auto(u32, PendingSymbol) = .empty;
    defer pending_symbols.deinit(gpa);
    if (!is_archive)
        try pending_symbols.ensureUnusedCapacity(gpa, header.number_of_symbols);

    var section_merges: std.ArrayList(struct {
        from: String,
        to: String,
    }) = .empty;
    defer section_merges.deinit(gpa);

    // Discover symbol names and COMDAT symbol mappings
    var symbol_i: u32 = 0;
    var num_included_symbols: u32 = 0;
    while (symbol_i < header.number_of_symbols) {
        var symbol: std.coff.Symbol = undefined;
        @memcpy(std.mem.asBytes(&symbol)[0..symbol_size], try r.take(symbol_size));
        if (target_endian != native_endian)
            std.mem.byteSwapAllFields(std.coff.Symbol, &symbol);

        const aux_symbols = if (symbol.number_of_aux_symbols > 0)
            try r.take(symbol_size * symbol.number_of_aux_symbols)
        else
            &.{};
        defer symbol_i += symbol.number_of_aux_symbols + 1;

        const name = std.mem.sliceTo(if (std.mem.eql(u8, symbol.name[0..4], "\x00\x00\x00\x00")) name: {
            const index = std.mem.readInt(u32, symbol.name[4..], target_endian);
            if (index >= string_table.len)
                return diags.failParse(path, "bad string offset for symbol 0x{x}", .{symbol_i});
            break :name string_table[index..];
        } else &symbol.name, 0);

        if (is_archive) {
            if (switch (symbol.storage_class) {
                .WEAK_EXTERNAL => true,
                .EXTERNAL => symbol.section_number != .UNDEFINED,
                else => false,
            }) try coff.ensureMemberSymbol(mi, coff.getOrPutStringAssumeCapacity(name));

            continue;
        }

        switch (symbol.section_number) {
            .UNDEFINED, .DEBUG, .ABSOLUTE => {},
            else => |sn| if (@intFromEnum(sn) > sections.len)
                return diags.failParse(path, "out-of-bounds section number {d} in symbol 0x{x}", .{ sn, symbol_i }),
        }

        const psi: PendingSymbolIndex = .wrap(@intCast(pending_symbols.count()));
        const section_number: Symbol.SectionNumber = @enumFromInt(@intFromEnum(symbol.section_number));

        const values: []const @FieldType(PendingSymbol, "value") = pending_symbols: switch (symbol.storage_class) {
            .STATIC, .LABEL => |storage_class| switch (section_number) {
                // TODO: Do we need to do anything with @feat.00?
                //       https://llvm.org/doxygen/namespacellvm_1_1COFF.html#aeffa16735e18df727a173beaf748c392
                .UNDEFINED,
                .DEBUG,
                => &.{},
                .ABSOLUTE => &.{.{ .static = symbol.value }},
                else => |sn| {
                    const section = &sections[sn.toIndex()];

                    // Section symbol
                    const is_section = storage_class == .STATIC and
                        symbol.value == 0 and
                        symbol.type == std.coff.SymType{
                            .complex_type = .NULL,
                            .base_type = .NULL,
                        } and
                        symbol.number_of_aux_symbols > 0;

                    if (is_section) {
                        if (symbol.number_of_aux_symbols > 1)
                            return diags.failParse(path, "invalid number of aux symbols for section symbol 0x{x}: {d}", .{
                                symbol_i,
                                symbol.number_of_aux_symbols,
                            });

                        var section_def: std.coff.SectionDefinition = undefined;
                        @memcpy(std.mem.asBytes(&section_def)[0..symbol_size], aux_symbols[0..symbol_size]);
                        if (target_endian != native_endian)
                            std.mem.byteSwapAllFields(std.coff.SectionDefinition, &section_def);

                        if (section_def.number_of_relocations != section.header.number_of_relocations)
                            return diags.failParse(
                                path,
                                "section aux symbol 0x{x} for '{s}' relocation count did not match section header: {d} vs {d}",
                                .{ symbol_i + 1, name, section_def.number_of_relocations, section.header.number_of_relocations },
                            );

                        if (section_def.number_of_linenumbers != section.header.number_of_linenumbers)
                            return diags.failParse(
                                path,
                                "section aux symbol 0x{x} for '{s}' line number count did not match section header: {d} vs {d}",
                                .{ symbol_i + 1, name, section_def.number_of_linenumbers, section.header.number_of_linenumbers },
                            );

                        if (section.header.flags.LNK_COMDAT) {
                            if (section_def.selection == .ASSOCIATIVE) {
                                if (section_def.number == 0 or section_def.number > sections.len)
                                    return diags.failParse(
                                        path,
                                        "section aux symbol 0x{x} for '{s}' contained an invalid associated section number: 0x{x}",
                                        .{ symbol_i + 1, name, section_def.number },
                                    );

                                section.comdat_association = @enumFromInt(section_def.number);
                            }

                            section.comdat = section_def.selection;
                            section.comdat_crc = section_def.checksum;
                        }

                        section.psi = psi;
                    }

                    break :pending_symbols &.{if (is_section)
                        .{ .section = section.header.size_of_raw_data }
                    else
                        .{ .static = symbol.value }};
                },
            },
            .WEAK_EXTERNAL => switch (symbol.section_number) {
                .UNDEFINED => {
                    if (symbol.value != 0)
                        return diags.failParse(
                            path,
                            "invalid value {d} for weak external symbol 0x{x}",
                            .{ symbol.value, symbol_i },
                        );

                    var weak_external: std.coff.WeakExternalDefinition = undefined;
                    @memcpy(std.mem.asBytes(&weak_external)[0..symbol_size], aux_symbols[0..symbol_size]);
                    if (target_endian != native_endian)
                        std.mem.byteSwapAllFields(std.coff.WeakExternalDefinition, &weak_external);

                    if (weak_external.tag_index >= header.number_of_symbols)
                        return diags.failParse(
                            path,
                            "invalid tag_index 0x{x} for weak external symbol 0x{x}",
                            .{ weak_external.tag_index, symbol_i },
                        );

                    break :pending_symbols switch (weak_external.flag) {
                        else => |flag| &.{
                            .{ .weak_external = weak_external.tag_index },
                            .{ .weak_external_aux = WeakExternalStrat.fromFlag(flag) },
                        },
                        _ => return diags.failParse(
                            path,
                            "encountered unknown weak external characteristic 0x{x} for symbol 0x{x}",
                            .{ weak_external.flag, symbol_i },
                        ),
                    };
                },
                else => |sn| return diags.failParse(
                    path,
                    "invalid section number {d} for weak external symbol 0x{x}",
                    .{ sn, symbol_i },
                ),
            },
            .EXTERNAL => switch (section_number) {
                .UNDEFINED,
                .ABSOLUTE,
                => &.{.{ .external = symbol.value }},
                .DEBUG => return diags.failParse(
                    path,
                    "unexpected external symbol 0x{x} in DEBUG section: '{s}'",
                    .{ symbol_i, name },
                ),
                else => &.{.{ .external = symbol.value }},
            },
            .FILE => {
                if (!std.mem.eql(u8, name, ".file"))
                    return diags.failParse(
                        path,
                        "unexpected symbol name '{s}' for file symbol 0x{x}",
                        .{ name, symbol_i },
                    );

                var file: std.coff.FileDefinition = undefined;
                @memcpy(std.mem.asBytes(&file)[0..symbol_size], aux_symbols[0..symbol_size]);

                input.source_name = (try coff.getOrPutString(file.getFileName())).toOptional();
                break :pending_symbols &.{};
            },
            else => |storage_class| return diags.failParse(
                path,
                "TODO handle storage class {t} for symbol 0x{x}",
                .{ storage_class, symbol_i },
            ),
        };

        for (values, 0..) |value, i| {
            if (section_number == .ABSOLUTE)
                num_included_symbols += 1;

            switch (value) {
                .section => {},
                .static,
                .external,
                .weak_external,
                => {
                    num_global_symbols += 1;
                    if (section_number.hasIndex()) {
                        const section = &sections[section_number.toIndex()];
                        section.num_symbols += 1;
                        if (section.header.flags.LNK_COMDAT and section.comdat_psi == .none)
                            section.comdat_psi = psi;
                    }
                },
                .weak_external_aux => {},
            }

            const symbol_name = coff.getOrPutStringAssumeCapacity(name);
            pending_symbols.putAssumeCapacity(symbol_i + @as(u32, @intCast(i)), .{
                .name = symbol_name,
                .value = value,
                .section_number = section_number,
                .si = .null,
                .weak_external_psi = .none,
            });
        }
    }

    try coff.globals.ensureUnusedCapacity(gpa, num_global_symbols);
    for (sections) |*section| {
        if (section.header.flags.LNK_INFO) {
            if (std.mem.eql(u8, &section.header.name, ".drectve")) {
                try fr.seekTo(fl.offset + section.header.pointer_to_raw_data);
                // TODO: Don't really want an additional buffer here, but want to limit to size_of_raw_data
                var buf: [128]u8 = undefined;
                var section_r = r.limited(.limited(section.header.size_of_raw_data), &buf);
                while (section_r.interface.takeDelimiter(' ') catch |err| switch (err) {
                    error.StreamTooLong => return diags.failParse(path, "unexpectedly long .drectve argument", .{}),
                    else => |e| return e,
                }) |arg| {
                    // Microsoft tools emit 3 space characters into this section even with /Zl
                    if (arg.len == 0) continue;

                    if (std.ascii.startsWithIgnoreCase(arg, "-exclude-symbols:")) {
                        // TODO: When implementing mingw auto-exports (if at all?), track this to not export this symbol
                    } else if (std.ascii.startsWithIgnoreCase(arg, "/include:")) {
                        _ = try coff.globalSymbol(.{ .name = arg["/include:".len..] });
                    } else if (std.ascii.startsWithIgnoreCase(arg, "/alternatename:")) {
                        var split = std.mem.splitScalar(u8, arg["/alternatename:".len..], '=');
                        const orig = split.first();
                        const alt = split.next() orelse
                            return diags.failParse(path, "malformed .drectve argument: '{s}'", .{arg});

                        try coff.ensureManyUnusedStringCapacity(2, orig.len + alt.len + 2);
                        const orig_str = coff.getOrPutStringAssumeCapacity(orig);
                        const alt_str = coff.getOrPutStringAssumeCapacity(alt);
                        const gop = try coff.alternate_names.getOrPut(gpa, orig_str);
                        if (!gop.found_existing) {
                            log.debug("alternateName({s}={s})", .{ orig, alt });
                            gop.value_ptr.* = alt_str;
                        } else if (gop.value_ptr.* != alt_str)
                            return diags.failParse(
                                path,
                                "conflicting /alternatename .drectve arguments: first seen as {s}={s}, now seen as {s}={s}",
                                .{ orig, gop.value_ptr.toSlice(coff), orig, alt },
                            );
                    } else if (std.ascii.startsWithIgnoreCase(arg, "/guardsym:")) {
                        // TODO: https://learn.microsoft.com/en-us/windows/win32/secbp/pe-metadata
                    } else if (std.ascii.startsWithIgnoreCase(arg, "/merge:")) merge: {
                        var split = std.mem.splitScalar(u8, arg["/merge:".len..], '=');
                        const from = split.first();
                        const to = split.next() orelse
                            return diags.failParse(path, "malformed .drectve argument: '{s}'", .{arg});
                        if (to.len > header_name_max_len)
                            return diags.failParse(
                                path,
                                "/merge .drectve target exceeds max length of {d}: '{s}'",
                                .{ header_name_max_len, arg },
                            );
                        if (std.mem.eql(u8, from, to)) break :merge;

                        try coff.ensureManyUnusedStringCapacity(2, from.len + to.len + 2);
                        const from_str = coff.getOrPutStringAssumeCapacity(from);
                        const to_str = coff.getOrPutStringAssumeCapacity(to);

                        {
                            var iter = to_str;
                            while (coff.section_merges.get(iter)) |next_to| {
                                if (next_to == from_str)
                                    return diags.failParse(
                                        path,
                                        "/merge .drectve argument would create a cycle: {s}={s} leads to {s}={s}",
                                        .{ from, to, iter.toSlice(coff), to },
                                    );

                                iter = next_to;
                            }
                        }

                        try coff.section_merges.ensureUnusedCapacity(gpa, 1);
                        const gop = coff.section_merges.getOrPutAssumeCapacity(from_str);
                        if (!gop.found_existing) {
                            coff.synth_prog_node.increaseEstimatedTotalItems(1);
                            gop.value_ptr.* = to_str;
                        } else if (gop.value_ptr.* != to_str)
                            return diags.failParse(
                                path,
                                "conflicting /merge .drectve arguments: first seen as {s}={s}, now seen as {s}={s}",
                                .{ from, gop.value_ptr.toSlice(coff), from, to },
                            );
                    } else if (std.ascii.startsWithIgnoreCase(arg, "/disallowlib:")) {
                        const lib_name = arg["/disallowlib:".len..];
                        // TODO: Track these and issue error in prelink if any match
                        _ = lib_name;
                    } else if (std.ascii.startsWithIgnoreCase(arg, "/defaultlib:")) {
                        const lib_path = arg["/defaultlib:".len..];
                        const trim = std.mem.trim(u8, lib_path, "\"");
                        if (lib_path.len == trim.len or lib_path.len - 2 == trim.len) {
                            if (!comp.config.link_libc or comp.libc_installation == null)
                                return diags.failParse(path, "encountered /DEFAULTLIB .drectve argument when libc was not available: {s}", .{arg});

                            (try coff.pending_default_libs.addOne(gpa)).* = .{
                                .path = try gpa.dupe(u8, lib_path),
                                .ioi = ioi,
                            };
                        } else return diags.failParse(
                            path,
                            "malformed /DEFAULTLIB .drectve argument: `{s}`",
                            .{arg},
                        );
                    } else return diags.failParse(path, "unsupported argument in .drectve section: `{s}`", .{arg});
                }
            }

            section.comdat_result = .skip;
            continue;
        }

        if (section.header.flags.LNK_REMOVE or
            section.header.flags.MEM_DISCARDABLE)
        {
            // TODO: Convert .debug$* sections into PDB
            section.comdat_result = .skip;
            continue;
        }

        section.comdat_result = comdat: switch (section.comdat) {
            .NONE => .include,
            .ASSOCIATIVE => {
                // Associative COMDAT sections have no COMDAT symbol.
                // They are linked if the assocated section is linked.
                var iter = section;
                var iter_sn = iter.comdat_association;
                while (iter.comdat == .ASSOCIATIVE) {
                    iter = &sections[iter_sn.toIndex()];
                    iter_sn = iter.comdat_association;
                    if (iter == section)
                        return diags.failParse(
                            path,
                            "circular COMDAT association loop detected, starting at symbol 0x{x}",
                            .{pending_symbols.keys()[section.psi.unwrap().?]},
                        );
                }

                assert(iter != section);
                break :comdat switch (iter.comdat_result) {
                    .pending => .{ .pending_association = iter_sn },
                    else => |iter_result| iter_result,
                };
            },
            else => |comdat| {
                const psi = section.comdat_psi.unwrap() orelse section.psi.unwrap().?;
                const symbol = &pending_symbols.values()[psi];
                const si = existing: switch (symbol.value) {
                    .weak_external => unreachable,
                    .weak_external_aux => unreachable,
                    .static => break :comdat .include,
                    .section => {
                        assert(section.comdat_psi == .none);
                        if (coff.object_section_table.get(section.name)) |si|
                            break :existing si
                        else if (coff.pseudo_section_table.get(section.name)) |si|
                            break :existing si
                        else if (coff.section_table.get(section.name)) |s|
                            break :existing s.si
                        else
                            break :comdat .include;
                    },
                    .external => {
                        const global_gop = try coff.getOrPutGlobalSymbol(.{
                            .name = symbol.name.toSlice(coff),
                        });

                        // TODO: What if the same symbol is incorrectly defined twice in this obj?
                        //       Would need to mark this global as pending, or notice it later when .ni != none
                        if (!global_gop.found_existing or global_gop.value_ptr.si.get(coff).ni == .none) {
                            symbol.si = global_gop.value_ptr.si;
                            break :comdat .include;
                        }

                        break :existing global_gop.value_ptr.si;
                    },
                };

                const index = pending_symbols.keys()[psi];
                switch (comdat) {
                    .NODUPLICATES => return coff.failMultipleDefinitions(
                        path,
                        member_name,
                        symbol.name,
                        index,
                        si,
                        .duplicate,
                    ),
                    .ANY => {
                        symbol.si = si;
                        break :comdat .skip;
                    },
                    .SAME_SIZE => {
                        // TODO: Verify that this node isn't resized after creation
                        _, const size = si.get(coff).ni.location(&coff.mf).resolve(&coff.mf);
                        if (size == section.header.size_of_raw_data) {
                            symbol.si = si;
                            break :comdat .skip;
                        }

                        return coff.failMultipleDefinitions(
                            path,
                            member_name,
                            symbol.name,
                            index,
                            si,
                            .{ .size = .{ .a = size, .b = section.header.size_of_raw_data } },
                        );
                    },
                    .EXACT_MATCH => {
                        const sym = si.get(coff);
                        const existing_crc = switch (coff.getNode(sym.ni)) {
                            .input_section => |isi| isi.inputSection(coff).crc,
                            else => std.hash.crc.Crc32Jamcrc.hash(sym.ni.sliceConst(&coff.mf)),
                        };

                        if (existing_crc == section.comdat_crc) {
                            symbol.si = si;
                            break :comdat .skip;
                        }

                        return coff.failMultipleDefinitions(
                            path,
                            member_name,
                            symbol.name,
                            index,
                            si,
                            .{ .crc = .{ .a = existing_crc, .b = section.comdat_crc } },
                        );
                    },
                    .LARGEST => {
                        // TODO: Resize existing .ni and replace with this section's contents
                        // TODO: This will be tricky, what to do about existing InputSection?
                        unreachable;
                    },
                    .NONE, .ASSOCIATIVE, _ => unreachable,
                }
            },
        };
    }

    try coff.flushSectionMerges();

    // Resolve pending associations, create parent sections
    var num_included_sections: u16 = 0;
    var num_included_relocs: u32 = 0;
    for (sections) |*section| {
        comdat: switch (section.comdat_result) {
            .pending_association => |root_assoc_sn| {
                const root_result = sections[root_assoc_sn.toIndex()].comdat_result;
                assert(root_result != .pending_association);
                section.comdat_result = root_result;
                continue :comdat root_result;
            },
            .include => {},
            .skip => {
                assert(switch (section.comdat) {
                    .NONE, .ASSOCIATIVE => true,
                    else => if (section.comdat_psi.unwrap()) |psi|
                        pending_symbols.values()[psi].si != .null
                    else
                        pending_symbols.values()[section.psi.unwrap().?].si != .null,
                });
                continue;
            },
            .pending => unreachable,
        }

        // Until we support sorting .pdata, we shouldn't merge these in, the result would be invalid
        const section_name = section.name.toSlice(coff);
        if (std.mem.startsWith(u8, section_name, ".pdata"))
            continue;

        num_included_sections += 1;
        num_included_symbols += section.num_symbols;
        num_included_relocs += section.header.number_of_relocations;

        section.parent_si = (try coff.objectSectionMapIndex(
            section.name,
            section.header.flags.ALIGN.alignment() orelse .@"1",
            .fromFlags(section.header.flags),
        )).symbol(coff);
    }

    try coff.nodes.ensureUnusedCapacity(gpa, num_included_sections);
    try coff.relocs.ensureUnusedCapacity(gpa, num_included_relocs);
    try coff.symbols.ensureUnusedCapacity(gpa, num_included_symbols + num_included_sections);
    try coff.input_sections.ensureUnusedCapacity(gpa, num_included_sections);

    for (sections) |*section| {
        if (section.parent_si == .null) continue;

        const ni = try coff.mf.addLastChildNode(gpa, section.parent_si.node(coff), .{
            .size = section.header.size_of_raw_data,
            .alignment = section.header.flags.ALIGN.alignment() orelse .@"1",
            .moved = true,
        });
        coff.nodes.appendAssumeCapacity(.{ .input_section = @enumFromInt(coff.input_sections.items.len) });

        section.si = coff.addSymbolAssumeCapacity();
        if (section.psi.unwrap()) |psi|
            pending_symbols.values()[psi].si = section.si;

        const sym = section.si.get(coff);
        sym.ni = ni;
        sym.section_number = section.parent_si.get(coff).section_number;

        coff.input_sections.addOneAssumeCapacity().* = .{
            .ioi = ioi,
            .si = section.si,
            .file_location = .{
                .offset = fl.offset + section.header.pointer_to_raw_data,
                .size = section.header.size_of_raw_data,
            },
            .first_li = @enumFromInt(coff.input_symbols.items.len),
            .crc = section.comdat_crc,
            .comdat_si = if (section.comdat_psi.unwrap()) |psi|
                pending_symbols.values()[psi].si
            else
                .null,
        };

        log.debug(
            "addInputSection({s}, 0x{x}) = {d}@{d}",
            .{ section.name.toSlice(coff), section.comdat_crc, section.si, sym.section_number },
        );
        coff.synth_prog_node.increaseEstimatedTotalItems(1);
    }

    for (pending_symbols.values(), pending_symbols.keys(), 0..) |*symbol, index, i| {
        switch (symbol.value) {
            .weak_external_aux => continue,
            else => {},
        }

        defer log.debug("addInputSymbol({s}, 0x{x}@{d}, {t}=0x{x}) = n{d} {d}@{d}", .{
            symbol.name.toSlice(coff),
            index,
            symbol.section_number,
            symbol.value,
            switch (symbol.value) {
                .weak_external_aux => unreachable,
                inline else => |v| v,
            },
            symbol.si.get(coff).ni,
            symbol.si,
            symbol.si.get(coff).section_number,
        });

        const section = switch (symbol.section_number) {
            .UNDEFINED => switch (symbol.value) {
                .section,
                .static,
                .weak_external_aux,
                => unreachable,
                .external => {
                    if (symbol.weak_external_psi.unwrap()) |weak_external_i| {
                        // If the alias itself is an undef external, we need to wait until flushing the weak
                        // external global before creating a global for the alias, as another input could
                        // still provide the weak external.
                        const weak_sym = pending_symbols.values()[weak_external_i].si.get(coff);
                        weak_sym.setValue(.{ .weak_alias_name = symbol.name });
                        weak_sym.flags.weak_external_strat = pending_symbols.values()[weak_external_i + 1].value.weak_external_aux;
                    }

                    // Deferred until referenced by a reloc in this object.
                    // vcruntime.lib defines symbols like this (ie. memcpy_$fo$) that are not referenced
                    continue;
                },
                .weak_external => |alias_index| {
                    const global_gop = try coff.getOrPutGlobalSymbol(.{ .name = symbol.name.toSlice(coff) });
                    symbol.si = global_gop.value_ptr.si;
                    if (!global_gop.found_existing or symbol.si.get(coff).ni == .none) {
                        const sym = symbol.si.get(coff);
                        const alias = pending_symbols.getPtr(alias_index) orelse
                            return diags.failParse(
                                path,
                                "weak external 0x{x} {s}{f} targets unknown symbol index 0x{x}",
                                .{
                                    index,
                                    symbol.name.toSlice(coff),
                                    fmtMemberNameString(member_name),
                                    alias_index,
                                },
                            );

                        if (alias.si == .null and alias_index > index) {
                            // Resolve this once we see alias
                            alias.weak_external_psi = .wrap(@intCast(i));
                        } else {
                            sym.setValue(if (alias.si.unwrap()) |alias_si| .{
                                .weak_alias_si = alias_si,
                            } else .{
                                .weak_alias_name = alias.name,
                            });
                            sym.flags.weak_external_strat = pending_symbols.values()[i + 1].value.weak_external_aux;
                        }
                    }

                    continue;
                },
            },
            .ABSOLUTE => {
                const value = sym: switch (symbol.value) {
                    .static => |value| {
                        symbol.si = coff.addSymbolAssumeCapacity();
                        break :sym value;
                    },
                    .external => |value| {
                        const global_gop = try coff.getOrPutGlobalSymbol(.{ .name = symbol.name.toSlice(coff) });
                        symbol.si = global_gop.value_ptr.si;
                        if (global_gop.found_existing)
                            return coff.failMultipleDefinitions(
                                path,
                                member_name,
                                symbol.name,
                                index,
                                global_gop.value_ptr.si,
                                .none,
                            );
                        break :sym value;
                    },
                    else => unreachable,
                };

                const sym = symbol.si.get(coff);
                sym.rva = value;
                sym.section_number = .ABSOLUTE;
                continue;
            },
            .DEBUG => continue,
            else => |sn| &sections[sn.toIndex()],
        };

        if (section.si == .null)
            continue;

        if (symbol.si == .null) {
            switch (symbol.value) {
                .section => unreachable,
                .static => {
                    symbol.si = coff.addSymbolAssumeCapacity();
                },
                .external => {
                    assert(index != section.comdat_psi.unwrap());
                    const global_gop = try coff.getOrPutGlobalSymbol(.{ .name = symbol.name.toSlice(coff) });
                    symbol.si = global_gop.value_ptr.si;

                    const sym = symbol.si.get(coff);
                    if (global_gop.found_existing and sym.ni != .none)
                        return coff.failMultipleDefinitions(
                            path,
                            member_name,
                            symbol.name,
                            index,
                            global_gop.value_ptr.si,
                            .none,
                        );
                },
                .weak_external,
                .weak_external_aux,
                => unreachable,
            }

            if (section.comdat_psi.unwrap() == @as(u32, @intCast(i)))
                coff.getNode(section.si.get(coff).ni).input_section.inputSection(coff).comdat_si = symbol.si;
        }

        if (symbol.weak_external_psi.unwrap()) |weak_external_i| {
            assert(symbol.si != .null);
            const weak_sym = pending_symbols.values()[weak_external_i].si.get(coff);
            weak_sym.setValue(.{ .weak_alias_si = symbol.si });
            weak_sym.flags.weak_external_strat = pending_symbols.values()[weak_external_i + 1].value.weak_external_aux;
        }

        if (section.si != symbol.si) {
            const sym = symbol.si.get(coff);
            assert(sym.ni == .none);
            sym.ni = section.si.get(coff).ni;
            switch (symbol.value) {
                .section => |v| sym.setExtra(.{ .size = v }),
                .static => |v| sym.setValue(.{ .node_offset = v }),
                .external => |v| switch (symbol.section_number) {
                    .UNDEFINED, .ABSOLUTE, .DEBUG => unreachable,
                    else => sym.setValue(.{ .node_offset = v }),
                },
                .weak_external,
                .weak_external_aux,
                => unreachable,
            }

            sym.section_number = section.si.get(coff).section_number;
        }
    }

    const relocation_size = std.coff.Relocation.sizeOf();
    for (sections) |section| {
        if (section.si == .null) continue;

        const loc_sym = section.si.get(coff);
        assert(loc_sym.loc_relocs == .none);
        loc_sym.loc_relocs = @enumFromInt(coff.relocs.items.len);

        if (section.header.number_of_relocations == 0) continue;

        try fr.seekTo(fl.offset + section.header.pointer_to_relocations);
        for (0..section.header.number_of_relocations) |reloc_i| {
            var reloc: std.coff.Relocation = undefined;
            @memcpy(std.mem.asBytes(&reloc)[0..relocation_size], try r.take(relocation_size));
            if (target_endian != native_endian)
                std.mem.byteSwapAllFields(std.coff.Relocation, &reloc);

            const symbol = pending_symbols.getPtr(reloc.symbol_table_index) orelse
                return diags.failParse(
                    path,
                    "relocation 0x{x} in section '{s}' of {f}{f} targets invalid symbol index 0x{x}",
                    .{
                        reloc_i,
                        section.name.toSlice(coff),
                        path.fmtEscapeString(),
                        fmtMemberNameString(member_name),
                        reloc.symbol_table_index,
                    },
                );

            if (symbol.si == .null) {
                assert(symbol.section_number == .UNDEFINED);
                switch (symbol.value) {
                    .external => |size| {
                        const global_gop = try coff.getOrPutGlobalSymbol(.{ .name = symbol.name.toSlice(coff) });
                        symbol.si = global_gop.value_ptr.si;
                        if (!global_gop.found_existing or symbol.si.get(coff).ni == .none) {
                            const sym = symbol.si.get(coff);
                            sym.setExtra(.{ .size = @max(sym.size(), size) });
                        }
                    },
                    else => unreachable,
                }
            }

            assert(symbol.si != .null);
            try coff.addReloc(
                section.si,
                reloc.virtual_address - section.header.virtual_address,
                symbol.si,
                .pending,
                .{ .u16 = reloc.type },
            );
        }
    }

    // Set up contiguous symbol ranges in `input_symbols` for both symbols we just created,
    // and symbols that were previously created as undefined, but we just defined.
    const SortContext = struct {
        v: []const PendingSymbol,

        pub fn lessThan(ctx: @This(), a_index: usize, b_index: usize) bool {
            const lhs = &ctx.v[a_index];
            const rhs = &ctx.v[b_index];
            if (lhs.section_number == rhs.section_number)
                return @intFromEnum(lhs.si) < @intFromEnum(rhs.si);
            return @intFromEnum(lhs.section_number) < @intFromEnum(rhs.section_number);
        }
    };

    pending_symbols.sortUnstable(SortContext{ .v = pending_symbols.values() });

    try coff.input_symbols.ensureUnusedCapacity(gpa, num_included_symbols + num_included_sections);
    var prev_sn: Symbol.SectionNumber = .DEBUG;
    var include_section = false;
    for (pending_symbols.values()) |symbol| {
        // The symbol may have not been included, or it's an undefined external / aux
        if (symbol.si == .null or symbol.si.get(coff).ni == .none) continue;

        if (prev_sn != symbol.section_number) {
            prev_sn = symbol.section_number;
            if (symbol.section_number.hasIndex()) {
                const section = &sections[symbol.section_number.toIndex()];
                include_section = section.comdat_result == .include;
                if (include_section) {
                    const isi = coff.getNode(section.si.get(coff).ni).input_section;
                    isi.inputSection(coff).first_li = @enumFromInt(coff.input_symbols.items.len);
                }
            }
        }

        if (include_section) {
            assert(coff.getNode(symbol.si.get(coff).ni) == .input_section);
            symbol.si.get(coff).setExtra(.{ .isli = @enumFromInt(coff.input_symbols.items.len) });
            coff.input_symbols.addOneAssumeCapacity().* = .{
                .si = symbol.si,
                .name = symbol.name,
            };
        }
    }
}

fn failMultipleDefinitions(
    coff: *Coff,
    path: std.Build.Cache.Path,
    member_name: ?[]const u8,
    name: String,
    index: u32,
    existing_si: Symbol.Index,
    comdat_reason: union(enum) {
        none: void,
        duplicate: void,
        size: struct { a: u64, b: u64 },
        crc: struct { a: u32, b: u32 },
    },
) error{ AlreadyReported, OutOfMemory } {
    const num_notes: usize = 2 + @as(usize, @intFromBool(comdat_reason != .none));
    var err = try coff.base.comp.link_diags.addErrorWithNotes(num_notes);
    try err.addMsg("multiple definitions of '{s}'", .{name.toSlice(coff)});

    switch (coff.getNode(existing_si.get(coff).ni)) {
        .input_section => |isi| {
            const other_ioi = isi.input(coff);
            err.addNote("first seen in input '{f}{f}'", .{
                other_ioi.path(coff).fmtEscapeString(),
                fmtMemberNameString(other_ioi.memberName(coff)),
            });
        },
        .nav, .uav => err.addNote("first seen in module '{s}'", .{
            coff.base.comp.zcu.?.root_mod.fully_qualified_name,
        }),
        else => unreachable,
    }

    err.addNote("defined again in input '{f}{f}' (0x{x}))", .{ path, fmtMemberNameString(member_name), index });
    switch (comdat_reason) {
        .none => {},
        .duplicate => err.addNote("COMDAT rule requires no duplicates", .{}),
        .size => |s| err.addNote(
            "COMDAT rule require duplicates to have the same size ({d} vs {d})",
            .{ s.a, s.b },
        ),
        .crc => |s| err.addNote(
            "COMDAT rule require duplicates to have the same CRC (0x{x} vs 0x{x})",
            .{ s.a, s.b },
        ),
    }

    return error.AlreadyReported;
}

const ArchiveMemberHeader = struct {
    name: []const u8,
    size: u34,
};

/// Return value lifetime is that of `header`
fn parseArchiveMemberHeader(
    diags: *link.Diags,
    path: std.Build.Cache.Path,
    header: *const std.coff.ArchiveMemberHeader,
    opt_longnames: ?[]const u8,
) !ArchiveMemberHeader {
    return parseArchiveMemberHeaderInner(header, opt_longnames) catch |err| switch (err) {
        error.BadName => return diags.failParse(path, "malformed member name: '{s}'", .{&header.name}),
        error.BadSize => return diags.failParse(path, "malformed member size: '{s}'", .{&header.size}),
        error.BadEndOfHeader => return diags.failParse(path, "end of header was invalid", .{}),
        error.NoLongNames => return diags.failParse(path, "long name used without longnames member", .{}),
    };
}

fn parseArchiveMemberHeaderInner(
    header: *const std.coff.ArchiveMemberHeader,
    opt_longnames: ?[]const u8,
) !ArchiveMemberHeader {
    const name = try header.parseName(opt_longnames);
    const size = header.parseSize() catch return error.BadSize;

    if (!std.mem.eql(u8, &header.end_of_header, std.coff.archive_end_of_header))
        return error.BadEndOfHeader;

    return .{
        .name = name,
        .size = size,
    };
}

fn loadArchive(coff: *Coff, path: std.Build.Cache.Path, fr: *Io.File.Reader) LoadInputError!void {
    const comp = coff.base.comp;
    const gpa = comp.gpa;
    const diags = &comp.link_diags;
    const r = &fr.interface;
    const target_endian = coff.targetEndian();

    log.debug("loadArchive({f})", .{path.fmtEscapeString()});

    const signature = try r.take(std.coff.archive_signature.len);
    if (!std.mem.eql(u8, signature, std.coff.archive_signature))
        return diags.failParse(path, "bad signature", .{});

    var opt_expected_kind: ?std.coff.ArchiveMemberHeader.Kind = .first_linker;
    var opt_longnames: ?[]const u8 = null;
    defer if (opt_longnames) |l| gpa.free(l);

    var members: std.ArrayList(struct {
        offset: u32,
        iami: ?InputArchive.Member.Index,
    }) = .empty;
    var symbol_member_indices: std.ArrayList(u32) = .empty;

    const iai: InputArchive.Index = @enumFromInt(coff.input_archives.items.len);
    (try coff.input_archives.addOne(gpa)).* = .{
        .path = path,
    };

    const first_iami = coff.input_archive_members.items.len;
    const first_iamsi = coff.input_archive_symbols.items.len;
    const first_symbol_indices_index = coff.input_archive_symbol_indices.count();

    errdefer {
        for (coff.input_archive_symbol_indices.values()) |*v| {
            if (@intFromEnum(v.last) < first_iamsi) continue;
            if (@intFromEnum(v.first) >= first_iamsi) continue;

            var iter = v.first;
            v.last = while (iter != v.last) {
                const sym = &coff.input_archive_symbols.items[@intFromEnum(iter)];
                if (@intFromEnum(sym.next) >= first_iamsi) {
                    sym.next = iter;
                    break iter;
                }

                iter = sym.next;
            } else unreachable;
        }

        // New entries in this map will only have pointed to iamsi we also just added
        coff.input_archive_symbol_indices.shrinkRetainingCapacity(first_symbol_indices_index);
        coff.input_archive_symbols.shrinkRetainingCapacity(first_iamsi);
        coff.input_archive_members.shrinkRetainingCapacity(first_iami);
        _ = coff.input_archives.pop();
    }

    var pos = fr.logicalPos();
    const size = try fr.getSize();
    while (pos < size) : (pos = fr.logicalPos()) {
        if ((pos & 1) != 0) try r.discardAll(1);
        const header = try r.takeStruct(std.coff.ArchiveMemberHeader, target_endian);
        const res = try parseArchiveMemberHeader(diags, path, &header, opt_longnames);

        const member_end = fr.logicalPos() + res.size;
        if (member_end > size)
            return diags.failParse(path, "out-of-bounds length 0x{x} in member '{s}'", .{ res.size, res.name });

        log.debug("loadArchiveMember({s})", .{res.name});

        if (opt_expected_kind) |expected_kind| switch (expected_kind) {
            .first_linker => {
                if (!std.mem.eql(u8, res.name, "/"))
                    return diags.failParse(path, "expected first linker member, found '{s}'", .{res.name});

                try fr.seekTo(fr.logicalPos() + res.size);
                opt_expected_kind = .second_linker;
                continue;
            },
            .second_linker => {
                if (!std.mem.eql(u8, res.name, "/"))
                    return diags.failParse(path, "expected second linker member, found '{s}'", .{res.name});

                const num_members = try r.takeInt(u32, target_endian);
                pos = fr.logicalPos();
                if (pos + num_members * @sizeOf(u32) > member_end)
                    return diags.failParse(path, "invalid member count 0x{x} in second linker member", .{num_members});

                try members.ensureTotalCapacity(gpa, num_members);
                for (0..num_members) |_|
                    members.addOneAssumeCapacity().* = .{
                        .offset = try r.takeInt(u32, target_endian),
                        .iami = null,
                    };

                const num_symbols = try r.takeInt(u32, target_endian);
                pos = fr.logicalPos();
                if (pos + num_symbols * @sizeOf(u16) > member_end)
                    return diags.failParse(path, "invalid symbol count 0x{x} in second linker member", .{num_symbols});

                try symbol_member_indices.ensureTotalCapacity(gpa, num_symbols);
                for (0..num_symbols) |_|
                    symbol_member_indices.addOneAssumeCapacity().* = (try r.takeInt(u16, target_endian)) - 1;

                pos = fr.logicalPos();
                try coff.ensureManyUnusedStringCapacity(num_symbols, @intCast(member_end - pos));
                try coff.input_archive_members.ensureUnusedCapacity(gpa, num_members);
                try coff.input_archive_symbols.ensureUnusedCapacity(gpa, num_symbols);
                try coff.input_archive_symbol_indices.ensureUnusedCapacity(gpa, num_symbols);

                var symbol_i: u32 = 0;
                while (pos < member_end and symbol_i < num_symbols) : ({
                    pos = fr.logicalPos();
                    symbol_i += 1;
                }) {
                    const name = if (r.takeDelimiter(0) catch |err| switch (err) {
                        error.StreamTooLong => null,
                        else => |e| return e,
                    }) |n| n else return diags.failParse(path, "unterminated string found in second linker member", .{});

                    const string = coff.getOrPutStringAssumeCapacity(name);
                    const iamsi: InputArchive.Member.Symbol.Index = @enumFromInt(coff.input_archive_symbols.items.len);
                    const symbol_gop = coff.input_archive_symbol_indices.getOrPutAssumeCapacity(string);
                    if (!symbol_gop.found_existing) {
                        symbol_gop.value_ptr.* = .{
                            .first = iamsi,
                            .last = iamsi,
                        };
                    } else {
                        coff.input_archive_symbols.items[@intFromEnum(symbol_gop.value_ptr.last)].next = iamsi;
                        symbol_gop.value_ptr.last = iamsi;
                    }

                    const iami = members.items[symbol_member_indices.items[symbol_i]].iami orelse iami: {
                        const iami: InputArchive.Member.Index = @enumFromInt(coff.input_archive_members.items.len);
                        const member_offset = members.items[symbol_member_indices.items[symbol_i]].offset;
                        coff.input_archive_members.addOneAssumeCapacity().* = .{
                            .iai = iai,
                            .name = undefined,
                            .content = .{
                                .object = .{
                                    .offset = member_offset,
                                    .size = undefined,
                                },
                            },
                            .flags = .{
                                .is_loaded = false,
                            },
                        };

                        members.items[symbol_member_indices.items[symbol_i]].iami = iami;
                        break :iami iami;
                    };

                    log.debug("loadArchiveMemberSymbol({s}) = ({d}, {d}, {d})", .{ name, iai, iami, iamsi });

                    coff.input_archive_symbols.addOneAssumeCapacity().* = .{
                        .iami = iami,
                        .next = iamsi,
                    };
                }

                if (symbol_i != num_symbols)
                    return diags.failParse(
                        path,
                        " expected {d} entries in second linker member string table, but found {d}",
                        .{ num_symbols, symbol_i },
                    );

                try fr.seekTo(member_end);
                opt_expected_kind = .longnames;
                continue;
            },
            .longnames => {
                // This member is optional
                if (std.mem.eql(u8, res.name, "//"))
                    opt_longnames = try r.readAlloc(gpa, @intCast(res.size));

                opt_expected_kind = null;
                break;
            },
            else => unreachable,
        };
    }

    if (opt_expected_kind) |expected_kind| switch (expected_kind) {
        .first_linker => return diags.failParse(path, "missing first linker member", .{}),
        .second_linker => return diags.failParse(path, "missing second linker member", .{}),
        else => {},
    };

    // Validate / read names and sizes of all the referenced members, enumerate imports
    for (coff.input_archive_members.items[first_iami..]) |*member| {
        try fr.seekTo(member.content.object.offset);

        const header = try r.takeStruct(std.coff.ArchiveMemberHeader, target_endian);
        const res = try parseArchiveMemberHeader(diags, path, &header, opt_longnames);

        try coff.ensureUnusedStringCapacity(res.name.len);
        member.name = coff.getOrPutStringAssumeCapacity(res.name);

        const member_sig = try r.peek(4);
        const machine: std.coff.IMAGE.FILE.MACHINE =
            @enumFromInt(std.mem.readInt(u16, member_sig[0..2], target_endian));
        const sig = std.mem.readInt(u16, member_sig[2..4], target_endian);

        log.debug("verifyArchiveMember({s}) = 0x{x}+{x}", .{
            res.name,
            member.content.object.offset,
            res.size,
        });

        const expected_machine = comp.root_mod.resolved_target.result.toCoffMachine();
        if (machine == std.coff.IMAGE.FILE.MACHINE.UNKNOWN and sig == 0xffff) {
            const import_header = try r.takeStruct(std.coff.ImportHeader, target_endian);
            const strings = r.take(import_header.size_of_data) catch |err| switch (err) {
                error.EndOfStream => return diags.failParse(path, "invalid data size in import header '{s}'", .{res.name}),
                else => |e| return e,
            };

            var split = std.mem.splitScalar(u8, strings, 0);
            const symbol_name = split.next() orelse
                return diags.failParse(path, "invalid symbol name string in import header '{s}'", .{res.name});
            var lib_name = split.next() orelse
                return diags.failParse(path, "invalid dll name string in import header '{s}' ('{s}')", .{ res.name, symbol_name });

            if (import_header.machine != expected_machine)
                return diags.failParse(path, "machine mismatch in import header '{s}' ('{s}'): expected {t}, found {t}", .{
                    res.name,
                    symbol_name,
                    expected_machine,
                    machine,
                });

            const ext = ".dll";
            if (!std.mem.endsWith(u8, lib_name, ext))
                return diags.failParse(
                    path,
                    "unexpected extension for import '{s} ('{s}'): '{s}'",
                    .{ res.name, symbol_name, lib_name },
                );

            lib_name = lib_name[0 .. lib_name.len - ext.len];
            log.debug("verifyArchiveImportHeader({s}, {s}, {s}) = {t} ({t})", .{
                res.name,
                symbol_name,
                lib_name,
                import_header.types.type,
                import_header.types.name_type,
            });

            try coff.ensureManyUnusedStringCapacity(2, strings.len - ext.len);
            member.content = .{
                .import = .{
                    .symbol_name = coff.getOrPutStringAssumeCapacity(symbol_name),
                    .lib_name = coff.getOrPutStringAssumeCapacity(lib_name),
                    .import_ordinal_hint = import_header.hint,
                    .type = import_header.types.type,
                    .name_type = import_header.types.name_type,
                },
            };
        } else {
            member.content.object.size = res.size;
            // Microsoft's CRT contains members that set .UNKNOWN but do have undef symbols
            if (machine != expected_machine and machine != .UNKNOWN) {
                return diags.failParse(path, "machine mismatch in member header '{s}': expected {t}, found {t}", .{
                    res.name,
                    expected_machine,
                    machine,
                });
            }
        }
    }
}

fn loadRes(coff: *Coff, path: std.Build.Cache.Path, fr: *Io.File.Reader) LoadInputError!void {
    const comp = coff.base.comp;
    const gpa = comp.gpa;
    const diags = &comp.link_diags;
    const r = &fr.interface;

    log.debug("loadRes({f})", .{path.fmtEscapeString()});

    _ = gpa;
    _ = diags;
    _ = r;
}

fn loadDll(coff: *Coff, path: std.Build.Cache.Path, fr: *Io.File.Reader) LoadInputError!void {
    const comp = coff.base.comp;
    const gpa = comp.gpa;
    const diags = &comp.link_diags;
    const r = &fr.interface;

    log.debug("loadDll({f})", .{path.fmtEscapeString()});

    _ = gpa;
    _ = diags;
    _ = r;
}

pub fn prelink(coff: *Coff, prog_node: std.Progress.Node) link.Error!void {
    _ = prog_node;
    const base = coff.base;
    const comp = base.comp;

    log.debug("prelink()", .{});

    if (coff.pending_default_libs.items.len > 0) {
        // Libs provided by /DEFAULTLIB arguments in objects are searched after all other inputs
        const gpa = comp.gpa;
        const arena = comp.arena;
        const target = &comp.root_mod.resolved_target.result;

        defer {
            for (coff.pending_default_libs.items) |l| gpa.free(l.path);
            coff.pending_default_libs.clearAndFree(gpa);
        }

        assert(comp.config.link_libc);
        const libc_installation = comp.libc_installation.?;
        const all_paths: [3]?[]const u8 = .{
            libc_installation.crt_dir,
            libc_installation.msvc_lib_dir,
            libc_installation.kernel32_lib_dir,
        };
        const search_paths = all_paths[0..if (target.abi == .msvc or target.abi == .itanium) 3 else 1];
        lib: for (coff.pending_default_libs.items) |lib| {
            if (!std.mem.eql(u8, std.fs.path.extension(lib.path), ".lib"))
                return comp.link_diags.failParse(
                    lib.ioi.path(coff),
                    "/DEFAULTLIB library '{s}' had unexpected extension",
                    .{lib.path},
                );

            log.debug("loadDefaultLib({s}, {f})", .{ lib.path, lib.ioi.path(coff) });
            for (search_paths) |opt_path| if (opt_path) |search_path| {
                const lib_path = try Path.initCwd(search_path).join(arena, lib.path);
                const archive = link.openObject(comp.io, lib_path, false, false) catch |err| switch (err) {
                    error.FileNotFound => {
                        arena.free(lib_path.sub_path);
                        continue;
                    },
                    else => |e| return comp.link_diags.failParse(
                        lib.ioi.path(coff),
                        "error opening /DEFAULTLIB library '{s}': {t}",
                        .{ lib.path, e },
                    ),
                };
                errdefer archive.file.close(comp.io);

                coff.loadInput(.{ .archive = archive }) catch |err| switch (err) {
                    else => |e| return comp.link_diags.failParse(
                        lib.ioi.path(coff),
                        "error loading /DEFAULTLIB library '{s}': {t}",
                        .{ lib.path, e },
                    ),
                };

                break :lib;
            };

            return comp.link_diags.failParse(
                lib.ioi.path(coff),
                "/DEFAULTLIB library '{s}' was not found",
                .{lib.path},
            );
        }
    }

    coff.inputs_complete = true;
    if (comp.zcu == null)
        coff.exports_complete = true;
}

pub fn updateNav(coff: *Coff, pt: Zcu.PerThread, nav_index: InternPool.Nav.Index) link.Error!void {
    coff.updateNavInner(pt, nav_index) catch |err| switch (err) {
        error.MappedFileIo => return coff.base.cgFail(
            nav_index,
            "linker failed to update variable: {t}",
            .{coff.mf.io_err.?},
        ),
        else => |e| return e,
    };
}
fn updateNavInner(coff: *Coff, pt: Zcu.PerThread, nav_index: InternPool.Nav.Index) !void {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;
    const ip = &zcu.intern_pool;

    const nav = ip.getNav(nav_index);
    if (ip.indexToKey(nav.resolved.?.value) == .@"extern") return;
    if (!Type.fromInterned(nav.resolved.?.type).hasRuntimeBits(zcu)) return;

    const nmi = try coff.navMapIndex(zcu, nav_index);
    const si = nmi.symbol(coff);
    log.debug("updateNav({f}) = {d}", .{ nav.fqn.fmt(ip), si });
    const ni = ni: {
        switch (si.get(coff).ni) {
            .none => {
                const sec_si = try coff.navSection(zcu, nav.resolved.?);
                try coff.nodes.ensureUnusedCapacity(gpa, 1);
                if (!isImage(coff)) try coff.symbol_table.symbols.ensureUnusedCapacity(gpa, 1);
                const ni = try coff.mf.addLastChildNode(gpa, sec_si.node(coff), .{
                    .alignment = zcu.navAlignment(nav_index).toStdMem(),
                    .moved = true,
                });
                coff.nodes.appendAssumeCapacity(.{ .nav = nmi });
                const sym = si.get(coff);
                sym.ni = ni;
                sym.section_number = sec_si.get(coff).section_number;
            },
            else => si.deleteLocationRelocs(coff),
        }
        const sym = si.get(coff);
        assert(sym.loc_relocs == .none);
        sym.loc_relocs = @enumFromInt(coff.relocs.items.len);
        if (!isImage(coff) and sym.target_relocs != .none)
            try coff.pendingSymbolTableEntry(si);

        break :ni sym.ni;
    };

    {
        var nw: MappedFile.Node.Writer = undefined;
        ni.writer(&coff.mf, gpa, &nw);
        defer nw.deinit();
        codegen.generateSymbol(
            &coff.base,
            pt,
            .fromInterned(nav.resolved.?.value),
            &nw.interface,
            .{ .atom_index = @enumFromInt(@intFromEnum(si)) },
        ) catch |err| switch (err) {
            error.WriteFailed => return nw.err.?,
            else => |e| return e,
        };
        si.get(coff).extra.size = @intCast(nw.interface.end);
        try si.applyLocationRelocs(coff);
    }

    if (nav.resolved.?.@"linksection".unwrap()) |_| {
        try ni.resize(&coff.mf, gpa, si.get(coff).extra.size);
        var parent_ni = ni;
        while (true) {
            parent_ni = parent_ni.parent(&coff.mf);
            switch (coff.getNode(parent_ni)) {
                else => unreachable,
                .image_section, .pseudo_section => break,
                .object_section => {
                    var child_it = parent_ni.reverseChildren(&coff.mf);
                    const last_offset, const last_size =
                        child_it.next().?.location(&coff.mf).resolve(&coff.mf);
                    try parent_ni.resize(&coff.mf, gpa, last_offset + last_size);
                },
            }
        }
    }
}

pub fn lowerUav(
    coff: *Coff,
    pt: Zcu.PerThread,
    uav_val: InternPool.Index,
    uav_align: InternPool.Alignment,
) link.Error!link.File.SymbolId {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;

    try coff.pending_uavs.ensureUnusedCapacity(gpa, 1);
    const umi = try coff.uavMapIndex(uav_val);
    const si = umi.symbol(coff);
    if (switch (si.get(coff).ni) {
        .none => true,
        else => |ni| uav_align.toStdMem().order(ni.alignment(&coff.mf)).compare(.gt),
    }) {
        const gop = coff.pending_uavs.getOrPutAssumeCapacity(umi);
        if (gop.found_existing) {
            gop.value_ptr.alignment = gop.value_ptr.alignment.max(uav_align);
        } else {
            gop.value_ptr.* = .{
                .alignment = uav_align,
            };
            coff.const_prog_node.increaseEstimatedTotalItems(1);
        }
    }
    return @enumFromInt(@intFromEnum(si));
}

pub fn updateFunc(
    coff: *Coff,
    pt: Zcu.PerThread,
    func_index: InternPool.Index,
    mir: *const codegen.AnyMir,
) link.Error!void {
    coff.updateFuncInner(pt, func_index, mir) catch |err| switch (err) {
        else => |e| return e,
        error.MappedFileIo => return coff.base.cgFail(
            pt.zcu.funcInfo(func_index).owner_nav,
            "linker failed to update function: {t}",
            .{coff.mf.io_err.?},
        ),
    };
}
fn updateFuncInner(
    coff: *Coff,
    pt: Zcu.PerThread,
    func_index: InternPool.Index,
    mir: *const codegen.AnyMir,
) !void {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;
    const ip = &zcu.intern_pool;
    const func = zcu.funcInfo(func_index);
    const nav = ip.getNav(func.owner_nav);

    const nmi = try coff.navMapIndex(zcu, func.owner_nav);
    const si = nmi.symbol(coff);
    log.debug("updateFunc({f}) = {d}", .{ nav.fqn.fmt(ip), si });
    const ni = ni: {
        switch (si.get(coff).ni) {
            .none => {
                const sec_si = try coff.navSection(zcu, nav.resolved.?);
                try coff.nodes.ensureUnusedCapacity(gpa, 1);
                if (!isImage(coff)) try coff.symbol_table.symbols.ensureUnusedCapacity(gpa, 1);
                const mod = zcu.navFileScope(func.owner_nav).mod.?;
                const target = &mod.resolved_target.result;
                const ni = try coff.mf.addLastChildNode(gpa, sec_si.node(coff), .{
                    .alignment = switch (nav.resolved.?.@"align") {
                        .none => switch (mod.optimize_mode) {
                            .Debug,
                            .ReleaseSafe,
                            .ReleaseFast,
                            => target_util.defaultFunctionAlignment(target),
                            .ReleaseSmall => target_util.minFunctionAlignment(target),
                        },
                        else => |a| a.maxStrict(target_util.minFunctionAlignment(target)),
                    }.toStdMem(),
                    .moved = true,
                });
                coff.nodes.appendAssumeCapacity(.{ .nav = nmi });
                const sym = si.get(coff);
                sym.ni = ni;
                sym.section_number = sec_si.get(coff).section_number;
            },
            else => si.deleteLocationRelocs(coff),
        }
        const sym = si.get(coff);
        assert(sym.loc_relocs == .none);
        sym.loc_relocs = @enumFromInt(coff.relocs.items.len);
        if (!isImage(coff) and sym.target_relocs != .none)
            try coff.pendingSymbolTableEntry(si);
        break :ni sym.ni;
    };

    var nw: MappedFile.Node.Writer = undefined;
    ni.writer(&coff.mf, gpa, &nw);
    defer nw.deinit();
    codegen.emitFunction(
        &coff.base,
        pt,
        func_index,
        @enumFromInt(@intFromEnum(si)),
        mir,
        &nw.interface,
        .none,
    ) catch |err| switch (err) {
        error.WriteFailed => return nw.err.?,
        else => |e| return e,
    };
    si.get(coff).extra.size = @intCast(nw.interface.end);
    try si.applyLocationRelocs(coff);
}

pub fn updateErrorData(coff: *Coff, pt: Zcu.PerThread) !void {
    coff.flushLazy(pt, .{
        .kind = .const_data,
        .index = @intCast(coff.lazy.getPtr(.const_data).map.getIndex(.anyerror_type) orelse return),
    }) catch |err| switch (err) {
        else => |e| return e,
        error.MappedFileIo => return coff.base.comp.link_diags.fail(
            "updateErrorData failed: {t}",
            .{coff.mf.io_err.?},
        ),
    };
}

fn flushImplib(
    coff: *Coff,
    implib_file: []const u8,
) !void {
    // Emitting implibs is only valid for images
    assert(coff.export_table.ni != .none);

    const comp = coff.base.comp;
    const gpa = comp.gpa;
    const io = comp.io;

    const image_name = std.mem.sliceTo(
        coff.export_table.ni.slice(&coff.mf)[@sizeOf(std.coff.ExportDirectoryTable)..],
        0,
    );
    const machine_type = coff.targetLoad(&coff.headerPtr().machine);
    const members = members: {
        const def_arena: std.heap.ArenaAllocator = .init(gpa);
        var def: ModuleDefinition = .{
            .name = image_name,
            .arena = def_arena,
            .type = .mingw,
        };
        defer def.deinit();

        try def.exports.ensureUnusedCapacity(
            def.arena.allocator(),
            coff.export_table.entries.count(),
        );

        const name_table_slice = coff.export_table.name_table_ni.slice(&coff.mf);
        for (coff.export_table.entries.values(), 0..) |entry, ord| {
            const name = name_table_slice[entry.name_index..][0..entry.name_len];
            const section_number = entry.si.get(coff).section_number;
            const import_type: std.coff.ImportType = switch (section_number.symbol(coff)) {
                .data, .rdata => .DATA,
                .text => .CODE,
                else => return comp.link_diags.fail(
                    "unsupported section for export '{s}': {s}",
                    .{ name, &section_number.header(coff).name },
                ),
            };

            def.exports.appendAssumeCapacity(.{
                .name = name,
                .mangled_symbol_name = null,
                .ext_name = null,
                .import_name = null,
                .export_as = null,
                .no_name = false,
                .ordinal = @intCast(ord),
                .type = import_type,
                .private = false,
            });
        }

        def.fixupForImportLibraryGeneration(machine_type);
        break :members try implib.getMembers(gpa, def, machine_type);
    };
    defer members.deinit();

    const lib_sub_path = try std.fs.path.join(gpa, &.{
        std.fs.path.dirname(coff.base.emit.sub_path) orelse "",
        implib_file,
    });
    defer gpa.free(lib_sub_path);

    const lib_final_file = try coff.base.emit.root_dir.handle.createFile(io, lib_sub_path, .{ .truncate = true });
    defer lib_final_file.close(io);
    var buffer: [1024]u8 = undefined;
    var file_writer = lib_final_file.writer(io, &buffer);
    try implib.writeCoffArchive(gpa, &file_writer.interface, members);
    try file_writer.interface.flush();
}

fn reportUndefs(coff: *Coff, tid: Zcu.PerThread.Id) !void {
    const comp = coff.base.comp;
    const gpa = comp.gpa;
    const max_notes = 4;

    var undef_indices: std.ArrayListUnmanaged(u32) = .empty;
    for (coff.relocs.items, 0..) |reloc, reloc_i| {
        if (reloc.flags.free) continue;
        const target_sym = reloc.target.get(coff);
        switch (target_sym.ni) {
            .none => {
                assert(target_sym.gmi != .none);
                if (target_sym.section_number == .ABSOLUTE) continue;
                (try undef_indices.addOne(gpa)).* = @intCast(reloc_i);
            },
            else => continue,
        }
    }

    if (undef_indices.items.len == 0) return;

    const undefLessThan = struct {
        fn lessThan(ctx: *const Coff, lhs: u32, rhs: u32) bool {
            const reloc_l = &ctx.relocs.items[lhs];
            const reloc_r = &ctx.relocs.items[rhs];
            if (reloc_l.target == reloc_r.target)
                return @intFromEnum(reloc_l.loc) < @intFromEnum(reloc_r.loc)
            else
                return @intFromEnum(reloc_l.target) < @intFromEnum(reloc_r.target);
        }
    }.lessThan;

    std.mem.sortUnstable(u32, undef_indices.items, coff, undefLessThan);

    var start_i: usize = 0;
    var num_unique_references: usize = 1;
    for (0..undef_indices.items.len) |i| {
        const target = coff.relocs.items[undef_indices.items[start_i]].target;
        if (i == undef_indices.items.len - 1 or target != coff.relocs.items[undef_indices.items[i + 1]].target) {
            defer {
                start_i = i + 1;
                num_unique_references = 1;
            }

            const num_full_notes = @min(max_notes, num_unique_references);
            var err = try comp.link_diags.addErrorWithNotes(
                num_full_notes + @intFromBool(num_unique_references > max_notes),
            );
            const target_sym = target.get(coff);
            try err.addMsg("undefined symbol: {s}", .{target_sym.gmi.name(coff).toSlice(coff)});

            // TODO: If lib_name is set, show the user

            var prev_loc_si: Symbol.Index = .null;
            for (undef_indices.items[start_i .. i + 1]) |reference_i| {
                if (err.note_slot == num_full_notes) break;

                const reloc = &coff.relocs.items[reference_i];
                const loc_si = reloc.loc;
                if (loc_si == prev_loc_si) continue;
                defer prev_loc_si = loc_si;

                const loc_sym = loc_si.get(coff);

                // TODO: Make this a helper for anything that needs to report "referenced by" notes
                switch (coff.getNode(loc_sym.ni)) {
                    .data_directories => {
                        const dir: std.coff.IMAGE.DIRECTORY_ENTRY =
                            @enumFromInt(reloc.offset / @sizeOf(std.coff.ImageDataDirectory));
                        err.addNote("referenced by data directory entry: {t}", .{dir});
                    },
                    .optional_header => err.addNote("referenced by optional header field", .{}),
                    .input_section => |isi| {
                        const other_ioi = isi.input(coff);
                        if (loc_sym.gmi == .none) {
                            const section = isi.inputSection(coff);
                            const section_name = coff.getNode(loc_sym.ni.parent(&coff.mf))
                                .object_section.name(coff).toSlice(coff);

                            if (section.comdat_si != .null) {
                                const comdat_sym = section.comdat_si.get(coff);
                                const comdat_name = if (comdat_sym.gmi != .none)
                                    comdat_sym.gmi.name(coff).toSlice(coff)
                                else
                                    comdat_sym.extra.isli.name(coff).toSlice(coff);

                                err.addNote("referenced by input COMDAT section '{s}={s}' '{f}{f}'", .{
                                    section_name,
                                    comdat_name,
                                    other_ioi.path(coff).fmtEscapeString(),
                                    fmtMemberNameString(other_ioi.memberName(coff)),
                                });
                            } else {
                                err.addNote("referenced by input section '{s}' '{f}{f}'", .{
                                    section_name,
                                    other_ioi.path(coff).fmtEscapeString(),
                                    fmtMemberNameString(other_ioi.memberName(coff)),
                                });
                            }
                        } else {
                            err.addNote("referenced by input symbol '{s}' from '{f}{f}'", .{
                                loc_sym.gmi.name(coff).toSlice(coff),
                                other_ioi.path(coff).fmtEscapeString(),
                                fmtMemberNameString(other_ioi.memberName(coff)),
                            });
                        }
                    },
                    .import_thunk => |gmi| err.addNote("referenced by import thunk for '{s}'", .{
                        gmi.name(coff).toSlice(coff),
                    }),
                    inline .nav,
                    .uav,
                    .lazy_code,
                    .lazy_const_data,
                    => |val, tag| {
                        err.addNote("referenced by '{f}'", .{
                            format: switch (tag) {
                                .nav => {
                                    const ip = &comp.zcu.?.intern_pool;
                                    break :format ip.getNav(val.navIndex(coff)).fqn.fmt(ip);
                                },
                                .uav => Value.fromInterned(val.uavValue(coff)).fmtValue(.{
                                    .zcu = coff.base.comp.zcu.?,
                                    .tid = tid,
                                }),
                                inline .lazy_code, .lazy_const_data => Type.fromInterned(val.lazySymbol(coff).ty).fmt(.{
                                    .zcu = coff.base.comp.zcu.?,
                                    .tid = tid,
                                }),
                                else => unreachable,
                            },
                        });
                    },
                    else => unreachable,
                }
            }

            if (num_unique_references > max_notes)
                err.addNote("referenced {d} more times", .{num_unique_references - max_notes});
        } else if (i != start_i and
            coff.relocs.items[undef_indices.items[i - 1]].loc != coff.relocs.items[undef_indices.items[i]].loc)
        {
            num_unique_references += 1;
        }
    }

    return error.AlreadyReported;
}

pub fn flush(
    coff: *Coff,
    arena: std.mem.Allocator,
    tid: Zcu.PerThread.Id,
    prog_node: std.Progress.Node,
) link.Error!void {
    _ = arena;
    _ = prog_node;
    const comp = coff.base.comp;

    // TODO: When https://github.com/ziglang/zig/issues/23617 is in,
    //       this should be set after updateExports instead
    coff.exports_complete = true;

    while (try coff.resolve(tid)) {}
    while (try coff.idle(tid)) {}

    // This has to occur after all other flushMoved / flushResized have resolved,
    // but it will also generate one more set of resizes and moves.
    if (coff.symbol_table.pending_shrink) {
        coff.symbol_table.pending_shrink = false;

        const number_of_symbols = coff.targetLoad(&coff.headerPtr().number_of_symbols);
        coff.symbol_table.ni.shrink(
            &coff.mf,
            comp.gpa,
            number_of_symbols * std.coff.Symbol.sizeOf(),
            true,
        ) catch |err| return comp.link_diags.fail(
            "linker failed to compact symbol table: {t}",
            .{err},
        );
    }
    while (try coff.idle(tid)) {}

    if (coff.isImage())
        try coff.reportUndefs(tid);

    if (comp.emit_implib) |implib_file|
        coff.flushImplib(implib_file) catch |err|
            return comp.link_diags.fail("flushing implib '{s}' failed: {t}", .{ implib_file, err });

    coff.mf.flush() catch |err| switch (err) {
        error.Canceled => |e| return e,
        else => |e| return comp.link_diags.fail("flush write failed: {t}", .{e}),
    };

    if (coff.options.enable_link_snapshots)
        coff.dumpStderr(tid) catch |err|
            return comp.link_diags.fail("dumping link snapshot failed: {t}", .{err});
}

/// Runs a single "resolution" task.
/// These are tasks that need to modify the node structure in some way.
/// They must run in a defined order with respect to linker tasks.
fn resolve(coff: *Coff, tid: Zcu.PerThread.Id) !bool {
    const comp = coff.base.comp;
    task: {
        while (coff.section_merge_pending_index < coff.section_merges.count()) {
            defer coff.section_merge_pending_index += 1;
            const sub_prog_node = coff.synth_prog_node.start(
                coff.section_merges.keys()[coff.section_merge_pending_index].toSlice(coff),
                0,
            );
            defer sub_prog_node.end();
            coff.flushSectionMerge(coff.section_merge_pending_index) catch |err| switch (err) {
                //error.OutOfMemory => |e| return e,
                else => |e| return comp.link_diags.fail(
                    "linker failed to merge section {s} into {s}: {t}",
                    .{
                        coff.section_merges.keys()[coff.section_merge_pending_index].toSlice(coff),
                        coff.section_merges.values()[coff.section_merge_pending_index].toSlice(coff),
                        e,
                    },
                ),
            };
            break :task;
        }
        while (coff.pending_uavs.pop()) |pending_uav| {
            const sub_prog_node = coff.idleProgNode(tid, coff.const_prog_node, .{ .uav = pending_uav.key });
            defer sub_prog_node.end();
            coff.flushUav(
                .{ .zcu = comp.zcu.?, .tid = tid },
                pending_uav.key,
                pending_uav.value.alignment,
            ) catch |err| switch (err) {
                else => |e| return e,
                error.MappedFileIo => return comp.link_diags.fail(
                    "linker failed to lower constant: {t}",
                    .{coff.mf.io_err.?},
                ),
            };
            break :task;
        }
        if (coff.pending_input) |pending_iami| {
            const name_slice = pending_iami.member(coff).name.toSlice(coff);
            const sub_prog_node = coff.input_prog_node.start(
                name_slice,
                0,
            );
            defer sub_prog_node.end();
            coff.pending_input = null;
            coff.flushInputMember(pending_iami) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => |e| return comp.link_diags.fail(
                    "linker failed to load archive member '{f}{f}': {t}",
                    .{
                        pending_iami.member(coff).iai.path(coff),
                        fmtMemberNameString(name_slice),
                        e,
                    },
                ),
            };
            break :task;
        }
        if (coff.exports_complete and coff.global_pending_index < coff.globals.count()) {
            const gmi: Node.GlobalMapIndex = .wrap(coff.global_pending_index);
            const sub_prog_node = coff.synth_prog_node.start(
                gmi.name(coff).toSlice(coff),
                0,
            );
            defer sub_prog_node.end();
            if (coff.flushGlobal(gmi) catch |err| switch (err) {
                else => |e| return e,
                error.MappedFileIo => return comp.link_diags.fail(
                    "linker failed to lower constant: {t}",
                    .{coff.mf.io_err.?},
                ),
            }) coff.global_pending_index += 1;
            break :task;
        }
        if (coff.exports_complete and coff.pending_special_symbol != .none) {
            coff.pending_special_symbol = coff.flushSpecialSymbol(coff.pending_special_symbol) catch |err|
                switch (err) {
                    error.OutOfMemory => |e| return e,
                    else => |e| return comp.link_diags.fail(
                        "linker failed to flush special symbols: {t}",
                        .{e},
                    ),
                };
            break :task;
        }
        var lazy_it = coff.lazy.iterator();
        while (lazy_it.next()) |lazy| if (lazy.value.pending_index < lazy.value.map.count()) {
            const pt: Zcu.PerThread = .{ .zcu = comp.zcu.?, .tid = tid };
            const lmr: Node.LazyMapRef = .{ .kind = lazy.key, .index = lazy.value.pending_index };
            lazy.value.pending_index += 1;
            const kind = switch (lmr.kind) {
                .code => "code",
                .const_data => "data",
            };
            var name: [std.Progress.Node.max_name_len]u8 = undefined;
            const sub_prog_node = coff.synth_prog_node.start(
                std.fmt.bufPrint(&name, "lazy {s} for {f}", .{
                    kind,
                    Type.fromInterned(lmr.lazySymbol(coff).ty).fmt(pt),
                }) catch &name,
                0,
            );
            defer sub_prog_node.end();
            coff.flushLazy(pt, lmr) catch |err| switch (err) {
                else => |e| return e,
                error.MappedFileIo => return comp.link_diags.fail(
                    "linker failed to lower lazy {s}: {t}",
                    .{ kind, coff.mf.io_err.? },
                ),
            };
            break :task;
        };
        if (coff.symbol_table.pending_symbol_index < coff.symbol_table.symbols.count()) {
            defer coff.symbol_table.pending_symbol_index += 1;
            const si = coff.symbol_table.symbols.keys()[coff.symbol_table.pending_symbol_index];
            const sym = si.get(coff);
            const sub_prog_node = coff.idleProgNode(
                tid,
                coff.symbol_prog_node,
                if (sym.ni != .none)
                    coff.getNode(sym.ni)
                else
                    .{ .import_thunk = sym.gmi },
            );
            defer sub_prog_node.end();
            coff.flushSymbolTableEntry(
                coff.symbol_table.pending_symbol_index,
                .{ .zcu = comp.zcu.?, .tid = tid },
            ) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => |e| return comp.link_diags.fail(
                    "linker failed to flush symbol table entry: {t}",
                    .{e},
                ),
            };
            break :task;
        }
    }

    if (coff.section_merge_pending_index < coff.section_merges.count()) return true;
    if (coff.pending_uavs.count() > 0) return true;
    if (coff.pending_input != null) return true;
    if (coff.exports_complete and coff.globals.count() > coff.global_pending_index) return true;
    assert(!coff.exports_complete or coff.inputs_complete);
    if (coff.exports_complete and coff.pending_special_symbol != .none) return true;
    for (&coff.lazy.values) |lazy| if (lazy.map.count() > lazy.pending_index) return true;
    if (coff.symbol_table.pending_symbol_index < coff.symbol_table.symbols.count()) return true;
    return false;
}

pub fn idle(coff: *Coff, tid: Zcu.PerThread.Id) !bool {
    // Idle tasks should not modify create / modify nodes, otherwise the output is not reproducible.
    coff.mf.nodes_lock.lock();
    defer coff.mf.nodes_lock.unlock();

    const comp = coff.base.comp;
    task: {
        // TODO: Idle task for flushing obj into lib
        if (coff.input_section_pending_index < coff.input_sections.items.len) {
            const isi: Node.InputSection.Index = @enumFromInt(coff.input_section_pending_index);
            coff.input_section_pending_index += 1;
            const sub_prog_node = coff.idleProgNode(tid, coff.input_prog_node, coff.getNode(isi.symbol(coff).node(coff)));
            defer sub_prog_node.end();
            coff.flushInputSection(isi) catch |err| switch (err) {
                else => |e| {
                    const ioi = isi.input(coff);
                    return comp.link_diags.fail(
                        "linker failed to read input section '{s}' from \"{f}{f}\": {t}",
                        .{
                            isi.symbol(coff).get(coff).section_number.name(coff).toSlice(coff),
                            ioi.path(coff).fmtEscapeString(),
                            fmtMemberNameString(ioi.memberName(coff)),
                            e,
                        },
                    );
                },
            };
            break :task;
        }
        while (coff.mf.updates.pop()) |ni| {
            const clean_moved = ni.cleanMoved(&coff.mf);
            const clean_resized = ni.cleanResized(&coff.mf);
            if (clean_moved or clean_resized) {
                const sub_prog_node =
                    coff.idleProgNode(tid, coff.mf.update_prog_node, coff.getNode(ni));
                defer sub_prog_node.end();
                if (clean_moved) try coff.flushMoved(ni);
                if (clean_resized) try coff.flushResized(ni);
                break :task;
            } else coff.mf.update_prog_node.completeOne();
        }
        while (coff.pending_members.pop()) |pending_mi| {
            const sub_prog_node = coff.idleProgNode(
                tid,
                coff.symbol_prog_node,
                coff.getNode(pending_mi.key.get(coff).content_ni),
            );
            defer sub_prog_node.end();
            try coff.flushMember(pending_mi.key);
            break :task;
        }
        if (coff.exports_complete and coff.export_table.pending_sort) {
            defer coff.export_table.pending_sort = false;
            const sub_prog_node = coff.idleProgNode(
                tid,
                coff.synth_prog_node,
                coff.getNode(coff.export_table.ni),
            );
            defer sub_prog_node.end();

            coff.flushExportsSort();
            break :task;
        }
    }
    if (coff.input_sections.items.len > coff.input_section_pending_index) return true;
    if (coff.mf.updates.items.len > 0) return true;
    if (coff.pending_members.count() > 0) return true;
    if (coff.exports_complete and coff.export_table.pending_sort) return true;
    return false;
}

fn idleProgNode(
    coff: *Coff,
    tid: Zcu.PerThread.Id,
    prog_node: std.Progress.Node,
    node: Node,
) std.Progress.Node {
    var name: [std.Progress.Node.max_name_len]u8 = undefined;
    return prog_node.start(name: switch (node) {
        else => |tag| @tagName(tag),
        .image_section => |si| std.mem.sliceTo(&si.get(coff).section_number.header(coff).name, 0),
        inline .pseudo_section, .object_section => |smi| smi.name(coff).toSlice(coff),
        .input_section => |isi| {
            const ioi = isi.input(coff);
            break :name std.fmt.bufPrint(&name, "{f}{f} {s}", .{
                ioi.path(coff).fmtEscapeString(),
                fmtMemberNameString(ioi.memberName(coff)),
                coff.getNode(isi.symbol(coff).node(coff).parent(&coff.mf)).object_section.name(coff).toSlice(coff),
            }) catch &name;
        },
        .import_thunk => |gmi| gmi.name(coff).toSlice(coff),
        .nav => |nmi| {
            const ip = &coff.base.comp.zcu.?.intern_pool;
            break :name ip.getNav(nmi.navIndex(coff)).fqn.toSlice(ip);
        },
        .uav => |umi| std.fmt.bufPrint(&name, "{f}", .{
            Value.fromInterned(umi.uavValue(coff)).fmtValue(.{
                .zcu = coff.base.comp.zcu.?,
                .tid = tid,
            }),
        }) catch &name,
        .archive_member => |mi| &mi.get(coff).headerPtr(coff).name,
    }, 0);
}

fn flushUav(
    coff: *Coff,
    pt: Zcu.PerThread,
    umi: Node.UavMapIndex,
    uav_align: InternPool.Alignment,
) !void {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;

    const uav_val = umi.uavValue(coff);
    const si = umi.symbol(coff);
    const ni = ni: {
        switch (si.get(coff).ni) {
            .none => {
                const sec_si = (try coff.objectSectionMapIndex(
                    .@".rdata",
                    coff.mf.flags.block_size,
                    .{ .read = true, .initialized = true },
                )).symbol(coff);
                try coff.nodes.ensureUnusedCapacity(gpa, 1);
                if (!isImage(coff)) try coff.symbol_table.symbols.ensureUnusedCapacity(gpa, 1);
                const sym = si.get(coff);
                const ni = try coff.mf.addLastChildNode(gpa, sec_si.node(coff), .{
                    .alignment = uav_align.toStdMem(),
                    .moved = true,
                });
                coff.nodes.appendAssumeCapacity(.{ .uav = umi });
                sym.ni = ni;
                sym.section_number = sec_si.get(coff).section_number;
            },
            else => {
                if (si.get(coff).ni.alignment(&coff.mf).order(uav_align.toStdMem()).compare(.gte))
                    return;
                si.deleteLocationRelocs(coff);
            },
        }
        const sym = si.get(coff);
        assert(sym.loc_relocs == .none);
        sym.loc_relocs = @enumFromInt(coff.relocs.items.len);
        if (!isImage(coff) and sym.target_relocs != .none)
            try coff.pendingSymbolTableEntry(si);

        break :ni sym.ni;
    };

    var nw: MappedFile.Node.Writer = undefined;
    ni.writer(&coff.mf, gpa, &nw);
    defer nw.deinit();
    codegen.generateSymbol(
        &coff.base,
        pt,
        .fromInterned(uav_val),
        &nw.interface,
        .{ .atom_index = @enumFromInt(@intFromEnum(si)) },
    ) catch |err| switch (err) {
        error.WriteFailed => return nw.err.?,
        else => |e| return e,
    };
    si.get(coff).extra.size = @intCast(nw.interface.end);
    try si.applyLocationRelocs(coff);
}

fn aliasGlobal(coff: *Coff, gmi: Node.GlobalMapIndex, alias_si: Symbol.Index) !void {
    const si = gmi.symbol(coff);
    const sym = si.get(coff);
    const alias_sym = alias_si.get(coff);
    assert(sym.section_number == .UNDEFINED);
    assert(sym.loc_relocs == .none);

    log.debug("aliasGlobal({s}, {?s}) {d}->{d} ({?s})", .{
        gmi.name(coff).toSlice(coff),
        gmi.libName(coff).toSlice(coff),
        si,
        alias_si,
        if (alias_sym.gmi != .none) alias_sym.gmi.name(coff).toSlice(coff) else null,
    });

    var ri = sym.target_relocs;
    while (ri != .none) {
        const reloc = ri.get(coff);
        assert(reloc.target == si);
        reloc.target = alias_si;
        if (reloc.next == .none) {
            reloc.next = alias_sym.target_relocs;
            if (alias_sym.target_relocs != .none)
                alias_sym.target_relocs.get(coff).prev = ri;
            break;
        }
        ri = reloc.next;
    }

    const prev_target_relocs = alias_sym.target_relocs;
    if (sym.target_relocs != .none)
        alias_sym.target_relocs = sym.target_relocs;
    sym.target_relocs = .none;
    sym.gmi = alias_sym.gmi;
    coff.globals.values()[gmi.unwrap().?].si = alias_si;
    // Only apply the new relocs
    try alias_si.applyTargetRelocs(coff, prev_target_relocs);
}

fn flushGlobal(coff: *Coff, gmi: Node.GlobalMapIndex) !bool {
    const comp = coff.base.comp;
    const gpa = comp.gpa;
    const name = gmi.name(coff);
    const si = gmi.symbol(coff);

    log.debug(
        "flushGlobal({s}, {?s}) = n{d} {d}@{d}",
        .{
            name.toSlice(coff),
            gmi.libName(coff).toSlice(coff),
            si.get(coff).ni,
            si,
            si.get(coff).section_number,
        },
    );

    if (!coff.isImage()) {
        try coff.pendingSymbolTableEntry(si);
        if (coff.isArchive() and si.get(coff).ni != .none)
            try coff.ensureMemberSymbol(
                coff.getNode(Node.known.zcu_member).archive_member,
                name,
            );

        return true;
    }

    if (si.get(coff).ni != .none)
        return true;

    const Import = struct {
        lib_name: String,
        name: String.Optional,
        ordinal_hint: u16,
        kind: enum {
            iat_ptr,
            thunk,
        },
    };

    const import: Import = import: {
        const sym = si.get(coff);
        const name_slice = name.toSlice(coff);
        const imp_match = std.mem.startsWith(u8, name_slice, imp_prefix);

        // Globals may have the __imp_ prefix already if they are undef externals from another input.
        assert(sym.flags.dll_storage_class != .dllexport);
        const search_name, const is_imp = if (imp_match or sym.flags.dll_storage_class != .dllimport)
            .{ name, imp_match }
        else name: {
            try coff.ensureUnusedStringCapacity(imp_prefix.len + name_slice.len);
            const imp_name = try std.fmt.allocPrint(gpa, imp_prefix ++ "{s}", .{name_slice});
            defer gpa.free(imp_name);
            break :name .{ coff.getOrPutStringAssumeCapacity(imp_name), true };
        };

        const opt_alt_search_name = coff.alternate_names.get(search_name);
        const search_libs = switch (sym.flags.value_tag) {
            .weak_alias_si, .weak_alias_name => switch (sym.flags.weak_external_strat) {
                .none => unreachable,
                .no_library => false,
                .library,
                .alias,
                => true,
                .anti_dependency => return comp.link_diags.fail(
                    // TODO: Figure out what the purpose of this is
                    "TODO support anti_dependency weak external: {s}",
                    .{name.toSlice(coff)},
                ),
            },
            else => true,
        };

        const opt_indices_lists: []const ?InputArchive.SearchList = if (search_libs) &.{
            coff.input_archive_symbol_indices.get(search_name),
            if (opt_alt_search_name) |alt| coff.input_archive_symbol_indices.get(alt) else null,
        } else &.{};

        for (opt_indices_lists) |opt_indices_list| {
            const indices_list = opt_indices_list orelse continue;
            var iter: InputArchive.Member.Symbol.Index = indices_list.first;
            while (true) {
                const archive_sym = &coff.input_archive_symbols.items[@intFromEnum(iter)];
                const member = &coff.input_archive_members.items[@intFromEnum(archive_sym.iami)];
                member: switch (member.content) {
                    .object => if (!member.flags.is_loaded) {
                        if (gmi.libName(coff).unwrap()) |lib_name|
                            if (!std.ascii.eqlIgnoreCase(
                                lib_name.toSlice(coff),
                                member.iai.path(coff).stem(),
                            )) break :member;

                        // Try loading the input member and then retry.
                        // This could still be a member containing imports
                        // that use the older non-IMPORT_HEADER method.
                        coff.pending_input = archive_sym.iami;
                        return false;
                    },
                    .import => |import| {
                        if (gmi.libName(coff).unwrap()) |lib_name|
                            if (!std.ascii.eqlIgnoreCase(
                                import.lib_name.toSlice(coff),
                                lib_name.toSlice(coff),
                            )) break :member;

                        const imp_name: String.Optional = name: switch (import.name_type) {
                            .NAME,
                            .NAME_NOPREFIX,
                            .NAME_UNDECORATE,
                            => |tag| {
                                const symbol_name: []const u8 = import.symbol_name.toSlice(coff);
                                const end_match = std.mem.endsWith(u8, name_slice, symbol_name);
                                const len_delta = name_slice.len -% symbol_name.len;
                                if (!end_match or
                                    (!imp_match and len_delta != 0) or
                                    (imp_match and len_delta != imp_prefix.len))
                                    return comp.link_diags.fail(
                                        "global '{s}' has mismatched symbol name in import header: '{s}'",
                                        .{
                                            name.toSlice(coff),
                                            import.symbol_name.toSlice(coff),
                                        },
                                    );

                                const imp_name = if (tag == .NAME) import.symbol_name else undecorated: {
                                    var imp_name = std.mem.trimStart(u8, symbol_name, "?@_");
                                    if (tag == .NAME_UNDECORATE)
                                        imp_name = std.mem.sliceTo(imp_name, '@');

                                    try coff.ensureUnusedStringCapacity(imp_name.len);
                                    break :undecorated coff.getOrPutStringAssumeCapacity(imp_name);
                                };

                                break :name imp_name.toOptional();
                            },
                            .ORDINAL => break :name .none,
                            else => |t| return comp.link_diags.fail("TODO handle name_type {t}", .{t}),
                        };

                        break :import .{
                            .lib_name = import.lib_name,
                            .name = imp_name,
                            .ordinal_hint = import.import_ordinal_hint,
                            .kind = if (import.type == .CODE and !is_imp) .thunk else .iat_ptr,
                        };
                    },
                }

                if (archive_sym.next == iter) break;
                iter = archive_sym.next;
            }
        }

        switch (sym.flags.value_tag) {
            .weak_alias_si => {
                try coff.aliasGlobal(gmi, sym.value.weak_alias_si);
                return true;
            },
            .weak_alias_name => {
                // Convert an unresolved weak external that itself refers to an undef external
                // into a (possibly new) global, so it can be resolved separately.
                const alias_gop = try coff.getOrPutGlobalSymbol(.{
                    .name = sym.value.weak_alias_name.toSlice(coff),
                });
                try coff.aliasGlobal(gmi, alias_gop.value_ptr.si);
                return true;
            },
            else => {},
        }

        // If there was an object that had the alternate name, we've attempted to load it
        if (opt_alt_search_name) |alt_search_name| {
            if (coff.globals.get(alt_search_name)) |alias_global| {
                try coff.aliasGlobal(gmi, alias_global.si);
                return true;
            }
        }

        // Allow importing symbols with no implib entry, if a lib_name was specified.
        // This is necessary for certain ntdll symbols, such as LdrRegisterDllNotification,
        // which are not in the implib.
        if (sym.flags.type != .unknown) {
            if (gmi.libName(coff).unwrap()) |lib_name| break :import .{
                .lib_name = lib_name,
                .name = name.toOptional(),
                .ordinal_hint = 0,
                .kind = if (sym.flags.type == .code) .thunk else .iat_ptr,
            };
        }

        return true;
    };

    try coff.nodes.ensureUnusedCapacity(gpa, 4);
    try coff.symbols.ensureUnusedCapacity(gpa, 2);

    const target_endian = coff.targetEndian();
    const addr_info = coff.targetAddrInfo();
    const lib_name = import.lib_name.toSlice(coff);
    const gop = try coff.import_table.entries.getOrPutAdapted(
        gpa,
        lib_name,
        ImportTable.Adapter{ .coff = coff },
    );
    const import_hint_name_align: std.mem.Alignment = .@"2";
    if (!gop.found_existing) {
        errdefer _ = coff.import_table.entries.pop();
        try coff.import_table.ni.resize(
            &coff.mf,
            gpa,
            @sizeOf(std.coff.ImportDirectoryEntry) * (gop.index + 2),
        );
        const import_hint_name_table_len =
            import_hint_name_align.forward(lib_name.len + ".dll".len + 1);
        const idata_section_ni = coff.import_table.ni.parent(&coff.mf);
        const import_lookup_table_ni = try coff.mf.addLastChildNode(gpa, idata_section_ni, .{
            .size = addr_info.size * 2,
            .alignment = addr_info.alignment,
            .moved = true,
        });
        const import_address_table_ni = try coff.mf.addLastChildNode(gpa, idata_section_ni, .{
            .size = addr_info.size * 2,
            .alignment = addr_info.alignment,
            .moved = true,
        });
        const import_address_table_si = coff.addSymbolAssumeCapacity();
        {
            const import_address_table_sym = import_address_table_si.get(coff);
            import_address_table_sym.ni = import_address_table_ni;
            assert(import_address_table_sym.loc_relocs == .none);
            import_address_table_sym.loc_relocs = @enumFromInt(coff.relocs.items.len);
            import_address_table_sym.section_number =
                coff.getNode(idata_section_ni).object_section.symbol(coff).get(coff).section_number;
        }
        const import_hint_name_table_ni = try coff.mf.addLastChildNode(gpa, idata_section_ni, .{
            .size = import_hint_name_table_len,
            .alignment = import_hint_name_align,
            .moved = true,
        });
        gop.value_ptr.* = .{
            .import_lookup_table_ni = import_lookup_table_ni,
            .import_address_table_si = import_address_table_si,
            .import_hint_name_table_ni = import_hint_name_table_ni,
            .import_address_table_symbols = .empty,
            .len = 0,
            .hint_name_len = @intCast(import_hint_name_table_len),
        };
        const import_hint_name_slice = import_hint_name_table_ni.slice(&coff.mf);
        @memcpy(import_hint_name_slice[0..lib_name.len], lib_name);
        @memcpy(import_hint_name_slice[lib_name.len..][0..".dll".len], ".dll");
        @memset(import_hint_name_slice[lib_name.len + ".dll".len ..], 0);
        coff.nodes.appendAssumeCapacity(.{ .import_lookup_table = @enumFromInt(gop.index) });
        coff.nodes.appendAssumeCapacity(.{ .import_address_table = @enumFromInt(gop.index) });
        coff.nodes.appendAssumeCapacity(.{ .import_hint_name_table = @enumFromInt(gop.index) });

        const import_directory_entries = coff.importDirectoryTableSlice()[gop.index..][0..2];
        import_directory_entries.* = .{ .{
            .import_lookup_table_rva = coff.computeNodeRva(import_lookup_table_ni),
            .time_date_stamp = 0,
            .forwarder_chain = 0,
            .name_rva = coff.computeNodeRva(import_hint_name_table_ni),
            .import_address_table_rva = coff.computeNodeRva(import_address_table_ni),
        }, .{
            .import_lookup_table_rva = 0,
            .time_date_stamp = 0,
            .forwarder_chain = 0,
            .name_rva = 0,
            .import_address_table_rva = 0,
        } };
        if (target_endian != native_endian)
            std.mem.byteSwapAllFields([2]std.coff.ImportDirectoryEntry, import_directory_entries);
    }

    log.debug(
        "flushGlobalImport({s}, {?s}, {d}, {s})",
        .{ name.toSlice(coff), import.name.toSlice(coff), import.ordinal_hint, lib_name },
    );

    const iat_symbol_gop = try coff.import_table.iat_symbol_indices.getOrPut(gpa, .{
        .iti = @enumFromInt(gop.index),
        .name = import.name,
        .ordinal_hint = import.ordinal_hint,
    });
    if (!iat_symbol_gop.found_existing) {
        const import_symbol_index = gop.value_ptr.len;
        iat_symbol_gop.value_ptr.* = import_symbol_index;

        gop.value_ptr.len = import_symbol_index + 1;
        const new_symbol_table_size = addr_info.size * (import_symbol_index + 2);

        try gop.value_ptr.import_lookup_table_ni.resize(&coff.mf, gpa, new_symbol_table_size);
        const import_address_table_ni = gop.value_ptr.import_address_table_si.node(coff);
        try import_address_table_ni.resize(&coff.mf, gpa, new_symbol_table_size);

        const opt_imp_name = import.name.toSlice(coff);
        const opt_import_hint_name_index = if (opt_imp_name) |imp_name| blk: {
            const import_hint_name_index = gop.value_ptr.hint_name_len;
            gop.value_ptr.hint_name_len = @intCast(
                import_hint_name_align.forward(import_hint_name_index + 2 + imp_name.len + 1),
            );
            try gop.value_ptr.import_hint_name_table_ni.resize(&coff.mf, gpa, gop.value_ptr.hint_name_len);
            break :blk import_hint_name_index;
        } else null;

        const import_hint_name_rva = if (opt_import_hint_name_index) |import_hint_name_index| blk: {
            const import_hint_name_slice = gop.value_ptr.import_hint_name_table_ni.slice(&coff.mf);
            const ordinal_hint: *u16 = @ptrCast(@alignCast(import_hint_name_slice[import_hint_name_index..][0..2]));
            ordinal_hint.* = std.mem.nativeTo(u16, import.ordinal_hint, target_endian);
            @memcpy(import_hint_name_slice[import_hint_name_index + 2 ..][0..opt_imp_name.?.len], opt_imp_name.?);
            @memset(import_hint_name_slice[import_hint_name_index + 2 + opt_imp_name.?.len ..], 0);
            break :blk coff.computeNodeRva(gop.value_ptr.import_hint_name_table_ni) + import_hint_name_index;
        } else 0;

        const import_lookup_slice = gop.value_ptr.import_lookup_table_ni.slice(&coff.mf);
        const import_address_slice = import_address_table_ni.slice(&coff.mf);
        switch (addr_info.magic) {
            _ => unreachable,
            inline .PE32, .@"PE32+" => |ct_magic| {
                const Entry = std.coff.ImportLookupTableEntry(ct_magic);
                const import_lookup_table: []Entry = @ptrCast(@alignCast(import_lookup_slice));
                const import_address_table: []Entry = @ptrCast(@alignCast(import_address_slice));
                var import_hint_name_rvas: [2]Entry = .{
                    .{
                        .payload = if (import.name == .none)
                            .{ .ordinal = .{ .ordinal = import.ordinal_hint } }
                        else
                            .{ .hint_name_rva = @intCast(import_hint_name_rva) },
                        .is_ordinal = import.name == .none,
                    },
                    @bitCast(@as(@typeInfo(Entry).@"struct".backing_integer.?, 0)),
                };
                if (native_endian != target_endian)
                    for (&import_hint_name_rvas) |*v| std.mem.byteSwapAllFields(Entry, v);

                import_lookup_table[import_symbol_index..][0..2].* = import_hint_name_rvas;
                import_address_table[import_symbol_index..][0..2].* = import_hint_name_rvas;
            },
        }
    }

    const sym = si.get(coff);
    assert(sym.loc_relocs == .none);
    const iat_offset: u32 = @intCast(addr_info.size * iat_symbol_gop.value_ptr.*);
    switch (import.kind) {
        .iat_ptr => {
            const iat_sym = gop.value_ptr.import_address_table_si.get(coff);
            sym.section_number = iat_sym.section_number;
            sym.ni = iat_sym.ni;
            sym.setValue(.{ .node_offset = iat_offset });
            (try gop.value_ptr.import_address_table_symbols.addOne(gpa)).* = si;
        },
        .thunk => {
            sym.loc_relocs = @enumFromInt(coff.relocs.items.len);

            const target = &comp.root_mod.resolved_target.result;
            const alignment = switch (comp.root_mod.optimize_mode) {
                .Debug,
                .ReleaseSafe,
                .ReleaseFast,
                => target_util.defaultFunctionAlignment(target),
                .ReleaseSmall => target_util.minFunctionAlignment(target),
            }.toStdMem();
            const parent_si = (try coff.pseudoSectionMapIndex(
                .@".thunks",
                alignment,
                .{ .execute = true, .read = true },
            )).symbol(coff);

            const parent_sym = parent_si.get(coff);
            sym.section_number = parent_sym.section_number;

            switch (coff.targetLoad(&coff.headerPtr().machine)) {
                else => |tag| @panic(@tagName(tag)),
                .AMD64 => {
                    const init = [_]u8{ 0xff, 0x25, 0x00, 0x00, 0x00, 0x00 };
                    const ni = try coff.mf.addLastChildNode(gpa, parent_sym.ni, .{
                        .alignment = alignment,
                        .size = init.len,
                    });
                    @memcpy(ni.slice(&coff.mf)[0..init.len], &init);
                    sym.ni = ni;
                    sym.extra.size = init.len;
                    try coff.addReloc(
                        si,
                        init.len - 4,
                        gop.value_ptr.import_address_table_si,
                        .{ .known = iat_offset },
                        .{ .AMD64 = .REL32 },
                    );
                },
            }
            coff.nodes.appendAssumeCapacity(.{ .import_thunk = gmi });
        },
    }

    try si.flushMoved(coff);
    return true;
}

fn flushSpecialSymbol(coff: *Coff, pending: SpecialSymbol) !SpecialSymbol {
    const comp = coff.base.comp;

    if (!coff.isImage()) return .none;
    const gpa = comp.gpa;
    const machine = coff.targetLoad(&coff.headerPtr().machine);
    const target = &comp.root_mod.resolved_target.result;

    return next: switch (pending) {
        .entry => {
            // TODO: Use explicitly specified entry if set, add err if not found
            const entries: []const struct { ?[]const u8, []const u8 } = if (coff.isExe())
                if (comp.config.link_libc) switch (coff.optionalHeaderField(.subsystem)) {
                    .WINDOWS_CUI => &.{
                        .{ "main", "mainCRTStartup" },
                        .{ "wmain", "wmainCRTStartup" },
                    },
                    .WINDOWS_GUI => &.{
                        .{ "WinMain", "WinMainCRTStartup" },
                        .{ "wWinMain", "wWinMainCRTStartup" },
                    },
                    else => unreachable,
                } else &.{
                    .{ "wWinMainCRTStartup", "wWinMainCRTStartup" },
                }
            else
                &.{.{ null, if (target.abi.isGnu()) "DllMainCRTStartup" else "_DllMainCRTStartup" }};

            const entry_si = for (entries) |entry| {
                if (entry[0]) |required_name|
                    if (coff.getDefinedGlobal(required_name) == .null) continue;

                break try coff.globalSymbol(.{ .name = entry[1], .type = .code });
            } else .null;

            if (entry_si != .null) {
                log.debug(
                    "entry({s}, {d})",
                    .{ entry_si.get(coff).gmi.name(coff).toSlice(coff), entry_si },
                );

                try coff.symbols.ensureUnusedCapacity(gpa, 1);
                const optional_hdr_si = coff.addSymbolAssumeCapacity();
                const optional_hdr_sym = optional_hdr_si.get(coff);
                optional_hdr_sym.ni = Node.known.optional_header;
                assert(optional_hdr_sym.loc_relocs == .none);
                optional_hdr_sym.loc_relocs = @enumFromInt(coff.relocs.items.len);

                const optional_hdr = coff.optionalHeaderStandardPtr();
                optional_hdr.address_of_entry_point = std.mem.nativeTo(
                    u32,
                    entry_si.get(coff).rva,
                    coff.targetEndian(),
                );

                try coff.addReloc(
                    optional_hdr_si,
                    @intFromPtr(&optional_hdr.address_of_entry_point) - @intFromPtr(optional_hdr),
                    entry_si,
                    .{ .known = 0 },
                    switch (machine) {
                        else => |tag| @panic(@tagName(tag)),
                        .AMD64 => .{ .AMD64 = .ADDR32NB },
                        .I386 => .{ .I386 = .DIR32NB },
                    },
                );
            }

            // Referencing the startup functions may trigger loading the object containing them,
            // we need to wait until that is done before looking for further symbols.
            break :next .tls;
        },
        .tls => {
            if (coff.getDefinedGlobal("_tls_used").unwrap()) |tls_used_si| {
                log.debug("tlsDir({d})", .{tls_used_si});

                const tls_directory = coff.dataDirectoryPtr(.TLS);
                tls_directory.* = .{
                    .virtual_address = tls_used_si.get(coff).rva,
                    .size = switch (coff.targetLoad(&coff.optionalHeaderStandardPtr().magic)) {
                        _ => unreachable,
                        .PE32 => 24,
                        .@"PE32+" => 40,
                    },
                };
                if (coff.targetEndian() != native_endian)
                    std.mem.byteSwapAllFields(std.coff.ImageDataDirectory, tls_directory);

                try coff.symbols.ensureUnusedCapacity(gpa, 1);
                const data_dir_si = coff.addSymbolAssumeCapacity();
                const data_dir_sym = data_dir_si.get(coff);
                data_dir_sym.ni = Node.known.data_directories;
                assert(data_dir_sym.loc_relocs == .none);
                data_dir_sym.loc_relocs = @enumFromInt(coff.relocs.items.len);

                try coff.addReloc(
                    data_dir_si,
                    @intFromPtr(&tls_directory.virtual_address) - @intFromPtr(coff.dataDirectorySlice().ptr),
                    tls_used_si,
                    .{ .known = 0 },
                    switch (machine) {
                        else => |tag| @panic(@tagName(tag)),
                        .AMD64 => .{ .AMD64 = .ADDR32NB },
                        .I386 => .{ .I386 = .DIR32NB },
                    },
                );
            }

            break :next .none;
        },
        .none => unreachable,
    };
}

fn flushLazy(coff: *Coff, pt: Zcu.PerThread, lmr: Node.LazyMapRef) !void {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;

    const lazy = lmr.lazySymbol(coff);
    const si = lmr.symbol(coff);
    const ni = ni: {
        const sym = si.get(coff);
        switch (sym.ni) {
            .none => {
                try coff.nodes.ensureUnusedCapacity(gpa, 1);
                const sec_si: Symbol.Index = switch (lazy.kind) {
                    .code => .text,
                    .const_data => .rdata,
                };
                const ni = try coff.mf.addLastChildNode(gpa, sec_si.node(coff), .{ .moved = true });
                coff.nodes.appendAssumeCapacity(switch (lazy.kind) {
                    .code => .{ .lazy_code = @enumFromInt(lmr.index) },
                    .const_data => .{ .lazy_const_data = @enumFromInt(lmr.index) },
                });
                sym.ni = ni;
                sym.section_number = sec_si.get(coff).section_number;
            },
            else => si.deleteLocationRelocs(coff),
        }
        assert(sym.loc_relocs == .none);
        sym.loc_relocs = @enumFromInt(coff.relocs.items.len);
        if (!isImage(coff) and sym.target_relocs != .none)
            try coff.pendingSymbolTableEntry(si);

        break :ni sym.ni;
    };

    var required_alignment: InternPool.Alignment = .none;
    var nw: MappedFile.Node.Writer = undefined;
    ni.writer(&coff.mf, gpa, &nw);
    defer nw.deinit();
    codegen.generateLazySymbol(
        &coff.base,
        pt,
        lazy,
        &required_alignment,
        &nw.interface,
        .none,
        .{ .atom_index = @enumFromInt(@intFromEnum(si)) },
    ) catch |err| switch (err) {
        error.WriteFailed => return nw.err.?,
        else => |e| return e,
    };
    si.get(coff).extra.size = @intCast(nw.interface.end);
    try si.applyLocationRelocs(coff);
}

fn flushMoved(coff: *Coff, ni: MappedFile.Node.Index) !void {
    log.debug("flushMoved({s}, n{d})", .{ @tagName(coff.getNode(ni)), ni });
    switch (coff.getNode(ni)) {
        .file,
        .header,
        .signature,
        => unreachable,
        .coff_header,
        .optional_header,
        .data_directories,
        .section_table,
        .placeholder,
        => assert(!coff.isImage()),
        .symbol_table,
        .string_table,
        => |_, tag| {
            if (tag == .symbol_table)
                coff.targetStore(
                    &coff.headerPtr().pointer_to_symbol_table,
                    @intCast(ni.location(&coff.mf).resolve(&coff.mf)[0]),
                );

            if (!coff.symbol_table.pending_shrink) {
                const symbol_table_loc, const symbol_table_size = coff.symbol_table.ni.location(&coff.mf).resolve(&coff.mf);
                const string_table_offset, _ = coff.symbol_table.strings_ni.location(&coff.mf).resolve(&coff.mf);
                coff.symbol_table.pending_shrink = string_table_offset - (symbol_table_loc + symbol_table_size) > 0;
            }
        },
        .relocation_table => |sn| {
            coff.targetStore(
                &sn.header(coff).pointer_to_relocations,
                @intCast(ni.location(&coff.mf).resolve(&coff.mf)[0]),
            );
        },
        .relocation_table_entry => {},
        .archive_member_header => |mi| {
            const member = mi.get(coff);
            switch (member.kind) {
                .first_linker, .second_linker, .longnames => {},
                else => coff.targetStore(
                    &coff.secondLinkerMemberOffsetsSlice()[@intFromEnum(mi) - Member.Index.known_count],
                    @intCast(ni.fileLocation(&coff.mf, false).offset),
                ),
            }

            if (member.kind == .coff)
                try coff.pending_members.put(coff.base.comp.gpa, mi, {});
        },
        .archive_member,
        => {},
        .image_section => |si| {
            const sym = si.get(coff);
            const flags = coff.targetLoad(&sym.section_number.header(coff).flags);
            if (!flags.CNT_UNINITIALIZED_DATA) {
                const file_offset = if (isArchive(coff))
                    sym.ni.location(&coff.mf).resolve(&coff.mf)[0]
                else
                    ni.fileLocation(&coff.mf, false).offset;

                return coff.targetStore(
                    &sym.section_number.header(coff).pointer_to_raw_data,
                    @intCast(file_offset),
                );
            }
        },
        .input_section => |isi| {
            try isi.symbol(coff).flushMoved(coff);
            for (coff.input_symbols.items[@intFromEnum(isi.firstSymbol(coff))..]) |input_symbol| {
                if (input_symbol.si.get(coff).ni != ni) break;
                try input_symbol.si.flushMoved(coff);
            }
        },
        .import_directory_table => {
            _, const size = ni.location(&coff.mf).resolve(&coff.mf);
            if (size > 0)
                coff.targetStore(
                    &coff.dataDirectoryPtr(.IMPORT).virtual_address,
                    coff.computeNodeRva(ni),
                );
        },
        .import_lookup_table => |import_index| coff.targetStore(
            &coff.importDirectoryEntryPtr(import_index).import_lookup_table_rva,
            coff.computeNodeRva(ni),
        ),
        .import_address_table => |import_index| {
            const entry = import_index.get(coff);
            const import_address_table_si = entry.import_address_table_si;
            try import_address_table_si.flushMoved(coff);
            coff.targetStore(
                &coff.importDirectoryEntryPtr(import_index).import_address_table_rva,
                import_address_table_si.get(coff).rva,
            );

            for (entry.import_address_table_symbols.items) |iat_ptr_si|
                try iat_ptr_si.flushMoved(coff);
        },
        .import_hint_name_table => |import_index| {
            const magic = coff.targetLoad(&coff.optionalHeaderStandardPtr().magic);
            const import_hint_name_rva = coff.computeNodeRva(ni);
            coff.targetStore(
                &coff.importDirectoryEntryPtr(import_index).name_rva,
                import_hint_name_rva,
            );
            const import_entry = import_index.get(coff);
            const import_lookup_slice = import_entry.import_lookup_table_ni.slice(&coff.mf);
            const import_address_slice =
                import_entry.import_address_table_si.node(coff).slice(&coff.mf);
            const import_hint_name_slice = ni.slice(&coff.mf);
            const import_hint_name_align = ni.alignment(&coff.mf);

            var import_hint_name_index: u32 = 0;
            for (0..import_entry.len) |import_symbol_index| {
                switch (magic) {
                    _ => unreachable,
                    inline .PE32, .@"PE32+" => |ct_magic| {
                        const Entry = std.coff.ImportLookupTableEntry(ct_magic);
                        const import_lookup_table: []Entry = @ptrCast(@alignCast(import_lookup_slice));
                        const import_address_table: []Entry = @ptrCast(@alignCast(import_address_slice));

                        var entry = coff.targetLoad(&import_lookup_table[import_symbol_index]);
                        if (entry.is_ordinal)
                            continue;

                        import_hint_name_index = @intCast(import_hint_name_align.forward(
                            std.mem.indexOfScalarPos(
                                u8,
                                import_hint_name_slice,
                                import_hint_name_index,
                                0,
                            ).? + 1,
                        ));

                        entry.payload.hint_name_rva = @intCast(import_hint_name_rva + import_hint_name_index);
                        import_hint_name_index += 2;

                        coff.targetStore(&import_lookup_table[import_symbol_index], entry);
                        coff.targetStore(&import_address_table[import_symbol_index], entry);
                    },
                }
            }
        },
        .export_directory_table => {
            const rva = coff.computeNodeRva(ni);
            coff.targetStore(&coff.dataDirectoryPtr(.EXPORT).virtual_address, rva);
            coff.targetStore(&coff.exportDirectoryTable().name_rva, rva + @sizeOf(std.coff.ExportDirectoryTable));
        },
        .export_address_table => {
            try coff.export_table.export_address_table_si.flushMoved(coff);

            // These relocs are applied directly here instead of via the above flushMoved call as
            // they are non-contiguous, and not tracked under export_address_table_si.
            for (coff.export_table.entries.values()) |entry|
                try entry.export_address_table_ri.get(coff).apply(coff);

            coff.targetStore(
                &coff.exportDirectoryTable().export_address_table_rva,
                coff.computeNodeRva(ni),
            );
        },
        .export_name_pointer_table => coff.targetStore(
            &coff.exportDirectoryTable().name_pointer_table_rva,
            coff.computeNodeRva(ni),
        ),
        .export_ordinal_table => coff.targetStore(
            &coff.exportDirectoryTable().ordinal_table_rva,
            coff.computeNodeRva(ni),
        ),
        .export_name_table => {
            const name_table_rva = coff.computeNodeRva(coff.export_table.name_table_ni);
            for (
                coff.exportNamePointerTableSlice(),
                coff.exportOrdinalTableSlice(),
            ) |*np, target_ord| {
                const ord: ExportTable.Ordinal = @enumFromInt(coff.targetLoad(&target_ord.unbiased_ordinal));
                const entry = ord.get(coff);
                coff.targetStore(
                    &np.name_rva,
                    @intCast(name_table_rva + entry.name_index),
                );
            }
        },
        inline .pseudo_section,
        .object_section,
        .import_thunk,
        .nav,
        .uav,
        .lazy_code,
        .lazy_const_data,
        => |mi| try mi.symbol(coff).flushMoved(coff),
        .builtin => |si| try si.flushMoved(coff),
    }
    try ni.childrenMoved(coff.base.comp.gpa, &coff.mf);
}

fn flushResized(coff: *Coff, ni: MappedFile.Node.Index) !void {
    const offset, const size = ni.location(&coff.mf).resolve(&coff.mf);
    log.debug("flushResized({s}, n{d}, 0x{x})", .{ @tagName(coff.getNode(ni)), ni, size });

    switch (coff.getNode(ni)) {
        .file => {
            if (coff.isArchive() and coff.members.items.len > 0) {
                const last_member = coff.members.items[coff.members.items.len - 1];
                // See .archive_member branch for reasoning
                assert(Node.known.file.reverseChildren(&coff.mf).ni == last_member.content_ni);
                try coff.flushResized(last_member.content_ni);
            }
        },
        .header => {
            if (coff.isImage()) {
                switch (coff.optionalHeaderPtr()) {
                    inline else => |optional_header| coff.targetStore(
                        &optional_header.size_of_headers,
                        @intCast(size),
                    ),
                }

                if (size > coff.section_table.values()[0].si.get(coff).rva) try coff.virtualSlide(
                    0,
                    std.mem.alignForward(
                        u32,
                        @intCast(size * 4),
                        coff.optionalHeaderField(.section_alignment),
                    ),
                );
            }
        },
        .signature,
        .archive_member_header,
        => unreachable,
        .archive_member => |mi| {
            const content_ni = mi.get(coff).content_ni;
            const next_ni = content_ni.next(&coff.mf);
            const content_offset, _ = content_ni.location(&coff.mf).resolve(&coff.mf);
            const next_offset = switch (next_ni) {
                .none => offset: {
                    assert(content_ni.parent(&coff.mf) == Node.known.file);
                    // This must take into account the final file size. If there are trailing
                    // bytes, they will be expected to contain another valid member header
                    break :offset coff.mf.memory_map.memory.len;
                },
                else => offset: {
                    assert(coff.getNode(next_ni) == .archive_member_header);
                    break :offset next_ni.location(&coff.mf).resolve(&coff.mf)[0];
                },
            };

            // Not inserting IMAGE_ARCHIVE_PAD `\n` byte here, because we are expanding to full size
            Member.storeHeaderDecimalStr(&mi.get(coff).headerPtr(coff).size, next_offset - content_offset);
        },
        .coff_header,
        .optional_header,
        .data_directories,
        => unreachable,
        .section_table => {},
        .symbol_table => {
            assert(!coff.isImage());
            if (!coff.symbol_table.pending_shrink) {
                const string_table_offset, _ = coff.symbol_table.strings_ni.location(&coff.mf).resolve(&coff.mf);
                coff.symbol_table.pending_shrink =
                    size > coff.targetLoad(&coff.headerPtr().number_of_symbols) * std.coff.Symbol.sizeOf() or
                    string_table_offset - (offset + size) > 0;
            }
        },
        .string_table => {
            assert(!coff.isImage());
            coff.targetStore(coff.symbolTableStringLenPtr(), @intCast(size));
        },
        .relocation_table,
        .relocation_table_entry,
        => assert(!coff.isImage()),
        .image_section => |si| {
            const sym = si.get(coff);
            const section_index = sym.section_number.toIndex();
            const section = &coff.sectionTableSlice()[section_index];
            coff.targetStore(&section.size_of_raw_data, @intCast(size));
            if (coff.isImage() and size > coff.targetLoad(&section.virtual_size)) {
                const virtual_size = std.mem.alignForward(
                    u32,
                    @intCast(size * 4),
                    coff.optionalHeaderField(.section_alignment),
                );
                coff.targetStore(&section.virtual_size, virtual_size);
                try coff.virtualSlide(section_index + 1, sym.rva + virtual_size);
            }

            if (!coff.isImage()) {
                if (coff.symbolTableSectionAuxEntryPtr(si.sti(coff))) |aux_ptr|
                    coff.targetStore(&aux_ptr.length, @intCast(size));
            }
        },
        .input_section => {},
        .import_directory_table => {
            const prev_size = coff.targetLoad(&coff.dataDirectoryPtr(.IMPORT).size);
            coff.targetStore(
                &coff.dataDirectoryPtr(.IMPORT).size,
                @intCast(size),
            );
            if (prev_size == 0) try coff.flushMoved(ni);
        },
        .import_lookup_table,
        .import_address_table,
        .import_hint_name_table,
        => {},
        .export_directory_table => unreachable,
        .export_address_table,
        .export_name_pointer_table,
        .export_ordinal_table,
        .export_name_table,
        => {},
        inline .pseudo_section,
        .object_section,
        => |smi, tag| {
            if (tag == .pseudo_section and smi.name(coff) == .@".edata") {
                coff.targetStore(
                    &coff.dataDirectoryPtr(.EXPORT).size,
                    @intCast(size),
                );
            }

            var sym = smi.symbol(coff).get(coff);
            while (sym.flags.extra_tag == .next_alias_si)
                sym = sym.extra.next_alias_si.get(coff);

            sym.extra.size = @intCast(size);
        },
        .import_thunk,
        .nav,
        .uav,
        .lazy_code,
        .lazy_const_data,
        .builtin,
        => {},
        .placeholder,
        => unreachable,
    }
}

fn flushMember(coff: *Coff, mi: Member.Index) !void {
    const member = mi.get(coff);
    switch (member.kind) {
        .first_linker,
        .longnames,
        .import,
        => unreachable,
        .second_linker => {
            const Context = struct {
                coff: *Coff,
                indices: []u16,
                strings: []String,

                pub fn lessThan(ctx: @This(), lhs: usize, rhs: usize) bool {
                    return std.mem.lessThan(
                        u8,
                        ctx.strings[lhs].toSlice(ctx.coff),
                        ctx.strings[rhs].toSlice(ctx.coff),
                    );
                }

                pub fn swap(ctx: @This(), lhs: usize, rhs: usize) void {
                    std.mem.swap(u16, &ctx.indices[lhs], &ctx.indices[rhs]);
                    std.mem.swap(String, &ctx.strings[lhs], &ctx.strings[rhs]);
                }
            };

            // TODO: Does this sort need to also sort by linker input order (if names equal)?
            std.sort.pdqContext(0, coff.lib_string_table.items.len, Context{
                .coff = coff,
                .indices = coff.secondLinkerMemberIndicesSlice(),
                .strings = coff.lib_string_table.items,
            });

            var offset: usize = 0;
            var string_table = coff.secondLinkerMemberStringsSlice();
            for (coff.lib_string_table.items) |string| {
                const str = string.toSlice(coff);
                @memcpy(string_table[offset..][0..str.len], str);
                string_table[offset + str.len] = 0;
                offset += str.len + 1;
            }
        },
        .coff => {
            const file_offset: u32 = @intCast(member.header_ni.fileLocation(&coff.mf, false).offset);
            const first_linker_offsets = coff.firstLinkerMemberOffsetsSlice();
            for (member.first_linker_indices.values()) |mfli|
                first_linker_offsets[@intFromEnum(mfli)] = std.mem.nativeTo(u32, file_offset, .big);
        },
    }
}

fn flushExportsSort(coff: *Coff) void {
    const Context = struct {
        coff: *Coff,
        np: []std.coff.ExportNamePointerTableEntry,
        ord: []std.coff.ExportOrdinalTableEntry,
        entries: []ExportTable.Entry,
        nt: []const u8,

        pub fn lessThan(ctx: *const @This(), lhs: usize, rhs: usize) bool {
            const lhs_entry = &ctx.entries[ctx.coff.targetLoad(&ctx.ord[lhs].unbiased_ordinal)];
            const rhs_entry = &ctx.entries[ctx.coff.targetLoad(&ctx.ord[rhs].unbiased_ordinal)];
            return std.mem.lessThan(
                u8,
                ctx.nt[lhs_entry.name_index..][0..lhs_entry.name_len],
                ctx.nt[rhs_entry.name_index..][0..rhs_entry.name_len],
            );
        }

        pub fn swap(ctx: @This(), lhs: usize, rhs: usize) void {
            std.mem.swap(std.coff.ExportNamePointerTableEntry, &ctx.np[lhs], &ctx.np[rhs]);
            std.mem.swap(std.coff.ExportOrdinalTableEntry, &ctx.ord[lhs], &ctx.ord[rhs]);
        }
    };

    std.sort.pdqContext(0, coff.export_table.entries.count(), &Context{
        .coff = coff,
        .np = coff.exportNamePointerTableSlice(),
        .ord = coff.exportOrdinalTableSlice(),
        .entries = coff.export_table.entries.values(),
        .nt = coff.export_table.name_table_ni.slice(&coff.mf),
    });
}

fn flushSectionMerges(coff: *Coff) !void {
    while (coff.section_merge_pending_index < coff.section_merges.count()) : (coff.section_merge_pending_index += 1)
        try coff.flushSectionMerge(coff.section_merge_pending_index);
}

fn flushSectionMerge(coff: *Coff, index: u32) !void {
    assert(coff.isImage());
    const from = coff.section_merges.keys()[index];
    const to = coff.section_merges.values()[index];
    assert(from != to);

    log.debug("flushSectionMerge({s}->{s})", .{ from.toSlice(coff), to.toSlice(coff) });

    const opt_to_sec = coff.section_table.getPtr(to);
    if (coff.section_table.getPtr(from)) |from_sec| {
        const from_sym = from_sec.si.get(coff);
        if (opt_to_sec) |to_sec| {
            const to_sym = to_sec.si.get(coff);

            // TODO: Create a pseudo-section named `from` in `to`, copy `from_sec` ni into that pseudo section
            // TODO: Update .section_number for all contained syms
            // TODO: Remove `from_sec` from section table (set size = 0 and can do it in flushResized?).
            //       This is non-trivial as we can't leave holes in the section table.
            // TODO: Merge section flags
            _ = to_sym;
            return coff.base.comp.link_diags.fail("TODO implement section to section merge", .{});
        } else if (coff.pseudo_section_table.get(to)) |to_ps_si| {
            const to_sym = to_ps_si.get(coff);
            if (from_sym.section_number == to_sym.section_number)
                return;

            // TODO: Same as above, except place `from` into a node in `to_psmi`'s parent
            return coff.base.comp.link_diags.fail("TODO implement section to pseudosection merge", .{});
        }

        // If `to` doesn't exist, /MERGE is defined as renaming `from` to `to`.
        // No other path will create image-level sections, so we can safely rename this now
        const from_name = &from_sec.si.get(coff).section_number.header(coff).name;
        const to_slice = to.toSlice(coff);
        @memcpy(from_name[0..to_slice.len], to_slice);
        @memset(from_name[to_slice.len..], 0);
    } else if (coff.pseudo_section_table.getIndex(from)) |from_index| {
        const from_psmi: Node.PseudoSectionMapIndex = @enumFromInt(from_index);
        const from_sym = from_psmi.symbol(coff).get(coff);
        if (opt_to_sec) |to_sec| {
            const to_sym = to_sec.si.get(coff);
            if (from_sym.section_number == to_sym.section_number)
                return;

            // TODO: Move from_psmi's node into to_sec
            // TODO: Update .section_number for all contained syms
            // TODO: Merge section flags
            return coff.base.comp.link_diags.fail("TODO implement pseudosection to section merge", .{});
        } else if (coff.pseudo_section_table.get(to)) |to_ps_si| {
            const to_sym = to_ps_si.get(coff);
            if (from_sym.section_number == to_sym.section_number)
                return;

            // TODO: Same as above, but move from_psmi's node after to_psmi's node in its parent
            return coff.base.comp.link_diags.fail("TODO implement pseudosection to pseudosection merge", .{});
        }

        // Renaming pseudo-sections have no effect on the output, so this is a no-op.
    }
}

fn virtualSlide(coff: *Coff, start_section_index: usize, start_rva: u32) !void {
    var rva = start_rva;
    for (
        coff.section_table.values()[start_section_index..],
        coff.sectionTableSlice()[start_section_index..],
    ) |*section, *header| {
        const section_sym = section.si.get(coff);
        section_sym.rva = rva;
        coff.targetStore(&header.virtual_address, rva);
        try section_sym.ni.childrenMoved(coff.base.comp.gpa, &coff.mf);
        rva += coff.targetLoad(&header.virtual_size);
    }
    switch (coff.optionalHeaderPtr()) {
        inline else => |optional_header| coff.targetStore(
            &optional_header.size_of_image,
            @intCast(rva),
        ),
    }
}

pub fn updateExports(
    coff: *Coff,
    pt: Zcu.PerThread,
    exported: Zcu.Exported,
    export_indices: []const Zcu.Export.Index,
) link.Error!void {
    const diags = &coff.base.comp.link_diags;
    return coff.updateExportsInner(pt, exported, export_indices) catch |err| switch (err) {
        error.MappedFileIo => return diags.fail(
            "failed to write output file: {t}",
            .{coff.mf.io_err.?},
        ),
        else => |e| return e,
    };
}
fn updateExportsInner(
    coff: *Coff,
    pt: Zcu.PerThread,
    exported: Zcu.Exported,
    export_indices: []const Zcu.Export.Index,
) !void {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;
    const ip = &zcu.intern_pool;

    try coff.symbols.ensureUnusedCapacity(gpa, export_indices.len);
    const exported_si: Symbol.Index = switch (exported) {
        .nav => |nav| try coff.navSymbol(zcu, nav),
        .uav => |uav| @enumFromInt(@intFromEnum(try coff.lowerUav(
            pt,
            uav,
            Type.fromInterned(ip.typeOf(uav)).abiAlignment(zcu),
        ))),
    };
    switch (exported) {
        .nav => |nav| log.debug("updateExports({f}) = {d}", .{ ip.getNav(nav).fqn.fmt(ip), exported_si }),
        .uav => |uav| log.debug("updateExports(@as({f}, {f})) = {d}", .{
            Type.fromInterned(ip.typeOf(uav)).fmt(pt),
            Value.fromInterned(uav).fmtValue(pt),
            exported_si,
        }),
    }
    while (try coff.resolve(pt.tid)) {}
    while (try coff.idle(pt.tid)) {}

    const machine = coff.targetLoad(&coff.headerPtr().machine);
    const exported_ni = exported_si.node(coff);
    const exported_sym = exported_si.get(coff);
    var prev_alias_si = exported_si;

    for (export_indices) |export_index| {
        const @"export" = export_index.ptr(zcu);
        const name = @"export".opts.name.toSlice(ip);

        // TODO: add an errMsg if this conflicts with an existing symbol
        const export_si = try coff.globalSymbol(.{ .name = name });
        const export_sym = export_si.get(coff);
        export_sym.ni = exported_ni;
        export_sym.rva = exported_sym.rva;
        export_sym.section_number = exported_sym.section_number;
        if (@"export".opts.linkage == .weak and !coff.isImage()) {
            // exported_si needs to be ahead of export_si in the symbol table,
            // so that its sti is known when creating the weak external aux entry
            try coff.pendingSymbolTableEntry(exported_si);
            export_sym.flags.weak_external_strat = .alias;
            export_sym.setValue(.{ .weak_alias_si = exported_si });
        }
        defer export_si.applyTargetRelocs(coff, .none) catch unreachable;

        // The last symbol in the alias list holds the size
        const prev_alias_sym = prev_alias_si.get(coff);
        switch (prev_alias_sym.flags.extra_tag) {
            .size => export_sym.setExtra(.{ .size = prev_alias_sym.extra.size }),
            // This export should have been deleted
            .next_alias_si => assert(prev_alias_sym.extra.next_alias_si == export_si),
            else => unreachable,
        }

        prev_alias_sym.setExtra(.{ .next_alias_si = export_si });
        prev_alias_si = export_si;

        if (!coff.isImage()) continue;

        const entries_ctx = ExportTable.Adapter{ .coff = coff };
        const gop = try coff.export_table.entries.getOrPutAdapted(
            gpa,
            name,
            entries_ctx,
        );

        if (!gop.found_existing) {
            errdefer _ = coff.export_table.entries.pop();

            const export_count = coff.export_table.entries.count();
            if (export_count > std.math.maxInt(@FieldType(std.coff.ExportDirectoryTable, "number_of_entries")))
                return coff.base.comp.link_diags.fail("exceeded maximum number of exports", .{});

            const name_index: u32 = @intCast(coff.export_table.name_table_ni.location(&coff.mf).resolve(&coff.mf)[1]);
            const new_name_table_size = name_index + name.len + 1;
            if (new_name_table_size > std.math.maxInt(@FieldType(ExportTable.Entry, "name_index")))
                return coff.base.comp.link_diags.fail("exports name table limit reached", .{});

            try coff.export_table.name_table_ni.resize(&coff.mf, gpa, new_name_table_size);

            const name_table_slice = coff.export_table.name_table_ni.slice(&coff.mf);
            @memcpy(name_table_slice[name_index..][0 .. name.len + 1], name[0 .. name.len + 1]);

            // If the new name sorts after the current tail of the sorted list, we don't need to re-sort
            {
                const ordinal_table_slice = coff.exportOrdinalTableSlice();
                if (ordinal_table_slice.len > 0 and !coff.export_table.pending_sort) {
                    const tail_index: ExportTable.Ordinal =
                        @enumFromInt(ordinal_table_slice[ordinal_table_slice.len - 1].unbiased_ordinal);
                    const tail_entry = tail_index.get(coff);
                    const tail_name = name_table_slice[tail_entry.name_index..][0..tail_entry.name_len];
                    coff.export_table.pending_sort = std.mem.lessThan(u8, name, tail_name);
                }
            }

            const edt = coff.exportDirectoryTable();
            coff.targetStore(&edt.number_of_names, @intCast(export_count));
            edt.number_of_entries = edt.number_of_names;

            // TODO: These should all be resized ahead of time to fit all exports
            //       after https://github.com/ziglang/zig/issues/23616
            try coff.export_table.export_address_table_si.node(coff).resize(
                &coff.mf,
                gpa,
                export_count * @sizeOf(std.coff.ExportAddressTableEntry),
            );

            try coff.export_table.name_pointer_table_ni.resize(
                &coff.mf,
                gpa,
                export_count * @sizeOf(std.coff.ExportNamePointerTableEntry),
            );

            try coff.export_table.ordinal_table_ni.resize(
                &coff.mf,
                gpa,
                export_count * @sizeOf(std.coff.ExportOrdinalTableEntry),
            );

            coff.targetStore(
                &coff.exportNamePointerTableSlice()[gop.index].name_rva,
                @intCast(coff.computeNodeRva(coff.export_table.name_table_ni) + name_index),
            );
            coff.targetStore(
                &coff.exportOrdinalTableSlice()[gop.index].unbiased_ordinal,
                @intCast(gop.index),
            );

            gop.value_ptr.* = .{
                .si = export_si,
                .name_index = @intCast(name_index),
                .name_len = @intCast(name.len),
                .export_address_table_ri = @enumFromInt(coff.relocs.items.len),
            };

            try coff.addReloc(
                coff.export_table.export_address_table_si,
                @intCast(@sizeOf(std.coff.ExportAddressTableEntry) * gop.index),
                export_si,
                .{ .known = 0 },
                switch (machine) {
                    else => |tag| @panic(@tagName(tag)),
                    .AMD64 => .{ .AMD64 = .ADDR32NB },
                    .I386 => .{ .I386 = .DIR32NB },
                },
            );
        } else {
            gop.value_ptr.si = export_si;
            const reloc = gop.value_ptr.*.export_address_table_ri.get(coff);
            reloc.target = export_si;
        }
    }
}

pub fn deleteExport(
    coff: *Coff,
    exported: Zcu.Exported,
    name: InternPool.NullTerminatedString,
) void {
    const zcu = coff.base.comp.zcu.?;
    const ip = &zcu.intern_pool;

    const exported_si: Symbol.Index = switch (exported) {
        .nav => |nav| coff.navs.get(nav).?,
        .uav => |uav| coff.uavs.get(uav).?,
    };

    const name_slice = name.toSlice(ip);
    log.debug("deleteExport({s}, {d})", .{ name_slice, exported_si });

    // TODO: Delete from first / second linker member table
    // TODO: Delete from symbol table inside section
}

fn dumpStderr(coff: *Coff, tid: Zcu.PerThread.Id) !void {
    const comp = coff.base.comp;
    const io = comp.io;
    var buffer: [512]u8 = undefined;
    const stderr = try io.lockStderr(&buffer, null);
    defer io.unlockStderr();
    const w = &stderr.file_writer.interface;
    _ = try coff.dump(w, tid);
}

pub fn dump(coff: *Coff, w: *Io.Writer, tid: Zcu.PerThread.Id) !link.File.DumpResult {
    if (coff.options.enable_link_snapshots) {
        try coff.printNode(tid, w, .root, 0);
        try w.writeAll("Section table:\n");
        for (coff.section_table.keys(), coff.section_table.values()) |name, sec|
            try coff.printSection(w, name, sec.si);
        try w.writeAll("Symbol table:\n");
        for (1..coff.symbols.items.len) |si|
            try coff.printSymbol(w, tid, @enumFromInt(si));

        return .enabled;
    }
    return .disabled;
}

fn printSection(coff: *Coff, w: *Io.Writer, name: String, si: Symbol.Index) !void {
    const sym = si.get(coff);
    try w.print("{d:0>6}@{d:0>2} {x:08} n{d:0>8} | {s}\n", .{
        si,
        sym.section_number,
        if (sym.flags.extra_tag == .size) sym.extra.size else 0,
        sym.ni,
        name.toSlice(coff),
    });
}

fn printSymbol(
    coff: *Coff,
    w: *Io.Writer,
    tid: Zcu.PerThread.Id,
    si: Symbol.Index,
) !void {
    const sym = si.get(coff);
    const node = coff.getNode(sym.ni);
    try w.print("{d:0>6}@{d:0>2} {x:08} {s} {s} {s} n{d:0>8}+{x:08}:{t: <26} | {x:08} ", .{
        si,
        sym.section_number,
        if (sym.flags.extra_tag == .size)
            @as(u64, sym.extra.size)
        else if (sym.ni != .none)
            sym.ni.location(&coff.mf).resolve(&coff.mf)[1]
        else
            0,
        switch (sym.flags.value_tag) {
            .none => "xx",
            .weak_alias_name => "an",
            .weak_alias_si => "as",
            .node_offset => "no",
        },
        switch (sym.flags.extra_tag) {
            .size => "sz",
            .isli => "li",
            .next_alias_si => "na",
        },
        switch (sym.flags.type) {
            .unknown => "u",
            .code => "c",
            .data => "d",
        },
        sym.ni,
        if (sym.flags.value_tag == .node_offset) sym.value.node_offset else 0,
        node,
        sym.rva,
    });

    if (sym.gmi != .none) {
        try w.print("G {f}\n", .{fmtGlobalName(coff, sym.gmi)});
    } else {
        try w.writeAll("| ");
        try coff.printNodeName(w, tid, node);
        if (sym.flags.extra_tag == .isli)
            try w.print(" | {s}", .{sym.extra.isli.name(coff).toSlice(coff)});
        try w.writeByte('\n');
    }
}

const FmtGlobalName = struct { coff: *Coff, gmi: Node.GlobalMapIndex };

fn fmtGlobalName(coff: *Coff, gmi: Node.GlobalMapIndex) std.fmt.Alt(FmtGlobalName, globalNameEscape) {
    return .{ .data = .{ .coff = coff, .gmi = gmi } };
}

fn globalNameEscape(data: FmtGlobalName, w: *std.Io.Writer) std.Io.Writer.Error!void {
    if (data.gmi == .none) return;
    try w.writeAll(data.gmi.name(data.coff).toSlice(data.coff));
    if (data.gmi.libName(data.coff).unwrap()) |lib_name|
        try w.print("({s})", .{lib_name.toSlice(data.coff)});
}

fn printNodeName(
    coff: *Coff,
    w: *std.Io.Writer,
    tid: Zcu.PerThread.Id,
    node: Node,
) !void {
    switch (node) {
        else => {},
        .image_section => |si| try w.print("({s})", .{
            std.mem.sliceTo(&si.get(coff).section_number.header(coff).name, 0),
        }),
        .input_section => |isi| {
            const ioi = isi.input(coff);
            const is = isi.inputSection(coff);
            try w.print("({f}{f}, {s}", .{
                ioi.path(coff).fmtEscapeString(),
                fmtMemberNameString(ioi.memberName(coff)),
                coff.getNode(is.si.node(coff).parent(&coff.mf)).object_section.name(coff).toSlice(coff),
            });
            if (is.comdat_si != .null) {
                const comdat_sym = is.comdat_si.get(coff);
                const comdat_name = if (comdat_sym.gmi != .none)
                    comdat_sym.gmi.name(coff).toSlice(coff)
                else
                    coff.input_symbols.items[@intFromEnum(comdat_sym.extra.isli)].name.toSlice(coff);

                try w.print("={s}", .{comdat_name});
            }
            try w.writeAll(")");
        },
        .import_lookup_table,
        .import_address_table,
        .import_hint_name_table,
        => |import_index| try w.print("({s})", .{
            std.mem.sliceTo(import_index.get(coff).import_hint_name_table_ni.sliceConst(&coff.mf), 0),
        }),
        inline .pseudo_section, .object_section => |smi| try w.print("({s})", .{
            smi.name(coff).toSlice(coff),
        }),
        .import_thunk,
        => |gmi| {
            try w.writeByte('(');
            if (gmi.libName(coff).toSlice(coff)) |lib_name| try w.print("{s}.dll, ", .{lib_name});
            try w.print("{s})", .{gmi.name(coff).toSlice(coff)});
        },
        .nav => |nmi| {
            const zcu = coff.base.comp.zcu.?;
            const ip = &zcu.intern_pool;
            const nav = ip.getNav(nmi.navIndex(coff));
            try w.print("({f}, {f})", .{
                Type.fromInterned(ip.typeOf(nav.resolved.?.value)).fmt(.{ .zcu = zcu, .tid = tid }),
                nav.fqn.fmt(ip),
            });
        },
        .uav => |umi| {
            const zcu = coff.base.comp.zcu.?;
            const val: Value = .fromInterned(umi.uavValue(coff));
            try w.print("({f}, {f})", .{
                val.typeOf(zcu).fmt(.{ .zcu = zcu, .tid = tid }),
                val.fmtValue(.{ .zcu = zcu, .tid = tid }),
            });
        },
        inline .lazy_code, .lazy_const_data => |lmi| try w.print("({f})", .{
            Type.fromInterned(lmi.lazySymbol(coff).ty).fmt(.{
                .zcu = coff.base.comp.zcu.?,
                .tid = tid,
            }),
        }),
        .builtin => |si| {
            const sym = si.get(coff);
            if (sym.gmi != .none) {
                try w.writeByte('(');
                if (sym.gmi.libName(coff).toSlice(coff)) |lib_name| try w.print("{s}.dll, ", .{lib_name});
                try w.print("{s})", .{sym.gmi.name(coff).toSlice(coff)});
            }
        },
    }
}

pub fn printNode(
    coff: *Coff,
    tid: Zcu.PerThread.Id,
    w: *Io.Writer,
    ni: MappedFile.Node.Index,
    indent: usize,
) !void {
    const node = coff.getNode(ni);
    try w.splatByteAll(' ', indent);
    try w.writeAll(@tagName(node));
    try coff.printNodeName(w, tid, node);
    {
        const mf_node = &coff.mf.nodes.items[@intFromEnum(ni)];
        const off, const size = mf_node.location().resolve(&coff.mf);
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
    var child_it = ni.children(&coff.mf);
    while (child_it.next()) |child_ni| {
        leaf = false;
        try coff.printNode(tid, w, child_ni, indent + 1);
    }
    if (leaf) {
        const file_loc = ni.fileLocation(&coff.mf, false);
        if (file_loc.size == 0) return;
        var address = file_loc.offset;
        const line_len = 0x10;
        var line_it = std.mem.window(
            u8,
            coff.mf.memory_map.memory[@intCast(file_loc.offset)..][0..@intCast(file_loc.size)],
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
}

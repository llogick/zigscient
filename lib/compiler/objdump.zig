const std = @import("std");
const Io = std.Io;
const fatal = std.process.fatal;
const mem = std.mem;
const assert = std.debug.assert;

const builtin = @import("builtin");
const native_endian = builtin.cpu.arch.endian();

var stdout_buffer: [4000]u8 = undefined;

const Options = struct {
    exports: bool,
    exports_sort: bool,
    file_headers: bool,
    imports: bool,
    input_path: []const u8,
    member_filters: []const []const u8 = &.{},
    member_headers: bool,
    elements: std.enums.EnumArray(Element, bool),
    redact: std.enums.EnumArray(FieldKind, bool),
    relocs: bool,
    section_filters: []const []const u8 = &.{},
    section_headers: bool,
    symbol_filters: []const []const u8 = &.{},
    strings: bool,
    symbols: bool,
    tls: bool,

    // Coff-specific
    linker_member: ?std.coff.ArchiveMemberHeader.Kind,
};

const FieldKind = enum {
    va,
    rva,
    ord,
    size,
};

const Element = enum {
    @"file-type",
    @"header-name",
    @"member-path",
    newlines,
    @"table-header",
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const arena = init.arena.allocator();

    var i: usize = 1;

    var opt_exports: ?bool = null;
    var opt_exports_sort: ?bool = null;
    var opt_file_headers: ?bool = null;
    var opt_imports: ?bool = null;
    var opt_input_path: ?[]const u8 = null;
    var opt_linker_member: ?std.coff.ArchiveMemberHeader.Kind = null;
    var opt_member_headers: ?bool = null;
    var any_elements = false;
    var elements: ?@FieldType(Options, "elements") = null;
    var redact: @FieldType(Options, "redact") = .initFill(false);
    var opt_relocs: ?bool = null;
    var opt_section_headers: ?bool = null;
    var opt_strings: ?bool = null;
    var opt_symbols: ?bool = null;
    var opt_tls: ?bool = null;
    var section_filters: std.ArrayList([]const u8) = .empty;
    var symbol_filters: std.ArrayList([]const u8) = .empty;
    var member_filters: std.ArrayList([]const u8) = .empty;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (mem.startsWith(u8, arg, "-")) {
            if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                return Io.File.stdout().writeStreamingAll(io, usage);
            } else if (mem.eql(u8, arg, "--all-headers")) {
                opt_file_headers = true;
                opt_linker_member = .second_linker;
                opt_member_headers = true;
                opt_section_headers = true;
                opt_symbols = true;
                opt_relocs = true;
            } else if (mem.startsWith(u8, arg, "--exports")) {
                opt_exports = true;
                opt_linker_member = .second_linker;
                if (mem.eql(u8, arg["--exports".len..], "=sort"))
                    opt_exports_sort = true;
            } else if (mem.eql(u8, arg, "--file-headers")) {
                opt_file_headers = true;
            } else if (mem.eql(u8, arg, "--imports")) {
                opt_imports = true;
            } else if (mem.startsWith(u8, arg, "--linker-member")) {
                if (mem.eql(u8, arg["--linker-member".len..], "=1"))
                    opt_linker_member = .first_linker
                else if (mem.eql(u8, arg["--linker-member".len..], "=longnames"))
                    opt_linker_member = .longnames
                else
                    opt_linker_member = .second_linker;
            } else if (mem.eql(u8, arg, "--member-headers")) {
                opt_member_headers = true;
            } else if (mem.startsWith(u8, arg, "--elements=")) {
                any_elements = true;
                var split = std.mem.splitScalar(u8, arg["--elements=".len..], ',');
                while (split.next()) |element| {
                    const kind, const add = if (element.len > 0 and element[0] == '-')
                        .{ element[1..], false }
                    else
                        .{ element, true };

                    if (elements == null) elements = .initFill(false);
                    if (std.meta.stringToEnum(Element, kind)) |format_kind| {
                        elements.?.set(format_kind, add);
                    } else if (std.mem.eql(u8, kind, "all")) {
                        elements.? = .initFill(add);
                    } else {
                        fatal("unrecognized element: '{s}'", .{kind});
                    }
                }
            } else if (mem.startsWith(u8, arg, "--only-member=")) {
                (try member_filters.addOne(arena)).* = try arena.dupe(u8, arg["--only-member=".len..]);
            } else if (mem.startsWith(u8, arg, "--only-section=")) {
                (try section_filters.addOne(arena)).* = try arena.dupe(u8, arg["--only-section=".len..]);
            } else if (mem.startsWith(u8, arg, "--only-symbol=")) {
                (try symbol_filters.addOne(arena)).* = try arena.dupe(u8, arg["--only-symbol=".len..]);
            } else if (mem.startsWith(u8, arg, "--redact=")) {
                const kind = arg["--redact=".len..];
                if (std.meta.stringToEnum(FieldKind, kind)) |field_kind| {
                    redact.set(field_kind, true);
                } else if (std.mem.eql(u8, kind, "all")) {
                    redact = .initFill(true);
                } else {
                    fatal("unrecognized redaction kind: {s}", .{kind});
                }
            } else if (mem.eql(u8, arg, "--relocs")) {
                opt_relocs = true;
            } else if (mem.eql(u8, arg, "--section-headers")) {
                opt_section_headers = true;
            } else if (mem.eql(u8, arg, "-s") or mem.eql(u8, arg, "--snapshot")) {
                elements = .initFill(false);
                redact = .initFill(true);
            } else if (mem.eql(u8, arg, "--strings")) {
                opt_strings = true;
            } else if (mem.eql(u8, arg, "--symbols")) {
                opt_symbols = true;
            } else if (mem.eql(u8, arg, "--tls")) {
                opt_tls = true;
            } else {
                fatal("unrecognized argument: {s}", .{arg});
            }
        } else if (opt_input_path == null) {
            opt_input_path = arg;
        } else {
            fatal("unexpected positional: {s}", .{arg});
        }
    }

    const opts: Options = .{
        .input_path = opt_input_path orelse fatal("missing input file path positional argument", .{}),
        .exports = opt_exports orelse false,
        .exports_sort = opt_exports_sort orelse false,
        .file_headers = opt_file_headers orelse false,
        .imports = opt_imports orelse false,
        .linker_member = opt_linker_member,
        .member_filters = member_filters.items,
        .member_headers = opt_member_headers orelse false,
        .elements = elements orelse .initFill(true),
        .redact = redact,
        .relocs = opt_relocs orelse false,
        .section_filters = section_filters.items,
        .section_headers = opt_section_headers orelse false,
        .strings = opt_strings orelse false,
        .symbol_filters = symbol_filters.items,
        .symbols = opt_symbols orelse false,
        .tls = opt_tls orelse false,
    };

    var file = std.Io.Dir.cwd().openFile(io, opts.input_path, .{}) catch |err|
        fatal("failed to open {s}: {t}", .{ opts.input_path, err });
    defer file.close(io);

    var buffer: [4096]u8 = undefined;
    var file_reader = file.reader(io, &buffer);
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &stdout_buffer);

    const ctx: DumpContext = .{
        .gpa = init.gpa,
        .opts = &opts,
        .fr = &file_reader,
        .w = &stdout_writer.interface,
    };

    dump(&ctx) catch |err| switch (err) {
        error.ReadFailed => return file_reader.err.?,
        error.WriteFailed => return stdout_writer.err.?,
        error.UnknownFile => fatal("unrecognized file: {s}", .{opts.input_path}),
        error.ParseFailure => {},
        else => |e| return e,
    };
    try stdout_writer.flush();
}

fn dump(d: *const DumpContext) !void {
    const r = &d.fr.interface;
    try r.fill(4);
    elf: {
        if (!mem.eql(u8, r.buffered()[0..4], std.elf.MAGIC)) break :elf;
        return elf.dump(r, d.w);
    }
    macho: {
        if (mem.readInt(u32, r.buffered()[0..4], .little) != std.macho.MH_MAGIC_64) break :macho;
        return macho.dump(r, d.w);
    }
    wasm: {
        comptime assert(std.wasm.magic.len == 4);
        if (!mem.eql(u8, r.buffered()[0..4], &std.wasm.magic)) break :wasm;
        return wasm.dump(r, d.w);
    }
    coff: {
        const ext = std.fs.path.extension(d.opts.input_path);
        const basename = std.fs.path.basename(d.opts.input_path);
        if (std.mem.eql(u8, ext, ".exe") or std.mem.eql(u8, ext, ".dll")) {
            if (!mem.eql(u8, r.buffered()[0..2], "MZ")) break :coff;
            try r.discardAll(std.coff.pe_pointer_offset);
            const sig_offset = try r.takeInt(u32, .little);
            try d.fr.seekTo(sig_offset);
            const sig = try r.take(4);

            if (!std.mem.eql(u8, sig, std.coff.pe_signature)) {
                try d.w.print("invalid PE signature: {x}", .{sig});
                return error.ParseFailure;
            }

            if (d.element(.@"file-type")) {
                try d.w.print("{s}: PE/COFF image\n\n", .{basename});
                if (d.element(.newlines)) try d.w.writeByte('\n');
            }

            return coff.dumpObject(d, true, basename);
        } else if (std.mem.eql(u8, ext, ".lib")) {
            r.fill(std.coff.archive_signature.len) catch break :coff;
            if (!mem.eql(u8, r.buffered()[0..std.coff.archive_signature.len], std.coff.archive_signature)) break :coff;
            if (d.element(.@"file-type")) {
                try d.w.print("{s}: COFF archive\n", .{basename});
                if (d.element(.newlines)) try d.w.writeByte('\n');
            }

            return coff.dumpArchive(d);
        } else if (std.mem.eql(u8, ext, ".obj")) {
            if (d.element(.@"file-type")) {
                try d.w.print("{s}: COFF object\n", .{basename});
                if (d.element(.newlines)) try d.w.writeByte('\n');
            }

            return coff.dumpObject(d, false, basename);
        }
    }
    return error.UnknownFile;
}

const DumpContext = struct {
    gpa: std.mem.Allocator,
    opts: *const Options,
    fr: *Io.File.Reader,
    w: *Io.Writer,

    fn element(self: *const DumpContext, e: Element) bool {
        return self.opts.elements.get(e);
    }

    fn redacted(self: *const DumpContext, opt_kind: ?FieldKind) bool {
        const kind = opt_kind orelse return false;
        return self.opts.redact.get(kind);
    }

    fn failParse(
        ctx: *const DumpContext,
        comptime fmt: []const u8,
        args: anytype,
    ) noreturn {
        std.log.err("error parsing '{s}'", .{std.fs.path.basename(ctx.opts.input_path)});
        fatal(fmt, args);
    }
};

const elf = struct {
    fn dump(r: *Io.Reader, w: *Io.Writer) !void {
        _ = r;
        try w.writeAll("TODO dump elf file\n");
    }
};

const macho = struct {
    fn dump(r: *Io.Reader, w: *Io.Writer) !void {
        _ = r;
        try w.writeAll("TODO dump macho file\n");
    }
};

const wasm = struct {
    fn dump(r: *Io.Reader, w: *Io.Writer) !void {
        _ = r;
        try w.writeAll("TODO dump wasm file\n");
    }
};

const coff = struct {
    const DIRECTORY_ENTRY = std.coff.IMAGE.DIRECTORY_ENTRY;

    const Section = struct {
        header: std.coff.SectionHeader,
        name: []const u8,

        fn rvaFileOffset(section: *const Section, rva: u32) !u32 {
            if (rva < section.header.virtual_address or
                rva >= section.header.virtual_address + section.header.size_of_raw_data)
                return error.OutOfBounds;

            return section.header.pointer_to_raw_data + (rva - section.header.virtual_address);
        }
    };

    const ArchiveHeader = struct {
        name: []const u8,
        date: u40,
        user_id: u20,
        group_id: u20,
        file_mode: u24,
        size: u34,

        pub fn fromRaw(d: *const DumpContext, raw_header: *const std.coff.ArchiveMemberHeader, opt_longnames: ?[]const u8) @This() {
            const name = raw_header.parseName(opt_longnames) catch |err| switch (err) {
                error.BadName => d.failParse("malformed member name: '{s}'", .{&raw_header.name}),
                error.NoLongNames => d.failParse("member uses a long name, but there was no longnames member", .{}),
            };

            return .{
                .name = name,
                .date = raw_header.parseDate() catch |err|
                    d.failParse("unable to parse date '{s}' in member '{s}': {t}", .{ raw_header.date, name, err }),
                .user_id = raw_header.parseUserId() catch |err|
                    d.failParse("unable to parse user_id '{s}' in member '{s}': {t}", .{ raw_header.user_id, name, err }),
                .group_id = raw_header.parseGroupId() catch |err|
                    d.failParse("unable to parse group_id '{s}' in member '{s}': {t}", .{ raw_header.group_id, name, err }),
                .file_mode = raw_header.parseFileMode() catch |err|
                    d.failParse("unable to parse file_mode '{s}' in member '{s}': {t}", .{ raw_header.file_mode, name, err }),
                .size = raw_header.parseSize() catch |err|
                    d.failParse("unable to parse size '{s}' in member '{s}': {t}", .{ raw_header.size, name, err }),
            };
        }
    };

    fn dumpArchive(d: *const DumpContext) !void {
        const gpa = d.gpa;
        const fr = d.fr;
        const w = d.w;

        const r = &fr.interface;
        r.toss(std.coff.archive_signature.len);

        const Member = struct {
            offset: u32,
            order: ?u32,
        };

        var members: std.ArrayList(Member) = .empty;
        defer members.deinit(gpa);
        var symbol_member_indices: std.ArrayList(u32) = .empty;
        defer symbol_member_indices.deinit(gpa);

        var opt_expected_kind: ?std.coff.ArchiveMemberHeader.Kind = .first_linker;
        var opt_longnames: ?[]const u8 = null;
        defer if (opt_longnames) |l| gpa.free(l);

        var pos = fr.logicalPos();
        const size = try fr.getSize();
        while (pos < size) : (pos = fr.logicalPos()) {
            if ((pos & 1) != 0) try r.discardAll(1);
            const raw_header = try r.takeStruct(std.coff.ArchiveMemberHeader, .little);
            const header: ArchiveHeader = .fromRaw(d, &raw_header, opt_longnames);

            if (!std.mem.eql(u8, &raw_header.end_of_header, std.coff.archive_end_of_header))
                return d.failParse("malformed end-of-header field in member '{s}': {x}", .{ header.name, raw_header.end_of_header });

            const dump_header =
                (d.opts.member_headers and filterMatches(d.opts.member_filters, header.name)) or
                (d.opts.linker_member == opt_expected_kind);

            if (dump_header)
                try dumpArchiveHeader(d, &header, @intCast(pos));

            const member_end = fr.logicalPos() + header.size;
            if (member_end > size)
                return d.failParse("out-of-bounds length 0x{x} in member '{s}'", .{ header.size, header.name });

            if (opt_expected_kind) |expected_kind| switch (expected_kind) {
                .first_linker => {
                    if (!std.mem.eql(u8, header.name, "/"))
                        return d.failParse("expected first linker member, found '{s}'", .{header.name});

                    const num_symbols = try r.takeInt(u32, .big);
                    if (dump_header)
                        try w.print(
                            \\{t: >16} type
                            \\               | {d} symbols
                            \\
                        , .{ expected_kind, num_symbols });

                    if (d.opts.linker_member == .first_linker) {
                        if (d.element(.@"table-header"))
                            try w.writeAll(
                                \\
                                \\Archive symbols:
                                \\& Member Symbol
                                \\
                            );

                        const offsets = try r.readAlloc(gpa, num_symbols * 4);
                        defer gpa.free(offsets);

                        for (0..num_symbols) |symbol_i| {
                            const symbol = r.takeDelimiter(0) catch |err|
                                return d.failParse("unable to read first linker member string table: {t}", .{err});

                            if (!filterMatches(d.opts.symbol_filters, symbol.?))
                                continue;

                            const offset = std.mem.readInt(u32, offsets[symbol_i * 4 ..][0..4], .big);
                            try w.print("{f} {s}\n", .{
                                fmtIntField(d, offset, .{ .kind = .va }),
                                symbol.?,
                            });
                        }
                    }
                    if (dump_header and d.element(.newlines)) try w.writeByte('\n');

                    try fr.seekTo(member_end);
                    opt_expected_kind = .second_linker;
                    continue;
                },
                .second_linker => {
                    if (!std.mem.eql(u8, header.name, "/"))
                        return d.failParse("expected second linker member, found '{s}'", .{header.name});

                    const num_members = try r.takeInt(u32, .little);
                    pos = fr.logicalPos();
                    if (pos + num_members * @sizeOf(u32) > member_end)
                        return d.failParse("invalid member count 0x{x} in second linker member", .{num_members});

                    try members.ensureTotalCapacity(gpa, num_members);
                    for (0..num_members) |_|
                        members.addOneAssumeCapacity().* = .{
                            .offset = try r.takeInt(u32, .little),
                            .order = null,
                        };

                    const num_symbols = try r.takeInt(u32, .little);
                    pos = fr.logicalPos();
                    if (pos + num_symbols * @sizeOf(u16) > member_end)
                        return d.failParse("invalid symbol count 0x{x} in second linker member", .{num_symbols});

                    if (dump_header)
                        try w.print(
                            \\{t: >16} type
                            \\               | {f} symbols
                            \\               | {f} members
                            \\
                        , .{
                            expected_kind,
                            fmtIntField(d, num_symbols, .{ .kind = .size, .width = .auto }),
                            fmtIntField(d, num_members, .{ .kind = .size, .width = .auto }),
                        });

                    try symbol_member_indices.ensureTotalCapacity(gpa, num_symbols);
                    for (0..num_symbols) |order| {
                        const index = (try r.takeInt(u16, .little)) - 1;
                        if (index >= members.items.len)
                            return d.failParse("invalid member index 0x{x} in seconds linker member indices array", .{index});

                        symbol_member_indices.addOneAssumeCapacity().* = index;

                        if (members.items[index].order == null)
                            members.items[index].order = @intCast(order);
                    }

                    if (d.opts.exports and d.opts.exports_sort) {
                        std.sort.pdq(Member, members.items, {}, struct {
                            fn lessThan(ctx: void, lhs: Member, rhs: Member) bool {
                                _ = ctx;
                                if (lhs.order == null and rhs.order == null)
                                    return lhs.offset < rhs.offset
                                else if (lhs.order) |lhs_order|
                                    return if (rhs.order) |rhs_order| lhs_order < rhs_order else false
                                else if (rhs.order) |rhs_order|
                                    return if (lhs.order) |lhs_order| lhs_order < rhs_order else true
                                else
                                    unreachable;
                            }
                        }.lessThan);
                    }

                    if (d.opts.linker_member == .second_linker) {
                        if (d.element(.@"table-header"))
                            try w.writeAll(
                                \\
                                \\Archive Symbols:
                                \\& Member Symbol
                                \\
                            );

                        pos = fr.logicalPos();
                        var symbol_i: u32 = 0;
                        while (pos < member_end and symbol_i < num_symbols) : ({
                            pos = fr.logicalPos();
                            symbol_i += 1;
                        }) {
                            const symbol_name = if (r.takeDelimiter(0) catch |err| switch (err) {
                                error.StreamTooLong => null,
                                else => |e| return e,
                            }) |n| n else return d.failParse("unterminated string found in second linker member", .{});

                            if (!filterMatches(d.opts.symbol_filters, symbol_name))
                                continue;

                            try w.print("{f} {s}\n", .{
                                fmtIntField(
                                    d,
                                    members.items[symbol_member_indices.items[symbol_i]].offset,
                                    .{ .kind = .va },
                                ),
                                symbol_name,
                            });
                        }

                        if (symbol_i != num_symbols)
                            return d.failParse(
                                " expected {d} entries in second linker member string table, but found {d}",
                                .{ num_symbols, symbol_i },
                            );
                    }

                    if (d.element(.newlines)) try w.writeByte('\n');
                    try fr.seekTo(member_end);
                    opt_expected_kind = .longnames;
                    continue;
                },
                .longnames => {
                    // This member is optional
                    if (std.mem.eql(u8, header.name, "//")) {
                        opt_longnames = try r.readAlloc(gpa, header.size);
                        if (dump_header)
                            try w.print("{t: >16} type\n", .{expected_kind});

                        if (d.opts.linker_member == .longnames) {
                            if (d.element(.@"table-header"))
                                try w.print(
                                    \\
                                    \\Longnames (0x{x} bytes):
                                    \\
                                , .{opt_longnames.?.len});

                            var lr = Io.Reader.fixed(opt_longnames.?);
                            while (try lr.takeDelimiter(0)) |str| {
                                try w.writeAll(str);
                                try w.writeByte('\n');
                            }
                        }

                        if (d.element(.newlines)) try w.writeByte('\n');
                    }

                    opt_expected_kind = null;
                    break;
                },
                else => unreachable,
            };
        }

        if (opt_expected_kind) |expected_kind| switch (expected_kind) {
            .first_linker => d.failParse("missing first linker member", .{}),
            .second_linker => d.failParse("missing second linker member", .{}),
            else => {},
        };

        for (members.items, 0..) |member, member_i| {
            fr.seekTo(member.offset) catch |err|
                d.failParse("unable to read member {d} at offset 0x{x}: {t}", .{ member_i, member.offset, err });

            const raw_header = try r.takeStruct(std.coff.ArchiveMemberHeader, .little);
            const header: ArchiveHeader = .fromRaw(d, &raw_header, opt_longnames);
            if (!filterMatches(d.opts.member_filters, header.name)) continue;

            const member_sig = try r.peek(4);
            const machine: std.coff.IMAGE.FILE.MACHINE =
                @fromBackingInt(@intCast(std.mem.readInt(u16, member_sig[0..2], .little)));
            const sig = std.mem.readInt(u16, member_sig[2..4], .little);

            const is_imp_lib = machine == std.coff.IMAGE.FILE.MACHINE.UNKNOWN and sig == 0xffff;
            if (d.opts.member_headers)
                try dumpArchiveHeader(d, &header, member.offset);

            if (d.opts.member_headers or (d.opts.exports and is_imp_lib)) {
                if (is_imp_lib) {
                    const imp_header = try r.takeStruct(std.coff.ImportHeader, .little);
                    const sym_name = (try r.takeDelimiter(0)).?;
                    const imp_dll = (try r.takeDelimiter(0)).?;

                    if (!filterMatches(d.opts.symbol_filters, sym_name))
                        continue;

                    if (d.element(.@"header-name"))
                        try w.writeAll("\nImport header:\n");

                    try dumpHeader(d, std.coff.ImportHeader, &imp_header, struct {
                        pub fn sig1(_: *const DumpContext, _: *const std.coff.ImportHeader) !void {}
                        pub fn sig2(_: *const DumpContext, _: *const std.coff.ImportHeader) !void {}
                        pub fn types(id: *const DumpContext, h: *const std.coff.ImportHeader) !void {
                            try id.w.print(
                                \\{t: >16} import_type 
                                \\{t: >16} name_type 
                                \\
                            , .{ h.types.type, h.types.name_type });
                        }
                    });

                    const imp_name = imp_name: switch (imp_header.types.name_type) {
                        .NAME_NOPREFIX,
                        .NAME_UNDECORATE,
                        => |tag| {
                            var imp_name = std.mem.trimStart(u8, sym_name, "?@_");
                            if (tag == .NAME_UNDECORATE)
                                imp_name = std.mem.sliceTo(imp_name, '@');
                            break :imp_name imp_name;
                        },
                        else => sym_name,
                    };

                    try w.print(
                        \\     symbol name | {s}
                        \\     import name | {s}
                        \\             dll | {s}
                        \\
                    , .{
                        sym_name,
                        imp_name,
                        imp_dll,
                    });
                } else {
                    try w.writeAll("     COFF object type\n");
                }
                if (d.element(.newlines)) try w.writeByte('\n');
            }

            if (is_imp_lib) continue;
            if (d.opts.section_headers or
                d.opts.file_headers or
                d.opts.relocs or
                d.opts.strings or
                d.opts.symbols)
            {
                const member_name = if (d.element(.@"member-path"))
                    header.name
                else
                    std.fs.path.basename(header.name);

                if (d.element(.@"file-type")) {
                    try w.print("{s}({s}): COFF object\n", .{
                        std.fs.path.basename(d.opts.input_path),
                        member_name,
                    });
                    if (d.element(.newlines)) try w.writeByte('\n');
                }
                try dumpObject(d, false, member_name);
            }
        }
    }

    fn dumpObject(
        d: *const DumpContext,
        is_image: bool,
        obj_name: []const u8,
    ) !void {
        const gpa = d.gpa;
        const fr = d.fr;
        const w = d.w;

        const file_location = fr.logicalPos();
        const r = &fr.interface;
        const header = r.takeStruct(std.coff.Header, .little) catch |err|
            return d.failParse("unable to read COFF header: {t}", .{err});

        if (d.opts.file_headers) {
            if (d.element(.@"header-name")) try w.writeAll("COFF Header:\n");
            try dumpHeader(d, std.coff.Header, &header, struct {});
            if (d.element(.newlines)) try w.writeByte('\n');
        }

        switch (header.machine) {
            _ => return d.failParse("unknown machine type: {x}", .{header.machine}),
            else => {},
        }

        var known_dirs: [DIRECTORY_ENTRY.len]std.coff.ImageDataDirectory = undefined;
        const needs_data_dirs =
            d.opts.exports or
            d.opts.imports or
            d.opts.tls;

        const ImageInfo = struct {
            data_dirs: []const std.coff.ImageDataDirectory,
            magic: std.coff.OptionalHeader.Magic,
            image_base: u64,
        };

        const image_info: ?ImageInfo = if (header.size_of_optional_header > 0) image_info: {
            if (!d.opts.file_headers and !needs_data_dirs) {
                try fr.seekBy(header.size_of_optional_header);
                break :image_info null;
            }

            if (d.opts.file_headers and d.element(.@"header-name"))
                try w.writeAll("COFF Optional Header:\n");

            const magic: std.coff.OptionalHeader.Magic = @fromBackingInt(@intCast(try r.peekInt(u16, .little)));
            const num_directory_entries, const image_base = switch (magic) {
                inline .PE32, .@"PE32+" => |v| num_data_dirs: {
                    const OptionalHeader = if (v == .PE32)
                        std.coff.OptionalHeader.PE32
                    else
                        std.coff.OptionalHeader.@"PE32+";

                    const optional_header = r.takeStruct(OptionalHeader, .little) catch |err|
                        return d.failParse("unable to read optional header: {t}", .{err});

                    if (d.opts.file_headers) {
                        try dumpHeader(d, OptionalHeader, &optional_header, struct {
                            pub fn base_of_code(id: *const DumpContext, h: *const std.coff.OptionalHeader) !void {
                                const base = @as(*const OptionalHeader, @ptrCast(@alignCast(h))).image_base;
                                try dumpRvaField(id, @src().fn_name, h.base_of_code, base);
                            }

                            pub fn address_of_entry_point(id: *const DumpContext, h: *const std.coff.OptionalHeader) !void {
                                const base = @as(*const OptionalHeader, @ptrCast(@alignCast(h))).image_base;
                                try dumpRvaField(id, @src().fn_name, h.base_of_code, base);
                            }

                            pub fn major_linker_version(id: *const DumpContext, h: *const std.coff.OptionalHeader) !void {
                                try dumpVersionField(id.w, "linker_version", h.major_linker_version, h.minor_linker_version);
                            }
                            pub fn minor_linker_version(_: *const DumpContext, _: *const std.coff.OptionalHeader) !void {}

                            pub fn major_operating_system_version(id: *const DumpContext, h: *const OptionalHeader) !void {
                                try dumpVersionField(
                                    id.w,
                                    "operating_system_version",
                                    h.major_operating_system_version,
                                    h.minor_operating_system_version,
                                );
                            }
                            pub fn minor_operating_system_version(_: *const DumpContext, _: *const OptionalHeader) !void {}

                            pub fn major_image_version(id: *const DumpContext, h: *const OptionalHeader) !void {
                                try dumpVersionField(id.w, "image_version", h.major_image_version, h.minor_image_version);
                            }
                            pub fn minor_image_version(_: *const DumpContext, _: *const OptionalHeader) !void {}

                            pub fn major_subsystem_version(id: *const DumpContext, h: *const OptionalHeader) !void {
                                try dumpVersionField(id.w, "subsystem_version", h.major_subsystem_version, h.minor_subsystem_version);
                            }
                            pub fn minor_subsystem_version(_: *const DumpContext, _: *const OptionalHeader) !void {}
                        });
                        if (d.element(.newlines)) try w.writeByte('\n');
                    }

                    break :num_data_dirs .{
                        optional_header.number_of_rva_and_sizes,
                        optional_header.image_base,
                    };
                },
                else => return d.failParse("invalid optional header magic number: {x}", .{magic}),
            };

            if (d.opts.file_headers and d.element(.@"header-name"))
                try w.writeAll("Data Directories:\n");

            for (0..num_directory_entries) |dir_i| {
                const dir = r.takeStruct(std.coff.ImageDataDirectory, .little) catch |err|
                    return d.failParse("unable to read data directory {x}: {t}", .{ dir_i, err });

                if (dir_i < known_dirs.len)
                    known_dirs[dir_i] = dir;

                if (d.opts.file_headers)
                    try w.print(
                        "{x: >16} {x: >8} {t}\n",
                        .{ dir.virtual_address, dir.size, @as(DIRECTORY_ENTRY, @fromBackingInt(@intCast(dir_i))) },
                    );
            }
            if (d.opts.file_headers and d.element(.newlines)) try w.writeByte('\n');

            break :image_info .{
                .data_dirs = known_dirs[0..@min(known_dirs.len, num_directory_entries)],
                .magic = magic,
                .image_base = image_base,
            };
        } else if (is_image) {
            return d.failParse("image did not contain an optional header", .{});
        } else null;

        // Section names in images don't use the string table, as they must fit inline in the header
        const load_string_table = (d.opts.strings or !is_image) and header.pointer_to_symbol_table > 0;
        const string_table = if (load_string_table) string_table: {
            const pos = fr.logicalPos();
            fr.seekTo(file_location + header.pointer_to_symbol_table + header.number_of_symbols * std.coff.Symbol.sizeOf()) catch |err|
                return d.failParse("unable to seek to string table: {t}", .{err});

            const string_table_len = r.peekInt(u32, .little) catch |err|
                return d.failParse("unable to read string table length: {t}", .{err});

            const table = r.readAlloc(gpa, string_table_len) catch |err|
                return d.failParse("unable to read string table: {t}", .{err});

            try fr.seekTo(pos);
            break :string_table table;
        } else &.{};
        defer gpa.free(string_table);

        if (d.opts.strings) {
            if (d.element(.@"table-header"))
                try w.print(
                    \\String Table (0x{x} bytes):
                    \\
                , .{string_table.len});

            var sr = Io.Reader.fixed(string_table[@sizeOf(u32)..]);
            while (try sr.takeDelimiter(0)) |str| {
                try w.writeAll(str);
                try w.writeByte('\n');
            }

            if (d.element(.newlines)) try w.writeByte('\n');
        }

        var sections: std.ArrayList(Section) = .empty;
        defer sections.deinit(gpa);
        var sections_with_data: u16 = 0;

        const load_sections =
            d.opts.section_headers or
            d.opts.symbols or
            d.opts.relocs or
            needs_data_dirs;

        if (load_sections) {
            if (d.opts.section_headers and d.element(.@"table-header"))
                try w.print(
                    \\Sections in '{s}':
                    \\Num Name          RVA Virt Size Data Size   & Data & Relocs  & Lines # Relocs  # Lines    Flags
                    \\
                , .{obj_name});

            try sections.resize(gpa, header.number_of_sections);
            for (sections.items, 0..) |*section, section_i| {
                section.header = r.takeStruct(std.coff.SectionHeader, .little) catch |err|
                    return d.failParse("unable to read section header {x}: {t}", .{ section_i, err });
                section.name = headerName(&section.header.name, string_table) catch |err| switch (err) {
                    error.Overflow,
                    error.InvalidCharacter,
                    => return d.failParse("unable to parse section name offset '{s}': {t}", .{
                        section.name,
                        err,
                    }),
                    error.OutOfBounds => return d.failParse("section name offset '{s}' was out of bounds (>= {x})", .{
                        section.name,
                        string_table.len,
                    }),
                };

                sections_with_data += @intFromBool(section.header.size_of_raw_data > 0);
                if (d.opts.section_headers) {
                    if (!filterMatches(d.opts.section_filters, section.name)) continue;
                    const raw_name = std.mem.sliceTo(&section.header.name, 0);
                    try w.print(
                        "{x: >3} {s: <8} {f} {f} {f} {f} {f} {f} {f} {f} {x:0>8} |",
                        .{
                            section_i + 1,
                            raw_name,
                            fmtIntField(d, section.header.virtual_address, .{ .kind = .va }),
                            fmtIntField(d, section.header.virtual_size, .{ .kind = .size, .width = .{ .explicit = 9 } }),
                            fmtIntField(d, section.header.size_of_raw_data, .{ .kind = .size, .width = .{ .explicit = 9 } }),
                            fmtIntField(d, section.header.pointer_to_raw_data, .{ .kind = .va }),
                            fmtIntField(d, section.header.pointer_to_relocations, .{ .kind = .va }),
                            fmtIntField(d, section.header.pointer_to_linenumbers, .{ .kind = .va }),
                            fmtIntField(d, section.header.number_of_relocations, .{ .kind = .va }),
                            fmtIntField(d, section.header.number_of_linenumbers, .{ .kind = .va }),
                            @as(u32, @bitCast(section.header.flags)),
                        },
                    );

                    try dumpFlags(w, "{s}", std.coff.SectionHeader.Flags, &section.header.flags, 1);
                    if (section.name.len > 8)
                        try w.print("\n  | {s}", .{section.name});

                    try w.writeByte('\n');
                }
            }

            if (d.opts.section_headers and d.element(.newlines)) try w.writeByte('\n');
        }

        var symbols: std.ArrayList(struct {
            name: []const u8,
            section_number: std.coff.SectionNumber,
        }) = .empty;
        defer symbols.deinit(gpa);

        var name_arena: std.heap.ArenaAllocator = .init(gpa);
        defer name_arena.deinit();

        if (d.opts.relocs)
            try symbols.ensureUnusedCapacity(gpa, header.number_of_symbols);

        if (d.opts.symbols or d.opts.relocs) {
            if (header.pointer_to_symbol_table > 0) {
                fr.seekTo(file_location + header.pointer_to_symbol_table) catch |err|
                    return d.failParse("unable to seek to symbol table: {t}", .{err});

                if (d.opts.symbols and d.element(.@"table-header"))
                    try w.print(
                        \\Symbols in '{s}':
                        \\ Ord    Value  Sect Type           Storage   Name
                        \\
                    , .{obj_name});

                const symbol_size = std.coff.Symbol.sizeOf();
                var symbol_i: u32 = 0;
                while (symbol_i < header.number_of_symbols) {
                    var symbol: std.coff.Symbol = undefined;
                    const symbol_bytes = r.take(symbol_size) catch |err|
                        return d.failParse("unable to read symbol {x}: {t}", .{ symbol_i, err });

                    @memcpy(std.mem.asBytes(&symbol)[0..symbol_size], symbol_bytes);
                    if (native_endian != .little)
                        std.mem.byteSwapAllFields(std.coff.Symbol, &symbol);

                    const aux_symbols = if (symbol.number_of_aux_symbols > 0)
                        try r.take(symbol_size * symbol.number_of_aux_symbols)
                    else
                        &.{};
                    defer symbol_i += symbol.number_of_aux_symbols + 1;

                    const name = if (std.mem.eql(u8, symbol.name[0..4], "\x00\x00\x00\x00")) name: {
                        const index = std.mem.readInt(u32, symbol.name[4..], .little);
                        if (index >= string_table.len)
                            return d.failParse("invalid name offset for symbol {x} ({x} >= {x})", .{
                                symbol_i,
                                index,
                                string_table.len,
                            });
                        break :name std.mem.sliceTo(string_table[index..], 0);
                    } else try name_arena.allocator().dupe(u8, std.mem.sliceTo(&symbol.name, 0));

                    if (d.opts.relocs)
                        symbols.appendNTimesAssumeCapacity(.{
                            .name = name,
                            .section_number = symbol.section_number,
                        }, 1 + symbol.number_of_aux_symbols);

                    if (!d.opts.symbols or !filterMatches(d.opts.symbol_filters, name))
                        continue;

                    try w.print("{f} {x:0>8} ", .{
                        fmtIntField(d, @as(u16, @intCast(symbol_i)), .{ .kind = .ord }),
                        symbol.value,
                    });
                    try switch (symbol.section_number) {
                        .UNDEFINED => w.writeAll("UNDEF"),
                        .ABSOLUTE => w.writeAll("  ABS"),
                        .DEBUG => w.writeAll("DEBUG"),
                        else => |v| {
                            const backing = @backingInt(v);
                            const fmt = "{x: >5}";
                            if (backing >= 0)
                                try w.print(fmt, .{@as(u15, @intCast(backing))})
                            else
                                try w.print(fmt, .{backing});
                        },
                    };

                    try w.print("{t: >5}", .{symbol.type.base_type});
                    if (switch (symbol.type.complex_type) {
                        .NULL => "  ",
                        .POINTER => "* ",
                        .FUNCTION => "()",
                        .ARRAY => "[]",
                        else => null,
                    }) |suffix| try w.writeAll(suffix) else try w.print("{x}", .{symbol.type.complex_type});

                    try w.print("{t: >16} | {s}\n", .{ symbol.storage_class, name });

                    for (0..symbol.number_of_aux_symbols) |aux_i| {
                        _ = aux_i;
                        try w.writeAll("   |");

                        if (symbol.storage_class == .EXTERNAL and
                            symbol.type == std.coff.SymType{
                                .complex_type = .FUNCTION,
                                .base_type = .NULL,
                            } and
                            @backingInt(symbol.section_number) > 0)
                        {
                            try w.writeAll("TODO function aux symbol");
                        } else if (symbol.type == std.coff.SymType{
                            .complex_type = .FUNCTION,
                            .base_type = .NULL,
                        } and
                            (std.mem.eql(u8, name, ".bf") or std.mem.eql(u8, name, ".ef")))
                        {
                            try w.writeAll("TODO bf / ef aux symbol");
                        } else if (symbol.storage_class == .WEAK_EXTERNAL and symbol.section_number == .UNDEFINED) {
                            if (symbol.value != 0)
                                return d.failParse(
                                    "invalid value 0x{x} for weak external symbol 0x{x}",
                                    .{ symbol.value, symbol_i },
                                );

                            var weak_external: std.coff.WeakExternalDefinition = undefined;
                            @memcpy(std.mem.asBytes(&weak_external)[0..symbol_size], aux_symbols[0..symbol_size]);
                            if (native_endian != .little)
                                std.mem.byteSwapAllFields(std.coff.WeakExternalDefinition, &weak_external);

                            if (weak_external.tag_index >= header.number_of_symbols)
                                return d.failParse(
                                    "invalid tag_index 0x{x} for weak external symbol 0x{x}",
                                    .{ weak_external.tag_index, symbol_i },
                                );

                            if (d.redacted(.ord))
                                try w.print("  Weak External [falls back to relative ordinal {x:0>8} via {t}]", .{
                                    @as(i64, weak_external.tag_index) - symbol_i,
                                    weak_external.flag,
                                })
                            else
                                try w.print("  Weak External [falls back to ordinal {x:0>8} via {t}]", .{
                                    weak_external.tag_index,
                                    weak_external.flag,
                                });
                        } else if (symbol.storage_class == .FILE) {
                            if (!std.mem.eql(u8, name, ".file")) {
                                try w.print(" !! unexpected symbol name '{s}' for file symbol 0x{x}", .{ name, symbol_i });
                                continue;
                            }

                            const filename = std.mem.sliceTo(aux_symbols, 0);
                            try w.print("     File       '{s}'", .{filename});
                            break;
                        } else if (symbol.storage_class == .STATIC and
                            symbol.type == std.coff.SymType{
                                .complex_type = .NULL,
                                .base_type = .NULL,
                            } and
                            symbol.value == 0 and
                            switch (symbol.section_number) {
                                .UNDEFINED, .DEBUG, .ABSOLUTE => false,
                                else => |sn| @backingInt(sn) > 0,
                            })
                        {
                            const section_i: u15 = @intCast(@backingInt(symbol.section_number) - 1);
                            try w.writeAll("  Section ");

                            if (section_i >= sections.items.len) {
                                try w.print(" !! invalid section number: {x}", .{section_i});
                                continue;
                            }

                            var section_def: std.coff.SectionDefinition = undefined;
                            @memcpy(std.mem.asBytes(&section_def)[0..symbol_size], aux_symbols[0..symbol_size]);
                            if (native_endian != .little)
                                std.mem.byteSwapAllFields(std.coff.SectionDefinition, &section_def);

                            const section = &sections.items[section_i];
                            if (section_def.number_of_relocations != section.header.number_of_relocations) {
                                try w.print(
                                    " !! relocation count did not match section header: {d} vs {d}",
                                    .{ section_def.number_of_relocations, section.header.number_of_relocations },
                                );
                                continue;
                            }

                            if (section_def.number_of_linenumbers != section.header.number_of_linenumbers) {
                                try w.print(
                                    " !! line number count did not match section header: {d} vs {d}",
                                    .{ section_def.number_of_linenumbers, section.header.number_of_linenumbers },
                                );
                                continue;
                            }

                            try w.print("      [size {f} chksum {x:0>8} relocs {x:0>4} lines {x:0>4}]", .{
                                fmtIntField(d, section_def.length, .{ .kind = .size, .zero_fill = true }),
                                section_def.checksum,
                                section_def.number_of_relocations,
                                section_def.number_of_linenumbers,
                            });

                            switch (section_def.selection) {
                                .NONE => {},
                                else => |selection| {
                                    try w.print(" COMDAT({t}", .{selection});
                                    if (selection == .ASSOCIATIVE)
                                        try w.print("->{x}", .{section_def.number});
                                    try w.writeAll(")");
                                },
                            }
                        }

                        try w.writeByte('\n');
                    }
                }

                if (d.opts.symbols and d.element(.newlines)) try w.writeByte('\n');
            } else if (d.opts.symbols) {
                try w.writeAll("No symbol table found\n");
            }
        }

        if (d.opts.relocs) {
            const relocation_size = std.coff.Relocation.sizeOf();

            for (sections.items, 0..) |section, section_i| {
                if (section.header.pointer_to_relocations == 0) continue;

                if (d.element(.@"table-header"))
                    try w.print(
                        \\Relocs for section {x} '{s}' in {s}:
                        \\  Offset Type                Symbol -> Sect   Name
                        \\
                    , .{ section_i + 1, section.name, obj_name });

                fr.seekTo(file_location + section.header.pointer_to_relocations) catch |err|
                    return d.failParse("unable to seek to section {x} relocation table: {t}", .{ section_i + 1, err });

                for (0..section.header.number_of_relocations) |reloc_i| {
                    var reloc: std.coff.Relocation = undefined;
                    @memcpy(std.mem.asBytes(&reloc)[0..relocation_size], try r.take(relocation_size));
                    if (native_endian != .little)
                        std.mem.byteSwapAllFields(std.coff.Relocation, &reloc);

                    const sym = &symbols.items[reloc.symbol_table_index];
                    if (!filterMatches(d.opts.symbol_filters, sym.name))
                        continue;

                    try w.print("{f} ", .{
                        fmtIntField(d, reloc.virtual_address, .{ .kind = .va, .zero_fill = true }),
                    });
                    switch (header.machine) {
                        _ => unreachable,
                        inline else => |m| switch (m.RelocationType()) {
                            void => try w.writeAll("(unknown arch)"),
                            else => |RelocationType| try w.print(
                                "{t: <17} ",
                                .{@as(RelocationType, @fromBackingInt(@intCast(reloc.type)))},
                            ),
                        },
                    }

                    if (reloc.symbol_table_index >= symbols.items.len)
                        return d.failParse(
                            "reloc {x} in section {x} has out-of-bounds symbol index {x}",
                            .{ reloc_i, section_i + 1, reloc.symbol_table_index },
                        );

                    try w.print("{f}   {f} | {s}\n", .{
                        fmtIntField(d, reloc.symbol_table_index, .{ .kind = .ord }),
                        fmtSectionNumber(sym.section_number),
                        sym.name,
                    });
                }
                if (d.element(.newlines)) try w.writeByte('\n');
            }
        }

        // Sections indices with raw data, sorted by RVA
        const rva_index = if (needs_data_dirs) rva_index: {
            const rva_index = try gpa.alloc(u16, sections_with_data);
            var indices_i: u16 = 0;
            for (sections.items, 0..) |*section, i| {
                if (section.header.size_of_raw_data == 0) continue;
                rva_index[indices_i] = @intCast(i);
                indices_i += 1;
            }

            const Context = struct {
                indices: []u16,
                sections: []const Section,

                pub fn lessThan(ctx: @This(), lhs: usize, rhs: usize) bool {
                    return ctx.sections[ctx.indices[lhs]].header.virtual_address <
                        ctx.sections[ctx.indices[rhs]].header.virtual_address;
                }

                pub fn swap(ctx: @This(), lhs: usize, rhs: usize) void {
                    std.mem.swap(u16, &ctx.indices[lhs], &ctx.indices[rhs]);
                }
            };

            std.sort.pdqContext(0, rva_index.len, Context{
                .indices = rva_index,
                .sections = sections.items,
            });

            break :rva_index rva_index;
        } else &.{};
        defer gpa.free(rva_index);

        if (d.opts.exports) exports: {
            if (try seekToDataDirectory(
                d,
                rva_index,
                sections.items,
                (image_info orelse {
                    try w.writeAll("COFF objects do not contain an export data directory");
                    break :exports;
                }).data_dirs,
                .EXPORT,
            )) |section_index| {
                const export_dir = r.takeStruct(std.coff.ExportDirectoryTable, .little) catch |err|
                    return d.failParse("unable to read export directory: {t}", .{err});

                try w.print("Export directory:\n", .{});
                try dumpHeader(d, std.coff.ExportDirectoryTable, &export_dir, struct {
                    pub fn major_version(id: *const DumpContext, h: *const std.coff.ExportDirectoryTable) !void {
                        try dumpVersionField(id.w, "version", h.major_version, h.minor_version);
                    }
                    pub fn minor_version(_: *const DumpContext, _: *const std.coff.ExportDirectoryTable) !void {}
                });

                const section = sections.items[section_index];
                const name_loc = section.rvaFileOffset(export_dir.name_rva) catch
                    return d.failParse(
                        "export name rva 0x{x} was not within the export section",
                        .{export_dir.name_rva},
                    );

                const eat_loc = section.rvaFileOffset(export_dir.export_address_table_rva) catch
                    return d.failParse(
                        "export address table rva 0x{x} was not within the export section",
                        .{export_dir.export_address_table_rva},
                    );

                const name_pointer_loc = section.rvaFileOffset(export_dir.name_pointer_table_rva) catch
                    return d.failParse(
                        "export name pointer table rva 0x{x} was not within the export section",
                        .{export_dir.name_pointer_table_rva},
                    );

                const ord_loc = section.rvaFileOffset(export_dir.ordinal_table_rva) catch
                    return d.failParse(
                        "export ordinal table rva 0x{x} was not within the export section",
                        .{export_dir.ordinal_table_rva},
                    );

                // All the variable length fields should be contained within this directory.
                // Read it entirely to avoid needing to seek per-name when iterating.
                const dir = image_info.?.data_dirs[@backingInt(DIRECTORY_ENTRY.EXPORT)];
                const dir_end_rva = dir.virtual_address + dir.size;
                const dir_loc = fr.logicalPos();
                const dir_slice = try r.readAlloc(gpa, dir.size);
                defer gpa.free(dir_slice);

                const dll_name = std.mem.sliceTo(dir_slice[name_loc - dir_loc ..], 0);
                if (d.element(.@"table-header"))
                    try w.print(
                        \\
                        \\Exports from {s}:
                        \\ Ord Hint      RVA   Name
                        \\
                    , .{dll_name});

                const name_pointers = dir_slice[name_pointer_loc - dir_loc ..][0 .. export_dir.number_of_names * @sizeOf(u32)];
                const ords = dir_slice[ord_loc - dir_loc ..][0 .. export_dir.number_of_names * @sizeOf(u16)];
                const addrs = dir_slice[eat_loc - dir_loc ..][0 .. export_dir.number_of_entries * @sizeOf(u32)];
                const name_rva_to_offset = dir.virtual_address + @sizeOf(std.coff.ExportDirectoryTable);
                for (0..export_dir.number_of_names) |name_i| {
                    const name_rva = std.mem.readInt(u32, name_pointers[name_i * @sizeOf(u32) ..][0..@sizeOf(u32)], .little);
                    const name = std.mem.sliceTo(dir_slice[name_rva - name_rva_to_offset ..], 0);
                    if (!filterMatches(d.opts.symbol_filters, name))
                        continue;

                    const ord = std.mem.readInt(u16, ords[name_i * @sizeOf(u16) ..][0..@sizeOf(u16)], .little);
                    const addr = std.mem.readInt(u32, addrs[@as(u32, ord) * @sizeOf(u32) ..][0..@sizeOf(u32)], .little);

                    try w.print("{f} {f} ", .{
                        fmtIntField(d, @as(u16, @intCast(export_dir.ordinal_base + ord)), .{ .kind = .ord }),
                        fmtIntField(d, @as(u16, @intCast(name_i)), .{ .kind = .ord }),
                    });
                    const is_forwarder = addr >= dir.virtual_address and addr < dir_end_rva;
                    if (is_forwarder) {
                        try w.writeAll("forwards");
                    } else {
                        try w.print("{f}", .{fmtIntField(d, addr, .{ .kind = .rva })});
                    }

                    try w.print(" | {s}", .{name});
                    if (is_forwarder)
                        try w.print(" -> {s}", .{std.mem.sliceTo(dir_slice[addr - name_rva_to_offset ..], 0)});
                    try w.writeByte('\n');
                }
            }
        }

        if (d.opts.imports) imports: {
            if (try seekToDataDirectory(
                d,
                rva_index,
                sections.items,
                (image_info orelse {
                    try w.writeAll("COFF objects do not contain an import data directory");
                    break :imports;
                }).data_dirs,
                .IMPORT,
            )) |_| {
                const Entry = std.coff.ImportDirectoryEntry;
                var directory_entries: std.ArrayList(Entry) = .empty;
                defer directory_entries.deinit(gpa);
                while (true) {
                    const entry = r.takeStruct(Entry, .little) catch |err|
                        return d.failParse(
                            "unable to read import directory entry {x}: {t}",
                            .{ directory_entries.items.len, err },
                        );

                    if (std.mem.allEqual(u8, std.mem.asBytes(&entry), 0)) break;
                    (try directory_entries.addOne(gpa)).* = entry;
                }

                for (directory_entries.items) |entry| {
                    const name_section = sectionContainingRva(
                        rva_index,
                        sections.items,
                        entry.name_rva,
                    ) orelse
                        return d.failParse(
                            "import directory entry name rva 0x{x} was not found in any section",
                            .{entry.name_rva},
                        );

                    const name_loc = sections.items[name_section].rvaFileOffset(
                        entry.name_rva,
                    ) catch unreachable;
                    fr.seekTo(name_loc) catch |err|
                        return d.failParse(
                            "unable to seek to import directory entry name at 0x{x}: {t}",
                            .{ name_loc, err },
                        );

                    const dll_name = (try r.takeDelimiter(0)).?;

                    if (d.element(.@"header-name"))
                        try w.print("Import table entry for {s}:\n", .{dll_name});
                    try dumpHeader(d, Entry, &entry, struct {});

                    if (d.element(.@"table-header"))
                        try w.print(
                            \\
                            \\ Ord Hint   Name
                            \\
                        , .{});

                    const ilt_section = sectionContainingRva(
                        rva_index,
                        sections.items,
                        entry.import_lookup_table_rva,
                    ) orelse
                        return d.failParse(
                            "import directory entry ilt rva 0x{x} was not found in any section",
                            .{entry.import_lookup_table_rva},
                        );

                    const ilt_loc = sections.items[ilt_section].rvaFileOffset(
                        entry.import_lookup_table_rva,
                    ) catch unreachable;
                    fr.seekTo(ilt_loc) catch |err|
                        return d.failParse(
                            "unable to seek to import directory ilt at 0x{x}: {t}",
                            .{ ilt_loc, err },
                        );

                    switch (image_info.?.magic) {
                        _ => try w.writeAll("(unknown magic)"),
                        inline else => |m| {
                            const TableEntry = std.coff.ImportLookupTableEntry(m);
                            const null_entry: TableEntry = @bitCast(@as(@typeInfo(TableEntry).@"struct".backing_integer.?, 0));

                            var ilt_entries: std.ArrayList(TableEntry) = .empty;
                            defer ilt_entries.deinit(gpa);
                            while (true) {
                                const table_entry = r.takeStruct(TableEntry, .little) catch |err|
                                    return d.failParse(
                                        "unable to read ilt entry {s}:{x}: {t}",
                                        .{ dll_name, ilt_entries.items.len, err },
                                    );
                                if (table_entry == null_entry) break;
                                (try ilt_entries.addOne(gpa)).* = table_entry;
                            }

                            for (ilt_entries.items, 0..) |ilt_entry, ilt_entry_i| {
                                if (ilt_entry.is_ordinal) {
                                    try w.print("{x: >4}", .{ilt_entry.payload.ordinal.ordinal});
                                } else {
                                    const hint_section = sectionContainingRva(
                                        rva_index,
                                        sections.items,
                                        ilt_entry.payload.hint_name_rva,
                                    ) orelse
                                        return d.failParse(
                                            "import directory ilt entry 0x{x}'s hint rva 0x{x} was not found in any section",
                                            .{ ilt_entry_i, ilt_entry.payload.hint_name_rva },
                                        );

                                    const hint_loc = sections.items[hint_section].rvaFileOffset(
                                        ilt_entry.payload.hint_name_rva,
                                    ) catch unreachable;
                                    fr.seekTo(hint_loc) catch |err|
                                        return d.failParse(
                                            "unable to seek to ilt entry 0x{x}'s hint at 0x{x}: {t}",
                                            .{ ilt_entry_i, hint_loc, err },
                                        );

                                    const hint = r.takeInt(u16, .little) catch |err|
                                        return d.failParse(
                                            "unable to read import directory ilt entry 0x{x}'s hint: {t}",
                                            .{ ilt_entry_i, err },
                                        );

                                    const name = r.takeDelimiter(0) catch |err|
                                        return d.failParse(
                                            "unable to read import directory ilt entry 0x{x}'s name: {t}",
                                            .{ ilt_entry_i, err },
                                        );

                                    try w.print("     {x: >4} | {s}\n", .{ hint, name.? });
                                }
                            }
                            if (d.element(.newlines)) try w.writeByte('\n');
                        },
                    }
                }
            }
        }

        if (d.opts.tls) tls: {
            if (try seekToDataDirectory(
                d,
                rva_index,
                sections.items,
                (image_info orelse {
                    try w.writeAll("COFF objects do not contain a TLS data directory");
                    break :tls;
                }).data_dirs,
                .TLS,
            )) |_| {
                switch (image_info.?.magic) {
                    _ => try w.writeAll("(unknown magic)"),
                    inline else => |m| {
                        const TlsDirectoryEntry = std.coff.TlsDirectoryEntry(m);
                        const tls_entry = r.takeStruct(TlsDirectoryEntry, .little) catch |err|
                            return d.failParse("unable to read tls directory: {t}", .{err});

                        try w.writeAll("TLS Directory:\n");
                        try dumpHeader(d, TlsDirectoryEntry, &tls_entry, struct {});

                        try w.writeAll("               | ");
                        if (tls_entry.characteristics.alignment == .NONE) {
                            try w.writeAll("Alignment not specified");
                        } else {
                            try w.print(
                                "Alignment: {d}",
                                .{tls_entry.characteristics.alignment.toByteUnits().?},
                            );
                        }

                        try w.writeAll(
                            \\
                            \\
                            \\TLS Callbacks:
                            \\         Address
                            \\
                        );

                        const callbacks_rva: u32 = @intCast(tls_entry.callbacks_va - image_info.?.image_base);
                        const section_index = sectionContainingRva(
                            rva_index,
                            sections.items,
                            callbacks_rva,
                        ) orelse
                            return d.failParse(
                                "tls callbacks rva 0x{x} was not found in any section",
                                .{callbacks_rva},
                            );

                        const callbacks_loc = sections.items[section_index]
                            .rvaFileOffset(callbacks_rva) catch unreachable;

                        fr.seekTo(callbacks_loc) catch |err|
                            return d.failParse(
                                "unable to seek to tls callbacks array at offset 0x{x}: {t}",
                                .{ callbacks_loc, err },
                            );

                        while (true) {
                            const callback_va = r.takeInt(@FieldType(TlsDirectoryEntry, "callbacks_va"), .little) catch |err|
                                return d.failParse(
                                    "unable to read tls callbacks array: {t}",
                                    .{err},
                                );

                            try w.print("{f}\n", .{fmtIntField(d, callback_va, .{ .kind = .va })});
                            if (callback_va == 0) break;
                        }
                        if (d.element(.newlines)) try w.writeByte('\n');
                    },
                }
            }
        }
    }

    fn seekToDataDirectory(
        d: *const DumpContext,
        rva_index: []const u16,
        sections: []const Section,
        data_dirs: []const std.coff.ImageDataDirectory,
        entry: DIRECTORY_ENTRY,
    ) !?u16 {
        if (@backingInt(entry) < data_dirs.len) blk: {
            const rva = data_dirs[@backingInt(entry)].virtual_address;
            if (rva == 0) break :blk;

            const section_index = sectionContainingRva(rva_index, sections, rva) orelse
                return d.failParse(
                    "{t} directory rva 0x{x} was not found in any section",
                    .{ entry, rva },
                );

            const file_offset = sections[section_index].rvaFileOffset(rva) catch unreachable;
            d.fr.seekTo(file_offset) catch |err|
                return d.failParse(
                    "unable to seek to {t} directory at offset 0x{x}: {t}",
                    .{ entry, file_offset, err },
                );

            return section_index;
        }

        try d.w.print("{t} directory was not present in optional header\n", .{entry});
        return null;
    }

    fn sectionContainingRva(
        /// Indices into `sections` sorted by rva
        indices: []const u16,
        sections: []const Section,
        rva: u32,
    ) ?u16 {
        const Context = struct {
            rva: u32,
            sections: []const Section,

            fn order(ctx: @This(), section_index: u16) std.math.Order {
                const h = &ctx.sections[section_index].header;
                if (ctx.rva < h.virtual_address) return .lt;
                const end = h.virtual_address + h.size_of_raw_data;
                if (ctx.rva >= end) return .gt;
                return .eq;
            }
        };

        const indices_index = std.sort.binarySearch(u16, indices, Context{
            .rva = rva,
            .sections = sections,
        }, Context.order) orelse return null;
        return @intCast(indices[indices_index]);
    }

    fn headerName(raw: *const [8]u8, string_table: []const u8) ![]const u8 {
        return if (raw[0] == '/') name: {
            const name_offset = try std.fmt.parseUnsigned(u24, std.mem.sliceTo(raw[1..], 0), 10);
            if (name_offset >= string_table.len)
                return error.OutOfBounds;

            break :name std.mem.sliceTo(string_table[name_offset..], 0);
        } else std.mem.sliceTo(raw, 0);
    }

    fn fmtSectionNumber(section_number: std.coff.SectionNumber) std.fmt.Alt(std.coff.SectionNumber, sectionNumberString) {
        return .{ .data = section_number };
    }

    fn sectionNumberString(section_number: std.coff.SectionNumber, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try switch (section_number) {
            .UNDEFINED => w.writeAll("UNDEF"),
            .ABSOLUTE => w.writeAll("  ABS"),
            .DEBUG => w.writeAll("DEBUG"),
            else => |v| {
                const backing = @backingInt(v);
                const fmt = "{x: >5}";
                if (backing >= 0)
                    try w.print(fmt, .{@as(u15, @intCast(backing))})
                else
                    try w.print(fmt, .{backing});
            },
        };
    }

    const FormatIntField = struct {
        val: ?u64,
        width: ?usize,
        zero_fill: bool,
    };

    fn fmtIntField(
        d: *const DumpContext,
        val: anytype,
        params: struct {
            kind: ?FieldKind = null,
            width: union(enum) {
                fit_max,
                auto,
                explicit: usize,
            } = .fit_max,
            zero_fill: bool = false,
        },
    ) std.fmt.Alt(FormatIntField, intFieldString) {
        return .{
            .data = .{
                .val = if (d.redacted(params.kind)) null else val,
                .width = switch (params.width) {
                    .fit_max => @typeInfo(@TypeOf(val)).int.bits / 4,
                    .auto => null,
                    .explicit => |w| w,
                },
                .zero_fill = params.zero_fill,
            },
        };
    }

    fn intFieldString(field: FormatIntField, w: *std.Io.Writer) std.Io.Writer.Error!void {
        if (field.val) |val| {
            try w.printInt(val, 16, .lower, .{
                .width = field.width,
                .alignment = .right,
                .fill = if (field.zero_fill) '0' else ' ',
            });
        } else try w.splatByteAll('x', field.width orelse 1);
    }

    fn dumpFlags(w: *Io.Writer, comptime fmt: []const u8, comptime T: type, flags: *const T, cols: u32) !void {
        const s = @typeInfo(T).@"struct";
        inline for (s.field_names, s.field_types) |field_name, field_type| {
            if (field_type == bool and @field(flags, field_name)) {
                try w.splatByteAll(' ', cols);
                try w.print(fmt, .{field_name});
            }
        }
    }

    fn dumpArchiveHeader(d: *const DumpContext, header: *const ArchiveHeader, pos: u32) !void {
        if (d.element(.@"header-name"))
            try d.w.print("Archive member at offset 0x{x}: '{s}'\n", .{ pos, header.name });
        try dumpHeader(d, ArchiveHeader, header, struct {
            pub fn name(_: *const DumpContext, _: *const ArchiveHeader) !void {}
            pub fn file_mode(id: *const DumpContext, h: *const ArchiveHeader) !void {
                try id.w.print("{o: >16} file_mode\n", .{h.file_mode});
            }
        });
    }

    fn fieldKind(name: []const u8) ?FieldKind {
        if (std.mem.endsWith(u8, name, "_rva"))
            return .rva;
        if (std.mem.endsWith(u8, name, "_va") or
            std.mem.endsWith(u8, name, "_address") or
            std.mem.startsWith(u8, name, "pointer_"))
            return .va;
        if (std.mem.startsWith(u8, name, "number_") or
            std.mem.startsWith(u8, name, "size"))
            return .size;
        if (std.mem.startsWith(u8, name, "hint"))
            return .ord;
        return null;
    }

    fn dumpHeader(
        d: *const DumpContext,
        comptime T: type,
        header: *const T,
        Custom: type,
    ) !void {
        const s = @typeInfo(T).@"struct";
        inline for (s.field_names, s.field_types) |field_name, field_type| {
            const val = &@field(header, field_name);
            if (@hasDecl(Custom, field_name)) {
                try @field(Custom, field_name)(d, header);
            } else {
                switch (@typeInfo(field_type)) {
                    .int => try d.w.print("{f} {s}\n", .{ fmtIntField(d, val.*, .{
                        .kind = comptime fieldKind(field_name),
                        .width = .{ .explicit = 16 },
                    }), field_name }),
                    .@"enum" => try d.w.print("{x: >16} {s} ({t})\n", .{ val.*, field_name, val.* }),
                    .@"struct" => |s_field| {
                        switch (s_field.layout) {
                            .auto,
                            .@"extern",
                            => try dumpHeader(d, field_type, val, Custom),
                            .@"packed" => {
                                try d.w.print("{x: >16} {s}\n", .{ @as(s_field.backing_integer.?, @bitCast(val.*)), field_name });
                                try dumpFlags(d.w, "| {s}\n", field_type, val, 15);
                            },
                        }
                    },
                    else => unreachable,
                }
            }
        }
    }

    fn dumpVersionField(w: *Io.Writer, name: []const u8, major: anytype, minor: anytype) !void {
        try w.print("{d: >13}.{x:0<2} {s}\n", .{ major, minor, name });
    }

    fn dumpRvaField(d: *const DumpContext, name: []const u8, rva: u64, base: u64) !void {
        try d.w.print("{f} {s} ({f})\n", .{
            fmtIntField(d, rva, .{ .kind = .rva }),
            name,
            fmtIntField(d, base + rva, .{ .kind = .va }),
        });
    }
};

fn filterMatches(filters: []const []const u8, val: []const u8) bool {
    return for (filters) |filter| {
        if (std.mem.containsAtLeast(u8, val, 1, filter)) break true;
    } else filters.len == 0;
}

const usage =
    \\Usage: zig objdump [options] file
    \\
    \\Options:
    \\  -h, --help                         Print this help and exit
    \\  --all-headers                      Alias for --file-headers --linker-member=2 --member-headers --section-headers --relocs --symbols
    \\  --exports[=sort]                   Display exported symbols. 
    \\                                     In the case of COFF import libraries, displays the symbol list and import headers.
    \\                                     Specify =sort to optionally sort the import headers by symbol name.
    \\  --file-headers                     Display file-format specific headers
    \\  --imports                          Display imported symbols
    \\  --linker-member[=1|2|longnames]    (Coff) Display contents of the specified archive linker member (default 2)
    \\  --member-headers                   Display archive member headers
    \\  --elements=[e1],[e2],-[e3],...     Select which formatting elements are displayed. Intended for snapshot testing.
    \\      file-type                      File type summary
    \\      header-name                    Name that precedes a header block     
    \\      member-path                    Display full member paths. If removed, only basenames will be used.
    \\      newlines                       Newlines between output sections
    \\      table-header                   Table headers with column names
    \\      all                            (default) All of the above
    \\  --only-member=[name]               Only consider archive members names that contain [name]. Can be specified multiple times.
    \\  --only-section=[name]              Only consider section names that contain [name]. Can be specified multiple times.
    \\  --only-symbol=[name]               Only consider symbol names that contain [name]. Can be specified multiple times.
    \\  --redact=[kind]                    Redact the specified field kind. Intended for snapshot testing.
    \\      rva                            Relative virtual addresses
    \\      va                             Virtual addresses and file offsets
    \\      ord                            Symbol ordinals / hints
    \\      size                           Sizes and lengths
    \\      all                            All of the above
    \\  --relocs                           Display relocations
    \\  -s, --snapshot                     Alias for --redact=all --elements=-all
    \\  --section-headers                  Display section headers
    \\  --strings                          Display string tables
    \\  --symbols                          Display symbol tables
    \\  --tls                              Display TLS information
;

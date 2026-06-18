const Configuration = @This();

const std = @import("../std.zig");
const builtin = @import("builtin");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const max_u32 = std.math.maxInt(u32);
const native_endian = builtin.target.cpu.arch.endian();

string_bytes: []u8,
steps: []Step,
path_deps_base: []Path.Base,
path_deps_sub: []String,
unlazy_deps: []String,
system_integrations: []SystemIntegration,
available_options: []AvailableOption,
search_prefixes: []String,
extra: []u32,
default_step: Step.Index,
generated_files_len: u32,
poisoned: bool,

/// The field order here matches `Configuration` which documents the order in
/// the serialized format.
pub const Header = extern struct {
    string_bytes_len: u32,
    steps_len: u32,
    path_deps_len: u32,
    unlazy_deps_len: u32,
    system_integrations_len: u32,
    available_options_len: u32,
    search_prefixes_len: u32,
    extra_len: u32,

    default_step: Step.Index,
    /// There is not actually any data stored for this - it just provides a way
    /// for maker process to preallocate an array for these.
    generated_files_len: u32,
    flags: Flags,

    pub const Flags = packed struct(u32) {
        poisoned: bool,
        _: u31 = 0,
    };
};

pub const Wip = struct {
    gpa: Allocator,
    string_table: StringTable = .empty,
    /// De-duplicates an array inside `extra`.
    dedupe_table: DedupeTable = .empty,
    targets_table: TargetsTable = .empty,

    string_bytes: std.ArrayList(u8) = .empty,
    unlazy_deps: std.ArrayList(String) = .empty,
    system_integrations: std.ArrayList(SystemIntegration) = .empty,
    available_options: std.ArrayList(AvailableOption) = .empty,
    steps: std.ArrayList(Step) = .empty,
    path_deps: std.MultiArrayList(Path) = .empty,
    search_prefixes: std.ArrayList(String) = .empty,
    extra: std.ArrayList(u32) = .empty,
    next_generated_file_index: u32 = 0,
    cache_poison: bool = false,

    const DedupeTable = std.HashMapUnmanaged(ExtraSlice, void, ExtraSlice.Context, std.hash_map.default_max_load_percentage);
    const TargetsTable = std.HashMapUnmanaged(TargetQuery.Index, void, TargetsTableContext, std.hash_map.default_max_load_percentage);

    const ExtraSlice = struct {
        index: u32,
        len: u32,

        const Context = struct {
            extra: []const u32,

            pub fn eql(ctx: @This(), a: ExtraSlice, b: ExtraSlice) bool {
                const slice_a = ctx.extra[a.index..][0..a.len];
                const slice_b = ctx.extra[b.index..][0..b.len];
                return std.mem.eql(u32, slice_a, slice_b);
            }

            pub fn hash(ctx: @This(), key: ExtraSlice) u64 {
                const slice = ctx.extra[key.index..][0..key.len];
                return std.hash_map.hashString(@ptrCast(slice));
            }
        };
    };

    const TargetsTableContext = struct {
        extra: []const u32,

        pub fn eql(ctx: @This(), a: TargetQuery.Index, b: TargetQuery.Index) bool {
            const slice_a = a.extraSlice(ctx.extra);
            const slice_b = b.extraSlice(ctx.extra);
            return std.mem.eql(u32, slice_a, slice_b);
        }

        pub fn hash(ctx: @This(), key: TargetQuery.Index) u64 {
            const slice = key.extraSlice(ctx.extra);
            return std.hash_map.hashString(@ptrCast(slice));
        }
    };

    const StringTable = std.HashMapUnmanaged(String, void, StringTableContext, std.hash_map.default_max_load_percentage);
    const StringTableContext = struct {
        bytes: []const u8,

        pub fn eql(_: @This(), a: String, b: String) bool {
            return a == b;
        }

        pub fn hash(ctx: @This(), key: String) u64 {
            return std.hash_map.hashString(std.mem.sliceTo(ctx.bytes[@intFromEnum(key)..], 0));
        }
    };

    const StringTableIndexAdapter = struct {
        bytes: []const u8,

        pub fn eql(ctx: @This(), a: []const u8, b: String) bool {
            return std.mem.eql(u8, a, std.mem.sliceTo(ctx.bytes[@intFromEnum(b)..], 0));
        }

        pub fn hash(_: @This(), adapted_key: []const u8) u64 {
            assert(std.mem.indexOfScalar(u8, adapted_key, 0) == null);
            return std.hash_map.hashString(adapted_key);
        }
    };

    pub fn init(gpa: Allocator) Wip {
        return .{ .gpa = gpa };
    }

    pub fn deinit(wip: *Wip) void {
        const gpa = wip.gpa;
        wip.string_bytes.deinit(gpa);
        wip.unlazy_deps.deinit(gpa);
        wip.system_integrations.deinit(gpa);
        wip.available_options.deinit(gpa);
        wip.steps.deinit(gpa);
        wip.path_deps.deinit(gpa);
        wip.search_prefixes.deinit(gpa);
        wip.extra.deinit(gpa);
        wip.* = undefined;
    }

    pub const Static = struct {
        default_step: Step.Index,
        generated_files_len: u32,
        poisoned: bool,
    };

    pub fn write(wip: *Wip, w: *Io.Writer, static: Static) Io.Writer.Error!void {
        const header: Header = .{
            .string_bytes_len = @intCast(wip.string_bytes.items.len),
            .steps_len = @intCast(wip.steps.items.len),
            .path_deps_len = @intCast(wip.path_deps.len),
            .unlazy_deps_len = @intCast(wip.unlazy_deps.items.len),
            .system_integrations_len = @intCast(wip.system_integrations.items.len),
            .available_options_len = @intCast(wip.available_options.items.len),
            .search_prefixes_len = @intCast(wip.search_prefixes.items.len),
            .extra_len = @intCast(wip.extra.items.len),

            .default_step = static.default_step,
            .generated_files_len = static.generated_files_len,
            .flags = .{
                .poisoned = static.poisoned,
            },
        };
        var buffers = [_][]const u8{
            @ptrCast(&header),
            wip.string_bytes.items,
            @ptrCast(wip.steps.items),
            @ptrCast(wip.path_deps.items(.base)),
            @ptrCast(wip.path_deps.items(.sub)),
            @ptrCast(wip.unlazy_deps.items),
            @ptrCast(wip.system_integrations.items),
            @ptrCast(wip.available_options.items),
            @ptrCast(wip.search_prefixes.items),
            @ptrCast(wip.extra.items),
        };
        try w.writeVecAll(&buffers);
    }

    pub fn addString(wip: *Wip, bytes: []const u8) Allocator.Error!String {
        const gpa = wip.gpa;
        assert(std.mem.indexOfScalar(u8, bytes, 0) == null);
        const gop = try wip.string_table.getOrPutContextAdapted(
            gpa,
            @as([]const u8, bytes),
            @as(StringTableIndexAdapter, .{ .bytes = wip.string_bytes.items }),
            @as(StringTableContext, .{ .bytes = wip.string_bytes.items }),
        );
        if (gop.found_existing) return gop.key_ptr.*;

        try wip.string_bytes.ensureUnusedCapacity(gpa, bytes.len + 1);
        const new_off: String = @enumFromInt(wip.string_bytes.items.len);

        wip.string_bytes.appendSliceAssumeCapacity(bytes);
        wip.string_bytes.appendAssumeCapacity(0);

        gop.key_ptr.* = new_off;

        return new_off;
    }

    pub fn addOptionalString(wip: *Wip, bytes: ?[]const u8) Allocator.Error!OptionalString {
        return .init(try addString(wip, bytes orelse return .none));
    }

    pub fn addStringList(wip: *Wip, list: []const []const u8) Allocator.Error!StringList {
        // Increase size of extra to support the list. Add the string list
        // there. Then check for duplicate, reverting list if already found.
        const gpa = wip.gpa;
        const revert_index: u32 = @intCast(wip.extra.items.len);
        const added = try wip.extra.addManyAsSlice(gpa, list.len + 1);
        added[0] = @intCast(list.len);
        for (added[1..], list) |*d, s| d.* = @intFromEnum(try addString(wip, s));
        const gop = try wip.dedupe_table.getOrPutContext(gpa, .{
            .index = revert_index,
            .len = @intCast(added.len),
        }, @as(ExtraSlice.Context, .{ .extra = wip.extra.items }));

        if (gop.found_existing) {
            wip.extra.items.len = revert_index;
            return @enumFromInt(gop.key_ptr.index);
        }

        return @enumFromInt(revert_index);
    }

    pub fn addBytes(wip: *Wip, bytes: []const u8) Allocator.Error!Bytes {
        try wip.string_bytes.appendSlice(wip.gpa, bytes);
        return .{
            .index = @intCast(wip.string_bytes.items.len - bytes.len),
            .len = @intCast(bytes.len),
        };
    }

    pub fn addSemVer(wip: *Wip, sv: std.SemanticVersion) Allocator.Error!String {
        var buffer: [256]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&buffer);
        sv.format(&writer) catch return error.OutOfMemory;
        return addString(wip, writer.buffered());
    }

    pub fn addTargetQuery(wip: *Wip, q: *const std.Target.Query) !TargetQuery.OptionalIndex {
        if (q.isNative()) return .none;
        const gpa = wip.gpa;
        const cpu_name: ?String = switch (q.cpu_model) {
            .native, .baseline, .determined_by_arch_os => null,
            .explicit => |model| try wip.addString(model.name),
        };
        const os_version_min: TargetQuery.OsVersion = if (q.os_version_min) |ver| switch (ver) {
            .none => .none,
            .semver => |sem_ver| .{ .semver = try wip.addSemVer(sem_ver) },
            .windows => |win_ver| .{ .windows = win_ver },
        } else .default;
        const os_version_max: TargetQuery.OsVersion = if (q.os_version_max) |ver| switch (ver) {
            .none => .none,
            .semver => |sem_ver| .{ .semver = try wip.addSemVer(sem_ver) },
            .windows => |win_ver| .{ .windows = win_ver },
        } else .default;
        const glibc_version: ?String = if (q.glibc_version) |sem_ver| try wip.addSemVer(sem_ver) else null;
        const dynamic_linker: ?String = if (q.dynamic_linker) |*dl|
            if (dl.get()) |s| try wip.addString(s) else .empty
        else
            null;
        const cpu_features_add_empty = q.cpu_features_add.isEmpty();
        const cpu_features_sub_empty = q.cpu_features_sub.isEmpty();
        const result_index: TargetQuery.Index = try wip.addExtra(TargetQuery, .{
            .flags = .{
                .cpu_arch = .init(q.cpu_arch),
                .cpu_model = .init(q.cpu_model),
                .cpu_features_add = !cpu_features_add_empty,
                .cpu_features_sub = !cpu_features_sub_empty,
                .os_tag = .init(q.os_tag),
                .abi = .init(q.abi),
                .object_format = .init(q.ofmt),
                .os_version_min = os_version_min,
                .os_version_max = os_version_max,
                .glibc_version = glibc_version != null,
                .android_api_level = q.android_api_level != null,
                .dynamic_linker = dynamic_linker != null,
            },
            .cpu_features_add = .{ .value = if (cpu_features_add_empty) null else q.cpu_features_add },
            .cpu_features_sub = .{ .value = if (cpu_features_sub_empty) null else q.cpu_features_sub },
            .glibc_version = .{ .value = glibc_version },
            .android_api_level = .{ .value = q.android_api_level },
            .dynamic_linker = .{ .value = dynamic_linker },
            .cpu_name = .{ .value = cpu_name },
            .os_version_min = .{ .u = os_version_min },
            .os_version_max = .{ .u = os_version_max },
        });

        // Deduplicate.
        const gop = try wip.targets_table.getOrPutContext(gpa, result_index, @as(TargetsTableContext, .{
            .extra = wip.extra.items,
        }));
        if (gop.found_existing) {
            wip.extra.items.len = @intFromEnum(result_index);
            return .init(gop.key_ptr.*);
        } else {
            return .init(result_index);
        }
    }

    pub fn addTarget(wip: *Wip, t: std.Target) !TargetQuery.Index {
        const gpa = wip.gpa;
        const cpu_name: String = try wip.addString(t.cpu.model.name);

        const os_version_min: TargetQuery.OsVersion, const os_version_max: TargetQuery.OsVersion, const glibc_version: ?String, const android_api_level: ?u32 = switch (t.os.versionRange()) {
            .none => .{
                .none,
                .none,
                null,
                null,
            },
            .semver => |range| .{
                .{ .semver = try wip.addSemVer(range.min) },
                .{ .semver = try wip.addSemVer(range.max) },
                null,
                null,
            },
            .hurd => |hurd| .{
                .{ .semver = try wip.addSemVer(hurd.range.min) },
                .{ .semver = try wip.addSemVer(hurd.range.max) },
                try wip.addSemVer(hurd.glibc),
                null,
            },
            .linux => |linux| .{
                .{ .semver = try wip.addSemVer(linux.range.min) },
                .{ .semver = try wip.addSemVer(linux.range.max) },
                try wip.addSemVer(linux.glibc),
                linux.android,
            },
            .windows => |range| .{
                .{ .windows = range.min },
                .{ .windows = range.max },
                null,
                null,
            },
        };
        const dynamic_linker: ?String = if (t.dynamic_linker.get()) |dl| try wip.addString(dl) else null;
        const cpu_features_add_empty = t.cpu.features.isEmpty();
        const result_index = try wip.addExtra(TargetQuery, .{
            .flags = .{
                .cpu_arch = .init(t.cpu.arch),
                .cpu_model = .explicit,
                .cpu_features_add = !cpu_features_add_empty,
                .cpu_features_sub = false,
                .os_tag = .init(t.os.tag),
                .abi = .init(t.abi),
                .object_format = .init(t.ofmt),
                .os_version_min = os_version_min,
                .os_version_max = os_version_max,
                .glibc_version = glibc_version != null,
                .android_api_level = android_api_level != null,
                .dynamic_linker = dynamic_linker != null,
            },
            .cpu_features_add = .{ .value = if (cpu_features_add_empty) null else t.cpu.features },
            .cpu_features_sub = .{ .value = null },
            .glibc_version = .{ .value = glibc_version },
            .android_api_level = .{ .value = android_api_level },
            .dynamic_linker = .{ .value = dynamic_linker },
            .cpu_name = .{ .value = cpu_name },
            .os_version_min = .{ .u = os_version_min },
            .os_version_max = .{ .u = os_version_max },
        });

        // Deduplicate.
        const gop = try wip.targets_table.getOrPutContext(gpa, result_index, @as(TargetsTableContext, .{
            .extra = wip.extra.items,
        }));
        if (gop.found_existing) {
            wip.extra.items.len = @intFromEnum(result_index);
            return gop.key_ptr.*;
        } else {
            return result_index;
        }
    }

    pub fn addExtra(wip: *Wip, comptime T: type, v: T) Allocator.Error!T.Index {
        const extra_len = Storage.extraLen(v);
        try wip.extra.ensureUnusedCapacity(wip.gpa, extra_len);
        return addExtraReserved(wip, T, v);
    }

    pub fn addExtraErased(wip: *Wip, comptime T: type, v: T) Allocator.Error!u32 {
        const extra_len = Storage.extraLen(v);
        try wip.extra.ensureUnusedCapacity(wip.gpa, extra_len);
        return addExtraReservedErased(wip, T, v);
    }

    /// Same as `addExtra` but uses a hash map to possibly return an already
    /// existing index instead of appending to `extra`.
    pub fn addDeduped(wip: *Wip, comptime T: type, v: T) Allocator.Error!T.Index {
        const gpa = wip.gpa;
        const revert_index = wip.extra.items.len;
        const upper_bound_len = Storage.extraLen(v);
        try wip.extra.ensureUnusedCapacity(gpa, upper_bound_len);
        try wip.dedupe_table.ensureUnusedCapacityContext(gpa, 1, @as(ExtraSlice.Context, .{
            .extra = wip.extra.items,
        }));
        const new_index = addExtraReservedErased(wip, T, v);
        const len: u32 = @intCast(wip.extra.items.len - new_index);
        assert(len != 0);
        const gop = wip.dedupe_table.getOrPutAssumeCapacityContext(.{
            .index = new_index,
            .len = len,
        }, @as(ExtraSlice.Context, .{ .extra = wip.extra.items }));

        if (gop.found_existing) {
            wip.extra.items.len = revert_index;
            return @enumFromInt(gop.key_ptr.index);
        }

        return @enumFromInt(new_index);
    }

    pub fn addExtraReserved(wip: *Wip, comptime T: type, v: T) T.Index {
        return @enumFromInt(addExtraReservedErased(wip, T, v));
    }

    pub fn addExtraReservedErased(wip: *Wip, comptime T: type, v: T) u32 {
        const result: u32 = @intCast(wip.extra.items.len);
        wip.extra.items.len = Storage.setExtra(wip.extra.allocatedSlice(), result, v);
        return result;
    }

    fn addExtraOptionalStringAssumeCapacity(wip: *Wip, optional_string: ?String) void {
        const string = optional_string orelse return;
        wip.extra.appendAssumeCapacity(@intFromEnum(string));
    }

    pub fn addGeneratedFile(wip: *Wip) GeneratedFileIndex {
        defer wip.next_generated_file_index += 1;
        return @enumFromInt(wip.next_generated_file_index);
    }

    /// Returned slice expires upon next append to the configuration.
    pub fn stringSlice(wip: *const Wip, s: String) [:0]const u8 {
        const start_slice = wip.string_bytes.items[@intFromEnum(s)..];
        return start_slice[0..std.mem.indexOfScalar(u8, start_slice, 0).? :0];
    }
};

pub const SystemIntegration = extern struct {
    name: String,
    status: Status,

    pub const Status = enum(u32) {
        disabled = 0,
        enabled = 1,
    };
};

pub const AvailableOption = extern struct {
    name: String,
    description: String,
    type: Type,
    /// If the `type_id` is `enum` or `enum_list` this provides the list of enum options
    enum_options: OptionalStringList,

    pub const Type = enum(u8) {
        bool,
        int,
        float,
        @"enum",
        enum_list,
        string,
        list,
        build_id,
        lazy_path,
        lazy_path_list,
    };
};

pub const Step = extern struct {
    name: String,
    owner: Package.Index,
    deps: Deps.Index,
    max_rss: MaxRss,
    extended: Storage.Extended(Flags, union(Tag) {
        check_file: CheckFile,
        compile: Compile,
        config_header: ConfigHeader,
        fail: Fail,
        find_program: FindProgram,
        fmt: Fmt,
        install_artifact: InstallArtifact,
        install_dir: InstallDir,
        install_file: InstallFile,
        obj_copy: ObjCopy,
        options: Options,
        run: Run,
        top_level: TopLevel,
        translate_c: TranslateC,
        update_source_files: UpdateSourceFiles,
        write_file: WriteFile,
    }),

    /// Points into `steps`.
    pub const Index = enum(u32) {
        _,

        pub fn ptr(i: Index, c: *const Configuration) *const Step {
            return &c.steps[@intFromEnum(i)];
        }
    };

    /// Shared by all steps.
    pub const Flags = packed struct(u32) {
        tag: Tag,
        _: u27 = 0,
    };

    pub const Tag = enum(u5) {
        check_file,
        compile,
        config_header,
        fail,
        find_program,
        fmt,
        install_artifact,
        install_dir,
        install_file,
        obj_copy,
        options,
        run,
        top_level,
        translate_c,
        update_source_files,
        write_file,
    };

    pub const TopLevel = struct {
        flags: @This().Flags = .{},
        description: String,

        pub const Flags = packed struct(u32) {
            tag: Tag = .top_level,
            _: u27 = 0,
        };
    };

    /// The first dependency step index will be the compile step whose
    /// artifacts are being installed with this step.
    pub const InstallArtifact = struct {
        flags: @This().Flags,
        bin_dir: Storage.FlagOptional(.flags, .bin_dir, InstallDestDir),
        implib_dir: Storage.FlagOptional(.flags, .implib_dir, InstallDestDir),
        pdb_dir: Storage.FlagOptional(.flags, .pdb_dir, InstallDestDir),
        h_dir: Storage.FlagOptional(.flags, .h_dir, InstallDestDir),
        bin_sub_path: Storage.FlagOptional(.flags, .bin_sub_path, String),

        pub const Flags = packed struct(u32) {
            tag: Tag = .install_artifact,
            dylib_symlinks: bool,
            bin_dir: bool,
            implib_dir: bool,
            pdb_dir: bool,
            h_dir: bool,
            bin_sub_path: bool,
            _: u21 = 0,
        };
    };

    pub const Run = struct {
        flags: @This().Flags,
        flags2: Flags2,
        args: Storage.LengthPrefixedList(Arg.Index),
        cwd: Storage.FlagOptional(.flags, .cwd, LazyPath.Index),
        captured_stdout: Storage.FlagOptional(.flags, .captured_stdout, CapturedStream),
        captured_stderr: Storage.FlagOptional(.flags, .captured_stderr, CapturedStream),
        file_inputs: Storage.LengthPrefixedList(LazyPath.Index),
        stdio_limit: Storage.FlagOptional(.flags, .stdio_limit, u64),
        /// Always a compile step.
        producer: Storage.FlagOptional(.flags, .producer, Step.Index),
        /// First half is keys, second half is values.
        environ_map: Storage.FlagOptional(.flags, .environ_map, EnvironMap.Index),
        stdin: Storage.FlagUnion(.flags, .stdin, StdIn),
        expect_stderr_exact: Storage.FlagOptional(.flags2, .expect_stderr_exact, Bytes),
        expect_stdout_exact: Storage.FlagOptional(.flags2, .expect_stdout_exact, Bytes),
        expect_stderr_match: Storage.FlagLengthPrefixedList(.flags2, .expect_stderr_match, Bytes),
        expect_stdout_match: Storage.FlagLengthPrefixedList(.flags2, .expect_stdout_match, Bytes),
        expect_term_value: Storage.FlagOptional(.flags2, .expect_term, u32),

        pub const CapturedStream = extern struct {
            generated_file: GeneratedFileIndex,
            basename: String,
        };

        pub const Arg = struct {
            flags: @This().Flags,
            prefix: Storage.FlagOptional(.flags, .prefix, String),
            suffix: Storage.FlagOptional(.flags, .suffix, String),
            basename: Storage.FlagOptional(.flags, .basename, String),
            path: Storage.FlagOptional(.flags, .path, LazyPath.Index),
            /// Always a compile step.
            producer: Storage.FlagOptional(.flags, .producer, Step.Index),
            generated: Storage.FlagOptional(.flags, .generated, GeneratedFileIndex),

            pub const Flags = packed struct(u32) {
                tag: Arg.Tag,
                prefix: bool,
                suffix: bool,
                basename: bool,
                path: bool,
                producer: bool,
                generated: bool,
                dep_file: bool,
                _: u21 = 0,
            };

            pub const Tag = enum(u4) {
                artifact,
                /// `path` contains the file.
                path_file,
                path_directory,
                /// `prefix` contains the string.
                string,
                file_content,
                output_file,
                output_directory,
                passthru,
            };

            pub const Index = IndexType(@This());
        };

        pub const Color = enum(u4) {
            /// `CLICOLOR_FORCE` is set, and `NO_COLOR` is unset.
            enable,
            /// `NO_COLOR` is set, and `CLICOLOR_FORCE` is unset.
            disable,
            /// If the build runner is using color, equivalent to `.enable`. Otherwise, equivalent to `.disable`.
            inherit,
            /// If stderr is captured or checked, equivalent to `.disable`. Otherwise, equivalent to `.inherit`.
            auto,
            /// The build runner does not modify the `CLICOLOR_FORCE` or `NO_COLOR` environment variables.
            /// They are treated like normal variables, so can be controlled through `setEnvironmentVariable`.
            manual,
        };

        pub const StdIn = union(@This().Tag) {
            none: void,
            bytes: Bytes,
            lazy_path: LazyPath.Index,

            pub const Tag = enum(u2) { none, bytes, lazy_path };
        };
        pub const TrimWhitespace = enum(u2) { none, all, leading, trailing };
        pub const StdIo = enum(u2) { infer_from_args, inherit, check, zig_test };

        pub const ExpectTermStatus = enum(u2) { exited, signal, stopped, unknown };

        pub const Flags = packed struct(u32) {
            tag: Tag = .run,
            disable_zig_progress: bool,
            skip_foreign_checks: bool,
            failing_to_execute_foreign_is_an_error: bool,
            has_side_effects: bool,
            test_runner_mode: bool,
            color: Color,
            stdin: StdIn.Tag,
            stdio: StdIo,
            stdout_trim_whitespace: TrimWhitespace,
            stderr_trim_whitespace: TrimWhitespace,
            stdio_limit: bool,
            producer: bool,
            cwd: bool,
            captured_stdout: bool,
            captured_stderr: bool,
            environ_map: bool,
            _: u4 = 0,
        };

        pub const Flags2 = packed struct(u32) {
            expect_stderr_exact: bool,
            expect_stdout_exact: bool,
            expect_stderr_match: bool,
            expect_stdout_match: bool,
            expect_term: bool,
            expect_term_status: ExpectTermStatus,
            _: u25 = 0,
        };
    };

    pub const Compile = struct {
        flags: @This().Flags,
        flags2: Flags2,
        flags3: Flags3,
        flags4: Flags4,

        root_module: Module.Index,
        root_name: String,

        filters: Storage.FlagLengthPrefixedList(.flags, .filters_len, String),
        exec_cmd_args: Storage.FlagLengthPrefixedList(.flags, .exec_cmd_args_len, OptionalString),
        installed_headers: Storage.FlagLengthPrefixedList(.flags, .installed_headers_len, Storage.Extended(InstalledHeader.Flags, InstalledHeader)),
        force_undefined_symbols: Storage.FlagLengthPrefixedList(.flags, .force_undefined_symbols_len, String),
        expect_errors: Storage.FlagUnion(.flags4, .expect_errors, ExpectErrors),
        linker_script: Storage.FlagOptional(.flags4, .linker_script, LazyPath.Index),
        version_script: Storage.FlagOptional(.flags4, .version_script, LazyPath.Index),
        zig_lib_dir: Storage.FlagOptional(.flags3, .zig_lib_dir, LazyPath.Index),
        libc_file: Storage.FlagOptional(.flags4, .libc_file, LazyPath.Index),
        win32_manifest: Storage.FlagOptional(.flags3, .win32_manifest, LazyPath.Index),
        win32_module_definition: Storage.FlagOptional(.flags3, .win32_module_definition, LazyPath.Index),
        entitlements: Storage.FlagOptional(.flags4, .entitlements, LazyPath.Index),
        version: Storage.FlagOptional(.flags3, .version, String), // semantic version string
        entry: Storage.EnumOptional(.flags3, .entry, .symbol_name, String),
        install_name: Storage.FlagOptional(.flags4, .install_name, String),
        initial_memory: Storage.FlagOptional(.flags3, .initial_memory, u64),
        max_memory: Storage.FlagOptional(.flags3, .max_memory, u64),
        global_base: Storage.FlagOptional(.flags3, .global_base, u64),
        image_base: Storage.FlagOptional(.flags3, .image_base, u64),
        link_z_common_page_size: Storage.FlagOptional(.flags4, .link_z_common_page_size, u64),
        link_z_max_page_size: Storage.FlagOptional(.flags4, .link_z_max_page_size, u64),
        pagezero_size: Storage.FlagOptional(.flags4, .pagezero_size, u64),
        stack_size: Storage.FlagOptional(.flags4, .stack_size, u64),
        headerpad_size: Storage.FlagOptional(.flags4, .headerpad_size, u32),
        error_limit: Storage.FlagOptional(.flags4, .error_limit, u32),
        build_id: Storage.EnumOptional(.flags3, .build_id, .hexstring, String),
        test_runner: Storage.FlagUnion(.flags3, .test_runner, TestRunner),

        emit_directory: Storage.FlagOptional(.flags4, .emit_directory, GeneratedFileIndex),
        generated_docs: Storage.FlagOptional(.flags4, .generated_docs, GeneratedFileIndex),
        generated_asm: Storage.FlagOptional(.flags4, .generated_asm, GeneratedFileIndex),
        generated_bin: Storage.FlagOptional(.flags4, .generated_bin, GeneratedFileIndex),
        generated_pdb: Storage.FlagOptional(.flags4, .generated_pdb, GeneratedFileIndex),
        generated_implib: Storage.FlagOptional(.flags4, .generated_implib, GeneratedFileIndex),
        generated_llvm_bc: Storage.FlagOptional(.flags4, .generated_llvm_bc, GeneratedFileIndex),
        generated_llvm_ir: Storage.FlagOptional(.flags4, .generated_llvm_ir, GeneratedFileIndex),
        generated_h: Storage.FlagOptional(.flags4, .generated_h, GeneratedFileIndex),

        pub const InstalledHeader = union(@This().Tag) {
            file: File,
            directory: Directory,

            pub const Flags = packed struct(u32) {
                tag: InstalledHeader.Tag,
                _: u24 = 0,
            };

            pub const Tag = enum(u8) {
                file,
                directory,
            };

            pub const File = struct {
                flags: @This().Flags = .{},
                source: LazyPath.Index,
                dest_sub_path: String,

                pub const Flags = packed struct(u32) {
                    tag: InstalledHeader.Tag = .file,
                    _: u24 = 0,
                };
            };

            pub const Directory = struct {
                flags: @This().Flags,
                source: LazyPath.Index,
                dest_sub_path: String,
                exclude_extensions: Storage.FlagLengthPrefixedList(.flags, .exclude_extensions, String),
                include_extensions: Storage.FlagLengthPrefixedList(.flags, .include_extensions, String),

                pub const Flags = packed struct(u32) {
                    tag: InstalledHeader.Tag = .directory,
                    exclude_extensions: bool,
                    include_extensions: bool,
                    _: u22 = 0,
                };
            };
        };
        pub const ExpectErrors = union(@This().Tag) {
            pub const Tag = enum(u3) { contains, exact, starts_with, stderr_contains, none };

            contains: String,
            exact: Storage.LengthPrefixedList(String),
            starts_with: String,
            stderr_contains: String,
            none: void,
        };
        pub const TestRunner = union(@This().Tag) {
            pub const Tag = enum(u2) { default, simple, server };

            default: void,
            simple: LazyPath.Index,
            server: LazyPath.Index,
        };
        pub const Entry = enum(u2) { default, disabled, enabled, symbol_name };

        pub const Lto = enum(u2) {
            none,
            full,
            thin,
            default,

            pub fn init(lto: ?std.zig.LtoMode) Lto {
                return switch (lto orelse return .default) {
                    .none => .none,
                    .full => .full,
                    .thin => .thin,
                };
            }
        };

        pub const BuildId = enum(u3) {
            none,
            fast,
            uuid,
            sha1,
            md5,
            hexstring,
            default,

            pub fn init(build_id: ?std.zig.BuildId) BuildId {
                return switch (build_id orelse return .default) {
                    .none => .none,
                    .fast => .fast,
                    .uuid => .uuid,
                    .sha1 => .sha1,
                    .md5 => .md5,
                    .hexstring => .hexstring,
                };
            }

            pub fn unwrap(this: @This(), hexstring: ?String, c: *const Configuration) ?std.zig.BuildId {
                if (hexstring) |h| {
                    assert(this == .hexstring);
                    return .initHexString(h.slice(c));
                }
                return switch (this) {
                    .none => .none,
                    .fast => .fast,
                    .uuid => .uuid,
                    .sha1 => .sha1,
                    .md5 => .md5,
                    .hexstring => unreachable,
                    .default => null,
                };
            }
        };
        pub const WasiExecModel = enum(u2) {
            default,
            command,
            reactor,

            pub fn init(wasi_exec_model: ?std.builtin.WasiExecModel) WasiExecModel {
                return switch (wasi_exec_model orelse return .default) {
                    .command => .command,
                    .reactor => .reactor,
                };
            }
        };
        pub const Linkage = enum(u2) {
            static,
            dynamic,
            default,

            pub fn init(link_mode: ?std.builtin.LinkMode) Linkage {
                return switch (link_mode orelse return .default) {
                    .static => .static,
                    .dynamic => .dynamic,
                };
            }

            pub fn unwrap(this: @This()) ?std.builtin.LinkMode {
                return switch (this) {
                    .static => .static,
                    .dynamic => .dynamic,
                    .default => null,
                };
            }
        };
        pub const Kind = enum(u3) {
            exe,
            lib,
            obj,
            @"test",
            test_obj,

            pub fn isTest(kind: Kind) bool {
                return switch (kind) {
                    .exe, .lib, .obj => false,
                    .@"test", .test_obj => true,
                };
            }

            pub fn toOutputMode(kind: Kind) std.builtin.OutputMode {
                return switch (kind) {
                    .exe, .@"test" => .Exe,
                    .lib => .Lib,
                    .obj, .test_obj => .Obj,
                };
            }
        };
        pub const Subsystem = enum(u4) {
            console,
            windows,
            posix,
            native,
            efi_application,
            efi_boot_service_driver,
            efi_rom,
            efi_runtime_driver,
            default,

            pub fn init(subsystem: ?std.zig.Subsystem) Subsystem {
                return switch (subsystem orelse return .default) {
                    .console => .console,
                    .windows => .windows,
                    .posix => .posix,
                    .native => .native,
                    .efi_application => .efi_application,
                    .efi_boot_service_driver => .efi_boot_service_driver,
                    .efi_rom => .efi_rom,
                    .efi_runtime_driver => .efi_runtime_driver,
                };
            }
        };

        pub const Flags = packed struct(u32) {
            tag: Tag = .compile,

            filters_len: bool,
            exec_cmd_args_len: bool,
            installed_headers_len: bool,
            force_undefined_symbols_len: bool,

            verbose_link: bool,
            verbose_cc: bool,
            rdynamic: bool,
            import_memory: bool,
            export_memory: bool,
            import_symbols: bool,
            import_table: bool,
            export_table: bool,
            shared_memory: bool,
            link_eh_frame_hdr: bool,
            link_emit_relocs: bool,
            link_function_sections: bool,
            link_data_sections: bool,
            linker_dynamicbase: bool,
            link_z_notext: bool,
            link_z_relro: bool,
            link_z_lazy: bool,
            link_z_defs: bool,
            headerpad_max_install_names: bool,
            dead_strip_dylibs: bool,
            force_load_objc: bool,
            discard_local_symbols: bool,
            mingw_unicode_entry_point: bool,
        };

        pub const Flags2 = packed struct(u32) {
            pie: DefaultingBool,
            formatted_panics: DefaultingBool,
            bundle_compiler_rt: DefaultingBool,
            bundle_ubsan_rt: DefaultingBool,
            each_lib_rpath: DefaultingBool,
            link_gc_sections: DefaultingBool,
            linker_allow_shlib_undefined: DefaultingBool,
            linker_allow_undefined_version: DefaultingBool,
            linker_enable_new_dtags: DefaultingBool,
            dll_export_fns: DefaultingBool,
            use_llvm: DefaultingBool,
            use_lld: DefaultingBool,
            use_new_linker: DefaultingBool,
            allow_so_scripts: DefaultingBool,
            sanitize_coverage_trace_pc_guard: DefaultingBool,
            linkage: Linkage,
        };

        pub const Flags3 = packed struct(u32) {
            is_linking_libc: bool,
            is_linking_libcpp: bool,
            version: bool,
            initial_memory: bool,
            max_memory: bool,
            kind: Kind,
            compress_debug_sections: std.zig.CompressDebugSections,
            global_base: bool,
            test_runner: TestRunner.Tag,
            wasi_exec_model: WasiExecModel,
            win32_manifest: bool,
            win32_module_definition: bool,
            zig_lib_dir: bool,
            rc_includes: std.zig.RcIncludes,
            image_base: bool,
            build_id: BuildId,
            entry: Entry,
            lto: Lto,
            subsystem: Subsystem,
        };

        pub const Flags4 = packed struct(u32) {
            libc_file: bool,
            link_z_common_page_size: bool,
            link_z_max_page_size: bool,
            pagezero_size: bool,
            stack_size: bool,
            headerpad_size: bool,
            error_limit: bool,
            install_name: bool,
            entitlements: bool,
            expect_errors: ExpectErrors.Tag,
            linker_script: bool,
            version_script: bool,
            emit_directory: bool,
            generated_docs: bool,
            generated_asm: bool,
            generated_bin: bool,
            generated_pdb: bool,
            generated_implib: bool,
            generated_llvm_bc: bool,
            generated_llvm_ir: bool,
            generated_h: bool,
            incremental: DefaultingBool,
            _: u7 = 0,
        };

        pub fn isDynamicLibrary(compile: *const Compile) bool {
            return compile.flags3.kind == .lib and compile.flags2.linkage == .dynamic;
        }

        pub fn isStaticLibrary(compile: *const Compile) bool {
            return compile.flags3.kind == .lib and compile.flags2.linkage != .dynamic;
        }

        pub fn producesImplib(compile: *const Compile, c: *const Configuration) bool {
            return isDll(compile, c);
        }

        pub fn isDll(compile: *const Compile, c: *const Configuration) bool {
            return isDynamicLibrary(compile) and rootModuleTarget(compile, c).flags.os_tag == .windows;
        }

        pub fn rootModuleTarget(compile: *const Compile, c: *const Configuration) TargetQuery {
            return compile.root_module.get(c).resolved_target.get(c).?.result.get(c);
        }
    };

    pub const CheckFile = struct {
        flags: @This().Flags,
        file: LazyPath.Index,
        expected_exact: Storage.FlagOptional(.flags, .expected_exact, Bytes),
        expected_matches: Storage.FlagLengthPrefixedList(.flags, .expected_matches, Bytes),
        max_bytes: Storage.FlagOptional(.flags, .max_bytes, u32),

        pub const Flags = packed struct(u32) {
            tag: Tag = .check_file,
            expected_exact: bool,
            expected_matches: bool,
            max_bytes: bool,
            _: u24 = 0,
        };
    };

    pub const ConfigHeader = struct {
        flags: @This().Flags,
        template_file: Storage.FlagOptional(.flags, .template_file, LazyPath.Index),
        generated_dir: GeneratedFileIndex,
        input_size_limit: Storage.FlagOptional(.flags, .input_size_limit, u64),
        include_path: String,
        include_guard: Storage.FlagOptional(.flags, .include_guard, String),
        values: Storage.LengthPrefixedList(Value.Pair),

        pub const Style = enum(u3) {
            autoconf_undef,
            autoconf_at,
            cmake,
            blank,
            nasm,

            pub fn init(s: std.Build.Step.ConfigHeader.Style) Style {
                return switch (s) {
                    .autoconf_undef => .autoconf_undef,
                    .autoconf_at => .autoconf_at,
                    .cmake => .cmake,
                    .blank => .blank,
                    .nasm => .nasm,
                };
            }
        };

        pub const Value = struct {
            flags: @This().Flags,
            i64: Storage.EnumOptional(.flags, .tag, .i64, i64),
            u64: Storage.EnumOptional(.flags, .tag, .u64, u64),
            ident: Storage.EnumOptional(.flags, .tag, .ident, String),
            string: Storage.EnumOptional(.flags, .tag, .string, String),

            pub const Flags = packed struct(u32) {
                tag: Value.Tag,
                small: u29,
            };

            pub const Tag = enum(u3) {
                ident,
                string,
                small_unsigned,
                small_signed,
                i64,
                u64,
            };

            pub const Pair = extern struct {
                key: String,
                index: Value.Index,
            };

            pub const Index = enum(u32) {
                int_0 = max_u32 - 5,
                int_1 = max_u32 - 4,
                bool_false = max_u32 - 3,
                bool_true = max_u32 - 2,
                undef = max_u32 - 1,
                defined = max_u32,
                _,

                pub fn unpack(this: @This(), c: *const Configuration) Unpacked {
                    return switch (this) {
                        .int_0 => .{ .u64 = 0 },
                        .int_1 => .{ .u64 = 1 },
                        .bool_false => .{ .bool = false },
                        .bool_true => .{ .bool = true },
                        .undef => .undef,
                        .defined => .defined,
                        _ => {
                            const value = extraData(c, Value, @intFromEnum(this));
                            return switch (value.flags.tag) {
                                .ident => .{ .ident = value.ident.value.?.slice(c) },
                                .string => .{ .string = value.string.value.?.slice(c) },
                                .small_unsigned => .{ .u64 = value.flags.small },
                                .small_signed => .{ .i64 = @as(i29, @bitCast(value.flags.small)) },
                                .i64 => .{ .i64 = value.i64.value.? },
                                .u64 => .{ .u64 = value.u64.value.? },
                            };
                        },
                    };
                }
            };

            pub const Unpacked = union(enum) {
                bool: bool,
                undef,
                defined,
                i64: i64,
                u64: u64,
                ident: []const u8,
                string: []const u8,
            };

            pub fn initSigned(x: i64) @This() {
                return switch (x) {
                    0 => unreachable, // should have been an Index
                    1 => unreachable, // should have been an Index
                    2...std.math.maxInt(u29) => .{
                        .flags = .{
                            .tag = .small_unsigned,
                            .small = @intCast(x),
                        },
                        .i64 = .{ .value = null },
                        .u64 = .{ .value = null },
                        .ident = .{ .value = null },
                        .string = .{ .value = null },
                    },
                    std.math.minInt(i29)...-1 => .{
                        .flags = .{
                            .tag = .small_signed,
                            .small = @bitCast(@as(i29, @intCast(x))),
                        },
                        .i64 = .{ .value = null },
                        .u64 = .{ .value = null },
                        .ident = .{ .value = null },
                        .string = .{ .value = null },
                    },
                    else => .{
                        .flags = .{
                            .tag = .i64,
                            .small = 0,
                        },
                        .i64 = .{ .value = x },
                        .u64 = .{ .value = null },
                        .ident = .{ .value = null },
                        .string = .{ .value = null },
                    },
                };
            }
        };

        pub const Flags = packed struct(u32) {
            tag: Tag = .config_header,
            template_file: bool,
            style: Style,
            input_size_limit: bool,
            include_guard: bool,
            _: u21 = 0,
        };
    };

    pub const Fail = struct {
        flags: @This().Flags = .{},
        msg: String,

        pub const Flags = packed struct(u32) {
            tag: Tag = .fail,
            _: u27 = 0,
        };
    };

    pub const Fmt = struct {
        flags: @This().Flags,
        paths: Storage.FlagLengthPrefixedList(.flags, .paths, LazyPath.Index),
        exclude_paths: Storage.FlagLengthPrefixedList(.flags, .exclude_paths, LazyPath.Index),

        pub const Flags = packed struct(u32) {
            tag: Tag = .fmt,
            paths: bool,
            exclude_paths: bool,
            check: bool,
            _: u24 = 0,
        };
    };

    pub const FindProgram = struct {
        flags: @This().Flags = .{},
        names: StringList,
        found_path: GeneratedFileIndex,

        pub const Flags = packed struct(u32) {
            tag: Tag = .find_program,
            _: u27 = 0,
        };
    };

    pub const InstallDir = struct {
        flags: @This().Flags,
        source_dir: LazyPath.Index,
        dest_dir: InstallDestDir,
        dest_sub_path: Storage.FlagOptional(.flags, .dest_sub_path, String),
        exclude_extensions: Storage.FlagLengthPrefixedList(.flags, .exclude_extensions, String),
        include_extensions: Storage.FlagLengthPrefixedList(.flags, .include_extensions, String),
        blank_extensions: Storage.FlagLengthPrefixedList(.flags, .blank_extensions, String),

        pub const Flags = packed struct(u32) {
            tag: Tag = .install_dir,
            dest_sub_path: bool,
            exclude_extensions: bool,
            include_extensions: bool,
            include_extensions_active: bool,
            blank_extensions: bool,
            _: u22 = 0,
        };
    };

    pub const InstallFile = struct {
        flags: @This().Flags = .{},
        source: LazyPath.Index,
        dest_dir: InstallDestDir,
        dest_sub_path: String,

        pub const Flags = packed struct(u32) {
            tag: Tag = .install_file,
            _: u27 = 0,
        };
    };

    pub const ObjCopy = struct {
        flags: @This().Flags,
        input_file: LazyPath.Index,
        output_file: GeneratedFileIndex,
        basename: Storage.FlagOptional(.flags, .basename, String),
        debug_file: Storage.FlagOptional(.flags, .debug_file, GeneratedFileIndex),
        debug_basename: Storage.FlagOptional(.flags, .debug_basename, String),
        only_section: Storage.FlagOptional(.flags, .only_section, String),
        pad_to: Storage.FlagOptional(.flags, .pad_to, u64),
        add_section: Storage.FlagLengthPrefixedList(.flags, .add_section, AddSection),
        update_section: Storage.FlagLengthPrefixedList(.flags, .update_section, UpdateSection),

        pub const Format = enum(u2) {
            binary,
            hex,
            elf,
            default,

            pub fn init(f: ?std.Build.Step.ObjCopy.Format) @This() {
                return switch (f orelse return .default) {
                    .binary => .binary,
                    .hex => .hex,
                    .elf => .elf,
                };
            }
        };

        pub const Strip = enum(u2) {
            none,
            debug,
            debug_and_symbols,
        };

        pub const AddSection = extern struct {
            section_name: String,
            file_path: LazyPath.Index,
        };

        pub const UpdateSection = extern struct {
            section_name: String,
            flags: @This().Flags,

            pub const Flags = packed struct(u32) {
                section_flags: SectionFlags,
                alignment: Alignment,
                _: u17 = 0,
            };
        };

        pub const SectionFlags = packed struct(u9) {
            /// add SHF_ALLOC
            alloc: bool = false,
            /// if section is SHT_NOBITS, set SHT_PROGBITS, otherwise do nothing
            contents: bool = false,
            /// if section is SHT_NOBITS, set SHT_PROGBITS, otherwise do nothing (same as contents)
            load: bool = false,
            /// readonly: clear default SHF_WRITE flag
            readonly: bool = false,
            /// add SHF_EXECINSTR
            code: bool = false,
            /// add SHF_EXCLUDE
            exclude: bool = false,
            /// add SHF_X86_64_LARGE. Fatal error if target is not x86_64
            large: bool = false,
            /// add SHF_MERGE
            merge: bool = false,
            /// add SHF_STRINGS
            strings: bool = false,

            pub const default: @This() = .{};
        };

        pub const Flags = packed struct(u32) {
            tag: Tag = .obj_copy,
            basename: bool,
            debug_file: bool,
            debug_basename: bool,
            format: Format,
            strip: Strip,
            compress_debug: bool,
            only_section: bool,
            pad_to: bool,
            add_section: bool,
            update_section: bool,
            _: u15 = 0,
        };
    };

    pub const Options = struct {
        flags: @This().Flags,
        generated_file: GeneratedFileIndex,
        contents: Bytes,
        args: Storage.FlagLengthPrefixedList(.flags, .args, Arg),

        pub const Arg = extern struct {
            name: String,
            path: LazyPath.Index,
        };

        pub const Flags = packed struct(u32) {
            tag: Tag = .options,
            args: bool,
            _: u26 = 0,
        };
    };

    pub const TranslateC = struct {
        flags: @This().Flags,
        src_path: LazyPath.Index,
        output_file: GeneratedFileIndex,
        include_dirs: Storage.UnionList(.flags, .include_dirs, Module.IncludeDir),
        system_libs: Storage.FlagLengthPrefixedList(.flags, .system_libs, SystemLib.Index),
        c_macros: Storage.FlagLengthPrefixedList(.flags, .c_macros, String),
        target: ResolvedTarget.OptionalIndex,

        pub const Flags = packed struct(u32) {
            tag: Tag = .translate_c,
            include_dirs: bool,
            system_libs: bool,
            c_macros: bool,
            link_libc: bool,
            optimize: Module.Optimize,
            _: u20 = 0,
        };
    };

    pub const UpdateSourceFiles = struct {
        flags: @This().Flags,
        embeds: Storage.FlagLengthPrefixedList(.flags, .embeds, Embed),
        copies: Storage.FlagLengthPrefixedList(.flags, .copies, Copy),

        pub const Embed = WriteFile.Embed;
        pub const Copy = WriteFile.Copy;

        pub const Flags = packed struct(u32) {
            tag: Tag = .update_source_files,
            embeds: bool,
            copies: bool,
            _: u25 = 0,
        };
    };

    pub const WriteFile = struct {
        flags: @This().Flags,
        generated_directory: GeneratedFileIndex,
        embeds: Storage.FlagLengthPrefixedList(.flags, .embeds, Embed),
        copies: Storage.FlagLengthPrefixedList(.flags, .copies, Copy),
        directories: Storage.FlagLengthPrefixedList(.flags, .directories, Directory),
        mutate_path: Storage.EnumOptional(.flags, .mode, .mutate, LazyPath.Index),

        pub const Embed = extern struct {
            sub_path: String,
            contents: Bytes,
        };

        pub const Copy = extern struct {
            sub_path: String,
            src_file: LazyPath.Index,
        };

        pub const Directory = extern struct {
            sub_path: String,
            src_path: LazyPath.Index,
            exclude_extensions: OptionalStringList,
            include_extensions: OptionalStringList,
        };

        pub const Mode = enum(u2) {
            whole_cached,
            tmp,
            mutate,
        };

        pub const Flags = packed struct(u32) {
            tag: Tag = .write_file,
            embeds: bool,
            copies: bool,
            directories: bool,
            mode: Mode,
            _: u22 = 0,
        };
    };

    pub fn flags(s: *const Step, c: *const Configuration) Flags {
        return @bitCast(c.extra[@intFromEnum(s.extended)]);
    }
};

pub const MaxRss = enum(u32) {
    none = 0,
    _,

    pub fn toBytes(mr: MaxRss) u64 {
        const x: usize = @intFromEnum(mr);
        return x << 8;
    }

    pub fn fromBytes(bytes: u64) MaxRss {
        return @enumFromInt(bytes >> 8);
    }
};

pub const LazyPath = union(@This().Tag) {
    source_path: SourcePath,
    relative: Relative,
    generated: Generated,

    pub const Tag = enum(u8) {
        /// A source file path relative to build root.
        source_path,
        /// Relative to the directory indicated in flags.
        relative,
        /// Path is available only after it is populated by its owning step.
        generated,
    };

    pub const Flags = packed struct(u32) {
        tag: Tag,
        _: u24 = 0,
    };

    /// An index into `extra`.
    pub const Index = enum(u32) {
        _,

        pub fn get(this: @This(), c: *const Configuration) LazyPath {
            return extraData(c, LazyPath, @intFromEnum(this));
        }
    };

    /// An index into `extra`, or `null`.
    pub const OptionalIndex = enum(u32) {
        none = max_u32,
        _,

        pub fn unwrap(this: @This()) ?Index {
            return switch (this) {
                .none => null,
                else => @enumFromInt(@intFromEnum(this)),
            };
        }
    };

    pub const SourcePath = struct {
        flags: @This().Flags = .{},
        owner: Package.Index,
        sub_path: String,

        pub const Flags = packed struct(u32) {
            tag: Tag = .source_path,
            _: u24 = 0,
        };
    };

    pub const Generated = struct {
        flags: @This().Flags = .{},
        index: GeneratedFileIndex,
        /// Applied after `up`.
        sub_path: String = .empty,

        pub const Flags = packed struct(u32) {
            tag: Tag = .generated,
            /// The number of parent directories to go up.
            /// 0 means the generated file itself.
            /// 1 means the directory of the generated file.
            /// 2 means the parent of that directory, and so on.
            up: u24 = 0,
        };
    };

    pub const Relative = struct {
        flags: @This().Flags,
        sub_path: String,

        pub const Flags = packed struct(u32) {
            tag: Tag = .relative,
            base: Path.Base,
            _: u16 = 0,
        };
    };
};

pub const GeneratedFileIndex = enum(u32) {
    _,
};

pub const OptionalGeneratedFileIndex = enum(u32) {
    none = max_u32,
    _,

    pub fn init(i: ?GeneratedFileIndex) OptionalGeneratedFileIndex {
        return @enumFromInt(@intFromEnum(i orelse return .none));
    }

    pub fn unwrap(this: @This()) ?GeneratedFileIndex {
        return switch (this) {
            .none => null,
            else => @enumFromInt(@intFromEnum(this)),
        };
    }
};

pub const Package = struct {
    dep_prefix: String,
    hash: String,
    root_path: String,

    pub const Index = enum(u32) {
        root = max_u32,
        _,

        /// Returns `null` for root package.
        pub fn get(i: @This(), c: *const Configuration) ?Package {
            if (i == .root) return null;
            return extraData(c, Package, @intFromEnum(i));
        }

        pub fn depPrefixSlice(i: @This(), c: *const Configuration) [:0]const u8 {
            const package = get(i, c) orelse return "";
            return package.dep_prefix.slice(c);
        }
    };
};

pub const Module = struct {
    flags: Flags,
    flags2: Flags2,
    import_table: ImportTable.Index,
    owner: Package.Index,
    root_source_file: LazyPath.OptionalIndex,
    resolved_target: ResolvedTarget.OptionalIndex,
    c_macros: Storage.FlagLengthPrefixedList(.flags, .c_macros, String),
    lib_paths: Storage.FlagLengthPrefixedList(.flags, .lib_paths, LazyPath.Index),
    export_symbol_names: Storage.FlagLengthPrefixedList(.flags, .export_symbol_names, String),
    include_dirs: Storage.UnionList(.flags, .include_dirs, IncludeDir),
    rpaths: Storage.UnionList(.flags, .rpaths, RPath),
    link_objects: Storage.UnionList(.flags, .link_objects, LinkObject),
    frameworks: Storage.FlagLengthPrefixedList(.flags, .frameworks, Framework),

    pub const Optimize = enum(u3) {
        debug,
        safe,
        fast,
        small,
        default,

        pub fn init(o: ?std.builtin.OptimizeMode) Optimize {
            return switch (o orelse return .default) {
                .Debug => .debug,
                .ReleaseSafe => .safe,
                .ReleaseFast => .fast,
                .ReleaseSmall => .small,
            };
        }
    };

    pub const UnwindTables = enum(u2) {
        none,
        sync,
        async,
        default,

        pub fn init(ut: ?std.builtin.UnwindTables) UnwindTables {
            return switch (ut orelse return .default) {
                .none => .none,
                .sync => .sync,
                .async => .async,
            };
        }
    };

    pub const SanitizeC = enum(u2) {
        off,
        trap,
        full,
        default,

        pub fn init(sc: ?std.zig.SanitizeC) SanitizeC {
            return switch (sc orelse return .default) {
                .off => .off,
                .trap => .trap,
                .full => .full,
            };
        }
    };

    pub const DwarfFormat = enum(u2) {
        @"32",
        @"64",
        default,

        pub fn init(df: ?std.dwarf.Format) DwarfFormat {
            return switch (df orelse return .default) {
                .@"32" => .@"32",
                .@"64" => .@"64",
            };
        }
    };

    pub const Index = enum(u32) {
        _,

        pub fn get(this: @This(), c: *const Configuration) Module {
            return extraData(c, Module, @intFromEnum(this));
        }
    };

    pub const Flags = packed struct(u32) {
        optimize: Optimize,
        strip: DefaultingBool,
        unwind_tables: UnwindTables,
        dwarf_format: DwarfFormat,
        single_threaded: DefaultingBool,
        stack_protector: DefaultingBool,
        stack_check: DefaultingBool,
        sanitize_c: SanitizeC,
        sanitize_thread: DefaultingBool,
        fuzz: DefaultingBool,
        code_model: std.builtin.CodeModel,
        c_macros: bool,
        include_dirs: bool,
        lib_paths: bool,
        rpaths: bool,
        frameworks: bool,
        link_objects: bool,
        export_symbol_names: bool,
    };

    pub const Flags2 = packed struct(u32) {
        valgrind: DefaultingBool,
        pic: DefaultingBool,
        red_zone: DefaultingBool,
        omit_frame_pointer: DefaultingBool,
        error_tracing: DefaultingBool,
        link_libc: DefaultingBool,
        link_libcpp: DefaultingBool,
        no_builtin: DefaultingBool,
        _: u16 = 0,
    };

    pub const IncludeDir = union(enum(u3)) {
        path: LazyPath.Index,
        path_system: LazyPath.Index,
        path_after: LazyPath.Index,
        framework_path: LazyPath.Index,
        framework_path_system: LazyPath.Index,
        /// Always `Step.Tag.config_header`.
        config_header_step: Step.Index,
        embed_path: LazyPath.Index,
    };

    pub const RPath = union(enum(u1)) {
        lazy_path: LazyPath.Index,
        special: String,
    };

    pub const LinkObject = union(enum(u3)) {
        static_path: LazyPath.Index,
        /// Always `Step.Tag.compile`.
        other_step: Step.Index,
        system_lib: SystemLib.Index,
        assembly_file: LazyPath.Index,
        c_source_file: CSourceFile.Index,
        c_source_files: CSourceFiles.Index,
        win32_resource_file: RcSourceFile.Index,
    };

    pub const Framework = extern struct {
        flags: @This().Flags,
        name: String,

        pub const Flags = packed struct(u32) {
            needed: bool,
            weak: bool,
            _: u30 = 0,
        };
    };
};

pub const ImportTable = struct {
    imports: Storage.MultiList(Import),

    pub const Import = struct {
        name: String,
        module: Module.Index,
    };

    /// Points into `extra`.
    pub const Index = enum(u32) {
        invalid = max_u32,
        _,

        pub fn get(this: @This(), c: *const Configuration) ImportTable {
            return switch (this) {
                .invalid => unreachable,
                _ => extraData(c, ImportTable, @intFromEnum(this)),
            };
        }
    };
};

pub const Deps = struct {
    steps: Storage.LengthPrefixedList(Step.Index),

    pub const Index = enum(u32) {
        _,

        pub fn get(this: @This(), c: *const Configuration) Deps {
            return extraData(c, Deps, @intFromEnum(this));
        }

        pub fn slice(this: @This(), c: *const Configuration) []const Step.Index {
            return get(this, c).steps.slice;
        }
    };
};

pub const EnvironMap = struct {
    keys: StringList,
    values: StringList,

    pub const Index = IndexType(@This());
};

/// Points into `extra`, where the first element is count of strings, following
/// elements is `String` per count.
///
/// Stored identically to `Deps`.
pub const StringList = enum(u32) {
    _,

    pub fn slice(this: @This(), c: *const Configuration) []const String {
        const len = c.extra[@intFromEnum(this)];
        return @ptrCast(c.extra[@intFromEnum(this) + 1 ..][0..len]);
    }
};

pub const OptionalStringList = enum(u32) {
    none = max_u32,
    _,

    pub fn init(opt_string_list: ?StringList) OptionalStringList {
        const sl = opt_string_list orelse return .none;
        const result: OptionalStringList = @enumFromInt(@intFromEnum(sl));
        assert(result != .none);
        return result;
    }

    pub fn unwrap(this: @This()) ?StringList {
        if (this == .none) return null;
        return @enumFromInt(@intFromEnum(this));
    }

    pub fn slice(this: @This(), c: *const Configuration) ?[]const String {
        return (unwrap(this) orelse return null).slice(c);
    }
};

pub const Path = extern struct {
    base: Base,
    sub: String,

    pub const Base = enum(u8) {
        cwd,
        local_cache,
        global_cache,
        build_root,
        zig_exe,
        zig_lib,
        install_prefix,
        install_lib,
        install_bin,
        install_include,
    };

    pub fn toCachePath(path: Path, c: *const Configuration, arena: Allocator) std.Build.Cache.Path {
        _ = c;
        _ = arena;
        _ = path;
        @panic("TODO");
    }
};

pub const InstallDestDir = enum(u32) {
    none = max_u32 - 4,
    prefix = max_u32 - 3,
    lib = max_u32 - 2,
    bin = max_u32 - 1,
    header = max_u32,
    /// A `String` path relative to the prefix.
    _,

    pub fn initCustom(sub_path: String) InstallDestDir {
        assert(@intFromEnum(sub_path) < @intFromEnum(InstallDestDir.none));
        return @enumFromInt(@intFromEnum(sub_path));
    }

    pub const Unpacked = union(enum) {
        prefix,
        lib,
        bin,
        header,
        sub_path: String,
    };

    pub fn unpack(this: @This()) ?Unpacked {
        return switch (this) {
            .none => null,
            .prefix => .prefix,
            .lib => .lib,
            .bin => .bin,
            .header => .header,
            _ => .{ .sub_path = @enumFromInt(@intFromEnum(this)) },
        };
    }
};

/// Points into `string_bytes`, null-terminated.
pub const OptionalString = enum(u32) {
    empty = 0,
    /// The string "root".
    root = 1,
    none = max_u32,
    _,

    pub fn init(s: String) OptionalString {
        const result: OptionalString = @enumFromInt(@intFromEnum(s));
        assert(result != .none);
        return result;
    }

    pub fn unwrap(this: @This()) ?String {
        if (this == .none) return null;
        return @enumFromInt(@intFromEnum(this));
    }

    pub fn slice(this: @This(), c: *const Configuration) ?[:0]const u8 {
        return (unwrap(this) orelse return null).slice(c);
    }
};

/// Points into `string_bytes`, null-terminated.
pub const String = enum(u32) {
    empty = 0,
    /// The string "root".
    root = 1,
    _,

    pub fn slice(index: String, c: *const Configuration) [:0]const u8 {
        const start_slice = c.string_bytes[@intFromEnum(index)..];
        return start_slice[0..std.mem.indexOfScalar(u8, start_slice, 0).? :0];
    }
};

/// Arbitrary sequence of bytes that may contain null bytes.
pub const Bytes = extern struct {
    /// Points into `string_bytes`.
    index: u32,
    len: u32,

    pub fn slice(bytes: Bytes, c: *const Configuration) []const u8 {
        return c.string_bytes[bytes.index..][0..bytes.len];
    }
};

/// Stored as a power-of-two, with one special value to indicate none.
pub const Alignment = enum(u6) {
    @"1" = 0,
    @"2" = 1,
    @"4" = 2,
    @"8" = 3,
    @"16" = 4,
    @"32" = 5,
    @"64" = 6,
    none = std.math.maxInt(u6),
    _,

    pub fn init(optional_alignment: ?std.mem.Alignment) @This() {
        const a = optional_alignment orelse return .none;
        return @enumFromInt(@intFromEnum(a));
    }

    pub fn toBytes(a: @This()) ?u64 {
        return switch (a) {
            .none => null,
            else => @as(u64, 1) << @intFromEnum(a),
        };
    }
};

pub const DefaultingBool = enum(u2) {
    false,
    true,
    default,

    pub fn init(b: ?bool) DefaultingBool {
        return switch (b orelse return .default) {
            false => .false,
            true => .true,
        };
    }

    pub fn toBool(db: DefaultingBool) ?bool {
        return switch (db) {
            .false => false,
            .true => true,
            .default => null,
        };
    }
};

pub const SystemLib = struct {
    name: String,
    flags: Flags,

    pub const Index = enum(u32) {
        _,

        pub fn get(this: @This(), c: *const Configuration) SystemLib {
            return extraData(c, SystemLib, @intFromEnum(this));
        }
    };

    pub const UsePkgConfig = enum(u2) {
        /// Don't use pkg-config, just pass -lfoo where foo is name.
        no,
        /// Try to get information on how to link the library from pkg-config.
        /// If that fails, fall back to passing -lfoo where foo is name.
        yes,
        /// Try to get information on how to link the library from pkg-config.
        /// If that fails, error out.
        force,
    };

    pub const LinkMode = std.builtin.LinkMode;

    pub const Flags = packed struct(u32) {
        needed: bool,
        weak: bool,
        use_pkg_config: UsePkgConfig,
        preferred_link_mode: LinkMode,
        search_strategy: SearchStrategy,
        _: u25 = 0,
    };

    pub const SearchStrategy = enum(u2) { paths_first, mode_first, no_fallback };
};

pub const CSourceFiles = struct {
    flags: Flags,
    root: LazyPath.Index,
    args: Storage.FlagList(.flags, .args_len, String),
    sub_paths: Storage.LengthPrefixedList(String),

    pub const Index = enum(u32) {
        _,

        pub fn get(this: @This(), c: *const Configuration) CSourceFiles {
            return extraData(c, CSourceFiles, @intFromEnum(this));
        }
    };

    pub const Flags = packed struct(u32) {
        /// C compiler CLI flags.
        args_len: u29,
        lang: OptionalCSourceLanguage,
    };
};

pub const CSourceFile = struct {
    flags: Flags,
    file: LazyPath.Index,
    args: Storage.FlagList(.flags, .args_len, String),

    pub const Index = enum(u32) {
        _,

        pub fn get(this: @This(), c: *const Configuration) CSourceFile {
            return extraData(c, CSourceFile, @intFromEnum(this));
        }
    };

    pub const Flags = packed struct(u32) {
        /// C compiler CLI flags.
        args_len: u29,
        lang: OptionalCSourceLanguage,
    };
};

pub const RcSourceFile = struct {
    flags: Flags,
    file: LazyPath.Index,
    args: Storage.FlagList(.flags, .args_len, String),
    include_paths: Storage.FlagLengthPrefixedList(.flags, .include_paths, LazyPath.Index),

    pub const Index = enum(u32) {
        _,

        pub fn get(this: @This(), c: *const Configuration) RcSourceFile {
            return extraData(c, RcSourceFile, @intFromEnum(this));
        }
    };

    pub const Flags = packed struct(u32) {
        /// C compiler CLI flags.
        args_len: u31,
        include_paths: bool,
    };
};

pub const OptionalCSourceLanguage = enum(u3) {
    c,
    cpp,
    objective_c,
    objective_cpp,
    assembly,
    assembly_with_preprocessor,
    default,

    pub fn init(x: ?std.Build.Module.CSourceLanguage) @This() {
        return switch (x orelse return .default) {
            .c => .c,
            .cpp => .cpp,
            .objective_c => .objective_c,
            .objective_cpp => .objective_cpp,
            .assembly => .assembly,
            .assembly_with_preprocessor => .assembly_with_preprocessor,
        };
    }

    pub fn get(this: @This()) ?std.Build.Module.CSourceLanguage {
        return switch (this) {
            .c => .c,
            .cpp => .cpp,
            .objective_c => .objective_c,
            .objective_cpp => .objective_cpp,
            .assembly => .assembly,
            .assembly_with_preprocessor => .assembly_with_preprocessor,
            .default => null,
        };
    }
};

pub const ResolvedTarget = struct {
    /// none indicates host.
    query: TargetQuery.OptionalIndex,
    /// defaults will be resolved.
    result: TargetQuery.Index,

    pub const Index = enum(u32) {
        _,

        pub fn get(this: @This(), c: *const Configuration) ResolvedTarget {
            return extraData(c, ResolvedTarget, @intFromEnum(this));
        }
    };

    pub const OptionalIndex = enum(u32) {
        none = max_u32,
        _,

        pub fn init(i: Index) OptionalIndex {
            const result: OptionalIndex = @enumFromInt(@intFromEnum(i));
            assert(result != .none);
            return result;
        }

        pub fn unwrap(this: @This()) ?Index {
            return switch (this) {
                .none => null,
                _ => @enumFromInt(@intFromEnum(this)),
            };
        }

        pub fn get(this: @This(), c: *const Configuration) ?ResolvedTarget {
            return (unwrap(this) orelse return null).get(c);
        }
    };

    pub fn unwrapQuery(rt: *const ResolvedTarget, c: *const Configuration) ?std.Target.Query {
        const tq = rt.query.get(c) orelse return null;
        const cpu_arch = tq.flags.cpu_arch.unwrap() orelse rt.result.get(c).flags.cpu_arch.unwrap().?;
        return .{
            .cpu_arch = cpu_arch,
            .cpu_model = switch (tq.flags.cpu_model) {
                .native => .native,
                .baseline => .baseline,
                .determined_by_arch_os => .determined_by_arch_os,
                .explicit => .{ .explicit = cpu_arch.parseCpuModel(tq.cpu_name.value.?.slice(c)).? },
            },
            .cpu_features_add = tq.cpu_features_add.value orelse .empty,
            .cpu_features_sub = tq.cpu_features_sub.value orelse .empty,
            .os_tag = tq.flags.os_tag.unwrap(),
            .os_version_min = tq.os_version_min.u.unwrap(c),
            .os_version_max = tq.os_version_max.u.unwrap(c),
            .glibc_version = if (tq.glibc_version.value) |s|
                std.SemanticVersion.parse(s.slice(c)) catch unreachable
            else
                null,
            .android_api_level = tq.android_api_level.value,
            .abi = tq.flags.abi.unwrap(),
            .dynamic_linker = if (tq.dynamic_linker.value) |s| .init(s.slice(c)) else null,
            .ofmt = tq.flags.object_format.unwrap(),
        };
    }
};

pub const TargetQuery = struct {
    flags: Flags,

    cpu_features_add: Storage.FlagOptional(.flags, .cpu_features_add, std.Target.Cpu.Feature.Set),
    cpu_features_sub: Storage.FlagOptional(.flags, .cpu_features_sub, std.Target.Cpu.Feature.Set),
    cpu_name: Storage.EnumOptional(.flags, .cpu_model, .explicit, String),
    os_version_min: Storage.FlagUnion(.flags, .os_version_min, OsVersion),
    os_version_max: Storage.FlagUnion(.flags, .os_version_max, OsVersion),
    glibc_version: Storage.FlagOptional(.flags, .glibc_version, String),
    android_api_level: Storage.FlagOptional(.flags, .android_api_level, u32),
    dynamic_linker: Storage.FlagOptional(.flags, .dynamic_linker, String),

    pub const Index = enum(u32) {
        _,

        pub fn extraSlice(i: Index, extra: []const u32) []const u32 {
            return extra[@intFromEnum(i)..][0..length(i, extra)];
        }

        pub fn length(i: Index, extra: []const u32) usize {
            return Storage.dataLength(extra, @intFromEnum(i), TargetQuery);
        }

        pub fn get(this: @This(), c: *const Configuration) TargetQuery {
            return extraData(c, TargetQuery, @intFromEnum(this));
        }
    };

    pub const OptionalIndex = enum(u32) {
        none = max_u32,
        _,

        pub fn init(i: Index) OptionalIndex {
            const result: OptionalIndex = @enumFromInt(@intFromEnum(i));
            assert(result != .none);
            return result;
        }

        pub fn unwrap(this: @This()) ?Index {
            return switch (this) {
                .none => null,
                _ => @enumFromInt(@intFromEnum(this)),
            };
        }

        pub fn get(this: @This(), c: *const Configuration) ?TargetQuery {
            return (this.unwrap() orelse return null).get(c);
        }
    };

    pub const CpuModel = enum(u2) {
        native,
        baseline,
        determined_by_arch_os,
        explicit,

        pub fn init(x: std.Target.Query.CpuModel) @This() {
            return switch (x) {
                .native => .native,
                .baseline => .baseline,
                .determined_by_arch_os => .determined_by_arch_os,
                .explicit => .explicit,
            };
        }
    };
    pub const OsVersion = union(@This().Tag) {
        pub const Tag = enum(u2) { none, semver, windows, default };

        none: void,
        semver: String,
        windows: std.Target.Os.WindowsVersion,
        default: void,

        pub fn unwrap(this: @This(), c: *const Configuration) ?std.Target.Query.OsVersion {
            return switch (this) {
                .none => .none,
                .semver => |sv| .{ .semver = std.SemanticVersion.parse(sv.slice(c)) catch unreachable },
                .windows => |wv| .{ .windows = wv },
                .default => null,
            };
        }
    };

    pub const Abi = enum(u5) {
        none,
        gnu,
        gnuabin32,
        gnuabi64,
        gnueabi,
        gnueabihf,
        gnuf32,
        gnusf,
        gnux32,
        eabi,
        eabihf,
        abin32,
        x32,
        ilp32,
        android,
        androideabi,
        musl,
        muslabin32,
        muslabi64,
        musleabi,
        musleabihf,
        muslf32,
        muslsf,
        muslx32,
        msvc,
        itanium,
        simulator,
        ohos,
        ohoseabi,
        call0,

        default,

        pub fn init(x: ?std.Target.Abi) @This() {
            return switch (x orelse return .default) {
                .none => .none,
                .gnu => .gnu,
                .gnuabin32 => .gnuabin32,
                .gnuabi64 => .gnuabi64,
                .gnueabi => .gnueabi,
                .gnueabihf => .gnueabihf,
                .gnuf32 => .gnuf32,
                .gnusf => .gnusf,
                .gnux32 => .gnux32,
                .eabi => .eabi,
                .eabihf => .eabihf,
                .abin32 => .abin32,
                .x32 => .x32,
                .ilp32 => .ilp32,
                .android => .android,
                .androideabi => .androideabi,
                .musl => .musl,
                .muslabin32 => .muslabin32,
                .muslabi64 => .muslabi64,
                .musleabi => .musleabi,
                .musleabihf => .musleabihf,
                .muslf32 => .muslf32,
                .muslsf => .muslsf,
                .muslx32 => .muslx32,
                .msvc => .msvc,
                .itanium => .itanium,
                .simulator => .simulator,
                .ohos => .ohos,
                .ohoseabi => .ohoseabi,
                .call0 => .call0,
            };
        }

        pub fn unwrap(this: @This()) ?std.Target.Abi {
            return switch (this) {
                .none => .none,
                .gnu => .gnu,
                .gnuabin32 => .gnuabin32,
                .gnuabi64 => .gnuabi64,
                .gnueabi => .gnueabi,
                .gnueabihf => .gnueabihf,
                .gnuf32 => .gnuf32,
                .gnusf => .gnusf,
                .gnux32 => .gnux32,
                .eabi => .eabi,
                .eabihf => .eabihf,
                .abin32 => .abin32,
                .x32 => .x32,
                .ilp32 => .ilp32,
                .android => .android,
                .androideabi => .androideabi,
                .musl => .musl,
                .muslabin32 => .muslabin32,
                .muslabi64 => .muslabi64,
                .musleabi => .musleabi,
                .musleabihf => .musleabihf,
                .muslf32 => .muslf32,
                .muslsf => .muslsf,
                .muslx32 => .muslx32,
                .msvc => .msvc,
                .itanium => .itanium,
                .simulator => .simulator,
                .ohos => .ohos,
                .ohoseabi => .ohoseabi,
                .call0 => .call0,
                .default => null,
            };
        }
    };

    pub const CpuArch = enum(u6) {
        aarch64,
        aarch64_be,
        alpha,
        amdgcn,
        arc,
        arceb,
        arm,
        armeb,
        avr,
        bpfeb,
        bpfel,
        csky,
        ez80,
        hexagon,
        hppa,
        hppa64,
        kalimba,
        kvx,
        lanai,
        loongarch32,
        loongarch64,
        m68k,
        m88k,
        microblaze,
        microblazeel,
        mips,
        mipsel,
        mips64,
        mips64el,
        msp430,
        nvptx,
        nvptx64,
        or1k,
        powerpc,
        powerpcle,
        powerpc64,
        powerpc64le,
        propeller,
        riscv32,
        riscv32be,
        riscv64,
        riscv64be,
        s390x,
        sh,
        sheb,
        sparc,
        sparc64,
        spirv32,
        spirv64,
        thumb,
        thumbeb,
        ve,
        wasm32,
        wasm64,
        x86_16,
        x86,
        x86_64,
        xcore,
        xtensa,
        xtensaeb,

        default,

        pub fn init(x: ?std.Target.Cpu.Arch) @This() {
            return switch (x orelse return .default) {
                .aarch64 => .aarch64,
                .aarch64_be => .aarch64_be,
                .alpha => .alpha,
                .amdgcn => .amdgcn,
                .arc => .arc,
                .arceb => .arceb,
                .arm => .arm,
                .armeb => .armeb,
                .avr => .avr,
                .bpfeb => .bpfeb,
                .bpfel => .bpfel,
                .csky => .csky,
                .ez80 => .ez80,
                .hexagon => .hexagon,
                .hppa => .hppa,
                .hppa64 => .hppa64,
                .kalimba => .kalimba,
                .kvx => .kvx,
                .lanai => .lanai,
                .loongarch32 => .loongarch32,
                .loongarch64 => .loongarch64,
                .m68k => .m68k,
                .m88k => .m88k,
                .microblaze => .microblaze,
                .microblazeel => .microblazeel,
                .mips => .mips,
                .mipsel => .mipsel,
                .mips64 => .mips64,
                .mips64el => .mips64el,
                .msp430 => .msp430,
                .nvptx => .nvptx,
                .nvptx64 => .nvptx64,
                .or1k => .or1k,
                .powerpc => .powerpc,
                .powerpcle => .powerpcle,
                .powerpc64 => .powerpc64,
                .powerpc64le => .powerpc64le,
                .propeller => .propeller,
                .riscv32 => .riscv32,
                .riscv32be => .riscv32be,
                .riscv64 => .riscv64,
                .riscv64be => .riscv64be,
                .s390x => .s390x,
                .sh => .sh,
                .sheb => .sheb,
                .sparc => .sparc,
                .sparc64 => .sparc64,
                .spirv32 => .spirv32,
                .spirv64 => .spirv64,
                .thumb => .thumb,
                .thumbeb => .thumbeb,
                .ve => .ve,
                .wasm32 => .wasm32,
                .wasm64 => .wasm64,
                .x86_16 => .x86_16,
                .x86 => .x86,
                .x86_64 => .x86_64,
                .xcore => .xcore,
                .xtensa => .xtensa,
                .xtensaeb => .xtensaeb,
            };
        }

        pub fn unwrap(this: @This()) ?std.Target.Cpu.Arch {
            return switch (this) {
                .aarch64 => .aarch64,
                .aarch64_be => .aarch64_be,
                .alpha => .alpha,
                .amdgcn => .amdgcn,
                .arc => .arc,
                .arceb => .arceb,
                .arm => .arm,
                .armeb => .armeb,
                .avr => .avr,
                .bpfeb => .bpfeb,
                .bpfel => .bpfel,
                .csky => .csky,
                .ez80 => .ez80,
                .hexagon => .hexagon,
                .hppa => .hppa,
                .hppa64 => .hppa64,
                .kalimba => .kalimba,
                .kvx => .kvx,
                .lanai => .lanai,
                .loongarch32 => .loongarch32,
                .loongarch64 => .loongarch64,
                .m68k => .m68k,
                .m88k => .m88k,
                .microblaze => .microblaze,
                .microblazeel => .microblazeel,
                .mips => .mips,
                .mipsel => .mipsel,
                .mips64 => .mips64,
                .mips64el => .mips64el,
                .msp430 => .msp430,
                .nvptx => .nvptx,
                .nvptx64 => .nvptx64,
                .or1k => .or1k,
                .powerpc => .powerpc,
                .powerpcle => .powerpcle,
                .powerpc64 => .powerpc64,
                .powerpc64le => .powerpc64le,
                .propeller => .propeller,
                .riscv32 => .riscv32,
                .riscv32be => .riscv32be,
                .riscv64 => .riscv64,
                .riscv64be => .riscv64be,
                .s390x => .s390x,
                .sh => .sh,
                .sheb => .sheb,
                .sparc => .sparc,
                .sparc64 => .sparc64,
                .spirv32 => .spirv32,
                .spirv64 => .spirv64,
                .thumb => .thumb,
                .thumbeb => .thumbeb,
                .ve => .ve,
                .wasm32 => .wasm32,
                .wasm64 => .wasm64,
                .x86_16 => .x86_16,
                .x86 => .x86,
                .x86_64 => .x86_64,
                .xcore => .xcore,
                .xtensa => .xtensa,
                .xtensaeb => .xtensaeb,

                .default => null,
            };
        }
    };

    pub const OsTag = enum(u6) {
        freestanding,
        other,
        contiki,
        fuchsia,
        hermit,
        managarm,
        haiku,
        hurd,
        illumos,
        linux,
        plan9,
        rtems,
        serenity,
        dragonfly,
        freebsd,
        netbsd,
        openbsd,
        driverkit,
        ios,
        maccatalyst,
        macos,
        tvos,
        visionos,
        watchos,
        windows,
        uefi,
        @"3ds",
        wiiu,
        psx,
        ps3,
        ps4,
        ps5,
        psp,
        vita,
        emscripten,
        wasi,
        amdhsa,
        amdpal,
        cuda,
        mesa3d,
        nvcl,
        opencl,
        opengl,
        vulkan,
        tios,

        default,

        pub fn init(x: ?std.Target.Os.Tag) @This() {
            return switch (x orelse return .default) {
                .freestanding => .freestanding,
                .other => .other,
                .contiki => .contiki,
                .fuchsia => .fuchsia,
                .hermit => .hermit,
                .managarm => .managarm,
                .haiku => .haiku,
                .hurd => .hurd,
                .illumos => .illumos,
                .linux => .linux,
                .plan9 => .plan9,
                .rtems => .rtems,
                .serenity => .serenity,
                .dragonfly => .dragonfly,
                .freebsd => .freebsd,
                .netbsd => .netbsd,
                .openbsd => .openbsd,
                .driverkit => .driverkit,
                .ios => .ios,
                .maccatalyst => .maccatalyst,
                .macos => .macos,
                .tvos => .tvos,
                .visionos => .visionos,
                .watchos => .watchos,
                .windows => .windows,
                .uefi => .uefi,
                .@"3ds" => .@"3ds",
                .wiiu => .wiiu,
                .psx => .psx,
                .ps3 => .ps3,
                .ps4 => .ps4,
                .ps5 => .ps5,
                .psp => .psp,
                .vita => .vita,
                .emscripten => .emscripten,
                .wasi => .wasi,
                .amdhsa => .amdhsa,
                .amdpal => .amdpal,
                .cuda => .cuda,
                .mesa3d => .mesa3d,
                .nvcl => .nvcl,
                .opencl => .opencl,
                .opengl => .opengl,
                .vulkan => .vulkan,
                .tios => .tios,
            };
        }

        pub fn unwrap(this: @This()) ?std.Target.Os.Tag {
            return switch (this) {
                .freestanding => .freestanding,
                .other => .other,
                .contiki => .contiki,
                .fuchsia => .fuchsia,
                .hermit => .hermit,
                .managarm => .managarm,
                .haiku => .haiku,
                .hurd => .hurd,
                .illumos => .illumos,
                .linux => .linux,
                .plan9 => .plan9,
                .rtems => .rtems,
                .serenity => .serenity,
                .dragonfly => .dragonfly,
                .freebsd => .freebsd,
                .netbsd => .netbsd,
                .openbsd => .openbsd,
                .driverkit => .driverkit,
                .ios => .ios,
                .maccatalyst => .maccatalyst,
                .macos => .macos,
                .tvos => .tvos,
                .visionos => .visionos,
                .watchos => .watchos,
                .windows => .windows,
                .uefi => .uefi,
                .@"3ds" => .@"3ds",
                .wiiu => .wiiu,
                .psx => .psx,
                .ps3 => .ps3,
                .ps4 => .ps4,
                .ps5 => .ps5,
                .psp => .psp,
                .vita => .vita,
                .emscripten => .emscripten,
                .wasi => .wasi,
                .amdhsa => .amdhsa,
                .amdpal => .amdpal,
                .cuda => .cuda,
                .mesa3d => .mesa3d,
                .nvcl => .nvcl,
                .opencl => .opencl,
                .opengl => .opengl,
                .vulkan => .vulkan,
                .tios => .tios,

                .default => null,
            };
        }
    };

    pub const ObjectFormat = enum(u4) {
        c,
        coff,
        elf,
        hex,
        macho,
        plan9,
        raw,
        spirv,
        wasm,

        default,

        pub fn init(x: ?std.Target.ObjectFormat) @This() {
            return switch (x orelse return .default) {
                .c => .c,
                .coff => .coff,
                .elf => .elf,
                .hex => .hex,
                .macho => .macho,
                .plan9 => .plan9,
                .raw => .raw,
                .spirv => .spirv,
                .wasm => .wasm,
            };
        }

        pub fn unwrap(this: @This()) ?std.Target.ObjectFormat {
            return switch (this) {
                .c => .c,
                .coff => .coff,
                .elf => .elf,
                .hex => .hex,
                .macho => .macho,
                .plan9 => .plan9,
                .raw => .raw,
                .spirv => .spirv,
                .wasm => .wasm,

                .default => null,
            };
        }
    };

    pub const Flags = packed struct(u32) {
        cpu_arch: CpuArch,
        cpu_model: CpuModel,
        cpu_features_add: bool,
        cpu_features_sub: bool,
        os_tag: OsTag,
        abi: Abi,
        object_format: ObjectFormat,
        os_version_min: OsVersion.Tag,
        os_version_max: OsVersion.Tag,
        glibc_version: bool,
        android_api_level: bool,
        dynamic_linker: bool,
    };

    pub fn unwrapTarget(tq: *const TargetQuery, c: *const Configuration) std.Target {
        const cpu_arch = tq.flags.cpu_arch.unwrap().?;
        const os_tag = tq.flags.os_tag.unwrap().?;
        return .{
            .cpu = .{
                .arch = cpu_arch,
                .model = cpu_arch.parseCpuModel(tq.cpu_name.value.?.slice(c)).?,
                .features = tq.cpu_features_add.value.?,
            },
            .os = .{
                .tag = os_tag,
                .version_range = switch (os_tag) {
                    .linux => .{ .linux = .{
                        .range = .{
                            .min = tq.os_version_min.u.unwrap(c).?.semver,
                            .max = tq.os_version_max.u.unwrap(c).?.semver,
                        },
                        .glibc = std.SemanticVersion.parse(tq.glibc_version.value.?.slice(c)) catch unreachable,
                        .android = tq.android_api_level.value.?,
                    } },
                    .hurd => .{ .hurd = .{
                        .range = .{
                            .min = tq.os_version_min.u.unwrap(c).?.semver,
                            .max = tq.os_version_max.u.unwrap(c).?.semver,
                        },
                        .glibc = std.SemanticVersion.parse(tq.glibc_version.value.?.slice(c)) catch unreachable,
                    } },
                    .windows => .{ .windows = .{
                        .min = tq.os_version_min.u.unwrap(c).?.windows,
                        .max = tq.os_version_max.u.unwrap(c).?.windows,
                    } },
                    else => switch (tq.os_version_min.u.unwrap(c).?) {
                        .none => .{ .none = {} },
                        .semver => |min| .{ .semver = .{
                            .min = min,
                            .max = tq.os_version_max.u.unwrap(c).?.semver,
                        } },
                        .windows => unreachable,
                    },
                },
            },
            .abi = tq.flags.abi.unwrap().?,
            .ofmt = tq.flags.object_format.unwrap().?,
            .dynamic_linker = .init(if (tq.dynamic_linker.value) |s| s.slice(c) else null),
        };
    }
};

pub const Storage = enum {
    flag_optional,
    enum_optional,
    extended,
    length_prefixed_list,
    flag_length_prefixed_list,
    union_list,
    flag_union,
    multi_list,
    flag_list,

    /// The presence of the field is determined by a boolean within a packed
    /// struct.
    pub fn FlagOptional(
        comptime flags_arg: @EnumLiteral(),
        comptime flag_arg: @EnumLiteral(),
        comptime ValueArg: type,
    ) type {
        return struct {
            value: ?Value,

            pub const storage: Storage = .flag_optional;
            pub const flags = flags_arg;
            pub const flag = flag_arg;
            pub const Value = ValueArg;
        };
    }

    /// The type of the field is determined by an enum within a packed struct.
    pub fn FlagUnion(
        comptime flags_arg: @EnumLiteral(),
        comptime flag_arg: @EnumLiteral(),
        comptime UnionArg: type,
    ) type {
        return struct {
            u: Union,

            pub const storage: Storage = .flag_union;
            pub const flags = flags_arg;
            pub const flag = flag_arg;
            pub const Union = UnionArg;

            pub const Tag = @typeInfo(Union).@"union".tag_type.?;
        };
    }

    /// The field is present if an enum tag from flags matches a specific value.
    pub fn EnumOptional(
        comptime flags_arg: @EnumLiteral(),
        comptime flag_arg: @EnumLiteral(),
        comptime tag_arg: @EnumLiteral(),
        comptime ValueArg: type,
    ) type {
        return struct {
            value: ?Value,

            pub const storage: Storage = .enum_optional;
            pub const flags = flags_arg;
            pub const flag = flag_arg;
            pub const tag = tag_arg;
            pub const Value = ValueArg;
        };
    }

    /// The field indexes into an auxilary buffer, with the first element being
    /// a packed struct that contains the tag.
    pub fn Extended(comptime BaseFlags: type, comptime U: type) type {
        return enum(u32) {
            _,

            pub const storage: Storage = .extended;

            pub fn tag(this: @This(), c: *const Configuration) @FieldType(BaseFlags, "tag") {
                const base_flags: BaseFlags = @bitCast(c.extra[@intFromEnum(this)]);
                return base_flags.tag;
            }

            pub fn cast(this: @This(), c: *const Configuration, comptime S: type) ?S {
                const wanted_tag = blk: {
                    const info = @typeInfo(S.Flags).@"struct";
                    break :blk info.field_attrs[0].defaultValue(info.field_types[0]).?;
                };
                const base_flags: BaseFlags = @bitCast(c.extra[@intFromEnum(this)]);
                if (base_flags.tag != wanted_tag) return null;
                var i: usize = @intFromEnum(this);
                return data(c.extra, &i, S);
            }

            pub fn get(this: @This(), buffer: []const u32) U {
                var i: usize = @intFromEnum(this);
                const base_flags: BaseFlags = @bitCast(buffer[i]);
                return switch (base_flags.tag) {
                    inline else => |t| @unionInit(U, @tagName(t), data(buffer, &i, @FieldType(U, @tagName(t)))),
                };
            }
        };
    }

    /// A field in flags determines whether the length is zero or nonzero. If
    /// the length is nonzero, then there is a length field followed by the
    /// list. The elements need well-defined memory layout but can otherwise be
    /// any multiple of u32 length. The length is the number of elements, not
    /// the number of u32s.
    pub fn FlagLengthPrefixedList(
        comptime flags_arg: @EnumLiteral(),
        comptime flag_arg: @EnumLiteral(),
        comptime ElemArg: type,
    ) type {
        return struct {
            slice: []const Elem,

            pub const storage: Storage = .flag_length_prefixed_list;
            pub const flags = flags_arg;
            pub const flag = flag_arg;
            pub const Elem = ElemArg;

            pub fn initErased(s: []const u32) @This() {
                return .{ .slice = @ptrCast(s) };
            }
        };
    }

    /// The field contains a u32 length followed by that many items. Each
    /// element needs well-defined memory layout but can otherwise be any
    /// multiple of u32 length. The length is number of elements, not the
    /// number of u32s.
    pub fn LengthPrefixedList(comptime ElemArg: type) type {
        return struct {
            slice: []const Elem,

            pub const storage: Storage = .length_prefixed_list;
            pub const Elem = ElemArg;

            pub fn initErased(s: []const u32) @This() {
                return .{ .slice = @ptrCast(s) };
            }
        };
    }

    /// The field is a list whose length is an integer inside flags.
    pub fn FlagList(
        comptime flags_arg: @EnumLiteral(),
        comptime flag_arg: @EnumLiteral(),
        comptime ElemArg: type,
    ) type {
        return struct {
            slice: []const Elem,

            pub const storage: Storage = .flag_list;
            pub const flags = flags_arg;
            pub const flag = flag_arg;
            pub const Elem = ElemArg;

            pub fn initErased(s: []const u32) @This() {
                return .{ .slice = @ptrCast(s) };
            }
        };
    }

    /// The field contains a u32 length followed by that many items for the
    /// first field, that many items for the second field, etc.
    pub fn MultiList(comptime ElemArg: type) type {
        return struct {
            mal: std.MultiArrayList(Elem),

            pub const storage: Storage = .multi_list;
            pub const Elem = ElemArg;
        };
    }

    /// `UnionArg` is a tagged union with a small integer for the enum tag.
    ///
    /// A field in flags determines whether the metadata is present.
    ///
    /// The metadata is bit-packed consecutive packed struct which is the
    /// `UnionArg` enum tag combined with a "last" marker boolean field.
    /// When "last" is true, the element is the last one, providing
    /// the length of the list.
    ///
    /// Following is each element of the list; each bitcastable to u32.
    pub fn UnionList(
        comptime flags_arg: @EnumLiteral(),
        comptime flag_arg: @EnumLiteral(),
        comptime UnionArg: type,
    ) type {
        return struct {
            /// When serializing it is UnionArg slice pointer.
            /// When deserializing it is extra index of first UnionArg element.
            data: ?*const anyopaque,
            len: usize,

            pub const storage: Storage = .union_list;
            pub const flags = flags_arg;
            pub const flag = flag_arg;
            pub const Union = UnionArg;

            pub const Tag = @typeInfo(Union).@"union".tag_type.?;
            pub const MetaInt = @Int(.unsigned, @bitSizeOf(Tag) + 1);
            pub const Meta = packed struct(MetaInt) {
                tag: Tag,
                last: bool,
            };

            /// Valid to call only when serializing.
            pub fn init(s: []const Union) @This() {
                return .{ .data = s.ptr, .len = s.len };
            }

            /// Valid to call only when deserializing.
            pub fn slice(this: *const @This(), extra: []const u32) []const u32 {
                return extra[@intFromPtr(this.data)..][0..this.len];
            }

            /// Valid to call only when deserializing.
            pub fn get(this: *const @This(), extra: []const u32, i: usize) Union {
                const elem = slice(this, extra)[i];
                return switch (this.tag(extra, i)) {
                    inline else => |comptime_tag| @unionInit(Union, @tagName(comptime_tag), @enumFromInt(elem)),
                };
            }

            /// Valid to call only when deserializing.
            pub fn tag(this: *const @This(), extra: []const u32, i: usize) Tag {
                const start = @intFromPtr(this.data);
                const meta_start = start - (this.len * @bitSizeOf(Meta) + 31) / 32;
                return loadBits(u32, extra[meta_start..], i * @bitSizeOf(Meta), Meta).tag;
            }

            fn extraLen(len: usize) usize {
                return len + (len * @bitSizeOf(Meta) + 31) / 32;
            }
        };
    }

    pub fn dataLength(buffer: []const u32, i: usize, comptime S: type) usize {
        var end = i;
        _ = data(buffer, &end, S);
        return end - i;
    }

    pub fn data(buffer: []const u32, i: *usize, comptime T: type) T {
        switch (@typeInfo(T)) {
            .@"struct" => |info| {
                var result: T = undefined;
                inline for (info.field_names, info.field_types) |field_name, field_type| {
                    @field(result, field_name) = dataField(buffer, i, &result, field_type);
                }
                return result;
            },
            .@"union" => |info| {
                const flags: T.Flags = @bitCast(buffer[i.*]);
                return switch (flags.tag) {
                    inline else => |comptime_tag| @unionInit(
                        T,
                        @tagName(comptime_tag),
                        data(buffer, i, info.field_types[@intFromEnum(comptime_tag)]),
                    ),
                };
            },
            else => comptime unreachable,
        }
    }

    fn dataField(buffer: []const u32, i: *usize, container: anytype, comptime Field: type) Field {
        switch (@typeInfo(Field)) {
            .void => return {},
            .int => |info| switch (info.bits) {
                32 => {
                    defer i.* += 1;
                    return buffer[i.*];
                },
                64 => {
                    defer i.* += 2;
                    return @bitCast(buffer[i.*..][0..2].*);
                },
                else => comptime unreachable,
            },
            .@"enum" => {
                defer i.* += 1;
                return @enumFromInt(buffer[i.*]);
            },
            .@"struct" => |info| switch (info.layout) {
                .@"packed" => switch (info.backing_integer.?) {
                    u32 => {
                        defer i.* += 1;
                        return @bitCast(buffer[i.*]);
                    },
                    u64 => {
                        defer i.* += 2;
                        return @bitCast(buffer[i.*..][0..2].*);
                    },
                    else => comptime unreachable,
                },
                .auto => switch (Field) {
                    std.Target.Cpu.Feature.Set => {
                        const u32_count = (Field.usize_count * @sizeOf(usize)) / @sizeOf(u32);
                        defer i.* += u32_count;
                        return .{ .ints = @as(
                            *align(@alignOf(u32)) const [Field.usize_count]usize,
                            @ptrCast(buffer[i.*..][0..u32_count]),
                        ).* };
                    },
                    else => switch (Field.storage) {
                        .flag_optional => {
                            const flags = @field(container, @tagName(Field.flags));
                            const flag = @field(flags, @tagName(Field.flag));
                            return .{
                                .value = if (flag) dataField(buffer, i, container, Field.Value) else null,
                            };
                        },
                        .flag_union => {
                            const flags = @field(container, @tagName(Field.flags));
                            const tag: Field.Tag = @field(flags, @tagName(Field.flag));
                            return .{
                                .u = switch (tag) {
                                    inline else => |comptime_tag| @unionInit(
                                        Field.Union,
                                        @tagName(comptime_tag),
                                        dataField(
                                            buffer,
                                            i,
                                            container,
                                            @typeInfo(Field.Union).@"union".field_types[@intFromEnum(comptime_tag)],
                                        ),
                                    ),
                                },
                            };
                        },
                        .enum_optional => {
                            const flags = @field(container, @tagName(Field.flags));
                            const tag = @field(flags, @tagName(Field.flag));
                            const match = tag == Field.tag;
                            return .{
                                .value = if (match) dataField(buffer, i, container, Field.Value) else null,
                            };
                        },
                        .extended => @compileError("unimplemented"),
                        .length_prefixed_list => {
                            const n = @divExact(@sizeOf(Field.Elem), @sizeOf(u32));
                            const data_start = i.* + 1;
                            const buf_len = buffer[data_start - 1] * n;
                            defer i.* = data_start + buf_len;
                            return .{ .slice = @ptrCast(buffer[data_start..][0..buf_len]) };
                        },
                        .flag_length_prefixed_list => {
                            const flags = @field(container, @tagName(Field.flags));
                            const flag = @field(flags, @tagName(Field.flag));
                            if (!flag) return .{ .slice = &.{} };
                            const n = @divExact(@sizeOf(Field.Elem), @sizeOf(u32));
                            const data_start = i.* + 1;
                            const buf_len = buffer[data_start - 1] * n;
                            defer i.* = data_start + buf_len;
                            return .{ .slice = @ptrCast(buffer[data_start..][0..buf_len]) };
                        },
                        .flag_list => {
                            const flags = @field(container, @tagName(Field.flags));
                            const len: u32 = @field(flags, @tagName(Field.flag));
                            const data_start = i.*;
                            defer i.* = data_start + len;
                            return .{ .slice = @ptrCast(buffer[data_start..][0..len]) };
                        },
                        .multi_list => {
                            const data_start = i.* + 1;
                            const len = buffer[data_start - 1];
                            defer i.* = data_start + len * @typeInfo(Field.Elem).@"struct".field_names.len;
                            return .{ .mal = .{
                                .bytes = @ptrCast(@constCast(buffer[data_start..][0..len])),
                                .len = len,
                                .capacity = len,
                            } };
                        },
                        .union_list => {
                            const flags = @field(container, @tagName(Field.flags));
                            const flag = @field(flags, @tagName(Field.flag));
                            if (!flag) return .{ .data = null, .len = 0 };
                            const meta_start = i.*;
                            const meta_buffer = buffer[meta_start..];
                            var len: u32 = 0;
                            var bit_offset: usize = 0;
                            while (true) : (bit_offset += @bitSizeOf(Field.Meta)) {
                                const meta = loadBits(u32, meta_buffer, bit_offset, Field.Meta);
                                len += 1;
                                if (meta.last) break;
                            }
                            const end = meta_start + Field.extraLen(len);
                            i.* = end;
                            return .{ .data = @ptrFromInt(end - len), .len = len };
                        },
                    },
                },
                .@"extern" => {
                    const n = @divExact(@sizeOf(Field), @sizeOf(u32));
                    defer i.* += n;
                    return @bitCast(buffer[i.*..][0..n].*);
                },
            },
            else => comptime unreachable,
        }
    }

    /// Returns new end index.
    fn setExtra(buffer: []u32, index: usize, extra: anytype) usize {
        const info = @typeInfo(@TypeOf(extra)).@"struct";
        var i = index;
        inline for (info.field_names, info.field_types) |field_name, field_type| {
            i += setExtraField(buffer, i, field_type, @field(extra, field_name));
        }
        return i;
    }

    fn extraFieldLen(field: anytype) usize {
        const Field = @TypeOf(field);
        return switch (@typeInfo(Field)) {
            .void => 0,
            .int => |info| switch (info.bits) {
                32 => 1,
                64 => 2,
                else => comptime unreachable,
            },
            .@"enum" => 1,
            .@"struct" => |info| switch (info.layout) {
                .@"packed" => switch (info.backing_integer.?) {
                    u32 => 1,
                    u64 => 2,
                    else => comptime unreachable,
                },
                .auto => switch (Field.storage) {
                    .flag_optional, .enum_optional => (@sizeOf(Field.Value) + 3) / 4,
                    .extended => 1,
                    .length_prefixed_list,
                    .flag_length_prefixed_list,
                    .flag_list,
                    => 1 + @divExact(@sizeOf(Field.Elem), @sizeOf(u32)) * field.slice.len,
                    .multi_list => 1 + field.mal.len * @typeInfo(Field.Elem).@"struct".field_names.len,
                    .union_list => Field.extraLen(field.len),
                    .flag_union => switch (field.u) {
                        inline else => |v| extraFieldLen(v),
                    },
                },
                .@"extern" => @divExact(@sizeOf(Field), @sizeOf(u32)),
            },
            else => @compileError("bad type: " ++ @typeName(Field)),
        };
    }

    fn extraLen(extra: anytype) usize {
        const field_names = @typeInfo(@TypeOf(extra)).@"struct".field_names;
        var i: usize = 0;
        inline for (field_names) |name| {
            i += Storage.extraFieldLen(@field(extra, name));
        }
        return i;
    }

    inline fn setExtraField(buffer: []u32, i: usize, comptime Field: type, value: anytype) usize {
        switch (@typeInfo(Field)) {
            .void => return 0,
            .int => |info| switch (info.bits) {
                32 => {
                    buffer[i] = value;
                    return 1;
                },
                64 => {
                    buffer[i..][0..2].* = @bitCast(value);
                    return 2;
                },
                else => comptime unreachable,
            },
            .@"enum" => {
                buffer[i] = @intFromEnum(value);
                return 1;
            },
            .@"struct" => |info| switch (info.layout) {
                .@"packed" => switch (info.backing_integer.?) {
                    u32 => {
                        buffer[i] = @bitCast(value);
                        return 1;
                    },
                    u64 => {
                        buffer[i..][0..2].* = @bitCast(value);
                        return 2;
                    },
                    else => comptime unreachable,
                },
                .auto => switch (Field) {
                    std.Target.Cpu.Feature.Set => {
                        const casted: []const u32 = @ptrCast(&value.ints);
                        @memcpy(buffer[i..][0..casted.len], casted);
                        return casted.len;
                    },
                    else => switch (Field.storage) {
                        .flag_optional, .enum_optional => {
                            return if (value.value) |v| setExtraField(buffer, i, Field.Value, v) else 0;
                        },
                        .flag_union => return switch (value.u) {
                            inline else => |x| setExtraField(buffer, i, @TypeOf(x), x),
                        },
                        .extended => @compileError("unimplemented"),
                        .flag_length_prefixed_list => {
                            const len: u32 = @intCast(value.slice.len);
                            if (len == 0) return 0; // Flag bit hides the length prefix.
                            buffer[i] = len;
                            const buf_len = len * @divExact(@sizeOf(Field.Elem), @sizeOf(u32));
                            @memcpy(buffer[i + 1 ..][0..buf_len], @as([]const u32, @ptrCast(value.slice)));
                            return 1 + buf_len;
                        },
                        .length_prefixed_list => {
                            const len: u32 = @intCast(value.slice.len);
                            buffer[i] = len;
                            const buf_len = len * @divExact(@sizeOf(Field.Elem), @sizeOf(u32));
                            @memcpy(buffer[i + 1 ..][0..buf_len], @as([]const u32, @ptrCast(value.slice)));
                            return 1 + buf_len;
                        },
                        .flag_list => {
                            const len: u32 = @intCast(value.slice.len);
                            @memcpy(buffer[i..][0..len], @as([]const u32, @ptrCast(value.slice)));
                            return len;
                        },
                        .multi_list => {
                            const len: u32 = @intCast(value.mal.len);
                            buffer[i] = len;
                            const field_names = @typeInfo(Field.Elem).@"struct".field_names;
                            inline for (0..field_names.len) |field_i| @memcpy(
                                buffer[i + 1 + field_i * len ..][0..len],
                                @as([]const u32, @ptrCast(value.mal.items(@enumFromInt(field_i)))),
                            );
                            return 1 + field_names.len * len;
                        },
                        .union_list => {
                            if (value.len == 0) return 0;
                            const Tag = @typeInfo(Field.Union).@"union".tag_type.?;
                            const slice_ptr: [*]const Field.Union = @ptrCast(@alignCast(value.data));
                            const slice = slice_ptr[0..value.len];
                            const meta_buffer = buffer[i..][0 .. (slice.len * @bitSizeOf(Field.Meta) + 31) / 32];
                            for (slice[0 .. slice.len - 1], 0..) |elem, elem_index| {
                                const union_tag: Tag = elem;
                                storeBits(u32, meta_buffer, elem_index * @bitSizeOf(Field.Meta), @as(Field.Meta, .{
                                    .tag = union_tag,
                                    .last = false,
                                }));
                            } else {
                                const elem_index = slice.len - 1;
                                const elem = slice[elem_index];
                                const union_tag: Tag = elem;
                                storeBits(u32, meta_buffer, elem_index * @bitSizeOf(Field.Meta), @as(Field.Meta, .{
                                    .tag = union_tag,
                                    .last = true,
                                }));
                            }
                            var total: usize = meta_buffer.len;
                            for (i + meta_buffer.len.., slice) |elem_index, src| switch (src) {
                                inline else => |x| total += setExtraField(buffer, elem_index, @TypeOf(x), x),
                            };
                            return total;
                        },
                    },
                },
                .@"extern" => {
                    const n = @divExact(@sizeOf(Field), @sizeOf(u32));
                    buffer[i..][0..n].* = @bitCast(value);
                    return n;
                },
            },
            else => @compileError("bad field type: " ++ @typeName(Field)),
        }
    }
};

fn IndexType(comptime T: type) type {
    return enum(u32) {
        _,

        pub fn get(this: @This(), c: *const Configuration) T {
            return extraData(c, T, @intFromEnum(this));
        }
    };
}

pub fn extraData(c: *const Configuration, comptime T: type, index: usize) T {
    var i: usize = index;
    return Storage.data(c.extra, &i, T);
}

pub const LoadFileError = Io.File.Reader.Error || Allocator.Error || error{EndOfStream};

pub fn loadFile(arena: Allocator, io: Io, file: Io.File) LoadFileError!Configuration {
    var buffer: [2000]u8 = undefined;
    var fr = file.reader(io, &buffer);
    return load(arena, &fr.interface) catch |err| switch (err) {
        error.ReadFailed => return fr.err.?,
        else => |e| return e,
    };
}

pub const LoadError = Io.Reader.Error || Allocator.Error;

pub fn load(arena: Allocator, reader: *Io.Reader) LoadError!Configuration {
    const header = try reader.takeStruct(Header, .native);
    const result: Configuration = .{
        .string_bytes = try arena.alloc(u8, header.string_bytes_len),
        .steps = try arena.alloc(Step, header.steps_len),
        .path_deps_sub = try arena.alloc(String, header.path_deps_len),
        .path_deps_base = try arena.alloc(Path.Base, header.path_deps_len),
        .unlazy_deps = try arena.alloc(String, header.unlazy_deps_len),
        .system_integrations = try arena.alloc(SystemIntegration, header.system_integrations_len),
        .available_options = try arena.alloc(AvailableOption, header.available_options_len),
        .search_prefixes = try arena.alloc(String, header.search_prefixes_len),
        .extra = try arena.alloc(u32, header.extra_len),
        .default_step = header.default_step,
        .generated_files_len = header.generated_files_len,
        .poisoned = header.flags.poisoned,
    };
    var vecs = [_][]u8{
        result.string_bytes,
        @ptrCast(result.steps),
        @ptrCast(result.path_deps_base),
        @ptrCast(result.path_deps_sub),
        @ptrCast(result.unlazy_deps),
        @ptrCast(result.system_integrations),
        @ptrCast(result.available_options),
        @ptrCast(result.search_prefixes),
        @ptrCast(result.extra),
    };
    try reader.readVecAll(&vecs);
    return result;
}

pub fn deinit(c: *Configuration, allocator: Allocator) void {
    allocator.free(c.string_bytes);
    allocator.free(c.steps);
    allocator.free(c.path_deps_sub);
    allocator.free(c.path_deps_base);
    allocator.free(c.unlazy_deps);
    allocator.free(c.system_integrations);
    allocator.free(c.available_options);
    allocator.free(c.search_prefixes);
    allocator.free(c.extra);
}

/// Loads bits using native endianness when `value` spans multiple bytes.
/// On big endian architectures, `bit_offset` uses MSb 0 bit numbering.
/// On little endian architectures, `bit_offset` uses LSb 0 bit numbering.
/// See `storeBits`.
pub fn loadBits(comptime Int: type, buffer: []const Int, bit_offset: usize, comptime Result: type) Result {
    const index = bit_offset / @bitSizeOf(Int);
    const small_bit_offset = bit_offset % @bitSizeOf(Int);
    const ResultInt = @Int(.unsigned, @bitSizeOf(Result));
    switch (native_endian) {
        .little => {
            const result: ResultInt = @truncate(buffer[index] >> @intCast(small_bit_offset));
            const available_bits = @bitSizeOf(Int) - small_bit_offset;
            if (available_bits >= @bitSizeOf(ResultInt)) return @bitCast(result);
            const missing_bits = @bitSizeOf(ResultInt) - available_bits;
            const upper: ResultInt = @truncate(buffer[index + 1] & ((@as(usize, 1) << @intCast(missing_bits)) - 1));
            return @bitCast(result | (upper << @intCast(available_bits)));
        },
        .big => {
            const available_bits = @bitSizeOf(Int) - small_bit_offset;
            if (available_bits >= @bitSizeOf(ResultInt)) {
                const shift = available_bits - @bitSizeOf(ResultInt);
                const result: ResultInt = @truncate(buffer[index] >> @intCast(shift));
                return @bitCast(result);
            }
            const mask = (@as(Int, 1) << @intCast(available_bits)) - 1;
            const result: ResultInt = @intCast(buffer[index] & mask);
            const missing_bits = @bitSizeOf(ResultInt) - available_bits;
            const lower: ResultInt = @truncate(buffer[index + 1] >> @intCast(@bitSizeOf(Int) - missing_bits));
            return @bitCast((result << @intCast(missing_bits)) | lower);
        },
    }
}

/// Store bits using native endianness when `value` spans multiple bytes.
/// On big endian architectures:
/// - For a given value, the bits of an earlier byte are more significant than the bits of subsequent bytes.
/// - `bit_offset` uses MSb 0 bit numbering.
/// On little endian architectures:
/// - For a given value, the bits of an earlier byte are less significant than the bits of subsequent bytes.
/// - `bit_offset` uses LSb 0 bit numbering.
pub fn storeBits(comptime Int: type, buffer: []Int, bit_offset: usize, value: anytype) void {
    const Value = @TypeOf(value);
    const ValueInt = @Int(.unsigned, @bitSizeOf(Value));
    const value_int: ValueInt = @bitCast(value);
    const index = bit_offset / @bitSizeOf(Int);
    const small_bit_offset = bit_offset % @bitSizeOf(Int);
    const available_bits = @bitSizeOf(Int) - small_bit_offset;
    if (available_bits >= @bitSizeOf(ValueInt)) {
        const shift = switch (native_endian) {
            .little => small_bit_offset,
            .big => available_bits - @bitSizeOf(ValueInt),
        };
        buffer[index] &= ~(((@as(Int, 1) << @intCast(@bitSizeOf(Value))) - 1) << @intCast(shift));
        buffer[index] |= @as(Int, value_int) << @intCast(shift);
    } else {
        const DoubleInt = @Int(.unsigned, @bitSizeOf(Int) * 2);
        const shift = switch (native_endian) {
            .little => small_bit_offset,
            .big => @bitSizeOf(DoubleInt) - small_bit_offset - @bitSizeOf(ValueInt),
        };
        const ptr: *align(@alignOf(Int)) DoubleInt = @ptrCast(buffer[index..][0..2]);
        ptr.* &= ~(((@as(DoubleInt, 1) << @intCast(@bitSizeOf(Value))) - 1) << @intCast(shift));
        ptr.* |= @as(DoubleInt, value_int) << @intCast(shift);
    }
}

test "loadBits and storeBits" {
    var buffer: [2]u32 = switch (native_endian) {
        .little => .{
            //──┐ 0b100011 (end)     ┌─┐ 0b100
            0b01111111000000001111111100000000,
            //            n <── bit offset 0 ┘
            //                             ┌── 0b100011 (start)
            0b11111111000000001111111100000100,
        },
        .big => .{
            //      ┌─┐ 0b100              ┌── 0b100011 (start)
            0b11111110000000001111111100000100,
            //└ bit offset 0 ──> n
            //──┐ 0b100011 (end)
            0b01111111000000001111111100000000,
        },
    };

    try std.testing.expectEqual(0b100, loadBits(u32, &buffer, 6, u3));
    try std.testing.expectEqual(0b100011, loadBits(u32, &buffer, 29, u6));

    storeBits(u32, &buffer, 0, @as(u1, 0b0));
    storeBits(u32, &buffer, 6, @as(u3, 0b010));
    storeBits(u32, &buffer, 29, @as(u6, 0b010110));
    storeBits(u32, &buffer, 40, @as(u17, 0b01110110011111110));

    try std.testing.expectEqual(0b0, loadBits(u32, &buffer, 0, u1));
    try std.testing.expectEqual(0b010, loadBits(u32, &buffer, 6, u3));
    try std.testing.expectEqual(0b010110, loadBits(u32, &buffer, 29, u6));
    try std.testing.expectEqual(0b01110110011111110, loadBits(u32, &buffer, 40, u17));

    // Test roundtripping of size/offset combinations
    inline for (1..32) |value_size| {
        for (0..64) |bit_offset| {
            if (value_size + bit_offset > @bitSizeOf(@TypeOf(buffer))) continue;

            buffer = .{ 0, 0 };

            const Value = @Int(.unsigned, value_size);
            const value: Value = @intCast((@as(u32, 1) << @intCast(@bitSizeOf(Value))) - 1);
            storeBits(u32, &buffer, bit_offset, value);
            std.testing.expectEqual(value, loadBits(u32, &buffer, bit_offset, Value)) catch |err| {
                std.debug.print("value size: {} bit offset: {}\n", .{ value_size, bit_offset });
                std.debug.print("buffer: {b:0>32} {b:0>32}\n", .{ buffer[0], buffer[1] });
                return err;
            };
        }
    }
}

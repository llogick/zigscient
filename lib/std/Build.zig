const Build = @This();

const builtin = @import("builtin");

const std = @import("std.zig");
const Io = std.Io;
const fs = std.fs;
const mem = std.mem;
const panic = std.debug.panic;
const assert = std.debug.assert;
const log = std.log;
const StringHashMap = std.StringHashMap;
const Allocator = std.mem.Allocator;
const Target = std.Target;
const process = std.process;
const File = std.Io.File;
const Sha256 = std.crypto.hash.sha2.Sha256;
const ArrayList = std.ArrayList;

pub const Cache = @import("Build/Cache.zig");
pub const Step = @import("Build/Step.zig");
pub const Module = @import("Build/Module.zig");
pub const abi = @import("Build/abi.zig");
/// The serialized output of configure phase ingested by make phase.
pub const Configuration = @import("Build/Configuration.zig");

/// Shared state among all Build instances.
graph: *Graph,
install_tls: Step.TopLevel,
uninstall_tls: Step.TopLevel,
allocator: Allocator,
user_input_options: UserInputOptionsMap,
available_options_map: std.array_hash_map.String(AvailableOption) = .empty,
invalid_user_input: bool,
default_step: *Step,
top_level_steps: std.array_hash_map.String(*Step.TopLevel),
/// Path to the directory containing build.zig.
root: Cache.Path,
debug_log_scopes: []const []const u8 = &.{},
/// Number of stack frames captured when a `StackTrace` is recorded for debug purposes,
/// in particular at `Step` creation.
/// Set to 0 to disable stack collection.
debug_stack_frames_count: u8 = 8,

/// Experimental. Use system Darling installation to run cross compiled macOS build artifacts.
enable_darling: bool = false,
/// Use system QEMU installation to run cross compiled foreign architecture build artifacts.
enable_qemu: bool = false,
/// Darwin. Use Rosetta to run x86_64 macOS build artifacts on arm64 macOS.
enable_rosetta: bool = false,
/// Use system Wasmtime installation to run cross compiled wasm/wasi build artifacts.
enable_wasmtime: bool = false,
/// Use system Wine installation to run cross compiled Windows build artifacts.
enable_wine: bool = false,

dep_prefix: []const u8 = "",

modules: std.array_hash_map.String(*Module),

named_writefiles: std.array_hash_map.String(*Step.WriteFile),
named_lazy_paths: std.array_hash_map.String(LazyPath),
/// The hash of this instance's package. `""` means that this is the root package.
pkg_hash: []const u8,
/// A mapping from dependency names to package hashes.
available_deps: AvailableDeps,

pub const ReleaseMode = enum {
    off,
    any,
    fast,
    safe,
    small,
};

/// Shared state among all Build instances.
/// Settings that are here rather than in Build are not configurable per-package.
pub const Graph = struct {
    io: Io,
    /// Process lifetime.
    arena: Allocator,
    system_integration_options: std.array_hash_map.String(SystemLibraryMode) = .empty,
    system_package_mode: bool = false,
    zig_exe: []const u8,
    environ_map: process.Environ.Map,
    needed_lazy_dependencies: std.array_hash_map.String(void) = .empty,
    /// Information about the native target. Computed before build() is invoked.
    host: ResolvedTarget,
    dependency_cache: InitializedDepMap = .empty,
    allow_so_scripts: ?bool = null,
    time_report: bool = false,
    verbose: bool = false,
    /// Similar to the `Io.Terminal.Mode` returned by `Io.lockStderr`, but also
    /// respects the '--color' flag.
    stderr_mode: ?Io.Terminal.Mode = null,
    release_mode: ReleaseMode = .off,

    /// Indexes correspond to `Configuration.GeneratedFileIndex`.
    generated_files: std.ArrayList(*Step),
    wip_configuration: Configuration.Wip,

    cache_poison: CachePoison = .pure,
    /// Observing this data causes cache poisoning. See `CachePoison`.
    search_prefixes: std.ArrayList([]const u8) = .empty,

    /// If the cache is poisoned means that the **configure logic** had side
    /// effects, or otherwise did something that could not be tracked by the
    /// cache system.
    ///
    /// This is not to be confused with whether individual steps may have side
    /// effects when being evaluated; it has to do with the logic inside build.zig
    /// itself. For example, a `Run` step that prints "hello world" has side
    /// effects *at make time* and therefore does not warrant setting this flag,
    /// while checking for the existence of `scdoc` *at configure time* in order to
    /// choose the default value for a configuration option does.
    ///
    /// Keeping the cache pure will make `zig build` faster, bypassing the
    /// configurer process when identical configuration would be generated.
    ///
    /// When the cache is poisoned, the maker process will delete the build
    /// configuration file upon ingesting it since it cannot be reused.
    pub const CachePoison = enum {
        pure,
        poisoned,
        /// Indicates the user would like to see a stack trace if the cache
        /// would become poisoned.
        disallowed,
        /// Indicates the user would like to ignore the cache being poisoned
        /// and cache anyway, opting into cache hits on stale configuration.
        ignored,
    };

    pub fn addGeneratedFile(graph: *Graph, owner: *Step) Configuration.GeneratedFileIndex {
        graph.generated_files.append(graph.arena, owner) catch @panic("OOM");
        return @enumFromInt(graph.generated_files.items.len - 1);
    }

    pub fn dupeString(graph: *const Graph, bytes: []const u8) []const u8 {
        return graph.arena.dupe(u8, bytes) catch @panic("OOM");
    }

    pub fn dupePath(graph: *const Graph, bytes: []const u8) []const u8 {
        return dupePathInner(graph.arena, bytes);
    }

    fn dupePathInner(arena: Allocator, bytes: []const u8) []const u8 {
        if (builtin.os.tag != .windows) return arena.dupe(u8, bytes) catch @panic("OOM");
        const the_copy = arena.dupe(u8, bytes) catch @panic("OOM");
        mem.replaceScalar(u8, the_copy, '/', '\\');
        return the_copy;
    }

    pub fn dupeStrings(graph: *const Graph, strings: []const []const u8) []const []const u8 {
        const array = graph.alloc([]const u8, strings.len);
        for (array, strings) |*dest, source| dest.* = dupeString(graph, source);
        return array;
    }

    /// An absolute path or a path relative to the current working directory of
    /// the build runner process.
    ///
    /// Use of this function indicates a dependency on the host system.
    pub fn cwdRelativePath(graph: *Graph, sub_path: []const u8) LazyPath {
        return @This().path(graph, .cwd, sub_path);
    }

    /// A path whose components and contents are known at some point during
    /// `Step` resolution, relative to the provided base directory.
    pub fn path(graph: *Graph, base: Configuration.Path.Base, sub_path: []const u8) LazyPath {
        return .{ .relative = .{
            .base = base,
            .sub_path = @This().dupePath(graph, sub_path),
        } };
    }

    /// Allocates using the global process arena, failing the build on
    /// allocation failure.
    pub fn alloc(graph: *const Graph, comptime T: type, n: usize) []T {
        return graph.arena.allocAdvancedWithRetAddr(T, null, n, @returnAddress()) catch @panic("OOM");
    }

    /// Allocates using the global process arena, failing the build on
    /// allocation failure.
    pub fn create(graph: *const Graph, comptime T: type) *T {
        return @ptrCast(graph.arena.allocBytesAligned(.of(T), @sizeOf(T), @returnAddress()) catch @panic("OOM"));
    }

    pub fn addBytesList(graph: *Graph, bytes_list: []const []const u8) []const Configuration.Bytes {
        const result = graph.alloc(Configuration.Bytes, bytes_list.len);
        for (result, bytes_list) |*d, s| d.* = addBytes(graph, s);
        return result;
    }

    pub fn addBytes(graph: *Graph, bytes: []const u8) Configuration.Bytes {
        const wc = &graph.wip_configuration;
        return wc.addBytes(bytes) catch @panic("OOM");
    }

    pub fn addString(graph: *Graph, bytes: []const u8) Configuration.String {
        const wc = &graph.wip_configuration;
        return wc.addString(bytes) catch @panic("OOM");
    }

    /// Indicates that the **configure logic** had side effects, or otherwise
    /// did something that could not be tracked by the cache system.
    ///
    /// See `CachePoison` documentation for more details.
    pub fn poisonCache(graph: *Graph) void {
        switch (graph.cache_poison) {
            .pure => graph.cache_poison = .poisoned,
            .poisoned => return,
            .disallowed => @panic("cache poisoned"),
            .ignored => log.warn("ignoring cache poisoning", .{}),
        }
    }
};

const AvailableDeps = []const struct { []const u8, []const u8 };

pub const SystemLibraryMode = enum {
    /// User asked for the library to be disabled.
    /// The build runner has not confirmed whether the setting is recognized yet.
    user_disabled,
    /// User asked for the library to be enabled.
    /// The build runner has not confirmed whether the setting is recognized yet.
    user_enabled,
    /// The build runner has confirmed that this setting is recognized.
    /// System integration with this library has been resolved to off.
    declared_disabled,
    /// The build runner has confirmed that this setting is recognized.
    /// System integration with this library has been resolved to on.
    declared_enabled,
};

const InitializedDepMap = std.HashMapUnmanaged(InitializedDepKey, *Dependency, InitializedDepContext, std.hash_map.default_max_load_percentage);
const InitializedDepKey = struct {
    build_root_string: []const u8,
    user_input_options: UserInputOptionsMap,
};

const InitializedDepContext = struct {
    allocator: Allocator,

    pub fn hash(ctx: @This(), k: InitializedDepKey) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(k.build_root_string);
        hashUserInputOptionsMap(ctx.allocator, k.user_input_options, &hasher);
        return hasher.final();
    }

    pub fn eql(_: @This(), lhs: InitializedDepKey, rhs: InitializedDepKey) bool {
        if (!std.mem.eql(u8, lhs.build_root_string, rhs.build_root_string))
            return false;

        if (lhs.user_input_options.count() != rhs.user_input_options.count())
            return false;

        var it = lhs.user_input_options.iterator();
        while (it.next()) |lhs_entry| {
            const rhs_value = rhs.user_input_options.get(lhs_entry.key_ptr.*) orelse return false;
            if (!userValuesAreSame(lhs_entry.value_ptr.*.value, rhs_value.value))
                return false;
        }

        return true;
    }
};

const UserInputOptionsMap = StringHashMap(UserInputOption);

const AvailableOption = struct {
    name: []const u8,
    type_id: Configuration.AvailableOption.Type,
    description: []const u8,
    /// If the `type_id` is `enum` or `enum_list` this provides the list of enum options
    enum_options: ?[]const []const u8,
};

const UserInputOption = struct {
    name: []const u8,
    value: UserValue,
    used: bool,
};

const UserValue = union(enum) {
    flag: void,
    scalar: []const u8,
    list: std.array_list.Managed([]const u8),
    map: StringHashMap(*const UserValue),
    lazy_path: LazyPath,
    lazy_path_list: std.array_list.Managed(LazyPath),
};

pub fn create(
    graph: *Graph,
    root: Cache.Path,
    available_deps: AvailableDeps,
) error{OutOfMemory}!*Build {
    const arena = graph.arena;

    const b = try arena.create(Build);
    b.* = .{
        .graph = graph,
        .root = root,
        .invalid_user_input = false,
        .allocator = arena,
        .user_input_options = UserInputOptionsMap.init(arena),
        .top_level_steps = .{},
        .default_step = undefined,
        .install_tls = .{
            .step = .init(.{
                .tag = .top_level,
                .name = "install",
                .owner = b,
            }),
            .description = "Copy build artifacts to prefix path",
        },
        .uninstall_tls = .{
            .step = .init(.{
                .tag = .top_level,
                .name = "uninstall",
                .owner = b,
            }),
            .description = "Remove build artifacts from prefix path",
        },
        .modules = .empty,
        .named_writefiles = .empty,
        .named_lazy_paths = .empty,
        .pkg_hash = "",
        .available_deps = available_deps,
    };
    try b.top_level_steps.put(arena, b.install_tls.step.name, &b.install_tls);
    try b.top_level_steps.put(arena, b.uninstall_tls.step.name, &b.uninstall_tls);
    b.default_step = &b.install_tls.step;
    return b;
}

fn createChild(
    parent: *Build,
    dep_name: []const u8,
    root: Cache.Path,
    pkg_hash: []const u8,
    pkg_deps: AvailableDeps,
    user_input_options: UserInputOptionsMap,
) error{OutOfMemory}!*Build {
    const arena = parent.graph.arena;
    const child = try arena.create(Build);
    child.* = .{
        .graph = parent.graph,
        .root = root,
        .allocator = arena,
        .install_tls = .{
            .step = .init(.{
                .tag = .top_level,
                .name = "install",
                .owner = child,
            }),
            .description = "Copy build artifacts to prefix path",
        },
        .uninstall_tls = .{
            .step = .init(.{
                .tag = .top_level,
                .name = "uninstall",
                .owner = child,
            }),
            .description = "Remove build artifacts from prefix path",
        },
        .user_input_options = user_input_options,
        .invalid_user_input = false,
        .default_step = undefined,
        .top_level_steps = .{},
        .debug_log_scopes = parent.debug_log_scopes,
        .enable_darling = parent.enable_darling,
        .enable_qemu = parent.enable_qemu,
        .enable_rosetta = parent.enable_rosetta,
        .enable_wasmtime = parent.enable_wasmtime,
        .enable_wine = parent.enable_wine,
        .dep_prefix = parent.fmt("{s}{s}.", .{ parent.dep_prefix, dep_name }),
        .modules = .empty,
        .named_writefiles = .empty,
        .named_lazy_paths = .empty,
        .pkg_hash = pkg_hash,
        .available_deps = pkg_deps,
    };
    try child.top_level_steps.put(arena, child.install_tls.step.name, &child.install_tls);
    try child.top_level_steps.put(arena, child.uninstall_tls.step.name, &child.uninstall_tls);
    child.default_step = &child.install_tls.step;
    return child;
}

fn userInputOptionsFromArgs(arena: Allocator, args: anytype) UserInputOptionsMap {
    var map = UserInputOptionsMap.init(arena);
    const args_info = @typeInfo(@TypeOf(args)).@"struct";
    inline for (args_info.field_names, args_info.field_types) |field_name, field_type| {
        if (field_type == @TypeOf(null)) continue;
        addUserInputOptionFromArg(arena, &map, field_name, field_type, @field(args, field_name));
    }
    return map;
}

fn addUserInputOptionFromArg(
    arena: Allocator,
    map: *UserInputOptionsMap,
    field_name: [:0]const u8,
    comptime T: type,
    /// If null, the value won't be added, but `T` will still be type-checked.
    maybe_value: ?T,
) void {
    switch (T) {
        Target.Query => return if (maybe_value) |v| {
            map.put(field_name, .{
                .name = field_name,
                .value = .{ .scalar = v.zigTriple(arena) catch @panic("OOM") },
                .used = false,
            }) catch @panic("OOM");
            map.put("cpu", .{
                .name = "cpu",
                .value = .{ .scalar = v.serializeCpuAlloc(arena) catch @panic("OOM") },
                .used = false,
            }) catch @panic("OOM");
        },
        ResolvedTarget => return if (maybe_value) |v| {
            map.put(field_name, .{
                .name = field_name,
                .value = .{ .scalar = v.query.zigTriple(arena) catch @panic("OOM") },
                .used = false,
            }) catch @panic("OOM");
            map.put("cpu", .{
                .name = "cpu",
                .value = .{ .scalar = v.query.serializeCpuAlloc(arena) catch @panic("OOM") },
                .used = false,
            }) catch @panic("OOM");
        },
        std.zig.BuildId => return if (maybe_value) |v| {
            map.put(field_name, .{
                .name = field_name,
                .value = .{ .scalar = std.fmt.allocPrint(arena, "{f}", .{v}) catch @panic("OOM") },
                .used = false,
            }) catch @panic("OOM");
        },
        LazyPath => return if (maybe_value) |v| {
            map.put(field_name, .{
                .name = field_name,
                .value = .{ .lazy_path = v.dupeInner(arena) },
                .used = false,
            }) catch @panic("OOM");
        },
        []const LazyPath => return if (maybe_value) |v| {
            var list = std.array_list.Managed(LazyPath).initCapacity(arena, v.len) catch @panic("OOM");
            for (v) |lp| list.appendAssumeCapacity(lp.dupeInner(arena));
            map.put(field_name, .{
                .name = field_name,
                .value = .{ .lazy_path_list = list },
                .used = false,
            }) catch @panic("OOM");
        },
        []const u8 => return if (maybe_value) |v| {
            map.put(field_name, .{
                .name = field_name,
                .value = .{ .scalar = arena.dupe(u8, v) catch @panic("OOM") },
                .used = false,
            }) catch @panic("OOM");
        },
        []const []const u8 => return if (maybe_value) |v| {
            var list = std.array_list.Managed([]const u8).initCapacity(arena, v.len) catch @panic("OOM");
            for (v) |s| list.appendAssumeCapacity(arena.dupe(u8, s) catch @panic("OOM"));
            map.put(field_name, .{
                .name = field_name,
                .value = .{ .list = list },
                .used = false,
            }) catch @panic("OOM");
        },
        else => switch (@typeInfo(T)) {
            .bool => return if (maybe_value) |v| {
                map.put(field_name, .{
                    .name = field_name,
                    .value = .{ .scalar = if (v) "true" else "false" },
                    .used = false,
                }) catch @panic("OOM");
            },
            .@"enum", .enum_literal => return if (maybe_value) |v| {
                map.put(field_name, .{
                    .name = field_name,
                    .value = .{ .scalar = @tagName(v) },
                    .used = false,
                }) catch @panic("OOM");
            },
            .comptime_int, .int => return if (maybe_value) |v| {
                map.put(field_name, .{
                    .name = field_name,
                    .value = .{ .scalar = std.fmt.allocPrint(arena, "{d}", .{v}) catch @panic("OOM") },
                    .used = false,
                }) catch @panic("OOM");
            },
            .comptime_float, .float => return if (maybe_value) |v| {
                map.put(field_name, .{
                    .name = field_name,
                    .value = .{ .scalar = std.fmt.allocPrint(arena, "{x}", .{v}) catch @panic("OOM") },
                    .used = false,
                }) catch @panic("OOM");
            },
            .pointer => |ptr_info| switch (ptr_info.size) {
                .one => switch (@typeInfo(ptr_info.child)) {
                    .array => |array_info| {
                        addUserInputOptionFromArg(
                            arena,
                            map,
                            field_name,
                            @Pointer(.slice, .{ .@"const" = true }, array_info.child, null),
                            maybe_value orelse null,
                        );
                        return;
                    },
                    else => {},
                },
                .slice => switch (@typeInfo(ptr_info.child)) {
                    .@"enum" => return if (maybe_value) |v| {
                        var list = std.array_list.Managed([]const u8).initCapacity(arena, v.len) catch @panic("OOM");
                        for (v) |tag| list.appendAssumeCapacity(@tagName(tag));
                        map.put(field_name, .{
                            .name = field_name,
                            .value = .{ .list = list },
                            .used = false,
                        }) catch @panic("OOM");
                    },
                    else => {
                        addUserInputOptionFromArg(
                            arena,
                            map,
                            field_name,
                            @Pointer(ptr_info.size, .{ .@"const" = true }, ptr_info.child, null),
                            maybe_value orelse null,
                        );
                        return;
                    },
                },
                else => {},
            },
            .null => unreachable,
            .optional => |info| switch (@typeInfo(info.child)) {
                .optional => {},
                else => {
                    addUserInputOptionFromArg(
                        arena,
                        map,
                        field_name,
                        info.child,
                        maybe_value orelse null,
                    );
                    return;
                },
            },
            else => {},
        },
    }
    @compileError("option '" ++ field_name ++ "' has unsupported type: " ++ @typeName(T));
}

const OrderedUserValue = union(enum) {
    flag: void,
    scalar: []const u8,
    list: std.array_list.Managed([]const u8),
    map: std.array_list.Managed(Pair),
    lazy_path: LazyPath,
    lazy_path_list: std.array_list.Managed(LazyPath),

    const Pair = struct {
        name: []const u8,
        value: OrderedUserValue,
        fn lessThan(_: void, lhs: Pair, rhs: Pair) bool {
            return std.ascii.lessThanIgnoreCase(lhs.name, rhs.name);
        }
    };

    fn hash(val: OrderedUserValue, hasher: *std.hash.Wyhash) void {
        hasher.update(&std.mem.toBytes(std.meta.activeTag(val)));
        switch (val) {
            .flag => {},
            .scalar => |scalar| hasher.update(scalar),
            // lists are already ordered
            .list => |list| for (list.items) |list_entry|
                hasher.update(list_entry),
            .map => |map| for (map.items) |map_entry| {
                hasher.update(map_entry.name);
                map_entry.value.hash(hasher);
            },
            .lazy_path => |lp| hashLazyPath(lp, hasher),
            .lazy_path_list => |lp_list| for (lp_list.items) |lp| {
                hashLazyPath(lp, hasher);
            },
        }
    }

    fn hashLazyPath(lp: LazyPath, hasher: *std.hash.Wyhash) void {
        switch (lp) {
            .src_path => |sp| {
                hasher.update(sp.owner.pkg_hash);
                hasher.update(sp.sub_path);
            },
            .generated => |gen| {
                hasher.update(@ptrCast(&gen.index));
                hasher.update(@ptrCast(&gen.up));
                hasher.update(gen.sub_path);
            },
            .cwd_relative => |rel_path| {
                hasher.update(rel_path);
            },
            .relative => |r| {
                hasher.update(@ptrCast(&r.base));
                hasher.update(@ptrCast(&r.sub_path));
            },
            .dependency => |dep| {
                hasher.update(dep.dependency.builder.pkg_hash);
                hasher.update(dep.sub_path);
            },
        }
    }

    fn mapFromUnordered(allocator: Allocator, unordered: std.StringHashMap(*const UserValue)) std.array_list.Managed(Pair) {
        var ordered = std.array_list.Managed(Pair).init(allocator);
        var it = unordered.iterator();
        while (it.next()) |entry| {
            ordered.append(.{
                .name = entry.key_ptr.*,
                .value = OrderedUserValue.fromUnordered(allocator, entry.value_ptr.*.*),
            }) catch @panic("OOM");
        }

        std.mem.sortUnstable(Pair, ordered.items, {}, Pair.lessThan);
        return ordered;
    }

    fn fromUnordered(allocator: Allocator, unordered: UserValue) OrderedUserValue {
        return switch (unordered) {
            .flag => .{ .flag = {} },
            .scalar => |scalar| .{ .scalar = scalar },
            .list => |list| .{ .list = list },
            .map => |map| .{ .map = OrderedUserValue.mapFromUnordered(allocator, map) },
            .lazy_path => |lp| .{ .lazy_path = lp },
            .lazy_path_list => |list| .{ .lazy_path_list = list },
        };
    }
};

const OrderedUserInputOption = struct {
    name: []const u8,
    value: OrderedUserValue,
    used: bool,

    fn hash(opt: OrderedUserInputOption, hasher: *std.hash.Wyhash) void {
        hasher.update(opt.name);
        opt.value.hash(hasher);
    }

    fn fromUnordered(allocator: Allocator, user_input_option: UserInputOption) OrderedUserInputOption {
        return OrderedUserInputOption{
            .name = user_input_option.name,
            .used = user_input_option.used,
            .value = OrderedUserValue.fromUnordered(allocator, user_input_option.value),
        };
    }

    fn lessThan(_: void, lhs: OrderedUserInputOption, rhs: OrderedUserInputOption) bool {
        return std.ascii.lessThanIgnoreCase(lhs.name, rhs.name);
    }
};

// The hash should be consistent with the same values given a different order.
// This function takes a user input map, orders it, then hashes the contents.
fn hashUserInputOptionsMap(allocator: Allocator, user_input_options: UserInputOptionsMap, hasher: *std.hash.Wyhash) void {
    var ordered = std.array_list.Managed(OrderedUserInputOption).init(allocator);
    var it = user_input_options.iterator();
    while (it.next()) |entry|
        ordered.append(OrderedUserInputOption.fromUnordered(allocator, entry.value_ptr.*)) catch @panic("OOM");

    std.mem.sortUnstable(OrderedUserInputOption, ordered.items, {}, OrderedUserInputOption.lessThan);

    // juice it
    for (ordered.items) |user_option|
        user_option.hash(hasher);
}

/// Create a set of key-value pairs that can be converted into a Zig source
/// file and then inserted into a Zig compilation's module table for importing.
/// In other words, this provides a way to expose build.zig values to Zig
/// source code with `@import`.
/// Related: `Module.addOptions`.
pub fn addOptions(b: *Build) *Step.Options {
    return Step.Options.create(b);
}

pub const ExecutableOptions = struct {
    name: []const u8,
    root_module: *Module,
    version: ?std.SemanticVersion = null,
    linkage: ?std.builtin.LinkMode = null,
    max_rss: u64 = 0,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    zig_lib_dir: ?LazyPath = null,
    /// Embed a `.manifest` file in the compilation if the object format supports it.
    /// https://learn.microsoft.com/en-us/windows/win32/sbscs/manifest-files-reference
    /// Manifest files must have the extension `.manifest`.
    /// Can be set regardless of target. The `.manifest` file will be ignored
    /// if the target object format does not support embedded manifests.
    win32_manifest: ?LazyPath = null,
};

pub fn addExecutable(b: *Build, options: ExecutableOptions) *Step.Compile {
    return .create(b, .{
        .name = options.name,
        .root_module = options.root_module,
        .version = options.version,
        .kind = .exe,
        .linkage = options.linkage,
        .max_rss = options.max_rss,
        .use_llvm = options.use_llvm,
        .use_lld = options.use_lld,
        .zig_lib_dir = options.zig_lib_dir,
        .win32_manifest = options.win32_manifest,
    });
}

pub const ObjectOptions = struct {
    name: []const u8,
    root_module: *Module,
    max_rss: u64 = 0,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    zig_lib_dir: ?LazyPath = null,
};

pub fn addObject(b: *Build, options: ObjectOptions) *Step.Compile {
    return .create(b, .{
        .name = options.name,
        .root_module = options.root_module,
        .kind = .obj,
        .max_rss = options.max_rss,
        .use_llvm = options.use_llvm,
        .use_lld = options.use_lld,
        .zig_lib_dir = options.zig_lib_dir,
    });
}

pub const LibraryOptions = struct {
    linkage: std.builtin.LinkMode = .static,
    name: []const u8,
    root_module: *Module,
    version: ?std.SemanticVersion = null,
    max_rss: u64 = 0,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    zig_lib_dir: ?LazyPath = null,
    /// Embed a `.manifest` file in the compilation if the object format supports it.
    /// https://learn.microsoft.com/en-us/windows/win32/sbscs/manifest-files-reference
    /// Manifest files must have the extension `.manifest`.
    /// Can be set regardless of target. The `.manifest` file will be ignored
    /// if the target object format does not support embedded manifests.
    win32_manifest: ?LazyPath = null,
    /// Win32 module definition file (.def).
    win32_module_definition: ?LazyPath = null,
};

pub fn addLibrary(b: *Build, options: LibraryOptions) *Step.Compile {
    return .create(b, .{
        .name = options.name,
        .root_module = options.root_module,
        .kind = .lib,
        .linkage = options.linkage,
        .version = options.version,
        .max_rss = options.max_rss,
        .use_llvm = options.use_llvm,
        .use_lld = options.use_lld,
        .zig_lib_dir = options.zig_lib_dir,
        .win32_manifest = options.win32_manifest,
        .win32_module_definition = options.win32_module_definition,
    });
}

pub const TestOptions = struct {
    name: []const u8 = "test",
    root_module: *Module,
    max_rss: u64 = 0,
    filters: []const []const u8 = &.{},
    test_runner: ?Step.Compile.TestRunner = null,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    zig_lib_dir: ?LazyPath = null,
    /// Emits an object file instead of a test binary.
    /// The object must be linked separately.
    /// Usually used in conjunction with a custom `test_runner`.
    emit_object: bool = false,
};

/// Creates an executable containing unit tests.
///
/// Equivalent to running the command `zig test --test-no-exec ...`.
///
/// **This step does not run the unit tests**. Typically, the result of this
/// function will be passed to `addRunArtifact`, creating a `Step.Run`. These
/// two steps are separated because they are independently configured and
/// cached.
pub fn addTest(b: *Build, options: TestOptions) *Step.Compile {
    return .create(b, .{
        .name = options.name,
        .kind = if (options.emit_object) .test_obj else .@"test",
        .root_module = options.root_module,
        .max_rss = options.max_rss,
        .filters = b.dupeStrings(options.filters),
        .test_runner = options.test_runner,
        .use_llvm = options.use_llvm,
        .use_lld = options.use_lld,
        .zig_lib_dir = options.zig_lib_dir,
    });
}

pub const AssemblyOptions = struct {
    name: []const u8,
    source_file: LazyPath,
    /// To choose the same computer as the one building the package, pass the
    /// `host` field of the package's `Build` instance.
    target: ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    max_rss: u64 = 0,
    zig_lib_dir: ?LazyPath = null,
};

/// This function creates a module and adds it to the package's module set, making
/// it available to other packages which depend on this one.
/// `createModule` can be used instead to create a private module.
pub fn addModule(b: *Build, name: []const u8, options: Module.CreateOptions) *Module {
    const graph = b.graph;
    const arena = graph.arena;
    const module = Module.create(b, options);
    const gop = b.modules.getOrPutValue(
        arena,
        graph.dupeString(name),
        module,
    ) catch @panic("OOM");
    if (gop.found_existing) {
        panic(
            "A module with the name '{s}' has already been added to the package. Consider creating a private module with std.Build.createModule",
            .{name},
        );
    }
    return module;
}

/// This function creates a private module, to be used by the current package,
/// but not exposed to other packages depending on this one.
/// `addModule` can be used instead to create a public module.
pub fn createModule(b: *Build, options: Module.CreateOptions) *Module {
    return Module.create(b, options);
}

/// Creates a step that executes a process on the host system.
///
/// `argv` is one or more command line arguments passed to the executed
/// process. The first element is the name of the executable to run. More
/// command line arguments can be added with methods of `Step.Run`, such as:
/// * `Step.Run.addArgs`
/// * `Step.Run.addArtifactArg`
/// * `Step.Run.addFileArg`
/// * `Step.Run.addOutputFileArg`
///
/// This function introduces a system dependency, compromising reproducibility
/// and making it more difficult to set up one's computer in order to build the
/// project from source.
///
/// See also:
/// * `addRunArtifact`
/// * `addRunFile`
pub fn addSystemCommand(b: *Build, argv: []const []const u8) *Step.Run {
    assert(argv.len >= 1);
    const run_step = Step.Run.create(b, b.fmt("run {s}", .{argv[0]}));
    run_step.addArgs(argv);
    return run_step;
}

/// Creates a `Step.Run` with an executable built with `addExecutable`.
/// Add command line arguments with methods of `Step.Run`.
///
/// It doesn't have to target the host. In some cases cross-compiled binaries
/// can even be executed.
///
/// This is declarative; it constructs a build step that may or may not be run
/// depending on the options provided by the user to the build command.
///
/// See also:
/// * `addSystemCommand`
/// * `addRunFile`
pub fn addRunArtifact(b: *Build, exe: *Step.Compile) *Step.Run {
    // Avoid the common case of the step name looking like "run test test".
    const step_name = if (exe.kind.isTest() and mem.eql(u8, exe.name, "test"))
        b.fmt("run {t}", .{exe.kind})
    else
        b.fmt("run {t} {s}", .{ exe.kind, exe.name });

    const run_step = Step.Run.create(b, step_name);
    run_step.producer = exe;
    if (exe.kind == .@"test") {
        if (exe.exec_cmd_args) |exec_cmd_args| {
            for (exec_cmd_args) |cmd_arg| {
                if (cmd_arg) |arg| {
                    run_step.addArg(arg);
                } else {
                    run_step.addArtifactArg(exe);
                }
            }
        } else {
            run_step.addArtifactArg(exe);
        }

        const test_server_mode: bool = s: {
            if (exe.test_runner) |r| break :s r.mode == .server;
            if (exe.use_llvm == false) {
                // The default test runner does not use the server protocol if the selected backend
                // is too immature to support it. Keep this logic in sync with `need_simple` in the
                // default test runner implementation.
                switch (exe.rootModuleTarget().cpu.arch) {
                    // stage2_aarch64
                    .aarch64,
                    .aarch64_be,
                    // stage2_powerpc
                    .powerpc,
                    .powerpcle,
                    .powerpc64,
                    .powerpc64le,
                    // stage2_riscv64
                    .riscv64,
                    => break :s false,

                    else => {},
                }
            }
            break :s true;
        };
        if (test_server_mode) {
            run_step.enableTestRunnerMode();
        } else if (exe.test_runner == null) {
            // If a test runner does not use the `std.zig.Server` protocol, it can instead
            // communicate failure via its exit code.
            run_step.expectExitCode(0);
        }
    } else {
        run_step.addArtifactArg(exe);
    }

    return run_step;
}

/// Creates a step that executes the provided file.
///
/// Add more command line arguments via methods of `Step.Run`.
///
/// See also:
/// * `addSystemCommand`
/// * `addRunArtifact`
pub fn addRunFile(b: *Build, executable: LazyPath) *Step.Run {
    const run_step = Step.Run.create(b, b.fmt("run {f}", .{executable}));
    run_step.addFileArg(executable);
    return run_step;
}

/// Using the `values` provided, produces a C header file, possibly based on a
/// template input file (e.g. config.h.in).
/// When an input template file is provided, this function will fail the build
/// when an option not found in the input file is provided in `values`, and
/// when an option found in the input file is missing from `values`.
pub fn addConfigHeader(
    b: *Build,
    options: Step.ConfigHeader.Options,
    values: anytype,
) *Step.ConfigHeader {
    var options_copy = options;
    if (options_copy.first_ret_addr == null)
        options_copy.first_ret_addr = @returnAddress();

    const config_header_step = Step.ConfigHeader.create(b, options_copy);
    config_header_step.addValues(values);
    return config_header_step;
}

pub fn dupe(b: *Build, bytes: []const u8) []const u8 {
    return b.graph.dupeString(bytes);
}

/// Deprecated, call `Graph.dupeStrings` instead.
pub fn dupeStrings(b: *Build, strings: []const []const u8) []const []const u8 {
    return b.graph.dupeStrings(strings);
}

/// Deprecated, call `Graph.dupePath` instead.
pub fn dupePath(b: *Build, bytes: []const u8) []const u8 {
    return b.graph.dupePath(bytes);
}

pub fn addWriteFile(b: *Build, file_path: []const u8, data: []const u8) *Step.WriteFile {
    const write_file_step = b.addWriteFiles();
    _ = write_file_step.add(file_path, data);
    return write_file_step;
}

pub fn addNamedWriteFiles(b: *Build, name: []const u8) *Step.WriteFile {
    const graph = b.graph;
    const wf = Step.WriteFile.create(b);
    const gop = b.named_writefiles.getOrPutValue(
        graph.arena,
        graph.dupeString(name),
        wf,
    ) catch @panic("OOM");
    if (gop.found_existing) {
        panic(
            "A WriteFile step with the name '{s}' has already been added to the package. Consider creating a private WriteFile step with std.Build.addWriteFiles",
            .{name},
        );
    }
    return wf;
}

pub fn addNamedLazyPath(b: *Build, name: []const u8, lp: LazyPath) void {
    const graph = b.graph;
    const gop = b.named_lazy_paths.getOrPutValue(
        graph.arena,
        graph.dupeString(name),
        lp.dupe(graph),
    ) catch @panic("OOM");
    if (gop.found_existing) {
        panic(
            "A LazyPath with the name '{s}' has already been added to the package.",
            .{name},
        );
    }
}

/// Creates a step for mutating files inside a temporary directory created lazily
/// and automatically cleaned up upon successful build.
///
/// The directory will be placed inside "tmp" rather than "o", and caching will
/// be skipped. During the `make` phase, the step will always do all the file
/// system operations, and on successful build completion, the dir will be
/// deleted along with all other tmp directories. The directory is therefore
/// eligible to be used for mutations by other steps.
///
/// See also:
/// * `addWriteFiles`
/// * `addMutateFiles`
pub fn addTempFiles(b: *Build) *Step.WriteFile {
    const wf = addWriteFiles(b);
    wf.mode = .tmp;
    return wf;
}

/// Creates a step for mutating temporary directories created with `addTempFiles`.
///
/// Consider instead `addWriteFiles` which is for creating a cached directory
/// of files to operate on.
///
/// This should only be used with a `tmp_path` obtained via `addTempFiles` or
/// `tmpPath`.
pub fn addMutateFiles(b: *Build, tmp_path: LazyPath) *Step.WriteFile {
    const wf = addWriteFiles(b);
    wf.mode = .{ .mutate = tmp_path };
    tmp_path.addStepDependencies(&wf.step);
    return wf;
}

pub fn addWriteFiles(b: *Build) *Step.WriteFile {
    return Step.WriteFile.create(b);
}

/// Creates a step for writing data to paths relative to the build root,
/// mutating the project's source files.
///
/// This build step was designed not to be used during the normal build
/// process, but rather as a utility run by a developer with intention to
/// update source files, which will then be committed to version control.
///
/// Example use cases:
/// * precompiling assets which are tracked by version control
/// * snapshot testing
pub fn addUpdateSourceFiles(b: *Build) *Step.UpdateSourceFiles {
    return Step.UpdateSourceFiles.create(b);
}

pub fn addFail(b: *Build, error_msg: []const u8) *Step.Fail {
    return Step.Fail.create(b, error_msg);
}

pub fn addFmt(b: *Build, options: Step.Fmt.Options) *Step.Fmt {
    return Step.Fmt.create(b, options);
}

pub fn addTranslateC(b: *Build, options: Step.TranslateC.Options) *Step.TranslateC {
    return Step.TranslateC.create(b, options);
}

pub fn getInstallStep(b: *Build) *Step {
    return &b.install_tls.step;
}

pub fn getUninstallStep(b: *Build) *Step {
    return &b.uninstall_tls.step;
}

/// Creates a configuration option to be passed to the build.zig script.
/// When a user directly runs `zig build`, they can set these options with `-D` arguments.
/// When a project depends on a Zig package as a dependency, it programmatically sets
/// these options when calling the dependency's build.zig script as a function.
/// `null` is returned when an option is left to default.
pub fn option(b: *Build, comptime T: type, name_raw: []const u8, description_raw: []const u8) ?T {
    const graph = b.graph;
    const arena = graph.arena;
    const name = graph.dupeString(name_raw);
    const description = graph.dupeString(description_raw);
    const type_id = comptime typeToEnum(T);
    const enum_options = if (type_id == .@"enum" or type_id == .enum_list) blk: {
        const EnumType = if (type_id == .enum_list) @typeInfo(T).pointer.child else T;
        const field_names = comptime std.meta.fieldNames(EnumType);
        var options = std.array_list.Managed([]const u8).initCapacity(b.allocator, field_names.len) catch @panic("OOM");

        inline for (field_names) |field_name| {
            options.appendAssumeCapacity(field_name);
        }

        break :blk options.toOwnedSlice() catch @panic("OOM");
    } else null;
    const available_option = AvailableOption{
        .name = name,
        .type_id = type_id,
        .description = description,
        .enum_options = enum_options,
    };
    if ((b.available_options_map.fetchPut(arena, name, available_option) catch @panic("OOM")) != null) {
        panic("option '{s}' declared twice", .{name});
    }

    const option_ptr = b.user_input_options.getPtr(name) orelse return null;
    option_ptr.used = true;
    switch (type_id) {
        .bool => switch (option_ptr.value) {
            .flag => return true,
            .scalar => |s| {
                if (mem.eql(u8, s, "true")) {
                    return true;
                } else if (mem.eql(u8, s, "false")) {
                    return false;
                } else {
                    log.err("expected -D{s} to be a boolean; received: {s}", .{ name, s });
                    b.markInvalidUserInput();
                    return null;
                }
            },
            .list, .map, .lazy_path, .lazy_path_list => {
                log.err("expected -D{s} to be a boolean; received: {t}", .{ name, option_ptr.value });
                b.markInvalidUserInput();
                return null;
            },
        },
        .int => switch (option_ptr.value) {
            .flag, .list, .map, .lazy_path, .lazy_path_list => {
                log.err("expected -D{s} to be an integer; received: {t}", .{ name, option_ptr.value });
                b.markInvalidUserInput();
                return null;
            },
            .scalar => |s| {
                const n = std.fmt.parseInt(T, s, 10) catch |err| switch (err) {
                    error.Overflow => {
                        log.err("-D{s} value {s} cannot fit into type {s}", .{ name, s, @typeName(T) });
                        b.markInvalidUserInput();
                        return null;
                    },
                    else => {
                        log.err("expected -D{s} to be an integer of type {s}", .{ name, @typeName(T) });
                        b.markInvalidUserInput();
                        return null;
                    },
                };
                return n;
            },
        },
        .float => switch (option_ptr.value) {
            .flag, .map, .list, .lazy_path, .lazy_path_list => {
                log.err("expected -D{s} to be a float; received: {t}", .{ name, option_ptr.value });
                b.markInvalidUserInput();
                return null;
            },
            .scalar => |s| {
                const n = std.fmt.parseFloat(T, s) catch {
                    log.err("expected -D{s} to be a float of type {s}", .{ name, @typeName(T) });
                    b.markInvalidUserInput();
                    return null;
                };
                return n;
            },
        },
        .@"enum" => switch (option_ptr.value) {
            .flag, .map, .list, .lazy_path, .lazy_path_list => {
                log.err("expected -D{s} to be an enum; received: {t}.", .{ name, option_ptr.value });
                b.markInvalidUserInput();
                return null;
            },
            .scalar => |s| {
                if (std.meta.stringToEnum(T, s)) |enum_lit| {
                    return enum_lit;
                } else {
                    log.err("expected -D{s} to be of type {s}", .{ name, @typeName(T) });
                    b.markInvalidUserInput();
                    return null;
                }
            },
        },
        .string => switch (option_ptr.value) {
            .flag, .list, .map, .lazy_path, .lazy_path_list => {
                log.err("expected -D{s} to be a string; received: {t}", .{ name, option_ptr.value });
                b.markInvalidUserInput();
                return null;
            },
            .scalar => |s| return s,
        },
        .build_id => switch (option_ptr.value) {
            .flag, .map, .list, .lazy_path, .lazy_path_list => {
                log.err("expected -D{s} to be an enum; received: {t}.", .{ name, option_ptr.value });
                b.markInvalidUserInput();
                return null;
            },
            .scalar => |s| {
                if (std.zig.BuildId.parse(s)) |build_id| {
                    return build_id;
                } else |err| {
                    log.err("failed to parse option -D{s}: {t}", .{ name, err });
                    b.markInvalidUserInput();
                    return null;
                }
            },
        },
        .list => switch (option_ptr.value) {
            .flag, .map, .lazy_path, .lazy_path_list => {
                log.err("expected -D{s} to be a list; received: {t}", .{ name, option_ptr.value });
                b.markInvalidUserInput();
                return null;
            },
            .scalar => |s| {
                return arena.dupe([]const u8, &[_][]const u8{s}) catch @panic("OOM");
            },
            .list => |lst| return lst.items,
        },
        .enum_list => switch (option_ptr.value) {
            .flag, .map, .lazy_path, .lazy_path_list => {
                log.err("expected -D{s} to be a list; received: {t}", .{ name, option_ptr.value });
                b.markInvalidUserInput();
                return null;
            },
            .scalar => |s| {
                const Child = @typeInfo(T).pointer.child;
                const value = std.meta.stringToEnum(Child, s) orelse {
                    log.err("expected -D{s} to be of type {s}", .{ name, @typeName(Child) });
                    b.markInvalidUserInput();
                    return null;
                };
                return arena.dupe(Child, &[_]Child{value}) catch @panic("OOM");
            },
            .list => |lst| {
                const Child = @typeInfo(T).pointer.child;
                const new_list = graph.alloc(Child, lst.items.len);
                for (new_list, lst.items) |*new_item, str| {
                    new_item.* = std.meta.stringToEnum(Child, str) orelse {
                        log.err("expected -D{s} to be of type {s}", .{ name, @typeName(Child) });
                        b.markInvalidUserInput();
                        arena.free(new_list);
                        return null;
                    };
                }
                return new_list;
            },
        },
        .lazy_path => switch (option_ptr.value) {
            .scalar => |s| return .{ .cwd_relative = s },
            .lazy_path => |lp| return lp,
            .flag, .map, .list, .lazy_path_list => {
                log.err("expected -D{s} to be a path; received: {t}", .{ name, option_ptr.value });
                b.markInvalidUserInput();
                return null;
            },
        },
        .lazy_path_list => switch (option_ptr.value) {
            .scalar => |s| return arena.dupe(LazyPath, &[_]LazyPath{.{ .cwd_relative = s }}) catch @panic("OOM"),
            .lazy_path => |lp| return arena.dupe(LazyPath, &[_]LazyPath{lp}) catch @panic("OOM"),
            .list => |lst| {
                const new_list = graph.alloc(LazyPath, lst.items.len);
                for (new_list, lst.items) |*new_item, str| {
                    new_item.* = .{ .cwd_relative = str };
                }
                return new_list;
            },
            .lazy_path_list => |lp_list| return lp_list.items,
            .flag, .map => {
                log.err("expected -D{s} to be a path; received: {t}", .{ name, option_ptr.value });
                b.markInvalidUserInput();
                return null;
            },
        },
    }
}

pub fn step(b: *Build, name: []const u8, description: []const u8) *Step {
    const graph = b.graph;
    const arena = graph.arena;
    const step_info = arena.create(Step.TopLevel) catch @panic("OOM");
    step_info.* = .{
        .step = .init(.{
            .tag = .top_level,
            .name = name,
            .owner = b,
        }),
        .description = graph.dupeString(description),
    };
    const gop = b.top_level_steps.getOrPut(arena, name) catch @panic("OOM");
    if (gop.found_existing) panic("A top-level step with name \"{s}\" already exists", .{name});

    gop.key_ptr.* = step_info.step.name;
    gop.value_ptr.* = step_info;

    return &step_info.step;
}

pub const StandardOptimizeOptionOptions = struct {
    preferred_optimize_mode: ?std.builtin.OptimizeMode = null,
};

pub fn standardOptimizeOption(b: *Build, options: StandardOptimizeOptionOptions) std.builtin.OptimizeMode {
    const graph = b.graph;

    if (options.preferred_optimize_mode) |mode| {
        if (b.option(bool, "release", "optimize for end users") orelse (graph.release_mode != .off)) {
            return mode;
        } else {
            return .Debug;
        }
    }

    if (b.option(
        std.builtin.OptimizeMode,
        "optimize",
        "Prioritize performance, safety, or binary size",
    )) |mode| {
        return mode;
    }

    return switch (graph.release_mode) {
        .off => .Debug,
        .any => {
            std.debug.print("the project does not declare a preferred optimization mode. choose: --release=fast, --release=safe, or --release=small\n", .{});
            process.exit(1);
        },
        .fast => .ReleaseFast,
        .safe => .ReleaseSafe,
        .small => .ReleaseSmall,
    };
}

pub const StandardTargetOptionsArgs = struct {
    whitelist: ?[]const Target.Query = null,
    default_target: Target.Query = .{},
};

/// Exposes standard `zig build` options for choosing a target and additionally
/// resolves the target query.
pub fn standardTargetOptions(b: *Build, args: StandardTargetOptionsArgs) ResolvedTarget {
    const query = b.standardTargetOptionsQueryOnly(args);
    return b.resolveTargetQuery(query);
}

/// Obtain a target query from a string, reporting diagnostics to stderr if the
/// parsing failed.
/// Asserts that the `diagnostics` field of `options` is `null`. This use case
/// is handled instead by calling `std.Target.Query.parse` directly.
pub fn parseTargetQuery(options: std.Target.Query.ParseOptions) error{ParseFailed}!std.Target.Query {
    assert(options.diagnostics == null);
    var diags: Target.Query.ParseOptions.Diagnostics = .{};
    var opts_copy = options;
    opts_copy.diagnostics = &diags;
    return std.Target.Query.parse(opts_copy) catch |err| switch (err) {
        error.UnknownCpuModel => {
            std.debug.print("unknown CPU: '{s}'\navailable CPUs for architecture '{t}':\n", .{
                diags.cpu_name.?, diags.arch.?,
            });
            for (diags.arch.?.allCpuModels()) |cpu| {
                std.debug.print(" {s}\n", .{cpu.name});
            }
            return error.ParseFailed;
        },
        error.UnknownCpuFeature => {
            std.debug.print(
                \\unknown CPU feature: '{s}'
                \\available CPU features for architecture '{t}':
                \\
            , .{
                diags.unknown_feature_name.?, diags.arch.?,
            });
            for (diags.arch.?.allFeaturesList()) |feature| {
                std.debug.print(" {s}: {s}\n", .{ feature.name, feature.description });
            }
            return error.ParseFailed;
        },
        error.UnknownOperatingSystem => {
            std.debug.print(
                \\unknown OS: '{s}'
                \\available operating systems:
                \\
            , .{diags.os_name.?});
            inline for (comptime std.meta.fieldNames(Target.Os.Tag)) |field_name| {
                std.debug.print(" {s}\n", .{field_name});
            }
            return error.ParseFailed;
        },
        else => |e| {
            std.debug.print("unable to parse target '{s}': {s}\n", .{
                options.arch_os_abi, @errorName(e),
            });
            return error.ParseFailed;
        },
    };
}

/// Exposes standard `zig build` options for choosing a target.
pub fn standardTargetOptionsQueryOnly(b: *Build, args: StandardTargetOptionsArgs) Target.Query {
    const graph = b.graph;
    const arena = graph.arena;

    const maybe_triple = b.option(
        []const u8,
        "target",
        "The CPU architecture, OS, and ABI to build for",
    );
    const mcpu = b.option(
        []const u8,
        "cpu",
        "Target CPU features to add or subtract",
    );
    const ofmt = b.option(
        []const u8,
        "ofmt",
        "Target object format",
    );
    const dynamic_linker = b.option(
        []const u8,
        "dynamic-linker",
        "Path to interpreter on the target system",
    );

    if (maybe_triple == null and mcpu == null and ofmt == null and dynamic_linker == null)
        return args.default_target;

    const triple = maybe_triple orelse "native";

    const selected_target = parseTargetQuery(.{
        .arch_os_abi = triple,
        .cpu_features = mcpu,
        .object_format = ofmt,
        .dynamic_linker = dynamic_linker,
    }) catch |err| switch (err) {
        error.ParseFailed => {
            b.markInvalidUserInput();
            return args.default_target;
        },
    };

    const whitelist = args.whitelist orelse return selected_target;

    // Make sure it's a match of one of the list.
    for (whitelist) |q| {
        if (q.eql(selected_target))
            return selected_target;
    }

    for (whitelist) |q| {
        log.info("allowed target: -Dtarget={s} -Dcpu={s}", .{
            q.zigTriple(arena) catch @panic("OOM"),
            q.serializeCpuAlloc(arena) catch @panic("OOM"),
        });
    }
    log.err("chosen target '{s}' does not match one of the allowed targets", .{
        selected_target.zigTriple(arena) catch @panic("OOM"),
    });
    b.markInvalidUserInput();
    return args.default_target;
}

pub fn addUserInputOption(b: *Build, name_raw: []const u8, value_raw: []const u8) error{OutOfMemory}!bool {
    const graph = b.graph;
    const arena = graph.arena;
    const name = graph.dupeString(name_raw);
    const value = graph.dupeString(value_raw);
    const gop = try b.user_input_options.getOrPut(name);
    if (!gop.found_existing) {
        gop.value_ptr.* = UserInputOption{
            .name = name,
            .value = .{ .scalar = value },
            .used = false,
        };
        return false;
    }

    // option already exists
    switch (gop.value_ptr.value) {
        .scalar => |s| {
            // turn it into a list
            var list = std.array_list.Managed([]const u8).init(arena);
            try list.append(s);
            try list.append(value);
            try b.user_input_options.put(name, .{
                .name = name,
                .value = .{ .list = list },
                .used = false,
            });
        },
        .list => |*list| {
            // append to the list
            try list.append(value);
            try b.user_input_options.put(name, .{
                .name = name,
                .value = .{ .list = list.* },
                .used = false,
            });
        },
        .flag => {
            log.warn("option '-D{s}={s}' conflicts with flag '-D{s}'.", .{ name, value, name });
            return true;
        },
        .map => |*map| {
            _ = map;
            log.warn("TODO maps as command line arguments is not implemented yet.", .{});
            return true;
        },
        .lazy_path, .lazy_path_list => {
            log.warn("the lazy path value type isn't added from the CLI, but somehow '{s}' is a .{f}", .{
                name, std.zig.fmtId(@tagName(gop.value_ptr.value)),
            });
            return true;
        },
    }
    return false;
}

pub fn addUserInputFlag(b: *Build, name_raw: []const u8) error{OutOfMemory}!bool {
    const graph = b.graph;
    const name = graph.dupeString(name_raw);
    const gop = try b.user_input_options.getOrPut(name);
    if (!gop.found_existing) {
        gop.value_ptr.* = .{
            .name = name,
            .value = .{ .flag = {} },
            .used = false,
        };
        return false;
    }

    // option already exists
    switch (gop.value_ptr.value) {
        .scalar => |s| {
            log.err("Flag '-D{s}' conflicts with option '-D{s}={s}'.", .{ name, name, s });
            return true;
        },
        .list, .map, .lazy_path_list => {
            log.err("Flag '-D{s}' conflicts with multiple options of the same name.", .{name});
            return true;
        },
        .lazy_path => |lp| {
            log.err("Flag '-D{s}' conflicts with option '-D{s}={f}'.", .{ name, name, lp });
            return true;
        },

        .flag => {},
    }
    return false;
}

fn typeToEnum(comptime T: type) Configuration.AvailableOption.Type {
    return switch (T) {
        std.zig.BuildId => .build_id,
        LazyPath => .lazy_path,
        else => return switch (@typeInfo(T)) {
            .int => .int,
            .float => .float,
            .bool => .bool,
            .@"enum" => .@"enum",
            .pointer => |pointer| switch (pointer.child) {
                u8 => .string,
                []const u8 => .list,
                LazyPath => .lazy_path_list,
                else => switch (@typeInfo(pointer.child)) {
                    .@"enum" => .enum_list,
                    else => @compileError("Unsupported type: " ++ @typeName(T)),
                },
            },
            else => @compileError("Unsupported type: " ++ @typeName(T)),
        },
    };
}

fn markInvalidUserInput(b: *Build) void {
    b.invalid_user_input = true;
}

pub fn validateUserInputDidItFail(b: *Build) bool {
    // Make sure all args are used.
    var it = b.user_input_options.iterator();
    while (it.next()) |entry| {
        if (!entry.value_ptr.used) {
            log.err("invalid option: -D{s}", .{entry.key_ptr.*});
            b.markInvalidUserInput();
        }
    }

    return b.invalid_user_input;
}

/// This creates the install step and adds it to the dependencies of the
/// top-level install step, using all the default options.
/// See `addInstallArtifact` for a more flexible function.
pub fn installArtifact(b: *Build, artifact: *Step.Compile) void {
    b.getInstallStep().dependOn(&b.addInstallArtifact(artifact, .{}).step);
}

/// This merely creates the step; it does not add it to the dependencies of the
/// top-level install step.
pub fn addInstallArtifact(
    b: *Build,
    artifact: *Step.Compile,
    options: Step.InstallArtifact.Options,
) *Step.InstallArtifact {
    return Step.InstallArtifact.create(b, artifact, options);
}

///`dest_rel_path` is relative to prefix path
pub fn installFile(b: *Build, src_path: []const u8, dest_rel_path: []const u8) void {
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(b.path(src_path), .prefix, dest_rel_path).step);
}

pub fn installDirectory(b: *Build, options: Step.InstallDir.Options) void {
    b.getInstallStep().dependOn(&b.addInstallDirectory(options).step);
}

///`dest_rel_path` is relative to bin path
pub fn installBinFile(b: *Build, src_path: []const u8, dest_rel_path: []const u8) void {
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(b.path(src_path), .bin, dest_rel_path).step);
}

///`dest_rel_path` is relative to lib path
pub fn installLibFile(b: *Build, src_path: []const u8, dest_rel_path: []const u8) void {
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(b.path(src_path), .lib, dest_rel_path).step);
}

pub fn addObjCopy(b: *Build, source: LazyPath, options: Step.ObjCopy.Options) *Step.ObjCopy {
    return Step.ObjCopy.create(b, source, options);
}

/// `dest_rel_path` is relative to install prefix path
pub fn addInstallFile(b: *Build, source: LazyPath, dest_rel_path: []const u8) *Step.InstallFile {
    return b.addInstallFileWithDir(source, .prefix, dest_rel_path);
}

/// `dest_rel_path` is relative to bin path
pub fn addInstallBinFile(b: *Build, source: LazyPath, dest_rel_path: []const u8) *Step.InstallFile {
    return b.addInstallFileWithDir(source, .bin, dest_rel_path);
}

/// `dest_rel_path` is relative to lib path
pub fn addInstallLibFile(b: *Build, source: LazyPath, dest_rel_path: []const u8) *Step.InstallFile {
    return b.addInstallFileWithDir(source, .lib, dest_rel_path);
}

/// `dest_rel_path` is relative to header path
pub fn addInstallHeaderFile(b: *Build, source: LazyPath, dest_rel_path: []const u8) *Step.InstallFile {
    return b.addInstallFileWithDir(source, .header, dest_rel_path);
}

pub fn addInstallFileWithDir(
    b: *Build,
    source: LazyPath,
    install_dir: InstallDir,
    dest_rel_path: []const u8,
) *Step.InstallFile {
    return Step.InstallFile.create(b, source, install_dir, dest_rel_path);
}

pub fn addInstallDirectory(b: *Build, options: Step.InstallDir.Options) *Step.InstallDir {
    return Step.InstallDir.create(b, options);
}

pub fn addCheckFile(
    b: *Build,
    file_source: LazyPath,
    options: Step.CheckFile.Options,
) *Step.CheckFile {
    return Step.CheckFile.create(b, file_source, options);
}

/// References a file or directory relative to the source root.
pub fn path(b: *Build, sub_path: []const u8) LazyPath {
    if (fs.path.isAbsolute(sub_path)) {
        panic("sub_path is expected to be relative to the build root, but was this absolute path: '{s}'. Absolute paths can cause problems but can be created via Graph.cwdRelativePath", .{
            sub_path,
        });
    }
    return .{ .src_path = .{
        .owner = b,
        .sub_path = sub_path,
    } };
}

/// Creates a list of files and/or directories relative to the source root.
pub fn pathList(b: *Build, sub_paths: []const []const u8) []const LazyPath {
    const graph = b.graph;
    const result = graph.alloc(LazyPath, sub_paths.len);
    for (result, sub_paths) |*d, s| d.* = path(b, s);
    return result;
}

pub fn pathJoin(b: *Build, paths: []const []const u8) []u8 {
    const graph = b.graph;
    const arena = graph.arena;
    return fs.path.join(arena, paths) catch @panic("OOM");
}

pub fn pathResolve(b: *Build, paths: []const []const u8) []u8 {
    const graph = b.graph;
    const arena = graph.arena;
    return fs.path.resolve(arena, paths) catch @panic("OOM");
}

pub fn fmt(b: *Build, comptime format: []const u8, args: anytype) []u8 {
    const graph = b.graph;
    const arena = graph.arena;
    return std.fmt.allocPrint(arena, format, args) catch @panic("OOM");
}

/// Creates an anonymous `Step` that searches for an executable on the host that
/// has more than one possible name.
///
/// Returns the `LazyPath` of the found executable. The search only takes place
/// if the `LazyPath` will be used by a depending `Step`.
///
/// This API is useful in the following cases:
/// * The binary is not named the same across all systems (for example "python"
///   vs "python3").
/// * The binary may be produced by building from source rather than being
///   globally installed and will therefore be possibly found in one of the
///   search prefix paths.
///
/// Names are searched in order, observing search prefixes first and then PATH
/// environment variable.
///
/// Windows file name extensions are searched automatically, respecting the
/// PATHEXT environment variable, so they need not be included in this list.
/// However, even on Windows, the names will be checked without appending
/// extensions first, so that can be used as a priority system.
///
/// See also:
/// * `findProgram`
pub fn findProgramLazy(b: *Build, options: Step.FindProgram.Options) LazyPath {
    return .{ .generated = .{ .index = Step.FindProgram.create(b, options).found_path } };
}

pub const FindProgramOptions = Step.FindProgram.Options;

/// Immediately (in the configure phase), searches for an executable on the host
/// that has more than one possible name.
///
/// Calling this function poisons the configuration cache, so it is only
/// appropriate when the existence of the program or its output needs to be
/// observed by configuration logic. For more information, see
/// `Graph.CachePoison` documentation.
///
/// Names are searched in order, observing search prefixes first and then PATH
/// environment variable.
///
/// Windows file name extensions are searched automatically, respecting the
/// PATHEXT environment variable, so they need not be included in this list.
/// However, even on Windows, the names will be checked without appending
/// extensions first, so that can be used as a priority system.
///
/// See also:
/// * `findProgramLazy`
pub fn findProgram(b: *Build, options: FindProgramOptions) ?[]const u8 {
    const graph = b.graph;

    // Because it observes search prefixes and contents of directories in PATH.
    graph.poisonCache();

    for (options.names) |name| {
        if (Io.Dir.path.isAbsolute(name)) {
            if (tryFindProgram(b, name)) |found| return found;
        }
        for (graph.search_prefixes.items) |search_prefix| {
            const full_path = b.pathJoin(&.{ search_prefix, "bin", name });
            if (tryFindProgram(b, full_path)) |found| return found;
        }
    }

    if (b.graph.environ_map.get("PATH")) |PATH| {
        for (options.names) |name| {
            var it = mem.tokenizeScalar(u8, PATH, Io.Dir.path.delimiter);
            while (it.next()) |p| {
                const full_path = b.pathJoin(&.{ p, name });
                if (tryFindProgram(b, full_path)) |found| return found;
            }
        }
    }

    return null;
}

fn supportedWindowsProgramExtension(ext: []const u8) bool {
    inline for (@typeInfo(std.process.WindowsExtension).@"enum".field_names) |field_name| {
        if (std.ascii.eqlIgnoreCase(ext, "." ++ field_name)) return true;
    }
    return false;
}

fn tryFindProgram(b: *Build, full_path: []const u8) ?[]const u8 {
    const graph = b.graph;
    const io = graph.io;
    const arena = graph.arena;

    if (Io.Dir.cwd().access(io, full_path, .{ .execute = true })) |_| {
        return full_path;
    } else |err| switch (err) {
        error.FileNotFound, error.AccessDenied, error.PermissionDenied => |e| {
            if (graph.verbose) log.info("searched: {t} {s}", .{ e, full_path });
        },
        else => |e| return panic("failed accessing {s}: {t}", .{ full_path, e }),
    }

    if (builtin.os.tag == .windows) {
        if (b.graph.environ_map.get("PATHEXT")) |PATHEXT| {
            var it = mem.tokenizeScalar(u8, PATHEXT, fs.path.delimiter);

            const extended_path_buf = arena.alloc(u8, full_path.len + 1 + std.process.WindowsExtension.max_len) catch @panic("OOM");
            @memcpy(extended_path_buf[0..full_path.len], full_path);

            while (it.next()) |ext| {
                if (!supportedWindowsProgramExtension(ext)) continue;

                @memcpy(extended_path_buf[full_path.len..][0..ext.len], ext);
                const extended_path = extended_path_buf[0 .. full_path.len + ext.len];

                if (Io.Dir.cwd().access(io, extended_path, .{ .execute = true })) |_| {
                    return extended_path;
                } else |err| switch (err) {
                    error.FileNotFound, error.AccessDenied, error.PermissionDenied => |e| {
                        if (graph.verbose) log.info("searched: {t} {s}", .{ e, extended_path });
                    },
                    else => |e| return panic("failed accessing {s}: {t}", .{ extended_path, e }),
                }
            }
        }
    }

    return null;
}

/// Deprecated; use `runFallible`.
pub fn runAllowFail(
    b: *Build,
    argv: []const []const u8,
    exit_code: *u8,
    stderr_behavior: process.SpawnOptions.StdIo,
) anyerror![]u8 {
    if (!process.can_spawn) return error.ExecNotSupported;
    switch (runFallible(b, argv, .{
        .stderr_behavior = stderr_behavior,
    })) {
        .success => |stdout| return stdout,
        .spawn_failed => |err| return err,
        .bad_exit_code => |code| {
            exit_code.* = code;
            return error.ExitCodeFailure;
        },
        .crashed => {
            exit_code.* = 255;
            return error.ProcessTerminated;
        },
    }
}

pub const RunOptions = struct {
    stderr_behavior: process.SpawnOptions.StdIo = .inherit,
    /// Fail the configuration if stdout is larger than this.
    stdout_limit: Io.Limit = .limited(1_000_000),
    /// Set to change the current working directory when spawning the child
    /// process.
    cwd: process.Child.Cwd = .inherit,
    /// Replaces the child environment when provided. The PATH value from here
    /// is not used to resolve `argv[0]`; that resolution always uses parent
    /// environment.
    environ_map: ?*const process.Environ.Map = null,
    expand_arg0: process.ArgExpansion = .no_expand,
};

pub const RunResult = union(enum) {
    /// Thild process exited with code 0, writing this stdout.
    success: []u8,
    /// The child process could not be created.
    spawn_failed: process.SpawnError,
    /// The child process indicated failure.
    bad_exit_code: u8,
    /// The child process terminated abnormally.
    crashed,
};

/// Executes the provided command immediately, allowing failure.
///
/// If the program exits successfully, stdout is returned. Otherwise, returns
/// an indication of failure.
///
/// See also:
/// * `run`.
pub fn runFallible(b: *Build, argv: []const []const u8, options: RunOptions) RunResult {
    assert(argv.len != 0);

    const graph = b.graph;
    const io = graph.io;
    const arena = graph.arena;

    const print_opts: std.zig.AllocPrintCmdOptions = .{
        .cwd = switch (options.cwd) {
            .inherit => null,
            .path => |p| p,
            .dir => null, // Unknown without changing function signature of runFallible.
        },
        .child_env = options.environ_map,
        .parent_env = &graph.environ_map,
    };

    if (graph.verbose) {
        const text = std.zig.allocPrintCmd(arena, argv, print_opts) catch @panic("OOM");
        std.log.scoped(.verbose).info("{s}", .{text});
    }

    var child = process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = options.stderr_behavior,
        .cwd = options.cwd,
        .environ_map = &graph.environ_map,
        .expand_arg0 = options.expand_arg0,
    }) catch |err| return .{ .spawn_failed = err };

    var stdout_reader = child.stdout.?.readerStreaming(io, &.{});
    const stdout = stdout_reader.interface.allocRemaining(arena, options.stdout_limit) catch |err| switch (err) {
        error.ReadFailed => panic("failed to read from child: {t}", .{stdout_reader.err.?}),
        else => |e| panic("failed to read from child: {t}", .{e}),
    };

    const term = child.wait(io) catch @panic("unexpected");

    return switch (term) {
        .exited => |code| switch (code) {
            0 => .{ .success = stdout },
            else => .{ .bad_exit_code = code },
        },
        .signal, .stopped, .unknown => .crashed,
    };
}

/// Executes the provided command immediately.
///
/// If the program exits successfully, stdout is returned. Otherwise, fails the
/// build with a helpful message.
///
/// See also:
/// * `runFallible`.
pub fn run(b: *Build, argv: []const []const u8) []u8 {
    const graph = b.graph;
    const arena = graph.arena;
    switch (b.runFallible(argv, .{
        .stderr_behavior = .inherit,
    })) {
        .success => |stdout| return stdout,
        .spawn_failed => |err| process.fatal("the following command failed with {t}:\n{s}", .{
            err, std.zig.allocPrintCmd(arena, argv, .{}) catch @panic("OOM"),
        }),
        .bad_exit_code => |code| process.fatal("the following command exited with code {d}:\n{s}", .{
            code, std.zig.allocPrintCmd(arena, argv, .{}) catch @panic("OOM"),
        }),
        .crashed => process.fatal("the following command crashed:\n{s}", .{
            std.zig.allocPrintCmd(arena, argv, .{}) catch @panic("OOM"),
        }),
    }
}

/// Adds additional paths, equivalent to the `--search-prefix` arguments
/// provided by the user. Paths added with this function have lower precedence
/// than the ones specified by the user on the command line.
///
/// It is generally best practice to avoid calling this function, instead
/// relying on the user to provide these paths via the standard build system
/// interface. However, when integrating with other build systems, the user may
/// have already provided the information to the other build system, and thus
/// it is desirable to use that same information without requiring the user to
/// provide it again.
pub fn addSearchPrefix(b: *Build, search_prefix: []const u8) void {
    if (b.isRoot()) {
        const graph = b.graph;
        const wc = &graph.wip_configuration;
        const string = wc.addString(search_prefix) catch @panic("OOM");
        wc.search_prefixes.append(wc.gpa, string) catch @panic("OOM");
    }
}

pub fn isRoot(b: *const Build) bool {
    return b.pkg_hash.len == 0;
}

pub const Dependency = struct {
    builder: *Build,

    pub fn artifact(d: *Dependency, name: []const u8) *Step.Compile {
        var found: ?*Step.Compile = null;
        for (d.builder.install_tls.step.dependencies.items) |dep_step| {
            const inst = dep_step.cast(Step.InstallArtifact) orelse continue;
            if (mem.eql(u8, inst.artifact.name, name)) {
                if (found != null) panic("artifact name '{s}' is ambiguous", .{name});
                found = inst.artifact;
            }
        }
        return found orelse {
            for (d.builder.install_tls.step.dependencies.items) |dep_step| {
                const inst = dep_step.cast(Step.InstallArtifact) orelse continue;
                log.info("available artifact: '{s}'", .{inst.artifact.name});
            }
            panic("unable to find artifact '{s}'", .{name});
        };
    }

    pub fn module(d: *Dependency, name: []const u8) *Module {
        return d.builder.modules.get(name) orelse {
            panic("unable to find module '{s}'", .{name});
        };
    }

    pub fn namedWriteFiles(d: *Dependency, name: []const u8) *Step.WriteFile {
        return d.builder.named_writefiles.get(name) orelse {
            panic("unable to find named writefiles '{s}'", .{name});
        };
    }

    pub fn namedLazyPath(d: *Dependency, name: []const u8) LazyPath {
        return d.builder.named_lazy_paths.get(name) orelse {
            panic("unable to find named lazypath '{s}'", .{name});
        };
    }

    pub fn path(d: *Dependency, sub_path: []const u8) LazyPath {
        return .{
            .dependency = .{
                .dependency = d,
                .sub_path = sub_path,
            },
        };
    }
};

fn findPkgHashOrFatal(b: *Build, name: []const u8) []const u8 {
    for (b.available_deps) |dep| {
        if (mem.eql(u8, dep[0], name)) return dep[1];
    }
    std.log.info("all dependencies used by build.zig must be declared in corresponding build.zig.zon", .{});
    if (b.pkg_hash.len == 0) panic("no dependency named {s}", .{name});
    panic("no dependency named {s} in {s} ({s})", .{ name, b.dep_prefix, b.pkg_hash });
}

inline fn findImportPkgHashOrFatal(b: *Build, comptime asking_build_zig: type, comptime dep_name: []const u8) []const u8 {
    const build_runner = @import("root");
    const deps = build_runner.dependencies;
    const arena = b.graph.arena;

    const b_pkg_hash, const b_pkg_deps = comptime for (@typeInfo(deps.packages).@"struct".decl_names) |pkg_hash| {
        const pkg = @field(deps.packages, pkg_hash);
        if (@hasDecl(pkg, "build_zig") and pkg.build_zig == asking_build_zig) break .{ pkg_hash, pkg.deps };
    } else .{ "", deps.root_deps };
    if (!std.mem.eql(u8, b_pkg_hash, b.pkg_hash)) {
        const build_zig_path = b.root.join(arena, "build.zig") catch @panic("OOM");
        panic("{} is not the struct that corresponds to {f}", .{
            asking_build_zig, build_zig_path,
        });
    }
    comptime for (b_pkg_deps) |dep| {
        if (std.mem.eql(u8, dep[0], dep_name)) return dep[1];
    };

    const full_path = b.root.join(arena, "build.zig.zon") catch @panic("OOM");
    panic("no dependency named {s} in {f}. All packages used in build.zig must be declared in this file", .{
        dep_name, full_path,
    });
}

fn markNeededLazyDep(b: *Build, pkg_hash: []const u8) void {
    b.graph.needed_lazy_dependencies.put(b.graph.arena, pkg_hash, {}) catch @panic("OOM");
}

/// When this function is called, it means that the current build does, in
/// fact, require this dependency. If the dependency is already fetched, it
/// proceeds in the same manner as `dependency`. However if the dependency was
/// not fetched, then when the build script is finished running, the build will
/// not proceed to the make phase. Instead, the parent process will
/// additionally fetch all the lazy dependencies that were actually required by
/// running the build script, rebuild the build script, and then run it again.
/// In other words, if this function returns `null` it means that the only
/// purpose of completing the configure phase is to find out all the other lazy
/// dependencies that are also required.
///
/// It is allowed to use this function for non-lazy dependencies, in which case
/// it will never return `null`. This allows toggling laziness via
/// build.zig.zon without changing build.zig logic.
pub fn lazyDependency(b: *Build, name: []const u8, args: anytype) ?*Dependency {
    const build_runner = @import("root");
    const deps = build_runner.dependencies;
    const pkg_hash = findPkgHashOrFatal(b, name);

    inline for (@typeInfo(deps.packages).@"struct".decl_names) |decl_name| {
        if (mem.eql(u8, decl_name, pkg_hash)) {
            const pkg = @field(deps.packages, decl_name);
            const available = !@hasDecl(pkg, "available") or pkg.available;
            if (!available) {
                markNeededLazyDep(b, pkg_hash);
                return null;
            }
            return dependencyInner(b, name, pkg.build_root, if (@hasDecl(pkg, "build_zig")) pkg.build_zig else null, pkg_hash, pkg.deps, args);
        }
    }

    unreachable; // Bad @dependencies source
}

pub fn dependency(b: *Build, name: []const u8, args: anytype) *Dependency {
    const build_runner = @import("root");
    const deps = build_runner.dependencies;
    const pkg_hash = findPkgHashOrFatal(b, name);

    inline for (@typeInfo(deps.packages).@"struct".decl_names) |decl_name| {
        if (mem.eql(u8, decl_name, pkg_hash)) {
            const pkg = @field(deps.packages, decl_name);
            if (@hasDecl(pkg, "available")) {
                panic("dependency '{s}{s}' is marked as lazy in build.zig.zon which means it must use the lazyDependency function instead", .{ b.dep_prefix, name });
            }
            return dependencyInner(b, name, pkg.build_root, if (@hasDecl(pkg, "build_zig")) pkg.build_zig else null, pkg_hash, pkg.deps, args);
        }
    }

    unreachable; // Bad @dependencies source
}

/// In a build.zig file, this function is to `@import` what `lazyDependency` is to `dependency`.
/// If the dependency is lazy and has not yet been fetched, it instructs the parent process to fetch
/// that dependency after the build script has finished running, then returns `null`.
/// If the dependency is lazy but has already been fetched, or if it is eager, it returns
/// the build.zig struct of that dependency, just like a regular `@import`.
pub inline fn lazyImport(
    b: *Build,
    /// The build.zig struct of the package importing the dependency.
    /// When calling this function from the `build` function of a build.zig file's, you normally
    /// pass `@This()`.
    comptime asking_build_zig: type,
    comptime dep_name: []const u8,
) ?type {
    const build_runner = @import("root");
    const deps = build_runner.dependencies;
    const pkg_hash = findImportPkgHashOrFatal(b, asking_build_zig, dep_name);

    inline for (@typeInfo(deps.packages).@"struct".decl_names) |decl_name| {
        if (comptime mem.eql(u8, decl_name, pkg_hash)) {
            const pkg = @field(deps.packages, decl_name);
            const available = !@hasDecl(pkg, "available") or pkg.available;
            if (!available) {
                markNeededLazyDep(b, pkg_hash);
                return null;
            }
            return if (@hasDecl(pkg, "build_zig"))
                pkg.build_zig
            else
                @compileError("dependency '" ++ dep_name ++ "' does not have a build.zig");
        }
    }

    comptime unreachable; // Bad @dependencies source
}

pub fn dependencyFromBuildZig(
    b: *Build,
    /// The build.zig struct of the dependency, normally obtained by `@import` of the dependency.
    /// If called from the build.zig file itself, use `@This` to obtain a reference to the struct.
    comptime build_zig: type,
    args: anytype,
) *Dependency {
    const build_runner = @import("root");
    const deps = build_runner.dependencies;
    const graph = b.graph;
    const arena = graph.arena;

    find_dep: {
        const pkg, const pkg_hash = inline for (@typeInfo(deps.packages).@"struct".decl_names) |pkg_hash| {
            const pkg = @field(deps.packages, pkg_hash);
            if (@hasDecl(pkg, "build_zig") and pkg.build_zig == build_zig) break .{ pkg, pkg_hash };
        } else break :find_dep;
        const dep_name = for (b.available_deps) |dep| {
            if (mem.eql(u8, dep[1], pkg_hash)) break dep[1];
        } else break :find_dep;
        return dependencyInner(b, dep_name, pkg.build_root, pkg.build_zig, pkg_hash, pkg.deps, args);
    }

    const full_path = b.root.join(arena, "build.zig.zon") catch @panic("OOM");
    panic("{} is not a build.zig struct of a dependency in {f}", .{ build_zig, full_path });
}

fn userValuesAreSame(lhs: UserValue, rhs: UserValue) bool {
    if (std.meta.activeTag(lhs) != rhs) return false;
    switch (lhs) {
        .flag => {},
        .scalar => |lhs_scalar| {
            const rhs_scalar = rhs.scalar;

            if (!std.mem.eql(u8, lhs_scalar, rhs_scalar))
                return false;
        },
        .list => |lhs_list| {
            const rhs_list = rhs.list;

            if (lhs_list.items.len != rhs_list.items.len)
                return false;

            for (lhs_list.items, rhs_list.items) |lhs_list_entry, rhs_list_entry| {
                if (!std.mem.eql(u8, lhs_list_entry, rhs_list_entry))
                    return false;
            }
        },
        .map => |lhs_map| {
            const rhs_map = rhs.map;

            if (lhs_map.count() != rhs_map.count())
                return false;

            var lhs_it = lhs_map.iterator();
            while (lhs_it.next()) |lhs_entry| {
                const rhs_value = rhs_map.get(lhs_entry.key_ptr.*) orelse return false;
                if (!userValuesAreSame(lhs_entry.value_ptr.*.*, rhs_value.*))
                    return false;
            }
        },
        .lazy_path => |lhs_lp| {
            const rhs_lp = rhs.lazy_path;
            return userLazyPathsAreTheSame(lhs_lp, rhs_lp);
        },
        .lazy_path_list => |lhs_lp_list| {
            const rhs_lp_list = rhs.lazy_path_list;
            if (lhs_lp_list.items.len != rhs_lp_list.items.len) return false;
            for (lhs_lp_list.items, rhs_lp_list.items) |lhs_lp, rhs_lp| {
                if (!userLazyPathsAreTheSame(lhs_lp, rhs_lp)) return false;
            }
            return true;
        },
    }

    return true;
}

fn userLazyPathsAreTheSame(lhs_lp: LazyPath, rhs_lp: LazyPath) bool {
    if (std.meta.activeTag(lhs_lp) != rhs_lp) return false;
    switch (lhs_lp) {
        .src_path => |lhs_sp| {
            const rhs_sp = rhs_lp.src_path;

            if (lhs_sp.owner != rhs_sp.owner) return false;
            if (std.mem.eql(u8, lhs_sp.sub_path, rhs_sp.sub_path)) return false;
        },
        .generated => |*lhs_gen| {
            const rhs_gen = &rhs_lp.generated;

            if (lhs_gen.index != rhs_gen.index) return false;
            if (lhs_gen.up != rhs_gen.up) return false;
            if (std.mem.eql(u8, lhs_gen.sub_path, rhs_gen.sub_path)) return false;
        },
        .cwd_relative => |lhs_rel_path| {
            const rhs_rel_path = rhs_lp.cwd_relative;

            if (!std.mem.eql(u8, lhs_rel_path, rhs_rel_path)) return false;
        },
        .relative => |lhs| return lhs.eql(rhs_lp.relative),
        .dependency => |lhs_dep| {
            const rhs_dep = rhs_lp.dependency;

            if (lhs_dep.dependency != rhs_dep.dependency) return false;
            if (!std.mem.eql(u8, lhs_dep.sub_path, rhs_dep.sub_path)) return false;
        },
    }
    return true;
}

fn dependencyInner(
    b: *Build,
    name: []const u8,
    build_root_string: []const u8,
    comptime build_zig: ?type,
    pkg_hash: []const u8,
    pkg_deps: AvailableDeps,
    args: anytype,
) *Dependency {
    const graph = b.graph;
    const io = graph.io;
    const arena = graph.arena;
    const user_input_options = userInputOptionsFromArgs(arena, args);
    if (graph.dependency_cache.getContext(.{
        .build_root_string = build_root_string,
        .user_input_options = user_input_options,
    }, .{ .allocator = arena })) |dep| return dep;

    const dep_root: Cache.Path = .{
        .root_dir = .{
            .path = build_root_string,
            .handle = Io.Dir.cwd().openDir(io, build_root_string, .{}) catch |err|
                process.fatal("unable to open {s}: {t}", .{ build_root_string, err }),
        },
    };

    const sub_builder = b.createChild(name, dep_root, pkg_hash, pkg_deps, user_input_options) catch
        @panic("unhandled error");
    if (build_zig) |bz| {
        sub_builder.runBuild(bz) catch @panic("unhandled error");

        if (sub_builder.validateUserInputDidItFail()) {
            std.debug.dumpCurrentStackTrace(.{ .first_address = @returnAddress() });
        }
    }

    const dep = graph.create(Dependency);
    dep.* = .{ .builder = sub_builder };

    graph.dependency_cache.putContext(arena, .{
        .build_root_string = build_root_string,
        .user_input_options = user_input_options,
    }, dep, .{ .allocator = arena }) catch @panic("OOM");
    return dep;
}

pub fn runBuild(b: *Build, build_zig: anytype) anyerror!void {
    switch (@typeInfo(@typeInfo(@TypeOf(build_zig.build)).@"fn".return_type.?)) {
        .void => build_zig.build(b),
        .error_union => try build_zig.build(b),
        else => @compileError("expected return type of build to be 'void' or '!void'"),
    }
}

// dirnameAllowEmpty is a variant of fs.path.dirname
// that allows "" to refer to the root for relative paths.
//
// For context, dirname("foo") and dirname("") are both null.
// However, for relative paths, we want dirname("foo") to be ""
// so that we can join it with another path (e.g. build root, cache root, etc.)
//
// dirname("") should still be null, because we can't go up any further.
fn dirnameAllowEmpty(full_path: []const u8) ?[]const u8 {
    return fs.path.dirname(full_path) orelse {
        if (fs.path.isAbsolute(full_path) or full_path.len == 0) return null;

        return "";
    };
}

test dirnameAllowEmpty {
    try std.testing.expectEqualStrings(
        "foo",
        dirnameAllowEmpty("foo" ++ fs.path.sep_str ++ "bar") orelse @panic("unexpected null"),
    );

    try std.testing.expectEqualStrings(
        "",
        dirnameAllowEmpty("foo") orelse @panic("unexpected null"),
    );

    try std.testing.expect(dirnameAllowEmpty("") == null);
}

/// A reference to an existing or future path.
pub const LazyPath = union(enum) {
    /// A source file path relative to build root.
    src_path: struct {
        owner: *std.Build,
        sub_path: []const u8,
    },

    generated: struct {
        index: Configuration.GeneratedFileIndex,

        /// The number of parent directories to go up.
        /// 0 means the generated file itself.
        /// 1 means the directory of the generated file.
        /// 2 means the parent of that directory, and so on.
        up: usize = 0,

        /// Applied after `up`.
        sub_path: []const u8 = "",
    },

    /// Deprecated; call `Graph.cwdRelativePath` instead.
    cwd_relative: []const u8,

    dependency: struct {
        dependency: *Dependency,
        sub_path: []const u8,
    },

    relative: struct {
        base: Configuration.Path.Base,
        sub_path: []const u8 = "",

        pub fn eql(a: @This(), b: @This()) bool {
            return a.base == b.base and mem.eql(u8, a.sub_path, b.sub_path);
        }
    },

    /// Path to the Zig executable being used to execute "zig build".
    pub const zig_exe: LazyPath = .{ .relative = .{ .base = .zig_exe } };
    /// Path to the "lib/" directory from the Zig installation being used to
    /// execute "zig build".
    pub const zig_lib: LazyPath = .{ .relative = .{ .base = .zig_lib } };
    /// Path to the project's local cache directory (usually called ".zig-cache").
    pub const cache_root: LazyPath = .{ .relative = .{ .base = .local_cache } };

    /// Returns a lazy path referring to the directory containing this path.
    ///
    /// The dirname is not allowed to escape the logical root for underlying
    /// path. For example, if the path is relative to the build root, the
    /// dirname is not allowed to traverse outside of the build root.
    /// Similarly, if the path is a generated file inside zig-cache, the
    /// dirname is not allowed to traverse outside of zig-cache.
    pub fn dirname(lazy_path: LazyPath) LazyPath {
        return switch (lazy_path) {
            .src_path => |sp| .{ .src_path = .{
                .owner = sp.owner,
                .sub_path = dirnameAllowEmpty(sp.sub_path) orelse {
                    dumpBadDirnameHelp(null, null, "dirname() attempted to traverse outside the build root\n", .{}) catch {};
                    @panic("misconfigured build script");
                },
            } },
            .generated => |generated| .{ .generated = if (dirnameAllowEmpty(generated.sub_path)) |sub_dirname| .{
                .index = generated.index,
                .up = generated.up,
                .sub_path = sub_dirname,
            } else .{
                .index = generated.index,
                .up = generated.up + 1,
                .sub_path = "",
            } },
            .cwd_relative => |rel_path| .{
                .cwd_relative = dirnameAllowEmpty(rel_path) orelse {
                    // If we get null, it means one of two things:
                    // - rel_path was absolute, and is now root
                    // - rel_path was relative, and is now ""
                    // In either case, the build script tried to go too far
                    // and we should panic.
                    if (fs.path.isAbsolute(rel_path)) {
                        dumpBadDirnameHelp(null, null,
                            \\dirname() attempted to traverse outside the root.
                            \\No more directories left to go up.
                            \\
                        , .{}) catch {};
                        @panic("misconfigured build script");
                    } else {
                        dumpBadDirnameHelp(null, null,
                            \\dirname() attempted to traverse outside the current working directory.
                            \\
                        , .{}) catch {};
                        @panic("misconfigured build script");
                    }
                },
            },
            .relative => |r| .{ .relative = .{
                .base = r.base,
                .sub_path = dirnameAllowEmpty(r.sub_path) orelse {
                    dumpBadDirnameHelp(null, null, "dirname() attempted to traverse outside the base path\n", .{}) catch {};
                    @panic("misconfigured build script");
                },
            } },
            .dependency => |dep| .{ .dependency = .{
                .dependency = dep.dependency,
                .sub_path = dirnameAllowEmpty(dep.sub_path) orelse {
                    dumpBadDirnameHelp(null, null,
                        \\dirname() attempted to traverse outside the dependency root.
                        \\
                    , .{}) catch {};
                    @panic("misconfigured build script");
                },
            } },
        };
    }

    pub fn path(lazy_path: LazyPath, b: *Build, sub_path: []const u8) LazyPath {
        const graph = b.graph;
        const arena = graph.arena;
        return lazy_path.join(arena, sub_path) catch @panic("OOM");
    }

    pub fn join(lazy_path: LazyPath, arena: Allocator, sub_path: []const u8) Allocator.Error!LazyPath {
        return switch (lazy_path) {
            .src_path => |src| .{ .src_path = .{
                .owner = src.owner,
                .sub_path = try fs.path.resolve(arena, &.{ src.sub_path, sub_path }),
            } },
            .generated => |gen| .{ .generated = .{
                .index = gen.index,
                .up = gen.up,
                .sub_path = try fs.path.resolve(arena, &.{ gen.sub_path, sub_path }),
            } },
            .cwd_relative => |cwd_relative| .{
                .cwd_relative = try fs.path.resolve(arena, &.{ cwd_relative, sub_path }),
            },
            .relative => |r| .{ .relative = .{
                .base = r.base,
                .sub_path = try fs.path.resolve(arena, &.{ r.sub_path, sub_path }),
            } },
            .dependency => |dep| .{ .dependency = .{
                .dependency = dep.dependency,
                .sub_path = try fs.path.resolve(arena, &.{ dep.sub_path, sub_path }),
            } },
        };
    }

    /// Deprecated, use `format` instead.
    pub fn getDisplayName(lazy_path: LazyPath) []const u8 {
        return switch (lazy_path) {
            .src_path => |sp| sp.sub_path,
            .cwd_relative => |p| p,
            .generated => "generated",
            .dependency => "dependency",
            .relative => |r| @tagName(r.base),
        };
    }

    pub fn format(lp: LazyPath, w: *Io.Writer) Io.Writer.Error!void {
        switch (lp) {
            .src_path => |sp| try w.writeAll(sp.sub_path),
            .cwd_relative => |p| try w.writeAll(p),
            .generated => try w.writeAll("generated"),
            .dependency => try w.writeAll("dependency"),
            .relative => |r| try w.print("{t} {s}", .{ r.base, r.sub_path }),
        }
    }

    /// Adds dependencies this file source implies to the given step.
    pub fn addStepDependencies(lazy_path: LazyPath, other_step: *Step) void {
        switch (lazy_path) {
            .src_path, .cwd_relative, .relative, .dependency => {},
            .generated => |gen| {
                const graph = other_step.owner.graph;
                const generated_owner_step = graph.generated_files.items[@intFromEnum(gen.index)];
                other_step.dependOn(generated_owner_step);
            },
        }
    }

    /// Copies the internal strings.
    ///
    /// The `graph` parameter is only used for the global arena allocator.
    pub fn dupe(lazy_path: LazyPath, graph: *const Graph) LazyPath {
        return dupeInner(lazy_path, graph.arena);
    }

    /// Copies the slice of paths and all internal strings.
    ///
    /// The `graph` parameter is only used for the global arena allocator.
    pub fn dupeList(lazy_paths: []const LazyPath, graph: *const Graph) []const LazyPath {
        const arena = graph.arena;
        const result = graph.alloc(LazyPath, lazy_paths.len);
        for (result, lazy_paths) |*d, s| d.* = dupeInner(s, arena);
        return result;
    }

    fn dupeInner(lazy_path: LazyPath, arena: Allocator) LazyPath {
        return switch (lazy_path) {
            .src_path => |sp| .{ .src_path = .{ .owner = sp.owner, .sub_path = sp.owner.dupePath(sp.sub_path) } },
            .cwd_relative => |p| .{ .cwd_relative = Graph.dupePathInner(arena, p) },
            .relative => |r| .{ .relative = r },
            .generated => |gen| .{ .generated = .{
                .index = gen.index,
                .up = gen.up,
                .sub_path = Graph.dupePathInner(arena, gen.sub_path),
            } },
            .dependency => |dep| .{ .dependency = .{
                .dependency = dep.dependency,
                .sub_path = Graph.dupePathInner(arena, dep.sub_path),
            } },
        };
    }
};

fn dumpBadDirnameHelp(
    fail_step: ?*Step,
    asking_step: ?*Step,
    comptime msg: []const u8,
    args: anytype,
) anyerror!void {
    const stderr = std.debug.lockStderr(&.{}).terminal();
    defer std.debug.unlockStderr();
    const w = stderr.writer;

    try w.print(msg, args);

    if (fail_step) |s| {
        stderr.setColor(.red) catch {};
        try w.writeAll("    The step was created by this stack trace:\n");
        stderr.setColor(.reset) catch {};

        s.dump(stderr);
    }

    if (asking_step) |as| {
        stderr.setColor(.red) catch {};
        try w.print("    The step '{s}' that is missing a dependency on the above step was created by this stack trace:\n", .{as.name});
        stderr.setColor(.reset) catch {};

        as.dump(stderr);
    }

    stderr.setColor(.red) catch {};
    try w.writeAll("    Proceeding to panic.\n");
    stderr.setColor(.reset) catch {};
}

pub const InstallDir = union(enum) {
    prefix: void,
    lib: void,
    bin: void,
    header: void,
    /// A path relative to the prefix
    custom: []const u8,

    /// Duplicates the install directory including the path if set to custom.
    pub fn dupe(dir: InstallDir, graph: *const Graph) InstallDir {
        if (dir == .custom) {
            return .{ .custom = graph.dupeString(dir.custom) };
        } else {
            return dir;
        }
    }
};

/// Creates a path leading to a directory inside "tmp" subdirectory of local
/// cache which is created on demand and cleaned up by the build runner upon
/// success.
pub fn tmpPath(b: *Build) LazyPath {
    const wf = b.addTempFiles();
    return wf.getDirectory();
}

/// A pair of target query and fully resolved target.
/// This type is generally required by build system API that need to be given a
/// target. The query is kept because the Zig toolchain needs to know which parts
/// of the target are "native". This can apply to the CPU, the OS, or even the ABI.
pub const ResolvedTarget = struct {
    query: Target.Query,
    result: Target,
};

/// Converts a target query into a fully resolved target that can be passed to
/// various parts of the API.
pub fn resolveTargetQuery(b: *Build, query: Target.Query) ResolvedTarget {
    if (query.isNative()) {
        // Hot path. This is faster than querying the native CPU and OS again.
        return b.graph.host;
    }
    const io = b.graph.io;
    return .{
        .query = query,
        .result = std.zig.system.resolveTargetQuery(io, query) catch
            @panic("unable to resolve target query"),
    };
}

pub fn wantSharedLibSymLinks(target: Target) bool {
    return target.os.tag != .windows;
}

pub const SystemIntegrationOptionConfig = struct {
    /// If left as null, then the default will depend on system_package_mode.
    default: ?bool = null,
};

pub fn systemIntegrationOption(
    b: *Build,
    name: []const u8,
    config: SystemIntegrationOptionConfig,
) bool {
    const graph = b.graph;
    const arena = graph.arena;
    const gop = graph.system_integration_options.getOrPut(arena, name) catch @panic("OOM");
    if (gop.found_existing) switch (gop.value_ptr.*) {
        .user_disabled => {
            gop.value_ptr.* = .declared_disabled;
            return false;
        },
        .user_enabled => {
            gop.value_ptr.* = .declared_enabled;
            return true;
        },
        .declared_disabled => return false,
        .declared_enabled => return true,
    } else {
        gop.key_ptr.* = graph.dupeString(name);
        if (config.default orelse graph.system_package_mode) {
            gop.value_ptr.* = .declared_enabled;
            return true;
        } else {
            gop.value_ptr.* = .declared_disabled;
            return false;
        }
    }
}

test {
    _ = Cache;
    _ = Step;
    _ = Configuration;
    _ = &findProgram;
}

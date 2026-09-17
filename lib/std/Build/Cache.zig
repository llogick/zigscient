//! Tracks metadata of file inputs associated with Zig compiler and build
//! system artifacts in order to determine whether those artifacts must be
//! produced again, or may be retrieved from the cache directory on the
//! filesystem.
const Cache = @This();
const builtin = @import("builtin");

const std = @import("std");
const Io = std.Io;
const crypto = std.crypto;
const assert = std.debug.assert;
const testing = std.testing;
const mem = std.mem;
const fmt = std.fmt;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.cache);

gpa: Allocator,
io: Io,
manifest_dir: Io.Dir,
hash: HashHelper = .{},
/// This value is accessed from multiple threads, protected by mutex.
recent_problematic_timestamp: Io.Timestamp = .zero,
mutex: Io.Mutex = .init,

/// A set of strings such as the zig library directory or project source root, which
/// are stripped from the file paths before putting into the cache. They
/// are replaced with single-character indicators. This is not to save
/// space but to eliminate absolute file paths. This improves portability
/// and usefulness of the cache for advanced use cases.
prefixes_buffer: [5]Directory = undefined,
prefixes_len: usize = 0,
/// Used to identify prefixes. References external memory.
cwd: []const u8,

pub const Path = @import("Cache/Path.zig");
pub const Directory = @import("Cache/Directory.zig");
pub const DepTokenizer = @import("Cache/DepTokenizer.zig");

pub fn addPrefix(cache: *Cache, directory: Directory) void {
    cache.prefixes_buffer[cache.prefixes_len] = directory;
    cache.prefixes_len += 1;
}

/// Be sure to call `Manifest.deinit` after successful initialization.
pub fn obtain(cache: *Cache) Manifest {
    return .{
        .cache = cache,
        .hash = cache.hash,
        .manifest_file = null,
        .state = .input,
    };
}

pub fn prefixes(cache: *const Cache) []const Directory {
    return cache.prefixes_buffer[0..cache.prefixes_len];
}

const PrefixIndex = u6;

const PrefixedPath = struct {
    prefix: PrefixIndex,
    sub_path: []const u8,
};

fn appendPrefixedPath(cache: *const Cache, contents: *std.ArrayList(u8), prefixed_path: PrefixedPath) !PrefixIndex {
    const end = contents.items.len + prefixed_path.sub_path.len;
    const needed_alignment = @alignOf(Manifest.File) - (end % @alignOf(Manifest.File));
    assert(needed_alignment >= 1); // Always need at least a null byte.
    // Extra +1 here is due to the requirement to keep at least 1 unused capacity in `Manifest.contents` at all times.
    try contents.ensureTotalCapacity(cache.gpa, end + needed_alignment + 1);
    contents.appendSliceAssumeCapacity(prefixed_path.sub_path);
    contents.appendNTimesAssumeCapacity(0, needed_alignment);
    return prefixed_path.prefix;
}

fn resolveAppendPath(cache: *const Cache, contents: *std.ArrayList(u8), path: Path) !PrefixIndex {
    const gpa = cache.gpa;
    const cwd = cache.cwd;
    const path_start = contents.items.len;

    const resolved_path = try std.fs.path.resolveAlloc(gpa, &.{
        path.root_dir.path orelse cwd,
        path.subPathOrDot(),
    });
    defer gpa.free(resolved_path);

    for (cache.prefixes(), 0..) |prefix, i| {
        const pp = prefix.path orelse continue;
        contents.shrinkRetainingCapacity(path_start);
        try std.fs.path.relativeAppend(gpa, contents, cwd, null, pp, resolved_path);
        const relative = contents.items[path_start..];

        var component_iterator: std.fs.path.NativeComponentIterator = .init(relative);
        if (component_iterator.root() != null) continue;
        const first_component = component_iterator.first();
        if (first_component != null and mem.eql(u8, first_component.?.name, "..")) continue;

        const needed_alignment = @alignOf(Manifest.File) - (contents.items.len % @alignOf(Manifest.File));
        assert(needed_alignment >= 1); // Always need at least a null byte.
        // Extra +1 here is due to the requirement to keep at least 1 unused capacity in `Manifest.contents` at all
        // times.
        try contents.ensureUnusedCapacity(gpa, needed_alignment + 1);
        contents.appendNTimesAssumeCapacity(0, needed_alignment);

        return @intCast(i);
    }

    contents.shrinkRetainingCapacity(path_start);
    try contents.appendSlice(gpa, resolved_path);

    const needed_alignment = @alignOf(Manifest.File) - (contents.items.len % @alignOf(Manifest.File));
    assert(needed_alignment >= 1); // Always need at least a null byte.
    // Extra +1 here is due to the requirement to keep at least 1 unused capacity in `Manifest.contents` at all times.
    try contents.ensureUnusedCapacity(gpa, needed_alignment + 1);
    contents.appendNTimesAssumeCapacity(0, needed_alignment);

    return 0;
}

/// This is 128 bits - Even with 2^54 cache entries, the probably of a collision would be under 10^-6
pub const bin_digest_len = 16;
pub const hex_digest_len = bin_digest_len * 2;
pub const BinDigest = [bin_digest_len]u8;
pub const HexDigest = [hex_digest_len]u8;

/// The type used for hashing file contents. Currently, this is SipHash128(1, 3), because it
/// provides enough collision resistance for the Manifest use cases, while being one of our
/// fastest options right now.
pub const Hasher = crypto.auth.siphash.SipHash128(1, 3);

/// Initial state with random bytes, that can be copied.
/// Refresh this with new random bytes when the manifest
/// format is modified in a non-backwards-compatible way.
pub const hasher_init: Hasher = Hasher.init(&.{
    0x02, 0xe9, 0xfa, 0xfe,
    0xe0, 0x95, 0x81, 0x55,
    0xf5, 0x5a, 0x15, 0xcb,
    0x4a, 0xf4, 0x00, 0x09,
});

pub const HashHelper = struct {
    hasher: Hasher = hasher_init,

    pub fn addBytes(hh: *HashHelper, bytes: []const u8) void {
        hh.hasher.update(mem.asBytes(&bytes.len));
        hh.hasher.update(bytes);
    }

    pub fn addBytesZ(hh: *HashHelper, bytes: [:0]const u8) void {
        hh.hasher.update(mem.absorbSentinel(bytes));
    }

    pub fn addOptionalBytes(hh: *HashHelper, optional_bytes: ?[]const u8) void {
        hh.add(optional_bytes != null);
        hh.addBytes(optional_bytes orelse return);
    }

    pub fn addListOfBytes(hh: *HashHelper, list_of_bytes: []const []const u8) void {
        hh.add(list_of_bytes.len);
        for (list_of_bytes) |bytes| hh.addBytes(bytes);
    }

    pub fn addOptionalListOfBytes(hh: *HashHelper, optional_list_of_bytes: ?[]const []const u8) void {
        hh.add(optional_list_of_bytes != null);
        hh.addListOfBytes(optional_list_of_bytes orelse return);
    }

    /// Convert the input value into bytes and record it as a dependency of the process being cached.
    pub fn add(hh: *HashHelper, x: anytype) void {
        switch (@TypeOf(x)) {
            std.SemanticVersion => {
                hh.add(x.major);
                hh.add(x.minor);
                hh.add(x.patch);
            },
            std.Target.Os.TaggedVersionRange => {
                switch (x) {
                    .hurd => |hurd| {
                        hh.add(hurd.range.min);
                        hh.add(hurd.range.max);
                        hh.add(hurd.glibc);
                    },
                    .linux => |linux| {
                        hh.add(linux.range.min);
                        hh.add(linux.range.max);
                        hh.add(linux.glibc);
                        hh.add(linux.android);
                    },
                    .windows => |windows| {
                        hh.add(windows.min);
                        hh.add(windows.max);
                    },
                    .semver => |semver| {
                        hh.add(semver.min);
                        hh.add(semver.max);
                    },
                    .none => {},
                }
            },
            std.zig.BuildId => switch (x) {
                .none, .fast, .uuid, .sha1, .md5 => hh.add(std.meta.activeTag(x)),
                .hexstring => |hex_string| hh.addBytes(hex_string.toSlice()),
            },
            else => switch (@typeInfo(@TypeOf(x))) {
                .bool, .int, .@"enum", .array => hh.addBytes(mem.asBytes(&x)),
                else => @compileError("unable to hash type " ++ @typeName(@TypeOf(x))),
            },
        }
    }

    pub fn addOptional(hh: *HashHelper, optional: anytype) void {
        hh.add(optional != null);
        hh.add(optional orelse return);
    }

    /// Returns a hex encoded hash of the inputs, without modifying state.
    pub fn peek(hh: HashHelper) [hex_digest_len]u8 {
        var copy = hh;
        return copy.final();
    }

    pub fn peekBin(hh: HashHelper) BinDigest {
        var copy = hh;
        var bin_digest: BinDigest = undefined;
        copy.hasher.final(&bin_digest);
        return bin_digest;
    }

    /// Returns a hex encoded hash of the inputs, mutating the state of the hasher.
    pub fn final(hh: *HashHelper) HexDigest {
        var bin_digest: BinDigest = undefined;
        hh.hasher.final(&bin_digest);
        return binToHex(bin_digest);
    }

    pub fn oneShot(bytes: []const u8) [hex_digest_len]u8 {
        var hasher: Hasher = hasher_init;
        hasher.update(bytes);
        var bin_digest: BinDigest = undefined;
        hasher.final(&bin_digest);
        return binToHex(bin_digest);
    }
};

pub fn binToHex(bin_digest: BinDigest) HexDigest {
    var out_digest: HexDigest = undefined;
    var w: Io.Writer = .fixed(&out_digest);
    w.printHex(&bin_digest, .lower) catch unreachable;
    return out_digest;
}

pub const Lock = struct {
    manifest_file: Io.File,

    pub fn release(lock: *Lock, io: Io) void {
        if (builtin.os.tag == .windows) {
            // Windows does not guarantee that locks are immediately unlocked when
            // the file handle is closed. See LockFileEx documentation.
            lock.manifest_file.unlock(io);
        }

        lock.manifest_file.close(io);
        lock.* = undefined;
    }
};

/// Format: a series of consecutive `Manifest.File`, followed by a final
/// terminating zero byte to distinguish empty manifest file from manifest with
/// zero files.
pub const Manifest = struct {
    cache: *Cache,
    /// Current state for incremental hashing.
    hash: HashHelper,
    /// When this is null, `Manifest` is in "pre-check" phase. Otherwise it is in "post-check" phase.
    manifest_file: ?Io.File,
    state: State,
    /// Set this flag to true before calling `check` in order to indicate that upon a cache hit, the code
    /// using the cache will not modify the files within the cache directory. This allows multiple processes
    /// to utilize the same cache directory at the same time.
    want_shared_lock: bool = true,
    have_exclusive_lock: bool = false,
    // Indicate that we want isProblematicTimestamp to perform a filesystem write in
    // order to obtain a problematic timestamp for the next call. Calls after that
    // will then use the same timestamp, to avoid unnecessary filesystem writes.
    want_refresh_timestamp: bool = true,
    /// Uses `Cache.gpa`.
    files: Files = .empty,
    /// Indexes line up with `files`, but only up until `hit` is called. Uses
    /// `Cache.gpa`.
    input_paths: std.ArrayList(InputPath) = .empty,
    /// Keeps track of the last time we performed a file system write to observe
    /// what time the file system thinks it is, according to its own granularity.
    recent_problematic_timestamp: Io.Timestamp = .zero,
    /// The entire manifest file contents, except for the final terminating
    /// zero byte. However maintains always at least 1 unused capacity so the
    /// final terminating byte can be added without allocation. Uses
    /// `Cache.gpa`.
    contents: std.ArrayList(u8) = .empty,
    /// All contents from all `input_paths` whose contents were requested,
    /// concatenated. Total byte size will be less than `max_input_content_len`
    /// otherwise an error is returned.
    ///
    /// Data is invalidated when `addDiscoveredPath` is called.
    all_input_content: std.ArrayList(u8) = .empty,
    max_input_content_len: usize = std.math.maxInt(u32),

    pub const Files = std.array_hash_map.Custom(File.Offset, void, File.HashContext, false);

    pub const State = enum {
        /// Call `addInputPath`, `addInputPathOptional`, and methods of `Manifest.hash`. Once all input files and state
        /// have been added, call `check`.
        input,
        /// `check` has already been called and a hit occurred. Call `hitDigest` to find cache artifact directory.
        hit,
        /// `hitDigest` has already been called. No further operations are allowed.
        hit_digested,
        /// `check` has already been called and a miss occurred. `missDigest` has not been called yet. Miss diagnostic
        /// data may still be accessed. Call `addDiscoveredPath` to add discovered files and directories.
        miss,
        /// A miss occurred, `missDigest` has not been called yet. Call `addDiscoveredPath` to add more discovered files
        /// and directories. Miss diagnostic data may no longer be accessed.
        miss_discovered,
        /// `missDigest` has been called, but `finalize` has not been called yet.
        miss_digested,
        /// The cache manifest has been written to disk such that the next check for the same inputs will yield a hit.
        /// No further operations are allowed.
        miss_finalized,
    };

    /// Source files and directories whose prefix and relative path are
    /// included when computing the cache manifest digest. It's the information
    /// needed to lazily hash the input files only when a cache miss occurs.
    ///
    /// `File.prefix`, `File.path`, and `File.mode` will be always populated,
    /// but the other fields of `File` will be populated depending on the
    /// fields of `InputPath`.
    pub const InputPath = struct {
        /// Determines whether `check` will keep the handle open or close it.
        request_handle: bool,
        /// Determines whether `handle` is populated.
        have_handle: bool,
        /// Determines whether `File.size`, `File.inode`, and `File.mtime` are populated.
        have_stat: bool,
        /// Determines whether `File.digest` is populated.
        have_digest: bool,
        contents: struct {
            pop_off: enum(u32) { unpopulated = std.math.maxInt(u32), _ },
            req_len: enum(u32) { unrequested = std.math.maxInt(u32) - 1, requested = std.math.maxInt(u32), _ },

            pub const requested: @This() = .{
                .pop_off = .unpopulated,
                .req_len = .requested,
            };

            pub const unrequested: @This() = .{
                .pop_off = .unpopulated,
                .req_len = .unrequested,
            };

            pub fn populated(p: Populated) @This() {
                return .{
                    .pop_off = @fromBackingInt(p.off),
                    .req_len = @fromBackingInt(p.len),
                };
            }

            pub const Unwrapped = union(enum) {
                unrequested,
                requested,
                populated: Populated,
            };

            pub const Populated = struct {
                off: u32,
                len: u32,
            };

            pub fn unwrap(this: @This()) Unwrapped {
                return switch (this.pop_off) {
                    .unpopulated => switch (this.req_len) {
                        .unrequested => .unrequested,
                        .requested => .requested,
                        _ => unreachable,
                    },
                    _ => .{ .populated = .{
                        .off = @backingInt(this.pop_off),
                        .len = @backingInt(this.req_len),
                    } },
                };
            }

            pub fn get(this: @This(), all_contents: []const u8) ?[]const u8 {
                return switch (this.unwrap()) {
                    .unrequested, .requested => null,
                    .populated => |p| all_contents[p.off..][0..p.len],
                };
            }
        },
        /// `have_handle` determines whether this is populated.
        handle: union {
            file: Io.File,
            dir: Io.Dir,
        },

        pub const Handle = union(enum) {
            none,
            file: Io.File,
            dir: Io.Dir,
        };

        /// Index into `Manifest.input_paths`.
        pub const Index = enum(u32) {
            _,

            pub fn get(i: @This(), manifest: *const Manifest) InputPath {
                return manifest.input_paths.items[@backingInt(i)];
            }

            pub fn offset(i: @This(), manifest: *const Manifest) File.Offset {
                return manifest.files.keys()[@backingInt(i)];
            }

            pub fn contents(i: @This(), manifest: *const Manifest) []const u8 {
                const input_path = get(i, manifest);
                return input_path.contents.get(manifest.all_input_content.items).?;
            }
        };

        pub fn getHandle(this: @This(), file: *const File) Handle {
            return if (!this.have_handle) .none else switch (file.flags.is_directory) {
                false => .{ .file = this.handle.file },
                true => .{ .dir = this.handle.dir },
            };
        }
    };

    /// The data per tracked input file that is stored in the manifest file.
    pub const File = extern struct {
        size: u64 align(1),
        inode: Io.File.INode align(1),
        /// Nanoseconds.
        mtime: i64 align(1),
        /// To simplify the hashing logic, this value is computed from size, inode, and mtime
        /// in `hashFromMetadata` in the case that `Flags.metadata_only` is `true`.
        digest: BinDigest align(1),
        /// Starting with this field and continuing into the path, excluding the null byte,
        /// is the string that is hashed for the manifest digest.
        flags: Flags align(1),
        /// Terminated by zero byte, then followed by padding until 8-byte aligned.
        path_start: [0]u8 align(1),

        pub const Flags = packed struct(u8) {
            is_directory: bool,
            metadata_only: bool,
            prefix: PrefixIndex,
        };

        /// Prefixes path names in encoded directory contents. Starts numbering
        /// at `1` so that null byte can be used unambiguously as entry
        /// separator.
        pub const Kind = enum(u8) {
            file = 1,
            directory = 2,
            other = 3,

            pub fn fromStat(kind: Io.File.Kind) @This() {
                return switch (kind) {
                    .file => .file,
                    .directory => .directory,
                    else => .other,
                };
            }
        };

        /// Byte index within `Manifest.contents` where the entry starts.
        pub const Offset = enum(u32) {
            _,

            pub fn get(offset: Offset, contents: []u8) *File {
                return @constCast(getConst(offset, contents));
            }

            pub fn getConst(offset: Offset, contents: []const u8) *const File {
                return @ptrCast(@alignCast(contents[@backingInt(offset)..][0..@sizeOf(File)]));
            }

            pub fn getFallible(offset: Offset, contents: []u8) error{InvalidFormat}!*File {
                // TODO make @constCast support in-memory coercion across error unions and optionals
                return @constCast(try getFallibleConst(offset, contents));
            }

            pub fn getFallibleConst(offset: Offset, contents: []const u8) error{InvalidFormat}!*const File {
                if (@backingInt(offset) + @sizeOf(File) >= contents.len) return error.InvalidFormat;
                if (!mem.isAligned(@backingInt(offset), @alignOf(File))) return error.InvalidFormat;
                return getConst(offset, contents);
            }

            pub fn flagsAndPath(off: File.Offset, contents: []const u8) [:0]const u8 {
                const flags_off = @offsetOf(File, "flags");
                comptime assert(@offsetOf(File, "path_start") - flags_off == 1);
                const start = @backingInt(off) + flags_off;
                // Scan for the sentinel starting from the path_start offset because flags might be zero.
                const end = mem.findScalarPos(u8, contents, start + 1, 0).?;
                return contents[start..end :0];
            }

            pub fn pathFallible(off: File.Offset, contents: []const u8) error{InvalidFormat}![:0]const u8 {
                const path_start = @backingInt(off) + @offsetOf(File, "path_start");
                const path_end = mem.findScalarPos(u8, contents, path_start, 0) orelse return error.InvalidFormat;
                return contents[path_start..path_end :0];
            }

            pub fn path(off: File.Offset, contents: []const u8) [:0]const u8 {
                return pathFallible(off, contents) catch unreachable;
            }
        };

        /// Intentionally matches if the files are different only by flags other than prefix.
        pub const HashContext = struct {
            contents: []const u8,

            pub fn hash(this: @This(), off: Offset) u32 {
                const file_prefix = off.getConst(this.contents).flags.prefix;
                const file_path = off.path(this.contents);
                return @truncate(std.hash.Wyhash.hash(file_prefix, file_path));
            }

            pub fn eql(this: @This(), a_off: Offset, b_off: Offset, b_index: usize) bool {
                _ = b_index;
                const a_prefix = a_off.getConst(this.contents).flags.prefix;
                const b_prefix = b_off.getConst(this.contents).flags.prefix;
                if (a_prefix != b_prefix) return false;
                const a_path = a_off.path(this.contents);
                const b_path = b_off.path(this.contents);
                return mem.eql(u8, a_path, b_path);
            }
        };

        fn hashFromMetadata(file: *File) void {
            var hasher = hasher_init;
            hasher.update(mem.asBytes(&file.size));
            hasher.update(mem.asBytes(&file.inode));
            hasher.update(mem.asBytes(&file.mtime));
            hasher.final(&file.digest);
        }

        fn stat(file: *const File) Stat {
            return .{
                .size = file.size,
                .inode = file.inode,
                .mtime = .fromNanoseconds(file.mtime),
            };
        }

        fn setStatUnchecked(file: *File, s: Stat) void {
            file.size = s.size;
            file.inode = s.inode;
            file.mtime = @intCast(s.mtime.toNanoseconds());
        }

        fn setStat(file: *File, m: *Manifest, s: Stat) Io.Cancelable!void {
            setStatUnchecked(file, s);

            if (try m.isProblematicTimestamp(s.mtime)) {
                // The actual file has an unreliable timestamp; force it to be hashed.
                file.mtime = 0;
                file.inode = 0;
            }
        }

        /// Returns true if the stat was changed. Updates the `file` with the new stat value.
        fn setStatChanged(file: *File, m: *Manifest, s: Stat) Io.Cancelable!bool {
            if (s.size == file.size and
                s.mtime.nanoseconds == file.mtime and
                s.inode == file.inode)
            {
                return false;
            } else {
                try setStat(file, m, s);
                return true;
            }
        }

        /// `path_len` does not include the null byte.
        pub fn sizeOf(path_len: usize) usize {
            const end = @offsetOf(File, "path_start") + path_len;
            const needed_alignment = @alignOf(File) - (end % @alignOf(File));
            assert(needed_alignment >= 1); // Always need at least a null byte.
            return end + needed_alignment;
        }
    };

    pub const CheckDiagnostic = union(enum) {
        manifest_create: Io.File.OpenError,
        manifest_stat: Io.File.StatError,
        manifest_oversize,
        manifest_read: Io.File.ReadPositionalError,
        manifest_lock: Io.File.LockError,
        file_open: FileOp,
        file_stat: FileOp,
        file_read: FileOp,
        file_hash: FileOp,

        pub const FileOp = struct {
            file_offset: File.Offset,
            err: anyerror,

            /// Returned `Path` references `Manifest.contents`.
            pub fn path(fo: FileOp, manifest: *const Manifest) Path {
                const contents = manifest.contents.items;
                const prefix = fo.file_offset.get(contents).flags.prefix;
                return .{
                    .root_dir = manifest.cache.prefixes()[prefix],
                    .sub_path = fo.file_offset.path(contents),
                };
            }
        };

        pub const Format = struct {
            diagnostic: CheckDiagnostic,
            manifest: *const Manifest,

            pub fn format(this: @This(), w: *Io.Writer) Io.Writer.Error!void {
                switch (this.diagnostic) {
                    .manifest_oversize => return w.writeAll(@tagName(this.diagnostic)),
                    .manifest_create, .manifest_stat, .manifest_read, .manifest_lock => |e| {
                        return w.print("{t} {t}", .{ this.diagnostic, e });
                    },
                    .file_open, .file_stat, .file_read, .file_hash => |op| {
                        const path = op.path(this.manifest);
                        return w.print("{t} {t} {f}", .{ this.diagnostic, op.err, path });
                    },
                }
            }
        };

        pub fn fmt(diagnostic: CheckDiagnostic, manifest: *const Manifest) Format {
            return .{
                .diagnostic = diagnostic,
                .manifest = manifest,
            };
        }
    };

    pub const Stat = struct {
        size: u64,
        inode: Io.File.INode,
        mtime: Io.Timestamp,

        pub fn init(other: Io.File.Stat) Stat {
            return .{
                .size = other.size,
                .inode = other.inode,
                .mtime = other.mtime,
            };
        }
    };

    pub const PathHandle = union(enum) {
        file: ?Io.File,
        /// If provided, this handle must be opened with iteration capability.
        dir: ?Io.Dir,

        pub fn isDirectory(this: @This()) bool {
            return this == .dir;
        }

        pub fn have(this: @This()) bool {
            return switch (this) {
                .file => |opt_file| opt_file != null,
                .dir => |opt_dir| opt_dir != null,
            };
        }
    };

    pub const AddInputPathOptions = struct {
        /// If provided, will be closed when `check` is called, unless `request_handle` is also set.
        handle: PathHandle = .{ .file = null },
        stat: ?Stat = null,
        /// If set, file handle will remain open after `check` is called.
        request_handle: bool = false,
        /// Can request file or directory contents depending on `handle`.
        request_contents: bool = false,
        /// Content hashing skipped; any difference in metadata implies cache
        /// miss.
        metadata_only: bool = false,
    };

    /// Add a file or directory path as a dependency of process being cached.
    /// When `hit` is called, the contents will be checked to ensure
    /// that it matches the contents from previous times.
    ///
    /// The contents of the input file may be requested and subsequently
    /// obtained via methods of the returned `InputPath.Index` after calling
    /// `hit`.
    ///
    /// Contents of a directory are considered to be the sorted list of file
    /// names of direct entries, separated by null byte. Each file name is
    /// prefixed by `Io.File.Kind` byte, +1 so that the zero tag is not aliased
    /// by the entry separator.
    ///
    /// See also:
    /// * `addDiscoveredPath`
    pub fn addInputPath(m: *Manifest, path: Path, options: AddInputPathOptions) Allocator.Error!InputPath.Index {
        assert(m.state == .input);
        const cache = m.cache;
        const gpa = cache.gpa;
        const is_directory = options.handle.isDirectory();

        try m.files.ensureUnusedCapacityContext(gpa, 1, .{ .contents = m.contents.items });
        try m.input_paths.ensureUnusedCapacity(gpa, 1);

        const new_file_offset: File.Offset = @fromBackingInt(@intCast(m.contents.items.len));
        try m.contents.appendNTimes(gpa, 0, @offsetOf(File, "path_start"));
        errdefer m.contents.shrinkRetainingCapacity(@backingInt(new_file_offset));

        const new_prefix = try cache.resolveAppendPath(&m.contents, path);
        assert(mem.isAligned(m.contents.items.len, @alignOf(File)));
        new_file_offset.get(m.contents.items).flags = .{
            .prefix = new_prefix,
            .is_directory = is_directory,
            .metadata_only = options.metadata_only,
        };

        const gop = m.files.getOrPutAssumeCapacityContext(new_file_offset, .{ .contents = m.contents.items });
        m.files.lockPointers();
        defer m.files.unlockPointers();

        if (gop.found_existing) {
            m.contents.shrinkRetainingCapacity(@backingInt(new_file_offset));
            const existing_input_file = &m.input_paths.items[gop.index];
            switch (options.handle) {
                .file => |opt_file| if (opt_file) |file| {
                    existing_input_file.handle = .{ .file = file };
                    existing_input_file.have_handle = true;
                },
                .dir => |opt_dir| if (opt_dir) |dir| {
                    existing_input_file.handle = .{ .dir = dir };
                    existing_input_file.have_handle = true;
                },
            }
            if (options.request_contents) switch (existing_input_file.contents.unwrap()) {
                .requested, .unrequested => existing_input_file.contents = .requested,
                .populated => {},
            };
            const existing_header = m.files.keys()[gop.index].get(m.contents.items);
            if (options.stat) |stat| {
                existing_input_file.have_stat = true;
                existing_header.size = stat.size;
                existing_header.inode = stat.inode;
                existing_header.mtime = @intCast(stat.mtime.toNanoseconds());
            }
            // If it trips, the same file path has been added to the cache
            // manifest both as a directory and as a normal file, making the
            // intended caching behavior ambiguous.
            assert(existing_header.flags.is_directory == is_directory);
            if (!options.metadata_only)
                existing_header.flags.metadata_only = false;
        } else {
            m.input_paths.appendAssumeCapacity(.{
                .request_handle = options.request_handle,
                .have_handle = options.handle.have(),
                .handle = switch (options.handle) {
                    .file => |opt_file| if (opt_file) |file| .{ .file = file } else undefined,
                    .dir => |opt_dir| if (opt_dir) |dir| .{ .dir = dir } else undefined,
                },
                .contents = if (options.request_contents) .requested else .unrequested,
                .have_digest = false,
                .have_stat = options.stat != null,
            });
            assert(m.input_paths.items.len - 1 == gop.index);
            if (options.stat) |stat| {
                const header = new_file_offset.get(m.contents.items);
                header.size = stat.size;
                header.inode = stat.inode;
                header.mtime = @intCast(stat.mtime.toNanoseconds());
            }
        }
        return @fromBackingInt(@intCast(gop.index));
    }

    pub fn addInputPathOptional(m: *Manifest, opt_path: ?Path, options: AddInputPathOptions) Allocator.Error!void {
        assert(m.state == .input);
        m.hash.add(opt_path != null);
        _ = try addInputPath(m, opt_path orelse return, options);
    }

    pub const AddInputDepFileError = error{
        InvalidDepFile,
    } || Allocator.Error || Io.File.OpenError || Io.File.Reader.Error;

    pub fn addInputDepFile(m: *Manifest, path: Path, diagnostic: ?*DepTokenizer.Token) AddInputDepFileError!void {
        assert(m.manifest_file == null);
        assert(m.state == .input);

        const cache = m.cache;
        const gpa = cache.gpa;
        const io = cache.io;

        // TODO: change DepTokenizer to be streaming rather than operating on slice of bytes.
        const prev_len = m.all_input_content.items.len;
        defer m.all_input_content.items.len = prev_len;

        const file = try path.root_dir.handle.openFile(io, path.sub_path, .{});
        defer file.close(io);

        var file_reader: Io.File.Reader = .init(file, io, &.{});
        file_reader.interface.appendRemainingUnlimited(gpa, &m.all_input_content) catch |err| switch (err) {
            error.OutOfMemory => |e| return e,
            error.ReadFailed => return file_reader.err.?,
        };

        var aux: std.ArrayList(u8) = .empty;
        defer aux.deinit(gpa);

        var it: DepTokenizer = .{ .bytes = m.all_input_content.items[prev_len..] };
        while (it.next()) |token| switch (token) {
            .target, .target_must_resolve => {},
            .prereq => |file_path| {
                _ = try m.addInputPath(.initCwd(file_path), .{});
            },
            .prereq_must_resolve => {
                aux.clearRetainingCapacity();
                try token.resolve(gpa, &aux);
                _ = try m.addInputPath(.initCwd(aux.items), .{});
            },
            else => |err| {
                if (diagnostic) |d| d.* = err;
                return error.InvalidDepFile;
            },
        };
    }

    pub const CheckResult = union(enum) {
        hit,
        incomplete_manifest,
        invalid_manifest,
        path_deleted: File.Offset,
        directory_status_changed: File.Offset,
        metadata_changed: File.Offset,
        contents_changed: File.Offset,

        pub const Format = struct {
            check_result: CheckResult,
            manifest: *const Manifest,

            pub fn format(this: @This(), w: *Io.Writer) Io.Writer.Error!void {
                switch (this.check_result) {
                    .hit, .incomplete_manifest, .invalid_manifest => return w.writeAll(@tagName(this.check_result)),
                    .path_deleted, .directory_status_changed, .metadata_changed, .contents_changed => |off| {
                        const path = off.path(this.manifest.contents.items);
                        return w.print("{t} {s}", .{ this.check_result, path });
                    },
                }
            }
        };

        pub fn fmt(check_result: CheckResult, manifest: *const Manifest) Format {
            return .{
                .check_result = check_result,
                .manifest = manifest,
            };
        }
    };

    pub const CheckError = error{
        /// Unable to check the cache for a reason that has been recorded into
        /// the `diagnostic` field.
        CacheCheckFailed,
    } || Allocator.Error || Io.Cancelable;

    /// Check the cache to see if the input exists in it.
    /// A hex encoding of its hash is available by calling `final`.
    ///
    /// This function will also acquire an exclusive lock to the manifest file. This means
    /// that a process holding a Manifest will block any other process attempting to
    /// acquire the lock. If `want_shared_lock` is `true`, a cache hit guarantees the
    /// manifest file to be locked in shared mode, and a cache miss guarantees the manifest
    /// file to be locked in exclusive mode.
    ///
    /// The lock on the manifest file is released when `deinit` is called. As another
    /// option, one may call `toOwnedLock` to obtain a smaller object which can represent
    /// the lock. `deinit` is safe to call whether or not `toOwnedLock` has been called.
    pub fn check(
        man: *Manifest,
        diag: *CheckDiagnostic,
        parent_progress_node: std.Progress.Node,
    ) CheckError!CheckResult {
        const node = parent_progress_node.start("Reusing Cache Artifacts", 0);
        defer node.end();
        return checkProgressless(man, diag);
    }

    pub fn checkProgressless(man: *Manifest, diag: *CheckDiagnostic) CheckError!CheckResult {
        assert(man.state == .input);
        assert(man.manifest_file == null);

        // This is *not* hashing the contents of the input files. It is the
        // flags (including prefix) and path only.
        for (man.files.keys()[0..man.input_paths.items.len]) |file_off| {
            const flags_and_path = file_off.flagsAndPath(man.contents.items);
            man.hash.hasher.update(mem.absorbSentinel(flags_and_path));
        }

        var input_digest: BinDigest = undefined;
        man.hash.hasher.final(&input_digest);
        const input_hex_digest = binToHex(input_digest);

        const manifest_file_path = &input_hex_digest;
        const io = man.cache.io;

        // We'll try to open the cache with an exclusive lock, but if that would block
        // and `want_shared_lock` is set, a shared lock might be sufficient, so we'll
        // open with a shared lock instead.
        while (true) {
            if (man.cache.manifest_dir.createFile(io, manifest_file_path, .{
                .read = true,
                .truncate = false,
                .lock = .exclusive,
                .lock_nonblocking = man.want_shared_lock,
            })) |manifest_file| {
                man.manifest_file = manifest_file;
                man.have_exclusive_lock = true;
                break;
            } else |err| switch (err) {
                error.WouldBlock => {
                    man.manifest_file = man.cache.manifest_dir.openFile(io, manifest_file_path, .{
                        .mode = .read_write,
                        .lock = .shared,
                    }) catch |e| return fail(diag, .{ .manifest_create = e });
                    break;
                },
                error.FileNotFound => {
                    // There are no dir components, so the only possibility
                    // should be that the directory behind the handle has been
                    // deleted, however we have observed on macOS two processes
                    // racing to do openat() with O_CREAT manifest in ENOENT.
                    //
                    // As a workaround, we retry with exclusive=true which
                    // disambiguates by returning EEXIST, indicating original
                    // failure was a race, or ENOENT, indicating deletion of
                    // the directory of our open handle.
                    if (!builtin.os.tag.isDarwin()) return fail(diag, .{ .manifest_create = error.FileNotFound });

                    if (man.cache.manifest_dir.createFile(io, manifest_file_path, .{
                        .read = true,
                        .truncate = false,
                        .lock = .exclusive,
                        .lock_nonblocking = man.want_shared_lock,
                        .exclusive = true,
                    })) |manifest_file| {
                        man.manifest_file = manifest_file;
                        man.have_exclusive_lock = true;
                        break;
                    } else |excl_err| switch (excl_err) {
                        error.WouldBlock, error.PathAlreadyExists => continue,
                        error.FileNotFound => return fail(diag, .{ .manifest_create = error.FileNotFound }),
                        error.Canceled => |e| return e,
                        else => |e| return fail(diag, .{ .manifest_create = e }),
                    }
                },
                error.Canceled => |e| return e,
                else => |e| return fail(diag, .{ .manifest_create = e }),
            }
        }

        man.want_refresh_timestamp = true;

        // We're going to construct a second hash. Its input will begin with the digest we've already computed
        // (`input_digest`), and then it'll have the digests of each input file, including discovered files (see
        // `addDiscoveredPath`). If this is a hit, we learn the set of discovered files from the manifest on disk. If
        // this is a miss, we'll learn those from future calls to `addDiscoveredPath` etc. As such, the state of
        // `man.hash.hasher` after this function depends on whether this is a hit or a miss.
        //
        // If we return `CacheStatus.hit`, then `man.hash.hasher` must already include the digests of the discovered
        // files, so the caller can call `final`. Otherwise, on a cache miss, `man.hash.hasher` will include the digests
        // of all non-discovered files -- that is, the ones we've already been told about. The rest will be discovered
        // through calls to `addDiscoveredPath` etc, which will update the hasher. After all files are added, the user
        // can use `final`, and will at some point `finalize` the file list to disk.
        man.hash.hasher = hasher_init;
        man.hash.hasher.update(&input_digest);

        hit: {
            const miss_result = miss: {
                const result = try man.checkLocked(diag);
                if (result == .hit) {
                    break :hit;
                } else if (!try man.upgradeToExclusiveLock(diag)) {
                    break :miss result;
                }
                // Missed with the shared lock, and upgraded to an exclusive lock. However, another process may have
                // modified the cache directory, so we need to check again before deciding to miss.
                man.shrinkFilesToInput();
                const refreshed_result = try man.checkLocked(diag);
                if (refreshed_result == .hit) break :hit;
                break :miss refreshed_result;
            };

            // Cache miss, but `checkLocked` guarantees that all input files have their digests computed, even on a
            // cache miss, which is needed because they will be used in the manifest digest.
            man.state = .miss;
            return miss_result;
        }

        if (man.want_shared_lock) {
            man.downgradeToSharedLock() catch |err| return fail(diag, .{ .manifest_lock = err });
        }

        man.state = .hit;
        return .hit;
    }

    fn transitionToMissDiscovered(m: *Manifest) void {
        switch (m.state) {
            .input => unreachable,
            .hit => unreachable,
            .hit_digested => unreachable,
            .miss => {
                m.shrinkFilesToInput();
                m.state = .miss_discovered;
            },
            .miss_discovered => {},
            .miss_digested => unreachable,
            .miss_finalized => unreachable,
        }
    }

    fn shrinkFilesToInput(m: *Manifest) void {
        if (m.files.count() <= m.input_paths.items.len) return;
        // Reads from files hash map whose data is destroyed on the next line.
        const off = m.files.keys()[m.input_paths.items.len];
        // Reads from the unshrunken contents whose data is destroyed on the next line.
        m.files.shrinkRetainingCapacityContext(m.input_paths.items.len, .{ .contents = m.contents.items });
        m.contents.shrinkRetainingCapacity(@backingInt(off));
        assert(mem.isAligned(m.contents.items.len, @alignOf(File)));
    }

    /// Does not observe or modify `self.hash.hasher`. Asserts `self.files` contains only the original input files.
    fn checkLocked(m: *Manifest, diag: *CheckDiagnostic) CheckError!CheckResult {
        assert(m.files.count() == m.input_paths.items.len);
        const gpa = m.cache.gpa;
        const io = m.cache.io;
        const manifest_file = m.manifest_file.?;

        const manifest_stat = manifest_file.stat(io) catch |err| switch (err) {
            error.Canceled => |e| return e,
            else => |e| return fail(diag, .{ .manifest_stat = e }),
        };
        const manifest_size = std.math.cast(u32, manifest_stat.size) orelse
            return fail(diag, .manifest_oversize);

        if (manifest_size == 0 or manifest_size < m.contents.items.len) {
            // Manifest file was never finalized.
            try m.contents.ensureUnusedCapacity(gpa, 1);
            return populateMissingInputFileHashes(m, diag, 0, .incomplete_manifest);
        }

        // We must not clobber existing `Manifest.contents` because it possibly contains prepopulated stat and digest
        // information which we must compare with the file system. Since non input files are typically greater in number
        // than input files, the strategy here is to move the contents to make room for entirety of the manifest
        // contents on disk, and then later truncate the contents array.
        //
        // The file on disk already supposedly includes the extra null byte that we have to maintain.
        const input_contents_len = m.contents.items.len;
        // After this resize, every return statement needs to modify m.contents length.
        try m.contents.resize(gpa, input_contents_len + manifest_size);
        errdefer m.contents.shrinkRetainingCapacity(input_contents_len);
        @memcpy(m.contents.items[manifest_size..][0..input_contents_len], m.contents.items[0..input_contents_len]);
        {
            const n = manifest_file.readPositionalAll(io, m.contents.items, 0) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => |e| return fail(diag, .{ .manifest_read = e }),
            };
            if (n != manifest_size) return missInput(m, diag, 0, input_contents_len, manifest_size, .incomplete_manifest);
        }
        const disk_contents = m.contents.items[0..manifest_size];
        const input_contents = m.contents.items[manifest_size..][0..input_contents_len];

        // First the input files section, which must match our input files, otherwise it's invalid or incomplete.
        var off: usize = 0;
        for (m.input_paths.items, m.files.keys()[0..m.input_paths.items.len], 0..) |*input_path, file_off, i| {
            if (@backingInt(file_off) + 1 >= disk_contents.len)
                return missInput(m, diag, i, input_contents_len, manifest_size, .incomplete_manifest);
            if (!mem.eql(u8, file_off.flagsAndPath(disk_contents), file_off.flagsAndPath(input_contents)))
                return missInput(m, diag, i, input_contents_len, manifest_size, .invalid_manifest);

            const result = try checkInputPath(m, diag, file_off, input_path, disk_contents, input_contents);
            if (result != .hit) return missInput(m, diag, i + 1, input_contents_len, manifest_size, result);
            off = @backingInt(file_off);
        }

        // Guess number of files based on manifest contents len to reduce allocations.
        // This is not an upper bound; subsequent insertions may potentially allocate.
        try m.files.ensureUnusedCapacityContext(gpa, disk_contents.len / (@sizeOf(File) + 32), .{
            .contents = disk_contents,
        });

        // Validate and check discovered files.
        while (off + 1 < disk_contents.len) {
            const file_off: File.Offset = @fromBackingInt(@intCast(off));
            const file = file_off.getFallible(disk_contents) catch return .invalid_manifest;
            if (file.flags.prefix >= m.cache.prefixes_len) return .invalid_manifest;
            const path = file_off.pathFallible(disk_contents) catch return .invalid_manifest;
            if (path.len == 0) return .invalid_manifest;

            try m.files.putContext(gpa, file_off, {}, .{ .contents = disk_contents });
            const result = try checkDiscoveredPath(m, diag, file_off, disk_contents);
            if (result != .hit) return result;

            off += File.sizeOf(path.len);
        }

        // Final terminating zero byte to distinguish empty manifest file from
        // manifest with zero files.
        const file_valid = off + 1 == disk_contents.len and disk_contents[off] == 0;
        if (!file_valid) return .incomplete_manifest;

        // Since it's a cache hit, we accept the input file contents from disk and discard the other copy.
        // Furthermore, don't track the trailing zero byte in contents.
        m.contents.shrinkRetainingCapacity(manifest_size - 1);
        return .hit;
    }

    /// Restore input file contents to prepare for cache miss workflow. We want to keep everything prior to `off` to
    /// avoid redundant computation of digest and stat.
    ///
    /// Furthermore, this function is responsible for populating the remaining input file digests and metadata after the
    /// missed one.
    fn missInput(
        m: *Manifest,
        diag: *CheckDiagnostic,
        next_file_index: usize,
        input_contents_len: usize,
        manifest_size: usize,
        result: CheckResult,
    ) CheckError!CheckResult {
        const file_offs = m.files.keys();
        const off = if (file_offs.len - next_file_index == 0)
            input_contents_len
        else
            @backingInt(file_offs[next_file_index]);
        const copy_len = input_contents_len - off;
        if (manifest_size > 0) @memcpy(
            m.contents.items[off..][0..copy_len],
            m.contents.items[manifest_size + off ..][0..copy_len],
        );
        m.contents.shrinkRetainingCapacity(input_contents_len);
        return populateMissingInputFileHashes(m, diag, next_file_index, result);
    }

    fn populateMissingInputFileHashes(
        m: *Manifest,
        diag: *CheckDiagnostic,
        next_file_index: usize,
        result: CheckResult,
    ) CheckError!CheckResult {
        const file_offs = m.files.keys();
        const contents = m.contents.items;
        for (file_offs[next_file_index..], m.input_paths.items[next_file_index..]) |input_file_off, *input_path| {
            try populateInputPath(m, diag, input_file_off, input_path, contents);
        }
        return result;
    }

    /// Similar to `checkInputPath` and `checkDiscoveredPath` but does not compare metadata or digest against file
    /// system. Only ensures that metadata and digest are available.
    fn populateInputPath(
        m: *Manifest,
        diag: *CheckDiagnostic,
        file_off: File.Offset,
        input_path: *InputPath,
        contents: []u8,
    ) CheckError!void {
        const cache = m.cache;
        const io = cache.io;
        const input_file = file_off.get(contents);
        const parent_dir = cache.prefixes()[input_file.flags.prefix].handle;
        const file_path = file_off.path(contents);
        const gpa = cache.gpa;

        if (input_path.have_digest) return;

        const stat_path_ok = switch (input_path.contents.unwrap()) {
            .populated => true,
            .unrequested, .requested => input_file.flags.metadata_only,
        };
        if (!input_path.have_stat and stat_path_ok) {
            // Since this is an input file, FileNotFound counts as a failure, not a cache miss.
            const actual_stat = switch (input_path.getHandle(input_file)) {
                .none => parent_dir.statFile(io, file_path, .{}) catch |err| switch (err) {
                    error.Canceled => |e| return e,
                    else => |e| return fail(diag, .{ .file_stat = .{
                        .file_offset = file_off,
                        .err = e,
                    } }),
                },
                .file => |opened_file| opened_file.stat(io) catch |err| switch (err) {
                    error.Canceled => |e| return e,
                    else => |e| return fail(diag, .{ .file_stat = .{
                        .file_offset = file_off,
                        .err = e,
                    } }),
                },
                .dir => |opened_dir| opened_dir.stat(io) catch |err| switch (err) {
                    error.Canceled => |e| return e,
                    else => |e| return fail(diag, .{ .file_stat = .{
                        .file_offset = file_off,
                        .err = e,
                    } }),
                },
            };
            const actual_is_directory = actual_stat.kind == .directory;
            if (actual_is_directory != input_file.flags.is_directory) {
                // Since this is an input file, this is a failure, not a cache miss.
                return fail(diag, .{ .file_stat = .{
                    .file_offset = file_off,
                    .err = if (actual_is_directory) error.IsDir else error.NotDir,
                } });
            }
            try input_file.setStat(m, .init(actual_stat));
        }

        if (input_file.flags.metadata_only) {
            assert(stat_path_ok);
            input_file.hashFromMetadata();
            return;
        }

        if (input_path.contents.get(m.all_input_content.items)) |file_or_dir_contents| {
            assert(stat_path_ok);
            var hasher = hasher_init;
            hasher.update(file_or_dir_contents);
            hasher.final(&input_file.digest);
            return;
        }

        if (input_file.flags.is_directory) {
            const opened_dir = if (input_path.have_handle)
                input_path.handle.dir
            else
                parent_dir.openDir(io, file_path, .{
                    .iterate = true,
                    .access_sub_paths = false,
                }) catch |err| switch (err) {
                    error.Canceled => |e| return e,
                    else => |e| return fail(diag, .{ .file_open = .{
                        .file_offset = file_off,
                        .err = e,
                    } }),
                };
            defer if (!input_path.request_handle) opened_dir.close(io) else {
                input_path.handle = .{ .dir = opened_dir };
                input_path.have_handle = true;
            };

            if (!input_path.have_stat) {
                assert(!stat_path_ok);
                const actual_stat = opened_dir.stat(io) catch |err| switch (err) {
                    error.Canceled => |e| return e,
                    else => |e| return fail(diag, .{ .file_stat = .{
                        .file_offset = file_off,
                        .err = e,
                    } }),
                };
                try input_file.setStat(m, .init(actual_stat));
            }

            const dir_contents_start = m.all_input_content.items.len;
            hashDir(gpa, io, opened_dir, &input_file.digest, &m.all_input_content) catch |err| switch (err) {
                error.Canceled, error.OutOfMemory => |e| return e,
                else => |e| return fail(diag, .{ .file_read = .{
                    .file_offset = file_off,
                    .err = e,
                } }),
            };
            defer switch (input_path.contents.unwrap()) {
                .requested => input_path.contents = .populated(.{
                    .off = @intCast(dir_contents_start),
                    .len = @intCast(m.all_input_content.items.len - dir_contents_start),
                }),
                .unrequested => m.all_input_content.shrinkRetainingCapacity(dir_contents_start),
                .populated => unreachable,
            };
        } else {
            const opened_file = if (input_path.have_handle)
                input_path.handle.file
            else
                parent_dir.openFile(io, file_path, .{ .mode = .read_only }) catch |err| switch (err) {
                    error.Canceled => |e| return e,
                    else => |e| return fail(diag, .{ .file_open = .{
                        .file_offset = file_off,
                        .err = e,
                    } }),
                };
            defer if (!input_path.request_handle) opened_file.close(io) else {
                input_path.handle = .{ .file = opened_file };
                input_path.have_handle = true;
            };

            if (!input_path.have_stat) {
                assert(!stat_path_ok);
                const actual_stat = opened_file.stat(io) catch |err| switch (err) {
                    error.Canceled => |e| return e,
                    else => |e| return fail(diag, .{ .file_stat = .{
                        .file_offset = file_off,
                        .err = e,
                    } }),
                };
                try input_file.setStat(m, .init(actual_stat));
            }

            switch (input_path.contents.unwrap()) {
                .requested => {
                    const start = m.all_input_content.items.len;
                    hashFileAppend(io, opened_file, &input_file.digest, &m.all_input_content, gpa) catch |err| switch (err) {
                        error.Canceled, error.OutOfMemory => |e| return e,
                        else => |e| return fail(diag, .{ .file_read = .{
                            .file_offset = file_off,
                            .err = e,
                        } }),
                    };
                    input_path.contents = .populated(.{
                        .off = @intCast(start),
                        .len = @intCast(m.all_input_content.items.len - start),
                    });
                },
                .unrequested => hashFile(io, opened_file, &input_file.digest) catch |err| switch (err) {
                    error.Canceled => |e| return e,
                    else => |e| return fail(diag, .{ .file_read = .{
                        .file_offset = file_off,
                        .err = e,
                    } }),
                },
                .populated => unreachable,
            }
        }
    }

    /// Upon return, disk_contents digest and stat will be populated regardless of whether hit or miss occurs.
    fn checkInputPath(
        m: *Manifest,
        diag: *CheckDiagnostic,
        file_off: File.Offset,
        input_path: *InputPath,
        disk_contents: []u8,
        input_contents: []u8,
    ) CheckError!CheckResult {
        const cache = m.cache;
        const io = cache.io;
        const gpa = cache.gpa;
        const disk_file = file_off.get(disk_contents);
        const input_file = file_off.get(input_contents);
        const parent_dir = cache.prefixes()[disk_file.flags.prefix].handle;
        const file_path = file_off.path(disk_contents);

        assert(disk_file.flags == input_file.flags);

        if (input_path.have_digest) {
            if (mem.eql(u8, &disk_file.digest, &input_file.digest))
                return .hit;
        }

        if (input_path.have_stat) {
            const changed = try disk_file.setStatChanged(m, input_file.stat());
            if (!changed) return .hit;
        }

        if (disk_file.flags.metadata_only) {
            if (!input_path.have_stat) {
                // Since this is an input file, FileNotFound counts as a failure, not a cache miss.
                const actual_stat = switch (input_path.getHandle(input_file)) {
                    .none => parent_dir.statFile(io, file_path, .{}) catch |err| switch (err) {
                        error.Canceled => |e| return e,
                        else => |e| return fail(diag, .{ .file_stat = .{
                            .file_offset = file_off,
                            .err = e,
                        } }),
                    },
                    .file => |opened_file| opened_file.stat(io) catch |err| switch (err) {
                        error.Canceled => |e| return e,
                        else => |e| return fail(diag, .{ .file_stat = .{
                            .file_offset = file_off,
                            .err = e,
                        } }),
                    },
                    .dir => |opened_dir| opened_dir.stat(io) catch |err| switch (err) {
                        error.Canceled => |e| return e,
                        else => |e| return fail(diag, .{ .file_stat = .{
                            .file_offset = file_off,
                            .err = e,
                        } }),
                    },
                };
                // In the other case (have_stat=true), this check is redundant since we already asserted the flags are
                // identical, which contains the prefix.
                const actual_is_directory = actual_stat.kind == .directory;
                if (actual_is_directory != disk_file.flags.is_directory) {
                    // Since this is an input file, this is a failure, not a cache miss.
                    return fail(diag, .{ .file_stat = .{
                        .file_offset = file_off,
                        .err = if (actual_is_directory) error.IsDir else error.NotDir,
                    } });
                }
                const stat: Stat = .init(actual_stat);
                const changed = try disk_file.setStatChanged(m, stat);
                disk_file.hashFromMetadata();
                if (!changed) return .hit;
            }
            return .{ .metadata_changed = file_off };
        }

        if (input_path.contents.get(m.all_input_content.items)) |file_or_dir_contents| {
            var hasher = hasher_init;
            hasher.update(file_or_dir_contents);
            hasher.final(&disk_file.digest);

            if (mem.eql(u8, &disk_file.digest, &input_file.digest)) return .hit;
            return .{ .contents_changed = file_off };
        }

        if (disk_file.flags.is_directory) {
            const opened_dir = if (input_path.have_handle)
                input_path.handle.dir
            else
                parent_dir.openDir(io, file_path, .{
                    .iterate = true,
                    .access_sub_paths = false,
                }) catch |err| switch (err) {
                    error.Canceled => |e| return e,
                    else => |e| return fail(diag, .{ .file_open = .{
                        .file_offset = file_off,
                        .err = e,
                    } }),
                };
            defer if (!input_path.request_handle) opened_dir.close(io) else {
                input_path.handle = .{ .dir = opened_dir };
                input_path.have_handle = true;
            };

            if (!input_path.have_stat) {
                const actual_stat = opened_dir.stat(io) catch |err| switch (err) {
                    error.Canceled => |e| return e,
                    else => |e| return fail(diag, .{ .file_stat = .{
                        .file_offset = file_off,
                        .err = e,
                    } }),
                };
                if (!try disk_file.setStatChanged(m, .init(actual_stat))) return .hit;
            }

            const dir_contents_start = m.all_input_content.items.len;
            hashDir(gpa, io, opened_dir, &disk_file.digest, &m.all_input_content) catch |err| switch (err) {
                error.Canceled, error.OutOfMemory => |e| return e,
                else => |e| return fail(diag, .{ .file_read = .{
                    .file_offset = file_off,
                    .err = e,
                } }),
            };
            defer switch (input_path.contents.unwrap()) {
                .requested => input_path.contents = .populated(.{
                    .off = @intCast(dir_contents_start),
                    .len = @intCast(m.all_input_content.items.len - dir_contents_start),
                }),
                .unrequested => m.all_input_content.shrinkRetainingCapacity(dir_contents_start),
                .populated => unreachable,
            };

            if (mem.eql(u8, &disk_file.digest, &input_file.digest)) return .hit;
            return .{ .contents_changed = file_off };
        } else {
            const opened_file = if (input_path.have_handle)
                input_path.handle.file
            else
                parent_dir.openFile(io, file_path, .{ .mode = .read_only }) catch |err| switch (err) {
                    error.Canceled => |e| return e,
                    else => |e| return fail(diag, .{ .file_open = .{
                        .file_offset = file_off,
                        .err = e,
                    } }),
                };
            defer if (!input_path.request_handle) opened_file.close(io) else {
                input_path.handle = .{ .file = opened_file };
                input_path.have_handle = true;
            };

            if (!input_path.have_stat) {
                const actual_stat = opened_file.stat(io) catch |err| switch (err) {
                    error.Canceled => |e| return e,
                    else => |e| return fail(diag, .{ .file_stat = .{
                        .file_offset = file_off,
                        .err = e,
                    } }),
                };
                if (!try disk_file.setStatChanged(m, .init(actual_stat))) return .hit;
            }

            switch (input_path.contents.unwrap()) {
                .requested => {
                    const start = m.all_input_content.items.len;
                    hashFileAppend(io, opened_file, &disk_file.digest, &m.all_input_content, gpa) catch |err| switch (err) {
                        error.Canceled, error.OutOfMemory => |e| return e,
                        else => |e| return fail(diag, .{ .file_read = .{
                            .file_offset = file_off,
                            .err = e,
                        } }),
                    };
                    input_path.contents = .populated(.{
                        .off = @intCast(start),
                        .len = @intCast(m.all_input_content.items.len - start),
                    });
                },
                .unrequested => hashFile(io, opened_file, &disk_file.digest) catch |err| switch (err) {
                    error.Canceled => |e| return e,
                    else => |e| return fail(diag, .{ .file_read = .{
                        .file_offset = file_off,
                        .err = e,
                    } }),
                },
                .populated => unreachable,
            }

            if (mem.eql(u8, &disk_file.digest, &input_file.digest)) return .hit;
            return .{ .contents_changed = file_off };
        }
    }

    fn checkDiscoveredPath(
        m: *Manifest,
        diag: *CheckDiagnostic,
        file_off: File.Offset,
        contents: []u8,
    ) CheckError!CheckResult {
        const file = file_off.get(contents);
        const cache = m.cache;
        const gpa = cache.gpa;
        const io = cache.io;
        const parent_dir = cache.prefixes()[file.flags.prefix].handle;
        const file_path = file_off.path(contents);

        if (file.flags.metadata_only) {
            const actual_stat = parent_dir.statFile(io, file_path, .{}) catch |err| switch (err) {
                error.FileNotFound => return .{ .path_deleted = file_off },
                error.Canceled => |e| return e,
                else => |e| return fail(diag, .{ .file_stat = .{
                    .file_offset = file_off,
                    .err = e,
                } }),
            };

            const actual_is_directory = actual_stat.kind == .directory;
            if (actual_is_directory != file.flags.is_directory) return .{ .directory_status_changed = file_off };

            const changed = try file.setStatChanged(m, .init(actual_stat));
            file.hashFromMetadata();
            if (changed) return .{ .metadata_changed = file_off };
            return .hit;
        }

        if (file.flags.is_directory) {
            const opened_dir = parent_dir.openDir(io, file_path, .{
                .iterate = true,
                .access_sub_paths = false,
            }) catch |err| switch (err) {
                error.FileNotFound => return .{ .path_deleted = file_off },
                error.NotDir => return .{ .directory_status_changed = file_off },
                error.Canceled => |e| return e,
                else => |e| return fail(diag, .{ .file_open = .{
                    .file_offset = file_off,
                    .err = e,
                } }),
            };
            defer opened_dir.close(io);

            const actual_stat = opened_dir.stat(io) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => |e| return fail(diag, .{ .file_stat = .{
                    .file_offset = file_off,
                    .err = e,
                } }),
            };
            if (try file.setStatChanged(m, .init(actual_stat))) {
                const prev_digest: BinDigest = file.digest;
                const dir_contents_start = m.all_input_content.items.len;
                defer m.all_input_content.shrinkRetainingCapacity(dir_contents_start);
                hashDir(gpa, io, opened_dir, &file.digest, &m.all_input_content) catch |err| switch (err) {
                    error.Canceled, error.OutOfMemory => |e| return e,
                    else => |e| return fail(diag, .{ .file_read = .{
                        .file_offset = file_off,
                        .err = e,
                    } }),
                };

                if (!mem.eql(u8, &file.digest, &prev_digest)) return .{ .contents_changed = file_off };
            }
            return .hit;
        }

        const opened_file = parent_dir.openFile(io, file_path, .{ .mode = .read_only }) catch |err| switch (err) {
            error.FileNotFound => return .{ .path_deleted = file_off },
            error.IsDir => return .{ .directory_status_changed = file_off },
            error.Canceled => |e| return e,
            else => |e| return fail(diag, .{ .file_open = .{
                .file_offset = file_off,
                .err = e,
            } }),
        };
        defer opened_file.close(io);

        const actual_stat = opened_file.stat(io) catch |err| switch (err) {
            error.Canceled => |e| return e,
            else => |e| return fail(diag, .{ .file_stat = .{
                .file_offset = file_off,
                .err = e,
            } }),
        };

        if (try file.setStatChanged(m, .init(actual_stat))) {
            const prev_digest: BinDigest = file.digest;
            hashFile(io, opened_file, &file.digest) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => |e| return fail(diag, .{ .file_read = .{
                    .file_offset = file_off,
                    .err = e,
                } }),
            };

            if (!mem.eql(u8, &file.digest, &prev_digest)) return .{ .contents_changed = file_off };
        }

        return .hit;
    }

    fn fail(ptr: *CheckDiagnostic, d: CheckDiagnostic) error{CacheCheckFailed} {
        ptr.* = d;
        return error.CacheCheckFailed;
    }

    fn isProblematicTimestamp(man: *Manifest, timestamp: Io.Timestamp) error{Canceled}!bool {
        const io = man.cache.io;

        // If the file_time is prior to the most recent problematic timestamp
        // then we don't need to access the filesystem.
        if (timestamp.nanoseconds < man.recent_problematic_timestamp.nanoseconds)
            return false;

        // Next we will check the globally shared Cache timestamp, which is accessed
        // from multiple threads.
        try man.cache.mutex.lock(io);
        defer man.cache.mutex.unlock(io);

        // Save the global one to our local one to avoid locking next time.
        man.recent_problematic_timestamp = man.cache.recent_problematic_timestamp;
        if (timestamp.nanoseconds < man.recent_problematic_timestamp.nanoseconds)
            return false;

        // This flag prevents multiple filesystem writes for the same hit() call.
        if (man.want_refresh_timestamp) {
            man.want_refresh_timestamp = false;

            var file = man.cache.manifest_dir.createFile(io, "timestamp", .{
                .read = true,
                .truncate = true,
            }) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => return true,
            };
            defer file.close(io);

            // Save locally and also save globally (we still hold the global lock).
            const stat = file.stat(io) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => return true,
            };
            man.recent_problematic_timestamp = stat.mtime;
            man.cache.recent_problematic_timestamp = man.recent_problematic_timestamp;
        }

        return timestamp.nanoseconds >= man.recent_problematic_timestamp.nanoseconds;
    }

    pub const AddDiscoveredPathOptions = struct {
        discovered_path: DiscoveredPath,
        handle: PathHandle = .{ .file = null },
        stat: ?Stat = null,
        /// If it is a directory, there is a special encoding required for contents, which
        /// is null-separated sorted entries, each one prefixed with `File.Kind`.
        contents: ?[]const u8 = null,
        metadata_only: bool = false,
        /// Populated if and only if `error.FileSystemFailure` is returned from `addDiscoveredPath`.
        diagnostic: ?*AddDiscoveredPathDiagnostic = null,
    };

    pub const DiscoveredPath = union(enum) {
        unresolved: Path,
        prefixed: PrefixedPath,
    };

    pub const AddDiscoveredPathDiagnostic = union(enum) {
        none,
        open_file: Io.File.OpenError,
        open_dir: Io.Dir.OpenError,
        stat_file: Io.File.StatError,
        stat_dir: Io.Dir.StatError,
        read_file: Io.File.ReadPositionalError,
        read_dir: Io.Dir.Reader.Error,

        pub fn format(this: @This(), w: *Io.Writer) Io.Writer.Error!void {
            switch (this) {
                .none => return w.writeAll("none"),
                else => |err, tag| return w.print("{t}: {t}", .{ tag, err }),
            }
        }
    };

    pub const AddDiscoveredPathError = error{
        /// If this is returned, diagnostic will be populated.
        /// If contents and stat are both provided, this is unreachable.
        FileSystemFailure,
    } || Allocator.Error || Io.Cancelable;

    /// Add a file or directory as a dependency of process being cached, after cache miss occurs.
    ///
    /// See also:
    /// * `addInputPath`
    /// * `addDiscoveredDepFile`
    /// * `addDiscoveredManifest`
    pub fn addDiscoveredPath(m: *Manifest, options: AddDiscoveredPathOptions) AddDiscoveredPathError!void {
        assert(m.manifest_file != null);
        transitionToMissDiscovered(m);
        const cache = m.cache;
        const gpa = cache.gpa;
        const io = cache.io;
        const is_directory = options.handle == .dir;

        try m.files.ensureUnusedCapacityContext(gpa, 1, .{ .contents = m.contents.items });

        const new_file_offset: File.Offset = @fromBackingInt(@intCast(m.contents.items.len));
        try m.contents.appendNTimes(gpa, 0, @offsetOf(File, "path_start"));
        errdefer m.contents.shrinkRetainingCapacity(@backingInt(new_file_offset));

        const new_prefix = switch (options.discovered_path) {
            .unresolved => |unresolved| try cache.resolveAppendPath(&m.contents, unresolved),
            .prefixed => |prefixed| try cache.appendPrefixedPath(&m.contents, prefixed),
        };
        assert(mem.isAligned(m.contents.items.len, @alignOf(File)));
        new_file_offset.get(m.contents.items).flags = .{
            .prefix = new_prefix,
            .is_directory = is_directory,
            .metadata_only = options.metadata_only,
        };

        const gop = m.files.getOrPutAssumeCapacityContext(new_file_offset, .{ .contents = m.contents.items });
        m.files.lockPointers();
        defer m.files.unlockPointers();

        const file_offset = if (gop.found_existing) h: {
            m.contents.shrinkRetainingCapacity(@backingInt(new_file_offset));
            const existing_off = gop.key_ptr.*;
            const header = existing_off.get(m.contents.items);
            // If it trips, the same file path has been added to the cache
            // manifest both as a directory and as a normal file, making the
            // intended caching behavior ambiguous.
            assert(header.flags.is_directory == is_directory);
            if (!options.metadata_only)
                header.flags.metadata_only = false;
            break :h existing_off;
        } else new_file_offset;

        const header = file_offset.get(m.contents.items);

        if (options.stat) |stat| {
            try header.setStat(m, stat);
            if (header.flags.metadata_only) {
                header.hashFromMetadata();
            } else if (options.contents) |contents| {
                var hasher = hasher_init;
                hasher.update(contents);
                hasher.final(&header.digest);
            }
            return;
        }

        const need_stat = options.stat == null;
        const metadata_only = header.flags.metadata_only;
        const prefix = header.flags.prefix;

        switch (options.handle) {
            .dir => |opt_handle| if (opt_handle) |handle| {
                try populateDirectory(m, header, need_stat, handle, options.contents, metadata_only, options.diagnostic);
            } else {
                const dir = cache.prefixes()[prefix].handle;
                const sub_path = file_offset.path(m.contents.items);
                const handle = dir.openDir(io, sub_path, .{
                    .access_sub_paths = false,
                    .iterate = true,
                }) catch |err| switch (err) {
                    error.Canceled => |e| return e,
                    else => |e| {
                        if (options.diagnostic) |d| d.* = .{ .open_dir = e };
                        return error.FileSystemFailure;
                    },
                };
                defer handle.close(io);
                try populateDirectory(m, header, need_stat, handle, options.contents, metadata_only, options.diagnostic);
            },

            .file => |opt_handle| if (opt_handle) |handle| {
                try populateFile(m, header, need_stat, handle, options.contents, metadata_only, options.diagnostic);
            } else {
                const dir = cache.prefixes()[prefix].handle;
                const sub_path = file_offset.path(m.contents.items);
                const handle = dir.openFile(io, sub_path, .{ .mode = .read_only }) catch |err| switch (err) {
                    error.Canceled => |e| return e,
                    else => |e| {
                        if (options.diagnostic) |d| d.* = .{ .open_file = e };
                        return error.FileSystemFailure;
                    },
                };
                defer handle.close(io);
                try populateFile(m, header, need_stat, handle, options.contents, metadata_only, options.diagnostic);
            },
        }
    }

    pub const AddDiscoveredDepFileError = error{
        InvalidDepFile,
    } || AddDiscoveredPathError || Io.File.OpenError || Io.File.Reader.Error;

    pub const AddDiscoveredDepFileDiagnostic = union(enum) {
        add_discovered_path: AddDiscoveredPathDiagnostic,
        dep_tokenizer: DepTokenizer.Token,
    };

    /// Add a GNU make style dep file as a dependency of process being cached, after cache miss occurs.
    ///
    /// See also:
    /// * `addDiscoveredPath
    /// * `addDiscoveredManifest`
    pub fn addDiscoveredDepFile(
        m: *Manifest,
        path: Path,
        diagnostic: ?*AddDiscoveredDepFileDiagnostic,
    ) AddDiscoveredDepFileError!void {
        assert(m.manifest_file != null);
        transitionToMissDiscovered(m);

        const cache = m.cache;
        const gpa = cache.gpa;
        const io = cache.io;

        // TODO: change DepTokenizer to be streaming rather than operating on slice of bytes.
        const prev_len = m.all_input_content.items.len;
        defer m.all_input_content.items.len = prev_len;

        const file = try path.root_dir.handle.openFile(io, path.sub_path, .{});
        defer file.close(io);

        var file_reader: Io.File.Reader = .init(file, io, &.{});
        file_reader.interface.appendRemainingUnlimited(gpa, &m.all_input_content) catch |err| switch (err) {
            error.OutOfMemory => |e| return e,
            error.ReadFailed => return file_reader.err.?,
        };

        var aux: std.ArrayList(u8) = .empty;
        defer aux.deinit(gpa);

        var it: DepTokenizer = .{ .bytes = m.all_input_content.items[prev_len..] };
        while (it.next()) |token| switch (token) {
            .target, .target_must_resolve => {},
            .prereq => |p| try m.addDiscoveredPath(.{ .discovered_path = .{ .unresolved = .initCwd(p) } }),
            .prereq_must_resolve => {
                aux.clearRetainingCapacity();
                try token.resolve(gpa, &aux);
                try m.addDiscoveredPath(.{ .discovered_path = .{ .unresolved = .initCwd(aux.items) } });
            },
            else => |err| {
                if (diagnostic) |d| d.* = .{ .dep_tokenizer = err };
                return error.InvalidDepFile;
            },
        };
    }

    fn populateFile(
        m: *Manifest,
        file: *File,
        need_stat: bool,
        handle: Io.File,
        contents: ?[]const u8,
        metadata_only: bool,
        diagnostic: ?*AddDiscoveredPathDiagnostic,
    ) AddDiscoveredPathError!void {
        const io = m.cache.io;

        if (need_stat) {
            const stat = handle.stat(io) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => |e| {
                    if (diagnostic) |d| d.* = .{ .stat_file = e };
                    return error.FileSystemFailure;
                },
            };
            try file.setStat(m, .init(stat));
        }
        if (metadata_only) {
            file.hashFromMetadata();
            return;
        }
        if (contents) |bytes| {
            var hasher = hasher_init;
            hasher.update(bytes);
            hasher.final(&file.digest);
        } else {
            hashFile(io, handle, &file.digest) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => |e| {
                    if (diagnostic) |d| d.* = .{ .read_file = e };
                    return error.FileSystemFailure;
                },
            };
        }
    }

    fn populateDirectory(
        m: *Manifest,
        file: *File,
        need_stat: bool,
        handle: Io.Dir,
        contents: ?[]const u8,
        metadata_only: bool,
        diagnostic: ?*AddDiscoveredPathDiagnostic,
    ) AddDiscoveredPathError!void {
        const cache = m.cache;
        const io = cache.io;
        const gpa = cache.gpa;

        if (need_stat) {
            const stat = handle.stat(io) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => |e| {
                    if (diagnostic) |d| d.* = .{ .stat_dir = e };
                    return error.FileSystemFailure;
                },
            };
            try file.setStat(m, .init(stat));
        }
        if (metadata_only) {
            file.hashFromMetadata();
            return;
        }
        if (contents) |bytes| {
            var hasher = hasher_init;
            hasher.update(bytes);
            hasher.final(&file.digest);
        } else {
            const prev_contents_len = m.all_input_content.items.len;
            defer m.all_input_content.shrinkRetainingCapacity(prev_contents_len);
            hashDir(gpa, io, handle, &file.digest, &m.all_input_content) catch |err| switch (err) {
                error.OutOfMemory, error.Canceled => |e| return e,
                else => |e| {
                    if (diagnostic) |d| d.* = .{ .read_dir = e };
                    return error.FileSystemFailure;
                },
            };
        }
    }

    /// See also `hitDigestHex`.
    pub fn hitDigest(m: *Manifest) BinDigest {
        assert(m.manifest_file != null);
        assert(m.state == .hit);
        m.state = .hit_digested;
        return finalDigest(m);
    }

    pub fn hitDigestHex(m: *Manifest) HexDigest {
        return binToHex(m.hitDigest());
    }

    /// See also `missDigestHex`.
    pub fn missDigest(m: *Manifest) BinDigest {
        assert(m.manifest_file != null);
        transitionToMissDiscovered(m);
        m.state = .miss_digested;
        return finalDigest(m);
    }

    pub fn missDigestHex(m: *Manifest) HexDigest {
        return binToHex(m.missDigest());
    }

    fn finalDigest(m: *Manifest) BinDigest {
        const contents = m.contents.items;
        const hasher = &m.hash.hasher;

        for (m.files.keys()) |off| {
            const file = off.get(contents);
            hasher.update(&file.digest);
        }
        // We don't close the manifest file yet, because we want to keep it locked until the API user is done using it.
        // We also don't write out the manifest yet, because until `finalize` is called we still might be working on
        // creating the artifacts to cache.
        var bin_digest: BinDigest = undefined;
        hasher.final(&bin_digest);
        return bin_digest;
    }

    /// If `want_shared_lock` is true, this function automatically downgrades the
    /// lock from exclusive to shared.
    pub fn finalize(m: *Manifest) !void {
        const io = m.cache.io;
        const manifest_file = m.manifest_file.?;

        assert(m.state == .miss_digested);
        assert(m.have_exclusive_lock);

        {
            m.contents.appendAssumeCapacity(0);
            defer _ = m.contents.pop().?;

            try manifest_file.setLength(io, m.contents.items.len);
            try manifest_file.writePositionalAll(io, m.contents.items, 0);

            m.state = .miss_finalized;
        }

        if (m.want_shared_lock) {
            try m.downgradeToSharedLock();
        }
    }

    fn downgradeToSharedLock(self: *Manifest) !void {
        if (!self.have_exclusive_lock) return;
        const io = self.cache.io;

        if (std.process.can_spawn or !builtin.single_threaded) {
            const manifest_file = self.manifest_file.?;
            try manifest_file.downgradeLock(io);
        }

        self.have_exclusive_lock = false;
    }

    fn upgradeToExclusiveLock(m: *Manifest, diag: *CheckDiagnostic) error{CacheCheckFailed}!bool {
        if (m.have_exclusive_lock) return false;
        assert(m.manifest_file != null);
        const io = m.cache.io;

        if (std.process.can_spawn or !builtin.single_threaded) {
            const manifest_file = m.manifest_file.?;
            // Here we intentionally have a period where the lock is released, in case there are
            // other processes holding a shared lock.
            manifest_file.unlock(io);
            manifest_file.lock(io, .exclusive) catch |err| return fail(diag, .{ .manifest_lock = err });
        }
        m.have_exclusive_lock = true;
        return true;
    }

    /// Obtain only the data needed to maintain a lock on the manifest file.
    /// The `Manifest` remains safe to deinit.
    ///
    /// Don't forget to call `finalize` before this!
    pub fn toOwnedLock(self: *Manifest) Lock {
        defer self.manifest_file = null;
        return .{ .manifest_file = self.manifest_file.? };
    }

    pub const SelfContainedFiles = struct {
        /// References memory inside `contents`.
        files: Files,
        contents: std.ArrayList(u8),

        pub const empty: @This() = .{
            .files = .empty,
            .contents = .empty,
        };

        pub fn deinit(scf: *SelfContainedFiles, gpa: Allocator) void {
            scf.files.deinit(gpa);
            scf.contents.deinit(gpa);
            scf.* = undefined;
        }

        pub fn path(scf: *const SelfContainedFiles, file_offset: File.Offset) [:0]const u8 {
            return file_offset.path(scf.contents.items);
        }
    };

    pub fn takeFiles(m: *Manifest) SelfContainedFiles {
        defer m.files = .empty;
        defer m.contents = .empty;
        return borrowFiles(m);
    }

    pub fn borrowFiles(m: *const Manifest) SelfContainedFiles {
        return .{
            .files = m.files,
            .contents = m.contents,
        };
    }

    /// Releases the manifest file and frees any memory the Manifest was using.
    /// `Manifest.hit` must be called first.
    ///
    /// Don't forget to call `finalize` before this!
    pub fn deinit(m: *Manifest) void {
        const io = m.cache.io;
        const gpa = m.cache.gpa;

        if (m.manifest_file) |file| {
            if (builtin.os.tag == .windows) {
                // See Lock.release for why this is required on Windows
                file.unlock(io);
            }

            file.close(io);
        }
        m.files.deinit(gpa);
        m.contents.deinit(gpa);
        m.input_paths.deinit(gpa);
        m.all_input_content.deinit(gpa);
        m.* = undefined;
    }

    pub fn populateFileSystemInputs(man: *const Manifest, buf: *std.ArrayList(u8)) Allocator.Error!void {
        assert(@typeInfo(std.zig.Server.Message.PathPrefix).@"enum".field_names.len == man.cache.prefixes_len);
        buf.clearRetainingCapacity();
        const gpa = man.cache.gpa;
        const files = man.files.keys();
        if (files.len > 0) {
            const contents = man.contents.items;
            for (files) |file| {
                const file_path = file.path(contents);
                try buf.ensureUnusedCapacity(gpa, file_path.len + 2);
                buf.appendAssumeCapacity(@as(u8, file.get(contents).flags.prefix) + 1);
                buf.appendSliceAssumeCapacity(file_path);
                buf.appendAssumeCapacity(0);
            }
            // The null byte is a separator, not a terminator.
            buf.items.len -= 1;
        }
    }

    /// Add the full set of paths from another `Manifest` as a dependency of process being cached, after cache miss
    /// occurs.
    ///
    /// See also:
    /// * `addDiscoveredPath
    /// * `addDiscoveredDepFile`
    pub fn addDiscoveredManifest(m: *Manifest, discovered: *const Manifest, prefix_map: [5]u8) Allocator.Error!void {
        const gpa = m.cache.gpa;
        assert(m.manifest_file != null);
        transitionToMissDiscovered(m);
        assert(@typeInfo(std.zig.Server.Message.PathPrefix).@"enum".field_names.len == discovered.cache.prefixes_len);
        assert(discovered.cache.prefixes_len == 5);

        const discovered_files = discovered.files.keys();
        const orig_files_len = m.files.count();
        const orig_contents_len = m.contents.items.len;
        errdefer {
            m.files.shrinkRetainingCapacityContext(orig_files_len, .{ .contents = m.contents.items });
            m.contents.shrinkRetainingCapacity(orig_contents_len);
        }

        for (discovered_files, 0..) |off, file_index| {
            try m.files.ensureUnusedCapacityContext(gpa, 1, .{ .contents = m.contents.items });

            const next_index = file_index + 1;
            const next_off = if (discovered_files.len - next_index == 0)
                discovered.contents.items.len
            else
                @backingInt(discovered_files[next_index]);

            const copy_bytes = discovered.contents.items[@backingInt(off)..next_off];
            const prev_contents_len: File.Offset = @fromBackingInt(@intCast(m.contents.items.len));
            try m.contents.appendSlice(gpa, copy_bytes);

            const gop = m.files.getOrPutAssumeCapacityContext(prev_contents_len, .{
                .contents = m.contents.items,
            });

            if (gop.found_existing) {
                m.contents.shrinkRetainingCapacity(@backingInt(prev_contents_len));
                continue;
            }

            // Flags are already copied but the prefix is supposed to be filtered by `prefix_map`.
            const other_file = prev_contents_len.get(m.contents.items);
            other_file.flags.prefix = @intCast(prefix_map[other_file.flags.prefix]);
        }
    }

    fn hashFile(io: Io, file: Io.File, bin_digest: *[Hasher.mac_length]u8) Io.File.ReadPositionalError!void {
        var buffer: [2048]u8 = undefined;
        var hasher = hasher_init;
        var offset: u64 = 0;
        while (true) {
            const n = try file.readPositional(io, &.{&buffer}, offset);
            if (n == 0) break;
            hasher.update(buffer[0..n]);
            offset += n;
        }
        hasher.final(bin_digest);
    }

    fn hashFileAppend(
        io: Io,
        file: Io.File,
        bin_digest: *[Hasher.mac_length]u8,
        al: *std.ArrayList(u8),
        gpa: Allocator,
    ) (Io.File.ReadPositionalError || Allocator.Error)!void {
        var hasher = hasher_init;
        var offset: u64 = 0;
        while (true) {
            try al.ensureUnusedCapacity(gpa, 2048);
            const buffer = al.unusedCapacitySlice();
            const n = try file.readPositional(io, &.{buffer}, offset);
            if (n == 0) break;
            hasher.update(buffer[0..n]);
            offset += n;
            al.items.len += n;
        }
        hasher.final(bin_digest);
    }

    const HashDirError = Io.Dir.Reader.Error || Allocator.Error;

    /// Appends the sorted, encoded directory entries to `contents`.
    fn hashDir(
        gpa: Allocator,
        io: Io,
        dir: Io.Dir,
        bin_digest: *[Hasher.mac_length]u8,
        contents: *std.ArrayList(u8),
    ) HashDirError!void {
        var buffer: [@max(2048, Io.Dir.Reader.min_buffer_len)]u8 align(@alignOf(usize)) = undefined;
        var reader: Io.Dir.Reader = .init(dir, &buffer);
        var entry_buffer: [16]Io.Dir.Entry = undefined;

        const contents_start = contents.items.len;
        errdefer contents.shrinkRetainingCapacity(contents_start);

        // Each index points into `contents`.
        var entries_list: std.ArrayList(u32) = .empty;
        defer entries_list.deinit(gpa);

        while (reader.state != .finished) {
            const entries = entry_buffer[0..try reader.read(io, &entry_buffer)];
            for (try entries_list.addManyAsSlice(gpa, entries.len), entries) |*off, entry| {
                off.* = @intCast(contents.items.len);
                // As an optimization, make the reservation also count the duplication
                // of the contents buffer that will be required after sorting.
                try contents.ensureUnusedCapacity(gpa, (contents.items.len + entry.name.len + 2 - contents_start) * 2);
                contents.appendAssumeCapacity(@backingInt(Manifest.File.Kind.fromStat(entry.kind)));
                contents.appendSliceAssumeCapacity(entry.name);
                contents.appendAssumeCapacity(0);
            }
        }

        const Sort = struct {
            contents: [*:0]const u8,
            pub fn lessThan(this: @This(), lhs: u32, rhs: u32) bool {
                // This comparison includes the kind byte.
                return mem.lessThanZ(u8, this.contents + lhs, this.contents + rhs);
            }
        };
        mem.sortUnstable(u32, entries_list.items, @as(Sort, .{
            .contents = @ptrCast(contents.items.ptr),
        }), Sort.lessThan);

        // Duplicate the contents such that we may refer to it while creating a
        // sorted copy in the original position (at contents_start). We will then
        // offset all the entries_list offsets by contents len when reading from the unsorted copy.
        const contents_len = contents.items.len - contents_start;
        @memcpy(contents.addManyAsSliceAssumeCapacity(contents_len), contents.items[contents_start..][0..contents_len]);

        var new_offset: usize = contents_start;
        for (entries_list.items) |wrong_offset| {
            const offset = wrong_offset + contents_len;
            // Includes the kind prefix which we also want to copy.
            const entry: [*:0]const u8 = @ptrCast(contents.items[offset..]);
            new_offset += mem.copySentinelInclusive(u8, 0, contents.items[new_offset..], entry);
        }
        assert(new_offset == contents_start + contents_len);
        contents.shrinkRetainingCapacity(contents_start + contents_len);

        var hasher = hasher_init;
        hasher.update(contents.items[contents_start..][0..contents_len]);
        hasher.final(bin_digest);
    }
};

/// Create/Write a file, close it, then grab its stat.mtime timestamp.
fn testGetCurrentFileTimestamp(io: Io, dir: Io.Dir) !Io.Timestamp {
    const test_out_file = "test-filetimestamp.tmp";

    var file = try dir.createFile(io, test_out_file, .{
        .read = true,
        .truncate = true,
    });
    defer {
        file.close(io);
        dir.deleteFile(io, test_out_file) catch {};
    }

    return (try file.stat(io)).mtime;
}

test "cache file and then recall it" {
    const io = testing.io;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd = try std.process.currentPathAlloc(io, testing.allocator);
    defer testing.allocator.free(cwd);

    const temp_file = "test.txt";
    const temp_manifest_dir = "temp_manifest_dir";

    try tmp.dir.writeFile(io, .{ .sub_path = temp_file, .data = "Hello, world!\n" });
    const tmp_directory: Directory = .{
        .path = try std.fs.path.join(testing.allocator, &.{std.testing.TmpDir.parent_dir_path}),
        .handle = tmp.dir,
    };
    defer testing.allocator.free(tmp_directory.path.?);

    // Wait for file timestamps to tick
    const initial_time = try testGetCurrentFileTimestamp(io, tmp.dir);
    while ((try testGetCurrentFileTimestamp(io, tmp.dir)).nanoseconds == initial_time.nanoseconds) {
        try Io.Clock.Duration.sleep(.{ .clock = .boot, .raw = .fromNanoseconds(1) }, io);
    }

    var digest1: HexDigest = undefined;
    var digest2: HexDigest = undefined;

    {
        var cache: Cache = .{
            .io = io,
            .gpa = testing.allocator,
            .manifest_dir = try tmp.dir.createDirPathOpen(io, temp_manifest_dir, .{}),
            .cwd = cwd,
        };
        cache.addPrefix(.{ .path = null, .handle = Io.Dir.cwd() });
        cache.addPrefix(tmp_directory);
        defer cache.manifest_dir.close(io);

        {
            var man = cache.obtain();
            defer man.deinit();

            man.hash.add(true);
            man.hash.add(@as(u16, 1234));
            man.hash.addBytes("1234");
            _ = try man.addInputPath(.{
                .root_dir = tmp_directory,
                .sub_path = temp_file,
            }, .{});

            var diag: Manifest.CheckDiagnostic = undefined;
            try testing.expectEqual(.incomplete_manifest, try man.check(&diag, .none));

            digest1 = man.missDigestHex();
            try man.finalize();
        }
        {
            var man = cache.obtain();
            defer man.deinit();

            man.hash.add(true);
            man.hash.add(@as(u16, 1234));
            man.hash.addBytes("1234");
            _ = try man.addInputPath(.{
                .root_dir = tmp_directory,
                .sub_path = temp_file,
            }, .{});

            // Cache hit! We just "built" the same file
            var diag: Manifest.CheckDiagnostic = undefined;
            try testing.expectEqual(.hit, try man.check(&diag, .none));
            digest2 = man.hitDigestHex();

            try testing.expectEqual(false, man.have_exclusive_lock);
        }

        try testing.expectEqual(digest1, digest2);
    }
}

test "check that changing a file causes cache miss" {
    const io = testing.io;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd = try std.process.currentPathAlloc(io, testing.allocator);
    defer testing.allocator.free(cwd);

    const temp_file = "cache_hash_change_file_test.txt";
    const temp_manifest_dir = "cache_hash_change_file_manifest_dir";
    const original_temp_file_contents = "Hello, world!\n";
    const updated_temp_file_contents = "Hello, world; but updated!\n";

    try tmp.dir.writeFile(io, .{ .sub_path = temp_file, .data = original_temp_file_contents });
    const tmp_directory: Directory = .{
        .path = try std.fs.path.join(testing.allocator, &.{std.testing.TmpDir.parent_dir_path}),
        .handle = tmp.dir,
    };
    defer testing.allocator.free(tmp_directory.path.?);

    // Wait for file timestamps to tick
    const initial_time = try testGetCurrentFileTimestamp(io, tmp.dir);
    while ((try testGetCurrentFileTimestamp(io, tmp.dir)).nanoseconds == initial_time.nanoseconds) {
        try Io.Clock.Duration.sleep(.{ .clock = .boot, .raw = .fromNanoseconds(1) }, io);
    }

    var digest1: HexDigest = undefined;
    var digest2: HexDigest = undefined;

    {
        var cache: Cache = .{
            .io = io,
            .gpa = testing.allocator,
            .manifest_dir = try tmp.dir.createDirPathOpen(io, temp_manifest_dir, .{}),
            .cwd = cwd,
        };
        cache.addPrefix(.{ .path = null, .handle = Io.Dir.cwd() });
        cache.addPrefix(tmp_directory);
        defer cache.manifest_dir.close(io);

        {
            var man = cache.obtain();
            defer man.deinit();

            man.hash.addBytes("1234");
            const temp_file_idx = try man.addInputPath(.{
                .root_dir = tmp_directory,
                .sub_path = temp_file,
            }, .{ .request_contents = true });

            var diag: Manifest.CheckDiagnostic = undefined;
            try testing.expectEqual(.incomplete_manifest, try man.check(&diag, .none));

            try testing.expectEqualStrings(original_temp_file_contents, temp_file_idx.contents(&man));

            digest1 = man.missDigestHex();

            try man.finalize();
        }

        try tmp.dir.writeFile(io, .{ .sub_path = temp_file, .data = updated_temp_file_contents });

        {
            var man = cache.obtain();
            defer man.deinit();

            man.hash.addBytes("1234");
            const temp_file_idx = try man.addInputPath(.{
                .root_dir = tmp_directory,
                .sub_path = temp_file,
            }, .{ .request_contents = true });

            // The one input file changed.
            var diag: Manifest.CheckDiagnostic = undefined;
            try testing.expectEqual(
                @as(Manifest.CheckResult, .{ .contents_changed = temp_file_idx.offset(&man) }),
                try man.check(&diag, .none),
            );

            try testing.expectEqualStrings(updated_temp_file_contents, temp_file_idx.contents(&man));

            digest2 = man.missDigestHex();

            try man.finalize();
        }

        try testing.expect(!mem.eql(u8, &digest1, &digest2));
    }
}

test "no file inputs" {
    const io = testing.io;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd = try std.process.currentPathAlloc(io, testing.allocator);
    defer testing.allocator.free(cwd);

    const temp_manifest_dir = "no_file_inputs_manifest_dir";

    var digest1: HexDigest = undefined;
    var digest2: HexDigest = undefined;

    var cache: Cache = .{
        .io = io,
        .gpa = testing.allocator,
        .manifest_dir = try tmp.dir.createDirPathOpen(io, temp_manifest_dir, .{}),
        .cwd = cwd,
    };
    cache.addPrefix(.{ .path = null, .handle = tmp.dir });
    defer cache.manifest_dir.close(io);

    {
        var man = cache.obtain();
        defer man.deinit();

        man.hash.addBytes("1234");

        var diag: Manifest.CheckDiagnostic = undefined;
        try testing.expectEqual(.incomplete_manifest, try man.check(&diag, .none));

        digest1 = man.missDigestHex();

        try man.finalize();
    }
    {
        var man = cache.obtain();
        defer man.deinit();

        man.hash.addBytes("1234");

        var diag: Manifest.CheckDiagnostic = undefined;
        try testing.expectEqual(.hit, try man.check(&diag, .none));
        digest2 = man.hitDigestHex();
        try testing.expectEqual(false, man.have_exclusive_lock);
    }

    try testing.expectEqual(digest1, digest2);
}

test "Manifest with files added after initial hash" {
    const io = testing.io;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd = try std.process.currentPathAlloc(io, testing.allocator);
    defer testing.allocator.free(cwd);

    const temp_file1 = "cache_hash_post_file_test1.txt";
    const temp_file2 = "cache_hash_post_file_test2.txt";
    const temp_manifest_dir = "cache_hash_post_file_manifest_dir";

    try tmp.dir.writeFile(io, .{ .sub_path = temp_file1, .data = "Hello, world!\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = temp_file2, .data = "Hello world the second!\n" });
    const tmp_directory: Directory = .{
        .path = try std.fs.path.join(testing.allocator, &.{std.testing.TmpDir.parent_dir_path}),
        .handle = tmp.dir,
    };
    defer testing.allocator.free(tmp_directory.path.?);

    // Wait for file timestamps to tick
    const initial_time = try testGetCurrentFileTimestamp(io, tmp.dir);
    while ((try testGetCurrentFileTimestamp(io, tmp.dir)).nanoseconds == initial_time.nanoseconds) {
        try Io.Clock.Duration.sleep(.{ .clock = .boot, .raw = .fromNanoseconds(1) }, io);
    }

    var digest1: HexDigest = undefined;
    var digest2: HexDigest = undefined;
    var digest3: HexDigest = undefined;

    {
        var cache: Cache = .{
            .io = io,
            .gpa = testing.allocator,
            .manifest_dir = try tmp.dir.createDirPathOpen(io, temp_manifest_dir, .{}),
            .cwd = cwd,
        };
        cache.addPrefix(.{ .path = null, .handle = Io.Dir.cwd() });
        cache.addPrefix(tmp_directory);
        defer cache.manifest_dir.close(io);

        {
            var man = cache.obtain();
            defer man.deinit();

            man.hash.addBytes("1234");
            _ = try man.addInputPath(.{
                .root_dir = tmp_directory,
                .sub_path = temp_file1,
            }, .{});

            var diag: Manifest.CheckDiagnostic = undefined;
            try testing.expectEqual(.incomplete_manifest, try man.check(&diag, .none));

            try man.addDiscoveredPath(.{ .discovered_path = .{ .unresolved = .{
                .root_dir = tmp_directory,
                .sub_path = temp_file2,
            } } });

            digest1 = man.missDigestHex();
            try man.finalize();
        }
        {
            var man = cache.obtain();
            defer man.deinit();

            man.hash.addBytes("1234");
            _ = try man.addInputPath(.{
                .root_dir = tmp_directory,
                .sub_path = temp_file1,
            }, .{});

            var diag: Manifest.CheckDiagnostic = undefined;
            try testing.expect(.hit == try man.check(&diag, .none));
            digest2 = man.hitDigestHex();

            try testing.expectEqual(false, man.have_exclusive_lock);
        }
        try testing.expect(mem.eql(u8, &digest1, &digest2));

        // Modify the file added after initial hash
        try tmp.dir.writeFile(io, .{ .sub_path = temp_file2, .data = "Hello world the second, updated\n" });

        // Wait for file timestamps to tick
        const initial_time2 = try testGetCurrentFileTimestamp(io, tmp.dir);
        while ((try testGetCurrentFileTimestamp(io, tmp.dir)).nanoseconds == initial_time2.nanoseconds) {
            try Io.Clock.Duration.sleep(.{ .clock = .boot, .raw = .fromNanoseconds(1) }, io);
        }

        {
            var man = cache.obtain();
            defer man.deinit();

            man.hash.addBytes("1234");
            _ = try man.addInputPath(.{
                .root_dir = tmp_directory,
                .sub_path = temp_file1,
            }, .{});

            var diag: Manifest.CheckDiagnostic = undefined;
            switch (try man.check(&diag, .none)) {
                .contents_changed => |off| {
                    try testing.expectEqualStrings(temp_file2, off.path(man.contents.items));
                },
                else => return error.TestFailed,
            }

            try man.addDiscoveredPath(.{ .discovered_path = .{ .unresolved = .{
                .root_dir = tmp_directory,
                .sub_path = temp_file2,
            } } });

            digest3 = man.missDigestHex();

            try man.finalize();
        }

        try testing.expect(!mem.eql(u8, &digest1, &digest3));
    }
}

test {
    _ = Path;
    _ = Directory;
    _ = DepTokenizer;
}

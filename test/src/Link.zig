b: *Build,
step: *Step,
optimize: std.builtin.OptimizeMode,
target: std.Build.ResolvedTarget,
target_desc: []const u8,
use_llvm: bool,
use_lld: bool,
link_libc: bool,
test_filters: []const []const u8,
update_step: ?*Step.UpdateSourceFiles,
updated_snapshots: std.StringArrayHashMapUnmanaged(void),
max_rss: usize,

pub fn includeTest(self: *Link, prefix: []const u8) ?Case {
    if (for (self.test_filters) |filter| {
        if (std.mem.find(u8, prefix, filter)) |_| break false;
    } else self.test_filters.len > 0) return null;

    return .{
        .ctx = self,
        .prefix = prefix,
    };
}

pub fn sourcePath(self: *const Link, sub_path: []const u8) std.Build.LazyPath {
    return self.b.path(self.b.pathJoin(&.{ "test/link", sub_path }));
}

pub const Case = struct {
    ctx: *Link,
    prefix: []const u8,

    fn resolveName(self: *const Case, overlay: *const OverlayOptions) []const u8 {
        if (!overlay.name_prefix and !overlay.name_target)
            return overlay.name;

        if (overlay.name_prefix == overlay.name_target)
            return self.ctx.b.fmt("{s}-{s}-{s}", .{ self.prefix, overlay.name, self.ctx.target_desc })
        else if (overlay.name_prefix)
            return self.ctx.b.fmt("{s}-{s}", .{ self.prefix, overlay.name })
        else
            return self.ctx.b.fmt("{s}-{s}", .{ overlay.name, self.ctx.target_desc });
    }

    pub fn addLibrary(
        self: *const Case,
        linkage: std.builtin.LinkMode,
        overlay: OverlayOptions,
    ) *Step.Compile {
        return self.ctx.b.addLibrary(.{
            .linkage = linkage,
            .name = self.resolveName(&overlay),
            .root_module = self.ctx.createModule(overlay),
            .use_llvm = overlay.use_llvm orelse self.ctx.use_llvm,
            .use_lld = overlay.use_lld orelse self.ctx.use_lld,
        });
    }

    pub fn addExecutable(
        self: *const Case,
        overlay: OverlayOptions,
    ) *Step.Compile {
        return self.ctx.b.addExecutable(.{
            .name = self.resolveName(&overlay),
            .root_module = self.ctx.createModule(overlay),
            .use_llvm = overlay.use_llvm orelse self.ctx.use_llvm,
            .use_lld = overlay.use_lld orelse self.ctx.use_lld,
        });
    }

    pub fn addRunArtifact(
        self: *const Case,
        exe: *Step.Compile,
    ) *Step.Run {
        const run_step = self.ctx.b.addRunArtifact(exe);
        run_step.skip_foreign_checks = true;
        self.ctx.step.dependOn(&run_step.step);
        return run_step;
    }

    pub fn addObject(
        self: *const Case,
        overlay: OverlayOptions,
    ) *Step.Compile {
        return self.ctx.b.addObject(.{
            .name = self.resolveName(&overlay),
            .root_module = self.ctx.createModule(overlay),
            .use_llvm = overlay.use_llvm orelse self.ctx.use_llvm,
            .use_lld = overlay.use_lld orelse self.ctx.use_lld,
        });
    }

    pub fn expectLinkErrors(
        self: *const Case,
        comp: *Step.Compile,
        expected_errors: Step.Compile.ExpectedCompileErrors,
    ) void {
        comp.expect_errors = expected_errors;
        const bin_file = comp.getEmittedBin();
        bin_file.addStepDependencies(self.ctx.step);
    }

    const SnapshotScope = struct {
        /// If a test case has multiple verifyObjdump calls, `opt_sub_name` should
        /// be used to differentiate them.
        sub_name: ?[]const u8 = null,
        arch: bool = false,
        os: bool = false,
        abi: bool = false,
        optimize: bool = false,
        use_llvm: bool = false,
        use_lld: bool = false,
        link_libc: bool = false,
    };

    /// Verify the results of a `zig objdump` call against a snapshot, which
    /// contains the expected output. Snapshots alias between all build
    /// configurations by default, but by specifying fields in `scope`,
    /// unique snapshot names are generated for each value of that field.
    pub fn verifyObjdump(
        self: *const Case,
        file: Build.LazyPath,
        args: []const []const u8,
        scope: SnapshotScope,
    ) void {
        const ctx = self.ctx;
        const snapshot_name = self.snapshotName(scope) catch @panic("OOM");
        const snapshot_sub_path = ctx.b.pathJoin(&.{ "test/link/snapshots/", snapshot_name });

        // Many tests may read the same snapshot, so only use the first one to update.
        // If there are differences in output, they will show up on the next test run.
        if (ctx.update_step != null) {
            const gop = ctx.updated_snapshots.getOrPut(ctx.b.allocator, snapshot_sub_path) catch @panic("OOM");
            if (gop.found_existing) return;
        }

        const run_step = Step.Run.create(ctx.b, ctx.b.fmt(
            "objdump {s} {s}",
            .{ snapshot_name, ctx.target_desc },
        ));
        run_step.addArgs(&.{ ctx.b.graph.zig_exe, "objdump" });
        run_step.addFileArg(file);
        run_step.addArgs(args);
        run_step.addCheck(.{ .expect_term = .{ .exited = 0 } });

        if (ctx.update_step) |update_step| {
            // Workaround for the build system not realizing objdump itself has changed
            run_step.has_side_effects = true;

            const snapshot_update_path = run_step.captureStdOut(.{});
            update_step.addCopyFileToSource(snapshot_update_path, snapshot_sub_path);
        } else {
            run_step.addCheck(.{ .expect_stdout_snapshot = ctx.b.path(snapshot_sub_path) });
        }

        ctx.step.dependOn(&run_step.step);
    }

    fn snapshotName(
        self: *const Case,
        scope: SnapshotScope,
    ) ![]const u8 {
        const ctx = self.ctx;
        var snapshot_name: std.Io.Writer.Allocating = .init(ctx.b.allocator);
        const w = &snapshot_name.writer;

        try w.writeAll(self.prefix);
        var sep: u8 = '.';

        if (try snapshotNameInner(w, scope.sub_name != null, &sep))
            try w.writeAll(scope.sub_name.?);
        if (try snapshotNameInner(w, scope.arch, &sep))
            try w.print("{t}", .{ctx.target.result.cpu.arch});
        if (try snapshotNameInner(w, scope.os, &sep))
            try w.print("{t}", .{ctx.target.result.os.tag});
        if (try snapshotNameInner(w, scope.abi, &sep))
            try w.print("{t}", .{ctx.target.result.abi});
        if (try snapshotNameInner(w, scope.optimize, &sep))
            try w.print("{t}", .{ctx.optimize});
        if (try snapshotNameInner(w, scope.use_llvm, &sep))
            try w.writeAll(if (ctx.use_llvm) "llvm" else "no-llvm");
        if (try snapshotNameInner(w, scope.use_lld, &sep))
            try w.writeAll(if (ctx.use_lld) "lld" else "no-lld");
        if (try snapshotNameInner(w, scope.link_libc, &sep))
            try w.writeAll(if (ctx.link_libc) "libc" else "no-libc");

        if (sep == '-') sep = '.';
        try w.writeByte(sep);
        try w.writeAll("dmp");

        return try snapshot_name.toOwnedSlice();
    }

    fn snapshotNameInner(w: *std.Io.Writer, cond: bool, sep: *u8) !bool {
        if (cond) {
            try w.writeByte(sep.*);
            sep.* = '-';
        }

        return cond;
    }
};

fn createModule(self: *const Link, overlay: OverlayOptions) *Build.Module {
    const write_files = self.b.addWriteFiles();

    const mod = self.b.createModule(.{
        .target = self.target,
        .optimize = self.optimize,
        .root_source_file = overlay.zig_source_file orelse rsf: {
            const bytes = overlay.zig_source_bytes orelse break :rsf null;
            const name = self.b.fmt("{s}.zig", .{overlay.name});
            break :rsf write_files.add(name, bytes);
        },
        .link_libc = self.link_libc, // TODO: Should this be in overlay instead?
        .pic = overlay.pic,
        .strip = overlay.strip,
    });

    if (overlay.objcpp_source_bytes) |bytes| {
        mod.addCSourceFile(.{
            .file = write_files.add("a.mm", bytes),
            .flags = overlay.objcpp_source_flags,
        });
    }
    if (overlay.objc_source_bytes) |bytes| {
        mod.addCSourceFile(.{
            .file = write_files.add("a.m", bytes),
            .flags = overlay.objc_source_flags,
        });
    }
    if (overlay.cpp_source_bytes) |bytes| {
        mod.addCSourceFile(.{
            .file = write_files.add("a.cpp", bytes),
            .flags = overlay.cpp_source_flags,
        });
    }
    if (overlay.c_source_bytes) |bytes| {
        mod.addCSourceFile(.{
            .file = write_files.add("a.c", bytes),
            .flags = overlay.c_source_flags,
        });
    }
    if (overlay.asm_source_bytes) |bytes| {
        mod.addAssemblyFile(write_files.add("a.s", bytes));
    }

    return mod;
}

const OverlayOptions = struct {
    name: []const u8,
    /// Prefix the name with the test case prefix.
    /// Unset if names with specific lengths are needed.
    name_prefix: bool = true,
    /// Prefix the name with `target_desc`.
    /// Can be unset when the snapshot needs to contain the name,
    /// so that snapshots can alias between targets.
    name_target: bool = true,
    asm_source_bytes: ?[]const u8 = null,
    c_source_bytes: ?[]const u8 = null,
    c_source_flags: []const []const u8 = &.{},
    cpp_source_bytes: ?[]const u8 = null,
    cpp_source_flags: []const []const u8 = &.{},
    objc_source_bytes: ?[]const u8 = null,
    objc_source_flags: []const []const u8 = &.{},
    objcpp_source_bytes: ?[]const u8 = null,
    objcpp_source_flags: []const []const u8 = &.{},
    zig_source_bytes: ?[]const u8 = null,
    zig_source_file: ?std.Build.LazyPath = null,
    pic: ?bool = null,
    strip: ?bool = null,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
};

const std = @import("std");
const Build = std.Build;
const Step = Build.Step;

const Link = @This();

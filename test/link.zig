pub fn addCases(ctx: *LinkContext) void {
    if (ctx.target.result.isMinGW())
        @import("link/mingw.zig").addCases(ctx);

    if (ctx.includeTest("static-lib")) |case| {
        const obj1 = case.addObject(.{
            .name = "obj1",
            .name_prefix = false,
            .name_target = false,
            .use_llvm = true,
            .use_lld = true,
            .c_source_bytes =
            \\int foo1 = 1;
            \\int foo2 = 2;
            \\unsigned int fooBar() {
            \\  return foo1 + foo2;
            \\}
            ,
        });
        const obj2 = case.addObject(.{
            .name = "this_is_a_long_name",
            .name_prefix = false,
            .name_target = false,
            .zig_source_bytes =
            \\fn fooWeak() callconv(.c) usize {
            \\    return 0xaabbccddaabbccdd;
            \\}
            \\export var foo_array: [2]u16 = .{ 0xffff, 0xabcd };
            \\export var foo_strong: usize = 0x1122334411223344;
            \\comptime {
            \\    @export(&fooWeak, .{ .name = "fooWeak", .linkage = .weak });
            \\    @export(&foo_strong, .{ .name = "foo_strong_alias", .linkage = .strong });
            \\}
            ,
        });

        const lib = case.addLibrary(.static, .{
            .name = "lib",
            .name_prefix = false,
            .name_target = false,
        });
        lib.root_module.addObject(obj1);
        lib.root_module.addObject(obj2);

        case.verifyObjdump(lib.getEmittedBin(), &.{
            "-s",
            "--elements=file-type",
            "--symbols",
            "--only-symbol=foo",
        }, .{ .use_llvm = true });

        const exe = case.addExecutable(.{
            .name = "test",
            .zig_source_bytes =
            \\extern fn fooBar() c_uint;
            \\extern fn fooWeak() usize;
            \\extern var foo_array: [2]u16;
            \\extern var foo_strong: usize;
            \\extern var foo_strong_alias: usize;
            \\pub fn main() !u8 {
            \\    return @intFromBool(0xcd003365cd00df35 != fooBar() +
            \\        fooWeak() +
            \\        foo_array[1] +
            \\        foo_strong +
            \\        foo_strong_alias);
            \\}
            ,
        });
        exe.root_module.linkLibrary(lib);

        const run = case.addRunArtifact(exe);
        run.addCheck(.{ .expect_term = .{ .exited = 0 } });
    }

    if (ctx.includeTest("tls")) |case| {
        const obj = case.addObject(.{
            .name = "obj",
            .zig_source_bytes =
            \\threadlocal var threadlocal_var: u32 = 1234;
            \\threadlocal var threadlocal_arr: [4]u16 = .{ 0x1111, 0x2222, 0x3333, 0x4444, };
            \\export fn threadlocal_read(a: *u32, b: *u16) void {
            \\    a.* = threadlocal_var;
            \\    b.* = threadlocal_arr[3];
            \\}
            \\export fn threadlocal_write(a: u32, b: u16) void {
            \\    threadlocal_var = a;
            \\    threadlocal_arr[3] = b;
            \\}
            ,
        });

        case.verifyObjdump(obj.getEmittedBin(), &.{
            "-s",
            "--symbols",
            "--only-symbol=threadlocal",
            "--only-symbol=tls",
        }, .{ .use_llvm = true });

        const exe = case.addExecutable(.{
            .name = "test",
            .zig_source_bytes =
            \\extern fn threadlocal_read(a: *u32, b: *u16) void;
            \\extern fn threadlocal_write(a: u32, b: u16) void;
            \\threadlocal var threadlocal_foo: u64 = 0xcafecafecafecafe;
            \\pub fn main() !u8 {
            \\    var a: u32 = undefined;
            \\    var b: u16 = undefined;
            \\    threadlocal_read(&a, &b);
            \\    if (a != 1234 or b != 0x4444) return 1;
            \\    if (threadlocal_foo != 0xcafecafecafecafe) return 2;
            \\    threadlocal_write(0xabcdabcd, 0x5555);
            \\    threadlocal_foo = 1;
            \\    threadlocal_read(&a, &b);
            \\    if (a != 0xabcdabcd or b != 0x5555) return 3;
            \\    if (threadlocal_foo != 1) return 4;
            \\    return 0;
            \\}
            ,
        });
        exe.root_module.addObject(obj);

        const run = case.addRunArtifact(exe);
        run.addCheck(.{ .expect_term = .{ .exited = 0 } });
    }

    if (ctx.includeTest("dynamic-lib-code")) |case| {
        const lib = case.addLibrary(.dynamic, .{
            .name = "lib",
            .name_target = false,
            .zig_source_bytes =
            \\export fn foo1() callconv(.c) u64 {
            \\    return 0x1122334411223344;
            \\}
            \\export fn foo2() callconv(.c) u64 {
            \\    return 0xaabbccddaabbccdd;
            \\}
            ,
        });

        case.verifyObjdump(lib.getEmittedBin(), &.{
            "-s",
            "--exports",
            "--only-symbol=foo",
        }, .{ .os = true });

        if (ctx.target.result.os.tag == .windows) {
            case.verifyObjdump(lib.getEmittedImplib(), &.{
                "-s",
                "--exports=sort",
                "--only-symbol=foo",
            }, .{ .sub_name = "implib", .os = true, .arch = true });
        }

        const exe = case.addExecutable(.{
            .name = "test",
            .zig_source_bytes =
            \\extern fn foo1() u64;
            \\pub fn main() !u8 {
            \\    const foo2 = @extern(
            \\        *const fn () callconv(.c) u64,
            \\        .{ .name = "foo2", .is_dll_import = true },
            \\    );
            \\    return @intFromBool(0xbbde0021bbde0021 != foo1() + foo2());
            \\}
            ,
        });
        exe.root_module.linkLibrary(lib);

        const run = case.addRunArtifact(exe);
        run.addCheck(.{ .expect_term = .{ .exited = 0 } });
    }

    if (ctx.includeTest("dynamic-lib-data")) |case| {
        const lib = case.addLibrary(.dynamic, .{
            .name = "lib",
            .name_target = false,
            .zig_source_bytes =
            \\export var foo_array: [2]u16 = .{ 0xffff, 0xabcd };
            \\export var foo_strong: usize = 0x1122334411223344;
            \\comptime {
            \\    @export(&foo_strong, .{ .name = "foo_strong_alias", .linkage = .strong });
            \\}
            ,
        });

        case.verifyObjdump(lib.getEmittedBin(), &.{
            "-s",
            "--exports",
            "--only-symbol=foo",
        }, .{});

        if (ctx.target.result.os.tag == .windows) {
            case.verifyObjdump(lib.getEmittedImplib(), &.{
                "-s",
                "--exports=sort",
                "--only-symbol=foo",
            }, .{ .sub_name = "implib", .os = true, .arch = true });
        }

        const exe = case.addExecutable(.{
            .name = "test",
            .zig_source_bytes =
            \\pub fn main() !u8 {
            \\    const foo_array = @extern(*[2]u16, .{ .name = "foo_array", .is_dll_import = true });
            \\    const foo_strong = @extern(*usize, .{ .name = "foo_strong", .is_dll_import = true });
            \\    const foo_strong_alias = @extern(*usize, .{ .name = "foo_strong_alias", .is_dll_import = true });
            \\    return @intFromBool(0x2244668822451255 !=
            \\        foo_array[1] +
            \\            foo_strong.* +
            \\            foo_strong_alias.*);
            \\}
            ,
        });
        exe.root_module.linkLibrary(lib);

        const run = case.addRunArtifact(exe);
        run.addCheck(.{ .expect_term = .{ .exited = 0 } });
    }

    if (ctx.includeTest("abs-symbol")) |case| {
        const abs = case.addObject(.{
            .name = "abs",
            .use_llvm = true, // TODO: .globl not supported on self-hosted
            .use_lld = true,
            .asm_source_bytes =
            \\.globl foo
            \\foo = 0xcafecafe
            \\
            ,
        });

        const abs_reloc = case.addObject(.{
            .name = "abs_reloc",
            .use_llvm = true, // TODO: .globl not supported on self-hosted
            .use_lld = true,
            .asm_source_bytes =
            \\.data
            \\.globl foo_copy
            \\foo_copy:
            \\.long foo
            ,
        });

        case.verifyObjdump(abs_reloc.getEmittedBin(), &.{
            "-s",
            "--relocs",
        }, .{ .arch = true });

        const exe = case.addExecutable(.{
            .name = "test",
            .zig_source_bytes =
            \\extern var foo_copy: u32;
            \\pub fn main() !u8 {
            \\    return @intFromBool(foo_copy != 0xcafecafe);
            \\}
            ,
        });
        exe.root_module.addObject(abs);
        exe.root_module.addObject(abs_reloc);

        const run = case.addRunArtifact(exe);
        run.addCheck(.{ .expect_term = .{ .exited = 0 } });

        if (!ctx.use_llvm) {
            const exe_reloc_err = case.addExecutable(.{
                .name = "test-reloc-err",
                .zig_source_bytes =
                \\extern const foo: u32;
                \\pub fn main() !u8 {
                \\    return @intFromBool(foo != 0xcafecafe);
                \\}
                ,
            });
            exe_reloc_err.root_module.addObject(abs);
            case.expectLinkErrors(exe_reloc_err, .{
                .contains = "error: absolute symbol 'foo' targeted by invalid relocation type: /?/",
            });
        }
    }

    if (ctx.includeTest("explicit-extern-lib-name")) |case| {
        // TODO: Lld.zig does not look at explicit inputs to resolve explicit extern lib names
        if (ctx.use_llvm) return;

        const lib1 = case.addLibrary(.dynamic, .{
            .name = "lib1",
            .name_target = false,
            .zig_source_bytes =
            \\export fn foo() u8 {
            \\    return 43;
            \\}
            ,
        });

        const lib2 = case.addLibrary(.dynamic, .{
            .name = "lib2",
            .name_target = false,
            .zig_source_bytes =
            \\export fn foo() u8 {
            \\    return 42;
            \\}
            ,
        });

        const lib3 = case.addLibrary(.static, .{
            .name = "lib3",
            .zig_source_bytes =
            \\extern fn foo() u8;
            \\export fn callFoo() u8 {
            \\    return foo();
            \\}
            ,
        });

        const exe = case.addExecutable(.{
            .name = "test",
            .zig_source_bytes =
            \\extern "explicit-extern-lib-name-lib2" fn foo() u8;
            \\extern fn callFoo() u8;
            \\pub fn main() !u8 {
            \\    return foo() + callFoo();
            \\}
            ,
        });
        exe.root_module.linkLibrary(lib1);
        exe.root_module.linkLibrary(lib2);
        // exe.root_module.addLibraryPath(.{
        //     .generated = .{
        //         .index = lib2.getEmittedBin().generated.index,
        //         .up = 1,
        //     },
        // });
        exe.root_module.linkLibrary(lib3);

        const run = case.addRunArtifact(exe);
        run.addCheck(.{ .expect_term = .{ .exited = 84 } });
    }
}

const LinkContext = @import("tests.zig").LinkContext;
const std = @import("std");

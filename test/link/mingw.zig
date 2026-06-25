pub fn addCases(ctx: *LinkContext) void {
    if (ctx.includeTest("ctor-dtor")) |case| {
        if (!ctx.link_libc) return;

        const obj = case.addObject(.{
            .name = "obj",
            .use_llvm = true,
            .use_lld = true,
            .c_source_bytes =
            \\#include <stdlib.h>
            \\int foo;
            \\__attribute__((constructor))
            \\static void init_foo() {
            \\    foo = 42;
            \\}
            \\__attribute__((destructor))
            \\static void deinit_foo() {
            \\    exit(42);
            \\}
            ,
        });

        const lib = case.addLibrary(.static, .{
            .name = "lib",
            .name_prefix = false,
            .name_target = false,
        });
        lib.root_module.addObject(obj);

        const exe = case.addExecutable(.{
            .name = "test",
            .zig_source_bytes =
            \\extern var foo: u32; 
            \\pub fn main() !u8 {
            \\    if (foo != 42) return 1;
            \\    return 2;
            \\}
            ,
        });
        exe.root_module.addObject(obj);

        const run = case.addRunArtifact(exe);
        run.addCheck(.{ .expect_term = .{ .exited = 42 } });
    }
}

const LinkContext = @import("../tests.zig").LinkContext;
const std = @import("std");

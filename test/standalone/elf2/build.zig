pub fn build(b: *Build) void {
    const test_step = b.step("test", "Test the new ELF linker");
    b.default_step = test_step;

    if (b.graph.host.result.cpu.arch == .x86_64 and b.graph.host.result.os.tag == .linux) {
        addOne(b, test_step, b.graph.host, false, .static, false, "elf2-hello-native-selfhosted-static");
        addOne(b, test_step, b.graph.host, false, .dynamic, false, "elf2-hello-native-selfhosted-dynamic");
        addOne(b, test_step, b.graph.host, false, .static, true, "elf2-hello-native-selfhosted-static-pie");
        addOne(b, test_step, b.graph.host, false, .dynamic, true, "elf2-hello-native-selfhosted-dynamic-pie");
        addOne(b, test_step, b.graph.host, true, .static, false, "elf2-hello-native-llvm-static");
        addOne(b, test_step, b.graph.host, true, .dynamic, false, "elf2-hello-native-llvm-dynamic");
    }

    const x86_64_linux_target: Build.ResolvedTarget = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
    });
    addOne(b, test_step, x86_64_linux_target, false, .static, false, "elf2-hello-selfhosted-static");
    addOne(b, test_step, x86_64_linux_target, false, .static, true, "elf2-hello-selfhosted-static-pie");
    addOne(b, test_step, x86_64_linux_target, true, .static, false, "elf2-hello-llvm-static");
}

fn addOne(
    b: *Build,
    test_step: *Build.Step,
    target: Build.ResolvedTarget,
    use_llvm: bool,
    link_mode: std.lang.LinkMode,
    pie: bool,
    name: []const u8,
) void {
    const mod = b.createModule(.{
        .root_source_file = b.path("hello.zig"),
        .target = target,
        .optimize = .Debug,
        .link_libc = link_mode == .dynamic,
    });
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = mod,
        .linkage = link_mode,
    });
    exe.use_new_linker = true;
    exe.use_llvm = use_llvm;
    if (pie) exe.pie = true;

    const run = b.addRunArtifact(exe);
    run.expectExitCode(0);
    run.expectStdOutEqual("Hello, World!\n");
    run.skip_foreign_checks = true;

    test_step.dependOn(&run.step);
}

const std = @import("std");
const Build = std.Build;

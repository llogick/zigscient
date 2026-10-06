const builtin = @import("builtin");
const std = @import("std");

const compiler_rt = @import("../../compiler_rt.zig");
const symbol = compiler_rt.symbol;

comptime {
    symbol(@ptrCast(&__zig_elf_auxv), "__zig_elf_auxv");
}

/// Populated by `std.start` when libc is not linked on targets that provide an ELF auxiliary vector
/// to the process on startup. Provided by compiler-rt so that there is no confusion about where
/// this state lives regardless of how the final artifact (executable or shared library) is
/// compiled.
///
/// It is expected that this will gradually be replaced with better mechanisms as operating systems
/// improve; see https://codeberg.org/ziglang/zig/issues/31290.
var __zig_elf_auxv: [*]std.elf.Auxv = undefined;

const std = @import("std");
const windows = std.os.windows;

extern "kernel32" fn LoadLibraryW(windows.LPCWSTR) callconv(.winapi) ?windows.HMODULE;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) return error.NoDllPathSpecified;
    const dll_path = args[1];
    const dll_path_w = try std.unicode.wtf8ToWtf16LeAllocZ(arena, dll_path);
    _ = LoadLibraryW(dll_path_w) orelse return error.FailedToLoadDll;
}

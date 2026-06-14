const std = @import("std");
const windows = std.os.windows;

const DLL_PROCESS_ATTACH = 1;

pub fn DllMain(
    hinstDLL: windows.HINSTANCE,
    fdwReason: windows.DWORD,
    lpReserved: windows.LPVOID,
) windows.BOOL {
    _ = hinstDLL;
    _ = lpReserved;
    switch (fdwReason) {
        DLL_PROCESS_ATTACH => std.debug.print("hello from DllMain", .{}),
        else => {},
    }
    return .TRUE;
}

export fn entry(ptr: *anyopaque) void {
    const ct_only: *type = @ptrCast(ptr);
    _ = ct_only.*;
}

// error
//
// :3:16: error: cannot load comptime-only type 'type'
// :3:9: note: pointer of type '*type' is runtime-known

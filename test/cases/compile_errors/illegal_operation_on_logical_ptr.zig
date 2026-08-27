export fn intFromPtr() void {
    var value: u8 = 0;
    _ = @intFromPtr(&value);
}

export fn ptrFromInt() void {
    var v: u32 = 0x1234;
    var ptr: *u8 = @ptrFromInt(v);
    _ = &v;
    _ = &ptr;
}

export fn ptrPtrArithmetic() void {
    var value0: u8 = 0;
    var value1: u8 = 0;
    _ = &value0 - &value1;
}

export fn ptrIntArithmetic() void {
    var ptr0: [*]u8 = undefined;
    _ = &ptr0;
    _ = ptr0 - 10;
}

const slice: []const u8 = "abc";

export fn sliceElemVal() void {
    var i: u32 = 0;
    _ = &i;
    _ = slice[i];
}

export fn sliceElemPtr() void {
    var i: u32 = 0;
    _ = &i;
    _ = &slice[i];
}

export fn manyElemVal() void {
    var ptr: [*]const u8 = "abc";
    var i: u32 = 0;
    _ = .{ &ptr, &i };
    _ = ptr[i];
}

export fn manyElemPtr() void {
    var ptr: [*]const u8 = "abc";
    var i: u32 = 0;
    _ = .{ &ptr, &i };
    _ = &ptr[i];
}

// error
// target=spirv64-vulkan
//
// :3:21: error: illegal operation on logical pointer of type '*u8'
// :3:21: note: pointers with address space 'generic' do not support arithmetic or indexing on target spirv-vulkan
// :8:20: error: illegal operation on logical pointer of type '*u8'
// :8:20: note: pointers with address space 'generic' do not support arithmetic or indexing on target spirv-vulkan
// :16:17: error: illegal operation on logical pointer of type '*u8'
// :16:17: note: pointers with address space 'generic' do not support arithmetic or indexing on target spirv-vulkan
// :22:14: error: illegal operation on logical pointer of type '[*]u8'
// :22:14: note: pointers with address space 'generic' do not support arithmetic or indexing on target spirv-vulkan
// :30:14: error: illegal operation on logical pointer of type '[]const u8'
// :30:14: note: pointers with address space 'generic' do not support arithmetic or indexing on target spirv-vulkan
// :36:15: error: illegal operation on logical pointer of type '[]const u8'
// :36:15: note: pointers with address space 'generic' do not support arithmetic or indexing on target spirv-vulkan
// :43:12: error: illegal operation on logical pointer of type '[*]const u8'
// :43:12: note: pointers with address space 'generic' do not support arithmetic or indexing on target spirv-vulkan
// :50:13: error: illegal operation on logical pointer of type '[*]const u8'
// :50:13: note: pointers with address space 'generic' do not support arithmetic or indexing on target spirv-vulkan

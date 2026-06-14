export fn entry1(x: *anyopaque) void {
    _ = @as([]u8, @ptrCast(x));
}

const Opaque = opaque {};
export fn entry2(x: *Opaque) void {
    _ = @as([]u8, @ptrCast(x));
}

// error
//
// :2:19: error: cannot infer length of slice of 'u8' from pointer to opaque type 'anyopaque' with unknown size
// :7:19: error: cannot infer length of slice of 'u8' from pointer to opaque type 'tmp.Opaque' with unknown size
// :5:16: note: opaque declared here

pub const A = enum {
    a1,
    a2,

    pub fn x(comptime _: A) usize {
        return 0;
    }

    pub fn y(self: A) usize {
        return self.x();
    }
};

pub fn main() void {
    _ = A.y(.a1);
}

// error
//
// :10:20: error: unable to resolve comptime value
// :10:20: note: argument to comptime parameter must be comptime-known
// :5:14: note: parameter declared comptime here

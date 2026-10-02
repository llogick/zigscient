pub fn main() void {
    var x: u32 = 0;
    for (0..3) |_| {
        x +%= 1;
    }
    {
        var i: u32 = 0;
        while (i < 3) : (i +%= 1) {
            x +%= 1;
        }
    }
    {
        var i: u32 = 0;
        while (i < 3) {
            i +%= 1;
        }
    }
    inline for (0..3) |_| {
        x +%= 1;
    }
    {
        comptime var i: u32 = 0;
        inline while (i < 3) : (i +%= 1) {
            x +%= 1;
        }
    }
    {
        comptime var i: u32 = 0;
        inline while (i < 3) {
            i +%= 1;
        }
    }
    x +%= 1;
}

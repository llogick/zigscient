inline fn select(cond: bool, a: anytype, b: anytype) @TypeOf(a, b) {
    if (cond) {
        return a;
    } else {
        return b;
    }
}
export fn f(x: u32) u32 {
    return select(x > 0, 2, 1);
}

// error
//
// :9:18: error: value with comptime-only type 'comptime_int' depends on runtime control flow
// :2:9: note: runtime control flow here
// :9:18: note: called inline here

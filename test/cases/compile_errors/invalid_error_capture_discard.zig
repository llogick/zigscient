export fn a() void {
    const x: error{}!void = {};
    x catch |_| {
        @"_";
    };
}
export fn b() void {
    const x: error{}!void = {};
    x catch |_| switch (_) {};
}
export fn c() void {
    const x: error{}!u32 = 0;
    if (x) |v| v else |_| switch (_) {}
}

// error
//
// :3:14: error: discard of error capture; omit it instead
// :4:9: error: use of undeclared identifier '_'
// :9:14: error: discard of error capture; omit it instead
// :13:24: error: discard of error capture; omit it instead

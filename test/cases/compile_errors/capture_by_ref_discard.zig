export fn a() void {
    for (.{}) |*_| {}
}

export fn b() void {
    switch (0) {
        else => |*_| {},
    }
}

export fn c() void {
    if (null) |*_| {}
}

export fn d() void {
    while (null) |*_| {}
}

export fn e() void {
    if (0) |*_| {} else |err| switch (err) {}
}

// error
//
// :2:16: error: pointer modifier invalid on discard
// :7:18: error: pointer modifier invalid on discard
// :12:16: error: pointer modifier invalid on discard
// :16:19: error: pointer modifier invalid on discard
// :20:13: error: pointer modifier invalid on discard

const E = enum(@compileError("enum")) {
    x = 0,
};

const U = union(enum(@compileError("union"))) {
    x = 0,
};

const S = packed struct(@compileError("struct")) {
    x: u8 = 0,
};

comptime {
    _ = &E.x;
}

comptime {
    _ = &U.x;
}

comptime {
    _ = &S{};
}

// error
//
// :1:16: error: enum
// :5:22: error: union
// :9:25: error: struct

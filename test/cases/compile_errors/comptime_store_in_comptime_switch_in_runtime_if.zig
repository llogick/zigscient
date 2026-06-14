fn foo() bool {
    return false;
}

pub export fn entry() void {
    const Widget = union(enum) { a: u0 };

    comptime var a = 1;
    const info = @typeInfo(Widget).@"union";
    inline for (info.field_types) |field_type| {
        if (foo()) {
            switch (field_type) {
                u0 => a = 2,
                else => unreachable,
            }
        }
    }
}

// error
//
// :13:25: error: store to comptime variable depends on runtime condition
// :11:16: note: runtime condition here

fn T() type {
    return u64;
}

test {
    struct {
        var a: u64 = 0;
    }.a, const b: T() = .{ 1, 2 };
    _ = b;
}

// compile
// output_mode=Obj

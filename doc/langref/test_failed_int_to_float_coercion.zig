test "integer type is too large for implicit cast to float" {
    var int: u25 = 123;
    _ = &int;
    const float: f32 = int;
    _ = float;
}

// test_error=

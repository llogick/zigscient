const Error = error {OutOfMemory, ReadFailed};
const result: Error!u64 = error.OutOfMemory;

test {
    _ = result catch |err| switch (err) {
        error.ReadFailed => 2,
        error.OutOfMemory => |*val| 1,
    };
}

test {
    _ = result catch |err| switch (err) {
        error.ReadFailed => 2,
        error.OutOfMemory => |_, tag| 1,
    };
}

test {
    _ = if (result) |n| n else |err| switch (err) {
        error.ReadFailed => 2,
        error.OutOfMemory => |*val| 1,
    };
}

test {
    _ = if (result) |n| n else |err| switch (err) {
        error.ReadFailed => 2,
        error.OutOfMemory => |_, tag| 1,
    };
}

// error
//
// :7:32: error: error set cannot be captured by reference
// :14:34: error: cannot capture tag of error union
// :21:32: error: error set cannot be captured by reference
// :28:34: error: cannot capture tag of error union

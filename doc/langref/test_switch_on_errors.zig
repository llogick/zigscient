const FileOpenError0 = error{
    AccessDenied,
    OutOfMemory,
    FileNotFound,
};

fn openFile0() FileOpenError0 {
    return error.OutOfMemory;
}

test "unreachable else prong" {
    switch (openFile0()) {
        error.AccessDenied, error.FileNotFound => |e| return e,
        error.OutOfMemory => {},
        // 'openFile0' cannot return any more errors, so an 'else' prong would be
        // statically known to be unreachable. Nonetheless, in this case, adding
        // one does not raise an "unreachable else prong" compile error:
        else => unreachable,
    }

    // Allowed unreachable else prongs are:
    //    `else => unreachable,`
    //    `else => return,`
    //    `else => |e| return e,` (where `e` is any identifier)
}

const FileOpenError1 = error{
    AccessDenied,
    SystemResources,
    FileNotFound,
};

fn openFile1() FileOpenError1 {
    return error.SystemResources;
}

fn openFileGeneric(comptime kind: u1) switch (kind) {
    0 => FileOpenError0,
    1 => FileOpenError1,
} {
    return switch (kind) {
        0 => openFile0(),
        1 => openFile1(),
    };
}

test "comptime unreachable errors not in error set" {
    switch (openFileGeneric(1)) {
        error.AccessDenied, error.FileNotFound => |e| return e,
        error.OutOfMemory => comptime unreachable, // not in `FileOpenError1`!
        error.SystemResources => {},
    }
}

// test

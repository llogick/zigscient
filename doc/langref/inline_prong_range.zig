fn isFieldOptional(comptime T: type, field_index: usize) !bool {
    const field_types = @typeInfo(T).@"struct".field_types;
    return switch (field_index) {
        inline 0...field_types.len - 1 => |idx| @typeInfo(field_types[idx]) == .optional,
        else => return error.IndexOutOfBounds,
    };
}

// syntax

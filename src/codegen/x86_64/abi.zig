pub const Class = enum {
    /// INTEGER: This class consists of integral types that fit into one of the general
    ///     purpose registers.
    integer,
    /// SSE: The class consists of types that fit into a vector register.
    sse,
    /// SSEUP: The class consists of types that fit into a vector register and can be passed
    ///     and returned in the upper bytes of it.
    sseup,
    /// X87, X87UP: These classes consist of types that will be returned via the
    ///     x87 FPU.
    x87,
    /// The 15-bit exponent, 1-bit sign, and 6 bytes of padding of an `f80`.
    x87up,
    /// NO_CLASS: This class is used as initializer in the algorithms. It will be used for
    ///     padding and empty structures and unions.
    none,
    /// MEMORY: This class consists of types that will be passed and returned in mem-
    ///     ory via the stack.
    memory,
    /// Win64 passes 128-bit integers as `Class.memory` but returns them as `Class.sse`.
    win_i128,
    /// A `Class.sse` containing one `f32`.
    float,
    /// A `Class.sse` containing two `f32`s.
    float_combine,
    /// Clang uses different element sizes depending on the vector length.
    bool_vector_mask,
    /// Clang passes each vector element in a separate `Class.integer`.
    integer_per_element,
    /// Clang passes each vector element in a separate `Class.sse`.
    sse_per_element,
    /// Just complete insanity, idk what to say.
    sse_sse_x87_per_qword,
    /// Clang passes each 16 bytes in a separate `Class.sse`.
    sse_per_xword,
    /// Clang passes each 32 bytes in a separate `Class.sse`.
    sse_per_yword,
    /// Clang passes each 64 bytes in a separate `Class.sse`.
    sse_per_zword,

    pub const zero_bit: [8]Class = .{ .none, .none, .none, .none, .none, .none, .none, .none };

    pub const one_integer: [8]Class = .{ .integer, .none, .none, .none, .none, .none, .none, .none };
    pub const two_integers: [8]Class = .{ .integer, .integer, .none, .none, .none, .none, .none, .none };
    pub const three_integers: [8]Class = .{ .integer, .integer, .integer, .none, .none, .none, .none, .none };
    pub const four_integers: [8]Class = .{ .integer, .integer, .integer, .integer, .none, .none, .none, .none };
    pub const len_integers: [8]Class = .{ .integer_per_element, .none, .none, .none, .none, .none, .none, .none };

    pub const @"f16" = @"f64";
    pub const @"f32": [8]Class = .{ .float, .none, .none, .none, .none, .none, .none, .none };
    pub const @"f64": [8]Class = .{ .sse, .none, .none, .none, .none, .none, .none, .none };
    pub const @"f80": [8]Class = .{ .x87, .x87up, .none, .none, .none, .none, .none, .none };
    pub const @"f128": [8]Class = .{ .sse, .sseup, .none, .none, .none, .none, .none, .none };

    /// COMPLEX_X87: This class consists of types that will be returned via the x87
    ///     FPU.
    pub const complex_x87: [8]Class = .{ .x87, .x87up, .x87, .x87up, .none, .none, .none, .none };

    pub const stack: [8]Class = .{ .memory, .none, .none, .none, .none, .none, .none, .none };

    pub fn isX87(class: Class) bool {
        return switch (class) {
            .x87, .x87up => true,
            else => false,
        };
    }

    /// Combine a field class with the prev one.
    fn combineSystemV(prev_class: Class, next_class: Class) Class {
        // "If both classes are equal, this is the resulting class."
        if (prev_class == next_class)
            return if (prev_class == .float) .float_combine else prev_class;

        // "If one of the classes is NO_CLASS, the resulting class
        // is the other class."
        if (prev_class == .none) return next_class;

        // "If one of the classes is MEMORY, the result is the MEMORY class."
        if (prev_class == .memory or next_class == .memory) return .memory;

        // "If one of the classes is INTEGER, the result is the INTEGER."
        if (prev_class == .integer or next_class == .integer) return .integer;

        // "If one of the classes is X87, X87UP, COMPLEX_X87 class,
        // MEMORY is used as class."
        if (prev_class.isX87() or next_class.isX87()) return .memory;

        // "Otherwise class SSE is used."
        return .sse;
    }
};

pub const Context = enum { ret, arg, other };

pub fn classifyWindows(init_ty: Type, zcu: *Zcu, target: *const std.Target, ctx: Context) Class {
    // https://docs.microsoft.com/en-gb/cpp/build/x64-calling-convention?view=vs-2017
    // "There's a strict one-to-one correspondence between a function call's arguments
    // and the registers used for those arguments. Any argument that doesn't fit in 8
    // bytes, or isn't 1, 2, 4, or 8 bytes, must be passed by reference. A single argument
    // is never spread across multiple registers."
    // "All floating point operations are done using the 16 XMM registers."
    // "Structs and unions of size 8, 16, 32, or 64 bits, and __m64 types, are passed
    // as if they were integers of the same size."
    var ty = init_ty;
    while (true) return switch (ty.zigTypeTag(zcu)) {
        .void => return .none,
        .bool,
        .pointer,
        .int,
        .@"enum",
        .error_set,
        .@"struct",
        .@"union",
        .optional,
        .array,
        .error_union,
        .@"anyframe",
        .frame,
        => switch (ty.abiSize(zcu)) {
            0 => .none,
            1, 2, 4, 8 => .integer,
            else => switch (ty.zigTypeTag(zcu)) {
                .int => .win_i128,
                .@"struct", .@"union" => if (ty.containerLayout(zcu) == .@"packed")
                    .win_i128
                else
                    .memory,
                else => .memory,
            },
        },
        .noreturn => unreachable,
        .float => switch (ty.floatBits(target)) {
            16, 32, 64 => .sse,
            80 => .memory,
            128 => if (ctx == .arg) .memory else .sse,
            else => unreachable,
        },
        .vector => {
            const len = ty.vectorLen(zcu);
            if (len == 0) return .none;
            const elem_ty = ty.childType(zcu);
            if (len == 1) {
                ty = elem_ty;
                continue;
            }
            const reg_size: u64, const split_class: Class = if (target.cpu.has(.x86, .avx512f))
                .{ 64, .sse_per_zword }
            else if (target.cpu.has(.x86, .avx))
                .{ 32, .sse_per_yword }
            else
                .{ 16, .sse_per_xword };
            if (elem_ty.toIntern() == .bool_type) {
                if (len > reg_size) return if (ctx == .arg) .integer_per_element else .memory;
                return .bool_vector_mask;
            }
            const elem_size = elem_ty.abiSize(zcu);
            const unaligned_size = elem_size * len;
            if ((unaligned_size <= 8 or unaligned_size > reg_size) and !std.math.isPowerOfTwo(len)) {
                if (ctx == .ret and len > Win64.c_abi_int_return_regs.len) return .memory;
                if (!elem_ty.isRuntimeFloat()) return .integer_per_element;
                if (ctx == .ret and len > 2 and elem_size == 8) return .sse_sse_x87_per_qword;
                return .sse_per_element;
            }
            if (unaligned_size <= reg_size) return if (ctx == .arg) .memory else .sse;
            if (ctx == .ret and unaligned_size > reg_size * Win64.c_abi_sse_return_regs.len) return .memory;
            return split_class;
        },
        .type,
        .comptime_float,
        .comptime_int,
        .undefined,
        .null,
        .@"fn",
        .@"opaque",
        .spirv,
        .enum_literal,
        => unreachable,
    };
}

/// There are a maximum of 8 possible return slots. Returned values are in
/// the beginning of the array; unused slots are filled with .none.
pub fn classifySystemV(ty: Type, zcu: *Zcu, target: *const std.Target, ctx: Context) [8]Class {
    switch (ty.zigTypeTag(zcu)) {
        .void => return Class.zero_bit,
        .bool => return Class.one_integer,
        .noreturn => unreachable,
        .int, .@"enum", .error_set => {
            const bits = ty.intInfo(zcu).bits;
            if (bits == 0) return Class.zero_bit;
            if (bits <= 64 * 1) return Class.one_integer;
            if (bits <= 64 * 2) return Class.two_integers;
            if (bits <= 64 * 3) return Class.three_integers;
            if (bits <= 64 * 4) return Class.four_integers;
            return Class.stack;
        },
        .float => switch (ty.floatBits(target)) {
            16 => {
                if (ctx == .other) return Class.stack;
                // TODO clang doesn't allow __fp16 as .ret or .arg
                return Class.f16;
            },
            32 => return Class.f32,
            64 => return Class.f64,
            // "Arguments of types __float128, _Decimal128 and __m128 are
            // split into two halves.  The least significant ones belong
            // to class SSE, the most significant one to class SSEUP."
            128 => return Class.f128,
            // "The 64-bit mantissa of arguments of type long double
            // belongs to class X87, the 16-bit exponent plus 6 bytes
            // of padding belongs to class X87UP."
            80 => return Class.f80,
            else => unreachable,
        },
        .pointer => switch (ty.ptrSize(zcu)) {
            .slice => return Class.two_integers,
            else => return Class.one_integer,
        },
        .vector => {
            const len = ty.vectorLen(zcu);
            if (len == 0) return Class.zero_bit;
            const elem_ty = ty.childType(zcu);
            if (elem_ty.toIntern() == .bool_type) {
                if (len <= 32) return Class.one_integer;
                if (len <= 64) return Class.f64;
                if (ctx != .arg) return Class.stack;
                if (len <= 128) return Class.len_integers;
                if (len <= 256 and target.cpu.has(.x86, .avx)) return Class.len_integers;
                if (len <= 512 and target.cpu.has(.x86, .avx512f)) return Class.len_integers;
                return Class.stack;
            }
            if (elem_ty.isRuntimeFloat() and elem_ty.floatBits(target) == 80) switch (len) {
                0 => unreachable,
                1 => return Class.f80,
                2 => return Class.complex_x87,
                else => return Class.stack,
            };
            const unaligned_size = elem_ty.abiSize(zcu) * len;
            if (unaligned_size <= 4) return Class.one_integer;
            if (ctx == .arg and unaligned_size == 8 * 1 * 1 and len == 1 and
                elem_ty.isRuntimeFloat()) return Class.stack; // what
            if (unaligned_size <= 8 * 1) return .{ .sse, .none, .none, .none, .none, .none, .none, .none };
            if (unaligned_size <= 8 * 2) return .{ .sse, .sseup, .none, .none, .none, .none, .none, .none };
            if (!target.cpu.has(.x86, .avx)) {
                if (ctx == .ret) switch (unaligned_size) {
                    else => {},
                    8 * 3 => if (len == 3) return if (elem_ty.isRuntimeFloat()) .{
                        .sse_sse_x87_per_qword, .none, .none, .none, .none, .none, .none, .none, // how
                    } else Class.len_integers, // why
                    8 * 2 * 2, 8 * 2 * 4 => return .{ .sse_per_xword, .none, .none, .none, .none, .none, .none, .none },
                };
                return Class.stack;
            }
            if (unaligned_size <= 8 * 3) return .{ .sse, .sseup, .sseup, .none, .none, .none, .none, .none };
            if (unaligned_size <= 8 * 4) return .{ .sse, .sseup, .sseup, .sseup, .none, .none, .none, .none };
            if (!target.cpu.has(.x86, .avx512f)) {
                if (ctx == .ret) switch (unaligned_size) {
                    else => {},
                    8 * 4 * 2, 8 * 4 * 4 => return .{ .sse_per_yword, .none, .none, .none, .none, .none, .none, .none },
                };
                return Class.stack;
            }
            if (unaligned_size <= 8 * 5) return .{ .sse, .sseup, .sseup, .sseup, .sseup, .none, .none, .none };
            if (unaligned_size <= 8 * 6) return .{ .sse, .sseup, .sseup, .sseup, .sseup, .sseup, .none, .none };
            if (unaligned_size <= 8 * 7) return .{ .sse, .sseup, .sseup, .sseup, .sseup, .sseup, .sseup, .none };
            if (unaligned_size <= 8 * 8) return .{ .sse, .sseup, .sseup, .sseup, .sseup, .sseup, .sseup, .sseup };
            if (ctx == .ret) switch (unaligned_size) {
                else => {},
                8 * 8 * 2, 8 * 8 * 4 => return .{ .sse_per_zword, .none, .none, .none, .none, .none, .none, .none },
            };
            return Class.stack;
        },
        .optional => {
            if (ty.optionalReprIsPayload(zcu)) {
                return classifySystemV(ty.optionalChild(zcu), zcu, target, ctx);
            }
            return Class.stack;
        },
        .@"struct", .@"union" => {
            // "If the size of an object is larger than eight eightbytes, or
            // it contains unaligned fields, it has class MEMORY"
            // "If the size of the aggregate exceeds a single eightbyte, each is classified
            // separately.".
            const ty_size = ty.abiSize(zcu);
            if (ty_size == 0) return Class.zero_bit;
            switch (ty.containerLayout(zcu)) {
                .auto => unreachable,
                .@"extern" => {},
                .@"packed" => {
                    if (ty_size <= 8) return Class.one_integer;
                    if (ty_size <= 16) return Class.two_integers;
                    unreachable; // frontend should not have allowed this type as extern
                },
            }
            if (ty_size > 64) return Class.stack;

            var result: [8]Class = @splat(.none);
            _ = if (zcu.typeToStruct(ty)) |loaded_struct|
                classifySystemVStruct(&result, 0, loaded_struct, zcu, target)
            else if (zcu.typeToUnion(ty)) |loaded_union|
                classifySystemVUnion(&result, 0, loaded_union, zcu, target)
            else
                unreachable;

            // Post-merger cleanup

            // "If one of the classes is MEMORY, the whole argument is passed in memory"
            // "If X87UP is not preceded by X87, the whole argument is passed in memory."
            for (result, 0..) |class, i| switch (class) {
                .memory => return Class.stack,
                .x87up => if (i == 0 or result[i - 1] != .x87) return Class.stack,
                else => {},
            };
            // "If the size of the aggregate exceeds two eightbytes and the first eight-
            // byte isn't SSE or any other eightbyte isn't SSEUP, the whole argument
            // is passed in memory."
            if (ty_size > 16 and (result[0] != .sse or
                std.mem.indexOfNone(Class, result[1..], &.{ .sseup, .none }) != null)) return Class.stack;

            // "If SSEUP is not preceded by SSE or SSEUP, it is converted to SSE."
            for (&result, 0..) |*class, i| switch (class.*) {
                .sseup => switch (result[i - 1]) {
                    .sse, .sseup => {},
                    else => class.* = .sse,
                },
                .float => if (i + 1 < result.len) switch (result[i + 1]) {
                    .none => {},
                    else => class.* = .float_combine,
                },
                else => {},
            };
            return result;
        },
        .array => {
            const ty_size = ty.abiSize(zcu);
            if (ty_size == 0) return Class.zero_bit;
            if (ty_size <= 8) return Class.one_integer;
            if (ty_size <= 16) return Class.two_integers;
            return Class.stack;
        },
        else => unreachable,
    }
}

fn classifySystemVStruct(
    result: *[8]Class,
    starting_byte_offset: u64,
    loaded_struct: InternPool.LoadedStructType,
    zcu: *Zcu,
    target: *const std.Target,
) u64 {
    const ip = &zcu.intern_pool;
    var byte_offset = starting_byte_offset;
    var field_it = loaded_struct.iterateRuntimeOrder(ip);
    while (field_it.next()) |field_index| {
        const field_ty = Type.fromInterned(loaded_struct.field_types.get(ip)[field_index]);
        const field_align = loaded_struct.field_aligns.getOrNone(ip, field_index);
        byte_offset = std.mem.alignForward(
            u64,
            byte_offset,
            field_align.toByteUnits() orelse field_ty.abiAlignment(zcu).toByteUnits().?,
        );
        if (zcu.typeToStruct(field_ty)) |field_loaded_struct| {
            switch (field_loaded_struct.layout) {
                .auto => unreachable,
                .@"extern" => {
                    byte_offset = classifySystemVStruct(result, byte_offset, field_loaded_struct, zcu, target);
                    continue;
                },
                .@"packed" => {},
            }
        } else if (zcu.typeToUnion(field_ty)) |field_loaded_union| {
            switch (field_loaded_union.layout) {
                .auto => unreachable,
                .@"extern" => {
                    byte_offset = classifySystemVUnion(result, byte_offset, field_loaded_union, zcu, target);
                    continue;
                },
                .@"packed" => {},
            }
        }
        const field_classes = std.mem.sliceTo(&classifySystemV(field_ty, zcu, target, .other), .none);
        for (result[@intCast(byte_offset / 8)..][0..field_classes.len], field_classes) |*result_class, field_class|
            result_class.* = result_class.combineSystemV(field_class);
        byte_offset += field_ty.abiSize(zcu);
    }
    const final_byte_offset = starting_byte_offset + loaded_struct.size;
    std.debug.assert(final_byte_offset == std.mem.alignForward(
        u64,
        byte_offset,
        loaded_struct.alignment.toByteUnits().?,
    ));
    return final_byte_offset;
}

fn classifySystemVUnion(
    result: *[8]Class,
    starting_byte_offset: u64,
    loaded_union: InternPool.LoadedUnionType,
    zcu: *Zcu,
    target: *const std.Target,
) u64 {
    const ip = &zcu.intern_pool;
    for (0..loaded_union.field_types.len) |field_index| {
        const field_ty = Type.fromInterned(loaded_union.field_types.get(ip)[field_index]);
        if (zcu.typeToStruct(field_ty)) |field_loaded_struct| {
            switch (field_loaded_struct.layout) {
                .auto => unreachable,
                .@"extern" => {
                    _ = classifySystemVStruct(result, starting_byte_offset, field_loaded_struct, zcu, target);
                    continue;
                },
                .@"packed" => {},
            }
        } else if (zcu.typeToUnion(field_ty)) |field_loaded_union| {
            switch (field_loaded_union.layout) {
                .auto => unreachable,
                .@"extern" => {
                    _ = classifySystemVUnion(result, starting_byte_offset, field_loaded_union, zcu, target);
                    continue;
                },
                .@"packed" => {},
            }
        }
        const field_classes = std.mem.sliceTo(&classifySystemV(field_ty, zcu, target, .other), .none);
        for (result[@intCast(starting_byte_offset / 8)..][0..field_classes.len], field_classes) |*result_class, field_class|
            result_class.* = result_class.combineSystemV(field_class);
    }
    return starting_byte_offset + loaded_union.size;
}

pub const zigcc = struct {
    pub const stack_align: ?InternPool.Alignment = null;
    pub const return_in_regs = true;
    pub const params_in_regs = true;

    const volatile_gpr = gp_regs.len - 5;
    const volatile_x87 = x87_regs.len - 1;
    const volatile_sse = sse_avx_regs.len;

    /// Note that .rsp and .rbp also belong to this set, however, we never expect to use them
    /// for anything else but stack offset tracking therefore we exclude them from this set.
    pub const callee_preserved_regs = gp_regs[volatile_gpr..] ++ x87_regs[volatile_x87 .. x87_regs.len - 1] ++ sse_avx_regs[volatile_sse..];
    /// These registers need to be preserved (saved on the stack) and restored by the caller before
    /// the caller relinquishes control to a subroutine via call instruction (or similar).
    /// In other words, these registers are free to use by the callee.
    pub const caller_preserved_regs = gp_regs[0..volatile_gpr] ++ x87_regs[0..volatile_x87] ++ sse_avx_regs[0..volatile_sse];

    const int_param_regs = gp_regs[0 .. volatile_gpr - 1];
    const x87_param_regs = x87_regs[0..volatile_x87];
    const sse_param_regs = sse_avx_regs[0 .. volatile_sse / 2];
    const int_return_regs = gp_regs[0..volatile_gpr];
    const x87_return_regs = x87_regs[0..volatile_x87];
    const sse_return_regs = sse_avx_regs[0..volatile_gpr];
};

pub const SysV = struct {
    /// Note that .rsp and .rbp also belong to this set, however, we never expect to use them
    /// for anything else but stack offset tracking therefore we exclude them from this set.
    pub const callee_preserved_regs = [_]Register{ .rbx, .r12, .r13, .r14, .r15 };
    /// These registers need to be preserved (saved on the stack) and restored by the caller before
    /// the caller relinquishes control to a subroutine via call instruction (or similar).
    /// In other words, these registers are free to use by the callee.
    pub const caller_preserved_regs = [_]Register{ .rax, .rcx, .rdx, .rsi, .rdi, .r8, .r9, .r10, .r11 } ++ x87_regs ++ sse_avx_regs;

    pub const c_abi_int_param_regs = [_]Register{ .rdi, .rsi, .rdx, .rcx, .r8, .r9 };
    pub const c_abi_x87_param_regs = x87_regs[0..0];
    pub const c_abi_sse_param_regs = sse_avx_regs[0..8];
    pub const c_abi_int_return_regs = [_]Register{ .rax, .rdx, .rcx };
    pub const c_abi_x87_return_regs = x87_regs[0..2];
    pub const c_abi_sse_return_regs = sse_avx_regs[0..4];
};

pub const Win64 = struct {
    /// Note that .rsp and .rbp also belong to this set, however, we never expect to use them
    /// for anything else but stack offset tracking therefore we exclude them from this set.
    pub const callee_preserved_regs = [_]Register{ .rbx, .rsi, .rdi, .r12, .r13, .r14, .r15 };
    /// These registers need to be preserved (saved on the stack) and restored by the caller before
    /// the caller relinquishes control to a subroutine via call instruction (or similar).
    /// In other words, these registers are free to use by the callee.
    pub const caller_preserved_regs = [_]Register{ .rax, .rcx, .rdx, .r8, .r9, .r10, .r11 } ++ x87_regs ++ sse_avx_regs;

    pub const c_abi_int_param_regs = [_]Register{ .rcx, .rdx, .r8, .r9 };
    pub const c_abi_x87_param_regs = x87_regs[0..0];
    pub const c_abi_sse_param_regs = sse_avx_regs[0..4];
    pub const c_abi_int_return_regs = [_]Register{ .rax, .rdx, .rcx };
    pub const c_abi_x87_return_regs = x87_regs[0..1];
    pub const c_abi_sse_return_regs = sse_avx_regs[0..4];
};

pub fn getCalleePreservedRegs(cc: std.lang.CallingConvention.Tag) []const Register {
    return switch (cc) {
        .auto => zigcc.callee_preserved_regs,
        .x86_64_sysv => &SysV.callee_preserved_regs,
        .x86_64_win => &Win64.callee_preserved_regs,
        else => unreachable,
    };
}

pub fn getCallerPreservedRegs(cc: std.lang.CallingConvention.Tag) []const Register {
    return switch (cc) {
        .auto => zigcc.caller_preserved_regs,
        .x86_64_sysv => &SysV.caller_preserved_regs,
        .x86_64_win => &Win64.caller_preserved_regs,
        else => unreachable,
    };
}

pub fn getCAbiIntParamRegs(cc: std.lang.CallingConvention.Tag) []const Register {
    return switch (cc) {
        .auto => zigcc.int_param_regs,
        .x86_64_sysv => &SysV.c_abi_int_param_regs,
        .x86_64_win => &Win64.c_abi_int_param_regs,
        else => unreachable,
    };
}

pub fn getCAbiX87ParamRegs(cc: std.lang.CallingConvention.Tag) []const Register {
    return switch (cc) {
        .auto => zigcc.x87_param_regs,
        .x86_64_sysv => SysV.c_abi_x87_param_regs,
        .x86_64_win => Win64.c_abi_x87_param_regs,
        else => unreachable,
    };
}

pub fn getCAbiSseParamRegs(cc: std.lang.CallingConvention.Tag, target: *const std.Target) []const Register {
    return switch (cc) {
        .auto => switch (target.cpu.arch) {
            else => unreachable,
            .x86 => zigcc.sse_param_regs[0 .. zigcc.sse_param_regs.len / 2],
            .x86_64 => zigcc.sse_param_regs,
        },
        .x86_64_sysv => SysV.c_abi_sse_param_regs,
        .x86_64_win => Win64.c_abi_sse_param_regs,
        else => unreachable,
    };
}

pub fn getCAbiIntReturnRegs(cc: std.lang.CallingConvention.Tag) []const Register {
    return switch (cc) {
        .auto => zigcc.int_return_regs,
        .x86_64_sysv => &SysV.c_abi_int_return_regs,
        .x86_64_win => &Win64.c_abi_int_return_regs,
        else => unreachable,
    };
}

pub fn getCAbiX87ReturnRegs(cc: std.lang.CallingConvention.Tag) []const Register {
    return switch (cc) {
        .auto => zigcc.x87_return_regs,
        .x86_64_sysv => SysV.c_abi_x87_return_regs,
        .x86_64_win => Win64.c_abi_x87_return_regs,
        else => unreachable,
    };
}

pub fn getCAbiSseReturnRegs(cc: std.lang.CallingConvention.Tag) []const Register {
    return switch (cc) {
        .auto => zigcc.sse_return_regs,
        .x86_64_sysv => SysV.c_abi_sse_return_regs,
        .x86_64_win => Win64.c_abi_sse_return_regs,
        else => unreachable,
    };
}

pub fn getCAbiLinkerScratchReg(cc: std.lang.CallingConvention.Tag) Register {
    return switch (cc) {
        .auto => zigcc.int_return_regs[zigcc.int_return_regs.len - 1],
        .x86_64_sysv => SysV.c_abi_int_return_regs[0],
        .x86_64_win => Win64.c_abi_int_return_regs[0],
        else => unreachable,
    };
}

const gp_regs = [_]Register{
    .rax, .rdx, .rbx, .rcx, .rsi, .rdi, .r8, .r9, .r10, .r11, .r12, .r13, .r14, .r15,
};
const x87_regs = [_]Register{
    .st0, .st1, .st2, .st3, .st4, .st5, .st6, .st7,
};
const sse_avx_regs = [_]Register{
    .ymm0, .ymm1, .ymm2,  .ymm3,  .ymm4,  .ymm5,  .ymm6,  .ymm7,
    .ymm8, .ymm9, .ymm10, .ymm11, .ymm12, .ymm13, .ymm14, .ymm15,
};
const allocatable_regs = gp_regs ++ x87_regs[0 .. x87_regs.len - 1] ++ sse_avx_regs;
pub const RegisterManager = RegisterManagerFn(@import("CodeGen.zig"), Register, allocatable_regs);

// Register classes
const RegisterBitSet = RegisterManager.RegisterBitSet;
pub const RegisterClass = struct {
    pub const gp: RegisterBitSet = blk: {
        var set = RegisterBitSet.empty;
        for (allocatable_regs, 0..) |reg, index| if (reg.isClass(.general_purpose)) set.set(index);
        break :blk set;
    };
    pub const gphi: RegisterBitSet = blk: {
        var set = RegisterBitSet.empty;
        for (allocatable_regs, 0..) |reg, index| if (reg.isClass(.gphi)) set.set(index);
        break :blk set;
    };
    pub const x87: RegisterBitSet = blk: {
        var set = RegisterBitSet.empty;
        for (allocatable_regs, 0..) |reg, index| if (reg.isClass(.x87)) set.set(index);
        break :blk set;
    };
    pub const sse: RegisterBitSet = blk: {
        var set = RegisterBitSet.empty;
        for (allocatable_regs, 0..) |reg, index| if (reg.isClass(.sse)) set.set(index);
        break :blk set;
    };
};

const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

const InternPool = @import("../../InternPool.zig");
const Register = @import("bits.zig").Register;
const RegisterManagerFn = @import("../../register_manager.zig").RegisterManager;
const Type = @import("../../Type.zig");
const Value = @import("../../Value.zig");
const Zcu = @import("../../Zcu.zig");

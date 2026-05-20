//! This namespace is the default one used by the Zig compiler to emit various
//! kinds of safety panics, due to the logic in `std.builtin.panic`.
//!
//! Since Zig does not have interfaces, this file serves as an example template
//! for users to provide their own alternative panic handling.
//!
//! As an alternative, see `std.debug.FullPanic`.

const std = @import("../std.zig");

/// Prints the message to stderr without a newline and then traps.
///
/// Explicit calls to `@panic` lower to calling this function.
pub fn call(msg: []const u8, ra: ?usize) noreturn {
    @branchHint(.cold);
    _ = ra;
    const stderr_writer = &std.debug.lockStderr(&.{}).file_writer.interface;
    stderr_writer.writeAll(msg) catch {};
    @trap();
}

pub fn sentinelMismatch(expected: anytype, found: @TypeOf(expected)) noreturn {
    @branchHint(.cold);
    _ = found;
    call("sentinel mismatch", null);
}

pub fn unwrapError(err: anyerror) noreturn {
    @branchHint(.cold);
    _ = &err;
    call("attempt to unwrap error", null);
}

pub fn outOfBounds(index: usize, len: usize) noreturn {
    @branchHint(.cold);
    _ = index;
    _ = len;
    call("index out of bounds", null);
}

pub fn startGreaterThanEnd(start: usize, end: usize) noreturn {
    @branchHint(.cold);
    _ = start;
    _ = end;
    call("start index is larger than end index", null);
}

pub fn inactiveUnionField(active: anytype, accessed: @TypeOf(active)) noreturn {
    @branchHint(.cold);
    _ = accessed;
    call("access of inactive union field", null);
}

pub fn sliceCastLenRemainder(src_len: usize) noreturn {
    @branchHint(.cold);
    _ = src_len;
    call("slice length does not divide exactly into destination elements", null);
}

pub fn reachedUnreachable() noreturn {
    @branchHint(.cold);
    call("reached unreachable code", null);
}

pub fn unwrapNull() noreturn {
    @branchHint(.cold);
    call("attempt to use null value", null);
}

pub fn castToNull() noreturn {
    @branchHint(.cold);
    call("cast causes pointer to be null", null);
}

pub fn incorrectAlignment() noreturn {
    @branchHint(.cold);
    call("incorrect alignment", null);
}

pub fn invalidErrorCode() noreturn {
    @branchHint(.cold);
    call("invalid error code", null);
}

pub fn unexpectedErrorCode(err: anyerror) noreturn {
    @branchHint(.cold);
    _ = err;
    call("unexpected error code", null);
}

pub fn integerOutOfBounds() noreturn {
    @branchHint(.cold);
    call("integer does not fit in destination type", null);
}

pub fn integerOverflow() noreturn {
    @branchHint(.cold);
    call("integer overflow", null);
}

pub fn shlOverflow() noreturn {
    @branchHint(.cold);
    call("left shift overflowed bits", null);
}

pub fn shrOverflow() noreturn {
    @branchHint(.cold);
    call("right shift overflowed bits", null);
}

pub fn divideByZero() noreturn {
    @branchHint(.cold);
    call("division by zero", null);
}

pub fn exactDivisionRemainder() noreturn {
    @branchHint(.cold);
    call("exact division produced remainder", null);
}

pub fn integerPartOutOfBounds() noreturn {
    @branchHint(.cold);
    call("integer part of floating point value out of bounds", null);
}

pub fn corruptSwitch() noreturn {
    @branchHint(.cold);
    call("switch on corrupt value", null);
}

pub fn shiftRhsTooBig() noreturn {
    @branchHint(.cold);
    call("shift amount is greater than the type size", null);
}

pub fn invalidEnumValue() noreturn {
    @branchHint(.cold);
    call("invalid enum value", null);
}

pub fn forLenMismatch() noreturn {
    @branchHint(.cold);
    call("for loop over objects with non-equal lengths", null);
}

pub fn copyLenMismatch() noreturn {
    @branchHint(.cold);
    call("source and destination have non-equal lengths", null);
}

pub fn memcpyAlias() noreturn {
    @branchHint(.cold);
    call("@memcpy arguments alias", null);
}

pub fn noreturnReturned() noreturn {
    @branchHint(.cold);
    call("'noreturn' function returned", null);
}

pub fn loadUninstantiableType() noreturn {
    call("attempt to load uninstantiable type", null);
}

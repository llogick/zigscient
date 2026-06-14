const RangeSet = @This();

ranges: std.MultiArrayList(Range),

pub const Range = struct {
    first: Value,
    last: Value,
    src: LazySrcLoc,
};

pub const empty: RangeSet = .{ .ranges = .empty };

pub fn deinit(self: *RangeSet, allocator: Allocator) void {
    self.ranges.deinit(allocator);
    self.* = undefined;
}

pub fn ensureUnusedCapacity(self: *RangeSet, allocator: Allocator, additional_count: usize) Allocator.Error!void {
    return self.ranges.ensureUnusedCapacity(allocator, additional_count);
}

pub fn addAssumeCapacity(set: *RangeSet, new: Range, ty: Type, zcu: *Zcu) ?LazySrcLoc {
    assert(new.first.typeOf(zcu).eql(ty));
    assert(new.last.typeOf(zcu).eql(ty));
    assert(new.first.compareScalar(.lte, new.last, ty, zcu));

    const idx = std.sort.lowerBound(Value, set.ranges.items(.last), @as(SearchCtx, .{
        .val = new.first,
        .zcu = zcu,
    }), compare);

    if (idx != set.ranges.len and // `new.first` is *not* greater than all `old.last`
        new.last.compareScalar(.gte, set.ranges.items(.first)[idx], ty, zcu))
    {
        return set.ranges.items(.src)[idx]; // `new` overlaps with existing range.
    }
    set.ranges.insertAssumeCapacity(idx, new);
    return null;
}

pub fn add(set: *RangeSet, allocator: Allocator, new: Range, ty: Type, zcu: *Zcu) Allocator.Error!?LazySrcLoc {
    try set.ensureUnusedCapacity(allocator, 1);
    return set.addAssumeCapacity(new, ty, zcu);
}

pub fn spans(
    set: *RangeSet,
    allocator: Allocator,
    first: Value,
    last: Value,
    ty: Type,
    zcu: *Zcu,
) Allocator.Error!bool {
    assert(first.typeOf(zcu).eql(ty));
    assert(last.typeOf(zcu).eql(ty));
    if (set.ranges.len == 0) return false;

    assert(std.sort.isSorted(Value, set.ranges.items(.first), @as(SortCtx, .{ .ty = ty, .zcu = zcu }), lessThan));
    assert(std.sort.isSorted(Value, set.ranges.items(.last), @as(SortCtx, .{ .ty = ty, .zcu = zcu }), lessThan));

    if (!set.ranges.items(.first)[0].eql(first, ty, zcu) or
        !set.ranges.items(.last)[set.ranges.len - 1].eql(last, ty, zcu))
    {
        return false;
    }

    const limbs = try allocator.alloc(
        math.big.Limb,
        math.big.int.calcTwosCompLimbCount(ty.intInfo(zcu).bits),
    );
    defer allocator.free(limbs);
    var counter: math.big.int.Mutable = .init(limbs, 0);

    var space: InternPool.Key.Int.Storage.BigIntSpace = undefined;

    // look for gaps
    for (
        set.ranges.items(.first)[1..],
        set.ranges.items(.last)[0 .. set.ranges.len - 1],
    ) |cur_first, prev_last| {
        // prev_last + 1 == cur_first
        counter.copy(prev_last.toBigInt(&space, zcu));
        counter.addScalar(counter.toConst(), 1);

        const cur_start_int = cur_first.toBigInt(&space, zcu);
        if (!cur_start_int.eql(counter.toConst())) {
            return false;
        }
    }

    return true;
}

const SearchCtx = struct {
    val: Value,
    zcu: *const Zcu,
};
fn compare(ctx: SearchCtx, other: Value) math.Order {
    return ctx.val.order(other, ctx.zcu);
}

const SortCtx = struct {
    ty: Type,
    zcu: *Zcu,
};
fn lessThan(ctx: SortCtx, a: Value, b: Value) bool {
    return a.compareScalar(.lt, b, ctx.ty, ctx.zcu);
}

const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const InternPool = @import("InternPool.zig");
const Type = @import("Type.zig");
const Value = @import("Value.zig");
const Zcu = @import("Zcu.zig");
const LazySrcLoc = Zcu.LazySrcLoc;

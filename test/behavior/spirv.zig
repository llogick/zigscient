const std = @import("std");
const expect = std.testing.expect;

const Sampler = @SpirvType(.sampler);
const Image = @SpirvType(.{ .image = .{
    .usage = .{ .sampled = u32 },
    .format = .unknown,
    .dim = .@"2d",
    .depth = .unknown,
    .arrayed = false,
    .multisampled = false,
    .access = .unknown,
} });
const SampledImage = @SpirvType(.{ .sampled_image = Image });
const StorageImage = @SpirvType(.{ .image = .{
    .usage = .{ .storage = u32 },
    .format = .unknown,
    .dim = .@"2d",
    .depth = .unknown,
    .arrayed = false,
    .multisampled = false,
    .access = .unknown,
} });
const RuntimeArray = @SpirvType(.{ .runtime_array = u32 });

const RuntimeArrayBuf = extern struct { e: RuntimeArray };

const sampler = @extern(*addrspace(.constant) const Sampler, .{
    .name = "sampler",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 0 } },
});
const sampled_image = @extern(*addrspace(.constant) const SampledImage, .{
    .name = "sampled_image",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 1 } },
});
const storage_image = @extern(*addrspace(.constant) const StorageImage, .{
    .name = "storage_image",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 2 } },
});
const runtime_array = @extern(*addrspace(.storage_buffer) const RuntimeArrayBuf, .{
    .name = "runtime_array",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 3 } },
});

test "@SpirvType" {
    _ = sampler;
    _ = sampled_image;
    _ = storage_image;
    _ = runtime_array;
}

test "@SpirvType equality" {
    try expect(@SpirvType(.sampler) == Sampler);
    try expect(@SpirvType(.{ .runtime_array = u32 }) == RuntimeArray);
    try expect(@SpirvType(.{ .sampled_image = Image }) == SampledImage);
    try expect(@SpirvType(.{ .image = .{
        .usage = .{ .sampled = u32 },
        .format = .unknown,
        .dim = .@"2d",
        .depth = .unknown,
        .arrayed = false,
        .multisampled = false,
        .access = .unknown,
    } }) == Image);
    try expect(@SpirvType(.{ .image = .{
        .usage = .{ .sampled = u32 },
        .format = .unknown,
        .dim = .@"3d",
        .depth = .unknown,
        .arrayed = false,
        .multisampled = false,
        .access = .unknown,
    } }) != Image);
    try expect(@SpirvType(.{ .runtime_array = u32 }) != @SpirvType(.{ .runtime_array = u8 }));
    try expect(@SpirvType(.sampler) != @SpirvType(.{ .runtime_array = u32 }));
}

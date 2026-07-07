const std = @import("std");

const RuntimeArray = @SpirvType(.{ .runtime_array = @Vector(4, f32) });
const Buffer = extern struct {
    data: RuntimeArray,
};

const output = @extern(*addrspace(.storage_buffer) Buffer, .{
    .name = "output",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 0 } },
});

const num_segments = 20;

export fn main() callconv(.{ .spirv_kernel = .{ .x = 1, .y = 1, .z = 1 } }) void {
    const val = std.spirv.global_invocation_id[0];
    if (val > num_segments) return;
    var val_f: f32 = @floatFromInt(val);
    val_f /= num_segments;
    output.data[val] = .{ val_f, val_f, 0, 1 };
}

// compile
// output_mode=Obj
// backend=auto
// target=spirv32-opengl
// emit_bin=true

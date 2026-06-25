pub const Image = @SpirvType(.{ .image = .{
    .usage = .{ .sampled = f32 },
    .format = .unknown,
    .dim = .@"2d",
    .depth = .not_depth,
    .arrayed = false,
    .multisampled = false,
    .access = .unknown,
} });
pub const SampledImage = @SpirvType(.{ .sampled_image = Image });

const image_in = @extern(*addrspace(.constant) const SampledImage, .{
    .name = "image_in",
    .decoration = .{ .descriptor = .{ .set = 2, .binding = 0 } },
});
const uv_in = @extern(*addrspace(.input) @Vector(2, f32), .{ .name = "uv", .decoration = .{ .location = 0 } });
const color_out = @extern(*addrspace(.output) @Vector(4, f32), .{ .name = "color", .decoration = .{ .location = 0 } });

export fn main() callconv(.{ .spirv_fragment = .{} }) void {
    color_out.* = imageSample(image_in, uv_in.*);
}

fn imageSample(
    sampled_image: *addrspace(.constant) const SampledImage,
    uv: @Vector(2, f32),
) @Vector(4, f32) {
    return asm volatile (
        \\%loaded_sampler = OpLoad %SampledImage %sampled_image
        \\%ret            = OpImageSampleImplicitLod %Result %loaded_sampler %uv
        : [ret] "" (-> @Vector(4, f32)),
        : [SampledImage] "t" (SampledImage),
          [sampled_image] "" (sampled_image),
          [Result] "t" (@Vector(4, f32)),
          [uv] "" (uv),
    );
}

// compile
// output_mode=Exe
// backend=selfhosted
// target=spirv32-vulkan
// emit_bin=true

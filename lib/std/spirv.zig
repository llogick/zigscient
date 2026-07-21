const builtin = @import("builtin");
const std = @import("std.zig");

pub const position_in = @extern(*addrspace(.input) @Vector(4, f32), .{ .name = "position" });
pub const position_out = @extern(*addrspace(.output) @Vector(4, f32), .{ .name = "position" });
pub const point_size_in = @extern(*addrspace(.input) f32, .{ .name = "point_size" });
pub const point_size_out = @extern(*addrspace(.output) f32, .{ .name = "point_size" });
pub extern const invocation_id: u32 addrspace(.input);
pub extern const frag_coord: @Vector(4, f32) addrspace(.input);
pub extern const point_coord: @Vector(2, f32) addrspace(.input);
// TODO: direct/indirect values
// pub extern const front_facing: bool addrspace(.input);
// TODO: runtime array
// pub extern const sample_mask;
pub extern var frag_depth: f32 addrspace(.output);
pub extern const num_workgroups: @Vector(3, u32) addrspace(.input);
pub extern const workgroup_size: @Vector(3, u32) addrspace(.input);
pub extern const workgroup_id: @Vector(3, u32) addrspace(.input);
pub extern const local_invocation_id: @Vector(3, u32) addrspace(.input);
pub extern const global_invocation_id: @Vector(3, u32) addrspace(.input);
pub extern const vertex_index: u32 addrspace(.input);
pub extern const instance_index: u32 addrspace(.input);

pub const Scope = enum(u32) {
    cross_device = 0,
    device = 1,
    workgroup = 2,
    subgroup = 3,
    invocation = 4,
    queue_family = 5,
    shader_call_khr = 6,
};

pub const MemorySemantics = packed struct(u32) {
    _reserved_bit_0: bool = false,
    acquire: bool = false,
    release: bool = false,
    acquire_release: bool = false,
    sequentially_consistent: bool = false,
    _reserved_bit_5: bool = false,
    uniform_memory: bool = false,
    subgroup_memory: bool = false,
    workgroup_memory: bool = false,
    cross_workgroup_memory: bool = false,
    atomic_counter_memory: bool = false,
    image_memory: bool = false,
    output_memory: bool = false,
    make_available: bool = false,
    make_visible: bool = false,
    @"volatile": bool = false,
    _reserved: u16 = 0,

    pub const none: MemorySemantics = .{};
};

pub fn controlBarrier(
    comptime execution: Scope,
    comptime memory: Scope,
    comptime semantics: MemorySemantics,
) void {
    asm volatile (
        \\OpControlBarrier %exec %mem %sem
        :
        : [exec] "" (@as(u32, @backingInt(execution))),
          [mem] "" (@as(u32, @backingInt(memory))),
          [sem] "" (@as(u32, @bitCast(semantics))),
    );
}

pub fn memoryBarrier(comptime memory: Scope, comptime semantics: MemorySemantics) void {
    asm volatile (
        \\OpMemoryBarrier %mem %sem
        :
        : [mem] "" (@as(u32, @backingInt(memory))),
          [sem] "" (@as(u32, @bitCast(semantics))),
    );
}

pub fn workgroupBarrier() void {
    controlBarrier(
        .workgroup,
        .workgroup,
        .{ .acquire_release = true, .workgroup_memory = true },
    );
}

pub fn specConst(T: type, comptime default_value: T, comptime spec_id: u32) T {
    switch (@typeInfo(T)) {
        .bool => {
            const op = if (default_value) "OpSpecConstantTrue" else "OpSpecConstantFalse";
            return asm ("%ret = " ++ op ++ " %ty\n" ++
                    "OpDecorate %ret SpecId $spec_id"
                : [ret] "" (-> T),
                : [ty] "t" (T),
                  [spec_id] "c" (spec_id),
            );
        },
        .int, .float => return asm (
            \\%ret = OpSpecConstant %ty $default_value
            \\       OpDecorate %ret SpecId $spec_id
            : [ret] "" (-> T),
            : [ty] "t" (T),
              [default_value] "c" (default_value),
              [spec_id] "c" (spec_id),
        ),
        .vector => return asm (
            \\%ret = OpSpecConstantComposite %ty %default_value %spec_id
            : [ret] "" (-> T),
            : [ty] "t" (T),
              [default_value] "c" (default_value),
              [spec_id] "c" (spec_id),
        ),
        else => @compileError("Invalid spec-constant type"),
    }
}

/// Get the type that specifies a coordinate for a SPIR-V image or sampled image.
fn ImageCoordinate(Image: type, Element: type) type {
    const image_info = switch (@typeInfo(Image)) {
        .spirv => |spirv| switch (spirv) {
            .sampled_image => |sampled_image| @typeInfo(sampled_image).spirv.image,
            .image => |image| image,
            else => @compileError("Expected SPIR-V image or sampled image type, found '" ++ @typeName(Image) ++ "'"),
        },
        else => @compileError("Expected SPIR-V image or sampled image type, found '" ++ @typeName(Image) ++ "'"),
    };
    const dim = switch (image_info.dim) {
        .@"1d" => 1 + @as(u8, @intFromBool(image_info.arrayed)),
        .@"2d" => 2 + @as(u8, @intFromBool(image_info.arrayed)),
        .@"3d", .cube => 3 + @as(u8, @intFromBool(image_info.arrayed)),
    };
    if (dim == 1) return Element else return @Vector(dim, Element);
}

/// The type of the components that result from sampling or reading from the given SPIR-V image or sampled image type.
fn ImageSampledType(Image: type) type {
    const image_info = switch (@typeInfo(Image)) {
        .spirv => |spirv| switch (spirv) {
            .sampled_image => |sampled_image| @typeInfo(sampled_image).spirv.image,
            .image => |image| image,
            else => @compileError("Expected SPIR-V image or sampled image type, found '" ++ @typeName(Image) ++ "'"),
        },
        else => @compileError("Expected SPIR-V image or sampled image type, found '" ++ @typeName(Image) ++ "'"),
    };
    return switch (image_info.usage) {
        inline else => |usage| usage,
    };
}

/// The type of `sampled_image` must be a pointer to a SPIR-V sampled image.
pub fn imageSampleImplicitLod(
    sampled_image: anytype,
    coordinate: ImageCoordinate(std.meta.Child(@TypeOf(sampled_image)), f32),
) @Vector(4, ImageSampledType(std.meta.Child(@TypeOf(sampled_image)))) {
    const SampledImage = switch (@typeInfo(@TypeOf(sampled_image))) {
        .pointer => |pointer| pointer.child,
        else => @compileError("Expected a pointer to SPIR-V sampled image type, found '" ++ @typeName(@TypeOf(sampled_image)) ++ "'"),
    };
    const Result = @Vector(4, ImageSampledType(SampledImage));

    const image_info = switch (@typeInfo(SampledImage)) {
        .spirv => |spirv| switch (spirv) {
            .sampled_image => |sampled_image_info| @typeInfo(sampled_image_info).spirv.image,
            else => @compileError("Expected SPIR-V sampled image type, found '" ++ @typeName(SampledImage) ++ "'"),
        },
        else => @compileError("Expected SPIR-V sampled image type, found '" ++ @typeName(SampledImage) ++ "'"),
    };

    if (image_info.multisampled)
        @compileError("Can not implicitly sample a sampled image that was multisampled");

    // TOOD: If buffer dim is added, throw a compile error if the dimension is a buffer.

    return asm volatile (
        \\%loaded_sampler = OpLoad %SampledImage %sampled_image
        \\%ret            = OpImageSampleImplicitLod %Result %loaded_sampler %coordinate
        : [ret] "" (-> Result),
        : [SampledImage] "t" (SampledImage),
          [sampled_image] "" (sampled_image),
          [Result] "t" (Result),
          [coordinate] "" (coordinate),
    );
}

/// Query the dimensions of `image`, with no level of detail.
pub fn imageQuerySize(
    image: anytype,
) ImageCoordinate(std.meta.Child(@TypeOf(image)), u32) {
    const Image = switch (@typeInfo(@TypeOf(image))) {
        .pointer => |pointer| pointer.child,
        else => @compileError("Expected a pointer to SPIR-V image type, found '" ++ @typeName(@TypeOf(image)) ++ "'"),
    };

    const image_info = switch (@typeInfo(Image)) {
        .spirv => |spirv| switch (spirv) {
            .image => |info| info,
            else => @compileError("Expected SPIR-V image type, found '" ++ @typeName(Image) ++ "'"),
        },
        else => @compileError("Expected SPIR-V image type, found '" ++ @typeName(Image) ++ "'"),
    };

    // TODO: Remove this check if dimension is not 1d, 2d, 3d, or cube (in case buffer is added).
    if (!image_info.multisampled and image_info.usage != .unknown and image_info.usage != .storage)
        @compileError("SPIR-V image must be either be multisampled or have an unknown or storage usage");

    const Result = ImageCoordinate(std.meta.Child(@TypeOf(image)), u32);

    return asm volatile (
        \\%loaded_image = OpLoad %Image %image
        \\%ret          = OpImageQuerySize %Result %loaded_image
        : [ret] "" (-> Result),
        : [Image] "t" (Image),
          [image] "" (image),
          [Result] "t" (Result),
    );
}

/// Write a texel to an image without a sampler.
/// The type of `image` must be a pointer to a SPIR-V image.
pub fn imageWrite(
    image: anytype,
    T: type,
    coordinate: ImageCoordinate(std.meta.Child(@TypeOf(image)), T),
    texel: @Vector(4, ImageSampledType(std.meta.Child(@TypeOf(image)))),
) void {
    switch (T) {
        u32, i32 => {},
        f32 => if (builtin.target.os.tag != .opencl) {
            @compileError("Floating point image coordinates only supported by OpenCL");
        },
        else => @compileError("Expected one of u32, i32 and f32 types. Found '" ++ @typeName(T) ++ "'"),
    }

    const Image = switch (@typeInfo(@TypeOf(image))) {
        .pointer => |pointer| pointer.child,
        else => @compileError("Expected a pointer to SPIR-V image type, found '" ++ @typeName(@TypeOf(image)) ++ "'"),
    };

    const image_info = switch (@typeInfo(Image)) {
        .spirv => |spirv| switch (spirv) {
            .image => |info| info,
            else => @compileError("Expected SPIR-V image type, found '" ++ @typeName(Image) ++ "'"),
        },
        else => @compileError("Expected SPIR-V image type, found '" ++ @typeName(Image) ++ "'"),
    };

    switch (image_info.usage) {
        .unknown, .storage => {},
        else => @compileError("SPIR-V image must have unknown or storage usage"),
    }

    // TODO: If SubpassData dim is added, throw a compiler error if the image is arrayed and has the SubpassData dim.

    return asm volatile (
        \\%loaded_image = OpLoad %Image %image
        \\                OpImageWrite %loaded_image %coordinate %texel
        :
        : [Image] "t" (Image),
          [image] "" (image),
          [coordinate] "" (coordinate),
          [texel] "" (texel),
    );
}

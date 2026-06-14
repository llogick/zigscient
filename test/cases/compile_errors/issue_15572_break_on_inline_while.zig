const std = @import("std");

pub const DwarfSection = enum {
    eh_frame,
    eh_frame_hdr,
};

pub fn main() void {
    const section = inline for (@typeInfo(DwarfSection).@"enum".field_names) |section_name| {
        if (std.mem.eql(u8, section_name, "eh_frame")) break section_name;
    };

    _ = section;
}

// error
// target=x86_64-linux
//
// :9:28: error: incompatible types: '[:0]const u8' and 'void'

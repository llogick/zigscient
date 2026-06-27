const std = @import("std");

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Test it");
    b.default_step = test_step;

    const config_header = b.addConfigHeader(
        .{ .style = .{ .autoconf_undef = b.path("autoconf_undef/config.h.in") } },
        .{
            .SOME_NO = null,
            .SOME_TRUE = true,
            .SOME_FALSE = false,
            .SOME_ZERO = 0,
            .SOME_ONE = 1,
            .SOME_TEN = 10,
            .SOME_ENUM = @as(enum { foo, bar }, .foo),
            .SOME_ENUM_LITERAL = .@"test",
            .SOME_STRING = "test",
            .PREFIX_SPACE = null,
            .PREFIX_TAB = null,
            .POSTFIX_SPACE = null,
            .POSTFIX_TAB = null,
            .SOME_UNDERSCORED = true,
        },
    );
    const check_config_header = b.addCheckFile(config_header.getOutputFile(), .{
        .expected_exact = @embedFile("autoconf_undef/config.h"),
    });
    test_step.dependOn(&check_config_header.step);

    const config_header_autoconf_at = b.addConfigHeader(
        .{ .style = .{ .autoconf_at = b.path("autoconf_at/autoconf_at.h.in") } },
        .{
            .undefined = null,
            .defined = {},
            .boolean_true = true,
            .boolean_false = false,
            .integer = 42,
            .string = "text",
            .string_at = "@string@",
            .underscored_var = "value",
            .at_sign = "@",
        },
    );
    const check_config_header_autoconf_at = b.addCheckFile(config_header_autoconf_at.getOutputFile(), .{
        .expected_exact = @embedFile("autoconf_at/autoconf_at.h"),
    });
    test_step.dependOn(&check_config_header_autoconf_at.step);

    const config_header_blank = b.addConfigHeader(
        .{
            .style = .blank,
            .include_path = "config.h",
        },
        .{
            .UNDEFINED = null,
            .DEFINED = {},
            .TRUE = true,
            .FALSE = false,
            .ZERO = 0,
            .ONE = 1,
            .TEN = 10,
            .IDENT = @as(enum { identifier }, .identifier),
            .STRING = "test",
        },
    );
    const check_config_header_blank = b.addCheckFile(config_header_blank.getOutputFile(), .{
        .expected_exact = @embedFile("blank/config.h"),
    });
    test_step.dependOn(&check_config_header_blank.step);

    const config_header_nasm = b.addConfigHeader(
        .{
            .style = .nasm,
            .include_path = "config.asm",
        },
        .{
            .UNDEFINED = null,
            .DEFINED = {},
            .TRUE = true,
            .FALSE = false,
            .ZERO = 0,
            .ONE = 1,
            .TEN = 10,
            .IDENT = @as(enum { identifier }, .identifier),
            .STRING = "test",
        },
    );
    const check_config_header_nasm = b.addCheckFile(config_header_nasm.getOutputFile(), .{
        .expected_exact = @embedFile("nasm/config.asm"),
    });
    test_step.dependOn(&check_config_header_nasm.step);

    addCmakeChecks(b, test_step);
}

fn addCmakeChecks(b: *std.Build, test_step: *std.Build.Step) void {
    const config_header = b.addConfigHeader(
        .{ .style = .{ .cmake = b.path("cmake/config.h.in") } },
        .{
            .NOVAL = null,
            .TRUEVAL = true,
            .FALSEVAL = false,
            .ZEROVAL = 0,
            .ONEVAL = 1,
            .TENVAL = 10,
            .STRINGVAL = "test",
            .BOOLNOVAL = {},
            .BOOLTRUEVAL = true,
            .BOOLFALSEVAL = false,
            .BOOLZEROVAL = 0,
            .BOOLONEVAL = 1,
            .BOOLTENVAL = 10,
            .BOOLSTRINGVAL = "test",
        },
    );
    const check_config_header = b.addCheckFile(config_header.getOutputFile(), .{
        .expected_exact = @embedFile("cmake/config.h"),
    });
    test_step.dependOn(&check_config_header.step);

    const pwd_sh = b.addConfigHeader(
        .{ .style = .{ .cmake = b.path("cmake/pwd.sh.in") } },
        .{ .DIR = "${PWD}" },
    );
    const check_pwd_sh = b.addCheckFile(pwd_sh.getOutputFile(), .{
        .expected_exact = @embedFile("cmake/pwd.sh"),
    });
    test_step.dependOn(&check_pwd_sh.step);

    const config_header_edge_cases = b.addConfigHeader(
        .{ .style = .{ .cmake = b.path("cmake/edge_cases.h.in") } },
        .{
            .DOLLAR = "$",
            .UNDERSCORE = "_",
            .STRING = "text",
            .STRING_PROXY = "STRING",
            .STRING_AT = "@STRING@",
            .STRING_CURLY = "{STRING}",
            .STRING_VAR = "${STRING}",
            .NEST_UNDERSCORE_PROXY = "UNDERSCORE",
            .NEST_PROXY = "NEST_UNDERSCORE_PROXY",
        },
    );
    const check_config_header_edge_cases = b.addCheckFile(config_header_edge_cases.getOutputFile(), .{
        .expected_exact = @embedFile("cmake/edge_cases.h"),
    });
    test_step.dependOn(&check_config_header_edge_cases.step);

    const config_header_cmakedefine_edge_cases = b.addConfigHeader(
        .{
            .style = .{ .cmake = b.path("cmake/cmakedefine_edge_cases.h.in") },
            .include_path = "cmakedefine_edge_cases_renamed.h",
        },
        .{
            .MULTI_WORD = true,
            .MULTI_WORD_FALSE = false,
            .NO_VALUE = true,
            .NO_VALUE_FALSE = false,
            .WITH_UNDERSCORE_TRUE = true,
            .WITH_UNDERSCORE_FALSE = false,
            ._LEADING = true,
            .TRAILING_ = true,
            ._UNDER_01 = true,
            .UNDER_01_ = true,
            .SUBST_VAL = true,
            .SUBST_VAL_FALSE = false,
            .STRING = "text",
            .VAR_NAME = "ACTUAL_VAR",
            .ACTUAL_VAR = true,
            .AT_SIGN = "@",
            .DOLLAR_SIGN = "$",
        },
    );
    const check_config_header_cmakedefine_edge_cases = b.addCheckFile(config_header_cmakedefine_edge_cases.getOutputFile(), .{
        .expected_exact = @embedFile("cmake/cmakedefine_edge_cases.h"),
    });
    test_step.dependOn(&check_config_header_cmakedefine_edge_cases.step);
}

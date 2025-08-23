const std = @import("std");
const build_options = @import("build_options");

/// These versions must be ordered from newest to oldest.
/// There should be no need to have a build runner for minor patches (e.g. 0.10.1)
/// The GitHub matrix in `.github\workflows\build_runner.yml` should be updated to check Zig master with the latest build runner file.
pub const BuildRunnerVersion = enum {
    @"0.15.0",
    @"0.14.0",
    @"0.13.0",
    @"0.12.0",

    pub fn selectBuildRunnerVersion(runtime_zig_version: std.SemanticVersion) ?BuildRunnerVersion {
        const runtime_zig_version_is_tagged = runtime_zig_version.build == null and runtime_zig_version.pre == null;
        var target_ver: std.SemanticVersion = if (!runtime_zig_version_is_tagged) .{
            .major = runtime_zig_version.major,
            .minor = runtime_zig_version.minor - 1,
            .patch = 0,
        } else runtime_zig_version;
        target_ver.patch = 0;

        const available_version_tags = comptime std.meta.tags(BuildRunnerVersion);
        for (available_version_tags) |tag| {
            switch (target_ver.order(std.SemanticVersion.parse(@tagName(tag)) catch unreachable)) {
                .eq => return tag,
                else => {},
            }
        }

        return null;
    }

    pub fn getBuildRunnerFile(version: BuildRunnerVersion) [:0]const u8 {
        return switch (version) {
            .@"0.15.0" => @embedFile("0.15.0.zig"),
            .@"0.14.0" => @embedFile("0.14.0.zig"),
            .@"0.13.0",
            .@"0.12.0",
            => @embedFile("legacy.zig"),
        };
    }
};

test {
    @setEvalBranchQuota(6_000);
    const expectEqual = std.testing.expectEqual;
    const parse = std.SemanticVersion.parse;

    // 0.11.0-dev < 0.11.0 < 0.12.0-dev < 0.12.0 < 0.13.0-dev < 0.13.0

    {
        const current_zig_version = @import("builtin").zig_version;
        const build_runner = BuildRunnerVersion.selectBuildRunnerVersion(current_zig_version);
        if (build_runner == null) {
            std.debug.print(
                \\Project is being tested with Zig {}.
                \\No build runner could be resolved for this Zig version!
                \\
            , .{current_zig_version});
            return error.TestUnexpectedResult;
        }
    }

    {
        try expectEqual(.@"0.12.0", BuildRunnerVersion.selectBuildRunnerVersion(
            try parse("0.12.0"), // Zig version
        ));
        try expectEqual(.@"0.12.0", BuildRunnerVersion.selectBuildRunnerVersion(
            try parse("0.12.1"), // Zig version
        ));
        try expectEqual(.@"0.12.0", BuildRunnerVersion.selectBuildRunnerVersion(
            try parse("0.13.0-dev.1+aaaaaaaaa"), // Zig version
        ));
        try expectEqual(.@"0.14.0", BuildRunnerVersion.selectBuildRunnerVersion(
            try parse("0.14.0"), // Zig version
        ));
        try expectEqual(.@"0.13.0", BuildRunnerVersion.selectBuildRunnerVersion(
            try parse("0.14.0-dev.3445+6c3cbb0c8"), // Zig version
        ));
    }
}

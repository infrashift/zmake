const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // `--release` builds ReleaseSafe: assertions stay active (ADR-0003).
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const mod = b.addModule("zmake", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // `zmake --version` prints the package version and the git commit (ADR-0025).
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", @import("build.zig.zon").version);
    build_options.addOption([]const u8, "commit", gitCommit(b));

    const exe = b.addExecutable(.{
        .name = "zmake",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zmake", .module = mod },
                .{ .name = "build_options", .module = build_options.createModule() },
            },
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    b.step("run", "Run zmake").dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run the unit tests and the mode tests");
    const mod_tests = b.addTest(.{ .root_module = mod });
    test_step.dependOn(&b.addRunArtifact(mod_tests).step);
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);
    for ([_][]const u8{ "tests/legacy_test.zig", "tests/modern_test.zig" }) |path| {
        const t = b.addTest(.{ .root_module = b.createModule(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zmake", .module = mod }},
        }) });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }

    const acceptance = b.addSystemCommand(&.{ "bash", "tests/acceptance.sh" });
    acceptance.addArtifactArg(exe);
    acceptance.has_side_effects = true;
    b.step("acceptance", "Run the end-to-end scenarios against the binary").dependOn(&acceptance.step);
}

/// The commit of the work tree: `git rev-parse HEAD`, plus `-dirty` when a
/// tracked file has a change. `unknown` when git or `.git` is not available,
/// for example in a source tarball. The build never fails here.
fn gitCommit(b: *std.Build) []const u8 {
    // The result depends on the git state, which the configure cache cannot
    // track. Run the configure phase on each `zig build`.
    b.graph.poisonCache();
    // Without this check, git finds a parent repository of an unpacked tarball.
    b.root.access(b.graph.io, ".git", .{}) catch return "unknown";
    const root = b.root.joinString(b.allocator, ".") catch @panic("OOM");
    const head = switch (b.runFallible(&.{ "git", "-C", root, "rev-parse", "HEAD" }, .{ .stderr_behavior = .ignore })) {
        .success => |out| std.mem.trim(u8, out, " \t\r\n"),
        else => return "unknown",
    };
    if (head.len != 40 and head.len != 64) return "unknown";
    for (head) |c| if (!std.ascii.isHex(c)) return "unknown";
    const status = switch (b.runFallible(&.{ "git", "-C", root, "status", "--porcelain", "--untracked-files=no" }, .{ .stderr_behavior = .ignore })) {
        .success => |out| out,
        else => return "unknown",
    };
    if (status.len == 0) return head;
    return b.fmt("{s}-dirty", .{head});
}

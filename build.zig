const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get dependencies
    const zqlite_dep = b.dependency("zqlite", .{
        .target = target,
        .optimize = optimize,
    });
    const pg_dep = b.dependency("pg", .{
        .target = target,
        .optimize = optimize,
    });
    const myzql_dep = b.dependency("myzql", .{
        .target = target,
        .optimize = optimize,
    });

    // Main library module
    const zdbc_mod = b.addModule("zdbc", .{
        .root_source_file = b.path("src/zdbc.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "zqlite", .module = zqlite_dep.module("zqlite") },
            .{ .name = "pg", .module = pg_dep.module("pg") },
            .{ .name = "myzql", .module = myzql_dep.module("myzql") },
        },
    });
    // Link SQLite C library for zqlite
    zdbc_mod.linkSystemLibrary("sqlite3", .{});

    // Unit tests module
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/zdbc.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "zqlite", .module = zqlite_dep.module("zqlite") },
            .{ .name = "pg", .module = pg_dep.module("pg") },
            .{ .name = "myzql", .module = myzql_dep.module("myzql") },
        },
    });
    test_mod.linkSystemLibrary("sqlite3", .{});

    // Unit tests
    const main_tests = b.addTest(.{
        .name = "zdbc-test",
        .root_module = test_mod,
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_main_tests.step);

    // Integration tests module
    const integration_test_mod = b.createModule(.{
        .root_source_file = b.path("src/integration_test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "zqlite", .module = zqlite_dep.module("zqlite") },
            .{ .name = "pg", .module = pg_dep.module("pg") },
            .{ .name = "myzql", .module = myzql_dep.module("myzql") },
        },
    });
    integration_test_mod.linkSystemLibrary("sqlite3", .{});

    const integration_tests = b.addTest(.{
        .name = "zdbc-integration-test",
        .root_module = integration_test_mod,
    });

    const run_integration_tests = b.addRunArtifact(integration_tests);

    const integration_test_step = b.step("integration-test", "Run integration tests");
    integration_test_step.dependOn(&run_integration_tests.step);

    // NOTE: Examples are disabled for Zig 0.16.0 due to breaking API changes.
    // They need to be updated to use the new Zig 0.16.0 std library APIs:
    // - std.heap.GeneralPurposeAllocator -> std.heap.ArenaAllocator
    // - std.process.argsAlloc -> Args.Iterator API
    // - std.fs.cwd() -> Io.Dir based API
    //
    // To re-enable examples, update examples/simple.zig and examples/log.zig
    // with the new Zig 0.16.0 APIs.
}

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const server_mod = b.addModule("Server", .{
        .root_source_file = b.path("src/server/root.zig"),
        .target = target,
    });

    const http_mod = b.addModule("http", .{
        .root_source_file = b.path("src/http/root.zig"),
        .target = target,
    });

    const kafka_mod = b.addModule("kafka", .{
        .root_source_file = b.path("src/kafka/root.zig"),
        .target = target,
    });

    const generator_mod = b.addModule("generator", .{
        .root_source_file = b.path("src/generator/root.zig"),
        .target = target,
    });

    const broker_exe = b.addExecutable(.{
        .name = "broker",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/broker.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "Server", .module = server_mod },
                .{ .name = "http", .module = http_mod },
                .{ .name = "kafka", .module = kafka_mod },
            },
        }),
    });

    const generator_exe = b.addExecutable(.{
        .name = "generator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/generator.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "generator", .module = generator_mod },
            },
        }),
    });

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(broker_exe);
    b.installArtifact(generator_exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(broker_exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // add generate subcommand
    const generate_cmd = b.addRunArtifact(generator_exe);
    generate_cmd.step.dependOn(b.getInstallStep());
    const generate_step = b.step("generate", "Run the generator");
    generate_step.dependOn(&generate_cmd.step);

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
        generate_cmd.addArgs(args);
    }

    const test_step = b.step("test", "Run tests");
    var it = b.modules.iterator();
    while (it.next()) |entry| {
        const mod_test = b.addTest(.{
            .root_module = entry.value_ptr.*,
        });
        const mod_test_run = b.addRunArtifact(mod_test);
        test_step.dependOn(&mod_test_run.step);
    }
}

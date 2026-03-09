const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "memory",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true
        }),
    });

    if (optimize != .Debug) {
        const mod = exe.root_module;
        
        mod.unwind_tables = .none;
        mod.single_threaded = true;
        mod.error_tracing = false;
        mod.omit_frame_pointer = true;
        mod.pic = true;

        exe.root_module.strip = true;
        exe.link_gc_sections = true;
        exe.link_function_sections = true;
        exe.link_data_sections = true;
        
        // LTO (Link Time Optimization)
        exe.lto = .full; 
    }

    const asm_source = exe.getEmittedAsm();
    const install_asm = b.addInstallFile(asm_source, "bin/memory.s"); 

    b.getInstallStep().dependOn(&install_asm.step);
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}

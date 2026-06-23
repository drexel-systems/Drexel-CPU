const std = @import("std");

pub fn build(b: *std.Build) void {
    // RV32IM — 32-bit RISC-V with integer multiply/divide, no compressed
    // instructions.  Matches the CS281 board's cpu configuration.
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .riscv32,
        .os_tag   = .freestanding,
        .abi      = .none,
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
        .cpu_features_add = std.Target.riscv.featureSet(&.{ .m }),
    });

    // Zig 0.15+: target and optimize move into root_module via b.createModule().
    const exe = b.addExecutable(.{
        .name        = "lab5z",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target           = target,
            .optimize         = .ReleaseSmall,
        }),
    });

    // Use our board linker script (ROM @ 0x20000000, RAM @ 0x40000000).
    exe.setLinkerScript(b.path("cs281.ld"));

    b.installArtifact(exe);
}

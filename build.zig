const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    b.setPreferredReleaseMode(std.builtin.Mode.ReleaseSafe);

    const exe = b.addExecutable("proxy-wasm-cloud-logging-trace-context", "src/main.zig");
    exe.setTarget(.{ .cpu_arch = .wasm32, .os_tag = .wasi });

    exe.addPackage(.{
        .name = "proxy-wasm-zig-sdk",
        .source = .{ .path = "libs/proxy-wasm-zig-sdk/lib/lib.zig" },
    });

    exe.setBuildMode(std.builtin.Mode.ReleaseSafe);
    exe.wasi_exec_model = .reactor;

    exe.install();
}

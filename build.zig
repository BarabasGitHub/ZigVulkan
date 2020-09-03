const std = @import("std");
const build_lib = std.build;
const Builder = build_lib.Builder;
const builtin = std.builtin;
const path = std.fs.path;

const GLFWDependencies = [_][]const u8{
    "c",
    "user32",
    "gdi32",
    "shell32",
};
const vulkan_library = "E:/Libraries/VulkanSDK/1.2.148.1/Lib/vulkan-1.lib";
const glfw_library = "E:/Libraries/glfw/build/src/Release/glfw3.lib";

fn linkVulkanGLFWAndDependencies(step: *build_lib.LibExeObjStep) void {
    step.addObjectFile(vulkan_library);
    step.addObjectFile(glfw_library);

    for (GLFWDependencies) |dep| {
        step.linkSystemLibrary(dep);
    }
}

fn doCommonStuff(lib_or_tests: anytype, build_mode: builtin.Mode) void {
    lib_or_tests.addIncludeDir(".");
    lib_or_tests.addPackagePath("ZigZag", "../ZigZag/main.zig");
    lib_or_tests.setBuildMode(build_mode);
    linkVulkanGLFWAndDependencies(lib_or_tests);
}

fn addShader(b: *Builder, in_file: []const u8, out_file: []const u8) !*build_lib.RunStep {
    const dirname = "Shaders";
    const full_in = try path.join(b.allocator, &[_][]const u8{ dirname, in_file });
    defer b.allocator.free(full_in);
    const full_out = try path.join(b.allocator, &[_][]const u8{ dirname, out_file });
    defer b.allocator.free(full_out);

    return b.addSystemCommand(&[_][]const u8{
        "glslangValidator",
        "-V100",
        "-e",
        "main",
        // "--vn",
        // "shader_data",
        "-o",
        full_out,
        full_in,
    });
}

pub fn build(b: *Builder) !void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("ZigVulkan", "main.zig");
    doCommonStuff(lib, mode);
    lib.install();

    var main_tests = b.addTest("main.zig");
    doCommonStuff(main_tests, mode);
    main_tests.step.dependOn(&(try addShader(b, "fixed_rectangle.vert.hlsl", "fixed_rectangle.vert.spr")).step);
    main_tests.step.dependOn(&(try addShader(b, "white.frag.hlsl", "white.frag.spr")).step);
    main_tests.step.dependOn(&(try addShader(b, "fixed_uv_rectangle.vert.hlsl", "fixed_uv_rectangle.vert.spr")).step);
    main_tests.step.dependOn(&(try addShader(b, "textured.frag.hlsl", "textured.frag.spr")).step);
    main_tests.step.dependOn(&(try addShader(b, "rectangle.vert.hlsl", "rectangle.vert.spr")).step);
    main_tests.step.dependOn(&(try addShader(b, "plain_colour.frag.hlsl", "plain_colour.frag.spr")).step);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}

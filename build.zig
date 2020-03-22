const std = @import("std");
const build_lib = std.build;
const Builder = build_lib.Builder;
const builtin = std.builtin;

const GLFWDependencies = [_][]const u8{
    "c",
    "user32",
    "gdi32",
    "shell32",
};
const vulkan_library = "E:/Libraries/VulkanSDK/1.1.121.2/Lib/vulkan-1.lib";
const glfw_library = "E:/Libraries/glfw/build/src/Release/glfw3.lib";

fn linkVulkanGLFWAndDependencies(step: *build_lib.LibExeObjStep) void {
    step.addObjectFile(vulkan_library);
    step.addObjectFile(glfw_library);

    for (GLFWDependencies) |dep| {
        step.linkSystemLibrary(dep);
    }
}

pub fn doCommonStuff(lib_or_tests: var, build_mode: builtin.Mode) void {
    lib_or_tests.addPackagePath("ZigZag", "../ZigZag/main.zig");
    lib_or_tests.addLibPath("C:/Program Files (x86)/Microsoft Visual Studio/2019/Community/VC/Tools/MSVC/14.25.28610/lib/x64");
    lib_or_tests.setBuildMode(build_mode);
    linkVulkanGLFWAndDependencies(lib_or_tests);
}

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("ZigVulkan", "main.zig");
    doCommonStuff(lib, mode);
    lib.install();

    var main_tests = b.addTest("main.zig");
    doCommonStuff(main_tests, mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}

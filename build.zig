const build_lib = @import("std").build;
const Builder = build_lib.Builder;

const GLFWDependencies = [_][]const u8{"c", "user32", "gdi32", "shell32"};
const vulkan_library = "E:/Libraries/VulkanSDK/1.1.121.2/Lib/vulkan-1";
const glfw_library = "E:/Libraries/glfw/build/src/Release/glfw3";

fn linkVulkanGLFWAndDependencies(step: *build_lib.LibExeObjStep) void {
    step.linkSystemLibrary(vulkan_library);
    step.linkSystemLibrary(glfw_library);

    step.linkSystemLibrary("c");
    step.linkSystemLibrary("user32");
    step.linkSystemLibrary("gdi32");
    step.linkSystemLibrary("shell32");
}

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("ZigVulkan", "main.zig");
    linkVulkanGLFWAndDependencies(lib);
    lib.setBuildMode(mode);
    lib.install();

    var main_tests = b.addTest("main.zig");
    linkVulkanGLFWAndDependencies(main_tests);
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}

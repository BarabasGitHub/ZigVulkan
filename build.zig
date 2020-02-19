const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("ZigVulkan", "vulkan_instance.zig");
    const vulkan = b.addStaticLibrary("Vulkan", "");
    lib.linkSystemLibrary("E:/Libraries/VulkanSDK/1.1.121.2/Lib/vulkan-1");
    lib.setBuildMode(mode);
    lib.install();

    var main_tests = b.addTest("vulkan_instance.zig");
    main_tests.linkSystemLibrary("E:/Libraries/VulkanSDK/1.1.121.2/Lib/vulkan-1");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}

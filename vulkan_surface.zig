const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const glfw = @import("glfw_wrapper.zig");

usingnamespace @import("vulkan_instance.zig");
usingnamespace @import("vulkan_general.zig");

pub fn createSurface(instance: Vk.Instance, window: *Vk.c.GLFWwindow) !Vk.SurfaceKHR {
    var surface: Vk.SurfaceKHR = undefined;
    try checkVulkanResult(glfw.c.glfwCreateWindowSurface(instance, window, null, @ptrCast(*Vk.c.VkSurfaceKHR, &surface)));
    return surface;
}

pub fn destroySurface(instance: Vk.Instance, surface: Vk.SurfaceKHR) void {
    Vk.c.vkDestroySurfaceKHR(instance, surface, null);
}

test "Creating a surface should succeed" {
    try glfw.init();
    defer glfw.deinit();
    const window = try glfw.createWindow(10, 10, "");
    defer glfw.destroyWindow(window);
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyTestInstance(instance);
    const surface = try createSurface(instance, window);
    destroySurface(instance, surface);
}

test "Creating a surface without the required instance extensions should fail" {
    try glfw.init();
    defer glfw.deinit();
    const window = try glfw.createWindow(10, 10, "");
    defer glfw.destroyWindow(window);
    const instance = try createTestInstance(&[_][*:0]const u8{});
    defer destroyTestInstance(instance);
    testing.expectError(error.VkErrorExtensionNotPresent, createSurface(instance, window));
}

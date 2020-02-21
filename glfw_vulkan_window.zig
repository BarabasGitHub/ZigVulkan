const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;
const testing = std.testing;

usingnamespace @import("vulkan_instance.zig");
usingnamespace @import("vulkan_general.zig");

pub const Window = struct{
    handle: *glfw.GLFWwindow,
    surface: vulkan_c.VkSurfaceKHR,

    pub fn init(width: u31, height: u31, title: [*:0]const u8, instance: vulkan_c.VkInstance) !Window {
        var window: Window = undefined;
        window.handle = try glfw.createWindow(width, height, title);
        window.surface = try createSurface(instance, window.handle);
        return window;
    }

    pub fn deinit(self: Window, instance: vulkan_c.VkInstance) void {
        destroySurface(instance, self.surface);
        glfw.destroyWindow(self.handle);
    }
};

pub fn createSurface(instance: vulkan_c.VkInstance, window: *vulkan_c.GLFWwindow) !vulkan_c.VkSurfaceKHR {
    var surface: vulkan_c.VkSurfaceKHR = undefined;
    try checkVulkanResult(glfw_c.glfwCreateWindowSurface(instance, window, null, &surface));
    return surface;
}

pub fn destroySurface(instance: vulkan_c.VkInstance, surface: vulkan_c.VkSurfaceKHR) void {
    vulkan_c.vkDestroySurfaceKHR(instance, surface, null);
}

test "Creating a surface should succeed" {
    try glfw.init();
    defer glfw.deinit();
    const window = try glfw.createWindow(10, 10, "");
    defer glfw.destroyWindow(window);
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyInstance(instance, null);
    const surface = try createSurface(instance, window);
    destroySurface(instance, surface);
}

// // this test somehow makes the next test fail... =/
// test "Creating a surface without the required instance extensions should fail" {
//     try glfw.init();
//     defer glfw.deinit();
//     const window = try glfw.createWindow(10, 10, "");
//     defer glfw.destroyWindow(window);
//     const instance = try createTestInstance(&[_][*:0]const u8{});
//     defer destroyInstance(instance, null);
//     testing.expectError(error.VkErrorExtensionNotPresent, createSurface(instance, window));
// }

test "initializing a window should succeed" {
    try glfw.init();
    defer glfw.deinit();
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyInstance(instance, null);
    const window = try Window.init(10, 10, "", instance);
    window.deinit(instance);
}

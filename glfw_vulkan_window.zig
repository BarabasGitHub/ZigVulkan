const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const glfw = @import("glfw_wrapper.zig");

usingnamespace @import("vulkan_instance.zig");
usingnamespace @import("vulkan_general.zig");

pub const Window = struct{
    handle: *glfw.GLFWwindow,
    surface: Vk.c.VkSurfaceKHR,

    pub fn init(width: u31, height: u31, title: [*:0]const u8, instance: Vk.c.VkInstance) !Window {
        var window: Window = undefined;
        window.handle = try glfw.createWindow(width, height, title);
        window.surface = try createSurface(instance, window.handle);
        return window;
    }

    pub fn deinit(self: Window, instance: Vk.c.VkInstance) void {
        destroySurface(instance, self.surface);
        glfw.destroyWindow(self.handle);
    }

    pub fn getSize(self: Window) !Vk.c.VkExtent2D {
        var width : i32 = undefined;
        var height : i32 = undefined;
        try glfw.getWindowSize(self.handle, &width, &height);
        return Vk.c.VkExtent2D{.width=@intCast(u32, width), .height=@intCast(u32, height)};
    }
};

pub fn createSurface(instance: Vk.c.VkInstance, window: *Vk.c.GLFWwindow) !Vk.c.VkSurfaceKHR {
    var surface: Vk.c.VkSurfaceKHR = undefined;
    try checkVulkanResult(glfw.c.glfwCreateWindowSurface(instance, window, null, &surface));
    return surface;
}

pub fn destroySurface(instance: Vk.c.VkInstance, surface: Vk.c.VkSurfaceKHR) void {
    Vk.c.vkDestroySurfaceKHR(instance, surface, null);
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

test "getting the size of the window should work" {
    try glfw.init();
    defer glfw.deinit();
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyInstance(instance, null);
    const width = 200;
    const height = 300;
    const window = try Window.init(width, height, "", instance);
    defer window.deinit(instance);

    testing.expectEqual(Vk.c.VkExtent2D{.width=width, .height=height}, try window.getSize());

}

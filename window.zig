const glfw = @import("glfw_wrapper.zig");
usingnamespace @import("vulkan_general.zig");

pub const Window = struct {
    handle: *glfw.GLFWwindow,

    pub fn init(width: u31, height: u31, title: [*:0]const u8) !Window {
        var window: Window = undefined;
        window.handle = try glfw.createWindow(width, height, title);
        return window;
    }

    pub fn deinit(self: Window) void {
        glfw.destroyWindow(self.handle);
    }

    pub fn getSize(self: Window) !Vk.c.VkExtent2D {
        var width: i32 = undefined;
        var height: i32 = undefined;
        try glfw.getWindowSize(self.handle, &width, &height);
        return Vk.c.VkExtent2D{ .width = @intCast(u32, width), .height = @intCast(u32, height) };
    }

    pub fn show(self: Window) !void {
        try glfw.showWindow(self.handle);
    }
};

const testing = @import("std").testing;

test "initializing a window should succeed" {
    try glfw.init();
    defer glfw.deinit();
    const window = try Window.init(10, 10, "test_title");
    window.deinit();
}

test "getting the size of the window should work" {
    try glfw.init();
    defer glfw.deinit();
    const width = 200;
    const height = 300;
    const window = try Window.init(width, height, "");
    defer window.deinit();

    testing.expectEqual(Vk.c.VkExtent2D{ .width = width, .height = height }, try window.getSize());
}

const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const glfw = @import("glfw_wrapper.zig");
usingnamespace @import("window.zig");
usingnamespace @import("vulkan_general.zig");
usingnamespace @import("vulkan_instance.zig");
usingnamespace @import("vulkan_graphics_device.zig");
usingnamespace @import("command_buffer.zig");

test "render an empty screen" {
    try glfw.init();
    defer glfw.deinit();
    const window = try Window.init(200, 200, "test_window");
    defer window.deinit();
    var renderer = try Renderer.init(window, testApplicationInfo(), testExtensions(), testing.allocator);
    defer renderer.deinit();

    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try renderer.updateImageIndex();

        const command_buffer = renderer.command_buffers[renderer.current_render_image_index];
        try simpleBeginCommandBuffer(command_buffer);

        beginRenderPassWithClearValueAndFullExtent(
            command_buffer,
            renderer.render_pass,
            renderer.core_device_data.swap_chain.extent,
            renderer.frame_buffers[renderer.current_render_image_index],
            [4]f32{ 0, 0.5, 1, 1 },
        );

        Vk.c.vkCmdEndRenderPass(command_buffer);

        try endCommandBuffer(command_buffer);

        try renderer.draw();
        try renderer.present();
    }
}

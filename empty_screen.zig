const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const glfw = @import("glfw_wrapper.zig");
usingnamespace @import("window.zig");
usingnamespace @import("vulkan_general.zig");
usingnamespace @import("vulkan_instance.zig");
usingnamespace @import("vulkan_graphics_device.zig");

fn draw(r: Renderer) !void {
    const waitStages = [_]Vk.c.VkPipelineStageFlags{Vk.c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};

    const submit_info = Vk.c.VkSubmitInfo{
        .sType = .VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .pNext = null,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &r.semaphores.image_available,
        .pWaitDstStageMask = &waitStages,

        .commandBufferCount = 1,
        .pCommandBuffers = r.command_buffers.ptr + r.current_render_image_index,
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &r.semaphores.render_finished,
    };
    try checkVulkanResult(Vk.c.vkQueueSubmit(r.core_device_data.queues.graphics, 1, &submit_info, null));
}

fn fillCommandBuffer(render_pass: Vk.RenderPass, swap_chain_extent: Vk.c.VkExtent2D, frame_buffer: Vk.Framebuffer, command_buffer: Vk.CommandBuffer, clear_color: [4]f32) !void {
    const beginInfo = Vk.c.VkCommandBufferBeginInfo{
        .sType = .VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .pNext = null,
        .flags = Vk.c.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT,
        .pInheritanceInfo = null,
    };

    try checkVulkanResult(Vk.c.vkBeginCommandBuffer(command_buffer, &beginInfo));

    const clearColor = Vk.c.VkClearValue{ .color = .{ .float32 = clear_color } };
    const renderPassInfo = Vk.c.VkRenderPassBeginInfo{
        .sType = .VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .pNext = null,
        .renderPass = render_pass,
        .framebuffer = frame_buffer,
        .renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = swap_chain_extent },
        .clearValueCount = 1,
        .pClearValues = &clearColor,
    };

    Vk.c.vkCmdBeginRenderPass(command_buffer, &renderPassInfo, .VK_SUBPASS_CONTENTS_INLINE);

    Vk.c.vkCmdEndRenderPass(command_buffer);

    try checkVulkanResult(Vk.c.vkEndCommandBuffer(command_buffer));
}

test "render an empty screen" {
    try glfw.init();
    defer glfw.deinit();
    const window = try Window.init(200, 200, "test_window");
    defer window.deinit();
    var renderer = try Renderer.init(window, testApplicationInfo(), testExtensions(), testing.allocator);
    defer renderer.deinit();

    try window.show();
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try renderer.updateImageIndex();
        try fillCommandBuffer(
            renderer.render_pass,
            renderer.core_device_data.swap_chain.extent,
            renderer.frame_buffers[renderer.current_render_image_index],
            renderer.command_buffers[renderer.current_render_image_index],
            [4]f32{ 0, 0.5, 1, 1 },
        );
        try draw(renderer);
        try renderer.present();
    }
}

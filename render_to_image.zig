const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const glfw = @import("glfw_wrapper.zig");
usingnamespace @import("device_memory_store.zig");
usingnamespace @import("vulkan_general.zig");
usingnamespace @import("vulkan_graphics_device.zig");
usingnamespace @import("vulkan_image.zig");
usingnamespace @import("vulkan_instance.zig");
usingnamespace @import("physical_device.zig");
usingnamespace @import("device_and_queues.zig");

fn fillCommandBufferEmptyScreen(render_pass: Vk.RenderPass, image_extent: Vk.c.VkExtent2D, frame_buffer: Vk.Framebuffer, command_buffer: Vk.CommandBuffer, clear_color: [4]f32) !void {
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
        .renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = image_extent },
        .clearValueCount = 1,
        .pClearValues = &clearColor,
    };

    Vk.c.vkCmdBeginRenderPass(command_buffer, &renderPassInfo, .VK_SUBPASS_CONTENTS_INLINE);

    Vk.c.vkCmdEndRenderPass(command_buffer);

    try checkVulkanResult(Vk.c.vkEndCommandBuffer(command_buffer));
}
test "render an empty image" {
    try glfw.init();
    defer glfw.deinit();
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyTestInstance(instance);
    const physical_device = try findPhysicalDeviceSuitableForGraphics(instance, testing.allocator);
    const device_and_queues = try createLogicalDeviceAndQueusForGraphics(physical_device, testing.allocator);
    defer destroyDevice(device_and_queues.device);

    const image_format = Vk.c.VkFormat.VK_FORMAT_R32G32B32A32_SFLOAT;
    const render_pass = try createRenderPass(image_format, device_and_queues.device);
    defer destroyRenderPass(device_and_queues.device, render_pass, null);

    var store = try DeviceMemoryStore.init(
        .{
            .default_allocation_size = 1e3,
            .default_staging_upload_buffer_size = 1e6,
            .default_staging_download_buffer_size = 1e6,
            .maximum_uniform_buffer_size = null,
            .buffering_mode = .Single,
        },
        physical_device,
        device_and_queues.device,
        device_and_queues.transfer_queue,
        device_and_queues.graphics_queue,
        testing.allocator,
    );
    defer store.deinit();

    const image_extent = Vk.c.VkExtent2D{ .width = 16, .height = 16 };
    const image_id = try store.allocateImage2D(image_extent, Vk.c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | Vk.c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT, image_format);
    const image_info = store.getImageInformation(image_id);
    const image_view = try createImageView2D(device_and_queues.device, image_info.image, image_info.format);
    defer Vk.c.vkDestroyImageView(device_and_queues.device, image_view, null);

    const frame_buffers = try createFramebuffers(device_and_queues.device, render_pass, @ptrCast([*]const Vk.ImageView, &image_view)[0..1], image_extent, testing.allocator);
    defer {
        destroyFramebuffers(device_and_queues.device, frame_buffers);
        testing.allocator.free(frame_buffers);
    }

    const command_pool = try device_and_queues.graphics_queue.createCommandPool(device_and_queues.device, 0);
    defer destroyCommandPool(device_and_queues.device, command_pool, null);

    const command_buffers = try createCommandBuffers(device_and_queues.device, command_pool, frame_buffers, testing.allocator);
    defer {
        freeCommandBuffers(device_and_queues.device, command_pool, command_buffers);
        testing.allocator.free(command_buffers);
    }

    const color = [4]f32{ 0, 0.5, 1, 1 };

    try fillCommandBufferEmptyScreen(
        render_pass,
        image_extent,
        frame_buffers[0],
        command_buffers[0],
        color,
    );

    try device_and_queues.graphics_queue.submitSingle(&[0]Vk.Semaphore{}, command_buffers, &[0]Vk.Semaphore{}, null);
    try device_and_queues.graphics_queue.waitIdle();
    const data = try store.downloadImage2DAndDiscard([4]f32, image_id, .VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, 0, image_extent, device_and_queues.graphics_queue);
    testing.expectEqual(@as(usize, image_extent.width * image_extent.height), data.len);
    for (data) |d| {
        testing.expectEqual(color, d);
    }
}

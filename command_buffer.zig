const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const glfw = @import("glfw_wrapper.zig");
usingnamespace @import("vulkan_general.zig");

pub fn createCommandBuffers(logical_device: Vk.Device, command_pool: Vk.CommandPool, frame_buffers: []Vk.Framebuffer, allocator: *mem.Allocator) ![]Vk.CommandBuffer {
    const command_buffers = try allocator.alloc(Vk.CommandBuffer, frame_buffers.len);
    errdefer allocator.free(command_buffers);
    const allocInfo = Vk.c.VkCommandBufferAllocateInfo{
        .sType = .VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .pNext = null,
        .commandPool = command_pool,
        .level = .VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = @intCast(u32, command_buffers.len),
    };
    try checkVulkanResult(Vk.c.vkAllocateCommandBuffers(logical_device, &allocInfo, @ptrCast(*Vk.c.VkCommandBuffer, command_buffers.ptr)));
    return command_buffers;
}

pub fn freeCommandBuffers(logical_device: Vk.Device, command_pool: Vk.CommandPool, command_buffers: []Vk.CommandBuffer) void {
    Vk.c.vkFreeCommandBuffers(logical_device, command_pool, @intCast(u32, command_buffers.len), command_buffers.ptr);
}

pub fn simpleBeginCommandBuffer(command_buffer: Vk.CommandBuffer) !void {
    const beginInfo = Vk.c.VkCommandBufferBeginInfo{
        .sType = .VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .pNext = null,
        .flags = 0,
        .pInheritanceInfo = null,
    };

    try checkVulkanResult(Vk.c.vkBeginCommandBuffer(command_buffer, &beginInfo));
}

pub fn endCommandBuffer(command_buffer: Vk.CommandBuffer) !void {
    try checkVulkanResult(Vk.c.vkEndCommandBuffer(command_buffer));
}

pub fn beginRenderPassWithClearValueAndFullExtent(
    command_buffer: Vk.CommandBuffer,
    render_pass: Vk.RenderPass,
    image_extent: Vk.c.VkExtent2D,
    frame_buffer: Vk.Framebuffer,
    clear_color: [4]f32,
) void {
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
}

pub fn drawFourVerticesWithDynamicOffsetsForUniformBuffers(
    command_buffer: Vk.CommandBuffer,
    graphics_pipeline: Vk.Pipeline,
    graphics_pipeline_layout: Vk.PipelineLayout,
    descriptor_sets: []const Vk.DescriptorSet,
    dynamic_offsets: []const u32,
) void {
    Vk.c.vkCmdBindPipeline(command_buffer, .VK_PIPELINE_BIND_POINT_GRAPHICS, graphics_pipeline);

    std.debug.assert(descriptor_sets.len == dynamic_offsets.len);
    for (descriptor_sets) |descriptor_set, i| {
        Vk.c.vkCmdBindDescriptorSets(command_buffer, .VK_PIPELINE_BIND_POINT_GRAPHICS, graphics_pipeline_layout, 0, 1, &descriptor_set, 1, &dynamic_offsets[i]);
        Vk.c.vkCmdDraw(command_buffer, 4, 1, 0, 0);
    }
}

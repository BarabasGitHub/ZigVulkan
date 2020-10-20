const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const glfw = @import("glfw_wrapper.zig");
usingnamespace @import("vulkan_general.zig");

pub fn recordCommandBufferWithUniformBuffers(
    render_pass: Vk.RenderPass,
    swap_chain_extent: Vk.c.VkExtent2D,
    frame_buffer: Vk.Framebuffer,
    command_buffer: Vk.CommandBuffer,
    graphics_pipeline: Vk.Pipeline,
    graphics_pipeline_layout: Vk.PipelineLayout,
    descriptor_sets: []const Vk.DescriptorSet,
    dynamic_offsets: []const u32,
    clear_color: [4]f32,
) !void {
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

    Vk.c.vkCmdBindPipeline(command_buffer, .VK_PIPELINE_BIND_POINT_GRAPHICS, graphics_pipeline);

    std.debug.assert(descriptor_sets.len == dynamic_offsets.len);
    for (descriptor_sets) |descriptor_set, i| {
        Vk.c.vkCmdBindDescriptorSets(command_buffer, .VK_PIPELINE_BIND_POINT_GRAPHICS, graphics_pipeline_layout, 0, 1, &descriptor_set, 1, &dynamic_offsets[i]);
        Vk.c.vkCmdDraw(command_buffer, 6, 1, 0, 0);
    }

    Vk.c.vkCmdEndRenderPass(command_buffer);

    try checkVulkanResult(Vk.c.vkEndCommandBuffer(command_buffer));
}

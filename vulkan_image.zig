const std = @import("std");
usingnamespace @import("vulkan_general.zig");

pub fn create2DImage(extent: Vk.c.VkExtent2D, format: Vk.c.VkFormat, usage: u32, logical_device: Vk.Device) !Vk.Image {
    const create_info = Vk.c.VkImageCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .imageType = .VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = .{ .width = extent.width, .height = extent.height, .depth = 1 },
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = .VK_SAMPLE_COUNT_1_BIT,
        .tiling = .VK_IMAGE_TILING_OPTIMAL,
        .usage = usage,
        .sharingMode = .VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 0,
        .pQueueFamilyIndices = null,
        .initialLayout = .VK_IMAGE_LAYOUT_UNDEFINED,
    };
    var image: Vk.Image = undefined;
    try checkVulkanResult(Vk.c.vkCreateImage(logical_device, &create_info, null, @ptrCast(*Vk.c.VkImage, &image)));
    return image;
}

pub fn createImageView2D(device: Vk.Device, image: Vk.Image, format: Vk.c.VkFormat) !Vk.ImageView {
    const view_create_info = Vk.c.VkImageViewCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .image = image,
        .viewType = .VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .components = .{ .r = .VK_COMPONENT_SWIZZLE_IDENTITY, .g = .VK_COMPONENT_SWIZZLE_IDENTITY, .b = .VK_COMPONENT_SWIZZLE_IDENTITY, .a = .VK_COMPONENT_SWIZZLE_IDENTITY },
        .subresourceRange = .{ .aspectMask = Vk.c.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = 0, .levelCount = Vk.c.VK_REMAINING_MIP_LEVELS, .baseArrayLayer = 0, .layerCount = Vk.c.VK_REMAINING_ARRAY_LAYERS },
    };

    var view: Vk.ImageView = undefined;
    try checkVulkanResult(Vk.c.vkCreateImageView(device, &view_create_info, null, @ptrCast(*Vk.c.VkImageView, &view)));
    return view;
}

pub fn createFramebuffers(logical_device: Vk.Device, render_pass: Vk.RenderPass, image_views: []const Vk.ImageView, image_extent: Vk.c.VkExtent2D, allocator: *std.mem.Allocator) ![]Vk.Framebuffer {
    const frame_buffers = try allocator.alloc(Vk.Framebuffer, image_views.len);
    errdefer allocator.free(frame_buffers);
    for (image_views) |image_view, i| {
        errdefer destroyFramebuffers(logical_device, frame_buffers[0..i]);
        const framebuffer_info = Vk.c.VkFramebufferCreateInfo{
            .sType = .VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .renderPass = render_pass,
            .attachmentCount = 1,
            .pAttachments = &image_view,
            .width = image_extent.width,
            .height = image_extent.height,
            .layers = 1,
        };
        try checkVulkanResult(Vk.c.vkCreateFramebuffer(logical_device, &framebuffer_info, null, @ptrCast(*Vk.c.VkFramebuffer, frame_buffers.ptr + i)));
        // TODO: somehow clean up in case of an error.
    }
    return frame_buffers;
}

pub const destroyFramebuffer = Vk.c.vkDestroyFramebuffer;

pub fn destroyFramebuffers(logical_device: Vk.Device, frame_buffers: []Vk.Framebuffer) void {
    for (frame_buffers) |frame_buffer| {
        destroyFramebuffer(logical_device, frame_buffer, null);
    }
}

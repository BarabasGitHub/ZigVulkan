const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const glfw = @import("glfw_wrapper.zig");
usingnamespace @import("window.zig");
usingnamespace @import("device_memory_store.zig");
usingnamespace @import("vulkan_general.zig");
usingnamespace @import("vulkan_graphics_device.zig");
usingnamespace @import("vulkan_image.zig");
usingnamespace @import("vulkan_instance.zig");
usingnamespace @import("vulkan_shader.zig");
usingnamespace @import("pipeline_and_layout.zig");

fn fillCommandBufferEmptyScreen(render_pass: Vk.RenderPass, swap_chain_extent: Vk.c.VkExtent2D, frame_buffer: Vk.Framebuffer, command_buffer: Vk.CommandBuffer, clear_color: [4]f32) !void {
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
        try fillCommandBufferEmptyScreen(
            renderer.render_pass,
            renderer.core_device_data.swap_chain.extent,
            renderer.frame_buffers[renderer.current_render_image_index],
            renderer.command_buffers[renderer.current_render_image_index],
            [4]f32{ 0, 0.5, 1, 1 },
        );
        try renderer.draw();
        try renderer.present();
    }
}

const RectangleBuffer = packed struct {
    extent_x: f32,
    extent_y: f32,
    rotation_r: f32,
    rotation_i: f32,
    center_x: f32,
    center_y: f32,
    center_z: f32,
    _padding: u32 = undefined,
    colour_r: f32,
    colour_g: f32,
    colour_b: f32,
    colour_a: f32,
};

test "render multiple plain rectangles" {
    try glfw.init();
    defer glfw.deinit();
    const window = try Window.init(200, 200, "test_window");
    defer window.deinit();
    var renderer = try Renderer.init(window, testApplicationInfo(), testExtensions(), testing.allocator);
    defer renderer.deinit();

    const descriptor_set_layouts = [_]Vk.DescriptorSetLayout{try createDescriptorSetLayout(renderer.core_device_data.logical_device)};
    defer {
        for (descriptor_set_layouts) |l|
            Vk.c.vkDestroyDescriptorSetLayout(renderer.core_device_data.logical_device, l, null);
    }

    var descriptor_sets: [2]Vk.DescriptorSet = undefined;
    try allocateDescriptorSet(&descriptor_set_layouts, renderer.descriptor_pool, renderer.core_device_data.logical_device, descriptor_sets[0..1]);
    descriptor_sets[1] = descriptor_sets[0];

    var shader_stages: [2]Vk.c.VkPipelineShaderStageCreateInfo = undefined;

    const fixed_rectangle = try createShaderModuleFromEmbeddedFile(renderer.core_device_data.logical_device, "Shaders/rectangle.vert.spr", .Vertex);
    defer fixed_rectangle.deinit(renderer.core_device_data.logical_device);
    shader_stages[0] = fixed_rectangle.toPipelineShaderStageCreateInfo();

    const white_pixel = try createShaderModuleFromEmbeddedFile(renderer.core_device_data.logical_device, "Shaders/plain_colour.frag.spr", .Fragment);
    defer white_pixel.deinit(renderer.core_device_data.logical_device);
    shader_stages[1] = white_pixel.toPipelineShaderStageCreateInfo();

    const pipeline_and_layout = try createGraphicsPipelineAndLayout(renderer.core_device_data.swap_chain.extent, renderer.core_device_data.logical_device, renderer.render_pass, &descriptor_set_layouts, &shader_stages);
    defer destroyPipelineAndLayout(renderer.core_device_data.logical_device, pipeline_and_layout);

    var store = try DeviceMemoryStore.init(
        .{
            .default_allocation_size = 1e3,
            .default_staging_upload_buffer_size = 1e4,
            .default_staging_download_buffer_size = 1e4,
            .maximum_uniform_buffer_size = null,
            .buffering_mode = .Triple,
        },
        renderer.core_device_data.physical_device,
        renderer.core_device_data.logical_device,
        renderer.core_device_data.queues.transfer,
        renderer.core_device_data.queues.graphics,
        testing.allocator,
    );
    defer store.deinit();

    const buffer1 = try store.reserveBufferSpace(@sizeOf(RectangleBuffer), .{ .usage = Vk.c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, .properties = Vk.c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT | Vk.c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT });
    const buffer2 = try store.reserveBufferSpace(@sizeOf(RectangleBuffer), .{ .usage = Vk.c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, .properties = Vk.c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT | Vk.c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT });
    std.debug.assert(store.getVkBufferForBufferId(buffer1) == store.getVkBufferForBufferId(buffer2));
    writeUniformBufferToDescriptorSet(renderer.core_device_data.logical_device, store.getVkDescriptorBufferInfoForBufferId(buffer1), descriptor_sets[0]);

    const rectangles: [2]RectangleBuffer = .{
        .{
            .extent_x = 0.5,
            .extent_y = 0.5,
            .rotation_r = 1,
            .rotation_i = 0,
            .center_x = -0.5,
            .center_y = -0.5,
            .center_z = 0,
            .colour_r = 1,
            .colour_g = 0,
            .colour_b = 0,
            .colour_a = 1,
        },
        .{
            .extent_x = 0.5,
            .extent_y = 0.5,
            .rotation_r = 1,
            .rotation_i = 0,
            .center_x = 0.5,
            .center_y = 0.5,
            .center_z = 0,
            .colour_r = 0,
            .colour_g = 1,
            .colour_b = 0,
            .colour_a = 1,
        },
    };
    const dynamic_offsets: [2]u32 = .{ 0, @sizeOf(RectangleBuffer) };

    try window.show();
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try renderer.updateImageIndex();
        const mapped_buffer_slices = try store.getMappedBufferSlices(testing.allocator);
        defer testing.allocator.free(mapped_buffer_slices);
        std.debug.assert(mapped_buffer_slices.len == 1);
        std.mem.copy(u8, mapped_buffer_slices[0], std.mem.sliceAsBytes(&rectangles));
        try store.flushAndSwitchBuffers();
        try fillCommandBufferWithUniformBuffers(
            renderer.render_pass,
            renderer.core_device_data.swap_chain.extent,
            renderer.frame_buffers[renderer.current_render_image_index],
            renderer.command_buffers[renderer.current_render_image_index],
            pipeline_and_layout.graphics_pipeline,
            pipeline_and_layout.layout,
            &descriptor_sets,
            &dynamic_offsets,
            [4]f32{ 0, 0.5, 1, 1 },
        );
        try renderer.draw();
        try renderer.present();
    }
}

fn fillCommandBufferWithUniformBuffers(
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

fn createDescriptorSetLayout(device: Vk.Device) !Vk.DescriptorSetLayout {
    const bindings = [_]Vk.c.VkDescriptorSetLayoutBinding{
        .{
            .binding = 1,
            .descriptorType = .VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
            .descriptorCount = 1,
            .stageFlags = Vk.c.VK_SHADER_STAGE_FRAGMENT_BIT | Vk.c.VK_SHADER_STAGE_VERTEX_BIT,
            .pImmutableSamplers = null,
        },
        .{
            .binding = 2,
            .descriptorType = .VK_DESCRIPTOR_TYPE_SAMPLER,
            .descriptorCount = 1,
            .stageFlags = Vk.c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .pImmutableSamplers = null,
        },
        .{
            .binding = 3,
            .descriptorType = .VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
            .descriptorCount = 1,
            .stageFlags = Vk.c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .pImmutableSamplers = null,
        },
    };

    const create_info = Vk.c.VkDescriptorSetLayoutCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .bindingCount = @intCast(u32, bindings.len),
        .pBindings = &bindings[0],
    };

    var descriptor_set_layout: Vk.DescriptorSetLayout = undefined;
    try checkVulkanResult(Vk.c.vkCreateDescriptorSetLayout(device, &create_info, null, @ptrCast(*Vk.c.VkDescriptorSetLayout, &descriptor_set_layout)));
    return descriptor_set_layout;
}

fn createSampler(device: Vk.Device) !Vk.Sampler {
    const create_info = Vk.c.VkSamplerCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .magFilter = .VK_FILTER_NEAREST, //VK_FILTER_LINEAR;
        .minFilter = .VK_FILTER_NEAREST, //VK_FILTER_LINEAR;
        .mipmapMode = .VK_SAMPLER_MIPMAP_MODE_LINEAR,
        .addressModeU = .VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .addressModeV = .VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .addressModeW = .VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .mipLodBias = 0,
        // .anisotropyEnable = VK_TRUE;
        .anisotropyEnable = Vk.c.VK_FALSE,
        .maxAnisotropy = 16,
        .compareEnable = Vk.c.VK_FALSE,
        .compareOp = .VK_COMPARE_OP_ALWAYS,
        .minLod = 0,
        .maxLod = 32,
        .borderColor = .VK_BORDER_COLOR_INT_OPAQUE_WHITE,
        .unnormalizedCoordinates = Vk.c.VK_FALSE,
    };
    var sampler: Vk.Sampler = undefined;
    try checkVulkanResult(Vk.c.vkCreateSampler(device, &create_info, null, @ptrCast(*Vk.c.VkSampler, &sampler)));
    return sampler;
}

fn allocateDescriptorSet(layouts: []const Vk.DescriptorSetLayout, pool: Vk.DescriptorPool, logical_device: Vk.Device, sets: []Vk.DescriptorSet) !void {
    std.debug.assert(layouts.len == sets.len);
    const allocInfo = Vk.c.VkDescriptorSetAllocateInfo{
        .sType = .VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .pNext = null,
        .descriptorPool = pool,
        .descriptorSetCount = @intCast(u32, layouts.len),
        .pSetLayouts = layouts.ptr,
    };

    try checkVulkanResult(Vk.c.vkAllocateDescriptorSets(logical_device, &allocInfo, @ptrCast(*Vk.c.VkDescriptorSet, sets.ptr)));
}

test "render one textured rectangle" {
    try glfw.init();
    defer glfw.deinit();
    const window = try Window.init(200, 200, "test_window");
    defer window.deinit();
    var renderer = try Renderer.init(window, testApplicationInfo(), testExtensions(), testing.allocator);
    defer renderer.deinit();

    const descriptor_set_layouts = [_]Vk.DescriptorSetLayout{try createDescriptorSetLayout(renderer.core_device_data.logical_device)};
    defer {
        for (descriptor_set_layouts) |l|
            Vk.c.vkDestroyDescriptorSetLayout(renderer.core_device_data.logical_device, l, null);
    }
    var descriptor_sets: [descriptor_set_layouts.len]Vk.DescriptorSet = undefined;
    try allocateDescriptorSet(&descriptor_set_layouts, renderer.descriptor_pool, renderer.core_device_data.logical_device, &descriptor_sets);

    var shader_stages: [2]Vk.c.VkPipelineShaderStageCreateInfo = undefined;

    const fixed_rectangle = try createShaderModuleFromEmbeddedFile(renderer.core_device_data.logical_device, "Shaders/fixed_uv_rectangle.vert.spr", .Vertex);
    defer fixed_rectangle.deinit(renderer.core_device_data.logical_device);
    shader_stages[0] = fixed_rectangle.toPipelineShaderStageCreateInfo();

    const textured_pixel = try createShaderModuleFromEmbeddedFile(renderer.core_device_data.logical_device, "Shaders/textured.frag.spr", .Fragment);
    defer textured_pixel.deinit(renderer.core_device_data.logical_device);
    shader_stages[1] = textured_pixel.toPipelineShaderStageCreateInfo();

    const pipeline_and_layout = try createGraphicsPipelineAndLayout(renderer.core_device_data.swap_chain.extent, renderer.core_device_data.logical_device, renderer.render_pass, &descriptor_set_layouts, &shader_stages);
    defer destroyPipelineAndLayout(renderer.core_device_data.logical_device, pipeline_and_layout);

    var store = try DeviceMemoryStore.init(
        .{
            .default_allocation_size = 1e3,
            .default_staging_upload_buffer_size = 1e4,
            .default_staging_download_buffer_size = 1e4,
            .maximum_uniform_buffer_size = null,
            .buffering_mode = .Triple,
        },
        renderer.core_device_data.physical_device,
        renderer.core_device_data.logical_device,
        renderer.core_device_data.queues.transfer,
        renderer.core_device_data.queues.graphics,
        testing.allocator,
    );
    defer store.deinit();

    const sampler = try createSampler(renderer.core_device_data.logical_device);
    defer Vk.c.vkDestroySampler(renderer.core_device_data.logical_device, sampler, null);

    const image_id = try store.allocateImage2D(.{ .width = 32, .height = 32 }, Vk.c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | Vk.c.VK_IMAGE_USAGE_SAMPLED_BIT, .VK_FORMAT_R8G8B8A8_UNORM);
    const data = [_][4]u8{.{ 0xFF, 0xFF, 0xFF, 0xFF }} ++ [_][4]u8{.{ 0xFF, 0x00, 0xFF, 0xFF }} ** 31 ++ [_][4]u8{.{ 0xFF, 0xFF, 0x00, 0xFF }} ** (31 * 32);
    try store.uploadImage2D([4]u8, image_id, .{ .width = 32, .height = 32 }, &data, renderer.core_device_data.queues.transfer, renderer.core_device_data.queues.graphics);
    const image_info = store.getImageInformation(image_id);
    const image_view = try createImageView2D(renderer.core_device_data.logical_device, image_info.image, image_info.format);
    defer Vk.c.vkDestroyImageView(renderer.core_device_data.logical_device, image_view, null);

    // write descriptor sets
    writeImageAndSamplerToDescriptorSet(renderer.core_device_data.logical_device, sampler, image_view, image_info.layout, descriptor_sets[0]);

    try window.show();
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try renderer.updateImageIndex();
        try fillCommandBufferWithUniformBuffers(
            renderer.render_pass,
            renderer.core_device_data.swap_chain.extent,
            renderer.frame_buffers[renderer.current_render_image_index],
            renderer.command_buffers[renderer.current_render_image_index],
            pipeline_and_layout.graphics_pipeline,
            pipeline_and_layout.layout,
            &descriptor_sets,
            &[1]u32{0},

            [4]f32{ 0, 0.5, 1, 1 },
        );
        try renderer.draw();
        try renderer.present();
    }
}

fn writeUniformBufferToDescriptorSet(device: Vk.Device, buffer_info: Vk.c.VkDescriptorBufferInfo, descriptor_set: Vk.DescriptorSet) void {
    const write_descriptor_sets = [_]Vk.c.VkWriteDescriptorSet{.{
        .sType = .VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .pNext = null,
        .dstSet = descriptor_set,
        .dstBinding = 1,
        .dstArrayElement = 0,
        .descriptorCount = 1,
        .descriptorType = .VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
        .pImageInfo = null,
        .pBufferInfo = &buffer_info,
        .pTexelBufferView = null,
    }};
    Vk.c.vkUpdateDescriptorSets(device, @intCast(u32, write_descriptor_sets.len), &write_descriptor_sets[0], 0, null);
}

fn writeImageAndSamplerToDescriptorSet(device: Vk.Device, sampler: Vk.Sampler, view: Vk.ImageView, layout: Vk.c.VkImageLayout, descriptor_set: Vk.DescriptorSet) void {
    const image_info = Vk.c.VkDescriptorImageInfo{
        .sampler = sampler,
        .imageView = view,
        .imageLayout = layout,
    };

    const write_descriptor_sets = [_]Vk.c.VkWriteDescriptorSet{
        .{
            .sType = .VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .pNext = null,
            .dstSet = descriptor_set,
            .dstBinding = 2,
            .dstArrayElement = 0,
            .descriptorCount = 1,
            .descriptorType = .VK_DESCRIPTOR_TYPE_SAMPLER,
            .pImageInfo = &image_info,
            .pBufferInfo = null,
            .pTexelBufferView = null,
        },
        .{
            .sType = .VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .pNext = null,
            .dstSet = descriptor_set,
            .dstBinding = 3,
            .dstArrayElement = 0,
            .descriptorCount = 1,
            .descriptorType = .VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
            .pImageInfo = &image_info,
            .pBufferInfo = null,
            .pTexelBufferView = null,
        },
    };

    Vk.c.vkUpdateDescriptorSets(device, @intCast(u32, write_descriptor_sets.len), &write_descriptor_sets[0], 0, null);
}

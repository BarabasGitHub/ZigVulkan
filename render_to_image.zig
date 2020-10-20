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
usingnamespace @import("vulkan_shader.zig");
usingnamespace @import("pipeline_and_layout.zig");
usingnamespace @import("index_utilities.zig");
usingnamespace @import("descriptor_sets.zig");
usingnamespace @import("command_buffer.zig");

const ImageIDAndView = struct {
    id: DeviceMemoryStore.ImageID,
    view: Vk.ImageView,
};

fn allocateImage2dAndCreateView(store: *DeviceMemoryStore, device: Vk.Device, extent: Vk.c.VkExtent2D, usage: u32, format: Vk.c.VkFormat) !ImageIDAndView {
    const image_id = try store.allocateImage2D(extent, usage, format);
    const image_info = store.getImageInformation(image_id);
    return ImageIDAndView{ .id = image_id, .view = try createImageView2D(device, image_info.image, image_info.format) };
}

fn createTestStore(physical_device: Vk.PhysicalDevice, device_and_queues: DeviceAndQueues, allocator: *std.mem.Allocator) !DeviceMemoryStore {
    return try DeviceMemoryStore.init(
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
        allocator,
    );
}

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

    var store = try createTestStore(physical_device, device_and_queues, testing.allocator);
    defer store.deinit();

    const image_extent = Vk.c.VkExtent2D{ .width = 16, .height = 16 };
    const image = try allocateImage2dAndCreateView(&store, device_and_queues.device, image_extent, Vk.c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | Vk.c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT, image_format);
    defer Vk.c.vkDestroyImageView(device_and_queues.device, image.view, null);

    const frame_buffers = try createFramebuffers(device_and_queues.device, render_pass, @ptrCast([*]const Vk.ImageView, &image.view)[0..1], image_extent, testing.allocator);
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
    const data = try store.downloadImage2DAndDiscard([4]f32, image.id, .VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, 0, image_extent, device_and_queues.graphics_queue);
    testing.expectEqual(@as(usize, image_extent.width * image_extent.height), data.len);
    for (data) |d| {
        testing.expectEqual(color, d);
    }
}

fn fillCommandBufferWithoutDescriptors(
    render_pass: Vk.RenderPass,
    swap_chain_extent: Vk.c.VkExtent2D,
    frame_buffer: Vk.Framebuffer,
    command_buffer: Vk.CommandBuffer,
    graphics_pipeline: Vk.Pipeline,
    graphics_pipeline_layout: Vk.PipelineLayout,
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

    Vk.c.vkCmdDraw(command_buffer, 6, 1, 0, 0);

    Vk.c.vkCmdEndRenderPass(command_buffer);

    try checkVulkanResult(Vk.c.vkEndCommandBuffer(command_buffer));
}

fn reintepretSlice(comptime T: type, slice: anytype) []const T {
    return std.mem.bytesAsSlice(T, std.mem.sliceAsBytes(slice));
}

test "render one plain rectangle" {
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

    var store = try createTestStore(physical_device, device_and_queues, testing.allocator);
    defer store.deinit();

    const image_extent = Vk.c.VkExtent2D{ .width = 16, .height = 16 };
    const image = try allocateImage2dAndCreateView(&store, device_and_queues.device, image_extent, Vk.c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | Vk.c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT, image_format);
    defer Vk.c.vkDestroyImageView(device_and_queues.device, image.view, null);

    const frame_buffers = try createFramebuffers(device_and_queues.device, render_pass, @ptrCast([*]const Vk.ImageView, &image.view)[0..1], image_extent, testing.allocator);
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

    const descriptor_set_layouts = [_]Vk.c.VkDescriptorSetLayout{};
    var shader_stages: [2]Vk.c.VkPipelineShaderStageCreateInfo = undefined;

    const fixed_rectangle = try createShaderModuleFromEmbeddedFile(device_and_queues.device, "Shaders/fixed_rectangle.vert.spr", .Vertex);
    defer fixed_rectangle.deinit(device_and_queues.device);
    shader_stages[0] = fixed_rectangle.toPipelineShaderStageCreateInfo();

    const white_pixel = try createShaderModuleFromEmbeddedFile(device_and_queues.device, "Shaders/white.frag.spr", .Fragment);
    defer white_pixel.deinit(device_and_queues.device);
    shader_stages[1] = white_pixel.toPipelineShaderStageCreateInfo();

    const pipeline_and_layout = try createGraphicsPipelineAndLayout(image_extent, device_and_queues.device, render_pass, &descriptor_set_layouts, &shader_stages);
    defer destroyPipelineAndLayout(device_and_queues.device, pipeline_and_layout);

    const background_color = [4]f32{ 0, 0, 0, 0 };

    try fillCommandBufferWithoutDescriptors(
        render_pass,
        image_extent,
        frame_buffers[0],
        command_buffers[0],
        pipeline_and_layout.graphics_pipeline,
        pipeline_and_layout.layout,
        background_color,
    );

    try device_and_queues.graphics_queue.submitSingle(&[0]Vk.Semaphore{}, command_buffers, &[0]Vk.Semaphore{}, null);
    try device_and_queues.graphics_queue.waitIdle();
    const data = try store.downloadImage2DAndDiscard([4]f32, image.id, .VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, 0, image_extent, device_and_queues.graphics_queue);
    const expected_image = im: {
        var expected_image: [image_extent.height * image_extent.width][4]f32 = undefined;
        for (expected_image) |*color, i| {
            const index2d = calculate2DindexFrom1D(@intCast(u32, i), image_extent.width);
            if (image_extent.width / 4 <= index2d.x and index2d.x < (image_extent.width * 3) / 4 and image_extent.height / 4 <= index2d.y and index2d.y < (image_extent.height * 3) / 4) {
                color.* = .{ 1, 1, 1, 1 };
            } else {
                color.* = background_color;
            }
        }
        break :im expected_image;
    };
    testing.expectEqualSlices(f32, reintepretSlice(f32, &expected_image), reintepretSlice(f32, data));
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

test "render multiple plain rectangles" {
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

    var store = try createTestStore(physical_device, device_and_queues, testing.allocator);
    defer store.deinit();

    const image_extent = Vk.c.VkExtent2D{ .width = 16, .height = 16 };
    const image = try allocateImage2dAndCreateView(&store, device_and_queues.device, image_extent, Vk.c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | Vk.c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT, image_format);
    defer Vk.c.vkDestroyImageView(device_and_queues.device, image.view, null);

    const frame_buffers = try createFramebuffers(device_and_queues.device, render_pass, @ptrCast([*]const Vk.ImageView, &image.view)[0..1], image_extent, testing.allocator);
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

    const descriptor_set_layouts = [_]Vk.DescriptorSetLayout{try createDescriptorSetLayout(device_and_queues.device)};
    defer {
        for (descriptor_set_layouts) |l|
            Vk.c.vkDestroyDescriptorSetLayout(device_and_queues.device, l, null);
    }

    const descriptor_pool = try createDescriptorPool(device_and_queues.device);
    defer destroyDescriptorPool(device_and_queues.device, descriptor_pool, null);

    var descriptor_sets: [2]Vk.DescriptorSet = undefined;
    try allocateDescriptorSet(&descriptor_set_layouts, descriptor_pool, device_and_queues.device, descriptor_sets[0..1]);
    descriptor_sets[1] = descriptor_sets[0];

    var shader_stages: [2]Vk.c.VkPipelineShaderStageCreateInfo = undefined;

    const fixed_rectangle = try createShaderModuleFromEmbeddedFile(device_and_queues.device, "Shaders/rectangle.vert.spr", .Vertex);
    defer fixed_rectangle.deinit(device_and_queues.device);
    shader_stages[0] = fixed_rectangle.toPipelineShaderStageCreateInfo();

    const white_pixel = try createShaderModuleFromEmbeddedFile(device_and_queues.device, "Shaders/plain_colour.frag.spr", .Fragment);
    defer white_pixel.deinit(device_and_queues.device);
    shader_stages[1] = white_pixel.toPipelineShaderStageCreateInfo();

    const pipeline_and_layout = try createGraphicsPipelineAndLayout(image_extent, device_and_queues.device, render_pass, &descriptor_set_layouts, &shader_stages);
    defer destroyPipelineAndLayout(device_and_queues.device, pipeline_and_layout);

    const buffer1 = try store.reserveBufferSpace(@sizeOf(RectangleBuffer), .{ .usage = Vk.c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, .properties = Vk.c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT | Vk.c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT });
    const buffer2 = try store.reserveBufferSpace(@sizeOf(RectangleBuffer), .{ .usage = Vk.c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, .properties = Vk.c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT | Vk.c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT });
    std.debug.assert(store.getVkBufferForBufferId(buffer1) == store.getVkBufferForBufferId(buffer2));
    writeUniformBufferToDescriptorSet(device_and_queues.device, store.getVkDescriptorBufferInfoForBufferId(buffer1), descriptor_sets[0]);

    const background_color = [4]f32{ 0, 0, 0, 0 };
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

    const mapped_buffer_slices = try store.getMappedBufferSlices(testing.allocator);
    defer testing.allocator.free(mapped_buffer_slices);
    std.debug.assert(mapped_buffer_slices.len == 1);
    std.mem.copy(u8, mapped_buffer_slices[0], std.mem.sliceAsBytes(&rectangles));
    try store.flushAndSwitchBuffers();

    try recordCommandBufferWithUniformBuffers(
        render_pass,
        image_extent,
        frame_buffers[0],
        command_buffers[0],
        pipeline_and_layout.graphics_pipeline,
        pipeline_and_layout.layout,
        &descriptor_sets,
        &dynamic_offsets,
        background_color,
    );

    try device_and_queues.graphics_queue.submitSingle(&[0]Vk.Semaphore{}, command_buffers, &[0]Vk.Semaphore{}, null);
    try device_and_queues.graphics_queue.waitIdle();
    const data = try store.downloadImage2DAndDiscard([4]f32, image.id, .VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, 0, image_extent, device_and_queues.graphics_queue);
    const expected_image = im: {
        var expected_image: [image_extent.height * image_extent.width][4]f32 = undefined;
        for (expected_image) |*color, i| {
            const index2d = calculate2DindexFrom1D(@intCast(u32, i), image_extent.width);
            if (index2d.x < image_extent.width / 2 and index2d.y < image_extent.height / 2) {
                color.* = .{ rectangles[0].colour_r, rectangles[0].colour_g, rectangles[0].colour_b, rectangles[0].colour_a };
            } else if (index2d.x >= image_extent.width / 2 and index2d.y >= image_extent.height / 2) {
                color.* = .{ rectangles[1].colour_r, rectangles[1].colour_g, rectangles[1].colour_b, rectangles[1].colour_a };
            } else {
                color.* = background_color;
            }
        }
        break :im expected_image;
    };
    testing.expectEqualSlices(f32, reintepretSlice(f32, &expected_image), reintepretSlice(f32, data));
}

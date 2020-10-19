const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const glfw = @import("glfw_wrapper.zig");
usingnamespace @import("device_memory_store.zig");
usingnamespace @import("vulkan_general.zig");
usingnamespace @import("vulkan_graphics_device.zig");
usingnamespace @import("vulkan_image.zig");
usingnamespace @import("vulkan_instance.zig");

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

fn findPhysicalDeviceSuitableForGraphics(instance: Vk.Instance, allocator: *mem.Allocator) !Vk.PhysicalDevice {
    var device_count: u32 = 0;
    try checkVulkanResult(Vk.c.vkEnumeratePhysicalDevices(instance, &device_count, null));
    if (device_count == 0) {
        return error.NoDeviceWithVulkanSupportFound;
    }
    const devices = try allocator.alloc(Vk.PhysicalDevice, device_count);
    defer allocator.free(devices);
    try checkVulkanResult(Vk.c.vkEnumeratePhysicalDevices(instance, &device_count, @ptrCast([*]Vk.c.VkPhysicalDevice, devices.ptr)));
    for (devices) |device| {
        const queue_familiy_properties = try getPhysicalDeviceQueueFamiliyPropeties(device, allocator);
        defer allocator.free(queue_familiy_properties);
        if (findGraphicsFamilyQueue(queue_familiy_properties) != null) {
            return device;
        }
    }
    return error.FailedToFindSuitableVulkanDevice;
}

const DeviceAndQueues = struct {
    device: Vk.Device,
    graphics_queue: Queue,
    transfer_queue: Queue,
};

fn createLogicalDeviceAndQueusForGraphics(physical_device: Vk.PhysicalDevice, allocator: *mem.Allocator) !DeviceAndQueues {
    const queue_familiy_properties = try getPhysicalDeviceQueueFamiliyPropeties(physical_device, allocator);
    defer allocator.free(queue_familiy_properties);
    const graphics_family = findGraphicsFamilyQueue(queue_familiy_properties).?;
    const transfer_family = findTransferFamilyQueue(queue_familiy_properties).?;

    var queue_create_infos: [2]Vk.c.VkDeviceQueueCreateInfo = undefined;
    const queue_priority: f32 = 1;
    var queue_create_info = Vk.c.VkDeviceQueueCreateInfo{
        .sType = Vk.c.VkStructureType.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .queueFamilyIndex = graphics_family,
        .queueCount = 1,
        .pQueuePriorities = &queue_priority,
    };
    queue_create_infos[0] = queue_create_info;
    var queue_create_info_count: u32 = 1;
    if (graphics_family != transfer_family) {
        queue_create_info.queueFamilyIndex = transfer_family;
        queue_create_infos[queue_create_info_count] = queue_create_info;
        queue_create_info_count += 1;
    }
    std.debug.assert(queue_create_infos.len >= queue_create_info_count);
    const device_features = std.mem.zeroes(Vk.c.VkPhysicalDeviceFeatures);

    var create_info = Vk.c.VkDeviceCreateInfo{
        .sType = Vk.c.VkStructureType.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .queueCreateInfoCount = queue_create_info_count,
        .pQueueCreateInfos = &queue_create_infos,
        .pEnabledFeatures = &device_features,
        .enabledLayerCount = 0,
        .ppEnabledLayerNames = null,
        .enabledExtensionCount = 0,
        .ppEnabledExtensionNames = null,
    };
    if (USE_DEBUG_TOOLS) {
        create_info.enabledLayerCount = validation_layers.len;
        create_info.ppEnabledLayerNames = @ptrCast([*c]const [*:0]const u8, validation_layers.ptr);
    }
    var logical_device: Vk.Device = undefined;
    try checkVulkanResult(Vk.c.vkCreateDevice(physical_device, &create_info, null, @ptrCast(*Vk.c.VkDevice, &logical_device)));
    var graphics_queue: Vk.Queue = undefined;
    Vk.c.vkGetDeviceQueue(logical_device, graphics_family, 0, @ptrCast(*Vk.c.VkQueue, &graphics_queue));
    var transfer_queue: Vk.Queue = undefined;
    Vk.c.vkGetDeviceQueue(logical_device, transfer_family, 0, @ptrCast(*Vk.c.VkQueue, &transfer_queue));
    return DeviceAndQueues{
        .device = logical_device,
        .graphics_queue = .{ .handle = graphics_queue, .family_index = graphics_family, .queue_index = 0 },
        .transfer_queue = .{ .handle = transfer_queue, .family_index = transfer_family, .queue_index = 0 },
    };
}

test "render an empty image" {
    try glfw.init();
    defer glfw.deinit();
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyTestInstance(instance);
    const physical_device = try findPhysicalDeviceSuitableForGraphics(instance, testing.allocator);
    const device_and_queues = try createLogicalDeviceAndQueusForGraphics(physical_device, testing.allocator);
    defer destroyDevice(device_and_queues.device);

    // const render_pass = try createRenderPass(.VK_FORMAT_R8G8B8A8_UNORM, device_and_queues.device);
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

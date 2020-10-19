const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const glfw = @import("glfw_wrapper.zig");

usingnamespace @import("vulkan_general.zig");
usingnamespace @import("vulkan_surface.zig");
usingnamespace @import("vulkan_instance.zig");
usingnamespace @import("physical_device.zig");

pub const Queue = struct {
    handle: Vk.Queue,
    family_index: u16,
    queue_index: u16,

    pub fn createCommandPool(self: Queue, logical_device: Vk.Device, flags: Vk.c.VkCommandPoolCreateFlags) !Vk.CommandPool {
        const poolInfo = Vk.c.VkCommandPoolCreateInfo{
            .sType = .VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .pNext = null,
            .queueFamilyIndex = self.family_index,
            .flags = flags,
        };
        var command_pool: Vk.CommandPool = undefined;
        try checkVulkanResult(Vk.c.vkCreateCommandPool(logical_device, &poolInfo, null, @ptrCast(*Vk.c.VkCommandPool, &command_pool)));
        return command_pool;
    }

    pub fn submitSingle(self: Queue, wait_semaphores: []const Vk.Semaphore, command_buffers: []const Vk.CommandBuffer, signal_semaphores: []const Vk.Semaphore, stage_mask: ?u32) !void {
        const stage_mask_ptr = if (stage_mask != null) &stage_mask.? else null;
        const submit_info = Vk.c.VkSubmitInfo{
            .sType = .VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .pNext = null,
            .waitSemaphoreCount = @intCast(u32, wait_semaphores.len),
            .pWaitSemaphores = wait_semaphores.ptr,
            .pWaitDstStageMask = stage_mask_ptr,
            .commandBufferCount = @intCast(u32, command_buffers.len),
            .pCommandBuffers = command_buffers.ptr,
            .signalSemaphoreCount = @intCast(u32, signal_semaphores.len),
            .pSignalSemaphores = signal_semaphores.ptr,
        };
        try checkVulkanResult(Vk.c.vkQueueSubmit(self.handle, 1, &submit_info, null));
    }

    pub fn waitIdle(self: Queue) !void {
        try checkVulkanResult(Vk.c.vkQueueWaitIdle(self.handle));
    }

    pub fn present(self: Queue, wait_semaphores: []const Vk.Semaphore, swap_chains: []const Vk.SwapchainKHR, image_indices: []const u32) !void {
        std.debug.assert(swap_chains.len == image_indices.len);
        const present_info = Vk.c.VkPresentInfoKHR{
            .sType = .VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .pNext = null,
            .waitSemaphoreCount = @intCast(u32, wait_semaphores.len),
            .pWaitSemaphores = wait_semaphores.ptr,
            .swapchainCount = @intCast(u32, swap_chains.len),
            .pSwapchains = swap_chains.ptr,
            .pImageIndices = image_indices.ptr,
            .pResults = null, // Optional
        };
        try checkVulkanResult(Vk.c.vkQueuePresentKHR(self.handle, &present_info));
    }
};

pub const QueuesGPT = struct {
    graphics: Queue,
    present: Queue,
    transfer: Queue,
};

pub fn findTransferFamilyQueue(queue_familiy_properties: []const Vk.c.VkQueueFamilyProperties) ?u16 {
    var transfer_family: ?u16 = null;
    for (queue_familiy_properties) |properties, i| {
        // ----------------------------------------------------------
        // All commands that are allowed on a queue that supports transfer operations are also allowed on a queue that supports either graphics or compute operations.
        // Thus, if the capabilities of a queue family include VK_QUEUE_GRAPHICS_BIT or VK_QUEUE_COMPUTE_BIT, then reporting the VK_QUEUE_TRANSFER_BIT capability
        // separately for that queue family is optional
        // ----------------------------------------------------------
        // Thus we check if it has any of these capabilities and prefer a dedicated one
        if (properties.queueCount > 0 and (properties.queueFlags & @as(u32, Vk.c.VK_QUEUE_TRANSFER_BIT | Vk.c.VK_QUEUE_GRAPHICS_BIT | Vk.c.VK_QUEUE_COMPUTE_BIT)) != 0 and
            // prefer dedicated transfer queue
            (transfer_family == null or (properties.queueFlags & @as(u32, Vk.c.VK_QUEUE_GRAPHICS_BIT | Vk.c.VK_QUEUE_COMPUTE_BIT)) == 0))
        {
            transfer_family = @intCast(u16, i);
        }
    }
    return transfer_family;
}

pub fn createLogicalDeviceAndQueuesGPT(physical_device: Vk.PhysicalDevice, surface: Vk.c.VkSurfaceKHR, allocator: *mem.Allocator, logical_device: *Vk.Device, queues: *QueuesGPT) !void {
    const queue_familiy_properties = try getPhysicalDeviceQueueFamiliyPropeties(physical_device, allocator);
    defer allocator.free(queue_familiy_properties);
    const graphics_family = findGraphicsFamilyQueue(queue_familiy_properties).?;
    const present_family = (try findPresentFamilyQueue(physical_device, surface, queue_familiy_properties)).?;
    const transfer_family = findTransferFamilyQueue(queue_familiy_properties).?;

    var queue_create_infos: [3]Vk.c.VkDeviceQueueCreateInfo = undefined;
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
    if (graphics_family != present_family) {
        queue_create_info.queueFamilyIndex = present_family;
        queue_create_infos[queue_create_info_count] = queue_create_info;
        queue_create_info_count += 1;
    }

    if (graphics_family != transfer_family and present_family != transfer_family) {
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
        .enabledExtensionCount = 1,
        .ppEnabledExtensionNames = @ptrCast([*c]const [*:0]const u8, &Vk.c.VK_KHR_SWAPCHAIN_EXTENSION_NAME),
    };
    if (USE_DEBUG_TOOLS) {
        create_info.enabledLayerCount = validation_layers.len;
        create_info.ppEnabledLayerNames = @ptrCast([*c]const [*:0]const u8, validation_layers.ptr);
    }
    try checkVulkanResult(Vk.c.vkCreateDevice(physical_device, &create_info, null, @ptrCast(*Vk.c.VkDevice, logical_device)));
    Vk.c.vkGetDeviceQueue(logical_device.*, graphics_family, 0, @ptrCast(*Vk.c.VkQueue, &queues.graphics));
    Vk.c.vkGetDeviceQueue(logical_device.*, present_family, 0, @ptrCast(*Vk.c.VkQueue, &queues.present));
    Vk.c.vkGetDeviceQueue(logical_device.*, transfer_family, 0, @ptrCast(*Vk.c.VkQueue, &queues.transfer));
    queues.graphics.family_index = graphics_family;
    queues.present.family_index = present_family;
    queues.transfer.family_index = transfer_family;
    queues.graphics.queue_index = 0;
    queues.present.queue_index = 0;
    queues.transfer.queue_index = 0;
}

pub fn destroyDevice(device: Vk.c.VkDevice) void {
    Vk.c.vkDestroyDevice(device, null);
}

test "Creating logical device and queues for graphics and present should succeed on my pc" {
    try glfw.init();
    defer glfw.deinit();
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyTestInstance(instance);
    const window = try @import("window.zig").Window.init(10, 10, "");
    defer window.deinit();
    const surface = try createSurface(instance, window.handle);
    defer destroySurface(instance, surface);
    const physical_device = try findPhysicalDeviceSuitableForGraphicsAndPresenting(instance, surface, testing.allocator);

    var logical_device: Vk.Device = undefined;
    var queues: QueuesGPT = .{ .graphics = undefined, .present = undefined, .transfer = undefined };
    try createLogicalDeviceAndQueuesGPT(physical_device, surface, testing.allocator, &logical_device, &queues);
    defer destroyDevice(logical_device);

    // testing.expect(logical_device != null);
    // testing.expect(queues.graphics != null);
    // testing.expect(queues.present != null);
    // testing.expect(queues.transfer != null);
}

pub const DeviceAndQueues = struct {
    device: Vk.Device,
    graphics_queue: Queue,
    transfer_queue: Queue,
};

pub fn createLogicalDeviceAndQueusForGraphics(physical_device: Vk.PhysicalDevice, allocator: *mem.Allocator) !DeviceAndQueues {
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

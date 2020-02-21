const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;
const testing = std.testing;

usingnamespace @import("vulkan_general.zig");
usingnamespace @import("vulkan_instance.zig");
usingnamespace @import("glfw_vulkan_window.zig");

const CoreGraphicsDeviceData = struct {
    physical_device: vulkan_c.VkPhysicalDevice = null,
    logical_device: vulkan_c.VkPhysicalDevice = null,
    queues: Queues = .{.graphics_queue=null, .graphics_queue_index=undefined, .present_queue=null, .present_queue_index=undefined, .transfer_queue=null, .transfer_queue_index=undefined},
};

// the caller owns the returned memory and is responsible for freeing it.
fn getPhysicalDeviceQueueFamiliyPropeties(device: vulkan_c.VkPhysicalDevice, allocator: *mem.Allocator) ![]vulkan_c.VkQueueFamilyProperties {
    var queue_family_count : u32 = undefined;
    vulkan_c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);
    const queue_familiy_properties = try allocator.alloc(vulkan_c.VkQueueFamilyProperties, queue_family_count);
    vulkan_c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_familiy_properties.ptr);
    return queue_familiy_properties;
}

fn findGraphicsFamilyQueue(queue_familiy_properties: []const vulkan_c.VkQueueFamilyProperties) ?u16 {
    for (queue_familiy_properties) |properties, i| {
        if (queue_familiy_properties[i].queueCount > 0 and (queue_familiy_properties[i].queueFlags & @as(u32, vulkan_c.VK_QUEUE_GRAPHICS_BIT)) != 0) {
            return @intCast(u16, i);
        }
    }
    return null;
}

fn findPresentFamilyQueue(device: vulkan_c.VkPhysicalDevice, surface: vulkan_c.VkSurfaceKHR, queue_familiy_properties: []const vulkan_c.VkQueueFamilyProperties) !?u16 {
    var present_family: ?u16 = null;
    for (queue_familiy_properties) |properties, i| {
        var present_support : u32 = undefined;
        try checkVulkanResult(vulkan_c.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(u32, i), surface, &present_support));
        if (properties.queueCount > 0 and present_support != 0) {
            return @intCast(u16, i);
        }
    }
    return null;
}

fn hasSuitableDeviceQueueFamilies(device: vulkan_c.VkPhysicalDevice, surface: vulkan_c.VkSurfaceKHR, allocator: *mem.Allocator) !bool {
    const queue_familiy_properties = try getPhysicalDeviceQueueFamiliyPropeties(device, allocator);
    defer allocator.free(queue_familiy_properties);
    return findGraphicsFamilyQueue(queue_familiy_properties) != null and (try findPresentFamilyQueue(device, surface, queue_familiy_properties)) != null;
}

fn containsSwapChainExtension(available_extensions: []const vulkan_c.VkExtensionProperties) bool {
    for (available_extensions) |extension| {
        if (std.cstr.cmp(@ptrCast([*:0]const u8, &extension.extensionName), vulkan_c.VK_KHR_SWAPCHAIN_EXTENSION_NAME) == 0) {
            return true;
        }
    }
    return false;
}

fn hasAdequateSwapChain(device: vulkan_c.VkPhysicalDevice, surface: vulkan_c.VkSurfaceKHR, allocator: *mem.Allocator) !bool {
    var extension_count : u32 = undefined;
    try checkVulkanResult(vulkan_c.vkEnumerateDeviceExtensionProperties(device, null, &extension_count, null));
    const available_extensions = try allocator.alloc(vulkan_c.VkExtensionProperties, extension_count);
    defer allocator.free(available_extensions);
    try checkVulkanResult(vulkan_c.vkEnumerateDeviceExtensionProperties(device, null, &extension_count, available_extensions.ptr));
    if (containsSwapChainExtension(available_extensions)) {
        var capabilities: vulkan_c.VkSurfaceCapabilitiesKHR = undefined;
        try checkVulkanResult(vulkan_c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &capabilities));
        var surface_format_count : u32 = undefined;
        try checkVulkanResult(vulkan_c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &surface_format_count, null));
        var present_mode_count: u32 = undefined;
        try checkVulkanResult(vulkan_c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, null));
        return surface_format_count > 0 and present_mode_count > 0;
    }
    return false;
}

fn isDeviceSuitableForGraphicsAndPresentation(device: vulkan_c.VkPhysicalDevice, surface: vulkan_c.VkSurfaceKHR, allocator: *mem.Allocator) !bool {
    var deviceProperties: vulkan_c.VkPhysicalDeviceProperties = undefined;
    vulkan_c.vkGetPhysicalDeviceProperties(device, &deviceProperties);
    var deviceFeatures : vulkan_c.VkPhysicalDeviceFeatures = undefined;
    vulkan_c.vkGetPhysicalDeviceFeatures(device, &deviceFeatures);

    return (try hasSuitableDeviceQueueFamilies(device, surface, allocator)) and hasAdequateSwapChain(device, surface, allocator);
}

pub fn findPhysicalDeviceSuitableForGraphicsAndPresenting(instance: vulkan_c.VkInstance, surface: vulkan_c.VkSurfaceKHR, allocator: *mem.Allocator) !std.meta.Child(vulkan_c.VkPhysicalDevice) {
    var device_count : u32 = 0;
    try checkVulkanResult(vulkan_c.vkEnumeratePhysicalDevices(instance, &device_count, null));
    if (device_count == 0) {
        return error.NoDeviceWithVulkanSupportFound;
    }
    const devices = try allocator.alloc(std.meta.Child(vulkan_c.VkPhysicalDevice), device_count);
    defer allocator.free(devices);
    try checkVulkanResult(vulkan_c.vkEnumeratePhysicalDevices(instance, &device_count, @ptrCast([*c]vulkan_c.VkPhysicalDevice, devices.ptr)));
    for (devices) |device| {
        if (try isDeviceSuitableForGraphicsAndPresentation(device, surface, allocator)) {
            return device;
        }
    }
    return error.FailedToFindSuitableVulkanDevice;
}

test "finding a physical device suitable for graphics and presenting should succeed on my pc" {
    try glfw.init();
    defer glfw.deinit();
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyInstance(instance, null);
    const window = try Window.init(10, 10, "", instance);
    defer window.deinit(instance);
    _ = try findPhysicalDeviceSuitableForGraphicsAndPresenting(instance, window.surface, testing.allocator);
}

const Queues = struct {
    graphics_queue: vulkan_c.VkQueue,
    graphics_queue_index: u32,
    present_queue: vulkan_c.VkQueue,
    present_queue_index: u32,
    transfer_queue: vulkan_c.VkQueue,
    transfer_queue_index: u32,
};

fn findTransferFamilyQueue(queue_familiy_properties: []const vulkan_c.VkQueueFamilyProperties) ?u16 {
    var transfer_family: ?u16 = null;
    for (queue_familiy_properties) |properties, i| {
        // ----------------------------------------------------------
        // All commands that are allowed on a queue that supports transfer operations are also allowed on a queue that supports either graphics or compute operations.
        // Thus, if the capabilities of a queue family include VK_QUEUE_GRAPHICS_BIT or VK_QUEUE_COMPUTE_BIT, then reporting the VK_QUEUE_TRANSFER_BIT capability
        // separately for that queue family is optional
        // ----------------------------------------------------------
        // Thus we check if it has any of these capabilities and prefer a dedicated one
        if (properties.queueCount > 0 and (properties.queueFlags & @as(u32, vulkan_c.VK_QUEUE_TRANSFER_BIT | vulkan_c.VK_QUEUE_GRAPHICS_BIT | vulkan_c.VK_QUEUE_COMPUTE_BIT)) != 0 and
            // prefer dedicated transfer queue
            (transfer_family == null or (properties.queueFlags & @as(u32, vulkan_c.VK_QUEUE_GRAPHICS_BIT | vulkan_c.VK_QUEUE_COMPUTE_BIT)) == 0)) {
            transfer_family = @intCast(u16, i);
        }
    }
    return transfer_family;
}

fn createLogicalDeviceAndQueues(physical_device: vulkan_c.VkPhysicalDevice, surface: vulkan_c.VkSurfaceKHR, allocator: *mem.Allocator, logical_device: *vulkan_c.VkDevice, queues: *Queues) !void {
    const queue_familiy_properties = try getPhysicalDeviceQueueFamiliyPropeties(physical_device, allocator);
    defer allocator.free(queue_familiy_properties);
    const graphics_family = findGraphicsFamilyQueue(queue_familiy_properties).?;
    const present_family = (try findPresentFamilyQueue(physical_device, surface, queue_familiy_properties)).?;
    const transfer_family = findTransferFamilyQueue(queue_familiy_properties).?;

    var queue_create_infos: [3]vulkan_c.VkDeviceQueueCreateInfo = undefined;
    const queue_priority: f32 = 1;
    var queue_create_info = vulkan_c.VkDeviceQueueCreateInfo{
        .sType=vulkan_c.VkStructureType.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .pNext=null,
        .flags=0,
        .queueFamilyIndex=graphics_family,
        .queueCount=1,
        .pQueuePriorities=&queue_priority,
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
    const device_features = std.mem.zeroes(vulkan_c.VkPhysicalDeviceFeatures);

    var create_info = vulkan_c.VkDeviceCreateInfo{
        .sType=vulkan_c.VkStructureType.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext=null,
        .flags=0,
        .queueCreateInfoCount=queue_create_info_count,
        .pQueueCreateInfos=&queue_create_infos,
        .pEnabledFeatures=&device_features,
        .enabledLayerCount=0,
        .ppEnabledLayerNames=null,
        .enabledExtensionCount=1,
        .ppEnabledExtensionNames=@ptrCast([*c]const [*:0]const u8, &vulkan_c.VK_KHR_SWAPCHAIN_EXTENSION_NAME),
    };
    if (USE_DEBUG_TOOLS) {
        create_info.enabledLayerCount=validation_layers.len;
        create_info.ppEnabledLayerNames=@ptrCast([*c]const [*:0]const u8, validation_layers.ptr);
    }
    try checkVulkanResult(vulkan_c.vkCreateDevice(physical_device, &create_info, null, logical_device));
    vulkan_c.vkGetDeviceQueue(logical_device.*, graphics_family, 0, &queues.graphics_queue);
    vulkan_c.vkGetDeviceQueue(logical_device.*, present_family, 0, &queues.present_queue);
    vulkan_c.vkGetDeviceQueue(logical_device.*, transfer_family, 0, &queues.transfer_queue);
    queues.graphics_queue_index = graphics_family;
    queues.present_queue_index = present_family;
    queues.transfer_queue_index = transfer_family;
}

fn destroyDevice(device: vulkan_c.VkDevice) void {
    vulkan_c.vkDestroyDevice(device, null);
}

test "Creating logical device and queues should succeed on my pc" {
    try glfw.init();
    defer glfw.deinit();
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyInstance(instance, null);
    const window = try Window.init(10, 10, "", instance);
    defer window.deinit(instance);
    const physical_device = try findPhysicalDeviceSuitableForGraphicsAndPresenting(instance, window.surface, testing.allocator);

    var logical_device: vulkan_c.VkDevice = null;
    const invalid_index = std.math.maxInt(u32);
    var queues: Queues = .{.graphics_queue=null, .graphics_queue_index=invalid_index, .present_queue=null, .present_queue_index=invalid_index, .transfer_queue=null, .transfer_queue_index=invalid_index};
    try createLogicalDeviceAndQueues(physical_device, window.surface, testing.allocator, &logical_device, &queues);
    defer destroyDevice(logical_device);

    testing.expect(logical_device != null);
    testing.expect(queues.graphics_queue != null);
    testing.expect(queues.graphics_queue_index != invalid_index);
    testing.expect(queues.present_queue != null);
    testing.expect(queues.present_queue_index != invalid_index);
    testing.expect(queues.transfer_queue != null);
    testing.expect(queues.transfer_queue_index != invalid_index);
}

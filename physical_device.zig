const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const glfw = @import("glfw_wrapper.zig");

usingnamespace @import("vulkan_general.zig");

pub fn getPhysicalDeviceProperties(physical_device: Vk.PhysicalDevice) Vk.c.VkPhysicalDeviceProperties {
    var device_properties: Vk.c.VkPhysicalDeviceProperties = undefined;
    Vk.c.vkGetPhysicalDeviceProperties(physical_device, &device_properties);
    return device_properties;
}

// the caller owns the returned memory and is responsible for freeing it.
pub fn getPhysicalDeviceQueueFamiliyPropeties(device: Vk.c.VkPhysicalDevice, allocator: *mem.Allocator) ![]Vk.c.VkQueueFamilyProperties {
    var queue_family_count: u32 = undefined;
    Vk.c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);
    const queue_familiy_properties = try allocator.alloc(Vk.c.VkQueueFamilyProperties, queue_family_count);
    Vk.c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_familiy_properties.ptr);
    return queue_familiy_properties;
}

pub fn findGraphicsFamilyQueue(queue_familiy_properties: []const Vk.c.VkQueueFamilyProperties) ?u16 {
    for (queue_familiy_properties) |properties, i| {
        if (queue_familiy_properties[i].queueCount > 0 and (queue_familiy_properties[i].queueFlags & @as(u32, Vk.c.VK_QUEUE_GRAPHICS_BIT)) != 0) {
            return @intCast(u16, i);
        }
    }
    return null;
}

pub fn findPresentFamilyQueue(device: Vk.c.VkPhysicalDevice, surface: Vk.c.VkSurfaceKHR, queue_familiy_properties: []const Vk.c.VkQueueFamilyProperties) !?u16 {
    var present_family: ?u16 = null;
    for (queue_familiy_properties) |properties, i| {
        var present_support: u32 = undefined;
        try checkVulkanResult(Vk.c.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(u32, i), surface, &present_support));
        if (properties.queueCount > 0 and present_support != 0) {
            return @intCast(u16, i);
        }
    }
    return null;
}

fn hasGraphicsAndPresentQueueFamilies(device: Vk.c.VkPhysicalDevice, surface: Vk.c.VkSurfaceKHR, allocator: *mem.Allocator) !bool {
    const queue_familiy_properties = try getPhysicalDeviceQueueFamiliyPropeties(device, allocator);
    defer allocator.free(queue_familiy_properties);
    return findGraphicsFamilyQueue(queue_familiy_properties) != null and (try findPresentFamilyQueue(device, surface, queue_familiy_properties)) != null;
}

fn isDeviceSuitableForGraphicsAndPresentation(device: Vk.PhysicalDevice, surface: Vk.SurfaceKHR, allocator: *mem.Allocator) !bool {
    const deviceProperties = getPhysicalDeviceProperties(device);
    var deviceFeatures: Vk.c.VkPhysicalDeviceFeatures = undefined;
    Vk.c.vkGetPhysicalDeviceFeatures(device, &deviceFeatures);

    return (try hasGraphicsAndPresentQueueFamilies(device, surface, allocator)) and hasAdequateSwapChain(device, surface, allocator);
}

fn containsSwapChainExtension(available_extensions: []const Vk.c.VkExtensionProperties) bool {
    for (available_extensions) |extension| {
        if (std.cstr.cmp(@ptrCast([*:0]const u8, &extension.extensionName), Vk.c.VK_KHR_SWAPCHAIN_EXTENSION_NAME) == 0) {
            return true;
        }
    }
    return false;
}

fn hasAdequateSwapChain(device: Vk.c.VkPhysicalDevice, surface: Vk.c.VkSurfaceKHR, allocator: *mem.Allocator) !bool {
    var extension_count: u32 = undefined;
    try checkVulkanResult(Vk.c.vkEnumerateDeviceExtensionProperties(device, null, &extension_count, null));
    const available_extensions = try allocator.alloc(Vk.c.VkExtensionProperties, extension_count);
    defer allocator.free(available_extensions);
    try checkVulkanResult(Vk.c.vkEnumerateDeviceExtensionProperties(device, null, &extension_count, available_extensions.ptr));
    if (containsSwapChainExtension(available_extensions)) {
        var capabilities: Vk.c.VkSurfaceCapabilitiesKHR = undefined;
        try checkVulkanResult(Vk.c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &capabilities));
        var surface_format_count: u32 = undefined;
        try checkVulkanResult(Vk.c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &surface_format_count, null));
        var present_mode_count: u32 = undefined;
        try checkVulkanResult(Vk.c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, null));
        return surface_format_count > 0 and present_mode_count > 0;
    }
    return false;
}

fn hasDeviceHostVisibleLocalMemory(device: Vk.PhysicalDevice) bool {
    var memory_properties: Vk.c.VkPhysicalDeviceMemoryProperties = undefined;
    Vk.c.vkGetPhysicalDeviceMemoryProperties(device, &memory_properties);
    var i: u32 = 0;
    while (i < memory_properties.memoryTypeCount) : (i += 1) {
        const local_and_host_visible = @as(u32, (Vk.c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT | Vk.c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT));
        if ((memory_properties.memoryTypes[i].propertyFlags & local_and_host_visible) == local_and_host_visible) {
            return true;
        }
    }
    return false;
}

pub fn findPhysicalDeviceSuitableForGraphicsAndPresenting(instance: Vk.Instance, surface: Vk.SurfaceKHR, allocator: *mem.Allocator) !Vk.PhysicalDevice {
    var device_count: u32 = 0;
    try checkVulkanResult(Vk.c.vkEnumeratePhysicalDevices(instance, &device_count, null));
    if (device_count == 0) {
        return error.NoDeviceWithVulkanSupportFound;
    }
    const devices = try allocator.alloc(Vk.PhysicalDevice, device_count);
    defer allocator.free(devices);
    try checkVulkanResult(Vk.c.vkEnumeratePhysicalDevices(instance, &device_count, @ptrCast([*]Vk.c.VkPhysicalDevice, devices.ptr)));
    for (devices) |device| {
        if ((try isDeviceSuitableForGraphicsAndPresentation(device, surface, allocator)) and hasDeviceHostVisibleLocalMemory(device)) {
            return device;
        }
    }
    return error.FailedToFindSuitableVulkanDevice;
}

pub fn findPhysicalDeviceSuitableForGraphics(instance: Vk.Instance, allocator: *mem.Allocator) !Vk.PhysicalDevice {
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

usingnamespace @import("vulkan_instance.zig");
usingnamespace @import("window.zig");
usingnamespace @import("vulkan_surface.zig");

test "finding a physical device suitable for graphics should succeed on my pc" {
    try glfw.init();
    defer glfw.deinit();
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyTestInstance(instance);
    _ = try findPhysicalDeviceSuitableForGraphics(instance, testing.allocator);
}

test "finding a physical device suitable for graphics and presenting should succeed on my pc" {
    try glfw.init();
    defer glfw.deinit();
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyTestInstance(instance);
    const window = try Window.init(10, 10, "");
    defer window.deinit();
    const surface = try createSurface(instance, window.handle);
    defer destroySurface(instance, surface);
    _ = try findPhysicalDeviceSuitableForGraphicsAndPresenting(instance, surface, testing.allocator);
}

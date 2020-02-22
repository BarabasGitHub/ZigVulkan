const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const glfw = @import("glfw_wrapper.zig");

usingnamespace @import("vulkan_general.zig");
usingnamespace @import("vulkan_instance.zig");
usingnamespace @import("glfw_vulkan_window.zig");

// the caller owns the returned memory and is responsible for freeing it.
fn getPhysicalDeviceQueueFamiliyPropeties(device: Vk.c.VkPhysicalDevice, allocator: *mem.Allocator) ![]Vk.c.VkQueueFamilyProperties {
    var queue_family_count : u32 = undefined;
    Vk.c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);
    const queue_familiy_properties = try allocator.alloc(Vk.c.VkQueueFamilyProperties, queue_family_count);
    Vk.c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_familiy_properties.ptr);
    return queue_familiy_properties;
}

fn findGraphicsFamilyQueue(queue_familiy_properties: []const Vk.c.VkQueueFamilyProperties) ?u16 {
    for (queue_familiy_properties) |properties, i| {
        if (queue_familiy_properties[i].queueCount > 0 and (queue_familiy_properties[i].queueFlags & @as(u32, Vk.c.VK_QUEUE_GRAPHICS_BIT)) != 0) {
            return @intCast(u16, i);
        }
    }
    return null;
}

fn findPresentFamilyQueue(device: Vk.c.VkPhysicalDevice, surface: Vk.c.VkSurfaceKHR, queue_familiy_properties: []const Vk.c.VkQueueFamilyProperties) !?u16 {
    var present_family: ?u16 = null;
    for (queue_familiy_properties) |properties, i| {
        var present_support : u32 = undefined;
        try checkVulkanResult(Vk.c.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(u32, i), surface, &present_support));
        if (properties.queueCount > 0 and present_support != 0) {
            return @intCast(u16, i);
        }
    }
    return null;
}

fn hasSuitableDeviceQueueFamilies(device: Vk.c.VkPhysicalDevice, surface: Vk.c.VkSurfaceKHR, allocator: *mem.Allocator) !bool {
    const queue_familiy_properties = try getPhysicalDeviceQueueFamiliyPropeties(device, allocator);
    defer allocator.free(queue_familiy_properties);
    return findGraphicsFamilyQueue(queue_familiy_properties) != null and (try findPresentFamilyQueue(device, surface, queue_familiy_properties)) != null;
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
    var extension_count : u32 = undefined;
    try checkVulkanResult(Vk.c.vkEnumerateDeviceExtensionProperties(device, null, &extension_count, null));
    const available_extensions = try allocator.alloc(Vk.c.VkExtensionProperties, extension_count);
    defer allocator.free(available_extensions);
    try checkVulkanResult(Vk.c.vkEnumerateDeviceExtensionProperties(device, null, &extension_count, available_extensions.ptr));
    if (containsSwapChainExtension(available_extensions)) {
        var capabilities: Vk.c.VkSurfaceCapabilitiesKHR = undefined;
        try checkVulkanResult(Vk.c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &capabilities));
        var surface_format_count : u32 = undefined;
        try checkVulkanResult(Vk.c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &surface_format_count, null));
        var present_mode_count: u32 = undefined;
        try checkVulkanResult(Vk.c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, null));
        return surface_format_count > 0 and present_mode_count > 0;
    }
    return false;
}

fn isDeviceSuitableForGraphicsAndPresentation(device: Vk.c.VkPhysicalDevice, surface: Vk.c.VkSurfaceKHR, allocator: *mem.Allocator) !bool {
    var deviceProperties: Vk.c.VkPhysicalDeviceProperties = undefined;
    Vk.c.vkGetPhysicalDeviceProperties(device, &deviceProperties);
    var deviceFeatures : Vk.c.VkPhysicalDeviceFeatures = undefined;
    Vk.c.vkGetPhysicalDeviceFeatures(device, &deviceFeatures);

    return (try hasSuitableDeviceQueueFamilies(device, surface, allocator)) and hasAdequateSwapChain(device, surface, allocator);
}

pub fn findPhysicalDeviceSuitableForGraphicsAndPresenting(instance: Vk.c.VkInstance, surface: Vk.c.VkSurfaceKHR, allocator: *mem.Allocator) !Vk.PhysicalDevice {
    var device_count : u32 = 0;
    try checkVulkanResult(Vk.c.vkEnumeratePhysicalDevices(instance, &device_count, null));
    if (device_count == 0) {
        return error.NoDeviceWithVulkanSupportFound;
    }
    const devices = try allocator.alloc(Vk.PhysicalDevice, device_count);
    defer allocator.free(devices);
    try checkVulkanResult(Vk.c.vkEnumeratePhysicalDevices(instance, &device_count, @ptrCast([*c]Vk.c.VkPhysicalDevice, devices.ptr)));
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

pub const Queues = struct {
    graphics: std.meta.Child(Vk.c.VkQueue),
    graphics_index: u16,
    present: std.meta.Child(Vk.c.VkQueue),
    present_index: u16,
    transfer: std.meta.Child(Vk.c.VkQueue),
    transfer_index: u16,
};

fn findTransferFamilyQueue(queue_familiy_properties: []const Vk.c.VkQueueFamilyProperties) ?u16 {
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
            (transfer_family == null or (properties.queueFlags & @as(u32, Vk.c.VK_QUEUE_GRAPHICS_BIT | Vk.c.VK_QUEUE_COMPUTE_BIT)) == 0)) {
            transfer_family = @intCast(u16, i);
        }
    }
    return transfer_family;
}

fn createLogicalDeviceAndQueues(physical_device: Vk.c.VkPhysicalDevice, surface: Vk.c.VkSurfaceKHR, allocator: *mem.Allocator, logical_device: *std.meta.Child(Vk.c.VkDevice), queues: *Queues) !void {
    const queue_familiy_properties = try getPhysicalDeviceQueueFamiliyPropeties(physical_device, allocator);
    defer allocator.free(queue_familiy_properties);
    const graphics_family = findGraphicsFamilyQueue(queue_familiy_properties).?;
    const present_family = (try findPresentFamilyQueue(physical_device, surface, queue_familiy_properties)).?;
    const transfer_family = findTransferFamilyQueue(queue_familiy_properties).?;

    var queue_create_infos: [3]Vk.c.VkDeviceQueueCreateInfo = undefined;
    const queue_priority: f32 = 1;
    var queue_create_info = Vk.c.VkDeviceQueueCreateInfo{
        .sType=Vk.c.VkStructureType.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
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
    const device_features = std.mem.zeroes(Vk.c.VkPhysicalDeviceFeatures);

    var create_info = Vk.c.VkDeviceCreateInfo{
        .sType=Vk.c.VkStructureType.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext=null,
        .flags=0,
        .queueCreateInfoCount=queue_create_info_count,
        .pQueueCreateInfos=&queue_create_infos,
        .pEnabledFeatures=&device_features,
        .enabledLayerCount=0,
        .ppEnabledLayerNames=null,
        .enabledExtensionCount=1,
        .ppEnabledExtensionNames=@ptrCast([*c]const [*:0]const u8, &Vk.c.VK_KHR_SWAPCHAIN_EXTENSION_NAME),
    };
    if (USE_DEBUG_TOOLS) {
        create_info.enabledLayerCount=validation_layers.len;
        create_info.ppEnabledLayerNames=@ptrCast([*c]const [*:0]const u8, validation_layers.ptr);
    }
    try checkVulkanResult(Vk.c.vkCreateDevice(physical_device, &create_info, null, @ptrCast(*Vk.c.VkDevice, logical_device)));
    Vk.c.vkGetDeviceQueue(logical_device.*, graphics_family, 0, @ptrCast(*Vk.c.VkQueue, &queues.graphics));
    Vk.c.vkGetDeviceQueue(logical_device.*, present_family, 0, @ptrCast(*Vk.c.VkQueue, &queues.present));
    Vk.c.vkGetDeviceQueue(logical_device.*, transfer_family, 0, @ptrCast(*Vk.c.VkQueue, &queues.transfer));
    queues.graphics_index = graphics_family;
    queues.present_index = present_family;
    queues.transfer_index = transfer_family;
}

fn destroyDevice(device: Vk.c.VkDevice) void {
    Vk.c.vkDestroyDevice(device, null);
}

test "Creating logical device and queues should succeed on my pc" {
    try glfw.init();
    defer glfw.deinit();
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyInstance(instance, null);
    const window = try Window.init(10, 10, "", instance);
    defer window.deinit(instance);
    const physical_device = try findPhysicalDeviceSuitableForGraphicsAndPresenting(instance, window.surface, testing.allocator);

    var logical_device: std.meta.Child(Vk.c.VkDevice) = undefined;
    const invalid_index = std.math.maxInt(u16);
    var queues: Queues = .{.graphics=undefined, .graphics_index=invalid_index, .present=undefined, .present_index=invalid_index, .transfer=undefined, .transfer_index=invalid_index};
    try createLogicalDeviceAndQueues(physical_device, window.surface, testing.allocator, &logical_device, &queues);
    defer destroyDevice(logical_device);

    // testing.expect(logical_device != null);
    // testing.expect(queues.graphics != null);
    testing.expect(queues.graphics_index != invalid_index);
    // testing.expect(queues.present != null);
    testing.expect(queues.present_index != invalid_index);
    // testing.expect(queues.transfer != null);
    testing.expect(queues.transfer_index != invalid_index);
}

pub const SwapChainData = struct {
    const Self = @This();

    allocator: *mem.Allocator,
    swap_chain: Vk.c.VkSwapchainKHR,
    images: []const Vk.c.VkImage,
    views: []const Vk.c.VkImageView,
    surface_format: Vk.c.VkSurfaceFormatKHR,
    extent: Vk.c.VkExtent2D,

    pub fn init(window: Window, physical_device: Vk.c.VkPhysicalDevice, logical_device: Vk.c.VkDevice, graphics_queue_index: u16, present_queue_index: u16, allocator: *mem.Allocator) !SwapChainData {
        return createSwapChain(window, physical_device, logical_device, graphics_queue_index, present_queue_index, allocator);
    }

    pub fn deinit(self: Self, logical_device: Vk.c.VkDevice) void {
        for (self.views)|view|{
            Vk.c.vkDestroyImageView(logical_device, view, null);
        }
        self.allocator.free(self.images);
        self.allocator.free(self.views);
        Vk.c.vkDestroySwapchainKHR(logical_device, self.swap_chain, null);
    }
};

fn chooseSwapSurfaceFormat(surface: Vk.c.VkSurfaceKHR, physical_device: Vk.c.VkPhysicalDevice, allocator: *mem.Allocator) !Vk.c.VkSurfaceFormatKHR {
    var surface_format_count : u32 = undefined;
    try checkVulkanResult(Vk.c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &surface_format_count, null));
    const surface_formats = try allocator.alloc(Vk.c.VkSurfaceFormatKHR, surface_format_count);
    defer allocator.free(surface_formats);
    try checkVulkanResult(Vk.c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &surface_format_count, surface_formats.ptr));

    // TODO: make it possible to specify what format(s) you prefer
    for (surface_formats) |available_format| {
        if (available_format.format == .VK_FORMAT_B8G8R8A8_UNORM and available_format.colorSpace == .VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            return available_format;
        }
    }
    // if we don't find the one we like, just pick the first one
    return surface_formats[0];
}

fn chooseSwapExtent(capabilities: Vk.c.VkSurfaceCapabilitiesKHR, window: Window) !Vk.c.VkExtent2D {
    // if we get some extent, use it
    if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return Vk.c.VkExtent2D{.width=std.math.max(@as(u32, 1), capabilities.currentExtent.width), .height=std.math.max(1, capabilities.currentExtent.height)};
    } else {
        // otherwise pick something
        var actual_extent = try window.getSize();
        actual_extent.width = std.math.max(1, std.math.clamp(actual_extent.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width));
        actual_extent.height = std.math.max(1, std.math.clamp(actual_extent.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height));

        return actual_extent;
    }
}


fn chooseSwapPresentMode(surface: Vk.c.VkSurfaceKHR, physical_device: Vk.c.VkPhysicalDevice, allocator: *mem.Allocator) !Vk.c.VkPresentModeKHR {
    var present_mode_count : u32 = undefined;
    try checkVulkanResult(Vk.c.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &present_mode_count, null));
    const present_modes = try allocator.alloc(Vk.c.VkPresentModeKHR, present_mode_count);
    defer allocator.free(present_modes);
    try checkVulkanResult(Vk.c.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &present_mode_count, present_modes.ptr));
    for (present_modes) |present_mode| {
        // preferred
        if (present_mode == .VK_PRESENT_MODE_MAILBOX_KHR) {
            return present_mode;
        }
    }
    // default
    return .VK_PRESENT_MODE_FIFO_KHR;
}

fn getSwapChainImages(logical_device: Vk.c.VkDevice, swap_chain: Vk.c.VkSwapchainKHR, allocator: *mem.Allocator) ![]Vk.c.VkImage {
    var image_count : u32 = undefined;
    try checkVulkanResult(Vk.c.vkGetSwapchainImagesKHR(logical_device, swap_chain, &image_count, null));
    const images = try allocator.alloc(Vk.c.VkImage, image_count);
    errdefer allocator.free(images);
    try checkVulkanResult(Vk.c.vkGetSwapchainImagesKHR(logical_device, swap_chain, &image_count, images.ptr));
    return images;
}

fn createSwapChainImageViews(logical_device: Vk.c.VkDevice, images: []const Vk.c.VkImage, format: Vk.c.VkFormat, allocator: *mem.Allocator) ![] Vk.c.VkImageView {
    const image_views = try allocator.alloc(Vk.c.VkImageView, images.len);
    errdefer allocator.free(image_views);
    for (images) |image, i| {
        const create_info = Vk.c.VkImageViewCreateInfo{
            .sType=.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext=null,
            .flags=0,
            .image=image,
            .viewType=.VK_IMAGE_VIEW_TYPE_2D,
            .format=format,

            .components=.{
                .r=.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g=.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b=.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a=.VK_COMPONENT_SWIZZLE_IDENTITY,
                },

            .subresourceRange=.{
                .aspectMask=Vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel=0,
                .levelCount=1,
                .baseArrayLayer=0,
                .layerCount=Vk.c.VK_REMAINING_ARRAY_LAYERS,
            },
        };
        try checkVulkanResult(Vk.c.vkCreateImageView(logical_device, &create_info, null, &image_views[i]));
    }
    return image_views;
}

fn createSwapChain(window: Window, physical_device: Vk.c.VkPhysicalDevice, logical_device: Vk.c.VkDevice, graphics_queue_index: u16, present_queue_index: u16, allocator: *mem.Allocator) !SwapChainData {
    const surface_format = try chooseSwapSurfaceFormat(window.surface, physical_device, allocator);

    var capabilities: Vk.c.VkSurfaceCapabilitiesKHR = undefined;
    try checkVulkanResult(Vk.c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, window.surface, &capabilities));

    var create_info = Vk.c.VkSwapchainCreateInfoKHR{
        .sType=.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .pNext=null,
        .flags=0,
        .surface=window.surface,
        // try to get one more so we can have triple buffering
        // maxImageCount == 0 means unlimited, so subtract 1 to get uint32_t(-1) and then add one again, because we want one more than the minimum anyway
        .minImageCount=std.math.min(capabilities.minImageCount, capabilities.maxImageCount - 1) + 1,
        .imageFormat=surface_format.format,
        .imageColorSpace=surface_format.colorSpace,
        .imageExtent=try chooseSwapExtent(capabilities, window),
        .imageArrayLayers=1,
        .imageUsage=Vk.c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .imageSharingMode=.VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount=0, // Optional
        .pQueueFamilyIndices=null, // Optional
        .preTransform=capabilities.currentTransform,
        .compositeAlpha=.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode=try chooseSwapPresentMode(window.surface, physical_device, allocator),
        .clipped=@boolToInt(true),
        .oldSwapchain=null,
    };
    const queueFamilyIndices = [_]u32{graphics_queue_index, present_queue_index};
    // if they're not the same share using concurrent for now
    if (graphics_queue_index != present_queue_index)
    {
        create_info.imageSharingMode=.VK_SHARING_MODE_CONCURRENT;
        create_info.queueFamilyIndexCount=2;
        create_info.pQueueFamilyIndices=&queueFamilyIndices;
    }
    var swap_chain: Vk.c.VkSwapchainKHR = undefined;
    errdefer Vk.c.vkDestroySwapchainKHR(logical_device, swap_chain, null);
    try checkVulkanResult(Vk.c.vkCreateSwapchainKHR(logical_device, &create_info, null, &swap_chain));
    const images = try getSwapChainImages(logical_device, swap_chain, allocator);
    errdefer allocator.free(images);
    const image_views = try createSwapChainImageViews(logical_device, images, surface_format.format, allocator);
    return SwapChainData{.allocator=allocator, .swap_chain=swap_chain, .images=images, .views=image_views, .surface_format=surface_format, .extent=create_info.imageExtent,};
}

test "Creating a swap chain should succeed on my pc" {
    try glfw.init();
    defer glfw.deinit();
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyInstance(instance, null);
    const window = try Window.init(10, 10, "", instance);
    defer window.deinit(instance);
    const physical_device = try findPhysicalDeviceSuitableForGraphicsAndPresenting(instance, window.surface, testing.allocator);

    var logical_device: std.meta.Child(Vk.c.VkDevice) = undefined;
    var queues: Queues = undefined;
    try createLogicalDeviceAndQueues(physical_device, window.surface, testing.allocator, &logical_device, &queues);
    defer destroyDevice(logical_device);

    const swap_chain = try createSwapChain(window, physical_device, logical_device, queues.graphics_index, queues.present_index, testing.allocator);
    defer swap_chain.deinit(logical_device);
    testing.expect(swap_chain.images.len != 0);
    testing.expect(swap_chain.views.len != 0);
    testing.expectEqual(swap_chain.views.len, swap_chain.images.len);
    testing.expect(swap_chain.surface_format.format != .VK_FORMAT_UNDEFINED);
    // testing.expect(swap_chain.surface_format.colorSpace != ???);
    testing.expect(swap_chain.extent.width != 0);
    testing.expect(swap_chain.extent.height != 0);
}

pub const CoreGraphicsDeviceData = struct {
    const Self = @This();

    physical_device: std.meta.Child(Vk.c.VkPhysicalDevice),
    logical_device: std.meta.Child(Vk.c.VkDevice),
    queues: Queues,
    swap_chain : SwapChainData,

    pub fn init(instance: Vk.c.VkInstance, window: Window, allocator: *mem.Allocator) !CoreGraphicsDeviceData {
        var self : CoreGraphicsDeviceData = undefined;
        self.physical_device = try findPhysicalDeviceSuitableForGraphicsAndPresenting(instance, window.surface, allocator);
        try createLogicalDeviceAndQueues(self.physical_device, window.surface, allocator, &self.logical_device, &self.queues);
        self.swap_chain = try SwapChainData.init(window, self.physical_device, self.logical_device, self.queues.graphics_index, self.queues.present_index, allocator);
        return self;
    }

    pub fn deinit(self: Self) void {
        self.swap_chain.deinit(self.logical_device);
        destroyDevice(self.logical_device);
    }

    pub fn getPhysicalDeviceProperties(self: Self) Vk.PhysicalDeviceProperties {
        var device_properties: Vk.PhysicalDeviceProperties = undefined;
        Vk.c.vkGetPhysicalDeviceProperties(self.physical_device, &device_properties);
        return device_properties;
    }
};

test "initializing and de-initializing CoreGraphicsDeviceData should succeed on my pc" {
    try glfw.init();
    defer glfw.deinit();
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyInstance(instance, null);
    const window = try Window.init(10, 10, "", instance);
    defer window.deinit(instance);

    const core_graphics_device_data = try CoreGraphicsDeviceData.init(instance, window, testing.allocator);
    core_graphics_device_data.deinit();
}

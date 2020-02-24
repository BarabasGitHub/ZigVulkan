const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const glfw = @import("glfw_wrapper.zig");

usingnamespace @import("vulkan_general.zig");
usingnamespace @import("vulkan_instance.zig");
usingnamespace @import("vulkan_surface.zig");
usingnamespace @import("window.zig");

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

fn isDeviceSuitableForGraphicsAndPresentation(device: Vk.PhysicalDevice, surface: Vk.SurfaceKHR, allocator: *mem.Allocator) !bool {
    var deviceProperties: Vk.c.VkPhysicalDeviceProperties = undefined;
    Vk.c.vkGetPhysicalDeviceProperties(device, &deviceProperties);
    var deviceFeatures : Vk.c.VkPhysicalDeviceFeatures = undefined;
    Vk.c.vkGetPhysicalDeviceFeatures(device, &deviceFeatures);

    return (try hasSuitableDeviceQueueFamilies(device, surface, allocator)) and hasAdequateSwapChain(device, surface, allocator);
}

pub fn findPhysicalDeviceSuitableForGraphicsAndPresenting(instance: Vk.Instance, surface: Vk.SurfaceKHR, allocator: *mem.Allocator) !Vk.PhysicalDevice {
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
    defer destroyTestInstance(instance);
    const window = try Window.init(10, 10, "");
    defer window.deinit();
    const surface = try createSurface(instance, window.handle);
    defer destroySurface(instance, surface);
    _ = try findPhysicalDeviceSuitableForGraphicsAndPresenting(instance, surface, testing.allocator);
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
    defer destroyTestInstance(instance);
    const window = try Window.init(10, 10, "");
    defer window.deinit();
    const surface = try createSurface(instance, window.handle);
    defer destroySurface(instance, surface);
    const physical_device = try findPhysicalDeviceSuitableForGraphicsAndPresenting(instance, surface, testing.allocator);

    var logical_device: std.meta.Child(Vk.c.VkDevice) = undefined;
    const invalid_index = std.math.maxInt(u16);
    var queues: Queues = .{.graphics=undefined, .graphics_index=invalid_index, .present=undefined, .present_index=invalid_index, .transfer=undefined, .transfer_index=invalid_index};
    try createLogicalDeviceAndQueues(physical_device, surface, testing.allocator, &logical_device, &queues);
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
    swap_chain: Vk.SwapchainKHR,
    images: []const Vk.Image,
    views: []const Vk.ImageView,
    surface_format: Vk.c.VkSurfaceFormatKHR,
    extent: Vk.c.VkExtent2D,

    pub fn init(surface: Vk.SurfaceKHR, physical_device: Vk.PhysicalDevice, logical_device: Vk.Device, graphics_queue_index: u16, present_queue_index: u16, allocator: *mem.Allocator) !SwapChainData {
        return createSwapChain(surface, physical_device, logical_device, graphics_queue_index, present_queue_index, allocator);
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

fn chooseSwapExtent(capabilities: Vk.c.VkSurfaceCapabilitiesKHR) Vk.c.VkExtent2D {
    // if we get some extent, use it
    if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return Vk.c.VkExtent2D{.width=std.math.max(@as(u32, 1), capabilities.currentExtent.width), .height=std.math.max(1, capabilities.currentExtent.height)};
    } else {
        // otherwise pick something
        var arbitrary_extent = Vk.c.VkExtent2D{.width=128, .height=128};
        arbitrary_extent.width = std.math.max(1, std.math.clamp(arbitrary_extent.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width));
        arbitrary_extent.height = std.math.max(1, std.math.clamp(arbitrary_extent.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height));

        return arbitrary_extent;
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

fn getSwapChainImages(logical_device: Vk.Device, swap_chain: Vk.SwapchainKHR, allocator: *mem.Allocator) ![]Vk.Image {
    var image_count : u32 = undefined;
    try checkVulkanResult(Vk.c.vkGetSwapchainImagesKHR(logical_device, swap_chain, &image_count, null));
    const images = try allocator.alloc(Vk.Image, image_count);
    errdefer allocator.free(images);
    try checkVulkanResult(Vk.c.vkGetSwapchainImagesKHR(logical_device, swap_chain, &image_count, @ptrCast([*]Vk.c.VkImage, images.ptr)));
    return images;
}

fn createSwapChainImageViews(logical_device: Vk.Device, images: []const Vk.Image, format: Vk.c.VkFormat, allocator: *mem.Allocator) ![] Vk.ImageView {
    const image_views = try allocator.alloc(Vk.ImageView, images.len);
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
        try checkVulkanResult(Vk.c.vkCreateImageView(logical_device, &create_info, null, @ptrCast(*Vk.c.VkImageView, &image_views[i])));
        // TODO: clean up properly in case of an error
    }
    return image_views;
}

fn createSwapChain(surface: Vk.SurfaceKHR, physical_device: Vk.PhysicalDevice, logical_device: Vk.Device, graphics_queue_index: u16, present_queue_index: u16, allocator: *mem.Allocator) !SwapChainData {
    const surface_format = try chooseSwapSurfaceFormat(surface, physical_device, allocator);

    var capabilities: Vk.c.VkSurfaceCapabilitiesKHR = undefined;
    try checkVulkanResult(Vk.c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &capabilities));

    var create_info = Vk.c.VkSwapchainCreateInfoKHR{
        .sType=.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .pNext=null,
        .flags=0,
        .surface=surface,
        // try to get one more so we can have triple buffering
        // maxImageCount == 0 means unlimited, so subtract 1 to get uint32_t(-1) and then add one again, because we want one more than the minimum anyway
        .minImageCount=std.math.min(capabilities.minImageCount, capabilities.maxImageCount - 1) + 1,
        .imageFormat=surface_format.format,
        .imageColorSpace=surface_format.colorSpace,
        .imageExtent=chooseSwapExtent(capabilities),
        .imageArrayLayers=1,
        .imageUsage=Vk.c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .imageSharingMode=.VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount=0, // Optional
        .pQueueFamilyIndices=null, // Optional
        .preTransform=capabilities.currentTransform,
        .compositeAlpha=.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode=try chooseSwapPresentMode(surface, physical_device, allocator),
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
    var swap_chain: Vk.SwapchainKHR = undefined;
    errdefer Vk.c.vkDestroySwapchainKHR(logical_device, swap_chain, null);
    try checkVulkanResult(Vk.c.vkCreateSwapchainKHR(logical_device, &create_info, null, @ptrCast(*Vk.c.VkSwapchainKHR, &swap_chain)));
    const images = try getSwapChainImages(logical_device, swap_chain, allocator);
    errdefer allocator.free(images);
    const image_views = try createSwapChainImageViews(logical_device, images, surface_format.format, allocator);
    return SwapChainData{.allocator=allocator, .swap_chain=swap_chain, .images=images, .views=image_views, .surface_format=surface_format, .extent=create_info.imageExtent,};
}

test "Creating a swap chain should succeed on my pc" {
    try glfw.init();
    defer glfw.deinit();
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyTestInstance(instance);
    const window = try Window.init(10, 10, "");
    defer window.deinit();
    const surface = try createSurface(instance, window.handle);
    defer destroySurface(instance, surface);
    const physical_device = try findPhysicalDeviceSuitableForGraphicsAndPresenting(instance, surface, testing.allocator);

    var logical_device: std.meta.Child(Vk.c.VkDevice) = undefined;
    var queues: Queues = undefined;
    try createLogicalDeviceAndQueues(physical_device, surface, testing.allocator, &logical_device, &queues);
    defer destroyDevice(logical_device);

    const swap_chain = try createSwapChain(surface, physical_device, logical_device, queues.graphics_index, queues.present_index, testing.allocator);
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

    surface: Vk.SurfaceKHR,
    physical_device: Vk.PhysicalDevice,
    logical_device: Vk.Device,
    queues: Queues,
    swap_chain : SwapChainData,

    pub fn init(instance: Vk.Instance, window: Window, allocator: *mem.Allocator) !CoreGraphicsDeviceData {
        var self : CoreGraphicsDeviceData = undefined;
        self.surface = try createSurface(instance, window.handle);
        errdefer destroySurface(instance, self.surface);
        self.physical_device = try findPhysicalDeviceSuitableForGraphicsAndPresenting(instance, self.surface, allocator);
        try createLogicalDeviceAndQueues(self.physical_device, self.surface, allocator, &self.logical_device, &self.queues);
        errdefer destroyDevice(self.logical_device);
        self.swap_chain = try SwapChainData.init(self.surface, self.physical_device, self.logical_device, self.queues.graphics_index, self.queues.present_index, allocator);
        return self;
    }

    pub fn deinit(self: Self, instance: Vk.Instance) void {
        self.swap_chain.deinit(self.logical_device);
        destroyDevice(self.logical_device);
        destroySurface(instance, self.surface);
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
    defer destroyTestInstance(instance);
    const window = try Window.init(10, 10, "");
    defer window.deinit();
    const surface = try createSurface(instance, window.handle);
    defer destroySurface(instance, surface);

    const core_graphics_device_data = try CoreGraphicsDeviceData.init(instance, window, testing.allocator);
    core_graphics_device_data.deinit(instance);
}

fn createGraphicsCommandPool(logical_device: Vk.Device, graphics_family_index: u32) !Vk.CommandPool
{
    const poolInfo = Vk.c.VkCommandPoolCreateInfo{
        .sType=.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .pNext=null,
        .queueFamilyIndex=graphics_family_index,
        .flags=Vk.c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT, // Optional
    };
    var command_pool: Vk.CommandPool = undefined;
    try checkVulkanResult(Vk.c.vkCreateCommandPool(logical_device, &poolInfo, null, @ptrCast(*Vk.c.VkCommandPool, &command_pool)));
    return command_pool;
}

const destroyCommandPool = Vk.c.vkDestroyCommandPool;

fn createDescriptorPool(logical_device: Vk.Device ) !Vk.DescriptorPool
{
    const pool_sizes = [3]Vk.c.VkDescriptorPoolSize{
        .{
            .type=.VK_DESCRIPTOR_TYPE_SAMPLER,
            .descriptorCount=64,
        },
        .{
            .type=.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
            .descriptorCount=64,
        },
        .{
            .type=.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount=64,
            }};

    const pool_info = Vk.c.VkDescriptorPoolCreateInfo{
        .sType =.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .pNext=null,
        .poolSizeCount = pool_sizes.len,
        .pPoolSizes = &pool_sizes,
        .maxSets = 128,
        .flags = 0,
    };

    var descriptor_pool: Vk.DescriptorPool = undefined;
    try checkVulkanResult(Vk.c.vkCreateDescriptorPool(logical_device, &pool_info, null, @ptrCast(*Vk.c.VkDescriptorPool, &descriptor_pool)));
    return descriptor_pool;
}

const destroyDescriptorPool = Vk.c.vkDestroyDescriptorPool;

fn createRenderPass(display_image_format: Vk.c.VkFormat, logical_device: Vk.Device) !Vk.RenderPass
{
    const colorAttachment = Vk.c.VkAttachmentDescription{
        .format=display_image_format,
        .samples=.VK_SAMPLE_COUNT_1_BIT,
        .loadOp=.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp=.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp=.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp=.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout=.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout=.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        .flags=0,
    };

    const colorAttachmentRef = Vk.c.VkAttachmentReference{
        .attachment=0,
        .layout=.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    const subpass = Vk.c.VkSubpassDescription{
        .pipelineBindPoint=.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount=1,
        .pColorAttachments=&colorAttachmentRef,
        .inputAttachmentCount=0,
        .pInputAttachments=null,
        .pResolveAttachments=null,
        .pDepthStencilAttachment=null,
        .preserveAttachmentCount=0,
        .pPreserveAttachments=null,
        .flags=0,
    };

    const dependency = Vk.c.VkSubpassDependency{
        .srcSubpass=Vk.c.VK_SUBPASS_EXTERNAL,
        .dstSubpass=0,
        .srcStageMask=Vk.c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask=0,
        .dstStageMask=Vk.c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstAccessMask=Vk.c.VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | Vk.c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .dependencyFlags=0,
    };

    const renderPassInfo = Vk.c.VkRenderPassCreateInfo{
        .sType=.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .pNext=null,
        .attachmentCount=1,
        .pAttachments=&colorAttachment,
        .subpassCount=1,
        .pSubpasses=&subpass,
        .dependencyCount=1,
        .pDependencies=&dependency,
        .flags=0,
    };

    var render_pass: Vk.RenderPass = undefined;
    try checkVulkanResult(Vk.c.vkCreateRenderPass(logical_device, &renderPassInfo, null, @ptrCast(*Vk.c.VkRenderPass, &render_pass)));
    return render_pass;
}

const destroyRenderPass = Vk.c.vkDestroyRenderPass;

fn createFramebuffers(logical_device: Vk.Device, render_pass: Vk.RenderPass, image_views: []const Vk.ImageView, image_extent: Vk.c.VkExtent2D, allocator: *mem.Allocator) ![]Vk.Framebuffer {
    const frame_buffers = try allocator.alloc(Vk.Framebuffer, image_views.len);
    for (image_views) |image_view, i| {
        const framebuffer_info = Vk.c.VkFramebufferCreateInfo{
            .sType=.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .pNext=null,
            .flags=0,
            .renderPass=render_pass,
            .attachmentCount=1,
            .pAttachments=&image_view,
            .width=image_extent.width,
            .height=image_extent.height,
            .layers=1,
        };
        try checkVulkanResult(Vk.c.vkCreateFramebuffer(logical_device, &framebuffer_info, null, @ptrCast(*Vk.c.VkFramebuffer, frame_buffers.ptr + i)));
        // TODO: somehow clean up in case of an error.
    }
    return frame_buffers;
}

const destroyFramebuffer = Vk.c.vkDestroyFramebuffer;

fn destroyFramebuffers(logical_device: Vk.Device, frame_buffers: []Vk.Framebuffer) void {
    for (frame_buffers) |frame_buffer| {
        destroyFramebuffer(logical_device, frame_buffer, null);
    }
}

fn createCommandBuffers(logical_device: Vk.Device, command_pool: Vk.CommandPool, frame_buffers: []Vk.Framebuffer, allocator: *mem.Allocator) ![]Vk.CommandBuffer {
    const command_buffers = try allocator.alloc(Vk.CommandBuffer, frame_buffers.len);
    const allocInfo = Vk.c.VkCommandBufferAllocateInfo{
        .sType=.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .pNext=null,
        .commandPool=command_pool,
        .level=.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount=@intCast(u32, command_buffers.len),
    };
    try checkVulkanResult(Vk.c.vkAllocateCommandBuffers(logical_device, &allocInfo, @ptrCast(*Vk.c.VkCommandBuffer, command_buffers.ptr)));
    return command_buffers;
}

fn freeCommandBuffers(logical_device: Vk.Device, command_pool: Vk.CommandPool, command_buffers: []Vk.CommandBuffer) void {
    Vk.c.vkFreeCommandBuffers(logical_device, command_pool, @intCast(u32, command_buffers.len), command_buffers.ptr);
}

pub const Renderer = struct {
    const Self = @This();

    instance: Vk.Instance,
    core_device_data: CoreGraphicsDeviceData,
    graphics_command_pool: Vk.CommandPool,
    descriptor_pool: Vk.DescriptorPool,
    render_pass: Vk.RenderPass,
    frame_buffers: []Vk.Framebuffer,
    command_buffers: []Vk.CommandBuffer,
    allocator: *mem.Allocator,

    pub fn init(
        window: Window,
        application_info: ApplicationInfo,
        input_extensions: []const [*:0]const u8,
        allocator: *mem.Allocator,
        ) !Renderer {
        const glfw_extensions = try glfw.getRequiredInstanceExtensions();
        var extensions = try allocator.alloc([*:0] const u8, glfw_extensions.len + input_extensions.len);
        defer allocator.free(extensions);
        std.mem.copy([*:0]const u8, extensions, glfw_extensions);
        std.mem.copy([*:0]const u8, extensions[glfw_extensions.len..], input_extensions);
        const instance = try createInstance(application_info, extensions);
        errdefer destroyInstance(instance, null);
        const core_device_data = try CoreGraphicsDeviceData.init(instance, window, allocator);
        errdefer core_device_data.deinit(instance);
        const graphics_command_pool = try createGraphicsCommandPool(core_device_data.logical_device, core_device_data.queues.graphics_index);
        errdefer destroyCommandPool(core_device_data.logical_device, graphics_command_pool, null);
        const descriptor_pool = try createDescriptorPool(core_device_data.logical_device);
        errdefer destroyDescriptorPool(core_device_data.logical_device, descriptor_pool, null);
        const render_pass = try createRenderPass(core_device_data.swap_chain.surface_format.format, core_device_data.logical_device);
        errdefer destroyRenderPass(core_device_data.logical_device, render_pass, null);
        const frame_buffers = try createFramebuffers(core_device_data.logical_device, render_pass, core_device_data.swap_chain.views, core_device_data.swap_chain.extent, allocator);
        errdefer destroyFramebuffers(core_device_data.logical_device, frame_buffers);
        errdefer allocator.free(frame_buffers);
        const command_buffers = try createCommandBuffers(core_device_data.logical_device, graphics_command_pool, frame_buffers, allocator);
        errdefer freeCommandBuffers(core_device_data.logical_device, graphics_command_pool, command_buffers);
        errdefer allocator.free(command_buffers);
        return Renderer{
            .instance=instance,
            .core_device_data=core_device_data,
            .graphics_command_pool=graphics_command_pool,
            .descriptor_pool=descriptor_pool,
            .render_pass=render_pass,
            .frame_buffers=frame_buffers,
            .command_buffers=command_buffers,
            .allocator=allocator,
        };
    }

    pub fn deinit(self: Self) void {
        destroyFramebuffers(self.core_device_data.logical_device, self.frame_buffers);
        freeCommandBuffers(self.core_device_data.logical_device, self.graphics_command_pool, self.command_buffers);
        self.allocator.free(self.frame_buffers);
        self.allocator.free(self.command_buffers);
        destroyRenderPass(self.core_device_data.logical_device, self.render_pass, null);
        destroyDescriptorPool(self.core_device_data.logical_device, self.descriptor_pool, null);
        destroyCommandPool(self.core_device_data.logical_device, self.graphics_command_pool, null);
        self.core_device_data.deinit(self.instance);
        destroyInstance(self.instance, null);
    }
};

test "creating a Renderer should succeed" {
    try glfw.init();
    defer glfw.deinit();
    const window = try Window.init(200, 200, "test_window");
    defer window.deinit();
    const renderer = try Renderer.init(
        window,
        .{.application=.{.name="", .version=.{.major=0, .minor=0, .patch=0}}, .engine=.{.name="", .version=.{.major=0, .minor=0, .patch=0}}},
        &[_][*:0]const u8{Vk.c.VK_EXT_DEBUG_REPORT_EXTENSION_NAME},
        testing.allocator);
    defer renderer.deinit();
    testing.expect(renderer.frame_buffers.len > 0);
    testing.expect(renderer.command_buffers.len > 0);
}

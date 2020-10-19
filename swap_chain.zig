const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const glfw = @import("glfw_wrapper.zig");

usingnamespace @import("vulkan_general.zig");
usingnamespace @import("vulkan_instance.zig");
usingnamespace @import("vulkan_surface.zig");
usingnamespace @import("window.zig");
usingnamespace @import("physical_device.zig");
usingnamespace @import("device_and_queues.zig");

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
        for (self.views) |view| {
            Vk.c.vkDestroyImageView(logical_device, view, null);
        }
        self.allocator.free(self.images);
        self.allocator.free(self.views);
        Vk.c.vkDestroySwapchainKHR(logical_device, self.swap_chain, null);
    }
};

fn chooseSwapSurfaceFormat(surface: Vk.c.VkSurfaceKHR, physical_device: Vk.c.VkPhysicalDevice, allocator: *mem.Allocator) !Vk.c.VkSurfaceFormatKHR {
    var surface_format_count: u32 = undefined;
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
        return Vk.c.VkExtent2D{ .width = std.math.max(@as(u32, 1), capabilities.currentExtent.width), .height = std.math.max(1, capabilities.currentExtent.height) };
    } else {
        // otherwise pick something
        var arbitrary_extent = Vk.c.VkExtent2D{ .width = 128, .height = 128 };
        arbitrary_extent.width = std.math.max(1, std.math.clamp(arbitrary_extent.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width));
        arbitrary_extent.height = std.math.max(1, std.math.clamp(arbitrary_extent.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height));

        return arbitrary_extent;
    }
}

fn chooseSwapPresentMode(surface: Vk.c.VkSurfaceKHR, physical_device: Vk.c.VkPhysicalDevice, allocator: *mem.Allocator) !Vk.c.VkPresentModeKHR {
    var present_mode_count: u32 = undefined;
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
    var image_count: u32 = undefined;
    try checkVulkanResult(Vk.c.vkGetSwapchainImagesKHR(logical_device, swap_chain, &image_count, null));
    const images = try allocator.alloc(Vk.Image, image_count);
    errdefer allocator.free(images);
    try checkVulkanResult(Vk.c.vkGetSwapchainImagesKHR(logical_device, swap_chain, &image_count, @ptrCast([*]Vk.c.VkImage, images.ptr)));
    return images;
}

fn createSwapChainImageViews(logical_device: Vk.Device, images: []const Vk.Image, format: Vk.c.VkFormat, allocator: *mem.Allocator) ![]Vk.ImageView {
    const image_views = try allocator.alloc(Vk.ImageView, images.len);
    errdefer allocator.free(image_views);
    for (images) |image, i| {
        errdefer {
            for (image_views[0..i]) |view| {
                Vk.c.vkDestroyImageView(logical_device, view, null);
            }
        }
        const create_info = Vk.c.VkImageViewCreateInfo{
            .sType = .VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .image = image,
            .viewType = .VK_IMAGE_VIEW_TYPE_2D,
            .format = format,

            .components = .{
                .r = .VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = .VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = .VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = .VK_COMPONENT_SWIZZLE_IDENTITY,
            },

            .subresourceRange = .{
                .aspectMask = Vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = Vk.c.VK_REMAINING_ARRAY_LAYERS,
            },
        };
        try checkVulkanResult(Vk.c.vkCreateImageView(logical_device, &create_info, null, @ptrCast(*Vk.c.VkImageView, &image_views[i])));
    }
    return image_views;
}

fn createSwapChain(surface: Vk.SurfaceKHR, physical_device: Vk.PhysicalDevice, logical_device: Vk.Device, graphics_queue_index: u16, present_queue_index: u16, allocator: *mem.Allocator) !SwapChainData {
    const surface_format = try chooseSwapSurfaceFormat(surface, physical_device, allocator);

    var capabilities: Vk.c.VkSurfaceCapabilitiesKHR = undefined;
    try checkVulkanResult(Vk.c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &capabilities));

    var create_info = Vk.c.VkSwapchainCreateInfoKHR{
        .sType = .VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .pNext = null,
        .flags = 0,
        .surface = surface,
        // try to get one more so we can have triple buffering
        // maxImageCount == 0 means unlimited, so subtract 1 to get uint32_t(-1) and then add one again, because we want one more than the minimum anyway
        .minImageCount = std.math.min(capabilities.minImageCount, capabilities.maxImageCount - 1) + 1,
        .imageFormat = surface_format.format,
        .imageColorSpace = surface_format.colorSpace,
        .imageExtent = chooseSwapExtent(capabilities),
        .imageArrayLayers = 1,
        .imageUsage = Vk.c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .imageSharingMode = .VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 0, // Optional
        .pQueueFamilyIndices = null, // Optional
        .preTransform = capabilities.currentTransform,
        .compositeAlpha = .VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = try chooseSwapPresentMode(surface, physical_device, allocator),
        .clipped = @boolToInt(true),
        .oldSwapchain = null,
    };
    const queueFamilyIndices = [_]u32{ graphics_queue_index, present_queue_index };
    // if they're not the same share using concurrent for now
    if (graphics_queue_index != present_queue_index) {
        create_info.imageSharingMode = .VK_SHARING_MODE_CONCURRENT;
        create_info.queueFamilyIndexCount = 2;
        create_info.pQueueFamilyIndices = &queueFamilyIndices;
    }
    var swap_chain: Vk.SwapchainKHR = undefined;
    errdefer Vk.c.vkDestroySwapchainKHR(logical_device, swap_chain, null);
    try checkVulkanResult(Vk.c.vkCreateSwapchainKHR(logical_device, &create_info, null, @ptrCast(*Vk.c.VkSwapchainKHR, &swap_chain)));
    const images = try getSwapChainImages(logical_device, swap_chain, allocator);
    errdefer allocator.free(images);
    const image_views = try createSwapChainImageViews(logical_device, images, surface_format.format, allocator);
    return SwapChainData{ .allocator = allocator, .swap_chain = swap_chain, .images = images, .views = image_views, .surface_format = surface_format, .extent = create_info.imageExtent };
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
    var queues: QueuesGPT = undefined;
    try createLogicalDeviceAndQueuesGPT(physical_device, surface, testing.allocator, &logical_device, &queues);
    defer destroyDevice(logical_device);

    const swap_chain = try createSwapChain(surface, physical_device, logical_device, queues.graphics.family_index, queues.present.family_index, testing.allocator);
    defer swap_chain.deinit(logical_device);
    testing.expect(swap_chain.images.len != 0);
    testing.expect(swap_chain.views.len != 0);
    testing.expectEqual(swap_chain.views.len, swap_chain.images.len);
    testing.expect(swap_chain.surface_format.format != .VK_FORMAT_UNDEFINED);
    // testing.expect(swap_chain.surface_format.colorSpace != ???);
    testing.expect(swap_chain.extent.width != 0);
    testing.expect(swap_chain.extent.height != 0);
}

const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const glfw = @import("glfw_wrapper.zig");

usingnamespace @import("vulkan_general.zig");
usingnamespace @import("vulkan_instance.zig");
usingnamespace @import("vulkan_surface.zig");
usingnamespace @import("vulkan_image.zig");
usingnamespace @import("window.zig");
usingnamespace @import("device_and_queues.zig");
usingnamespace @import("physical_device.zig");
usingnamespace @import("swap_chain.zig");
usingnamespace @import("descriptor_sets.zig");
usingnamespace @import("command_buffer.zig");

pub const CoreGraphicsDeviceData = struct {
    const Self = @This();

    surface: Vk.SurfaceKHR,
    physical_device: Vk.PhysicalDevice,
    logical_device: Vk.Device,
    queues: QueuesGPT,
    swap_chain: SwapChainData,

    pub fn init(instance: Vk.Instance, window: Window, allocator: *mem.Allocator) !CoreGraphicsDeviceData {
        var self: CoreGraphicsDeviceData = undefined;
        self.surface = try createSurface(instance, window.handle);
        errdefer destroySurface(instance, self.surface);
        self.physical_device = try findPhysicalDeviceSuitableForGraphicsAndPresenting(instance, self.surface, allocator);
        try createLogicalDeviceAndQueuesGPT(self.physical_device, self.surface, allocator, &self.logical_device, &self.queues);
        errdefer destroyDevice(self.logical_device);
        self.swap_chain = try SwapChainData.init(self.surface, self.physical_device, self.logical_device, self.queues.graphics.family_index, self.queues.present.family_index, allocator);
        return self;
    }

    pub fn deinit(self: Self, instance: Vk.Instance) void {
        self.swap_chain.deinit(self.logical_device);
        destroyDevice(self.logical_device);
        destroySurface(instance, self.surface);
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

pub const destroyCommandPool = Vk.c.vkDestroyCommandPool;

pub fn createRenderPass(display_image_format: Vk.c.VkFormat, logical_device: Vk.Device) !Vk.RenderPass {
    const colorAttachment = Vk.c.VkAttachmentDescription{
        .format = display_image_format,
        .samples = .VK_SAMPLE_COUNT_1_BIT,
        .loadOp = .VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = .VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = .VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = .VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = .VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = .VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        .flags = 0,
    };

    const colorAttachmentRef = Vk.c.VkAttachmentReference{
        .attachment = 0,
        .layout = .VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    const subpass = Vk.c.VkSubpassDescription{
        .pipelineBindPoint = .VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &colorAttachmentRef,
        .inputAttachmentCount = 0,
        .pInputAttachments = null,
        .pResolveAttachments = null,
        .pDepthStencilAttachment = null,
        .preserveAttachmentCount = 0,
        .pPreserveAttachments = null,
        .flags = 0,
    };

    const dependency = Vk.c.VkSubpassDependency{
        .srcSubpass = Vk.c.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = Vk.c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = 0,
        .dstStageMask = Vk.c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstAccessMask = Vk.c.VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | Vk.c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .dependencyFlags = 0,
    };

    const renderPassInfo = Vk.c.VkRenderPassCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .pNext = null,
        .attachmentCount = 1,
        .pAttachments = &colorAttachment,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 1,
        .pDependencies = &dependency,
        .flags = 0,
    };

    var render_pass: Vk.RenderPass = undefined;
    try checkVulkanResult(Vk.c.vkCreateRenderPass(logical_device, &renderPassInfo, null, @ptrCast(*Vk.c.VkRenderPass, &render_pass)));
    return render_pass;
}

pub const destroyRenderPass = Vk.c.vkDestroyRenderPass;

const Semaphores = struct {
    image_available: Vk.Semaphore,
    render_finished: Vk.Semaphore,

    pub fn init(logical_device: Vk.Device) !Semaphores {
        var semaphores: Semaphores = undefined;
        const semaphoreInfo = Vk.c.VkSemaphoreCreateInfo{
            .sType = .VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
        };
        try checkVulkanResult(Vk.c.vkCreateSemaphore(logical_device, &semaphoreInfo, null, @ptrCast(*Vk.c.VkSemaphore, &semaphores.image_available)));
        errdefer Vk.c.vkDestroySemaphore(logical_device, semaphores.image_available, null);
        try checkVulkanResult(Vk.c.vkCreateSemaphore(logical_device, &semaphoreInfo, null, @ptrCast(*Vk.c.VkSemaphore, &semaphores.render_finished)));
        return semaphores;
    }

    pub fn deinit(self: Semaphores, logical_device: Vk.Device) void {
        Vk.c.vkDestroySemaphore(logical_device, self.image_available, null);
        Vk.c.vkDestroySemaphore(logical_device, self.render_finished, null);
    }
};

pub const Renderer = struct {
    const Self = @This();

    instance: Vk.Instance,
    core_device_data: CoreGraphicsDeviceData,
    graphics_command_pool: Vk.CommandPool,
    descriptor_pool: Vk.DescriptorPool,
    render_pass: Vk.RenderPass,
    frame_buffers: []Vk.Framebuffer,
    command_buffers: []Vk.CommandBuffer,
    semaphores: Semaphores,
    current_render_image_index: u32,
    allocator: *mem.Allocator,

    pub fn init(
        window: Window,
        application_info: ApplicationInfo,
        input_extensions: []const [*:0]const u8,
        allocator: *mem.Allocator,
    ) !Renderer {
        const glfw_extensions = try glfw.getRequiredInstanceExtensions();
        var extensions = try allocator.alloc([*:0]const u8, glfw_extensions.len + input_extensions.len);
        defer allocator.free(extensions);
        std.mem.copy([*:0]const u8, extensions, glfw_extensions);
        std.mem.copy([*:0]const u8, extensions[glfw_extensions.len..], input_extensions);
        const instance = try if (USE_DEBUG_TOOLS) createTestInstance(extensions) else createInstance(application_info, extensions);
        errdefer destroyInstance(instance, null);
        const core_device_data = try CoreGraphicsDeviceData.init(instance, window, allocator);
        errdefer core_device_data.deinit(instance);
        const graphics_command_pool = try core_device_data.queues.graphics.createCommandPool(core_device_data.logical_device, Vk.c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT);
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
        const semaphores = try Semaphores.init(core_device_data.logical_device);
        errdefer semaphores.deinit();
        return Renderer{
            .instance = instance,
            .core_device_data = core_device_data,
            .graphics_command_pool = graphics_command_pool,
            .descriptor_pool = descriptor_pool,
            .render_pass = render_pass,
            .frame_buffers = frame_buffers,
            .command_buffers = command_buffers,
            .semaphores = semaphores,
            .current_render_image_index = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Self) void {
        _ = Vk.c.vkDeviceWaitIdle(self.core_device_data.logical_device);
        destroyFramebuffers(self.core_device_data.logical_device, self.frame_buffers);
        freeCommandBuffers(self.core_device_data.logical_device, self.graphics_command_pool, self.command_buffers);
        self.allocator.free(self.frame_buffers);
        self.allocator.free(self.command_buffers);
        destroyRenderPass(self.core_device_data.logical_device, self.render_pass, null);
        destroyDescriptorPool(self.core_device_data.logical_device, self.descriptor_pool, null);
        destroyCommandPool(self.core_device_data.logical_device, self.graphics_command_pool, null);
        self.semaphores.deinit(self.core_device_data.logical_device);
        self.core_device_data.deinit(self.instance);
        if (USE_DEBUG_TOOLS) {
            destroyTestInstance(self.instance);
        } else {
            destroyInstance(self.instance, null);
        }
    }

    pub fn draw(self: Self) !void {
        try self.core_device_data.queues.graphics.submitSingle(
            @ptrCast([*]const Vk.Semaphore, &self.semaphores.image_available)[0..1],
            self.command_buffers[self.current_render_image_index .. self.current_render_image_index + 1],
            @ptrCast([*]const Vk.Semaphore, &self.semaphores.render_finished)[0..1],
            @as(u32, Vk.c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
        );
    }

    pub fn present(self: Self) !void {
        try self.core_device_data.queues.present.waitIdle();
        try self.core_device_data.queues.present.present(
            @ptrCast([*]const Vk.Semaphore, &self.semaphores.render_finished)[0..1],
            @ptrCast([*]const Vk.SwapchainKHR, &self.core_device_data.swap_chain.swap_chain)[0..1],
            @ptrCast([*]const u32, &self.current_render_image_index)[0..1],
        ) catch |err| switch (err) {
            error.VkErrorOutOfDateKhr, error.VkSuboptimalKhr => {}, // recreate swapchain and return
            else => err,
        };
    }

    pub fn updateImageIndex(self: *Self) !void {
        return checkVulkanResult(Vk.c.vkAcquireNextImageKHR(
            self.core_device_data.logical_device,
            self.core_device_data.swap_chain.swap_chain,
            std.math.maxInt(u64),
            self.semaphores.image_available,
            null,
            &self.current_render_image_index,
        )) catch |err| switch (err) {
            error.VkErrorOutOfDateKhr => err, // recreate swapchain and try again (continue)
            error.VkSuboptimalKhr => {},
            else => err,
        };
    }
};

test "creating a Renderer should succeed" {
    try glfw.init();
    defer glfw.deinit();
    const window = try Window.init(200, 200, "test_window");
    defer window.deinit();
    const renderer = try Renderer.init(
        window,
        testApplicationInfo(),
        &[_][*:0]const u8{Vk.c.VK_EXT_DEBUG_REPORT_EXTENSION_NAME},
        testing.allocator,
    );
    defer renderer.deinit();
    testing.expect(renderer.frame_buffers.len > 0);
    testing.expect(renderer.command_buffers.len > 0);
}

const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const glfw = @import("glfw_wrapper.zig");
const Window = @import("glfw_vulkan_window.zig").Window;
usingnamespace @import("vulkan_instance.zig");
const CoreGraphicsDeviceData = @import("vulkan_graphics_device.zig").CoreGraphicsDeviceData;

usingnamespace @import("vulkan_general.zig");

fn createTransferCommandPool(logical_device: Vk.Device, transfer_family_index: u32) !Vk.CommandPool {
    const poolInfo = Vk.CommandPoolCreateInfo{
        .sType=.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .pNext=null,
        .queueFamilyIndex=transfer_family_index,
        .flags=Vk.c.VK_COMMAND_POOL_CREATE_TRANSIENT_BIT,
    };
    var command_pool: Vk.CommandPool = undefined;
    try checkVulkanResult(Vk.c.vkCreateCommandPool(@ptrCast(Vk.c.VkDevice, logical_device), &poolInfo, null, @ptrCast(*Vk.c.VkCommandPool, &command_pool)));
    return command_pool;
}

fn createSemaphore(logical_device: Vk.Device) !Vk.Semaphore {
    const semaphoreInfo = Vk.c.VkSemaphoreCreateInfo{
        .sType=.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        .pNext=null,
        .flags=0,
    };
    var semaphore: Vk.Semaphore = undefined;
    try checkVulkanResult(Vk.c.vkCreateSemaphore(logical_device, &semaphoreInfo, null, @ptrCast(*Vk.c.VkSemaphore, &semaphore)));
    return semaphore;
}


fn alignInteger(offset: u64, alignment: u64) u64
{
    return (offset + (alignment - 1)) & ~ (alignment - 1);
}

fn createBuffer(logical_device: Vk.Device, size: u64, usage: Vk.c.VkBufferUsageFlags) !Vk.Buffer {
    const buffer_info = Vk.c.VkBufferCreateInfo{
        .sType=.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .pNext=null,
        .flags=0,
        .queueFamilyIndexCount=0,
        .pQueueFamilyIndices=null,
        .size=size,
        .usage=usage,
        .sharingMode=.VK_SHARING_MODE_EXCLUSIVE,
    };

    var buffer : Vk.Buffer = undefined;
    try checkVulkanResult(Vk.c.vkCreateBuffer(logical_device, &buffer_info, null, @ptrCast(*Vk.c.VkBuffer, &buffer)));
    return buffer;
}

const DeviceMemoryStore = struct {
    const Self = @This();

    pub const ConfigurationRequest = struct {
        default_allocation_size: u32,
        default_staging_buffer_size: u32,
    };

    pub const Configuration = struct {
        min_uniform_buffer_offset_alignment: u64,
        non_coherent_atom_size: u64,
        default_allocation_size: u32,
    };

    allocator: *mem.Allocator,
    configuration: Configuration,
    // not owned by this
    physical_device: Vk.PhysicalDevice,
    logical_device: Vk.Device,
    transfer_command_pool: Vk.CommandPool,
    graphics_command_pool: Vk.CommandPool,
    transfer_queue_ownership_semaphore: Vk.Semaphore,
    staging_buffer: StagingBuffer,

    pub fn init(requested_configuration: ConfigurationRequest, core_graphics_device_data: CoreGraphicsDeviceData, allocator: *mem.Allocator) !Self {
        var self: Self = undefined;
        self.allocator = allocator;
        const device_properties = core_graphics_device_data.getPhysicalDeviceProperties();
        self.configuration.min_uniform_buffer_offset_alignment = device_properties.limits.minUniformBufferOffsetAlignment;
        self.configuration.non_coherent_atom_size = device_properties.limits.nonCoherentAtomSize;
        self.configuration.default_allocation_size = requested_configuration.default_allocation_size;
        self.physical_device = core_graphics_device_data.physical_device;
        self.logical_device = core_graphics_device_data.logical_device;
        self.transfer_command_pool = try createTransferCommandPool(self.logical_device, core_graphics_device_data.queues.transfer_index);
        self.graphics_command_pool = try createTransferCommandPool(self.logical_device, core_graphics_device_data.queues.graphics_index);
        self.transfer_queue_ownership_semaphore = try createSemaphore(self.logical_device);
        self.staging_buffer = try StagingBuffer.init(requested_configuration.default_staging_buffer_size, self.physical_device, self.logical_device, self.configuration.min_uniform_buffer_offset_alignment);
        return self;
    }

    pub fn deinit(self: Self) void {
        Vk.c.vkDestroyCommandPool(self.logical_device, self.transfer_command_pool, null);
        Vk.c.vkDestroyCommandPool(self.logical_device, self.graphics_command_pool, null);
        Vk.c.vkDestroySemaphore(self.logical_device, self.transfer_queue_ownership_semaphore, null);
        self.staging_buffer.deinit(self.logical_device);
    }
};

fn findMemoryType(physical_device: Vk.PhysicalDevice, typeFilter: u32, properties: Vk.c.VkMemoryPropertyFlags) !u32
{
    var memory_properties: Vk.c.VkPhysicalDeviceMemoryProperties = undefined;
    Vk.c.vkGetPhysicalDeviceMemoryProperties(physical_device, &memory_properties);

    var i: u32 = 0;
    while(i < memory_properties.memoryTypeCount) {
        if ((typeFilter & (@as(u32, 1) << @intCast(u5, i))) != 0 and ((memory_properties.memoryTypes[i].propertyFlags & properties) == properties)) {
            return i;
        }
        i += 1;
    }

    return error.FailedToFindSuitableMemoryType;
}

fn allocateMemory(physical_device: Vk.PhysicalDevice, logical_device: Vk.Device, requirements: Vk.c.VkMemoryRequirements, properties: Vk.c.VkMemoryPropertyFlags) !Vk.DeviceMemory {
    const allocInfo = Vk.c.VkMemoryAllocateInfo{
        .sType=.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .pNext=null,
        .allocationSize=requirements.size,
        .memoryTypeIndex=try findMemoryType(physical_device, requirements.memoryTypeBits, properties),
    };
    var device_pointer : Vk.DeviceMemory = undefined;
    try checkVulkanResult(Vk.c.vkAllocateMemory(logical_device, &allocInfo, null, @ptrCast(*Vk.c.VkDeviceMemory, &device_pointer)));
    return device_pointer;
}

const StagingBuffer = struct {
    const Self = @This();

    buffer: Vk.Buffer,
    device_memory: Vk.DeviceMemory,
    mapped: []u8,

    pub fn init(requested_size: u32, physical_device: Vk.PhysicalDevice, logical_device: Vk.Device, min_uniform_buffer_offset_alignment: u64) !Self {
        const size = alignInteger(requested_size, min_uniform_buffer_offset_alignment);
        const buffer = try createBuffer(logical_device, size, Vk.c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
        errdefer Vk.c.vkDestroyBuffer(logical_device, buffer, null);
        var requirements: Vk.c.VkMemoryRequirements = undefined;
        Vk.c.vkGetBufferMemoryRequirements(logical_device, buffer, &requirements);
        const device_memory = try allocateMemory(physical_device, logical_device, requirements, Vk.c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | Vk.c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
        errdefer Vk.c.vkFreeMemory(logical_device, device_memory, null);
        try checkVulkanResult(Vk.c.vkBindBufferMemory(logical_device, buffer, device_memory, 0));
        var mapped: [*]u8 = undefined;
        try checkVulkanResult(Vk.c.vkMapMemory(logical_device, device_memory, 0, requirements.size, 0, @ptrCast(*?*c_void, &mapped)));
        return Self{
            .buffer=buffer,
            .device_memory=device_memory,
            .mapped=mapped[0..size],
        };
    }

    pub fn deinit(self: Self, logical_device: Vk.Device) void {
        Vk.c.vkFreeMemory(logical_device, self.device_memory, null);
        Vk.c.vkDestroyBuffer(logical_device, self.buffer, null);
    }
};

test "Initializing a device memory store should succeed" {
    try glfw.init();
    defer glfw.deinit();
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyInstance(instance, null);
    const window = try Window.init(10, 10, "", instance);
    defer window.deinit(instance);
    const core_graphics_device_data = try CoreGraphicsDeviceData.init(instance, window, testing.allocator);
    defer core_graphics_device_data.deinit();

    const config = DeviceMemoryStore.ConfigurationRequest{
        .default_allocation_size=1e3,
        .default_staging_buffer_size=1e4,
    };
    const store = try DeviceMemoryStore.init(config, core_graphics_device_data, testing.allocator);
    defer store.deinit();
    testing.expect(store.configuration.default_allocation_size >= config.default_allocation_size);
    testing.expect(store.staging_buffer.mapped.len >= config.default_staging_buffer_size);
}


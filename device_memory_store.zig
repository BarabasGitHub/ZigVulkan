const std = @import("std");
const mem = std.mem;
const testing = std.testing;

usingnamespace @import("Utilities/handle_generator.zig");

const glfw = @import("glfw_wrapper.zig");
const Window = @import("glfw_vulkan_window.zig").Window;
usingnamespace @import("vulkan_instance.zig");
usingnamespace @import("vulkan_graphics_device.zig");

usingnamespace @import("vulkan_general.zig");

fn ArrayListExtension(comptime Type: type) type {
    return struct {
        const Self = std.ArrayList(Type);

        pub fn ensureSize(self: *Self, size: usize) !void {
            if (self.len < size) {
                try self.resize(size);
            }
        }

        pub fn assignAtPositionAndResizeIfNecessary(self: *Self, index: usize, value: Type) !void {
            try ensureSize(self, index + 1);
            self.set(index, value);
        }
    };
}

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

fn getBufferMemoryRequirements(logical_device: Vk.Device, buffer: Vk.Buffer) Vk.c.VkMemoryRequirements {
    var requirements: Vk.c.VkMemoryRequirements = undefined;
    Vk.c.vkGetBufferMemoryRequirements(logical_device, buffer, &requirements);
    return requirements;
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

    pub const BufferID = Handle(Vk.Buffer);
    const BufferIDGenerator = HandleGenerator(BufferID);

    const CommandPools = struct {
        transfer: Vk.CommandPool,
        graphics: Vk.CommandPool,
        transfer_queue_ownership_semaphore: Vk.Semaphore,
        pub fn init(logical_device: Vk.Device, queues: Queues) !CommandPools {
            return CommandPools{
                .transfer=try createTransferCommandPool(logical_device, queues.transfer_index),
                .graphics=try createTransferCommandPool(logical_device, queues.graphics_index),
                .transfer_queue_ownership_semaphore=try createSemaphore(logical_device),
            };
        }

        pub fn deinit(self: CommandPools, logical_device: Vk.Device) void {
            Vk.c.vkDestroyCommandPool(logical_device, self.transfer, null);
            Vk.c.vkDestroyCommandPool(logical_device, self.graphics, null);
            Vk.c.vkDestroySemaphore(logical_device, self.transfer_queue_ownership_semaphore, null);
        }
    };

    allocator: *mem.Allocator,
    configuration: Configuration,
    // not owned
    physical_device: Vk.PhysicalDevice,
    logical_device: Vk.Device,
    // owned
    command_pools: CommandPools,
    staging_buffer: StagingBuffer,
    buffer_id_generator: BufferIDGenerator,
    read_write_buffer_allocations: std.AutoHashMap(Vk.Buffer, ReadWriteBufferAllocation),
    buffer_ranges: std.ArrayList(Vk.c.VkDescriptorBufferInfo),

    pub fn init(requested_configuration: ConfigurationRequest, core_graphics_device_data: CoreGraphicsDeviceData, allocator: *mem.Allocator) !Self {
        var self: Self = undefined;
        self.allocator = allocator;
        const device_properties = core_graphics_device_data.getPhysicalDeviceProperties();
        self.configuration.min_uniform_buffer_offset_alignment = device_properties.limits.minUniformBufferOffsetAlignment;
        self.configuration.non_coherent_atom_size = device_properties.limits.nonCoherentAtomSize;
        self.configuration.default_allocation_size = requested_configuration.default_allocation_size;
        self.physical_device = core_graphics_device_data.physical_device;
        self.logical_device = core_graphics_device_data.logical_device;
        self.command_pools = try CommandPools.init(self.logical_device, core_graphics_device_data.queues);
        self.staging_buffer = try StagingBuffer.init(requested_configuration.default_staging_buffer_size, self.physical_device, self.logical_device, self.configuration.min_uniform_buffer_offset_alignment);
        self.buffer_id_generator = BufferIDGenerator.init(allocator);
        self.read_write_buffer_allocations = std.AutoHashMap(Vk.Buffer, ReadWriteBufferAllocation).init(allocator);
        self.buffer_ranges = std.ArrayList(Vk.c.VkDescriptorBufferInfo).init(allocator);
        return self;
    }

    pub fn deinit(self: Self) void {
        // if waiting fails we will just destroy our objects
        _ = Vk.c.vkDeviceWaitIdle(self.logical_device);
        self.command_pools.deinit(self.logical_device);
        self.staging_buffer.deinit(self.logical_device);
        self.buffer_id_generator.deinit();
        var iter = self.read_write_buffer_allocations.iterator();
        while(iter.next())|kv| {
            Vk.c.vkDestroyBuffer(self.logical_device, kv.key, null);
            Vk.c.vkFreeMemory(self.logical_device, kv.value.device_memory, null);
        }
        self.read_write_buffer_allocations.deinit();
        self.buffer_ranges.deinit();
    }

    pub const BufferMemoryProperties = struct {
        properties: Vk.c.VkMemoryPropertyFlags,
        usage: Vk.c.VkBufferUsageFlags,
    };

    pub const ReadWriteBufferAllocation = struct {
        device_memory: Vk.DeviceMemory,
        properties: BufferMemoryProperties,
        size_per_frame: u64,
        used_offset: u64,
        mapped: ?[*]u8,
    };


    fn createNewBuffer(self: *Self, minimum_size: u64, frame_count: u32, properties: BufferMemoryProperties) !BufferID {
        const size_per_frame = alignInteger(std.math.max(minimum_size, self.configuration.default_allocation_size), std.math.max(self.configuration.min_uniform_buffer_offset_alignment, self.configuration.non_coherent_atom_size));
        const size = size_per_frame * frame_count;
        const buffer = try createBuffer(self.logical_device, size, properties.usage);
        const requirements = getBufferMemoryRequirements(self.logical_device, buffer);
        const device_pointer = try allocateMemory(self.physical_device, self.logical_device, requirements, properties.properties);
        try checkVulkanResult(Vk.c.vkBindBufferMemory(self.logical_device, buffer, device_pointer, 0));
        try self.read_write_buffer_allocations.putNoClobber(buffer, .{
            .device_memory=device_pointer,
            .properties=properties,
            .size_per_frame=size_per_frame,
            .used_offset=alignInteger(minimum_size, self.configuration.min_uniform_buffer_offset_alignment),
            .mapped=null,
            });
        const id = try self.buffer_id_generator.newHandle();
        try ArrayListExtension(Vk.c.VkDescriptorBufferInfo).assignAtPositionAndResizeIfNecessary(
            &self.buffer_ranges, id.index, .{
            .buffer=buffer,
            .offset=0,
            .range=minimum_size,
        });
        return id;
    }

    pub fn allocateBufferSpace(self: *Self, size: u64, frame_count: u32, memory_properties: BufferMemoryProperties) !BufferID {
        if (try self.findSpaceInExistingBuffer(size, memory_properties)) |id| {
            return id;
        }
        return self.createNewBuffer(size, frame_count, memory_properties);
    }

    pub fn isValidBufferId(self: Self, id: BufferID) bool {
        return self.buffer_id_generator.isValid(id);
    }

    pub fn getDescriptorBufferInfo(self: Self, id: BufferID) Vk.c.VkDescriptorBufferInfo {
        std.debug.assert(self.isValidBufferId(id));
        return self.buffer_ranges.at(id.index);
    }

    pub fn findSpaceInExistingBuffer(self: *Self, size: u64, memory_properties: BufferMemoryProperties) !?BufferID {
        var iter = self.read_write_buffer_allocations.iterator();
        while (iter.next()) |kv| {
            var allocation_info = &kv.value;
            if (std.meta.eql(allocation_info.properties, memory_properties) and hasSpaceInBuffer(size, allocation_info.*)) {
                const id = try self.buffer_id_generator.newHandle();
                try ArrayListExtension(Vk.c.VkDescriptorBufferInfo).assignAtPositionAndResizeIfNecessary(
                    &self.buffer_ranges, id.index, .{
                    .buffer=kv.key,
                    .offset=allocation_info.used_offset,
                    .range=size,
                });
                allocation_info.used_offset = alignInteger(allocation_info.used_offset + size, self.configuration.min_uniform_buffer_offset_alignment);
                return id;
            }
        }
        return null;
    }

};

fn hasSpaceInBuffer(size: u64, allocation: DeviceMemoryStore.ReadWriteBufferAllocation) bool {
    return allocation.size_per_frame > allocation.used_offset + size;
}


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
        const requirements = getBufferMemoryRequirements(logical_device, buffer);
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

fn allocateUniformBuffer(store: *DeviceMemoryStore, size: u64, frame_count: u32) !DeviceMemoryStore.BufferID {
    return try store.allocateBufferSpace(size, frame_count, .{.usage=Vk.c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, .properties=Vk.c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT | Vk.c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT});
}

test "allocating a buffer should succeed" {
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
        .default_staging_buffer_size=1,
    };
    var store = try DeviceMemoryStore.init(config, core_graphics_device_data, testing.allocator);
    defer store.deinit();
    const buffer_id = try allocateUniformBuffer(&store, 100, 2);
    testing.expect(store.isValidBufferId(buffer_id));
}

test "allocating multiple buffers which fit in one allocation should have the same VkBuffer" {
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
        .default_staging_buffer_size=1,
    };
    var store = try DeviceMemoryStore.init(config, core_graphics_device_data, testing.allocator);
    defer store.deinit();
    var buffers: [4]DeviceMemoryStore.BufferID = undefined;
    for (buffers) |*buf| {
        buf.* = try allocateUniformBuffer(&store, store.configuration.default_allocation_size / (buffers.len * 2), 2);
    }
    for (buffers) |buf| {
        testing.expectEqual(store.getDescriptorBufferInfo(buffers[0]).buffer, store.getDescriptorBufferInfo(buf).buffer);
    }
}

test "allocating multiple buffers which do not fit in one allocation should have different VkBuffers" {
    try glfw.init();
    defer glfw.deinit();
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyInstance(instance, null);
    const window = try Window.init(10, 10, "", instance);
    defer window.deinit(instance);
    const core_graphics_device_data = try CoreGraphicsDeviceData.init(instance, window, testing.allocator);
    defer core_graphics_device_data.deinit();

    const config = DeviceMemoryStore.ConfigurationRequest{
        .default_allocation_size=1,
        .default_staging_buffer_size=1,
    };
    var store = try DeviceMemoryStore.init(config, core_graphics_device_data, testing.allocator);
    defer store.deinit();

    const buffer_id1 = try allocateUniformBuffer(&store, store.configuration.default_allocation_size, 2);
    const buffer_id2 = try allocateUniformBuffer(&store, store.configuration.default_allocation_size, 2);
    testing.expect(!std.meta.eql(buffer_id1, buffer_id2));
}


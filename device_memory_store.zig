const std = @import("std");
const mem = std.mem;
const testing = std.testing;

usingnamespace @import("Utilities/handle_generator.zig");

const glfw = @import("glfw_wrapper.zig");
const Window = @import("window.zig").Window;
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

fn alignInteger(offset: u64, alignment: u64) u64 {
    return (offset + (alignment - 1)) & ~(alignment - 1);
}

fn createBuffer(logical_device: Vk.Device, size: u64, usage: Vk.c.VkBufferUsageFlags) !Vk.Buffer {
    const buffer_info = Vk.c.VkBufferCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .queueFamilyIndexCount = 0,
        .pQueueFamilyIndices = null,
        .size = size,
        .usage = usage,
        .sharingMode = .VK_SHARING_MODE_EXCLUSIVE,
    };

    var buffer: Vk.Buffer = undefined;
    try checkVulkanResult(Vk.c.vkCreateBuffer(logical_device, &buffer_info, null, @ptrCast(*Vk.c.VkBuffer, &buffer)));
    return buffer;
}

fn getBufferMemoryRequirements(logical_device: Vk.Device, buffer: Vk.Buffer) Vk.c.VkMemoryRequirements {
    var requirements: Vk.c.VkMemoryRequirements = undefined;
    Vk.c.vkGetBufferMemoryRequirements(logical_device, buffer, &requirements);
    return requirements;
}

// Idea
// Uniform buffers:
//      Allocate memory and reserve space for all uniform buffers. Fill buffer as needed in order of rendering.
//      This means there is no fixed spot for a specific object, they get assigned a place in the buffer as needed.
//      For objects using the same uniform data structure there are two options.
//          - Use dynamic offsets to specify where the buffer is.
//          - Store data in an array and push an index in the push constants to tell the object where to get it's data.
//      For uploading the data there are three two options:
//          - Easy: Write directly to 'device local' and 'host visable' storage. However this memory might be limited (256MB on AMD)
//          - Hard: Write to a staging buffer in 'host visable' storage and copy to device local storage (just as with textures and fixed vertex buffers)
//              It's one copy extra via the vulkan api with command buffers and stuff, but it might end up in faster memory. To investigate. Interface can be the same?
//
// Textures:
//      Allocate memory ... ?
//      Have one big array of image descriptors (?) and push the image index via push constants or uniform buffer (or maybe even vertex buffer?)
//      Upload via staging buffer and transform to appropriate layout via temporary command buffers.
//
// Vertex and Index buffers:
//      Similar to textures allocate memory ... ?
//      Put everything in as few buffers as possible. It's possible to only have one binding on my AMD card for example and just use the offset to select where to start.
//      However on the Intel GPU the max offset is rather low (2047 bytes), so there we probably have to set descriptors for every mesh or so?
//      It might be possible to use vkCmdDraw(... firstVertex ...) or vkCmdDrawIndexed(... vertexOffset ...) to select data in the buffer??
const DeviceMemoryStore = struct {
    const Self = @This();

    pub const BufferingMode = enum {
        Single,
        Double,
        Triple,

        pub fn getBufferCount(self: BufferingMode) u2 {
            return switch (self) {
                .Single => 1,
                .Double => 2,
                .Triple => 3,
            };
        }
    };

    pub const ConfigurationRequest = struct {
        default_allocation_size: u64,
        default_staging_buffer_size: u64,

        /// if `null` it'll use the maximum from the device properties
        maximum_uniform_buffer_size: ?u64,
        buffering_mode: BufferingMode,
    };

    pub const Configuration = struct {
        min_uniform_buffer_offset_alignment: u64,
        non_coherent_atom_size: u64,
        default_allocation_size: u64,
        maximum_uniform_buffer_size: u64,
        buffering_mode: BufferingMode,

        pub fn initFromRequest(request: ConfigurationRequest, limits: Vk.c.VkPhysicalDeviceLimits) Configuration {
            return .{
                .min_uniform_buffer_offset_alignment = limits.minUniformBufferOffsetAlignment,
                .non_coherent_atom_size = limits.nonCoherentAtomSize,
                .default_allocation_size = alignInteger(request.default_allocation_size, std.math.max(limits.minUniformBufferOffsetAlignment, limits.nonCoherentAtomSize)),
                .maximum_uniform_buffer_size = std.math.min(request.maximum_uniform_buffer_size orelse limits.maxUniformBufferRange, limits.maxUniformBufferRange),
                .buffering_mode = request.buffering_mode,
            };
        }

        pub fn getSingleBufferingSize(self: Configuration, minimum_size: u64) u64 {
            return alignInteger(std.math.max(minimum_size, self.default_allocation_size), std.math.max(self.min_uniform_buffer_offset_alignment, self.non_coherent_atom_size));
        }
    };

    const CommandPools = struct {
        transfer: Vk.CommandPool,
        graphics: Vk.CommandPool,
        transfer_queue_ownership_semaphore: Vk.Semaphore,
        pub fn init(logical_device: Vk.Device, queues: Queues) !CommandPools {
            return CommandPools{
                .transfer = try createCommandPool(logical_device, Vk.c.VK_COMMAND_POOL_CREATE_TRANSIENT_BIT, queues.transfer_index),
                .graphics = try createCommandPool(logical_device, Vk.c.VK_COMMAND_POOL_CREATE_TRANSIENT_BIT, queues.graphics_index),
                .transfer_queue_ownership_semaphore = try createSemaphore(logical_device),
            };
        }

        pub fn deinit(self: CommandPools, logical_device: Vk.Device) void {
            Vk.c.vkDestroyCommandPool(logical_device, self.transfer, null);
            Vk.c.vkDestroyCommandPool(logical_device, self.graphics, null);
            Vk.c.vkDestroySemaphore(logical_device, self.transfer_queue_ownership_semaphore, null);
        }
    };

    pub const BufferMemoryProperties = struct {
        properties: Vk.c.VkMemoryPropertyFlags,
        usage: Vk.c.VkBufferUsageFlags,
    };

    pub const BufferAllocation = struct {
        buffer: Vk.Buffer,
        device_memory: Vk.DeviceMemory,
        properties: BufferMemoryProperties,
        size: u64,
        used: u64,
        mapped: [*]u8,

        pub fn hasSpace(allocation: BufferAllocation, size: u64) bool {
            return allocation.size > allocation.used + size;
        }
    };

    pub const IdInformation = struct {
        allocation_index: u16,
        size: usize,
        offset: usize,
    };

    pub const BufferID = Handle(Vk.Buffer);
    const BufferIDGenerator = HandleGenerator(BufferID);

    allocator: *mem.Allocator,
    configuration: Configuration,
    physical_device_memory_properties: Vk.c.VkPhysicalDeviceMemoryProperties,
    // not owned
    logical_device: Vk.Device,
    // owned
    command_pools: CommandPools,
    staging_buffer: StagingBuffer,
    buffer_id_generator: BufferIDGenerator,

    buffer_allocations: std.ArrayList(BufferAllocation),
    id_infos: std.ArrayList(IdInformation),
    buffering_index: usize,

    pub fn init(requested_configuration: ConfigurationRequest, core_graphics_device_data: CoreGraphicsDeviceData, allocator: *mem.Allocator) !Self {
        var self: Self = undefined;
        self.allocator = allocator;
        self.configuration = Configuration.initFromRequest(requested_configuration, core_graphics_device_data.getPhysicalDeviceProperties().limits);
        Vk.c.vkGetPhysicalDeviceMemoryProperties(core_graphics_device_data.physical_device, &self.physical_device_memory_properties);
        self.logical_device = core_graphics_device_data.logical_device;
        self.command_pools = try CommandPools.init(self.logical_device, core_graphics_device_data.queues);
        errdefer self.command_pools.deinit(self.logical_device);
        self.staging_buffer = try StagingBuffer.init(requested_configuration.default_staging_buffer_size, self.physical_device_memory_properties, self.logical_device);
        errdefer self.staging_buffer.deinit();
        self.buffer_id_generator = @TypeOf(self.buffer_id_generator).init(allocator);
        self.buffer_allocations = @TypeOf(self.buffer_allocations).init(allocator);
        self.id_infos = @TypeOf(self.id_infos).init(allocator);
        self.buffering_index = 0;
        return self;
    }

    pub fn deinit(self: Self) void {
        // if waiting fails we will just destroy our objects
        _ = Vk.c.vkDeviceWaitIdle(self.logical_device);
        self.command_pools.deinit(self.logical_device);
        self.staging_buffer.deinit(self.logical_device);
        self.buffer_id_generator.deinit();
        for (self.buffer_allocations.span()) |allocation| {
            Vk.c.vkDestroyBuffer(self.logical_device, allocation.buffer, null);
            Vk.c.vkUnmapMemory(self.logical_device, allocation.device_memory);
            Vk.c.vkFreeMemory(self.logical_device, allocation.device_memory, null);
        }
        self.buffer_allocations.deinit();
        self.id_infos.deinit();
    }

    fn createNewBuffer(self: *Self, minimum_size: u64, properties: BufferMemoryProperties) !BufferID {
        const size = self.configuration.getSingleBufferingSize(minimum_size);
        const total_size = size * self.configuration.buffering_mode.getBufferCount();
        const buffer = try createBuffer(self.logical_device, total_size, properties.usage);
        errdefer Vk.c.vkDestroyBuffer(self.logical_device, buffer, null);
        const requirements = getBufferMemoryRequirements(self.logical_device, buffer);
        const device_memory = try allocateMemory(self.physical_device_memory_properties, self.logical_device, requirements, properties.properties);
        errdefer Vk.c.vkFreeMemory(self.logical_device, device_memory, null);
        try checkVulkanResult(Vk.c.vkBindBufferMemory(self.logical_device, buffer, device_memory, 0));
        var mapped_memory: [*]u8 = undefined;
        try checkVulkanResult(Vk.c.vkMapMemory(self.logical_device, device_memory, 0, total_size, 0, @ptrCast([*]?*c_void, &mapped_memory)));
        try self.buffer_allocations.append(.{
            .buffer = buffer,
            .device_memory = device_memory,
            .properties = properties,
            .size = size,
            .used = minimum_size,
            .mapped = mapped_memory,
        });
        errdefer _ = self.buffer_allocations.pop();
        const id = try self.buffer_id_generator.newHandle();
        errdefer self.buffer_id_generator.discard(id) catch unreachable;
        try ArrayListExtension(IdInformation).assignAtPositionAndResizeIfNecessary(&self.id_infos, id.index, .{
            .allocation_index = @intCast(u16, self.buffer_allocations.len - 1),
            .size = minimum_size,
            .offset = 0,
        });
        return id;
    }

    pub fn reserveBufferSpace(self: *Self, size: u64, memory_properties: BufferMemoryProperties) !BufferID {
        if (try self.findSpaceInExistingBuffer(size, memory_properties)) |id| {
            return id;
        }
        return self.createNewBuffer(size, memory_properties);
    }

    pub fn isValidBufferId(self: Self, id: BufferID) bool {
        return self.buffer_id_generator.isValid(id);
    }

    pub fn findSpaceInExistingBuffer(self: *Self, size: u64, memory_properties: BufferMemoryProperties) !?BufferID {
        for (self.buffer_allocations.span()) |*allocation_info, i| {
            if (std.meta.eql(allocation_info.properties, memory_properties) and allocation_info.hasSpace(size)) {
                const id = try self.buffer_id_generator.newHandle();
                try ArrayListExtension(IdInformation).assignAtPositionAndResizeIfNecessary(&self.id_infos, id.index, .{
                    .allocation_index = @intCast(u16, i),
                    .size = size,
                    .offset = allocation_info.used,
                });
                allocation_info.used = alignInteger(allocation_info.used + size, self.configuration.min_uniform_buffer_offset_alignment);
                return id;
            }
        }
        return null;
    }

    pub fn getMappedSlice(self: Self, id: BufferID) []u8 {
        std.debug.assert(self.isValidBufferId(id));
        const info = self.id_infos.at(id.index);
        const allocation = self.buffer_allocations.at(info.allocation_index);
        return (allocation.mapped + allocation.size * self.buffering_index)[info.offset..info.offset+info.size];
    }

    pub fn flushAndSwitchBuffers(self: *Self) !void {
        var mapped_ranges = try std.ArrayList(Vk.c.VkMappedMemoryRange).initCapacity(self.allocator, self.buffer_allocations.len);
        defer mapped_ranges.deinit();
        for (self.buffer_allocations.span()) |allocation| {
            mapped_ranges.appendAssumeCapacity(.{
                .sType = .VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
                .pNext = null,
                .memory = allocation.device_memory,
                .offset = allocation.size * self.buffering_index,
                .size = alignInteger(allocation.used, self.configuration.non_coherent_atom_size),
            });
        }
        try checkVulkanResult(Vk.c.vkFlushMappedMemoryRanges(self.logical_device, @intCast(u32, mapped_ranges.len), mapped_ranges.span().ptr));
        self.buffering_index = (self.buffering_index + 1) % self.configuration.buffering_mode.getBufferCount();
    }

    // pub fn getDescriptorBufferInfoOnlyForBufferId(self: Self, frame: u32, buffer_id: BufferID) Vk.c.VkDescriptorBufferInfo {
    //     std.debug.assert(self.isValidBufferId(buffer_id));
    //     var buffer_info = self.buffer_ranges.at(buffer_id.index);
    //     const size_per_frame = self.read_write_buffer_allocations.get(buffer_info.buffer.?).?.value.size_per_frame;
    //     buffer_info.offset += size_per_frame * frame;
    //     return buffer_info;
    // }

    fn getVkDescriptorBufferInfoFromAllocationAndBufferingMode(allocation: BufferAllocation, buffering_mode: BufferingMode) Vk.c.VkDescriptorBufferInfo {
        return .{
            .buffer = allocation.buffer,
            .offset = 0,
            .range = allocation.size * buffering_mode.getBufferCount(),
        };
    }

    pub fn getVkBufferForBufferId(self: Self, id: BufferID) Vk.Buffer {
        std.debug.assert(self.isValidBufferId(id));
        return self.buffer_allocations.at(self.id_infos.at(id.index).allocation_index).buffer;
    }

    // pub fn getVkDeviceMemoryForBufferId(self: Self, id: BufferID) Vk.DeviceMemory {
    //     const buffer = self.getVkBufferForBufferId(id);
    //     return self.read_write_buffer_allocations.get(buffer).?.value.device_memory;
    // }
};

fn findMemoryType(memory_properties: Vk.c.VkPhysicalDeviceMemoryProperties, typeFilter: u32, properties: Vk.c.VkMemoryPropertyFlags) !u32 {
    var i: u32 = 0;
    while (i < memory_properties.memoryTypeCount) {
        if ((typeFilter & (@as(u32, 1) << @intCast(u5, i))) != 0 and
            ((memory_properties.memoryTypes[i].propertyFlags & properties) == properties))
        {
            return i;
        }
        i += 1;
    }
    return error.FailedToFindSuitableMemoryType;
}

fn allocateMemory(physical_device_memory_properties: Vk.c.VkPhysicalDeviceMemoryProperties, logical_device: Vk.Device, requirements: Vk.c.VkMemoryRequirements, properties: Vk.c.VkMemoryPropertyFlags) !Vk.DeviceMemory {
    const allocInfo = Vk.c.VkMemoryAllocateInfo{
        .sType = .VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .pNext = null,
        .allocationSize = requirements.size,
        .memoryTypeIndex = try findMemoryType(physical_device_memory_properties, requirements.memoryTypeBits, properties),
    };
    var device_pointer: Vk.DeviceMemory = undefined;
    try checkVulkanResult(Vk.c.vkAllocateMemory(logical_device, &allocInfo, null, @ptrCast(*Vk.c.VkDeviceMemory, &device_pointer)));
    return device_pointer;
}

const StagingBuffer = struct {
    const Self = @This();

    buffer: Vk.Buffer,
    device_memory: Vk.DeviceMemory,
    mapped: []u8,

    pub fn init(size: u64, physical_device_memory_properties: Vk.c.VkPhysicalDeviceMemoryProperties, logical_device: Vk.Device) !Self {
        const buffer = try createBuffer(logical_device, size, Vk.c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
        errdefer Vk.c.vkDestroyBuffer(logical_device, buffer, null);
        const requirements = getBufferMemoryRequirements(logical_device, buffer);
        const device_memory = try allocateMemory(physical_device_memory_properties, logical_device, requirements, Vk.c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | Vk.c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
        errdefer Vk.c.vkFreeMemory(logical_device, device_memory, null);
        try checkVulkanResult(Vk.c.vkBindBufferMemory(logical_device, buffer, device_memory, 0));
        var mapped: [*]u8 = undefined;
        try checkVulkanResult(Vk.c.vkMapMemory(logical_device, device_memory, 0, requirements.size, 0, @ptrCast(*?*c_void, &mapped)));
        return Self{
            .buffer = buffer,
            .device_memory = device_memory,
            .mapped = mapped[0..size],
        };
    }

    pub fn deinit(self: Self, logical_device: Vk.Device) void {
        Vk.c.vkDestroyBuffer(logical_device, self.buffer, null);
        Vk.c.vkFreeMemory(logical_device, self.device_memory, null);
    }
};

test "Initializing a device memory store should succeed" {
    try glfw.init();
    defer glfw.deinit();
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyTestInstance(instance);
    const window = try Window.init(10, 10, "");
    defer window.deinit();
    const core_graphics_device_data = try CoreGraphicsDeviceData.init(instance, window, testing.allocator);
    defer core_graphics_device_data.deinit(instance);

    const config = DeviceMemoryStore.ConfigurationRequest{
        .default_allocation_size = 1e3,
        .default_staging_buffer_size = 1e4,
        .maximum_uniform_buffer_size = null,
        .buffering_mode = .Single,
    };
    const store = try DeviceMemoryStore.init(config, core_graphics_device_data, testing.allocator);
    defer store.deinit();
    testing.expect(store.configuration.default_allocation_size >= config.default_allocation_size);
    testing.expect(store.staging_buffer.mapped.len >= config.default_staging_buffer_size);
}

fn allocateUniformBuffer(store: *DeviceMemoryStore, size: u64) !DeviceMemoryStore.BufferID {
    return try store.reserveBufferSpace(size, .{ .usage = Vk.c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, .properties = Vk.c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT | Vk.c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT });
}

test "reserving a buffer should succeed" {
    try glfw.init();
    defer glfw.deinit();
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyTestInstance(instance);
    const window = try Window.init(10, 10, "");
    defer window.deinit();
    const core_graphics_device_data = try CoreGraphicsDeviceData.init(instance, window, testing.allocator);
    defer core_graphics_device_data.deinit(instance);

    const config = DeviceMemoryStore.ConfigurationRequest{
        .default_allocation_size = 1e3,
        .default_staging_buffer_size = 1,
        .maximum_uniform_buffer_size = null,
        .buffering_mode = .Single,
    };
    var store = try DeviceMemoryStore.init(config, core_graphics_device_data, testing.allocator);
    defer store.deinit();
    const buffer_id = try allocateUniformBuffer(&store, 100);
    testing.expect(store.isValidBufferId(buffer_id));
}

test "reserving multiple buffers which fit in one allocation should result in one allocation" {
    try glfw.init();
    defer glfw.deinit();
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyTestInstance(instance);
    const window = try Window.init(10, 10, "");
    defer window.deinit();
    const core_graphics_device_data = try CoreGraphicsDeviceData.init(instance, window, testing.allocator);
    defer core_graphics_device_data.deinit(instance);

    const config = DeviceMemoryStore.ConfigurationRequest{
        .default_allocation_size = 1e3,
        .default_staging_buffer_size = 1,
        .maximum_uniform_buffer_size = null,
        .buffering_mode = .Double,
    };
    var store = try DeviceMemoryStore.init(config, core_graphics_device_data, testing.allocator);
    defer store.deinit();
    var buffers: [4]DeviceMemoryStore.BufferID = undefined;
    for (buffers) |*buf| {
        buf.* = try allocateUniformBuffer(&store, store.configuration.default_allocation_size / (buffers.len * 2));
    }
    testing.expectEqual(@as(usize, 1), store.buffer_allocations.len);
    for (buffers) |id| {
        testing.expectEqual(store.getVkBufferForBufferId(buffers[0]), store.getVkBufferForBufferId(id));
    }
}

test "reserving multiple buffers which do not fit in one allocation should have different VkBuffers" {
    try glfw.init();
    defer glfw.deinit();
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyTestInstance(instance);
    const window = try Window.init(10, 10, "");
    defer window.deinit();
    const core_graphics_device_data = try CoreGraphicsDeviceData.init(instance, window, testing.allocator);
    defer core_graphics_device_data.deinit(instance);

    const config = DeviceMemoryStore.ConfigurationRequest{
        .default_allocation_size = 1,
        .default_staging_buffer_size = 1,
        .maximum_uniform_buffer_size = null,
        .buffering_mode = .Single,
    };
    var store = try DeviceMemoryStore.init(config, core_graphics_device_data, testing.allocator);
    defer store.deinit();

    const buffer_id1 = try allocateUniformBuffer(&store, store.configuration.default_allocation_size);
    const buffer_id2 = try allocateUniformBuffer(&store, store.configuration.default_allocation_size);
    testing.expect(store.getVkBufferForBufferId(buffer_id1) != store.getVkBufferForBufferId(buffer_id2));
}

test "getting mapped pointers for different frames should have an offset of default_allocation_size" {
    try glfw.init();
    defer glfw.deinit();
    const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
    defer destroyTestInstance(instance);
    const window = try Window.init(10, 10, "");
    defer window.deinit();
    const core_graphics_device_data = try CoreGraphicsDeviceData.init(instance, window, testing.allocator);
    defer core_graphics_device_data.deinit(instance);

    const config = DeviceMemoryStore.ConfigurationRequest{
        .default_allocation_size = 1e3,
        .default_staging_buffer_size = 1,
        .maximum_uniform_buffer_size = null,
        .buffering_mode = .Triple,
    };
    var store = try DeviceMemoryStore.init(config, core_graphics_device_data, testing.allocator);
    defer store.deinit();

    const buffer_id = try allocateUniformBuffer(&store, 200);

    const slice0 = store.getMappedSlice(buffer_id);
    try store.flushAndSwitchBuffers();
    const slice1 = store.getMappedSlice(buffer_id);
    testing.expectEqual(slice0.ptr + store.configuration.default_allocation_size, slice1.ptr);
}

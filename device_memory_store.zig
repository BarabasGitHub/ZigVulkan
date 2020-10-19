const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const debug = std.debug;

usingnamespace @import("Utilities/handle_generator.zig");

const glfw = @import("glfw_wrapper.zig");
const Window = @import("window.zig").Window;
usingnamespace @import("vulkan_instance.zig");
usingnamespace @import("vulkan_image.zig");
usingnamespace @import("vulkan_graphics_device.zig");
usingnamespace @import("device_and_queues.zig");

usingnamespace @import("vulkan_general.zig");

fn ArrayListExtension(comptime Type: type) type {
    return struct {
        const Self = std.ArrayList(Type);

        pub fn ensureSize(self: *Self, size: usize) !void {
            if (self.items.len < size) {
                try self.resize(size);
            }
        }

        pub fn assignAtPositionAndResizeIfNecessary(self: *Self, index: usize, value: Type) !void {
            try ensureSize(self, index + 1);
            self.items[index] = value;
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

fn getImageMemoryRequirements(logical_device: Vk.Device, image: Vk.Image) Vk.c.VkMemoryRequirements {
    var requirements: Vk.c.VkMemoryRequirements = undefined;
    Vk.c.vkGetImageMemoryRequirements(logical_device, image, &requirements);
    return requirements;
}

// Idea
// Uniform buffers:
//      Allocate memory and reserve space for all uniform buffers. Fill buffer as needed in order of rendering.
//      This means there is no fixed spot for a specific object, they get assigned a place in the buffer as needed.
//      For objects using the same uniform data structure there are two options.
//          - Use dynamic offsets to specify where the buffer is.
//          - Store data in an array and push an index in the push constants to tell the object where to get it's data.
//      For uploading the data there are two options:
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
pub const DeviceMemoryStore = struct {
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
        default_staging_upload_buffer_size: u64,
        default_staging_download_buffer_size: u64,

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

        pub fn getSingleBufferingSize(self: Configuration, requested_size: u64) u64 {
            return alignInteger(std.math.max(requested_size, self.default_allocation_size), std.math.max(self.min_uniform_buffer_offset_alignment, self.non_coherent_atom_size));
        }

        pub fn adjustUniformBufferSize(self: Configuration, requsted_size: u64) u64 {
            debug.assert(requsted_size <= self.maximum_uniform_buffer_size);
            return alignInteger(requsted_size, self.min_uniform_buffer_offset_alignment);
        }
    };

    const CommandPools = struct {
        transfer: Vk.CommandPool,
        graphics: Vk.CommandPool,
        transfer_queue_ownership_semaphore: Vk.Semaphore,
        pub fn init(logical_device: Vk.Device, transfer_queue: Queue, graphics_queue: Queue) !CommandPools {
            return CommandPools{
                .transfer = try transfer_queue.createCommandPool(logical_device, Vk.c.VK_COMMAND_POOL_CREATE_TRANSIENT_BIT),
                .graphics = try graphics_queue.createCommandPool(logical_device, Vk.c.VK_COMMAND_POOL_CREATE_TRANSIENT_BIT),
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
            return allocation.size >= allocation.used + size;
        }
    };

    pub const BufferIdInformation = struct {
        allocation_index: u32,
        size: u64,
    };

    pub const BufferID = Handle(Vk.Buffer);
    const BufferIDGenerator = HandleGenerator(BufferID);

    const ImageIdInformation = struct {
        image: Vk.Image,
        layout: Vk.c.VkImageLayout,
        format: Vk.c.VkFormat,
        // this should go somewhere else if not every image has a seprate memory allocation
        device_memory: Vk.DeviceMemory,
    };

    pub const ImageID = Handle(Vk.Image);
    const ImageIDGenerator = HandleGenerator(ImageID);

    allocator: *mem.Allocator,
    configuration: Configuration,
    physical_device_memory_properties: Vk.c.VkPhysicalDeviceMemoryProperties,
    // not owned
    logical_device: Vk.Device,
    // owned
    command_pools: CommandPools,
    staging_upload_buffer: StagingBuffer,
    staging_download_buffer: StagingBuffer,

    buffer_id_generator: BufferIDGenerator,

    buffer_allocations: std.ArrayList(BufferAllocation),
    buffer_id_infos: std.ArrayList(BufferIdInformation),
    buffering_index: usize,

    image_id_generator: ImageIDGenerator,
    image_id_infos: std.ArrayList(ImageIdInformation),

    pub fn init(requested_configuration: ConfigurationRequest, physical_device: Vk.PhysicalDevice, logical_device: Vk.Device, transfer_queue: Queue, graphics_queue: Queue, allocator: *mem.Allocator) !Self {
        var self: Self = undefined;
        self.allocator = allocator;
        self.configuration = Configuration.initFromRequest(requested_configuration, getPhysicalDeviceProperties(physical_device).limits);
        Vk.c.vkGetPhysicalDeviceMemoryProperties(physical_device, &self.physical_device_memory_properties);
        self.logical_device = logical_device;
        self.command_pools = try CommandPools.init(self.logical_device, transfer_queue, graphics_queue);
        errdefer self.command_pools.deinit(self.logical_device);
        self.staging_upload_buffer = try StagingBuffer.initUpload(requested_configuration.default_staging_upload_buffer_size, self.physical_device_memory_properties, self.logical_device);
        errdefer self.staging_upload_buffer.deinit(self.logical_device);
        self.staging_download_buffer = try StagingBuffer.initDownload(requested_configuration.default_staging_download_buffer_size, self.physical_device_memory_properties, self.logical_device);
        errdefer self.staging_download_buffer.deinit(self.logical_device);
        self.buffer_id_generator = @TypeOf(self.buffer_id_generator).init(allocator);
        self.buffer_allocations = @TypeOf(self.buffer_allocations).init(allocator);
        self.buffer_id_infos = @TypeOf(self.buffer_id_infos).init(allocator);
        self.buffering_index = 0;

        self.image_id_generator = @TypeOf(self.image_id_generator).init(allocator);
        self.image_id_infos = @TypeOf(self.image_id_infos).init(allocator);
        return self;
    }

    pub fn deinit(self: Self) void {
        // if waiting fails we will just destroy our objects
        _ = Vk.c.vkDeviceWaitIdle(self.logical_device);
        self.command_pools.deinit(self.logical_device);
        self.staging_upload_buffer.deinit(self.logical_device);
        self.staging_download_buffer.deinit(self.logical_device);

        self.buffer_id_generator.deinit();
        for (self.buffer_allocations.items) |allocation| {
            Vk.c.vkDestroyBuffer(self.logical_device, allocation.buffer, null);
            Vk.c.vkUnmapMemory(self.logical_device, allocation.device_memory);
            Vk.c.vkFreeMemory(self.logical_device, allocation.device_memory, null);
        }
        self.buffer_allocations.deinit();
        self.buffer_id_infos.deinit();

        self.image_id_generator.deinit();
        for (self.image_id_infos.items) |image_id_info| {
            Vk.c.vkDestroyImage(self.logical_device, image_id_info.image, null);
            Vk.c.vkFreeMemory(self.logical_device, image_id_info.device_memory, null);
        }
        self.image_id_infos.deinit();
    }

    pub fn reserveBufferSpace(self: *Self, requsted_size: u64, memory_properties: BufferMemoryProperties) !BufferID {
        const size = self.configuration.adjustUniformBufferSize(requsted_size);
        const allocation_index = if (self.findSpaceInExistingBufferAllocation(size, memory_properties)) |index| b: {
            break :b index;
        } else b: {
            try self.createNewBufferAllocation(size, memory_properties);
            break :b self.buffer_allocations.items.len - 1;
        };
        const id = try self.buffer_id_generator.newHandle();
        errdefer self.buffer_id_generator.discard(id) catch unreachable;
        try ArrayListExtension(BufferIdInformation).assignAtPositionAndResizeIfNecessary(&self.buffer_id_infos, id.index, .{
            .allocation_index = @intCast(u32, allocation_index),
            .size = size,
        });
        self.buffer_allocations.items[allocation_index].used += size;
        return id;
    }

    fn createNewBufferAllocation(self: *Self, requested_size: u64, properties: BufferMemoryProperties) !void {
        const size = self.configuration.getSingleBufferingSize(requested_size);
        const total_size = size * self.configuration.buffering_mode.getBufferCount();
        const buffer = try createBuffer(self.logical_device, total_size, properties.usage);
        errdefer Vk.c.vkDestroyBuffer(self.logical_device, buffer, null);
        const requirements = getBufferMemoryRequirements(self.logical_device, buffer);
        const device_memory = try allocateDeviceMemory(self.physical_device_memory_properties, self.logical_device, requirements, properties.properties);
        errdefer Vk.c.vkFreeMemory(self.logical_device, device_memory, null);
        try checkVulkanResult(Vk.c.vkBindBufferMemory(self.logical_device, buffer, device_memory, 0));
        var mapped_memory: [*]u8 = undefined;
        try checkVulkanResult(Vk.c.vkMapMemory(self.logical_device, device_memory, 0, total_size, 0, @ptrCast([*]?*c_void, &mapped_memory)));
        try self.buffer_allocations.append(.{
            .buffer = buffer,
            .device_memory = device_memory,
            .properties = properties,
            .size = size,
            .used = 0,
            .mapped = mapped_memory,
        });
    }

    fn findSpaceInExistingBufferAllocation(self: *Self, size: u64, memory_properties: BufferMemoryProperties) ?usize {
        for (self.buffer_allocations.span()) |*allocation_info, i| {
            if (std.meta.eql(allocation_info.properties, memory_properties) and allocation_info.hasSpace(size)) {
                return i;
            }
        }
        return null;
    }

    pub fn isValidBufferId(self: Self, id: BufferID) bool {
        return self.buffer_id_generator.isValid(id);
    }

    pub fn getMappedBufferSlices(self: Self, allocator: *mem.Allocator) ![][]u8 {
        const slices = try allocator.alloc([]u8, self.buffer_allocations.items.len);
        errdefer allocator.free(slices);
        for (self.buffer_allocations.items) |allocation, i| {
            slices[i] = (allocation.mapped + allocation.size * self.buffering_index)[0..allocation.used];
        }
        return slices;
    }

    pub fn flushAndSwitchBuffers(self: *Self) !void {
        var mapped_ranges = try std.ArrayList(Vk.c.VkMappedMemoryRange).initCapacity(self.allocator, self.buffer_allocations.items.len);
        defer mapped_ranges.deinit();
        for (self.buffer_allocations.items) |allocation| {
            mapped_ranges.appendAssumeCapacity(.{
                .sType = .VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
                .pNext = null,
                .memory = allocation.device_memory,
                .offset = allocation.size * self.buffering_index,
                .size = alignInteger(allocation.used, self.configuration.non_coherent_atom_size),
            });
        }
        try checkVulkanResult(Vk.c.vkFlushMappedMemoryRanges(self.logical_device, @intCast(u32, mapped_ranges.items.len), mapped_ranges.items.ptr));
        self.buffering_index = (self.buffering_index + 1) % self.configuration.buffering_mode.getBufferCount();
    }

    fn getVkDescriptorBufferInfoFromAllocationAndBufferingMode(allocation: BufferAllocation, buffering_mode: BufferingMode) Vk.c.VkDescriptorBufferInfo {}

    pub fn getVkBufferForBufferId(self: Self, id: BufferID) Vk.Buffer {
        debug.assert(self.isValidBufferId(id));
        return self.buffer_allocations.items[self.buffer_id_infos.items[id.index].allocation_index].buffer;
    }

    pub fn getVkDescriptorBufferInfoForBufferId(self: Self, id: BufferID) Vk.c.VkDescriptorBufferInfo {
        debug.assert(self.isValidBufferId(id));
        const info = &self.buffer_id_infos.items[id.index];
        return .{
            .buffer = self.buffer_allocations.items[info.allocation_index].buffer,
            .offset = 0,
            .range = info.size,
        };
    }

    // images

    pub fn allocateImage2D(self: *Self, extent: Vk.c.VkExtent2D, usage: u32, format: Vk.c.VkFormat) !ImageID {
        std.debug.assert(usage != 0);
        const image = try create2DImage(extent, format, usage, self.logical_device);
        errdefer Vk.c.vkDestroyImage(self.logical_device, image, null);
        const memory_requirements = getImageMemoryRequirements(self.logical_device, image);
        const device_memory = try allocateDeviceMemory(self.physical_device_memory_properties, self.logical_device, memory_requirements, Vk.c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
        errdefer Vk.c.vkFreeMemory(self.logical_device, device_memory, null);
        try checkVulkanResult(Vk.c.vkBindImageMemory(self.logical_device, image, device_memory, 0));

        const id = try self.image_id_generator.newHandle();
        errdefer self.image_id_generator.discard(id) catch unreachable;
        try ArrayListExtension(ImageIdInformation).assignAtPositionAndResizeIfNecessary(&self.image_id_infos, id.index, .{
            .image = image,
            .layout = Vk.c.VkImageLayout.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .format = format,
            .device_memory = device_memory,
        });
        return id;
    }

    pub fn uploadImage2D(self: *Self, comptime DataType: type, image_id: ImageID, extent: Vk.c.VkExtent2D, data: []const DataType, transfer_queue: Queue, graphics_queue: Queue) !void {
        std.debug.assert(extent.width * extent.height == data.len);
        const data_size = data.len * @sizeOf(DataType);
        if (data_size > self.staging_upload_buffer.mapped.len) {
            var size = self.staging_upload_buffer.mapped.len;
            while (size < data_size)
                size += (size + 1) / 2;
            try self.resetStagingUploadBuffer(size);
        }
        // TODO: When we get a real image class, copy without padding
        std.mem.copy(u8, self.staging_upload_buffer.mapped[0..data_size], std.mem.sliceAsBytes(data)[0..data_size]);
        const image = self.image_id_infos.items[image_id.index].image;
        const transfer_command_buffer = try createTemporaryCommandBuffer(self.logical_device, self.command_pools.transfer);
        const graphics_command_buffer = try createTemporaryCommandBuffer(self.logical_device, self.command_pools.graphics);
        try copyBufferToImage(
            extent,
            self.staging_upload_buffer.buffer,
            image,
            transfer_command_buffer,
            transfer_queue,
            graphics_command_buffer,
            graphics_queue,
            self.command_pools.transfer_queue_ownership_semaphore,
        );
        try transfer_queue.waitIdle();
        Vk.c.vkFreeCommandBuffers(self.logical_device, self.command_pools.transfer, 1, &transfer_command_buffer);
        try graphics_queue.waitIdle();
        Vk.c.vkFreeCommandBuffers(self.logical_device, self.command_pools.graphics, 1, &graphics_command_buffer);
    }

    pub fn downloadImage2DAndDiscard(self: *Self, comptime DataType: type, image_id: ImageID, image_layout: Vk.c.VkImageLayout, image_access: Vk.c.VkAccessFlags, extent: Vk.c.VkExtent2D, graphics_queue: Queue) ![]const DataType {
        const data_size = extent.height * extent.width * @sizeOf(DataType);
        if (data_size > self.staging_download_buffer.mapped.len) {
            var size = self.staging_download_buffer.mapped.len;
            while (size < data_size)
                size += (size + 1) / 2;
            try self.resetStagingDownloadBuffer(size);
        }
        const image = self.image_id_infos.items[image_id.index].image;
        // const transfer_command_buffer = try createTemporaryCommandBuffer(self.logical_device, self.command_pools.transfer);
        const graphics_command_buffer = try createTemporaryCommandBuffer(self.logical_device, self.command_pools.graphics);
        try copyImageToBufferAndDiscard(
            extent,
            self.staging_download_buffer.buffer,
            image,
            image_layout,
            image_access,
            graphics_command_buffer,
            graphics_queue,
        );
        try graphics_queue.waitIdle();
        Vk.c.vkFreeCommandBuffers(self.logical_device, self.command_pools.graphics, 1, &graphics_command_buffer);
        return std.mem.bytesAsSlice(DataType, @alignCast(@alignOf(DataType), self.staging_download_buffer.mapped[0..data_size]));
    }

    pub fn isValidImageId(self: Self, id: ImageID) bool {
        return self.image_id_generator.isValid(id);
    }

    pub fn getImageInformation(self: Self, id: ImageID) ImageIdInformation {
        std.debug.assert(self.isValidImageId(id));
        return self.image_id_infos.items[id.index];
    }

    pub fn resetStagingUploadBuffer(self: *Self, size: usize) !void {
        self.staging_upload_buffer.deinit(self.logical_device);
        self.staging_upload_buffer = try StagingBuffer.initUpload(size, self.physical_device_memory_properties, self.logical_device);
    }

    pub fn resetStagingDownloadBuffer(self: *Self, size: usize) !void {
        self.staging_download_buffer.deinit(self.logical_device);
        self.staging_download_buffer = try StagingBuffer.initDownload(size, self.physical_device_memory_properties, self.logical_device);
    }
};

fn createTemporaryCommandBuffer(logical_device: Vk.Device, command_pool: Vk.CommandPool) !Vk.CommandBuffer {
    const allocation_info = Vk.c.VkCommandBufferAllocateInfo{
        .sType = .VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .pNext = null,
        .commandPool = command_pool,
        .level = .VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    var commandBuffer: Vk.CommandBuffer = undefined;
    try checkVulkanResult(Vk.c.vkAllocateCommandBuffers(logical_device, &allocation_info, @ptrCast(*Vk.c.VkCommandBuffer, &commandBuffer)));
    return commandBuffer;
}

fn copyBufferToImage(
    extent: Vk.c.VkExtent2D,
    buffer: Vk.Buffer,
    image: Vk.Image,
    transfer_command_buffer: Vk.CommandBuffer,
    transfer_queue: Queue,
    graphics_command_buffer: Vk.CommandBuffer,
    graphics_queue: Queue,
    transfer_queue_ownership_semaphore: Vk.Semaphore,
) !void {
    const begin_info = Vk.c.VkCommandBufferBeginInfo{
        .sType = .VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .pNext = null,
        .flags = Vk.c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        .pInheritanceInfo = null,
    };
    try checkVulkanResult(Vk.c.vkBeginCommandBuffer(transfer_command_buffer, &begin_info));

    const image_subresource_layers = Vk.c.VkImageSubresourceLayers{
        .aspectMask = Vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
        .mipLevel = 0,
        .baseArrayLayer = 0,
        .layerCount = 1,
    };
    const image_subresource_range = Vk.c.VkImageSubresourceRange{
        .aspectMask = image_subresource_layers.aspectMask,
        .baseMipLevel = 0,
        .levelCount = 1,
        .baseArrayLayer = image_subresource_layers.baseArrayLayer,
        .layerCount = image_subresource_layers.layerCount,
    };

    transitionImageLayoutToTransferDestination(transfer_command_buffer, image, image_subresource_range);

    const buffer_image_copy = Vk.c.VkBufferImageCopy{
        .bufferOffset = 0,
        .bufferRowLength = extent.width,
        .bufferImageHeight = extent.height,
        .imageSubresource = image_subresource_layers,
        .imageOffset = .{ .x = 0, .y = 0, .z = 0 },
        .imageExtent = .{ .width = extent.width, .height = extent.height, .depth = 1 },
    };
    Vk.c.vkCmdCopyBufferToImage(transfer_command_buffer, buffer, image, .VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &buffer_image_copy);

    transitionImageLayoutToShaderReadOnlyFromTransferDestinationSourceQueue(transfer_command_buffer, transfer_queue.family_index, graphics_queue.family_index, image, image_subresource_range);

    try checkVulkanResult(Vk.c.vkEndCommandBuffer(transfer_command_buffer));

    try transfer_queue.submitSingle(
        &[0]Vk.Semaphore{},
        @ptrCast([*]const Vk.CommandBuffer, &transfer_command_buffer)[0..1],
        @ptrCast([*]const Vk.Semaphore, &transfer_queue_ownership_semaphore)[0..1],
        null,
    );

    try checkVulkanResult(Vk.c.vkBeginCommandBuffer(graphics_command_buffer, &begin_info));

    transitionImageLayoutToShaderReadOnlyFromTransferDestinationDestinationQueue(transfer_queue.family_index, graphics_command_buffer, graphics_queue.family_index, image, image_subresource_range);

    try checkVulkanResult(Vk.c.vkEndCommandBuffer(graphics_command_buffer));

    try graphics_queue.submitSingle(
        @ptrCast([*]const Vk.Semaphore, &transfer_queue_ownership_semaphore)[0..1],
        @ptrCast([*]const Vk.CommandBuffer, &graphics_command_buffer)[0..1],
        &[0]Vk.Semaphore{},
        @as(u32, Vk.c.VK_PIPELINE_STAGE_TRANSFER_BIT),
    );
}

fn copyImageToBufferAndDiscard(
    extent: Vk.c.VkExtent2D,
    buffer: Vk.Buffer,
    image: Vk.Image,
    layout: Vk.c.VkImageLayout,
    image_access: Vk.c.VkAccessFlags,
    command_buffer: Vk.CommandBuffer,
    queue: Queue,
) !void {
    const begin_info = Vk.c.VkCommandBufferBeginInfo{
        .sType = .VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .pNext = null,
        .flags = Vk.c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        .pInheritanceInfo = null,
    };
    try checkVulkanResult(Vk.c.vkBeginCommandBuffer(command_buffer, &begin_info));

    const image_subresource_layers = Vk.c.VkImageSubresourceLayers{
        .aspectMask = Vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
        .mipLevel = 0,
        .baseArrayLayer = 0,
        .layerCount = 1,
    };
    const image_subresource_range = Vk.c.VkImageSubresourceRange{
        .aspectMask = image_subresource_layers.aspectMask,
        .baseMipLevel = 0,
        .levelCount = 1,
        .baseArrayLayer = image_subresource_layers.baseArrayLayer,
        .layerCount = image_subresource_layers.layerCount,
    };

    transitionImageLayout(
        command_buffer,
        .VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        .VK_PIPELINE_STAGE_TRANSFER_BIT,
        image_access,
        Vk.c.VK_ACCESS_TRANSFER_READ_BIT,
        layout,
        .VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        Vk.c.VK_QUEUE_FAMILY_IGNORED,
        Vk.c.VK_QUEUE_FAMILY_IGNORED,
        image,
        image_subresource_range,
    );

    const buffer_image_copy = Vk.c.VkBufferImageCopy{
        .bufferOffset = 0,
        .bufferRowLength = extent.width,
        .bufferImageHeight = extent.height,
        .imageSubresource = image_subresource_layers,
        .imageOffset = .{ .x = 0, .y = 0, .z = 0 },
        .imageExtent = .{ .width = extent.width, .height = extent.height, .depth = 1 },
    };
    Vk.c.vkCmdCopyImageToBuffer(command_buffer, image, .VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, buffer, 1, &buffer_image_copy);

    try checkVulkanResult(Vk.c.vkEndCommandBuffer(command_buffer));

    try queue.submitSingle(
        &[0]Vk.Semaphore{},
        @ptrCast([*]const Vk.CommandBuffer, &command_buffer)[0..1],
        &[0]Vk.Semaphore{},
        null,
    );
}

fn transitionImageLayoutToTransferDestination(command_buffer: Vk.CommandBuffer, image: Vk.Image, subresource_range: Vk.c.VkImageSubresourceRange) void {
    transitionImageLayout(
        command_buffer,
        .VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        .VK_PIPELINE_STAGE_TRANSFER_BIT,
        0,
        Vk.c.VK_ACCESS_TRANSFER_WRITE_BIT,
        .VK_IMAGE_LAYOUT_UNDEFINED,
        .VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        Vk.c.VK_QUEUE_FAMILY_IGNORED,
        Vk.c.VK_QUEUE_FAMILY_IGNORED,
        image,
        subresource_range,
    );
}

fn transitionImageLayoutToTransferSource(command_buffer: Vk.CommandBuffer, image: Vk.Image, subresource_range: Vk.c.VkImageSubresourceRange) void {
    transitionImageLayout(
        command_buffer,
        .VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        .VK_PIPELINE_STAGE_TRANSFER_BIT,
        0,
        Vk.c.VK_ACCESS_TRANSFER_READ_BIT,
        .VK_IMAGE_LAYOUT_UNDEFINED,
        .VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        Vk.c.VK_QUEUE_FAMILY_IGNORED,
        Vk.c.VK_QUEUE_FAMILY_IGNORED,
        image,
        subresource_range,
    );
}

fn transitionImageLayoutToShaderReadOnlyFromTransferDestinationSourceQueue(
    transfer_command_buffer: Vk.CommandBuffer,
    transfer_queue_family: u32,
    graphics_queue_family: u32,
    image: Vk.Image,
    subresource_range: Vk.c.VkImageSubresourceRange,
) void {
    transitionImageLayout(
        transfer_command_buffer,
        .VK_PIPELINE_STAGE_TRANSFER_BIT,
        .VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
        Vk.c.VK_ACCESS_TRANSFER_WRITE_BIT,
        0,
        .VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        transfer_queue_family,
        graphics_queue_family,
        image,
        subresource_range,
    );
}

fn transitionImageLayoutToShaderReadOnlyFromTransferDestinationDestinationQueue(
    transfer_queue_family: u32,
    graphics_command_buffer: Vk.CommandBuffer,
    graphics_queue_family: u32,
    image: Vk.Image,
    subresource_range: Vk.c.VkImageSubresourceRange,
) void {
    transitionImageLayout(
        graphics_command_buffer,
        .VK_PIPELINE_STAGE_TRANSFER_BIT,
        .VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
        0,
        Vk.c.VK_ACCESS_SHADER_READ_BIT,
        .VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        transfer_queue_family,
        graphics_queue_family,
        image,
        subresource_range,
    );
}

fn transitionImageLayout(
    command_buffer: Vk.CommandBuffer,
    source_stage: Vk.c.VkPipelineStageFlagBits,
    destination_stage: Vk.c.VkPipelineStageFlagBits,
    source_access: Vk.c.VkAccessFlags,
    destination_access: Vk.c.VkAccessFlags,
    old_layout: Vk.c.VkImageLayout,
    new_layout: Vk.c.VkImageLayout,
    source_queue: u32,
    destination_queue: u32,
    image: Vk.Image,
    subresource_range: Vk.c.VkImageSubresourceRange,
) void {
    const memory_barrier = Vk.c.VkImageMemoryBarrier{
        .sType = .VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .pNext = null,
        .srcAccessMask = source_access,
        .dstAccessMask = destination_access,
        .oldLayout = old_layout,
        .newLayout = new_layout,
        .srcQueueFamilyIndex = source_queue,
        .dstQueueFamilyIndex = destination_queue,
        .image = image,
        .subresourceRange = subresource_range,
    };
    Vk.c.vkCmdPipelineBarrier(command_buffer, @intCast(u32, @enumToInt(source_stage)), @intCast(u32, @enumToInt(destination_stage)), 0, 0, null, 0, null, 1, &memory_barrier);
}

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

fn allocateDeviceMemory(physical_device_memory_properties: Vk.c.VkPhysicalDeviceMemoryProperties, logical_device: Vk.Device, requirements: Vk.c.VkMemoryRequirements, properties: Vk.c.VkMemoryPropertyFlags) !Vk.DeviceMemory {
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

    pub fn initUpload(size: u64, physical_device_memory_properties: Vk.c.VkPhysicalDeviceMemoryProperties, logical_device: Vk.Device) !Self {
        const buffer = try createBuffer(logical_device, size, Vk.c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
        errdefer Vk.c.vkDestroyBuffer(logical_device, buffer, null);
        const requirements = getBufferMemoryRequirements(logical_device, buffer);
        const device_memory = try allocateDeviceMemory(physical_device_memory_properties, logical_device, requirements, Vk.c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | Vk.c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
        errdefer Vk.c.vkFreeMemory(logical_device, device_memory, null);
        try checkVulkanResult(Vk.c.vkBindBufferMemory(logical_device, buffer, device_memory, 0));
        var mapped: [*]u8 = undefined;
        try checkVulkanResult(Vk.c.vkMapMemory(logical_device, device_memory, 0, size, 0, @ptrCast(*?*c_void, &mapped)));
        return Self{
            .buffer = buffer,
            .device_memory = device_memory,
            .mapped = mapped[0..size],
        };
    }

    pub fn initDownload(size: u64, physical_device_memory_properties: Vk.c.VkPhysicalDeviceMemoryProperties, logical_device: Vk.Device) !Self {
        const buffer = try createBuffer(logical_device, size, Vk.c.VK_BUFFER_USAGE_TRANSFER_DST_BIT);
        errdefer Vk.c.vkDestroyBuffer(logical_device, buffer, null);
        const requirements = getBufferMemoryRequirements(logical_device, buffer);
        const device_memory = try allocateDeviceMemory(physical_device_memory_properties, logical_device, requirements, Vk.c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | Vk.c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
        errdefer Vk.c.vkFreeMemory(logical_device, device_memory, null);
        try checkVulkanResult(Vk.c.vkBindBufferMemory(logical_device, buffer, device_memory, 0));
        var mapped: [*]u8 = undefined;
        try checkVulkanResult(Vk.c.vkMapMemory(logical_device, device_memory, 0, size, 0, @ptrCast(*?*c_void, &mapped)));
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

const TestEnvironment = struct {
    instance: Vk.Instance,
    window: Window,
    core_graphics_device_data: CoreGraphicsDeviceData,

    pub fn init() !TestEnvironment {
        try glfw.init();
        errdefer glfw.deinit();
        const instance = try createTestInstance(try glfw.getRequiredInstanceExtensions());
        errdefer destroyTestInstance(instance);
        const window = try Window.init(10, 10, "");
        errdefer window.deinit();
        const core_graphics_device_data = try CoreGraphicsDeviceData.init(instance, window, testing.allocator);
        errdefer core_graphics_device_data.deinit(instance);
        return TestEnvironment{ .instance = instance, .window = window, .core_graphics_device_data = core_graphics_device_data };
    }

    pub fn deinit(self: TestEnvironment) void {
        defer glfw.deinit();
        defer destroyTestInstance(self.instance);
        defer self.window.deinit();
        defer self.core_graphics_device_data.deinit(self.instance);
    }
};

test "Initializing a device memory store should succeed" {
    var env = try TestEnvironment.init();
    defer env.deinit();

    const config = DeviceMemoryStore.ConfigurationRequest{
        .default_allocation_size = 1e3,
        .default_staging_upload_buffer_size = 1e4,
        .default_staging_download_buffer_size = 1e4,
        .maximum_uniform_buffer_size = null,
        .buffering_mode = .Single,
    };
    const store = try DeviceMemoryStore.init(
        config,
        env.core_graphics_device_data.physical_device,
        env.core_graphics_device_data.logical_device,
        env.core_graphics_device_data.queues.transfer,
        env.core_graphics_device_data.queues.graphics,
        testing.allocator,
    );
    defer store.deinit();
    testing.expect(store.configuration.default_allocation_size >= config.default_allocation_size);
    testing.expect(store.staging_upload_buffer.mapped.len >= config.default_staging_upload_buffer_size);
}

fn reserveUniformBufferStorage(store: *DeviceMemoryStore, size: u64) !DeviceMemoryStore.BufferID {
    return try store.reserveBufferSpace(size, .{ .usage = Vk.c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, .properties = Vk.c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT | Vk.c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT });
}

test "reserving a buffer should succeed" {
    var env = try TestEnvironment.init();
    defer env.deinit();

    const config = DeviceMemoryStore.ConfigurationRequest{
        .default_allocation_size = 1e3,
        .default_staging_upload_buffer_size = 1,
        .default_staging_download_buffer_size = 1,
        .maximum_uniform_buffer_size = null,
        .buffering_mode = .Single,
    };
    var store = try DeviceMemoryStore.init(
        config,
        env.core_graphics_device_data.physical_device,
        env.core_graphics_device_data.logical_device,
        env.core_graphics_device_data.queues.transfer,
        env.core_graphics_device_data.queues.graphics,
        testing.allocator,
    );
    defer store.deinit();
    const buffer_id = try reserveUniformBufferStorage(&store, 100);
    testing.expect(store.isValidBufferId(buffer_id));
}

test "reserving multiple buffers which fit in one allocation should result in one allocation" {
    var env = try TestEnvironment.init();
    defer env.deinit();

    const config = DeviceMemoryStore.ConfigurationRequest{
        .default_allocation_size = 1e3,
        .default_staging_upload_buffer_size = 1,
        .default_staging_download_buffer_size = 1,
        .maximum_uniform_buffer_size = null,
        .buffering_mode = .Double,
    };
    var store = try DeviceMemoryStore.init(
        config,
        env.core_graphics_device_data.physical_device,
        env.core_graphics_device_data.logical_device,
        env.core_graphics_device_data.queues.transfer,
        env.core_graphics_device_data.queues.graphics,
        testing.allocator,
    );
    defer store.deinit();
    var buffers: [4]DeviceMemoryStore.BufferID = undefined;
    for (buffers) |*buf| {
        buf.* = try reserveUniformBufferStorage(&store, store.configuration.default_allocation_size / (buffers.len * 2));
    }
    testing.expectEqual(@as(usize, 1), store.buffer_allocations.items.len);
    for (buffers) |id| {
        testing.expectEqual(store.getVkBufferForBufferId(buffers[0]), store.getVkBufferForBufferId(id));
    }
}

test "reserving multiple buffers which do not fit in one allocation should have different VkBuffers" {
    var env = try TestEnvironment.init();
    defer env.deinit();

    const config = DeviceMemoryStore.ConfigurationRequest{
        .default_allocation_size = 1,
        .default_staging_upload_buffer_size = 1,
        .default_staging_download_buffer_size = 1,
        .maximum_uniform_buffer_size = null,
        .buffering_mode = .Single,
    };
    var store = try DeviceMemoryStore.init(
        config,
        env.core_graphics_device_data.physical_device,
        env.core_graphics_device_data.logical_device,
        env.core_graphics_device_data.queues.transfer,
        env.core_graphics_device_data.queues.graphics,
        testing.allocator,
    );
    defer store.deinit();

    const buffer_id1 = try reserveUniformBufferStorage(&store, store.configuration.default_allocation_size);
    const buffer_id2 = try reserveUniformBufferStorage(&store, store.configuration.default_allocation_size);
    testing.expect(store.getVkBufferForBufferId(buffer_id1) != store.getVkBufferForBufferId(buffer_id2));
}

test "getting mapped pointers for different frames should have an offset of default_allocation_size" {
    var env = try TestEnvironment.init();
    defer env.deinit();

    const config = DeviceMemoryStore.ConfigurationRequest{
        .default_allocation_size = 1e3,
        .default_staging_upload_buffer_size = 1,
        .default_staging_download_buffer_size = 1,
        .maximum_uniform_buffer_size = null,
        .buffering_mode = .Triple,
    };
    var store = try DeviceMemoryStore.init(
        config,
        env.core_graphics_device_data.physical_device,
        env.core_graphics_device_data.logical_device,
        env.core_graphics_device_data.queues.transfer,
        env.core_graphics_device_data.queues.graphics,
        testing.allocator,
    );
    defer store.deinit();

    const buffer_id = try reserveUniformBufferStorage(&store, 200);

    const slices0 = try store.getMappedBufferSlices(testing.allocator);
    defer testing.allocator.free(slices0);
    testing.expectEqual(@as(usize, 1), slices0.len);
    try store.flushAndSwitchBuffers();
    const slices1 = try store.getMappedBufferSlices(testing.allocator);
    defer testing.allocator.free(slices1);
    testing.expectEqual(slices0[0].ptr + store.configuration.default_allocation_size, slices1[0].ptr);
}

test "Allocating a 2d image should succeed" {
    var env = try TestEnvironment.init();
    defer env.deinit();

    const config = DeviceMemoryStore.ConfigurationRequest{
        .default_allocation_size = 1e3,
        .default_staging_upload_buffer_size = 1,
        .default_staging_download_buffer_size = 1,
        .maximum_uniform_buffer_size = null,
        .buffering_mode = .Triple,
    };
    var store = try DeviceMemoryStore.init(
        config,
        env.core_graphics_device_data.physical_device,
        env.core_graphics_device_data.logical_device,
        env.core_graphics_device_data.queues.transfer,
        env.core_graphics_device_data.queues.graphics,
        testing.allocator,
    );
    defer store.deinit();

    const image_id = try store.allocateImage2D(.{ .width = 32, .height = 32 }, Vk.c.VK_IMAGE_USAGE_SAMPLED_BIT, .VK_FORMAT_R8G8B8A8_UNORM);
    testing.expect(store.isValidImageId(image_id));
}

test "Uploading a 2d image should succeed" {
    var env = try TestEnvironment.init();
    defer env.deinit();

    const config = DeviceMemoryStore.ConfigurationRequest{
        .default_allocation_size = 1e3,
        .default_staging_upload_buffer_size = 1,
        .default_staging_download_buffer_size = 1,
        .maximum_uniform_buffer_size = null,
        .buffering_mode = .Triple,
    };
    var store = try DeviceMemoryStore.init(
        config,
        env.core_graphics_device_data.physical_device,
        env.core_graphics_device_data.logical_device,
        env.core_graphics_device_data.queues.transfer,
        env.core_graphics_device_data.queues.graphics,
        testing.allocator,
    );
    defer store.deinit();

    const image_id = try store.allocateImage2D(.{ .width = 32, .height = 32 }, Vk.c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | Vk.c.VK_IMAGE_USAGE_SAMPLED_BIT, .VK_FORMAT_R8G8B8A8_UNORM);
    const data = [_][4]u8{.{ 0x05, 0x80, 0xF0, 0xFF }} ** (32 * 32);
    try store.uploadImage2D([4]u8, image_id, .{ .width = 32, .height = 32 }, &data, env.core_graphics_device_data.queues.transfer, env.core_graphics_device_data.queues.graphics);
}

const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const glfw = @import("glfw_wrapper.zig");
usingnamespace @import("vulkan_general.zig");

pub fn allocateDescriptorSet(layouts: []const Vk.DescriptorSetLayout, pool: Vk.DescriptorPool, logical_device: Vk.Device, sets: []Vk.DescriptorSet) !void {
    std.debug.assert(layouts.len == sets.len);
    const allocInfo = Vk.c.VkDescriptorSetAllocateInfo{
        .sType = .VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .pNext = null,
        .descriptorPool = pool,
        .descriptorSetCount = @intCast(u32, layouts.len),
        .pSetLayouts = layouts.ptr,
    };

    try checkVulkanResult(Vk.c.vkAllocateDescriptorSets(logical_device, &allocInfo, @ptrCast(*Vk.c.VkDescriptorSet, sets.ptr)));
}

pub fn createDescriptorPool(logical_device: Vk.Device) !Vk.DescriptorPool {
    const pool_sizes = [_]Vk.c.VkDescriptorPoolSize{
        .{
            .type = .VK_DESCRIPTOR_TYPE_SAMPLER,
            .descriptorCount = 64,
        },
        .{
            .type = .VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
            .descriptorCount = 64,
        },
        .{
            .type = .VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 64,
        },
        .{
            .type = .VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
            .descriptorCount = 64,
        },
    };

    const pool_info = Vk.c.VkDescriptorPoolCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .pNext = null,
        .poolSizeCount = pool_sizes.len,
        .pPoolSizes = &pool_sizes,
        .maxSets = 128,
        .flags = 0,
    };

    var descriptor_pool: Vk.DescriptorPool = undefined;
    try checkVulkanResult(Vk.c.vkCreateDescriptorPool(logical_device, &pool_info, null, @ptrCast(*Vk.c.VkDescriptorPool, &descriptor_pool)));
    return descriptor_pool;
}

pub const destroyDescriptorPool = Vk.c.vkDestroyDescriptorPool;

pub fn writeUniformBufferToDescriptorSet(device: Vk.Device, buffer_info: Vk.c.VkDescriptorBufferInfo, descriptor_set: Vk.DescriptorSet) void {
    const write_descriptor_sets = [_]Vk.c.VkWriteDescriptorSet{.{
        .sType = .VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .pNext = null,
        .dstSet = descriptor_set,
        .dstBinding = 1,
        .dstArrayElement = 0,
        .descriptorCount = 1,
        .descriptorType = .VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
        .pImageInfo = null,
        .pBufferInfo = &buffer_info,
        .pTexelBufferView = null,
    }};
    Vk.c.vkUpdateDescriptorSets(device, @intCast(u32, write_descriptor_sets.len), &write_descriptor_sets[0], 0, null);
}

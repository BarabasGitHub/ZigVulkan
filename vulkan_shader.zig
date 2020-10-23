const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const glfw = @import("glfw_wrapper.zig");
usingnamespace @import("window.zig");
usingnamespace @import("vulkan_general.zig");
usingnamespace @import("vulkan_instance.zig");
usingnamespace @import("vulkan_graphics_device.zig");

pub fn createShaderModule(shader_data: []const u32, logical_device: Vk.Device) !Vk.ShaderModule {
    const createInfo = Vk.c.VkShaderModuleCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = shader_data.len * @sizeOf(u32),
        .pCode = shader_data.ptr,
    };
    var shaderModule: Vk.ShaderModule = undefined;
    try checkVulkanResult(Vk.c.vkCreateShaderModule(logical_device, &createInfo, null, @ptrCast(*Vk.c.VkShaderModule, &shaderModule)));
    return shaderModule;
}

pub const destroyShaderModule = Vk.c.vkDestroyShaderModule;

// compiled as hlsl: "float4 main() : SV_POSITION { return 0; }"
// glslangValidator.exe -S vert -D -V -e main .\empty_shader.hlsl -x -o empty_shader.txt
const empty_shader: []const u32 = &[_]u32{
    0x07230203, 0x00010000, 0x00080007, 0x00000011, 0x00000000, 0x00020011, 0x00000001, 0x0006000b,
    0x00000001, 0x4c534c47, 0x6474732e, 0x3035342e, 0x00000000, 0x0003000e, 0x00000000, 0x00000001,
    0x0006000f, 0x00000000, 0x00000004, 0x6e69616d, 0x00000000, 0x00000010, 0x00030003, 0x00000005,
    0x000001f4, 0x00040005, 0x00000004, 0x6e69616d, 0x00000000, 0x00070005, 0x00000010, 0x746e6540,
    0x6f507972, 0x4f746e69, 0x75707475, 0x00000074, 0x00040047, 0x00000010, 0x0000000b, 0x00000000,
    0x00020013, 0x00000002, 0x00030021, 0x00000003, 0x00000002, 0x00030016, 0x00000006, 0x00000020,
    0x00040017, 0x00000007, 0x00000006, 0x00000004, 0x0004002b, 0x00000006, 0x0000000b, 0x00000000,
    0x0007002c, 0x00000007, 0x0000000c, 0x0000000b, 0x0000000b, 0x0000000b, 0x0000000b, 0x00040020,
    0x0000000f, 0x00000003, 0x00000007, 0x0004003b, 0x0000000f, 0x00000010, 0x00000003, 0x00050036,
    0x00000002, 0x00000004, 0x00000000, 0x00000003, 0x000200f8, 0x00000005, 0x0003003e, 0x00000010,
    0x0000000c, 0x000100fd, 0x00010038,
};

test "creating a shader module from an empty main hlsl shader should succeed on my machine" {
    try glfw.init();
    defer glfw.deinit();
    const window = try Window.init(200, 200, "test_window");
    defer window.deinit();
    const renderer = try Renderer.init(window, testApplicationInfo(), testExtensions(), testing.allocator);
    defer renderer.deinit();

    const shader_module = try createShaderModule(empty_shader, renderer.core_device_data.logical_device);
    destroyShaderModule(renderer.core_device_data.logical_device, shader_module, null);
}

pub const ShaderStage = enum {
    Fragment,
    Vertex,

    pub fn toShaderStageFlagBits(self: ShaderStage) Vk.c.VkShaderStageFlagBits {
        return switch (self) {
            .Fragment => .VK_SHADER_STAGE_FRAGMENT_BIT,
            .Vertex => .VK_SHADER_STAGE_VERTEX_BIT,
        };
    }
};

pub const Shader = struct {
    module: Vk.ShaderModule,
    stage: ShaderStage,

    pub fn init(logical_device: Vk.Device, shader_data: []const u32, stage: ShaderStage) !Shader {
        return Shader{ .module = try createShaderModule(shader_data, logical_device), .stage = stage };
    }

    pub fn initFromEmbeddedFile(logical_device: Vk.Device, comptime file: []const u8, comptime stage: ShaderStage) !Shader {
        return Shader.init(logical_device, std.mem.bytesAsSlice(u32, @alignCast(@alignOf(u32), @embedFile(file))), stage);
    }

    pub fn deinit(self: Shader, logical_device: Vk.Device) void {
        destroyShaderModule(logical_device, self.module, null);
    }

    pub fn toPipelineShaderStageCreateInfo(self: Shader) Vk.c.VkPipelineShaderStageCreateInfo {
        return .{
            .sType = .VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = self.stage.toShaderStageFlagBits(),
            .module = self.module,
            .pName = "main",
            .pSpecializationInfo = null,
        };
    }
};

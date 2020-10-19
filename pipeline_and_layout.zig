const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const glfw = @import("glfw_wrapper.zig");

usingnamespace @import("vulkan_general.zig");
usingnamespace @import("vulkan_instance.zig");

pub const PipelineAndLayout = struct {
    graphics_pipeline: Vk.Pipeline,
    layout: Vk.PipelineLayout,
};

fn createPipelineLayout(logical_device: Vk.Device, descriptor_set_layouts: []const Vk.c.VkDescriptorSetLayout) !Vk.PipelineLayout {
    const pipelineLayoutInfo: Vk.c.VkPipelineLayoutCreateInfo = .{
        .sType = .VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .setLayoutCount = @intCast(u32, descriptor_set_layouts.len),
        .pSetLayouts = descriptor_set_layouts.ptr,
        .pushConstantRangeCount = 0, // Optional
        .pPushConstantRanges = 0, // Optional
    };

    var pipeline_layout: Vk.PipelineLayout = undefined;
    try checkVulkanResult(Vk.c.vkCreatePipelineLayout(logical_device, &pipelineLayoutInfo, null, @ptrCast(*Vk.c.VkPipelineLayout, &pipeline_layout)));
    return pipeline_layout;
}

const destroyPipelineLayout = Vk.c.vkDestroyPipelineLayout;

pub fn createGraphicsPipelineAndLayout(
    swap_chain_extent: Vk.c.VkExtent2D,
    logical_device: Vk.Device,
    render_pass: Vk.RenderPass,
    descriptor_set_layouts: []const Vk.c.VkDescriptorSetLayout,
    shader_stages: []const Vk.c.VkPipelineShaderStageCreateInfo,
) !PipelineAndLayout {
    const vertex_input_info: Vk.c.VkPipelineVertexInputStateCreateInfo = .{
        .sType = .VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .vertexBindingDescriptionCount = 0,
        .vertexAttributeDescriptionCount = 0,
        .pVertexBindingDescriptions = null,
        .pVertexAttributeDescriptions = null,
    };

    const input_assembly: Vk.c.VkPipelineInputAssemblyStateCreateInfo = .{
        .sType = .VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .topology = .VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP,
        .primitiveRestartEnable = Vk.c.VK_FALSE,
    };
    const viewport: Vk.c.VkViewport = .{
        .x = 0,
        .y = 0,
        .width = @intToFloat(f32, swap_chain_extent.width),
        .height = @intToFloat(f32, swap_chain_extent.height),
        .minDepth = 0,
        .maxDepth = 1,
    };
    const scissor: Vk.c.VkRect2D = .{
        .offset = .{ .x = 0, .y = 0 },
        .extent = swap_chain_extent,
    };
    const viewportState: Vk.c.VkPipelineViewportStateCreateInfo = .{
        .sType = .VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .viewportCount = 1,
        .pViewports = &viewport,
        .scissorCount = 1,
        .pScissors = &scissor,
    };
    const rasterizer: Vk.c.VkPipelineRasterizationStateCreateInfo = .{
        .sType = .VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .depthClampEnable = Vk.c.VK_FALSE,
        .rasterizerDiscardEnable = Vk.c.VK_FALSE,
        .polygonMode = .VK_POLYGON_MODE_FILL,
        .lineWidth = 1,
        .cullMode = Vk.c.VK_CULL_MODE_BACK_BIT,
        .frontFace = .VK_FRONT_FACE_CLOCKWISE,
        .depthBiasEnable = Vk.c.VK_FALSE,
        .depthBiasConstantFactor = 0, // Optional
        .depthBiasClamp = 0, // Optional
        .depthBiasSlopeFactor = 0, // Optional
    };
    const multisampling: Vk.c.VkPipelineMultisampleStateCreateInfo = .{
        .sType = .VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .sampleShadingEnable = Vk.c.VK_FALSE,
        .rasterizationSamples = .VK_SAMPLE_COUNT_1_BIT,
        .minSampleShading = 1, // Optional
        .pSampleMask = null, // Optional
        .alphaToCoverageEnable = Vk.c.VK_FALSE, // Optional
        .alphaToOneEnable = Vk.c.VK_FALSE, // Optional
    };
    const color_blend_attachment: Vk.c.VkPipelineColorBlendAttachmentState = .{
        .colorWriteMask = Vk.c.VK_COLOR_COMPONENT_R_BIT | Vk.c.VK_COLOR_COMPONENT_G_BIT | Vk.c.VK_COLOR_COMPONENT_B_BIT | Vk.c.VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = Vk.c.VK_FALSE,
        .srcColorBlendFactor = .VK_BLEND_FACTOR_ONE, // Optional
        .dstColorBlendFactor = .VK_BLEND_FACTOR_ZERO, // Optional
        .colorBlendOp = .VK_BLEND_OP_ADD, // Optional
        .srcAlphaBlendFactor = .VK_BLEND_FACTOR_ONE, // Optional
        .dstAlphaBlendFactor = .VK_BLEND_FACTOR_ZERO, // Optional
        .alphaBlendOp = .VK_BLEND_OP_ADD, // Optional
    };
    const colorBlending: Vk.c.VkPipelineColorBlendStateCreateInfo = .{
        .sType = .VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .logicOpEnable = Vk.c.VK_FALSE,
        .logicOp = .VK_LOGIC_OP_COPY, // Optional
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
        .blendConstants = [_]f32{
            0,
            0,
            0,
            0,
        }, // Optional
    };
    const pipeline_layout = try createPipelineLayout(logical_device, descriptor_set_layouts);
    errdefer destroyPipelineLayout(logical_device, pipeline_layout, null);

    const pipelineInfo: Vk.c.VkGraphicsPipelineCreateInfo = .{
        .sType = .VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stageCount = @intCast(u32, shader_stages.len),
        .pStages = shader_stages.ptr,

        .pVertexInputState = &vertex_input_info,
        .pInputAssemblyState = &input_assembly,
        .pViewportState = &viewportState,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pDepthStencilState = null, // Optional
        .pColorBlendState = &colorBlending,
        .pDynamicState = null, // Optional
        .pTessellationState = null,

        .layout = pipeline_layout,

        .renderPass = render_pass,
        .subpass = 0,

        .basePipelineHandle = null, // Optional
        .basePipelineIndex = -1, // Optional
    };

    var graphics_pipeline: Vk.Pipeline = undefined;
    try checkVulkanResult(Vk.c.vkCreateGraphicsPipelines(logical_device, null, 1, &pipelineInfo, null, @ptrCast(*Vk.c.VkPipeline, &graphics_pipeline)));
    return PipelineAndLayout{ .graphics_pipeline = graphics_pipeline, .layout = pipeline_layout };
}

pub fn destroyPipelineAndLayout(logical_device: Vk.Device, pipeline_and_layout: PipelineAndLayout) void {
    destroyPipelineLayout(logical_device, pipeline_and_layout.layout, null);
    Vk.c.vkDestroyPipeline(logical_device, pipeline_and_layout.graphics_pipeline, null);
}

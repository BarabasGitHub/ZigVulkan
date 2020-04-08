const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const glfw = @import("glfw_wrapper.zig");
usingnamespace @import("window.zig");
usingnamespace @import("vulkan_general.zig");
usingnamespace @import("vulkan_instance.zig");
usingnamespace @import("vulkan_graphics_device.zig");
usingnamespace @import("vulkan_shader.zig");

fn fillCommandBufferEmptyScreen(render_pass: Vk.RenderPass, swap_chain_extent: Vk.c.VkExtent2D, frame_buffer: Vk.Framebuffer, command_buffer: Vk.CommandBuffer, clear_color: [4]f32) !void {
    const beginInfo = Vk.c.VkCommandBufferBeginInfo{
        .sType = .VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .pNext = null,
        .flags = Vk.c.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT,
        .pInheritanceInfo = null,
    };

    try checkVulkanResult(Vk.c.vkBeginCommandBuffer(command_buffer, &beginInfo));

    const clearColor = Vk.c.VkClearValue{ .color = .{ .float32 = clear_color } };
    const renderPassInfo = Vk.c.VkRenderPassBeginInfo{
        .sType = .VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .pNext = null,
        .renderPass = render_pass,
        .framebuffer = frame_buffer,
        .renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = swap_chain_extent },
        .clearValueCount = 1,
        .pClearValues = &clearColor,
    };

    Vk.c.vkCmdBeginRenderPass(command_buffer, &renderPassInfo, .VK_SUBPASS_CONTENTS_INLINE);

    Vk.c.vkCmdEndRenderPass(command_buffer);

    try checkVulkanResult(Vk.c.vkEndCommandBuffer(command_buffer));
}

test "render an empty screen" {
    try glfw.init();
    defer glfw.deinit();
    const window = try Window.init(200, 200, "test_window");
    defer window.deinit();
    var renderer = try Renderer.init(window, testApplicationInfo(), testExtensions(), testing.allocator);
    defer renderer.deinit();

    try window.show();
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try renderer.updateImageIndex();
        try fillCommandBufferEmptyScreen(
            renderer.render_pass,
            renderer.core_device_data.swap_chain.extent,
            renderer.frame_buffers[renderer.current_render_image_index],
            renderer.command_buffers[renderer.current_render_image_index],
            [4]f32{ 0, 0.5, 1, 1 },
        );
        try renderer.draw();
        try renderer.present();
    }
}

fn fillCommandBuffer(render_pass: Vk.RenderPass, swap_chain_extent: Vk.c.VkExtent2D, frame_buffer: Vk.Framebuffer, command_buffer: Vk.CommandBuffer, graphics_pipeline: Vk.Pipeline, clear_color: [4]f32) !void {
    const beginInfo = Vk.c.VkCommandBufferBeginInfo{
        .sType = .VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .pNext = null,
        .flags = Vk.c.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT,
        .pInheritanceInfo = null,
    };

    try checkVulkanResult(Vk.c.vkBeginCommandBuffer(command_buffer, &beginInfo));

    const clearColor = Vk.c.VkClearValue{ .color = .{ .float32 = clear_color } };
    const renderPassInfo = Vk.c.VkRenderPassBeginInfo{
        .sType = .VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .pNext = null,
        .renderPass = render_pass,
        .framebuffer = frame_buffer,
        .renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = swap_chain_extent },
        .clearValueCount = 1,
        .pClearValues = &clearColor,
    };

    Vk.c.vkCmdBeginRenderPass(command_buffer, &renderPassInfo, .VK_SUBPASS_CONTENTS_INLINE);

    Vk.c.vkCmdBindPipeline(command_buffer, .VK_PIPELINE_BIND_POINT_GRAPHICS, graphics_pipeline);

    Vk.c.vkCmdDraw(command_buffer, 6, 1, 0, 0);

    Vk.c.vkCmdEndRenderPass(command_buffer);

    try checkVulkanResult(Vk.c.vkEndCommandBuffer(command_buffer));
}

const PipelineAndLayout = struct {
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

fn createGraphicsPipelineAndLayout(
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

fn destroyPipelineAndLayout(logical_device: Vk.Device, pipeline_and_layout: PipelineAndLayout) void {
    destroyPipelineLayout(logical_device, pipeline_and_layout.layout, null);
    Vk.c.vkDestroyPipeline(logical_device, pipeline_and_layout.graphics_pipeline, null);
}

fn createShaderModuleFromEmbeddedFile(comptime file: []const u8, logical_device: Vk.Device) !Vk.ShaderModule {
    return createShaderModule(std.mem.bytesAsSlice(u32, @alignCast(@alignOf(u32), @embedFile(file))), logical_device);
}

test "render one rectangle" {
    try glfw.init();
    defer glfw.deinit();
    const window = try Window.init(200, 200, "test_window");
    defer window.deinit();
    var renderer = try Renderer.init(window, testApplicationInfo(), testExtensions(), testing.allocator);
    defer renderer.deinit();

    const descriptor_set_layouts = [_]Vk.c.VkDescriptorSetLayout{};
    var shader_stages : [2]Vk.c.VkPipelineShaderStageCreateInfo = undefined;

    const fixed_rectangle = try createShaderModuleFromEmbeddedFile("Shaders/fixed_rectangle.vert.spr", renderer.core_device_data.logical_device);
    defer destroyShaderModule(renderer.core_device_data.logical_device, fixed_rectangle, null);

    shader_stages[0] = .{
        .sType = .VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stage = .VK_SHADER_STAGE_VERTEX_BIT,
        .module= fixed_rectangle,
        .pName = "main",
        .pSpecializationInfo = null,
        };

    const white_pixel = try createShaderModuleFromEmbeddedFile("Shaders/white.frag.spr", renderer.core_device_data.logical_device);
    defer destroyShaderModule(renderer.core_device_data.logical_device, white_pixel, null);

    shader_stages[1] = .{
        .sType = .VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stage = .VK_SHADER_STAGE_FRAGMENT_BIT,
        .module=white_pixel,
        .pName = "main",
        .pSpecializationInfo = null,
        };

    const pipeline_and_layout = try createGraphicsPipelineAndLayout(renderer.core_device_data.swap_chain.extent, renderer.core_device_data.logical_device, renderer.render_pass, &descriptor_set_layouts, &shader_stages);
    defer destroyPipelineAndLayout(renderer.core_device_data.logical_device, pipeline_and_layout);

    try window.show();
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try renderer.updateImageIndex();
        try fillCommandBuffer(
            renderer.render_pass,
            renderer.core_device_data.swap_chain.extent,
            renderer.frame_buffers[renderer.current_render_image_index],
            renderer.command_buffers[renderer.current_render_image_index],
            pipeline_and_layout.graphics_pipeline,
            [4]f32{ 0, 0.5, 1, 1 },
        );
        try renderer.draw();
        try renderer.present();
    }
}

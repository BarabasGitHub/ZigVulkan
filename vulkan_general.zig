const std = @import("std");
const builtin = std.builtin;

pub fn checkVulkanResult(result: Vk.c.VkResult) !void {
    return switch (result) {
        .VK_SUCCESS => void{},
        .VK_NOT_READY => error.VkNotReady,
        .VK_TIMEOUT => error.VkTimeout,
        .VK_EVENT_SET => error.VkEventSet,
        .VK_EVENT_RESET => error.VkEventReset,
        .VK_INCOMPLETE => error.VkIncomplete,
        .VK_ERROR_OUT_OF_HOST_MEMORY => error.VkErrorOutOfHostMemory,
        .VK_ERROR_OUT_OF_DEVICE_MEMORY => error.VkErrorOutOfDeviceMemory,
        .VK_ERROR_INITIALIZATION_FAILED => error.VkErrorInitializationFailed,
        .VK_ERROR_DEVICE_LOST => error.VkErrorDeviceLost,
        .VK_ERROR_MEMORY_MAP_FAILED => error.VkErrorMemoryMapFailed,
        .VK_ERROR_LAYER_NOT_PRESENT => error.VkErrorLayerNotPresent,
        .VK_ERROR_EXTENSION_NOT_PRESENT => error.VkErrorExtensionNotPresent,
        .VK_ERROR_FEATURE_NOT_PRESENT => error.VkErrorFeatureNotPresent,
        .VK_ERROR_INCOMPATIBLE_DRIVER => error.VkErrorIncompatibleDriver,
        .VK_ERROR_TOO_MANY_OBJECTS => error.VkErrorTooManyObjects,
        .VK_ERROR_FORMAT_NOT_SUPPORTED => error.VkErrorFormatNotSupported,
        .VK_ERROR_FRAGMENTED_POOL => error.VkErrorFragmentedPool,
        .VK_ERROR_OUT_OF_POOL_MEMORY => error.VkErrorOutOfPoolMemory,
        .VK_ERROR_INVALID_EXTERNAL_HANDLE => error.VkErrorInvalidExternalHandle,
        .VK_ERROR_SURFACE_LOST_KHR => error.VkErrorSurfaceLostKhr,
        .VK_ERROR_NATIVE_WINDOW_IN_USE_KHR => error.VkErrorNativeWindowInUseKhr,
        .VK_SUBOPTIMAL_KHR => error.VkSuboptimalKhr,
        .VK_ERROR_OUT_OF_DATE_KHR => error.VkErrorOutOfDateKhr,
        .VK_ERROR_INCOMPATIBLE_DISPLAY_KHR => error.VkErrorIncompatibleDisplayKhr,
        .VK_ERROR_VALIDATION_FAILED_EXT => error.VkErrorValidationFailedExt,
        .VK_ERROR_INVALID_SHADER_NV => error.VkErrorInvalidShaderNv,
        .VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT => error.VkErrorInvalidDrmFormatModifierPlaneLayoutExt,
        .VK_ERROR_FRAGMENTATION_EXT => error.VkErrorFragmentationExt,
        .VK_ERROR_NOT_PERMITTED_EXT => error.VkErrorNotPermittedExt,
        .VK_ERROR_INVALID_DEVICE_ADDRESS_EXT => error.VkErrorInvalidDeviceAddressExt,
        .VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT => error.VkErrorFullScreenExclusiveModeLostExt,
        // these are duplicates
        // .VK_ERROR_OUT_OF_POOL_MEMORY_KHR => error.VkErrorOutOfPoolMemoryKhr,
        // .VK_ERROR_INVALID_EXTERNAL_HANDLE_KHR => error.VkErrorInvalidExternalHandleKhr,
        // .VK_RESULT_BEGIN_RANGE => error.VkResultBeginRange,
        // .VK_RESULT_END_RANGE => error.VkResultEndRange,
        .VK_RESULT_RANGE_SIZE => error.VkResultRangeSize,
        .VK_RESULT_MAX_ENUM => error.VkResultMaxEnum,
        else => error.VKUnknownError,
    };
}

pub const USE_DEBUG_TOOLS = builtin.mode == builtin.Mode.Debug or builtin.mode == builtin.Mode.ReleaseSafe;

pub const Vk = struct {
    pub const c = @import("GLFW_and_Vulkan.zig");

    const MakeNonOptional = std.meta.Child;
    pub const Instance = MakeNonOptional(c.VkInstance);
    pub const PhysicalDevice = MakeNonOptional(c.VkPhysicalDevice);
    pub const Device = MakeNonOptional(c.VkDevice);
    pub const CommandPool = MakeNonOptional(c.VkCommandPool);
    pub const Semaphore = MakeNonOptional(c.VkSemaphore);
    pub const Buffer = MakeNonOptional(c.VkBuffer);
    pub const DeviceMemory = MakeNonOptional(c.VkDeviceMemory);
    pub const SurfaceKHR = MakeNonOptional(c.VkSurfaceKHR);
    pub const SwapchainKHR = MakeNonOptional(c.VkSwapchainKHR);
    pub const Image = MakeNonOptional(c.VkImage);
    pub const ImageView = MakeNonOptional(c.VkImageView);
    pub const DescriptorPool = MakeNonOptional(c.VkDescriptorPool);
    pub const RenderPass = MakeNonOptional(c.VkRenderPass);
    pub const Framebuffer = MakeNonOptional(c.VkFramebuffer);
    pub const CommandBuffer = MakeNonOptional(c.VkCommandBuffer);
    pub const ShaderModule = MakeNonOptional(c.VkShaderModule);
    pub const Pipeline = MakeNonOptional(c.VkPipeline);
    pub const PipelineLayout = MakeNonOptional(c.VkPipelineLayout);
    pub const Queue = MakeNonOptional(c.VkQueue);
    pub const DescriptorSetLayout = MakeNonOptional(c.VkDescriptorSetLayout);
    pub const DescriptorSet = MakeNonOptional(c.VkDescriptorSet);
    pub const Sampler = MakeNonOptional(c.VkSampler);
};

pub fn createCommandPool(logical_device: Vk.Device, flags: u32, transfer_family_index: u32) !Vk.CommandPool {
    const poolInfo = Vk.c.VkCommandPoolCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .pNext = null,
        .queueFamilyIndex = transfer_family_index,
        .flags = flags,
    };
    var command_pool: Vk.CommandPool = undefined;
    try checkVulkanResult(Vk.c.vkCreateCommandPool(@ptrCast(Vk.c.VkDevice, logical_device), &poolInfo, null, @ptrCast(*Vk.c.VkCommandPool, &command_pool)));
    return command_pool;
}

pub fn createSemaphore(logical_device: Vk.Device) !Vk.Semaphore {
    const semaphoreInfo = Vk.c.VkSemaphoreCreateInfo{
        .sType = .VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
    };
    var semaphore: Vk.Semaphore = undefined;
    try checkVulkanResult(Vk.c.vkCreateSemaphore(logical_device, &semaphoreInfo, null, @ptrCast(*Vk.c.VkSemaphore, &semaphore)));
    return semaphore;
}

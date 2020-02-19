const glfw_vulkan = @import("GLFW_and_Vulkan.zig");
const builtin = @import("builtin");

const Version = struct {
    major: u8,
    minor: u8,
    patch: u8,
};

fn checkVulkanResult(result: glfw_vulkan.VkResult) !void {
    return switch(result) {
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
        // .VK_ERROR_OUT_OF_POOL_MEMORY_KHR => error.VkErrorOutOfPoolMemoryKhr,
        // .VK_ERROR_INVALID_EXTERNAL_HANDLE_KHR => error.VkErrorInvalidExternalHandleKhr,
        // .VK_RESULT_BEGIN_RANGE => error.VkResultBeginRange,
        // .VK_RESULT_END_RANGE => error.VkResultEndRange,
        .VK_RESULT_RANGE_SIZE => error.VkResultRangeSize,
        .VK_RESULT_MAX_ENUM => error.VkResultMaxEnum,
        _ => error.VKUnknownError,
    };
}

const USE_DEBUG_TOOLS = builtin.mode == builtin.Mode.Debug or builtin.mode == builtin.Mode.ReleaseSafe;

const validation_layers : []const []const u8 = if (comptime USE_DEBUG_TOOLS) &[_][]const u8{ "VK_LAYER_LUNARG_standard_validation", } else {};

fn createInstance(application_name: [*:0]const u8, application_version: Version, engine_name: [*:0]const u8, engine_version: Version, extentions: []const [*:0]const u8) !glfw_vulkan.VkInstance {
    const app_info = glfw_vulkan.VkApplicationInfo{
        .sType=glfw_vulkan.enum_VkStructureType.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pNext=null,
        .pApplicationName="test_name",
        .applicationVersion=glfw_vulkan.VK_MAKE_VERSION(0, 0, 0),
        .pEngineName="test_engine",
        .engineVersion=glfw_vulkan.VK_MAKE_VERSION(0, 0, 0),
        .apiVersion=glfw_vulkan.VK_API_VERSION_1_0,
    };

    const createInfo = glfw_vulkan.VkInstanceCreateInfo{
        .sType=glfw_vulkan.VkStructureType.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext=null,
        .pApplicationInfo=&app_info,
        .enabledExtensionCount=@intCast(u32, extentions.len),
        .ppEnabledExtensionNames=@ptrCast([*c]const [*c]const u8, extentions.ptr),
        .flags=0,
        .enabledLayerCount=@intCast(u32, validation_layers.len),
        .ppEnabledLayerNames=@ptrCast([*c]const [*c]const u8, validation_layers.ptr),
    };
    var instance: glfw_vulkan.VkInstance = undefined;
    try checkVulkanResult(glfw_vulkan.vkCreateInstance(&createInfo, null, &instance));
    return instance;
}

const destroyInstance = glfw_vulkan.vkDestroyInstance;

const testing = @import("std").testing;

fn createTestInstance(extentions: []const [*:0]const u8) !glfw_vulkan.VkInstance {
    return try createInstance("test_application", .{.major=0, .minor=0, .patch=0}, "test_engine", .{.major=0, .minor=0, .patch=0}, extentions);
}

test "Creating a Vulkan instance without extentions should succeed" {
    const instance = try createTestInstance(&[_][*:0]const u8{});
    destroyInstance(instance, null);
}

test "Creating a Vulkan instance without non-existing extentions should fail with VkErrorExtensionNotPresent" {
    testing.expectError(error.VkErrorExtensionNotPresent, createTestInstance(&[_][*:0]const u8{"non-existing extention"}));
}

fn createDebugCallback(instance: glfw_vulkan.VkInstance, user_callback: @typeInfo(glfw_vulkan.PFN_vkDebugReportCallbackEXT).Optional.child, user_data: var) !glfw_vulkan.VkDebugReportCallbackEXT {
    return try createDebugCallbackWithCanFail(instance, user_callback, user_data);
}

fn createDebugCallbackWithCanFail(instance: glfw_vulkan.VkInstance, user_callback: glfw_vulkan.PFN_vkDebugReportCallbackEXT, user_data: var) !glfw_vulkan.VkDebugReportCallbackEXT {
    var createInfo = glfw_vulkan.VkDebugReportCallbackCreateInfoEXT{
        .sType=glfw_vulkan.VkStructureType.VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT,
        .pNext=null,
        .pUserData=user_data,
        .flags=0
        | glfw_vulkan.VK_DEBUG_REPORT_ERROR_BIT_EXT
        | glfw_vulkan.VK_DEBUG_REPORT_WARNING_BIT_EXT,
        .pfnCallback=user_callback,
    };
    if (USE_DEBUG_TOOLS) {
        createInfo.flags = createInfo.flags
        | @as(u32, glfw_vulkan.VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT)
        | @as(u32, glfw_vulkan.VK_DEBUG_REPORT_INFORMATION_BIT_EXT)
        | @as(u32, glfw_vulkan.VK_DEBUG_REPORT_DEBUG_BIT_EXT)
        ;
    }
    var callback : glfw_vulkan.VkDebugReportCallbackEXT = undefined;
    const func = @ptrCast(glfw_vulkan.PFN_vkCreateDebugReportCallbackEXT, glfw_vulkan.vkGetInstanceProcAddr(instance, "vkCreateDebugReportCallbackEXT"));
    if (func) |f| {
        try checkVulkanResult(f(instance, &createInfo, null, &callback));
    }
    else {
        return error.VkErrorExtensionNotPresent;
    }

    return callback;
}

fn destroyDebugCallback(instance: glfw_vulkan.VkInstance, callback: glfw_vulkan.VkDebugReportCallbackEXT) void {
    if (@ptrCast(glfw_vulkan.PFN_vkDestroyDebugReportCallbackEXT, glfw_vulkan.vkGetInstanceProcAddr(instance, "vkDestroyDebugReportCallbackEXT"))) |func| {
        func(instance, callback, null);
    }
}

fn debugCallback(flags: glfw_vulkan.VkDebugReportFlagsEXT, object_type: glfw_vulkan.VkDebugReportObjectTypeEXT, object: u64, location: usize, message_code: i32, layer_prefix: [*c]const u8, message: [*c]const u8, user_data: ?*c_void) callconv(.C) glfw_vulkan.VkBool32 {
    @ptrCast(*u32, @alignCast(@alignOf(u32), user_data)).* += 1;
    return @boolToInt(false);
}

test "Creating a debug callback should succeed" {
    var instance = try createTestInstance(&[_][*:0]const u8{glfw_vulkan.VK_EXT_DEBUG_REPORT_EXTENSION_NAME});
    // setup callback with user data
    var user_data : u32 = 0;
    const callback = try createDebugCallback(instance, debugCallback, &user_data);
    defer destroyDebugCallback(instance, callback);
    // make it generate an error/warning and call the callback by creating a null callback
    destroyDebugCallback(instance, try createDebugCallbackWithCanFail(instance, null, null));
    // check our callback was called
    testing.expectEqual(@as(u32, 1), user_data);
    destroyInstance(instance, null);
}


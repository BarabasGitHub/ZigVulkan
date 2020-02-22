const std = @import("std");
const mem = std.mem;

usingnamespace @import("vulkan_general.zig");

pub const Version = struct {
    major: u8,
    minor: u8,
    patch: u8,

};

pub const validation_layers : []const [:0]const u8 = if (comptime USE_DEBUG_TOOLS) &[_][:0]const u8{ "VK_LAYER_LUNARG_standard_validation", } else {};

pub fn createInstance(application_name: [*:0]const u8, application_version: Version, engine_name: [*:0]const u8, engine_version: Version, extensions: []const [*:0]const u8) !Vk.c.VkInstance {
    const app_info = Vk.c.VkApplicationInfo{
        .sType=Vk.c.enum_VkStructureType.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pNext=null,
        .pApplicationName=application_name,
        .applicationVersion=Vk.c.VK_MAKE_VERSION(0, 0, 0),
        .pEngineName=engine_name,
        .engineVersion=Vk.c.VK_MAKE_VERSION(0, 0, 0),
        .apiVersion=Vk.c.VK_API_VERSION_1_0,
    };

    const createInfo = Vk.c.VkInstanceCreateInfo{
        .sType=Vk.c.VkStructureType.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext=null,
        .pApplicationInfo=&app_info,
        .enabledExtensionCount=@intCast(u32, extensions.len),
        .ppEnabledExtensionNames=@ptrCast([*c]const [*c]const u8, extensions.ptr),
        .flags=0,
        .enabledLayerCount=@intCast(u32, validation_layers.len),
        .ppEnabledLayerNames=@ptrCast([*c]const [*c]const u8, validation_layers.ptr),
    };
    var instance: Vk.c.VkInstance = undefined;
    try checkVulkanResult(Vk.c.vkCreateInstance(&createInfo, null, &instance));
    return instance;
}

pub const destroyInstance = Vk.c.vkDestroyInstance;

pub fn destroyTestInstance(instance: Vk.c.VkInstance) void {
    destroyDebugCallback(instance, global_debug_callback_for_testing.?);
    global_debug_callback_for_testing = null;
    destroyInstance(instance, null);
}

const testing = std.testing;

pub fn createTestInstanceWithoutDebugCallback(extensions: []const [*:0]const u8) !Vk.c.VkInstance {
    return createInstance("test_application", .{.major=0, .minor=0, .patch=0}, "test_engine", .{.major=0, .minor=0, .patch=0}, extensions);
}

fn debugCallbackPrintingWarnings(flags: Vk.c.VkDebugReportFlagsEXT, object_type: Vk.c.VkDebugReportObjectTypeEXT, object: u64, location: usize, message_code: i32, layer_prefix: [*c]const u8, message: [*c]const u8, user_data: ?*c_void) callconv(.C) Vk.c.VkBool32 {
    if (std.cstr.cmp(layer_prefix, "Loader Message") != 0){
        std.debug.warn("Validation layer({s}): {s}\n", .{layer_prefix, message});
    }
    return @boolToInt(false);
}

var global_debug_callback_for_testing : Vk.c.VkDebugReportCallbackEXT = null;

pub fn createTestInstance(extensions: []const [*:0]const u8) !Vk.c.VkInstance {
    var extension_list = std.ArrayList([*:0]const u8).init(testing.allocator);
    defer extension_list.deinit();
    try extension_list.append(Vk.c.VK_EXT_DEBUG_REPORT_EXTENSION_NAME);
    try extension_list.appendSlice(extensions);
    var instance = try createInstance("test_application", .{.major=0, .minor=0, .patch=0}, "test_engine", .{.major=0, .minor=0, .patch=0}, extension_list.toSlice());
    global_debug_callback_for_testing = try createDebugCallback(instance, debugCallbackPrintingWarnings, null);
    return instance;
}


test "Creating a Vulkan instance without extensions should succeed" {
    const instance = try createTestInstanceWithoutDebugCallback(&[_][*:0]const u8{});
    destroyInstance(instance, null);
}

test "Creating a Vulkan instance without non-existing extensions should fail with VkErrorExtensionNotPresent" {
    testing.expectError(error.VkErrorExtensionNotPresent, createTestInstance(&[_][*:0]const u8{"non-existing extension"}));
}

fn createDebugCallback(instance: Vk.c.VkInstance, user_callback: @typeInfo(Vk.c.PFN_vkDebugReportCallbackEXT).Optional.child, user_data: var) !Vk.c.VkDebugReportCallbackEXT {
    return createDebugCallbackWichCanFail(instance, user_callback, user_data);
}

fn createDebugCallbackWichCanFail(instance: Vk.c.VkInstance, user_callback: Vk.c.PFN_vkDebugReportCallbackEXT, user_data: var) !Vk.c.VkDebugReportCallbackEXT {
    var createInfo = Vk.c.VkDebugReportCallbackCreateInfoEXT{
        .sType=Vk.c.VkStructureType.VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT,
        .pNext=null,
        .pUserData=user_data,
        .flags=0
        | Vk.c.VK_DEBUG_REPORT_ERROR_BIT_EXT
        | Vk.c.VK_DEBUG_REPORT_WARNING_BIT_EXT,
        .pfnCallback=user_callback,
    };
    if (USE_DEBUG_TOOLS) {
        createInfo.flags = createInfo.flags
        | @as(u32, Vk.c.VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT)
        | @as(u32, Vk.c.VK_DEBUG_REPORT_INFORMATION_BIT_EXT)
        | @as(u32, Vk.c.VK_DEBUG_REPORT_DEBUG_BIT_EXT)
        ;
    }
    var callback : Vk.c.VkDebugReportCallbackEXT = undefined;
    const func = @ptrCast(Vk.c.PFN_vkCreateDebugReportCallbackEXT, Vk.c.vkGetInstanceProcAddr(instance, "vkCreateDebugReportCallbackEXT"));
    if (func) |f| {
        try checkVulkanResult(f(instance, &createInfo, null, &callback));
    }
    else {
        return error.VkErrorExtensionNotPresent;
    }

    return callback;
}

fn destroyDebugCallback(instance: Vk.c.VkInstance, callback: Vk.c.VkDebugReportCallbackEXT) void {
    if (@ptrCast(Vk.c.PFN_vkDestroyDebugReportCallbackEXT, Vk.c.vkGetInstanceProcAddr(instance, "vkDestroyDebugReportCallbackEXT"))) |func| {
        func(instance, callback, null);
    }
}

fn debugCallback(flags: Vk.c.VkDebugReportFlagsEXT, object_type: Vk.c.VkDebugReportObjectTypeEXT, object: u64, location: usize, message_code: i32, layer_prefix: [*c]const u8, message: [*c]const u8, user_data: ?*c_void) callconv(.C) Vk.c.VkBool32 {
    @ptrCast(*u32, @alignCast(@alignOf(u32), user_data)).* += 1;
    return @boolToInt(false);
}

test "Creating a debug callback should succeed" {
    var instance = try createTestInstanceWithoutDebugCallback(&[_][*:0]const u8{Vk.c.VK_EXT_DEBUG_REPORT_EXTENSION_NAME});
    defer destroyInstance(instance, null);
    // setup callback with user data
    var user_data : u32 = 0;
    const callback = try createDebugCallback(instance, debugCallback, &user_data);
    defer destroyDebugCallback(instance, callback);
    // make it generate an error/warning and call the callback by creating a null callback
    destroyDebugCallback(instance, try createDebugCallbackWichCanFail(instance, null, null));
    // check our callback was called
    testing.expectEqual(@as(u32, 1), user_data);
}


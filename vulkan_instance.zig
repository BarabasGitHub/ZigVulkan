const std = @import("std");
const mem = std.mem;

usingnamespace @import("vulkan_general.zig");

pub const ApplicationInfo = struct {
    application: NameAndVersion,
    engine: NameAndVersion,

    pub const Version = struct {
        major: u10,
        minor: u10,
        patch: u12,
    };

    pub const NameAndVersion = struct {
        name: [:0]const u8,
        version: Version,
    };
};

pub fn testApplicationInfo() ApplicationInfo {
    return .{
        .application = .{ .name = "", .version = .{ .major = 0, .minor = 0, .patch = 0 } },
        .engine = .{ .name = "", .version = .{ .major = 0, .minor = 0, .patch = 0 } },
    };
}

pub fn testExtensions() []const [*:0]const u8 {
    return &[_][*:0]const u8{Vk.c.VK_EXT_DEBUG_REPORT_EXTENSION_NAME};
}

fn VulkanVersionFromVersion(version: ApplicationInfo.Version) u32 {
    return Vk.c.VK_MAKE_VERSION(@as(u32, version.major), @as(u22, version.minor), version.patch);
}

pub const validation_layers: []const [*:0]const u8 = if (comptime USE_DEBUG_TOOLS) &[_][*:0]const u8{"VK_LAYER_LUNARG_standard_validation"} else {};

pub fn createInstance(application_info: ApplicationInfo, extensions: []const [*:0]const u8) !Vk.Instance {
    const app_info = Vk.c.VkApplicationInfo{
        .sType = Vk.c.enum_VkStructureType.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pNext = null,
        .pApplicationName = application_info.application.name,
        .applicationVersion = VulkanVersionFromVersion(application_info.application.version),
        .pEngineName = application_info.engine.name,
        .engineVersion = VulkanVersionFromVersion(application_info.engine.version),
        .apiVersion = Vk.c.VK_API_VERSION_1_0,
    };

    const createInfo = Vk.c.VkInstanceCreateInfo{
        .sType = Vk.c.VkStructureType.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = null,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = @intCast(u32, extensions.len),
        .ppEnabledExtensionNames = extensions.ptr,
        .flags = 0,
        .enabledLayerCount = @intCast(u32, validation_layers.len),
        .ppEnabledLayerNames = validation_layers.ptr,
    };
    var instance: Vk.Instance = undefined;
    try checkVulkanResult(Vk.c.vkCreateInstance(&createInfo, null, @ptrCast(*Vk.c.VkInstance, &instance)));
    return instance;
}

pub const destroyInstance = Vk.c.vkDestroyInstance;

pub fn destroyTestInstance(instance: Vk.c.VkInstance) void {
    destroyDebugCallback(instance, global_debug_callback_for_testing.?);
    testing.expectEqual(@as(usize, 0), global_counter_for_warning_messages);
    global_counter_for_warning_messages = 0;
    global_debug_callback_for_testing = null;
    destroyInstance(instance, null);
}

const testing = std.testing;

pub fn createTestInstanceWithoutDebugCallback(extensions: []const [*:0]const u8) !Vk.Instance {
    const application_info = ApplicationInfo{
        .application = .{ .name = "test_application", .version = .{ .major = 0, .minor = 0, .patch = 0 } },
        .engine = .{
            .name = "test_engine",
            .version = .{ .major = 0, .minor = 0, .patch = 0 },
        },
    };
    return createInstance(application_info, extensions);
}

fn debugCallbackPrintingWarnings(
    flags: Vk.c.VkDebugReportFlagsEXT,
    object_type: Vk.c.VkDebugReportObjectTypeEXT,
    object: u64,
    location: usize,
    message_code: i32,
    layer_prefix: [*c]const u8,
    message: [*c]const u8,
    user_data: ?*c_void,
) callconv(.Stdcall) Vk.c.VkBool32 {
    if (std.cstr.cmp(layer_prefix, "Loader Message") != 0) {
        std.debug.warn("Validation layer({s}): {s}\n", .{ layer_prefix, message });
        @ptrCast(*usize, @alignCast(@alignOf(usize), user_data)).* += 1;
    }
    return @boolToInt(false);
}

var global_debug_callback_for_testing: Vk.c.VkDebugReportCallbackEXT = null;
var global_counter_for_warning_messages: usize = 0;

pub fn createTestInstance(extensions: []const [*:0]const u8) !Vk.Instance {
    var extension_list = std.ArrayList([*:0]const u8).init(testing.allocator);
    defer extension_list.deinit();
    try extension_list.append(Vk.c.VK_EXT_DEBUG_REPORT_EXTENSION_NAME);
    try extension_list.appendSlice(extensions);
    var instance = try createInstance(testApplicationInfo(), extension_list.span());
    global_debug_callback_for_testing = try createDebugCallback(instance, debugCallbackPrintingWarnings, &global_counter_for_warning_messages);
    return instance;
}

test "Creating a Vulkan instance without extensions should succeed" {
    const instance = try createTestInstanceWithoutDebugCallback(&[_][*:0]const u8{});
    destroyInstance(instance, null);
}

test "Creating a Vulkan instance without non-existing extensions should fail with VkErrorExtensionNotPresent" {
    testing.expectError(error.VkErrorExtensionNotPresent, createTestInstance(&[_][*:0]const u8{"non-existing extension"}));
}

fn createDebugCallback(instance: Vk.c.VkInstance, user_callback: @typeInfo(Vk.c.PFN_vkDebugReportCallbackEXT).Optional.child, user_data: anytype) !Vk.c.VkDebugReportCallbackEXT {
    return createDebugCallbackWichCanFail(instance, user_callback, user_data);
}

fn createDebugCallbackWichCanFail(instance: Vk.c.VkInstance, user_callback: Vk.c.PFN_vkDebugReportCallbackEXT, user_data: anytype) !Vk.c.VkDebugReportCallbackEXT {
    var createInfo = Vk.c.VkDebugReportCallbackCreateInfoEXT{
        .sType = Vk.c.VkStructureType.VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT,
        .pNext = null,
        .pUserData = user_data,
        .flags = 0 | Vk.c.VK_DEBUG_REPORT_ERROR_BIT_EXT | Vk.c.VK_DEBUG_REPORT_WARNING_BIT_EXT,
        .pfnCallback = user_callback,
    };
    if (USE_DEBUG_TOOLS) {
        createInfo.flags = createInfo.flags | @as(u32, Vk.c.VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT) | @as(u32, Vk.c.VK_DEBUG_REPORT_INFORMATION_BIT_EXT) | @as(u32, Vk.c.VK_DEBUG_REPORT_DEBUG_BIT_EXT);
    }
    var callback: Vk.c.VkDebugReportCallbackEXT = undefined;
    const func = @ptrCast(Vk.c.PFN_vkCreateDebugReportCallbackEXT, Vk.c.vkGetInstanceProcAddr(instance, "vkCreateDebugReportCallbackEXT"));
    if (func) |f| {
        try checkVulkanResult(f(instance, &createInfo, null, &callback));
    } else {
        return error.VkErrorExtensionNotPresent;
    }

    return callback;
}

fn destroyDebugCallback(instance: Vk.c.VkInstance, callback: Vk.c.VkDebugReportCallbackEXT) void {
    if (@ptrCast(Vk.c.PFN_vkDestroyDebugReportCallbackEXT, Vk.c.vkGetInstanceProcAddr(instance, "vkDestroyDebugReportCallbackEXT"))) |func| {
        func(instance, callback, null);
    }
}

fn debugCallback(
    flags: Vk.c.VkDebugReportFlagsEXT,
    object_type: Vk.c.VkDebugReportObjectTypeEXT,
    object: u64,
    location: usize,
    message_code: i32,
    layer_prefix: [*c]const u8,
    message: [*c]const u8,
    user_data: ?*c_void,
) callconv(.C) Vk.c.VkBool32 {
    @ptrCast(*u32, @alignCast(@alignOf(u32), user_data)).* += 1;
    return @boolToInt(false);
}

test "Creating a debug callback should succeed" {
    var instance = try createTestInstanceWithoutDebugCallback(&[_][*:0]const u8{Vk.c.VK_EXT_DEBUG_REPORT_EXTENSION_NAME});
    defer destroyInstance(instance, null);
    // setup callback with user data
    var user_data: u32 = 0;
    const callback = try createDebugCallback(instance, debugCallbackPrintingWarnings, &user_data);
    defer destroyDebugCallback(instance, callback);
    // make it generate an error/warning and call the callback somehow
    // // make it generate an error/warning and call the callback by creating a null callback
    // // destroyDebugCallback(instance, try createDebugCallbackWichCanFail(instance, null, null));
    // check our callback was called
    // testing.expectEqual(@as(u32, 1), user_data);
}

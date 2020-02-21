usingnamespace @import("GLFW_and_Vulkan.zig");

//         glfwSetWindowUserPointer(window, &input);
//         glfwSetKeyCallback(window, key_callback);
//         glfwSetCharCallback(window, character_callback);
//         glfwSetMouseButtonCallback(window, mouse_button_callback);
//         glfwSetScrollCallback(window, scroll_callback);
//         glfwSetWindowSizeCallback(window, window_size_callback);
//         glfwSetWindowIconifyCallback(window, iconify_callback);
//         glfwSetWindowFocusCallback(window, focus_callback);

const testing = @import("std").testing;

fn getGlfwError() !void {
    return switch(glfwGetError(null)) {
        GLFW_NO_ERROR => {},

        GLFW_NOT_INITIALIZED => error.GlfwNotINitialized,
        GLFW_NO_CURRENT_CONTEXT => error.GlfwNoCurrentContext,
        GLFW_INVALID_ENUM => error.GlfwInvalidEnum,
        GLFW_INVALID_VALUE => error.GlfwInvalidValue,
        GLFW_OUT_OF_MEMORY => error.GlfwOutOfMemory,
        GLFW_API_UNAVAILABLE => error.GlfwApiUnavailable,
        GLFW_VERSION_UNAVAILABLE => error.GlfwVersionUnavailable,
        GLFW_PLATFORM_ERROR => error.GlfwPlatformError,
        GLFW_FORMAT_UNAVAILABLE => error.GlfwFormatUnavailable,
        GLFW_NO_WINDOW_CONTEXT => error.GlfwNoWindowContext,
        else => error.UnknownGlfwError,
    };
}

pub fn init() !void {
    if (glfwInit() == GLFW_FALSE) {
        return getGlfwError();
    }
}

pub fn deinit() void {
    glfwTerminate();
}

test "Initializing glfw should succeed" {
    try init();
    deinit();
}

pub fn createWindow(width: u31, height: u31, title: [*:0]const u8) !*GLFWwindow {
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindowHint(GLFW_RESIZABLE, GLFW_TRUE);
    glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);
    const window = glfwCreateWindow(width, height, title, null, null);
    if (window) |w| {
        return w;
    } else {
        if (getGlfwError()) |_| {
            unreachable;
        } else |err| {
            return err;
        }
    }
}

pub const destroyWindow = glfwDestroyWindow;

test "Creating a window must succeed" {
    try init();
    defer deinit();
    const window = try createWindow(10, 10, "test");
    destroyWindow(window);
}

test "Creating a zero size window must fail" {
    try init();
    defer deinit();
    testing.expectError(error.GlfwInvalidValue, createWindow(0, 0, "test"));
}

// the returned slice is owned by glfw
pub fn getRequiredInstanceExtensions() ![]const[*:0]const u8 {
    var glfwExtensionCount : u32 = 0;
    const extensions = glfwGetRequiredInstanceExtensions(&glfwExtensionCount);
    try getGlfwError();
    return extensions[0..glfwExtensionCount];
}

test "Getting the required instance extentions should return at least one extension" {
    try init();
    defer deinit();
    testing.expect((try getRequiredInstanceExtensions()).len > 0);
}

pub fn getWindowSize(window: *GLFWwindow, width: *i32, height: *i32) !void {
    glfwGetWindowSize(window, width, height);
    try getGlfwError();
}

test "Getting the window size should succeed" {
    try init();
    defer deinit();
    const width = 200;
    const height = 300;
    const window = try createWindow(width, height, "test");
    defer destroyWindow(window);
    var width_result : i32 = 0;
    var height_result : i32 = 0;
    try getWindowSize(window, &width_result, &height_result);
    testing.expectEqual(@as(i32, width), width_result);
    testing.expectEqual(@as(i32, height), height_result);
}

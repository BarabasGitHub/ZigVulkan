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

test "Creating a window must succeed" {
    try init();
    defer deinit();
    const window = try createWindow(10, 10, "test");
}

test "Creating a zero size window must fail" {
    try init();
    defer deinit();
    testing.expectError(error.GlfwInvalidValue, createWindow(0, 0, "test"));
}

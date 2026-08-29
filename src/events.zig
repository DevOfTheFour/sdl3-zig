//! The event queue, as a Zig tagged union.
//!
//! SDL hands over a C union plus a type tag and leaves the two to be kept in
//! agreement by hand. `Event` is the same information as a `union(enum)`, so
//! the payload you can reach is the payload the tag says is there, and a
//! `switch` over it is exhaustive.
//!
//! Anything the wrapper does not name yet arrives as `.other`, carrying the
//! raw union, so no event is ever dropped on the floor.

const std = @import("std");
const raw = @import("sdl3_raw");
const errors = @import("errors.zig");
const keyboard_mod = @import("keyboard.zig");
const mouse_mod = @import("mouse.zig");
const gamepad_mod = @import("gamepad.zig");
const video_mod = @import("video.zig");
const rect_mod = @import("rect.zig");

const Error = errors.Error;
const check = errors.check;
const WindowId = video_mod.WindowId;
const DisplayId = video_mod.DisplayId;
const Point = rect_mod.Point;
const Size = rect_mod.Size;

/// Every event SDL can queue. Mostly useful for `has`, `flush` and reading
/// `.other`; a handler switches on `Event` instead.
pub const EventType = enum(u32) {
    quit = raw.SDL_EVENT_QUIT,
    terminating = raw.SDL_EVENT_TERMINATING,
    low_memory = raw.SDL_EVENT_LOW_MEMORY,
    will_enter_background = raw.SDL_EVENT_WILL_ENTER_BACKGROUND,
    did_enter_background = raw.SDL_EVENT_DID_ENTER_BACKGROUND,
    will_enter_foreground = raw.SDL_EVENT_WILL_ENTER_FOREGROUND,
    did_enter_foreground = raw.SDL_EVENT_DID_ENTER_FOREGROUND,
    locale_changed = raw.SDL_EVENT_LOCALE_CHANGED,
    system_theme_changed = raw.SDL_EVENT_SYSTEM_THEME_CHANGED,
    display_orientation = raw.SDL_EVENT_DISPLAY_ORIENTATION,
    display_added = raw.SDL_EVENT_DISPLAY_ADDED,
    display_removed = raw.SDL_EVENT_DISPLAY_REMOVED,
    display_moved = raw.SDL_EVENT_DISPLAY_MOVED,
    display_desktop_mode_changed = raw.SDL_EVENT_DISPLAY_DESKTOP_MODE_CHANGED,
    display_current_mode_changed = raw.SDL_EVENT_DISPLAY_CURRENT_MODE_CHANGED,
    display_content_scale_changed = raw.SDL_EVENT_DISPLAY_CONTENT_SCALE_CHANGED,
    display_usable_bounds_changed = raw.SDL_EVENT_DISPLAY_USABLE_BOUNDS_CHANGED,
    window_shown = raw.SDL_EVENT_WINDOW_SHOWN,
    window_hidden = raw.SDL_EVENT_WINDOW_HIDDEN,
    window_exposed = raw.SDL_EVENT_WINDOW_EXPOSED,
    window_moved = raw.SDL_EVENT_WINDOW_MOVED,
    window_resized = raw.SDL_EVENT_WINDOW_RESIZED,
    window_pixel_size_changed = raw.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED,
    window_metal_view_resized = raw.SDL_EVENT_WINDOW_METAL_VIEW_RESIZED,
    window_minimized = raw.SDL_EVENT_WINDOW_MINIMIZED,
    window_maximized = raw.SDL_EVENT_WINDOW_MAXIMIZED,
    window_restored = raw.SDL_EVENT_WINDOW_RESTORED,
    window_mouse_enter = raw.SDL_EVENT_WINDOW_MOUSE_ENTER,
    window_mouse_leave = raw.SDL_EVENT_WINDOW_MOUSE_LEAVE,
    window_focus_gained = raw.SDL_EVENT_WINDOW_FOCUS_GAINED,
    window_focus_lost = raw.SDL_EVENT_WINDOW_FOCUS_LOST,
    window_close_requested = raw.SDL_EVENT_WINDOW_CLOSE_REQUESTED,
    window_hit_test = raw.SDL_EVENT_WINDOW_HIT_TEST,
    window_iccprof_changed = raw.SDL_EVENT_WINDOW_ICCPROF_CHANGED,
    window_display_changed = raw.SDL_EVENT_WINDOW_DISPLAY_CHANGED,
    window_display_scale_changed = raw.SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED,
    window_safe_area_changed = raw.SDL_EVENT_WINDOW_SAFE_AREA_CHANGED,
    window_occluded = raw.SDL_EVENT_WINDOW_OCCLUDED,
    window_enter_fullscreen = raw.SDL_EVENT_WINDOW_ENTER_FULLSCREEN,
    window_leave_fullscreen = raw.SDL_EVENT_WINDOW_LEAVE_FULLSCREEN,
    window_destroyed = raw.SDL_EVENT_WINDOW_DESTROYED,
    window_hdr_state_changed = raw.SDL_EVENT_WINDOW_HDR_STATE_CHANGED,
    key_down = raw.SDL_EVENT_KEY_DOWN,
    key_up = raw.SDL_EVENT_KEY_UP,
    text_editing = raw.SDL_EVENT_TEXT_EDITING,
    text_input = raw.SDL_EVENT_TEXT_INPUT,
    keymap_changed = raw.SDL_EVENT_KEYMAP_CHANGED,
    keyboard_added = raw.SDL_EVENT_KEYBOARD_ADDED,
    keyboard_removed = raw.SDL_EVENT_KEYBOARD_REMOVED,
    text_editing_candidates = raw.SDL_EVENT_TEXT_EDITING_CANDIDATES,
    screen_keyboard_shown = raw.SDL_EVENT_SCREEN_KEYBOARD_SHOWN,
    screen_keyboard_hidden = raw.SDL_EVENT_SCREEN_KEYBOARD_HIDDEN,
    mouse_motion = raw.SDL_EVENT_MOUSE_MOTION,
    mouse_button_down = raw.SDL_EVENT_MOUSE_BUTTON_DOWN,
    mouse_button_up = raw.SDL_EVENT_MOUSE_BUTTON_UP,
    mouse_wheel = raw.SDL_EVENT_MOUSE_WHEEL,
    mouse_added = raw.SDL_EVENT_MOUSE_ADDED,
    mouse_removed = raw.SDL_EVENT_MOUSE_REMOVED,
    joystick_axis_motion = raw.SDL_EVENT_JOYSTICK_AXIS_MOTION,
    joystick_ball_motion = raw.SDL_EVENT_JOYSTICK_BALL_MOTION,
    joystick_hat_motion = raw.SDL_EVENT_JOYSTICK_HAT_MOTION,
    joystick_button_down = raw.SDL_EVENT_JOYSTICK_BUTTON_DOWN,
    joystick_button_up = raw.SDL_EVENT_JOYSTICK_BUTTON_UP,
    joystick_added = raw.SDL_EVENT_JOYSTICK_ADDED,
    joystick_removed = raw.SDL_EVENT_JOYSTICK_REMOVED,
    joystick_battery_updated = raw.SDL_EVENT_JOYSTICK_BATTERY_UPDATED,
    joystick_update_complete = raw.SDL_EVENT_JOYSTICK_UPDATE_COMPLETE,
    gamepad_axis_motion = raw.SDL_EVENT_GAMEPAD_AXIS_MOTION,
    gamepad_button_down = raw.SDL_EVENT_GAMEPAD_BUTTON_DOWN,
    gamepad_button_up = raw.SDL_EVENT_GAMEPAD_BUTTON_UP,
    gamepad_added = raw.SDL_EVENT_GAMEPAD_ADDED,
    gamepad_removed = raw.SDL_EVENT_GAMEPAD_REMOVED,
    gamepad_remapped = raw.SDL_EVENT_GAMEPAD_REMAPPED,
    gamepad_touchpad_down = raw.SDL_EVENT_GAMEPAD_TOUCHPAD_DOWN,
    gamepad_touchpad_motion = raw.SDL_EVENT_GAMEPAD_TOUCHPAD_MOTION,
    gamepad_touchpad_up = raw.SDL_EVENT_GAMEPAD_TOUCHPAD_UP,
    gamepad_sensor_update = raw.SDL_EVENT_GAMEPAD_SENSOR_UPDATE,
    gamepad_update_complete = raw.SDL_EVENT_GAMEPAD_UPDATE_COMPLETE,
    gamepad_steam_handle_updated = raw.SDL_EVENT_GAMEPAD_STEAM_HANDLE_UPDATED,
    finger_down = raw.SDL_EVENT_FINGER_DOWN,
    finger_up = raw.SDL_EVENT_FINGER_UP,
    finger_motion = raw.SDL_EVENT_FINGER_MOTION,
    finger_canceled = raw.SDL_EVENT_FINGER_CANCELED,
    pinch_begin = raw.SDL_EVENT_PINCH_BEGIN,
    pinch_update = raw.SDL_EVENT_PINCH_UPDATE,
    pinch_end = raw.SDL_EVENT_PINCH_END,
    clipboard_update = raw.SDL_EVENT_CLIPBOARD_UPDATE,
    drop_file = raw.SDL_EVENT_DROP_FILE,
    drop_text = raw.SDL_EVENT_DROP_TEXT,
    drop_begin = raw.SDL_EVENT_DROP_BEGIN,
    drop_complete = raw.SDL_EVENT_DROP_COMPLETE,
    drop_position = raw.SDL_EVENT_DROP_POSITION,
    audio_device_added = raw.SDL_EVENT_AUDIO_DEVICE_ADDED,
    audio_device_removed = raw.SDL_EVENT_AUDIO_DEVICE_REMOVED,
    audio_device_format_changed = raw.SDL_EVENT_AUDIO_DEVICE_FORMAT_CHANGED,
    sensor_update = raw.SDL_EVENT_SENSOR_UPDATE,
    pen_proximity_in = raw.SDL_EVENT_PEN_PROXIMITY_IN,
    pen_proximity_out = raw.SDL_EVENT_PEN_PROXIMITY_OUT,
    pen_down = raw.SDL_EVENT_PEN_DOWN,
    pen_up = raw.SDL_EVENT_PEN_UP,
    pen_button_down = raw.SDL_EVENT_PEN_BUTTON_DOWN,
    pen_button_up = raw.SDL_EVENT_PEN_BUTTON_UP,
    pen_motion = raw.SDL_EVENT_PEN_MOTION,
    pen_axis = raw.SDL_EVENT_PEN_AXIS,
    camera_device_added = raw.SDL_EVENT_CAMERA_DEVICE_ADDED,
    camera_device_removed = raw.SDL_EVENT_CAMERA_DEVICE_REMOVED,
    camera_device_approved = raw.SDL_EVENT_CAMERA_DEVICE_APPROVED,
    camera_device_denied = raw.SDL_EVENT_CAMERA_DEVICE_DENIED,
    render_targets_reset = raw.SDL_EVENT_RENDER_TARGETS_RESET,
    render_device_reset = raw.SDL_EVENT_RENDER_DEVICE_RESET,
    render_device_lost = raw.SDL_EVENT_RENDER_DEVICE_LOST,
    private0 = raw.SDL_EVENT_PRIVATE0,
    private1 = raw.SDL_EVENT_PRIVATE1,
    private2 = raw.SDL_EVENT_PRIVATE2,
    private3 = raw.SDL_EVENT_PRIVATE3,
    poll_sentinel = raw.SDL_EVENT_POLL_SENTINEL,
    user = raw.SDL_EVENT_USER,
    _,
};

// ---------------------------------------------------------------------
// Payloads
// ---------------------------------------------------------------------

/// Timestamps are nanoseconds on SDL's monotonic clock, the same one
/// `timer.ticksNs` reads.
pub const Simple = struct {
    timestamp: u64,
};

pub const Display = struct {
    timestamp: u64,
    display_id: DisplayId,
    kind: Kind,

    pub const Kind = union(enum) {
        orientation: video_mod.DisplayOrientation,
        added,
        removed,
        moved,
        desktop_mode_changed,
        current_mode_changed,
        content_scale_changed,
        usable_bounds_changed,
        unknown: u32,
    };
};

pub const WindowEvent = struct {
    timestamp: u64,
    window_id: WindowId,
    kind: Kind,

    /// SDL spends one event type per window state change; they fold into one
    /// variant with the change as the payload.
    pub const Kind = union(enum) {
        shown,
        hidden,
        exposed,
        moved: Point,
        /// The window's size in screen coordinates changed.
        resized: Size,
        /// The size in *pixels* changed. This is the one a renderer or
        /// swapchain has to react to, and on a high-DPI display it is not the
        /// same number as `resized`.
        pixel_size_changed: Size,
        metal_view_resized: Size,
        minimized,
        maximized,
        restored,
        mouse_enter,
        mouse_leave,
        focus_gained,
        focus_lost,
        /// The user clicked the close button. Nothing has closed yet -- this
        /// is a request, and ignoring it keeps the window open.
        close_requested,
        hit_test,
        icc_profile_changed,
        display_changed: DisplayId,
        display_scale_changed,
        safe_area_changed,
        occluded,
        enter_fullscreen,
        leave_fullscreen,
        /// The window is being destroyed; its id is about to become invalid.
        destroyed,
        hdr_state_changed,
        unknown: u32,
    };
};

pub const Key = struct {
    timestamp: u64,
    window_id: WindowId,
    which: keyboard_mod.KeyboardId,
    /// The physical key position. Bind gameplay to this.
    scancode: keyboard_mod.Scancode,
    /// What that key types under the current layout. Bind shortcuts to this.
    key: keyboard_mod.Keycode,
    mod: keyboard_mod.KeyMod,
    /// The platform's own key code, unprocessed.
    raw_code: u16,
    down: bool,
    /// True for the auto-repeats that follow a held key.
    repeat: bool,
};

pub const TextInput = struct {
    timestamp: u64,
    window_id: WindowId,
    /// Borrowed from SDL and valid only until the next `poll`. Copy it to
    /// keep it.
    text: [:0]const u8,
};

pub const TextEditing = struct {
    timestamp: u64,
    window_id: WindowId,
    /// The in-progress IME composition. Borrowed, like `TextInput.text`.
    text: [:0]const u8,
    /// The selected range within `text`, or -1 when there is none.
    start: i32,
    length: i32,
};

pub const MouseMotion = struct {
    timestamp: u64,
    window_id: WindowId,
    which: mouse_mod.MouseId,
    buttons: mouse_mod.ButtonState,
    x: f32,
    y: f32,
    /// Motion since the last event. Use these rather than differencing `x`
    /// and `y`: in relative mode they are the only meaningful reading.
    xrel: f32,
    yrel: f32,
};

pub const MouseButton = struct {
    timestamp: u64,
    window_id: WindowId,
    which: mouse_mod.MouseId,
    button: mouse_mod.Button,
    down: bool,
    /// 1 for a single click, 2 for a double, and so on.
    clicks: u8,
    x: f32,
    y: f32,
};

pub const MouseWheel = struct {
    timestamp: u64,
    window_id: WindowId,
    which: mouse_mod.MouseId,
    x: f32,
    y: f32,
    direction: mouse_mod.WheelDirection,
    /// Where the pointer was, which the wheel deltas do not tell you.
    mouse_x: f32,
    mouse_y: f32,
    /// The same scroll accumulated into whole notches, for a UI that wants
    /// discrete steps rather than a smooth trackpad glide.
    integer_x: i32,
    integer_y: i32,
};

pub const MouseDevice = struct {
    timestamp: u64,
    which: mouse_mod.MouseId,
};

pub const GamepadAxis = struct {
    timestamp: u64,
    which: gamepad_mod.JoystickId,
    axis: gamepad_mod.Axis,
    value: i16,
};

pub const GamepadButton = struct {
    timestamp: u64,
    which: gamepad_mod.JoystickId,
    button: gamepad_mod.Button,
    down: bool,
};

pub const GamepadDevice = struct {
    timestamp: u64,
    which: gamepad_mod.JoystickId,
};

pub const JoystickDevice = struct {
    timestamp: u64,
    which: gamepad_mod.JoystickId,
};

pub const TouchFinger = struct {
    timestamp: u64,
    touch_id: u64,
    finger_id: u64,
    /// Normalised 0..1 across the window, not pixels.
    x: f32,
    y: f32,
    dx: f32,
    dy: f32,
    pressure: f32,
    window_id: WindowId,
};

pub const Drop = struct {
    timestamp: u64,
    window_id: WindowId,
    /// Where in the window the drop landed.
    x: f32,
    y: f32,
    /// The application the drop came from, when the platform says.
    source: ?[:0]const u8,
    /// The path for `drop_file`, the text for `drop_text`, null for the
    /// begin and complete markers. Borrowed until the next `poll`.
    data: ?[:0]const u8,
};

pub const AudioDevice = struct {
    timestamp: u64,
    which: u32,
    /// True for a capture device rather than a playback one.
    recording: bool,
};

pub const Render = struct {
    timestamp: u64,
    window_id: WindowId,
};

pub const User = struct {
    /// The type this event was pushed with, from `registerEvents`.
    type: u32,
    timestamp: u64,
    window_id: WindowId,
    code: i32,
    data1: ?*anyopaque,
    data2: ?*anyopaque,
};

// ---------------------------------------------------------------------
// The event
// ---------------------------------------------------------------------

pub const Event = union(enum) {
    quit: Simple,
    /// The OS is about to kill the process. Save now; there may be no later.
    terminating: Simple,
    low_memory: Simple,
    will_enter_background: Simple,
    did_enter_background: Simple,
    will_enter_foreground: Simple,
    did_enter_foreground: Simple,
    locale_changed: Simple,
    system_theme_changed: Simple,
    clipboard_update: Simple,
    keymap_changed: Simple,

    display: Display,
    window: WindowEvent,

    key_down: Key,
    key_up: Key,
    text_input: TextInput,
    text_editing: TextEditing,

    mouse_motion: MouseMotion,
    mouse_button_down: MouseButton,
    mouse_button_up: MouseButton,
    mouse_wheel: MouseWheel,
    mouse_added: MouseDevice,
    mouse_removed: MouseDevice,

    gamepad_axis_motion: GamepadAxis,
    gamepad_button_down: GamepadButton,
    gamepad_button_up: GamepadButton,
    gamepad_added: GamepadDevice,
    gamepad_removed: GamepadDevice,
    gamepad_remapped: GamepadDevice,

    joystick_added: JoystickDevice,
    joystick_removed: JoystickDevice,

    finger_down: TouchFinger,
    finger_up: TouchFinger,
    finger_motion: TouchFinger,
    finger_canceled: TouchFinger,

    drop_file: Drop,
    drop_text: Drop,
    drop_begin: Drop,
    drop_complete: Drop,
    drop_position: Drop,

    audio_device_added: AudioDevice,
    audio_device_removed: AudioDevice,
    audio_device_format_changed: AudioDevice,

    /// Every texture the renderer owns has been lost and must be recreated.
    render_targets_reset: Render,
    render_device_reset: Render,
    render_device_lost: Render,

    user: User,

    /// An event the wrapper does not name yet, with SDL's own union intact.
    other: raw.SDL_Event,

    /// The window this event concerns, when it concerns one. Note that the
    /// window may already have been destroyed by the time the event is read.
    pub fn targetWindow(self: Event) ?video_mod.Window {
        return switch (self) {
            .window => |e| video_mod.Window.fromId(e.window_id),
            .key_down, .key_up => |e| video_mod.Window.fromId(e.window_id),
            .text_input => |e| video_mod.Window.fromId(e.window_id),
            .text_editing => |e| video_mod.Window.fromId(e.window_id),
            .mouse_motion => |e| video_mod.Window.fromId(e.window_id),
            .mouse_button_down, .mouse_button_up => |e| video_mod.Window.fromId(e.window_id),
            .mouse_wheel => |e| video_mod.Window.fromId(e.window_id),
            .drop_file, .drop_text, .drop_begin, .drop_complete, .drop_position => |e| video_mod.Window.fromId(e.window_id),
            else => null,
        };
    }

    /// True for the two events that end an application: the quit request, and
    /// a close on the window whose id is given.
    pub fn isQuitFor(self: Event, window_id: WindowId) bool {
        return switch (self) {
            .quit => true,
            .window => |e| e.window_id == window_id and e.kind == .close_requested,
            else => false,
        };
    }
};

fn spanOrNull(text: [*c]const u8) ?[:0]const u8 {
    if (text == null) return null;
    return std.mem.span(text);
}

fn spanOrEmpty(text: [*c]const u8) [:0]const u8 {
    if (text == null) return "";
    return std.mem.span(text);
}

fn windowKind(event: raw.SDL_WindowEvent) WindowEvent.Kind {
    return switch (@as(c_int, @intCast(event.type))) {
        raw.SDL_EVENT_WINDOW_SHOWN => .shown,
        raw.SDL_EVENT_WINDOW_HIDDEN => .hidden,
        raw.SDL_EVENT_WINDOW_EXPOSED => .exposed,
        raw.SDL_EVENT_WINDOW_MOVED => .{ .moved = .{ .x = event.data1, .y = event.data2 } },
        raw.SDL_EVENT_WINDOW_RESIZED => .{
            .resized = .{ .width = event.data1, .height = event.data2 },
        },
        raw.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED => .{
            .pixel_size_changed = .{ .width = event.data1, .height = event.data2 },
        },
        raw.SDL_EVENT_WINDOW_METAL_VIEW_RESIZED => .{
            .metal_view_resized = .{ .width = event.data1, .height = event.data2 },
        },
        raw.SDL_EVENT_WINDOW_MINIMIZED => .minimized,
        raw.SDL_EVENT_WINDOW_MAXIMIZED => .maximized,
        raw.SDL_EVENT_WINDOW_RESTORED => .restored,
        raw.SDL_EVENT_WINDOW_MOUSE_ENTER => .mouse_enter,
        raw.SDL_EVENT_WINDOW_MOUSE_LEAVE => .mouse_leave,
        raw.SDL_EVENT_WINDOW_FOCUS_GAINED => .focus_gained,
        raw.SDL_EVENT_WINDOW_FOCUS_LOST => .focus_lost,
        raw.SDL_EVENT_WINDOW_CLOSE_REQUESTED => .close_requested,
        raw.SDL_EVENT_WINDOW_HIT_TEST => .hit_test,
        raw.SDL_EVENT_WINDOW_ICCPROF_CHANGED => .icc_profile_changed,
        raw.SDL_EVENT_WINDOW_DISPLAY_CHANGED => .{ .display_changed = @intCast(event.data1) },
        raw.SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED => .display_scale_changed,
        raw.SDL_EVENT_WINDOW_SAFE_AREA_CHANGED => .safe_area_changed,
        raw.SDL_EVENT_WINDOW_OCCLUDED => .occluded,
        raw.SDL_EVENT_WINDOW_ENTER_FULLSCREEN => .enter_fullscreen,
        raw.SDL_EVENT_WINDOW_LEAVE_FULLSCREEN => .leave_fullscreen,
        raw.SDL_EVENT_WINDOW_DESTROYED => .destroyed,
        raw.SDL_EVENT_WINDOW_HDR_STATE_CHANGED => .hdr_state_changed,
        else => .{ .unknown = event.type },
    };
}

fn displayKind(event: raw.SDL_DisplayEvent) Display.Kind {
    return switch (@as(c_int, @intCast(event.type))) {
        raw.SDL_EVENT_DISPLAY_ORIENTATION => .{ .orientation = @fromBackingInt(@intCast(event.data1)) },
        raw.SDL_EVENT_DISPLAY_ADDED => .added,
        raw.SDL_EVENT_DISPLAY_REMOVED => .removed,
        raw.SDL_EVENT_DISPLAY_MOVED => .moved,
        raw.SDL_EVENT_DISPLAY_DESKTOP_MODE_CHANGED => .desktop_mode_changed,
        raw.SDL_EVENT_DISPLAY_CURRENT_MODE_CHANGED => .current_mode_changed,
        raw.SDL_EVENT_DISPLAY_CONTENT_SCALE_CHANGED => .content_scale_changed,
        raw.SDL_EVENT_DISPLAY_USABLE_BOUNDS_CHANGED => .usable_bounds_changed,
        else => .{ .unknown = event.type },
    };
}

fn keyPayload(e: raw.SDL_KeyboardEvent) Key {
    return .{
        .timestamp = e.timestamp,
        .window_id = e.windowID,
        .which = e.which,
        .scancode = @fromBackingInt(@intCast(e.scancode)),
        .key = @fromBackingInt(@intCast(e.key)),
        .mod = @bitCast(e.mod),
        .raw_code = e.raw,
        .down = e.down,
        .repeat = e.repeat,
    };
}

fn mouseButtonPayload(e: raw.SDL_MouseButtonEvent) MouseButton {
    return .{
        .timestamp = e.timestamp,
        .window_id = e.windowID,
        .which = e.which,
        .button = @fromBackingInt(@intCast(e.button)),
        .down = e.down,
        .clicks = e.clicks,
        .x = e.x,
        .y = e.y,
    };
}

fn touchPayload(e: raw.SDL_TouchFingerEvent) TouchFinger {
    return .{
        .timestamp = e.timestamp,
        .touch_id = e.touchID,
        .finger_id = e.fingerID,
        .x = e.x,
        .y = e.y,
        .dx = e.dx,
        .dy = e.dy,
        .pressure = e.pressure,
        .window_id = e.windowID,
    };
}

fn dropPayload(e: raw.SDL_DropEvent) Drop {
    return .{
        .timestamp = e.timestamp,
        .window_id = e.windowID,
        .x = e.x,
        .y = e.y,
        .source = spanOrNull(e.source),
        .data = spanOrNull(e.data),
    };
}

fn audioPayload(e: raw.SDL_AudioDeviceEvent) AudioDevice {
    return .{ .timestamp = e.timestamp, .which = e.which, .recording = e.recording };
}

fn gamepadDevicePayload(e: raw.SDL_GamepadDeviceEvent) GamepadDevice {
    return .{ .timestamp = e.timestamp, .which = e.which };
}

fn renderPayload(e: raw.SDL_RenderEvent) Render {
    return .{ .timestamp = e.timestamp, .window_id = e.windowID };
}

/// Reads SDL's union through the member the tag says is live.
pub fn fromRaw(event: raw.SDL_Event) Event {
    const simple: Simple = .{ .timestamp = event.common.timestamp };
    return switch (@as(c_int, @intCast(event.type))) {
        raw.SDL_EVENT_QUIT => .{ .quit = simple },
        raw.SDL_EVENT_TERMINATING => .{ .terminating = simple },
        raw.SDL_EVENT_LOW_MEMORY => .{ .low_memory = simple },
        raw.SDL_EVENT_WILL_ENTER_BACKGROUND => .{ .will_enter_background = simple },
        raw.SDL_EVENT_DID_ENTER_BACKGROUND => .{ .did_enter_background = simple },
        raw.SDL_EVENT_WILL_ENTER_FOREGROUND => .{ .will_enter_foreground = simple },
        raw.SDL_EVENT_DID_ENTER_FOREGROUND => .{ .did_enter_foreground = simple },
        raw.SDL_EVENT_LOCALE_CHANGED => .{ .locale_changed = simple },
        raw.SDL_EVENT_SYSTEM_THEME_CHANGED => .{ .system_theme_changed = simple },
        raw.SDL_EVENT_CLIPBOARD_UPDATE => .{ .clipboard_update = simple },
        raw.SDL_EVENT_KEYMAP_CHANGED => .{ .keymap_changed = simple },

        raw.SDL_EVENT_DISPLAY_ORIENTATION,
        raw.SDL_EVENT_DISPLAY_ADDED,
        raw.SDL_EVENT_DISPLAY_REMOVED,
        raw.SDL_EVENT_DISPLAY_MOVED,
        raw.SDL_EVENT_DISPLAY_DESKTOP_MODE_CHANGED,
        raw.SDL_EVENT_DISPLAY_CURRENT_MODE_CHANGED,
        raw.SDL_EVENT_DISPLAY_CONTENT_SCALE_CHANGED,
        raw.SDL_EVENT_DISPLAY_USABLE_BOUNDS_CHANGED,
        => .{ .display = .{
            .timestamp = event.display.timestamp,
            .display_id = event.display.displayID,
            .kind = displayKind(event.display),
        } },

        raw.SDL_EVENT_WINDOW_SHOWN...raw.SDL_EVENT_WINDOW_HDR_STATE_CHANGED => .{ .window = .{
            .timestamp = event.window.timestamp,
            .window_id = event.window.windowID,
            .kind = windowKind(event.window),
        } },

        raw.SDL_EVENT_KEY_DOWN => .{ .key_down = keyPayload(event.key) },
        raw.SDL_EVENT_KEY_UP => .{ .key_up = keyPayload(event.key) },
        raw.SDL_EVENT_TEXT_INPUT => .{ .text_input = .{
            .timestamp = event.text.timestamp,
            .window_id = event.text.windowID,
            .text = spanOrEmpty(event.text.text),
        } },
        raw.SDL_EVENT_TEXT_EDITING => .{ .text_editing = .{
            .timestamp = event.edit.timestamp,
            .window_id = event.edit.windowID,
            .text = spanOrEmpty(event.edit.text),
            .start = event.edit.start,
            .length = event.edit.length,
        } },

        raw.SDL_EVENT_MOUSE_MOTION => .{ .mouse_motion = .{
            .timestamp = event.motion.timestamp,
            .window_id = event.motion.windowID,
            .which = event.motion.which,
            .buttons = @bitCast(event.motion.state),
            .x = event.motion.x,
            .y = event.motion.y,
            .xrel = event.motion.xrel,
            .yrel = event.motion.yrel,
        } },
        raw.SDL_EVENT_MOUSE_BUTTON_DOWN => .{ .mouse_button_down = mouseButtonPayload(event.button) },
        raw.SDL_EVENT_MOUSE_BUTTON_UP => .{ .mouse_button_up = mouseButtonPayload(event.button) },
        raw.SDL_EVENT_MOUSE_WHEEL => .{ .mouse_wheel = .{
            .timestamp = event.wheel.timestamp,
            .window_id = event.wheel.windowID,
            .which = event.wheel.which,
            .x = event.wheel.x,
            .y = event.wheel.y,
            .direction = @fromBackingInt(@intCast(event.wheel.direction)),
            .mouse_x = event.wheel.mouse_x,
            .mouse_y = event.wheel.mouse_y,
            .integer_x = event.wheel.integer_x,
            .integer_y = event.wheel.integer_y,
        } },
        raw.SDL_EVENT_MOUSE_ADDED => .{ .mouse_added = .{
            .timestamp = event.mdevice.timestamp,
            .which = event.mdevice.which,
        } },
        raw.SDL_EVENT_MOUSE_REMOVED => .{ .mouse_removed = .{
            .timestamp = event.mdevice.timestamp,
            .which = event.mdevice.which,
        } },

        raw.SDL_EVENT_GAMEPAD_AXIS_MOTION => .{ .gamepad_axis_motion = .{
            .timestamp = event.gaxis.timestamp,
            .which = event.gaxis.which,
            .axis = @fromBackingInt(@intCast(event.gaxis.axis)),
            .value = event.gaxis.value,
        } },
        raw.SDL_EVENT_GAMEPAD_BUTTON_DOWN => .{ .gamepad_button_down = .{
            .timestamp = event.gbutton.timestamp,
            .which = event.gbutton.which,
            .button = @fromBackingInt(@intCast(event.gbutton.button)),
            .down = event.gbutton.down,
        } },
        raw.SDL_EVENT_GAMEPAD_BUTTON_UP => .{ .gamepad_button_up = .{
            .timestamp = event.gbutton.timestamp,
            .which = event.gbutton.which,
            .button = @fromBackingInt(@intCast(event.gbutton.button)),
            .down = event.gbutton.down,
        } },
        raw.SDL_EVENT_GAMEPAD_ADDED => .{ .gamepad_added = gamepadDevicePayload(event.gdevice) },
        raw.SDL_EVENT_GAMEPAD_REMOVED => .{ .gamepad_removed = gamepadDevicePayload(event.gdevice) },
        raw.SDL_EVENT_GAMEPAD_REMAPPED => .{ .gamepad_remapped = gamepadDevicePayload(event.gdevice) },

        raw.SDL_EVENT_JOYSTICK_ADDED => .{ .joystick_added = .{
            .timestamp = event.jdevice.timestamp,
            .which = event.jdevice.which,
        } },
        raw.SDL_EVENT_JOYSTICK_REMOVED => .{ .joystick_removed = .{
            .timestamp = event.jdevice.timestamp,
            .which = event.jdevice.which,
        } },

        raw.SDL_EVENT_FINGER_DOWN => .{ .finger_down = touchPayload(event.tfinger) },
        raw.SDL_EVENT_FINGER_UP => .{ .finger_up = touchPayload(event.tfinger) },
        raw.SDL_EVENT_FINGER_MOTION => .{ .finger_motion = touchPayload(event.tfinger) },
        raw.SDL_EVENT_FINGER_CANCELED => .{ .finger_canceled = touchPayload(event.tfinger) },

        raw.SDL_EVENT_DROP_FILE => .{ .drop_file = dropPayload(event.drop) },
        raw.SDL_EVENT_DROP_TEXT => .{ .drop_text = dropPayload(event.drop) },
        raw.SDL_EVENT_DROP_BEGIN => .{ .drop_begin = dropPayload(event.drop) },
        raw.SDL_EVENT_DROP_COMPLETE => .{ .drop_complete = dropPayload(event.drop) },
        raw.SDL_EVENT_DROP_POSITION => .{ .drop_position = dropPayload(event.drop) },

        raw.SDL_EVENT_AUDIO_DEVICE_ADDED => .{ .audio_device_added = audioPayload(event.adevice) },
        raw.SDL_EVENT_AUDIO_DEVICE_REMOVED => .{ .audio_device_removed = audioPayload(event.adevice) },
        raw.SDL_EVENT_AUDIO_DEVICE_FORMAT_CHANGED => .{
            .audio_device_format_changed = audioPayload(event.adevice),
        },

        raw.SDL_EVENT_RENDER_TARGETS_RESET => .{ .render_targets_reset = renderPayload(event.render) },
        raw.SDL_EVENT_RENDER_DEVICE_RESET => .{ .render_device_reset = renderPayload(event.render) },
        raw.SDL_EVENT_RENDER_DEVICE_LOST => .{ .render_device_lost = renderPayload(event.render) },

        else => {
            if (event.type >= raw.SDL_EVENT_USER) return .{ .user = .{
                .type = event.user.type,
                .timestamp = event.user.timestamp,
                .window_id = event.user.windowID,
                .code = event.user.code,
                .data1 = event.user.data1,
                .data2 = event.user.data2,
            } };
            return .{ .other = event };
        },
    };
}

// ---------------------------------------------------------------------
// The queue
// ---------------------------------------------------------------------

/// Takes the next event, or null when the queue is empty. This also pumps the
/// queue, so a loop that polls needs no separate `pump`.
pub fn poll() ?Event {
    var event: raw.SDL_Event = undefined;
    if (!raw.SDL_PollEvent(&event)) return null;
    return fromRaw(event);
}

/// The same, without the conversion, for a caller reaching into SDL's union
/// directly.
pub fn pollRaw() ?raw.SDL_Event {
    var event: raw.SDL_Event = undefined;
    if (!raw.SDL_PollEvent(&event)) return null;
    return event;
}

/// Blocks until an event arrives. Fails only if SDL's event subsystem does.
pub fn wait() Error!Event {
    var event: raw.SDL_Event = undefined;
    try check(raw.SDL_WaitEvent(&event));
    return fromRaw(event);
}

/// Blocks for at most `timeout_ms`. Null on timeout.
pub fn waitTimeout(timeout_ms: i32) ?Event {
    var event: raw.SDL_Event = undefined;
    if (!raw.SDL_WaitEventTimeout(&event, timeout_ms)) return null;
    return fromRaw(event);
}

/// Collects input from the platform into the queue. `poll` and `wait` do this
/// for you; call it directly only when reading `keyboard.state` without
/// draining the queue.
pub fn pump() void {
    raw.SDL_PumpEvents();
}

pub fn has(event_type: EventType) bool {
    return raw.SDL_HasEvent(@backingInt(event_type));
}

/// Drops every queued event of one type. Useful after a mode change that
/// makes the queued input meaningless.
pub fn flush(event_type: EventType) void {
    raw.SDL_FlushEvent(@backingInt(event_type));
}

/// Reserves a contiguous range of user event types. Returns the first, or an
/// error when SDL has none left.
pub fn registerEvents(count: u32) Error!u32 {
    const first = raw.SDL_RegisterEvents(@intCast(count));
    if (first == 0) return Error.SdlError;
    return first;
}

/// Queues a user event. `event_type` must come from `registerEvents`.
pub fn pushUser(event_type: u32, code: i32, data1: ?*anyopaque, data2: ?*anyopaque) Error!void {
    var event: raw.SDL_Event = std.mem.zeroes(raw.SDL_Event);
    event.user = .{
        .type = event_type,
        .reserved = 0,
        .timestamp = 0,
        .windowID = 0,
        .code = code,
        .data1 = data1,
        .data2 = data2,
    };
    try check(raw.SDL_PushEvent(&event));
}

/// Pushes an event SDL built. `push`ing a raw event is the escape hatch for
/// anything `pushUser` cannot express.
pub fn pushRaw(event: *raw.SDL_Event) Error!void {
    try check(raw.SDL_PushEvent(event));
}

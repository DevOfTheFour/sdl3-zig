//! Gamepads: SDL's mapped view of a controller, where every pad has the same
//! buttons and axes whatever the hardware underneath is.
//!
//! Buttons are named by *position*, not by label -- `.south` is the bottom
//! face button, which is A on an Xbox pad and Cross on a PlayStation one.
//! `Gamepad.buttonLabel` gives the label to print; `.south` gives the button
//! to bind. That is the whole point of the split.

const std = @import("std");
const raw = @import("sdl3_raw");
const errors = @import("errors.zig");

const Error = errors.Error;
const check = errors.check;

/// SDL's id for a connected device. Stable while it stays plugged in.
pub const JoystickId = u32;

pub const Type = enum(c_uint) {
    unknown = raw.SDL_GAMEPAD_TYPE_UNKNOWN,
    standard = raw.SDL_GAMEPAD_TYPE_STANDARD,
    xbox360 = raw.SDL_GAMEPAD_TYPE_XBOX360,
    xboxone = raw.SDL_GAMEPAD_TYPE_XBOXONE,
    ps3 = raw.SDL_GAMEPAD_TYPE_PS3,
    ps4 = raw.SDL_GAMEPAD_TYPE_PS4,
    ps5 = raw.SDL_GAMEPAD_TYPE_PS5,
    switch_pro = raw.SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_PRO,
    switch_joycon_left = raw.SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_LEFT,
    switch_joycon_right = raw.SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_RIGHT,
    switch_joycon_pair = raw.SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_PAIR,
    gamecube = raw.SDL_GAMEPAD_TYPE_GAMECUBE,
    _,
};

/// Buttons by position on the pad.
pub const Button = enum(c_int) {
    invalid = raw.SDL_GAMEPAD_BUTTON_INVALID,
    /// Bottom face button: A on Xbox, Cross on PlayStation, B on Nintendo.
    south = raw.SDL_GAMEPAD_BUTTON_SOUTH,
    east = raw.SDL_GAMEPAD_BUTTON_EAST,
    west = raw.SDL_GAMEPAD_BUTTON_WEST,
    north = raw.SDL_GAMEPAD_BUTTON_NORTH,
    back = raw.SDL_GAMEPAD_BUTTON_BACK,
    /// The centre button: Xbox button, PS button, Home.
    guide = raw.SDL_GAMEPAD_BUTTON_GUIDE,
    start = raw.SDL_GAMEPAD_BUTTON_START,
    left_stick = raw.SDL_GAMEPAD_BUTTON_LEFT_STICK,
    right_stick = raw.SDL_GAMEPAD_BUTTON_RIGHT_STICK,
    left_shoulder = raw.SDL_GAMEPAD_BUTTON_LEFT_SHOULDER,
    right_shoulder = raw.SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER,
    dpad_up = raw.SDL_GAMEPAD_BUTTON_DPAD_UP,
    dpad_down = raw.SDL_GAMEPAD_BUTTON_DPAD_DOWN,
    dpad_left = raw.SDL_GAMEPAD_BUTTON_DPAD_LEFT,
    dpad_right = raw.SDL_GAMEPAD_BUTTON_DPAD_RIGHT,
    misc1 = raw.SDL_GAMEPAD_BUTTON_MISC1,
    right_paddle1 = raw.SDL_GAMEPAD_BUTTON_RIGHT_PADDLE1,
    left_paddle1 = raw.SDL_GAMEPAD_BUTTON_LEFT_PADDLE1,
    right_paddle2 = raw.SDL_GAMEPAD_BUTTON_RIGHT_PADDLE2,
    left_paddle2 = raw.SDL_GAMEPAD_BUTTON_LEFT_PADDLE2,
    touchpad = raw.SDL_GAMEPAD_BUTTON_TOUCHPAD,
    misc2 = raw.SDL_GAMEPAD_BUTTON_MISC2,
    misc3 = raw.SDL_GAMEPAD_BUTTON_MISC3,
    misc4 = raw.SDL_GAMEPAD_BUTTON_MISC4,
    misc5 = raw.SDL_GAMEPAD_BUTTON_MISC5,
    misc6 = raw.SDL_GAMEPAD_BUTTON_MISC6,
    _,

    /// SDL's own string, such as "a" or "dpleft". Owned by SDL.
    pub fn stringName(self: Button) []const u8 {
        const text = raw.SDL_GetGamepadStringForButton(@backingInt(self));
        if (text == null) return "";
        return std.mem.span(text);
    }
};

/// What is printed on a button, for a prompt the player will read.
pub const ButtonLabel = enum(c_uint) {
    unknown = raw.SDL_GAMEPAD_BUTTON_LABEL_UNKNOWN,
    a = raw.SDL_GAMEPAD_BUTTON_LABEL_A,
    b = raw.SDL_GAMEPAD_BUTTON_LABEL_B,
    x = raw.SDL_GAMEPAD_BUTTON_LABEL_X,
    y = raw.SDL_GAMEPAD_BUTTON_LABEL_Y,
    cross = raw.SDL_GAMEPAD_BUTTON_LABEL_CROSS,
    circle = raw.SDL_GAMEPAD_BUTTON_LABEL_CIRCLE,
    square = raw.SDL_GAMEPAD_BUTTON_LABEL_SQUARE,
    triangle = raw.SDL_GAMEPAD_BUTTON_LABEL_TRIANGLE,
    _,
};

pub const Axis = enum(c_int) {
    invalid = raw.SDL_GAMEPAD_AXIS_INVALID,
    left_x = raw.SDL_GAMEPAD_AXIS_LEFTX,
    left_y = raw.SDL_GAMEPAD_AXIS_LEFTY,
    right_x = raw.SDL_GAMEPAD_AXIS_RIGHTX,
    right_y = raw.SDL_GAMEPAD_AXIS_RIGHTY,
    /// Triggers rest at 0 and run to 32767, unlike the sticks.
    left_trigger = raw.SDL_GAMEPAD_AXIS_LEFT_TRIGGER,
    right_trigger = raw.SDL_GAMEPAD_AXIS_RIGHT_TRIGGER,
    _,

    pub fn stringName(self: Axis) []const u8 {
        const text = raw.SDL_GetGamepadStringForAxis(@backingInt(self));
        if (text == null) return "";
        return std.mem.span(text);
    }
};

pub const PowerState = enum(c_int) {
    err = raw.SDL_POWERSTATE_ERROR,
    unknown = raw.SDL_POWERSTATE_UNKNOWN,
    on_battery = raw.SDL_POWERSTATE_ON_BATTERY,
    no_battery = raw.SDL_POWERSTATE_NO_BATTERY,
    charging = raw.SDL_POWERSTATE_CHARGING,
    charged = raw.SDL_POWERSTATE_CHARGED,
    _,
};

pub const Power = struct {
    state: PowerState,
    /// 0..100, or null when the platform will not say.
    percent: ?u8,
};

/// True when at least one gamepad is connected.
pub fn hasGamepad() bool {
    return raw.SDL_HasGamepad();
}

/// The ids of every connected gamepad. The slice is SDL's; free it with
/// `freeIds`.
pub fn connectedIds() Error![]const JoystickId {
    var count: c_int = 0;
    const list = try errors.checkPtr(@as(?[*]JoystickId, raw.SDL_GetGamepads(&count)));
    return list[0..@intCast(count)];
}

pub fn freeIds(list: []const JoystickId) void {
    raw.SDL_free(@ptrCast(@constCast(list.ptr)));
}

/// Whether SDL has a mapping for this device. A joystick with no mapping
/// cannot be opened as a gamepad.
pub fn isGamepad(id: JoystickId) bool {
    return raw.SDL_IsGamepad(id);
}

pub const Gamepad = struct {
    handle: *raw.SDL_Gamepad,

    /// Opening the same id twice returns the same underlying device, and SDL
    /// reference-counts it, so each `init` still needs its own `deinit`.
    pub fn init(device: JoystickId) Error!Gamepad {
        return .{ .handle = try errors.checkPtr(raw.SDL_OpenGamepad(device)) };
    }

    /// The already-open gamepad for an id, without taking a reference.
    pub fn fromId(device: JoystickId) ?Gamepad {
        const handle = raw.SDL_GetGamepadFromID(device) orelse return null;
        return .{ .handle = handle };
    }

    pub fn deinit(self: Gamepad) void {
        raw.SDL_CloseGamepad(self.handle);
    }

    pub fn id(self: Gamepad) JoystickId {
        return raw.SDL_GetGamepadID(self.handle);
    }

    /// Owned by SDL.
    pub fn name(self: Gamepad) []const u8 {
        const text = raw.SDL_GetGamepadName(self.handle);
        if (text == null) return "";
        return std.mem.span(text);
    }

    pub fn kind(self: Gamepad) Type {
        return @fromBackingInt(@intCast(raw.SDL_GetGamepadType(self.handle)));
    }

    /// False once the device has been unplugged.
    pub fn connected(self: Gamepad) bool {
        return raw.SDL_GamepadConnected(self.handle);
    }

    pub fn isDown(self: Gamepad, button: Button) bool {
        return raw.SDL_GetGamepadButton(self.handle, @backingInt(button));
    }

    /// Whether this pad physically has the button at all.
    pub fn hasButton(self: Gamepad, button: Button) bool {
        return raw.SDL_GamepadHasButton(self.handle, @backingInt(button));
    }

    /// Raw, -32768..32767 for a stick and 0..32767 for a trigger. Apply your
    /// own dead zone; SDL applies none.
    pub fn axis(self: Gamepad, which: Axis) i16 {
        return raw.SDL_GetGamepadAxis(self.handle, @backingInt(which));
    }

    /// The same reading normalised to -1..1 (0..1 for a trigger).
    pub fn axisFloat(self: Gamepad, which: Axis) f32 {
        const value = self.axis(which);
        // The negative end reaches one further than the positive one, so
        // dividing by 32767 would let a full-left stick read past -1.
        const scale: f32 = if (value < 0) 32768.0 else 32767.0;
        return @as(f32, @floatFromInt(value)) / scale;
    }

    pub fn hasAxis(self: Gamepad, which: Axis) bool {
        return raw.SDL_GamepadHasAxis(self.handle, @backingInt(which));
    }

    /// What is printed on this button for this pad -- Cross rather than A on
    /// a PlayStation controller.
    pub fn buttonLabel(self: Gamepad, button: Button) ButtonLabel {
        return @fromBackingInt(@intCast(raw.SDL_GetGamepadButtonLabel(self.handle, @backingInt(button))));
    }

    /// Both motors, 0..65535 each, for `duration_ms`. Fails on a pad with no
    /// rumble rather than doing nothing.
    pub fn rumble(
        self: Gamepad,
        low_frequency: u16,
        high_frequency: u16,
        duration_ms: u32,
    ) Error!void {
        try check(raw.SDL_RumbleGamepad(self.handle, low_frequency, high_frequency, duration_ms));
    }

    /// The light bar on a DualShock, the ring on some others.
    pub fn setLed(self: Gamepad, r: u8, g: u8, b: u8) Error!void {
        try check(raw.SDL_SetGamepadLED(self.handle, r, g, b));
    }

    pub fn power(self: Gamepad) Power {
        var percent: c_int = -1;
        const state = raw.SDL_GetGamepadPowerInfo(self.handle, &percent);
        return .{
            .state = @fromBackingInt(@intCast(state)),
            .percent = if (percent < 0) null else @intCast(percent),
        };
    }
};

//! Keys, in SDL's two flavours, plus keyboard state and text input.
//!
//! A `Scancode` is a physical key position: `.w` is the key above `.s`
//! whatever the layout says it types. A `Keycode` is the character that key
//! produces under the current layout. Bind movement to scancodes and
//! shortcuts to keycodes, and neither breaks on an AZERTY keyboard.

const std = @import("std");
const raw = @import("sdl3_raw");
const errors = @import("errors.zig");
const rect_mod = @import("rect.zig");
const video_mod = @import("video.zig");

const Error = errors.Error;
const check = errors.check;
const Window = video_mod.Window;

pub const KeyboardId = u32;

/// Modifier keys held when an event fired. Named bits, where SDL hands over
/// an or-ed integer.
pub const KeyMod = packed struct(u16) {
    left_shift: bool = false,
    right_shift: bool = false,
    _reserved0: u4 = 0,
    left_ctrl: bool = false,
    right_ctrl: bool = false,
    left_alt: bool = false,
    right_alt: bool = false,
    left_gui: bool = false,
    right_gui: bool = false,
    num_lock: bool = false,
    caps_lock: bool = false,
    /// AltGr.
    mode: bool = false,
    scroll_lock: bool = false,

    pub const none: KeyMod = .{};

    /// Either shift key. The same for the three below -- a shortcut almost
    /// never cares which side was pressed.
    pub fn shift(self: KeyMod) bool {
        return self.left_shift or self.right_shift;
    }

    pub fn ctrl(self: KeyMod) bool {
        return self.left_ctrl or self.right_ctrl;
    }

    pub fn alt(self: KeyMod) bool {
        return self.left_alt or self.right_alt;
    }

    /// Command on macOS, Windows key elsewhere.
    pub fn gui(self: KeyMod) bool {
        return self.left_gui or self.right_gui;
    }
};

/// A physical key position, independent of layout.
///
/// Non-exhaustive: a keyboard can report a position SDL has no name for, and
/// `{t}` panics on exactly that value. Use
/// `std.enums.tagName(Scancode, code) orelse "unnamed"` to print one.
pub const Scancode = enum(c_uint) {
    unknown = raw.SDL_SCANCODE_UNKNOWN,
    a = raw.SDL_SCANCODE_A,
    b = raw.SDL_SCANCODE_B,
    c = raw.SDL_SCANCODE_C,
    d = raw.SDL_SCANCODE_D,
    e = raw.SDL_SCANCODE_E,
    f = raw.SDL_SCANCODE_F,
    g = raw.SDL_SCANCODE_G,
    h = raw.SDL_SCANCODE_H,
    i = raw.SDL_SCANCODE_I,
    j = raw.SDL_SCANCODE_J,
    k = raw.SDL_SCANCODE_K,
    l = raw.SDL_SCANCODE_L,
    m = raw.SDL_SCANCODE_M,
    n = raw.SDL_SCANCODE_N,
    o = raw.SDL_SCANCODE_O,
    p = raw.SDL_SCANCODE_P,
    q = raw.SDL_SCANCODE_Q,
    r = raw.SDL_SCANCODE_R,
    s = raw.SDL_SCANCODE_S,
    t = raw.SDL_SCANCODE_T,
    u = raw.SDL_SCANCODE_U,
    v = raw.SDL_SCANCODE_V,
    w = raw.SDL_SCANCODE_W,
    x = raw.SDL_SCANCODE_X,
    y = raw.SDL_SCANCODE_Y,
    z = raw.SDL_SCANCODE_Z,
    n1 = raw.SDL_SCANCODE_1,
    n2 = raw.SDL_SCANCODE_2,
    n3 = raw.SDL_SCANCODE_3,
    n4 = raw.SDL_SCANCODE_4,
    n5 = raw.SDL_SCANCODE_5,
    n6 = raw.SDL_SCANCODE_6,
    n7 = raw.SDL_SCANCODE_7,
    n8 = raw.SDL_SCANCODE_8,
    n9 = raw.SDL_SCANCODE_9,
    n0 = raw.SDL_SCANCODE_0,
    @"return" = raw.SDL_SCANCODE_RETURN,
    escape = raw.SDL_SCANCODE_ESCAPE,
    backspace = raw.SDL_SCANCODE_BACKSPACE,
    tab = raw.SDL_SCANCODE_TAB,
    space = raw.SDL_SCANCODE_SPACE,
    minus = raw.SDL_SCANCODE_MINUS,
    equals = raw.SDL_SCANCODE_EQUALS,
    leftbracket = raw.SDL_SCANCODE_LEFTBRACKET,
    rightbracket = raw.SDL_SCANCODE_RIGHTBRACKET,
    backslash = raw.SDL_SCANCODE_BACKSLASH,
    nonushash = raw.SDL_SCANCODE_NONUSHASH,
    semicolon = raw.SDL_SCANCODE_SEMICOLON,
    apostrophe = raw.SDL_SCANCODE_APOSTROPHE,
    grave = raw.SDL_SCANCODE_GRAVE,
    comma = raw.SDL_SCANCODE_COMMA,
    period = raw.SDL_SCANCODE_PERIOD,
    slash = raw.SDL_SCANCODE_SLASH,
    capslock = raw.SDL_SCANCODE_CAPSLOCK,
    f1 = raw.SDL_SCANCODE_F1,
    f2 = raw.SDL_SCANCODE_F2,
    f3 = raw.SDL_SCANCODE_F3,
    f4 = raw.SDL_SCANCODE_F4,
    f5 = raw.SDL_SCANCODE_F5,
    f6 = raw.SDL_SCANCODE_F6,
    f7 = raw.SDL_SCANCODE_F7,
    f8 = raw.SDL_SCANCODE_F8,
    f9 = raw.SDL_SCANCODE_F9,
    f10 = raw.SDL_SCANCODE_F10,
    f11 = raw.SDL_SCANCODE_F11,
    f12 = raw.SDL_SCANCODE_F12,
    printscreen = raw.SDL_SCANCODE_PRINTSCREEN,
    scrolllock = raw.SDL_SCANCODE_SCROLLLOCK,
    pause = raw.SDL_SCANCODE_PAUSE,
    insert = raw.SDL_SCANCODE_INSERT,
    home = raw.SDL_SCANCODE_HOME,
    pageup = raw.SDL_SCANCODE_PAGEUP,
    delete = raw.SDL_SCANCODE_DELETE,
    end = raw.SDL_SCANCODE_END,
    pagedown = raw.SDL_SCANCODE_PAGEDOWN,
    right = raw.SDL_SCANCODE_RIGHT,
    left = raw.SDL_SCANCODE_LEFT,
    down = raw.SDL_SCANCODE_DOWN,
    up = raw.SDL_SCANCODE_UP,
    numlockclear = raw.SDL_SCANCODE_NUMLOCKCLEAR,
    kp_divide = raw.SDL_SCANCODE_KP_DIVIDE,
    kp_multiply = raw.SDL_SCANCODE_KP_MULTIPLY,
    kp_minus = raw.SDL_SCANCODE_KP_MINUS,
    kp_plus = raw.SDL_SCANCODE_KP_PLUS,
    kp_enter = raw.SDL_SCANCODE_KP_ENTER,
    kp_1 = raw.SDL_SCANCODE_KP_1,
    kp_2 = raw.SDL_SCANCODE_KP_2,
    kp_3 = raw.SDL_SCANCODE_KP_3,
    kp_4 = raw.SDL_SCANCODE_KP_4,
    kp_5 = raw.SDL_SCANCODE_KP_5,
    kp_6 = raw.SDL_SCANCODE_KP_6,
    kp_7 = raw.SDL_SCANCODE_KP_7,
    kp_8 = raw.SDL_SCANCODE_KP_8,
    kp_9 = raw.SDL_SCANCODE_KP_9,
    kp_0 = raw.SDL_SCANCODE_KP_0,
    kp_period = raw.SDL_SCANCODE_KP_PERIOD,
    nonusbackslash = raw.SDL_SCANCODE_NONUSBACKSLASH,
    application = raw.SDL_SCANCODE_APPLICATION,
    power = raw.SDL_SCANCODE_POWER,
    kp_equals = raw.SDL_SCANCODE_KP_EQUALS,
    f13 = raw.SDL_SCANCODE_F13,
    f14 = raw.SDL_SCANCODE_F14,
    f15 = raw.SDL_SCANCODE_F15,
    f16 = raw.SDL_SCANCODE_F16,
    f17 = raw.SDL_SCANCODE_F17,
    f18 = raw.SDL_SCANCODE_F18,
    f19 = raw.SDL_SCANCODE_F19,
    f20 = raw.SDL_SCANCODE_F20,
    f21 = raw.SDL_SCANCODE_F21,
    f22 = raw.SDL_SCANCODE_F22,
    f23 = raw.SDL_SCANCODE_F23,
    f24 = raw.SDL_SCANCODE_F24,
    execute = raw.SDL_SCANCODE_EXECUTE,
    help = raw.SDL_SCANCODE_HELP,
    menu = raw.SDL_SCANCODE_MENU,
    select = raw.SDL_SCANCODE_SELECT,
    stop = raw.SDL_SCANCODE_STOP,
    again = raw.SDL_SCANCODE_AGAIN,
    undo = raw.SDL_SCANCODE_UNDO,
    cut = raw.SDL_SCANCODE_CUT,
    copy = raw.SDL_SCANCODE_COPY,
    paste = raw.SDL_SCANCODE_PASTE,
    find = raw.SDL_SCANCODE_FIND,
    mute = raw.SDL_SCANCODE_MUTE,
    volumeup = raw.SDL_SCANCODE_VOLUMEUP,
    volumedown = raw.SDL_SCANCODE_VOLUMEDOWN,
    kp_comma = raw.SDL_SCANCODE_KP_COMMA,
    kp_equalsas400 = raw.SDL_SCANCODE_KP_EQUALSAS400,
    international1 = raw.SDL_SCANCODE_INTERNATIONAL1,
    international2 = raw.SDL_SCANCODE_INTERNATIONAL2,
    international3 = raw.SDL_SCANCODE_INTERNATIONAL3,
    international4 = raw.SDL_SCANCODE_INTERNATIONAL4,
    international5 = raw.SDL_SCANCODE_INTERNATIONAL5,
    international6 = raw.SDL_SCANCODE_INTERNATIONAL6,
    international7 = raw.SDL_SCANCODE_INTERNATIONAL7,
    international8 = raw.SDL_SCANCODE_INTERNATIONAL8,
    international9 = raw.SDL_SCANCODE_INTERNATIONAL9,
    lang1 = raw.SDL_SCANCODE_LANG1,
    lang2 = raw.SDL_SCANCODE_LANG2,
    lang3 = raw.SDL_SCANCODE_LANG3,
    lang4 = raw.SDL_SCANCODE_LANG4,
    lang5 = raw.SDL_SCANCODE_LANG5,
    lang6 = raw.SDL_SCANCODE_LANG6,
    lang7 = raw.SDL_SCANCODE_LANG7,
    lang8 = raw.SDL_SCANCODE_LANG8,
    lang9 = raw.SDL_SCANCODE_LANG9,
    alterase = raw.SDL_SCANCODE_ALTERASE,
    sysreq = raw.SDL_SCANCODE_SYSREQ,
    cancel = raw.SDL_SCANCODE_CANCEL,
    clear = raw.SDL_SCANCODE_CLEAR,
    prior = raw.SDL_SCANCODE_PRIOR,
    return2 = raw.SDL_SCANCODE_RETURN2,
    separator = raw.SDL_SCANCODE_SEPARATOR,
    out = raw.SDL_SCANCODE_OUT,
    oper = raw.SDL_SCANCODE_OPER,
    clearagain = raw.SDL_SCANCODE_CLEARAGAIN,
    crsel = raw.SDL_SCANCODE_CRSEL,
    exsel = raw.SDL_SCANCODE_EXSEL,
    kp_00 = raw.SDL_SCANCODE_KP_00,
    kp_000 = raw.SDL_SCANCODE_KP_000,
    thousandsseparator = raw.SDL_SCANCODE_THOUSANDSSEPARATOR,
    decimalseparator = raw.SDL_SCANCODE_DECIMALSEPARATOR,
    currencyunit = raw.SDL_SCANCODE_CURRENCYUNIT,
    currencysubunit = raw.SDL_SCANCODE_CURRENCYSUBUNIT,
    kp_leftparen = raw.SDL_SCANCODE_KP_LEFTPAREN,
    kp_rightparen = raw.SDL_SCANCODE_KP_RIGHTPAREN,
    kp_leftbrace = raw.SDL_SCANCODE_KP_LEFTBRACE,
    kp_rightbrace = raw.SDL_SCANCODE_KP_RIGHTBRACE,
    kp_tab = raw.SDL_SCANCODE_KP_TAB,
    kp_backspace = raw.SDL_SCANCODE_KP_BACKSPACE,
    kp_a = raw.SDL_SCANCODE_KP_A,
    kp_b = raw.SDL_SCANCODE_KP_B,
    kp_c = raw.SDL_SCANCODE_KP_C,
    kp_d = raw.SDL_SCANCODE_KP_D,
    kp_e = raw.SDL_SCANCODE_KP_E,
    kp_f = raw.SDL_SCANCODE_KP_F,
    kp_xor = raw.SDL_SCANCODE_KP_XOR,
    kp_power = raw.SDL_SCANCODE_KP_POWER,
    kp_percent = raw.SDL_SCANCODE_KP_PERCENT,
    kp_less = raw.SDL_SCANCODE_KP_LESS,
    kp_greater = raw.SDL_SCANCODE_KP_GREATER,
    kp_ampersand = raw.SDL_SCANCODE_KP_AMPERSAND,
    kp_dblampersand = raw.SDL_SCANCODE_KP_DBLAMPERSAND,
    kp_verticalbar = raw.SDL_SCANCODE_KP_VERTICALBAR,
    kp_dblverticalbar = raw.SDL_SCANCODE_KP_DBLVERTICALBAR,
    kp_colon = raw.SDL_SCANCODE_KP_COLON,
    kp_hash = raw.SDL_SCANCODE_KP_HASH,
    kp_space = raw.SDL_SCANCODE_KP_SPACE,
    kp_at = raw.SDL_SCANCODE_KP_AT,
    kp_exclam = raw.SDL_SCANCODE_KP_EXCLAM,
    kp_memstore = raw.SDL_SCANCODE_KP_MEMSTORE,
    kp_memrecall = raw.SDL_SCANCODE_KP_MEMRECALL,
    kp_memclear = raw.SDL_SCANCODE_KP_MEMCLEAR,
    kp_memadd = raw.SDL_SCANCODE_KP_MEMADD,
    kp_memsubtract = raw.SDL_SCANCODE_KP_MEMSUBTRACT,
    kp_memmultiply = raw.SDL_SCANCODE_KP_MEMMULTIPLY,
    kp_memdivide = raw.SDL_SCANCODE_KP_MEMDIVIDE,
    kp_plusminus = raw.SDL_SCANCODE_KP_PLUSMINUS,
    kp_clear = raw.SDL_SCANCODE_KP_CLEAR,
    kp_clearentry = raw.SDL_SCANCODE_KP_CLEARENTRY,
    kp_binary = raw.SDL_SCANCODE_KP_BINARY,
    kp_octal = raw.SDL_SCANCODE_KP_OCTAL,
    kp_decimal = raw.SDL_SCANCODE_KP_DECIMAL,
    kp_hexadecimal = raw.SDL_SCANCODE_KP_HEXADECIMAL,
    lctrl = raw.SDL_SCANCODE_LCTRL,
    lshift = raw.SDL_SCANCODE_LSHIFT,
    lalt = raw.SDL_SCANCODE_LALT,
    lgui = raw.SDL_SCANCODE_LGUI,
    rctrl = raw.SDL_SCANCODE_RCTRL,
    rshift = raw.SDL_SCANCODE_RSHIFT,
    ralt = raw.SDL_SCANCODE_RALT,
    rgui = raw.SDL_SCANCODE_RGUI,
    mode = raw.SDL_SCANCODE_MODE,
    sleep = raw.SDL_SCANCODE_SLEEP,
    wake = raw.SDL_SCANCODE_WAKE,
    channel_increment = raw.SDL_SCANCODE_CHANNEL_INCREMENT,
    channel_decrement = raw.SDL_SCANCODE_CHANNEL_DECREMENT,
    media_play = raw.SDL_SCANCODE_MEDIA_PLAY,
    media_pause = raw.SDL_SCANCODE_MEDIA_PAUSE,
    media_record = raw.SDL_SCANCODE_MEDIA_RECORD,
    media_fast_forward = raw.SDL_SCANCODE_MEDIA_FAST_FORWARD,
    media_rewind = raw.SDL_SCANCODE_MEDIA_REWIND,
    media_next_track = raw.SDL_SCANCODE_MEDIA_NEXT_TRACK,
    media_previous_track = raw.SDL_SCANCODE_MEDIA_PREVIOUS_TRACK,
    media_stop = raw.SDL_SCANCODE_MEDIA_STOP,
    media_eject = raw.SDL_SCANCODE_MEDIA_EJECT,
    media_play_pause = raw.SDL_SCANCODE_MEDIA_PLAY_PAUSE,
    media_select = raw.SDL_SCANCODE_MEDIA_SELECT,
    ac_new = raw.SDL_SCANCODE_AC_NEW,
    ac_open = raw.SDL_SCANCODE_AC_OPEN,
    ac_close = raw.SDL_SCANCODE_AC_CLOSE,
    ac_exit = raw.SDL_SCANCODE_AC_EXIT,
    ac_save = raw.SDL_SCANCODE_AC_SAVE,
    ac_print = raw.SDL_SCANCODE_AC_PRINT,
    ac_properties = raw.SDL_SCANCODE_AC_PROPERTIES,
    ac_search = raw.SDL_SCANCODE_AC_SEARCH,
    ac_home = raw.SDL_SCANCODE_AC_HOME,
    ac_back = raw.SDL_SCANCODE_AC_BACK,
    ac_forward = raw.SDL_SCANCODE_AC_FORWARD,
    ac_stop = raw.SDL_SCANCODE_AC_STOP,
    ac_refresh = raw.SDL_SCANCODE_AC_REFRESH,
    ac_bookmarks = raw.SDL_SCANCODE_AC_BOOKMARKS,
    softleft = raw.SDL_SCANCODE_SOFTLEFT,
    softright = raw.SDL_SCANCODE_SOFTRIGHT,
    call = raw.SDL_SCANCODE_CALL,
    endcall = raw.SDL_SCANCODE_ENDCALL,
    reserved = raw.SDL_SCANCODE_RESERVED,
    _,

    /// SDL's name for the position, such as "Left Shift". Owned by SDL.
    pub fn name(self: Scancode) []const u8 {
        const text = raw.SDL_GetScancodeName(@backingInt(self));
        if (text == null) return "";
        return std.mem.span(text);
    }

    pub fn fromName(text: [:0]const u8) Scancode {
        return @fromBackingInt(@intCast(raw.SDL_GetScancodeFromName(text.ptr)));
    }

    /// What this key types under the current layout and the given modifiers.
    pub fn toKeycode(self: Scancode, mods: KeyMod) Keycode {
        return @fromBackingInt(@intCast(raw.SDL_GetKeyFromScancode(
            @backingInt(self),
            @bitCast(mods),
            false,
        )));
    }
};

/// The character a key produces under the current layout.
///
/// Values below 0x110000 are Unicode code points, so a printable key's
/// keycode *is* the character it types. Non-exhaustive for the same reason
/// `Scancode` is.
pub const Keycode = enum(u32) {
    unknown = raw.SDLK_UNKNOWN,
    @"return" = raw.SDLK_RETURN,
    escape = raw.SDLK_ESCAPE,
    backspace = raw.SDLK_BACKSPACE,
    tab = raw.SDLK_TAB,
    space = raw.SDLK_SPACE,
    exclaim = raw.SDLK_EXCLAIM,
    dblapostrophe = raw.SDLK_DBLAPOSTROPHE,
    hash = raw.SDLK_HASH,
    dollar = raw.SDLK_DOLLAR,
    percent = raw.SDLK_PERCENT,
    ampersand = raw.SDLK_AMPERSAND,
    apostrophe = raw.SDLK_APOSTROPHE,
    leftparen = raw.SDLK_LEFTPAREN,
    rightparen = raw.SDLK_RIGHTPAREN,
    asterisk = raw.SDLK_ASTERISK,
    plus = raw.SDLK_PLUS,
    comma = raw.SDLK_COMMA,
    minus = raw.SDLK_MINUS,
    period = raw.SDLK_PERIOD,
    slash = raw.SDLK_SLASH,
    n0 = raw.SDLK_0,
    n1 = raw.SDLK_1,
    n2 = raw.SDLK_2,
    n3 = raw.SDLK_3,
    n4 = raw.SDLK_4,
    n5 = raw.SDLK_5,
    n6 = raw.SDLK_6,
    n7 = raw.SDLK_7,
    n8 = raw.SDLK_8,
    n9 = raw.SDLK_9,
    colon = raw.SDLK_COLON,
    semicolon = raw.SDLK_SEMICOLON,
    less = raw.SDLK_LESS,
    equals = raw.SDLK_EQUALS,
    greater = raw.SDLK_GREATER,
    question = raw.SDLK_QUESTION,
    at = raw.SDLK_AT,
    leftbracket = raw.SDLK_LEFTBRACKET,
    backslash = raw.SDLK_BACKSLASH,
    rightbracket = raw.SDLK_RIGHTBRACKET,
    caret = raw.SDLK_CARET,
    underscore = raw.SDLK_UNDERSCORE,
    grave = raw.SDLK_GRAVE,
    a = raw.SDLK_A,
    b = raw.SDLK_B,
    c = raw.SDLK_C,
    d = raw.SDLK_D,
    e = raw.SDLK_E,
    f = raw.SDLK_F,
    g = raw.SDLK_G,
    h = raw.SDLK_H,
    i = raw.SDLK_I,
    j = raw.SDLK_J,
    k = raw.SDLK_K,
    l = raw.SDLK_L,
    m = raw.SDLK_M,
    n = raw.SDLK_N,
    o = raw.SDLK_O,
    p = raw.SDLK_P,
    q = raw.SDLK_Q,
    r = raw.SDLK_R,
    s = raw.SDLK_S,
    t = raw.SDLK_T,
    u = raw.SDLK_U,
    v = raw.SDLK_V,
    w = raw.SDLK_W,
    x = raw.SDLK_X,
    y = raw.SDLK_Y,
    z = raw.SDLK_Z,
    leftbrace = raw.SDLK_LEFTBRACE,
    pipe = raw.SDLK_PIPE,
    rightbrace = raw.SDLK_RIGHTBRACE,
    tilde = raw.SDLK_TILDE,
    delete = raw.SDLK_DELETE,
    plusminus = raw.SDLK_PLUSMINUS,
    capslock = raw.SDLK_CAPSLOCK,
    f1 = raw.SDLK_F1,
    f2 = raw.SDLK_F2,
    f3 = raw.SDLK_F3,
    f4 = raw.SDLK_F4,
    f5 = raw.SDLK_F5,
    f6 = raw.SDLK_F6,
    f7 = raw.SDLK_F7,
    f8 = raw.SDLK_F8,
    f9 = raw.SDLK_F9,
    f10 = raw.SDLK_F10,
    f11 = raw.SDLK_F11,
    f12 = raw.SDLK_F12,
    printscreen = raw.SDLK_PRINTSCREEN,
    scrolllock = raw.SDLK_SCROLLLOCK,
    pause = raw.SDLK_PAUSE,
    insert = raw.SDLK_INSERT,
    home = raw.SDLK_HOME,
    pageup = raw.SDLK_PAGEUP,
    end = raw.SDLK_END,
    pagedown = raw.SDLK_PAGEDOWN,
    right = raw.SDLK_RIGHT,
    left = raw.SDLK_LEFT,
    down = raw.SDLK_DOWN,
    up = raw.SDLK_UP,
    numlockclear = raw.SDLK_NUMLOCKCLEAR,
    kp_divide = raw.SDLK_KP_DIVIDE,
    kp_multiply = raw.SDLK_KP_MULTIPLY,
    kp_minus = raw.SDLK_KP_MINUS,
    kp_plus = raw.SDLK_KP_PLUS,
    kp_enter = raw.SDLK_KP_ENTER,
    kp_1 = raw.SDLK_KP_1,
    kp_2 = raw.SDLK_KP_2,
    kp_3 = raw.SDLK_KP_3,
    kp_4 = raw.SDLK_KP_4,
    kp_5 = raw.SDLK_KP_5,
    kp_6 = raw.SDLK_KP_6,
    kp_7 = raw.SDLK_KP_7,
    kp_8 = raw.SDLK_KP_8,
    kp_9 = raw.SDLK_KP_9,
    kp_0 = raw.SDLK_KP_0,
    kp_period = raw.SDLK_KP_PERIOD,
    application = raw.SDLK_APPLICATION,
    power = raw.SDLK_POWER,
    kp_equals = raw.SDLK_KP_EQUALS,
    f13 = raw.SDLK_F13,
    f14 = raw.SDLK_F14,
    f15 = raw.SDLK_F15,
    f16 = raw.SDLK_F16,
    f17 = raw.SDLK_F17,
    f18 = raw.SDLK_F18,
    f19 = raw.SDLK_F19,
    f20 = raw.SDLK_F20,
    f21 = raw.SDLK_F21,
    f22 = raw.SDLK_F22,
    f23 = raw.SDLK_F23,
    f24 = raw.SDLK_F24,
    execute = raw.SDLK_EXECUTE,
    help = raw.SDLK_HELP,
    menu = raw.SDLK_MENU,
    select = raw.SDLK_SELECT,
    stop = raw.SDLK_STOP,
    again = raw.SDLK_AGAIN,
    undo = raw.SDLK_UNDO,
    cut = raw.SDLK_CUT,
    copy = raw.SDLK_COPY,
    paste = raw.SDLK_PASTE,
    find = raw.SDLK_FIND,
    mute = raw.SDLK_MUTE,
    volumeup = raw.SDLK_VOLUMEUP,
    volumedown = raw.SDLK_VOLUMEDOWN,
    kp_comma = raw.SDLK_KP_COMMA,
    kp_equalsas400 = raw.SDLK_KP_EQUALSAS400,
    alterase = raw.SDLK_ALTERASE,
    sysreq = raw.SDLK_SYSREQ,
    cancel = raw.SDLK_CANCEL,
    clear = raw.SDLK_CLEAR,
    prior = raw.SDLK_PRIOR,
    return2 = raw.SDLK_RETURN2,
    separator = raw.SDLK_SEPARATOR,
    out = raw.SDLK_OUT,
    oper = raw.SDLK_OPER,
    clearagain = raw.SDLK_CLEARAGAIN,
    crsel = raw.SDLK_CRSEL,
    exsel = raw.SDLK_EXSEL,
    kp_00 = raw.SDLK_KP_00,
    kp_000 = raw.SDLK_KP_000,
    thousandsseparator = raw.SDLK_THOUSANDSSEPARATOR,
    decimalseparator = raw.SDLK_DECIMALSEPARATOR,
    currencyunit = raw.SDLK_CURRENCYUNIT,
    currencysubunit = raw.SDLK_CURRENCYSUBUNIT,
    kp_leftparen = raw.SDLK_KP_LEFTPAREN,
    kp_rightparen = raw.SDLK_KP_RIGHTPAREN,
    kp_leftbrace = raw.SDLK_KP_LEFTBRACE,
    kp_rightbrace = raw.SDLK_KP_RIGHTBRACE,
    kp_tab = raw.SDLK_KP_TAB,
    kp_backspace = raw.SDLK_KP_BACKSPACE,
    kp_a = raw.SDLK_KP_A,
    kp_b = raw.SDLK_KP_B,
    kp_c = raw.SDLK_KP_C,
    kp_d = raw.SDLK_KP_D,
    kp_e = raw.SDLK_KP_E,
    kp_f = raw.SDLK_KP_F,
    kp_xor = raw.SDLK_KP_XOR,
    kp_power = raw.SDLK_KP_POWER,
    kp_percent = raw.SDLK_KP_PERCENT,
    kp_less = raw.SDLK_KP_LESS,
    kp_greater = raw.SDLK_KP_GREATER,
    kp_ampersand = raw.SDLK_KP_AMPERSAND,
    kp_dblampersand = raw.SDLK_KP_DBLAMPERSAND,
    kp_verticalbar = raw.SDLK_KP_VERTICALBAR,
    kp_dblverticalbar = raw.SDLK_KP_DBLVERTICALBAR,
    kp_colon = raw.SDLK_KP_COLON,
    kp_hash = raw.SDLK_KP_HASH,
    kp_space = raw.SDLK_KP_SPACE,
    kp_at = raw.SDLK_KP_AT,
    kp_exclam = raw.SDLK_KP_EXCLAM,
    kp_memstore = raw.SDLK_KP_MEMSTORE,
    kp_memrecall = raw.SDLK_KP_MEMRECALL,
    kp_memclear = raw.SDLK_KP_MEMCLEAR,
    kp_memadd = raw.SDLK_KP_MEMADD,
    kp_memsubtract = raw.SDLK_KP_MEMSUBTRACT,
    kp_memmultiply = raw.SDLK_KP_MEMMULTIPLY,
    kp_memdivide = raw.SDLK_KP_MEMDIVIDE,
    kp_plusminus = raw.SDLK_KP_PLUSMINUS,
    kp_clear = raw.SDLK_KP_CLEAR,
    kp_clearentry = raw.SDLK_KP_CLEARENTRY,
    kp_binary = raw.SDLK_KP_BINARY,
    kp_octal = raw.SDLK_KP_OCTAL,
    kp_decimal = raw.SDLK_KP_DECIMAL,
    kp_hexadecimal = raw.SDLK_KP_HEXADECIMAL,
    lctrl = raw.SDLK_LCTRL,
    lshift = raw.SDLK_LSHIFT,
    lalt = raw.SDLK_LALT,
    lgui = raw.SDLK_LGUI,
    rctrl = raw.SDLK_RCTRL,
    rshift = raw.SDLK_RSHIFT,
    ralt = raw.SDLK_RALT,
    rgui = raw.SDLK_RGUI,
    mode = raw.SDLK_MODE,
    sleep = raw.SDLK_SLEEP,
    wake = raw.SDLK_WAKE,
    channel_increment = raw.SDLK_CHANNEL_INCREMENT,
    channel_decrement = raw.SDLK_CHANNEL_DECREMENT,
    media_play = raw.SDLK_MEDIA_PLAY,
    media_pause = raw.SDLK_MEDIA_PAUSE,
    media_record = raw.SDLK_MEDIA_RECORD,
    media_fast_forward = raw.SDLK_MEDIA_FAST_FORWARD,
    media_rewind = raw.SDLK_MEDIA_REWIND,
    media_next_track = raw.SDLK_MEDIA_NEXT_TRACK,
    media_previous_track = raw.SDLK_MEDIA_PREVIOUS_TRACK,
    media_stop = raw.SDLK_MEDIA_STOP,
    media_eject = raw.SDLK_MEDIA_EJECT,
    media_play_pause = raw.SDLK_MEDIA_PLAY_PAUSE,
    media_select = raw.SDLK_MEDIA_SELECT,
    ac_new = raw.SDLK_AC_NEW,
    ac_open = raw.SDLK_AC_OPEN,
    ac_close = raw.SDLK_AC_CLOSE,
    ac_exit = raw.SDLK_AC_EXIT,
    ac_save = raw.SDLK_AC_SAVE,
    ac_print = raw.SDLK_AC_PRINT,
    ac_properties = raw.SDLK_AC_PROPERTIES,
    ac_search = raw.SDLK_AC_SEARCH,
    ac_home = raw.SDLK_AC_HOME,
    ac_back = raw.SDLK_AC_BACK,
    ac_forward = raw.SDLK_AC_FORWARD,
    ac_stop = raw.SDLK_AC_STOP,
    ac_refresh = raw.SDLK_AC_REFRESH,
    ac_bookmarks = raw.SDLK_AC_BOOKMARKS,
    softleft = raw.SDLK_SOFTLEFT,
    softright = raw.SDLK_SOFTRIGHT,
    call = raw.SDLK_CALL,
    endcall = raw.SDLK_ENDCALL,
    left_tab = raw.SDLK_LEFT_TAB,
    level5_shift = raw.SDLK_LEVEL5_SHIFT,
    multi_key_compose = raw.SDLK_MULTI_KEY_COMPOSE,
    lmeta = raw.SDLK_LMETA,
    rmeta = raw.SDLK_RMETA,
    lhyper = raw.SDLK_LHYPER,
    rhyper = raw.SDLK_RHYPER,
    _,

    /// Owned by SDL.
    pub fn name(self: Keycode) []const u8 {
        const text = raw.SDL_GetKeyName(@backingInt(self));
        if (text == null) return "";
        return std.mem.span(text);
    }

    pub fn fromName(text: [:0]const u8) Keycode {
        return @fromBackingInt(@intCast(raw.SDL_GetKeyFromName(text.ptr)));
    }

    /// The physical key that types this character under the current layout.
    pub fn toScancode(self: Keycode) Scancode {
        return @fromBackingInt(@intCast(raw.SDL_GetScancodeFromKey(@backingInt(self), null)));
    }

    /// The Unicode code point this key types, when it types one.
    pub fn codepoint(self: Keycode) ?u21 {
        const value = @backingInt(self);
        if (value == 0 or value > 0x10FFFF) return null;
        return @intCast(value);
    }
};

// ---------------------------------------------------------------------
// State
// ---------------------------------------------------------------------

/// A snapshot of which keys are down, indexed by scancode. Owned by SDL and
/// updated in place by `events.pump`, so it is fetched once and read every
/// frame -- but only *after* pumping, or it never changes.
pub const State = struct {
    keys: []const bool,

    pub fn isDown(self: State, code: Scancode) bool {
        const index = @backingInt(code);
        if (index >= self.keys.len) return false;
        return self.keys[index];
    }
};

pub fn state() State {
    var count: c_int = 0;
    const keys = raw.SDL_GetKeyboardState(&count);
    if (keys == null or count <= 0) return .{ .keys = &.{} };
    return .{ .keys = keys[0..@intCast(count)] };
}

/// The modifiers held right now, which is not the same as the ones an event
/// carried: this is current, that was historical.
pub fn modState() KeyMod {
    return @bitCast(raw.SDL_GetModState());
}

pub fn setModState(mods: KeyMod) void {
    raw.SDL_SetModState(@bitCast(mods));
}

pub fn hasKeyboard() bool {
    return raw.SDL_HasKeyboard();
}

/// The window keyboard input is going to, or null when the application is not
/// focused.
pub fn focusedWindow() ?Window {
    const handle = raw.SDL_GetKeyboardFocus() orelse return null;
    return .{ .handle = handle };
}

// ---------------------------------------------------------------------
// Text input
// ---------------------------------------------------------------------

/// Turns on the platform's text input: dead keys compose, an IME opens where
/// there is one, and a phone raises its on-screen keyboard. Until this is on,
/// `text_input` events do not arrive at all.
pub fn startTextInput(window: Window) Error!void {
    try check(raw.SDL_StartTextInput(window.handle));
}

pub fn stopTextInput(window: Window) Error!void {
    try check(raw.SDL_StopTextInput(window.handle));
}

pub fn textInputActive(window: Window) bool {
    return raw.SDL_TextInputActive(window.handle);
}

/// Where the text is being typed, so the IME candidate window does not cover
/// it. `cursor` is the caret's offset from the left of `area`.
pub fn setTextInputArea(window: Window, area: rect_mod.Rect, cursor: i32) Error!void {
    try check(raw.SDL_SetTextInputArea(window.handle, @ptrCast(&area), cursor));
}

/// Throws away a half-composed IME sequence.
pub fn clearComposition(window: Window) Error!void {
    try check(raw.SDL_ClearComposition(window.handle));
}

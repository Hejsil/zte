pub const escape = "\x1b[";

pub const Erase = enum {};

pub const erase = struct {
    pub const active_to_end = "0";
    pub const start_to_active = "1";
    pub const all = "2";

    pub fn inDisplay(comptime p: []const u8) []const u8 {
        return escape ++ p ++ "J";
    }

    pub fn inLine(comptime p: []const u8) []const u8 {
        return escape ++ p ++ "K";
    }
};

pub const cursor = struct {
    pub const hide = escape ++ "?25l";
    pub const show = escape ++ "?25h";

    pub fn position(comptime p: []const u8) []const u8 {
        return escape ++ p ++ "H";
    }

    pub fn forward(comptime p: []const u8) []const u8 {
        return escape ++ p ++ "C";
    }

    pub fn down(comptime p: []const u8) []const u8 {
        return escape ++ p ++ "B";
    }
};

pub const device = struct {
    pub const response = struct {
        pub const ready = "0";
        pub const malfunction = "3";
    };

    pub const request = struct {
        pub const status = "5";
        pub const active_position = "6";
    };

    pub fn statusReport(comptime p: []const u8) []const u8 {
        return escape ++ p ++ "n";
    }
};

pub fn selectGraphicRendition(comptime p: []const u8) []const u8 {
    return escape ++ p ++ "m";
}

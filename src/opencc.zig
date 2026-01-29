/// OpenCC (Open Chinese Convert) wrapper for Zig.
/// Provides Chinese text conversion between Traditional and Simplified Chinese variants.
pub const OpenCC = opaque {
    /// Errors that can occur during OpenCC operations.
    pub const Error = error{
        /// Failed to initialize OpenCC instance (e.g., config file not found).
        InitFailed,
        /// Failed to convert text (e.g., invalid UTF-8 input).
        ConvertFailed,
    };

    /// Initialize a new OpenCC instance with the specified configuration.
    ///
    /// Parameters:
    ///   - config_path: Optional path to a configuration file (e.g., "s2t.json", "s2twp.json").
    ///             If null, uses the default configuration (s2t.json).
    ///
    /// Returns: Pointer to the initialized OpenCC instance.
    ///
    /// Errors: Returns InitFailed if the configuration file is not found or cannot be loaded.
    pub fn init(config_path: ?[:0]const u8) Error!*OpenCC {
        const opencc = c.opencc_open(if (config_path) |cfg| cfg.ptr else null);
        if (opencc == null or @intFromPtr(opencc) == std.math.maxInt(usize)) return Error.InitFailed;
        return @ptrCast(opencc);
    }

    /// Clean up and free resources associated with the OpenCC instance.
    /// Should be called when the instance is no longer needed.
    pub fn deinit(self: *OpenCC) void {
        _ = c.opencc_close(self.cval());
    }

    /// Convert a UTF-8 string using the configured conversion rules.
    ///
    /// Parameters:
    ///   - str: Input string to convert (must be valid UTF-8).
    ///
    /// Returns: The converted string. Must be freed with `free()` after use.
    ///
    /// Errors: Returns ConvertFailed if the input is not valid UTF-8.
    pub fn convert(self: *OpenCC, str: []const u8) Error![:0]const u8 {
        const result = c.opencc_convert_utf8(self.cval(), str.ptr, str.len);
        return if (result == null) Error.ConvertFailed else std.mem.span(result);
    }

    /// Free a string returned by `convert()`.
    ///
    /// Parameters:
    ///   - str: The string to free (must be a string previously returned by `convert()`).
    pub fn free(self: *OpenCC, str: [:0]const u8) void {
        _ = self;
        c.opencc_convert_utf8_free(@ptrCast(@constCast(str.ptr)));
    }

    /// Get the last error message from OpenCC.
    ///
    /// Returns: A string describing the last error that occurred.
    pub fn err() [:0]const u8 {
        const err_str = c.opencc_error();
        return std.mem.span(err_str);
    }

    inline fn cval(self: *OpenCC) c.opencc_t {
        return @ptrCast(self);
    }
};

test "opencc" {
    const opencc: *OpenCC = try .init(null);
    defer opencc.deinit();

    const input = "网络鼠标键盘";
    const output = try opencc.convert(input);
    defer opencc.free(output);

    try std.testing.expectEqualStrings("網絡鼠標鍵盤", output);
}

test "opencc use dict" {
    const opencc: *OpenCC = try .init("s2twp.json");
    defer opencc.deinit();

    const input = "网络鼠标键盘";
    const output = try opencc.convert(input);
    defer opencc.free(output);

    try std.testing.expectEqualStrings("網路滑鼠鍵盤", output);
}

test "opencc init failed" {
    try std.testing.expectEqualStrings("", OpenCC.err());
    try std.testing.expectError(OpenCC.Error.InitFailed, OpenCC.init("abc"));
    try std.testing.expectEqualStrings("abc not found or not accessible.", OpenCC.err());
}

test "opencc convert failed" {
    const opencc: *OpenCC = try .init(null);
    defer opencc.deinit();

    const input = [_]u8{ 0xFF, 0xFE, 0xFD };
    try std.testing.expectError(OpenCC.Error.ConvertFailed, opencc.convert(&input));
    try std.testing.expectStringStartsWith(OpenCC.err(), "Invalid UTF8:");
}

const std = @import("std");
const c = @import("c");

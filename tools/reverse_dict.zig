pub const main = if (builtin.zig_version.major == 0 and builtin.zig_version.minor < 16)
    @import("reverse_dict/v0_15.zig").main
else
    @import("reverse_dict/v0_16.zig").main;

const builtin = @import("builtin");

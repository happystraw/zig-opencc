pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 3) {
        std.debug.print("Usage: {s} [input] [output]\n", .{args[0]});
        std.debug.print("Reverse key and value of all pairs\n", .{});
        return error.InvalidArguments;
    }

    const input_path = args[1];
    const output_path = args[2];

    try reverseItems(allocator, input_path, output_path);
}

fn reverseItems(allocator: std.mem.Allocator, input_path: []const u8, output_path: []const u8) !void {
    // Read input file (supports absolute and relative paths)
    const input_file = if (std.fs.path.isAbsolute(input_path))
        try std.fs.openFileAbsolute(input_path, .{})
    else
        try std.fs.cwd().openFile(input_path, .{});
    defer input_file.close();

    const input_content = try input_file.readToEndAlloc(allocator, 10 * 1024 * 1024); // max 10MB
    defer allocator.free(input_content);

    // Use HashMap to store reversed mapping: value -> []key
    var dict: std.StringHashMap(StringList) = .init(allocator);
    defer {
        var it = dict.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.items) |item| allocator.free(item);
            entry.value_ptr.deinit(allocator);
        }
        dict.deinit();
    }

    // Parse input file
    var lines = std.mem.splitScalar(u8, input_content, '\n');
    while (lines.next()) |line| {
        const line_stripped = std.mem.trim(u8, line, " \t\r\n");

        // Skip empty lines and comment lines
        if (line_stripped.len == 0 or line_stripped[0] == '#') {
            continue;
        }

        // Split key and value (using tab)
        var parts = std.mem.splitScalar(u8, line_stripped, '\t');
        const key = parts.next() orelse continue;
        const value_part = parts.next() orelse continue;

        if (key.len == 0) continue;

        // value may be multiple space-separated values
        var values = std.mem.splitScalar(u8, value_part, ' ');
        while (values.next()) |value| {
            const value_trimmed = std.mem.trim(u8, value, " \t\r\n");
            if (value_trimmed.len == 0) continue;

            // Create or update mapping for each value
            const result = try dict.getOrPut(value_trimmed);
            if (!result.found_existing) {
                result.key_ptr.* = try allocator.dupe(u8, value_trimmed);
                result.value_ptr.* = .empty;
            }

            try result.value_ptr.append(allocator, try allocator.dupe(u8, key));
        }
    }

    // Sort keys
    var sorted_keys: StringList = .empty;
    defer sorted_keys.deinit(allocator);

    var it = dict.keyIterator();
    while (it.next()) |key| {
        try sorted_keys.append(allocator, key.*);
    }

    std.mem.sort([]const u8, sorted_keys.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);

    // Write output file
    var output_buffer: std.ArrayList(u8) = .empty;
    defer output_buffer.deinit(allocator);

    for (sorted_keys.items) |key| {
        const values_list = dict.get(key).?;

        try output_buffer.appendSlice(allocator, key);
        try output_buffer.append(allocator, '\t');

        for (values_list.items, 0..) |value, i| {
            if (i > 0) try output_buffer.append(allocator, ' ');
            try output_buffer.appendSlice(allocator, value);
        }

        try output_buffer.append(allocator, '\n');
    }

    const output_file = if (std.fs.path.isAbsolute(output_path))
        try std.fs.createFileAbsolute(output_path, .{})
    else
        try std.fs.cwd().createFile(output_path, .{});
    defer output_file.close();

    try output_file.writeAll(output_buffer.items);
}

const std = @import("std");
const StringList = std.ArrayList([]const u8);

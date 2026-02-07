pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const io = init.io;

    if (args.len != 3) {
        std.debug.print("Usage: {s} [input] [output]\n", .{args[0]});
        std.debug.print("Reverse key and value of all pairs\n", .{});
        return error.InvalidArguments;
    }

    const input_path = args[1];
    const output_path = args[2];

    try reverseItems(arena, io, input_path, output_path);
}

fn reverseItems(allocator: std.mem.Allocator, io: std.Io, input_path: []const u8, output_path: []const u8) !void {
    // Read input file (supports absolute and relative paths)
    const input_file = if (std.fs.path.isAbsolute(input_path))
        try std.Io.Dir.openFileAbsolute(io, input_path, .{})
    else
        try std.Io.Dir.cwd().openFile(io, input_path, .{});
    defer input_file.close(io);

    var reader_buffer: [1024]u8 = undefined;
    var input_file_reader = input_file.reader(io, &reader_buffer);
    const reader = &input_file_reader.interface;

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
    while (try reader.takeDelimiter('\n')) |line| {
        const line_stripped = std.mem.trim(u8, line, " \t\r");

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
            const value_trimmed = std.mem.trim(u8, value, " \t\r");
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
    var output_data: std.ArrayList(u8) = .empty;
    defer output_data.deinit(allocator);

    for (sorted_keys.items) |key| {
        const values_list = dict.get(key).?;

        try output_data.appendSlice(allocator, key);
        try output_data.append(allocator, '\t');

        for (values_list.items, 0..) |value, i| {
            if (i > 0) try output_data.append(allocator, ' ');
            try output_data.appendSlice(allocator, value);
        }

        try output_data.append(allocator, '\n');
    }

    const output_file = if (std.fs.path.isAbsolute(output_path))
        try std.Io.Dir.createFileAbsolute(io, output_path, .{})
    else
        try std.Io.Dir.cwd().createFile(io, output_path, .{});
    defer output_file.close(io);

    var writer_buffer: [1024]u8 = undefined;
    var output_file_writer = output_file.writer(io, &writer_buffer);
    const writer = &output_file_writer.interface;
    try writer.writeAll(output_data.items);
    try writer.flush();
}

const std = @import("std");
const StringList = std.ArrayList([]const u8);

const std = @import("std");

const Allocator = std.mem.Allocator;

const generator = @import("generator");

pub fn main(init: std.process.Init) !void {
    var args = try parseArgs(init.gpa, init.minimal.args);
    defer args.deinit();

    var read_buffer: [4096]u8 = undefined;
    var in: std.Io.File.Reader = undefined;
    if (args.get("in")) |in_file_flag| {
        const file = try std.Io.Dir.cwd().openFile(init.io, in_file_flag.string, .{ .mode = .read_only });
        in = file.reader(init.io, &read_buffer);
    } else {
        in = std.Io.File.stdin().reader(init.io, &read_buffer);
    }

    var write_buffer: [4096]u8 = undefined;
    var out: std.Io.File.Writer = undefined;
    if (args.get("out")) |out_file_flag| {
        const overwrite = if (args.get("overwrite")) |overwrite_flag| overwrite_flag.bool else false;
        const file = try std.Io.Dir.cwd().createFile(init.io, out_file_flag.string, .{ .exclusive = !overwrite });
        out = file.writer(init.io, &write_buffer);
    } else {
        out = std.Io.File.stdout().writer(init.io, &write_buffer);
    }
    defer out.flush() catch @panic("flush failed");

    try generator.do(init.gpa, &in.interface, &out.interface);
}

const Flag = union(enum) {
    string: []const u8,
    bool: bool,
};

/// Really primitive way of parsing arguments so I don't have to pull in 3rd
/// party anything. Basically it looks for `--{flag}` and tries to associate
/// the incoming value with `flag` in a string hashmap.
fn parseArgs(alloc: Allocator, args: std.process.Args) !std.StringHashMap(Flag) {
    var map: std.StringHashMap(Flag) = .init(alloc);
    var key: ?[]const u8 = null;
    var it = args.iterate();
    while (it.next()) |arg| {
        if (arg.len > 2 and arg[0] == '-' and arg[1] == '-') {
            key = arg[2..];
            try map.put(key.?, .{ .bool = true });
            continue;
        }
        if (key == null) {
            continue;
        }
        defer key = null;

        if (std.ascii.eqlIgnoreCase(arg, "true")) {
            try map.put(key.?, .{ .bool = true });
            continue;
        }
        if (std.ascii.eqlIgnoreCase(arg, "false")) {
            try map.put(key.?, .{ .bool = false });
            continue;
        }
        try map.put(key.?, .{ .string = arg });
    }
    return map;
}

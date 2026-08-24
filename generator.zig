const std = @import("std");

const json = std.json;
const mem = std.mem;

pub fn main(init: std.process.Init) !void {
    try hello(init);
}

const Field = struct {
    type: []const u8,
    name: []const u8,
    versions: []const u8,
    nullableVersions: []const u8 = "",
    flexibleVersions: []const u8 = "",
    fields: []Field = &.{},
};

const Msg = struct {
    apiKey: i16 = 0,
    type: []const u8,
    name: []const u8,
    validVersions: []const u8,
    flexibleVersions: []const u8,
    fields: []Field,
};

pub fn hello(init: std.process.Init) !void {
    const paths = [_][]const u8{
        "./protocol_json_files/MetadataRequest.json",
    };

    for (paths) |path| {
        try readAndPrint(init, path);
    }
}

fn readAndPrint(init: std.process.Init, path: []const u8) !void {
    const file_content = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .unlimited);
    defer init.gpa.free(file_content);

    const clean = try clearComments(file_content, init.gpa);
    defer init.gpa.free(clean);

    const parsed = try json.parseFromSlice(Msg, init.gpa, clean, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    // std.json.fmt(parsed.value, .{});
    // std.debug.print("{f}\n", .{std.json.fmt(parsed.value, .{})});

    p(parsed.value, 0);
}

fn p(T: anytype, indent: usize) void {
    var prefix = [_]u8{'\t'} ** indent;
    std.debug.print("{s}Name: {s}\nType: {s}\nFields:\n", .{ &prefix, T.name, T.type });
    for (T.fields) |field| {
        p(field, indent + 1);
    }
}

fn clearComments(src: []const u8, alloc: mem.Allocator) ![]const u8 {
    const dst = try alloc.alloc(u8, src.len);

    var pos: usize = 0;

    var in_comment = false;
    var in_string = false;
    for (src, 0..) |byte, i| {
        if (!in_string and byte == '"') {
            in_string = true;
        }
        if (in_string and byte == '"') {
            in_string = false;
        }
        if (!in_string and byte == '/' and i < src.len - 1 and src[i + 1] == '/') {
            in_comment = true;
        }

        if (in_comment and byte == '\n') {
            in_comment = false;
            continue;
        }

        if (in_comment) {
            continue;
        }

        dst[pos] = byte;
        pos += 1;
    }

    const result = try alloc.dupe(u8, dst[0..pos]);
    defer alloc.free(dst);

    return result;
}

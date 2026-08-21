const std = @import("std");

const Writer = @import("Writer.zig");

const mem = std.mem;

const ApiVersionsResponse = @This();

pub const ApiVersion = struct {
    api_key: i16,
    min_version: i16,
    max_version: i16,
};

error_code: i16,
api_keys: []const ApiVersion,

pub fn write(self: ApiVersionsResponse, alloc: mem.Allocator, writer: *Writer) !void {
    try writer.writeInt(alloc, @TypeOf(self.error_code), self.error_code);
    try writer.writeUvarint(alloc, @intCast(self.api_keys.len + 1));
    for (self.api_keys) |api_key| {
        try writer.writeInt(alloc, @TypeOf(api_key.api_key), api_key.api_key);
        try writer.writeInt(alloc, @TypeOf(api_key.min_version), api_key.min_version);
        try writer.writeInt(alloc, @TypeOf(api_key.max_version), api_key.max_version);
        try writer.writeUvarint(alloc, 0);
    }
    try writer.writeInt(alloc, i32, 100);
    try writer.writeUvarint(alloc, 0);
}

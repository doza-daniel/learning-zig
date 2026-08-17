const std = @import("std");

const Reader = @import("Reader.zig");

const mem = std.mem;

const RequestHeader = @This();

request_api_key: i16 = 0,
request_api_version: i16 = 0,
correlation_id: i32 = 0,
client_id: ?[]const u8 = null,

pub fn read(self: *RequestHeader, reader: *Reader, alloc: mem.Allocator) !void {
    self.request_api_key = try reader.readInt(i16);
    self.request_api_version = try reader.readInt(i16);
    self.correlation_id = try reader.readInt(i32);
    self.client_id = try reader.readNullableString(alloc);
    if (isFlexible(self.request_api_key, self.request_api_version) and try reader.readUvarint() > 0) {
        return error.UnexpectedTags;
    }
}

fn isFlexible(api_key: i16, api_version: i16) bool {
    switch (api_key) {
        0 => return api_version >= 9,
        3 => return api_version >= 9,
        18 => return api_version >= 3,
        else => return false,
    }
}

pub fn deinit(self: *RequestHeader, alloc: mem.Allocator) void {
    if (self.client_id) |str| {
        alloc.free(str);
    }
}

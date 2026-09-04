const std = @import("std");
const Reader = @import("../Reader.zig");
const RecordBatch = @import("../RecordBatch.zig");
const ApiVersionsRequest = @This();

pub fn isFlexible(version: i16) bool {
    if (version >= 3) {
        return true;
    } else {
        return false;
    }
}
ClientSoftwareName: []const u8 = "",
ClientSoftwareVersion: []const u8 = "",
ClusterId: ?[]const u8 = null,
NodeId: i32 = -1,

pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
    alloc.free(self.ClientSoftwareName);
    alloc.free(self.ClientSoftwareVersion);
    if (self.ClusterId) |val| {
        alloc.free(val);
    }
}

pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
    if (version >= 3) {
        if (isFlexible(version)) {
            self.ClientSoftwareName = try reader.readCompactString(alloc);
        } else {
            self.ClientSoftwareName = try reader.readString(alloc);
        }
    }
    if (version >= 3) {
        if (isFlexible(version)) {
            self.ClientSoftwareVersion = try reader.readCompactString(alloc);
        } else {
            self.ClientSoftwareVersion = try reader.readString(alloc);
        }
    }
    if (version >= 5) {
        if (isFlexible(version)) {
            if (version >= 5) {
                self.ClusterId = try reader.readCompactNullableString(alloc);
            } else {
                self.ClusterId = try reader.readCompactString(alloc);
            }
        } else {
            if (version >= 5) {
                self.ClusterId = try reader.readNullableString(alloc);
            } else {
                self.ClusterId = try reader.readString(alloc);
            }
        }
    }
    if (version >= 5) {
        self.NodeId = try reader.readInt(i32);
    }
    if (isFlexible(version)) {
        const num_tags = try reader.readUvarint();
        for (0..num_tags) |_| {
            const tag: u32 = try reader.readUvarint();
            const tag_len: u32 = try reader.readUvarint();
            defer reader.src = reader.src[tag_len..];
            switch (tag) {
                else => unreachable,
            }
        }
    }
}

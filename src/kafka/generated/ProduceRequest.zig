const std = @import("std");
const Reader = @import("../Reader.zig");
const RecordBatch = @import("../RecordBatch.zig");
const ProduceRequest = @This();

pub fn isFlexible(version: i16) bool {
    if (version >= 9) {
        return true;
    } else {
        return false;
    }
}
TransactionalId: ?[]const u8 = null,
Acks: i16 = 0,
TimeoutMs: i32 = 0,
TopicData: []TopicProduceData = &.{},

pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
    if (self.TransactionalId) |val| {
        alloc.free(val);
    }
    for (self.TopicData) |elem| {
        elem.deinit(alloc);
    }
    alloc.free(self.TopicData);
}

pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
    if (version >= 3) {
        if (isFlexible(version)) {
            if (version >= 3) {
                self.TransactionalId = try reader.readCompactNullableString(alloc);
            } else {
                self.TransactionalId = try reader.readCompactString(alloc);
            }
        } else {
            if (version >= 3) {
                self.TransactionalId = try reader.readNullableString(alloc);
            } else {
                self.TransactionalId = try reader.readString(alloc);
            }
        }
    }
    self.Acks = try reader.readInt(i16);
    self.TimeoutMs = try reader.readInt(i32);
    if (isFlexible(version)) {
        self.TopicData = try reader.readCompactArray(TopicProduceData, alloc, version);
    } else {
        self.TopicData = try reader.readArray(TopicProduceData, alloc, version);
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
const TopicProduceData = struct {
    Name: []const u8 = "",
    TopicId: [16]u8 = @as([16]u8, @splat(0)),
    PartitionData: []PartitionProduceData = &.{},

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.Name);
        for (self.PartitionData) |elem| {
            elem.deinit(alloc);
        }
        alloc.free(self.PartitionData);
    }

    pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
        if (version <= 12) {
            if (isFlexible(version)) {
                self.Name = try reader.readCompactString(alloc);
            } else {
                self.Name = try reader.readString(alloc);
            }
        }
        if (version >= 13) {
            self.TopicId = try reader.readUuid();
        }
        if (isFlexible(version)) {
            self.PartitionData = try reader.readCompactArray(PartitionProduceData, alloc, version);
        } else {
            self.PartitionData = try reader.readArray(PartitionProduceData, alloc, version);
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
};
const PartitionProduceData = struct {
    Index: i32 = 0,
    Records: ?RecordBatch = .{},

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        if (self.Records) |val| {
            val.deinit(alloc);
        }
    }

    pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
        self.Index = try reader.readInt(i32);
        var bytes: []u8 = undefined;
        if (isFlexible(version)) {
            bytes = try reader.readCompactBytes(alloc);
        } else {
            bytes = try reader.readBytes(alloc);
        }
        defer alloc.free(bytes);
        var record_reader: Reader = .{ .src = &bytes };
        try self.Records.read(&record_reader, alloc);
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
};

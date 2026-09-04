const std = @import("std");
const Reader = @import("../Reader.zig");
const RecordBatch = @import("../RecordBatch.zig");
const MetadataResponse = @This();

pub fn isFlexible(version: i16) bool {
    if (version >= 9) {
        return true;
    } else {
        return false;
    }
}
ThrottleTimeMs: i32 = 0,
Brokers: []MetadataResponseBroker = &.{},
ClusterId: ?[]const u8 = null,
ControllerId: i32 = -1,
Topics: []MetadataResponseTopic = &.{},
ClusterAuthorizedOperations: i32 = -2147483648,
ErrorCode: i16 = 0,

pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
    for (self.Brokers) |elem| {
        elem.deinit(alloc);
    }
    alloc.free(self.Brokers);
    if (self.ClusterId) |val| {
        alloc.free(val);
    }
    for (self.Topics) |elem| {
        elem.deinit(alloc);
    }
    alloc.free(self.Topics);
}

pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
    if (version >= 3) {
        self.ThrottleTimeMs = try reader.readInt(i32);
    }
    if (isFlexible(version)) {
        self.Brokers = try reader.readCompactArray(MetadataResponseBroker, alloc, version);
    } else {
        self.Brokers = try reader.readArray(MetadataResponseBroker, alloc, version);
    }
    if (version >= 2) {
        if (isFlexible(version)) {
            if (version >= 2) {
                self.ClusterId = try reader.readCompactNullableString(alloc);
            } else {
                self.ClusterId = try reader.readCompactString(alloc);
            }
        } else {
            if (version >= 2) {
                self.ClusterId = try reader.readNullableString(alloc);
            } else {
                self.ClusterId = try reader.readString(alloc);
            }
        }
    }
    if (version >= 1) {
        self.ControllerId = try reader.readInt(i32);
    }
    if (isFlexible(version)) {
        self.Topics = try reader.readCompactArray(MetadataResponseTopic, alloc, version);
    } else {
        self.Topics = try reader.readArray(MetadataResponseTopic, alloc, version);
    }
    if (version >= 8 and version <= 10) {
        self.ClusterAuthorizedOperations = try reader.readInt(i32);
    }
    if (version >= 13) {
        self.ErrorCode = try reader.readInt(i16);
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
const MetadataResponseBroker = struct {
    NodeId: i32 = 0,
    Host: []const u8 = "",
    Port: i32 = 0,
    Rack: ?[]const u8 = null,

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.Host);
        if (self.Rack) |val| {
            alloc.free(val);
        }
    }

    pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
        self.NodeId = try reader.readInt(i32);
        if (isFlexible(version)) {
            self.Host = try reader.readCompactString(alloc);
        } else {
            self.Host = try reader.readString(alloc);
        }
        self.Port = try reader.readInt(i32);
        if (version >= 1) {
            if (isFlexible(version)) {
                if (version >= 1) {
                    self.Rack = try reader.readCompactNullableString(alloc);
                } else {
                    self.Rack = try reader.readCompactString(alloc);
                }
            } else {
                if (version >= 1) {
                    self.Rack = try reader.readNullableString(alloc);
                } else {
                    self.Rack = try reader.readString(alloc);
                }
            }
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
const MetadataResponseTopic = struct {
    ErrorCode: i16 = 0,
    Name: ?[]const u8 = "",
    TopicId: [16]u8 = @as([16]u8, @splat(0)),
    IsInternal: bool = false,
    Partitions: []MetadataResponsePartition = &.{},
    TopicAuthorizedOperations: i32 = -2147483648,

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        if (self.Name) |val| {
            alloc.free(val);
        }
        for (self.Partitions) |elem| {
            elem.deinit(alloc);
        }
        alloc.free(self.Partitions);
    }

    pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
        self.ErrorCode = try reader.readInt(i16);
        if (isFlexible(version)) {
            if (version >= 12) {
                self.Name = try reader.readCompactNullableString(alloc);
            } else {
                self.Name = try reader.readCompactString(alloc);
            }
        } else {
            if (version >= 12) {
                self.Name = try reader.readNullableString(alloc);
            } else {
                self.Name = try reader.readString(alloc);
            }
        }
        if (version >= 10) {
            self.TopicId = try reader.readUuid();
        }
        if (version >= 1) {
            self.IsInternal = try reader.readBool();
        }
        if (isFlexible(version)) {
            self.Partitions = try reader.readCompactArray(MetadataResponsePartition, alloc, version);
        } else {
            self.Partitions = try reader.readArray(MetadataResponsePartition, alloc, version);
        }
        if (version >= 8) {
            self.TopicAuthorizedOperations = try reader.readInt(i32);
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
const MetadataResponsePartition = struct {
    ErrorCode: i16 = 0,
    PartitionIndex: i32 = 0,
    LeaderId: i32 = 0,
    LeaderEpoch: i32 = -1,
    ReplicaNodes: []i32 = &.{},
    IsrNodes: []i32 = &.{},
    OfflineReplicas: []i32 = &.{},

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.ReplicaNodes);
        alloc.free(self.IsrNodes);
        alloc.free(self.OfflineReplicas);
    }

    pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
        self.ErrorCode = try reader.readInt(i16);
        self.PartitionIndex = try reader.readInt(i32);
        self.LeaderId = try reader.readInt(i32);
        if (version >= 7) {
            self.LeaderEpoch = try reader.readInt(i32);
        }
        if (isFlexible(version)) {
            self.ReplicaNodes = try reader.readCompactArray(i32, alloc, version);
        } else {
            self.ReplicaNodes = try reader.readArray(i32, alloc, version);
        }
        if (isFlexible(version)) {
            self.IsrNodes = try reader.readCompactArray(i32, alloc, version);
        } else {
            self.IsrNodes = try reader.readArray(i32, alloc, version);
        }
        if (version >= 5) {
            if (isFlexible(version)) {
                self.OfflineReplicas = try reader.readCompactArray(i32, alloc, version);
            } else {
                self.OfflineReplicas = try reader.readArray(i32, alloc, version);
            }
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

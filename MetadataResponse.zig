const std = @import("std");

const Writer = @import("Writer.zig");

const mem = std.mem;

const MetadataResponse = @This();

pub const MetadataResponseBroker = struct {
    node_id: i32,
    host: []const u8,
    port: i32,
    rack: ?[]const u8,
    pub fn write(self: MetadataResponseBroker, alloc: mem.Allocator, writer: *Writer) !void {
        try writer.writeInt(alloc, @TypeOf(self.node_id), self.node_id);
        try writer.writeCompactString(alloc, self.host);
        try writer.writeInt(alloc, @TypeOf(self.port), self.port);
        if (self.rack) |str| {
            try writer.writeCompactString(alloc, str);
        } else {
            try writer.writeUvarint(alloc, 0);
        }
    }
};

pub const MetadataResponseTopic = struct {
    error_code: i16,
    name: ?[]const u8,
    topic_id: [16]u8,
    is_internal: bool,
    partitions: []const MetadataResponsePartition,
    topic_authorized_operations: i32 = -2147483648,

    pub fn write(self: MetadataResponseTopic, alloc: mem.Allocator, writer: *Writer) !void {
        try writer.writeInt(alloc, @TypeOf(self.error_code), self.error_code);
        if (self.name) |str| {
            try writer.writeCompactString(alloc, str);
        } else {
            try writer.writeUvarint(alloc, 0);
        }
        try writer.writeUuid(alloc, self.topic_id);
        try writer.writeBool(alloc, self.is_internal);

        try writer.writeUvarint(alloc, @intCast(self.partitions.len + 1));
        for (self.partitions) |partition| {
            try partition.write(alloc, writer);
            try writer.writeUvarint(alloc, 0);
        }

        try writer.writeInt(alloc, @TypeOf(self.topic_authorized_operations), self.topic_authorized_operations);
    }
};

pub const MetadataResponsePartition = struct {
    error_code: i16,
    partition_index: i32,
    leader_id: i32,
    leader_epoch: i32 = -1,
    replica_nodes: []const i32,
    isr_nodes: []const i32,
    offline_replicas: []const i32,

    pub fn write(self: MetadataResponsePartition, alloc: mem.Allocator, writer: *Writer) !void {
        try writer.writeInt(alloc, @TypeOf(self.error_code), self.error_code);
        try writer.writeInt(alloc, @TypeOf(self.partition_index), self.partition_index);
        try writer.writeInt(alloc, @TypeOf(self.leader_id), self.leader_id);
        try writer.writeInt(alloc, @TypeOf(self.leader_epoch), self.leader_epoch);

        try writer.writeUvarint(alloc, @intCast(self.replica_nodes.len + 1));
        for (self.replica_nodes) |replica_node| {
            try writer.writeInt(alloc, @TypeOf(replica_node), replica_node);
        }

        try writer.writeUvarint(alloc, @intCast(self.isr_nodes.len + 1));
        for (self.isr_nodes) |isr_node| {
            try writer.writeInt(alloc, @TypeOf(isr_node), isr_node);
        }

        try writer.writeUvarint(alloc, @intCast(self.offline_replicas.len + 1));
        for (self.offline_replicas) |offline_replica| {
            try writer.writeInt(alloc, @TypeOf(offline_replica), offline_replica);
        }
    }
};

throttle_time_ms: i32,
brokers: []const MetadataResponseBroker,
cluster_id: []const u8,
controller_id: i32,
topics: []const MetadataResponseTopic,
error_code: i16,

pub fn write(self: MetadataResponse, alloc: mem.Allocator, writer: *Writer) !void {
    try writer.writeInt(alloc, @TypeOf(self.throttle_time_ms), self.throttle_time_ms);

    // write brokers
    try writer.writeUvarint(alloc, @intCast(self.brokers.len + 1));
    for (self.brokers) |broker| {
        try broker.write(alloc, writer);
        try writer.writeUvarint(alloc, 0);
    }

    try writer.writeCompactString(alloc, self.cluster_id);
    try writer.writeInt(alloc, @TypeOf(self.controller_id), self.controller_id);

    // write topics
    try writer.writeUvarint(alloc, @intCast(self.topics.len + 1));
    for (self.topics) |topic| {
        try topic.write(alloc, writer);
        try writer.writeUvarint(alloc, 0);
    }

    try writer.writeInt(alloc, @TypeOf(self.error_code), self.error_code);

    try writer.writeUvarint(alloc, 0);
}

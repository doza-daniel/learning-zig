const std = @import("std");

const Reader = @import("Reader.zig");
const RecordBatch = @import("RecordBatch.zig");

const mem = std.mem;

const ProduceRequest = @This();

const PartitionProduceData = struct {
    index: i32,
    data: []u8,
    record_batch: RecordBatch,

    fn deinit(self: *PartitionProduceData, alloc: mem.Allocator) void {
        alloc.free(self.data);
    }
};

const TopicProduceData = struct {
    name: ?[]const u8 = null,
    topic_id: [16]u8,
    partition_data: []PartitionProduceData,

    fn deinit(self: *TopicProduceData, alloc: mem.Allocator) void {
        alloc.free(self.name);
        for (self.partition_data) |partition| {
            partition.deinit(alloc);
        }
        alloc.free(self.partition_data);
    }
};

version: i16,

transactional_id: ?[]const u8 = null,
acks: i16,
timeout_ms: i32,
topic_data: []TopicProduceData,

pub fn read(self: *ProduceRequest, reader: *Reader, alloc: mem.Allocator) !void {
    if (self.version >= 3) {
        if (self.isFlexible()) {
            self.transactional_id = try reader.readCompactString(alloc);
        } else {
            self.transactional_id = try reader.readNullableString(alloc);
        }
    }
    self.acks = try reader.readInt(i16);
    self.timeout_ms = try reader.readInt(i32);

    var num_topics: u32 = 0;
    if (self.isFlexible()) {
        num_topics = try reader.readUvarint();
    } else {
        num_topics = try reader.readInt(u32) + 1;
    }
    if (num_topics > 1) {
        try self.readTopics(reader, alloc, num_topics - 1);
    }
}

fn readTopics(self: *ProduceRequest, reader: *Reader, alloc: mem.Allocator, n: u32) !void {
    self.topic_data = try alloc.alloc(TopicProduceData, n);
    for (0..n) |i| {
        self.topic_data[i].name = null;
        if (self.version <= 12) {
            if (self.isFlexible()) {
                self.topic_data[i].name = try reader.readCompactString(alloc);
            } else {
                self.topic_data[i].name = try reader.readNullableString(alloc);
            }
        }
        if (self.version >= 13) {
            self.topic_data[i].topic_id = try reader.readUuid();
        }
        var num_partitions: u32 = 0;
        if (self.isFlexible()) {
            num_partitions = try reader.readUvarint();
        } else {
            num_partitions = try reader.readInt(u32) + 1;
        }
        if (num_partitions > 1) {
            try self.readPartitions(reader, alloc, &self.topic_data[i], num_partitions - 1);
        }
    }
}

fn readPartitions(self: *ProduceRequest, reader: *Reader, alloc: mem.Allocator, topic_data: *TopicProduceData, n: u32) !void {
    _ = self;
    topic_data.partition_data = try alloc.alloc(PartitionProduceData, n);
    for (0..n) |i| {
        topic_data.partition_data[i].index = try reader.readInt(i32);
        topic_data.partition_data[i].data = try reader.readCompactBytes(alloc);
        var record_batch_reader: Reader = .{ .src = topic_data.partition_data[i].data };
        try topic_data.partition_data[i].record_batch.read(&record_batch_reader, alloc);
    }
}

pub fn deinit(self: *ProduceRequest, alloc: mem.Allocator) void {
    alloc.free(self.transactional_id);
    for (self.topic_data) |topic| {
        topic.deinit(alloc);
    }
    alloc.free(self.topic_data);
}

pub fn isFlexible(self: ProduceRequest) bool {
    return self.version >= 9;
}

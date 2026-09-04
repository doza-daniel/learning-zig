const std = @import("std");
const Reader = @import("../Reader.zig");
const RecordBatch = @import("../RecordBatch.zig");
const ApiVersionsResponse = @This();

pub fn isFlexible(version: i16) bool {
    if (version >= 3) {
        return true;
    } else {
        return false;
    }
}
ErrorCode: i16 = 0,
ApiKeys: []ApiVersion = &.{},
ThrottleTimeMs: i32 = 0,
SupportedFeatures: []SupportedFeatureKey = &.{},
FinalizedFeaturesEpoch: i64 = -1,
FinalizedFeatures: []FinalizedFeatureKey = &.{},
ZkMigrationReady: bool = false,

pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
    for (self.ApiKeys) |elem| {
        elem.deinit(alloc);
    }
    alloc.free(self.ApiKeys);
    for (self.SupportedFeatures) |elem| {
        elem.deinit(alloc);
    }
    alloc.free(self.SupportedFeatures);
    for (self.FinalizedFeatures) |elem| {
        elem.deinit(alloc);
    }
    alloc.free(self.FinalizedFeatures);
}

pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
    self.ErrorCode = try reader.readInt(i16);
    if (isFlexible(version)) {
        self.ApiKeys = try reader.readCompactArray(ApiVersion, alloc, version);
    } else {
        self.ApiKeys = try reader.readArray(ApiVersion, alloc, version);
    }
    if (version >= 1) {
        self.ThrottleTimeMs = try reader.readInt(i32);
    }
    if (isFlexible(version)) {
        const num_tags = try reader.readUvarint();
        for (0..num_tags) |_| {
            const tag: u32 = try reader.readUvarint();
            const tag_len: u32 = try reader.readUvarint();
            defer reader.src = reader.src[tag_len..];
            switch (tag) {
                0 => {
                    var tag_reader: Reader = .{ .src = reader.src[0..tag_len] };
                    if (version >= 3) {
                        if (isFlexible(version)) {
                            self.SupportedFeatures = try tag_reader.readCompactArray(SupportedFeatureKey, alloc, version);
                        } else {
                            self.SupportedFeatures = try tag_reader.readArray(SupportedFeatureKey, alloc, version);
                        }
                    }
                },
                1 => {
                    var tag_reader: Reader = .{ .src = reader.src[0..tag_len] };
                    if (version >= 3) {
                        self.FinalizedFeaturesEpoch = try tag_reader.readInt(i64);
                    }
                },
                2 => {
                    var tag_reader: Reader = .{ .src = reader.src[0..tag_len] };
                    if (version >= 3) {
                        if (isFlexible(version)) {
                            self.FinalizedFeatures = try tag_reader.readCompactArray(FinalizedFeatureKey, alloc, version);
                        } else {
                            self.FinalizedFeatures = try tag_reader.readArray(FinalizedFeatureKey, alloc, version);
                        }
                    }
                },
                3 => {
                    var tag_reader: Reader = .{ .src = reader.src[0..tag_len] };
                    if (version >= 3) {
                        self.ZkMigrationReady = try tag_reader.readBool();
                    }
                },
                else => unreachable,
            }
        }
    }
}
const ApiVersion = struct {
    ApiKey: i16 = 0,
    MinVersion: i16 = 0,
    MaxVersion: i16 = 0,

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        _ = self;
        _ = alloc;
    }

    pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
        self.ApiKey = try reader.readInt(i16);
        self.MinVersion = try reader.readInt(i16);
        self.MaxVersion = try reader.readInt(i16);
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
        _ = alloc;
    }
};
const SupportedFeatureKey = struct {
    Name: []const u8 = "",
    MinVersion: i16 = 0,
    MaxVersion: i16 = 0,

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.Name);
    }

    pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
        if (version >= 3) {
            if (isFlexible(version)) {
                self.Name = try reader.readCompactString(alloc);
            } else {
                self.Name = try reader.readString(alloc);
            }
        }
        if (version >= 3) {
            self.MinVersion = try reader.readInt(i16);
        }
        if (version >= 3) {
            self.MaxVersion = try reader.readInt(i16);
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
const FinalizedFeatureKey = struct {
    Name: []const u8 = "",
    MaxVersionLevel: i16 = 0,
    MinVersionLevel: i16 = 0,

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.Name);
    }

    pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
        if (version >= 3) {
            if (isFlexible(version)) {
                self.Name = try reader.readCompactString(alloc);
            } else {
                self.Name = try reader.readString(alloc);
            }
        }
        if (version >= 3) {
            self.MaxVersionLevel = try reader.readInt(i16);
        }
        if (version >= 3) {
            self.MinVersionLevel = try reader.readInt(i16);
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

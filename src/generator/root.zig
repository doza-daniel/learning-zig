const std = @import("std");

const json = std.json;
const Allocator = std.mem.Allocator;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;

const Field = struct {
    type: *Ti,
    name: []const u8,
    versions: []const u8,
    nullableVersions: []const u8 = "",
    flexibleVersions: []const u8 = "",
    fields: []Field = &.{},
};

const Msg = struct {
    apiKey: i16 = 0,
    type: *Ti,
    name: []const u8,
    validVersions: []const u8,
    flexibleVersions: []const u8,
    fields: []Field,
};

pub fn do(alloc: Allocator, in: *Reader, out: *Writer) !void {
    const json_content = try readFull(alloc, in);

    const clean = try clearComments(json_content, alloc);
    alloc.free(json_content);
    defer alloc.free(clean);

    const parsed = try json.parseFromSlice(Msg, alloc, clean, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    try codeGen(parsed.value, alloc, out);
}

fn readFull(alloc: Allocator, in: *Reader) ![]u8 {
    var content: std.ArrayList(u8) = .empty;
    while (true) {
        var buff: [1024]u8 = undefined;
        const read = try in.readSliceShort(&buff);
        try content.appendSlice(alloc, buff[0..read]);
        if (read < buff.len) {
            break;
        }
    }
    return try content.toOwnedSlice(alloc);
}

fn codeGen(T: anytype, alloc: Allocator, out: *Writer) !void {
    var q: std.Deque(Field) = .empty;
    defer q.deinit(alloc);

    var close_struct: bool = false;

    switch (T.type.*) {
        .request, .response, .data, .header => {
            try out.print("const std = @import(\"std\");\n", .{});
            try out.print("const Reader = @import(\"Reader.zig\");\n", .{});
            try out.print("const RecordBatch = @import(\"RecordBatch.zig\");\n", .{});
            try out.print("const {s} = @This();\n", .{T.name});
        },
        .structure => |struct_name| {
            try out.print("const {s} = struct{{\n", .{struct_name});
            close_struct = true;
        },
        .array => |arr| {
            switch (arr.elements.*) {
                .structure => |struct_name| {
                    try out.print("const {s} = struct{{\n", .{struct_name});
                    close_struct = true;
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }

    for (T.fields) |field| {
        switch (field.type.*) {
            .array => try q.pushBack(alloc, field),
            else => {},
        }
        try out.print("{s}: {s},\n", .{ field.name, field.type.zigType() orelse "{FIX ME}" });
    }
    try out.print("pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator) !void {{\n", .{});
    for (T.fields) |field| {
        switch (field.type.*) {
            .bool => {
                try out.print("self.{s} = try reader.readBool();\n", .{field.name});
            },
            .int8 => {
                try out.print("self.{s} = try reader.readInt(i8);\n", .{field.name});
            },
            .int16 => {
                try out.print("self.{s} = try reader.readInt(i16);\n", .{field.name});
            },
            .int32 => {
                try out.print("self.{s} = try reader.readInt(i32);\n", .{field.name});
            },
            .int64 => {
                try out.print("self.{s} = try reader.readInt(i64);\n", .{field.name});
            },
            .uint16 => {
                try out.print("self.{s} = try reader.readInt(u16);\n", .{field.name});
            },
            .uint32 => {
                try out.print("self.{s} = try reader.readInt(u32);\n", .{field.name});
            },
            .uuid => {
                try out.print("self.{s} = try reader.readUuid();\n", .{field.name});
            },
            .float64 => {
                try out.print("self.{s} = try reader.readFloat64();\n", .{field.name});
            },
            .string => {
                try out.print("self.{s} = try reader.readString(alloc);\n", .{field.name});
            },
            .bytes => {
                try out.print("self.{s} = try reader.readBytes(alloc);\n", .{field.name});
            },
            .array => |arr| {
                try out.print("self.{s} = try reader.readArray({s}, alloc);\n", .{ field.name, arr.elements.zigType() orelse "{FIX ME}" });
            },
            .structure => {
                try out.print("try self.{s}.read(reader, alloc);\n", .{field.name});
            },
            .records => {
                try out.print("var bytes = try reader.readBytes(alloc);\n", .{});
                try out.print("defer alloc.free(bytes);\n", .{});
                try out.print("var record_reader: Reader = .{{.src = &bytes}};\n", .{});
                try out.print("try self.{s}.read(&record_reader, alloc);\n", .{field.name});
            },

            .response, .request, .data, .header => unreachable,
        }
    }
    try out.print("}}\n", .{});

    if (close_struct) {
        try out.print("}};\n", .{});
    }

    while (q.len > 0) {
        try codeGen(q.popFront().?, alloc, out);
    }
}

const Ti = union(enum) {
    bool: void,
    int8: void,
    int16: void,
    int32: void,
    int64: void,
    uint16: void,
    uint32: void,
    uuid: void,
    float64: void,
    string: void,
    bytes: void,
    data: void,
    records: void,
    response: void,
    request: void,
    header: void,

    array: struct {
        name: []const u8,
        elements: *Ti,
    },
    structure: []const u8,

    fn zigType(self: Ti) ?[]const u8 {
        return switch (self) {
            .bool => "bool",
            .int8 => "i8",
            .int16 => "i16",
            .int32 => "i32",
            .int64 => "i64",
            .uint16 => "u16",
            .uint32 => "u32",
            .uuid => "[16]u8",
            .float64 => "f64",
            .string => "[]const u8",
            .bytes => "[]u8",
            .records => "RecordBatch",
            .array => |arr| arr.name,
            .structure => |name| name,
            else => null,
        };
    }

    fn parse(str: []const u8, alloc: Allocator) !*Ti {
        const result = try alloc.create(Ti);
        errdefer alloc.destroy(result);

        if (std.meta.stringToEnum(std.meta.Tag(Ti), str)) |tag| {
            switch (tag) {
                .bool => |t| result.* = t,
                .int8 => |t| result.* = t,
                .int16 => |t| result.* = t,
                .int32 => |t| result.* = t,
                .int64 => |t| result.* = t,
                .uint16 => |t| result.* = t,
                .uint32 => |t| result.* = t,
                .uuid => |t| result.* = t,
                .float64 => |t| result.* = t,
                .string => |t| result.* = t,
                .bytes => |t| result.* = t,
                .data => |t| result.* = t,
                .records => |t| result.* = t,
                .response => |t| result.* = t,
                .request => |t| result.* = t,
                .header => |t| result.* = t,

                .array, .structure => return error.BadPrimitive,
            }
            return result;
        }

        // parse array
        if (str.len > 2 and str[0] == '[' and str[1] == ']') {
            const elements = try parse(str[2..], alloc);
            result.* = .{
                .array = .{
                    .name = try std.fmt.allocPrint(alloc, "[]{s}", .{elements.zigType().?}),
                    .elements = elements,
                },
            };
            return result;
        }

        // finally, try parse struct
        for (str) |c| {
            if (!std.ascii.isAlphanumeric(c)) {
                return error.BadStructIdent;
            }
        }
        result.* = .{
            .structure = try alloc.dupe(u8, str),
        };
        return result;
    }

    pub fn jsonParse(alloc: Allocator, source: anytype, opts: std.json.ParseOptions) !@This() {
        return switch (try source.nextAllocMax(alloc, .alloc_always, opts.max_value_len.?)) {
            .allocated_string => |s| {
                return (Ti.parse(s, alloc) catch unreachable).*;
            },
            else => unreachable,
        };
    }

    fn deinit(self: *@This(), alloc: Allocator) void {
        defer alloc.destroy(self);
        switch (self.*) {
            .array => |arr| {
                arr.elements.deinit(alloc);
                alloc.free(arr.name);
            },
            .structure => |name| {
                alloc.free(name);
            },
            else => {},
        }
    }
};

test "parse_primitives" {
    const table = .{
        .{ .in = "bool", .expect = .bool },
        .{ .in = "int8", .expect = .int8 },
        .{ .in = "int16", .expect = .int16 },
        .{ .in = "int32", .expect = .int32 },
        .{ .in = "int64", .expect = .int64 },
        .{ .in = "uint16", .expect = .uint16 },
        .{ .in = "uint32", .expect = .uint32 },
        .{ .in = "uuid", .expect = .uuid },
        .{ .in = "float64", .expect = .float64 },
        .{ .in = "string", .expect = .string },
        .{ .in = "bytes", .expect = .bytes },
        .{ .in = "data", .expect = .data },
        .{ .in = "records", .expect = .records },
        .{ .in = "response", .expect = .response },
        .{ .in = "request", .expect = .request },
        .{ .in = "header", .expect = .header },
    };
    inline for (table) |case| {
        const parsed = try Ti.parse(case.in, std.testing.allocator);
        defer parsed.deinit(std.testing.allocator);
        try std.testing.expectEqual(case.expect, parsed.*);
    }

    const my_array = try Ti.parse("[]MyStruct", std.testing.allocator);
    defer my_array.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("[]MyStruct", my_array.array.name);

    try std.testing.expectError(error.BadPrimitive, Ti.parse("structure", std.testing.allocator));
    try std.testing.expectError(error.BadPrimitive, Ti.parse("array", std.testing.allocator));
}

test "parse_struct" {
    const table = .{
        .{ .in = "foo", .expect_error = null },
        .{ .in = "fooBar", .expect_error = null },
        .{ .in = "fooBar1", .expect_error = null },
        .{ .in = "MyStruct", .expect_error = null },
        .{ .in = "MyStruct_", .expect_error = @as(?anyerror, error.BadStructIdent) },
    };
    inline for (table) |case| {
        const got = Ti.parse(case.in, std.testing.allocator);
        if (case.expect_error) |err| {
            try std.testing.expectError(err, got);
        } else {
            const parsed = try got;
            defer parsed.deinit(std.testing.allocator);
            try std.testing.expectEqualStrings(case.in, parsed.structure);
        }
    }
}

test "parse_array" {
    const table = .{
        .{ .in = "[]foo", .expect_error = null },
        .{ .in = "[]fooBar", .expect_error = null },
        .{ .in = "[]fooBar1", .expect_error = null },
        .{ .in = "[]MyStruct", .expect_error = null },
        .{ .in = "[]MyStruct_", .expect_error = @as(?anyerror, error.BadStructIdent) },
        .{ .in = "[]structure", .expect_error = @as(?anyerror, error.BadPrimitive) },
        .{ .in = "[]array", .expect_error = @as(?anyerror, error.BadPrimitive) },
    };
    inline for (table) |case| {
        const got = Ti.parse(case.in, std.testing.allocator);
        if (case.expect_error) |err| {
            try std.testing.expectError(err, got);
        } else {
            const parsed = try got;
            defer parsed.deinit(std.testing.allocator);
            try std.testing.expectEqualStrings(case.in, parsed.array.name);
        }
    }
}

test "zig_type" {
    try std.testing.expectEqualStrings("bool", @as(Ti, .bool).zigType().?);
    try std.testing.expectEqualStrings("i8", @as(Ti, .int8).zigType().?);
    try std.testing.expectEqualStrings("i16", @as(Ti, .int16).zigType().?);
    try std.testing.expectEqualStrings("i32", @as(Ti, .int32).zigType().?);
    try std.testing.expectEqualStrings("i64", @as(Ti, .int64).zigType().?);
    try std.testing.expectEqualStrings("u16", @as(Ti, .uint16).zigType().?);
    try std.testing.expectEqualStrings("u32", @as(Ti, .uint32).zigType().?);
    try std.testing.expectEqualStrings("[16]u8", @as(Ti, .uuid).zigType().?);
    try std.testing.expectEqualStrings("f64", @as(Ti, .float64).zigType().?);
    try std.testing.expectEqualStrings("[]const u8", @as(Ti, .string).zigType().?);
    try std.testing.expectEqualStrings("[]u8", @as(Ti, .bytes).zigType().?);

    try std.testing.expectEqualStrings("[]Pera", @as(Ti, .{ .array = .{ .name = "[]Pera", .elements = undefined } }).zigType().?);
    try std.testing.expectEqualStrings("MyStruct", @as(Ti, .{ .structure = "MyStruct" }).zigType().?);

    try std.testing.expectEqual(null, @as(Ti, .records).zigType());
    try std.testing.expectEqual(null, @as(Ti, .header).zigType());
    try std.testing.expectEqual(null, @as(Ti, .request).zigType());
    try std.testing.expectEqual(null, @as(Ti, .response).zigType());
}

fn clearComments(src: []const u8, alloc: Allocator) ![]const u8 {
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

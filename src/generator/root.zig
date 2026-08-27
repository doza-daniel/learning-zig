const std = @import("std");

const json = std.json;
const Allocator = std.mem.Allocator;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;

const Field = struct {
    type: *TypeInfo,
    name: []const u8,
    versions: VersionInfo,
    nullableVersions: ?VersionInfo = null,
    flexibleVersions: ?VersionInfo = null,
    fields: []Field = &.{},
};

const Msg = struct {
    apiKey: i16 = 0,
    type: *TypeInfo,
    name: []const u8,
    validVersions: VersionInfo,
    flexibleVersions: ?VersionInfo = null,
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

const formatter = struct {
    writer: *Writer,

    fn versioned(self: @This(), v: VersionInfo, comptime fmt: []const u8, args: anytype) !void {
        const should_close = generateIf(v, self.writer) catch |err| switch (err) {
            error.VersionNone => return,
            else => return err,
        };
        try self.writer.print(fmt, args);
        if (should_close) {
            try self.writer.print("}}\n", .{});
        }
    }

    fn versionedBlock(self: @This(), v: VersionInfo, field: Field, f: *const fn (*Writer, Field) anyerror!void) !void {
        const should_close = generateIf(v, self.writer) catch |err| switch (err) {
            error.VersionNone => return,
            else => return err,
        };
        try f(self.writer, field);
        if (should_close) {
            try self.writer.print("}}\n", .{});
        }
    }
};

fn generateIf(v: VersionInfo, w: *Writer) !bool {
    return switch (v) {
        .none => error.VersionNone,
        .exact => |version| {
            try w.print("if (version == {d}) {{", .{version});
            return true;
        },
        .range => |r| {
            if (r.min == 0 and r.max == null) {
                return false;
            }
            try w.print("if (", .{});
            if (r.min > 0) {
                try w.print("version >= {d}", .{r.min});
            }
            const logical_op = if (r.min > 0) " and " else "";
            if (r.max) |max| {
                try w.print("{s}version <= {d}", .{ logical_op, max });
            }
            try w.print(") {{\n", .{});
            return true;
        },
    };
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

            try out.print("pub fn isFlexible(version: i16) bool {{", .{});
            if (T.flexibleVersions) |flexi| switch (flexi) {
                .none => {},
                else => {
                    const fmt: formatter = .{ .writer = out };
                    try fmt.versioned(flexi, "return true;\n", .{});
                },
            };
            try out.print("return false;\n", .{});
            try out.print("}}\n", .{});
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
        // this should in theory recurse until leaf structure and find all the
        // structs along the way, but can't be bothered
        switch (field.type.*) {
            .structure => try q.pushBack(alloc, field),
            .array => |arr| switch (arr.elements.*) {
                .structure => try q.pushBack(alloc, field),
                else => {},
            },
            else => {},
        }
        try out.print("{s}: {s},\n", .{ field.name, field.type.zigType().? });
    }

    try out.print("pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {{\n", .{});
    for (T.fields) |field| {
        const v = field.versions;
        const fmt: formatter = .{ .writer = out };
        switch (field.type.*) {
            .bool => {
                try fmt.versioned(v, "self.{s} = try reader.readBool();\n", .{field.name});
            },
            .int8 => {
                try fmt.versioned(v, "self.{s} = try reader.readInt(i8);\n", .{field.name});
            },
            .int16 => {
                try fmt.versioned(v, "self.{s} = try reader.readInt(i16);\n", .{field.name});
            },
            .int32 => {
                try fmt.versioned(v, "self.{s} = try reader.readInt(i32);\n", .{field.name});
            },
            .int64 => {
                try fmt.versioned(v, "self.{s} = try reader.readInt(i64);\n", .{field.name});
            },
            .uint16 => {
                try fmt.versioned(v, "self.{s} = try reader.readInt(u16);\n", .{field.name});
            },
            .uint32 => {
                try fmt.versioned(v, "self.{s} = try reader.readInt(u32);\n", .{field.name});
            },
            .uuid => {
                try fmt.versioned(v, "self.{s} = try reader.readUuid();\n", .{field.name});
            },
            .float64 => {
                try fmt.versioned(v, "self.{s} = try reader.readFloat64();\n", .{field.name});
            },
            .string => {
                // TODO: flex + nullable
                try fmt.versioned(v, "self.{s} = try reader.readString(alloc);\n", .{field.name});
            },
            .bytes => {
                // TODO: flex + nullable
                try fmt.versioned(v, "self.{s} = try reader.readBytes(alloc);\n", .{field.name});
            },
            // TODO: flex + nullable
            .array => |arr| {
                try fmt.versioned(v, "self.{s} = try reader.readArray({s},alloc);\n", .{ field.name, arr.elements.zigType().? });
            },
            .structure => {
                try fmt.versioned(v, "try self.{s}.read(reader, alloc);\n", .{field.name});
            },
            .records => {
                try fmt.versionedBlock(v, field, struct {
                    fn call(w: *Writer, f: Field) !void {
                        // TODO: flex + nullable
                        try w.print("var bytes = try reader.readBytes(alloc);\n", .{});
                        try w.print("defer alloc.free(bytes);\n", .{});
                        try w.print("var record_reader: Reader = .{{.src = &bytes}};\n", .{});
                        try w.print("try self.{s}.read(&record_reader, alloc);\n", .{f.name});
                    }
                }.call);
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

const VersionInfo = union(enum) {
    none: void,
    exact: u4,
    range: struct {
        min: u4,
        max: ?u4 = null,
    },

    fn parse(str: []const u8) !VersionInfo {
        if (str.len == 0 or std.ascii.eqlIgnoreCase(str, "none")) {
            return .none;
        }

        if (str[str.len - 1] == '+') {
            return .{
                .range = .{
                    .min = try std.fmt.parseInt(u4, str[0 .. str.len - 1], 10),
                },
            };
        }

        if (std.ascii.findIgnoreCase(str, "-")) |i| {
            return .{
                .range = .{
                    .min = try std.fmt.parseInt(u4, str[0..i], 10),
                    .max = try std.fmt.parseInt(u4, str[i + 1 ..], 10),
                },
            };
        }

        return .{ .exact = try std.fmt.parseInt(u4, str, 10) };
    }

    pub fn jsonParse(alloc: Allocator, source: anytype, opts: std.json.ParseOptions) !@This() {
        return switch (try source.nextAllocMax(alloc, .alloc_always, opts.max_value_len.?)) {
            .allocated_string => |s| {
                return try VersionInfo.parse(s);
            },
            else => unreachable,
        };
    }
};

const TypeInfo = union(enum) {
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
        elements: *TypeInfo,
    },
    structure: []const u8,

    fn zigType(self: TypeInfo) ?[]const u8 {
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

    fn parse(str: []const u8, alloc: Allocator) !*TypeInfo {
        const result = try alloc.create(TypeInfo);
        errdefer alloc.destroy(result);

        if (std.meta.stringToEnum(std.meta.Tag(TypeInfo), str)) |tag| {
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
                return (TypeInfo.parse(s, alloc) catch unreachable).*;
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
        const parsed = try TypeInfo.parse(case.in, std.testing.allocator);
        defer parsed.deinit(std.testing.allocator);
        try std.testing.expectEqual(case.expect, parsed.*);
    }

    const my_array = try TypeInfo.parse("[]MyStruct", std.testing.allocator);
    defer my_array.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("[]MyStruct", my_array.array.name);

    try std.testing.expectError(error.BadPrimitive, TypeInfo.parse("structure", std.testing.allocator));
    try std.testing.expectError(error.BadPrimitive, TypeInfo.parse("array", std.testing.allocator));
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
        const got = TypeInfo.parse(case.in, std.testing.allocator);
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
        const got = TypeInfo.parse(case.in, std.testing.allocator);
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
    try std.testing.expectEqualStrings("bool", @as(TypeInfo, .bool).zigType().?);
    try std.testing.expectEqualStrings("i8", @as(TypeInfo, .int8).zigType().?);
    try std.testing.expectEqualStrings("i16", @as(TypeInfo, .int16).zigType().?);
    try std.testing.expectEqualStrings("i32", @as(TypeInfo, .int32).zigType().?);
    try std.testing.expectEqualStrings("i64", @as(TypeInfo, .int64).zigType().?);
    try std.testing.expectEqualStrings("u16", @as(TypeInfo, .uint16).zigType().?);
    try std.testing.expectEqualStrings("u32", @as(TypeInfo, .uint32).zigType().?);
    try std.testing.expectEqualStrings("[16]u8", @as(TypeInfo, .uuid).zigType().?);
    try std.testing.expectEqualStrings("f64", @as(TypeInfo, .float64).zigType().?);
    try std.testing.expectEqualStrings("[]const u8", @as(TypeInfo, .string).zigType().?);
    try std.testing.expectEqualStrings("[]u8", @as(TypeInfo, .bytes).zigType().?);

    try std.testing.expectEqualStrings("[]Pera", @as(TypeInfo, .{ .array = .{ .name = "[]Pera", .elements = undefined } }).zigType().?);
    try std.testing.expectEqualStrings("MyStruct", @as(TypeInfo, .{ .structure = "MyStruct" }).zigType().?);

    try std.testing.expectEqual(null, @as(TypeInfo, .records).zigType());
    try std.testing.expectEqual(null, @as(TypeInfo, .header).zigType());
    try std.testing.expectEqual(null, @as(TypeInfo, .request).zigType());
    try std.testing.expectEqual(null, @as(TypeInfo, .response).zigType());
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

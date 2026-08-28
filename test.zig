const std = @import("std");

const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;

const gen = @import("src/generator/root.zig");

pub fn main(init: std.process.Init) !void {
    const versions: gen.VersionInfo = .{ .range = .{ .min = 3 } };
    const nullableVersions: gen.VersionInfo = .{ .range = .{ .min = 5, .max = 7 } };
    const flexibleVersions: gen.VersionInfo = .{ .range = .{ .min = 6, .max = 8 } };

    const field_name: []const u8 = "some_field";

    const if_nullable: *Expr = try .makeIf(
        init.gpa,
        .{ .version = nullableVersions },
        try .makeLeaf(init.gpa, "self.{s} = try reader.readNullableString();\n", .{field_name}),
        try .makeLeaf(init.gpa, "self.{s} = try reader.readString();\n", .{field_name}),
    );
    const if_nullable_compact: *Expr = try .makeIf(
        init.gpa,
        .{ .version = nullableVersions },
        try .makeLeaf(init.gpa, "self.{s} = try reader.readCompactNullableString();\n", .{field_name}),
        try .makeLeaf(init.gpa, "self.{s} = try reader.readCompactString();\n", .{field_name}),
    );
    const if_flexi: *Expr = try .makeIf(
        init.gpa,
        .{ .version = flexibleVersions },
        if_nullable_compact,
        if_nullable,
    );
    const if_version: *Expr = try .makeIf(
        init.gpa,
        .{ .version = versions },
        if_flexi,
        null,
    );
    defer if_version.deinit(init.gpa);

    var out: Writer.Allocating = .init(init.gpa);
    defer out.deinit();
    try if_version.render(&out.writer);
    std.debug.print("{s}", .{out.written()});
}

const Condition = union(enum) {
    version: gen.VersionInfo,
    literal: []const u8,

    pub fn render(self: Condition, out: *Writer) !void {
        switch (self) {
            .version => |vi| switch (vi) {
                .exact => |exact| try out.print("version == {d}", .{exact}),
                .range => |range| {
                    var err: bool = true;
                    if (range.min > 0) {
                        try out.print("version >= {d}", .{range.min});
                        err = false;
                    }
                    if (range.max) |max| {
                        try out.print("{s}version <= {d}", .{ if (!err) " and " else "", max });
                        err = false;
                    }
                    if (err) {
                        return error.AlwaysTrue;
                    }
                },
                .none => return error.AlwaysFalse,
            },
            .literal => |str| try out.print("{s}", .{str}),
        }
    }
};

const Expr = union(enum) {
    If: struct {
        Cond: Condition,
        True: *Expr,
        False: ?*Expr,
    },
    Leaf: []const u8,

    fn makeIf(gpa: Allocator, c: Condition, t: *Expr, f: ?*Expr) !*Expr {
        const ptr = try gpa.create(Expr);
        ptr.* = .{ .If = .{ .Cond = c, .True = t, .False = f } };
        return ptr;
    }

    fn makeLeaf(gpa: Allocator, comptime fmt: []const u8, args: anytype) !*Expr {
        const ptr = try gpa.create(Expr);
        ptr.* = .{ .Leaf = try std.fmt.allocPrint(gpa, fmt, args) };
        return ptr;
    }

    fn render(self: @This(), writer: *Writer) !void {
        switch (self) {
            .If => |e| {
                var buff: [1024]u8 = undefined;
                var w: Writer = .fixed(&buff);
                e.Cond.render(&w) catch |err| {
                    return switch (err) {
                        error.AlwaysTrue => try e.True.render(writer),
                        error.AlwaysFalse => if (e.False) |f| try f.render(writer),
                        else => err,
                    };
                };

                try writer.print("if ({s}) {{\n", .{w.buffered()});

                try e.True.render(writer);
                if (e.False) |f| {
                    try writer.print("}} else {{\n", .{});
                    try f.render(writer);
                }
                try writer.print("}}\n", .{});
            },
            .Leaf => |e| {
                try writer.writeAll(e);
            },
        }
    }

    fn deinit(self: *@This(), gpa: Allocator) void {
        defer gpa.destroy(self);
        switch (self.*) {
            .If => |e| {
                e.True.deinit(gpa);
                if (e.False) |f| f.deinit(gpa);
            },
            .Leaf => |e| gpa.free(e),
        }
    }
};

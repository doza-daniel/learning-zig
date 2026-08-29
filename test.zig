const std = @import("std");

const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;

const VersionInfo = @import("src/generator/root.zig").VersionInfo;

pub fn main(init: std.process.Init) !void {
    const versions: VersionInfo = .{ .range = .{ .min = 3 } };
    const nullableVersions: VersionInfo = .{ .range = .{ .min = 5, .max = 7 } };
    const flexibleVersions: VersionInfo = .{ .range = .{ .min = 6, .max = 8 } };

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
    try if_version.render(.{}, &out.writer);
    std.debug.print("{s}", .{out.written()});
}

const context = struct {
    min: i16 = 0,
    max: i16 = std.math.maxInt(i16),

    fn make(c: Condition) context {
        return switch (c) {
            .version => |v| switch (v) {
                .range => |range| .{ .min = range.min, .max = range.max orelse std.math.maxInt(i16) },
                else => .{},
            },
            else => .{},
        };
    }
};

const Condition = union(enum) {
    version: VersionInfo,
    literal: []const u8,

    pub fn render(self: Condition, ctx: context, out: *Writer) !void {
        switch (self) {
            .version => |vi| switch (vi) {
                .exact => |exact| {
                    if (exact < ctx.min or exact > ctx.max) {
                        return error.AlwaysFalse;
                    }
                    try out.print("version == {d}", .{exact});
                },
                .range => |range| {
                    var err: bool = true;

                    if (range.min > ctx.max) {
                        return error.AlwaysFalse;
                    }

                    if (range.min > ctx.min) {
                        try out.print("version >= {d}", .{range.min});
                        err = false;
                    }

                    if (range.max) |max| {
                        if (max < ctx.min) {
                            return error.AlwaysFalse;
                        }
                        if (max < ctx.max) {
                            const and_op = if (!err) " and " else "";
                            try out.print("{s}version <= {d}", .{ and_op, range.max.? });
                            err = false;
                        }
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

    fn render(self: @This(), ctx: context, writer: *Writer) !void {
        switch (self) {
            .If => |e| {
                var buff: [1024]u8 = undefined;
                var w: Writer = .fixed(&buff);
                e.Cond.render(ctx, &w) catch |err| {
                    return switch (err) {
                        error.AlwaysTrue => try e.True.render(ctx, writer),
                        error.AlwaysFalse => if (e.False) |f| try f.render(ctx, writer),
                        else => err,
                    };
                };

                const new_ctx: context = .make(e.Cond);

                try writer.print("if ({s}) {{\n", .{w.buffered()});

                try e.True.render(new_ctx, writer);
                if (e.False) |f| {
                    try writer.print("}} else {{\n", .{});
                    try f.render(new_ctx, writer);
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

test "if literal" {
    const gpa = std.testing.allocator;
    const if_lit: *Expr = try .makeIf(gpa, .{ .literal = "cond" }, try .makeLeaf(gpa, "foo", .{}), try .makeLeaf(gpa, "bar", .{}));
    defer if_lit.deinit(gpa);
    var buff: [300]u8 = undefined;
    var out: Writer = .fixed(&buff);
    try if_lit.render(.{}, &out);
    try std.testing.expectEqualStrings("if (cond) {\nfoo} else {\nbar}\n", out.buffered());
}

test "if version - exact" {
    const gpa = std.testing.allocator;
    const version_info: VersionInfo = .{ .exact = 10 };
    const if_lit: *Expr = try .makeIf(gpa, .{ .version = version_info }, try .makeLeaf(gpa, "foo", .{}), try .makeLeaf(gpa, "bar", .{}));
    defer if_lit.deinit(gpa);
    var buff: [300]u8 = undefined;
    var out: Writer = .fixed(&buff);
    try if_lit.render(.{}, &out);
    try std.testing.expectEqualStrings("if (version == 10) {\nfoo} else {\nbar}\n", out.buffered());
}

test "if version - exact - out of range - left" {
    const gpa = std.testing.allocator;
    const version_info: VersionInfo = .{ .exact = 10 };
    const if_lit: *Expr = try .makeIf(gpa, .{ .version = version_info }, try .makeLeaf(gpa, "foo", .{}), try .makeLeaf(gpa, "bar", .{}));
    defer if_lit.deinit(gpa);
    var buff: [300]u8 = undefined;
    var out: Writer = .fixed(&buff);
    try if_lit.render(.{ .min = 11, .max = 12 }, &out);
    try std.testing.expectEqualStrings("bar", out.buffered());
}

test "if version - exact - out of range - right" {
    const gpa = std.testing.allocator;
    const version_info: VersionInfo = .{ .exact = 13 };
    const if_lit: *Expr = try .makeIf(gpa, .{ .version = version_info }, try .makeLeaf(gpa, "foo", .{}), try .makeLeaf(gpa, "bar", .{}));
    defer if_lit.deinit(gpa);
    var buff: [300]u8 = undefined;
    var out: Writer = .fixed(&buff);
    try if_lit.render(.{ .min = 11, .max = 12 }, &out);
    try std.testing.expectEqualStrings("bar", out.buffered());
}

test "if version - exact - out of range - empty" {
    const gpa = std.testing.allocator;
    const version_info: VersionInfo = .{ .exact = 13 };
    const if_lit: *Expr = try .makeIf(gpa, .{ .version = version_info }, try .makeLeaf(gpa, "foo", .{}), null);
    defer if_lit.deinit(gpa);
    var buff: [300]u8 = undefined;
    var out: Writer = .fixed(&buff);
    try if_lit.render(.{ .min = 11, .max = 12 }, &out);
    try std.testing.expectEqualStrings("", out.buffered());
}

test "if version - range full" {
    const gpa = std.testing.allocator;
    const version_info: VersionInfo = .{ .range = .{ .min = 10, .max = 20 } };
    const if_lit: *Expr = try .makeIf(gpa, .{ .version = version_info }, try .makeLeaf(gpa, "foo", .{}), try .makeLeaf(gpa, "bar", .{}));
    defer if_lit.deinit(gpa);
    var buff: [300]u8 = undefined;
    var out: Writer = .fixed(&buff);
    try if_lit.render(.{}, &out);
    try std.testing.expectEqualStrings("if (version >= 10 and version <= 20) {\nfoo} else {\nbar}\n", out.buffered());
}

test "if version - range only min" {
    const gpa = std.testing.allocator;
    const version_info: VersionInfo = .{ .range = .{ .min = 10 } };
    const if_lit: *Expr = try .makeIf(gpa, .{ .version = version_info }, try .makeLeaf(gpa, "foo", .{}), try .makeLeaf(gpa, "bar", .{}));
    defer if_lit.deinit(gpa);
    var buff: [300]u8 = undefined;
    var out: Writer = .fixed(&buff);
    try if_lit.render(.{}, &out);
    try std.testing.expectEqualStrings("if (version >= 10) {\nfoo} else {\nbar}\n", out.buffered());
}

test "if version - none (with else)" {
    const gpa = std.testing.allocator;
    const version_info: VersionInfo = .none;
    const if_lit: *Expr = try .makeIf(gpa, .{ .version = version_info }, try .makeLeaf(gpa, "foo", .{}), try .makeLeaf(gpa, "bar", .{}));
    defer if_lit.deinit(gpa);
    var buff: [300]u8 = undefined;
    var out: Writer = .fixed(&buff);
    try if_lit.render(.{}, &out);
    try std.testing.expectEqualStrings("bar", out.buffered());
}

test "if version - none (no else)" {
    const gpa = std.testing.allocator;
    const version_info: VersionInfo = .none;
    const if_lit: *Expr = try .makeIf(gpa, .{ .version = version_info }, try .makeLeaf(gpa, "foo", .{}), null);
    defer if_lit.deinit(gpa);
    var buff: [300]u8 = undefined;
    var out: Writer = .fixed(&buff);
    try if_lit.render(.{}, &out);
    try std.testing.expectEqualStrings("", out.buffered());
}

test "if version - always true - min" {
    const gpa = std.testing.allocator;
    const version_info: VersionInfo = .{ .range = .{ .min = 5 } };
    const if_lit: *Expr = try .makeIf(gpa, .{ .version = version_info }, try .makeLeaf(gpa, "foo", .{}), try .makeLeaf(gpa, "bar", .{}));
    defer if_lit.deinit(gpa);
    var buff: [300]u8 = undefined;
    var out: Writer = .fixed(&buff);
    try if_lit.render(.{ .min = 5 }, &out);
    try std.testing.expectEqualStrings("foo", out.buffered());
}

test "if version - always true - min and max" {
    const gpa = std.testing.allocator;
    const version_info: VersionInfo = .{ .range = .{ .min = 5, .max = 10 } };
    const if_lit: *Expr = try .makeIf(gpa, .{ .version = version_info }, try .makeLeaf(gpa, "foo", .{}), try .makeLeaf(gpa, "bar", .{}));
    defer if_lit.deinit(gpa);
    var buff: [300]u8 = undefined;
    var out: Writer = .fixed(&buff);
    try if_lit.render(.{ .min = 5, .max = 10 }, &out);
    try std.testing.expectEqualStrings("foo", out.buffered());
}

test "if version - nested if - range left" {
    const gpa = std.testing.allocator;
    const version_inner: VersionInfo = .{ .range = .{ .min = 2, .max = 4 } };
    const version_outer: VersionInfo = .{ .range = .{ .min = 5, .max = 10 } };
    const if_inner: *Expr = try .makeIf(gpa, .{ .version = version_inner }, try .makeLeaf(gpa, "foo", .{}), try .makeLeaf(gpa, "bar", .{}));
    const if_lit: *Expr = try .makeIf(gpa, .{ .version = version_outer }, if_inner, null);
    defer if_lit.deinit(gpa);
    var buff: [300]u8 = undefined;
    var out: Writer = .fixed(&buff);
    try if_lit.render(.{}, &out);
    try std.testing.expectEqualStrings("if (version >= 5 and version <= 10) {\nbar}\n", out.buffered());
}

test "if version - nested if - range left - touching" {
    const gpa = std.testing.allocator;
    const version_inner: VersionInfo = .{ .range = .{ .min = 2, .max = 5 } };
    const version_outer: VersionInfo = .{ .range = .{ .min = 5, .max = 10 } };
    const if_inner: *Expr = try .makeIf(gpa, .{ .version = version_inner }, try .makeLeaf(gpa, "foo", .{}), null);
    const if_lit: *Expr = try .makeIf(gpa, .{ .version = version_outer }, if_inner, null);
    defer if_lit.deinit(gpa);
    var buff: [300]u8 = undefined;
    var out: Writer = .fixed(&buff);
    try if_lit.render(.{}, &out);
    try std.testing.expectEqualStrings("if (version >= 5 and version <= 10) {\nif (version <= 5) {\nfoo}\n}\n", out.buffered());
}

test "if version - nested if - range left - intersect" {
    const gpa = std.testing.allocator;
    const version_inner: VersionInfo = .{ .range = .{ .min = 2, .max = 6 } };
    const version_outer: VersionInfo = .{ .range = .{ .min = 5, .max = 10 } };
    const if_inner: *Expr = try .makeIf(gpa, .{ .version = version_inner }, try .makeLeaf(gpa, "foo", .{}), null);
    const if_lit: *Expr = try .makeIf(gpa, .{ .version = version_outer }, if_inner, null);
    defer if_lit.deinit(gpa);
    var buff: [300]u8 = undefined;
    var out: Writer = .fixed(&buff);
    try if_lit.render(.{}, &out);
    try std.testing.expectEqualStrings("if (version >= 5 and version <= 10) {\nif (version <= 6) {\nfoo}\n}\n", out.buffered());
}

test "if version - nested if - range inside - touching left" {
    const gpa = std.testing.allocator;
    const version_inner: VersionInfo = .{ .range = .{ .min = 5, .max = 7 } };
    const version_outer: VersionInfo = .{ .range = .{ .min = 5, .max = 10 } };
    const if_inner: *Expr = try .makeIf(gpa, .{ .version = version_inner }, try .makeLeaf(gpa, "foo", .{}), null);
    const if_lit: *Expr = try .makeIf(gpa, .{ .version = version_outer }, if_inner, null);
    defer if_lit.deinit(gpa);
    var buff: [300]u8 = undefined;
    var out: Writer = .fixed(&buff);
    try if_lit.render(.{}, &out);
    try std.testing.expectEqualStrings("if (version >= 5 and version <= 10) {\nif (version <= 7) {\nfoo}\n}\n", out.buffered());
}

test "if version - nested if - range inside - sub" {
    const gpa = std.testing.allocator;
    const version_inner: VersionInfo = .{ .range = .{ .min = 6, .max = 7 } };
    const version_outer: VersionInfo = .{ .range = .{ .min = 5, .max = 10 } };
    const if_inner: *Expr = try .makeIf(gpa, .{ .version = version_inner }, try .makeLeaf(gpa, "foo", .{}), null);
    const if_lit: *Expr = try .makeIf(gpa, .{ .version = version_outer }, if_inner, null);
    defer if_lit.deinit(gpa);
    var buff: [300]u8 = undefined;
    var out: Writer = .fixed(&buff);
    try if_lit.render(.{}, &out);
    try std.testing.expectEqualStrings("if (version >= 5 and version <= 10) {\nif (version >= 6 and version <= 7) {\nfoo}\n}\n", out.buffered());
}

test "if version - nested if - range inside - touching right" {
    const gpa = std.testing.allocator;
    const version_inner: VersionInfo = .{ .range = .{ .min = 6, .max = 10 } };
    const version_outer: VersionInfo = .{ .range = .{ .min = 5, .max = 10 } };
    const if_inner: *Expr = try .makeIf(gpa, .{ .version = version_inner }, try .makeLeaf(gpa, "foo", .{}), null);
    const if_lit: *Expr = try .makeIf(gpa, .{ .version = version_outer }, if_inner, null);
    defer if_lit.deinit(gpa);
    var buff: [300]u8 = undefined;
    var out: Writer = .fixed(&buff);
    try if_lit.render(.{}, &out);
    try std.testing.expectEqualStrings("if (version >= 5 and version <= 10) {\nif (version >= 6) {\nfoo}\n}\n", out.buffered());
}

test "if version - nested if - range right - interset" {
    const gpa = std.testing.allocator;
    const version_inner: VersionInfo = .{ .range = .{ .min = 6, .max = 11 } };
    const version_outer: VersionInfo = .{ .range = .{ .min = 5, .max = 10 } };
    const if_inner: *Expr = try .makeIf(gpa, .{ .version = version_inner }, try .makeLeaf(gpa, "foo", .{}), null);
    const if_lit: *Expr = try .makeIf(gpa, .{ .version = version_outer }, if_inner, null);
    defer if_lit.deinit(gpa);
    var buff: [300]u8 = undefined;
    var out: Writer = .fixed(&buff);
    try if_lit.render(.{}, &out);
    try std.testing.expectEqualStrings("if (version >= 5 and version <= 10) {\nif (version >= 6) {\nfoo}\n}\n", out.buffered());
}

test "if version - nested if - range right - touching right" {
    const gpa = std.testing.allocator;
    const version_inner: VersionInfo = .{ .range = .{ .min = 10, .max = 11 } };
    const version_outer: VersionInfo = .{ .range = .{ .min = 5, .max = 10 } };
    const if_inner: *Expr = try .makeIf(gpa, .{ .version = version_inner }, try .makeLeaf(gpa, "foo", .{}), null);
    const if_lit: *Expr = try .makeIf(gpa, .{ .version = version_outer }, if_inner, null);
    defer if_lit.deinit(gpa);
    var buff: [300]u8 = undefined;
    var out: Writer = .fixed(&buff);
    try if_lit.render(.{}, &out);
    try std.testing.expectEqualStrings("if (version >= 5 and version <= 10) {\nif (version >= 10) {\nfoo}\n}\n", out.buffered());
}

test "if version - nested if - range right" {
    const gpa = std.testing.allocator;
    const version_inner: VersionInfo = .{ .range = .{ .min = 11, .max = 12 } };
    const version_outer: VersionInfo = .{ .range = .{ .min = 5, .max = 10 } };
    const if_inner: *Expr = try .makeIf(gpa, .{ .version = version_inner }, try .makeLeaf(gpa, "foo", .{}), try .makeLeaf(gpa, "bar", .{}));
    const if_lit: *Expr = try .makeIf(gpa, .{ .version = version_outer }, if_inner, null);
    defer if_lit.deinit(gpa);
    var buff: [300]u8 = undefined;
    var out: Writer = .fixed(&buff);
    try if_lit.render(.{}, &out);
    try std.testing.expectEqualStrings("if (version >= 5 and version <= 10) {\nbar}\n", out.buffered());
}

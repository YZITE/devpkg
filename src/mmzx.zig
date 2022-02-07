const builtin = @import("builtin");
const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

// "stolen" from "zig/lib/std/mem.zig", to replace "const T" with "T"
fn SplitIterator(comptime T: type) type {
    return struct {
        buffer: []T,
        index: ?usize,
        delimiter: []const T,

        const Self = @This();

        /// Returns a slice of the next field, or null if splitting is complete.
        pub fn next(self: *Self) ?[]T {
            const start = self.index orelse return null;
            const end = if (std.mem.indexOfPos(T, self.buffer, start, self.delimiter)) |delim_start| blk: {
                self.index = delim_start + self.delimiter.len;
                break :blk delim_start;
            } else blk: {
                self.index = null;
                break :blk self.buffer.len;
            };
            return self.buffer[start..end];
        }

        /// Returns a slice of the remaining bytes. Does not affect iterator state.
        pub fn rest(self: Self) []const T {
            const end = self.buffer.len;
            const start = self.index orelse end;
            return self.buffer[start..end];
        }
    };
}

const knownExts: []const []const u8 = &[2][]const u8 {
    "avi",
    "jpg",
  };

fn normalizeExt(name: []u8) ?[]u8 {
  var iter = SplitIterator(u8) {
    .index = 0,
    .buffer = name,
    .delimiter = ".",
  };
  var last_item: ?[]u8 = null;
  while (iter.next()) |item| last_item = item;
  const ret = last_item orelse return null;
  for (ret) |*c| {
    if (c.* >= 'A' and c.* <= 'Z')
      c.* += 'a' - 'A';
  }
  return ret;
}

fn hasKnownExt(ext: []const u8) bool {
  for (knownExts) |ext2|
    if (std.mem.eql(u8, ext, ext2))
      return true;
  return false;
}

fn lcs(comptime t: type, items: []const []const t) []const t {
  if (items.len == 0) {
    const EMPTY: [0]t = .{};
    return EMPTY[0..];
  }
  var ret = items[0];
  for (items[1..]) |item| {
    for (item) |c, i| {
      if (i >= ret.len) break;
      if (ret[i] != c) {
        ret = ret[0..i];
        break;
      }
    }
    if (ret.len == 0) break;
  }
  return ret;
}

test "lcs" {
  const a: []const []const u8 = &.{
    "allemam",
    "allem",
    "allex",
    "allexifiy",
    "allexa",
  };
  try testing.expectEqualSlices(u8, "alle", lcs(u8, a));
  const b: []const []const u8 = &.{"allemam", "allex", "b", "bonk"};
  try testing.expectEqualSlices(u8, "", lcs(u8, b));
}

const NameEnt = struct {
  orig_name: []const u8,
  name: []const u8,

  pub fn deinit(self: *@This(), allocator: Allocator) void {
    allocator.free(self.orig_name);
    allocator.free(self.name);
  }
};

fn runOnDir(
  allocator: Allocator,
  dir: std.fs.Dir,
  path: *std.ArrayList(u8),
  writer: anytype,
) anyerror!void {
  var names = std.ArrayList(NameEnt).init(allocator);
  defer {
    for (names.items) |*item| item.deinit(allocator);
    names.deinit();
  }
  var iter = dir.iterate();
  while (try iter.next()) |item| {
    if (item.name.len == 0 or item.name[0] == '.') {
      // skip hidden items
      continue;
    }
    if (dir.openDir(item.name, .{
      .iterate = true,
    })) |*dir2| {
      const opl = path.items.len;
      (try path.addOne()).* = std.fs.path.sep;
      try path.appendSlice(item.name);
      defer dir2.close();
      try runOnDir(allocator, dir2.*, path, writer);
      if (path.items.len <= opl) unreachable;
      try path.resize(opl);
    } else |err| {
      switch (err) {
        error.NotDir => {},
        error.FileNotFound => continue,
        else => return err,
      }
      // we got a file
      const dup_name_old = try allocator.dupe(u8, item.name);
      var dup_name = try allocator.dupe(u8, item.name);
      // do this to avoid special-casing 'continue'
      var dup_name_reg = false;
      defer {
        if (!dup_name_reg) {
          allocator.free(dup_name_old);
          allocator.free(dup_name);
        }
      }
      const ext = normalizeExt(dup_name);
      if (ext == null or !hasKnownExt(ext.?))
        continue;
      var fh = dir.openFile(item.name, .{}) catch |err2| {
        switch (err2) {
          error.FileNotFound => continue,
          else => return err2,
        }
      };
      const S = std.os.system.S;
      if (builtin.os.tag != .windows) {
        fh.chmod(S.IRUSR | S.IWUSR | S.IRGRP | S.IROTH) catch |err2| {
          try writer.print("CHM {s}{c}{s} ERR {p}", .{ path.items, std.fs.path.sep, dup_name, err2 });
        };
      }
      (try names.addOne()).* = .{
        .orig_name = dup_name_old,
        .name = dup_name,
      };
      dup_name_reg = true;
    }
  }

  // prune prefix
  var lcs_: []const u8 = undefined;
  {
    var tmp = try allocator.alloc([]const u8, names.items.len);
    defer allocator.free(tmp);
    for (names.items) |item, i| {
      tmp[i] = item.name;
    }
    lcs_ = lcs(u8, tmp);
  }

  for (names.items) |item| {
    const old_name = item.orig_name;
    const new_name = item.name[(lcs_.len)..];
    if (std.mem.eql(u8, old_name, new_name) or new_name.len == 0) continue;
    try writer.print("MV {s}: {s} -> {s}\n", .{ path.items, old_name, new_name });
    try dir.rename(old_name, new_name);
  }
}

pub fn main() !void {
  var stderr = std.io.getStdErr().writer();
  var gpa = std.heap.GeneralPurposeAllocator(.{}){};
  const allocator = gpa.allocator();
  defer {
    const leaked = gpa.deinit();
    if (leaked) {
      std.debug.print("-ERR- detected memory leak", .{});
    }
  }
  var path = std.ArrayList(u8).init(allocator);
  defer path.deinit();

  var d = try std.fs.cwd().openDir(".", .{ .iterate = true });
  defer d.close();

  var arena = std.heap.ArenaAllocator.init(allocator);
  defer arena.deinit();

  try runOnDir(
    arena.allocator(),
    d,
    &path,
    stderr,
  );
}

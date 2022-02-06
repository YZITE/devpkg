const std = @import("std");

pub const Aver = struct {
  vol: u64,
  accu: f64,

  const Self = @This();

  pub fn value(self: *const Self) f64 {
    return self.accu / @intToFloat(f64, self.vol);
  }

  pub fn update(self: *Self, nval: f64) void {
    self.vol += 1;
    self.accu += nval;
  }
};

fn expeq(a: f64, b: f64) !void {
  try std.testing.expectEqual(a, b);
}

test "aver" {
  var a = Aver {
    .vol = 0,
    .accu = 0,
  };
  try std.testing.expectEqual(true, std.math.isNan(a.value()));

  a.update(10.0); try expeq(10.0, a.value());
  a.update(0.0);  try expeq(5.0, a.value());
  a.update(2.0);  try expeq(4.0, a.value());
}

pub fn RoundRobinAver(
  comptime logsize: comptime_int,
) type {
  return struct {
    accu: [logsize]f64,
    pos: u32,

    const Self = @This();

    pub const default = Self {
      .accu = .{ 0 } ** logsize,
      .pos = 0,
    };

    pub fn value(self: *const Self) f64 {
      @setFloatMode(.Optimized);
      var ret: f64 = 0.0;
      for (self.accu) |item| {
        ret += item;
      }
      return ret / @intToFloat(f64, self.accu.len);
    }

    pub fn update(self: *Self, nval: f64) void {
      if (self.pos >= logsize) unreachable;
      self.accu[self.pos] = nval;
      self.pos = (self.pos + 1) % logsize;
    }
  };
}

test "rraver" {
  const Rra = RoundRobinAver(3);
  var a = Rra.default;
  try expeq(0.0, a.value());

  a.update(12.0); try expeq(4.0, a.value());
  a.update(3.0);  try expeq(5.0, a.value());
  a.update(6.0);  try expeq(7.0, a.value());
  a.update(9.0);  try expeq(6.0, a.value());
}

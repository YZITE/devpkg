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

pub const RoundRobinAver = struct {
  accu: []f64,
  pos: usize,

  const Self = @This();

  pub fn value(self: *const Self) f64 {
    @setFloatMode(.Optimized);
    var ret: f64 = 0.0;
    for (self.accu) |item| {
      ret += item;
    }
    return ret / @intToFloat(f64, self.accu.len);
  }

  pub fn update(self: *Self, nval: f64) void {
    self.pos %= self.accu.len;
    self.accu[self.pos] = nval;
    self.pos += 1;
  }
};

test "rraver" {
  var abk: [3]f64 = .{0.0} ** 3;
  var a = RoundRobinAver {
    .accu = &abk,
    .pos = 0,
  };
  try expeq(0.0, a.value());

  a.update(12.0); try expeq(4.0, a.value());
  a.update(3.0);  try expeq(5.0, a.value());
  a.update(6.0);  try expeq(7.0, a.value());
  a.update(9.0);  try expeq(6.0, a.value());
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const dvui = @import("dvui");

pub const CellState = enum(u8) {
    unk,
    filled,
    empty,
};

pub const Grid = struct {
    w: usize,
    h: usize,
    cells: []CellState,

    const Self = @This();

    pub fn init(gpa: Allocator, w: usize, h: usize) !Self {
        var self = Self{
            .w = w,
            .h = h,
            .cells = try gpa.alloc(CellState, w * h),
        };
        self.setAll(.unk);
        return self;
    }

    pub fn deinit(self: *Self, gpa: Allocator) void {
        gpa.free(self.cells);
    }

    pub fn clone(self: Self, gpa: Allocator) !Self {
        return Self{
            .w = self.w,
            .h = self.h,
            .cells = try gpa.dupe(CellState, self.cells),
        };
    }

    inline fn index(self: Self, x: usize, y: usize) usize {
        return y * self.w + x;
    }

    pub fn setAll(self: *Self, state: CellState) void {
        @memset(self.cells, state);
    }

    /// return cell really changed or not
    pub fn set(self: *Self, x: usize, y: usize, state: CellState) bool {
        defer self.cells[self.index(x, y)] = state;
        return self.cells[self.index(x, y)] != state;
    }

    pub fn get(self: Self, x: usize, y: usize) CellState {
        return self.data[self.index(x, y)];
    }

    pub fn getLine(self: Self, line_index: usize, line_buff: []CellState) []CellState {
        if (line_index < self.h) {
            const res = line_buff[0..self.w];
            @memcpy(res, @as([*]CellState, @ptrCast(&self.cells[line_index * self.w])));
            return res;
        } else {
            const res = line_buff[0..self.h];
            const x = line_index - self.h;
            for (0..self.h) |y| {
                res[y] = self.cells[self.index(x, y)];
            }
            return res;
        }
    }

    pub fn countUnknown(self: *Self) usize {
        var res: usize = 0;
        for (self.cells) |c| {
            if (c == .unk) res += 1;
        }
        return res;
    }
};

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Grid = @import("data.zig").Grid;
const CellState = @import("data.zig").CellState;

const LineStack = struct {
    data: []usize,
    len: usize,

    pub fn init(gpa: Allocator, len: usize) !@This() {
        return .{
            .data = try gpa.alloc(usize, len),
            .len = 0,
        };
    }

    pub fn deinit(self: @This(), gpa: Allocator) void {
        gpa.free(self.data);
    }

    pub fn add(self: *@This(), line: usize) void {
        for (self.data) |l| if (l == line) return;
        self.data[self.len] = line;
        self.len += 1;
    }

    pub fn pop(self: *@This()) usize {
        self.len -= 1;
        return self.data[self.len];
    }
};

pub fn sortStack(gpa: Allocator, grid: *const Grid, rules: []const []const usize, stack: *LineStack) !void {
    const Ctx = struct {
        grid: *const Grid,
        rules: []const []const usize,
        line_buff: []CellState,
        fn cmp(ctx: @This(), line1: usize, line2: usize) bool {
            const l1 = flexibility(ctx.grid.getLine(line1, ctx.line_buff), ctx.rules[line1]);
            const l2 = flexibility(ctx.grid.getLine(line2, ctx.line_buff), ctx.rules[line2]);
            return l1 > l2;
        }

        fn flexibility(line: []const CellState, rule: []const usize) usize {
            var res: usize = line.len + 1 - rule.len;
            for (rule) |r| res -= r;
            return res;
        }
    };
    const ctx = Ctx{
        .grid = grid,
        .rules = rules,
        .line_buff = try gpa.alloc(CellState, @max(grid.w, grid.h)),
    };
    std.sort.pdq(usize, stack.data[0..stack.len], ctx, Ctx.cmp);
}

pub const SolveState = union(enum) {
    unknown,
    success,
    rule_line_sum_fail: usize,
    rule_total_sum_fail,
    multi_solution,
    fail,
};

pub fn checkRules(grid_w: usize, grid_h: usize, rules: []const []const usize) SolveState {
    var hsum: usize = 0;
    var vsum: usize = 0;
    for (rules, 0..) |rule, i| {
        var line_sum: usize = 0;
        for (rule) |r| line_sum += r;
        if (i < grid_h) {
            if (line_sum + rule.len > grid_w + 1) return .{ .rule_line_sum_fail = i };
            hsum += line_sum;
        } else {
            if (line_sum + rule.len > grid_h + 1) return .{ .rule_line_sum_fail = i };
            vsum += line_sum;
        }
    }
    if (hsum == vsum) {
        return .{ .success = {} };
    } else {
        return .{ .rule_total_sum_fail = {} };
    }
}

pub fn solve(gpa: Allocator, grid: *Grid, rules: []const []const usize) !SolveState {
    switch (checkRules(grid.w, grid.h, rules)) {
        .success => {},
        else => |s| return s,
    }

    return solve0(gpa, grid, rules, null);
}

fn solve0(gpa: Allocator, grid: *Grid, rules: []const []const usize, hint: ?[]const usize) !SolveState {
    const w = grid.w;
    const h = grid.h;

    var stack = try LineStack.init(gpa, w + h);
    defer stack.deinit(gpa);

    if (hint) |hint_| {
        for (hint_) |l| stack.add(l);
    } else {
        // add all lines to stack
        for (0..w + h) |l| stack.add(l);
        try sortStack(gpa, grid, rules, &stack);
    }

    const line_buff = try gpa.alloc(CellState, @max(w, h));
    defer gpa.free(line_buff);
    const res_buff1 = try gpa.alloc(usize, @max(w, h));
    defer gpa.free(res_buff1);
    const res_buff2 = try gpa.alloc(usize, @max(w, h));
    defer gpa.free(res_buff2);

    // do fast solve if stack not empty
    while (stack.len > 0) {
        const curr_line = stack.pop();

        const line = grid.getLine(curr_line, line_buff);
        const rule = rules[curr_line];

        const dir: enum { h, v } = if (curr_line < h) .h else .v;
        const line_len = if (dir == .h) w else h;
        const line_index = if (dir == .h) curr_line else curr_line - h;

        const space1 = res_buff1[0 .. rule.len + 1];
        const space2 = res_buff2[0 .. rule.len + 1];

        if (try getLineSolution(gpa, .first, line, rule, space1) and
            try getLineSolution(gpa, .last, line, rule, space2))
        {} else {
            return .fail;
        }

        var seg1: usize = 0;
        var seg2: usize = 0;
        var block_index1: usize = 0;
        var space_index1: usize = 0;
        var block_index2: usize = 0;
        var space_index2: usize = 0;
        var is_space1: bool = true;
        var is_space2: bool = true;
        for (0..line_len) |i| {
            if (is_space1 and seg1 == space1[space_index1]) {
                seg1 = 0;
                space_index1 += 1;
                is_space1 = !is_space1;
            } else if (!is_space1 and seg1 == rule[block_index1]) {
                seg1 = 0;
                block_index1 += 1;
                is_space1 = !is_space1;
            }

            if (is_space2 and seg2 == space2[space_index2]) {
                seg2 = 0;
                space_index2 += 1;
                is_space2 = !is_space2;
            } else if (!is_space2 and seg2 == rule[block_index2]) {
                seg2 = 0;
                block_index2 += 1;
                is_space2 = !is_space2;
            }

            if (is_space1 and is_space2 and space_index1 == space_index2) {
                if (dir == .h) {
                    if (grid.set(i, line_index, .empty)) stack.add(i + h);
                } else {
                    if (grid.set(line_index, i, .empty)) stack.add(i);
                }
            } else if (!is_space1 and !is_space2 and block_index1 == block_index2) {
                if (dir == .h) {
                    if (grid.set(i, line_index, .filled)) stack.add(i + h);
                } else {
                    if (grid.set(line_index, i, .filled)) stack.add(i);
                }
            }

            seg1 += 1;
            seg2 += 1;
        }
    }

    const unk_num = grid.countUnknown();
    if (unk_num > 0) {
        var grid_copy1 = try grid.clone(gpa);
        defer grid_copy1.deinit(gpa);
        var grid_copy2 = try grid.clone(gpa);
        defer grid_copy2.deinit(gpa);

        var y: usize = 0;
        var x: usize = 0;
        for (grid.cells, 0..) |c, i| { // find first unknown cell and guess
            if (c == .unk) {
                grid_copy1.cells[i] = .filled;
                const s1 = try solve0(gpa, &grid_copy1, rules, &[2]usize{ h + x, y });
                grid_copy2.cells[i] = .empty;
                const s2 = try solve0(gpa, &grid_copy2, rules, &[2]usize{ h + x, y });

                if ((s1 == .multi_solution or s2 == .multi_solution) or (s1 == .success and s2 == .success)) {
                    if (s1 != .fail and s2 != .fail) {
                        for (grid_copy1.cells, grid_copy2.cells, grid.cells) |c1, c2, *c0| {
                            c0.* = if (c1 == c2) c1 else .unk;
                        }
                    }
                    return .multi_solution;
                }
                if (s1 == .fail and s2 == .fail) return .fail;
                if (s1 == .success) {
                    @memcpy(grid.cells, grid_copy1.cells);
                } else {
                    @memcpy(grid.cells, grid_copy2.cells);
                }
            }
            x += 1;
            if (x == w) {
                x = 0;
                y += 1;
            }
        }
    }

    return .success;
}

pub fn getLineSolution(gpa: Allocator, typ: enum { first, last }, line: []const CellState, rule: []const usize, res_space: []usize) !bool {
    if (rule.len == 0) {
        for (line) |c| {
            if (c == .filled) return false;
        }
        res_space[0] = line.len;
        return true;
    }
    if (typ == .last) {
        const rev_line = try gpa.alloc(CellState, line.len);
        defer gpa.free(rev_line);
        for (line, 0..) |c, i| rev_line[rev_line.len - 1 - i] = c;

        const rev_rule = try gpa.alloc(usize, rule.len);
        defer gpa.free(rev_rule);
        for (rule, 0..) |r, i| rev_rule[rev_rule.len - 1 - i] = r;

        if (!getLineFirstSolution0(rev_line, rev_rule, 0, 0, res_space)) return false;
    } else {
        if (!getLineFirstSolution0(line, rule, 0, 0, res_space)) return false;
    }

    var remaining_space = line.len;
    for (rule) |r| remaining_space -= r;
    for (res_space[0..rule.len]) |s| remaining_space -= s;
    res_space[rule.len] = remaining_space;

    if (typ == .last) std.mem.reverse(usize, res_space);
    return true;
}

fn getLineFirstSolution0(line: []const CellState, rule: []const usize, index: usize, start: usize, space: []usize) bool {
    const len = rule[index];
    var head = start;
    // need a space if this is not first block
    if (index > 0) head += 1;

    var tail = head;
    var have_filled = false;

    while (head < line.len) {
        switch (line[head]) {
            .empty => {
                if (have_filled) return false; // cannot skip a filled cell
                head += 1;
                tail = head;
                continue;
            },
            .filled => have_filled = true,
            else => {},
        }

        // check space long enough
        if (head - tail + 1 != len) {
            head += 1;
            continue;
        }

        // current space can fit this block, do more check
        success: {
            if (head < line.len - 1 and line[head + 1] == .filled) break :success;
            if (index == rule.len - 1) {
                // this is the last block
                if (head != line.len - 1) {
                    // check any filled cell unused
                    for (line[head + 1 ..]) |c| {
                        if (c == .filled) break :success;
                    }
                }
            } else if (!getLineFirstSolution0(line, rule, index + 1, head + 1, space)) {
                // remaining blocks cannot fit
                break :success;
            }
            // success
            space[index] = tail - start;
            return true;
        }

        if (line[tail] == .filled) return false; // can not miss a filled cell
        head += 1;
        tail += 1;
    }

    return false;
}

fn test_getLineFirstSolution(line: []const CellState, rule: []const usize, expected_space: ?[]const usize) !void {
    const testing = std.testing;
    const res_space = try testing.allocator.alloc(usize, rule.len + 1);
    defer testing.allocator.free(res_space);
    const succ = try getLineSolution(testing.allocator, .first, line, rule, res_space);

    if (expected_space == null) {
        try testing.expect(!succ);
    } else {
        try testing.expect(succ);
        try testing.expectEqualSlices(usize, expected_space.?, res_space);
    }
}

test "getLineFirstSolution" {
    {
        const line = [_]CellState{
            .unk,
            .unk,
            .empty,
            .unk,
            .unk,
        };

        try test_getLineFirstSolution(&line, &[_]usize{ 1, 1 }, &[_]usize{ 0, 2, 1 });
        try test_getLineFirstSolution(&line, &[_]usize{2}, &[_]usize{ 0, 3 });
        try test_getLineFirstSolution(&line, &[_]usize{3}, null);
    }

    {
        const line = [_]CellState{
            .unk,
            .unk,
            .empty,
            .unk,
            .filled,
        };

        try test_getLineFirstSolution(&line, &[_]usize{ 1, 1 }, &[_]usize{ 0, 3, 0 });
        try test_getLineFirstSolution(&line, &[_]usize{1}, &[_]usize{ 4, 0 });
        try test_getLineFirstSolution(&line, &[_]usize{2}, &[_]usize{ 3, 0 });
        try test_getLineFirstSolution(&line, &[_]usize{3}, null);
    }

    {
        const line = [_]CellState{
            .unk,
            .filled,
            .unk,
            .unk,
            .filled,
        };

        try test_getLineFirstSolution(&line, &[_]usize{ 1, 1 }, &[_]usize{ 1, 2, 0 });
        try test_getLineFirstSolution(&line, &[_]usize{ 2, 2 }, &[_]usize{ 0, 1, 0 });
        try test_getLineFirstSolution(&line, &[_]usize{3}, null);
        try test_getLineFirstSolution(&line, &[_]usize{4}, &[_]usize{ 1, 0 });
        try test_getLineFirstSolution(&line, &[_]usize{5}, &[_]usize{ 0, 0 });
    }
}

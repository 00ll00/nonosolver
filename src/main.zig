const std = @import("std");
const ArrayListManaged = std.array_list.Managed;
const ArrayList = std.ArrayList;
const SourceLocation = std.builtin.SourceLocation;
const Allocator = std.mem.Allocator;

const dvui = @import("dvui");
const Direction = dvui.enums.Direction;

const numlist = @import("numlist.zig");

pub const allocator = std.heap.smp_allocator;
pub const main = dvui.App.main;
pub const dvui_app = dvui.App{
    .config = .{
        .options = .{
            .size = .{ .w = 500, .h = 500 },
            .min_size = .all(150),
            .title = "nonosolver",
            .gpa = allocator,
        },
    },
    .initFn = appInit,
    .frameFn = appFrame,
    .deinitFn = appDeinit,
};

pub fn appInit(win: *dvui.Window) !void {
    _ = win;
}

pub fn appDeinit() void {
    global_grid.deinit(allocator);
}

var inited = false;
var grid_w: usize = 10;
var grid_h: usize = 10;
var global_grid: Grid = .{ .w = 0, .h = 0, .cells = &[0]CellState{} };
var global_rules: ArrayListManaged(ArrayListManaged(usize)) = .init(allocator);
var solve_state: solver.SolveState = .unknown;
var time: ?i64 = null;

pub fn initGrid(gpa: Allocator, w: ?usize, h: ?usize) !void {
    if (w) |w_| grid_w = w_;
    if (h) |h_| grid_h = h_;

    global_grid.deinit(gpa);
    global_grid = try Grid.init(gpa, grid_w, grid_h);

    for (global_rules.items) |r| r.deinit();
    global_rules.clearRetainingCapacity();

    try global_rules.appendNTimes(.init(gpa), grid_w + grid_h);
}

pub fn appFrame() !dvui.App.Result {
    if (try menu()) |res| return res;

    const sc = dvui.scrollArea(@src(), .{ .horizontal = .auto, .vertical = .auto }, .{ .expand = .both });
    defer sc.deinit();

    if (!inited) {
        dvui.label(@src(), "columns:", .{}, .{});
        _ = dvui.textEntryNumber(@src(), usize, .{ .value = &grid_w, .min = 1 }, .{});
        dvui.label(@src(), "rolls:", .{}, .{});
        _ = dvui.textEntryNumber(@src(), usize, .{ .value = &grid_h, .min = 1 }, .{});
        if (dvui.button(@src(), "init", .{}, .{})) {
            try initGrid(allocator, null, null);
            inited = true;
        }
    } else {
        try drawGrid(@src(), .{ .cell_size = 30 }, .{});
    }

    return .ok;
}

pub fn menu() !?dvui.App.Result {
    var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .style = .window, .background = true, .expand = .horizontal });
    defer hbox.deinit();

    var m = dvui.menu(@src(), .horizontal, .{});
    defer m.deinit();

    if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .tag = "first-focusable" })) |r| {
        var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
        defer fw.deinit();

        if (inited and dvui.menuItemLabel(@src(), "clear", .{}, .{ .expand = .horizontal }) != null) {
            inited = true;
            solve_state = .unknown;
            @memset(global_grid.cells, .unk);
            m.close();
        }

        if (dvui.menuItemLabel(@src(), "reset", .{}, .{ .expand = .horizontal }) != null) {
            inited = false;
            solve_state = .unknown;
            m.close();
        }

        if (inited and dvui.menuItemLabel(@src(), "save", .{}, .{ .expand = .horizontal }) != null) {
            if (dvui.dialogNativeFileSave(allocator, .{ .path = "./", .title = "save game data", .filters = &[_][]const u8{".json"} }) catch null) |path| {
                saveData(path) catch {};
            }
            m.close();
        }

        if (dvui.menuItemLabel(@src(), "load", .{}, .{ .expand = .horizontal }) != null) {
            if (dvui.dialogNativeFileOpen(allocator, .{ .path = "./", .title = "load game data", .filters = &[_][]const u8{".json"} }) catch null) |path| {
                loadData(path) catch return null;
                inited = true;
                solve_state = .unknown;
            }
            m.close();
        }
    }

    if (@import("builtin").mode == .Debug) {
        if (dvui.menuItemLabel(@src(), "Debug", .{ .submenu = true }, .{})) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();

            if (dvui.menuItemLabel(@src(), "show debug window", .{}, .{ .expand = .horizontal }) != null) {
                dvui.toggleDebugWindow();
                m.close();
            }

            if (dvui.menuItemLabel(@src(), "show examples", .{}, .{ .expand = .horizontal }) != null) {
                dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
                m.close();
            }
        }
        dvui.Examples.demo(.full);
    }

    if (inited) {
        const box1 = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer box1.deinit();

        if (dvui.menuItemLabel(@src(), "Run!", .{ .submenu = false }, .{ .font = .{ .weight = .bold } }) != null) {
            global_grid.setAll(.unk);
            const rule_slice = try allocator.alloc([]usize, global_rules.items.len);
            defer allocator.free(rule_slice);
            for (global_rules.items, rule_slice) |r1, *r2| {
                r2.* = r1.items;
            }

            const t1 = std.Io.Timestamp.now(dvui.io, .boot);
            solve_state = try solver.solve(allocator, &global_grid, rule_slice);
            const t2 = std.Io.Timestamp.now(dvui.io, .boot);
            time = t1.durationTo(t2).toMicroseconds();
        }

        switch (solve_state) {
            .success => if (time) |t| dvui.label(@src(), "solved in {d}ms", .{t}, .{ .gravity_y = 0.5, .color_text = comptime .fromHex("8c8") }),
            .fail => dvui.label(@src(), "failed to solve", .{}, .{ .gravity_y = 0.5, .color_text = comptime .fromHex("c33") }),
            .multi_solution => dvui.label(@src(), "multiple solutions", .{}, .{ .gravity_y = 0.5, .color_text = comptime .fromHex("8cc") }),
            .rule_line_sum_fail => dvui.label(@src(), "rule not fit grid size", .{}, .{ .gravity_y = 0.5, .color_text = comptime .fromHex("c8c") }),
            .rule_total_sum_fail => dvui.label(@src(), "rule sum check fail", .{}, .{ .gravity_y = 0.5, .color_text = comptime .fromHex("c8c") }),
            .unknown => dvui.label(@src(), "ready to solve", .{}, .{ .gravity_y = 0.5, .color_text = comptime .fromHex("888") }),
        }
    }

    return null;
}

const data = @import("data.zig");
const Grid = data.Grid;
const CellState = data.CellState;

const GridInitOption = struct {
    cell_size: f32 = 30,
    enabled: bool = true,
};

const solver = @import("solver.zig");

fn drawGrid(src: SourceLocation, init_opt: GridInitOption, opts: dvui.Options) !void {
    const box = dvui.box(src, .{ .dir = .vertical }, opts.override(.{
        .gravity_x = 0.5,
        .gravity_y = 0.5,
    }));
    defer box.deinit();

    const w = global_grid.w;
    const h = global_grid.h;
    const cell_size = init_opt.cell_size;

    {
        const box1 = dvui.box(@src(), .{ .dir = .horizontal }, opts);
        defer box1.deinit();

        var max_w: usize = 0;
        for (global_rules.items[0..h]) |rule| {
            max_w = @max(max_w, rule.items.len);
        }
        max_w += 1;

        _ = dvui.spacer(@src(), .{ .min_size_content = .{ .w = @as(f32, @floatFromInt(max_w)) * cell_size } });

        for (global_rules.items[h..], 0..) |*rule, i| {
            try numlist.numList(@src(), .{
                .cell_size = cell_size,
                .data = rule,
                .dir = .vertical,
                .enabled = init_opt.enabled,
            }, opts.override(.{
                .id_extra = i,
                .gravity_y = 1,
            }));
        }
    }

    {
        const box1 = dvui.box(@src(), .{ .dir = .horizontal }, opts);
        defer box1.deinit();

        {
            const box2 = dvui.box(@src(), .{ .dir = .vertical }, opts);
            defer box2.deinit();

            for (global_rules.items[0..h], 0..) |*rule, i| {
                try numlist.numList(@src(), .{
                    .cell_size = cell_size,
                    .data = rule,
                    .dir = .horizontal,
                    .enabled = init_opt.enabled,
                }, opts.override(.{
                    .id_extra = i,
                    .gravity_x = 1,
                }));
            }
        }

        {
            const fb = dvui.flexbox(@src(), .{}, opts.override(.{
                .min_size_content = .{ .w = @as(f32, @floatFromInt(w)) * cell_size, .h = @as(f32, @floatFromInt(h)) * cell_size },
                .max_size_content = .{ .w = @as(f32, @floatFromInt(w)) * cell_size, .h = @as(f32, @floatFromInt(h)) * cell_size },
            }));
            defer fb.deinit();

            const font_size = opts.fontGet().size;
            const border = 1;
            const content_size = font_size + 1;
            const padding = (cell_size - content_size) / 2 - border;

            for (global_grid.cells, 0..) |*c, i| {
                if (switch (c.*) {
                    .unk => dvui.labelClick(@src(), "?", .{}, .{}, opts.override(.{
                        .id_extra = i,
                        .tab_index = 0,
                        .min_size_content = .all(content_size),
                        .max_size_content = .all(content_size),
                        .border = .all(border),
                        .padding = .all(padding),
                        .background = true,
                        .color_fill = opts.color(.fill).lerp(.white, 0.3),
                        .color_text = opts.color(.fill).lerp(.yellow, 0.5),
                    })),
                    .empty => dvui.labelClick(@src(), "", .{}, .{}, opts.override(.{
                        .id_extra = i,
                        .tab_index = 0,
                        .min_size_content = .all(content_size),
                        .max_size_content = .all(content_size),
                        .border = .all(border),
                        .padding = .all(padding),
                        .background = true,
                        .color_fill = opts.color(.fill).lerp(.white, 0.3),
                    })),
                    .filled => dvui.labelClick(@src(), "", .{}, .{}, opts.override(.{
                        .id_extra = i,
                        .tab_index = 0,
                        .min_size_content = .all(content_size),
                        .max_size_content = .all(content_size),
                        .border = .all(border),
                        .padding = .all(padding),
                        .background = true,
                        .color_fill = opts.color(.fill).lerp(.black, 0.3),
                    })),
                }) {
                    var s = @intFromEnum(c.*);
                    s += 1;
                    if (s >= @typeInfo(CellState).@"enum".fields.len) s = 0;
                    c.* = @enumFromInt(s);
                }
            }
        }
    }
}

fn saveData(path: []const u8) !void {
    _ = path;
    dvui.toast(@src(), .{ .message = "Not Implemented..." });
    return error.NotImplemented;
}

fn loadData(path: []const u8) !void {
    _ = path;
    dvui.toast(@src(), .{ .message = "Not Implemented..." });
    return error.NotImplemented;
}

test "all" {
    _ = solver;
}

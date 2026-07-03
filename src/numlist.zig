const std = @import("std");
const ArrayListManaged = std.array_list.Managed;
const SourceLocation = std.builtin.SourceLocation;

const dvui = @import("dvui");
const Direction = dvui.enums.Direction;

pub const NumListInitOptions = struct {
    data: *ArrayListManaged(usize),
    dir: Direction,
    can_edit: bool = true,
    cell_size: f32,
    enabled: bool = true,
};

pub fn numList(src: SourceLocation, init_opts: NumListInitOptions, opts: dvui.Options) !void {
    const box = dvui.box(src, .{ .dir = init_opts.dir }, opts);
    defer box.deinit();

    const id = box.data().id;
    const nums = init_opts.data;
    const focus_editing = dvui.dataGetPtrDefault(null, id, "refresh_all", bool, false);
    const editing = dvui.dataGetPtrDefault(null, id, "editing", ?usize, null);
    const valid = dvui.dataGetPtrDefault(null, id, "valid", bool, true);
    const enabled = init_opts.enabled;
    var removing: ?usize = null;
    var adding: ?usize = null;
    const cell_size = init_opts.cell_size;

    if (dvui.button(src, "+", .{}, .{
        .id_extra = nums.items.len,
        .border = .all(1),
        .padding = .all(2),
        .margin = .all(5),
        .corner_radius = .all(100),
        .max_size_content = .all(cell_size - 16),
        .min_size_content = .all(cell_size - 16),
        .background = true,
        .color_text = opts.color(.text).lerp(.gray, 0.5),
    }) and enabled and adding == null) {
        adding = 0;
    }

    const padding = 3;
    const border: f32 = 1;
    const content_size = cell_size - 2 * (border + padding);

    for (nums.items, 0..) |*d, i| {
        const sub_src = @src();
        const wid = box.widget().extendId(sub_src, i);

        if (enabled and editing.* == i) {
            const text_entry = dvui.textEntry(sub_src, .{
                .multiline = false,
                .placeholder = "0",
            }, .{
                .id_extra = i,
                .border = .all(border),
                .max_size_content = .all(content_size),
                .min_size_content = .all(content_size),
                .corner_radius = .all(0),
                .padding = .all(padding),
                .margin = .all(0),
                .background = true,
                .color_fill = if (valid.*) null else opts.color(.fill).lerp(.red, 0.3),
            });
            defer text_entry.deinit();

            if (focus_editing.*) {
                dvui.focusWidget(wid, null, null);
                if (d.* > 0) {
                    var buffer: [20]u8 = undefined;
                    const text = std.fmt.bufPrint(&buffer, "{d}", .{d.*}) catch "";
                    text_entry.textSet(text, true);
                }
                focus_editing.* = false;
            }
            if (text_entry.text_changed) blk: {
                const value = std.fmt.parseInt(usize, text_entry.getText(), 0) catch {
                    valid.* = false;
                    break :blk;
                };
                valid.* = true;
                d.* = value;
            } else if (text_entry.enter_pressed or dvui.focusedWidgetId() != wid) {
                if (text_entry.getText().len == 0) {
                    d.* = 0;
                } else if (valid.* and text_entry.enter_pressed) {
                    editing.* = i + 1;
                    adding = i + 1;
                }
                editing.* = null;
                if (d.* == 0) {
                    removing = i;
                }
                valid.* = true;
            }
        } else {
            if (dvui.labelClick(sub_src, "{d}", .{d.*}, .{
                .label_opts = .{ .align_x = 0.5, .align_y = 0.5 },
            }, .{
                .id_extra = i,
                .background = true,
                .border = .all(border),
                .max_size_content = .all(content_size),
                .min_size_content = .all(content_size),
                .corner_radius = .all(0),
                .padding = .all(padding),
                .color_fill = opts.color(.fill).lerp(.white, 0.1),
            }) and enabled) {
                editing.* = i;
                focus_editing.* = true;
            }
        }
    }

    if (removing) |i| {
        _ = nums.orderedRemove(i);
        dvui.refresh(null, src, id);
    } else if (adding) |i| {
        try nums.insert(i, 0);
        focus_editing.* = true;
        editing.* = i;
        dvui.refresh(null, src, id);
    }
}

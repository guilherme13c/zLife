const std = @import("std");

const rl = @import("raylib");

const colormap = [_]rl.Color{
    rl.Color.red,
    rl.Color.green,
    rl.Color.blue,
    rl.Color.yellow,
    rl.Color.magenta,
    rl.Color.orange,
    rl.Color.purple,
    rl.Color.lime,
    rl.Color.brown,
    rl.Color.gold,
    rl.Color.pink,
};

const n = 100;
const screenSize: [2]u32 = .{ 800, 800 };
const type_count = 3;

const fps_target = 60;
const delta_t: f32 = 1.0 / @as(f32, @floatFromInt(fps_target));
const beta: f32 = 0.3;
const scaling_factor: f32 = 100.0;
const friction: f32 = std.math.pow(f32, 1.0 / 2.0, delta_t / 1);

const grid_cell_size: f32 = scaling_factor;
const grid_n_cells: [2]usize = .{
    @as(usize, @intFromFloat(screenSize[0] / grid_cell_size)),
    @as(usize, @intFromFloat(screenSize[1] / grid_cell_size)),
};

var grid: [grid_n_cells[0]][grid_n_cells[1]]std.ArrayList(usize) = undefined;

pub fn main() anyerror!void {
    rl.setTraceLogLevel(rl.TraceLogLevel.log_none);

    for (0..grid_n_cells[0]) |i| {
        for (0..grid_n_cells[1]) |j| {
            grid[i][j] = std.ArrayList(usize).init(std.heap.page_allocator);
        }
    }
    defer {
        for (0..grid_n_cells[0]) |i| {
            for (0..grid_n_cells[1]) |j| {
                grid[i][j].deinit();
            }
        }
    }

    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    var A: [type_count][type_count]f32 = undefined;

    for (0..type_count) |i| {
        for (0..type_count) |j| {
            A[i][j] = rand.floatNorm(f32);
        }
    }

    var positions: [2][n]i32 = undefined;
    var velocities: [2][n]f32 = undefined;
    var types: [n]u32 = undefined;
    for (0..n) |i| {
        positions[0][i] = rand.intRangeAtMost(i32, 0, screenSize[0]);
        positions[1][i] = rand.intRangeAtMost(i32, 0, screenSize[1]);
        velocities[0][i] = 0;
        velocities[1][i] = 0;
        types[i] = @intCast(i % type_count);
    }

    rl.initWindow(screenSize[0], screenSize[1], "zLife");
    defer rl.closeWindow();

    rl.setTargetFPS(fps_target);

    while (!rl.windowShouldClose()) {
        defer {
            for (0..grid_n_cells[0]) |i| {
                for (0..grid_n_cells[1]) |j| {
                    grid[i][j].clearAndFree();
                }
            }
        }

        for (0..n) |i| {
            var cell_x = @as(usize, @intFromFloat(@as(f32, @floatFromInt(positions[0][i])) / grid_cell_size));
            var cell_y = @as(usize, @intFromFloat(@as(f32, @floatFromInt(positions[1][i])) / grid_cell_size));

            if (cell_x >= grid_n_cells[0]) cell_x = grid_n_cells[0] - 1;
            if (cell_y >= grid_n_cells[1]) cell_y = grid_n_cells[1] - 1;

            try grid[cell_x][cell_y].append(i);
        }

        for (grid, 0..) |row, i| {
            for (row, 0..) |_, j| {
                const directions = [_][2]isize{
                    .{ -1, -1 },
                    .{ -1, 0 },
                    .{ -1, 1 },
                    .{ 0, -1 },
                    .{ 0, 0 },
                    .{ 0, 1 },
                    .{ 1, -1 },
                    .{ 1, 0 },
                    .{ 1, 1 },
                };

                for (grid[i][j].items) |p1_idx| {
                    var force: [2]f32 = .{ 0, 0 };

                    for (directions) |d| {
                        const cell_x = @as(usize, @intCast(try std.math.mod(isize, @as(isize, @intCast(i)) + d[0], @as(isize, @intCast(grid_n_cells[0])))));
                        const cell_y = @as(usize, @intCast(try std.math.mod(isize, @as(isize, @intCast(j)) + d[1], @as(isize, @intCast(grid_n_cells[1])))));

                        for (grid[cell_x][cell_y].items) |p2_idx| {
                            if (p1_idx == p2_idx) continue;

                            const d_temp: [2]i32 = .{
                                positions[0][p2_idx] - positions[0][p1_idx],
                                positions[1][p2_idx] - positions[1][p1_idx],
                            };

                            var displacement: [2]f32 = .{
                                if (@abs(@as(i32, @intCast(screenSize[0])) - d_temp[0]) > @abs(d_temp[0]))
                                    @floatFromInt(d_temp[0])
                                else
                                    @abs(@as(f32, @floatFromInt(@as(i32, @intCast(screenSize[0])) - d_temp[0]))),

                                if (@abs(@as(i32, @intCast(screenSize[1])) - d_temp[1]) > @abs(d_temp[1]))
                                    @floatFromInt(d_temp[1])
                                else
                                    @abs(@as(f32, @floatFromInt(@as(i32, @intCast(screenSize[1])) - d_temp[1]))),
                            };
                            const distance = std.math.sqrt(displacement[0] * displacement[0] + displacement[1] * displacement[1]);
                            const f = interaction(distance / scaling_factor, A[types[p1_idx]][types[p2_idx]]);

                            if (distance == 0) {
                                displacement = .{ 0, 0 };
                            } else {
                                displacement[0] /= distance;
                                displacement[1] /= distance;
                            }

                            force[0] += f * displacement[0];
                            force[1] += f * displacement[1];
                        }
                    }
                    velocities[0][p1_idx] *= friction;
                    velocities[1][p1_idx] *= friction;

                    velocities[0][p1_idx] += force[0];
                    velocities[1][p1_idx] += force[1];
                }
            }
        }

        for (0..n) |i| {
            positions[0][i] += std.math.lossyCast(i32, velocities[0][i] * delta_t);
            positions[1][i] += std.math.lossyCast(i32, velocities[1][i] * delta_t);

            positions[0][i] = try std.math.mod(i32, positions[0][i], screenSize[0]);
            positions[1][i] = try std.math.mod(i32, positions[1][i], screenSize[1]);
        }

        { // draw block
            rl.beginDrawing();
            defer rl.endDrawing();

            rl.clearBackground(rl.Color.black);

            for (1..grid_n_cells[0]) |i| {
                rl.drawLine(@as(i32, @intCast(i)) * @as(i32, @intFromFloat(grid_cell_size)), 0, @as(i32, @intCast(i)) * @as(i32, @intFromFloat(grid_cell_size)), screenSize[1], rl.Color.gray);
            }
            for (1..grid_n_cells[1]) |i| {
                rl.drawLine(0, @as(i32, @intCast(i)) * @as(i32, @intFromFloat(grid_cell_size)), screenSize[0], @as(i32, @intCast(i)) * @as(i32, @intFromFloat(grid_cell_size)), rl.Color.gray);
            }

            for (0..n) |i| {
                rl.drawCircle(positions[0][i], positions[1][i], 2, colormap[types[i]]);
            }

            rl.drawFPS(10, 10);
        }
    }
}

fn interaction(d: f32, a: f32) f32 {
    if (d < beta) {
        return (d / beta) - 1;
    } else if (d < 1) {
        return a * (1 - @abs(2 * d - 1 - beta) / (1 - beta));
    }
    return 0;
}

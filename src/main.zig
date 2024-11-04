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

const fps_target = 60;
const delta_t: f32 = 1.0 / @as(f32, @floatFromInt(fps_target));
const beta: f32 = 0.3;
const scaling_factor: f32 = 100.0;
const friction: f32 = std.math.pow(f32, 1.0 / 2.0, delta_t / 6);

pub fn main() anyerror!void {
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    const type_count = 6;
    var A: [type_count][type_count]f32 = undefined;

    for (0..type_count) |i| {
        for (0..type_count) |j| {
            A[i][j] = rand.floatNorm(f32) * 5;
        }
    }

    const n = 1000;

    const screenSize: [2]u32 = .{ 400, 400 };

    var positions: [2][n]i32 = undefined;
    var velocities: [2][n]f32 = undefined;
    var types: [n]u8 = undefined;
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
        rl.beginDrawing();
        defer rl.endDrawing();

        for (0..n) |i| {
            velocities[0][i] *= friction;
            velocities[1][i] *= friction;

            var force: [2]f32 = .{ 0, 0 };

            for (0..n) |j| {
                if (i == j) continue;

                var displacement: [2]f32 = [2]f32{
                    @floatFromInt(positions[0][j] - positions[0][i]),
                    @floatFromInt(positions[1][j] - positions[1][i]),
                };
                const distance = std.math.sqrt(displacement[0] * displacement[0] + displacement[1] * displacement[1]);
                const f = interaction(distance / scaling_factor, A[types[i]][types[j]]);

                displacement[0] /= distance;
                displacement[1] /= distance;

                force[0] += f * displacement[0];
                force[1] += f * displacement[1];
            }

            velocities[0][i] += force[0];
            velocities[1][i] += force[1];
        }

        for (0..n) |i| {
            positions[0][i] += std.math.lossyCast(i32, velocities[0][i] * delta_t);
            positions[1][i] += std.math.lossyCast(i32, velocities[1][i] * delta_t);

            positions[0][i] = try std.math.mod(i32, positions[0][i], screenSize[0]);
            positions[1][i] = try std.math.mod(i32, positions[1][i], screenSize[1]);
        }

        for (0..n) |i| {
            rl.drawCircle(positions[0][i], positions[1][i], 2, colormap[types[i]]);
        }

        rl.clearBackground(rl.Color.black);
    }
}

fn interaction(d: f32, a: f32) f32 {
    if (d < beta) {
        return (d / beta) - 1;
    } else if (d < 1) {
        return (a * (1 - @abs(2 * d - 1 - beta) / (1 - beta)));
    } else {
        return 0;
    }
}

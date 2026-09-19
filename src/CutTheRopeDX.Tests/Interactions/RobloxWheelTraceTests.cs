using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

using CutTheRopeDX.Framework.Core;
using CutTheRopeDX.GameMain;

using Xunit;

using static CutTheRopeDX.Framework.Helpers.CTRMathHelper;

namespace CutTheRopeDX.Tests.Interactions
{
    public sealed class RobloxWheelTraceTests
    {
        [Fact]
        public void ExportWheelGravityTrajectories()
        {
            string output = Environment.GetEnvironmentVariable("DX_ROBLOX_WHEEL_OUTPUT");
            if (string.IsNullOrEmpty(output))
            {
                return;
            }

            _ = HeadlessGame.Boot();
            List<object> runs = [];
            for (int pack = 7; pack <= 8; pack++)
            {
                for (int level = 1; level <= 25; level++)
                {
                    runs.Add(Run(pack, level, "idle", 120));
                }
            }

            runs.Add(Run(7, 1, "wheel", 480));
            runs.Add(Run(7, 8, "wheel", 360));
            runs.Add(Run(8, 1, "gravity", 240));
            runs.Add(Run(8, 4, "gravity", 240));
            runs.Add(Run(8, 9, "gravity", 240));
            runs.Add(Run(7, 1, "gravity", 240)); // Starts inside a bubble: buoyancy inversion.
            File.WriteAllText(output, JsonSerializer.Serialize(runs));
            Assert.Equal(56, runs.Count);
        }

        private static object Run(int pack, int level, string action, int ticks)
        {
            GameScene scene = HeadlessGame.LoadLevel(pack - 1, level - 1);
            for (int wait = 0; scene.IsIntroPanRunning() && wait < 1000; wait++)
            {
                scene.Update(1f / 60);
            }

            List<object> samples = [], actions = [];
            Grab wheel = scene.Grabs().FirstOrDefault(g => g.Wheel != null);
            float angle = 0;
            if (action == "wheel" && wheel != null)
            {
                _ = wheel.Wheel.TryBeginOperating(wheel, wheel.x + 90, wheel.y, 0);
            }

            for (int tick = 1; tick <= ticks; tick++)
            {
                if (action == "wheel" && wheel != null && tick >= 31)
                {
                    angle += tick < 220 ? -8 : 8;
                    float radians = angle * MathF.PI / 180;
                    Vector p = Vect(wheel.x + (90 * MathF.Cos(radians)), wheel.y + (90 * MathF.Sin(radians)));
                    wheel.Wheel.HandleRotate(wheel, p);
                    actions.Add(new { tick, x = p.X, y = p.Y });
                }
                if (action == "gravity" && (tick == 31 || tick == 85 || tick == 120 || tick == 125))
                {
                    scene.OnButtonPressed(0);
                }

                scene.Update(1f / 60);
                bool ended = scene.Candy().Lifecycle.ActiveBodies.Count == 0;
                if (tick == 1 || tick % 5 == 0 || ended)
                {
                    samples.Add(new
                    {
                        tick,
                        bodies = scene.Candy().Lifecycle.ActiveBodies.Select(b => new { x = b.Point.pos.X, y = b.Point.pos.Y, bubble = b.Bubble != null }).ToArray(),
                        ropes = scene.Grabs().Select(g => g.Rope == null ? null : new { parts = g.Rope.parts.Count, length = g.Rope.GetLength(), rest = g.Rope.tail.RestLengthFor(g.Rope.parts[^2]) }).ToArray()
                    });
                }
                // HeadlessGame has no menu controller for the delayed loss screen.
                // Record removal, then stop this route before that screen transition.
                if (ended)
                {
                    break;
                }
            }
            return new { pack, level, action, actions, samples };
        }
    }
}

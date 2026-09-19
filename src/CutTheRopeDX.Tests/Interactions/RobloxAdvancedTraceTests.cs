using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

using CutTheRopeDX.GameMain;

using Xunit;

namespace CutTheRopeDX.Tests.Interactions
{
    public sealed class RobloxAdvancedTraceTests
    {
        [Fact]
        public void ExportSpikeBeeTrajectories()
        {
            string output = Environment.GetEnvironmentVariable("DX_ROBLOX_ADVANCED_OUTPUT");
            if (string.IsNullOrEmpty(output))
            {
                return;
            }

            _ = HeadlessGame.Boot();
            List<object> runs = [];
            for (int pack = 9; pack <= 10; pack++)
            {
                for (int level = 1; level <= 25; level++)
                {
                    runs.Add(Run(pack, level, "idle", 120));
                }
            }

            foreach (int level in new[] { 1, 3, 9, 25 })
            {
                runs.Add(Run(9, level, "rotate", 360));
            }

            foreach (int level in new[] { 1, 8, 15, 25 })
            {
                runs.Add(Run(10, level, "bee", 600));
            }

            File.WriteAllText(output, JsonSerializer.Serialize(runs));
            Assert.Equal(58, runs.Count);
        }

        private static object Run(int pack, int level, string action, int ticks)
        {
            GameScene scene = HeadlessGame.LoadLevel(pack - 1, level - 1);
            for (int wait = 0; scene.IsIntroPanRunning() && wait < 1000; wait++)
            {
                scene.Update(1f / 60);
            }

            List<object> samples = [];
            for (int tick = 1; tick <= ticks; tick++)
            {
                if (action == "rotate" && (tick == 10 || tick == 16 || tick == 60 || tick == 90 || tick == 150))
                {
                    scene.RotateAllSpikesWithID(1);
                }

                if (action == "rotate" && (tick == 40 || tick == 80))
                {
                    scene.RotateAllSpikesWithID(2);
                }

                scene.Update(1f / 60);
                bool ended = scene.Candy().Lifecycle.ActiveBodies.Count == 0;
                if (tick == 1 || tick % 5 == 0 || ended)
                {
                    samples.Add(new
                    {
                        tick,
                        bodies = scene.Candy().Lifecycle.ActiveBodies.Select(b => new { x = b.Point.pos.X, y = b.Point.pos.Y, bubble = b.Bubble != null }).ToArray(),
                        grabs = scene.Grabs().Select(g => new { g.x, g.y, parts = g.Rope?.parts.Count ?? 0 }).ToArray(),
                        spikes = scene.SpikeStrips().Select(s => new { s.x, s.y, angle = s.rotation }).ToArray()
                    });
                }

                if (ended)
                {
                    break;
                }
            }
            return new { pack, level, action, samples };
        }
    }
}

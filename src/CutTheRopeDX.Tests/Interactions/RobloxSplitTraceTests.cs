using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

using CutTheRopeDX.GameMain;

using Xunit;

namespace CutTheRopeDX.Tests.Interactions
{
    public sealed class RobloxSplitTraceTests
    {
        [Fact]
        public void ExportSplitTrajectories()
        {
            string output = Environment.GetEnvironmentVariable("DX_ROBLOX_SPLIT_OUTPUT");
            if (string.IsNullOrEmpty(output))
            {
                return;
            }

            _ = HeadlessGame.Boot();
            List<object> runs = [];
            for (int pack = 5; pack <= 6; pack++)
            {
                for (int level = 1; level <= 25; level++)
                {
                    runs.Add(Run(pack, level, "idle", 120));
                }
            }

            runs.Add(Run(5, 1, "merge", 300));
            runs.Add(Run(6, 1, "bounce", 300));
            File.WriteAllText(output, JsonSerializer.Serialize(runs));
            Assert.Equal(52, runs.Count);
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
                if (action == "merge" && tick == 61) { scene.Grabs()[1].Rope.SetCut(0); scene.Grabs()[2].Rope.SetCut(0); }
                if (action == "merge" && tick == 181) { scene.Grabs()[0].Rope.SetCut(0); scene.Grabs()[3].Rope.SetCut(0); }
                if (action == "bounce" && tick == 61)
                {
                    scene.Grabs()[0].Rope.SetCut(0);
                }

                scene.Update(1f / 60);
                if (tick == 1 || tick % 5 == 0)
                {
                    CandyContext candy = scene.Candy();
                    samples.Add(new
                    {
                        tick,
                        split = candy.Lifecycle.Split != null,
                        bodies = candy.Lifecycle.ActiveBodies.Select(b => new { x = b.Point.pos.X, y = b.Point.pos.Y, bubble = b.Bubble != null }).ToArray(),
                        gone = scene.PrimaryCandyGone(),
                        stars = scene.Stars().Count
                    });
                }
            }
            return new { pack, level, action, samples };
        }
    }
}

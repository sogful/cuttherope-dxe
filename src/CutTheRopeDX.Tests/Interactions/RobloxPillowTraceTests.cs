using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

using CutTheRopeDX.GameMain;

using Xunit;

namespace CutTheRopeDX.Tests.Interactions
{
    public sealed class RobloxPillowTraceTests
    {
        [Fact]
        public void ExportPillowScenes()
        {
            string output = Environment.GetEnvironmentVariable("DX_ROBLOX_PILLOW_OUTPUT");
            if (string.IsNullOrEmpty(output))
            {
                return;
            }

            _ = HeadlessGame.Boot();
            List<object> runs = [];
            for (int level = 1; level <= 25; level++)
            {
                for (int mode = 0; mode < 3; mode++)
                {
                    runs.Add(Run(level, mode));
                }
            }

            File.WriteAllText(output, JsonSerializer.Serialize(runs));
            Assert.Equal(75, runs.Count);
        }
        private static object Run(int level, int mode)
        {
            GameScene scene = HeadlessGame.LoadLevel(15, level - 1);
            scene.gameSceneDelegate = new RecordingSceneDelegate();
            for (int wait = 0; scene.IsIntroPanRunning() && wait < 1000; wait++)
            {
                scene.Update(1f / 60);
            }

            CandyContext[] candies = [.. scene.Candies()];
            Star[] stars = [.. scene.Stars()];
            List<object> actions = [], samples = [];
            object Snapshot(int tick)
            {
                return new
                {
                    tick,
                    bodies = candies.Select(c => new
                    {
                        present = c.Lifecycle.ActiveBodies.Count > 0,
                        hidden = c.Lifecycle.Presence == CandyPresence.Hidden,
                        x = c.WholeBody.Point.pos.X,
                        y = c.WholeBody.Point.pos.Y,
                        px = c.WholeBody.Point.prevPos.X,
                        py = c.WholeBody.Point.prevPos.Y,
                        bubble = c.WholeBody.Bubble != null
                    }).ToArray(),
                    lit = stars.Select(s => s.IsLit).ToArray()
                };
            }

            samples.Add(Snapshot(0));
            for (int tick = 1; tick <= 480; tick++)
            {
                if (mode > 0 && (tick == 30 || tick == 150 || tick == 300))
                {
                    List<Grab> ropes = scene.Grabs();
                    for (int i = 0; i < ropes.Count; i++)
                    {
                        if (ropes[i].Rope != null && ropes[i].Rope.cut == -1 && (mode == 1 || i % 2 == tick / 150 % 2))
                    { ropes[i].Rope.SetCut(0); actions.Add(new { tick, kind = "cut", index = i + 1 }); }
                    }
                }
                if (mode == 2 && tick % 70 == 0)
                {
                    for (int i = 0; i < candies.Length; i++)
                    {
                        if (candies[i].WholeBody.Bubble != null)
                    { scene.PopCandyBubble(candies[i].WholeBody); actions.Add(new { tick, kind = "pop", index = i + 1 }); }
                    }
                }
                scene.Update(1f / 60);
                if (scene.Candy() != candies[0] || scene.Candy().Lifecycle.ActiveBodies.Count == 0)
                {
                    break;
                }

                samples.Add(Snapshot(tick));
            }
            return new { pack = 16, level, mode, actions, samples };
        }
    }
}

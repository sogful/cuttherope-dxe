using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

using CutTheRopeDX.Framework.Physics;
using CutTheRopeDX.GameMain;

using Xunit;

namespace CutTheRopeDX.Tests.Interactions
{
    // Optional golden-data export. Runs the real scene, not a second physics implementation.
    public sealed class RobloxPortTraceTests
    {
        private static readonly JsonSerializerOptions TraceOptions = new() { WriteIndented = true };

        [Fact]
        public void LevelSevenReferenceRouteCollectsThreeStars()
        {
            _ = HeadlessGame.Boot();
            GameScene scene = HeadlessGame.LoadLevel(0, 6);
            for (int tick = 1; tick <= 360; tick++)
            {
                if (tick == 61)
                {
                    foreach (int index in new[] { 0, 2, 3 })
                    {
                        scene.Grabs()[index].Rope.SetCut(0);
                    }
                }
                if (tick == 96)
                {
                    foreach (int index in new[] { 1, 5 })
                    {
                        scene.Grabs()[index].Rope.SetCut(0);
                    }
                }
                scene.Update(1f / 60f);
            }
            Assert.Empty(scene.Stars());
        }

        [Fact]
        public void ExportDesktopTrajectories()
        {
            string output = Environment.GetEnvironmentVariable("DX_ROBLOX_TRACE_OUTPUT");
            if (string.IsNullOrEmpty(output))
            {
                return;
            }
            _ = HeadlessGame.Boot();
            List<object> traces = [];
            foreach (int level in new[] { 1, 6, 7, 10 })
            {
                GameScene scene = HeadlessGame.LoadLevel(0, level - 1);
                List<object> samples = [];
                for (int tick = 1; tick <= 120; tick++)
                {
                    if (tick == 61 && level == 6)
                    {
                        scene.Grabs()[0].Rope.SetCut(0);
                    }
                    scene.Update(1f / 60f);
                    if (tick == 1 || tick % 15 == 0)
                    {
                        ConstraintedPoint point = scene.Candies()[0].WholeBody.Point;
                        samples.Add(new { tick, x = point.pos.X, y = point.pos.Y });
                    }
                }
                traces.Add(new { level, samples });
            }
            File.WriteAllText(output, JsonSerializer.Serialize(traces, TraceOptions));
            Assert.True(File.Exists(output));
        }
    }
}

using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Text.Json;

using CutTheRopeDX.Framework.Helpers;
using CutTheRopeDX.Framework.Physics;
using CutTheRopeDX.GameMain;

using Xunit;

namespace CutTheRopeDX.Tests.Interactions
{
    public sealed class RobloxCameraTraceTests
    {
        [Fact]
        public void ExportTallLevelCameraAndCandy()
        {
            string output = Environment.GetEnvironmentVariable("DX_ROBLOX_CAMERA_OUTPUT");
            if (string.IsNullOrEmpty(output))
            {
                return;
            }
            _ = HeadlessGame.Boot();
            List<object> runs = [];
            foreach (bool fast in new[] { false, true })
            {
                GameScene scene = HeadlessGame.LoadLevel(0, 14);
                Camera2D camera = (Camera2D)typeof(GameScene).GetField("camera", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(scene);
                List<object> samples = [];
                for (int tick = 0; tick <= 480; tick++)
                {
                    if (tick > 0)
                    {
                        if (fast && tick == 31)
                        {
                            _ = scene.TouchDownXYIndex(1280, 720, 0);
                        }
                        scene.Update(1f / 60f);
                    }
                    if (tick <= 5 || tick % 15 == 0)
                    {
                        ConstraintedPoint candy = scene.Candies()[0].WholeBody.Point;
                        samples.Add(new
                        {
                            tick,
                            x = camera.RenderPos.X,
                            y = camera.RenderPos.Y,
                            trackedX = camera.pos.X,
                            trackedY = camera.pos.Y,
                            camera.speed,
                            mode = camera.type.ToString(),
                            scene.ignoreTouches,
                            candyX = candy.pos.X,
                            candyY = candy.pos.Y
                        });
                    }
                }
                runs.Add(new { fast, samples });
            }
            File.WriteAllText(output, JsonSerializer.Serialize(runs, new JsonSerializerOptions { WriteIndented = true }));
            Assert.True(File.Exists(output));
        }
    }
}

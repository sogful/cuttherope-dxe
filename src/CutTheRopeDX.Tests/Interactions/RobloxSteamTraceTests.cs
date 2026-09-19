using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;

using CutTheRopeDX.Framework.Core;
using CutTheRopeDX.Framework.Helpers;
using CutTheRopeDX.Framework.Visual;
using CutTheRopeDX.GameMain;

using Xunit;

namespace CutTheRopeDX.Tests.Interactions
{
    public sealed class RobloxSteamTraceTests
    {
        private static T Field<T>(object instance, string name)
        {
            return (T)instance.GetType().GetField(name, BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public).GetValue(instance);
        }

        [Fact]
        public void ExportSteamScenes()
        {
            string output = Environment.GetEnvironmentVariable("DX_ROBLOX_STEAM_OUTPUT");
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
            GameScene scene = HeadlessGame.LoadLevel(12, level - 1);
            scene.gameSceneDelegate = new RecordingSceneDelegate();
            for (int wait = 0; scene.IsIntroPanRunning() && wait < 1000; wait++)
            {
                scene.Update(1f / 60);
            }

            List<SteamTube> tubes = Field<List<SteamTube>>(scene, "tubes");
            SteamTube firstTube = tubes[0];
            List<object> actions = [], samples = [];
            for (int tick = 1; tick <= 480; tick++)
            {
                if (mode > 0)
                {
                    for (int i = 0; i < tubes.Count; i++)
                {
                    if ((mode == 1 && (tick == 1 || tick == 41 || tick == 101 || tick == 181 || tick == 281 || tick == 381)) || (mode == 2 && tick % 80 == (1 + (i * 9)) % 80))
                    {
                            SteamTube tube = tubes[i];
                            Vector offset = CTRMathHelper.VectRotate(new(0, 28 * tube.GetHeightScale()), CTRMathHelper.DEGREES_TO_RADIANS(tube.rotation));
                        bool accepted = tube.OnTouchDownXY(tube.x + offset.X, tube.y + offset.Y);
                        actions.Add(new { tick, kind = "valve", index = i + 1, accepted });
                    }
                }
                }

                if (mode > 0 && (tick == 60 || tick == 211))
                {
                    foreach (Grab g in scene.Grabs())
                    {
                        if (g.Rope != null && g.Rope.cut == -1)
                        {
                            g.Rope.SetCut(0);
                        }
                    }

                    actions.Add(new { tick, kind = "cut", index = 0, accepted = true });
                }
                if (mode == 2 && tick % 70 == 0)
                {
                    CandyBody[] bodies = [.. scene.Candy().Lifecycle.ActiveBodies];
                    for (int i = 0; i < bodies.Length; i++)
                    {
                        if (bodies[i].Bubble != null)
                    {
                        scene.PopCandyBubble(bodies[i]);
                        actions.Add(new { tick, kind = "pop", index = i + 1, accepted = true });
                    }
                    }
                }
                scene.Update(1f / 60);
                if (Field<List<SteamTube>>(scene, "tubes")[0] != firstTube)
                {
                    break;
                }

                if (scene.Candy().Lifecycle.ActiveBodies.Count == 0)
                {
                    break;
                }

                if (tick == 1 || tick % 5 == 0)
                {
                    samples.Add(new
                {
                    tick,
                    bodies = scene.Candy().Lifecycle.ActiveBodies.Select(b => new { x = b.Point.pos.X, y = b.Point.pos.Y, bubble = b.Bubble != null }).ToArray(),
                    tubes = tubes.Select(t => new { state = t.steamState, height = t.GetCurrentHeightModulated(), valve = Field<Image>(t, "valve").rotation }).ToArray()
                });
                }
            }
            return new { pack = 13, level, mode, actions, samples };
        }
    }
}

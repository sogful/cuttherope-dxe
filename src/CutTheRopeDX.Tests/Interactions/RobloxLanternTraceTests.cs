using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;

using CutTheRopeDX.Framework.Core;
using CutTheRopeDX.Framework.Helpers;
using CutTheRopeDX.Framework.Physics;
using CutTheRopeDX.GameMain;

using Xunit;

namespace CutTheRopeDX.Tests.Interactions
{
    public sealed class RobloxLanternTraceTests
    {
        private static ConstraintedPoint Shared => (ConstraintedPoint)typeof(Lantern).GetProperty("SharedCandyPoint", BindingFlags.Static | BindingFlags.NonPublic).GetValue(null);
        private static T Field<T>(object instance, string name)
        {
            return (T)instance.GetType().GetField(name, BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public).GetValue(instance);
        }

        [Fact]
        public void ExportLanternScenes()
        {
            string output = Environment.GetEnvironmentVariable("DX_ROBLOX_LANTERN_OUTPUT");
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
            GameScene scene = HeadlessGame.LoadLevel(13, level - 1);
            scene.gameSceneDelegate = new RecordingSceneDelegate();
            for (int wait = 0; scene.IsIntroPanRunning() && wait < 1000; wait++)
            {
                scene.Update(1f / 60);
            }

            List<Lantern> lanterns = Lantern.GetAllLanterns();
            Lantern first = lanterns[0];
            int releaseCount = 0;
            List<object> actions = [], samples = [];
            object Snapshot(int tick)
            {
                return new
                {
                    tick,
                    bodies = scene.Candy().Lifecycle.ActiveBodies.Select(b => new
                    {
                        x = b.Point.pos.X,
                        y = b.Point.pos.Y,
                        px = b.Point.prevPos.X,
                        py = b.Point.prevPos.Y,
                        bubble = b.Bubble != null,
                        gravity = b.Point.disableGravity
                    }).ToArray(),
                    occupied = scene.Candy().Lifecycle.Attachments.InLantern,
                    shared = Shared != null,
                    lanterns = lanterns.Select(l => new { l.x, l.y, angle = l.rotation, state = l.lanternState }).ToArray()
                };
            }

            samples.Add(Snapshot(0));
            for (int tick = 1; tick <= 480; tick++)
            {
                if (mode > 0 && (tick == 30 || tick == 180 || tick == 300))
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
                if (mode > 0 && tick % 45 == 1 && Shared != null)
                {
                    int index = (releaseCount + (mode == 2 ? 1 : 0)) % lanterns.Count;
                    Lantern lantern = lanterns[index];
                    // Go through scene input so its separate .1s reveal is scheduled too.
                    Vector screen = scene.ScreenPositionOf(lantern);
                    _ = scene.TouchDownXYIndex(screen.X, screen.Y, 1);
                    _ = scene.TouchUpXYIndex(screen.X, screen.Y, 1);
                    bool accepted = Field<List<DispatchClass>>(Field<DelayedDispatcher>(lantern, "delayedDispatcher"), "dispatchers").Any(d => d.callThis.Method.Name == "ReleaseCandy");
                    actions.Add(new { tick, kind = "lantern", index = index + 1, accepted });
                    if (accepted)
                    {
                        releaseCount++;
                    }
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
                if (Lantern.GetAllLanterns().Count == 0 || Lantern.GetAllLanterns()[0] != first)
                {
                    break;
                }

                if (scene.Candy().Lifecycle.ActiveBodies.Count == 0)
                {
                    break;
                }
                // Every frame catches one-tick release/reveal and cooldown errors.
                samples.Add(Snapshot(tick));
            }
            return new { pack = 14, level, mode, actions, samples };
        }
    }
}

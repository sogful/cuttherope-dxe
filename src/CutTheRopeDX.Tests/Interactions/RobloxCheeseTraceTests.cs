using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;

using CutTheRopeDX.Framework.Core;
using CutTheRopeDX.GameMain;

using Xunit;

namespace CutTheRopeDX.Tests.Interactions
{
    public sealed class RobloxCheeseTraceTests
    {
        private static T Field<T>(object o, string name)
        {
            return (T)o.GetType().GetField(name, BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public).GetValue(o);
        }

        [Fact]
        public void ExportCheeseScenes()
        {
            string output = Environment.GetEnvironmentVariable("DX_ROBLOX_CHEESE_OUTPUT");
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
            GameScene scene = HeadlessGame.LoadLevel(14, level - 1);
            scene.gameSceneDelegate = new RecordingSceneDelegate();
            for (int wait = 0; scene.IsIntroPanRunning() && wait < 1000; wait++)
            {
                scene.Update(1f / 60);
            }

            List<Mouse> mice = scene.Mice();
            Mouse first = mice[0];
            MiceObject manager = Field<MiceObject>(scene, "miceManager");
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
                    active = Field<Mouse>(manager, "activeMouse").index,
                    mice = mice.Select(m => new { active = m.IsActive, carry = m.HasCandy, retreat = Field<bool>(m, "retreating"), grab = Field<bool>(m, "grabAnimating"), elapsed = Field<float>(m, "elapsedActive") }).ToArray()
                };
            }

            samples.Add(Snapshot(0));
            for (int tick = 1; tick <= 720; tick++)
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
                if (mode > 0 && tick % 47 == 1 && manager.ActiveMouseHasCandy())
                {
                    Mouse active = Field<Mouse>(manager, "activeMouse");
                    Vector screen = scene.ScreenPositionOf(new Framework.Core.Vector(active.x, active.y));
                    _ = scene.TouchDownXYIndex(screen.X, screen.Y, 1);
                    _ = scene.TouchUpXYIndex(screen.X, screen.Y, 1);
                    actions.Add(new { tick, kind = "mouse", index = Array.IndexOf([.. mice], active) + 1, accepted = !manager.ActiveMouseHasCandy() });
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
                if (scene.Mice().Count == 0 || scene.Mice()[0] != first || scene.Candy().Lifecycle.ActiveBodies.Count == 0)
                {
                    break;
                }

                samples.Add(Snapshot(tick));
            }
            return new { pack = 15, level, mode, actions, samples };
        }
    }
}

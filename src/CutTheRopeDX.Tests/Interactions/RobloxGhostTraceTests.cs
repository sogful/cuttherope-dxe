using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;

using CutTheRopeDX.GameMain;

using Xunit;

namespace CutTheRopeDX.Tests.Interactions
{
    public sealed class RobloxGhostTraceTests
    {
        private static T Field<T>(object instance, string name)
        {
            return (T)instance.GetType().GetField(name, BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public).GetValue(instance);
        }

        [Fact]
        public void ExportGhostScenes()
        {
            string output = Environment.GetEnvironmentVariable("DX_ROBLOX_GHOST_OUTPUT");
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
            GameScene scene = HeadlessGame.LoadLevel(11, level - 1);
            scene.gameSceneDelegate = new RecordingSceneDelegate();
            for (int wait = 0; scene.IsIntroPanRunning() && wait < 1000; wait++)
            {
                scene.Update(1f / 60);
            }

            List<Ghost> ghosts = Field<List<Ghost>>(scene, "ghosts");
            List<Bouncer> bouncers = Field<List<Bouncer>>(scene, "bouncers");
            List<object> actions = [], samples = [];
            for (int tick = 1; tick <= 360; tick++)
            {
                if (mode > 0 && (tick == 1 || tick == 31 || tick == 61 || tick == 121 || tick == 181 || tick == 241 || tick == 301))
                {
                    for (int i = 0; i < ghosts.Count; i++)
                    {
                        Ghost g = ghosts[i];
                        bool accepted = g.OnTouchDownXY(g.x, g.y);
                        actions.Add(new { tick, kind = "ghost", index = i + 1, accepted });
                    }
                }

                if (mode == 2 && (tick == 81 || tick == 211))
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
                if (mode == 2 && tick % 50 == 0)
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
                if (scene.Candy().Lifecycle.ActiveBodies.Count == 0)
                {
                    break;
                }

                if (tick == 1 || tick % 5 == 0)
                {
                    samples.Add(new
                {
                    tick,
                    bodies = scene.Candy().Lifecycle.ActiveBodies.Select(b => new { x = b.Point.pos.X, y = b.Point.pos.Y, bubble = b.Bubble != null, ghost = b.BubbleHasGhost }).ToArray(),
                    ghosts = ghosts.Select(g => new { form = (int)g.Form, parts = (g.Apparition as GhostGrab)?.Rope?.parts.Count ?? 0 }).ToArray(),
                    grabs = scene.Grabs().Count(),
                    bouncers = bouncers.Count,
                    bubbles = Field<List<Bubble>>(scene, "bubbles").Count
                });
                }
            }
            return new { pack = 12, level, mode, actions, samples };
        }
    }
}

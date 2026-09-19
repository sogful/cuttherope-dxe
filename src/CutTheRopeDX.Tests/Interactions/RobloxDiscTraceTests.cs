using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;

using CutTheRopeDX.Framework.Core;
using CutTheRopeDX.Framework.Helpers;
using CutTheRopeDX.GameMain;

using Xunit;

using static CutTheRopeDX.Framework.Helpers.CTRMathHelper;

namespace CutTheRopeDX.Tests.Interactions
{
    public sealed class RobloxDiscTraceTests
    {
        private static T Field<T>(object instance, string name)
        {
            return (T)instance.GetType().GetField(name, BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public).GetValue(instance);
        }

        [Fact]
        public void ExportRealDiscInput()
        {
            string output = Environment.GetEnvironmentVariable("DX_ROBLOX_DISC_OUTPUT");
            if (string.IsNullOrEmpty(output))
            {
                return;
            }

            _ = HeadlessGame.Boot();
            List<object> runs = [];
            for (int level = 1; level <= 25; level++)
            {
                runs.Add(Run(level, false));
                runs.Add(Run(level, true));
            }
            File.WriteAllText(output, JsonSerializer.Serialize(runs));
            Assert.Equal(50, runs.Count);
        }
        private static object Run(int level, bool drag)
        {
            GameScene scene = HeadlessGame.LoadLevel(10, level - 1);
            for (int wait = 0; scene.IsIntroPanRunning() && wait < 1000; wait++)
            {
                scene.Update(1f / 60);
            }

            Camera2D camera = Field<Camera2D>(scene, "camera");
            RotatedCircle[] originals = [.. Field<List<RotatedCircle>>(scene, "rotatedCircles")];
            Bubble[] bubbles = [.. Field<List<Bubble>>(scene, "bubbles")];
            Pump[] pumps = [.. Field<List<Pump>>(scene, "pumps")];
            List<object> actions = [], samples = [];
            RotatedCircle active = null;
            float angle = 0;
            void Input(string kind, Vector point, int tick)
            {
                float sx = (point.X - camera.RenderPos.X) * camera.Scale, sy = (point.Y - camera.RenderPos.Y) * camera.Scale;
                Vector world = camera.ScreenToWorld(sx, sy);
                actions.Add(new { tick, kind, x = world.X, y = world.Y });
                if (kind == "press")
                {
                    _ = scene.TouchDownXYIndex(sx, sy, 0);
                }

                if (kind == "drag")
                {
                    _ = scene.TouchMoveXYIndex(sx, sy, 0);
                }

                if (kind == "release")
                {
                    _ = scene.TouchUpXYIndex(sx, sy, 0);
                }
            }
            for (int tick = 1; tick <= 240; tick++)
            {
                int phase = (tick - 1) % 80;
                if (drag && originals.Length > 0)
                {
                    if (phase == 0)
                    {
                        active = originals[(tick - 1) / 80 % originals.Length];
                        angle = VectAngleNormalized(VectSub(active.handle2, Vect(active.x, active.y)));
                        Input("press", active.handle2, tick);
                    }
                    else if (phase < 60)
                    {
                        angle += (tick < 80 ? 1f : -1f) * .035f;
                        Input("drag", Vect(active.x + (active.size * 3 * MathF.Cos(angle)), active.y + (active.size * 3 * MathF.Sin(angle))), tick);
                    }
                    else if (phase == 60)
                    {
                        Input("release", active.handle2, tick);
                    }
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
                    discs = originals.Select(d => new { angle = d.rotation, leftX = d.handle1.X, leftY = d.handle1.Y, rightX = d.handle2.X, rightY = d.handle2.Y }).ToArray(),
                    bubbles = bubbles.Select(b => new { b.x, b.y }).ToArray(),
                    pumps = pumps.Select(p => new { p.x, p.y, angle = p.rotation }).ToArray()
                });
                }

                if (ended)
                {
                    break;
                }
            }
            return new { pack = 11, level, action = drag ? "drag" : "idle", actions, samples };
        }
    }
}

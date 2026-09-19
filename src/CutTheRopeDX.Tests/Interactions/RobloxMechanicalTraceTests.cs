using System;
using System.Collections;
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
    public sealed class RobloxMechanicalTraceTests
    {
        private static T Field<T>(object o, string n)
        {
            return (T)o.GetType().GetField(n, BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public).GetValue(o);
        }

        [Fact]
        public void ExportMechanicalScenes()
        {
            string output = Environment.GetEnvironmentVariable("DX_ROBLOX_MECHANICAL_OUTPUT");
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
            GameScene scene = HeadlessGame.LoadLevel(16, level - 1);
            scene.gameSceneDelegate = new RecordingSceneDelegate();
            for (int i = 0; scene.IsIntroPanRunning() && i < 1000; i++)
            {
                scene.Update(1f / 60);
            }

            CandyContext candy = scene.Candy();
            ConveyorBeltObject manager = Field<ConveyorBeltObject>(scene, "conveyors");
            ConveyorBelt[] belts = [.. manager.Iterator()];
            Star[] stars = [.. scene.Stars()];
            var removed = new bool[stars.Length];
            var items = new List<ITransporterItem>();
            foreach (ConveyorBelt b in belts)
            {
                foreach (ITransporterItem item in b.BoundObjects)
                {
                    items.Add(item);
                }
            }

            string[] fields = ["bubbles", "stars", "bouncers", "socks", "tubes", "pumps", "bungees"];
            string[] kinds = ["bubble", "star", "bouncer", "hat", "steam", "pump", "hook"];
            var itemIds = items.Select(item =>
            {
                for (int k = 0; k < fields.Length; k++)
                {
                    IList list = Field<System.Collections.IList>(scene, fields[k]);
                    int index = list.IndexOf(item);
                    if (index >= 0)
                    {
                        return new { kind = kinds[k], index = index + 1 };
                    }
                }
                throw new InvalidOperationException(item.GetType().Name);
            }).ToArray();
            var beltIds = belts.Select(b => new { b.x, b.y, length = b.width, manual = b.IsManual }).ToArray();
            List<object> actions = [], samples = [];
            object Snapshot(int tick)
            {
                return new
                {
                    tick,
                    bodies = candy.Lifecycle.ActiveBodies.Select(b => new { x = b.Point.pos.X, y = b.Point.pos.Y, px = b.Point.prevPos.X, py = b.Point.prevPos.Y, bubble = b.Bubble != null }).ToArray(),
                    hooks = scene.Grabs().Select(g => new { g.x, g.y, cut = g.Rope?.cut ?? -2 }).ToArray(),
                    items = items.Select(i => new { kind = i.GetType().Name, x = i.BindPoint.X, y = i.BindPoint.Y, position = i.PositionOnTransporter, scale = i.TransporterScale, belt = Array.FindIndex(belts, b => b.HasItem(i)) + 1 }).ToArray()
                };
            }

            samples.Add(Snapshot(0));
            ConveyorBelt held = null;
            Vector pointer = default;
            for (int tick = 1; tick <= 480; tick++)
            {
                if (mode > 0)
                {
                    int phase = (tick - 1) % 100;
                    if (phase == 10)
                    {
                        ConveyorBelt[] manual = [.. belts.Where(b => b.IsManual)];
                        if (manual.Length > 0)
                        {
                            ConveyorBelt candidate = manual[(tick - 1) / 100 % manual.Length];
                            pointer = new Vector(candidate.x + (candidate.Direction.X * candidate.width * .5f), candidate.y + (candidate.Direction.Y * candidate.width * .5f));
                            bool accepted = manager.OnPointerDown(pointer.X, pointer.Y, 1);
                            held = accepted ? candidate : null;
                            actions.Add(new { tick, kind = "down", x = pointer.X, y = pointer.Y, index = 0 });
                        }
                    }
                    if (held != null && phase > 10 && phase < 61)
                    {
                        float move = mode == 1 ? 12f : -23f;
                        pointer = new Vector(pointer.X + (held.Direction.X * move), pointer.Y + (held.Direction.Y * move));
                        _ = manager.OnPointerMove(pointer.X, pointer.Y, 1);
                        actions.Add(new { tick, kind = "drag", x = pointer.X, y = pointer.Y, index = 0 });
                    }
                    if (held != null && phase == 61)
                    {
                        _ = manager.OnPointerUp(pointer.X, pointer.Y, 1); held = null;
                        actions.Add(new { tick, kind = "up", x = pointer.X, y = pointer.Y, index = 0 });
                    }
                }
                if (mode == 2 && (tick == 40 || tick == 180 || tick == 320))
                {
                    for (int i = 0; i < scene.Grabs().Count; i++)
                    {
                        if (scene.Grabs()[i].Rope is { } rope && rope.cut == -1)
                    { rope.SetCut(0); actions.Add(new { tick, kind = "cut", x = 0, y = 0, index = i + 1 }); }
                    }
                }

                scene.Update(1f / 60);
                if (scene.Candy() != candy || candy.Lifecycle.ActiveBodies.Count == 0)
                {
                    break;
                }

                for (int i = 0; i < stars.Length; i++)
                {
                    if (!removed[i] && !scene.Stars().Contains(stars[i]))
                { removed[i] = true; actions.Add(new { tick, kind = "removeStar", x = 0, y = 0, index = i + 1 }); }
                }

                samples.Add(Snapshot(tick));
            }
            return new { level, mode, itemIds, beltIds, actions, samples };
        }
    }
}

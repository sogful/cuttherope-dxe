using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Xml.Linq;

using CutTheRopeDX.Framework;
using CutTheRopeDX.Framework.Core;
using CutTheRopeDX.Framework.Physics;
using CutTheRopeDX.GameMain;

using Xunit;

namespace CutTheRopeDX.Tests.Interactions
{
    // Optional port fixture: executes the real C# scene with reproducible inputs.
    public sealed class RobloxBoxTraceTests
    {
        [Fact]
        public void ExportBoxMovers()
        {
            string output = Environment.GetEnvironmentVariable("DX_ROBLOX_BOX_OUTPUT");
            if (string.IsNullOrEmpty(output))
            {
                return;
            }

            ActivePhysicsConstants.UseMobilePhysicsModel = false;
            List<object> runs = [];
            string content = Path.Combine(Environment.CurrentDirectory, "content", "maps");
            for (int pack = 2; pack <= 4; pack++)
            {
                for (int level = 1; level <= 25; level++)
                {
                    XElement map = XElement.Load(Path.Combine(content, $"{pack}_{level}.xml"));
                    XElement settings = map.Elements("layer").First();
                    XElement design = settings.Element("gameDesign");
                    float width = (float)settings.Element("map").Attribute("width");
                    XElement objects = map.Elements("layer").Single(l => (string)l.Attribute("name") == "Objects");
                    foreach (string kind in new[] { "star", "spike", "sock" })
                    {
                        int index = 0;
                        foreach (XElement node in objects.Elements().Where(n => n.Name.LocalName.StartsWith(kind, StringComparison.Ordinal) || kind == "spike" && n.Name.LocalName == "electro"))
                        {
                            index++;
                            if (node.Attribute("path") == null)
                            {
                                continue;
                            }

                            Vector origin = new(
                                ((int)(float)node.Attribute("x") * 3) + ((2560 - (width * 3)) / 2) + ((int?)design.Attribute("mapOffsetX") ?? 0),
                                ((int)(float)node.Attribute("y") * 3) + ((int?)design.Attribute("mapOffsetY") ?? 0));
                            CTRMover mover = CTRMover.FromXml(node, origin, (float?)node.Attribute("angle") ?? 0);
                            if (kind == "sock") { mover.angle_ += 90; mover.angle_initial = mover.angle_; mover.use_angle_initial = pack == 4 && level == 25; }
                            List<object> samples = [];
                            for (int tick = 1; tick <= 600; tick++)
                            {
                                mover.Update(.016f);
                                if (tick == 1 || tick % 15 == 0)
                                {
                                    samples.Add(new { tick, x = mover.pos.X, y = mover.pos.Y, angle = mover.angle_, target = mover.targetPoint + 1 });
                                }
                            }
                            runs.Add(new { pack, level, kind, index, samples });
                        }
                    }
                }
            }

            File.WriteAllText(Path.Combine(Path.GetDirectoryName(output), "box-movers-reference.json"), JsonSerializer.Serialize(runs));
            Assert.NotEmpty(runs);
        }

        [Fact]
        public void ExportBoxTrajectories()
        {
            string output = Environment.GetEnvironmentVariable("DX_ROBLOX_BOX_OUTPUT");
            if (string.IsNullOrEmpty(output))
            {
                return;
            }

            _ = HeadlessGame.Boot();
            List<object> runs = [];
            for (int pack = 2; pack <= 4; pack++)
            {
                for (int level = 1; level <= 25; level++)
                {
                    runs.Add(Run(pack, level, "idle", 120));
                }
            }
            runs.Add(Run(2, 1, "pump", 240));
            runs.Add(Run(3, 1, "rail", 240));
            runs.Add(Run(4, 1, "hat", 240));
            File.WriteAllText(output, JsonSerializer.Serialize(runs, new JsonSerializerOptions { WriteIndented = true }));
            Assert.Equal(78, runs.Count);
        }

        private static object Run(int pack, int level, string action, int ticks)
        {
            GameScene scene = HeadlessGame.LoadLevel(pack - 1, level - 1);
            // Compare gameplay ticks, not the optional camera flyover.
            for (int wait = 0; scene.IsIntroPanRunning() && wait < 1000; wait++)
            {
                scene.Update(1f / 60);
            }

            List<object> samples = [];
            for (int tick = 1; tick <= ticks; tick++)
            {
                if (action == "pump" && (tick == 61 || tick == 121))
                {
                    scene.Pumps()[0].pumpTouchTimer = .05f;
                }

                if (action == "rail" && tick >= 61 && tick <= 120)
                {
                    Grab grab = scene.Grabs()[0];
                    grab.Rail.DragTo(grab, grab.Rail.MinValue + ((tick - 60) * 10), grab.y);
                    grab.SyncRopeAnchor();
                    grab.ReCalcCircle();
                }
                if (action == "hat" && tick == 61)
                {
                    scene.Grabs()[0].Rope.SetCut(0);
                }

                scene.Update(1f / 60);
                if (tick == 1 || tick % 5 == 0)
                {
                    ConstraintedPoint point = scene.Candy().WholeBody.Point;
                    samples.Add(new
                    {
                        tick,
                        x = point.pos.X,
                        y = point.pos.Y,
                        gone = scene.PrimaryCandyGone(),
                        stars = scene.Stars().Count,
                        spiders = scene.Grabs().Where(g => g.Spider != null).Select(g => new
                        {
                            quad = g.Spider.Animation.quadToDraw,
                            position = g.Spider.Position,
                            timeline = g.Spider.Animation.GetCurrentTimelineIndex()
                        }).ToArray()
                    });
                }
            }
            return new { pack, level, action, samples };
        }
    }
}

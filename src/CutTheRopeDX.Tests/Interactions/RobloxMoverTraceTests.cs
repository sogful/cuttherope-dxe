using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Xml.Linq;

using CutTheRopeDX.Framework;
using CutTheRopeDX.GameMain;

using Xunit;

namespace CutTheRopeDX.Tests.Interactions
{
    public sealed class RobloxMoverTraceTests
    {
        [Fact]
        public void ExportRemainingCardboardTrajectories()
        {
            string output = Environment.GetEnvironmentVariable("DX_ROBLOX_CARDBOARD_OUTPUT");
            if (string.IsNullOrEmpty(output))
            {
                return;
            }
            _ = HeadlessGame.Boot();
            List<object> runs = [];
            for (int level = 17; level <= 25; level++)
            {
                GameScene scene = HeadlessGame.LoadLevel(0, level - 1);
                List<object> samples = [];
                for (int tick = 1; tick <= 120; tick++)
                {
                    scene.Update(1f / 60f);
                    if (tick == 1 || tick % 15 == 0)
                    {
                        Framework.Physics.ConstraintedPoint point = scene.Candy().WholeBody.Point;
                        samples.Add(new { tick, x = point.pos.X, y = point.pos.Y });
                    }
                }
                runs.Add(new { level, samples });
            }
            File.WriteAllText(output, JsonSerializer.Serialize(runs, new JsonSerializerOptions { WriteIndented = true }));
            Assert.Equal(9, runs.Count);
        }

        [Fact]
        public void ExportAuthoredCardboardMovers()
        {
            string output = Environment.GetEnvironmentVariable("DX_ROBLOX_MOVER_OUTPUT");
            string content = Environment.GetEnvironmentVariable("DX_ROBLOX_CONTENT");
            if (string.IsNullOrEmpty(output) || string.IsNullOrEmpty(content))
            {
                return;
            }
            ActivePhysicsConstants.UseMobilePhysicsModel = false;
            List<object> runs = [];
            foreach (int level in new[] { 22, 24 })
            {
                XElement map = XElement.Load(Path.Combine(content, "maps", $"1_{level}.xml"));
                float width = (float)map.Element("layer").Element("map").Attribute("width");
                XElement objects = map.Elements("layer").Single(layer => (string)layer.Attribute("name") == "Objects");
                foreach (string kind in new[] { "star", "spike" })
                {
                    int index = 0;
                    foreach (XElement node in objects.Elements().Where(node => node.Name.LocalName.StartsWith(kind, StringComparison.Ordinal)))
                    {
                        index++;
                        if (node.Attribute("path") == null)
                        {
                            continue;
                        }
                        var origin = new Framework.Core.Vector(
                            ((float)node.Attribute("x") * 3) + ((2560 - (width * 3)) / 2),
                            (float)node.Attribute("y") * 3);
                        CTRMover mover = CTRMover.FromXml(node, origin, (float?)node.Attribute("angle") ?? 0);
                        List<object> samples = [];
                        for (int tick = 0; tick <= 600; tick++)
                        {
                            if (tick > 0)
                            {
                                mover.Update(.016f);
                            }
                            if (tick <= 2 || tick % 15 == 0)
                            {
                                samples.Add(new { tick, x = mover.pos.X, y = mover.pos.Y, angle = mover.angle_, target = mover.targetPoint + 1 });
                            }
                        }
                        runs.Add(new { level, kind, index, samples });
                    }
                }
            }
            File.WriteAllText(output, JsonSerializer.Serialize(runs, new JsonSerializerOptions { WriteIndented = true }));
            Assert.Equal(3, runs.Count);
        }
    }
}

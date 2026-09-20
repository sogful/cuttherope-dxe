using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Xml.Linq;

using CutTheRopeDX.Framework;
using CutTheRopeDX.Framework.Core;
using CutTheRopeDX.GameMain;

using Xunit;

namespace CutTheRopeDX.Tests.Interactions
{
    /// <summary>Opt-in source-engine golden samples for the native DS port.</summary>
    public sealed class DsMoverExportTests
    {
        private static readonly JsonSerializerOptions ExportOptions = new() { WriteIndented = true };

        [Fact]
        public void ExportFirstSixBoxes()
        {
            string output = Environment.GetEnvironmentVariable("DX_DS_MOVER_OUTPUT");
            string content = Environment.GetEnvironmentVariable("DX_DS_CONTENT");
            if (string.IsNullOrEmpty(output) || string.IsNullOrEmpty(content))
            {
                return;
            }
            ActivePhysicsConstants.UseMobilePhysicsModel = false;
            List<object> samples = [];
            for (int box = 1; box <= 6; box++)
            {
                for (int level = 1; level <= 25; level++)
                {
                    XElement map = XElement.Load(Path.Combine(content, "maps", $"{box}_{level}.xml"));
                    XElement settings = map.Elements("layer").Single(layer => (string)layer.Attribute("name") == "settings");
                    XElement design = settings.Element("gameDesign");
                    float left = (2560 - ((float)settings.Element("map").Attribute("width") * 3)) / 2;
                    XElement objects = map.Elements("layer").Single(layer => (string)layer.Attribute("name") == "Objects");
                    Dictionary<string, int> counts = [];
                    foreach (XElement node in objects.Elements())
                    {
                        string kind = node.Name.LocalName;
                        kind = kind.StartsWith("spike", StringComparison.Ordinal) || kind == "electro" ? "spike" :
                            kind.StartsWith("bouncer", StringComparison.Ordinal) ? "bouncer" : kind;
                        int index = counts.GetValueOrDefault(kind);
                        counts[kind] = index + 1;
                        if (node.Attribute("path") == null || kind.StartsWith("tutorial", StringComparison.Ordinal))
                        {
                            continue;
                        }
                        Vector start = new(
                            ((float)node.Attribute("x") * 3) + left + ((float?)design.Attribute("mapOffsetX") ?? 0),
                            ((float)node.Attribute("y") * 3) + ((float?)design.Attribute("mapOffsetY") ?? 0));
                        float angle = ((float?)node.Attribute("angle") ?? 0) + (kind == "sock" ? 90 : 0);
                        CTRMover mover = CTRMover.FromXml(node, start, angle);
                        mover.use_angle_initial = box == 4 && level == 25 && kind == "sock";
                        for (int tick = 0; tick <= 600; tick++)
                        {
                            if (tick > 0)
                            {
                                mover.Update(.016f);
                            }
                            if (tick is 0 or 1 or 15 or 60 or 180 or 360 or 600)
                            {
                                samples.Add(new { level = ((box - 1) * 25) + level - 1, kind, index, tick, x = mover.pos.X, y = mover.pos.Y, angle = mover.angle_ });
                            }
                        }
                    }
                }
            }
            Assert.NotEmpty(samples);
            File.WriteAllText(output, JsonSerializer.Serialize(samples, ExportOptions));
        }
    }
}

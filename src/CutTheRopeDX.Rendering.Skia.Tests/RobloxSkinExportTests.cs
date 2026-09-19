using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Xml.Linq;

using CutTheRopeDX.Framework;
using CutTheRopeDX.Framework.Core;
using CutTheRopeDX.Framework.Platform;
using CutTheRopeDX.Framework.Visual;
using CutTheRopeDX.GameMain;
using CutTheRopeDX.Helpers;

using SkiaSharp;

using Xunit;

namespace CutTheRopeDX.Rendering.Skia.Tests
{
    public sealed class RobloxSkinExportTests
    {
        [Fact]
        public void ExportOriginalXmlAnimations()
        {
            string output = Environment.GetEnvironmentVariable("DX_SKIN_EXPORT");
            if (string.IsNullOrEmpty(output))
            {
                return;
            }

            _ = Directory.CreateDirectory(output);
            using ExportSurface surface = new();
            using SkiaRenderBackend renderer = new(surface);
            PlatformServices.Render = renderer;
            HeadlessHost.Boot(2560, 1440, Language.LANGEN);
            renderer.DiscardDeviceResources();
            renderer.SetMatrixMode(0);
            Type backendType = typeof(FlashXmlTargetAnimationBackend);
            MethodInfo play = backendType.GetMethod("PlayTimelineById", BindingFlags.NonPublic | BindingFlags.Instance);
            MethodInfo duration = backendType.GetMethod("GetTimelineDurationSeconds", BindingFlags.NonPublic | BindingFlags.Instance, [typeof(int)]);
            MethodInfo seek = backendType.GetMethod("SeekCurrentTimeline", BindingFlags.NonPublic | BindingFlags.Instance);
            using JsonDocument manifest = JsonDocument.Parse(File.ReadAllText(ContentPaths.GetAnimationXmlAbsolutePath("om_nom_skins.json")));
            int limit = int.TryParse(Environment.GetEnvironmentVariable("DX_SKIN_LIMIT"), out int parsed) ? parsed : 15;
            int first = int.TryParse(Environment.GetEnvironmentVariable("DX_SKIN_FIRST"), out int firstParsed) ? firstParsed : 1;
            List<object> exported = first > 1 ? [.. JsonSerializer.Deserialize<List<JsonElement>>(File.ReadAllText(Path.Combine(output, "index.json"))).Select(e => (object)e)] : [];
            for (int slot = 1; slot <= Math.Min(limit, OmNomSkinRegistry.TotalSkinCount - 1); slot++)
            {
                if (slot < first)
                {
                    continue;
                }

                OmNomSkinDefinition skin = OmNomSkinRegistry.GetXmlSkinDefinition(slot);
                string pirateOverride = Environment.GetEnvironmentVariable("DX_PIRATE_XML");
                bool pipeRemoved = slot == 7 && !string.IsNullOrEmpty(pirateOverride);
                if (pipeRemoved)
                {
                    XElement clean = XElement.Load(pirateOverride);
                    Assert.DoesNotContain(clean.Descendants("Image"), part => (string)part.Attribute("name") == "pipe");
                    skin = new OmNomSkinDefinition(skin.Id, skin.Name, pirateOverride,
                        skin.TimelineMappings, skin.Followups, skin.IdleVariants, skin.IdleToSleepTrimFrames,
                        skin.SlowTimelineIds, skin.StartWithGreeting, skin.UniqueSounds);
                }
                XElement xml = XElement.Load(skin.AnimationXmlPath);
                foreach (string resource in xml.DescendantsAndSelf().Attributes("src").Select(a => a.Value).Append("char_animations_smooth").Distinct())
                {
                    CTRTexture2D texture = Application.GetTexture(resource);
                    texture.textureHandle_ ??= new SkiaTexture(SKImage.FromEncodedData(File.ReadAllBytes(Path.Combine(ContentPaths.GetContentRootAbsolute(), "images", resource + ".png"))));
                }
                JsonElement config = manifest.RootElement[slot - 1];
                HashSet<int> ids = [.. config.GetProperty("timelines").EnumerateObject().Where(p => p.Name is not "LevelIntro" and not "LevelOutro").Select(p => p.Value.GetInt32())];
                foreach (JsonProperty p in config.GetProperty("followups").EnumerateObject())
                {
                    _ = ids.Add(p.Value.GetInt32());
                }

                int[] slow = [.. config.GetProperty("slowTimelines").EnumerateArray().Select(p => p.GetInt32())];
                Dictionary<int, object> timelines = [];
                foreach (int id in ids.Order())
                {
                    FlashXmlTargetAnimationBackend backend = new(skin);
                    _ = play.Invoke(backend, [id]);
                    float seconds = (float)duration.Invoke(backend, [id]);
                    float rate = slow.Contains(id) ? .6f : 1f;
                    int count = Math.Max(1, (int)MathF.Ceiling(seconds * 20));
                    string folder = Path.Combine(output, slot.ToString(), id.ToString());
                    _ = Directory.CreateDirectory(folder);
                    for (int frame = 0; frame < count; frame++)
                    {
                        _ = seek.Invoke(backend, [frame / 20f]);
                        surface.Canvas.Clear(SKColors.Transparent);
                        renderer.BeginFrame();
                        renderer.LoadIdentity();
                        renderer.Translate(surface.Width / 2, surface.Height / 2, 0);
                        renderer.Enable(1);
                        renderer.SetBlendFunc(BlendingFactor.GLONE, BlendingFactor.GLONEMINUSSRCALPHA);
                        backend.TargetObject.Draw();
                        renderer.EndFrame();
                        using SKImage image = surface.Surface.Snapshot();
                        using SKData png = image.Encode(SKEncodedImageFormat.Png, 100);
                        using FileStream stream = File.Create(Path.Combine(folder, frame + ".png"));
                        png.SaveTo(stream);
                    }
                    timelines[id] = new { frames = count, duration = seconds / rate, fps = 20 * rate };
                }
                object record = new { slot, config, timelines, canvas = surface.Width, pipeRemoved };
                if (slot <= exported.Count)
                {
                    exported[slot - 1] = record;
                }
                else
                {
                    exported.Add(record);
                }

                File.WriteAllText(Path.Combine(output, "index.json"), JsonSerializer.Serialize(exported));
                Console.WriteLine($"Exported XML skin {slot}: {timelines.Count} timelines");
            }
            Assert.True(exported.Count >= Math.Min(limit, 15));
        }

        private sealed class ExportSurface : ISkiaSurface, IDisposable
        {
            public SKSurface Surface { get; } = SKSurface.Create(new SKImageInfo(768, 768));
            public SKCanvas Canvas => Surface.Canvas;
            public GRContext Context => null;
            public int Width => 768;
            public int Height => 768;
            public void Flush()
            {
                Canvas.Flush();
            }

            public void Dispose()
            {
                Surface.Dispose();
            }
        }
    }
}

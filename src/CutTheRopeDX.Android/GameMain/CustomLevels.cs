using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Xml.Linq;

namespace CutTheRopeDX.GameMain
{
    /// <summary>
    /// Backing store for the Custom Box: user-imported level files kept in the app's own
    /// external media directory (/storage/emulated/0/Android/media/&lt;package&gt; on android),
    /// listed for the custom level-select screen and parsed into the level XML the game loads.
    /// Accepts CTR level <c>.xml</c> directly and the obscure numeric <c>.json</c> format,
    /// which is converted to XML using the same id map as candies.monster's convertlevels.
    /// </summary>
    internal static class CustomLevels
    {
        /// <summary>
        /// The custom level XML currently being played, or <see langword="null"/> for normal levels.
        /// The map load/reload paths use this instead of the bundled LevelsList when set.
        /// </summary>
        public static XElement PendingCustomMap;

        /// <summary>Absolute path to the directory holding imported custom level files.</summary>
        public static string LevelsDir
        {
            get
            {
                string dir;
#if ANDROID
                // the app's own external media dir: Android/media/<package>/ - readable/writable
                // with no runtime storage permission on every api level.
                Android.Content.Context ctx = Android.App.Application.Context;
                Java.IO.File[] mediaDirs = ctx.GetExternalMediaDirs();
                dir = mediaDirs != null && mediaDirs.Length > 0 && mediaDirs[0] != null
                    ? mediaDirs[0].AbsolutePath
                    : "/storage/emulated/0/Android/media/" + ctx.PackageName;
#else
                dir = Path.Combine(AppContext.BaseDirectory, "customlevels");
#endif
                try
                {
                    _ = Directory.CreateDirectory(dir);
                }
                catch (Exception)
                {
                }
                return dir;
            }
        }

        /// <summary>
        /// Lists imported level files (.xml / .json) sorted by name.
        /// </summary>
        /// <returns>Full paths to each imported level file; empty if none.</returns>
        public static List<string> ListLevelFiles()
        {
            List<string> files = [];
            try
            {
                foreach (string f in Directory.EnumerateFiles(LevelsDir))
                {
                    string ext = Path.GetExtension(f).ToLowerInvariant();
                    if (ext is ".xml" or ".json")
                    {
                        files.Add(f);
                    }
                }
                files.Sort(StringComparer.OrdinalIgnoreCase);
            }
            catch (Exception)
            {
            }
            return files;
        }

        /// <summary>
        /// Copies an imported file's bytes into the custom levels directory under <paramref name="fileName"/>.
        /// </summary>
        /// <param name="fileName">Destination file name (with .xml/.json extension).</param>
        /// <param name="content">Raw file bytes to write.</param>
        public static void ImportBytes(string fileName, byte[] content)
        {
            string safe = Path.GetFileName(fileName);
            File.WriteAllBytes(Path.Combine(LevelsDir, safe), content);
        }

        /// <summary>
        /// Reads an imported level file and returns the parsed level XML root, converting JSON to XML
        /// when needed. Throws on malformed content so the caller can surface an error.
        /// </summary>
        /// <param name="filePath">Full path to the imported level file.</param>
        /// <returns>The level's &lt;map&gt; XML element.</returns>
        public static XElement LoadLevel(string filePath)
        {
            string text = File.ReadAllText(filePath);
            if (Path.GetExtension(filePath).Equals(".json", StringComparison.OrdinalIgnoreCase))
            {
                text = JsonToXml(text);
            }
            return XDocument.Parse(text).Root;
        }

        /// <summary>
        /// Counts the star objects in an imported level for the level-tile star display. Returns the
        /// count only when it is a normal 1-3 (matching the original star icons); 0 for none or more.
        /// </summary>
        /// <param name="filePath">Full path to the imported level file.</param>
        /// <returns>Star count clamped to 0 (or 1-3 when exactly that many stars exist).</returns>
        public static int CountStars(string filePath)
        {
            try
            {
                XElement root = LoadLevel(filePath);
                int n = 0;
                foreach (XElement _ in root.Descendants("star"))
                {
                    n++;
                }
                return n is >= 1 and <= 3 ? n : 0;
            }
            catch (Exception)
            {
                return 0;
            }
        }

        /// <summary>
        /// Converts a CTR numeric-id JSON level into the level XML the game parses
        /// (port of convertjsontoxml from candies.monster's convertlevels).
        /// </summary>
        /// <param name="jsonText">The JSON level text.</param>
        /// <returns>Equivalent level XML string.</returns>
        public static string JsonToXml(string jsonText)
        {
            using JsonDocument doc = JsonDocument.Parse(jsonText);
            JsonElement root = doc.RootElement;

            StringBuilder xml = new();
            _ = xml.Append("<map>\n<layer name=\"settings\">\n");

            JsonElement mapS = FindByName(root, "settings", 0);
            int gridSize = GetInt(mapS, "gridSize", 32);
            int width = GetInt(mapS, "width", 320);
            int height = GetInt(mapS, "height", 480);
            _ = xml.Append($"<map gridSize=\"{gridSize}\" width=\"{width}\" height=\"{height}\" />\n");

            JsonElement gd = FindByName(root, "settings", 1);
            if (gd.ValueKind == JsonValueKind.Object)
            {
                _ = xml.Append($"<gameDesign ropePhysicsSpeed=\"{GetNum(gd, "ropePhysicsSpeed", 1)}\" special=\"{GetInt(gd, "special", 1)}\"");
                AppendIf(xml, gd, "twoParts");
                AppendIf(xml, gd, "nightLevel");
                AppendIf(xml, gd, "water");
                AppendIf(xml, gd, "waterSpeed");
                _ = xml.Append(" />\n");
            }
            else
            {
                _ = xml.Append("<gameDesign ropePhysicsSpeed=\"1.0\" special=\"1\" twoParts=\"false\" />\n");
            }
            _ = xml.Append("</layer>\n<layer name=\"Objects\">\n");

            if (root.TryGetProperty("objects", out JsonElement objects) && objects.ValueKind == JsonValueKind.Array)
            {
                foreach (JsonElement obj in objects.EnumerateArray())
                {
                    string name = GetInt(obj, "name", -1).ToString(System.Globalization.CultureInfo.InvariantCulture);
                    if (!JsonToXmlTag.TryGetValue(name, out string tag))
                    {
                        continue;
                    }
                    _ = xml.Append($"<{tag} x=\"{GetInt(obj, "x", 0)}\" y=\"{GetInt(obj, "y", 0)}\"");
                    foreach (string attr in OptionalAttrs)
                    {
                        AppendIf(xml, obj, attr);
                    }
                    _ = xml.Append(" />\n");
                }
            }
            _ = xml.Append("</layer>\n</map>");
            return xml.ToString();
        }

        /// <summary>Finds the settings entry whose numeric "name" matches <paramref name="name"/>.</summary>
        private static JsonElement FindByName(JsonElement root, string arrayProp, int name)
        {
            if (root.TryGetProperty(arrayProp, out JsonElement arr) && arr.ValueKind == JsonValueKind.Array)
            {
                foreach (JsonElement e in arr.EnumerateArray())
                {
                    if (e.TryGetProperty("name", out JsonElement n) && n.ValueKind == JsonValueKind.Number && n.GetInt32() == name)
                    {
                        return e;
                    }
                }
            }
            return default;
        }

        /// <summary>Appends <c> attr="value"</c> when the JSON object carries that property.</summary>
        private static void AppendIf(StringBuilder xml, JsonElement obj, string attr)
        {
            if (obj.ValueKind == JsonValueKind.Object && obj.TryGetProperty(attr, out JsonElement v))
            {
                string s = v.ValueKind switch
                {
                    JsonValueKind.True => "true",
                    JsonValueKind.False => "false",
                    JsonValueKind.String => v.GetString(),
                    _ => v.GetRawText()
                };
                _ = xml.Append($" {attr}=\"{s}\"");
            }
        }

        private static int GetInt(JsonElement obj, string prop, int fallback) =>
            obj.ValueKind == JsonValueKind.Object && obj.TryGetProperty(prop, out JsonElement v) && v.TryGetInt32(out int i) ? i : fallback;

        private static string GetNum(JsonElement obj, string prop, double fallback) =>
            (obj.ValueKind == JsonValueKind.Object && obj.TryGetProperty(prop, out JsonElement v) && v.ValueKind == JsonValueKind.Number
                ? v.GetDouble() : fallback).ToString(System.Globalization.CultureInfo.InvariantCulture);

        /// <summary>numeric CTR object id -> level XML tag name (from conversion.js jsontoxml).</summary>
        private static readonly Dictionary<string, string> JsonToXmlTag = new()
        {
            ["52"] = "candy", ["50"] = "candyL", ["51"] = "candyR", ["2"] = "target", ["3"] = "star",
            ["54"] = "bubble", ["55"] = "pump", ["56"] = "sock", ["58"] = "spike2", ["80"] = "spike3",
            ["53"] = "gravityswitch", ["60"] = "spike4", ["81"] = "bouncer1", ["120"] = "rotatedcircle",
            ["130"] = "ghost", ["131"] = "steamtube", ["132"] = "lantern", ["133"] = "gap",
            ["134"] = "lightbulb", ["135"] = "transporter", ["300"] = "hiddenelement", ["100"] = "grab",
            ["4"] = "tutorialtext", ["5"] = "tutorial01", ["6"] = "tutorial02", ["7"] = "tutorial03",
            ["8"] = "tutorial04", ["9"] = "tutorial05", ["10"] = "tutorial06", ["11"] = "tutorial07",
            ["12"] = "tutorial08", ["13"] = "tutorial09", ["14"] = "tutorial10", ["15"] = "tutorial11",
            ["16"] = "tutorial12", ["17"] = "tutorial13", ["18"] = "tutorial14", ["57"] = "spike", ["59"] = "spike1"
        };

        /// <summary>optional per-object attributes copied through when present (from convertjsontoxml).</summary>
        private static readonly string[] OptionalAttrs =
        [
            "timeout", "angle", "size", "group", "radius", "path", "moveSpeed", "initialDelay", "offTime",
            "onTime", "toggled", "rotateSpeed", "oneHandle", "handleAngle", "bouncer", "bubble", "grab",
            "candyCaptured", "activeTime", "index", "litRadius", "bulbNumber", "direction", "type", "width",
            "length", "velocity", "spider", "gun", "wheel", "part", "hidePath", "moveOffset", "moveVertical",
            "moveLength", "kickable", "kicked", "invisible", "helicopter", "bindBulb", "text", "height",
            "locale", "special"
        ];
    }
}

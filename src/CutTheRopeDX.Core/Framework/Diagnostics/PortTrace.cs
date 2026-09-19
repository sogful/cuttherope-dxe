using System;
using System.IO;
using System.Text.Json;
using System.Threading;

namespace CutTheRopeDX.Framework.Diagnostics
{
    /// <summary>Opt-in, launch-scoped port comparison events. Never touches player saves.</summary>
    internal static class PortTrace
    {
        private static readonly Lock Gate = new();
        private static readonly string Path = Environment.GetEnvironmentVariable("CTRDxPortTracePath");

        public static void Event(string kind, Action<Utf8JsonWriter> writeData)
        {
            if (string.IsNullOrWhiteSpace(Path))
            {
                return;
            }
            try
            {
                using MemoryStream buffer = new();
                using (Utf8JsonWriter writer = new(buffer))
                {
                    writer.WriteStartObject();
                    writer.WriteString("utc", DateTimeOffset.UtcNow);
                    writer.WriteString("kind", kind);
                    writer.WriteStartObject("data");
                    writeData(writer);
                    writer.WriteEndObject();
                    writer.WriteEndObject();
                }

                lock (Gate)
                {
                    using FileStream stream = new(Path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite);
                    buffer.WriteTo(stream);
                    stream.WriteByte((byte)'\n');
                }
            }
            catch (Exception)
            {
                // Diagnostics must never affect gameplay or loading.
            }
        }
    }
}

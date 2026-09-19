using System;
using System.Collections.Generic;

using CutTheRopeDX.Helpers;

using Microsoft.Xna.Framework.Content;
using Microsoft.Xna.Framework.Graphics;

#if ANDROID
using System.IO;
using Microsoft.Xna.Framework;
#endif

namespace CutTheRopeDX.Desktop
{
    /// <summary>
    /// Loads and caches image content. On desktop, textures are GPU-ready xnb loaded through
    /// per-asset content managers. On android, textures are ETC2-RGBA (GPU-compressed, premultiplied)
    /// uploaded straight to the gpu with zero cpu decode, so loading is just a file read + upload.
    /// </summary>
    internal sealed class Images
    {
        /*//////////////////////////// android /////////////////////////////////*/
#if ANDROID
        /// <summary>
        /// Loads a texture by asset name (android) from a small container with a 12-byte header
        /// (4-byte magic + int32 width + int32 height) followed by the pixel data, uploaded straight
        /// to the gpu with no cpu decode. Magic "ETC2" = ETC2_EAC_RGBA compressed blocks;
        /// "RAW0" = lossless premultiplied raw RGBA (used for high-detail menu art).
        /// </summary>
        /// <param name="imgName">The image asset name, relative to the content root.</param>
        /// <returns>The loaded texture, or <see langword="null"/> if loading fails.</returns>
        public static Texture2D Get(string imgName)
        {
            if (_androidTextures.TryGetValue(imgName, out Texture2D cached))
            {
                return cached;
            }

            try
            {
                string assetPath = ContentPaths.RootDirectory + "/" + imgName.Replace('\\', '/') + ".etc2";
                byte[] bytes;
                using (Stream stream = TitleContainer.OpenStream(assetPath))
                using (MemoryStream ms = new MemoryStream())
                {
                    stream.CopyTo(ms);
                    bytes = ms.ToArray();
                }

                bool raw = bytes[0] == (byte)'R' && bytes[1] == (byte)'A' && bytes[2] == (byte)'W' && bytes[3] == (byte)'0';
                int width = BitConverter.ToInt32(bytes, 4);
                int height = BitConverter.ToInt32(bytes, 8);
                SurfaceFormat format = raw ? SurfaceFormat.Color : SurfaceFormat.Rgba8Etc2;
                Texture2D texture = new Texture2D(Global.GraphicsDevice, width, height, false, format);
                texture.SetData(bytes, 12, bytes.Length - 12);
                _androidTextures.Add(imgName, texture);
                return texture;
            }
            catch (Exception)
            {
                return null;
            }
        }

        /// <summary>
        /// Disposes and removes the cached texture for the specified asset, freeing gpu memory.
        /// </summary>
        /// <param name="imgName">The image asset name.</param>
        public static void Free(string imgName)
        {
            if (_androidTextures.Remove(imgName, out Texture2D texture))
            {
                texture.Dispose();
            }
        }

        /// <summary>
        /// Cache of loaded android textures keyed by asset name, so each can be freed independently.
        /// </summary>
        private static readonly Dictionary<string, Texture2D> _androidTextures = [];
        /*//////////////////////////// android /////////////////////////////////*/
#else
        /// <summary>
        /// Returns the content manager used to load and unload a specific image asset.
        /// </summary>
        /// <param name="imgName">The image asset name.</param>
        /// <returns>The content manager associated with <paramref name="imgName"/>.</returns>
        private static ContentManager GetContentManager(string imgName)
        {
            _ = _contentManagers.TryGetValue(imgName, out ContentManager value);
            if (value == null)
            {
                value = new ContentManager(Global.XnaGame.Services, ContentPaths.RootDirectory);
                _contentManagers.Add(imgName, value);
            }
            return value;
        }

        /// <summary>
        /// Loads an image texture by asset name.
        /// </summary>
        /// <param name="imgName">The image asset name.</param>
        /// <returns>The loaded texture, or <see langword="null"/> if loading fails.</returns>
        public static Texture2D Get(string imgName)
        {
            ContentManager contentManager = GetContentManager(imgName);
            Texture2D result = null;
            Texture2D texture2D;
            try
            {
                result = contentManager.Load<Texture2D>(imgName);
                texture2D = result;
            }
            catch (Exception)
            {
                texture2D = result;
            }
            return texture2D;
        }

        /// <summary>
        /// Unloads the cached content manager for the specified image asset.
        /// </summary>
        /// <param name="imgName">The image asset name.</param>
        public static void Free(string imgName)
        {
            GetContentManager(imgName).Unload();
        }

        /// <summary>
        /// Stores per-image content managers so individual assets can be unloaded independently.
        /// </summary>
        private static readonly Dictionary<string, ContentManager> _contentManagers = [];
#endif
    }
}

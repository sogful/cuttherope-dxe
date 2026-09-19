using System.Collections.Generic;

using CutTheRopeDX.Desktop;
using CutTheRopeDX.Framework.Platform;

using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Input.Touch;

namespace CutTheRopeDX
{
    /// <summary>
    /// Reads the monogame touch panel and emits view-space touch locations matching the
    /// shape the shared canvas expects (mirrors <c>Desktop.MouseCursor.GetTouchLocation</c>).
    /// </summary>
    internal static class AndroidTouch
    {
        private static readonly List<TouchLocation> buffer = [];

        /// <summary>
        /// Returns the current frame's touches transformed into scaled-view space.
        /// </summary>
        public static List<TouchLocation> GetTouchLocations()
        {
            buffer.Clear();
            TouchCollection touches = TouchPanel.GetState();
            ScreenSizeManager ssm = Global.ScreenSizeManager;
            foreach (TouchLocation t in touches)
            {
                int vx = ssm.TransformWindowToViewX((int)t.Position.X);
                int vy = ssm.TransformWindowToViewY((int)t.Position.Y);
                buffer.Add(new TouchLocation(t.Id, t.State, new Vector2(vx, vy)));
            }
            return GLCanvas.ConvertTouches(buffer);
        }

        /// <summary>
        /// Gets the primary (first) active touch position in scaled-view space, for hover emulation.
        /// </summary>
        /// <param name="viewX">View-space X of the primary touch.</param>
        /// <param name="viewY">View-space Y of the primary touch.</param>
        /// <returns><see langword="true"/> if a touch is active; otherwise <see langword="false"/>.</returns>
        public static bool TryGetPrimary(out int viewX, out int viewY)
        {
            TouchCollection touches = TouchPanel.GetState();
            ScreenSizeManager ssm = Global.ScreenSizeManager;
            foreach (TouchLocation t in touches)
            {
                if (t.State is TouchLocationState.Pressed or TouchLocationState.Moved)
                {
                    viewX = ssm.TransformWindowToViewX((int)t.Position.X);
                    viewY = ssm.TransformWindowToViewY((int)t.Position.Y);
                    return true;
                }
            }
            viewX = 0;
            viewY = 0;
            return false;
        }
    }
}

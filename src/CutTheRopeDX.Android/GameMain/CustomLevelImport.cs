using System;

namespace CutTheRopeDX.GameMain
{
    /// <summary>
    /// Cross-platform bridge for importing custom level files. The android head wires
    /// <see cref="RequestImport"/> to the system file picker and sets <see cref="NeedsRefresh"/>
    /// once picked files are copied into the custom levels directory; the menu polls the flag
    /// on the game thread (MenuController.Update) and rebuilds the custom level list.
    /// </summary>
    internal static class CustomLevelImport
    {
        /// <summary>Platform hook that opens the file picker. Set by the android head; null elsewhere.</summary>
        public static Action RequestImport;

        /// <summary>Set true after files are imported, so the custom level view refreshes its list.</summary>
        public static volatile bool NeedsRefresh;

        /// <summary>Platform hook to show a short on-screen message (android toast). Null elsewhere.</summary>
        public static Action<string> ShowToast;
    }
}

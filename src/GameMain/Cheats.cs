namespace CutTheRopeDX.GameMain
{
    /// <summary>
    /// Holds the active cheat toggles. While any cheat is on the game saves to a separate
    /// profile (see <c>Preferences</c> cheat-save switching) so real progress is never touched.
    /// </summary>
    internal static class Cheats
    {
        /// <summary>All boxes and their levels are unlocked (runtime-only; never written to a save).</summary>
        public static bool UnlockAllBoxes { get; set; }

        /// <summary>Candy ignores hazards and never triggers a loss.</summary>
        public static bool Noclip { get; set; }

        /// <summary>Whether any cheat is currently enabled.</summary>
        public static bool AnyOn => UnlockAllBoxes || Noclip;
    }
}

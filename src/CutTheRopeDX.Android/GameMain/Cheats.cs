namespace CutTheRopeDX.GameMain
{
    internal static class Cheats
    {
        public static bool UnlockAllBoxes { get; set; }
        public static bool Noclip { get; set; }
        public static bool ShowFps { get; set; }
        public static bool AnyOn => UnlockAllBoxes || Noclip;
    }
}

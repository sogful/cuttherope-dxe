using System;
using System.Collections.Generic;
using System.IO;

using Android.App;
using Android.Content;
using Android.Content.PM;
using Android.OS;
using Android.Views;
using Android.Widget;

using CutTheRopeDX.GameMain;

using Microsoft.Xna.Framework;

namespace CutTheRopeDX
{
    /// <summary>
    /// Android entry point. Hosts the shared <see cref="Game1"/> inside a monogame android view,
    /// locked to landscape and drawn edge-to-edge in immersive fullscreen (no status/nav bars,
    /// extends into display cutouts) so the renderer sees the full physical surface.
    /// </summary>
    [Activity(
        MainLauncher = true,
        AlwaysRetainTaskState = true,
        LaunchMode = LaunchMode.SingleInstance,
        // window-level fullscreen (windowFullscreen=true): hides the status bar at creation,
        // which OEM skins like MIUI/HyperOS honor reliably where runtime InsetsController does not.
        Theme = "@android:style/Theme.NoTitleBar.Fullscreen",
        ScreenOrientation = ScreenOrientation.SensorLandscape,
        ConfigurationChanges = ConfigChanges.Orientation | ConfigChanges.Keyboard | ConfigChanges.KeyboardHidden | ConfigChanges.ScreenSize | ConfigChanges.UiMode)]
    public class MainActivity : AndroidGameActivity
    {
        private Game1 game;
        private View view;

        /// <inheritdoc />
        protected override void OnCreate(Bundle savedInstanceState)
        {
            base.OnCreate(savedInstanceState);

            // draw into display cutouts (notches) so the surface spans the whole screen
            if (Build.VERSION.SdkInt >= BuildVersionCodes.P)
            {
                WindowManagerLayoutParams attrs = Window.Attributes;
                attrs.LayoutInDisplayCutoutMode = LayoutInDisplayCutoutMode.ShortEdges;
                Window.Attributes = attrs;
            }
            Window.AddFlags(WindowManagerFlags.KeepScreenOn);
            GoImmersive();

            // let the Custom Box "Add Level" button open the system file picker
            CustomLevelImport.RequestImport = LaunchLevelPicker;
            CustomLevelImport.ShowToast = msg => RunOnUiThread(() => Toast.MakeText(this, msg, ToastLength.Short)?.Show());

            game = new Game1();
            view = game.Services.GetService(typeof(View)) as View;
            SetContentView(view);
            game.Run();
        }

        /// <inheritdoc />
        protected override void OnResume()
        {
            base.OnResume();
            GoImmersive();
        }

        /// <summary>
        /// Re-asserts immersive fullscreen whenever the activity regains focus (the system
        /// transiently restores the bars after dialogs, swipes, or resume).
        /// </summary>
        /// <param name="hasFocus">Whether the window now has focus.</param>
        public override void OnWindowFocusChanged(bool hasFocus)
        {
            base.OnWindowFocusChanged(hasFocus);
            if (hasFocus)
            {
                GoImmersive();
            }
        }

        /// <summary>
        /// Hides the status and navigation bars (sticky immersive) so the game owns the full screen.
        /// Applies both the legacy flags (which OEM skins like MIUI honor reliably) and the modern
        /// WindowInsetsController (api 30+), since neither alone covers every device.
        /// </summary>
        private void GoImmersive()
        {
            Window w = Window;
            if (w == null)
            {
                return;
            }
#pragma warning disable CS0618 // legacy fullscreen path: deprecated but still honored, incl. MIUI/older
            // MonoGame/MIUI sets FORCE_NOT_FULLSCREEN, which overrides FULLSCREEN + the immersive
            // sysui flags and forces the status bar to stay; clear it so fullscreen actually takes.
            w.ClearFlags(WindowManagerFlags.ForceNotFullscreen);
            w.AddFlags(WindowManagerFlags.Fullscreen);
            w.DecorView.SystemUiVisibility = (StatusBarVisibility)(
                SystemUiFlags.LayoutStable | SystemUiFlags.LayoutHideNavigation | SystemUiFlags.LayoutFullscreen |
                SystemUiFlags.HideNavigation | SystemUiFlags.Fullscreen | SystemUiFlags.ImmersiveSticky);
#pragma warning restore CS0618
            if (Build.VERSION.SdkInt >= BuildVersionCodes.R)
            {
                w.SetDecorFitsSystemWindows(false);
                var controller = w.DecorView?.WindowInsetsController ?? w.InsetsController;
                if (controller != null)
                {
                    controller.Hide(WindowInsets.Type.SystemBars());
                    controller.SystemBarsBehavior = 2; // BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                }
            }
        }

        /// <summary>Request code for the custom-level file picker.</summary>
        private const int PickLevelsRequest = 0x4C56;

        /// <summary>
        /// Opens the system document picker for level files (json + xml, multi-select).
        /// </summary>
        private void LaunchLevelPicker()
        {
            RunOnUiThread(() =>
            {
                try
                {
                    Intent intent = new Intent(Intent.ActionOpenDocument);
                    _ = intent.AddCategory(Intent.CategoryOpenable);
                    _ = intent.SetType("*/*");
                    intent.PutExtra(Intent.ExtraMimeTypes, new[] { "application/json", "text/xml", "application/xml" });
                    intent.PutExtra(Intent.ExtraAllowMultiple, true);
                    StartActivityForResult(Intent.CreateChooser(intent, "Select level files"), PickLevelsRequest);
                }
                catch (Exception)
                {
                }
            });
        }

        /// <inheritdoc />
        protected override void OnActivityResult(int requestCode, Result resultCode, Intent data)
        {
            base.OnActivityResult(requestCode, resultCode, data);
            if (requestCode != PickLevelsRequest || resultCode != Result.Ok || data == null)
            {
                return;
            }

            List<Android.Net.Uri> uris = [];
            if (data.ClipData != null)
            {
                for (int i = 0; i < data.ClipData.ItemCount; i++)
                {
                    uris.Add(data.ClipData.GetItemAt(i).Uri);
                }
            }
            else if (data.Data != null)
            {
                uris.Add(data.Data);
            }

            bool imported = false;
            foreach (Android.Net.Uri uri in uris)
            {
                try
                {
                    string name = QueryDisplayName(uri);
                    if (string.IsNullOrEmpty(name))
                    {
                        continue;
                    }
                    string ext = Path.GetExtension(name).ToLowerInvariant();
                    if (ext is not ".xml" and not ".json")
                    {
                        continue;
                    }
                    using Stream stream = ContentResolver.OpenInputStream(uri);
                    using MemoryStream ms = new();
                    stream.CopyTo(ms);
                    CustomLevels.ImportBytes(name, ms.ToArray());
                    imported = true;
                }
                catch (Exception)
                {
                }
            }
            if (imported)
            {
                CustomLevelImport.NeedsRefresh = true;
            }
            GoImmersive();
        }

        /// <summary>
        /// Resolves a content uri's display name (file name), or null if unavailable.
        /// </summary>
        /// <param name="uri">Content uri returned by the picker.</param>
        /// <returns>The file name, or <see langword="null"/>.</returns>
        private string QueryDisplayName(Android.Net.Uri uri)
        {
            try
            {
                using Android.Database.ICursor cursor = ContentResolver.Query(uri, null, null, null, null);
                if (cursor != null && cursor.MoveToFirst())
                {
                    int idx = cursor.GetColumnIndex("_display_name");
                    if (idx >= 0)
                    {
                        return cursor.GetString(idx);
                    }
                }
            }
            catch (Exception)
            {
            }
            return null;
        }
    }
}

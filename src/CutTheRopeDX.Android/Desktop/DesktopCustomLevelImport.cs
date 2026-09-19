#if !ANDROID
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

using CutTheRopeDX.GameMain;

namespace CutTheRopeDX.Desktop
{
    internal static class DesktopCustomLevelImport
    {
        public static void Install()
        {
            CustomLevelImport.RequestImport = RequestImport;
            CustomLevelImport.ShowToast = msg => Console.WriteLine($"[CustomBox] {msg}");
        }

        private static void RequestImport()
        {
            if (!OperatingSystem.IsWindows())
            {
                OpenLevelsFolder();
                return;
            }

            Thread thread = new Thread(PickAndImport){IsBackground = true};
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
        }
        private static void PickAndImport()
        {
            try
            {
                foreach (string path in ShowOpenDialog())
                {
                    try
                    {
                        CustomLevels.ImportBytes(Path.GetFileName(path), File.ReadAllBytes(path));
                    }
                    catch (Exception)
                    {
                    }
                }
                CustomLevelImport.NeedsRefresh = true;
            }
            catch (Exception)
            {
            }
        }
        private static void OpenLevelsFolder()
        {
            try
            {
                string dir = CustomLevels.LevelsDir;
                CustomLevelImport.ShowToast?.Invoke($"Drop .xml / .json levels into: {dir}");
                _ = Process.Start(new ProcessStartInfo{FileName = dir, UseShellExecute = true});
            }
            catch (Exception)
            {
            }
        }

        /*//////////////////////////// windows //////////////////////////////////*/

        private static string[] ShowOpenDialog()
        {
            const int bufferChars = 64 * 1024;
            OpenFileName ofn = new OpenFileName();
            ofn.lStructSize = Marshal.SizeOf<OpenFileName>();
            ofn.lpstrFilter = "Cut the Rope levels (*.xml;*.json)\0*.xml;*.json\0All files (*.*)\0*.*\0\0";
            ofn.nFilterIndex = 1;
            ofn.lpstrFile = new string('\0', bufferChars);
            ofn.nMaxFile = bufferChars;
            ofn.lpstrInitialDir = CustomLevels.LevelsDir;
            ofn.lpstrTitle = "Choose any valid level file!";
            ofn.Flags = OFN_EXPLORER | OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR | OFN_ALLOWMULTISELECT;

            return !GetOpenFileName(ref ofn) ? [] : ParseSelection(ofn.lpstrFile);
        }

        /// <param name="buffer">Raw null-separated buffer returned by the dialog.</param>
        /// <returns>Absolute paths of the selected files.</returns>
        private static string[] ParseSelection(string buffer)
        {
            string[] parts = buffer.Split('\0', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 0)
            {
                return [];
            }
            if (parts.Length == 1)
            {
                return parts;
            }
            string dir = parts[0];
            string[] files = new string[parts.Length - 1];
            for (int i = 1; i < parts.Length; i++)
            {
                files[i - 1] = Path.Combine(dir, parts[i]);
            }
            return files;
        }

        private const int OFN_ALLOWMULTISELECT = 0x00000200;
        private const int OFN_NOCHANGEDIR = 0x00000008;
        private const int OFN_PATHMUSTEXIST = 0x00000800;
        private const int OFN_FILEMUSTEXIST = 0x00001000;
        private const int OFN_EXPLORER = 0x00080000;

        [DllImport("comdlg32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool GetOpenFileName(ref OpenFileName ofn);

        /// <summary>Win32 OPENFILENAME marshalling struct for the open-file dialog.</summary>
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct OpenFileName
        {
            public int lStructSize;
            public IntPtr hwndOwner;
            public IntPtr hInstance;
            public string lpstrFilter;
            public string lpstrCustomFilter;
            public int nMaxCustFilter;
            public int nFilterIndex;
            public string lpstrFile;
            public int nMaxFile;
            public string lpstrFileTitle;
            public int nMaxFileTitle;
            public string lpstrInitialDir;
            public string lpstrTitle;
            public int Flags;
            public short nFileOffset;
            public short nFileExtension;
            public string lpstrDefExt;
            public IntPtr lCustData;
            public IntPtr lpfnHook;
            public string lpTemplateName;
            public IntPtr pvReserved;
            public int dwReserved;
            public int FlagsEx;
        }
        /*//////////////////////////// windows //////////////////////////////////*/
    }
}
#endif

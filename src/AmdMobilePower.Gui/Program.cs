using System.Runtime.InteropServices;

namespace AmdMobilePower.Gui;

internal static class Program
{
    private const string MutexName = "Local\\AmdMobilePower.Gui.v2";
    private const string ShowEventName = "Local\\AmdMobilePower.Show.v2";
    private const string AppUserModelId = "AmdMobilePower.Desktop";

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    private static extern void SetCurrentProcessExplicitAppUserModelID(string appId);

    [STAThread]
    private static void Main(string[] args)
    {
        bool startHidden = args.Contains("--tray", StringComparer.OrdinalIgnoreCase);
        bool enableWriteControls = args.Contains(
            "--enable-write-controls",
            StringComparer.OrdinalIgnoreCase);

        using Mutex mutex = new(initiallyOwned: true, MutexName, out bool ownsMutex);
        if (!ownsMutex)
        {
            SignalExistingInstance();
            return;
        }

        try
        {
            SetCurrentProcessExplicitAppUserModelID(AppUserModelId);
        }
        catch
        {
        }

        ApplicationConfiguration.Initialize();
        using EventWaitHandle showEvent = new(
            initialState: false,
            EventResetMode.AutoReset,
            ShowEventName);
        using MainForm form = new(showEvent, startHidden, enableWriteControls);
        Application.Run(form);
        GC.KeepAlive(mutex);
    }

    private static void SignalExistingInstance()
    {
        for (int attempt = 0; attempt < 12; attempt++)
        {
            try
            {
                using EventWaitHandle showEvent = EventWaitHandle.OpenExisting(ShowEventName);
                showEvent.Set();
                return;
            }
            catch (WaitHandleCannotBeOpenedException)
            {
                Thread.Sleep(100);
            }
        }
    }
}

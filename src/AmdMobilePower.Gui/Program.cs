using System.Runtime.InteropServices;
using AmdMobilePower.Core.Diagnostics;

namespace AmdMobilePower.Gui;

internal static class Program
{
    private const string MutexName = "Local\\AmdMobilePower.Gui.v2";
    private const string ShowEventName = "Local\\AmdMobilePower.Show.v2";
    private const string AppUserModelId = "AmdMobilePower.Desktop";

    [DefaultDllImportSearchPaths(DllImportSearchPath.SafeDirectories)]
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    private static extern void SetCurrentProcessExplicitAppUserModelID(string appId);

    [STAThread]
    private static void Main(string[] args)
    {
        bool startHidden = args.Contains("--tray", StringComparer.OrdinalIgnoreCase);
        bool enableWriteControls = args.Contains(
            "--enable-write-controls",
            StringComparer.OrdinalIgnoreCase);
        bool startInSimpleMode = args.Contains(
            "--simple-mode",
            StringComparer.OrdinalIgnoreCase);
        AppDiagnostics.Gui.Info(
            $"GUI starting. Tray={startHidden}; writes={enableWriteControls}.");
        AppDomain.CurrentDomain.UnhandledException += delegate (object sender, UnhandledExceptionEventArgs eventArgs)
        {
            Exception? error = eventArgs.ExceptionObject as Exception;
            AppDiagnostics.Gui.Error(
                $"Unhandled GUI exception. Terminating={eventArgs.IsTerminating}.",
                error);
        };
        TaskScheduler.UnobservedTaskException += delegate (object? sender, UnobservedTaskExceptionEventArgs eventArgs)
        {
            AppDiagnostics.Gui.Error("Unobserved GUI task exception.", eventArgs.Exception);
            eventArgs.SetObserved();
        };

        using Mutex mutex = new(initiallyOwned: true, MutexName, out bool ownsMutex);
        if (!ownsMutex)
        {
            AppDiagnostics.Gui.Info("Existing GUI instance found; requesting wake-up.");
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
        using MainForm form = new(
            showEvent,
            startHidden,
            enableWriteControls,
            startInSimpleMode ? UiMode.Simple : null);
        try
        {
            Application.Run(form);
        }
        finally
        {
            AppDiagnostics.Gui.Info($"GUI stopping. ExitCode={Environment.ExitCode}.");
            GC.KeepAlive(mutex);
        }
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
        AppDiagnostics.Gui.Warning("Existing GUI wake-up event was unavailable.");
    }
}

// Zen Browser Portable - community launcher. Compatible with Windows .NET Framework 4.x.
// Keep user profile in sibling Data folder; never launch App/Zen/zen.exe directly.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

internal static class ZenBrowserPortable
{
    // Lightweight, local evidence that the root launcher handled each phase.
    // Log failures must NEVER prevent the browser from starting or closing.
    private static void LogLauncher(string root, string message)
    {
        try
        {
            string dir = Path.Combine(root, @"Data\UpdaterCleanup");
            Directory.CreateDirectory(dir);
            File.AppendAllText(Path.Combine(dir, "launcher.log"),
                "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "] " + message + Environment.NewLine,
                new UTF8Encoding(false));
        }
        catch (Exception) { /* Optional diagnostics only. */ }
    }

    // Automatically clean shortcuts that point to THIS portable installation.
    // Install-specific update folder is derived automatically at each launch.
    // Never elevate, recursively delete Mozilla data, or touch unknown files.
    private static void TryPostExitCleanup(string root, string installHash)
    {
        string script = Path.Combine(root, @"Other\ZenUpdateCleanup.ps1");
        if (!File.Exists(script))
        {
            LogLauncher(root, "SKIP: cleanup helper is missing; install the complete build.");
            return;
        }
        try
        {
            string powerShell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                @"System32\WindowsPowerShell\v1.0\powershell.exe");
            var psi = new ProcessStartInfo(powerShell);
            psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + script +
                "\" -Mode Clean -Root \"" + root + "\" -InstallHash " + installHash;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            LogLauncher(root, "Automatic post-exit cleanup started.");
            using (Process cleaner = Process.Start(psi))
            {
                if (cleaner == null)
                {
                    LogLauncher(root, "SKIP: Windows did not start the cleanup process.");
                    return;
                }
                if (!cleaner.WaitForExit(90000))
                {
                    LogLauncher(root, "WARNING: cleanup exceeded 90 seconds; terminating helper.");
                    cleaner.Kill();
                    cleaner.WaitForExit();
                }
                LogLauncher(root, "Automatic cleanup finished (exit code " + cleaner.ExitCode +
                    "). See cleanup.log for individual paths.");
            }
        }
        catch (Exception ex)
        {
            LogLauncher(root, "WARNING: cleanup did not complete: " + ex.Message);
        }
    }

    // Run the Windows registry guard as this user, never as administrator.
    // A pre-launch snapshot is required; the after-run restore is best-effort
    // and runs only when no Zen processes are present.
    private static bool RegistryGuard(string root, string mode)
    {
        string script = Path.Combine(root, @"Other\ZenRegistryGuard.ps1");
        if (!File.Exists(script))
        {
            LogLauncher(root, "ERROR: Registry guard helper missing: " + script);
            return false;
        }
        try
        {
            string powerShell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                @"System32\WindowsPowerShell\v1.0\powershell.exe");
            var psi = new ProcessStartInfo(powerShell);
            psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + script +
                "\" -Mode " + mode + " -Root \"" + root + "\"";
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            using (Process helper = Process.Start(psi))
            {
                if (helper == null) return false;
                if (!helper.WaitForExit(30000))
                {
                    LogLauncher(root, "ERROR: Registry guard " + mode + " timed out.");
                    // Do not kill an in-progress registry restore.
                    return false;
                }
                LogLauncher(root, "Registry guard " + mode + " exit code " + helper.ExitCode + ".");
                return helper.ExitCode == 0;
            }
        }
        catch (Exception ex)
        {
            LogLauncher(root, "ERROR: Registry guard " + mode + ": " + ex.Message);
            return false;
        }
    }

    // The initial zen.exe process may exit while other Zen processes are still
    // loading or while the actual browser remains open. Waiting only for that
    // initial PID caused cleanup to run during the browsing session.
    // Match the PowerShell helper's conservative safety rule: do not clean host
    // files while ANY zen.exe is active. Never forcibly stop browser processes.
    // Unlike the short helper safety timeout, keep this launcher waiting for
    // the user's normal browser shutdown (which may take hours).
    private static bool WaitForZenShutdown(string root)
    {
        int quietChecks = 0;
        int elapsedSeconds = 0;
        bool reported = false;
        while (quietChecks < 5)
        {
            Process[] active;
            try
            {
                active = Process.GetProcessesByName("zen");
            }
            catch (Exception ex)
            {
                LogLauncher(root, "SKIP: could not check Zen processes safely: " + ex.Message);
                return false;
            }

            int count = active.Length;
            foreach (Process process in active) process.Dispose();
            if (count == 0)
            {
                quietChecks++;
            }
            else
            {
                quietChecks = 0;
                if (!reported || elapsedSeconds % 60 == 0)
                {
                    LogLauncher(root, "Zen still has " + count +
                        " running process(es). Waiting for browser to fully close; no cleanup yet.");
                    reported = true;
                }
            }

            if (quietChecks >= 5) break;
            System.Threading.Thread.Sleep(1000);
            elapsedSeconds++;
        }
        LogLauncher(root, "All zen.exe processes closed and remained absent; starting safe cleanup.");
        return true;
    }

    // Best-effort: these preferences discourage Windows shortcut integration.
    // Zen/Firefox can still create shortcuts on some builds: the post-exit
    // verifier remains essential. Never turn off Private Browsing itself.
    private static void EnsurePortablePreferences(string root, string profile)
    {
        string userJs = Path.Combine(profile, "user.js");
        string contents = File.Exists(userJs) ? File.ReadAllText(userJs) :
            "// Zen Portable profile defaults. Preserve this file inside Data.\r\n" +
            "user_pref(\"browser.shell.checkDefaultBrowser\", false);\r\n" +
            "user_pref(\"app.update.auto\", false);\r\n" +
            "user_pref(\"app.update.enabled\", false);\r\n";
        string original = contents;
        foreach (string preference in new string[] {
            "browser.shell.customIcon.enabled", "browser.privacySegmentation.enabled"
        })
        {
            // Replace only the named user_pref line; do not replace or erase
            // any unrelated preferences, bookmarks, sessions or extensions.
            string pattern = @"(?m)^[ \t]*user_pref\([ \t]*""" +
                Regex.Escape(preference) + @"""[ \t]*,[ \t]*(?:true|false)[ \t]*\);[ \t]*\r?\n?";
            contents = Regex.Replace(contents, pattern, "");
            contents = contents.TrimEnd('\r', '\n') + "\r\n" +
                "user_pref(\"" + preference + "\", false);\r\n";
        }
        if (File.Exists(userJs) && contents == original) return;
        if (File.Exists(userJs))
        {
            string backups = Path.Combine(root, @"Data\UpdaterCleanup\Backups");
            Directory.CreateDirectory(backups);
            string dest = Path.Combine(backups, "user.js.before-shortcut-fix-" +
                DateTime.Now.ToString("yyyyMMdd-HHmmss-fff") + ".bak");
            File.Copy(userJs, dest, false);
        }
        File.WriteAllText(userJs, contents, new UTF8Encoding(false));
    }

    [STAThread]
    private static int Main(string[] args)
    {
        string root = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
        string exe = Path.Combine(root, @"App\Zen\zen.exe");
        string profile = Path.Combine(root, @"Data\Profile");
        string temp = Path.Combine(root, @"Data\Temp");
        // These environment variables are changed ONLY for this child process.
        // Some Windows shell APIs ignore them, so verified post-exit cleanup remains.
        string roaming = Path.Combine(root, @"Data\HostEnvironment\Roaming");
        string local = Path.Combine(root, @"Data\HostEnvironment\Local");
        string installHash = InstallHash.ForDirectory(Path.GetDirectoryName(exe));
        bool registryOutstanding = false;
        try
        {
            if (!File.Exists(exe))
            {
                MessageBox.Show("Missing App\\Zen\\zen.exe. Please extract the whole ZIP.",
                    "Zen Browser Portable", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 2;
            }
            if (args.Length > 0)
            {
                // Arbitrary startup switches could override --profile or update policy.
                MessageBox.Show("This launcher does not accept command-line arguments. Open URLs inside Zen.",
                    "Zen Browser Portable", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return 3;
            }
            Directory.CreateDirectory(profile);
            Directory.CreateDirectory(temp);
            Directory.CreateDirectory(roaming);
            Directory.CreateDirectory(local);
            // One active portable launcher to reduce conflicting write access to the profile.
            using (var gate = new System.Threading.Mutex(false, @"Local\ZenBrowserPortable_Community_Launcher"))
            {
                bool owns = false;
                try
                {
                    try { owns = gate.WaitOne(0); }
                    catch (System.Threading.AbandonedMutexException) { owns = true; }
                    if (!owns)
                    {
                        MessageBox.Show("A Zen Browser Portable launcher is already running. Close it first.",
                            "Zen Browser Portable", MessageBoxButtons.OK, MessageBoxIcon.Information);
                        return 4;
                    }
                    // Do not run alongside a different installed Zen instance:
                    // snapshotting its registry would risk losing its changes.
                    Process[] otherZen = Process.GetProcessesByName("zen");
                    int otherCount = otherZen.Length;
                    foreach (Process process in otherZen) process.Dispose();
                    if (otherCount != 0)
                    {
                        MessageBox.Show("Another Zen Browser is already running. Close it before starting the portable copy.",
                            "Zen Browser Portable", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                        return 6;
                    }
                    // Snapshot the HKCU Zen registry tree BEFORE launching the browser.
                    // If snapshot fails, don't run an unprotected session.
                    if (!RegistryGuard(root, "Before"))
                    {
                        MessageBox.Show("Cannot safeguard Windows Zen registry settings. See Data\\HostEnvironment\\Registry\\registry.log.",
                            "Zen Browser Portable", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        return 7;
                    }
                    registryOutstanding = true;
                    // Apply settings after the single-instance lock is held.
                    EnsurePortablePreferences(root, profile);
                    LogLauncher(root, "Portable setup automatic; updater ID " + installHash + "; starting Zen.");
                    var psi = new ProcessStartInfo(exe);
                    psi.UseShellExecute = false;
                    psi.WorkingDirectory = Path.GetDirectoryName(exe);
                    psi.Arguments = "--no-remote --profile \"" + profile + "\"";
                    psi.EnvironmentVariables["TEMP"] = temp;
                    psi.EnvironmentVariables["TMP"] = temp;
                    psi.EnvironmentVariables["APPDATA"] = roaming;
                    psi.EnvironmentVariables["LOCALAPPDATA"] = local;
                    psi.EnvironmentVariables["MOZ_CRASHREPORTER_DISABLE"] = "1";
                    // No global PATH, registry or default-browser modifications.
                    using (Process child = Process.Start(psi))
                    {
                        if (child == null) throw new InvalidOperationException("Could not launch Zen.");
                        LogLauncher(root, "Portable Zen started (PID " + child.Id + ").");
                        try
                        {
                            child.WaitForExit();
                            LogLauncher(root, "Portable Zen exited (code " + child.ExitCode + ").");
                            return child.ExitCode;
                        }
                        finally
                        {
                            // Wait for ALL Zen processes, not just the first launched PID.
                            // May stay active until the user's actual browser session ends.
                            // The PowerShell helper still rechecks before deleting anything.
                            if (WaitForZenShutdown(root))
                            {
                                try { TryPostExitCleanup(root, installHash); }
                                finally
                                {
                                    // Run even when updater cleanup skipped an unknown file.
                                    if (RegistryGuard(root, "After")) registryOutstanding = false;
                                }
                            }
                        }
                    }
                }
                finally { if (owns) gate.ReleaseMutex(); }
            }
        }
        catch (Exception exc)
        {
            // Covers launch failure after a successful pre-launch registry snapshot.
            if (registryOutstanding && WaitForZenShutdown(root))
            {
                if (RegistryGuard(root, "After")) registryOutstanding = false;
            }
            LogLauncher(root, "ERROR: launcher failed: " + exc.Message);
            MessageBox.Show(exc.Message, "Zen Browser Portable error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}

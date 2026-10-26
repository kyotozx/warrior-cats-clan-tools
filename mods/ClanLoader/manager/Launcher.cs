using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.Windows.Forms;

// Windows GUI host: the same reviewed PowerShell backend is used by the GUI
// and automated installer tests. No terminal window or elevated token needed.
internal static class ClanLoaderLauncher {
    internal static Runspace CreateManagerRunspace() {
        // Limit the policy to this host process. Domain Group Policy still wins;
        // no machine/user policy changes or elevated permissions are required.
        InitialSessionState state=InitialSessionState.CreateDefault();
        state.ExecutionPolicy=Microsoft.PowerShell.ExecutionPolicy.Bypass;
        Runspace runspace=RunspaceFactory.CreateRunspace(state);
        runspace.ApartmentState=ApartmentState.STA;
        runspace.ThreadOptions=PSThreadOptions.UseCurrentThread;
        return runspace;
    }
    [STAThread]
    private static void Main() {
        try {
            string root=AppDomain.CurrentDomain.BaseDirectory;
            using (Runspace runspace=CreateManagerRunspace()) {
                runspace.Open();
                using (PowerShell ps=PowerShell.Create()) {
                    ps.Runspace=runspace;
                    ps.AddCommand(Path.Combine(root,"Manager.ps1"));
                    ps.Invoke();
                    if (ps.HadErrors) throw new InvalidOperationException(ps.Streams.Error[0].ToString());
                }
            }
        } catch (Exception e) {
            MessageBox.Show(e.Message,"Clan Loader",MessageBoxButtons.OK,MessageBoxIcon.Error);
        }
    }
}

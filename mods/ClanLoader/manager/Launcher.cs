using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.Windows.Forms;

// Windows GUI host: the same reviewed PowerShell backend is used by the GUI
// and automated installer tests. No terminal window or elevated token needed.
internal static class ClanLoaderLauncher {
    [STAThread]
    private static void Main() {
        try {
            string root=AppDomain.CurrentDomain.BaseDirectory;
            using (Runspace runspace=RunspaceFactory.CreateRunspace()) {
                runspace.ApartmentState=ApartmentState.STA;
                runspace.ThreadOptions=PSThreadOptions.UseCurrentThread;
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

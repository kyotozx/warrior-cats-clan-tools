using System;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

internal static class LauncherPolicyTest {
    private static string Policy(Runspace runspace, string scope) {
        using (PowerShell ps=PowerShell.Create()) {
            ps.Runspace=runspace;
            ps.AddCommand("Get-ExecutionPolicy").AddParameter("Scope",scope);
            return ps.Invoke()[0].ToString();
        }
    }
    [STAThread]
    private static void Main(string[] args) {
        using (Runspace original=RunspaceFactory.CreateRunspace()) {
            original.Open();
            foreach (string scope in new [] { "MachinePolicy", "UserPolicy" })
                if (Policy(original,scope)!="Undefined")
                    throw new Exception("Run this fixture without configured Group Policy. Managed policy must not be changed.");
            string user=Policy(original,"CurrentUser"), machine=Policy(original,"LocalMachine");
            using (PowerShell ps=PowerShell.Create()) {
                ps.Runspace=original;
                ps.AddCommand("Set-ExecutionPolicy").AddParameter("Scope","Process")
                    .AddParameter("ExecutionPolicy","Restricted").AddParameter("Force");
                ps.Invoke();
                if (ps.HadErrors) throw new Exception("Cannot set isolated test process policy.");
            }
            bool blocked=false;
            using (PowerShell ps=PowerShell.Create()) {
                ps.Runspace=original; ps.AddCommand(args[0]);
                try { ps.Invoke(); blocked=ps.HadErrors; }
                catch (RuntimeException) { blocked=true; }
            }
            if (!blocked) throw new Exception("Baseline did not reproduce the script restriction.");
            Console.WriteLine("PASS original host rejects scripts under Restricted policy");
            using (Runspace manager=ClanLoaderLauncher.CreateManagerRunspace()) {
                manager.Open();
                using (PowerShell ps=PowerShell.Create()) {
                    ps.Runspace=manager; ps.AddCommand(args[0]);
                    var result=ps.Invoke();
                    if (ps.HadErrors || result.Count!=1 || result[0].ToString()!="helper-loaded")
                        throw new Exception("Manager host failed to run the downloaded fixture and dot-sourced helper.");
                }
                if (Policy(manager,"CurrentUser")!=user || Policy(manager,"LocalMachine")!=machine)
                    throw new Exception("Persistent execution policy changed.");
            }
            Console.WriteLine("PASS manager host runs marked downloaded scripts and resolves PSScriptRoot");
            Console.WriteLine("PASS CurrentUser and LocalMachine policies unchanged");
        }
    }
}

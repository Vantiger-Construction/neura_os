using System;
using Neura.Presence.Tests;

public static class ContractTestRunner
{
    public static int Main()
    {
        int count = 0;
        foreach (string name in ContractCases.Names)
        {
            try { ContractCases.Run(name); Console.WriteLine("PASS " + name); count++; }
            catch (InvalidOperationException error) { Console.Error.WriteLine("FAIL " + name + ": " + error.Message); return 1; }
        }
        Console.WriteLine(count + " core scenarios passed (includes 270 presentation combinations).");
        int bridge = 0;
        foreach (string name in BridgeCases.Names)
        {
            try { BridgeCases.Run(name); Console.WriteLine("PASS " + name); bridge++; }
            catch (InvalidOperationException error) { Console.Error.WriteLine("FAIL " + name + ": " + error.Message); return 1; }
        }
        Console.WriteLine(bridge + " live-bridge protocol scenarios passed.");
        return 0;
    }
}

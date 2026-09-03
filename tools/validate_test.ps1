#requires -Version 5.1
<#
.SYNOPSIS
Tests validate.ps1 using an isolated fake executable; no game or export is run.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
# .NET Framework can emit a small test .exe without an external compiler. PowerShell
# 7's Add-Type cannot, so route this self-test through the supported Windows shell.
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$testId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '_' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$fixtureDirectory = Join-Path $projectRoot ('build\validation\selftest_' + $testId + '\fixture with spaces')
[void] [IO.Directory]::CreateDirectory($fixtureDirectory)
$fixtureExe = Join-Path $fixtureDirectory 'Fake Godot.exe'
$runner = Join-Path $PSScriptRoot 'validate.ps1'
# Run the actual command-line entry point under Windows PowerShell 5.1, even if
# the test itself was launched from PowerShell 7.
$testEnvironmentBefore = [Environment]::GetEnvironmentVariable('NIGHTWATCH_VALIDATION_TEST_CASE')
$checks = 0

$fixtureSource = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
public static class FakeGodot {
    public static int Main(string[] args) {
        Console.OutputEncoding = new UTF8Encoding(false);
        string mode = Environment.GetEnvironmentVariable("NIGHTWATCH_VALIDATION_TEST_CASE");
        if (mode == "sentinel") { Thread.Sleep(60000); return 0; }
        if (Array.IndexOf(args, "--fixture-tree-child") >= 0) {
            Console.WriteLine("FAKE_TREE_CHILD_READY:" + Process.GetCurrentProcess().Id);
            Thread.Sleep(60000);
            return 0;
        }
        Console.WriteLine("FAKE_PID:" + Process.GetCurrentProcess().Id);
        Console.WriteLine("FAKE_CWD:" + Environment.CurrentDirectory);
        string script = "";
        for (int i = 0; i + 1 < args.Length; ++i) {
            if (args[i] == "--script") { script = Path.GetFileNameWithoutExtension(args[i + 1]); }
        }
        string marker;
        switch (script) {
            case "research_contract_test": marker = "RESEARCH_CONTRACT_PASS"; break;
            case "smoke_test": marker = "SMOKE_TEST_PASS"; break;
            case "observation_span_probe": marker = "OBSERVATION_SPAN_PASS"; break;
            case "galactic_slice_test": marker = "GALACTIC_SLICE_PASS"; break;
            case "probe_layer2_test": marker = "PROBE_TEST_PASS"; break;
            case "sound_feedback_test": marker = "SOUND_FEEDBACK_PASS"; break;
            case "effect_feedback_test": marker = "EFFECT_FEEDBACK_PASS"; break;
            case "reference_capture_test": marker = "REFERENCE_CAPTURE_TEST_PASS"; break;
            case "research_visual_test": marker = "RESEARCH_VISUAL_PASS"; break;
            case "ui_presentation_test": marker = "UI_PRESENTATION_PASS"; break;
            case "game_fixture_test": marker = "GAME_FIXTURE_PASS"; break;
            case "meteor_render_cache_test": marker = "METEOR_RENDER_CACHE_PASS"; break;
            case "full_tree_economy_test": marker = "FULL_TREE_ECONOMY_PASS"; break;
            default: Console.Error.WriteLine("Unknown script: " + script); return 19;
        }
        Console.Error.WriteLine("WARNING: ObjectDB instances leaked at exit (run with --verbose for details).");
        if (script == "reference_capture_test" || mode == "git_error_wrong_gate") {
            string missingGit = Path.Combine(Environment.CurrentDirectory, "build", "nonexistent-reference-capture-git.exe");
            if (mode == "git_error_wrong_path") { missingGit += ".unexpected"; }
            Console.Error.WriteLine("ERROR: Could not create child process: " + missingGit + " -C " + Environment.CurrentDirectory.Replace('\\', '/') + "/ rev-parse HEAD");
        }
        if (mode == "no_marker") { Console.WriteLine("NOT_" + marker + ": no real marker"); return 0; }
        Console.WriteLine(marker + ": fake fixture");
        if (mode == "nonzero") { return 7; }
        if (mode == "script_error") { Console.Error.WriteLine("SCRIPT ERROR: deliberate error after PASS"); }
        if (mode == "parse_error") { Console.WriteLine("Parse Error: deliberate error after PASS"); }
        if (mode == "native_error") { Console.Error.WriteLine("ERROR: deliberate unknown engine error after PASS"); }
        if (mode == "timeout") { Thread.Sleep(30000); }
        if (mode == "timeout_tree") {
            string executable = Process.GetCurrentProcess().MainModule.FileName;
            var start = new ProcessStartInfo(executable, "--fixture-tree-child");
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            // Forces Framework's standard-handle setup while stdout/stderr themselves
            // remain inherited, reproducing Godot's console-wrapper output pipes.
            start.RedirectStandardInput = true;
            var child = Process.Start(start);
            File.WriteAllText(Path.Combine(Path.GetDirectoryName(executable), "tree-child.pid"), child.Id.ToString());
            Console.WriteLine("FAKE_TREE_CHILD_PID:" + child.Id);
            Thread.Sleep(30000);
        }
        return 0;
    }
}
'@
Add-Type -TypeDefinition $fixtureSource -Language CSharp -OutputAssembly $fixtureExe -OutputType ConsoleApplication

function Assert-Check([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
    $script:checks += 1
}

function Invoke-RunnerCase([string] $Mode, [switch] $Economy) {
    $process = New-Object Diagnostics.Process
    $process.StartInfo = New-Object Diagnostics.ProcessStartInfo
    $process.StartInfo.FileName = $windowsPowerShell
    $process.StartInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $runner + '" -GodotPath "' + $fixtureExe + '" -TimeoutSeconds 1 -EconomyTimeoutSeconds 2'
    if ($Economy) { $process.StartInfo.Arguments += ' -FullEconomy' }
    $process.StartInfo.WorkingDirectory = $fixtureDirectory
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    # This changes only the new process environment, not this shell or the user's settings.
    $process.StartInfo.EnvironmentVariables['NIGHTWATCH_VALIDATION_TEST_CASE'] = $Mode
    try {
        [void] $process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            $process.Kill()
            [void] $process.WaitForExit(5000)
            throw "Runner self-test hung: $Mode"
        }
        if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]] @($stdoutTask, $stderrTask), 5000)) {
            throw "Runner output did not close: $Mode"
        }
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        [IO.File]::WriteAllText((Join-Path $fixtureDirectory ($Mode + '.runner.stdout.log')), $stdout)
        [IO.File]::WriteAllText((Join-Path $fixtureDirectory ($Mode + '.runner.stderr.log')), $stderr)
        $summaryMatch = [regex]::Match($stdout, '(?m)^VALIDATION_SUMMARY: (.+?)\r?$')
        Assert-Check $summaryMatch.Success ("No summary for $Mode : $stdout $stderr")
        $caseSummaryPath = $summaryMatch.Groups[1].Value
        $caseSummary = Get-Content -LiteralPath $caseSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return [pscustomobject]@{ exit_code = $process.ExitCode; summary = $caseSummary; path = $caseSummaryPath; stdout = $stdout }
    } finally { $process.Dispose() }
}

$sentinel = $null
try {
    $success = Invoke-RunnerCase 'success'
    Assert-Check ($success.exit_code -eq 0 -and $success.summary.status -eq 'passed') 'Success case failed.'
    Assert-Check ($success.summary.results.Count -eq 12) 'The default suite must run exactly twelve gates.'
    Assert-Check ($success.summary.project_root -eq $projectRoot) 'Runner did not resolve the repository root.'
    foreach ($result in $success.summary.results) {
        Assert-Check ($result.pass_marker_found -and $result.exit_code -eq 0) ('Missing success evidence for ' + $result.name)
        $output = Get-Content -LiteralPath $result.stdout_log -Raw -Encoding UTF8
        Assert-Check ($output.Contains('FAKE_CWD:' + $projectRoot)) ('Wrong working directory for ' + $result.name)
    }
    $referenceErrorLog = $success.summary.results | Where-Object { $_.name -eq 'reference_capture_test' } | Select-Object -ExpandProperty stderr_log
    Assert-Check ((Get-Content -LiteralPath $referenceErrorLog -Raw).Contains('nonexistent-reference-capture-git.exe -C ')) 'Expected native-error fixture was not exercised.'

    $economy = Invoke-RunnerCase 'economy' -Economy
    Assert-Check ($economy.exit_code -eq 0 -and $economy.summary.results.Count -eq 13) 'FullEconomy did not append the economy gate.'
    Assert-Check ($economy.summary.results[12].name -eq 'full_tree_economy_test') 'Wrong economy gate order.'
    Assert-Check ($economy.path -ne $success.path) 'Separate invocations reused a summary path.'

    foreach ($mode in @('no_marker', 'nonzero', 'script_error', 'parse_error', 'native_error', 'git_error_wrong_gate')) {
        $failure = Invoke-RunnerCase $mode
        Assert-Check ($failure.exit_code -ne 0 -and $failure.summary.status -eq 'failed') ("False success for $mode")
        Assert-Check ($failure.summary.results.Count -eq 1) ("Did not stop at the first failure for $mode")
        $result = $failure.summary.results[0]
        switch ($mode) {
            'no_marker' { Assert-Check (-not $result.pass_marker_found) 'Accepted an embedded/spoofed PASS marker.' }
            'nonzero' { Assert-Check ($result.exit_code -eq 7 -and $result.pass_marker_found) 'Did not reject PASS with a nonzero exit.' }
            { $_ -in @('native_error', 'git_error_wrong_gate') } {
                Assert-Check ($result.pass_marker_found -and ($result.failures -like 'Unexpected Godot engine error:*').Count -gt 0) 'Ignored an unexpected native ERROR after PASS or outside the reference gate.'
            }
            default { Assert-Check ($result.pass_marker_found -and ($result.failures -contains 'Godot script/parse error in output')) 'Ignored an error printed after PASS.' }
        }
    }

    $wrongGitPath = Invoke-RunnerCase 'git_error_wrong_path'
    Assert-Check ($wrongGitPath.exit_code -ne 0 -and $wrongGitPath.summary.status -eq 'failed') 'Accepted a different missing executable in the reference gate.'
    Assert-Check ($wrongGitPath.summary.results.Count -eq 8 -and $wrongGitPath.summary.results[7].name -eq 'reference_capture_test') 'Wrong-path fixture did not reach and stop at the reference gate.'
    Assert-Check ($wrongGitPath.summary.results[7].pass_marker_found -and ($wrongGitPath.summary.results[7].failures -like 'Unexpected Godot engine error:*').Count -gt 0) 'Reference exception was not restricted to the exact expected path.'

    # Keep a separate fake executable alive to catch unsafe name-based timeout cleanup.
    $sentinel = New-Object Diagnostics.Process
    $sentinel.StartInfo = New-Object Diagnostics.ProcessStartInfo
    $sentinel.StartInfo.FileName = $fixtureExe
    $sentinel.StartInfo.UseShellExecute = $false
    $sentinel.StartInfo.CreateNoWindow = $true
    $sentinel.StartInfo.EnvironmentVariables['NIGHTWATCH_VALIDATION_TEST_CASE'] = 'sentinel'
    [void] $sentinel.Start()
    $timeout = Invoke-RunnerCase 'timeout'
    Assert-Check ($timeout.exit_code -ne 0 -and $timeout.summary.status -eq 'failed') 'Timeout was accepted.'
    Assert-Check ($timeout.summary.results.Count -eq 1 -and $timeout.summary.results[0].timed_out) 'Timeout evidence was not recorded.'
    Assert-Check $timeout.summary.results[0].pass_marker_found 'Timeout fixture did not exercise PASS-before-hang.'
    $timedOutId = [int] $timeout.summary.results[0].child_pid
    Assert-Check ($null -eq (Get-Process -Id $timedOutId -ErrorAction SilentlyContinue)) 'The timed-out child was left running.'
    Assert-Check (-not $sentinel.HasExited) 'Timeout terminated an unrelated same-name process.'

    $treeTimeout = Invoke-RunnerCase 'timeout_tree'
    Assert-Check ($treeTimeout.exit_code -ne 0 -and $treeTimeout.summary.status -eq 'failed') 'Wrapper timeout was accepted.'
    Assert-Check ($treeTimeout.summary.results.Count -eq 1 -and $treeTimeout.summary.results[0].timed_out) 'Wrapper timeout evidence was not recorded.'
    $treeResult = $treeTimeout.summary.results[0]
    $treeOutput = Get-Content -LiteralPath $treeResult.stdout_log -Raw -Encoding UTF8
    Assert-Check ($treeResult.pass_marker_found -and $treeOutput.Contains('FAKE_TREE_CHILD_READY:')) 'Child output was not inherited and drained after the wrapper timeout.'
    $treeChildId = [int] (Get-Content -LiteralPath (Join-Path $fixtureDirectory 'tree-child.pid') -Raw)
    Assert-Check ($null -eq (Get-Process -Id $treeResult.child_pid -ErrorAction SilentlyContinue)) 'The timed-out wrapper was left running.'
    Assert-Check ($null -eq (Get-Process -Id $treeChildId -ErrorAction SilentlyContinue)) 'The wrapper child was left running.'
    Assert-Check ($treeResult.termination.root_pid -eq $treeResult.child_pid -and $treeResult.termination.exit_code -eq 0) 'Termination did not target the exact wrapper PID successfully.'
    Assert-Check (-not $sentinel.HasExited) 'Tree cleanup terminated an unrelated same-name process.'
    Assert-Check ([Environment]::GetEnvironmentVariable('NIGHTWATCH_VALIDATION_TEST_CASE') -eq $testEnvironmentBefore) 'Self-test changed the parent environment.'
    Write-Output ("VALIDATION_RUNNER_TEST_PASS: $checks checks; fixtures at $fixtureDirectory")
} finally {
    # If an assertion exposes a cleanup regression, remove only the child created by
    # this unique fake fixture, after checking its executable path.
    $childPidFile = Join-Path $fixtureDirectory 'tree-child.pid'
    if (Test-Path -LiteralPath $childPidFile) {
        $leftoverId = [int] (Get-Content -LiteralPath $childPidFile -Raw)
        $leftover = Get-Process -Id $leftoverId -ErrorAction SilentlyContinue
        if ($null -ne $leftover) {
            try {
                if ($leftover.MainModule.FileName -eq $fixtureExe) {
                    $leftover.Kill()
                    [void] $leftover.WaitForExit(5000)
                }
            } finally { $leftover.Dispose() }
        }
    }
    if ($null -ne $sentinel) {
        if (-not $sentinel.HasExited) { $sentinel.Kill(); [void] $sentinel.WaitForExit(5000) }
        $sentinel.Dispose()
    }
}

#requires -Version 5.1
<#
.SYNOPSIS
Runs the Nightwatch Array correctness gates, with optional economy and export checks.
.EXAMPLE
.\tools\validate.ps1 -GodotPath C:\tools\godot\Godot_console.exe -FullEconomy -Build
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $GodotPath,
    [switch] $FullEconomy,
    [switch] $Build,
    [ValidateRange(1, 86400)]
    [int] $TimeoutSeconds = 180,
    [ValidateRange(1, 86400)]
    [int] $EconomyTimeoutSeconds = 900,
    [ValidateRange(1, 86400)]
    [int] $BuildTimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '_' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$runDirectory = Join-Path $projectRoot ('build\validation\' + $runId)
[void] [IO.Directory]::CreateDirectory($runDirectory)
$summaryPath = Join-Path $runDirectory 'summary.json'
$results = New-Object 'System.Collections.Generic.List[object]'
$summary = [ordered]@{
    status = 'running'
    started_utc = [DateTime]::UtcNow.ToString('o')
    finished_utc = $null
    project_root = $projectRoot
    godot_path = $GodotPath
    full_economy = [bool] $FullEconomy
    build = [bool] $Build
    economy_environment = @{
        NIGHTWATCH_ECONOMY_SEEDS = [Environment]::GetEnvironmentVariable('NIGHTWATCH_ECONOMY_SEEDS')
        NIGHTWATCH_ECONOMY_STRATEGIES = [Environment]::GetEnvironmentVariable('NIGHTWATCH_ECONOMY_STRATEGIES')
    }
    results = @()
    error = $null
    executable = $null
}

function Quote-NativeArgument([string] $Value) {
    # Windows argv quoting, including a trailing backslash in a quoted path.
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    return '"' + [regex]::Replace($escaped, '(\\+)$', '$1$1') + '"'
}

function Invoke-ValidationProcess {
    param([string] $Name, [string[]] $Arguments, [string] $PassMarker, [int] $Timeout, [switch] $Export)
    $stdoutPath = Join-Path $runDirectory ($Name + '.stdout.log')
    $stderrPath = Join-Path $runDirectory ($Name + '.stderr.log')
    $failures = New-Object 'System.Collections.Generic.List[string]'
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $process.StartInfo.FileName = $resolvedGodot
    $process.StartInfo.Arguments = ($Arguments | ForEach-Object { Quote-NativeArgument $_ }) -join ' '
    $process.StartInfo.WorkingDirectory = $projectRoot
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
    $process.StartInfo.StandardErrorEncoding = [Text.Encoding]::UTF8
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $childId = $null
    $exitCode = $null
    $timedOut = $false
    $termination = $null
    $stdout = ''
    $stderr = ''
    try {
        [void] $process.Start()
        $childId = $process.Id
        # Drain both pipes concurrently; a large stderr stream must not deadlock stdout.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($Timeout * 1000)) {
            $timedOut = $true
            $failures.Add("Timed out after $Timeout seconds")
            # Godot's console executable can launch the real engine as a child. Terminate
            # only the tree rooted at this still-live process, never all matching names.
            if (-not $process.HasExited) {
                $terminationOut = Join-Path $runDirectory ($Name + '.termination.stdout.log')
                $terminationErr = Join-Path $runDirectory ($Name + '.termination.stderr.log')
                $terminator = New-Object Diagnostics.Process
                $terminator.StartInfo = New-Object Diagnostics.ProcessStartInfo
                $terminator.StartInfo.FileName = Join-Path $env:SystemRoot 'System32\taskkill.exe'
                $terminator.StartInfo.Arguments = '/PID ' + $childId + ' /T /F'
                $terminator.StartInfo.UseShellExecute = $false
                $terminator.StartInfo.CreateNoWindow = $true
                $terminator.StartInfo.RedirectStandardOutput = $true
                $terminator.StartInfo.RedirectStandardError = $true
                try {
                    [void] $terminator.Start()
                    $terminationOutTask = $terminator.StandardOutput.ReadToEndAsync()
                    $terminationErrTask = $terminator.StandardError.ReadToEndAsync()
                    if (-not $terminator.WaitForExit(5000)) {
                        $terminator.Kill()
                        [void] $terminator.WaitForExit(5000)
                        throw 'The process-tree termination command timed out.'
                    }
                    if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]] @($terminationOutTask, $terminationErrTask), 5000)) {
                        throw 'Process-tree termination output did not close.'
                    }
                    [IO.File]::WriteAllText($terminationOut, $terminationOutTask.Result)
                    [IO.File]::WriteAllText($terminationErr, $terminationErrTask.Result)
                    $termination = @{
                        root_pid = $childId
                        exit_code = $terminator.ExitCode
                        stdout_log = $terminationOut
                        stderr_log = $terminationErr
                    }
                    if ($terminator.ExitCode -ne 0) { $failures.Add('Process-tree termination failed; inspect termination logs.') }
                } finally { $terminator.Dispose() }
            }
            if (-not $process.WaitForExit(5000)) { throw 'The timed-out process did not exit after tree termination.' }
        }
        $exitCode = $process.ExitCode
        $readTasks = [Threading.Tasks.Task[]] @($stdoutTask, $stderrTask)
        if (-not [Threading.Tasks.Task]::WaitAll($readTasks, 5000)) {
            throw 'The child exited but its output pipes did not close.'
        }
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        if ($exitCode -ne 0) { $failures.Add("Exit code $exitCode") }
    } catch {
        $failures.Add($_.Exception.Message)
    } finally {
        $timer.Stop()
        $process.Dispose()
        [IO.File]::WriteAllText($stdoutPath, $stdout)
        [IO.File]::WriteAllText($stderrPath, $stderr)
    }
    $allOutput = $stdout + "`n" + $stderr
    $markerFound = $false
    if ($PassMarker) {
        $markerFound = [regex]::IsMatch($allOutput, '(?m)^[ \t]*' + [regex]::Escape($PassMarker) + '(?=:|[ \t]*\r?$)')
        if (-not $markerFound) { $failures.Add("Missing PASS marker: $PassMarker") }
    }
    # Read the complete streams, including lines emitted after PASS. Warnings stay in
    # the logs. Only the reference gate's exact missing-Git negative case is exempt.
    if ($allOutput -match '(?im)\b(?:SCRIPT ERROR|Parse Error)\s*:') {
        $failures.Add('Godot script/parse error in output')
    }
    $normalizedRoot = $projectRoot.Replace('\', '/')
    $expectedGitError = 'ERROR: Could not create child process: ' + $normalizedRoot + '/build/nonexistent-reference-capture-git.exe -C ' + $normalizedRoot + '/ rev-parse HEAD'
    foreach ($errorMatch in [regex]::Matches($allOutput, '(?im)^[ \t]*ERROR\s*:.*$')) {
        $errorLine = $errorMatch.Value.Trim()
        $isExpectedGitError = -not $Export -and $Name -eq 'reference_capture_test' -and [string]::Equals($errorLine.Replace('\', '/'), $expectedGitError, [StringComparison]::OrdinalIgnoreCase)
        if (-not $isExpectedGitError) { $failures.Add('Unexpected Godot engine error: ' + $errorLine) }
    }
    return [pscustomobject]@{
        name = $Name
        status = $(if ($failures.Count -eq 0) { 'passed' } else { 'failed' })
        arguments = $Arguments
        pass_marker = $PassMarker
        pass_marker_found = $markerFound
        child_pid = $childId
        exit_code = $exitCode
        timed_out = $timedOut
        termination = $termination
        duration_seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 3)
        stdout_log = $stdoutPath
        stderr_log = $stderrPath
        failures = @($failures.ToArray())
    }
}

# These are correctness gates. Rendered captures, listening, and human-driven probes
# remain separate reviews; a headless pass cannot replace them.
$gates = @(
    @('research_contract_test', 'RESEARCH_CONTRACT_PASS'),
    @('smoke_test', 'SMOKE_TEST_PASS'),
    @('deep_sky_test', 'DEEP_SKY_PASS'),
    @('observation_span_probe', 'OBSERVATION_SPAN_PASS'),
    @('galactic_slice_test', 'GALACTIC_SLICE_PASS'),
    @('probe_layer2_test', 'PROBE_TEST_PASS'),
    @('sound_feedback_test', 'SOUND_FEEDBACK_PASS'),
    @('effect_feedback_test', 'EFFECT_FEEDBACK_PASS'),
    @('reference_capture_test', 'REFERENCE_CAPTURE_TEST_PASS'),
    @('research_visual_test', 'RESEARCH_VISUAL_PASS'),
    @('ui_presentation_test', 'UI_PRESENTATION_PASS'),
    @('game_fixture_test', 'GAME_FIXTURE_PASS'),
    @('meteor_render_cache_test', 'METEOR_RENDER_CACHE_PASS')
)
if ($FullEconomy) { $gates += ,@('full_tree_economy_test', 'FULL_TREE_ECONOMY_PASS') }

try {
    $resolvedGodot = (Resolve-Path -LiteralPath $GodotPath).ProviderPath
    if (-not [IO.File]::Exists($resolvedGodot)) { throw 'GodotPath must identify an executable file.' }
    $summary.godot_path = $resolvedGodot
    foreach ($gate in $gates) {
        $name = $gate[0]
        $limit = if ($name -eq 'full_tree_economy_test') { $EconomyTimeoutSeconds } else { $TimeoutSeconds }
        Write-Output ('[{0}/{1}] {2}' -f ($results.Count + 1), $gates.Count, $name)
        $result = Invoke-ValidationProcess -Name $name -Arguments @('--headless', '--path', $projectRoot, '--script', ('res://tests/' + $name + '.gd')) -PassMarker $gate[1] -Timeout $limit
        $results.Add($result)
        if ($result.status -ne 'passed') { throw ($name + ': ' + ($result.failures -join '; ')) }
        Write-Output ('PASS {0} ({1}s)' -f $name, $result.duration_seconds)
    }
    if ($Build) {
        # A unique staging path prevents an old successful export from masking a failure.
        $stagedExe = Join-Path $runDirectory 'NightwatchArray.exe'
        Write-Output 'Exporting Windows Desktop...'
        $result = Invoke-ValidationProcess -Name 'windows_export' -Arguments @('--headless', '--path', $projectRoot, '--export-release', 'Windows Desktop', $stagedExe) -Timeout $BuildTimeoutSeconds -Export
        $results.Add($result)
        if ($result.status -ne 'passed') { throw ('windows_export: ' + ($result.failures -join '; ')) }
        try {
            if (-not [IO.File]::Exists($stagedExe)) { throw 'Export did not create a new executable.' }
            $stream = [IO.File]::OpenRead($stagedExe)
            try {
                if ($stream.Length -lt 2 -or $stream.ReadByte() -ne 77 -or $stream.ReadByte() -ne 90) {
                    throw 'Export output is not a Windows executable (missing MZ header).'
                }
            } finally { $stream.Dispose() }
            $destination = Join-Path $projectRoot 'build\windows\NightwatchArray.exe'
            [void] [IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
            [IO.File]::Copy($stagedExe, $destination, $true)
            $summary.executable = @{
                path = $destination
                sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
                bytes = (Get-Item -LiteralPath $destination).Length
            }
        } catch {
            $result.status = 'failed'
            $result.failures = @($_.Exception.Message)
            throw
        }
        Write-Output ('PASS windows_export: ' + $destination)
    }
    $summary.status = 'passed'
} catch {
    $summary.status = 'failed'
    $summary.error = $_.Exception.Message
    Write-Output ('VALIDATION_FAIL: ' + $summary.error)
} finally {
    $summary.finished_utc = [DateTime]::UtcNow.ToString('o')
    $summary.results = @($results.ToArray())
    [IO.File]::WriteAllText($summaryPath, ($summary | ConvertTo-Json -Depth 8))
    Write-Output ('VALIDATION_SUMMARY: ' + $summaryPath)
}
if ($summary.status -ne 'passed') { exit 1 }
Write-Output ('VALIDATION_PASS: ' + $results.Count + ' checks')
exit 0

#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $installation) { throw 'MSVC C++ build tools are required for Windows performance telemetry.' }
$vcvars = Join-Path $installation 'VC\Auxiliary\Build\vcvars64.bat'
$output = Join-Path $projectRoot 'build\windows'
[void][IO.Directory]::CreateDirectory($output)
$source = Join-Path $projectRoot 'native\performance_sampler.cpp'
# Only fixed repository paths enter this command; quote each path for spaces.
$command = 'call "' + $vcvars + '" >nul && cl /nologo /std:c++17 /O2 /MT /W4 /WX /EHsc "' + $source + '" /Fo"' + $output + '\performance_sampler.obj" /Fe"' + $output + '\NightwatchMetrics.exe" /link pdh.lib'
& $env:ComSpec /d /c $command
if ($LASTEXITCODE -ne 0) { throw 'Windows performance sampler compilation failed.' }
Remove-Item -LiteralPath (Join-Path $output 'performance_sampler.obj') -ErrorAction SilentlyContinue
$testSource = Join-Path $projectRoot 'native\gpu_usage_test.cpp'
$testOutput = Join-Path $projectRoot 'build\native'
[void][IO.Directory]::CreateDirectory($testOutput)
$testExe = Join-Path $testOutput 'gpu_usage_test.exe'
$command = 'call "' + $vcvars + '" >nul && cl /nologo /std:c++17 /O2 /MT /W4 /WX /EHsc "' + $testSource + '" /Fo"' + $testOutput + '\gpu_usage_test.obj" /Fe"' + $testExe + '"'
& $env:ComSpec /d /c $command
if ($LASTEXITCODE -ne 0) { throw 'GPU counter regression test compilation failed.' }
& $testExe
if ($LASTEXITCODE -ne 0) { throw 'GPU counter regression test failed.' }
Write-Output 'PERFORMANCE_SAMPLER_BUILD_PASS'

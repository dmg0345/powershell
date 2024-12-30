<#
.DESCRIPTION
    Functions related to profilers of different languages.
#>

# [Initializations] ####################################################################################################

# Stop script on first error found.
$ErrorActionPreference = "Stop";

# Imports.
Import-Module "$PSScriptRoot/commons.psm1";

# [Declarations] #######################################################################################################

# [Internal Functions] #################################################################################################

# [Functions] ##########################################################################################################
function Start-LineProfiler
{
    <#
    .DESCRIPTION
        Runs line_profiler on the specified script, and generates a rich text output file with the results.

        For details, refer to ``python -m kernprof --help``, ``python -m line_profiler --help`` and
        https://github.com/pyutils/line_profiler.

    .PARAMETER ScriptPath
        Path to the Python script to execute for benchmarking.

    .PARAMETER OutputDir
        Path where to store the resulting artifacts of the benchmark, if this folder already exists, it is deleted
        before the profiler is executed.

    .PARAMETER TimeUnits
        Time units for the line profiler, defaults to '1e-6', the default of the tool.

    .EXAMPLE
        Start-LineProfiler -ScriptPath "benchmark.py" -OutputDir "benchmark/data" -TimeUnits "1"
    #>
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ScriptPath,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $OutputDir,
        [Parameter(Mandatory = $false)]
        [String]
        $TimeUnits
    )

    # Check the path to the Python script exists.
    if (-not (Test-Path $ScriptPath))
    {
        throw "The path to the Python script '$ScriptPath' does not exist.";
    }

    # Check if the output directory exists, in which case delete and start anew.
    if (Test-Path $OutputDir)
    {
        Remove-Item -Path $OutputDir -Recurse -Force;
    }
    New-Item -Path "$OutputDir" -ItemType Directory -Force | Out-Null;

    # Configure time units.
    $timeUnits = "1e-6";
    if ($PSBoundParameters.ContainsKey("CppCheckC2012RulesFile"))
    {
        $timeUnits = $TimeUnits;
    }

    # Get leaf component of the script and use it to generate artifacts in the output directory.
    $basename = [IO.Path]::GetFileNameWithoutExtension($ScriptPath);
    $lprofPath = Join-Path -Path "$OutputDir" -ChildPath "$basename.lprof";
    $txtPath = Join-Path -Path "$OutputDir" -ChildPath "$basename.txt";

    # Execute kernprof to generate the output data.
    Write-Log "Running kernprof with script '$ScriptPath' with output '$lprofPath'...";
    & "python" -m kernprof --line-by-line --builtin --outfile "$lprofPath" "$ScriptPath";
    if ($LASTEXITCODE -ne 0)
    {
        throw "Execution of kernprof finished with error '$LASTEXITCODE'";
    }

    # Execute line profiler and fetch the data written to the standard output.
    Write-Log "Running line profiler with profiler data '$lprofPath' with output '$txtPath'...";
    $output = & "python" -m line_profiler --summarize --rich --sort --unit "$timeUnits" "$lprofPath";
    if ($LASTEXITCODE -ne 0)
    {
        throw "Execution of line profiler finished with error '$LASTEXITCODE'.";
    }
    $output = $output -join [System.Environment]::NewLine;
    Set-Content -Path "$txtPath" -Value "$output" -Force;

    Write-Log "Finished running line profiler, no errors found." "Success";
}

# [Execution] ##########################################################################################################
Export-ModuleMember Start-LineProfiler;

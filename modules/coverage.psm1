<#
.DESCRIPTION
    Functions related to coverage tools of different languages.
#>

# [Initializations] ####################################################################################################

# Stop script on first error found.
$ErrorActionPreference = "Stop";

# [Declarations] #######################################################################################################

# [Internal Functions] #################################################################################################

# [Functions] ##########################################################################################################
function Start-FastCov
{
    <#
    .DESCRIPTION
        Runs fastcov to collect coverage files and generates a HTML report afterwards.
        
        All existing coverage files are deleted as a result of this call.

    .PARAMETER FastCovExe
        Path to the 'fastcov' executable.

    .PARAMETER LCovGenHTMLExe
        Path to the lcov 'genhtml' executable.

    .PARAMETER Include
        Filters for the files to include in the HTML report.

    .PARAMETER CoverageDir
        Folder where to store the coverage data and reports.

    .PARAMETER CMakeBuildDir
        Folder with the CMake build distributables.

    .OUTPUTS
        This function does not return a value.

    .EXAMPLE
        Start-FastCov -FastCovExe "fastcov" -LCovGenHTMLExe "genhtml" -Include @("src", "tests") `
            -CoverageDir ".coverage" -CMakeBuildDir ".cmake_build"
    #>
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $FastCovExe,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $LCovGenHTMLExe,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $Include,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $CoverageDir,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $CMakeBuildDir
    )

    # Delete coverage directory and create anew.
    if (Test-Path $CoverageDir)
    {
        Remove-Item -Path "$CoverageDir" -Recurse -Force;
    }
    New-Item -Path "$CoverageDir" -ItemType "Directory" -Force | Out-Null;

    # Set the number of cores.
    $numCores = $([System.Environment]::ProcessorCount - 1);

    # Run fastcov and generate coverage files with the results.
    Write-Log "Running fastcov with '$numCores' cores...";
    & "$FastCovExe" `
        --branch-coverage `
        --skip-exclusion-markers `
        --process-gcno `
        --include @Include `
        --dump-statistic `
        --validate-sources `
        --search-directory "$CMakeBuildDir" `
        --jobs $numCores `
        --lcov `
        --output "$(Join-Path -Path "$CoverageDir" -ChildPath "!coverage.info")";
    if ($LASTEXITCODE -ne 0)
    {
        throw "fastcov collection of files finished with error '$LASTEXITCODE'.";
    }
    Write-Log "Finished running fastcov." "Success";

    # Run fastcov again to delete all coverage files.
    Write-Log "Deleting existing coverage files...";
    & "$FastCovExe" --zerocounters --search-directory "$CMakeBuildDir";
    if ($LASTEXITCODE -ne 0)
    {
        throw "fastcov deletion of existing files finished with error '$LASTEXITCODE'.";
    }
    Write-Log "Deleted existing coverage files." "Success";

    # Generate HTML report, this also prints the location of the HTML report when finished.
    Write-Log "Generating coverage HTML report...";
    & "$LCovGenHTMLExe" `
        --output-directory "$CoverageDir" `
        --prefix "$PWD" `
        --show-details `
        --function-coverage `
        --branch-coverage `
        --num-spaces 4 `
        --dark-mode `
        --legend `
        --highlight `
        --header-title "Coverage Report" `
        --footer "" `
        --no-sort `
        "$(Join-Path -Path "$CoverageDir" -ChildPath "!coverage.info")";
    if ($LASTEXITCODE -ne 0)
    {
        throw "Generation of coverage HTML report finished with error '$LASTEXITCODE'.";
    }
    Write-Log "Finished generating coverage HTML report." "Success";
}

# [Execution] ##########################################################################################################
Export-ModuleMember Start-FastCov;

<#
.DESCRIPTION
    Functions related to documentation tools of different languages.
#>

# [Initializations] ####################################################################################################

# Stop script on first error found.
$ErrorActionPreference = "Stop";

# [Declarations] #######################################################################################################

# [Internal Functions] #################################################################################################

# [Functions] ##########################################################################################################
function Start-DoxygenSphinx
{
    <#
    .DESCRIPTION
        Runs 'doxygen' and 'sphinx' to generate documentation for C/C++ projects. Note that Sphinx, for a given
        set of source files, header files and reStructured text files, it can return false positives.

        The build directories for Doxygen and Sphinx will be in the configuration file, in '.doxygen_build' folder
        and '.sphinx_build' folder respectively. Note this must be consistent in the 'conf.py' and 'doxyfile'
        configuration files.

    .PARAMETER DoxygenExe
        Path to the 'doxygen' executable.

    .PARAMETER SphinxBuildExe
        Path to the 'sphinx-build' executable.

    .PARAMETER ConfigFolder
        Path to the root folder where the 'doxyfile' and the 'conf.py' files are located, and where the '.rst' files
        are stored.

    .PARAMETER HTMLOutput
        Folder where the HTML output will be stored.

    .OUTPUTS
        This function does not return a value.

    .EXAMPLE
        Start-DoxygenSphinx -DoxygenExe "doxygen" -SphinxBuildExe "sphinx-build" -ConfigFolder "doc" `
            -HTMLOutput "doc/.output"
    #>
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $DoxygenExe,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SphinxBuildExe,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ConfigFolder,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $HTMLOutputFolder
    )

    # Ensure paths to the configuration files exist.
    $doxyfilePath = Join-Path -Path "$ConfigFolder" -ChildPath "doxyfile";
    $confPath = Join-Path -Path "$ConfigFolder" -ChildPath "conf.py";
    foreach ($item in @($doxyfilePath, $confPath))
    {
        if (-not (Test-Path "$item"))
        {
            throw "Path '$item' does not exist.";
        }
    }

    # If paths to the build and output folders exist, create them anew.
    $sphinxBuildPath = Join-Path -Path "$ConfigFolder" -ChildPath ".sphinx_build";
    $doxygenBuildPath = Join-Path -Path "$ConfigFolder" -ChildPath ".doxygen_build";
    foreach ($item in @($sphinxBuildPath, $doxygenBuildPath, $HTMLOutputFolder))
    {
        if (Test-Path "$item")
        {
            Remove-Item -Path "$item" -Force -Recurse;
        }
        New-Item -Path "$item" -ItemType "Directory" -Force | Out-Null;
    }

    # Run Doxygen by feeding it from the standard input, to override command arguments.
    Write-Log "Running Doxygen...";
    & { Get-Content "$doxyfilePath" ; Write-Output "OUTPUT_DIRECTORY=$doxygenBuildPath" } | & "$DoxygenExe" -;
    # If there are errors in Doxygen, then do not continue building documentation.
    if ($LASTEXITCODE -ne 0)
    {
        throw "Doxygen execution finished with error '$LASTEXITCODE'.";
    }
    Write-Log "Doxygen execution finished successfully." "Success";

    # Run Sphinx, specifying the build directory.
    Write-Log "Running Sphinx, ensure warnings are not false positives...";
    $env:BUILDDIR = "$sphinxBuildPath";
    sphinx-build -j auto -v -W -b "html" "$ConfigFolder" "$HTMLOutputFolder";
    $env:BUILDDIR = $null;
    if ($LASTEXITCODE -ne 0)
    {
        throw "Sphinx execution finished with error '$LASTEXITCODE'.";
    }
    Write-Log "Sphinx execution finished, documentation built with no errors." "Success";
}

# [Execution] ##########################################################################################################
Export-ModuleMember Start-DoxygenSphinx;

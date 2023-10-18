<#
.DESCRIPTION
    Functions related to documentation tools of different languages.
#>

# [Initializations] ####################################################################################################

# Stop script on first error found.
$ErrorActionPreference = "Stop";

# Imports.
Import-Module "$PSScriptRoot/commons.psm1";

# [Declarations] #######################################################################################################

# [Internal Functions] #################################################################################################

# [Functions] ##########################################################################################################
function Start-Sphinx
{
    <#
    .DESCRIPTION
        Runs 'sphinx' to generate documentation for Python projects.

        The build directories for Sphinx will be in the configuration folder, in '.sphinx_build' folder respectively.
        Note this must be consistent with the 'conf.py' configuration file in the same configuration folder.

    .PARAMETER SphinxBuildExe
        Path to the 'sphinx-build' executable.

    .PARAMETER ConfigFolder
        Path to the root folder where the 'conf.py' file is located, and where the '.rst' files are stored.

    .PARAMETER HTMLOutput
        Folder where the HTML output will be stored.

    .OUTPUTS
        This function does not return a value.

    .EXAMPLE
        Start-Sphinx -SphinxBuildExe "sphinx-build" -ConfigFolder "doc" -HTMLOutput "doc/.output"
    #>
    param (
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

    # Ensure paths to the configuration file exist.
    $confPath = Join-Path -Path "$ConfigFolder" -ChildPath "conf.py";
    if (-not (Test-Path "$confPath"))
    {
        throw "Path '$confPath' does not exist.";
    }

    # If paths to the build and output folders exist, create them anew.
    $sphinxBuildPath = Join-Path -Path "$ConfigFolder" -ChildPath ".sphinx_build";
    foreach ($item in @($sphinxBuildPath, $HTMLOutputFolder))
    {
        if (Test-Path "$item")
        {
            Remove-Item -Path "$item" -Force -Recurse;
        }
        New-Item -Path "$item" -ItemType "Directory" -Force | Out-Null;
    }

    # Run Sphinx, specifying the build directory.
    Write-Log "Running Sphinx...";
    $env:BUILDDIR = "$sphinxBuildPath";
    sphinx-build -j auto -v -W -b "html" "$ConfigFolder" "$HTMLOutputFolder";
    $env:BUILDDIR = $null;
    if ($LASTEXITCODE -ne 0)
    {
        throw "Sphinx execution finished with error '$LASTEXITCODE'.";
    }
    Write-Log "Sphinx execution finished, documentation built with no errors." "Success";
}

########################################################################################################################
function Start-DoxygenSphinx
{
    <#
    .DESCRIPTION
        Runs 'doxygen' and 'sphinx' to generate documentation for C/C++ projects. Note that Sphinx, for a given
        set of source files, header files and reStructured text files, can return false positives.

        The build directories for Doxygen and Sphinx will be in the configuration folder, in '.doxygen_build' folder
        and '.sphinx_build' folder respectively. Note this must be consistent with the 'conf.py' and 'doxyfile'
        configuration files in the same configuration folder.

    .PARAMETER DoxygenExe
        Path to the 'doxygen' executable.

    .PARAMETER SphinxBuildExe
        Path to the 'sphinx-build' executable.

    .PARAMETER ConfigFolder
        Path to the root folder where the 'doxyfile' and the 'conf.py' files are located, and where the '.rst' files
        are stored.

    .PARAMETER CMakeBuildDir
        Path to the CMake build directory with the compilation database.

    .PARAMETER HTMLOutput
        Folder where the HTML output will be stored.

    .OUTPUTS
        This function does not return a value.

    .EXAMPLE
        Start-DoxygenSphinx -DoxygenExe "doxygen" -SphinxBuildExe "sphinx-build" -ConfigFolder "doc" `
            -CMakeBuildDir ".cmake_build" -HTMLOutput "doc/.output"
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
        [ValidateNotNullOrEmpty()]
        [String]
        $CMakeBuildDir,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $HTMLOutputFolder
    )

    # Ensure paths to the configuration file exists.
    $doxyfilePath = Join-Path -Path "$ConfigFolder" -ChildPath "doxyfile";
    if (-not (Test-Path "$doxyfilePath"))
    {
        throw "Path '$doxyfilePath' does not exist.";
    }

    # If paths to the build and output folders exist, create them anew.
    $doxygenBuildPath = Join-Path -Path "$ConfigFolder" -ChildPath ".doxygen_build";
    if (Test-Path "$doxygenBuildPath")
    {
        Remove-Item -Path "$doxygenBuildPath" -Force -Recurse;
    }
    New-Item -Path "$doxygenBuildPath" -ItemType "Directory" -Force | Out-Null;

    # Parse compilation database, and build definitions to add.
    $parsedDB = New-CompilationDatabase $(Join-Path "$CMakeBuildDir" "compile_commands.json");

    # Run Doxygen by feeding it from the standard input, to override command arguments and supply new ones.
    Write-Log "Running Doxygen...";
    & { 
        Get-Content "$doxyfilePath"; 
        Write-Output "OUTPUT_DIRECTORY = `"$doxygenBuildPath`"";
        if ($parsedDB.all_definitions.Count -gt 0)
        { 
            # Add to to variables that will be used in the preprocessor.
            $parsedDB.all_definitions | ForEach-Object { Write-Output "PREDEFINED += $_" };
            # Add to ENABLED_SECTIONS for conditional documentation, e.g. @if directives.
            $parsedDB.all_definitions | ForEach-Object { Write-Output "ENABLED_SECTIONS += $_" };
        }
    } | & "$DoxygenExe" -;
    # If there are errors in Doxygen, then do not continue building documentation.
    if ($LASTEXITCODE -ne 0)
    {
        throw "Doxygen execution finished with error '$LASTEXITCODE'.";
    }
    Write-Log "Doxygen execution finished successfully." "Success";

    # Run Sphinx, specifying the build directory.
    Start-Sphinx -SphinxBuildExe "$SphinxBuildExe" -ConfigFolder "$ConfigFolder" -HTMLOutput "$HTMLOutputFolder";
}

# [Execution] ##########################################################################################################
Export-ModuleMember Start-DoxygenSphinx;
Export-ModuleMember Start-Sphinx;
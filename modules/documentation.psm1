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

    .PARAMETER NoRebuild
        Avoids doing a full rebuild of the documentation.

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
        $HTMLOutputFolder,
        [Parameter(Mandatory = $false)]
        [Switch]
        $NoRebuild
    )

    # Ensure paths to the configuration file exist.
    $confPath = Join-Path -Path "$ConfigFolder" -ChildPath "conf.py";
    if (-not (Test-Path "$confPath"))
    {
        throw "Path '$confPath' does not exist.";
    }

    # If paths to the build and output folders exist, create them anew if requested.
    $sphinxBuildPath = Join-Path -Path "$ConfigFolder" -ChildPath ".sphinx_build";
    $docTreesPath = Join-Path -Path "$sphinxBuildPath" -ChildPath "doctrees";
    foreach ($item in @($sphinxBuildPath, $HTMLOutputFolder))
    {
        if ((-not $NoRebuild.IsPresent) -and (Test-Path "$item"))
        {
            Remove-Item -Path "$item" -Force -Recurse;
        }
        if (-not (Test-Path "$item"))
        {
            New-Item -Path "$item" -ItemType "Directory" -Force | Out-Null;
        }
    }

    # Run Sphinx and generate HTML folders.
    Write-Log "Running Sphinx...";
    $env:BUILDDIR = $sphinxBuildPath;
    & "$SphinxBuildExe" -M "html" "$ConfigFolder" "$HTMLOutputFolder" -j auto -v -W -d "$docTreesPath";
    $env:BUILDDIR = $sphinxBuildPath;
    if ($LASTEXITCODE -ne 0)
    {
        throw "Sphinx execution finished with error '$LASTEXITCODE'.";
    }
    Write-Log "Sphinx execution finished, documentation built with no errors." "Success";
}

########################################################################################################################
function Start-Doxygen
{
    <#
    .DESCRIPTION
        Runs 'doxygen' to generate documentation for C/C++ projects.

        The build directories for Doxygen will be in the configuration folder, in '.doxygen_build' folder. Note this
        must be consistent with the 'doxyfile' configuration files in the same configuration folder.

    .PARAMETER DoxygenExe
        Path to the 'doxygen' executable.

    .PARAMETER ConfigFolder
        Path to the root folder where the 'doxyfile' files is located.

    .PARAMETER CMakeBuildDir
        Path to the CMake build directory with the compilation database.

    .PARAMETER NoRebuild
        Avoids doing a full rebuild of the documentation.

    .EXAMPLE
        Start-Doxygen -DoxygenExe "doxygen" -ConfigFolder "doc" -CMakeBuildDir ".cmake_build"
    #>
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $DoxygenExe,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ConfigFolder,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $CMakeBuildDir,
        [Parameter(Mandatory = $false)]
        [Switch]
        $NoRebuild
    )

    # Ensure paths to the configuration file exists.
    $doxyfilePath = Join-Path -Path "$ConfigFolder" -ChildPath "doxyfile";
    if (-not (Test-Path "$doxyfilePath"))
    {
        throw "Path '$doxyfilePath' does not exist.";
    }

    # If paths to the build and output folders exist, create them anew if requested.
    $doxygenBuildPath = Join-Path -Path "$ConfigFolder" -ChildPath ".doxygen_build";
    if ((-not $NoRebuild.IsPresent) -and (Test-Path "$doxygenBuildPath"))
    {
        Remove-Item -Path "$doxygenBuildPath" -Force -Recurse;
    }
    if (-not (Test-Path "$doxygenBuildPath"))
    {
        New-Item -Path "$doxygenBuildPath" -ItemType "Directory" -Force | Out-Null;
    }

    # Parse compilation database, and build definitions to add.
    $parsedDB = New-CompilationDatabase $(Join-Path "$CMakeBuildDir" "compile_commands.json") -NoIncludes;

    # Run Doxygen by feeding it from the standard input, to override command arguments and supply new ones.
    Write-Log "Running Doxygen...";
    & { 
        Get-Content "$doxyfilePath"; 
        Write-Output "OUTPUT_DIRECTORY = `"$doxygenBuildPath`"";
        if ($parsedDB.all_definitions.Count -gt 0)
        { 
            $parsedDB.all_definitions | ForEach-Object {
                # Add to to variables that will be used in the preprocessor.
                Write-Output "PREDEFINED += $_"
                # Add to ENABLED_SECTIONS for conditional documentation, e.g. @if directives.
                Write-Output "ENABLED_SECTIONS += $_"
            };
        }
    } | & "$DoxygenExe" -;
    # If there are errors in Doxygen, then do not continue building documentation.
    if ($LASTEXITCODE -ne 0)
    {
        throw "Doxygen execution finished with error '$LASTEXITCODE'.";
    }
    Write-Log "Doxygen execution finished successfully." "Success";
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

    .PARAMETER NoRebuild
        Avoids doing a full rebuild of the documentation.

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
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $CMakeBuildDir,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $HTMLOutputFolder,
        [Parameter(Mandatory = $false)]
        [Switch]
        $NoRebuild
    )

    # Run Doxygen first.
    Start-Doxygen -DoxygenExe "$DoxygenExe" -ConfigFolder "$ConfigFolder" -CMakeBuildDir "$CMakeBuildDir" `
        -NoRebuild:$NoRebuild;
    # Run Sphinx afterwards.
    Start-Sphinx -SphinxBuildExe "$SphinxBuildExe" -ConfigFolder "$ConfigFolder" -HTMLOutput "$HTMLOutputFolder" `
        -NoRebuild:$NoRebuild;
}

# [Execution] ##########################################################################################################
Export-ModuleMember Start-Sphinx;
Export-ModuleMember Start-Doxygen;
Export-ModuleMember Start-DoxygenSphinx;

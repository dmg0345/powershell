<#
.DESCRIPTION
    Functions related to linters of different languages.
#>

# [Initializations] ####################################################################################################

# Stop script on first error found.
$ErrorActionPreference = "Stop";

# Imports.
Import-Module "$PSScriptRoot/commons.psm1";

# [Declarations] #######################################################################################################

# [Internal Functions] #################################################################################################

# [Functions] ##########################################################################################################
function Start-CppCheck
{
    <#
    .DESCRIPTION
        Runs CppCheck project wide reporting the errors and warnings to the standard output.

        Note that using many cores can cause internal errors on CppCheck when using the MISRA addon, if that occurs,
        reduce the number of cores to use, or keep retrying the analysis until no internal errors are raised.

        For details, refer to ``cppcheck --help`` and https://files.cppchecksolutions.com/manual.pdf.

    .PARAMETER CppCheckExe
        Path to the 'cppcheck' executable.

    .PARAMETER CppCheckHTMLReportExe
        Path to the 'cppcheck-htmlreport' executable.

    .PARAMETER SuppressionXML
        Path to the XML file with the suppressions.

    .PARAMETER CompileCommandsJSON
        Path to the 'compile_commands.json' file.

    .PARAMETER FileFilters
        Regular expressions to the files to fetch for analysis.

    .PARAMETER CppCheckBuildDir
        CppCheck build directory.

    .PARAMETER CppCheckReportDir
        CppCheck report directory.

    .PARAMETER CppCheckSourceDir
        CppCheck source directory for the report.

    .PARAMETER MaxJobs
        Maximum number of jobs, this needs to be manually adjusted.

    .PARAMETER CppCheckC2012RulesFile
        Optional path to the MISRA C:2012 rules file, this file is confidential and should not be distributed.
        If the argument is not provided, then the function does not perform any MISRA checks.
        If a path is provided and it does not exist, then an error is raised.
        If an empty string is provided, then MISRA checks are performed but no rule summary will be provided in the
        errors raised, only the rule number.
        If a path is provided and it exists, then process assumes valid MISRA C:2012 rules have been provided.

        The first Python executable found in PATH environment variable is used to run the addon.

    .OUTPUTS
        This function does not return a value.

    .EXAMPLE
        Start-CppCheck -CppCheckExe "cppcheck" -CppCheckHTMLReportExe "cppcheck-htmlreport" `
            -CppCheckC2012RulesFile "cppcheck_misra_rules.txt" -SuppressionXML "suppressions.xml" `
            -CompileCommandsJSON ".cmake/compile_commands.json" -FileFilters @("src/*", "inc/*") `
            -CppCheckBuildDir "other/cppcheck/.build" -CppCheckReportDir "other/cppcheck/.report" `
            -CppCheckSourceDir "." -MaxJobs 2;
    #>
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $CppCheckExe,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $CppCheckHTMLReportExe,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SuppressionXML,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $CompileCommandsJSON,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $FileFilters,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $CppCheckBuildDir,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $CppCheckReportDir,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $CppCheckSourceDir,

        [Parameter(Mandatory = $true)]
        [Int]
        $MaxJobs,
        [Parameter(Mandatory = $false)]
        [String]
        $CppCheckC2012RulesFile
    )

    # Check build and report directories, delete them and recreate them empty, as CppCheck
    # requires the directories to exist.
    foreach ($cppCheckDir in @($CppCheckBuildDir, $CppCheckReportDir))
    {
        if (Test-Path $cppCheckDir)
        {
            Remove-Item -Path "$cppCheckDir" -Recurse -Force;
        }
        New-Item -Path "$cppCheckDir" -ItemType "Directory" -Force | Out-Null;
    }

    # Set the number of cores.
    $numCores = [System.Environment]::ProcessorCount - 1;
    if ($numCores -gt $MaxJobs)
    {
        $numCores = $MaxJobs;
    }

    # Generate file filter expressions.
    $fileFilterExpr = @();
    foreach ($item in $FileFilters)
    {
        $fileFilterExpr += "--file-filter=$item";
    }

    # Generate expressions for MISRA C;2012.
    $misraCmdArgs = @();
    if ($PSBoundParameters.ContainsKey("CppCheckC2012RulesFile"))
    {
        # Check if empty string, in which case the analysis runs but with no rule summary.
        if ($CppCheckC2012RulesFile -eq "")
        {
            $misraJSONContents = "{`"script`": `"misra.py`", `"args`": []}";
        }
        # Check if file exists, in which case the analysys runs with rule summaries.
        elseif (Test-Path $CppCheckC2012RulesFile)
        {
            $rulesAbsPath = (Resolve-Path $CppCheckC2012RulesFile).Path;
            $misraJSONContents = "{`"script`": `"misra.py`", `"args`": [`"--rule-texts=$rulesAbsPath`"]}";
        }
        else
        {
            throw "CppCheck MISRA C:2012 rules provided does not exist or it is not a valid value.";
        }

        # Create MISRA JSON file in the build folder.
        $misraJSONFile = Join-Path -Path "$CppCheckBuildDir" -ChildPath "!misra.json";
        Set-Content -Force -Path $misraJSONFile -Value $misraJSONContents;
        $misraJSONFile = (Resolve-Path $misraJSONFile).Path;

        # Build final MISRA command line arguments.
        $misraCmdArgs = @("--addon=$misraJSONFile", "--addon-python=python");
    }

    # Run CppCheck and generate an XML report with the results, also make it return a specific error code if
    # errors are found in the codebase.
    Write-Log "Running CppCheck with '$MaxJobs' cores...";
    $outputXMLFile = Join-Path -Path "$CppCheckBuildDir" -ChildPath "!output.xml";
    & "$CppCheckExe" `
        @misraCmdArgs `
        --cppcheck-build-dir="$CppCheckBuildDir" `
        --enable="all" `
        --inline-suppr `
        --suppress-xml="$SuppressionXML" `
        --project="$CompileCommandsJSON" `
        @fileFilterExpr `
        --report-progress `
        --output-file="$outputXMLFile" `
        --xml `
        --verbose `
        --error-exitcode=100 `
        -j $numCores;
    if (-not ($LASTEXITCODE -in (0, 100)))
    {
        throw "CppCheck terminated with error '$($LASTEXITCODE)'.";
    }
    $cppCheckLastExitCode = $LASTEXITCODE;
    Write-Log "Finished running CppCheck." "Success";

    # Generate HTML report, this also prints the location of the HTML report when finished.
    Write-Log "Generating HTML CppCheck report...";
    & "$CppCheckHTMLReportExe" `
        --file "$outputXMLFile" `
        --report-dir "$CppCheckReportDir" `
        --source-dir "$CppCheckSourceDir" `
        --source-encoding "utf-8";
    if ($LASTEXITCODE -ne 0)
    {
        throw "Failed to generate CppCheck HTML report.";
    }
    Write-Log "Finished running CppCheck HTML report." "Success";

    # Get contents of the XML file, some errors are not reported as errors, but rather as warnings, not returning
    # an error on exit.
    $errCount = ([xml](Get-Content -Path "$outputXMLFile")).results.errors.error.Count;

    # Check if CppCheck found errors, and in that case report them.
    if (($cppCheckLastExitCode -ne 0) -or ($errCount -ne 0))
    {
        # On error, print the errors, the contents of the XML file, to the standard output, as CppCheck does not
        # print anything to the standard output when it finds errors if generating XML.
        Get-Content -Path "$outputXMLFile" | Write-Output;
        throw "CppCheck finished with error '$cppCheckLastExitCode' and '$errCount' errors, check output for details.";
    }
    Write-Log "Finished running CppCheck, no errors found." "Success";
}

########################################################################################################################
function Start-ClangTidy
{
    <#
    .DESCRIPTION
        Runs clang-tidy project wide reporting the errors and warnings to the standard output.

    .PARAMETER ClangFormatExe
        Path to the 'clang-tidy' executable.

    .PARAMETER Filters
        Path to wildcards to collect files from the compilation database for analysis with 'clang-tidy'. Only files
        with the extensions '.c', '.cpp', '.h' and '.hpp' are considered.

        If a header or source matches a wildcard specified, then it is added for analysis. Care should be taken with
        the project structure as not to include header files that are not meant to be included. Wildcards are checked
        against absolute paths and paths relative to the current working directory.

        The use of clang-tidy in this way might force to maintain a certain project structure in order to include the
        relevant headers and source files per target, the alternative is to maintain different executions for each
        execution target, which is harder to maintain.

    .PARAMETER ConfigFile
        Path to the '.clang-tidy' configuration file.

    .PARAMETER CMakeBuildDir
        CMake build directory where the 'compile_commands.json' file is generated.

    .OUTPUTS
        This function does not return a value.

    .EXAMPLE
        Start-ClangTidy -ClangTidyExe "clang-tidy-15" -Files @("src.c", "inc.h"); -ConfigFile ".clang-tidy" `
            -CMakeBuildDir ".cmake_build"
    #>
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ClangTidyExe,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $Filters,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ConfigFile,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $CMakeBuildDir
    )

    # Parse compilation database.
    $parsedDB = New-CompilationDatabase $(Join-Path "$CMakeBuildDir" "compile_commands.json") -NoDefinitions;
    # Get paths to the source files and the header files.
    Write-Log "Collecting files for analysis...";
    $allFiles = New-Object Collections.Generic.List[String];
    foreach ($arrayFiles in @($parsedDB.all_source_files.Keys, $parsedDB.all_include_files))
    {
        foreach ($file in $arrayFiles)
        {
            foreach ($wildcard in $Filters)
            {
                if (($file -like $wildcard) -or ($file -like (Join-Path $PWD $wildcard)))
                {
                    Write-Log "Adding file '$file' for analysis...";
                    $allFiles.Add($file);
                    break;
                }
            }
        }
    }
    if ($allFiles.Count -eq 0)
    {
        throw "Could not collect any file for analysis with the filters specified.";
    }
    Write-Log "Finished collecting $($allFiles.Count) files for analysis." "Success";

    Write-Log "Running clang-tidy...";
    & "$ClangTidyExe" -p="$CMakeBuildDir" --config-file="$ConfigFile" `
        --extra-arg "-Wno-unused-command-line-argument" --extra-arg "-Wno-unknown-warning-option" @allFiles;
    if ($LASTEXITCODE -ne 0)
    {
        throw "clang-tidy finished with error '$LASTEXITCODE', check output for details.";
    }
    Write-Log "Finished running clang-tidy, no errors found." "Success";
}

########################################################################################################################
function Start-ClangFormat
{
    <#
    .DESCRIPTION
        Runs clang-format project wide and in dry-run mode, reporting the errors and warnings to the standard output.

    .PARAMETER ClangFormatExe
        Path to the 'clang-format' executable.

    .PARAMETER Paths
        Paths to '.c', '.cpp', '.h' or '.hpp' C/C++ files or directories to search recursively for files with any of
        those extensions.

    .PARAMETER ConfigFile
        Path to the '.clang-format' configuration file.

    .OUTPUTS
        This function does not return a value.

    .EXAMPLE
        Start-ClangFormat -ClangFormatExe "clang-format-15" -Paths @("source.c", "header.h", "src"); `
            -ConfigFile ".clang-format"
    #>
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ClangFormatExe,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $Paths,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ConfigFile
    )

    Write-Log "Collecting files for analysis...";
    $files = @();
    foreach ($path in $Paths)
    {
        if (Test-Path "$path")
        {
            if ((Get-Item "$path") -is [System.IO.DirectoryInfo])
            {
                Get-ChildItem -Path "$path" -Include @("*.c", "*.cpp", "*.h", "*.hpp") -Force -Recurse | ForEach-Object `
                { 
                    $files += "$($_.FullName)";
                };
            }
            else
            {
                $files += "$input";
            }
        }
    }
    # Remove duplicates if any.
    $files = $files | Select-Object -Unique;
    if ($files.Count -eq 0)
    {
        throw "Could not collect any files with the arguments specified.";
    }
    Write-Log "Finished collecting $($files.Count) files for analysis." "Success";

    Write-Log "Running clang-format...";
    & "$ClangFormatExe" --style="file:$ConfigFile" --dry-run --Werror --verbose @files;
    if ($LASTEXITCODE -ne 0)
    {
        throw "clang-format finished with error '$LASTEXITCODE', check output for details.";
    }
    Write-Log "Finished running clang-format, no errors found." "Success";
}

########################################################################################################################
function Start-Doc8
{
    <#
    .DESCRIPTION
        Runs doc8 project wide reporting the errors and warnings to the standard output.

    .PARAMETER Doc8Exe
        Path to the 'clang-format' executable.

    .PARAMETER ConfigFile
        Path to the 'pyproject.toml' configuration file.

    .PARAMETER Inputs
        Array of directory and/or file inputs to recursively collect '.rst' files for analysis.

    .OUTPUTS
        This function does not return a value.

    .EXAMPLE
        Start-Doc8 -Doc8Exe "doc8" -ConfigFile "pyproject.toml" -Inputs @("file.rst", "dir")
    #>
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Doc8Exe,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ConfigFile,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $Inputs
    )

    $files = @();
    foreach ($input in $Inputs)
    {
        if (Test-Path "$input")
        {
            if ((Get-Item "$input") -is [System.IO.DirectoryInfo])
            {
                Get-ChildItem -Path "doc" -Include "*.rst" -Force -Recurse | ForEach-Object { $files += $_.FullName };
            }
            elseif ($input.EndsWith(".rst"))
            {
                $files += "$input";
            }
        }
    }

    Write-Log "Running doc8...";
    & "$Doc8Exe" --config="$ConfigFile" --verbose $files;
    if ($LASTEXITCODE -ne 0)
    {
        throw "doc8 finished with error '$LASTEXITCODE', check output for details.";
    }
    Write-Log "Finished running doc8, no errors found." "Success";
}

########################################################################################################################
function Start-Pylint
{
    <#
    .DESCRIPTION
        Runs Pylint project wide reporting the errors and warnings to the standard output.

    .PARAMETER PylintExe
        Path to the 'pylint' executable.

    .PARAMETER ConfigFile
        Path to the 'pyproject.toml' configuration file.

    .PARAMETER Inputs
        Directories and/or files to run pylint on, there will be a separate execution for each pylint input.

    .OUTPUTS
        This function does not return a value.

    .EXAMPLE
        Start-Pylint -PylintExe "pylint" -ConfigFile "pyproject.toml" -Inputs @("src", "tests")
    #>
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $PylintExe,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ConfigFile,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $Inputs
    )

    Write-Log "Running pylint...";
    foreach ($input in $Inputs)
    {
        # Check that item exists.
        if (-not (Test-Path "$input"))
        {
            throw "The directory or file '$input' does not exist.";
        }
        # Run Pylint on file or folder.
        Write-Log "Running pylint on '$input'...";
        & "$PylintExe" --rcfile "$ConfigFile" --verbose "$input";
        if ($LASTEXITCODE -ne 0)
        {
            throw "Pylint finished with error '$LASTEXITCODE', check output for details.";
        }
    }
    Write-Log "Finished running pylint, no errors found." "Success";
}

########################################################################################################################
function Start-Pyright
{
    <#
    .DESCRIPTION
        Runs Pyright project wide reporting the errors and warnings to the standard output.

    .PARAMETER PyrightExe
        Path to the 'pyright' executable.

    .PARAMETER ConfigFile
        Path to the 'pyproject.toml' configuration file.

    .PARAMETER Inputs
        Directories and/or files to run pyright on, there will be a separate execution for each pyright input.

    .OUTPUTS
        This function does not return a value.

    .EXAMPLE
        Start-Pyright -PyrightExe "pyright" -ConfigFile "pyproject.toml" -Inputs @("src", "tests")
    #>
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $PyrightExe,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ConfigFile,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $Inputs
    )

    Write-Log "Running pyright...";
    foreach ($input in $Inputs)
    {
        # Check that item exists.
        if (-not (Test-Path "$input"))
        {
            throw "The directory or file '$input' does not exist.";
        }
        # Run Pylint on file or folder.
        Write-Log "Running pyright on '$input'...";
        & "$PyrightExe" --warnings --project "$ConfigFile" --verbose "$input";
        if ($LASTEXITCODE -ne 0)
        {
            throw "Pyright finished with error '$LASTEXITCODE', check output for details.";
        }
    }
    Write-Log "Finished running pyright, no errors found." "Success";
}

########################################################################################################################
function Start-Black
{
    <#
    .DESCRIPTION
        Runs black project wide reporting the errors and warnings to the standard output.

    .PARAMETER BlackExe
        Path to the 'black' executable.

    .PARAMETER ConfigFile
        Path to the 'pyproject.toml' configuration file.

    .PARAMETER Inputs
        Directories and/or files to run black on, there will be a separate execution for each black input.

    .OUTPUTS
        This function does not return a value.

    .EXAMPLE
        Start-Black -BlackExe "black" -ConfigFile "pyproject.toml" -Inputs @("src", "tests")
    #>
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $BlackExe,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ConfigFile,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $Inputs
    )

    Write-Log "Running black...";
    foreach ($input in $Inputs)
    {
        # Check that item exists.
        if (-not (Test-Path "$input"))
        {
            throw "The directory or file '$input' does not exist.";
        }
        # Run black on file or folder.
        Write-Log "Running black on '$input'...";
        & "$BlackExe" --config "$ConfigFile" --check "$input";
        if ($LASTEXITCODE -ne 0)
        {
            throw "Black finished with error '$LASTEXITCODE', check output for details.";
        }
    }
    Write-Log "Finished running black, no errors found." "Success";
}

# [Execution] ##########################################################################################################
Export-ModuleMember Start-CppCheck;
Export-ModuleMember Start-ClangTidy;
Export-ModuleMember Start-ClangFormat;
Export-ModuleMember Start-Doc8;
Export-ModuleMember Start-Pylint;
Export-ModuleMember Start-Pyright;
Export-ModuleMember Start-Black;

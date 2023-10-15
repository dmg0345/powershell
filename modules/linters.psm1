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

    .PARAMETER PythonExe
        Path to the 'python' executable.

    .PARAMETER CppCheckHTMLReportExe
        Path to the 'cppcheck-htmlreport' executable.

    .PARAMETER CppCheckRulesFile
        Optional path to the MISRA rules file, this file is confidential and should not be distributed. If provided
        and it does not exist it will behave as if it was not provided.

        When not provided, only the MISRA rule identifier is displayed.

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

    .OUTPUTS
        This function does not return a value.

    .EXAMPLE
        Start-CppCheck -CppCheckExe "cppcheck" -PythonExe "python" -CppCheckHTMLReportExe "cppcheck-htmlreport" `
            -CppCheckRulesFile "cppcheck_misra_rules.txt" -SuppressionXML "suppressions.xml" `
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
        $PythonExe,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $CppCheckHTMLReportExe,

        [Parameter(Mandatory = $false)]
        [String]
        $CppCheckRulesFile,
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
        $MaxJobs
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

    # Check if the MISRA rules were given and if they exist.
    if ((-not $PSBoundParameters.ContainsKey("CppCheckRulesFile")) -or (-not (Test-Path $CppCheckRulesFile)))
    {
        # Create MISRA JSON file in the build folder, with no additional arguments.
        $misraJSONContents = @"
{
    "script": "misra.py",
    "args": []
}
"@;
    }
    else
    {
        # MISRA JSON contents with the path to the rules.
        $misraJSONContents = @"
{
    "script": "misra.py",
    "args": [
        "--rule-texts=$((Resolve-Path $CppCheckRulesFile).Path)"
    ]
}
"@;
    }
    # Create MISRA JSON file in the build folder.
    $misraJSONFile = Join-Path -Path "$CppCheckBuildDir" -ChildPath "!misra.json";
    Set-Content -Force -Path $misraJSONFile -Value $misraJSONContents;
    $misraJSONFile = (Resolve-Path $misraJSONFile).Path;

    # Run CppCheck and generate an XML report with the results, also make it return a specific error code if
    # errors are found in the codebase.
    Write-Log "Running CppCheck with '$MaxJobs' cores...";
    $outputXMLFile = Join-Path -Path "$CppCheckBuildDir" -ChildPath "!output.xml";
    & "$CppCheckExe" `
        --addon="$misraJSONFile" `
        --addon-python="$PythonExe" `
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

    .PARAMETER Files
        Path to the file with the source and header files to analyze. One per line.

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
        [String]
        $Files,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ConfigFile,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $CMakeBuildDir
    )

    Write-Log "Running clang-tidy...";
    & "$ClangTidyExe" -p="$CMakeBuildDir" --config-file="$ConfigFile" `
        --extra-arg "-Wno-unused-command-line-argument" (Get-Content -Path "$Files");
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

    .PARAMETER Files
        Path to the file with the source and header files to analyze. One per line.

    .PARAMETER ConfigFile
        Path to the '.clang-format' configuration file.

    .OUTPUTS
        This function does not return a value.

    .EXAMPLE
        Start-ClangFormat -ClangFormatExe "clang-format-15" -Files @("src.c", "inc.h"); -ConfigFile ".clang-format"
    #>
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ClangFormatExe,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Files,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ConfigFile
    )

    Write-Log "Running clang-format...";
    & "$ClangFormatExe" --style="file:$ConfigFile" --dry-run --Werror --verbose (Get-Content -Path "$Files");
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
                Get-ChildItem -Path "doc" -Include "*.rst" -Recurse | ForEach-Object { $files += $_.FullName };
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

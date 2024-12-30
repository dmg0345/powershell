<#
.DESCRIPTION
    Functionality and utilities that do not fit anywhere else.
#>

# [Initializations] ####################################################################################################

# Stop script on first error found.
$ErrorActionPreference = "Stop";

# [Declarations] #######################################################################################################

# [Internal Functions] #################################################################################################

# [Functions] ##########################################################################################################
function Write-Log
{
    <#
    .DESCRIPTION
        Logs the specified message to the standard output.

    .PARAMETER Message
        Message to print.

    .PARAMETER Level
        Foreground color of the message, one of "Success", "Error" or "Info", defaults to "Info".

    .EXAMPLE
        Write-Log -Message "Hello World" -Level "Info";
    #>
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Error", "Success")]
        [String]
        $Level
    )

    # If no level was specified, then assume information level as default.
    if (-not $PSBoundParameters.ContainsKey("Level"))
    {
        $Level = "Info";
    }

    # Get color for level.
    $color = @{ "Success" = "Green"; "Error" = "Red"; "Info" = "Magenta" }.$Level;
    # Get current time.
    $time = (Get-Date).tostring("dd/MM/yy HH:mm:ss");
    # Get line number and filename of original call if possible, otherwise use default values.
    $match = ((Get-PSCallStack).Location[1] -match "(.*)\..*: .* ([0-9]*)");
    if ($match) 
    {
        # Build formatted message with filename and line.
        $formattedMessage = "[$time] [{0,15}`:{1:d4}] $Message" -f $Matches[1], [int32]$Matches[2];
    }
    else
    {
        # Build formatted message without filename and line.
        $formattedMessage = "[$time] $Message";
    }

    # Write message to standard output.
    Write-Host "$formattedMessage" -ForegroundColor "$color";
}

########################################################################################################################
function Write-StandardOutput
{
    <#
    .DESCRIPTION
        Captures the standard output in a variable and prints it to the terminal at the same time.

        Based on: https://stackoverflow.com/a/71040823/21951997

    .PARAMETER InputObject
        The invocation of the command.

    .OUTPUTS
        The standard output that is printed to the terminal.

    .EXAMPLE
        $output = (pwsh --version) | Write-StandardOutput;
    #>
    param(
        [Parameter(ValueFromPipeline)]
        $InputObject
    )

    begin
    {
        $scriptCmd = { Out-Host };
        $steppablePipeline = $scriptCmd.GetSteppablePipeline($myInvocation.CommandOrigin);
        $steppablePipeline.Begin($PSCmdlet);
    }
    process
    {
        # Pass to Out-Host, and therefore to the host (terminal)
        $steppablePipeline.Process($InputObject);
        # Pass through (to the success stream)
        $InputObject;
    }
    end
    {
        $steppablePipeline.End();
    }
}

########################################################################################################################
function New-SymbolicLink
{
    <#
    .DESCRIPTION
        Creates a symbolic link to a file or directory in the directory specified.

        On Git, symbolic links need to be enabled, for example by running 'git config --global core.symlinks true'.
        On Windows hosts, the 'Create symbolic link' permission needs to be enabled.

    .PARAMETER Path
        The path to the file or directory symbolic link that will be created, if the directory structure does not
        exist it will be created.

    .PARAMETER Target
        The relative path, file or directory, to which the symbolic link resolves, relative to the parent directory of
        the parameter Path.

    .EXAMPLE
        New-SymbolicLink -Path "src/project" -Target "./../other/project/src";
    #>
    param(
        [Parameter(Mandatory = $true)]
        [String]
        $Path,
        [Parameter(Mandatory = $true)]
        [String]
        $Target
    )

    Write-Log "Creating symbolic link from '$Path' to '$Target'...";

    # Ensure that if running a Linux container, the symbolic links created can be handled by a Windows host.
    # See: https://stackoverflow.com/a/63325536/21951997
    if ($isLinux)
    {
        Write-Log "Enabling support for Windows symbolic links on Linux host...";
        $env:MSYS = "winsymlinks:nativestrict";
    }

    # Get parent path to the item and the leaf, which identifies the item to create.
    $parentDirectory = Split-Path -Path "$Path" -Parent;
    $leafItem = Split-Path -Path "$Path" -Leaf;

    # Check if the parent directory exists, if not, create it and its directory structure.
    if (-not (Test-Path "$($parentDirectory)"))
    {
        Write-Log "Creating directory structure to '$Path' because it does not exist...";
        New-Item -Path "$parentDirectory" -ItemType Directory -Force | Out-Null;
    }

    # Move to parent location to set the working directory, and from there the target value will resolve correctly.
    # See: https://www.github.com/PowerShell/PowerShell/issues/15235
    Push-Location "$parentDirectory";
    try
    {
        # Ensure the location where the symbolic link will target exists.
        $targetFullPath = Join-Path -Path "$($PWD.Path)" -ChildPath "$Target";
        if (-not (Test-Path $targetFullPath))
        {
            throw "The target path for the symbolic link does not exist.";
        }
        $targetFullPath = Resolve-Path $targetFullPath;
        # Create symbolic link.
        New-Item -ItemType SymbolicLink -Force -Path "$leafItem" -Target "$Target" | Out-Null;
    }
    finally
    {
        Pop-Location;
    }

    # If there is a '.gitattributes' file.
    if (Test-Path ".gitattributes")
    {
        Write-Log "Adding symbolic link to '.gitattributes' file, review after creating symbolic link...";
        if ((Get-Item $targetFullPath) -is [System.IO.DirectoryInfo])
        {
            $gitSym = "$Path symlink=directory";
        }
        else
        {
            $gitSym = "$Path symlink=file";
        }

        # Append the symbolic link to file.
        Add-Content -Path ".gitattributes" -Value "$gitSym";
    }

    Write-Log "Created symbolic link from '$((Resolve-Path $Path).Path)' to '$targetFullPath'." "Success";
}

########################################################################################################################
function New-CopyItem
{
    <#
    .DESCRIPTION
        Copies a file or directory from a source path to a destination path, recreating the folder structure if it
        does not exist and replacing existing files or folders if they already exist.

    .PARAMETER Source
        The file or directory to copy.

    .PARAMETER Destination
        The file or directory that will be created.

    .EXAMPLE
        New-CopyItem -Source "path/to/source" -Destination "path/to/destination";
    #>
    param(
        [Parameter(Mandatory = $true)]
        [String]
        $Source,
        [Parameter(Mandatory = $true)]
        [String]
        $Destination
    )
    
    Write-Log "Copying item from '$Source' to '$Destination'...";

    # Ensure if the source path exists.
    if (-not (Test-Path "$Source"))
    {
        throw "Path '$Source' does not exist.";
    }

    # Check if the parent directory does not exist, in which case create it.
    $parentPath = Split-Path "$Destination" -Parent;
    if (-not (Test-Path "$parentPath"))
    {
        New-Item -Path "$parentPath" -ItemType "Directory" -Force | Out-Null;
    }
    # Check if destination path exists, in which case remove it.
    elseif (Test-Path "$Destination")
    {
        Remove-Item -Path "$Destination" -Force -Recurse;
    }

    # Copy item, if a directory, copy recursively.
    Copy-Item -Path "$Source" -Destination "$Destination" -Force -Recurse;

    Write-Log "Copied item from '$((Resolve-Path $Source).Path)' to '$((Resolve-Path $Destination).Path)'..." "Success";
}

########################################################################################################################
function New-TemporaryFolder
{
    <#
    .DESCRIPTION
        Creates a new temporary folder.

    .OUTPUTS
        The path to the temporary folder.

    .EXAMPLE
        $tempFolder = New-TemporaryFolder;
    #>
    param()
    
    return New-TemporaryFile | ForEach-Object {
        Remove-Item $_ -Force; New-Item -Path "$($_.FullName)" -ItemType Directory -Force | Out-Null; $_.FullName;
    };
}

########################################################################################################################
function New-JSONC
{
    <#
    .DESCRIPTION
        Parses a JSON with comments, stripping them out and then returning a normal JSON object.
        
        JSON files with comments usually have the '.jsonc' extension.
        
        Based on: https://stackoverflow.com/a/57092959/21951997.

    .PARAMETER JSONCPath
        The path to the file with JSON with comments.

    .OUTPUTS
        A hashtable representing the JSON contents.

    .EXAMPLE
        New-JSONC -JSONCPath "file.jsonc";
    #>
    param(
        [Parameter(Mandatory = $true)]
        [String]
        $JSONCPath
    )
    
    # Ensure path to the JSONC file exists.
    if (-not (Test-Path "$JSONCPath"))
    {
        throw "Path '$JSONCPath' does not exist.";
    }
    
    # Get contents and comment everything out.
    $cnts = Get-Content -Path "$JSONCPath" -Raw;
    $cnts = $cnts -replace '(?m)(?<=^([^"]|"[^"]*")*)//.*';
    $cnts = $cnts -replace '(?ms)/\*.*?\*/';
    
    # Return as hashtable object.
    return $cnts | ConvertFrom-Json;
}

########################################################################################################################
function New-CompilationDatabase
{
    <#
    .DESCRIPTION
        Parses a given compilation database, a 'compile_commands.json' file, obtaining relevant data from it.

        This function expects the paths in the compilation database to be absolute or relative to the current
        working directory. The sources must have a file extension of '.c' or '.cpp', and the header files of '.h' or
        '.hpp', for C/C++ respectively.

    .PARAMETER CompileCommandsJSON
        The path to the 'compile_commands.json' file.

    .PARAMETER NoDefinitions
        Skips obtaining definitions from the compilation database, relevant fields in the hashtable will be empty.

    .PARAMETER NoIncludes
        Skips obtaining include directories and files from the compilation database, relevant fields in the hashtable
        will be empty.

    .OUTPUTS
        A hashtable with the following format:

        @{
            "c_compiler" = "Absolute path to the C compiler, if used, otherwise $null.";
            "cpp_compiler" = "Absolute path to the C++ compiler, if used, otherwise $null.";
            "all_source_files" = @{
                "absolute_path_to_source_file" = {
                    "include_dirs" = @{
                        "absolute_path_to_include_directory" = @(
                            "absolute_path_to_header_file_0",
                            "absolute_path_to_header_file_1"
                        );
                    };
                    "definitions" = @(
                        "DEFINITION_1",
                        "DEFINITION_2=30"
                    );
                };
            };
            "all_include_dirs" = @(
                "absolute_path_to_include_dir_0",
                "absolute_path_to_include_dir_0"
            );
            "all_include_files" = @(
                "absolute_path_to_header_file_0",
                "absolute_path_to_header_file_1"
            );
            "all_definitions" = @(
                "DEFINITION_1",
                "DEFINITION_2"
            );
        }

        Note that the include directories and include files do not include system header directories or files.

    .EXAMPLE
        New-CompilationDatabase -CompileCommandsJSON ".cmake_build/compile_commands.json";
    #>
    param(
        [Parameter(Mandatory = $true)]
        [String]
        $CompileCommandsJSON,
        [Parameter(Mandatory = $false)]
        [Switch]
        $NoDefinitions,
        [Parameter(Mandatory = $false)]
        [Switch]
        $NoIncludes
    )

    # Check the compilation database exists.
    if (-not (Test-Path $CompileCommandsJSON))
    {
        throw "Could not find compilation database at '$CompileCommandsJSON'.";
    }
    Write-Log "Parsing compilation database at '$($CompileCommandsJSON)'...";

    # Track time the parsing takes.
    $startTime = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();

    # Parse JSON as a hashtable, and loop each item.
    $compileCommands = New-JSONC $CompileCommandsJSON;
    $parsed = @{
        "c_compiler"        = $null;
        "cpp_compiler"      = $null;
        "all_source_files"  = @{};
        "all_include_dirs"  = New-Object Collections.Generic.List[String];
        "all_include_files" = New-Object Collections.Generic.List[String];
        "all_definitions"   = New-Object Collections.Generic.List[String];
    };
    # Cache for include directories to speed up operations.
    $includeDirsCache = @{};
    foreach ($cmd in $compileCommands)
    {
        # Define empty item to add.
        $item = @{
            "include_dirs" = @{};
            "definitions"  = New-Object Collections.Generic.List[String];
        };

        # Check command consistency.
        if (($null -eq $cmd.file) -or ($null -eq $cmd.command))
        {
            throw "Command in compilation database does not contain a 'file' or 'command' attribute";
        }

        # Resolve absolute path and normalize, if the path already exists in the parsed structure, then skip it.
        $sourceFile = (Resolve-Path $cmd.file).Path;
        if ($sourceFile -in $parsed.all_source_files.Keys)
        {
            continue;
        }

        # Check source file extension and verify it is a known C/C++ file.
        if (-not ($sourceFile.EndsWith(".c") -or $sourceFile.EndsWith(".cpp")))
        {
            continue;
        }

        $cmdArguments = $cmd.command.Trim().Split(" ");
        $cmdArgIndex = 0;
        foreach ($cmdArg in $cmdArguments)
        {
            # Remove spaces and the beginning and end.
            $cmdArg = $cmdArg.Trim();

            # Look for C compiler if a C file and not already set.
            if (($cmdArgIndex -eq 0) -and ($sourceFile.EndsWith(".c")) -and ($null -eq $parsed.c_compiler))
            {
                $parsed.c_compiler = (Resolve-Path $cmdArg).Path;
            }
            # Look for C++ compiler if a C++ file and not already set.
            elseif (($cmdArgIndex -eq 0) -and ($sourceFile.EndsWith(".cpp")) -and ($null -eq $parsed.cpp_compiler))
            {
                $parsed.cpp_compiler = (Resolve-Path $cmdArg).Path;
            }
            # Look for include directories (-I), if enabled.
            elseif ((-not $NoIncludes.IsPresent) -and ($cmdArg.StartsWith("-I")))
            {
                # Normalize path to include directory.
                $includeDir = (Resolve-Path ($cmdArg.SubString(2).Trim())).Path;

                # Check if include directory already in cache, and fetch the files from there.
                if ($includeDir -in $includeDirsCache.Keys)
                {
                    $includeFiles = $includeDirsCache[$includeDir];
                }
                else
                {
                    # Get header files recursively and in hidden folders too.
                    $includeFiles = New-Object Collections.Generic.List[String];
                    Get-ChildItem -Path $includeDir -Force -File -Recurse -Include @("*.h", "*.hpp") | ForEach-Object -Process `
                    {
                        $includeFiles.Add((Resolve-Path $_.FullName).Path);
                    }
                    # Add to cache.
                    $includeDirsCache.Add($includeDir, $includeFiles);
                }

                # Add elements to item.
                $item.include_dirs.Add($includeDir, $includeFiles);

                # Add include directory and include files to global lists if not already added.
                if (-not ($includeDir -in $parsed.all_include_dirs))
                {
                    $parsed.all_include_dirs.Add($includeDir);
                    foreach ($includeFile in $includeFiles)
                    {
                        if (-not ($includeFile -in $parsed.all_include_files))
                        {
                            $parsed.all_include_files.Add($includeFile);
                        }
                    }
                }
            }
            # Look for definitions (-D), if enabled.
            elseif ((-not $NoDefinitions.IsPresent) -and $cmdArg.StartsWith("-D"))
            {
                # Get definition.
                $definition = $cmdArg.SubString(2).Trim();

                # Add elements to item.
                $item.definitions.Add($definition);

                # Add definitiosn to list of definitions if not already added.
                if (-not ($definition -in $parsed.all_definitions))
                {
                    $parsed.all_definitions.Add($definition);
                }
            }

            # Increase index.
            $cmdArgIndex += 1;
        }

        # Add element to collection.
        $parsed.all_source_files.Add($sourceFile, $item);
    }

    # Track time the parsing takes.
    $stopTime = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();
    Write-Log "Parsed compilation database at '$($CompileCommandsJSON)' in $($stopTime - $startTime)ms..." "Success";

    # Return as hashtable object.
    return $parsed;
}

########################################################################################################################
function Remove-FromCompilationDatabase
{
    <#
    .DESCRIPTION
        Removes entries from a compilation database, generating one with the result.

    .PARAMETER InputCompileCommandsJSON
        The path to the input 'compile_commands.json' file.

    .PARAMETER OutputCompileCommandsJSON
        The path to the output 'compile_commands.json' file, with the removed entries.

    .PARAMETER Regex
        Regular expression that will result in the entry being deleted if it results in a match in the 'command'
        key-value pair.

    .OUTPUTS
        The deleted entries.

    .EXAMPLE
        Remove-FromCompilationDatabase './cmake_build/compile_commands.json' './cp_0.json' '-DDEF0';
    #>
    param(
        [Parameter(Mandatory = $true)]
        [String]
        $InputCompileCommandsJSON,
        [Parameter(Mandatory = $true)]
        [String]
        $OutputCompileCommandsJSON,
        [Parameter(Mandatory = $true)]
        [String]
        $Regex
    )

    # Check the input compilation database exists.
    if (-not (Test-Path $InputCompileCommandsJSON))
    {
        throw "Could not find input compilation database at '$InputCompileCommandsJSON'.";
    }
    Write-Log "Parsing compilation database at '$($InputCompileCommandsJSON)'...";

    # Parse input compile commands as a hashtable, and loop each item.
    $inputCompileCommands = New-JSONC $InputCompileCommandsJSON;
    $deletedEntries = @(); $keptEntries = @();
    foreach ($inputCmd in $inputCompileCommands)
    {
        # Check command consistency.
        if (($null -eq $inputCmd.file) -or ($null -eq $inputCmd.command))
        {
            throw "Command in compilation database does not contain a 'file' or 'command' attribute";
        }

        # Perform regular expression check on 'command', and assign the entry accordingly to kept or deleted entries.
        if ($inputCmd.command -match "$($Regex)")
        {
            Write-Log "Regex '$($Regex)' match, deleting entry for file '$($inputCmd.file)'...";
            $deletedEntries += $inputCmd;
        }
        else
        {
            $keptEntries += $inputCmd;
        }
    }

    # Save JSON to file, overwriting it if it exists, creating the file if not.
    ConvertTo-Json $keptEntries | Set-Content -Path "$($OutputCompileCommandsJSON)" -Force -Encoding utf8;

    # Print the location of the generated compilation database.
    Write-Log "Generated compilation database at '$($OutputCompileCommandsJSON)'." "Success";

    # Return deleted entries.
    return $deletedEntries;
}


# [Execution] ##########################################################################################################
Export-ModuleMember Write-Log;
Export-ModuleMember Write-StandardOutput;

Export-ModuleMember New-SymbolicLink;
Export-ModuleMember New-CopyItem;
Export-ModuleMember New-TemporaryFolder;

Export-ModuleMember New-JSONC;

Export-ModuleMember New-CompilationDatabase;
Export-ModuleMember Remove-FromCompilationDatabase;

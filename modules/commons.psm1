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

    .OUTPUTS
        This function does not return a value.

    .EXAMPLE
        Write-Host -Message "Hello World" -Level "Info";
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

    .OUTPUTS
        This function does not return a value.

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

    .OUTPUTS
        This function does not return a value.

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

# [Execution] ##########################################################################################################
Export-ModuleMember Write-Log;
Export-ModuleMember Write-StandardOutput;

Export-ModuleMember New-SymbolicLink;
Export-ModuleMember New-CopyItem;

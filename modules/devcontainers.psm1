<#
.DESCRIPTION
    Functionality and utilities related to development containers using Docker.
    
    This module expects 'docker', 'docker-compose' and 'devcontainer.cmd' in the PATH environment variable.
    
    A 'vscode' service must exist in the Docker compose file.
#>

# [Initializations] ####################################################################################################

# Stop script on first error found.
$ErrorActionPreference = "Stop";

# Imports.
Import-Module "$PSScriptRoot/commons.psm1";

# [Declarations] #######################################################################################################

# [Internal Functions] #################################################################################################

# [Functions] ##########################################################################################################
function Initialize-DevContainer
{
    <#
    .DESCRIPTION
        Builds the images and containers from the development container configuration files specified.

    .PARAMETER DevcontainerFile
        Path to the 'devcontainer.json' file. This is usually in the '.devcontainer' directory.

    .PARAMETER ProjectName
        The name of the compose project to build or create.

    .PARAMETER Inputs
        Input artifacts that will be copied accross prior to building images, they follow the format:

        @{
            "input_1" = @{
                "srcPath" = "/path/to/source";
                "destPath" = "/path/to/dest/";
            };
            "input_2" = @{
                "srcPath" = "/path/to/source";
                "destPath" = "/path/to/dest";
            };
        }

        The 'destPath' must be a path in the build context of the services to build.

    .PARAMETER Outputs
        Output artifacts that will be copied to the host from the development containers, they follow the format:

        @{
            "output_1" = @{
                "containerPath" = "/path/to/source";
                "hostPath" = "/path/to/dest/";
            };
            "output_2" = @{
                "containerPath" = "/path/to/source";
                "hostPath" = "/path/to/dest";
            };
        }

        The 'containerPath' is the path in the container.

    .OUTPUTS
        This function does not return a value.

    .EXAMPLE
        Initialize-DevContainer -DevcontainerFile ".devcontainer/devcontainer.json" -ProjectName "project"
    #>
    param (
        [Parameter(Mandatory = $true)]
        [String]
        $DevcontainerFile,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ProjectName,
        [Parameter(Mandatory = $false)]
        [hashtable]
        $Inputs,
        [Parameter(Mandatory = $false)]
        [hashtable]
        $Outputs
    )

    Write-Log "Building development container at '$DevcontainerFile'...";

    # Ensure path to configuration files exist.
    if (-not (Test-Path "$DevcontainerFile"))
    {
        throw "'$DevcontainerFile' file does not exist.";
    }

    # Handle input artifacts.
    if ($PSBoundParameters.ContainsKey("Inputs"))
    {
        foreach ($key in $Inputs.Keys)
        {
            Write-Log "Copying input artifact '$key'...";
            New-CopyItem -Source "$($Inputs.$key.srcPath)" -Destination "$($Inputs.$key.destPath)";
        }
    }

    # Create images and run containers, use the cache for the images but recreate the containers.
    # Note that devcontainer does not modify the last exit code, query the 'vscode' container creation for success.
    Write-Log "Building images and development containers, running until healthy...";
    $env:COMPOSE_PROJECT_NAME = $ProjectName;
    & "devcontainer" up --config "$DevcontainerFile" --remove-existing-container;
    $vscodeContainerID = & "docker-compose" --project-name "$ProjectName" ps --all --quiet "vscode";
    if (-not $vscodeContainerID)
    {
        throw "Failed to build images and development containers.";
    }
    $env:COMPOSE_PROJECT_NAME = $null;

    # Stop required containers after they have been built.
    Write-Log "Stopping development container...";
    & "docker-compose" --project-name "$ProjectName" stop;
    if ($LASTEXITCODE -ne 0)
    {
        throw "Failed to stop development container with error '$LASTEXITCODE'.";
    }

    # Handle output artifacts.
    if ($PSBoundParameters.ContainsKey("Outputs"))
    {
        foreach ($key in $Outputs.Keys)
        {
            Write-Log "Copying output artifact '$key' from container to host...";
            & "docker" cp "$($vscodeContainerID):$($Outputs.$key.containerPath)" "$($Outputs.$key.hostPath)";
            if ($LASTEXITCODE -ne 0)
            {
                throw "Failed to copy artifact from development container with error '$LASTEXITCODE'.";
            }
        }
    }

    Write-Log "Development containers created successfully." "Success";
}

########################################################################################################################
function Start-DevContainer
{
    <#
    .DESCRIPTION
        Runs a development container in the current working directory, opening Visual Studio Code.
        
        If the development container already exists, it is used, otherwise a new one is created.

    .PARAMETER DevcontainerFile
        Path to the 'devcontainer.json' file. This is usually in the '.devcontainer' directory.

    .PARAMETER ProjectName
        The name of the compose project to start.

    .PARAMETER Inputs
        Input artifacts that will be copied accross prior to building images, they follow the format:

        @{
            "input_1" = @{
                "srcPath" = "/path/to/source";
                "destPath" = "/path/to/dest/";
            };
            "input_2" = @{
                "srcPath" = "/path/to/source";
                "destPath" = "/path/to/dest";
            };
        }

        The 'destPath' must be a path in the build context of the services to build.

    .OUTPUTS
        This function does not return a value.

    .EXAMPLE
        Start-DevContainer -DevcontainerFile ".devcontainer/devcontainer.json" -ProjectName "project"
    #>
    param (
        [Parameter(Mandatory = $true)]
        [String]
        $DevcontainerFile,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ProjectName,
        [Parameter(Mandatory = $false)]
        [hashtable]
        $Inputs
    )

    # Handle input artifacts.
    if ($PSBoundParameters.ContainsKey("Inputs"))
    {
        foreach ($key in $Inputs.Keys)
        {
            Write-Log "Copying input artifact '$key'...";
            New-CopyItem -Source "$($Inputs.$key.srcPath)" -Destination "$($Inputs.$key.destPath)";
        }
    }

    # Start development container, and check if it is running by checking the 'vscode' service, as the devcontainer
    # utility does not set the $LASTEXITCODE variable.
    $env:COMPOSE_PROJECT_NAME = $ProjectName;
    Write-Log "Starting development container '$ProjectName'...";
    & "devcontainer" up --config "$DevcontainerFile";
    $vscodeContainerID = & "docker-compose" --project-name "$ProjectName" ps --all --quiet "vscode";
    $isRunning = & "docker" ps --filter "id=$($vscodeContainerID)" --filter "status=running" --quiet --no-trunc;
    if (-not $isRunning)
    {
        throw "Failed to start development container with error '$error'.";
    }

    # Open development container.
    Write-Log "Opening folder '$PWD' in Visual Studio code and development container...";
    & "devcontainer" open "$PWD" --disable-telemetry;
    $env:COMPOSE_PROJECT_NAME = $null;
}

# [Execution] ##########################################################################################################
Export-ModuleMember Initialize-DevContainer;
Export-ModuleMember Start-DevContainer;

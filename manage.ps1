<#
.SYNOPSIS
    Management script based on PowerShell, this script must be executed from the root directory.
#>

# [Initializations] ####################################################################################################
param (
    # Command to execute, one of:
    #    'load': Host/Container command, loads the Powershell modules in the terminal for more granular access.
    #    'clean': Host/Container command, recursively cleans the repository and submodules with Git.
    #    'build': Host command, builds the images and the development containers.
    #    'run': Host command creates or uses an existing development container and starts it in the current folder.
    [Parameter(Mandatory = $true)]
    [ValidateSet("load", "clean", "build", "run")]
    [String]
    $Command
)

# Stop on first error found.
$ErrorActionPreference = "Stop";

# Imports.
Import-Module "$PSScriptRoot/modules/commons.psm1";
Import-Module "$PSScriptRoot/modules/devcontainers.psm1"

# [Declarations] #######################################################################################################
# Path to 'devcontainer.json' file.
$DEVCONTAINER_FILE = ".devcontainer/devcontainer.json"; 
# Project name for the Docker compose project.
$DEVCONTAINER_PROJECT_NAME = "powershell_scripts";

# [Internal Functions] #################################################################################################

# [Functions] ##########################################################################################################

# [Execution] ##########################################################################################################
# Ensure the current location is the location of the script.
if (((Get-Item "$PSScriptRoot").Hashcode) -ne ((Get-Item "$PWD").Hashcode))
{
    throw "The script must run from the root directory, where this script is located."
}

if ($Command -eq "load")
{
    # The modules have already been imported due to the imports above, perform no other action.
    Write-Log "Modules imported." "Success";
}
elseif ($Command -eq "clean")
{
    Write-Log "Cleaning repository and submodules...";
    git clean -d -fx -f;
    git submodule foreach --recursive git clean -d -fx -f;
    Write-Log "Repository and submodules cleaned." "Success";
}
elseif ($Command -eq "build")
{
    # Build inputs for the development container.
    $inputs = @{};

    # Build outputs for the development container.
    $outputs = @{};

    Initialize-DevContainer -DevcontainerFile "$DEVCONTAINER_FILE" -ProjectName "$DEVCONTAINER_PROJECT_NAME" `
        -Inputs $inputs -Outputs $outputs;
}
elseif ($Command -eq "run")
{
    # Artifacts to copy in the workspace for the initialization script.
    $inputs = @{
        # This is the host path to Git authentication key.
        # 
        # This can't be provided as a secret in the Compose file as it needs specific permissions for it to be
        # trusted by the SSH utilities, and Compose does not do that, thus we copy it here and set the permissions
        # explicitly from the initialization script.
        "Git Authentication Key" = @{
            "hostPath" = "../!local/other-files/github/dmg0345-authentication-key/private-authentication-key.pem";
        };

        # This is the host path to Git signing key to sign commits.
        # 
        # This can't be provided as a secret in the Compose file as it needs specific permissions for it to be
        # trusted by the SSH utilities, and Compose does not do that, thus we copy it here and set the permissions
        # explicitly from the initialization script.
        "Git Signing Key" = @{
            "hostPath" = "../!local/other-files/github/dmg0345-signing-key/private-signing-key.pem";
        };
    };
    
    # Create initialization script for the volume of the development container.
    $initScript = @'
# Configure Git for user.
git config --global user.name "$ENV:GITHUB_USERNAME";
git config --global user.email "$ENV:GITHUB_EMAIL";
git config --global user.signingkey "/vol_store/private-signing-key.pem";
git config --global core.sshCommand "ssh -i '/vol_store/private-authentication-key.pem' -o 'IdentitiesOnly yes'";

# Own and set permissions of the keys to read/write for SSH to use them.
Get-ChildItem -Path "/vol_store" -Include "*.pem" -Recurse | ForEach-Object -Process `
{
    chown $(id -u -n) "$($_.FullName)";
    chmod 600 "$($_.FullName)";
}

# Trust Github for SSH connections.
if (-not (Test-Path "~/.ssh/known_hosts")) { New-Item -Path "~/.ssh/known_hosts" -ItemType File -Force | Out-Null; }
Set-Content -Path "~/.ssh/known_hosts" -Value "$(ssh-keyscan github.com)" -Force;

# Clone repository in the workspace folder.
git clone --recurse-submodules --branch develop "git@github.com:dmg0345/powershell.git" ".";
if ($LASTEXITCODE -ne 0) { throw "Failed to clone repository." }
'@;

    Start-DevContainer -DevcontainerFile "$DEVCONTAINER_FILE" -ProjectName "$DEVCONTAINER_PROJECT_NAME" `
        -VolumeInitScript $initScript -Inputs $inputs;
}
else
{
    throw "Command '$Command' is not recognized or an invalid combination of arguments was provided.";
}

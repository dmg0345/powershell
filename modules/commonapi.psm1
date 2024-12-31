<#
.DESCRIPTION
    COVESA / GENIVI Common API C++ related utilities.
#>

# [Initializations] ####################################################################################################

# Stop script on first error found.
$ErrorActionPreference = "Stop";

# Imports.
Import-Module "$PSScriptRoot/commons.psm1";

# [Declarations] #######################################################################################################

# [Internal Functions] #################################################################################################

# [Functions] ##########################################################################################################
function New-CommonAPIGeneration
{
    <#
    .DESCRIPTION
        Given a series of folders with Franca Interface Definition Language, '.fidl', and Franca Deployment, '.fdepl',
        files, runs the Common API C++ generators on them to produce generated source code.

        A first pass generates source code from the '.fidl' files with the Core generator. There must be at least 
        one '.fidl' file in the folder specified.

        A second pass generates source code from the '.fidl' and '.dbus.fdepl' files with the DBus generator. There
        must be at least one '.dbus.fdepl' file in the folder specified, if dbus is used.

        A third pass generates source code from the '.fidl' and '.someip.fdepl' files with the SomeIP generator. There
        must be at least one '.someip.fdepl' file in the folder specified, if someip is used.

    .PARAMETER Inputs
        An array of objects of the following type:

        @{
            "fidlDir" = "Path to the folder with '.fidl', '.dbus.fdepl' and '.someip.fdepl' files.";
            "coreDir" = "Path to the folder where the outputs of the core generator will be stored.";
            "dbusDir" = "Optional, path to the folder where the outputs of the dbus generator will be stored.";
            "someipDir" = "Optional, path to the folder where the outputs of the someip generator will be stored.";
            "clearOutputs" = "Optional, deletes the output directories before generating the outputs.";
        }

    .PARAMETER CoreGenerator
        Path to the 'commonapi-core-generator' executable.

    .PARAMETER DBusGenerator
        Path to the 'commonapi-dbus-generator' executable, can be NULL if not used.

    .PARAMETER SomeIPGenerator
        Path to the 'commonapi-someip-generator' executable, can be NULL if not used.

    .EXAMPLE
        New-CommonAPIGeneration -Inputs $fidlObjects `
            -CoreGenerator 'commonapi-core-generator' `
            -DBusGenerator 'commonapi-dbus-generator' `
            -SomeIPGenerator 'commonapi-someip-generator';
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]
        $Inputs,
        [Parameter(Mandatory = $true)]
        [String]
        $CoreGenerator,
        [Parameter(Mandatory = $false)]
        [String]
        $DBusGenerator,
        [Parameter(Mandatory = $false)]
        [String]
        $SomeIPGenerator
    )

    Write-Log "Generating Common API C++ source code from Franca IDL and deployment files...";

    # Create temporary folder to use as input for the generators.
    $tempFolder = New-TemporaryFolder;
    try
    {
        # Loop every folder specified as an input, build the temporary folders and run the generators.
        foreach ($input in $Inputs)
        {
            # Get paths to '.fidl', '.dbus.fdepl', and '.someip.fdepl' files in the folder specified.
            $fidlFiles = @(); $fdeplDBusFiles = @(); $fdeplSomeIPFiles = @();
            $fidlFiles += (Get-ChildItem -Path "$($input.fidlDir)" -Filter '*.fidl') | ForEach-Object { $_.FullName }
            $fdeplDBusFiles += (Get-ChildItem -Path "$($input.fidlDir)" -Filter '*.dbus.fdepl') | ForEach-Object { $_.FullName }
            $fdeplSomeIPFiles += (Get-ChildItem -Path "$($input.fidlDir)" -Filter '*.someip.fdepl') | ForEach-Object { $_.FullName }

            # Ensure there is a deployment file for a binding, otherwise it is invalid.
            if (($fdeplDBusFiles.Length -eq 0) -and ($fdeplSomeIPFiles.Length -eq 0))
            {
                throw "No DBus or SomeIP bindings found in folder '$($input.fidlDir)'.";
            }

            # Perform the three passes described in the documentation.
            foreach ($pass in @("core", "dbus", "someip"))
            {
                if ($pass -eq "core")
                {
                    # Check if there are '.fidl' files in folder, if not, it is an error.
                    if ($fidlFiles.Length -eq 0) { throw "Folder '$($input.fidlDir)' does not have any '.fidl' files."; }
                    Write-Log "Generating common source code from for '$($input.fidlDir)' with core generator...";

                    # Ensure output folder is empty if it already exists.
                    if (($input.clearOutputs -eq $true) -and (Test-Path -Path "$($input.coreDir)"))
                    {
                        Remove-Item -Path "$($input.coreDir)" -Force -Recurse;
                    }

                    # Fill temporary folder with '.fidl' files.
                    $fidlFiles | ForEach-Object {
                        $filename = (Split-Path -Path $_ -Leaf);
                        Copy-Item -Path "$($_)" -Destination "$($tempFolder)/$($filename)";
                        Write-Log "Using file '$($_)' for core generator...";
                    };

                    # Run core generator.
                    & "$($CoreGenerator)" `
                        --dest "$($input.coreDir)" `
                        --dest-common "$($input.coreDir)/common" `
                        --dest-proxy "$($input.coreDir)/proxy" `
                        --dest-stub "$($input.coreDir)/stub" `
                        --dest-skel "$($input.coreDir)/skel" `
                        --dest-subdirs --skel --searchpath "$($tempFolder)" --printfiles;
                    if ($LASTEXITCODE -ne 0) { throw "Failed to run core generator on folder '$($input.fidlDir)'."; }
                    Write-Log "Finished generating core source code from for '$($input.fidlDir)'..." "Success";
                }
                elseif ($pass -eq "dbus")
                {
                    # Check if there are '.dbus.fdepl' files in folder, if not, then continue with next binding.
                    if ($fdeplDBusFiles.Length -eq 0) { continue; }
                    Write-Log "Generating dbus source code from '$($input.fidlDir)' with dbus generator...";

                    # Ensure output folder is empty if it already exists.
                    if (($input.clearOutputs -eq $true) -and (Test-Path -Path "$($input.dbusDir)"))
                    {
                        Remove-Item -Path "$($input.dbusDir)" -Force -Recurse;
                    }

                    # Fill temporary folder with '.fidl' and '.dbus.fdepl' files.
                    ($fidlFiles + $fdeplDBusFiles) | ForEach-Object {
                        $filename = (Split-Path -Path $_ -Leaf) -Replace '.dbus.fdepl', '.fdepl';
                        Copy-Item -Path "$($_)" -Destination "$($tempFolder)/$($filename)";
                        Write-Log "Using file '$($_)' for dbus generator...";
                    };

                    # Run dbus generator.
                    & "$($DBusGenerator)" `
                        --dest "$($input.dbusDir)" `
                        --dest-common "$($input.dbusDir)/common" `
                        --dest-proxy "$($input.dbusDir)/proxy" `
                        --dest-stub "$($input.dbusDir)/stub" `
                        --dest-subdirs --searchpath "$($tempFolder)" --printfiles;
                    if ($LASTEXITCODE -ne 0) { throw "Failed to run dbus generator on folder '$($input.fidlDir)'."; }
                    Write-Log "Finished generating dbus source code from '$($input.fidlDir)'..." "Success";
                }
                elseif ($pass -eq "someip")
                {
                    # Check if there are '.someip.fdepl' files in folder, if not, then continue with next binding.
                    if ($fdeplSomeIPFiles.Length -eq 0) { continue; }
                    Write-Log "Generating some source code from '$($input.fidlDir)' with someip generator...";

                    # Ensure output folder is empty if it already exists.
                    if (($input.clearOutputs -eq $true) -and (Test-Path -Path "$($input.someipDir)"))
                    {
                        Remove-Item -Path "$($input.someipDir)" -Force -Recurse;
                    }

                    # Fill temporary folder with '.fidl' and '.someip.fdepl' files.
                    ($fidlFiles + $fdeplSomeIPFiles) | ForEach-Object {
                        $filename = (Split-Path -Path $_ -Leaf) -Replace '.someip.fdepl', '.fdepl';
                        Copy-Item -Path "$($_)" -Destination "$($tempFolder)/$($filename)";
                        Write-Log "Using file '$($_)' for someip generator...";
                    };

                    # Run someip generator.
                    & "$($SomeIPGenerator)" `
                        --dest "$($input.someipDir)" `
                        --dest-common "$($input.someipDir)/common" `
                        --dest-proxy "$($input.someipDir)/proxy" `
                        --dest-stub "$($input.someipDir)/stub" `
                        --dest-subdirs --val-warnings-as-errors --searchpath "$($tempFolder)" --printfiles;
                    if ($LASTEXITCODE -ne 0) { throw "Failed to run someip generator on folder '$($input.fidlDir)'."; }
                    Write-Log "Finished generating someip source code from '$($input.fidlDir)'..." "Success";
                }

                # Leave temporary folder empty for the next run.
                Get-ChildItem -Path ($tempFolder) -Recurse | ForEach-Object { Remove-Item "$($_.FullName)" -Force -Recurse; };
            }
        }
    }
    finally
    {
        # Remove temporary folder in any scenario.
        if (Test-Path -Path "$($tempFolder)") { Remove-Item -Path "$($tempFolder)" -Force -Recurse; }
    }

    Write-Log "Finished generating Common API C++ source code from Franca IDL and deployment files..." "Success";
}

# [Execution] ##########################################################################################################
Export-ModuleMember New-CommonAPIGeneration;

#######################################################################################

# Script Name: Add-UserToLocalAdmins.ps1

# Description: Adds a specified user account to the local administrators group.

#              Designed for use during a task sequence.

# Author: [Your Name]

# Version: 1.0

# Date: [Date]

#######################################################################################

<#

.SYNOPSIS

Adds a user account to the local Administrators group on a machine.

.DESCRIPTION

This script adds a specified user or group account to the local Administrators group on the machine

where it is executed. Designed to be used during task sequences in environments like MECM.

.PARAMETER UserName

Specifies the username to add to the local Administrators group.

.EXAMPLE

Add-UserToLocalAdmins.ps1 -UserName "Domain\\Username"

Adds the user "Domain\\Username" to the local Administrators group.

.NOTES

- This script should be executed with administrative privileges.

- Ensure that the user account executing this script has the necessary permissions to modify group memberships.

#>

param (

    [Parameter(Mandatory = $true, HelpMessage = "Specify the username to add to the local Administrators group.")]

    [string]$UserName

)

# Function to Add User to Local Administrators

Function Add-UserToLocalAdmins {

    param (

        [string]$UserName

    )

    try {

        Write-Output "Attempting to add user '$UserName' to local Administrators group."

        # Get the local Administrators group

        $AdministratorsGroup = [ADSI]"WinNT://./Administrators,group"

        # Check if the user is already a member

        $IsMember = $AdministratorsGroup.psbase.Invoke("Members") | ForEach-Object {

            $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null)

        } | Where-Object { $_ -eq $UserName }

        if ($IsMember) {

            Write-Output "User '$UserName' is already a member of the Administrators group."

        } else {

            # Add the user to the Administrators group

            $AdministratorsGroup.Add("WinNT://$UserName")

            Write-Output "User '$UserName' has been added to the Administrators group."

        }

    } catch {

        Write-Error "Failed to add user '$UserName' to the Administrators group. Error: $_"

    }

}

# Call the function

Add-UserToLocalAdmins -UserName $UserName
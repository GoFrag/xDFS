<#
These integration tests can only be run on a computer that:
1. Is a member of an Active Directory domain.
2. Has access to two Windows Server 2012 or greater servers with
   the FS-DFS-Replication and RSAT-DFS-Mgmt-Con features installed.
3. An AD User account that has the required permissions that are needed
   to create a DFS Replication Group.

If the above are available then to allow these tests to be run a
MSFT_xDFSReplicationGroup.config.json file must be created in the same folder as
this file. The content should be a customized version of the following:
{
    "Username":  "CONTOSO.COM\\Administrator",
    "Folders":  [
                    "TestFolder1",
                    "TestFolder2"
                ],
    "Members":  [
                    "Server1",
                    "Server2"
                ],
    "ContentPaths":  [
                    "c:\\IntegrationTests\\TestFolder1",
                    "c:\\IntegrationTests\\TestFolder2"
                ],
    "Password":  "MyPassword"
}

If the above are available and configured these integration tests will run.
#>
$Global:DSCModuleName   = 'xDFS'
$Global:DSCResourceName = 'MSFT_xDFSReplicationGroup'

# Test to see if the config file is available.
$ConfigFile = "$([System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path))\$($Global:DSCResourceName).config.json"
if (! (Test-Path -Path $ConfigFile))
{
    return
}

#region HEADER
# Integration Test Template Version: 1.1.0
[String] $moduleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $Script:MyInvocation.MyCommand.Path))
if ( (-not (Test-Path -Path (Join-Path -Path $moduleRoot -ChildPath 'DSCResource.Tests'))) -or `
     (-not (Test-Path -Path (Join-Path -Path $moduleRoot -ChildPath 'DSCResource.Tests\TestHelper.psm1'))) )
{
    & git @('clone','https://github.com/PowerShell/DscResource.Tests.git',(Join-Path -Path $moduleRoot -ChildPath '\DSCResource.Tests\'))
}

Import-Module (Join-Path -Path $moduleRoot -ChildPath 'DSCResource.Tests\TestHelper.psm1') -Force
$TestEnvironment = Initialize-TestEnvironment `
    -DSCModuleName $Global:DSCModuleName `
    -DSCResourceName $Global:DSCResourceName `
    -TestType Integration 
#endregion

# Using try/finally to always cleanup even if something awful happens.
try
{
    #region Integration Tests
    $ConfigFile = Join-Path -Path $PSScriptRoot -ChildPath "$($Global:DSCResourceName).config.ps1" 
    . $ConfigFile

    Describe "$($Global:DSCResourceName)_Integration" {
        #region DEFAULT TESTS
        It 'Should compile without throwing' {
            {
                $ConfigData = @{
                    AllNodes = @(
                        @{
                            NodeName = 'localhost'
                            PSDscAllowPlainTextPassword = $true
                        }
                    )
                }
                Invoke-Expression -Command "$($Global:DSCResourceName)_Config -OutputPath `$TestEnvironment.WorkingFolder -ConfigurationData `$ConfigData"
                Start-DscConfiguration -Path $TestEnvironment.WorkingFolder -ComputerName localhost -Wait -Verbose -Force
            } | Should not throw
        }

        It 'should be able to call Get-DscConfiguration without throwing' {
            { Get-DscConfiguration -Verbose -ErrorAction Stop } | Should Not throw
        }
        #endregion

        It 'Should have set the resource and all the parameters should match' {
            $ReplicationGroupNew = Get-DfsReplicationGroup `
                -GroupName $ReplicationGroup.GroupName `
                -ErrorAction Stop
            $ReplicationGroupNew.GroupName                 | Should Be $ReplicationGroup.GroupName
            $ReplicationGroupNew.Description               | Should Be $ReplicationGroup.Description
            # Check the members are in the Replication Group
            foreach ($Member in $ReplicationGroup.Members)
            {
                $ReplicationGroupMemberNew = Get-DfsrMember `
                    -GroupName $ReplicationGroup.GroupName `
                    -ComputerName $Member `
                    -ErrorAction Stop
                $ReplicationGroupMemberNew.GroupName       | Should Be $ReplicationGroup.GroupName
                # If Member name was an FQDN then match the DNSName property, otherwise the ComputerName property
                if ($Member.Contains('.'))
                {
                    $ReplicationGroupMemberNew.DnsName    | Should Be $Member
                }
                else
                {
                    $ReplicationGroupMemberNew.ComputerName    | Should Be $Member
                }
            }
            # Check the folders are in the Replication Group
            foreach ($Folder in $ReplicationGroup.Folders)
            {
                $ReplicationGroupFolderNew = Get-DfsReplicatedFolder `
                    -GroupName $ReplicationGroup.GroupName `
                    -FolderName $Folder `
                    -ErrorAction Stop
                $ReplicationGroupFolderNew.GroupName       | Should Be $ReplicationGroup.GroupName
                $ReplicationGroupFolderNew.FolderName      | Should Be $Folder
            }
        }
        
        # Clean up
        Remove-DFSReplicationGroup `
            -GroupName $ReplicationGroup.GroupName `
            -RemoveReplicatedFolders `
            -Force `
            -Confirm:$false
    }
    #endregion
}
finally
{
    #region FOOTER
    Restore-TestEnvironment -TestEnvironment $TestEnvironment
    #endregion
}

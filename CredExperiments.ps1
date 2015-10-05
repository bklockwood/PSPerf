function Test-Uptime {
<#
.Synopsis
Retreive uptime from computer.
.DESCRIPTION
   TBD
.PARAMETER Computer
Name of computer to retreive uptime from.
.EXAMPLE
   Example of how to use this cmdlet

#>

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true, Position=0)][Alias("hostname")]$ComputerName
    )

    $Error.Clear()
    #Get-CimInstance $computername takes a long time to fail if it cannot reach the target system.
    #So, invoke it on the remote computer via invoke-command with -AsJob
    #This way the job can be killed if not complete within an arbitrary amount of time. 
    $sb = {(Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $Using:ComputerName).LastBootUpTime}             
    $job = invoke-command -Computername $ComputerName -ScriptBlock $sb -AsJob
    Wait-Job $job -Timeout 10 |out-null
    Stop-Job $job
    Write-Verbose $job.State
    Switch ($job.State) {
        "Completed" {$lastboot = Receive-Job $job}
        "Failed" {$lastboot = "JobFailed"}
        Default {$lastboot = "JobTimeout"}
    }
    Remove-Job $job
    $lastboot
    break
    
    if ($error -or ($lastboot -eq "TIMEOUT")) {
        #If prior down report, calculate downtime, else write DOWN report and set downtime at 0d:0h:0m
        #if computer has gone from up to down, DownSince is written and Upsince is removed 
        write-verbose "$ComputerName is DOWN"
         $StorageHash.$ComputerName.Remove("UpSince")
        if (!$StorageHash.$ComputerName.DownSince) {            
            $storagehash.$ComputerName.Add("DownSince",(Get-Date))           
        }
    } else {        
        write-verbose "$ComputerName is UP"
        $StorageHash.$ComputerName.Remove("DownSince")
        #if computer has gone from down to up, UpSince gets written, and DownSince is removed
        if (!$StorageHash.$ComputerName.UpSince) {            
            $StorageHash.$ComputerName.Add("UpSince",$lastboot)
        }

        #make sure UpSince value is correct
        if ($StorageHash.$ComputerName.UpSince -ne $lastboot) {
            $StorageHash.$ComputerName.Set_Item("UPSince",$lastboot)
        }

    }

}

function Test-PsRemoting { 
<#
.SYNOPSIS
Tests whether PSRemoting to target computer is possible.
.PARAMETER Computername
Name of computer to test PSRemoting with.
.PARAMETER Credential
A PSCredential valid to the specified computer.
.NOTES
I have expanded on Lee Holmes' example at http://goo.gl/80QT23
Logic:
 +Attempt PsRemoting to $Computername via invoke-command
   +If FAIL:
    -Check and report whether localhost allows PSRemoting
    -Check and report whether $Computername is in TrustedHosts
    -Check and report whether $Computername is reachable on network
    -Check and report whether $Computername allows PSRemoting TODO
    -Check and report whether creds are valid on $Computername TODO
   +If SUCCESS:
    -Report $true
.EXAMPLE
PS> Test-PsRemoting -Computername ad1 -Credential $cred
True
.EXAMPLE
PS> Test-PsRemoting -Computername FAKENAME -Credential $cred -Verbose
WARNING: Could not connect to FAKENAME
VERBOSE: [FAKENAME] Connecting to remote server FAKENAME failed with the following error message : The WinRM client cannot proce
ss the request. If the authentication scheme is different from Kerberos, or if the client computer is not joined to a domain, th
en HTTPS transport must be used or the destination machine must be added to the TrustedHosts configuration setting. Use winrm.cm
d to configure TrustedHosts. Note that computers in the TrustedHosts list might not be authenticated. You can get more informati
on about that by running the following command: winrm help config. For more information, see the about_Remote_Troubleshooting He
lp topic.
VERBOSE: PSRemoting is enabled locally
VERBOSE: FAKENAME is NOT in TrustedHosts
VERBOSE: Testing connection to computer 'FAKENAME' failed: No such host is known
#>
    [CmdletBinding()]
    param( 
        [Parameter(Mandatory = $true, Position=0)]$Computername,
        [Parameter(Position=1)][PSCredential]$Credential
    ) 
    
    try { 
        $ErrorActionPreference = "Stop"
        if ($Credential) {
            $icmresult = Invoke-Command -ComputerName $computername -ScriptBlock { 1 } -Credential $Credential
        } else {
            $icmresult = Invoke-Command -ComputerName $computername -ScriptBlock { 1 } 
        }
    } catch { 
        $icmresult = $_ 
    } 

    if ($icmresult -eq 1) {
        return $true 
        #Function ends here if the Invoke-Command succeeded
    } else {
        Write-Warning "Could not connect to $Computername"
        Write-Verbose "$icmresult"
    }    
    
    #Report whether PSRemoting is enabled locally
    $psremotingenabled = $true
    try {
        $ErrorActionPreference = "Stop"
        New-PSSession -ComputerName localhost -Name testsession | out-null
    } catch {
        Write-Verbose "PSRemoting is NOT enabled locally."
        $psremotingenabled = $false
    }    
    if ($psremotingenabled) {
        Remove-PSSession -name testsession | out-null
        Write-Verbose "PSRemoting is enabled locally"
    }

    #Report whether remote computer is in TrustedHosts
    if ((get-item WSMan:\localhost\Client\TrustedHosts).Value -contains $Computername) {
        Write-Verbose "$Computername is in TrustedHosts"
    } else {
        Write-Verbose "$Computername is NOT in TrustedHosts"
    }

    #Report whether remote computer is pingable
    $reachable = $true
    try {
        $ErrorActionPreference = "Stop"
        test-connection -ComputerName $Computername -Count 1 |out-null
    } catch {
        Write-Verbose "$_"
        $reachable = $false
    }
    if ($reachable) {Write-Verbose "$Computername reachable on network"}

   
}

function Write-PSCredFile {
<#
.SYNOPSIS
Create a textfile containing username and securestring, which can be made into a PSCredential object.
.PARAMETER Computername
Name of computer the cred will be used on.
.NOTES
TBD
.EXAMPLE
TBD
#>
    [CmdletBinding()]
    param( 
        [Parameter(Mandatory=$true, Position=0)]$Computername
    )  

    #Prompt for the username
    $UserName = Read-Host -Prompt "Enter username to be used on $Computername"

    #Prompt for the password
    $SecurePass = Read-Host -Prompt "Enter password to be used on $Computername" -AsSecureString

    #Prompt for the output filepath
    $OutputFile = Read-Host -Prompt "Enter full path and name of filename to write. (Example: .\$Computername-Creds.txt)"

    $Computername | out-file -FilePath $OutputFile
    $username | out-file -FilePath $OutputFile -Append -NoClobber
    $SecurePass | ConvertFrom-SecureString | Out-File -FilePath $OutputFile -Append -NoClobber

}

function New-PSCredObj {
<#
.SYNOPSIS
Build PSCredential object using textfile created with Write-PSCredFile.
.PARAMETER InputFile
Name of file created with Write-PSCredFile.
.NOTES
TBD
.EXAMPLE
TBD
#>
    [CmdletBinding()]
    param( 
        [Parameter(Mandatory=$true, Position=0)]$InputFile
    ) 

    $contents = get-content $InputFile
    $Computername = $contents[0]
    $Username = $contents[1]
    $SecurePassword = $contents[2] | ConvertTo-SecureString
    $NewCred = New-Object System.Management.Automation.PSCredential -ArgumentList $UserName, $SecurePassword
    Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value $Computername -Concatenate
    $NewCred

}

break
Test-PsRemoting ad1 -Credential $ad1cred -Verbose
break
Test-Uptime -ComputerName ad1 -verbose
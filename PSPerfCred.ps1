function Test-PsRemoting { 
<#
.SYNOPSIS
Tests whether PSRemoting to target computer is possible.
Helps troubleshoot PSRemoting failures by breaking down 
possible causes.
.DESCRIPTION
TBD
.PARAMETER Computername
Name of computer to test PSRemoting with.
.PARAMETER Credential
A PSCredential valid to the specified computer.
.PARAMETER Details
Perform detailed checks and show results.
If this parameter is omitted, the cmdlet returns only 
a boolean (true/false)value.
.NOTES
I have expanded on Lee Holmes' example at http://goo.gl/80QT23
Logic:
 +Attempt PsRemoting to $Computername via invoke-command
   +If FAIL:
    -Check and report whether localhost allows PSRemoting
    -Check and report whether $Computername is in TrustedHosts
    -Check and report whether $Computername is pingable on network
    -Check and report whether $Computername allows PSRemoting 
    -Check and report whether creds are valid on $Computername TODO
   +If SUCCESS:
    -Report $true
.EXAMPLE
PS> Test-PsRemoting -Computername ad1 -Credential $cred
True
.EXAMPLE
PS> Test-PsRemoting -Computername ad1 -Details
Checking whether PSRemoting is enabled locally ...ENABLED (good).
Looking for ad1 in TrustedHosts ... FOUND (good).
Testing ping to ad1 ... SUCCESS (good).
Testing connection to ad1 WSMAN port ... OPEN (good).
PSRemoting to ad1 ...FAIL (bad)
[ad1] Connecting to remote server ad1 failed with the following error message : 
Access is denied. For more information, see the about_Remote_Troubleshooting 
Help topic.
#>
    [CmdletBinding()]
    param( 
        [Parameter(Mandatory = $true, Position=0)]$Computername,
        [Parameter(Position=1)][PSCredential]$Credential,
        [Parameter(Position=2)][switch]$Details
    )

    #if the Details switch is on, do all these detailed checks to 
    #help narrow down the cause of PSRemoting failures
    if ($Details) {
    
        #Report whether we can PSRemote to localhost
        Write-Host "Checking whether PSRemoting is enabled locally ... " -NoNewline -ForegroundColor White
        $psremotingenabled = $true
        try {
            $ErrorActionPreference = "Stop"
            New-PSSession -ComputerName localhost -Name testsession | out-null
        } catch {
            Write-Host "NOT ENABLED (bad)" -ForegroundColor Red
            $psremotingenabled = $false
        }    
        if ($psremotingenabled) {
            Remove-PSSession -name testsession | out-null
            Write-Host "ENABLED (good)." -ForegroundColor Green 
        }

        #Report whether remote computer is in TrustedHosts
        Write-Host "Looking for $Computername in TrustedHosts ... " -NoNewline
        $trustedhosts = (get-item WSMan:\localhost\Client\TrustedHosts).Value
        $trustedhosts = $trustedhosts -split(',')
        if ($trustedhosts -contains $Computername) {
            Write-Host -ForegroundColor Green "FOUND (good)."
        } else {
            Write-Host -ForegroundColor Red "NOT FOUND (bad)."
        }

        #Report whether remote computer is pingable
        #Should get IP another way, a system may have ping filtered while allowing WSMAN
        Write-Host "Testing ping to $Computername ... " -NoNewline
        $pingable = $true
        try {
            $ErrorActionPreference = "Stop"
            $pingresult = test-connection -ComputerName $Computername -Count 1 
            $ip = $pingresult.IPV4Address.IPAddressToString
        } catch {
            Write-Host -ForegroundColor Red "FAIL (bad)."
            $pingable = $false
        }        
        if ($pingable) {Write-Host -ForegroundColor Green "SUCCESS (good)."}
    
        #Report whether WSMAN port 5985 is open
        if ($pingable) {
            if (Test-Path Variable:socket) {Remove-Variable socket; write-host "removed"}
            Write-Host "Testing connection to $Computername WSMAN port ... " -NoNewline        
            try {            
                $socket = New-Object System.Net.Sockets.TcpClient
                $socket.SendTimeout = 1000
                $socket.ReceiveTimeout = 1000      
                $socket.BeginConnect($ip, 5985, $null, $null) | Out-Null            
            } catch {
                Write-Host -ForegroundColor Red "ERROR, FAIL (bad)."
                Write-Host $_
            } 
            start-sleep -Milliseconds 500         
            if ($socket.Connected -eq $true) {
                Write-Host -ForegroundColor Green "SUCCESS (good)."
                $socket.Close()
            } else {
                Write-Host -ForegroundColor Red "FAIL (bad)."
            }
        } #end "if ($pingable)"
        
     } #end "if ($Details)"

    #Now actually try a PSRemoting connection
    if ($Details) {Write-Host "PSRemoting to $Computername ... " -NoNewline}
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
        if (!$Details) {return $true}
        else {Write-Host -ForegroundColor Green "SUCCESS (good)"}
    } else {        
        if (!$Details) {return $false}
        else {
            Write-Host -ForegroundColor Red "FAIL (bad)"
            Write-Host -ForegroundColor Red "$icmresult"
        }
    }
}

function Add-PSCredtext {
<#
.SYNOPSIS
Interactively prompt user for a computername, username and password.
These are used to generate new lines added to PSPerf.ini
#>
    [CmdletBinding()]

    #Prompt for the computer name
    $Computername = Read-Host -Prompt "Enter the computer name."
    if ((get-item WSMan:\localhost\Client\TrustedHosts).Value -notcontains $Computername) {
        $yesno = Get-YNAnswer -Question "$Computername is not in TrustedHosts. Add it? (Y/N)"
        if ($yesno -eq "Y") { 
            Add-TrustedHost $Computername
            Write-Host "$Computername was added to TrustedHosts"
        } else {
            Write-Host "No modification to TrustedHosts"
        }
    }

    #Prompt for the username
    $UserName = Read-Host -Prompt "Enter username to be used on $Computername"

    #Prompt for the password
    $SecurePass = Read-Host -Prompt "Enter password to be used on $Computername" -AsSecureString
    $SecurePass = $SecurePass | ConvertFrom-SecureString
    [string]$output = @"

[$Computername]
username=$username
securestring=$SecurePass
"@

    Write-Host "The following will be added to PSPerf.ini:"
    Write-Host $output
    $answer = Get-YNAnswer -Question "Is this OK? (Y/N)"
    If ($answer -eq "Y") {
        $output | out-file -FilePath .\psperf.ini -Encoding ascii -Append -Force
    } else {
        Write-Host "By answering 'N' you have cancelled the script."
    }

}

function Get-YNAnswer {
<#
.SYNOPSIS
Ask a question. Constrain the answer to "Y" or "N".
Warn and repeat question if user flubs it.
.PARAMETER Question
The question to ask.
#>
    Param ( [Parameter(Mandatory=$true)][string]$Question )

    try {
        [ValidateSet("Y", "N")]$answer = Read-Host -Prompt $Question
    } catch {
        Write-Warning "Your answer must be either Y or N. Please try again."
        Get-YNAnswer $Question
    }
    $answer
}

function Add-TrustedHost {
<#
.SYNOPSIS
Add a computer to the TrustedHosts list
.PARAMETER ComputerName
Name of computer to add.
.LINK
http://blogs.technet.com/b/heyscriptingguy/archive/2013/11/29/remoting-week-non-domain-remoting.aspx
#>
    [CmdletBinding()]
    param( 
        [Parameter(Mandatory=$true, Position=0)]$ComputerName
    ) 

    Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value "$Computername" -Concatenate
}

function New-Cred {
<#
.SYNOPSIS
Build a PSCredential object using username 
and plaintext securestring.
.PARAMETER UserName
A username, typically in one of the following forms:
username
domainname\username
computername\username
username@somedomain.com
.PARAMETER SecureString
A plaintext securestring, often obtained via some construct such as:
$PlainTextSecureString = $SecureString | ConvertFrom-SecureString
.LINK
http://social.technet.microsoft.com/wiki/contents/articles/4546.working-with-passwords-secure-strings-and-credentials-in-windows-powershell.aspx
#>
    [CmdletBinding()]
    param( 
        [Parameter(Mandatory=$true, Position=0)]$UserName,
        [Parameter(Mandatory=$true, Position=1)]$SecureString
    )
    $NewCred = New-Object System.Management.Automation.PSCredential -ArgumentList $UserName, $SecureString
    $NewCred
}

$config = Get-IniContent .\psperf.ini
foreach ($target in ($config.targets.keys | where-object {$_ -notLike "Comment*" } | sort) ) {
    $target
    #first we try PSRemoting with implicit creds
    Write-Host " Try PSRemoting to $target using implicit creds ... " -NoNewline
    if (Test-PsRemoting -Computername $target) {write-host "SUCCESS"}
    else {
        #if PSRemoting fails, we try finding creds in PSPerf.ini (which is loaded as $config)
        Write-Host "FAIL"
        Write-Host " Looking for configured creds ... " -NoNewline
        if ($config.$target.username) {
            $username = $config.$target.username
        } else {
            $username = $config.defaults.username
        }

        if ($config.$target.securestring) {
            $securestring = $config.$target.securestring
        } else {
            $securestring  = $config.defaults.securestring
        }

        #if we've found creds in PSPerf.ini, try PSRemoting with those
        if (($username -eq $null) -and ($securestring -eq $null)) {
            Write-Host "NONE FOUND "
        } else {
            Write-Host "FOUND"
            Write-Host " Creating cred object ... " -NoNewline
            $securestring = $securestring | ConvertTo-SecureString
            try {$cred = New-Cred -UserName $username -SecureString $securestring}
            catch {write-host "FAIL"}
            if ($cred) {Write-Host "SUCCESS"}
            Write-Host " Try PSRemoting to $target using configured creds ... " -NoNewline            
            if (Test-PsRemoting $target $cred) {Write-Host "SUCCESS"}
            else {Write-Host "FAIL. Giving up."}            
        }
    }

        
    

    
}
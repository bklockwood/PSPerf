function Get-PerfDataOld {
<#
.Synopsis
   Gets a specific set of perfmon counters from local or remote computer.
   Returns a hashtable containing the data.
.DESCRIPTION
   The returned hashtable includes:
   CpuQueue, \System\Processor Queue Length
   PagesPerSec, \Memory\Pages Input/Sec
   DiskQueues, a hashtable containing on or more of the following objects:
        Instance = \PhysicalDisk\Avg. Disk Queue Length
   
   Each  disk "Instance" is a physical disk labeled by its disk number and 
   the partitions it contains. Examples: 
   
   "0 c:"     (disk 0 contains partition c:)
   "1 e: f:"  (disk 1 contains partitions e: and f:)
.PARAMETER ComputerName
The computer to get perfmon counter data from.
.EXAMPLE
PS> $pdata = get-perfdata -ComputerName s1
PS> $pdata
Name                           Value
----                           -----
DiskQueues                     @{0 c:=0.27; 1 e: f:=0; _total=0.27} 
CpuQueue                       1
PagesPerSec                    0
PS> $pdata.DiskQueues
$pdata.DiskQueues
0 c:      1 e: f:       _total
----      -------       ------
0.27      0             0.27
PS> $pdata.DiskQueues._total
0
PS> $pdata.CpuQueue
1
#>
    [CmdletBinding()]
    [OutputType([hashtable])]
    Param
    (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)]
        [Alias("hostname")]
        [string]$ComputerName,
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]
        $PerfCounters
    )

    Begin{}
    Process {
        #create two hashtable arrays, populate with data from perf counters
        $datahash = @{}
        $dqhash = @{}
        
        foreach ($comp in $ComputerName) {
            $error.Clear()
            $perfdata = get-counter -ComputerName $computername -counter $PerfCounters -ErrorAction SilentlyContinue
            if ($error) {
                write-host "ERROR"
            } else {
                foreach ($item in $perfdata.CounterSamples) {
                    write-host $item.path, $item.status, $item.CookedValue
                    if ($item.path -like "*Processor*") {$datahash.Add("CpuQueue",[math]::Round($item.cookedvalue))}
                    if ($item.path -like "*Pages*") {$datahash.Add("PagesPerSec", [math]::Round($item.cookedvalue))}
                    if ($item.path -like "*Logicaldisk*") {
                        if ($($item.instancename) -ne "_total") {
                            #perfmon names physicaldisk instances like so: "0 c: d:", "1 f: g:"
                            #store as "disk0", "disk1" etc.
                            [string]$diskname = $($item.instancename)
                            #$diskname = "disk$($diskname.substring(0,1))" no, store as the actual instancename (using logicaldisks now)
                            $dqhash.Add($diskname, [math]::Round($item.cookedvalue)) 
                        }                   
                    }
                }
            }
            #if any counter returns no data, populate with string "null"
            #because thats what jquery.sparklines will process properly
            if ($datahash.Keys -notcontains "CpuQueue") {$datahash.Add("CpuQueue","null")}
            if ($datahash.Keys -notcontains "PagesPerSec") {$datahash.Add("PagesPerSec","null")}
            if ($dqhash.Count -lt 1) {
                write-host "dqhash has no values!"
                $dqhash.Add("C:", "null")
                $dqhash.Add("D:", "null")                
            }
            $datahash.Add("DiskQueues", $dqhash)
            $datahash
        }
    }
    End{}
}

function Get-Perfdata {
<#
.Synopsis
Gets and stores perf data into a hashtable of previously collected data
.DESCRIPTION

.PARAMETER ComputerName
The computer to get perfmon counter data from.
.PARAMETER PerfCounters
Performance counters to retreive from ComputerName.
.PARAMETER StorageHash
The hash we'll add data to.

.EXAMPLE
   TBD
#>

    [CmdletBinding()]
    [OutputType([hashtable])]
    Param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)]
        [Alias("hostname")]
        [string]$ComputerName,
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]
        $StorageHash
    )

    Begin{}
    Process {        
        foreach ($comp in $ComputerName) {
            Write-Verbose $comp
            #if we haven't polled this computer before, create hashtable locations to store the data
            if ($StorageHash.keys -notcontains $comp) {
                Write-verbose " $comp not present in StorageHash, adding"
                $StorageHash.Add($comp, @{})
                $StorageHash.$comp.CpuQueue = New-Object System.Collections.ArrayList
                $StorageHash.$comp.MemQueue = New-Object System.Collections.ArrayList
                $StorageHash.$comp.Events = New-Object System.Collections.ArrayList
                $storageHash.$comp.Add("DiskQueue",@{})
                $storageHash.$comp.Add("DiskFree",@{})
            }
            $error.Clear()
            $PerfCounters = '\System\Processor Queue Length',
                            '\Memory\Pages Input/Sec',
                            '\LogicalDisk(*)\Avg. Disk Queue Length',
                            '\LogicalDisk(*)\% Free Space'
            $perfdata = get-counter -ComputerName $computername -counter $PerfCounters -ErrorAction SilentlyContinue
            if ($error) {
                Write-Error "ERROR"
            } else {
                #test whether $perfdata.countersamples.path contains each of the counters we want 
                #(if not, must write 'null')

                #cpuqueue
                $cdata=$perfdata.CounterSamples | Where-Object {$_.path -like "*process*"}
                Write-Verbose " $($cdata.Path), $($cdata.CookedValue)"
                if ($cdata.CookedValue -eq $null) {
                    [void] $StorageHash.$comp.CpuQueue.Add("null")
                } else {
                    [void] $StorageHash.$comp.CpuQueue.Add($cdata.cookedvalue)
                }

                #memqueue
                $cdata=$perfdata.CounterSamples | Where-Object {$_.path -like "*pages*"}
                Write-Verbose " $($cdata.Path), $($cdata.CookedValue)"
                if ($cdata.CookedValue -eq $null) {
                    [void] $StorageHash.$comp.MemQueue.Add("null")
                } else {
                    [void] $StorageHash.$comp.MemQueue.Add($cdata.cookedvalue)
                }

                #events
                #placeholder, I have not written the event gatherer yet
                [void] $StorageHash.$comp.Events.Add("null")


                #diskqueue
                if ($config.$comp.disks) {
                    $disks = $config.$comp.disks.split(",")
                } else {
                    $disks = $config.defaults.disks.split(",")
                }
                foreach ($disk in $disks) {
                    Write-Verbose "  DiskQueue $disk"
                    if (!$StorageHash.$comp.DiskQueue.$disk) {
                        $StorageHash.$comp.DiskQueue.$disk = New-Object System.Collections.ArrayList
                    }                
                    $cdata=$perfdata.CounterSamples | 
                        Where-Object {$_.path -like "*logicaldisk($disk)\avg. disk queue length*"}
                    Write-Verbose "   $($cdata.Path), $($cdata.CookedValue)"
                    if ($cdata.CookedValue -eq $null) {
                        [void] $StorageHash.$comp.DiskQueue.$disk.Add("null")
                    } else {
                        [void] $StorageHash.$comp.DiskQueue.$disk.Add($cdata.cookedvalue)
                    }
                }

                #diskfree (for each disk to check)
                foreach ($disk in $disks) {
                    Write-Verbose "  DiskFree $disk"
                    if (!$StorageHash.$comp.DiskFree.$disk) {
                        $StorageHash.$comp.DiskFree.$disk = New-Object System.Collections.ArrayList
                    }                
                    $cdata=$perfdata.CounterSamples | 
                        Where-Object {$_.path -like "*logicaldisk($disk)\% free space*"}
                    Write-Verbose "   $($cdata.Path), $($cdata.CookedValue)"
                    if ($cdata.CookedValue -eq $null) {
                        [void] $StorageHash.$comp.DiskFree.$disk.Add("null")
                    } else {
                        [void] $StorageHash.$comp.DiskFree.$disk.Add($cdata.cookedvalue)
                    }
                }
            }
        }
    }
    End{}

}

function Add-PerfDataOld {
<#
.Synopsis
   Stores perf data (from get-perfdata) into a hashtable of previously collected data
.DESCRIPTION
   Recurses through the collected performance data, writes it 
   to arrays in the storage hashtable (which contains prior collected data)
   for later use.
.PARAMETER StorageHash
   The hash we'll add data to.
.PARAMETER ComputerName
   The name of the Computer this data was collected from.
.PARAMETER PerfData
   Output from the Get-PerfData function/cmdlet
.EXAMPLE
   TBD
#>

    [CmdletBinding()]
    #[OutputType([int])]
    Param
    (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)][Alias("p1")][hashtable]$StorageHash,        
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, Position=1)][string]$ComputerName,
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, Position=2)][hashtable]$PerfData
    )

    Begin{}
    Process {
        #recursively iterate the hashtables and arrays in the $Perfdata hashtable,
        #and write their values to $storagehash
        #I am proud of my very first recursive function!
        function recurse ($object, $parent) {
            foreach ($key in $object.Keys) {
                if ($object.$key.GetType() -eq [System.Collections.Hashtable]) {
                    if ($storageHash.$ComputerName.Keys -notcontains $key) {
                        $storageHash.$ComputerName.Add($key,@{})
                    }
                    Recurse $object.$key $Key
                } else {
                    if ($parent) {
                        if ($StorageHash.$ComputerName.$parent.Keys -notcontains $key) {
                            $StorageHash.$ComputerName.$parent.$key = New-Object System.Collections.ArrayList
                        }
                        [void] $StorageHash.$ComputerName.$parent.$key.Add($object.$key)
                    } else {
                        if ($StorageHash.$ComputerName.Keys -notcontains $key) {
                            $StorageHash.$ComputerName.$key = New-Object System.Collections.ArrayList
                        }
                        [void] $StorageHash.$ComputerName.$key.Add($object.$key)
                    }
                }
            }
        } #end function recurse
        if ($StorageHash.Keys -notcontains $ComputerName) {$StorageHash.Add($ComputerName,@{})}  
        recurse $PerfData
    } #end process block

    End{}
}

function Output-StatusCell {
<#
.Synopsis
   Writes the 'Status' cell of a system's status line
.DESCRIPTION
   Long description
.Parameter ComputerName
    The computername
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
#>

    [CmdletBinding()]
    [OutputType([int])]
    Param
    (
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,Position=0)]$ComputerName
    )

    Begin{}
    Process {
        [bool]$reb = "$false" #true if server needs reboot
        [int]$SecPatch = 0 #security patches outstanding
        [int]$RecPatch = 0 #Recommended patches outstanding
        [int]$OptPatch = 0 #Optional patches outstanding
        [bool]$up = "$true" #True if server retruns CpuQueue value; false if not
        #[System.DateTime]$changed #timestamp of last time the $up value changed
        $Output += "<td><font size=""2"" color=""LightGray"">R </font>"
        $Output += "<font size=""1"" color=""LightGray"">P: $SecPatch.s/$RecPatch.r/$OptPatch.o</font>"
        $Output += "<br><font size=""1"" color=""green"">~ ~d:~h:~m</font></td>`r`n"
        $Output
    }
    End{}
}

function Output-CurrentPerfTableOld {
<#
.Synopsis
   Reads from hashtable of collected data and writes a web formatted table of
   sparklines.
.DESCRIPTION
   TBD
.PARAMETER DataStore
   The storage hash output from Add-PerfData
.PARAMETER Path
   Full path of file (usually a *.html) to output to.
.EXAMPLE
   Example of how to use this cmdlet

#>

    [CmdletBinding()]
    [OutputType([string])]
    Param
    (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)]
        [Alias("InputObject")][hashtable]$DataStore
    )

    Begin{}
    Process {
        [string]$Output = "<table class=""gridtable"">`r`n"
        $Output += "<tr><th></th><th>status</th><th>cpu</th><th>mem</th><th>events</th><th>disks</th></tr>`r`n"
        
        #start walking down the object. this should be recursive but I am lazy
        foreach ($key in $DataStore.Keys | Sort ) {
            if ($DataStore.$key.GetType() -eq [System.Collections.Hashtable] ) {
                $Computername = $key
            } 
            foreach ($subkey in $DataStore.$key.Keys) {
                if ($DataStore.$key.$subkey.GetType() -eq [System.Collections.Hashtable]) {
                    foreach ($subsubkey in $DataStore.$key.$subkey.Keys) {
                        #if array has > 144 elements, shrink to 144 (removing first, oldest elements)
                        while ($DataStore.$key.$subkey.$subsubkey.Count -gt 144) {
                                $DataStore.$key.$subkey.$subsubkey.RemoveAt(0)
                            }
                        if ($subsubkey.ToUpper() -eq "C:") {$disk1 = $DataStore.$key.$subkey.$subsubkey}
                        if ($subsubkey.ToUpper() -eq "D:") {$disk2 = $DataStore.$key.$subkey.$subsubkey}
                    } 
                } else {
                    #if array has > 144 elements, shrink to 144 (removing first, oldest elements)
                    while ($DataStore.$key.$subkey.Count -gt 144) {
                            $DataStore.$key.$subkey.RemoveAt(0)
                        }
                    if ($subkey -eq "CpuQueue") {$cpu = $DataStore.$key.$subkey}
                    if ($subkey -eq "PagesPerSec") {$mem = $DataStore.$key.$subkey}
                }
            }
            if ($cpu[-1] -eq "null") { #if no CpuQueue value received, mark computer with black backround, red text
                $Output += "<tr><td style=""background-color:black""><font color=""red"">$Computername</td>`r`n"
            } else {
                $Output += "<tr><td>$Computername</td>`r`n"
            }
            $Output += Output-StatusCell -ComputerName $Computername
            $Output += "<td><span class=""cpu"">$($cpu -join(","))</span></td>`r`n"
            $Output += "<td><span class=""mem"">$($mem -join(","))</span></td>`r`n"
            $Output += "<td><span class=""eventlog""></span></td>"
            $Output += "<td valign=""bottom"">C:<span class=""disk0"">$($disk1 -join(","))</span>&nbsp D:<span class=""disk1"">$($disk2 -join(","))</span></td>`r`n"
            #$Output += "<td><span class=""disk1"">$($disk2 -join(","))</span></td>`r`n"
            
            $Output += "</tr>`r`n`r`n"
        }
        $Output += "</table>`r`n`r`n"
        $Output
    } #end process block
    End{}
}

function Output-CurrentPerfTable {
<#
.Synopsis
   Reads from hashtable of collected data and writes a web formatted table of
   sparklines.
.DESCRIPTION
   TBD
.PARAMETER DataStore
   The storage hash output from Add-PerfData
.PARAMETER Path
   Full path of file (usually a *.html) to output to.
.EXAMPLE
   Example of how to use this cmdlet

#>

    [CmdletBinding()]
    [OutputType([string])]
    Param
    (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)]
        [Alias("InputObject")][hashtable]$StorageHash
    )

    Begin {write-verbose "Output-CurrentPerfTable"}
    Process {
        
        [string]$Output = "<table class=""gridtable"">`r`n"
        $Output += "<tr><th></th><th>status</th><th>cpu</th><th>mem</th><th>events</th><th>disks</th></tr>`r`n"
        foreach ($PC in $StorageHash.Keys | Sort ) {
            write-verbose " $PC"
            #if no CpuQueue value received, mark computer with black backround, red text
            if ($($StorageHash.$PC.CpuQueue[-1]) -eq "null") { 
                $Output += "<tr><td style=""background-color:black""><font color=""red"">$PC</td>`r`n"
            } else {
                $Output += "<tr><td>$PC</td>`r`n"
            }
            $Output += Output-StatusCell -ComputerName $PC
            write-verbose "  CpuQueue: $($StorageHash.$PC.CpuQueue)"
            $Output += "<td><span class=""cpu"">$($StorageHash.$PC.CpuQueue -join(","))</span></td>`r`n"
            write-verbose "  MemQueue: $($StorageHash.$PC.MemQueue)"
            $Output += "<td><span class=""mem"">$($StorageHash.$PC.MemQueue -join(","))</span></td>`r`n"
            write-verbose "  Events: $($StorageHash.$PC.Events)"
            $Output += "<td><span class=""events"">$($StorageHash.$PC.Events -join(","))</span></td>`r`n"
            $Output += "<td valign=""bottom"">"
            foreach ($disk in $StorageHash.$PC.DiskQueue.Keys) {
                [string]$dq = $($StorageHash.$PC.DiskQueue.$disk -join(","))
                $diskfree = $($StorageHash.$PC.DiskFree.$disk[-1])
                [string]$du = 100 - $diskfree
                $du = $du + ":100"
                write-verbose "  Disks:"
                Write-Verbose "    $disk queue $dq  "
                Write-Verbose "    $disk used $du"
                $Output += "$disk <span class=""diskused"">$du</span><span class=""disk"">$dq </span>&nbsp"
            }
           $Output += "</td>`r`n"
            
        }
        $Output += "</table>`r`n`r`n"
        $Output
    } #end process block
    End{}
}

function Output-Pageheader {
<#
.Synopsis
   Writes page header
.DESCRIPTION
   Long description
.PARAMETER Param1
Help for Param1
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
#>
    [CmdletBinding()]
    [OutputType([string])]
    Param
    (
        #[Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)][Alias("p1")][string]$Param1,        
        #[Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, Position=1)][int]$Param2
    )

    Begin{}

    Process {
        [string]$Output = @'
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" 
   "http://www.w3.org/TR/html4/strict.dtd">
<head>
    <meta http-equiv="refresh" content="5">    
	<style type="text/css">
	    body {
		    font:  16px Courier New, monospace;
		    line-height: 15px;
		    padding: 2em 3em;
	    }
	    table.gridtable {
		    font: italic 18px Consolas;
		    color:#333333;
		    border-width: 1px;
		    border-color: Gainsboro;
		    border-collapse: collapse;
	    }
	    table.gridtable th {
		    font: italic bold 18px Consolas;
		    text-align: center;
		    border-width: 1px;
		    padding: 5px;
		    border-style: solid;
		    border-color: Gainsboro;
		    background-color: #dedede;
	    }
	    table.gridtable td {
		    font: italic bold 14px Consolas;
		    border-width: 1px;
		    padding: 5px;
		    border-style: solid;
		    border-color: Gainsboro;
		    background-color: #ffffff;
	    }
    </style>

    <script type="text/javascript" src="https://cdn.jsdelivr.net/jquery/2.1.4/jquery.min.js"></script>
    <script type="text/javascript" src="https://cdn.jsdelivr.net/jquery.sparkline/2.1.2/jquery.sparkline.min.js"></script>
    <script type="text/javascript">
        $(function() {
	      $('.cpu').sparkline('html', { type: 'line', lineColor:'red', fillColor:"MistyRose", height:"30", 
		    width:"100", chartRangeMin:"0", chartRangeMax:"25", chartRangeClip: true } );
	      $('.mem').sparkline('html', { type: 'line', lineColor:'blue', fillColor:"MistyRose", height:"30", 
		    width:"100", chartRangeMin:"0", chartRangeMax:"50", chartRangeClip: true } );
	      $('.events').sparkline('html', { type: 'line', lineColor:'purple', fillColor:"MistyRose", height:"30", 
		    width:"100", chartRangeMin:"0", chartRangeMax:"5", chartRangeClip: true } );
	      $('.disk').sparkline('html', { type: 'line', lineColor:'orange', fillColor:"MistyRose", height:"30", 
		    width:"100", chartRangeMin:"0", chartRangeMax:"5", chartRangeClip: true } );
          $('.diskused').sparkline('html', { type: 'bar', stackedBarColor:["DarkRed","SeaGreen"], barWidth:"10", 
            zeroAxis:'false', height:"30", chartRangeMin:"0", chartRangeMax:"100"} );
          $('.eventlog').sparkline('html', { type: 'line', lineColor:'SaddleBrown', fillColor:"MistyRose", height:"30", 
            width:"100", chartRangeMin:"0", chartRangeMax:"10", chartRangeClip: true } )
        });
    </script>
    </head>
    <body>
    <b>Test</b> <hr>

'@
        $Output
    }

    End{}
}

function Output-PageFooter { 
<#
.Synopsis
   Short description
.DESCRIPTION
   Long description
.PARAMETER Param1
Help for Param1
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
#>
    [CmdletBinding()]
    [OutputType([string])]
    Param
    (
        #[Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)][Alias("p1")][string]$Param1,        
        #[Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, Position=1)][int]$Param2
    )

    Begin{}

    Process {
        [string]$Output = "</body>`r`n</html>`r`n"
        $Output
    }

    End{}
}

Function Get-IniContent {
    <#
    .Synopsis
        Gets the content of an INI file
    .Description
        Gets the content of an INI file and returns it as a hashtable
    .Notes
        Author		: Oliver Lipkau <oliver@lipkau.net>
        Blog		: http://oliver.lipkau.net/blog/
		Source		: https://github.com/lipkau/PsIni
                      http://gallery.technet.microsoft.com/scriptcenter/ea40c1ef-c856-434b-b8fb-ebd7a76e8d91
        Version		: 1.0.0 - 2010/03/12 - OL - Initial release
                      1.0.1 - 2014/12/11 - OL - Typo (Thx SLDR)
                                              Typo (Thx Dave Stiff)
                      1.0.2 - 2015/06/06 - OL - Improvment to switch (Thx Tallandtree)
                      1.0.3 - 2015/06/18 - OL - Migrate to semantic versioning (GitHub issue#4)
                      1.0.4 - 2015/06/18 - OL - Remove check for .ini extension (GitHub Issue#6)
        #Requires -Version 2.0
    .Inputs
        System.String
    .Outputs
        System.Collections.Hashtable
    .Parameter FilePath
        Specifies the path to the input file.
    .Example
        $FileContent = Get-IniContent "C:\myinifile.ini"
        -----------
        Description
        Saves the content of the c:\myinifile.ini in a hashtable called $FileContent
    .Example
        $inifilepath | $FileContent = Get-IniContent
        -----------
        Description
        Gets the content of the ini file passed through the pipe into a hashtable called $FileContent
    .Example
        C:\PS>$FileContent = Get-IniContent "c:\settings.ini"
        C:\PS>$FileContent["Section"]["Key"]
        -----------
        Description
        Returns the key "Key" of the section "Section" from the C:\settings.ini file
    .Link
        Out-IniFile
    #>

    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [ValidateScript({(Test-Path $_)})]
        [Parameter(ValueFromPipeline=$True,Mandatory=$True)]
        [string]$FilePath
    )

    Begin
        {Write-Verbose "$($MyInvocation.MyCommand.Name):: Function started"}

    Process
    {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Processing file: $Filepath"

        $ini = @{}
        switch -regex -file $FilePath
        {
            "^\[(.+)\]$" # Section
            {
                $section = $matches[1]
                $ini[$section] = @{}
                $CommentCount = 0
                continue
            }
            "^(;.*)$" # Comment
            {
                if (!($section))
                {
                    $section = "No-Section"
                    $ini[$section] = @{}
                }
                $value = $matches[1]
                $CommentCount = $CommentCount + 1
                $name = "Comment" + $CommentCount
                $ini[$section][$name] = $value
                continue
            }
            "(.+?)\s*=\s*(.*)" # Key
            {
                if (!($section))
                {
                    $section = "No-Section"
                    $ini[$section] = @{}
                }
                $name,$value = $matches[1..2]
                $ini[$section][$name] = $value
                continue
            }
        }
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Finished Processing file: $FilePath"
        Return $ini
    }

    End
        {Write-Verbose "$($MyInvocation.MyCommand.Name):: Function ended"}
}


## ---------------------------------------Script starts here---------------------------------
$config = Get-IniContent .\psperf.ini
if (!$StorageHash) {
    if (get-item $datafile -ErrorAction ignore) {
        $StorageHash = Import-Clixml -Path $config.files.datafile
    } else {
        $StorageHash = @{}
    }
}

foreach ($target in ( $config.targets.keys | sort) ) {    
    #Lipkau's Get-IniContent renders comment lines as keys named Comment1, Comment2, etc. 
    #ignore these!
    if ($target -notLike "Comment*" ) {Get-PerfData -ComputerName $target -StorageHash $StorageHash -Verbose}
}
#Export-Clixml -InputObject $StorageHash -Path $datafile -Force

$htmlstring = Output-Pageheader
$htmlstring += Output-CurrentPerfTable -StorageHash $StorageHash -verbose
$htmlstring += Output-PageFooter
out-file -InputObject $htmlstring -FilePath $config.files.htmlfile -Encoding UTF8 -Force

<# 
Next steps:

#> 

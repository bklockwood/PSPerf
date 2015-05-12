function Get-PerfData {
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
        [string]$ComputerName
    )

    Begin{}
    Process {
        #create two hashtable arrays, populate with data from perf counters
        $datahash = @{}
        $dqhash = @{}
        $perfcounters= '\System\Processor Queue Length', 
            '\Memory\Pages Input/Sec', 
            '\PhysicalDisk(*)\Avg. Disk Queue Length'
        foreach ($comp in $ComputerName) {
            $perfdata = get-counter -ComputerName $computername -counter $perfcounters -ErrorAction Ignore
            foreach ($item in $perfdata.CounterSamples) {
                if ($item.path -like "*Processor*") {$datahash.Add("CpuQueue",[math]::Round($item.cookedvalue))}
                if ($item.path -like "*Pages*") {$datahash.Add("PagesPerSec", [math]::Round($item.cookedvalue))}
                if ($item.path -like "*Physicaldisk*") {
                    if ($($item.instancename) -ne "_total") {
                        #perfmon names disk instances like so: "0 c: d:", "1 f: g:"
                        #store as "disk0", "disk1" etc.
                        [string]$diskname = $($item.instancename)
                        $diskname = "disk$($diskname.substring(0,1))"
                        $dqhash.Add($diskname, [math]::Round($item.cookedvalue)) 
                    }                   
                }
            }
            #if any counter returns no data, populate with string "null"
            #because thats what jquery.sparklines will process properly
            if ($datahash.Keys -notcontains "CpuQueue") {$datahash.Add("CpuQueue","null")}
            if ($datahash.Keys -notcontains "PagesPerSec") {$datahash.Add("PagesPerSec","null")}
            if ($dqhash.Count -lt 1) {
                $dqhash.Add("disk0", "null")
                $dqhash.Add("disk1", "null")                
            }
            $datahash.Add("DiskQueues", $dqhash)
            $datahash
        }
    }
    End{}
}

function Add-PerfData {
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
        [bool]$up = "$true" #True is server retruns CpuQueue value; false if not
        #[System.DateTime]$changed #timestamp of last time the $up value changed
        $Output += "<td><font size=""2"" color=""LightGray"">R </font>"
        $Output += "<font size=""1"" color=""LightGray"">P: $SecPatch.s/$RecPatch.r/$OptPatch.o</font>"
        $Output += "<br><font size=""1"" color=""green"">~ ~d:~h:~m</font></td>`r`n"
        $Output
    }
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
        [Alias("InputObject")][hashtable]$DataStore
    )

    Begin{}
    Process {
        [string]$Output = "<table class=""gridtable"">`r`n"
        $Output += "<tr><th></th><th>status</th><th>cpu</th><th>mem</th><th>disk0</th><th>disk1</th><th>eventlog</th></tr>`r`n"
        
        #start walking down the object. this should be recursive but I am lazy
        foreach ($key in $DataStore.Keys | Sort $key) {
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
                        if ($subsubkey -eq "disk0") {
                            $disk1 = $DataStore.$key.$subkey.$subsubkey
                            }
                        if ($subsubkey -eq "disk1") {$disk2 = $DataStore.$key.$subkey.$subsubkey}
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
            $Output += "<td><span class=""disk0"">$($disk1 -join(","))</span></td>`r`n"
            $Output += "<td><span class=""disk1"">$($disk2 -join(","))</span></td>`r`n"
            $Output += "<td><span class=""eventlog""></span></td>"
            $Output += "</tr>`r`n`r`n"
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
	      $('.disk0').sparkline('html', { type: 'line', lineColor:'purple', fillColor:"MistyRose", height:"30", 
		    width:"100", chartRangeMin:"0", chartRangeMax:"5", chartRangeClip: true } );
	      $('.disk1').sparkline('html', { type: 'line', lineColor:'orange', fillColor:"MistyRose", height:"30", 
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
    Version		: 1.0 - 2010/03/12 - Initial release 
                  1.1 - 2014/12/11 - Typo (Thx SLDR)
                                     Typo (Thx Dave Stiff)
         
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
    [ValidateScript({(Test-Path $_) -and ((Get-Item $_).Extension -eq ".ini")})] 
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
        } 
    } 
    Write-Verbose "$($MyInvocation.MyCommand.Name):: Finished Processing file: $FilePath" 
    Return $ini 
} 
         
End 
    {Write-Verbose "$($MyInvocation.MyCommand.Name):: Function ended"} 

}


## ---------------------------------------Script starts here---------------------------------
$psperfdir = "C:\Users\bryanda"
$datafile = "$psperfdir\datastore.clixml"
if (!$StorageHash) {
    if (get-item $datafile -ErrorAction ignore) {
        $StorageHash = Import-Clixml -Path $datafile
    } else {
        $StorageHash = @{}
    }
}
$computername = 's2', 's3', 'hyper1', 'hyper2', 'ad6', 'ad5', 'fs5'
foreach ($comp in $computername) {
    $pdata = Get-PerfData $comp
    add-perfdata -StorageHash $StorageHash -Computername $comp -PerfData $pdata
}
Export-Clixml -InputObject $StorageHash -Path $datafile -Force
$htmlfile = "$psperfdir\PSPerf.html"
$htmlstring = Output-Pageheader
$htmlstring += Output-CurrentPerfTable -DataStore $StorageHash
$htmlstring += Output-PageFooter
out-file -InputObject $htmlstring -FilePath $htmlfile -Encoding UTF8 -Force

<# 
Next steps:

#> 

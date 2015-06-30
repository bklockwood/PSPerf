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
            $PerfCounters = '\System\Processor Queue Length',
                            '\Memory\Pages Input/Sec',
                            '\LogicalDisk(*)\Avg. Disk Queue Length',
                            '\LogicalDisk(*)\% Free Space'
            #read psperf.ini to find which disks to poll
            if ($config.$comp.disks) {
                    $disks = $config.$comp.disks.split(",")
            } else {
                $disks = $config.defaults.disks.split(",")
            }
            #if we haven't polled this computer before, create hashtable locations to store the data
            if ($StorageHash.keys -notcontains $comp) {
                Write-verbose " $comp not present in StorageHash, adding"
                $StorageHash.Add($comp, @{})
                $StorageHash.$comp.CpuQueue = New-Object System.Collections.ArrayList
                $StorageHash.$comp.MemQueue = New-Object System.Collections.ArrayList
                $StorageHash.$comp.Events = New-Object System.Collections.ArrayList
                $storageHash.$comp.Add("DiskQueue",@{})
                $storageHash.$comp.Add("DiskFree",@{})
                foreach ($disk in $disks) {
                    $StorageHash.$comp.DiskQueue.$disk = New-Object System.Collections.ArrayList
                    $StorageHash.$comp.DiskFree.$disk = New-Object System.Collections.ArrayList
                }
            }  
            write-verbose "disks for $comp - $disks"
            $error.Clear()
            $perfdata = get-counter -ComputerName $comp -counter $PerfCounters -ErrorAction SilentlyContinue
            if ($error) {
                Write-Verbose "ERROR here we are"
                [void] $StorageHash.$comp.CpuQueue.Add("null")
                [void] $StorageHash.$comp.MemQueue.Add("null")
                [void] $StorageHash.$comp.Events.Add("null")
                foreach ($disk in $disks) {
                    Write-Verbose "in the disks clause"
                    [void] $StorageHash.$comp.DiskQueue.$disk.Add("null")
                    [void] $StorageHash.$comp.DiskFree.$disk.Add("null")
                }
                write-verbose "end of error clause"
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

                #diskfree 
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
                if ($($StorageHash.$PC.DiskFree.$disk[-1]) -notlike "null") {
                    $diskfree = $($StorageHash.$PC.DiskFree.$disk[-1])
                    $du = 100 - $diskfree
                    $du = [math]::Round($du)
                    #$du = $du + ":100"
                    $df = 100 - $du
                    [string]$diskused = $df.ToString() + ":" + $du.ToString()
                } else {
                    $du = "null"
                }
                write-verbose "  Disks:"
                Write-Verbose "    $disk queue $dq  "
                Write-Verbose "    $disk used $diskused"
                $Output += "$disk <span class=""diskused"">$diskused</span><span class=""disk"">$dq </span>&nbsp"
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

    <script type="text/javascript" src="jquery-1.11.2.min.js"></script>
    <script type="text/javascript" src="jquery.fortes.sparkline.min.js"></script>
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
          
          $('.diskused').sparkline('html', { type: 'bar', barWidth:10, stackedBarColor:["DarkRed","SeaGreen"],  
            zeroAxis:'false', width:10, height:"30", chartRangeMin:"0", chartRangeMax:"100"} );
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

foreach ($target in ($config.targets.keys | sort) ) {    
    #Lipkau's Get-IniContent renders comment lines as keys named Comment1, Comment2, etc. 
    #ignore these!
    if ($target -notLike "Comment*" ) {Get-PerfData -ComputerName $target -StorageHash $StorageHash}
}
Export-Clixml -InputObject $StorageHash -Path $datafile -Force

$htmlstring = Output-Pageheader
$htmlstring += Output-CurrentPerfTable -StorageHash $StorageHash 
$htmlstring += Output-PageFooter
out-file -InputObject $htmlstring -FilePath $config.files.htmlfile -Encoding UTF8 -Force

<# 
Next steps:

#> 

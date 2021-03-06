function Get-Data {
<#
.Synopsis
Wrapper function calls Get-Uptime, Get-Perfdata, Get-RebootStatus, 
Get-EventCount, and Get-PendingWU
.DESCRIPTION
TBD
.PARAMETER Computer
Name of computer to retreive uptime from.
.PARAMETER StorageHash
The storage hash to write to
.EXAMPLE
TBD

#>

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)][Alias("hostname")]$ComputerName,
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]$StorageHash
    )

    Write-Verbose "$ComputerName get-uptime: $(measure-command `
        {Get-Uptime -ComputerName $ComputerName -Storagehash $StorageHash})"
    Write-Verbose "$ComputerName perfdata: $(measure-command `
        {Get-PerfData -ComputerName $ComputerName -StorageHash $StorageHash})"
    Write-Verbose "$ComputerName rebootstatus: $(measure-command `
        {Get-RebootStatus -ComputerName $ComputerName -StorageHash $StorageHash})"
    Write-Verbose "$ComputerName Get-EventCount: $(Measure-Command `
        {Get-EventCount -ComputerName $ComputerName -LastSystemEvent $StorageHash.$ComputerName.LastSystemEvent `
        -LastApplicationEvent $StorageHash.$ComputerName.LastApplicationEvent})"
    Write-Verbose "$ComputerName Get-PendingWU: $(Measure-Command `
        {Get-PendingWU -ComputerName $ComputerName -StorageHash $StorageHash})"
}

function Get-Uptime {
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
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)][Alias("hostname")]$ComputerName,
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]$StorageHash
    )

    $Error.Clear()
    #Get-CimInstance $computername takes a long time to fail if it cannot reach the target system.
    #So, invoke it on the remote computer via invoke-command with -AsJob
    #This way the job can be killed if not complete within an arbitrary amount of time. 
    $sb = {(Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $Using:ComputerName).LastBootUpTime}
    $Session = Get-PSSession | Where ComputerName -eq $ComputerName
    if ($Session) {
        Write-Verbose "Session $Computername found"
        $job = invoke-command -Session $Session -ScriptBlock $sb -AsJob 
    } else {
        Write-Verbose "Session $Computername not found"      
        $job = invoke-command -Computername $ComputerName -ScriptBlock $sb -AsJob
    }
    Wait-Job $job -Timeout 10 |out-null
    Stop-Job $job 
    if ($job.State -eq "Completed") {$lastboot = Receive-Job $job} else {$lastboot = "TIMEOUT"}
    Remove-Job $job
    
    if ($error -or ($lastboot -eq "TIMEOUT")) {
        #If no prior down report, write DOWN report and set downtime 
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

function Get-RebootStatus {
<#
.Synopsis
Find out of computer needs a reboot. Returns $true or $false.
.DESCRIPTION TBD
.PARAMETER TBD
.PARAMETER TBD
.EXAMPLE
   Example of how to use this cmdlet
#>

    [CmdletBinding()]

    Param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)][Alias("hostname")]$ComputerName,
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]$StorageHash
    )

    Begin { Write-Verbose "Starting function 'Get-RebootStatus'"}
    Process {
        $sb = {
            $NeedsReboot = $false
            $CBS = (Test-Path -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending")
            $FRO = (Test-Path -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\FileRenameOperations\NeedsReboot")
            if ($CBS -or $FRO) {$NeedsReboot = $true}
            Write-Verbose "CBS $CBS FRO $FRO"
            $NeedsReboot
        }
        
        try {
            #Invoke-Command can take over two minutes to fail if it cannot connect to target.
            #So I'm using -asjob to impose a 10 second timeout.
            #$job = invoke-command -Computername $ComputerName -ScriptBlock $sb -AsJob -ErrorAction Stop
            $Session = Get-PSSession | Where ComputerName -eq $ComputerName
            if ($Session) {
                Write-Verbose "Session $Computername found"
                $job = invoke-command -Session $Session -ScriptBlock $sb -AsJob 
            } else {
                Write-Verbose "Session $Computername not found"      
                $job = invoke-command -Computername $ComputerName -ScriptBlock $sb -AsJob
            }
            Wait-Job $job -Timeout 10 |out-null
            Stop-job $job
            if ($job.State -eq "Completed") { $status = Receive-Job $job } else { $status = "TIMEOUT"}
            Remove-Job $job
        } catch {
            Write-warning "Error in Get-RebootStatus (catch block, $ComputerName)"
        }

        switch ($status) {
            "TIMEOUT" {
                #will write $false and hope a value is returned on next status check
                Write-Verbose "::::$ComputerName pendingreboot: NO STATUS RETURNED"
                $StorageHash.$ComputerName.Set_Item("PendingReboot", $false)
            }
            $false {
                #the $false value is used to make logic easier in Output-StatusCell
                Write-Verbose "::::$ComputerName pendingreboot: FALSE"
                $StorageHash.$ComputerName.Set_Item("PendingReboot", $false)
            }
            default {
                Write-Verbose "::::$ComputerName pendingreboot: TRUE, $(Get-Date)"
                #If there is already a timestamp written, do not overwrite
                if ($StorageHash.$ComputerName.PendingReboot.GetType() -ne "System.DateTime") {
                    Write-Verbose "$Computername has needed reboot since $($StorageHash.$ComputerName.PendingReboot)"
                    $StorageHash.$ComputerName.Set_Item("PendingReboot", (Get-Date))
                }                
            }
        }
    } 

    End { Write-Verbose "End of function 'Get-RebootStatus'"}
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
            $PerfCounters = '\System\Processor Queue Length',
                            '\Memory\Pages Input/Sec',
                            '\LogicalDisk(*)\Avg. Disk Queue Length',
                            '\LogicalDisk(*)\% Free Space'
            #read psperf.ini to find which disks to poll
            if ($config.$comp.disks) {
                $disks = $config.$comp.disks.split(",") | sort
            } else {
                $disks = $config.defaults.disks.split(",") | sort
            }
            
            $error.Clear()
            #Get-Counter $computername takes a long time to fail if it cannot reach the target system.
            #Also, it does not take a credential parameter.
            #So, invoke it on the remote computer via invoke-command with -AsJob
            #This way the job can be killed if not complete within an arbitrary amount of time. 
            #See https://goo.gl/zybIEc for a problem I had with icm and get-perfcounter; 
            #ThomasICG's post (select-expandproperty) solved that issue
            $sb = {get-counter $Using:PerfCounters| select -ExpandProperty CounterSamples}             
            $Session = Get-PSSession | Where ComputerName -eq $ComputerName
            if ($Session) {
                Write-Verbose "Session $Computername found"
                $job = invoke-command -Session $Session -ScriptBlock $sb -AsJob 
            } else {
                Write-Verbose "Session $Computername not found"      
                $job = invoke-command -Computername $ComputerName -ScriptBlock $sb -AsJob
            }
            Wait-Job $job -Timeout 10 |out-null
            Stop-Job $job 
            if ($job.State -eq "Completed") {$perfdata = Receive-Job $job} else {$perfdata = "TIMEOUT"}
            Remove-Job $job

            #if there's an error collecting perf data, write nulls for all fields
            if ($error -or ($perfdata -eq "TIMEOUT")) {
                #Write-Warning -Message "ERROR in Get-Perfdata" 
                [void] $StorageHash.$comp.CpuQueue.Add("null")
                [void] $StorageHash.$comp.MemQueue.Add("null")
                foreach ($disk in $disks) {                    
                    [void] $StorageHash.$comp.DiskQueue.$disk.Add("null")
                    [void] $StorageHash.$comp.DiskFree.$disk.Add("null")
                }
            } else {
                #test whether $perfdata.countersamples.path contains each of the counters we want 
                #(if not, must write 'null')

                #cpuqueue
                $cdata=$perfdata | Where-Object {$_.path -like "*process*"}
                Write-Verbose " $($cdata.Path), $($cdata.CookedValue)"
                if ($cdata.CookedValue -eq $null) {
                    [void] $StorageHash.$comp.CpuQueue.Add("null")
                } else {
                    [void] $StorageHash.$comp.CpuQueue.Add($cdata.cookedvalue)
                }

                #memqueue
                $cdata=$perfdata | Where-Object {$_.path -like "*pages*"}
                Write-Verbose " $($cdata.Path), $($cdata.CookedValue)"
                if ($cdata.CookedValue -eq $null) {
                    [void] $StorageHash.$comp.MemQueue.Add("null")
                } else {
                    [void] $StorageHash.$comp.MemQueue.Add($cdata.cookedvalue)
                }

                #diskqueue
                foreach ($disk in $disks) {
                    Write-Verbose "  DiskQueue $disk"
                    if (!$StorageHash.$comp.DiskQueue.$disk) {
                        $StorageHash.$comp.DiskQueue.$disk = New-Object System.Collections.ArrayList
                    }                
                    $cdata=$perfdata | Where-Object {$_.path -like "*logicaldisk($disk)\avg. disk queue length*"}
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
                    $cdata=$perfdata | Where-Object {$_.path -like "*logicaldisk($disk)\% free space*"}
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
    End{ Write-Verbose "Get-PerfCounter done"}

}

function Get-EventCount {
<#
.Synopsis
Retreive number of Error and Warning events from System and Application logs
on a Windows host.
.DESCRIPTION
TBD
.PARAMETER ComputerName
Name of computer to retreive events from.
.PARAMETER LastSystemEvent
Retrieves all events from System log *after* this specified index integer
.PARAMETER LastApplicationEvent
Retrieves all events from Application log *after* this specified index integer
.EXAMPLE
Example of how to use this cmdlet

#>

    [CmdletBinding()]
    [OutputType([string])]
    Param (
            [Parameter(Mandatory=$true, Position=0)][Alias("hostname")][string]$ComputerName,
            [Parameter(Mandatory=$true, Position=1)][datetime]$LastSystemEvent,
            [Parameter(Mandatory=$true, Position=2)][datetime]$LastApplicationEvent
    )

    try {
        #Get-Eventlog $computername can take a long time to fail if target system is unreachable.
        #So, invoke it on the remote computer via invoke-command with -AsJob
        #This way the job can be killed if not complete within an arbitrary amount of time. 
        #Additionally this allows a uniform way to supply credentials.
        $sb = {
            #Create a custom object containing newest timestamp in log, count of events
            $syslog = Get-EventLog -LogName System -EntryType Error, Warning -After $Using:LastSystemEvent -ErrorAction Ignore
            $applog = Get-EventLog -LogName Application -EntryType Error, Warning -After $Using:LastApplicationEvent -ErrorAction Ignore
            $eventcount = $syslog.Count + $applog.Count
            if ($($syslog.Count) -gt 0) {$systime = $syslog[0].TimeWritten} else {$systime = $Using:LastSystemEvent}
            if ($($applog.Count) -gt 0) {$apptime = $applog[0].TimeWritten} else {$apptime = $Using:LastApplicationEvent}
            $result = New-Object -TypeName PSObject
            Add-Member -InputObject $result -MemberType NoteProperty -Name SystemNewestEvent -Value $systime
            Add-Member -InputObject $result -MemberType NoteProperty -Name ApplicationNewestEvent -Value  $apptime
            Add-Member -InputObject $result -MemberType NoteProperty -Name EventCount -Value $eventcount
            $result
        }             
        $Session = Get-PSSession | Where ComputerName -eq $ComputerName
        if ($Session) {
            Write-Verbose "Session $Computername found"
            $job = invoke-command -Session $Session -ScriptBlock $sb -AsJob 
        } else {
            Write-Verbose "Session $Computername not found"      
            $job = invoke-command -Computername $ComputerName -ScriptBlock $sb -AsJob
        }
        $timeout = 120
        Wait-Job $job -Timeout $timeout |out-null
        Stop-Job $job
        if ($job.State -eq "Completed") {$result = Receive-Job $job} else {$result = "TIMEOUT"}
        Remove-Job $job 
        if ($result -ne "TIMEOUT") {
            write-verbose "$ComputerName newest System event: $($result.SystemNewestEvent)"
            $StorageHash.$ComputerName.Set_Item("LastSystemEvent", $($result.SystemNewestEvent))
            write-verbose "$ComputerName newest Application event: $($result.ApplicationNewestEvent)"
            $StorageHash.$ComputerName.Set_Item("LastApplicationEvent", $($result.ApplicationNewestEvent))
            write-verbose "$ComputerName Event count: $($result.EventCount)"
            $StorageHash.$ComputerName.ErrWarnEvents.Add($($result.EventCount)) | out-null
        } else {
            Write-Verbose "$ComputerName Get-EventCount TIMEOUT"
            $StorageHash.$ComputerName.ErrWarnEvents.Add("null") 
        }
    } catch {
        Write-Warning "ERROR in function Get-EventCount $error"
        $StorageHash.$ComputerName.ErrWarnEvents.Add("null")
    }
    
}

function Get-PendingWU {
<#
.Synopsis
Retreive number of *non-hidden* Windows Updates available but not installed.
.DESCRIPTION
TBD
.PARAMETER ComputerName
Name of computer to retreive WU count from.
.PARAMETER StorageHash
The StorageHash object to store results in.
.EXAMPLE
TBD

#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true, Position=0)][Alias("hostname")][string]$ComputerName,
        [Parameter(Mandatory=$true, Position=0)]$StorageHash
    )
    try {
        $sb = {
            $Criteria = "IsInstalled=0 and IsHidden=0"
            $Searcher = New-Object -ComObject Microsoft.Update.Searcher
            $ISearchResult = $Searcher.Search($Criteria)
            $ISearchResult | select -ExpandProperty Updates
        }
        $Session = Get-PSSession | Where ComputerName -eq $ComputerName
        if ($Session) {
            Write-Verbose "Session $Computername found"
            $job = invoke-command -Session $Session -ScriptBlock $sb -AsJob 
        } else {
            Write-Verbose "Session $Computername not found"      
            $job = invoke-command -Computername $ComputerName -ScriptBlock $sb -AsJob
        }
        Wait-Job $job -Timeout 30 #|out-null
        Stop-Job $job 
        if ($job.State -eq "Completed") {$result = Receive-Job $job} else {$result = "TIMEOUT"}
        Remove-Job $job
        #the $result variable does not get set if zero pending updates
        if (test-path variable:result) {
            Write-Verbose "Get-PendingWU $($Computername): $($result.count)"
            $StorageHash.$ComputerName.Set_Item("PendingWU", $($result.count))
        } else {
            if ($result -eq "TIMEOUT") {
                Write-Verbose "Get-PendingWU $($Computername): $result"
                $StorageHash.$ComputerName.Set_Item("PendingWU", $result)
            } else {
                Write-Verbose "Get-PendingWU $($Computername): 0"
                $StorageHash.$ComputerName.Set_Item("PendingWU", 0)
            }
        }
    } catch {
        Write-Warning "ERROR in Get-PendingWU catch block."
        $StorageHash.$ComputerName.Set_Item("PendingWU","Error")
    }
    
}

function New-ComputerRecord {
<#
.Synopsis
Writes a initial record when we start polling a new computer
.DESCRIPTION
TBD
.PARAMETER StorageHash
The data structure to write to.
.PARAMETER ComputerName
Record will be created with this name.
.EXAMPLE
TBD

#>

    Param (
        [Parameter(Mandatory=$true, Position=0)][Alias("hostname")][string]$ComputerName,
        [Parameter(Mandatory=$true, Position=1)]$StorageHash
    )

    #if we haven't polled this computer before, create hashtable locations to store the data
    if ($StorageHash.keys -notcontains $Computername) {
        Write-verbose " $Computername not present in StorageHash, adding"
        $StorageHash.Add($Computername, @{})
        $StorageHash.$Computername.CpuQueue = New-Object System.Collections.ArrayList
        $StorageHash.$Computername.MemQueue = New-Object System.Collections.ArrayList
        $storageHash.$Computername.Add("DiskQueue",@{})
        $storageHash.$Computername.Add("DiskFree",@{})
        $StorageHash.$Computername.Add("PendingReboot",$false)
        $StorageHash.$Computername.Add("LastSystemEvent",([DateTime]::Now.AddHours(-1)))
        $StorageHash.$ComputerName.Add("LastApplicationEvent",([DateTime]::Now.AddHours(-1)))
        $StorageHash.$Computername.Add("PendingWU",0)
        $Storagehash.$ComputerName.ErrWarnEvents = New-Object System.Collections.ArrayList
        if ($config.$ComputerName.disks) {
            $disks = $config.$ComputerName.disks.split(",") | sort
        } else {
            $disks = $config.defaults.disks.split(",") | sort
        }
        foreach ($disk in $disks) {
            $StorageHash.$Computername.DiskQueue.$disk = New-Object System.Collections.ArrayList
            $StorageHash.$Computername.DiskFree.$disk = New-Object System.Collections.ArrayList
        }
    }
}

function Output-Page {
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
<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html>
  <head>
    <meta content="text/html; charset=UTF-8" http-equiv="content-type">
    <title>Test on win10-dev</title>
    <style type="text/css">
	    body {
		    font:  16px Courier New, monospace;
		    line-height: 15px;
		    padding: 2em 3em;
            background-color: White;
	    }
	    table {
		    font: italic 18px Consolas;
		    color: Gray;
		    border-width: 1px;
		    border-color: Gainsboro;
		    border-collapse: collapse;
            background-color: White;
	    }
	    table th {
		    font: italic bold 18px Consolas;
		    text-align: center;
		    border-width: 1px;
		    padding: 5px;
		    border-style: solid;
            color: Black;
		    border-color: Gainsboro;
		    background-color: Gainsboro;
	    }
	    table td {
		    font: italic bold 14px Consolas;
		    border-width: 1px;
		    padding: 5px;
		    border-style: solid;
		    border-color: Gainsboro;
		    background-color: White;
            vertical-align: bottom;
        }
    </style>
    <script type="text/javascript" src="//cdn.jsdelivr.net/jquery/1.9.1/jquery-1.9.1.min.js"></script>
    <script type="text/javascript" src="jquery.sparkline.min.js"></script>
    <script type="text/javascript" src="//cdn.jsdelivr.net/momentjs/2.10.3/moment-with-locales.min.js"></script>
    <script type="text/javascript"> 
      
      $(document).ready(function(){  

        $.when($.getJSON('psperf.json'), $.getJSON('config.json')).then(function(ret1, ret2) {          
          var data = ret1[0];
          var config = ret2[0];

          //array of targets, sorted, filter out comments 
          var targets = new Array();
          for (var i in config.targets) {
            if (i.slice(0,7) != "Comment") {
                targets.push(i)
            }
          }
          //sort target array alphanumerically. thanks http://stackoverflow.com/a/9645447/2383
          targets.sort(function (a, b) {
            return a.toLowerCase().localeCompare(b.toLowerCase());
          });

          //display time of last data refresh
          moment.locale('en');
          var now = moment();
          //$('body').append('Page Refreshed: ' + now.format('YYYY/MM/DD HH:mm:ss') + '<br/>');
          var DataRefreshed = moment(data.PSPerf.LastDataWritten).format("YYYY/MM/DD hh:mm:ss");
          var DataAge = moment(data.PSPerf.LastDataWritten).fromNow()
          $('body').append('Data Refreshed: ' + DataRefreshed + ' (' + DataAge + ')');

          //write the table
          $('body').append('<table id="main">');
          $('#main').append('<tr><th></th><th>status</th><th>cpu</th><th>mem</th><th>events</th><th>disks</th></tr>');
          for (var i in targets) {
            var computername = targets[i];
 
            //the servername cell
            $('#main').append('<tr id=' + computername + '>' + computername + '</tr>');
            $('#' + computername).prepend('<td id=' + computername +'cell>' + computername + '</td>');
            $('#' + computername).append('<td id=' + computername + 'status>'); //status cell
            $('#' + computername).append('<td id=' + computername + 'cpu>'); //cpu cell
            $('#' + computername).append('<td id=' + computername + 'mem>'); //mem cell
            $('#' + computername).append('<td id=' + computername + 'events>'); //events cell
            $('#' + computername).append('<td id=' + computername + 'disks>'); //disks cell          
              
            //the status cell
              
            //status ... pending reboot?
            var rebootstatus = data[computername].PendingReboot
            if (!Boolean(rebootstatus)) {
            $('#' + computername + 'status').append('<font size="2" color="LightGray">R </font>');
            } else {
            $('#' + computername + 'status').append('<font size="2" color="Red">R </font>');
            }
              
            //status ... windows updates outstanding (not yet installed)?
            if (data[computername].PendingWU > 0) {
            $('#' + computername + 'status').append('<font size="1" color="Red">WU:' +
                data[computername].PendingWU + '</font>');
            } else {
            $('#' + computername + 'status').append('<font size="1" color="LightGray">WU:' +
                data[computername].PendingWU + '</font>');
            }
              
            //status ... uptime/downtime
            if ("DownSince" in data[computername]) {
            event = data[computername].DownSince;
            udstring ='<br/><font size="1" color="red">down ';
            $('#' + computername + 'cell').attr("style", "background-color: Black; color: Red");
            } else {
            event = data[computername].UpSince;
            udstring = '<br/><font size="1" color="green">up ';
            $('#' + computername + 'cell').attr("style", "background-color: Aquamarine; color: Black");
            }
            //status ... calc and display the time up or time down
            //show timespan in days, or if <1day, hours and minutes
            var compevent = moment(event); //time the computer went from up to down or vice versa
            var timespan = moment(now).diff(compevent, true);
            var dur = moment.duration(timespan); 
            if (moment(now).diff(compevent, "hours") > 24) {
            var formatteduptime = moment(now).diff(compevent, "days") + "d";
            } else {
            var formatteduptime = dur.get("hours") +"h:" + dur.get("minutes") + 'm';
            }
              
            $('#' + computername + 'status').append(udstring + formatteduptime + '</font>');
                
            //the cpu cell                
            var cpudata = data[computername].CpuQueue;            
            var cpuchart = $('<span>Loading</span>');
            cpuchart.sparkline(cpudata, { type: 'line', lineColor:'red', fillColor:"MistyRose", 
                height:"30", width:"100", chartRangeMin:"0", chartRangeMax:"15", 
                chartRangeClip: true });
            $('#' + computername + 'cpu').append(cpuchart);
              
            //the memory cell (page-ins per second)                
            var memdata = data[computername].MemQueue;            
            var memchart = $('<span>Loading</span>');
            memchart.sparkline(memdata, { type: 'line', lineColor:'blue', fillColor:"MistyRose", 
                height:"30", width:"100", chartRangeMin:"0", chartRangeMax:"100", 
                chartRangeClip: true } );
            $('#' + computername + 'mem').append(memchart);
              
            //the eventlog cell (errors found in system and application logs)                
            var eventdata = data[computername].ErrWarnEvents;            
            var eventchart = $('<span>Loading</span>');
            eventchart.sparkline(eventdata, { type: 'line', lineColor:'purple', 
                fillColor:"MistyRose", height:"30", width:"100", chartRangeMin:"0",
                chartRangeMax:"15", chartRangeClip: true } );
            $('#' + computername + 'events').append(eventchart);
              
            //the disks cell, iterate through the configured disks                
            // check to see if per-server disks are configured
            // !!var returns true if the variable is *not* null or undefined
            if ((computername in config) && ("disks" in config[computername])) {
                disks = config[computername].disks;
            } else {
                disks = config.defaults.disks
            }
            $.each(disks.split(','), function(arrayloc, disklabel) {
                //display the disk label
                $('#' + computername + 'disks').append(disklabel + ' ');
                //retreive the json array of diskfree values
                var diskfreevals = data[computername].DiskFree[disklabel];
                //only need the most recent diskfree value
                var diskfree = diskfreevals[diskfreevals.length - 1];
                //compute diskfree:diskused barchart values  
                if (!!diskfree) {                  
                var diskused = 100 - diskfree
                var dfarray = new Array(diskused, diskfree);
                //sparkline wants to see it as an array of arrays
                var dfchartval = new Array(dfarray);    
                var dfchart = $('<span>Loading</span>');
                //configure the sparkline barchart
                dfchart.sparkline(dfchartval, { type: 'bar', barWidth:10, 
                    stackedBarColor:["DarkRed", "SeaGreen"], zeroAxis:'false', width:10, 
                    height:"30", chartRangeMin:"0", chartRangeMax:"100"} );
                //append sparkline barchart to the table cell
                $('#' + computername + 'disks').append(dfchart);  
                $('#' + computername + 'disks').append(' ');
                }
                //the diskqueue chart
                var dqdata = data[computername].DiskQueue[disklabel];
                if (!!diskfree) {
                //$('#' + computername + 'disks').append(dqdata);
                var dqchart = $('<span>Loading</span>');
                dqchart.sparkline(dqdata, { type: 'line', lineColor:'orange', 
                    fillColor:"MistyRose", height:"30", width:"100", chartRangeMin:"0",
                    chartRangeMax:"10", chartRangeClip: true });
                $('#' + computername + 'disks').append(dqchart);
                $('#' + computername + 'disks').append(' ');
                }  
            }); //end of $.each(disks.split..
            $.sparkline_display_visible();              
              
          } // end of 'for (var i in targets)'
        });
        
        setTimeout(function(){window.location.reload();}, 30000)
      });         
    </script>
  </head>
  <body>
    
  </body>
</html>

'@
        $Output
    }

    End{}
}

function Resize-StorageHash {
<#
.Synopsis
Trim or inflate each arraylist element of the storagehash to contain exactly 144 sub-elements
.DESCRIPTION TBD
.PARAMETER TBD
.PARAMETER TBD
.EXAMPLE
   Example of how to use this cmdlet
#>

    [CmdletBinding()]

    Param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)][hashtable]$StorageHash
    )

    Begin{}
    Process {
        #recursively iterate the hashtables and arrays in the $Perfdata hashtable,
        #and trim arraylists to 144 elements max (maybe inflate them, with nulls, to 144 if under)
        function recurse ($object, $parent) {
            foreach ($key in $object.Keys) {
                if ($object.$key.GetType() -eq [System.Collections.ArrayList]) {
                    Write-Verbose "StorageHash$($parent).$($key) has $($object.$key.Count) elements"
                    if ($($object.$key.Count) -gt 144) {
                        while ($($object.$key.Count) -gt 144) {$object.$key.RemoveAt(0)}
                        Write-Verbose " ..trimmed to $($object.$key.Count) elements"
                    }
                    if ($($object.$key.Count) -lt 144) {
                        while ($($object.$key.Count) -lt 144) {$object.$key.Insert(0,"null")}
                        Write-Verbose " ..inflated to $($object.$key.Count) elements"
                    }
                }
                Recurse $object.$key "$($parent).$($Key)"
            }
        } 

        recurse $StorageHash
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
		Source		: https://github.com/lipkau/PsIni
                      http://gallery.technet.microsoft.com/scriptcenter/ea40c1ef-c856-434b-b8fb-ebd7a76e8d91
        Version		: 1.0.0 - 2010/03/12 - OL - Initial release
                      1.0.1 - 2014/12/11 - OL - Typo (Thx SLDR)
                                              Typo (Thx Dave Stiff)
                      1.0.2 - 2015/06/06 - OL - Improvment to switch (Thx Tallandtree)
                      1.0.3 - 2015/06/18 - OL - Migrate to semantic versioning (GitHub issue#4)
                      1.0.4 - 2015/06/18 - OL - Remove check for .ini extension (GitHub Issue#6)
                      1.1.0 - 2015/07/14 - CB - Improve round-tripping and be a bit more liberal (GitHub Pull #7)
                                           OL - Small Improvments and cleanup
                      1.1.1 - 2015/07/14 - CB - changed .outputs section to be OrderedDictionary
        #Requires -Version 2.0
    .Inputs
        System.String
    .Outputs
        System.Collections.Specialized.OrderedDictionary
    .Parameter FilePath
        Specifies the path to the input file.
    .Parameter CommentChar
        Specify what characters should be describe a comment.
        Lines starting with the characters provided will be rendered as comments.
        Default: ";"
    .Parameter IgnoreComments
        Remove lines determined to be comments from the resulting dictionary.
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
        [string]$FilePath,
        [char[]]$CommentChar = @(";"),
        [switch]$IgnoreComments
    )

    Begin
    {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Function started"
        $commentRegex = "^([$($CommentChar -join '')].*)$"
    }

    Process
    {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Processing file: $Filepath"

        $ini = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::OrdinalIgnoreCase)
        $commentCount = 0
        switch -regex -file $FilePath
        {
            "^\s*\[(.+)\]\s*$" # Section
            {
                $section = $matches[1]
                $ini[$section] = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::OrdinalIgnoreCase)
                $CommentCount = 0
                continue
            }
            $commentRegex # Comment
            {
                if (!$IgnoreComments)
                {
                    if (!(test-path "variable:section"))
                    {
                        $section = "_"
                        $ini[$section] = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::OrdinalIgnoreCase)
                    }
                    $value = $matches[1]
                    $CommentCount++
                    $name = "Comment" + $CommentCount
                    $ini[$section][$name] = $value
                }
                continue
            }
            "(.+?)\s*=\s*(.*)" # Key
            {
                if (!(test-path "variable:section"))
                {
                    $section = "_"
                    $ini[$section] = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::OrdinalIgnoreCase)
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
#requires -version 3
$config = Get-IniContent .\psperf.ini
$jsonconfig = "$($config.files.webdir)\config.json"
ConvertTo-Json -InputObject $config -Depth 10 | out-file $jsonconfig -Force
$webpage = "$($config.files.webdir)\$($config.files.pagename)"
$jsondata = "$($config.files.webdir)\psperf.json"

if (!$StorageHash) {
    if (get-item $config.files.datafile -ErrorAction ignore) {
        $StorageHash = Import-Clixml -Path $config.files.datafile
    } else {
        #So there's no current $StorageHash and no datafile to import. Create empty $storagehash; 
        #it will be written to datafile at end of script.
        $StorageHash = @{}
    }
}

Resize-StorageHash -StorageHash $StorageHash

#Get-IniContent renders comment lines as keys named Comment1, Comment2, etc. Ignore these!
foreach ($ComputerName in ($config.targets.keys | where-object {$_ -notLike "Comment*" } | sort) ) {
    if ($StorageHash.keys -notcontains $ComputerName) {New-ComputerRecord -ComputerName $ComputerName -StorageHash $StorageHash}
    #Look for an existing PSSession to $target; create if nonexistent; error if non-possible
    $Session = Get-PSSession | Where ComputerName -eq $ComputerName 
    #the session may exist in some broken state. remove if so.
    if ($Session -and ($session.Availability -ne "Available")) {Remove-PSSession $Session}
    #try to build session with implicit creds
    if (!$Session) {$Session = New-PSSession $ComputerName -ErrorAction Ignore}
    if (!$Session) {
        #Look for plaintext creds in PSPerf.ini (here represented as $config)
        if ($config.$ComputerName.username) {
            $username = $config.$ComputerName.username
        } else {
            $username = $config.defaults.username
        }

        if ($config.$ComputerName.securestring) {
            $securestring = $config.$ComputerName.securestring
        } else {
            $securestring  = $config.defaults.securestring
        }

        #if plaintext creds found, try building a PSSession with those
        if (($username -ne $null) -and ($securestring -ne $null)) {
            $securestring = $securestring | ConvertTo-SecureString
            $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $securestring
            $Session = New-PSSession -ComputerName "$ComputerName" -Credential $cred -ErrorAction Ignore   
        } 
    }

    if ($Session) {
        Write-Host "$ComputerName Get-Data: $(Measure-Command `
            {Get-Data -ComputerName $ComputerName -StorageHash $StorageHash})"
    } else {
        Write-Warning " No session for $ComputerName"
        $StorageHash.$ComputerName.Remove("UpSince")
        if (!$StorageHash.$ComputerName.DownSince) {            
            $storagehash.$ComputerName.Add("DownSince",(Get-Date))           
        }
    }
}

if ($StorageHash.keys -notcontains "PSPerf") {
    $StorageHash.Add("PSPerf", @{})
}
$StorageHash.PSPerf.Set_Item("LastDataWritten", ([DateTime]::Now))

write-host "write files: $(measure-command `
    {Export-Clixml -InputObject $StorageHash -Path $config.files.datafile -Force
    $htmlstring = Output-Page
    out-file -InputObject $htmlstring -FilePath $webpage -Encoding UTF8 -Force})"

    ConvertTo-Json -InputObject $StorageHash -Depth 10 | out-file $jsondata -Force
    

<# 
while loop for testing
$i=1; while ($i -lt 14400) {write-warning "iteration $i completed in $(measure-command {.\PSPerf.ps1})"; $i++}
#> 

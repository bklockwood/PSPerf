
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
function Get-PerfData #queries a single computer for performance data
{
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
        $perfdata = get-counter -ComputerName $computername -counter $perfcounters
        foreach ($item in $perfdata.CounterSamples) {
            if ($item.path -like "*Processor*") {$datahash.Add("CpuQueue",$item.cookedvalue)}
            if ($item.path -like "*Pages*") {$datahash.Add("PagesPerSec", $item.cookedvalue)}
            if ($item.path -like "*Physicaldisk*") {
                $dqhash.Add($item.InstanceName, $item.CookedValue)
            }
        }
        $datahash.Add("DiskQueues", $dqhash)
        $datahash
    }
    End{}
}

<#
.Synopsis
   Stores perf data (from get-perfdata) into a hashtable
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
function Add-Perfdata #Adds get-perfdata output into a hashtable of previously collected data
{
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

if (!$StorageHash) {$StorageHash = @{}}
$computername = 's1'
$pdata = Get-PerfData $computername
add-perfdata -StorageHash $StorageHash -Computername $computername -PerfData $pdata

<# 
Next steps:
 Store the table/object on disk with export-clixml
 Trim each array to latest 144 items
 Iterate storagehash ad created comma-separated text strings to write to page

#> 

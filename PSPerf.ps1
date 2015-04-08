Write-Host -ForegroundColor Red "CPU queue length"
(get-counter '\\bklsurface\system\processor queue length').CounterSamples 

Write-Host -ForegroundColor Red "Pages Input/sec"
(get-counter '\\bklsurface\memory\pages input/sec').CounterSamples 

Write-Host -ForegroundColor Red "Disk queue length"
(get-counter '\\bklsurface\PhysicalDisk(*)\Avg. Disk Queue Length').CounterSamples
 
Write-Host -ForegroundColor Red "NIC Outbound Queue length"
((get-counter -listset 'Network Interface').PathsWithInstances | select-string -SimpleMatch "Queue" | get-counter).CounterSamples

Write-Host -ForegroundColor Red "NIC Outbound Errors"
((get-counter -listset 'Network Interface').PathsWithInstances | select-string -SimpleMatch "Received Errors" | get-counter).CounterSamples

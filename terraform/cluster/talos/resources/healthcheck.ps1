# Number of nodes to check for readiness
param(
    [int]$NODE_COUNT = $env:NODE_COUNT -or (kubectl get nodes --no-headers 2>$null | Where-Object { $_.Trim() -ne "" } | Measure-Object | Select-Object -ExpandProperty Count),
    [int]$TIMEOUT = $env:TIMEOUT -or 300,  # Default timeout of 300 seconds
    [int]$INTERVAL = $env:INTERVAL -or 10  # Default check interval of 10 seconds
)

$start_time = Get-Date
$previous_ready_count = 0

Write-Host "Waiting for $NODE_COUNT nodes to be ready"

while ($true) {
    # Debug: Log the command being executed
    Write-Host "Executing: kubectl get nodes --no-headers"
    $ready_nodes = kubectl get nodes --no-headers 2>$null | Where-Object { $_ -match '\sReady\s' } | ForEach-Object { $_.Split(' ')[0] }
    
    # Debug: Log the raw output of the kubectl command
    Write-Host "Raw output of kubectl command: $ready_nodes"
    
    $ready_count = $ready_nodes.Count

    # Debug: Log the current ready count
    Write-Host "Current ready count: $ready_count"

    if ($ready_count -ne $previous_ready_count) {
        Write-Host "$ready_count / $NODE_COUNT nodes are ready"
        $previous_ready_count = $ready_count
    }

    if ($ready_count -eq $NODE_COUNT) {
        Write-Host "All nodes are ready"
        exit 0
    }

    $current_time = Get-Date
    $elapsed_time = ($current_time - $start_time).TotalSeconds

    # Debug: Log the elapsed time
    Write-Host "Elapsed time: $elapsed_time seconds"

    if ($elapsed_time -ge $TIMEOUT) {
        Write-Host "Timeout reached: Not all nodes are ready"
        exit 1
    }

    Start-Sleep -Seconds $INTERVAL
}

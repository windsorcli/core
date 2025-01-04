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
    $ready_nodes = kubectl get nodes --no-headers 2>$null | Where-Object { $_ -match '\sReady\s' } | ForEach-Object { $_.Split(' ')[0] }
    $ready_count = $ready_nodes.Count

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

    if ($elapsed_time -ge $TIMEOUT) {
        Write-Host "Timeout reached: Not all nodes are ready"
        exit 1
    }

    Start-Sleep -Seconds $INTERVAL
}

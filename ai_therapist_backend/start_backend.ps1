# PowerShell script to start the AI Therapist backend and display IP information
Write-Host "Starting AI Therapist Backend on port 8001..." -ForegroundColor Green

# Get all IPv4 addresses on this machine
$ipAddresses = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback" }

# Display IP addresses that could be used from a physical device
Write-Host "`nYour computer's network IP addresses:" -ForegroundColor Yellow
foreach ($ip in $ipAddresses) {
    if ($ip.IPAddress -notmatch "^(127\.|169\.254\.)") {
        Write-Host "- $($ip.IPAddress) (on $($ip.InterfaceAlias))" -ForegroundColor Cyan
    }
}

Write-Host "`nIMPORTANT: If testing on a physical device, update these settings:" -ForegroundColor Magenta
Write-Host "1. In 'ai_therapist_app/lib/config/api.dart', replace '192.168.1.X' with your actual IP address" -ForegroundColor White
Write-Host "2. Ensure your phone is connected to the same WiFi network as your computer" -ForegroundColor White
Write-Host "3. Make sure your firewall allows connections to port 8001" -ForegroundColor White

Write-Host "`nStarting backend server on port 8001..." -ForegroundColor Green
Write-Host "Press CTRL+C to stop the server`n" -ForegroundColor Yellow

# Start the backend server on port 8001 and allow connections from any IP
python -m uvicorn app.main:app --host 0.0.0.0 --port 8001 
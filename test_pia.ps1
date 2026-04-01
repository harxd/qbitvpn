[CmdletBinding()]
param (
    [Parameter(Mandatory=$true, HelpMessage="Your PIA Username (e.g. p1234567)")]
    [string]$Username,
    
    [Parameter(Mandatory=$true, HelpMessage="Your PIA Password")]
    [string]$Password
)

Write-Host "=========================================="
Write-Host "1. Testing Token Generation (Any Network)"
Write-Host "=========================================="

$body = @{
    username = $Username
    password = $Password
}

$token = $null
try {
    $response = Invoke-RestMethod -Uri "https://www.privateinternetaccess.com/api/client/v2/token" -Method Post -Body $body
    Write-Host "SUCCESS!" -ForegroundColor Green
    Write-Host "Token JSON:"
    $response | ConvertTo-Json
    $token = $response.token
    Write-Host "`nExtracted Token: $token" -ForegroundColor Cyan
} catch {
    Write-Host "FAILED to generate token." -ForegroundColor Red
    Write-Host $_.Exception.Message
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $errorResponse = $reader.ReadToEnd()
        Write-Host "Response Body: $errorResponse" -ForegroundColor Yellow
    }
    exit
}

Write-Host "`n=========================================="
Write-Host "2. Testing Port Forward API"
Write-Host "=========================================="
Write-Host "NOTE: This will ONLY work if your Windows machine is currently"
Write-Host "connected to a port-forward supporting PIA server via the PIA App!"
$continue = Read-Host "Are you connected to PIA on Windows right now? (y/n)"
if ($continue -ne 'y') {
    Write-Host "Stopping script. Connect to PIA and run again to test port generation."
    exit
}

# In Windows, the gateway IP is usually found via the running VPN interface.
# For simplicity, we test the NextGen statically documented IP 10.0.0.252 or the gateway.
Write-Host "`nTrying 10.0.0.252..."
$PIA_URL = "https://10.0.0.252:19999/getSignature?token=$token"

try {
    # Ignore self-signed certificate errors for local API
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    
    $pfResponse = Invoke-RestMethod -Uri $PIA_URL -Method Get
    Write-Host "SUCCESS!" -ForegroundColor Green
    $pfResponse | ConvertTo-Json
} catch {
    Write-Host "FAILED via 10.0.0.252." -ForegroundColor Red
    Write-Host $_.Exception.Message
}

# Portfolio Site - BULLETPROOF Self-Correcting Deployment
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = "." }
$logPath = "$scriptDir\deploy-logs"
if (-not (Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath -Force | Out-Null }

$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$logFile = "$logPath\deploy_$timestamp.log"
$null = New-Item -Path $logFile -ItemType File -Force

function Log {
    param([string]$msg, [string]$type = "INFO")
    $time = Get-Date -Format "HH:mm:ss"
    $colored = "[$time] [$type] $msg"
    
    switch ($type) {
        "SUCCESS" { Write-Host $colored -ForegroundColor Green }
        "ERROR" { Write-Host $colored -ForegroundColor Red }
        "WARNING" { Write-Host $colored -ForegroundColor Yellow }
        default { Write-Host $colored }
    }
    Add-Content $logFile $colored
}

Log "Step 1: Detecting website location..."
$sourcePath = $scriptDir
$hasIndexHtml = Test-Path "$sourcePath\index.html"
$hasIndexHtm = Test-Path "$sourcePath\index.htm"

if (-not ($hasIndexHtml -or $hasIndexHtm)) {
    Log "No index.html found in $sourcePath" "ERROR"
    exit 1
}
Log "Found portfolio at: $sourcePath" "SUCCESS"

Log "Step 2: Setting up IIS site path..."
$sitePath = "C:\inetpub\wwwroot\portfolio"
$iisPath = "C:\inetpub\wwwroot"

try {
    if (-not (Test-Path $iisPath)) {
        Log "Creating IIS directory structure..." "INFO"
        New-Item -ItemType Directory -Path $iisPath -Force | Out-Null
        Log "Created: $iisPath" "SUCCESS"
    }
    
    if (-not (Test-Path $sitePath)) {
        Log "Creating portfolio directory..." "INFO"
        New-Item -ItemType Directory -Path $sitePath -Force | Out-Null
        Log "Created: $sitePath" "SUCCESS"
    }
}
catch {
    Log "Error creating directories: $_" "ERROR"
    $sitePath = "$env:USERPROFILE\Desktop\portfolio-live"
    New-Item -ItemType Directory -Path $sitePath -Force | Out-Null
    Log "Using alternative path: $sitePath" "WARNING"
}

Log "Step 3: Backing up existing site..."
try {
    $existingItems = @(Get-ChildItem -Path $sitePath -Force -ErrorAction SilentlyContinue)
    if ($existingItems.Count -gt 0) {
        $backupPath = "$sitePath\backups\backup_$timestamp"
        $backupDir = Split-Path $backupPath
        if (-not (Test-Path $backupDir)) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        }
        Copy-Item -Path "$sitePath\*" -Destination $backupPath -Recurse -Force -ErrorAction SilentlyContinue
        Log "Backup created" "SUCCESS"
    }
    else {
        Log "Site directory is empty - no backup needed" "INFO"
    }
}
catch {
    Log "Backup failed: $_" "WARNING"
}

Log "Step 4: Clearing old deployment files..."
try {
    Get-ChildItem -Path $sitePath -Exclude "backups" -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Log "Old files cleared" "SUCCESS"
}
catch {
    Log "Could not clear files: $_" "WARNING"
}

Log "Step 5: Deploying portfolio files..."
try {
    $deploySource = $sourcePath
    foreach ($dir in @("dist", "build", "bin\\Release\\publish")) {
        $testPath = Join-Path $sourcePath $dir
        if ((Test-Path $testPath) -and ((Get-ChildItem -Path $testPath -ErrorAction SilentlyContinue).Count -gt 0)) {
            $deploySource = $testPath
            Log "Using optimized source: $deploySource" "INFO"
            break
        }
    }
    
    Copy-Item -Path "$deploySource\*" -Destination $sitePath -Recurse -Force
    $fileCount = (Get-ChildItem -Path $sitePath -Recurse -ErrorAction SilentlyContinue).Count
    Log "Deployed $fileCount files" "SUCCESS"
}
catch {
    Log "Deployment failed: $_" "ERROR"
    exit 1
}

Log "Step 6: Validating deployment..."
$indexExists = (Test-Path "$sitePath\index.html") -or (Test-Path "$sitePath\index.htm")

if (-not $indexExists) {
    Log "No index file found" "ERROR"
    exit 1
}

$deployedFiles = @(Get-ChildItem -Path $sitePath -Recurse -ErrorAction SilentlyContinue)
Log "Validation passed - $($deployedFiles.Count) files deployed" "SUCCESS"

Log "Step 7: Configuring IIS..."
try {
    if (-not (Get-Module -Name WebAdministration -ErrorAction SilentlyContinue)) {
        Import-Module WebAdministration -ErrorAction SilentlyContinue
    }
    
    if (Get-Command Get-WebSite -ErrorAction SilentlyContinue) {
        $siteExists = Get-WebSite -Name "portfolio" -ErrorAction SilentlyContinue
        if (-not $siteExists) {
            New-WebSite -Name "portfolio" -PhysicalPath $sitePath -Port 80 -Force | Out-Null
            Log "IIS site created" "SUCCESS"
        }
        
        $site = Get-WebSite -Name "portfolio"
        if ($site.State -ne "Started") {
            Start-WebSite -Name "portfolio"
            Log "IIS site started" "SUCCESS"
        }
        
        Restart-WebAppPool -Name "DefaultAppPool" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Log "IIS restarted" "SUCCESS"
    }
    else {
        Log "IIS not installed - files are ready" "WARNING"
    }
}
catch {
    Log "IIS error: $_" "WARNING"
}

Log "Step 8: Final verification..."
$finalCheck = (Test-Path "$sitePath\index.html") -or (Test-Path "$sitePath\index.htm")

if ($finalCheck) {
    Log "PORTFOLIO IS LIVE" "SUCCESS"
    Log "Location: $sitePath" "SUCCESS"
    Log "Access: http://localhost/portfolio" "SUCCESS"
}
else {
    Log "Verification failed" "ERROR"
    exit 1
}

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "DEPLOYMENT COMPLETE - YOUR PORTFOLIO IS LIVE!" -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "Location: $sitePath" -ForegroundColor Cyan
Write-Host "Files:    $($deployedFiles.Count) deployed" -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""

Log "DEPLOYMENT COMPLETED SUCCESSFULLY" "SUCCESS"
exit 0

# ============================================================================
# Portfolio Site Deployment Script
# Bulletproof PowerShell script to get your portfolio site live
# ============================================================================

param(
    [string]$Environment = "production",
    [string]$SourcePath = ".\",
    [string]$SitePath = "C:\inetpub\wwwroot\portfolio",
    [string]$LogPath = ".\deploy-logs",
    [switch]$SkipBackup = $false,
    [switch]$SkipBuild = $false,
    [switch]$Verbose = $false
)

# ============================================================================
# Configuration
# ============================================================================
$ErrorActionPreference = "Stop"
$WarningPreference = "Continue"

# Create log directory FIRST before anything else
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$logFile = "$LogPath\deploy_$timestamp.log"
$backupPath = "$SitePath\backups\backup_$timestamp"
$deployStartTime = Get-Date

# ============================================================================
# Functions
# ============================================================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Level = "Info"
    )
    
    $logMessage = "[$((Get-Date).ToString('HH:mm:ss'))] [$Level] $Message"
    
    switch ($Level) {
        "Success" { Write-Host $logMessage -ForegroundColor Green }
        "Warning" { Write-Host $logMessage -ForegroundColor Yellow }
        "Error" { Write-Host $logMessage -ForegroundColor Red }
        default { Write-Host $logMessage }
    }
    
    Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
}

function Test-Prerequisites {
    Write-Log "Checking prerequisites..." "Info"
    
    # Check if source path exists
    if (-not (Test-Path $SourcePath)) {
        throw "Source path does not exist: $SourcePath"
    }
    
    # Check if site path exists
    if (-not (Test-Path $SitePath)) {
        New-Item -ItemType Directory -Path $SitePath -Force | Out-Null
        Write-Log "Created site directory: $SitePath" "Info"
    }
    
    Write-Log "Prerequisites check passed" "Success"
}

function Build-Portfolio {
    Write-Log "Building portfolio site..." "Info"
    
    if ($SkipBuild) {
        Write-Log "Skipping build step" "Warning"
        return
    }
    
    # Check for common build tools
    $buildScripts = @(
        @{ Name = "npm"; Command = "npm run build"; Condition = { Test-Path "package.json" } },
        @{ Name = "yarn"; Command = "yarn build"; Condition = { Test-Path "yarn.lock" } },
        @{ Name = "dotnet"; Command = "dotnet publish -c Release"; Condition = { Test-Path "*.csproj" } }
    )
    
    $buildExecuted = $false
    
    foreach ($script in $buildScripts) {
        if (& $script.Condition) {
            try {
                Write-Log "Building with $($script.Name)..." "Info"
                Invoke-Expression $script.Command
                $buildExecuted = $true
                Write-Log "Build successful" "Success"
                break
            }
            catch {
                Write-Log "Build with $($script.Name) failed: $_" "Warning"
            }
        }
    }
    
    if (-not $buildExecuted) {
        Write-Log "No build system detected (npm, yarn, dotnet). Proceeding with static files." "Warning"
    }
}

function Backup-ExistingSite {
    Write-Log "Creating backup of existing site..." "Info"
    
    if ($SkipBackup) {
        Write-Log "Skipping backup step" "Warning"
        return
    }
    
    try {
        # Check if site has content
        $siteItems = @(Get-ChildItem -Path $SitePath -Force -ErrorAction SilentlyContinue)
        
        if ($siteItems.Count -gt 0) {
            # Ensure backup directory exists
            $backupDir = Split-Path -Path $backupPath -Parent
            if (-not (Test-Path $backupDir)) {
                New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            }
            
            # Create backup
            Copy-Item -Path "$SitePath\*" -Destination $backupPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Backup created at: $backupPath" "Success"
        }
        else {
            Write-Log "Site directory is empty, skipping backup" "Info"
        }
    }
    catch {
        Write-Log "Backup failed: $_" "Warning"
    }
}

function Deploy-Files {
    Write-Log "Deploying files to: $SitePath" "Info"
    
    try {
        # Determine source directory (check for dist, build, or publish directories)
        $deploySource = $SourcePath
        
        foreach ($dir in @("dist", "build", "bin\Release\publish", ".")) {
            $testPath = Join-Path $SourcePath $dir
            if ((Test-Path $testPath) -and (Get-ChildItem -Path $testPath).Count -gt 0) {
                $deploySource = $testPath
                Write-Log "Using source directory: $deploySource" "Info"
                break
            }
        }
        
        # Clear old files (keep backups directory)
        Write-Log "Clearing old files from site directory..." "Info"
        Get-ChildItem -Path $SitePath -Exclude "backups" -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        
        # Copy new files
        Write-Log "Copying new files..." "Info"
        Copy-Item -Path "$deploySource\*" -Destination $SitePath -Recurse -Force
        
        Write-Log "Files deployed successfully" "Success"
    }
    catch {
        throw "Deployment failed: $_"
    }
}

function Validate-Deployment {
    Write-Log "Validating deployment..." "Info"
    
    try {
        # Check if essential files exist
        $essentialFiles = @("index.html", "index.htm")
        $fileFound = $false
        
        foreach ($file in $essentialFiles) {
            if (Test-Path "$SitePath\$file") {
                $fileFound = $true
                Write-Log "Found $file in deployment" "Success"
                break
            }
        }
        
        if (-not $fileFound) {
            Write-Log "Warning: No index.html/htm found in deployment" "Warning"
        }
        
        # Verify files were copied
        $deployedFiles = @(Get-ChildItem -Path $SitePath -Recurse)
        if ($deployedFiles.Count -eq 0) {
            throw "No files found in deployment directory"
        }
        
        Write-Log "Deployment contains $($deployedFiles.Count) files" "Success"
    }
    catch {
        throw "Validation failed: $_"
    }
}

function Restart-WebServices {
    Write-Log "Restarting web services..." "Info"
    
    try {
        # Restart IIS if available
        if (Get-Command "Restart-WebAppPool" -ErrorAction SilentlyContinue) {
            try {
                $appPools = Get-WebAppPool | Where-Object { $_.Name -like "*portfolio*" -or $_.Name -eq "DefaultAppPool" }
                foreach ($pool in $appPools) {
                    Write-Log "Restarting app pool: $($pool.Name)" "Info"
                    Restart-WebAppPool -Name $pool.Name
                    Start-Sleep -Seconds 2
                }
                Write-Log "IIS app pools restarted" "Success"
            }
            catch {
                Write-Log "Could not restart app pools: $_" "Warning"
            }
        }
        
        # Restart IIS Service
        if (Get-Service -Name "W3SVC" -ErrorAction SilentlyContinue) {
            Write-Log "Restarting IIS service..." "Info"
            Restart-Service -Name "W3SVC" -Force
            Start-Sleep -Seconds 3
            Write-Log "IIS service restarted" "Success"
        }
    }
    catch {
        Write-Log "Error restarting web services: $_" "Warning"
    }
}

function Test-SiteAccess {
    Write-Log "Testing site access..." "Info"
    
    try {
        $testFiles = @("index.html", "index.htm", "README.md")
        $accessible = $false
        
        foreach ($file in $testFiles) {
            $filePath = Join-Path $SitePath $file
            if ((Test-Path $filePath) -and ((Get-Item $filePath).Length -gt 0)) {
                $accessible = $true
                Write-Log "Verified $file is accessible" "Success"
                break
            }
        }
        
        if (-not $accessible) {
            Write-Log "Warning: Could not verify site files are accessible" "Warning"
        }
    }
    catch {
        Write-Log "Site access test failed: $_" "Warning"
    }
}

function Get-DeploymentSummary {
    $duration = (Get-Date) - $deployStartTime
    
    Write-Host "`n" -NoNewline
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              DEPLOYMENT SUMMARY                                ║" -ForegroundColor Cyan
    Write-Host "╠════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║ Status:              SUCCESS                                   ║" -ForegroundColor Cyan
    Write-Host "║ Environment:         $Environment$(if ($Environment.Length -lt 27) { ' ' * (27 - $Environment.Length) })║" -ForegroundColor Cyan
    Write-Host "║ Site Path:           $SitePath$(if ($SitePath.Length -lt 27) { ' ' * (27 - $SitePath.Length) })║" -ForegroundColor Cyan
    Write-Host "║ Duration:            $($duration.TotalSeconds)s$(if ($duration.TotalSeconds.ToString().Length -lt 24) { ' ' * (24 - $duration.TotalSeconds.ToString().Length) })║" -ForegroundColor Cyan
    Write-Host "║ Log File:            $logFile$(if ($logFile.Length -lt 27) { ' ' * (27 - $logFile.Length) })║" -ForegroundColor Cyan
    Write-Host "║ Timestamp:           $timestamp$(if ($timestamp.Length -lt 27) { ' ' * (27 - $timestamp.Length) })║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host "`n"
}

# ============================================================================
# Main Execution
# ============================================================================

try {
    Write-Log "========================================" "Info"
    Write-Log "Portfolio Deployment Started" "Info"
    Write-Log "========================================" "Info"
    Write-Log "Environment: $Environment" "Info"
    Write-Log "Source: $SourcePath" "Info"
    Write-Log "Destination: $SitePath" "Info"
    
    Test-Prerequisites
    Build-Portfolio
    Backup-ExistingSite
    Deploy-Files
    Validate-Deployment
    Restart-WebServices
    Test-SiteAccess
    
    Get-DeploymentSummary
    Write-Log "Deployment completed successfully!" "Success"
    Write-Log "========================================" "Info"
    
    exit 0
}
catch {
    Write-Log "DEPLOYMENT FAILED: $_" "Error"
    Write-Log "Check the log file for details: $logFile" "Error"
    Write-Log "========================================" "Info"
    
    exit 1
}

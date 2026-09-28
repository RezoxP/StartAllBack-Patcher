<#
.SYNOPSIS
    StartAllBack Patcher & License Bypass Utility

.DESCRIPTION
    High-performance PowerShell script to patch StartAllBack DLL files directly in memory
    without converting binary streams to hex strings.

.PARAMETER Restore
    Restores the original DLL from the .bak backup file.

.PARAMETER Status
    Displays the patch status of all detected StartAllBack DLLs without making changes.

.PARAMETER Force
    Forces patch or restore operation even if warnings are raised.

.PARAMETER NoRestart
    Prevents restarting Windows Explorer automatically after completion.

.EXAMPLE
    .\new.ps1
    Applies the patch to installed StartAllBack DLLs.

.EXAMPLE
    .\new.ps1 -Restore
    Restores original DLLs from backup.

.EXAMPLE
    .\new.ps1 -Status
    Checks and displays patch status.
#>

[CmdletBinding()]
param(
    [switch]$Restore,
    [switch]$Status,
    [switch]$Force,
    [switch]$NoRestart
)

# -------------------------------------------------------------------
# Elevation Check & Self-Elevation
# -------------------------------------------------------------------
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $Status -and -not (Test-IsAdmin)) {
    $scriptPath = $MyInvocation.MyCommand.Path
    
    if (-not $scriptPath) {
        Write-Warning "Running without administrator rights. If modification fails, please run PowerShell as Administrator."
    } else {
        Write-Host "[!] Admin privileges required. Requesting elevation..." -ForegroundColor Yellow
        try {
            $argList = "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`""
            if ($Restore)   { $argList += " -Restore" }
            if ($Force)     { $argList += " -Force" }
            if ($NoRestart) { $argList += " -NoRestart" }

            $proc = Start-Process powershell.exe -ArgumentList $argList -Verb RunAs -PassThru -ErrorAction Stop
            $proc.WaitForExit()
            $global:LASTEXITCODE = $proc.ExitCode
            return
        } catch {
            Write-Warning "Could not automatically elevate process ($($_.Exception.Message)). Attempting to proceed..."
        }
    }
}

# -------------------------------------------------------------------
# Configuration & Byte Signatures
# -------------------------------------------------------------------
$TargetDllNames = @("StartAllBackX64.dll", "StartAllBack32.dll", "StartAllBackARM64.dll", "StartIsBack64.dll", "StartIsBack32.dll")

# Pattern definitions (Original vs Patched)
$Patterns = @(
    @{
        Name     = "StartAllBack v3.x Standard Pattern"
        Original = [byte[]]@(0x48,0x89,0x5C,0x24,0x08,0x55,0x56,0x57,0x48,0x8D,0xAC,0x24,0x70,0xFF,0xFF,0xFF)
        Patched  = [byte[]]@(0x67,0xC7,0x01,0x01,0x00,0x00,0x00,0xB8,0x01,0x00,0x00,0x00,0xC3,0x90,0x90,0x90)
    }
)

# -------------------------------------------------------------------
# Helper Functions
# -------------------------------------------------------------------
function Write-Header {
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "         StartAllBack High-Performance Patcher            " -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Find-Bytes {
    param(
        [byte[]]$Haystack,
        [byte[]]$Needle
    )
    if (-not $Haystack -or -not $Needle -or $Haystack.Length -lt $Needle.Length) { return -1 }
    
    $maxIndex = $Haystack.Length - $Needle.Length
    for ($i = 0; $i -le $maxIndex; $i++) {
        $match = $true
        for ($j = 0; $j -lt $Needle.Length; $j++) {
            if ($Haystack[$i + $j] -ne $Needle[$j]) {
                $match = $false
                break
            }
        }
        if ($match) { return $i }
    }
    return -1
}

function Get-InstalledDllPaths {
    $candidatePaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # 1. Registry Lookups (Uninstall Keys & App Keys)
    $regKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\StartAllBack",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\StartAllBack",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\StartAllBack",
        "HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\StartAllBack",
        "HKCU:\SOFTWARE\StartAllBack"
    )

    foreach ($key in $regKeys) {
        if (Test-Path $key) {
            $installDir = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).InstallLocation
            if ($installDir -and (Test-Path $installDir)) {
                foreach ($dllName in $TargetDllNames) {
                    $fullPath = Join-Path $installDir $dllName
                    if (Test-Path $fullPath) { $null = $candidatePaths.Add($fullPath) }
                }
            }
        }
    }

    # 2. Common Directory Locations (safely checking non-empty base paths)
    $searchParents = @(
        $env:LOCALAPPDATA,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        "$env:SystemDrive\Program Files",
        "$env:SystemDrive\Program Files (x86)"
    )

    foreach ($parent in $searchParents) {
        if ($parent -and (Test-Path $parent)) {
            $targetDir = Join-Path $parent "StartAllBack"
            if (Test-Path $targetDir) {
                foreach ($dllName in $TargetDllNames) {
                    $fullPath = Join-Path $targetDir $dllName
                    if (Test-Path $fullPath) { $null = $candidatePaths.Add($fullPath) }
                }
            }
        }
    }

    # 3. Script Root Locations (only if running from a script file on disk)
    if ($PSScriptRoot -and (Test-Path $PSScriptRoot)) {
        foreach ($dllName in $TargetDllNames) {
            $directPath = Join-Path $PSScriptRoot $dllName
            if (Test-Path $directPath) { $null = $candidatePaths.Add($directPath) }

            $subDir = Join-Path $PSScriptRoot "StartAllBack"
            if (Test-Path $subDir) {
                $subPath = Join-Path $subDir $dllName
                if (Test-Path $subPath) { $null = $candidatePaths.Add($subPath) }
            }
        }
    }

    return @($candidatePaths)
}

function Set-AutoRestartShell {
    param([int]$Value)
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
        Set-ItemProperty -Path $regPath -Name "AutoRestartShell" -Value $Value -Type DWord -Force -ErrorAction SilentlyContinue
    } catch {
        # Best effort
    }
}

function Stop-ExplorerAndApps {
    Write-Host "[*] Stopping Explorer and StartAllBack background processes..." -ForegroundColor Cyan
    Set-AutoRestartShell -Value 0

    $processNames = @("StartAllBackCfg", "explorer", "ShellHost", "StartMenuExperienceHost")
    foreach ($procName in $processNames) {
        $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($procs) {
            foreach ($p in $procs) {
                try {
                    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                } catch {}
            }
        }
    }

    # Wait briefly for processes to release handles
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 5) {
        $running = Get-Process -Name "explorer", "StartAllBackCfg" -ErrorAction SilentlyContinue
        if (-not $running) { break }
        Start-Sleep -Milliseconds 200
    }
}

function Start-ExplorerAndApps {
    param([string]$DllPath)
    
    Set-AutoRestartShell -Value 1

    if (-not $NoRestart) {
        Write-Host "[*] Restarting Windows Explorer..." -ForegroundColor Cyan
        try {
            Start-Process -FilePath "explorer.exe" -ErrorAction SilentlyContinue
            Write-Host "[+] Explorer restarted successfully." -ForegroundColor Green
        } catch {
            Write-Warning "Failed to launch explorer.exe automatically. Please launch it from Task Manager."
        }

        if ($DllPath) {
            $cfgExe = Join-Path (Split-Path $DllPath -Parent) "StartAllBackCfg.exe"
            if (Test-Path $cfgExe) {
                try { Start-Process -FilePath $cfgExe -ErrorAction SilentlyContinue } catch {}
            }
        }
    }
}

function Get-DllStatus {
    param([string]$DllPath)

    if (-not (Test-Path $DllPath)) {
        return @{ Status = "Missing"; MatchPattern = $null; Offset = -1 }
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($DllPath)
    } catch {
        return @{ Status = "Unreadable"; MatchPattern = $null; Offset = -1 }
    }

    foreach ($pat in $Patterns) {
        $patchedIndex = Find-Bytes $bytes $pat.Patched
        if ($patchedIndex -ge 0) {
            return @{ Status = "Patched"; MatchPattern = $pat; Offset = $patchedIndex }
        }

        $originalIndex = Find-Bytes $bytes $pat.Original
        if ($originalIndex -ge 0) {
            return @{ Status = "Original"; MatchPattern = $pat; Offset = $originalIndex }
        }
    }

    return @{ Status = "Unknown"; MatchPattern = $null; Offset = -1 }
}

function Patch-TargetDll {
    param([string]$DllPath)

    $statusInfo = Get-DllStatus -DllPath $DllPath
    $backupPath = "$DllPath.bak"

    if ($statusInfo.Status -eq "Patched") {
        Write-Host "[=] DLL is already patched: $DllPath" -ForegroundColor Green
        return $true
    }

    if ($statusInfo.Status -ne "Original" -and -not $Force) {
        Write-Error "Unsupported DLL version or unknown pattern in: $DllPath. Use -Force to override if necessary."
        return $false
    }

    $pat = $statusInfo.MatchPattern
    if (-not $pat) { $pat = $Patterns[0] }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($DllPath)
        $offset = $statusInfo.Offset
        if ($offset -lt 0) { $offset = Find-Bytes $bytes $pat.Original }

        if ($offset -lt 0 -and -not $Force) {
            Write-Error "Original byte pattern not found in: $DllPath"
            return $false
        }

        # Backup creation
        if (-not (Test-Path $backupPath)) {
            Write-Host "[*] Creating original backup: $backupPath" -ForegroundColor Cyan
            [System.IO.File]::Copy($DllPath, $backupPath, $true)
        } else {
            Write-Host "[*] Backup file already present: $backupPath" -ForegroundColor Gray
        }

        # Safe File Replacement (handles locked DLL unlinking)
        $tempPatched = "$DllPath.tmp"
        
        # Apply patch in memory
        [array]::Copy($pat.Patched, 0, $bytes, $offset, $pat.Patched.Length)
        [System.IO.File]::WriteAllBytes($tempPatched, $bytes)

        # Move original out of the way (unlinks loaded DLL) and replace
        $tempOld = "$DllPath.old_$([DateTime]::Now.Ticks)"
        [System.IO.File]::Move($DllPath, $tempOld)
        [System.IO.File]::Move($tempPatched, $DllPath)

        # Clean up temporary old file
        try { Remove-Item $tempOld -Force -ErrorAction SilentlyContinue } catch {}

        Write-Host "[+] Successfully patched DLL: $DllPath" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Failed to patch $($DllPath): $_"
        return $false
    }
}

function Restore-TargetDll {
    param([string]$DllPath)

    $backupPath = "$DllPath.bak"
    if (-not (Test-Path $backupPath)) {
        Write-Error "No backup file found at: $backupPath. Cannot restore."
        return $false
    }

    try {
        Write-Host "[*] Restoring original DLL from backup..." -ForegroundColor Cyan
        
        $tempOld = "$DllPath.patched_old_$([DateTime]::Now.Ticks)"
        if (Test-Path $DllPath) {
            [System.IO.File]::Move($DllPath, $tempOld)
        }
        
        [System.IO.File]::Copy($backupPath, $DllPath, $true)
        
        if (Test-Path $tempOld) {
            try { Remove-Item $tempOld -Force -ErrorAction SilentlyContinue } catch {}
        }

        Write-Host "[+] Successfully restored original DLL: $DllPath" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Failed to restore $($DllPath): $_"
        return $false
    }
}

# -------------------------------------------------------------------
# Execution Entry Point
# -------------------------------------------------------------------
Write-Header

$targetDlls = Get-InstalledDllPaths

if (-not $targetDlls -or $targetDlls.Count -eq 0) {
    Write-Error "No StartAllBack installation DLLs were found on this system."
    $global:LASTEXITCODE = 1
    return
}

Write-Host "[*] Discovered StartAllBack DLL(s):" -ForegroundColor White
foreach ($dll in $targetDlls) {
    $info = Get-DllStatus -DllPath $dll
    $bakState = if (Test-Path "$dll.bak") { "Backup Present" } else { "No Backup" }
    Write-Host "    -> $dll [$($info.Status)] ($bakState)" -ForegroundColor Yellow
}
Write-Host ""

if ($Status) {
    Write-Host "[*] Status check complete. No changes made." -ForegroundColor Cyan
    $global:LASTEXITCODE = 0
    return
}

# Stop processes before modifying files
Stop-ExplorerAndApps

$overallSuccess = $true
$primaryDll = $targetDlls[0]

foreach ($dll in $targetDlls) {
    if ($Restore) {
        $res = Restore-TargetDll -DllPath $dll
        if (-not $res) { $overallSuccess = $false }
    } else {
        $res = Patch-TargetDll -DllPath $dll
        if (-not $res) { $overallSuccess = $false }
    }
}

# Restart Explorer and background apps
Start-ExplorerAndApps -DllPath $primaryDll

if ($overallSuccess) {
    $actionName = if ($Restore) { "Restoration" } else { "Patching" }
    Write-Host ""
    Write-Host "[+] $actionName completed successfully!" -ForegroundColor Green
    $global:LASTEXITCODE = 0
    return
} else {
    Write-Host ""
    Write-Error "One or more operations encountered errors."
    $global:LASTEXITCODE = 1
    return
}
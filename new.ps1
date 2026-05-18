#Requires -RunAsAdministrator

param([switch]$Restore)

$appTargetDll = "StartAllBackX64.dll"
$appTargetExe = "StartAllBackCfg.exe"

# Byte patterns
$oldBytes = [byte[]]@(0x48,0x89,0x5C,0x24,0x08,0x55,0x56,0x57,
                      0x48,0x8D,0xAC,0x24,0x70,0xFF,0xFF,0xFF)
$newBytes = [byte[]]@(0x67,0xC7,0x01,0x01,0x00,0x00,0x00,0xB8,
                      0x01,0x00,0x00,0x00,0xC3,0x90,0x90,0x90)

function Find-Bytes {
    param([byte[]]$Haystack, [byte[]]$Needle)
    for ($i = 0; $i -le $Haystack.Length - $Needle.Length; $i++) {
        $match = $true
        for ($j = 0; $j -lt $Needle.Length; $j++) {
            if ($Haystack[$i+$j] -ne $Needle[$j]) { $match = $false; break }
        }
        if ($match) { return $i }
    }
    return -1
}

function Find-Dll {
    param([string]$DllName)
    @(
        Join-Path $env:LOCALAPPDATA         "StartAllBack\$DllName"
        Join-Path $env:ProgramFiles         "StartAllBack\$DllName"
        Join-Path ${env:ProgramFiles(x86)} "StartAllBack\$DllName"
        Join-Path $PSScriptRoot             "StartAllBack\$DllName"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Remove-FileOnReboot {
    param([string]$Path)
    $def = @"
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, uint dwFlags);
"@
    $k32 = Add-Type -MemberDefinition $def -Name "Kernel32" -Namespace "Win32" -PassThru
    $MOVEFILE_DELAY_UNTIL_REBOOT = 0x4
    $null = $k32::MoveFileEx($Path, $null, $MOVEFILE_DELAY_UNTIL_REBOOT)
}

function Patch-Dll {
    param([string]$DllPath)

    $backupPath = "$DllPath.bak"

    try {
        $data = [System.IO.File]::ReadAllBytes($DllPath)
    }
    catch {
        Write-Error "Cannot read DLL: $_"
        return $false
    }

    $index = Find-Bytes $data $oldBytes
    if ($index -lt 0) {
        Write-Error "Original byte pattern not found in DLL. The file may already be patched or the version is unsupported."
        return $false
    }

    # Handle existing backup
    if (Test-Path $backupPath) {
        try {
            Remove-Item $backupPath -Force -ErrorAction Stop
            Write-Host "Removed old backup file." -ForegroundColor Cyan
        }
        catch {
            Write-Warning "Could not remove old backup. Moving it to .bak.old (will be cleaned on reboot)."
            $oldBackup = "$backupPath.old"
            [System.IO.File]::Move($backupPath, $oldBackup)
            Remove-FileOnReboot $oldBackup
        }
    }

    Write-Host "Backing up original DLL..." -ForegroundColor Cyan
    # Rename locked original -> backup
    [System.IO.File]::Move($DllPath, $backupPath)

    Write-Host "Creating fresh copy of DLL..." -ForegroundColor Cyan
    # Copy backup -> original (fresh, unlocked file)
    [System.IO.File]::Copy($backupPath, $DllPath, $true)

    Write-Host "Patching DLL..." -ForegroundColor Cyan
    # Patch the new unlocked file
    [array]::Copy($newBytes, 0, $data, $index, $newBytes.Length)
    [System.IO.File]::WriteAllBytes($DllPath, $data)

    Write-Host "Patch applied successfully!" -ForegroundColor Green
    return $true
}

function Restore-Dll {
    param([string]$DllPath)
    $backupPath = "$DllPath.bak"

    if (-not (Test-Path $backupPath)) {
        Write-Error "Backup file not found: $backupPath. Cannot restore."
        return $false
    }

    Write-Host "Restoring original DLL from backup..." -ForegroundColor Cyan

    try {
        # 1. Move original backup to a temporary safe name
        $tempOriginal = "$DllPath.restore_original"
        [System.IO.File]::Move($backupPath, $tempOriginal)

        # 2. Rename current (patched) DLL to .bak (locked backup)
        [System.IO.File]::Move($DllPath, $backupPath)

        # 3. Restore original backup to the DLL location
        [System.IO.File]::Move($tempOriginal, $DllPath)
    }
    catch {
        Write-Error "Failed to restore DLL: $_"
        return $false
    }

    Write-Host "Restore completed. The previous (patched) DLL is now $backupPath (locked)." -ForegroundColor Green
    return $true
}

function Wait-ProcessExit {
    param([string]$ProcessName, [int]$TimeoutSeconds = 10)
    $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if (-not $proc) {
        Write-Host "Process '$ProcessName' is not running." -ForegroundColor Cyan
        return $true
    }

    try {
        Stop-Process -Name $ProcessName -Force -ErrorAction Stop
        Write-Host "Sent termination signal to '$ProcessName'. Waiting for exit..." -ForegroundColor Cyan
    }
    catch {
        Write-Warning "Could not terminate '$ProcessName': $_"
        return $false
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $stillRunning = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if (-not $stillRunning) {
            Write-Host "Process '$ProcessName' exited." -ForegroundColor Green
            return $true
        }
        Start-Sleep -Milliseconds 200
    }

    Write-Warning "Process '$ProcessName' did not exit within ${TimeoutSeconds}s. Continuing anyway..."
    return $false
}

function Set-RegistryDword {
    param([string]$KeyPath, [string]$ValueName, [int]$Value)
    $regPath = "HKLM:\$KeyPath"
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    Set-ItemProperty -Path $regPath -Name $ValueName -Value $Value -Type DWord -Force
    Write-Host "Registry value '$ValueName' set to $Value."
}

# -------------------------------------------------------------------
# Main
# -------------------------------------------------------------------
$dllPath = Find-Dll -DllName $appTargetDll
if (-not $dllPath) {
    Write-Error "StartAllBackX64.dll not found!"
    exit 1
}
Write-Host "File found: $dllPath"

try {
    $currentBytes = [System.IO.File]::ReadAllBytes($dllPath)
}
catch {
    Write-Error "Cannot read DLL: $_"
    exit 1
}

$isPatched     = (Find-Bytes $currentBytes $newBytes) -ge 0
$isOriginal    = (Find-Bytes $currentBytes $oldBytes) -ge 0
$backupPath    = "$dllPath.bak"
$backupExists  = Test-Path $backupPath

if ($Restore) {
    if (-not $backupExists) {
        Write-Error "No backup found. Cannot restore."
        exit 1
    }
}
else {
    if ($isPatched) {
        Write-Host "DLL is already patched. No changes needed." -ForegroundColor Green
        exit 0
    }
    if (-not $isOriginal) {
        Write-Error "Unknown DLL version – neither original nor patched pattern found. Aborting."
        exit 1
    }
}

# Kill related processes and wait for them to actually exit
Wait-ProcessExit -ProcessName $appTargetExe
Wait-ProcessExit -ProcessName "explorer"
Wait-ProcessExit -ProcessName "ShellHost"

# Disable shell auto‑restart
Set-RegistryDword -KeyPath "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" `
                  -ValueName "AutoRestartShell" -Value 0

# Perform operation
$success = $false
if ($Restore) {
    Write-Host "Restore mode selected."
    $success = Restore-Dll -DllPath $dllPath
}
else {
    Write-Host "Patch mode selected."
    $success = Patch-Dll -DllPath $dllPath
}

if ($success) {
    if (-not $Restore) {
        $exePath = Join-Path (Split-Path $dllPath -Parent) $appTargetExe
        if (Test-Path $exePath) {
            try { Start-Process -FilePath $exePath } catch { Write-Error "Failed to launch $exePath" }
        }
    }
}
else {
    Write-Error "Operation failed."
}

# Restart Explorer
Write-Host "Restarting Explorer..." -ForegroundColor Cyan
Start-Process -FilePath "explorer.exe"
Start-Sleep -Seconds 2
Write-Host "Explorer restarted." -ForegroundColor Green

# Re‑enable auto‑restart
Set-RegistryDword -KeyPath "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" `
                  -ValueName "AutoRestartShell" -Value 1

Write-Host "Script finished."
# StartAllBack Patcher

A PowerShell patcher for **StartAllBack** that applies a DLL modification so the app runs without a license check.

> **Disclaimer:** This tool is provided for educational use only. Use at your own risk. The author is not responsible for any damage or legal issues caused by its use.

---

## Requirements

- Windows 10 or 11
- PowerShell 5.1+ or PowerShell Core 7+
- Administrator privileges (requested automatically if needed)
- **StartAllBack 3.x** releases

---

## Quick Start

### Option 1: One-Liner (Remote)

Open **PowerShell as Administrator** and run:

```powershell
irm https://raw.githubusercontent.com/RezoxP/StartAllBack-Patcher/main/new.ps1 | iex
```

### Option 2: Run Downloaded File

1. Download the latest `new.ps1` file.
2. Open **PowerShell as Administrator** and run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File ".\new.ps1"
   ```
   Or right-click `new.ps1` and select **"Run with PowerShell"**.
3. If prompted, confirm the UAC prompt for Administrator rights.
4. The patch will be applied and Explorer will restart automatically.

---

## Command Line Options

| Switch | Description |
|---|---|
| `.\new.ps1` | Default mode: detects installed DLLs, creates `.bak` backup, applies patch, and restarts Explorer. |
| `.\new.ps1 -Status` | Inspects and displays patch status of installed StartAllBack DLLs without making any changes. |
| `.\new.ps1 -Restore` | Reverts patch and restores original DLL from `.bak` backup. |
| `.\new.ps1 -Force` | Forces patch application even if version signature is unrecognized. |
| `.\new.ps1 -NoRestart` | Prevents automatically restarting `explorer.exe` after completing. |

### Restore Original DLL Remote One-Liner

```powershell
& ([scriptblock]::create((irm https://raw.githubusercontent.com/RezoxP/StartAllBack-Patcher/main/new.ps1))) -Restore
```

---

## Safety & Backups

- An original backup (`.bak`) is created automatically before any modifications are written.
- Windows Winlogon shell auto-restart is temporarily suspended during patching to prevent process restart collisions.
- Running status checks (`-Status`) does not require Administrator rights.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| **"No StartAllBack installation DLLs found"** | Ensure StartAllBack is installed properly. |
| **"Access denied"** | Run PowerShell as Administrator. |
| **"Unknown DLL version"** | Your StartAllBack version may be unsupported. Use `-Force` to attempt patching anyway or check for repository updates. |
| **Explorer doesn't restart** | Open Task Manager (`Ctrl+Shift+Esc`), click **Run new task**, and type `explorer.exe`. |

---

## License

This project is for educational purposes. Please support developers by purchasing software you use regularly.

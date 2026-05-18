# StartAllBack Patcher

A simple PowerShell patcher for **StartAllBack** that applies a DLL modification so the app runs without a license check.

> **Disclaimer:** This tool is provided for educational use only. Use at your own risk. The author is not responsible for any damage or legal issues caused by its use.

---

## What It Does

- Searches for `StartAllBackX64.dll` on your system.
- Backs up the original DLL.
- Patches the DLL to bypass the license requirement.
- Restarts Explorer so the changes take effect.

---

## Requirements

- Windows 10 or 11
- PowerShell
- Administrator privileges (the script will ask for them automatically)
- **StartAllBack version 3.​** (3.x releases are supported)

---

## Quick Start

### Option 1: One-Liner (Remote)

Open **PowerShell as Administrator** and run:

```powershell
irm https://raw.githubusercontent.com/RezoxP/StartAllBack-Patcher/main/new.ps1 | iex
```

### Option 2: Run Downloaded File

1. **Download** the latest `new.ps1` file.
2. Open **PowerShell as Administrator** and run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File ".\new.ps1"
   ```
   Or simply right-click `new.ps1` and select **"Run with PowerShell"**.
3. If prompted, click **"Yes"** for the UAC (administrator) prompt.
4. Wait for the script to finish. You'll see:
   - `Patch applied successfully!`
   - Explorer will restart.
5. Open **StartAllBack** — it should now be activated.

---

## Restore Original DLL

If you want to undo the patch and restore the original file:

### Option 1: One-Liner (Remote)

```powershell
& ([scriptblock]::create((irm https://raw.githubusercontent.com/RezoxP/StartAllBack-Patcher/main/new.ps1))) -Restore
```

### Option 2: Run Downloaded File

1. Open **PowerShell as Administrator**.
2. Navigate to the folder containing `new.ps1` and run:
   ```powershell
   .\new.ps1 -Restore
   ```
3. The original DLL will be restored and Explorer will restart.

---

## Safety Notes

- The script **creates a `.bak` backup** of your original DLL before patching.
- If something goes wrong, you can always restore using the instructions above.
- The script temporarily disables Explorer auto-restart to prevent conflicts during patching.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "DLL not found" | Make sure StartAllBack is installed. Try reinstalling it. |
| "Access denied" | Run the script as Administrator. |
| "Unknown DLL version" | Your StartAllBack version may be too new or old. Check for script updates. |
| Explorer doesn't restart | Open Task Manager, end `explorer.exe`, then click File > Run new task > type `explorer.exe`. |

---

## License

This project is for educational purposes. Please support developers by purchasing software you use regularly.

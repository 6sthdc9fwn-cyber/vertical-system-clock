' Avvia l'helper in background, senza finestre, e lo fa ripartire se si chiude.
' Starts the helper in the background, no windows, and restarts it if it exits.
Set sh = CreateObject("WScript.Shell")
dir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\sysinfo.ps1"""
Do
    ' True = aspetta che l'helper termini / wait for the helper to exit
    sh.Run cmd, 0, True
    WScript.Sleep 30000
Loop

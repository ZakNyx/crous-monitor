Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File """ & scriptDir & "\crous_watcher.ps1"""
WshShell.Run cmd, 0, False
MsgBox "Surveillance CROUS lancee en arriere-plan !" & vbCrLf & "Vous recevrez une notification Windows des qu'un logement apparait ou disparait." & vbCrLf & vbCrLf & "Pour arreter, double-cliquez sur ARRETER_SURVEILLANCE.bat", vbInformation, "CROUS Monitor"

' Verilen PowerShell scriptini HIC pencere acmadan calistirir.
' wscript.exe bir GUI uygulamasi oldugu icin konsol ayrilmaz -- flas olmaz.
Option Explicit
Dim args, sh, ps, cmd, i
Set args = WScript.Arguments
If args.Count = 0 Then WScript.Quit 1
Set sh = CreateObject("WScript.Shell")
ps = sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
cmd = """" & ps & """ -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & args(0) & """"
For i = 1 To args.Count - 1
    cmd = cmd & " """ & args(i) & """"
Next
sh.Run cmd, 0, False

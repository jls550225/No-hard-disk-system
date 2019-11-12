echo REG ADD HKLM\SYSTEM\ControlSet001\Services\Tcpip\Parameters /v "NV Hostname" /t REG_SZ /d acfs-%random% /f > %windir%\system32\PCname.bat
echo REG DELETE HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce /v "PcName" /f >> %windir%\system32\PCname.bat

REG ADD HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce /v "PcName" /t REG_SZ /d %windir%\system32\PCname.bat /f

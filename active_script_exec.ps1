#Requires -RunAsAdministrator

reg add HKLM\Software\WireGuard /v DangerousScriptExecution /t REG_DWORD /d 1 /f
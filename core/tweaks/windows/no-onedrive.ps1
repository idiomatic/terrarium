# Keeps OneDrive from running, now and at every logon.
# timeout: 60
$ErrorActionPreference = 'Stop'
$key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
New-ItemProperty -Path $key -Name DisableFileSyncNGSC -Value 1 -PropertyType DWord -Force | Out-Null
$run = 'Software\Microsoft\Windows\CurrentVersion\Run'
Remove-ItemProperty -Path "HKCU:\$run" -Name OneDrive, OneDriveSetup -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\$run" -Name OneDrive, OneDriveSetup -ErrorAction SilentlyContinue
# New profiles are copied from the default user's hive, whose Run key installs OneDrive.
reg load HKU\TerrariumDefault C:\Users\Default\NTUSER.DAT | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'cannot load the default user hive' }
try {
    Remove-ItemProperty -Path "Registry::HKEY_USERS\TerrariumDefault\$run" -Name OneDrive, OneDriveSetup -ErrorAction SilentlyContinue
} finally {
    [gc]::Collect()
    reg unload HKU\TerrariumDefault | Out-Null
}
Get-Process OneDrive, OneDriveSetup -ErrorAction SilentlyContinue | Stop-Process -Force
exit 0

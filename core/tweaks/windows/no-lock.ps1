# Turns off the lock screen and screen saver (`NoLockScreen`, `ScreenSaveActive` policies).
# timeout: 60
$ErrorActionPreference = 'Stop'
$key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
New-ItemProperty -Path $key -Name NoLockScreen -Value 1 -PropertyType DWord -Force | Out-Null
$key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop'
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
New-ItemProperty -Path $key -Name ScreenSaveActive -Value '0' -PropertyType String -Force | Out-Null

# Turns off toast notifications.
# timeout: 60
$ErrorActionPreference = 'Stop'
$key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications'
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
New-ItemProperty -Path $key -Name NoToastApplicationNotification -Value 1 -PropertyType DWord -Force | Out-Null
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications'
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
New-ItemProperty -Path $key -Name ToastEnabled -Value 0 -PropertyType DWord -Force | Out-Null

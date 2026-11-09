# Turns off the lock screen and the screen saver.
# timeout: 60
$ErrorActionPreference = 'Stop'
$key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
New-Item -Path $key -Force | Out-Null
New-ItemProperty -Path $key -Name NoLockScreen -Value 1 -PropertyType DWord -Force | Out-Null
$key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop'
New-Item -Path $key -Force | Out-Null
New-ItemProperty -Path $key -Name ScreenSaveActive -Value '0' -PropertyType String -Force | Out-Null

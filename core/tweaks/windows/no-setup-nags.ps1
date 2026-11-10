# Turns off the first-logon animation and the "Let's finish setting up" and welcome prompts.
# timeout: 60
$ErrorActionPreference = 'Stop'
function Set-Dword($path, $name, $value) {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -Path $path -Name $name -Value $value -PropertyType DWord -Force | Out-Null
}
Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE' DisablePrivacyExperience 1
Set-Dword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' EnableFirstLogonAnimation 0
Set-Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' ScoobeSystemSettingEnabled 0
$delivery = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
foreach ($name in 'SubscribedContent-310093Enabled', 'SubscribedContent-338389Enabled') {
    Set-Dword $delivery $name 0
}

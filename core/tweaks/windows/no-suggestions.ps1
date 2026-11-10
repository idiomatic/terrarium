# Turns off Start recommendations, tips, Spotlight, and promoted apps.
# timeout: 60
$ErrorActionPreference = 'Stop'
function Set-Dword($path, $name, $value) {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -Path $path -Name $name -Value $value -PropertyType DWord -Force | Out-Null
}
$cloud = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
foreach ($name in 'DisableWindowsConsumerFeatures', 'DisableSoftLanding', 'DisableWindowsSpotlightFeatures', 'DisableTailoredExperiencesWithDiagnosticData', 'DisableCloudOptimizedContent') {
    Set-Dword $cloud $name 1
}
Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' HideRecommendedSection 1
$delivery = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
foreach ($name in 'ContentDeliveryAllowed', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled', 'SilentInstalledAppsEnabled', 'SoftLandingEnabled', 'SystemPaneSuggestionsEnabled', 'RotatingLockScreenOverlayEnabled', 'SubscribedContent-338387Enabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled', 'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled', 'SubscribedContent-353698Enabled') {
    Set-Dword $delivery $name 0
}
$advanced = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
Set-Dword $advanced Start_IrisRecommendations 0
Set-Dword $advanced Start_AccountNotifications 0
Set-Dword $advanced ShowSyncProviderNotifications 0

# Turns off the taskbar's Widgets, Copilot, and Chat, and Search highlights.
# timeout: 60
$ErrorActionPreference = 'Stop'
function Set-Dword($path, $name, $value) {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -Path $path -Name $name -Value $value -PropertyType DWord -Force | Out-Null
}
Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' AllowNewsAndInterests 0
Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' TurnOffWindowsCopilot 1
Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat' ChatIcon 3
Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' EnableDynamicContentInWSB 0
# Windows protects some of these per-user values from other writers; the policies above do the same, so a refusal is not a failure.
foreach ($pair in @(
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'TaskbarDa'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'TaskbarMn'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'ShowCopilotButton'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings', 'IsDynamicSearchBoxEnabled'))) {
    try { Set-Dword $pair[0] $pair[1] 0 } catch { }
}
exit 0

# Hides Microsoft Edge's first-run experience (`HKLM\SOFTWARE\Policies\Microsoft\Edge`, `HideFirstRunExperience`).
# timeout: 60
$ErrorActionPreference = 'Stop'
$key = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
New-ItemProperty -Path $key -Name HideFirstRunExperience -Value 1 -PropertyType DWord -Force | Out-Null

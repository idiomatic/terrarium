# Hides Microsoft Edge's first-run experience.
# timeout: 60
$ErrorActionPreference = 'Stop'
$key = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
New-Item -Path $key -Force | Out-Null
New-ItemProperty -Path $key -Name HideFirstRunExperience -Value 1 -PropertyType DWord -Force | Out-Null

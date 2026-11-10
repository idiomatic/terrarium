# Tells the virtual disk which blocks the guest has freed, so a saved layer holds only what is in use.
# timeout: 600
$ErrorActionPreference = 'Stop'
Optimize-Volume -DriveLetter C -ReTrim | Out-Null
exit 0

# Tells the virtual disk which blocks the guest has freed (`Optimize-Volume -ReTrim`), so a layer saved after it holds only what is in use.
# timeout: 600
$ErrorActionPreference = 'Stop'
Optimize-Volume -DriveLetter C -ReTrim | Out-Null
exit 0

# Turns display and system sleep and hibernation off.
# timeout: 60
$ErrorActionPreference = 'Stop'
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change monitor-timeout-ac 0
powercfg /change monitor-timeout-dc 0
powercfg /hibernate off

# Turns display and system sleep and hibernation off (`powercfg`); no recipe does.
# timeout: 60
$ErrorActionPreference = 'Stop'
foreach ($arguments in @(
    @('/change', 'standby-timeout-ac', '0'),
    @('/change', 'standby-timeout-dc', '0'),
    @('/change', 'monitor-timeout-ac', '0'),
    @('/change', 'monitor-timeout-dc', '0'),
    @('/hibernate', 'off'))) {
    powercfg @arguments
    if ($LASTEXITCODE -ne 0) { throw "powercfg $arguments failed ($LASTEXITCODE)" }
}
exit 0

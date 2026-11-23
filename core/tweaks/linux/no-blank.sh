# Stops the text console blanking, and at every boot through `/etc/local.d` where there is one.
set -e
off='printf "\033[9;0]\033[14;0]" > /dev/tty0'
# Read-only on some kernels, where the escape below does the same.
{ echo 0 > /sys/module/kernel/parameters/consoleblank; } 2>/dev/null || :
if [ -w /dev/tty0 ]; then sh -c "$off"; fi
if [ -d /etc/local.d ]; then
    printf '#!/bin/sh\n%s\n' "$off" > /etc/local.d/no-blank.start
    chmod 755 /etc/local.d/no-blank.start
fi

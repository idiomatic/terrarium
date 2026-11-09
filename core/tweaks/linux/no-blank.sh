# Keeps the text console from blanking, now and (where Alpine's local.d exists) at every boot.
off='printf "\033[9;0]\033[14;0]" > /dev/tty0'
{ echo 0 > /sys/module/kernel/parameters/consoleblank; } 2>/dev/null
[ -w /dev/tty0 ] && sh -c "$off"
if [ -d /etc/local.d ]; then
    printf '#!/bin/sh\n%s\n' "$off" > /etc/local.d/no-blank.start
    chmod 755 /etc/local.d/no-blank.start
fi
exit 0

#!/bin/bash
# HEAD-checks each URL on standard input and prints `STATUS URL`; the final status after redirects.
# Usage: tools/check-urls.sh < URLS
# Some hosts (DistroWatch, SourceForge, Microsoft) answer 403 to a script however it asks; that is not a dead link.
while read -r u; do
  [ -z "$u" ] && continue
  printf '%s %s\n' "$(curl -sIL -m 40 -A 'Mozilla/5.0' -o /dev/null -w '%{http_code}' "$u")" "$u"
done

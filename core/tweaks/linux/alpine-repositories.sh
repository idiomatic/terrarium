# Points Alpine's package repositories at the main and community repositories of its first mirror.
[ -f /etc/apk/repositories ] || { echo "not an Alpine guest" >&2; exit 1; }
# The first mirror line, commented out or not, without its repository name; the CDN's when there is none.
mirror=$(sed -n 's|^#*\(https\{0,1\}://.*\)$|\1|p' /etc/apk/repositories | head -1 | sed 's|/[a-z]*$||')
if [ -z "$mirror" ]; then
    mirror="https://dl-cdn.alpinelinux.org/alpine/v$(cut -d. -f1,2 /etc/alpine-release)"
fi
printf '%s/main\n%s/community\n' "$mirror" "$mirror" > /etc/apk/repositories

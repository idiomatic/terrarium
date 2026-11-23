# Turns off the account's screen saver and its password prompt.
# timeout: 30
set -e
defaults -currentHost write com.apple.screensaver idleTime -int 0
defaults write com.apple.screensaver askForPassword -int 0

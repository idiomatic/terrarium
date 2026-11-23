# Marks the account's first-login panes as seen (`com.apple.SetupAssistant`).
# timeout: 30
set -e
version=$(sw_vers -productVersion)
build=$(sw_vers -buildVersion)
for pane in Accessibility ActivationLock Appearance ApplePaySetup AvatarSetup CloudSetup Privacy ScreenTime SiriSetup SyncSetup SyncSetup2 TouchIDSetup TrueTonePrivacy; do
    defaults write com.apple.SetupAssistant "DidSee$pane" -bool true
done
defaults write com.apple.SetupAssistant LastSeenCloudProductVersion -string "$version"
defaults write com.apple.SetupAssistant LastSeenBuddyBuildVersion -string "$build"

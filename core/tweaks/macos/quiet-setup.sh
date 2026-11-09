# Marks the account's first-login panes (Siri, Screen Time, Touch ID, and the like) as seen.
version=$(sw_vers -productVersion)
build=$(sw_vers -buildVersion)
for pane in Accessibility ActivationLock Appearance ApplePaySetup AvatarSetup CloudSetup Privacy ScreenTime SiriSetup SyncSetup SyncSetup2 TouchIDSetup TrueTonePrivacy; do
    defaults write com.apple.SetupAssistant "DidSee$pane" -bool true
done
defaults write com.apple.SetupAssistant LastSeenCloudProductVersion -string "$version"
defaults write com.apple.SetupAssistant LastSeenBuddyBuildVersion -string "$build"

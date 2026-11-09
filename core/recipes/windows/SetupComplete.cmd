@echo off
if not exist C:\terrarium mkdir C:\terrarium
echo setupcomplete ran %date% %time% > C:\terrarium\setupcomplete.txt
rem At the account's logon, in its session (the clipboard needs one); /it needs no stored password.
schtasks /create /tn terrarium /sc onlogon /ru @USER@ /it /rl highest /tr C:\terrarium\terrarium-helper.exe /f >> C:\terrarium\setupcomplete.txt 2>&1

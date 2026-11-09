@echo off
setlocal EnableExtensions
set L=C:\install.log
echo [%time%] install start > %L%
for %%d in (D E F G H I J K L M N O P Q R S T U V W Y Z) do if exist %%d:\sources\install.wim set WIM=%%d:\sources\install.wim
echo wim=%WIM% >> %L%
if not defined WIM goto fail
echo list disk > X:\ld.txt
diskpart /s X:\ld.txt > X:\ld.out 2>&1
type X:\ld.out >> %L%
for /f "tokens=2" %%n in ('type X:\ld.out ^| find " @DISKGB@ GB"') do set TD=%%n
echo target disk=%TD% >> %L%
if not defined TD goto fail
(
echo select disk %TD%
echo clean
echo convert gpt
echo create partition efi size=260
echo format quick fs=fat32 label=ESP
echo assign letter=S
echo create partition msr size=16
echo create partition primary
echo format quick fs=ntfs label=Windows
echo assign letter=V
) > X:\dp.txt
diskpart /s X:\dp.txt >> %L% 2>&1
if not exist V:\ goto fail
echo [%time%] apply image >> %L%
dism /Apply-Image /ImageFile:%WIM% /Index:@INDEX@ /ApplyDir:V:\ >> %L% 2>&1
echo [%time%] apply exit %errorlevel% >> %L%
if errorlevel 1 goto fail
if not exist V:\Windows\System32\config\SYSTEM goto fail
dism /Image:V:\ /Add-Driver /Driver:C:\drivers /Recurse >> %L% 2>&1
echo [%time%] add-driver exit %errorlevel% >> %L%
bcdboot V:\Windows /s S: /f UEFI >> %L% 2>&1
echo [%time%] bcdboot exit %errorlevel% >> %L%
if errorlevel 1 goto fail
mkdir S:\EFI\BOOT >> %L% 2>&1
copy /y C:\EFI\BOOT\BOOTAA64.EFI S:\EFI\BOOT\BOOTAA64.EFI >> %L% 2>&1
if errorlevel 1 goto fail
mkdir V:\Windows\Panther >> %L% 2>&1
copy /y C:\unattend.xml V:\Windows\Panther\unattend.xml >> %L% 2>&1
if errorlevel 1 goto fail
mkdir V:\Windows\Setup\Scripts >> %L% 2>&1
copy /y C:\SetupComplete.cmd V:\Windows\Setup\Scripts\SetupComplete.cmd >> %L% 2>&1
if errorlevel 1 goto fail
mkdir V:\terrarium >> %L% 2>&1
copy /y C:\terrarium-helper.exe V:\terrarium\terrarium-helper.exe >> %L% 2>&1
if errorlevel 1 goto fail
reg load HKLM\OFFSOFT V:\Windows\System32\config\SOFTWARE >> %L% 2>&1
reg add HKLM\OFFSOFT\Microsoft\Windows\CurrentVersion\OOBE /v BypassNRO /t REG_DWORD /d 1 /f >> %L% 2>&1
reg unload HKLM\OFFSOFT >> %L% 2>&1
echo [%time%] install done >> %L%
rem Only a complete install leaves this; without it, the host does not save the guest.
echo ok > C:\install.ok
wpeutil shutdown
goto :eof
:fail
echo [%time%] FAILED >> %L%
wpeutil shutdown

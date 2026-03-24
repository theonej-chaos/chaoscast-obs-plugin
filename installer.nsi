; ChaosCast OBS Plugin Installer
; Handles multiple OBS versions and install locations

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"

; ── Branding ──
Name "ChaosCast OBS Plugin"
OutFile "ChaosCast-OBS-Plugin-Setup.exe"
Caption "ChaosCast OBS Plugin Installer"
BrandingText "ChaosCast — Multistream Manager"
!define MUI_ICON "installer-icon.ico"
Unicode true
SetCompressor /SOLID lzma

; Need admin for Program Files installs
RequestExecutionLevel admin

; ── Variables ──
Var ObsProgramFiles
Var ObsSteam
Var ObsAppData
Var InstallCount

; ── MUI Settings ──
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "ChaosCast OBS Plugin"
!define MUI_WELCOMEPAGE_TEXT "This will install the ChaosCast multistream plugin for OBS Studio.$\r$\n$\r$\nThe plugin lets you stream to multiple platforms simultaneously from one OBS instance.$\r$\n$\r$\nRequirements:$\r$\n  - OBS Studio 28+ with obs-websocket v5$\r$\n$\r$\nThe installer will auto-detect your OBS installation(s).$\r$\n$\r$\nClick Next to continue."
!define MUI_FINISHPAGE_TITLE "Installation Complete"
!define MUI_FINISHPAGE_TEXT "The ChaosCast plugin has been installed.$\r$\n$\r$\nNext steps:$\r$\n  1. Open (or restart) OBS Studio$\r$\n  2. Go to chaoscast.live and sign in$\r$\n  3. Click Copy Bridge URL and add it as a Browser Source in OBS$\r$\n  4. Toggle your platforms live from the dashboard$\r$\n$\r$\nHappy streaming!"

; ── Pages ──
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

; ── Init: Detect all OBS installs ──
Function .onInit
    StrCpy $ObsProgramFiles ""
    StrCpy $ObsSteam ""
    StrCpy $InstallCount "0"

    ; User-level appdata path (always available)
    ReadEnvStr $ObsAppData "APPDATA"
    StrCpy $ObsAppData "$ObsAppData\obs-studio"

    ; Check Program Files (standard install)
    IfFileExists "$PROGRAMFILES64\obs-studio\bin\64bit\obs64.exe" 0 NoPF
        StrCpy $ObsProgramFiles "$PROGRAMFILES64\obs-studio"
    NoPF:

    ; Check Steam
    IfFileExists "C:\Program Files (x86)\Steam\steamapps\common\OBS Studio\bin\64bit\obs64.exe" 0 NoSteam
        StrCpy $ObsSteam "C:\Program Files (x86)\Steam\steamapps\common\OBS Studio"
    NoSteam:

    ; Check registry if Program Files not found
    StrCmp $ObsProgramFiles "" 0 SkipReg
        ReadRegStr $0 HKLM "SOFTWARE\OBS Studio" ""
        StrCmp $0 "" SkipReg2 0
        IfFileExists "$0\bin\64bit\obs64.exe" 0 SkipReg2
            StrCpy $ObsProgramFiles "$0"
        SkipReg2:
    SkipReg:

    ; Warn if nothing found
    StrCmp $ObsProgramFiles "" 0 FoundSomething
    StrCmp $ObsSteam "" NothingFound FoundSomething

    NothingFound:
        MessageBox MB_YESNO|MB_ICONEXCLAMATION \
            "OBS Studio was not detected.$\r$\n$\r$\nThe plugin will be installed to:$\r$\n$ObsAppData\plugins$\r$\n$\r$\nContinue anyway?" \
            IDYES FoundSomething
        Abort

    FoundSomething:

    ; Check OBS version — we need 30+
    StrCmp $ObsProgramFiles "" SkipVersionCheck 0
        GetDLLVersion "$ObsProgramFiles\bin\64bit\obs64.exe" $R0 $R1
        IntOp $R2 $R0 >> 16
        IntOp $R2 $R2 & 0xFFFF
        IntCmp $R2 30 VersionOK VersionTooOld VersionOK
        VersionTooOld:
            MessageBox MB_YESNO|MB_ICONEXCLAMATION \
                "OBS Studio version $R2 detected. This plugin requires OBS 30 or newer.$\r$\n$\r$\nPlease update OBS from obsproject.com before installing.$\r$\n$\r$\nInstall anyway?" \
                IDYES VersionOK
            Abort
        VersionOK:
    SkipVersionCheck:
FunctionEnd

; ── Install Section ──
Section "Install"
    StrCpy $InstallCount "0"

    ; ── Remove old obs-multi-rtmp plugin if present ──
    ; Clean up the old name so users don't end up with both
    StrCmp $ObsProgramFiles "" SkipPFClean 0
        Delete "$ObsProgramFiles\obs-plugins\64bit\obs-multi-rtmp.dll"
        RMDir /r "$ObsProgramFiles\data\obs-plugins\obs-multi-rtmp"
    SkipPFClean:
    StrCmp $ObsSteam "" SkipSteamClean 0
        Delete "$ObsSteam\obs-plugins\64bit\obs-multi-rtmp.dll"
        RMDir /r "$ObsSteam\data\obs-plugins\obs-multi-rtmp"
    SkipSteamClean:
    RMDir /r "$ObsAppData\plugins\obs-multi-rtmp"

    ; ── Install to Program Files (flat layout) ──
    StrCmp $ObsProgramFiles "" SkipPFInstall 0
    IfFileExists "$ObsProgramFiles\obs-plugins\64bit\*.*" 0 SkipPFInstall
        DetailPrint "Installing to: $ObsProgramFiles\obs-plugins\64bit\"
        SetOutPath "$ObsProgramFiles\obs-plugins\64bit"
        File "chaoscast-plugin.dll"
        CreateDirectory "$ObsProgramFiles\data\obs-plugins\chaoscast-plugin\locale"
        SetOutPath "$ObsProgramFiles\data\obs-plugins\chaoscast-plugin\locale"
        File "data\locale\en-US.ini"
        IntOp $InstallCount $InstallCount + 1
        DetailPrint "Installed to Program Files (system-level)"
    SkipPFInstall:

    ; ── Install to Steam (flat layout) ──
    StrCmp $ObsSteam "" SkipSteamInstall 0
    IfFileExists "$ObsSteam\obs-plugins\64bit\*.*" 0 SkipSteamInstall
        DetailPrint "Installing to: $ObsSteam\obs-plugins\64bit\"
        SetOutPath "$ObsSteam\obs-plugins\64bit"
        File "chaoscast-plugin.dll"
        CreateDirectory "$ObsSteam\data\obs-plugins\chaoscast-plugin\locale"
        SetOutPath "$ObsSteam\data\obs-plugins\chaoscast-plugin\locale"
        File "data\locale\en-US.ini"
        IntOp $InstallCount $InstallCount + 1
        DetailPrint "Installed to Steam OBS (system-level)"
    SkipSteamInstall:

    ; ── Install to AppData (user-level, OBS 28+ style) ──
    DetailPrint "Installing to: $ObsAppData\plugins\chaoscast-plugin\"
    CreateDirectory "$ObsAppData\plugins\chaoscast-plugin\bin\64bit"
    SetOutPath "$ObsAppData\plugins\chaoscast-plugin\bin\64bit"
    File "chaoscast-plugin.dll"
    CreateDirectory "$ObsAppData\plugins\chaoscast-plugin\data\locale"
    SetOutPath "$ObsAppData\plugins\chaoscast-plugin\data\locale"
    File "data\locale\en-US.ini"
    IntOp $InstallCount $InstallCount + 1
    DetailPrint "Installed to AppData (user-level)"

    ; Summary
    DetailPrint ""
    DetailPrint "Plugin installed to $InstallCount location(s)"
    DetailPrint "Restart OBS Studio to activate the plugin."
SectionEnd

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
Unicode true
SetCompressor /SOLID lzma

; Need admin for Program Files installs
RequestExecutionLevel admin

; ── Variables ──
Var ObsFound
Var ObsProgramFiles
Var ObsSteam
Var ObsAppData
Var InstallCount

; ── MUI Settings ──
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "ChaosCast OBS Plugin"
!define MUI_WELCOMEPAGE_TEXT "This will install the ChaosCast multistream plugin for OBS Studio.$\r$\n$\r$\nThe plugin lets you stream to multiple platforms (Twitch, YouTube, Kick, TikTok, X) simultaneously from one OBS instance.$\r$\n$\r$\nRequirements:$\r$\n  • OBS Studio 28+ with obs-websocket v5$\r$\n$\r$\nThe installer will auto-detect your OBS installation(s).$\r$\n$\r$\nClick Next to continue."
!define MUI_FINISHPAGE_TITLE "Installation Complete"
!define MUI_FINISHPAGE_TEXT "The ChaosCast plugin has been installed.$\r$\n$\r$\nNext steps:$\r$\n  1. Open (or restart) OBS Studio$\r$\n  2. Go to chaoscast.live and sign in$\r$\n  3. Click 'Copy Bridge URL' and add it as a Browser Source in OBS$\r$\n  4. Toggle your platforms live from the dashboard$\r$\n$\r$\nHappy streaming!"

; ── Pages ──
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

; ── Init: Detect all OBS installs ──
Function .onInit
    StrCpy $ObsFound "0"
    StrCpy $ObsProgramFiles ""
    StrCpy $ObsSteam ""
    StrCpy $InstallCount "0"

    ; Always set up user-level appdata path
    ReadEnvStr $ObsAppData "$APPDATA"
    StrCpy $ObsAppData "$ObsAppData\obs-studio"

    ; 1. Check Program Files (standard install)
    IfFileExists "$PROGRAMFILES64\obs-studio\bin\64bit\obs64.exe" 0 +3
        StrCpy $ObsProgramFiles "$PROGRAMFILES64\obs-studio"
        StrCpy $ObsFound "1"

    ; 2. Check Steam common paths
    IfFileExists "C:\Program Files (x86)\Steam\steamapps\common\OBS Studio\bin\64bit\obs64.exe" 0 +3
        StrCpy $ObsSteam "C:\Program Files (x86)\Steam\steamapps\common\OBS Studio"
        StrCpy $ObsFound "1"

    ; 3. Check registry for OBS install path
    ${If} $ObsProgramFiles == ""
        ReadRegStr $0 HKLM "SOFTWARE\OBS Studio" ""
        ${If} $0 != ""
            IfFileExists "$0\bin\64bit\obs64.exe" 0 +2
                StrCpy $ObsProgramFiles "$0"
                StrCpy $ObsFound "1"
        ${EndIf}
    ${EndIf}

    ; 4. Check 32-bit registry too
    ${If} $ObsProgramFiles == ""
        ReadRegStr $0 HKLM "SOFTWARE\WOW6432Node\OBS Studio" ""
        ${If} $0 != ""
            IfFileExists "$0\bin\64bit\obs64.exe" 0 +2
                StrCpy $ObsProgramFiles "$0"
                StrCpy $ObsFound "1"
        ${EndIf}
    ${EndIf}

    ; If nothing found, warn but allow install to appdata
    ${If} $ObsFound == "0"
        MessageBox MB_YESNO|MB_ICONEXCLAMATION \
            "OBS Studio was not detected on this system.$\r$\n$\r$\nThe plugin will be installed to the user plugin directory:$\r$\n$ObsAppData\plugins$\r$\n$\r$\nContinue anyway?" \
            IDYES +2
        Abort
    ${EndIf}
FunctionEnd

; ── Install Section ──
Section "Install"
    StrCpy $InstallCount "0"

    ; ── Method 1: System-level flat layout (Program Files) ──
    ; For OBS installs that use C:\Program Files\obs-studio\obs-plugins\64bit\
    ${If} $ObsProgramFiles != ""
        IfFileExists "$ObsProgramFiles\obs-plugins\64bit\*.*" 0 SkipPF
            DetailPrint "Installing to: $ObsProgramFiles\obs-plugins\64bit\"
            SetOutPath "$ObsProgramFiles\obs-plugins\64bit"
            File "obs-multi-rtmp.dll"

            ; Also need data dir for locale files
            SetOutPath "$ObsProgramFiles\data\obs-plugins\obs-multi-rtmp\locale\en-US"
            File "data\locale\en-US.ini"

            IntOp $InstallCount $InstallCount + 1
            DetailPrint "Installed to Program Files (system-level)"
        SkipPF:
    ${EndIf}

    ; ── Method 2: System-level flat layout (Steam) ──
    ${If} $ObsSteam != ""
        IfFileExists "$ObsSteam\obs-plugins\64bit\*.*" 0 SkipSteam
            DetailPrint "Installing to: $ObsSteam\obs-plugins\64bit\"
            SetOutPath "$ObsSteam\obs-plugins\64bit"
            File "obs-multi-rtmp.dll"

            SetOutPath "$ObsSteam\data\obs-plugins\obs-multi-rtmp\locale\en-US"
            File "data\locale\en-US.ini"

            IntOp $InstallCount $InstallCount + 1
            DetailPrint "Installed to Steam OBS (system-level)"
        SkipSteam:
    ${EndIf}

    ; ── Method 3: User-level plugin directory (OBS 28+ style) ──
    ; Always install here as a fallback — works for newer OBS
    DetailPrint "Installing to: $ObsAppData\plugins\obs-multi-rtmp\"
    SetOutPath "$ObsAppData\plugins\obs-multi-rtmp\bin\64bit"
    File "obs-multi-rtmp.dll"

    SetOutPath "$ObsAppData\plugins\obs-multi-rtmp\data\locale\en-US"
    File "data\locale\en-US.ini"

    IntOp $InstallCount $InstallCount + 1
    DetailPrint "Installed to AppData (user-level)"

    ; Summary
    DetailPrint ""
    DetailPrint "Plugin installed to $InstallCount location(s)"
    DetailPrint "Restart OBS Studio to activate the plugin."
SectionEnd

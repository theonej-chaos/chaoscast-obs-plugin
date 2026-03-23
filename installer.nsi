; ChaosCast OBS Plugin Installer
; Installs the obs-multi-rtmp plugin with ChaosCast vendor support

!include "MUI2.nsh"
!include "FileFunc.nsh"

; ── Branding ──
Name "ChaosCast OBS Plugin"
OutFile "ChaosCast-OBS-Plugin-Setup.exe"
Caption "ChaosCast OBS Plugin Installer"
BrandingText "ChaosCast — Multistream Manager"
Unicode true
RequestExecutionLevel user
SetCompressor /SOLID lzma

; ── Variables ──
Var ObsPluginDir

; ── MUI Settings ──
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "ChaosCast OBS Plugin"
!define MUI_WELCOMEPAGE_TEXT "This will install the ChaosCast multistream plugin for OBS Studio.$\r$\n$\r$\nThe plugin lets you stream to multiple platforms (Twitch, YouTube, Kick, TikTok, X) simultaneously from one OBS instance.$\r$\n$\r$\nRequirements:$\r$\n  • OBS Studio 30+ (with obs-websocket v5)$\r$\n$\r$\nClick Next to continue."
!define MUI_FINISHPAGE_TITLE "Installation Complete"
!define MUI_FINISHPAGE_TEXT "The ChaosCast plugin has been installed.$\r$\n$\r$\nNext steps:$\r$\n  1. Open (or restart) OBS Studio$\r$\n  2. Go to chaoscast.live and sign in$\r$\n  3. Click 'Copy Bridge URL' and add it as a Browser Source in OBS$\r$\n  4. Toggle your platforms live from the dashboard$\r$\n$\r$\nHappy streaming!"

; ── Pages ──
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

; ── Init: Find OBS install ──
Function .onInit
    ; Try standard OBS plugin paths
    ; 1. %APPDATA%/obs-studio/plugins (user-level, preferred)
    ReadEnvStr $0 "APPDATA"
    StrCpy $ObsPluginDir "$0\obs-studio\plugins"
    IfFileExists "$0\obs-studio\*.*" FoundObs 0

    ; 2. %ALLUSERSPROFILE%/obs-studio/plugins (system-level)
    ReadEnvStr $0 "ALLUSERSPROFILE"
    StrCpy $ObsPluginDir "$0\obs-studio\plugins"
    IfFileExists "$0\obs-studio\*.*" FoundObs 0

    ; 3. Default Program Files
    StrCpy $ObsPluginDir "$PROGRAMFILES64\obs-studio\obs-plugins\64bit"
    IfFileExists "$PROGRAMFILES64\obs-studio\*.*" FoundObs 0

    ; Fallback to user appdata
    ReadEnvStr $0 "APPDATA"
    StrCpy $ObsPluginDir "$0\obs-studio\plugins"

    FoundObs:
FunctionEnd

; ── Install Section ──
Section "Install"
    SetOutPath "$ObsPluginDir\obs-multi-rtmp\bin\64bit"
    File "obs-multi-rtmp.dll"

    ; Write uninstaller
    SetOutPath "$ObsPluginDir\obs-multi-rtmp"
    WriteUninstaller "$ObsPluginDir\obs-multi-rtmp\uninstall.exe"
SectionEnd

; ── Uninstaller ──
Section "Uninstall"
    RMDir /r "$ObsPluginDir\obs-multi-rtmp"
SectionEnd

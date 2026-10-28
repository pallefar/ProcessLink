Unicode true
!include "MUI2.nsh"
!include "FileFunc.nsh"

!ifndef VERSION
!define VERSION "0.1.0"
!endif
!ifndef SRCDIR
!define SRCDIR "."
!endif
!ifndef OUTFILE
!define OUTFILE "ProcessLink-setup.exe"
!endif

Name "ProcessLink"
OutFile "${OUTFILE}"
InstallDir "$PROGRAMFILES64\ProcessLink"
InstallDirRegKey HKLM "Software\ProcessLink" "InstallDir"
RequestExecutionLevel admin
SetCompressor /SOLID lzma
BrandingText "ProcessLink · in-house discovery to TEOA improvement"

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "ProcessLink"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "CompanyName" "TE Operating Advantage"
VIAddVersionKey "FileDescription" "ProcessLink installer"
VIAddVersionKey "LegalCopyright" "TE Operating Advantage"

!define MUI_ICON "${SRCDIR}\icon.ico"
!define MUI_UNICON "${SRCDIR}\icon.ico"
!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "ProcessLink" SEC_APP
  SetOutPath "$INSTDIR"
  File "${SRCDIR}\processlink.exe"

  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\ProcessLink"
  CreateShortCut "$SMPROGRAMS\ProcessLink\ProcessLink.lnk" "$INSTDIR\processlink.exe"
  CreateShortCut "$DESKTOP\ProcessLink.lnk" "$INSTDIR\processlink.exe"

  WriteRegStr HKLM "Software\ProcessLink" "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\ProcessLink" "DisplayName" "ProcessLink"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\ProcessLink" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\ProcessLink" "Publisher" "TE Operating Advantage"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\ProcessLink" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\ProcessLink" "DisplayIcon" "$INSTDIR\processlink.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\ProcessLink" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\ProcessLink" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\ProcessLink" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\ProcessLink" "EstimatedSize" "$0"
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\processlink.exe"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\ProcessLink\ProcessLink.lnk"
  RMDir "$SMPROGRAMS\ProcessLink"
  Delete "$DESKTOP\ProcessLink.lnk"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\ProcessLink"
  DeleteRegKey HKLM "Software\ProcessLink"
SectionEnd

; =============================================================================
; فاز ۸ — بند ۰: نصب‌کننده Inno Setup برای داشبورد تعمیرات و خدمات (J.S.H)
; سازنده: آورین سگال بی همتا — نسخه هم‌گام با apps/dashboard/pubspec.yaml
;
; رفتار:
;   • مقصد نصب را خود کاربر انتخاب می‌کند (DefaultDirName + DisableDirPage=no)
;     پیش‌فرض: {autopf}\JSHDashboard — با PrivilegesRequired=lowest در حالت
;     بدون مجوز مدیر، {autopf} به %LOCALAPPDATA%\Programs اشاره می‌کند،
;     پس کاربر بدون UAC هم می‌تواند در هر پوشه دلخواه نصب کند.
;   • بند ۰: دیتابیس در همان پوشه نصب — پس از کپی فایل‌ها، فایل خالی
;     portable.marker کنار exe نوشته می‌شود؛ برنامه
;     (lib/core/services/install_paths.dart) با دیدن این نشانگر، بانک
;     jsh_dashboard.db (و -wal/-shm) را در همین پوشه می‌سازد.
;   • بند ۰.۲: هنگام حذف برنامه، کاربر پرسیده می‌شود که آیا دیتابیس و
;     داده‌ها هم کامل حذف شوند یا حفظ شوند (پیش‌فرض: حفظ).
;   • AllowNoIcons — امکان نصب بدون شورتکات در منوی استارت.
;
; ساخت در CI:  iscc installer\jsh_dashboard.iss
; خروجی:      installer/output/jsh-dashboard-setup-<نسخه>.exe
; =============================================================================

#define MyAppName "J.S.H Service Dashboard"
#define MyAppNameFa "داشبورد تعمیرات و خدمات"
; هم‌گام با version در apps/dashboard/pubspec.yaml و AppInfo.version
#define MyAppVersion "0.12.4"
#define MyAppPublisher "آورین سگال بی همتا"
#define MyAppExeName "jsh_service_dashboard.exe"
#define MyAppDbName "jsh_dashboard.db"

[Setup]
AppId={{8E4A2C1F-6B3D-4E9A-9F58-1C2D3A4B5C6D}
AppName={#MyAppName} ({#MyAppNameFa})
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppSupportPhone=09130356250
DefaultDirName={autopf}\JSHDashboard
DisableDirPage=no
DefaultGroupName={#MyAppNameFa}
AllowNoIcons=yes
; آیکن برند — همان منبعی که در Runner.rc ویندوز استفاده می‌شود (بند ۲)
SetupIconFile="..\apps\dashboard\windows\runner\resources\app_icon.ico"
UninstallDisplayIcon="{app}\{#MyAppExeName}"
; نصب بدون نیاز به مجوز مدیر — کاربر پوشه دلخواه خودش را انتخاب می‌کند
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=output
OutputBaseFilename=jsh-dashboard-setup-{#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#MyAppNameFa}
ArchitecturesInstallIn64BitMode=x64

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; \
    GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; خروجی flutter build windows --release — کل محتویات پوشه Release
Source: "..\apps\dashboard\build\windows\x64\runner\Release\*"; \
    DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#MyAppNameFa}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppNameFa}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppNameFa}"; Filename: "{app}\{#MyAppExeName}"; \
    Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppNameFa}}"; \
    Flags: nowait postinstall skipifsilent

[Code]
// فاز ۸ — بند ۰: پس از کپی فایل‌ها، نشانگر «حالت پرتابل» کنار exe نوشته می‌شود.
// برنامه با دیدن این فایل، پایگاه‌داده را در همین پوشه نصب می‌سازد.
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    SaveStringToFile(ExpandConstant('{app}\portable.marker'),
      'JSH portable install — database stays in this folder', False);
end;

// فاز ۸ — بند ۰.۲: هنگام حذف برنامه از کاربر پرسیده می‌شود که داده‌ها
// (بانک SQLite + wal/shm + نشانگر پرتابل) نیز کامل حذف شوند یا حفظ شوند.
// اگر کاربر «خیر» بگوید، داده‌ها در پوشه نصب باقی می‌مانند تا در نصب دوباره
// همان پوشه به‌صورت خودکار دوباره استفاده شوند.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DbPath: string;
  Msg: string;
begin
  if CurUninstallStep = usUninstall then
  begin
    DbPath := ExpandConstant('{app}\{#MyAppDbName}');
    if FileExists(DbPath) then
    begin
      Msg := 'آیا می‌خواهید دیتابیس و داده‌ها نیز کامل حذف شوند؟' #13#10 #13#10 +
             'در صورت انتخاب «No»، داده‌های شما (سفارش‌ها، مشتریان و فاکتورها) ' +
             'در پوشه نصب باقی می‌مانند و در نصب دوباره بازیابی می‌شوند.' #13#10 +
             'مسیر داده‌ها:' #13#10 + DbPath;
      if MsgBox(Msg, mbConfirmation, MB_YESNO) = IDYES then
      begin
        // بانک SQLite و فایل‌های ترجمه آن
        DeleteFile(ExpandConstant('{app}\{#MyAppDbName}'));
        DeleteFile(ExpandConstant('{app}\{#MyAppDbName}-wal'));
        DeleteFile(ExpandConstant('{app}\{#MyAppDbName}-shm'));
        // نشانگر پرتابل هم حذف می‌شود تا نصب بعدی تازه شروع شود
        DeleteFile(ExpandConstant('{app}\portable.marker'));
      end;
    end;
  end;
end;

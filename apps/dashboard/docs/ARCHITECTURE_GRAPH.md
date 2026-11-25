# نقشه گراف معماری برنامه (Graphify)

**آخرین به‌روزرسانی:** 2026-11-25T20:31:41
**فایل‌های Dart:** 48 — **خطوط کد:** 10592 — **لبه‌های وابستگی داخلی:** 174

## چطور استفاده کنم؟
قبل از هر اصلاح، فایل هدف را در گراف پیدا کن؛ مسیر وابستگی‌هایش نشان می‌دهد چه چیزهایی تحت‌تأثیر قرار می‌گیرند. بعد از اصلاح، دوباره graphify اجرا کن (اسکیل واچر).

## ماژول‌ها

| ماژول | فایل‌ها | خطوط |
|---|---|---|
| core/services | 12 | 1878 |
| shared/widgets | 7 | 1458 |
| features/settings | 2 | 731 |
| shared/charts | 1 | 652 |
| features/dbmanager | 2 | 573 |
| core/theme | 1 | 465 |
| features/shell | 1 | 458 |
| features/intake | 1 | 385 |
| features/onboarding | 1 | 366 |
| core/models.dart | 1 | 353 |
| core/repos.dart | 1 | 337 |
| features/calendar | 1 | 325 |
| features/tickets | 1 | 295 |
| features/home | 1 | 280 |
| features/customers | 1 | 264 |
| features/warranty | 1 | 240 |
| core/db | 1 | 206 |
| root | 2 | 196 |
| features/board | 1 | 181 |
| features/assistant | 1 | 173 |
| features/support | 2 | 157 |
| features/reminders | 1 | 152 |
| features/invoices | 1 | 145 |
| core/warranty.dart | 1 | 125 |
| core/utils.dart | 1 | 86 |
| core/constants.dart | 1 | 58 |
| shared/data | 1 | 53 |

## گراف وابستگی‌ها

```mermaid
flowchart LR
  N0["app"]:::core
  N1["core/constants"]:::core
  N2["core/db/db"]:::data
  N3["core/models"]:::data
  N4["core/repos"]:::data
  N5["core/services/app_session"]:::svc
  N6["core/services/assistant_service"]:::svc
  N7["core/services/backup_service"]:::svc
  N8["core/services/calendar_export_service"]:::svc
  N9["core/services/email_service"]:::svc
  N10["core/services/font_service"]:::svc
  N11["core/services/forecast_service"]:::svc
  N12["core/services/install_report_service"]:::svc
  N13["core/services/license_service"]:::svc
  N14["core/services/pdf_service"]:::svc
  N15["core/services/reminder_service"]:::svc
  N16["core/services/supervisor_service"]:::svc
  N17["core/theme/theme_config"]:::core
  N18["core/utils"]:::core
  N19["core/warranty"]:::core
  N20["features/assistant/assistant_page"]:::feat
  N21["features/board/board"]:::feat
  N22["features/calendar/calendar_page"]:::feat
  N23["features/customers/customers"]:::feat
  N24["features/dbmanager/db_manager_page"]:::feat
  N25["features/dbmanager/supervisor_gate"]:::feat
  N26["features/home/dashboard"]:::feat
  N27["features/intake/intake"]:::feat
  N28["features/invoices/invoices"]:::feat
  N29["features/onboarding/onboarding"]:::feat
  N30["features/reminders/reminders"]:::feat
  N31["features/settings/settings"]:::feat
  N32["features/settings/theme_settings"]:::feat
  N33["features/shell/shell"]:::feat
  N34["features/support/blocked"]:::feat
  N35["features/support/support"]:::feat
  N36["features/tickets/ticket_detail"]:::feat
  N37["features/warranty/warranty_page"]:::feat
  N38["main"]:::core
  N39["shared/charts/modern_charts"]:::shared
  N40["shared/data/holidays"]:::shared
  N41["shared/widgets/app_text"]:::shared
  N42["shared/widgets/data_table_pro"]:::shared
  N43["shared/widgets/hover_tile"]:::shared
  N44["shared/widgets/persian_number_field"]:::shared
  N45["shared/widgets/shamsi_calendar"]:::shared
  N46["shared/widgets/shamsi_date_field"]:::shared
  N47["shared/widgets/smart_data_table"]:::shared
  classDef svc fill:#dbe9ff,stroke:#3b6db5
  classDef feat fill:#e2f7e2,stroke:#3d9e4f
  classDef shared fill:#fff3d6,stroke:#c99a2e
  classDef data fill:#f2dcff,stroke:#8a54b5
  classDef core fill:#eee,stroke:#555
  N0 --> N1
  N0 --> N5
  N0 --> N7
  N0 --> N12
  N0 --> N15
  N0 --> N29
  N0 --> N33
  N0 --> N17
  N0 --> N34
  N4 --> N2
  N4 --> N3
  N5 --> N1
  N5 --> N3
  N5 --> N4
  N5 --> N9
  N5 --> N12
  N5 --> N13
  N5 --> N7
  N5 --> N15
  N5 --> N16
  N6 --> N3
  N6 --> N4
  N6 --> N18
  N6 --> N7
  N6 --> N14
  N6 --> N11
  N6 --> N15
  N6 --> N19
  N7 --> N2
  N7 --> N4
  N8 --> N1
  N8 --> N4
  N9 --> N4
  N11 --> N4
  N11 --> N19
  N12 --> N1
  N12 --> N4
  N12 --> N13
  N13 --> N1
  N13 --> N18
  N14 --> N1
  N14 --> N3
  N14 --> N18
  N15 --> N1
  N15 --> N2
  N15 --> N3
  N15 --> N4
  N16 --> N2
  N16 --> N4
  N17 --> N4
  N19 --> N2
  N19 --> N4
  N20 --> N6
  N21 --> N1
  N21 --> N3
  N21 --> N4
  N21 --> N18
  N21 --> N19
  N21 --> N36
  N22 --> N1
  N22 --> N3
  N22 --> N4
  N22 --> N8
  N22 --> N18
  N22 --> N40
  N22 --> N36
  N23 --> N3
  N23 --> N4
  N23 --> N18
  N23 --> N42
  N23 --> N36
  N24 --> N7
  N24 --> N16
  N24 --> N18
  N24 --> N42
  N24 --> N25
  N25 --> N16
  N25 --> N18
  N26 --> N4
  N26 --> N5
  N26 --> N11
  N26 --> N17
  N26 --> N18
  N26 --> N39
  N26 --> N41
  N27 --> N1
  N27 --> N3
  N27 --> N4
  N27 --> N9
  N27 --> N14
  N27 --> N15
  N27 --> N18
  N27 --> N44
  N27 --> N46
  N28 --> N3
  N28 --> N4
  N28 --> N18
  N28 --> N42
  N28 --> N36
  N29 --> N1
  N29 --> N4
  N29 --> N5
  N29 --> N9
  N29 --> N12
  N29 --> N13
  N29 --> N18
  N30 --> N1
  N30 --> N3
  N30 --> N4
  N30 --> N15
  N30 --> N18
  N30 --> N36
  N31 --> N1
  N31 --> N4
  N31 --> N5
  N31 --> N9
  N31 --> N18
  N32 --> N10
  N32 --> N17
  N32 --> N18
  N32 --> N41
  N32 --> N43
  N32 --> N39
  N33 --> N1
  N33 --> N17
  N33 --> N5
  N33 --> N18
  N33 --> N41
  N33 --> N43
  N33 --> N20
  N33 --> N21
  N33 --> N22
  N33 --> N23
  N33 --> N24
  N33 --> N26
  N33 --> N28
  N33 --> N27
  N33 --> N30
  N33 --> N31
  N33 --> N32
  N33 --> N35
  N33 --> N37
  N34 --> N1
  N35 --> N1
  N35 --> N18
  N36 --> N1
  N36 --> N3
  N36 --> N4
  N36 --> N15
  N36 --> N18
  N37 --> N4
  N37 --> N17
  N37 --> N18
  N37 --> N19
  N37 --> N41
  N37 --> N42
  N38 --> N0
  N38 --> N5
  N38 --> N10
  N38 --> N17
  N39 --> N17
  N39 --> N18
  N39 --> N41
  N41 --> N17
  N42 --> N4
  N42 --> N17
  N42 --> N18
  N42 --> N41
  N44 --> N18
  N45 --> N18
  N45 --> N40
  N46 --> N18
  N46 --> N45
  N47 --> N18
```

## فایل‌های بدون وابستگی ورودی (ورودی آزاد)

- lib/main.dart
- lib/shared/widgets/smart_data_table.dart
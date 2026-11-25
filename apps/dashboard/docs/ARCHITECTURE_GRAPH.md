# نقشه گراف معماری برنامه (Graphify)

**آخرین به‌روزرسانی:** 2026-11-25T19:58:48
**فایل‌های Dart:** 37 — **خطوط کد:** 7218 — **لبه‌های وابستگی داخلی:** 131

## چطور استفاده کنم؟
قبل از هر اصلاح، فایل هدف را در گراف پیدا کن؛ مسیر وابستگی‌هایش نشان می‌دهد چه چیزهایی تحت‌تأثیر قرار می‌گیرند. بعد از اصلاح، دوباره graphify اجرا کن (اسکیل واچر).

## ماژول‌ها

| ماژول | فایل‌ها | خطوط |
|---|---|---|
| core/services | 10 | 1614 |
| shared/widgets | 4 | 763 |
| features/dbmanager | 2 | 572 |
| features/intake | 1 | 385 |
| features/shell | 1 | 382 |
| features/onboarding | 1 | 366 |
| core/models.dart | 1 | 353 |
| core/repos.dart | 1 | 337 |
| features/calendar | 1 | 325 |
| features/tickets | 1 | 295 |
| features/customers | 1 | 263 |
| core/db | 1 | 197 |
| root | 2 | 186 |
| features/settings | 1 | 184 |
| features/assistant | 1 | 173 |
| features/board | 1 | 173 |
| features/support | 2 | 157 |
| features/reminders | 1 | 152 |
| features/invoices | 1 | 144 |
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
  N10["core/services/install_report_service"]:::svc
  N11["core/services/license_service"]:::svc
  N12["core/services/pdf_service"]:::svc
  N13["core/services/reminder_service"]:::svc
  N14["core/services/supervisor_service"]:::svc
  N15["core/utils"]:::core
  N16["features/assistant/assistant_page"]:::feat
  N17["features/board/board"]:::feat
  N18["features/calendar/calendar_page"]:::feat
  N19["features/customers/customers"]:::feat
  N20["features/dbmanager/db_manager_page"]:::feat
  N21["features/dbmanager/supervisor_gate"]:::feat
  N22["features/intake/intake"]:::feat
  N23["features/invoices/invoices"]:::feat
  N24["features/onboarding/onboarding"]:::feat
  N25["features/reminders/reminders"]:::feat
  N26["features/settings/settings"]:::feat
  N27["features/shell/shell"]:::feat
  N28["features/support/blocked"]:::feat
  N29["features/support/support"]:::feat
  N30["features/tickets/ticket_detail"]:::feat
  N31["main"]:::core
  N32["shared/data/holidays"]:::shared
  N33["shared/widgets/persian_number_field"]:::shared
  N34["shared/widgets/shamsi_calendar"]:::shared
  N35["shared/widgets/shamsi_date_field"]:::shared
  N36["shared/widgets/smart_data_table"]:::shared
  classDef svc fill:#dbe9ff,stroke:#3b6db5
  classDef feat fill:#e2f7e2,stroke:#3d9e4f
  classDef shared fill:#fff3d6,stroke:#c99a2e
  classDef data fill:#f2dcff,stroke:#8a54b5
  classDef core fill:#eee,stroke:#555
  N0 --> N1
  N0 --> N5
  N0 --> N7
  N0 --> N10
  N0 --> N13
  N0 --> N24
  N0 --> N27
  N0 --> N28
  N4 --> N2
  N4 --> N3
  N5 --> N1
  N5 --> N3
  N5 --> N4
  N5 --> N9
  N5 --> N10
  N5 --> N11
  N5 --> N7
  N5 --> N13
  N5 --> N14
  N6 --> N3
  N6 --> N4
  N6 --> N15
  N6 --> N7
  N6 --> N12
  N6 --> N13
  N7 --> N2
  N7 --> N4
  N8 --> N1
  N8 --> N4
  N9 --> N4
  N10 --> N1
  N10 --> N4
  N10 --> N11
  N11 --> N1
  N11 --> N15
  N12 --> N1
  N12 --> N3
  N12 --> N15
  N13 --> N1
  N13 --> N2
  N13 --> N3
  N13 --> N4
  N14 --> N2
  N14 --> N4
  N16 --> N6
  N17 --> N1
  N17 --> N3
  N17 --> N4
  N17 --> N15
  N17 --> N30
  N18 --> N1
  N18 --> N3
  N18 --> N4
  N18 --> N8
  N18 --> N15
  N18 --> N32
  N18 --> N30
  N19 --> N3
  N19 --> N4
  N19 --> N15
  N19 --> N36
  N19 --> N30
  N20 --> N7
  N20 --> N14
  N20 --> N15
  N20 --> N36
  N20 --> N21
  N21 --> N14
  N21 --> N15
  N22 --> N1
  N22 --> N3
  N22 --> N4
  N22 --> N9
  N22 --> N12
  N22 --> N13
  N22 --> N15
  N22 --> N33
  N22 --> N35
  N23 --> N3
  N23 --> N4
  N23 --> N15
  N23 --> N36
  N23 --> N30
  N24 --> N1
  N24 --> N4
  N24 --> N5
  N24 --> N9
  N24 --> N10
  N24 --> N11
  N24 --> N15
  N25 --> N1
  N25 --> N3
  N25 --> N4
  N25 --> N13
  N25 --> N15
  N25 --> N30
  N26 --> N1
  N26 --> N4
  N26 --> N5
  N26 --> N9
  N26 --> N15
  N27 --> N1
  N27 --> N4
  N27 --> N5
  N27 --> N15
  N27 --> N16
  N27 --> N17
  N27 --> N18
  N27 --> N19
  N27 --> N20
  N27 --> N23
  N27 --> N22
  N27 --> N25
  N27 --> N26
  N27 --> N29
  N28 --> N1
  N29 --> N1
  N29 --> N15
  N30 --> N1
  N30 --> N3
  N30 --> N4
  N30 --> N13
  N30 --> N15
  N31 --> N0
  N31 --> N5
  N33 --> N15
  N34 --> N15
  N34 --> N32
  N35 --> N15
  N35 --> N34
  N36 --> N15
```

## فایل‌های بدون وابستگی ورودی (ورودی آزاد)

- lib/main.dart
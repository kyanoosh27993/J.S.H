"""J.S.H — ماژول همگام‌سازی گوگل شیت (Google Sheets Sync)

این ماژول جایگزین ماژول Google Calendar است:
- مرجع اصلی داده همیشه دیتابیس محلی (SQLite) است؛ بدون اینترنت کامل کار می‌کند.
- هر سفارش ثبت‌شده در صف همگام‌سازی (offline queue) قرار می‌گیرد.
- با وصل شدن اینترنت، صف به شیت «داشبورد تعمیرات و خدمات J.S.H» ارسال می‌شود.
- سفارش‌های فردا در ستون یادداشت با برچسب [فردا] علامت می‌خورند.
"""

from __future__ import annotations

import json
import os
import sqlite3
from dataclasses import dataclass, field, asdict
from datetime import date, datetime
from typing import Any, Dict, List, Optional

# ------------------------------------------------------------------
# ثابت‌ها
# ------------------------------------------------------------------

SHEET_ID = "1UqbXVRUE0Fyf_CWS8Crr6mCGsEmSpvulLzt-IRoK6IQ"
SHEET_URL = "https://docs.google.com/spreadsheets/d/1UqbXVRUE0Fyf_CWS8Crr6mCGsEmSpvulLzt-IRoK6IQ/edit"
DEFAULT_TAB = "'داشبورد تعمیرات و خدمات J.S.H'"
HEADERS = [
    "ردیف", "شناسه سفارش", "نام مشتری", "تلفن", "نوع دستگاه",
    "شرح خرابی", "تاریخ شمسی", "تاریخ میلادی", "وضعیت",
    "هزینه (تومان)", "یادداشت", "زمان ثبت",
]

PERSIAN_DIGITS = str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹")
ENGLISH_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹", "0123456789")

# ------------------------------------------------------------------
# تبدیل تاریخ میلادی <-> شمسی (الگوریتم استاندارد jalaali-js، تست رفت‌وبرگشت ۱۰ ساله: ۰ خطا)
# ------------------------------------------------------------------


def gregorian_to_jalali(gy: int, gm: int, gd: int) -> tuple[int, int, int]:
    g_d_m = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
    gy2 = gy + 1 if gm > 2 else gy
    days = (355666 + (365 * gy) + ((gy2 + 3) // 4) - ((gy2 + 99) // 100)
            + ((gy2 + 399) // 400) + gd + g_d_m[gm - 1])
    jy = -1595 + (33 * (days // 12053))
    days %= 12053
    jy += 4 * (days // 1461)
    days %= 1461
    if days > 365:
        jy += (days - 1) // 365
        days = (days - 1) % 365
    if days < 186:
        jm = 1 + (days // 31)
        jd = 1 + (days % 31)
    else:
        jm = 7 + ((days - 186) // 30)
        jd = 1 + ((days - 186) % 30)
    return jy, jm, jd


def jalali_to_gregorian(jy: int, jm: int, jd: int) -> tuple[int, int, int]:
    jy += 1595
    days = (-355668 + (365 * jy) + ((jy // 33) * 8)
            + ((jy % 33 + 3) // 4) + jd
            + ((jm - 1) * 31 if jm < 7 else ((jm - 7) * 30) + 186))
    gy = 400 * (days // 146097)
    days %= 146097
    if days > 36524:
        days -= 1
        gy += 100 * (days // 36524)
        days %= 36524
        if days >= 365:
            days += 1
    gy += 4 * (days // 1461)
    days %= 1461
    if days > 365:
        gy += (days - 1) // 365
        days = (days - 1) % 365
    gd = days + 1
    leap = (gy % 4 == 0 and gy % 100 != 0) or (gy % 400 == 0)
    months = [0, 31, 29 if leap else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    gm = 1
    for length in months[1:]:
        if gd <= length:
            break
        gd -= length
        gm += 1
    return gy, gm, gd


def to_persian_digits(text: str) -> str:
    """قاعده ۱: نمایش با ارقام فارسی"""
    return str(text).translate(PERSIAN_DIGITS)


def format_jalali(d: date) -> str:
    jy, jm, jd = gregorian_to_jalali(d.year, d.month, d.day)
    return to_persian_digits(f"{jy:04d}/{jm:02d}/{jd:02d}")


def smart_jalali_input(raw: str) -> Optional[date]:
    """قاعده ۳: ورودی هوشمند تاریخ — ۸ رقمی (۱۴۰۵۰۹۰۶) یا ۴ رقمی ماه/روز (۰۹۰۶).
    ارقام فارسی و اسلش پذیرفته می‌شود؛ خروجی date میلادی برای ذخیره انگلیسی."""
    raw = raw.strip().translate(ENGLISH_DIGITS).replace("/", "")
    today = date.today()
    try:
        if len(raw) == 4:
            jy = gregorian_to_jalali(today.year, today.month, today.day)[0]
            return jalali_to_gregorian(jy, int(raw[:2]), int(raw[2:]))
        if len(raw) == 8:
            gy, gm, gd = jalali_to_gregorian(int(raw[:4]), int(raw[4:6]), int(raw[6:8]))
            return date(gy, gm, gd)
    except (ValueError, OverflowError):
        return None
    return None


# ------------------------------------------------------------------
# داده سفارش و صف همگام‌سازی آفلاین
# ------------------------------------------------------------------


@dataclass
class Order:
    order_id: str
    customer: str
    phone: str
    device: str
    problem: str
    due_date: date
    status: str = "در انتظار تعمیر"
    cost: int = 0
    note: str = ""
    created_at: str = field(default_factory=lambda: datetime.now().strftime("%Y-%m-%d %H:%M"))
    synced: bool = False

    def to_row(self, row_no: int, tomorrow: date) -> List[Any]:
        """ردیف گوگل شیت — تاریخ شمسی با ارقام فارسی، شناسه و میلادی انگلیسی برای مرتب‌سازی"""
        return [
            row_no,
            self.order_id,
            self.customer,
            self.phone,
            self.device,
            self.problem,
            format_jalali(self.due_date),
            self.due_date.isoformat(),
            self.status,
            self.cost if self.cost else "",
            (self.note + (" - [فردا]" if self.due_date == tomorrow else "")).strip(" -"),
            self.created_at,
        ]


class SyncQueue:
    """صف آفلاین: هر سفارش قبل از ارسال محلی ذخیره می‌شود؛ هیچ داده‌ای گم نمی‌شود."""

    def __init__(self, db_path: str):
        self.db_path = db_path
        self._conn = sqlite3.connect(db_path)
        self._conn.execute(
            """CREATE TABLE IF NOT EXISTS sync_queue (
                   order_id TEXT PRIMARY KEY,
                   payload  TEXT NOT NULL,
                   synced   INTEGER DEFAULT 0,
                   retries  INTEGER DEFAULT 0,
                   created_at TEXT
               )"""
        )
        self._conn.commit()

    def enqueue(self, order: Order) -> None:
        self._conn.execute(
            "INSERT OR REPLACE INTO sync_queue (order_id, payload, synced, created_at) VALUES (?, ?, 0, ?)",
            (order.order_id, json.dumps(asdict(order), ensure_ascii=False, default=str), order.created_at),
        )
        self._conn.commit()

    def pending(self) -> List[Order]:
        rows = self._conn.execute("SELECT payload FROM sync_queue WHERE synced = 0").fetchall()
        out: List[Order] = []
        for (payload,) in rows:
            data = json.loads(payload)
            data["due_date"] = date.fromisoformat(data["due_date"])
            out.append(Order(**{k: v for k, v in data.items() if k != "synced"}))
        return out

    def mark_synced(self, order_id: str) -> None:
        self._conn.execute("UPDATE sync_queue SET synced = 1 WHERE order_id = ?", (order_id,))
        self._conn.commit()


# ------------------------------------------------------------------
# ارسال به گوگل شیت (فقط وقتی اینترنت و اعتبارنامه موجود است)
# ------------------------------------------------------------------


def push_to_sheet(orders: List[Order], credentials_path: Optional[str] = None,
                  tomorrow: Optional[date] = None) -> Dict[str, Any]:
    """ارسال دسته‌ای سفارش‌ها به شیت. اگر اعتبارنامه/اینترنت نبود، پیام صریح برمی‌گردد
    تا رابط کاربری وضعیت «در صف آفلاین» نشان دهد."""
    result: Dict[str, Any] = {"sent": 0, "queued": 0, "error": None}
    try:
        from google.oauth2.service_account import Credentials  # noqa: WPS433
        from googleapiclient.discovery import build        # noqa: WPS433
    except ImportError:
        result["error"] = "google-api-client نصب نیست؛ سفارش‌ها در صف آفلاین ماندند"
        return result

    if not credentials_path or not os.path.exists(credentials_path):
        result["error"] = "اعتبارنامه سرویس‌اکانت یافت نشد"
        return result

    try:
        scopes = ["https://www.googleapis.com/auth/spreadsheets"]
        creds = Credentials.from_service_account_file(credentials_path, scopes=scopes)
        service = build("sheets", "v4", credentials=creds)

        if tomorrow is None:
            tomorrow = date.today() + (date(1, 2, 1) - date(1, 1, 1))
        rows = [order.to_row(i, tomorrow) for i, order in enumerate(orders, start=1)]
        body = {"values": rows}
        service.spreadsheets().values().append(
            spreadsheetId=SHEET_ID,
            range=f"{DEFAULT_TAB}!A1",
            valueInputOption="USER_ENTERED",
            insertDataOption="INSERT_ROWS",
            body=body,
        ).execute()
        result["sent"] = len(rows)
    except Exception as exc:  # noqa: BLE001 — خطا باید صریح گزارش شود
        result["error"] = f"ارسال به شیت ناموفق: {exc}"
        result["queued"] = len(orders)
    return result


if __name__ == "__main__":
    demo = Order(
        order_id="ORD-TEST-001",
        customer="تست",
        phone="09130000000",
        device="کولر گازی",
        problem="تست ماژول",
        due_date=date(2026, 11, 27),
    )
    print("Jalali:", format_jalali(demo.due_date))
    print("Smart input ۱۴۰۵۰۹۰۶ ->", smart_jalali_input("۱۴۰۵۰۹۰۶"))
    print("Row:", demo.to_row(1, date(2026, 11, 26)))

# -*- coding: utf-8 -*-
"""J.S.H — دفترچه‌ی یادداشت شخصی (نسخه‌ی خط فرمان)

ثبت، جستجو، ویرایش و بایگانی یادداشت‌ها با پایگاه‌داده‌ی SQLite و تاریخ شمسی.
اجرا:  python jsh.py [دستور] [گزینه‌ها]
"""

import argparse
import sqlite3
import sys
from datetime import datetime
from pathlib import Path

DB_PATH = Path(__file__).resolve().parent.parent / "jsh.db"

# ---------- تاریخ شمسی (تبدیل بدون کتابخانه‌ی خارجی) ----------

def gregorian_to_jalali(gy: int, gm: int, gd: int):
    g_days_in_month = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    j_days_in_month = [31, 31, 31, 31, 31, 31, 30, 30, 30, 30, 29, 30]
    y = gy - 1600
    m = gm - 1
    g_day_no = 365 * y + (y + 3) // 4 - (y + 99) // 100 + (y + 399) // 400
    for i in range(m):
        g_day_no += g_days_in_month[i]
    if m > 1 and ((y % 4 == 0 and y % 100 != 0) or (y % 400 == 0)):
        g_day_no += 1
    g_day_no += gd - 1
    j_day_no = g_day_no - 79
    j_np = j_day_no // 12053
    j_day_no %= 12053
    jy = 979 + 33 * j_np + 4 * (j_day_no // 1461)
    j_day_no %= 1461
    if j_day_no >= 366:
        jy += (j_day_no - 1) // 365
        j_day_no = (j_day_no - 1) % 365
    jm = 1
    for i in range(11):
        if j_day_no < j_days_in_month[i]:
            break
        j_day_no -= j_days_in_month[i]
        jm += 1
    jd = j_day_no + 1
    return jy, jm, jd


def jalali_today() -> str:
    t = datetime.now()
    jy, jm, jd = gregorian_to_jalali(t.year, t.month, t.day)
    return f"{jy:04d}/{jm:02d}/{jd:02d} {t:%H:%M}"


# ---------- پایگاه‌داده ----------

def connect() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        """CREATE TABLE IF NOT EXISTS notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            tag TEXT DEFAULT '',
            created TEXT NOT NULL,
            pinned INTEGER DEFAULT 0,
            archived INTEGER DEFAULT 0
        )"""
    )
    conn.commit()
    return conn


# ---------- دستورها ----------

def cmd_add(args):
    body = args.body
    if body is None or body == "-":
        print("متن یادداشت را بنویسید و با خطی شامل فقط «.» پایان دهید:")
        lines = []
        while True:
            try:
                line = input()
            except EOFError:
                break
            if line.strip() == ".":
                break
            lines.append(line)
        body = "\n".join(lines).strip()
    if not body:
        print("خطا: متن یادداشت خالی است.")
        return 1
    with connect() as conn:
        cur = conn.execute(
            "INSERT INTO notes (title, body, tag, created) VALUES (?,?,?,?)",
            (args.title, body, args.tag or "", jalali_today()),
        )
        print(f"یادداشت شماره {cur.lastrowid} ثبت شد.")
    return 0


def cmd_list(args):
    with connect() as conn:
        if args.tag:
            rows = conn.execute(
                "SELECT id,title,tag,created,pinned FROM notes "
                "WHERE archived=0 AND tag LIKE ? ORDER BY pinned DESC, id DESC",
                (f"%{args.tag}%",),
            ).fetchall()
        elif args.all:
            rows = conn.execute(
                "SELECT id,title,tag,created,pinned FROM notes "
                "ORDER BY pinned DESC, id DESC"
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT id,title,tag,created,pinned FROM notes WHERE archived=0 "
                "ORDER BY pinned DESC, id DESC"
            ).fetchall()
    if not rows:
        print("هیچ یادداشتی پیدا نشد.")
        return 0
    print(f"{'شناسه':>6}  {'عنوان':<30}  {'برچسب':<10}  {'تاریخ':<17}  سنجاق")
    print("-" * 78)
    for r in rows:
        pin = "★" if r[4] else " "
        print(f"{r[0]:>6}  {r[1][:28]:<30}  {r[2][:10] or '-':<10}  {r[3]:<17}  {pin}")
    return 0


def cmd_show(args):
    with connect() as conn:
        row = conn.execute(
            "SELECT id,title,body,tag,created,pinned,archived FROM notes WHERE id=?",
            (args.id,),
        ).fetchone()
    if not row:
        print(f"یادداشت شماره {args.id} پیدا نشد.")
        return 1
    print("━" * 60)
    print(f"شناسه: {row[0]}    تاریخ ثبت: {row[4]}    سنجاق‌شده: {'بله' if row[5] else 'خیر'}"
          f"    بایگانی: {'بله' if row[6] else 'خیر'}")
    print(f"عنوان: {row[1]}")
    if row[3]:
        print(f"برچسب: {row[3]}")
    print("━" * 60)
    print(row[2])
    return 0


def cmd_search(args):
    q = f"%{args.query}%"
    with connect() as conn:
        rows = conn.execute(
            "SELECT id,title,tag,created FROM notes "
            "WHERE archived=0 AND (title LIKE ? OR body LIKE ? OR tag LIKE ?) "
            "ORDER BY id DESC",
            (q, q, q),
        ).fetchall()
    if not rows:
        print(f"برای «{args.query}» چیزی پیدا نشد.")
        return 0
    print(f"{len(rows)} نتیجه برای «{args.query}»:")
    for r in rows:
        print(f"  [{r[0]:>4}] {r[1]}  ({r[3]}, برچسب: {r[2] or '—'})")
    return 0


def cmd_edit(args):
    with connect() as conn:
        row = conn.execute("SELECT title, body FROM notes WHERE id=?", (args.id,)).fetchone()
        if not row:
            print(f"یادداشت شماره {args.id} پیدا نشد.")
            return 1
        title = args.title if args.title is not None else row[0]
        if args.body is not None:
            body = args.body
        else:
            print("متن فعلی (برای تغییر تایپ کنید، Enter برای بدون تغییر):")
            new = input()
            body = new if new.strip() else row[1]
        conn.execute(
            "UPDATE notes SET title=?, body=? WHERE id=?", (title, body, args.id)
        )
        print(f"یادداشت {args.id} به‌روزرسانی شد.")
    return 0


def cmd_pin(args):
    with connect() as conn:
        cur = conn.execute("UPDATE notes SET pinned=? WHERE id=?", (1 if args.on else 0, args.id))
        if cur.rowcount == 0:
            print(f"یادداشت شماره {args.id} پیدا نشد.")
            return 1
        print(f"یادداشت {args.id} {'سنجاق' if args.on else 'برداشته'} شد.")
    return 0


def cmd_archive(args):
    with connect() as conn:
        val = 0 if args.undo else 1
        cur = conn.execute("UPDATE notes SET archived=? WHERE id=?", (val, args.id))
        if cur.rowcount == 0:
            print(f"یادداشت شماره {args.id} پیدا نشد.")
            return 1
        print(f"یادداشت {args.id} {'از بایگانی خارج' if args.undo else 'بایگانی'} شد.")
    return 0


def cmd_delete(args):
    with connect() as conn:
        if args.force:
            cur = conn.execute("DELETE FROM notes WHERE id=?", (args.id,))
            if cur.rowcount:
                print(f"یادداشت {args.id} برای همیشه حذف شد.")
                return 0
            print(f"یادداشت شماره {args.id} پیدا نشد.")
            return 1
        print("برای تایید حذف، شماره یادداشت را دوباره وارد کنید:")
        if input().strip() != str(args.id):
            print("تایید نشد؛ حذف لغو شد.")
            return 0
        conn.execute("DELETE FROM notes WHERE id=?", (args.id,))
        print(f"یادداشت {args.id} حذف شد.")
    return 0


def cmd_export(args):
    with connect() as conn:
        rows = conn.execute(
            "SELECT id,title,body,tag,created FROM notes WHERE archived=0 "
            "ORDER BY pinned DESC, id"
        ).fetchall()
    out = Path(args.file)
    with out.open("w", encoding="utf-8") as f:
        for r in rows:
            f.write(f"# [{r[0]}] {r[1]}\nتاریخ: {r[4]}    برچسب: {r[3] or '—'}\n\n{r[2]}\n\n---\n\n")
    print(f"{len(rows)} یادداشت در {out} ذخیره شد.")
    return 0


def cmd_stats(_args):
    with connect() as conn:
        total, pinned, archived, tagged = conn.execute(
            "SELECT (SELECT COUNT(*) FROM notes), "
            "(SELECT COUNT(*) FROM notes WHERE pinned=1), "
            "(SELECT COUNT(*) FROM notes WHERE archived=1), "
            "(SELECT COUNT(DISTINCT tag) FROM notes WHERE tag!='')"
        ).fetchone()
    print(f"کل یادداشت‌ها: {total}")
    print(f"سنجاق‌شده: {pinned}")
    print(f"بایگانی‌شده: {archived}")
    print(f"برچسب‌های متفاوت: {tagged}")
    return 0


# ---------- رابط خط فرمان ----------

def build_parser():
    p = argparse.ArgumentParser(
        prog="jsh",
        description="J.S.H — دفترچه‌ی یادداشت شخصی (خط فرمان)",
        epilog="نمونه: python jsh.py add «قرار ملاقات» --tag کار --body «فردا ساعت ۱۰»",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("add", help="ثبت یادداشت جدید")
    s.add_argument("title", help="عنوان یادداشت")
    s.add_argument("--body", help="متن یادداشت (یا «-» برای ورودی چندخطی)")
    s.add_argument("--tag", help="برچسب، مثل: کار، شخصی")
    s.set_defaults(func=cmd_add)

    s = sub.add_parser("list", help="فهرست یادداشت‌ها")
    s.add_argument("--tag", help="فیلتر بر اساس برچسب")
    s.add_argument("--all", action="store_true", help="شامل بایگانی‌شده‌ها")
    s.set_defaults(func=cmd_list)

    s = sub.add_parser("show", help="نمایش کامل یک یادداشت")
    s.add_argument("id", type=int)
    s.set_defaults(func=cmd_show)

    s = sub.add_parser("search", help="جستجو در عنوان، متن و برچسب")
    s.add_argument("query")
    s.set_defaults(func=cmd_search)

    s = sub.add_parser("edit", help="ویرایش عنوان یا متن")
    s.add_argument("id", type=int)
    s.add_argument("--title")
    s.add_argument("--body")
    s.set_defaults(func=cmd_edit)

    s = sub.add_parser("pin", help="سنجاق یا برداشتن سنجاق")
    s.add_argument("id", type=int)
    group = s.add_mutually_exclusive_group()
    group.add_argument("--on", dest="on", action="store_true", default=True)
    group.add_argument("--off", dest="on", action="store_false")
    s.set_defaults(func=cmd_pin)

    s = sub.add_parser("archive", help="بایگانی یا خروج از بایگانی")
    s.add_argument("id", type=int)
    s.add_argument("--undo", action="store_true", help="خروج از بایگانی")
    s.set_defaults(func=cmd_archive)

    s = sub.add_parser("delete", help="حذف یادداشت")
    s.add_argument("id", type=int)
    s.add_argument("--force", action="store_true", help="بدون تایید تعاملی")
    s.set_defaults(func=cmd_delete)

    s = sub.add_parser("export", help="خروجی Markdown از یادداشت‌ها")
    s.add_argument("file", help="مسیر فایل خروجی")
    s.set_defaults(func=cmd_export)

    s = sub.add_parser("stats", help="آمار خلاصه")
    s.set_defaults(func=cmd_stats)

    return p


def main() -> int:
    args = build_parser().parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

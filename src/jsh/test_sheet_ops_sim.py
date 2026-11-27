"""شبیه‌سازی کامل پروتکل همگام‌سازی Google Sheet — اعتبارسنجی منطق ویرایش/حذف

این تست همان ماشین حالت Dart (sheet_sync_service.dart) و همان معناشناسی
Apps Script (apps_script_sheet_sync.js) را شبیه‌سازی و سناریوهای واقعی را
اجرا می‌کند: افزودن → ویرایش → حذف → حالت‌های آفلاین و آشتی‌سازی.
"""
import json
from datetime import date

# ---------------------------------------------------------------
# شبیه‌سازی شیت — همان معناشناسی Apps Script
# ---------------------------------------------------------------

class FakeSheet:
    def __init__(self):
        self.rows = [["ردیف", "شناسه سفارش", "نام مشتری", "تلفن", "دستگاه",
                      "شرح خرابی", "تاریخ شمسی", "تاریخ میلادی", "وضعیت",
                      "هزینه (تومان)", "یادداشت", "زمان ثبت"]]

    def get_last_row(self):
        return len(self.rows)

    def find_row_by_code(self, code):
        for i, r in enumerate(self.rows[1:], start=2):
            if str(r[1]).strip() == str(code).strip():
                return i
        return -1

    def append_row(self, row):
        self.rows.append(list(row))

    def set_row(self, sheet_row_no, row):
        self.rows[sheet_row_no - 1] = list(row)

    def delete_row(self, sheet_row_no):
        del self.rows[sheet_row_no - 1]

    def renumber(self):
        for i, r in enumerate(self.rows[1:], start=1):
            r[0] = i

    def codes(self):
        return [r[1] for r in self.rows[1:]]


def apply_op(sheet, op):
    """آینه دقیق applyOp در Apps Script"""
    row = op.get("row", [])
    if op["op"] == "append":
        if sheet.find_row_by_code(op["code"]) != -1:
            return  # تکراری — به‌جای append، ویرایش است
        out = list(row)
        out[0] = sheet.get_last_row()
        sheet.append_row(out)
    elif op["op"] == "update":
        r = sheet.find_row_by_code(op["code"])
        if r == -1:
            out = list(row)
            out[0] = sheet.get_last_row()
            sheet.append_row(out)
            return
        out = list(row)
        out[0] = r - 1
        sheet.set_row(r, out)
    elif op["op"] == "delete":
        r = sheet.find_row_by_code(op["code"])
        if r != -1:
            sheet.delete_row(r)
    else:
        raise ValueError(f"عملیات ناشناخته: {op['op']}")


# ---------------------------------------------------------------
# ماشین حالت صف — آینه sheet_sync_service.dart
# ---------------------------------------------------------------

class Outbox:
    """صف آفلاین — code -> (op, synced, row)"""
    APPEND, UPDATE, DELETE = "append", "update", "delete"

    def __init__(self):
        self.items = {}

    def enqueue(self, code, op, row):
        self.items[code] = [op, 0, list(row)]

    def on_ticket_changed(self, code, current_row):
        if code not in self.items:
            self.enqueue(code, self.APPEND, current_row)
            return
        op, synced, _ = self.items[code]
        if op == self.DELETE:
            self.enqueue(code, self.UPDATE, current_row)
        elif synced == 1:
            self.enqueue(code, self.UPDATE, current_row)
        else:
            self.enqueue(code, op, current_row)

    def on_ticket_deleted(self, code):
        if code not in self.items:
            return  # هرگز به شیت نرسیده
        op, synced, _ = self.items[code]
        if op == self.APPEND and synced == 0:
            del self.items[code]  # فقط در صف بود → خود صف حذف می‌شود
        else:
            self.enqueue(code, self.DELETE, [0, code])

    def flush(self, sheet):
        """ارسال همه در انتظارها به endpoint (شبیه‌سازی POST)"""
        ops = [{"op": op, "code": c, "row": row}
               for c, (op, synced, row) in self.items.items() if synced == 0]
        for o in ops:
            apply_op(sheet, o)
        for code in [o["code"] for o in ops]:
            self.items[code][1] = 1
        return len(ops)

    def rows_equal_except_row_no(self, a, b):
        return all(str(a[i] if i < len(a) else "") ==
                   str(b[i] if i < len(b) else "")
                   for i in range(1, 12))

    def reconcile(self, sheet, tickets):
        """آشتی‌سازی pushAll — کشف اختلاف بانک با شیت"""
        changed = 0
        for code, row in tickets.items():
            st = self.items.get(code)
            if st is None:
                self.enqueue(code, self.APPEND, row)
                changed += 1
            else:
                op, synced, old = st
                if synced == 1:
                    if not self.rows_equal_except_row_no(old, row):
                        self.enqueue(code, self.UPDATE, row)
                        changed += 1
                elif op == self.DELETE:
                    self.enqueue(code, self.UPDATE, row)
                    changed += 1
                else:
                    self.enqueue(code, op, row)
        return changed


# ---------------------------------------------------------------
# سناریوهای واقعی
# ---------------------------------------------------------------

def make_row(code, name, status, phone="09131234567"):
    return [0, code, name, f"'{phone}", "iPhone 13", "مشکل صفحه",
            "۱۴۰۵/۰۹/۰۶", "2026-11-27", status, "۲,۵۰۰,۰۰۰", "", "2026-11-26"]


fails = []


def check(name, cond):
    print(("✓ " if cond else "✗ FAIL ") + name)
    if not cond:
        fails.append(name)


sheet = FakeSheet()
ob = Outbox()

# ۱) افزودن دو سفارش → دو ردیف
ob.on_ticket_changed("T-1", make_row("T-1", "علی", "ثبت شده"))
ob.on_ticket_changed("T-2", make_row("T-2", "مریم", "تعمیر"))
n = ob.flush(sheet)
check("افزودن دو سفارش → دو ردیف در شیت", n == 2 and sheet.codes() == ["T-1", "T-2"])
check("شماره‌گذاری ردیف‌ها پیوسته", [r[0] for r in sheet.rows[1:]] == [1, 2])

# ۲) ویرایش T-1 → ردیف شیت به‌روز می‌شود (نه ردیف جدید)
ob.on_ticket_changed("T-1", make_row("T-1", "علی", "تحویل شده"))
n = ob.flush(sheet)
check("ویرایش → یک عملیات update", n == 1)
check("وضعیت ویرایش‌شده در شیت", sheet.rows[1][8] == "تحویل شده")
check("ردیف تکراری ساخته نشد", sheet.codes() == ["T-1", "T-2"] and len(sheet.rows) == 3)
check("شماره ردیف ویرایش‌شده با موقعیت فعلی هم‌خوان", sheet.rows[1][0] == 1)

# ۳) حذف T-2 → ردیف از شیت حذف و شماره‌ها اصلاح می‌شوند
ob.on_ticket_deleted("T-2")
n = ob.flush(sheet)
check("حذف → ردیف از شیت پاک شد", sheet.codes() == ["T-1"])
check("بازشماری بعد از حذف", [r[0] for r in sheet.rows[1:]] == [1])

# ۴) آفلاین: سفارش تازه صف می‌شود، دو بار ویرایش → فقط یک append با آخرین داده
ob.on_ticket_changed("T-3", make_row("T-3", "رضا", "ثبت شده"))
ob.on_ticket_changed("T-3", make_row("T-3", "رضا", "تعمیر"))
ob.on_ticket_changed("T-3", make_row("T-3", "رضا", "آماده"))
pending = [c for c, (op, s, _) in ob.items.items() if s == 0]
check("ادغام رویدادها → فقط یک عملیات در صف", pending == ["T-3"])
n = ob.flush(sheet)
check("فلاش → یک append با آخرین وضعیت", n == 1 and sheet.rows[-1][8] == "آماده")

# ۵) حذف سفارشی که هنوز به شیت نرسیده → کل ورودی صف پاک می‌شود، شیت دست‌نخورده
before = len(sheet.rows)
ob.on_ticket_changed("T-4", make_row("T-4", "زهرا", "ثبت شده"))
ob.on_ticket_deleted("T-4")
n = ob.flush(sheet)
check("حذفِ در-انتظار → صف خالی و شیت تغییر نکرد",
      n == 0 and "T-4" not in ob.items and len(sheet.rows) == before and "T-4" not in sheet.codes())

# ۶) حذف سفارش همگام‌شده → delete واقعی از شیت
ob.on_ticket_deleted("T-3")
n = ob.flush(sheet)
check("حذف همگام‌شده → ردیف از شیت پاک شد", n == 1 and sheet.codes() == ["T-1"])

# ۷) سفارش بعد از صف‌شدن حذف، دوباره ساخته می‌شود → update نه append تکراری
ob.on_ticket_deleted("T-1")            # هنوز فلاش نشده — delete در صف
ob.on_ticket_changed("T-1", make_row("T-1", "علی", "بازگشایی"))
check("حذف+ساخت مجدد → عملیات update", ob.items["T-1"][0] == "update")
n = ob.flush(sheet)
check("update بعد از بازگشایی → ردیف با وضعیت جدید",
      sheet.codes() == ["T-1"] and sheet.rows[1][8] == "بازگشایی")

# ۸) آشتی‌سازی: ردیف شیت دستی/از مسیر دیگری تغییر کرده → pushAll اختلاف را می‌یابد
ob.items["T-1"] = [Outbox.APPEND, 1, make_row("T-1", "علی", "ثبت شده")]  # وضعیت قدیم در صف
changed = ob.reconcile(sheet, {"T-1": make_row("T-1", "علی", "تحویل شده")})
check("آشتی‌سازی → اختلاف کشف و صف شد", changed == 1 and ob.items["T-1"][0] == "update")
n = ob.flush(sheet)
check("فلاش آشتی‌سازی → شیت هم‌سان با بانک", sheet.rows[1][8] == "تحویل شده")

# ۹) idempotency: عملیات تکراری append برای کد موجود → ردیف تکراری نمی‌سازد
apply_op(sheet, {"op": "append", "code": "T-1", "row": make_row("T-1", "علی", "ثبت شده")})
check("append تکراری → شیت تغییر نکرد", sheet.codes() == ["T-1"] and len(sheet.rows) == 2)

# ۱۰) update برای کد غایب → append امن (بازیابی خودکار)
apply_op(sheet, {"op": "update", "code": "T-9", "row": make_row("T-9", "سام", "ثبت شده")})
check("update کد غایب → افزودن امن", sheet.codes() == ["T-1", "T-9"])

print()
if fails:
    raise SystemExit(f"{len(fails)} سناریو شکست خورد: {fails}")
print("همه ۱۰ سناریو سبز — پروتکل ویرایش/حذف تأیید شد ✓")

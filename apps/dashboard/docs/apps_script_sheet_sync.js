/**
 * J.S.H — Apps Script Web App همگام‌سازی Google Sheet
 * ================================================================
 *
 * این اسکریپت به شیت «داشبورد تعمیرات و خدمات J.S.H» وصل می‌شود و
 * عملیات افزودن / ویرایش / حذف ردیف را که از برنامه می‌رسد اعمال می‌کند.
 * کلید تطبیق ردیف‌ها = ستون «شناسه سفارش» (ستون B).
 *
 * ── راهنمای دیپلوی (یک بار، حدود ۲ دقیقه) ─────────────────────────
 * ۱. شیت را باز کنید: Extensions → Apps Script
 * ۲. محتوای این فایل را در Code.gs جای‌گذاری و ذخیره کنید
 * ۳. Deploy → New deployment → Type: Web app
 *      • Execute as: Me (نفس شما)
 *      • Who has access: Anyone        ← برای فراخوانی از برنامه لازم است
 * ۴. آدرس Web App (به شکل https://script.google.com/macros/s/.../exec)
 *    را در برنامه، بخش تنظیمات → همگام‌سازی شیت وارد کنید.
 * ۵. هر بار تغییر در کد → Deploy → Manage deployments → Edit → New version
 *
 * امنیت: هیچ کلید یا توکنی داخل برنامه نیست؛ endpoint فقط عملیات
 * سفارش را اعمال می‌کند و پاسخ JSON می‌دهد.
 */

const SHEET_ID = '1UqbXVRUE0Fyf_CWS8Crr6mCGsEmSpvulLzt-IRoK6IQ';

/** health check — در مرورگر باز کنید: باید {"ok":true} ببینید */
function doGet() {
  return ContentService.createTextOutput(JSON.stringify({
    ok: true,
    service: 'J.S.H sheet sync',
    time: new Date().toISOString(),
  })).setMimeType(ContentService.MimeType.JSON);
}

/** نقطه ورود برنامه — بدنه: {tab, sheetId, headers, ops:[{op,code,row}]} */
function doPost(e) {
  const lock = LockService.getScriptLock();
  lock.waitLock(30000); // جلوگیری از تداخل دو ارسال هم‌زمان
  try {
    const body = JSON.parse(e.postData.contents);
    const ss = SpreadsheetApp.openById(SHEET_ID);
    let sheet = (body.tab && ss.getSheetByName(body.tab)) || ss.getSheets()[0];

    // اگر شیت خالی است، سرستون‌ها را بساز (خروجی برنامه مرجع است)
    if (sheet.getLastRow() === 0 && body.headers) {
      sheet.getRange(1, 1, 1, body.headers.length).setValues([body.headers]);
      sheet.setFrozenRows(1);
    }

    const results = { ok: true, applied: 0, errors: [] };
    for (const op of (body.ops || [])) {
      try {
        applyOp(sheet, op);
        results.applied++;
      } catch (err) {
        results.ok = false;
        results.errors.push({ code: op.code, message: String(err) });
      }
    }
    if (results.applied > 0) renumber(sheet);
    return ContentService.createTextOutput(JSON.stringify(results))
        .setMimeType(ContentService.MimeType.JSON);
  } catch (err) {
    return ContentService.createTextOutput(JSON.stringify({
      ok: false, error: String(err),
    })).setMimeType(ContentService.MimeType.JSON);
  } finally {
    lock.releaseLock();
  }
}

/** یافتن شماره ردیف شیت با کلید «شناسه سفارش» (ستون B) — -۱ = نبود */
function findRowByCode(sheet, code) {
  const last = sheet.getLastRow();
  if (last < 2) return -1;
  const codes = sheet.getRange(2, 2, last - 1, 1).getValues();
  for (let i = 0; i < codes.length; i++) {
    if (String(codes[i][0]).trim() === String(code).trim()) return i + 2;
  }
  return -1;
}

/** اعمال یک عملیات: append / update / delete */
function applyOp(sheet, op) {
  const row = op.row || [];
  if (op.op === 'append') {
    if (findRowByCode(sheet, op.code) !== -1) {
      return; // تکراری — به‌جای append، ویرایش است
    }
    const out = row.slice();
    out[0] = sheet.getLastRow(); // شماره نمایشی بعدی (هدر = ردیف ۱)
    sheet.appendRow(out);
  } else if (op.op === 'update') {
    const r = findRowByCode(sheet, op.code);
    if (r === -1) {
      // ردیف در شیت نبود (مثلاً قبلاً دستی حذف شده) → افزودن مجدد
      const out = row.slice();
      out[0] = sheet.getLastRow();
      sheet.appendRow(out);
      return;
    }
    const out = row.slice();
    out[0] = r - 1; // شماره نمایشی متناظر با موقعیت فعلی
    sheet.getRange(r, 1, 1, out.length).setValues([out]);
  } else if (op.op === 'delete') {
    const r = findRowByCode(sheet, op.code);
    if (r !== -1) sheet.deleteRow(r);
    // یافت نشد = قبلاً حذف شده؛ بدون خطا (idempotent)
  } else {
    throw new Error('عملیات ناشناخته: ' + op.op);
  }
}

/** بازشماری ستون «ردیف» (A) بعد از تغییرات تا شماره‌ها پیوسته بمانند */
function renumber(sheet) {
  const last = sheet.getLastRow();
  if (last < 2) return;
  const vals = sheet.getRange(2, 1, last - 1, 1).getValues();
  for (let i = 0; i < vals.length; i++) vals[i][0] = i + 1;
  sheet.getRange(2, 1, last - 1, 1).setValues(vals);
}

/** تست دستی از داخل ادیتور Apps Script (Run ▶) — برای اطمینان از سلامت */
function selfTest() {
  const ss = SpreadsheetApp.openById(SHEET_ID);
  const sheet = ss.getSheets()[0];
  const testOp = {
    op: 'update',
    code: 'SELF-TEST-' + Date.now(),
    row: [1, 'SELF-TEST-' + Date.now(), 'تست داخلی', '', '', '',
          '', '', '', '', '', new Date().toISOString()],
  };
  applyOp(sheet, { op: 'append', code: testOp.code, row: testOp.row });
  applyOp(sheet, { op: 'delete', code: testOp.code, row: testOp.row });
  renumber(sheet);
  Logger.log('selfTest OK — ردیف تستی ساخته و حذف شد');
}

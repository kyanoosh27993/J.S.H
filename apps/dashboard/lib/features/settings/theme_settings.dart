/// تم و ظاهر — شخصی‌سازی کامل با ریز جزئیات (قاعده بازطراحی)
/// سه تم پیش‌فرض + رنگ تاکیدی + گردی + فونت متن/اعداد ویندوز + اندازه و چگالی
/// + انیمیشن‌ها + فرمان سراسری shrink-to-fit + نمودارها در داشبورد
library;

import 'package:flutter/material.dart';

import '../../core/services/font_service.dart';
import '../../core/theme/theme_config.dart';
import '../../core/utils.dart';
import '../../shared/widgets/app_text.dart';
import '../../shared/widgets/hover_tile.dart';
import '../../shared/charts/modern_charts.dart';

class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  List<String> fonts = const ['Vazirmatn'];
  bool savingFont = false;

  @override
  void initState() {
    super.initState();
    _loadFonts();
  }

  Future<void> _loadFonts() async {
    try {
      final list = await FontService.listSystemFonts();
      if (mounted) setState(() => fonts = list);
    } catch (_) {}
  }

  Future<void> _pickFont({required bool forNumbers}) async {
    setState(() => savingFont = true);
    try {
      final cfg = ThemeConfig.notifier.value;
      final current =
          forNumbers ? cfg.numberFontFamily : cfg.textFontFamily;
      final picked = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(forNumbers ? 'فونت نمایش اعداد' : 'فونت متن برنامه'),
          content: SizedBox(
            width: 340,
            height: 380,
            child: StatefulBuilder(
              builder: (context, setLocal) {
                var shown = fonts;
                return Column(
                  children: [
                    TextField(
                      decoration:
                          const InputDecoration(hintText: 'جستجوی فونت...'),
                      onChanged: (q) => setLocal(() {
                        shown = fonts
                            .where((f) => f.toLowerCase().contains(q.toLowerCase()))
                            .toList();
                      }),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (_, i) => ListTile(
                          dense: true,
                          // پیش‌نمایش واقعی هر فونت اگر بارگذاری شده باشد
                          title: Text(shown[i],
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontFamily:
                                      shown[i] == 'Vazirmatn' ? 'Vazirmatn' : null)),
                          subtitle: Text(
                              shown[i] == 'Vazirmatn'
                                  ? 'فونت داخلی برنامه'
                                  : 'فونت سیستم',
                              style: const TextStyle(fontSize: 10.5)),
                          trailing: current == shown[i]
                              ? Icon(Icons.check,
                                  size: 17, color: Theme.of(context).colorScheme.primary)
                              : null,
                          onTap: () => Navigator.pop(ctx, shown[i]),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('انصراف')),
          ],
        ),
      );
      if (picked == null) return;
      final path = await FontService.findFontFile(picked);
      final ok = path == null || await FontService.loadDynamicFont(picked, path);
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('بارگذاری فونت ناموفق بود — فونت دیگر را انتخاب کنید')));
        }
        return;
      }
      final c2 = forNumbers
          ? cfg.copyWith(numberFontFamily: picked, numberFontPath: path ?? '')
          : cfg.copyWith(textFontFamily: picked, textFontPath: path ?? '');
      await ThemeConfig.save(c2);
    } finally {
      if (mounted) setState(() => savingFont = false);
    }
  }

  Future<void> _update(ThemeConfig Function(ThemeConfig) edit) async {
    await ThemeConfig.save(edit(ThemeConfig.notifier.value));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ThemeConfig.notifier.value;
    final p = cfg.palette;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            AppText('تم و ظاهر — شخصی‌سازی کامل',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            // ── سه تم پیش‌فرض ──
            _section('تم پیش‌فرض', p),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final preset in ThemePreset.values)
                  _presetCard(preset, cfg.preset == preset.key),
              ],
            ),
            const SizedBox(height: 14),
            // ── رنگ تاکیدی ──
            _section('رنگ تاکیدی (روی همه اجزای تم اعمال می‌شود)', p),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final hex in const [
                  '', '2563EB', '4F8CFF', '0EA5E9', '10B981', 'F59E0B',
                  'EF4444', '8B5CF6', 'EC4899', 'A8761F', 'D4A437',
                ])
                  GestureDetector(
                    onTap: () => _update((c) => c.copyWith(accentHex: hex)),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: hex.isEmpty
                            ? kPalettes[cfg.presetEnum]!.primary
                            : Color(int.parse('FF$hex', radix: 16)),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: cfg.accentHex == hex
                                ? p.textPrimary
                                : p.border,
                            width: cfg.accentHex == hex ? 2.4 : 1),
                      ),
                      child: hex.isEmpty
                          ? Icon(Icons.auto_awesome,
                              size: 15,
                              color: kPalettes[cfg.presetEnum]!.onPrimary)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            // ── فونت‌ها ──
            _section('فونت متن و فونت اعداد — از فونت‌های نصب‌شده ویندوز', p),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _fontCard(
                  'فونت متن برنامه',
                  cfg.effectiveTextFont,
                  Icons.text_fields,
                  onPick: () => _pickFont(forNumbers: false),
                ),
                _fontCard(
                  'فونت نمایش اعداد (در کل برنامه)',
                  cfg.effectiveNumberFont,
                  Icons.pin,
                  onPick: () => _pickFont(forNumbers: true),
                ),
                if (savingFont)
                  const SizedBox(
                      width: 40,
                      height: 40,
                      child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(strokeWidth: 2))),
              ],
            ),
            const SizedBox(height: 14),
            // ── اسلایدرها ──
            _section('گردی گوشه‌ها، اندازه متن، چگالی (ارتفاع سطرها)', p),
            _slider('گردی گوشه‌ها', cfg.radiusScale, 0.6, 2.0,
                (v) => _update((c) => c.copyWith(radiusScale: v)),
                display: '${toPersianDigits('${(cfg.radiusScale * 100).round()}')}٪'),
            _slider('اندازه متن', cfg.fontScale, 0.85, 1.35,
                (v) => _update((c) => c.copyWith(fontScale: v)),
                display: '${toPersianDigits('${(cfg.fontScale * 100).round()}')}٪'),
            _slider('چگالی و ارتفاع سطر جدول‌ها', cfg.density, 0.85, 1.5,
                (v) => _update((c) => c.copyWith(density: v)),
                display: '${toPersianDigits('${(cfg.density * 100).round()}')}٪'),
            const SizedBox(height: 14),
            // ── کلیدها ──
            _section('رفتار برنامه', p),
            _toggle(
              'فرمان shrink-to-fit سراسری — هیچ متن و عددی از کادر بیرون نمی‌زند',
              'با فعال بودن، حتی پس از تغییر فونت، همه متن‌ها در ویندوز و موبایل داخل کادر خود کوچک می‌شوند.',
              cfg.shrinkToFit,
              (v) => _update((c) => c.copyWith(shrinkToFit: v)),
            ),
            _toggle(
              'انیمیشن‌ها (حرکت موس، ترنزیشن صفحات، نمودارها)',
              'روی سیستم‌های بسیار ضعیف می‌توانید خاموش کنید.',
              cfg.animations,
              (v) => _update((c) => c.copyWith(animations: v)),
            ),
            _toggle(
              'نمایش نمودارها در داشبورد',
              'دایره‌ای وضعیت، خطی درآمد و پیش‌بینی، میله‌ای قابل وصول.',
              cfg.showChartsOnDashboard,
              (v) => _update((c) => c.copyWith(showChartsOnDashboard: v)),
            ),
            const SizedBox(height: 14),
            // ── پیش‌نمایش زنده ──
            _section('پیش‌نمایش زنده', p),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText('نمونه متن برنامه با فونت فعلی',
                        style: TextStyle(
                            fontSize: 15 * cfg.fontScale,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    AppText(
                        'رسید سپردن دستگاه — مشتری: علی رضایی — گوشی iPhone 13',
                        style: TextStyle(
                            fontSize: 13 * cfg.fontScale,
                            color: p.textSecondary)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        AppNumText(
                            'مبلغ فاکتور: ${money(1234567)} تومان',
                            style: TextStyle(
                                fontSize: 14 * cfg.fontScale,
                                fontWeight: FontWeight.bold,
                                color: p.primary)),
                        const SizedBox(width: 16),
                        AppNumText('تاریخ: ${shamsiDate(DateTime.now())}',
                            style: TextStyle(
                                fontSize: 13 * cfg.fontScale,
                                color: p.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // نمونه نمودار کوچک
                    SizedBox(
                      height: 90,
                      child: LineChart(
                        points: const [
                          ChartPoint('۱', 300),
                          ChartPoint('۲', 520),
                          ChartPoint('۳', 410),
                          ChartPoint('۴', 640),
                          ChartPoint('۵', 700),
                        ],
                        height: 90,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final c = ThemeConfig();
                    // بارگذاری مجدد فونت‌های انتخابی پیش‌فرض
                    await ThemeConfig.save(c);
                  },
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('بازگشت به پیش‌فرض برنامه'),
                ),
                const SizedBox(width: 10),
                AppText('تغییرات بلافاصله اعمال و ذخیره می‌شوند.',
                    style: TextStyle(
                        fontSize: 11.5, color: p.textSecondary)),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppText(title,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: p.textSecondary)),
    );
  }

  Widget _presetCard(ThemePreset preset, bool active) {
    final pal = kPalettes[preset]!;
    final cfg = ThemeConfig.notifier.value;
    return HoverTile(
      active: active,
      radius: cfg.baseRadius,
      hoverColor: pal.primary.withValues(alpha: 0.1),
      activeColor: pal.primary.withValues(alpha: 0.14),
      animate: cfg.animations,
      onTap: () => _update((c) => c.copyWith(
          preset: preset.key,
          accentHex: '')), // بازگشت رنگ تاکیدی به پیش‌فرض تم
      child: SizedBox(
        width: 190,
        child: Card(
          elevation: active ? 4 : 1,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppText(preset.labelFa,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: pal.textPrimary)),
                    const Spacer(),
                    if (active)
                      Icon(Icons.check_circle,
                          size: 16, color: pal.primary),
                  ],
                ),
                const SizedBox(height: 8),
                // مینیاتور پیش‌نمایش تم
                Container(
                  height: 64,
                  decoration: BoxDecoration(
                    color: pal.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: pal.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        margin: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                              colors: pal.sidebarGradient),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Column(
                            children: [
                              Container(
                                height: 14,
                                decoration: BoxDecoration(
                                  color: pal.surface,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: pal.border),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: pal.primary
                                            .withValues(alpha: 0.85),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Container(
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: pal.accent
                                            .withValues(alpha: 0.6),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fontCard(String title, String value, IconData icon,
      {required VoidCallback onPick}) {
    final cfg = ThemeConfig.notifier.value;
    final p = cfg.palette;
    return SizedBox(
      width: 250,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(cfg.baseRadius),
          onTap: onPick,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: p.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(title,
                          style: TextStyle(
                              fontSize: 11.5, color: p.textSecondary)),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(value,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                fontFamily: value == 'Vazirmatn'
                                    ? 'Vazirmatn'
                                    : null)),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left, size: 18, color: p.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChanged,
      {required String display}) {
    final cfg = ThemeConfig.notifier.value;
    final p = cfg.palette;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 210,
              child: AppText(label, style: const TextStyle(fontSize: 12.5)),
            ),
            Expanded(
              child: Slider(
                value: value.clamp(min, max).toDouble(),
                min: min,
                max: max,
                divisions: 20,
                activeColor: p.primary,
                onChanged: onChanged,
              ),
            ),
            SizedBox(
                width: 56,
                child: AppNumText(display,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: p.primary),
                    textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }

  Widget _toggle(String title, String subtitle, bool value,
      ValueChanged<bool> onChanged) {
    final p = ThemeConfig.notifier.value.palette;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: AppText(title, style: const TextStyle(fontSize: 12.5)),
        subtitle: AppText(subtitle,
            style: TextStyle(fontSize: 11, color: p.textSecondary)),
      ),
    );
  }
}

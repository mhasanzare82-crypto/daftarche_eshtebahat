import 'package:material_ui/material_ui.dart';
import '../models/note.dart';

class ThemeManagerResult {
  final List<NoteTheme> themes;
  final List<String> randomThemeNames;
  final List<int> textColorPalette;
  const ThemeManagerResult(this.themes, this.randomThemeNames, this.textColorPalette);
}

class ThemeManagerDialog extends StatefulWidget {
  final List<NoteTheme> initialThemes;
  final List<String> customFonts;
  final List<String> initialRandomThemeNames;
  final List<int> initialTextColorPalette;
  final Future<List<String>> Function()? onAddCustomFont;
  const ThemeManagerDialog({
    super.key,
    required this.initialThemes,
    this.customFonts = const [],
    this.initialRandomThemeNames = const [],
    this.initialTextColorPalette = const [],
    this.onAddCustomFont,
  });
  @override
  State<ThemeManagerDialog> createState() => _ThemeManagerDialogState();
}

class _ThemeManagerDialogState extends State<ThemeManagerDialog> {
  late List<NoteTheme> palette;
  late List<String> fonts;
  late List<int> textColorPalette;
  double hue = 220, saturation = .06, brightness = .78;
  bool addingFonts = false;
  static const builtInFonts = ['sans-serif'];

  @override
  void initState() {
    super.initState();
    palette = [...widget.initialThemes];
    fonts = {...builtInFonts, ...widget.customFonts}.toList();
    textColorPalette = [...widget.initialTextColorPalette];
  }

  Color get selectedColor => HSVColor.fromAHSV(1, hue, saturation, brightness).toColor();
  Color readableText(Color c) => c.computeLuminance() > .42 ? const Color(0xFF211D27) : Colors.white;

  Future<void> addFonts() async {
    if (widget.onAddCustomFont == null || addingFonts) return;
    setState(() => addingFonts = true);
    try {
      final updated = await widget.onAddCustomFont!();
      if (mounted) setState(() => fonts = {...builtInFonts, ...updated}.toList());
    } finally {
      if (mounted) setState(() => addingFonts = false);
    }
  }

  void addSelectedBackgroundColor() {
    final color = selectedColor;
    final value = color.toARGB32();
    if (palette.any((item) => item.backgroundColor == value)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('این رنگ قبلاً در پالت پس‌زمینه اضافه شده است.')));
      return;
    }
    setState(() => palette.add(NoteTheme('رنگ ${palette.length + 1}', value, readableText(color).toARGB32(), 'sans-serif')));
  }

  void addSelectedTextColor() {
    final value = selectedColor.toARGB32();
    if (textColorPalette.contains(value)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('این رنگ قبلاً در پالت رنگ متن اضافه شده است.')));
      return;
    }
    setState(() => textColorPalette.add(value));
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: SizedBox(
        width: 520,
        height: MediaQuery.sizeOf(context).height * .86,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(children: [
              const Expanded(child: Text('مدیریت تم‌ها', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
            _sectionTitle('۱. فونت‌ها', Icons.font_download_outlined),
            const SizedBox(height: 6),
            const Text('فونت پیش‌فرض برنامه فقط sans-serif است. در صورت نیاز می‌توانی فونت دلخواه خودت را اضافه کنی.', style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: addingFonts ? null : addFonts,
              icon: addingFonts ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_file_outlined),
              label: Text(addingFonts ? 'در حال افزودن فونت‌ها...' : 'افزودن فونت دلخواه'),
            )),
            const SizedBox(height: 8),
            Wrap(spacing: 7, runSpacing: 7, children: fonts.map((family) => Chip(
              avatar: const Icon(Icons.text_fields, size: 16),
              label: Text(family, style: TextStyle(fontFamily: family, fontSize: 11)),
            )).toList()),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            _sectionTitle('۲. انتخاب رنگ', Icons.palette_outlined),
            const SizedBox(height: 8),
            const Text('سه اسلایدر را تنظیم کن و سپس رنگ انتخاب‌شده را به پالت پس‌زمینه یا پالت رنگ متن اضافه کن.', style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 12),
            _sliderRow('ته‌رنگ', hue, 0, 360, (v) => setState(() => hue = v), hue.round().toString()),
            _sliderRow('اشباع', saturation, 0, 1, (v) => setState(() => saturation = v), '${(saturation * 100).round()}٪'),
            _sliderRow('روشنایی', brightness, 0, 1, (v) => setState(() => brightness = v), '${(brightness * 100).round()}٪'),
            const SizedBox(height: 10),
            Container(
              height: 54,
              decoration: BoxDecoration(color: selectedColor, borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.center,
              child: Text('پیش‌نمایش رنگ انتخاب‌شده', style: TextStyle(color: readableText(selectedColor), fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: FilledButton.icon(
                onPressed: addSelectedBackgroundColor,
                icon: const Icon(Icons.wallpaper_outlined, size: 18),
                label: const Text('افزودن به پالت پس‌زمینه', textAlign: TextAlign.center),
              )),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                onPressed: addSelectedTextColor,
                icon: const Icon(Icons.format_color_text, size: 18),
                label: const Text('افزودن به پالت رنگ متن', textAlign: TextAlign.center),
              )),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: Text('پالت رنگ پس‌زمینه (${palette.length})', style: const TextStyle(fontWeight: FontWeight.w600))),
              TextButton.icon(onPressed: palette.isEmpty ? null : () => setState(palette.clear), icon: const Icon(Icons.delete_sweep_outlined, size: 18), label: const Text('پاک‌کردن')),
            ]),
            if (palette.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('هنوز رنگ پس‌زمینه‌ای اضافه نشده است.', textAlign: TextAlign.center))
            else
              Wrap(spacing: 9, runSpacing: 9, children: List.generate(palette.length, (index) {
                final item = palette[index];
                return Tooltip(message: item.name, child: GestureDetector(
                  onLongPress: () => setState(() => palette.removeAt(index)),
                  child: Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(color: Color(item.backgroundColor), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black26)),
                    child: Icon(Icons.check, color: Color(item.textColor), size: 19),
                  ),
                ));
              })),
            const SizedBox(height: 8),
            const Text('برای حذف رنگ پس‌زمینه، انگشتت را روی آن نگه دار.', style: TextStyle(fontSize: 11, color: Colors.black54)),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: Text('پالت رنگ متن (${textColorPalette.length})', style: const TextStyle(fontWeight: FontWeight.w600))),
              TextButton.icon(onPressed: textColorPalette.isEmpty ? null : () => setState(textColorPalette.clear), icon: const Icon(Icons.delete_sweep_outlined, size: 18), label: const Text('پاک‌کردن')),
            ]),
            if (textColorPalette.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('هنوز رنگ متنی اضافه نشده است.', textAlign: TextAlign.center))
            else
              Wrap(spacing: 9, runSpacing: 9, children: List.generate(textColorPalette.length, (index) {
                final value = textColorPalette[index];
                return Tooltip(message: '#${value.toRadixString(16).padLeft(8, '0').toUpperCase()}', child: GestureDetector(
                  onLongPress: () => setState(() => textColorPalette.removeAt(index)),
                  child: Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(color: Color(value), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black26)),
                    child: Icon(Icons.format_color_text, color: Color(value).computeLuminance() > .42 ? Colors.black : Colors.white, size: 19),
                  ),
                ));
              })),
            const SizedBox(height: 8),
            const Text('برای حذف رنگ متن، انگشتت را روی آن نگه دار.', style: TextStyle(fontSize: 11, color: Colors.black54)),
          ])),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 12), child: Row(children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
            const Spacer(),
            FilledButton.icon(
              onPressed: () {
                final names = palette.map((item) => item.name).toList();
                Navigator.pop(context, ThemeManagerResult([...palette], names, [...textColorPalette]));
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('ذخیره تنظیمات'),
            ),
          ])),
        ]),
      ),
    ),
  );

  Widget _sectionTitle(String title, IconData icon) => Row(children: [
    Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
    const SizedBox(width: 8),
    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
  ]);

  Widget _sliderRow(String label, double value, double min, double max, ValueChanged<double> onChanged, String valueText) => Row(children: [
    SizedBox(width: 62, child: Text(label, style: const TextStyle(fontSize: 12))),
    Expanded(child: Slider(value: value, min: min, max: max, onChanged: onChanged)),
    SizedBox(width: 42, child: Text(valueText, textAlign: TextAlign.left, style: const TextStyle(fontSize: 11))),
  ]);
}

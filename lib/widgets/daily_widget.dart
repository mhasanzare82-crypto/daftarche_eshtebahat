import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/note.dart';
import '../widgets/home_widget_sync.dart';

const _dailyWidgetSelectedIdsKey = 'daily_widget_selected_note_ids';

Future<bool> toggleDailyWidgetNote(Note note) async {
  final prefs = await SharedPreferences.getInstance();
  final ids = (prefs.getStringList(_dailyWidgetSelectedIdsKey) ?? <String>[]).toSet();
  final wasSelected = ids.remove(note.id);
  if (!wasSelected) ids.add(note.id);
  await prefs.setStringList(_dailyWidgetSelectedIdsKey, ids.toList());
  await HomeWidgetSync.refresh();
  return !wasSelected;
}

/// Selection, color, and typography controls for the Daily Reminder widget.
class DailyWidgetSettingsScreen extends StatefulWidget {
  final List<Note> notes;

  const DailyWidgetSettingsScreen({super.key, required this.notes});

  @override
  State<DailyWidgetSettingsScreen> createState() =>
      _DailyWidgetSettingsScreenState();
}

class _DailyWidgetSettingsScreenState extends State<DailyWidgetSettingsScreen> {
  static const _backgroundKey = 'daily_widget_background_color';
  static const _textColorKey = 'daily_widget_text_color';
  static const _fontSizeKey = 'daily_widget_font_size';
  static const _fontStyleKey = 'daily_widget_font_style';

  Set<String> _selectedIds = {};
  Color _background = const Color(0xFF202329);
  Color _textColor = const Color(0xFFF4F4F5);
  double _fontSize = 16;
  String _fontStyle = 'normal';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _selectedIds = (prefs.getStringList(_dailyWidgetSelectedIdsKey) ?? <String>[]).toSet();
      _background = Color(prefs.getInt(_backgroundKey) ?? _background.toARGB32());
      _textColor = Color(prefs.getInt(_textColorKey) ?? _textColor.toARGB32());
      _fontSize = (prefs.getDouble(_fontSizeKey) ??
              prefs.getInt(_fontSizeKey)?.toDouble() ??
              16.0)
          .clamp(12.0, 28.0)
          .toDouble();
      _fontStyle = prefs.getString(_fontStyleKey) ?? 'normal';
      _loading = false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_dailyWidgetSelectedIdsKey, _selectedIds.toList());
    await prefs.setInt(_backgroundKey, _background.toARGB32());
    await prefs.setInt(_textColorKey, _textColor.toARGB32());
    await prefs.setDouble(_fontSizeKey, _fontSize);
    await prefs.setString(_fontStyleKey, _fontStyle);
    await HomeWidgetSync.refresh();
  }

  String _plainText(String body) {
    const quillMarker = '__quill_note_v1__';
    const legacyMarker = '__rich_note_v1__';

    try {
      if (body.startsWith(quillMarker)) {
        final operations = jsonDecode(body.substring(quillMarker.length)) as List;
        return operations
            .map((operation) =>
                operation is Map && operation['insert'] is String
                    ? operation['insert'] as String
                    : '')
            .join();
      }

      final source =
          body.startsWith(legacyMarker) ? body.substring(legacyMarker.length) : body;
      if (source.trimLeft().startsWith('[')) {
        final blocks = jsonDecode(source) as List;
        return blocks
            .whereType<Map>()
            .where((block) => block['type'] == 'text')
            .map((block) => block['text']?.toString() ?? '')
            .join('\n');
      }
    } catch (_) {
      // Keep the original text if a legacy rich-text format cannot be parsed.
    }
    return body;
  }

  List<String> _boundedSections(Note note) {
    final body = _plainText(note.body);
    final separator = RegExp(r'^[ \t]*-{20,}[ \t]*$', multiLine: true);
    final chunks = body.split(separator);
    final lines = body.trimRight().split('\n');
    final beginsWithSeparator = lines.isNotEmpty &&
        RegExp(r'^[ \t]*-{20,}[ \t]*$', multiLine: true).hasMatch(lines.first);
    final endsWithSeparator = lines.isNotEmpty &&
        RegExp(r'^[ \t]*-{20,}[ \t]*$', multiLine: true).hasMatch(lines.last);

    // Do not show text outside a pair of separator lines, or notes with no separators.
    if (!beginsWithSeparator && chunks.isNotEmpty) chunks.removeAt(0);
    if (!endsWithSeparator && chunks.isNotEmpty) chunks.removeLast();

    return chunks
        .map((section) => section.trim())
        .where((section) => section.isNotEmpty)
        .toList();
  }

  Widget _channelSlider(String label, Color color, bool isBackground, int channel) {
    final redValue = (color.r * 255.0).round().clamp(0, 255);
    final greenValue = (color.g * 255.0).round().clamp(0, 255);
    final blueValue = (color.b * 255.0).round().clamp(0, 255);
    final value = channel == 0
        ? redValue
        : channel == 1
            ? greenValue
            : blueValue;

    return ListTile(
      dense: true,
      title: Text(label),
      subtitle: Slider(
        min: 0,
        max: 255,
        divisions: 255,
        value: value.toDouble(),
        onChanged: (newValue) {
          final red = channel == 0 ? newValue.round() : redValue;
          final green = channel == 1 ? newValue.round() : greenValue;
          final blue = channel == 2 ? newValue.round() : blueValue;
          final changed = Color.fromARGB(255, red, green, blue);
          setState(() {
            if (isBackground) {
              _background = changed;
            } else {
              _textColor = changed;
            }
          });
        },
        onChangeEnd: (_) => _saveSettings(),
      ),
    );
  }

  Widget _colorSection(String title, Color color, bool isBackground) {
    return ExpansionTile(
      title: Text(title),
      subtitle: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      children: [
        _channelSlider('قرمز', color, isBackground, 0),
        _channelSlider('سبز', color, isBackground, 1),
        _channelSlider('آبی', color, isBackground, 2),
      ],
    );
  }

  TextStyle get _previewStyle => TextStyle(
        color: _textColor,
        fontSize: _fontSize,
        fontWeight: _fontStyle.contains('bold') ? FontWeight.bold : FontWeight.normal,
        fontStyle: _fontStyle.contains('italic') ? FontStyle.italic : FontStyle.normal,
      );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('یادآوری‌های روزانه')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Card(
                    color: _background,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('نمونه یادآوری', style: _previewStyle.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('متن بخش انتخاب‌شده از یادداشت در اینجا نمایش داده می‌شود.', style: _previewStyle),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('بعدی  ›', style: _previewStyle.copyWith(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('یادداشت‌های قابل نمایش', style: Theme.of(context).textTheme.titleMedium),
                  const Text('فقط یادداشت‌هایی که انتخاب می‌کنی وارد گردش ویجت می‌شوند.'),
                  ...widget.notes.map((note) {
                    final sectionCount = _boundedSections(note).length;
                    return CheckboxListTile(
                      value: _selectedIds.contains(note.id),
                      title: Text(note.title.isEmpty ? 'بدون عنوان' : note.title),
                      subtitle: Text('$sectionCount بخش قابل نمایش'),
                      onChanged: (value) async {
                        setState(() {
                          if (value == true) {
                            _selectedIds.add(note.id);
                          } else {
                            _selectedIds.remove(note.id);
                          }
                        });
                        await _saveSettings();
                      },
                    );
                  }),
                  const Divider(),
                  Text('تنظیمات رنگ و فونت', style: Theme.of(context).textTheme.titleMedium),
                  _colorSection('رنگ پس‌زمینه', _background, true),
                  _colorSection('رنگ متن', _textColor, false),
                  ListTile(
                    title: const Text('اندازه فونت'),
                    subtitle: Slider(
                      min: 12,
                      max: 28,
                      divisions: 16,
                      value: _fontSize,
                      onChanged: (value) => setState(() => _fontSize = value),
                      onChangeEnd: (_) => _saveSettings(),
                    ),
                  ),
                  ListTile(
                    title: const Text('سبک فونت'),
                    subtitle: DropdownButton<String>(
                      value: _fontStyle,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'normal', child: Text('معمولی')),
                        DropdownMenuItem(value: 'bold', child: Text('ضخیم')),
                        DropdownMenuItem(value: 'italic', child: Text('مورب')),
                        DropdownMenuItem(value: 'bold_italic', child: Text('ضخیم و مورب')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _fontStyle = value);
                        _saveSettings();
                      },
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _saveSettings,
                    icon: const Icon(Icons.save),
                    label: const Text('ذخیره و اعمال تنظیمات'),
                  ),
                ],
              ),
      ),
    );
  }
}

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';
import '../widgets/home_widget_sync.dart';

/// Single persistence boundary for notebook data.
class NotebookRepository {
  static const _notesKey = 'notebook_notes';
  static const _themesKey = 'notebook_themes';
  static const _foldersKey = 'notebook_folders';
  static const _fontsKey = 'notebook_custom_fonts';
  static const _randomThemesKey = 'notebook_random_theme_names';
  static const _pinnedNotesKey = 'notebook_pinned_note_ids';
  static const _widgetNoteIdsKey = 'notebook_widget_note_ids';
  static const _pinnedFoldersKey = 'notebook_pinned_folder_ids';
  static const _textColorPaletteKey = 'notebook_text_color_palette';
  static const _appInterfaceFontKey = 'notebook_app_interface_font_family';
  static const _appThemeKey = 'notebook_app_theme';
  static const _quickWidgetNoteId = 'quick_note_widget_entries';

  Future<List<Note>> loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final notes = _decodeList(prefs.getString(_notesKey), Note.fromJson);
    // Rehydrate the native widget from the canonical notebook on app startup.
    await _syncDailyReminder(prefs, notes);
    return notes;
  }

  Future<List<NoteTheme>> loadThemes() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getString(_themesKey), NoteTheme.fromJson);
  }

  Future<List<NoteFolder>> loadFolders() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getString(_foldersKey), NoteFolder.fromJson);
  }

  Future<List<String>> loadPinnedNoteIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_pinnedNotesKey) ?? <String>[];
  }

  Future<List<String>> loadWidgetNoteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_widgetNoteIdsKey);
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      return List<String>.from(jsonDecode(raw) as List);
    } catch (_) {
      return <String>[];
    }
  }

  Future<void> saveWidgetNoteIds(List<String> values) async {
    final prefs = await SharedPreferences.getInstance();
    final uniqueIds = values.where((id) => id.isNotEmpty).toSet().toList();
    if (!await prefs.setString(_widgetNoteIdsKey, jsonEncode(uniqueIds))) {
      throw StateError('Unable to persist widget note selection');
    }
    final notes = _decodeList(prefs.getString(_notesKey), Note.fromJson);
    await _syncDailyReminder(prefs, notes);
  }

  Future<List<String>> loadPinnedFolderIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_pinnedFoldersKey) ?? <String>[];
  }

  Future<void> savePinnedNoteIds(List<String> values) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setStringList(_pinnedNotesKey, values)) {
      throw StateError('Unable to persist pinned notes');
    }
    await HomeWidgetSync.refresh();
  }

  Future<void> savePinnedFolderIds(List<String> values) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setStringList(_pinnedFoldersKey, values)) {
      throw StateError('Unable to persist pinned folders');
    }
  }

  Future<List<int>> loadTextColorPalette() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_textColorPaletteKey) ?? <String>[])
        .map((value) => int.tryParse(value))
        .whereType<int>()
        .toList();
  }

  Future<void> saveTextColorPalette(List<int> values) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setStringList(
      _textColorPaletteKey,
      values.map((value) => value.toString()).toList(),
    )) {
      throw StateError('Unable to persist text color palette');
    }
  }

  Future<String> loadAppInterfaceFontFamily() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_appInterfaceFontKey) ?? 'sans-serif';
  }

  Future<void> saveAppInterfaceFontFamily(String value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_appInterfaceFontKey, value)) {
      throw StateError('Unable to persist app interface font');
    }
  }

  Future<String> loadAppTheme() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_appThemeKey) ?? 'دودی';
  }

  Future<void> saveAppTheme(String value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_appThemeKey, value)) {
      throw StateError('Unable to persist app theme');
    }
  }

  Future<List<String>> loadRandomThemeNames() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_randomThemesKey) ?? <String>[];
  }

  Future<void> saveRandomThemeNames(List<String> values) async {
    final prefs = await SharedPreferences.getInstance();
    final success = await prefs.setStringList(_randomThemesKey, values);
    if (!success) throw StateError('Unable to persist random theme selection');
  }

  Future<Map<String, String>> loadCustomFonts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_fontsKey);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> saveNotes(List<Note> values) async {
    final prefs = await SharedPreferences.getInstance();
    final storedNotes = _decodeList(prefs.getString(_notesKey), Note.fromJson);
    final latestQuickNote = storedNotes
        .where((note) => note.id == _quickWidgetNoteId)
        .firstOrNull;
    final notesToSave = List<Note>.of(values);
    if (latestQuickNote != null) {
      final currentIndex = notesToSave.indexWhere(
        (note) => note.id == _quickWidgetNoteId,
      );
      if (currentIndex == -1) {
        notesToSave.add(latestQuickNote);
      } else if (latestQuickNote.updated.isAfter(
        notesToSave[currentIndex].updated,
      )) {
        notesToSave[currentIndex] = latestQuickNote;
      }
    }
    await _save(_notesKey, notesToSave.map((note) => note.toJson()).toList());
    await _syncDailyReminder(prefs, notesToSave);
    await HomeWidgetSync.refresh();
  }

  Future<void> _syncDailyReminder(
    SharedPreferences prefs,
    List<Note> notes,
  ) async {
    final rawIds = prefs.getString(_widgetNoteIdsKey);
    List<String> selectedIds = <String>[];
    if (rawIds != null && rawIds.isNotEmpty) {
      try {
        selectedIds = List<String>.from(jsonDecode(rawIds) as List);
      } catch (_) {
        selectedIds = <String>[];
      }
    }
    final selectedNotes = notes
        .where((note) => selectedIds.contains(note.id))
        .map((note) => note.toJson())
        .toList();
    await HomeWidgetSync.syncDailyReminder(selectedNotes);
  }

  Future<void> saveThemes(List<NoteTheme> values) =>
      _save(_themesKey, values.map((e) => e.toJson()).toList());

  Future<void> saveFolders(List<NoteFolder> values) async {
    await _save(_foldersKey, values.map((e) => e.toJson()).toList());
    await HomeWidgetSync.refresh();
  }

  Future<void> saveCustomFonts(Map<String, String> values) =>
      _save(_fontsKey, values);

  Future<void> _save(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    final success = await prefs.setString(key, jsonEncode(value));
    if (!success) throw StateError('Unable to persist notebook data: $key');
  }

  List<T> _decodeList<T>(
    String? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw == null || raw.isEmpty) return <T>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <T>[];
      return decoded
          .whereType<Map>()
          .map((item) => fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return <T>[];
    }
  }
}

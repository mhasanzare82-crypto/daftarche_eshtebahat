import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';

/// Single persistence boundary for notebook data.
/// Keeps the existing SharedPreferences keys to preserve user data.
class NotebookRepository {
  static const _notesKey = 'notebook_notes';
  static const _themesKey = 'notebook_themes';
  static const _foldersKey = 'notebook_folders';
  static const _fontsKey = 'notebook_custom_fonts';
  static const _randomThemesKey = 'notebook_random_theme_names';
  static const _pinnedNotesKey = 'notebook_pinned_note_ids';
  static const _pinnedFoldersKey = 'notebook_pinned_folder_ids';
  static const _textColorPaletteKey = 'notebook_text_color_palette';

  Future<List<Note>> loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getString(_notesKey), Note.fromJson);
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

  Future<List<String>> loadPinnedFolderIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_pinnedFoldersKey) ?? <String>[];
  }

  Future<void> savePinnedNoteIds(List<String> values) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setStringList(_pinnedNotesKey, values)) {
      throw StateError('Unable to persist pinned notes');
    }
  }

  Future<void> savePinnedFolderIds(List<String> values) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setStringList(_pinnedFoldersKey, values)) {
      throw StateError('Unable to persist pinned folders');
    }
  }

  Future<List<int>> loadTextColorPalette() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_textColorPaletteKey) ?? <String>[]).map((value) => int.tryParse(value)).whereType<int>().toList();
  }

  Future<void> saveTextColorPalette(List<int> values) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setStringList(_textColorPaletteKey, values.map((value) => value.toString()).toList())) {
      throw StateError('Unable to persist text color palette');
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
    try { return Map<String, String>.from(jsonDecode(raw) as Map); }
    catch (_) { return <String, String>{}; }
  }

  Future<void> saveNotes(List<Note> values) => _save(_notesKey, values.map((e) => e.toJson()).toList());
  Future<void> saveThemes(List<NoteTheme> values) => _save(_themesKey, values.map((e) => e.toJson()).toList());
  Future<void> saveFolders(List<NoteFolder> values) => _save(_foldersKey, values.map((e) => e.toJson()).toList());
  Future<void> saveCustomFonts(Map<String, String> values) => _save(_fontsKey, values);

  Future<void> _save(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    final success = await prefs.setString(key, jsonEncode(value));
    if (!success) throw StateError('Unable to persist notebook data: $key');
  }

  List<T> _decodeList<T>(String? raw, T Function(Map<String, dynamic>) fromJson) {
    if (raw == null || raw.isEmpty) return <T>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <T>[];
      return decoded.whereType<Map>().map((item) => fromJson(Map<String, dynamic>.from(item))).toList();
    } catch (_) { return <T>[]; }
  }
}

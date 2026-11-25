import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:dart_quill_delta/dart_quill_delta.dart' as delta;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'models/note.dart';
import 'data/notebook_repository.dart';
import 'widgets/home_widget_sync.dart';
import 'screens/theme_dialogs.dart';

const String _quillNoteMarker = '__quill_note_v1__';
const String _legacyRichNoteMarker = '__rich_note_v1__';

List<Map<String, dynamic>> _decodeNoteBlocks(String body) {
  final value = body.startsWith(_legacyRichNoteMarker)
      ? body.substring(_legacyRichNoteMarker.length)
      : body;
  try {
    final decoded = jsonDecode(value);
    if (decoded is List) {
      return decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    }
  } catch (_) {}
  if (body.startsWith(_quillNoteMarker)) {
    try {
      final delta = jsonDecode(body.substring(_quillNoteMarker.length)) as List;
      return delta.map((raw) {
        final op = Map<String, dynamic>.from(raw as Map);
        final insert = op['insert'];
        if (insert is Map && insert['image'] is String) {
          return <String, dynamic>{'type': 'image', 'path': insert['image'] as String};
        }
        return <String, dynamic>{'type': 'text', 'text': insert is String ? insert : ''};
      }).toList();
    } catch (_) {}
  }
  return body.isEmpty ? <Map<String, dynamic>>[] : <Map<String, dynamic>>[{'type': 'text', 'text': body}];
}

String _notePlainText(String body) {
  if (body.startsWith(_quillNoteMarker)) {
    try {
      final delta = jsonDecode(body.substring(_quillNoteMarker.length)) as List;
      final document = quill.Document.fromJson(delta);
      return document.toPlainText().trim();
    } catch (_) {}
  }
  return _decodeNoteBlocks(body)
      .where((block) => block['type'] == 'text')
      .map((block) => block['text'] as String? ?? '')
      .join('\n')
      .trim();
}

final ValueNotifier<String> appInterfaceFontFamily = ValueNotifier<String>('Estedad');
final ValueNotifier<String> appThemeName = ValueNotifier<String>('دودی');

ThemeData _buildAppTheme(String preset, String fontFamily) {
  final isWhite = preset == 'سفید';
  final isBlack = preset == 'سیاه';
  final isSilver = preset == 'نقره‌ای';
  final background = isWhite
      ? const Color(0xFFF9FAFB)
      : isBlack
          ? const Color(0xFF101114)
          : isSilver
              ? const Color(0xFFE1E4E8)
              : const Color(0xFF292D32);
  final surface = isWhite
      ? Colors.white
      : isBlack
          ? const Color(0xFF1A1C20)
          : isSilver
              ? const Color(0xFFF0F2F5)
              : const Color(0xFF363B41);
  final foreground = (isBlack || preset == 'دودی')
      ? const Color(0xFFF0F1F3)
      : const Color(0xFF202327);
  final primary = isWhite
      ? const Color(0xFF41464D)
      : isBlack
          ? const Color(0xFFB8BEC7)
          : isSilver
              ? const Color(0xFF68717C)
              : const Color(0xFFB7BEC7);
  final appBarBackground = isWhite
      ? const Color(0xFFF1F3F5)
      : isBlack
          ? const Color(0xFF08090B)
          : isSilver
              ? const Color(0xFFC8CDD4)
              : const Color(0xFF171A1E);
  return ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: (isBlack || preset == 'دودی') ? Brightness.dark : Brightness.light,
    ).copyWith(
      primary: primary,
      onPrimary: (isBlack || preset == 'دودی') ? const Color(0xFF17191C) : Colors.white,
      secondary: isSilver ? const Color(0xFF929BA6) : const Color(0xFF9DA3AA),
      onSecondary: const Color(0xFF202327),
      surface: surface,
    ),
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: appBarBackground,
      foregroundColor: foreground,
      elevation: 0,
      iconTheme: IconThemeData(color: foreground),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: (isBlack || preset == 'دودی') ? const Color(0xFF17191C) : Colors.white,
      elevation: 5,
    ),
  );
}

void main() => runApp(const NotebookApp());
class NotebookApp extends StatelessWidget {
  const NotebookApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: appInterfaceFontFamily,
    builder: (context, interfaceFont, _) => ValueListenableBuilder<String>(
      valueListenable: appThemeName,
      builder: (context, selectedTheme, _) => MaterialApp(
    debugShowCheckedModeBanner: false, title: 'دفترچه اشتباهات',
    theme: _buildAppTheme(selectedTheme, interfaceFont),
    localizationsDelegates: [...GlobalMaterialLocalizations.delegates, quill.FlutterQuillLocalizations.delegate],
    supportedLocales: const [Locale('fa'), Locale('en')],
    // Legacy Flutter-based dependencies still need this migration bridge.
    // ignore: deprecated_member_use
    builder: (context, child) => MaterialUiCompatibilityBridge(child: child!),
    home: const NotesPage(),
      ),
    ),
  );
}







class NotesPage extends StatefulWidget {
  const NotesPage({super.key});
  @override
  State<NotesPage> createState() => _NotesPageState();
}
class _NotesPageState extends State<NotesPage> with WidgetsBindingObserver {
  final NotebookRepository repository = NotebookRepository();
  final notes=<Note>[];
  final themes=<NoteTheme>[];
  final folders=<NoteFolder>[];
  final search=TextEditingController();
  final AudioPlayer noteAudioPlayer = AudioPlayer();
  String? currentlyPlayingAudio;
  String? selectedFolderId;
  bool showUnfiledOnly = true;
  bool loading=true;
  Note? featuredNote;
  final customFonts=<String, String>{};
  final randomThemeNames=<String>{};
  final pinnedNoteIds=<String>{};
  final pinnedFolderIds=<String>{};
  final Set<String> _selectedNoteIds = <String>{};
  bool get _selectionMode => _selectedNoteIds.isNotEmpty;
  List<Note> get _selectedNotes => filtered.where((note) => _selectedNoteIds.contains(note.id)).toList();
  final textColorPalette=<int>[];
  bool showPinnedOnly=false;
  bool isSearchExpanded=false;
  final noteBackgroundColors=<String, int>{};
  static const defaultThemes=[NoteTheme('یاسی',0xFFEDE7F6),NoteTheme('آبی',0xFFE3F2FD),NoteTheme('سبز',0xFFE8F5E9),NoteTheme('صورتی',0xFFFCE4EC),NoteTheme('هلویی',0xFFFFEAD5)];

  @override
  void initState(){super.initState();WidgetsBinding.instance.addObserver(this);search.addListener(()=>setState((){}));noteAudioPlayer.onPlayerComplete.listen((_){if(mounted)setState(()=>currentlyPlayingAudio=null);});load();}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !loading) {
      // A native Android screen (such as Quick Note) may have changed the
      // SharedPreferences file while this Flutter page stayed in memory.
      // Reload the notebook instead of only rebuilding the old in-memory list.
      _reloadNotesFromStorage();
    }
  }

  Future<void> _reloadNotesFromStorage() async {
    try {
      final latestNotes = await repository.loadNotes();
      if (!mounted) return;
      setState(() {
        notes
          ..clear()
          ..addAll(latestNotes);
        featuredNote = _randomNote(latestNotes, excludeId: featuredNote?.id);
        _randomizeNoteBackgrounds();
      });
    } catch (error, stackTrace) {
      debugPrint('Notebook refresh failed: $error\\n$stackTrace');
    }
  }

  void _randomizeNoteBackgrounds() {
    final availableThemes = themes.where((theme) => randomThemeNames.contains(theme.name)).toList();
    final themePool = availableThemes.isNotEmpty
        ? availableThemes
        : (themes.isEmpty ? defaultThemes : themes);
    if (themePool.isEmpty) return;
    final random = Random();
    noteBackgroundColors
      ..clear()
      ..addEntries(notes.map((note) => MapEntry(
        note.id,
        themePool[random.nextInt(themePool.length)].backgroundColor,
      )));
  }

  int _backgroundColorFor(Note note) {
    final availableThemes = themes.where((theme) => randomThemeNames.contains(theme.name)).toList();
    final themePool = availableThemes.isNotEmpty
        ? availableThemes
        : (themes.isEmpty ? defaultThemes : themes);
    if (themePool.isEmpty) return note.themeColor;
    return noteBackgroundColors.putIfAbsent(
      note.id,
      () => themePool[Random().nextInt(themePool.length)].backgroundColor,
    );
  }

  void _refreshFeaturedNote() {
    if (!mounted || loading) return;
    setState(() => featuredNote = _randomNote(notes, excludeId: featuredNote?.id));
  }
  Future<void> load() async {
    try {
      final loadedNotes = await repository.loadNotes();
      final loadedThemes = await repository.loadThemes();
      final loadedFolders = await repository.loadFolders();
      final loadedFonts = await repository.loadCustomFonts();
      final loadedRandomThemeNames = await repository.loadRandomThemeNames();
      final loadedPinnedNoteIds = await repository.loadPinnedNoteIds();
      final loadedPinnedFolderIds = await repository.loadPinnedFolderIds();
      final loadedTextColorPalette = await repository.loadTextColorPalette();
      final loadedAppFontFamily = await repository.loadAppInterfaceFontFamily();
      final loadedAppTheme = await repository.loadAppTheme();
      notes.addAll(loadedNotes);
      featuredNote = _randomNote(loadedNotes);
      themes.addAll(loadedThemes);
      folders.addAll(loadedFolders);
      customFonts.addAll(loadedFonts);
      randomThemeNames.addAll(loadedRandomThemeNames);
      pinnedNoteIds.addAll(loadedPinnedNoteIds);
      pinnedFolderIds.addAll(loadedPinnedFolderIds);
      textColorPalette.addAll(loadedTextColorPalette);
      for (final entry in customFonts.entries) {
        try {
          final file = File(entry.value);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final loader = FontLoader(entry.key)..addFont(Future.value(ByteData.sublistView(bytes)));
            await loader.load();
          }
        } catch (_) { /* An unavailable custom font must not block opening the notebook. */ }
      }
      appInterfaceFontFamily.value = customFonts.containsKey(loadedAppFontFamily)
          ? loadedAppFontFamily
          : 'Estedad';
      appThemeName.value = ['سفید', 'سیاه', 'دودی', 'نقره‌ای'].contains(loadedAppTheme) ? loadedAppTheme : 'دودی';
      if (themes.isEmpty) themes.addAll(defaultThemes);
      if (randomThemeNames.isEmpty) randomThemeNames.addAll(themes.map((theme) => theme.name));
      _randomizeNoteBackgrounds();
      if (mounted) setState(() => loading = false);
      await persistThemes();
    } catch (error, stackTrace) {
      debugPrint('Notebook load failed: $error\\n$stackTrace');
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> persist() => repository.saveNotes(notes);
  Future<void> persistFolders() => repository.saveFolders(folders);
  Future<void> persistThemes() => repository.saveThemes(themes);
  Future<void> persistPinnedNotes() => repository.savePinnedNoteIds(pinnedNoteIds.toList());
  Future<void> persistPinnedFolders() => repository.savePinnedFolderIds(pinnedFolderIds.toList());

  Future<void> togglePinnedNote(Note note) async {
    setState(() {
      if (!pinnedNoteIds.add(note.id)) pinnedNoteIds.remove(note.id);
    });
    await persistPinnedNotes();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(pinnedNoteIds.contains(note.id) ? 'یادداشت سنجاق شد' : 'سنجاق یادداشت برداشته شد'),
      ));
    }
  }

  Future<void> togglePinnedFolder(NoteFolder folder) async {
    setState(() {
      if (!pinnedFolderIds.add(folder.id)) pinnedFolderIds.remove(folder.id);
    });
    await persistPinnedFolders();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(pinnedFolderIds.contains(folder.id) ? 'پوشه سنجاق شد' : 'سنجاق پوشه برداشته شد'),
      ));
    }
  }

  Future<void> createFolder() async {
    final controller=TextEditingController();
    final name=await showDialog<String>(context:context,builder:(c)=>Directionality(textDirection:TextDirection.rtl,child:AlertDialog(
      title:const Text('ایجاد پوشه'),content:TextField(controller:controller,autofocus:true,maxLength:30,decoration:const InputDecoration(labelText:'نام پوشه',hintText:'مثلاً کار و پروژه‌ها')),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(c,controller.text.trim()),child:const Text('ایجاد'))])));
    controller.dispose();
    if(name==null||name.trim().isEmpty)return;
    final folder=NoteFolder(DateTime.now().microsecondsSinceEpoch.toString(),name.trim());
    setState((){folders.add(folder);selectedFolderId=folder.id;showUnfiledOnly=false;showPinnedOnly=false;});
    await persistFolders();
  }
  Future<void> moveNote(Note note) async {
    final folderScrollController = ScrollController();
    final destination = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        final availableListHeight = MediaQuery.sizeOf(dialogContext).height * 0.55;
        final listHeight = (folders.length * 56.0)
            .clamp(0.0, availableListHeight)
            .toDouble();

        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('انتقال یادداشت به پوشه'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.inbox_outlined),
                    title: const Text('بدون پوشه'),
                    onTap: () => Navigator.pop(dialogContext, ''),
                  ),
                  if (folders.isNotEmpty)
                    SizedBox(
                      height: listHeight,
                      child: Scrollbar(
                        controller: folderScrollController,
                        thumbVisibility: true,
                        interactive: true,
                        child: ListView.builder(
                          controller: folderScrollController,
                          primary: false,
                          itemCount: folders.length,
                          itemBuilder: (context, index) {
                            final folder = folders[index];
                            return ListTile(
                              leading: const Icon(Icons.folder_outlined),
                              title: Text(
                                folder.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.pop(dialogContext, folder.id),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('انصراف'),
              ),
            ],
          ),
        );
      },
    );
    folderScrollController.dispose();

    if (destination == null) return;
    final id = destination.isEmpty ? null : destination;
    setState(() {
      final i = notes.indexWhere((n) => n.id == note.id);
      if (i >= 0) {
        final n = notes[i];
        notes[i] = Note(
          n.id, n.title, n.body, n.updated, List.of(n.images),
          n.themeColor, n.themeTextColor, n.themeFontFamily, id,
          List.of(n.audios),
        );
      }
    });
    await persist();
  }
  Future<void> manageFolders() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => FolderManagerDialog(
        initialFolders: List<NoteFolder>.of(folders),
        onSave: (updatedFolders, deletedIds) async {
          setState(() {
            folders..clear()..addAll(updatedFolders);
            for (final folderId in deletedIds) {
              pinnedFolderIds.remove(folderId);
              if (selectedFolderId == folderId) selectedFolderId = null;
              for (var i = 0; i < notes.length; i++) {
                final note = notes[i];
                if (note.folderId == folderId) {
                  notes[i] = Note(note.id, note.title, note.body, note.updated,
                    List.of(note.images), note.themeColor, note.themeTextColor,
                    note.themeFontFamily, null, List.of(note.audios));
                }
              }
            }
          });
          await persistFolders();
          await persist();
          await persistPinnedFolders();
        },
        onSelect: (folder) {
          setState(() { selectedFolderId = folder.id; showUnfiledOnly = false; showPinnedOnly = false; });
        },
        initialPinnedFolderIds: Set<String>.of(pinnedFolderIds),
        onTogglePin: togglePinnedFolder,
      ),
    );
  }

  Future<void> manageThemes() async {
    final result=await showDialog<ThemeManagerResult>(context:context,builder:(context)=>ThemeManagerDialog(
      initialThemes:List.of(themes),
      customFonts:customFonts.keys.toList(),
      initialRandomThemeNames:randomThemeNames.toList(),
      initialTextColorPalette:List<int>.of(textColorPalette),
      initialAppFontFamily:appInterfaceFontFamily.value,
      initialAppThemeName:appThemeName.value,
      onAddCustomFont:() async {
        await addCustomFont();
        return customFonts.keys.toList();
      },
    ));
    if(result!=null){
      setState((){
        themes..clear()..addAll(result.themes);
        randomThemeNames..clear()..addAll(result.randomThemeNames);
        textColorPalette..clear()..addAll(result.textColorPalette);        appInterfaceFontFamily.value = result.appFontFamily;
        appThemeName.value = result.appThemeName;
      });
      await persistThemes();
      await repository.saveRandomThemeNames(randomThemeNames.toList());
      await repository.saveTextColorPalette(textColorPalette);
      await repository.saveAppInterfaceFontFamily(result.appFontFamily);
      await repository.saveAppTheme(result.appThemeName);
      await HomeWidgetSync.refresh();
    }
  }
  Future<void> addCustomFont() async {
    final picked=await FilePicker.pickFiles(type:FileType.custom,allowedExtensions:['ttf','otf']);
    if(picked.isEmpty)return;
    var added = 0;
    final failures = <String>[];
    for (final file in picked) {
    final filePath = file.path;
    if (filePath == null || filePath.isEmpty) {
      failures.add(file.name);
      continue;
    }
    try {
      final bytes = await File(filePath).readAsBytes();
    final parts=file.name.split('.');
    final original=parts.length>1?parts.sublist(0,parts.length-1).join('.'):file.name;
    final family = 'custom_${original.replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_')}_${DateTime.now().microsecondsSinceEpoch}';
    final dir=await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/custom_fonts');
    if(!await folder.exists())await folder.create(recursive:true);
    final ext=(file.extension??'ttf').toLowerCase();
    final saved = File('${folder.path}/$family.$ext');
    await saved.writeAsBytes(bytes,flush:true);
    try {
      final loader=FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    } catch(e) {
      failures.add(file.name);
      continue;
    }
    customFonts[family]=saved.path;
    added++;
    } catch (error) { failures.add(file.name); }
    }
    if (added > 0) await repository.saveCustomFonts(customFonts);
    if(mounted){
      setState((){});
      final message = failures.isEmpty ? '$added فونت با موفقیت اضافه شد.' : '$added فونت اضافه شد؛ ${failures.length} فایل ناموفق بود.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
    }
  }
  Note? _randomNote(List<Note> source, {String? excludeId}) {
    if (source.isEmpty) return null;
    final candidates = excludeId == null ? source : source.where((note) => note.id != excludeId).toList();
    final pool = candidates.isEmpty ? source : candidates;
    return pool[Random().nextInt(pool.length)];
  }

  Widget _folderFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? scheme.primary.withValues(alpha: .55) : scheme.outlineVariant.withValues(alpha: .55),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
                if (label.isNotEmpty) const SizedBox(width: 5),
              ],
              if (label.isNotEmpty) Text(
                label,
                style: TextStyle(
                  color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Note> get filtered {
    final q=search.text.trim().toLowerCase();
    final list=notes.where((n) =>
      (!showPinnedOnly || pinnedNoteIds.contains(n.id)) &&
      // A non-empty search is global: do not restrict matches to the
      // currently selected folder or the unfiled-notes view.
      (q.isNotEmpty ||
          (showPinnedOnly
              ? true
              : showUnfiledOnly
                  ? n.folderId == null
                  : selectedFolderId != null && n.folderId == selectedFolderId)) &&
      (n.title.toLowerCase().contains(q) || _notePlainText(n.body).toLowerCase().contains(q))
    ).toList();
    list.sort((a,b){
      final pinOrder=(pinnedNoteIds.contains(b.id)?1:0).compareTo(pinnedNoteIds.contains(a.id)?1:0);
      return pinOrder!=0?pinOrder:b.updated.compareTo(a.updated);
    });
    return list;
  }
  List<String> _matchingLines(Note note, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];
    return _notePlainText(note.body).split(RegExp(r'\r?\n'))
        .where((line) => line.toLowerCase().contains(normalized))
        .map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
  }
  Widget _searchHighlightedText(String text, String query, {required Color textColor, required String? fontFamily}) {
    final needle = query.trim();
    if (needle.isEmpty) return Text(text, style: TextStyle(color: textColor, fontFamily: fontFamily));
    final lowerText = text.toLowerCase();
    final lowerNeedle = needle.toLowerCase();
    final spans = <TextSpan>[];
    var cursor = 0;
    while (cursor < text.length) {
      final found = lowerText.indexOf(lowerNeedle, cursor);
      if (found < 0) { spans.add(TextSpan(text: text.substring(cursor))); break; }
      if (found > cursor) spans.add(TextSpan(text: text.substring(cursor, found)));
      final end = found + needle.length;
      spans.add(TextSpan(text: text.substring(found, end), style: const TextStyle(color: Color(0xFF7A3E00), backgroundColor: Color(0xFFFFD54F), fontWeight: FontWeight.w900)));
      cursor = end;
    }
    return RichText(text: TextSpan(style: TextStyle(color: textColor, fontFamily: fontFamily, fontWeight: FontWeight.w600), children: spans));
  }

  Future<void> edit({Note? note, String? searchQuery}) async {
    final availableThemes = themes.where((theme) => randomThemeNames.contains(theme.name)).toList();
    final themePool = availableThemes.isEmpty ? (themes.isEmpty ? defaultThemes : themes) : availableThemes;
    final selected=note==null?themePool[Random().nextInt(themePool.length)]:NoteTheme('فعلی',note.themeColor,note.themeTextColor,note.themeFontFamily);
    const builtInFonts = ['sans-serif'];
    final availableFonts = {...builtInFonts, ...customFonts.keys}.toList();
    final selectedFont = note == null
        ? availableFonts[Random().nextInt(availableFonts.length)]
        : selected.fontFamily;
    final initialTheme = NoteTheme(selected.name, selected.backgroundColor, selected.textColor, selectedFont);
    final result=await Navigator.push<Note>(context,MaterialPageRoute(builder:(_)=>EditorPage(note:note,searchQuery:searchQuery,themes:themes,customFonts:customFonts.keys.toList(),previousTitles:notes.map((item)=>item.title.trim()).where((value)=>value.isNotEmpty).toSet().toList(),existingNotes:List<Note>.of(notes),initialTheme:initialTheme,initialFolderId:note?.folderId??selectedFolderId,backgroundColorOverride:note == null ? null : _backgroundColorFor(note),onAutoSave:(draft) async { if(!mounted)return; setState(() { final i=notes.indexWhere((n)=>n.id==draft.id); if(i<0){notes.add(draft);}else{notes[i]=draft;} }); await persist(); })));
    if(result==null){_refreshFeaturedNote();return;}
    setState(() { final i=notes.indexWhere((n)=>n.id==result.id); if(i<0){notes.add(result);}else{notes[i]=result;} if(featuredNote?.id==result.id)featuredNote=result; });
    await persist();
    _refreshFeaturedNote();
  }
  void _toggleNoteSelection(Note note) {
    setState(() {
      if (!_selectedNoteIds.add(note.id)) _selectedNoteIds.remove(note.id);
    });
  }

  void _selectAllVisibleNotes() {
    final ids = filtered.map((note) => note.id).toSet();
    setState(() {
      if (ids.isNotEmpty && _selectedNoteIds.containsAll(ids)) {
        _selectedNoteIds.removeAll(ids);
      } else {
        _selectedNoteIds.addAll(ids);
      }
    });
  }

  void _clearSelection() => setState(_selectedNoteIds.clear);

  Future<void> _deleteSelectedNotes() async {
    final selected = _selectedNotes;
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف گروهی یادداشت‌ها'),
        content: Text('آیا از حذف ${selected.length} یادداشت انتخاب‌شده مطمئن هستی؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    final ids = selected.map((note) => note.id).toSet();
    setState(() {
      notes.removeWhere((note) => ids.contains(note.id));
      _selectedNoteIds.clear();
      if (featuredNote != null && ids.contains(featuredNote!.id)) {
        featuredNote = _randomNote(notes);
      }
    });
    await persist();
  }

  Future<void> _moveSelectedNotes() async {
    final selected = _selectedNotes;
    if (selected.isEmpty) return;
    final controller = ScrollController();
    final destination = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        final height = (folders.length * 56.0)
            .clamp(0.0, MediaQuery.sizeOf(dialogContext).height * .55)
            .toDouble();
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text('انتقال ${selected.length} یادداشت به پوشه'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                  leading: const Icon(Icons.inbox_outlined),
                  title: const Text('بدون پوشه'),
                  onTap: () => Navigator.pop(dialogContext, ''),
                ),
                if (folders.isNotEmpty)
                  SizedBox(
                    height: height,
                    child: Scrollbar(
                      controller: controller,
                      thumbVisibility: true,
                      interactive: true,
                      child: ListView.builder(
                        controller: controller,
                        primary: false,
                        itemCount: folders.length,
                        itemBuilder: (context, index) {
                          final folder = folders[index];
                          return ListTile(
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => Navigator.pop(dialogContext, folder.id),
                          );
                        },
                      ),
                    ),
                  ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
            ],
          ),
        );
      },
    );
    controller.dispose();
    if (destination == null) return;
    final targetFolderId = destination.isEmpty ? null : destination;
    final ids = selected.map((note) => note.id).toSet();
    setState(() {
      for (var i = 0; i < notes.length; i++) {
        final note = notes[i];
        if (!ids.contains(note.id)) continue;
        notes[i] = Note(
          note.id, note.title, note.body, DateTime.now(), List.of(note.images),
          note.themeColor, note.themeTextColor, note.themeFontFamily,
          targetFolderId, List.of(note.audios),
        );
      }
      _selectedNoteIds.clear();
    });
    await persist();
  }

  Future<void> _applyThemeToAllNotes({required bool randomize}) async {
    if (notes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هنوز یادداشتی برای تغییر تم وجود ندارد.')),
      );
      return;
    }
    if (themes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هنوز تمی برای انتخاب وجود ندارد.')),
      );
      return;
    }

    NoteTheme? selectedTheme;
    if (!randomize) {
      selectedTheme = await showDialog<NoteTheme>(
        context: context,
        builder: (dialogContext) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('انتخاب تم برای تمام نوشته‌ها'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: themes.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final theme = themes[index];
                  return Material(
                    color: Color(theme.backgroundColor),
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Color(theme.textColor),
                        child: Icon(Icons.text_fields, color: Color(theme.backgroundColor)),
                      ),
                      title: Text(theme.name, style: TextStyle(
                        color: Color(theme.textColor),
                        fontFamily: theme.fontFamily,
                        fontWeight: FontWeight.bold,
                      )),
                      subtitle: Text('پیش‌نمایش متن یادداشت', style: TextStyle(
                        color: Color(theme.textColor),
                        fontFamily: theme.fontFamily,
                      )),
                      onTap: () => Navigator.pop(dialogContext, theme),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('انصراف'),
              ),
            ],
          ),
        ),
      );
      if (selectedTheme == null || !mounted) return;
    }

    final random = Random();
    setState(() {
      for (var i = 0; i < notes.length; i++) {
        final note = notes[i];
        final theme = randomize
            ? themes[random.nextInt(themes.length)]
            : selectedTheme!;
        notes[i] = Note(
          note.id,
          note.title,
          note.body,
          note.updated,
          List<String>.of(note.images),
          theme.backgroundColor,
          theme.textColor,
          theme.fontFamily,
          note.folderId,
          List<String>.of(note.audios),
        );
        noteBackgroundColors.remove(note.id);
        if (featuredNote?.id == note.id) featuredNote = notes[i];
      }
    });
    await persist();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(randomize
              ? 'برای هر یادداشت یک تم تصادفی اعمال شد.'
              : 'تم «${selectedTheme!.name}» روی تمام نوشته‌ها اعمال شد.'),
        ),
      );
    }
  }

  Future<void> _changeSelectedNotesTheme() async {
    final selected = _selectedNotes;
    if (selected.isEmpty) return;
    if (themes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمی برای انتخاب وجود ندارد.')),
      );
      return;
    }
    final chosenTheme = await showDialog<NoteTheme>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تغییر تم ${selected.length} یادداشت'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: themes.length,
              separatorBuilder: (context, index) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final theme = themes[index];
                return Material(
                  color: Color(theme.backgroundColor),
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    title: Text(theme.name, style: TextStyle(
                      color: Color(theme.textColor),
                      fontFamily: theme.fontFamily,
                      fontWeight: FontWeight.bold,
                    )),
                    subtitle: Text('نمونه متن یادداشت', style: TextStyle(
                      color: Color(theme.textColor),
                      fontFamily: theme.fontFamily,
                    )),
                    onTap: () => Navigator.pop(dialogContext, theme),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
          ],
        ),
      ),
    );
    if (chosenTheme == null || !mounted) return;
    final ids = selected.map((note) => note.id).toSet();
    setState(() {
      for (var i = 0; i < notes.length; i++) {
        final note = notes[i];
        if (!ids.contains(note.id)) continue;
        notes[i] = Note(
          note.id, note.title, note.body, DateTime.now(), List.of(note.images),
          chosenTheme.backgroundColor, chosenTheme.textColor, chosenTheme.fontFamily,
          note.folderId, List.of(note.audios),
        );
        noteBackgroundColors.remove(note.id);
        if (featuredNote?.id == note.id) featuredNote = notes[i];
      }
      _selectedNoteIds.clear();
    });
    await persist();
  }

  Future<void> _exportSelectedNotes() async {
    final selected = _selectedNotes;
    if (selected.isEmpty) return;
    try {
      final archive = Archive();
      final usedNames = <String>{};
      for (final note in selected) {
        final bytes = await _buildDocx([note]);
        var baseName = (note.title.trim().isEmpty ? 'بدون عنوان' : note.title.trim())
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
            .replaceAll(RegExp(r'\s+'), '_');
        if (baseName.length > 72) baseName = baseName.substring(0, 72);
        var filename = '$baseName.docx';
        var suffix = 2;
        while (!usedNames.add(filename.toLowerCase())) {
          filename = '$baseName ($suffix).docx';
          suffix++;
        }
        archive.addFile(ArchiveFile(filename, bytes.length, bytes));
      }
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));
      final savedPath = await FilePicker.saveFile(fileName: 'یادداشت‌های_انتخاب‌شده.zip', bytes: zipBytes);
      if (savedPath != null && mounted) setState(_selectedNoteIds.clear);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ساخت خروجی گروهی ناموفق بود: $error')),
        );
      }
    }
  }

  Future<void> remove(Note n) async {
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:const Text('حذف یادداشت؟'),content:const Text('این یادداشت حذف خواهد شد.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('حذف'))]));
    if(yes==true){setState((){notes.removeWhere((x)=>x.id==n.id);if(featuredNote?.id==n.id)featuredNote=_randomNote(notes);});await persist();}
  }

  String _xmlEscape(String value) => value.replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;').replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;').replaceAll("'", '&apos;');

  List<Map<String, dynamic>> _deltaForNote(Note note) {
    const marker = '__quill_note_v1__';
    if (note.body.startsWith(marker)) {
      try { return (jsonDecode(note.body.substring(marker.length)) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(); } catch (_) {}
    }
    final legacy = _decodeNoteBlocks(note.body);
    final ops = <Map<String, dynamic>>[];
    for (final item in legacy) {
      if (item['type'] == 'image') { ops.add({'insert': {'image': item['path']}}); ops.add({'insert': '\n'}); }
      else { ops.add({'insert': '${item['text'] as String? ?? ''}\n'}); }
    }
    return ops;
  }

  String _docxRun(String value, Map attributes) {
    if (value.isEmpty) return '';
    final props = StringBuffer();
    if (attributes['bold'] == true) props.write('<w:b/>');
    if (attributes['italic'] == true) props.write('<w:i/>');
    if (attributes['underline'] == true) props.write('<w:u w:val="single"/>');
    if (attributes['strike'] == true) props.write('<w:strike/>');
    final color = attributes['color'];
    if (color is String && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(color)) props.write('<w:color w:val="$color"/>');
    final background = attributes['background'];
    if (background is String && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(background)) props.write('<w:shd w:fill="$background"/>');
    final size = double.tryParse('${attributes['size'] ?? ''}');
    if (size != null) { final half = (size * 2).round(); props.write('<w:sz w:val="$half"/><w:szCs w:val="$half"/>'); }
    final font = attributes['font'];
    if (font is String && font.isNotEmpty) props.write('<w:rFonts w:ascii="${_xmlEscape(font)}" w:hAnsi="${_xmlEscape(font)}" w:eastAsia="${_xmlEscape(font)}"/>');
    final rPr = props.isEmpty ? '' : '<w:rPr>${props.toString()}</w:rPr>';
    return '<w:r>$rPr<w:t xml:space="preserve">${_xmlEscape(value)}</w:t></w:r>';
  }

  String _docxImageDrawing(String relationshipId) => '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="4572000" cy="3048000"/><wp:docPr id="1" name="Embedded image"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="0" name="image"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="$relationshipId"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="4572000" cy="3048000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';

  Future<Uint8List> _buildDocx(List<Note> selected) async {
    final archive = Archive();
    final media = <String, List<int>>{};
    final relationships = <String>[];
    var imageIndex = 0;
    final paragraphs = <String>[];
    for (final note in selected) {
      paragraphs.add('<w:p><w:pPr><w:pStyle w:val="Title"/></w:pPr>${_docxRun(note.title.isEmpty ? 'بدون عنوان' : note.title, {'bold': true, 'size': 20})}</w:p>');
      var runs = StringBuffer();
      var paragraphAttributes = <String, dynamic>{};
      void flushParagraph() {
        final pPr = StringBuffer();
        final header = paragraphAttributes['header'];
        if (header == 1 || header == 2 || header == 3) pPr.write('<w:pStyle w:val="Heading$header"/>');
        final align = paragraphAttributes['align'];
        if (align == 'center' || align == 'right' || align == 'left' || align == 'justify') pPr.write('<w:jc w:val="$align"/>');
        final listType = paragraphAttributes['list'];
        if (listType == 'bullet' || listType == 'ordered') pPr.write('<w:numPr><w:ilvl w:val="0"/><w:numId w:val="${listType == 'ordered' ? 2 : 1}"/></w:numPr>');
        paragraphs.add('<w:p>${pPr.isEmpty ? '' : '<w:pPr>${pPr.toString()}</w:pPr>'}${runs.toString()}</w:p>');
        runs = StringBuffer();
        paragraphAttributes = <String, dynamic>{};
      }
      for (final operation in _deltaForNote(note)) {
        final insert = operation['insert'];
        final attrs = operation['attributes'] is Map ? Map<String, dynamic>.from(operation['attributes'] as Map) : <String, dynamic>{};
        if (insert is String) {
          paragraphAttributes.addAll(attrs);
          final pieces = insert.split('\n');
          for (var i = 0; i < pieces.length; i++) {
            if (pieces[i].isNotEmpty) runs.write(_docxRun(pieces[i], attrs));
            if (i < pieces.length - 1) flushParagraph();
          }
        } else if (insert is Map && insert['image'] is String) {
          final path = insert['image'] as String;
          final file = File(path);
          if (await file.exists()) {
            final ext = path.toLowerCase().endsWith('.png') ? 'png' : path.toLowerCase().endsWith('.gif') ? 'gif' : 'jpg';
            final name = 'image${++imageIndex}.$ext';
            media['word/media/$name'] = await file.readAsBytes();
            final rid = 'rIdImage$imageIndex';
            relationships.add('<Relationship Id="$rid" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/$name"/>');
            runs.write(_docxImageDrawing(rid));
          }        }      }
      if (runs.isNotEmpty) flushParagraph();
      paragraphs.add('<w:p/>');
    }
    for (final entry in media.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    final document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>${paragraphs.join()}<w:sectPr/></w:body></w:document>';
    final contentTypes = '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="jpg" ContentType="image/jpeg"/><Default Extension="png" ContentType="image/png"/><Default Extension="gif" ContentType="image/gif"/><Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>';
    final rootRels = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>';
    relationships.add('<Relationship Id="rIdNumbering" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>');
    final docRels = '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${relationships.join()}</Relationships>';
    final numbering = '<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="singleLevel"/><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="•"/><w:lvlJc w:val="right"/><w:pPr><w:tabs><w:tab w:val="num" w:pos="720"/></w:tabs><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl></w:abstractNum><w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="singleLevel"/><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/><w:lvlJc w:val="right"/><w:pPr><w:tabs><w:tab w:val="num" w:pos="720"/></w:tabs><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl></w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num><w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num></w:numbering>';
    archive
      ..addFile(ArchiveFile('[Content_Types].xml', contentTypes.length, utf8.encode(contentTypes)))
      ..addFile(ArchiveFile('_rels/.rels', rootRels.length, utf8.encode(rootRels)))
      ..addFile(ArchiveFile('word/_rels/document.xml.rels', docRels.length, utf8.encode(docRels)))
      ..addFile(ArchiveFile('word/numbering.xml', numbering.length, utf8.encode(numbering)))
      ..addFile(ArchiveFile('word/document.xml', document.length, utf8.encode(document)));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Future<void> exportDocx(List<Note> selected) async {
    if (selected.isEmpty) return;
    final bytes = await _buildDocx(selected);
    final name = selected.length == 1
        ? '${(selected.first.title.isEmpty ? 'note' : selected.first.title).replaceAll(RegExp(r'[^\w\-آ-ی]'), '_')}.docx'
        : 'notebook_export.docx';
    try {
      await FilePicker.saveFile(fileName: name, bytes: bytes);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ذخیره فایل Word انجام نشد: $e')));
    }
  }

  Future<Note?> _noteFromDocx(PlatformFile file) async {
    final bytes = await file.readAsBytes();
    final zip = ZipDecoder().decodeBytes(bytes);
    final documentFile = zip.findFile('word/document.xml');
    if (documentFile == null) return null;
    final xml = XmlDocument.parse(utf8.decode(documentFile.content as List<int>));
    final relsFile = zip.findFile('word/_rels/document.xml.rels');
    final relationships = <String, String>{};
    if (relsFile != null) {
      final rels = XmlDocument.parse(utf8.decode(relsFile.content as List<int>));
      for (final rel in rels.descendants.whereType<XmlElement>().where((e) => e.name.local == 'Relationship')) {
        final id = rel.attributes.where((a) => a.name.local == 'Id').map((a) => a.value).firstOrNull;
        final target = rel.attributes.where((a) => a.name.local == 'Target').map((a) => a.value).firstOrNull;
        if (id != null && target != null) relationships[id] = target;
      }
    }
    final numberingFormats = <String, String>{};
    final numberingFile = zip.findFile('word/numbering.xml');
    if (numberingFile != null) {
      final numberingXml = XmlDocument.parse(utf8.decode(numberingFile.content as List<int>));
      final abstractFormats = <String, String>{};
      for (final item in numberingXml.descendants.whereType<XmlElement>().where((e) => e.name.local == 'abstractNum')) {
        final abstractId = item.attributes.where((a) => a.name.local == 'abstractNumId').map((a) => a.value).firstOrNull;
        final format = item.descendants.whereType<XmlElement>().where((e) => e.name.local == 'numFmt').firstOrNull?.attributes.where((a) => a.name.local == 'val').map((a) => a.value).firstOrNull;
        if (abstractId != null && format != null) abstractFormats[abstractId] = format;
      }
      for (final item in numberingXml.descendants.whereType<XmlElement>().where((e) => e.name.local == 'num')) {
        final numId = item.attributes.where((a) => a.name.local == 'numId').map((a) => a.value).firstOrNull;
        final abstractId = item.descendants.whereType<XmlElement>().where((e) => e.name.local == 'abstractNumId').firstOrNull?.attributes.where((a) => a.name.local == 'val').map((a) => a.value).firstOrNull;
        if (numId != null && abstractId != null && abstractFormats.containsKey(abstractId)) numberingFormats[numId] = abstractFormats[abstractId]!;
      }
    }
    final imageDirRoot = await getApplicationDocumentsDirectory();
    final imageDir = Directory('${imageDirRoot.path}/notebook_images');
    if (!await imageDir.exists()) await imageDir.create(recursive: true);
    final operations = <Map<String, dynamic>>[];
    final imagePaths = <String>[];
    final paragraphs = xml.descendants.whereType<XmlElement>().where((e) => e.name.local == 'p').toList();
    // Use the source filename as the note title and retain every paragraph
    // from the DOCX document in the note body.
    final importedTitle = file.name
        .replaceFirst(RegExp(r'\.docx$', caseSensitive: false), '')
        .trim();
    for (final paragraph in paragraphs) {
      final pPr = paragraph.children.whereType<XmlElement>().where((e) => e.name.local == 'pPr').firstOrNull;
      final lineAttrs = <String, dynamic>{};
      if (pPr != null) {
        final style = pPr.descendants.whereType<XmlElement>().where((e) => e.name.local == 'pStyle').firstOrNull;
        final styleVal = style?.attributes.where((a) => a.name.local == 'val').map((a) => a.value).firstOrNull ?? '';
        final heading = RegExp(r'Heading([1-3])', caseSensitive: false).firstMatch(styleVal);
        if (heading != null) lineAttrs['header'] = int.parse(heading.group(1)!);
        final jc = pPr.descendants.whereType<XmlElement>().where((e) => e.name.local == 'jc').firstOrNull;
        final align = jc?.attributes.where((a) => a.name.local == 'val').map((a) => a.value).firstOrNull;
        if (align != null) lineAttrs['align'] = align;
        final numId = pPr.descendants.whereType<XmlElement>().where((e) => e.name.local == 'numId').firstOrNull?.attributes.where((a) => a.name.local == 'val').map((a) => a.value).firstOrNull;
        if (numId != null) { final format = numberingFormats[numId]; lineAttrs['list'] = format == null || format == 'bullet' ? 'bullet' : 'ordered'; }
      }
      for (final run in paragraph.descendants.whereType<XmlElement>().where((e) => e.name.local == 'r')) {
        final rPr = run.children.whereType<XmlElement>().where((e) => e.name.local == 'rPr').firstOrNull;
        final attrs = <String, dynamic>{};
        if (rPr != null) {
          if (rPr.descendants.whereType<XmlElement>().any((e) => e.name.local == 'b')) attrs['bold'] = true;
          if (rPr.descendants.whereType<XmlElement>().any((e) => e.name.local == 'i')) attrs['italic'] = true;
          if (rPr.descendants.whereType<XmlElement>().any((e) => e.name.local == 'u')) attrs['underline'] = true;
          if (rPr.descendants.whereType<XmlElement>().any((e) => e.name.local == 'strike')) attrs['strike'] = true;
          final color = rPr.descendants.whereType<XmlElement>().where((e) => e.name.local == 'color').firstOrNull;
          final colorValue = color?.attributes.where((a) => a.name.local == 'val').map((a) => a.value).firstOrNull;
          if (colorValue != null && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(colorValue)) attrs['color'] = colorValue;
          final shade = rPr.descendants.whereType<XmlElement>().where((e) => e.name.local == 'shd').firstOrNull;
          final shadeValue = shade?.attributes.where((a) => a.name.local == 'fill').map((a) => a.value).firstOrNull;
          if (shadeValue != null && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(shadeValue)) attrs['background'] = shadeValue;
          final size = rPr.descendants.whereType<XmlElement>().where((e) => e.name.local == 'sz').firstOrNull;
          final sizeValue = size?.attributes.where((a) => a.name.local == 'val').map((a) => a.value).firstOrNull;
          if (sizeValue != null) { final parsed = int.tryParse(sizeValue); if (parsed != null) attrs['size'] = (parsed / 2).toString(); }
          final fonts = rPr.descendants.whereType<XmlElement>().where((e) => e.name.local == 'rFonts').firstOrNull;
          final fontValue = fonts?.attributes.where((a) => a.name.local == 'ascii').map((a) => a.value).firstOrNull;
          if (fontValue != null) attrs['font'] = fontValue;
        }
        for (final textElement in run.descendants.whereType<XmlElement>().where((e) => e.name.local == 't')) {
          if (textElement.innerText.isNotEmpty) operations.add({'insert': textElement.innerText, if (attrs.isNotEmpty) 'attributes': attrs});
        }
        for (final blip in run.descendants.whereType<XmlElement>().where((e) => e.name.local == 'blip')) {
          final rid = blip.attributes.where((a) => a.name.local == 'embed').map((a) => a.value).firstOrNull;
          final target = rid == null ? null : relationships[rid];
          if (target == null) continue;
          final mediaPath = target.startsWith('/') ? target.substring(1) : target.startsWith('../') ? 'word/${target.substring(3)}' : 'word/$target';
          final normalized = mediaPath;
          final mediaFile = zip.findFile(normalized) ?? zip.findFile(mediaPath);
          if (mediaFile == null) continue;
          final ext = normalized.contains('.') ? normalized.substring(normalized.lastIndexOf('.')) : '.png';
          final path = '${imageDir.path}/imported_${DateTime.now().microsecondsSinceEpoch}_${imagePaths.length}$ext';
          await File(path).writeAsBytes(mediaFile.content as List<int>);
          imagePaths.add(path);
          operations.add({'insert': {'image': path}});
        }
      }
      operations.add({'insert': '\n', if (lineAttrs.isNotEmpty) 'attributes': lineAttrs});
    }
    if (operations.isEmpty) operations.add({'insert': '\n'});
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    return Note(id, importedTitle, '__quill_note_v1__${jsonEncode(operations)}', DateTime.now(), imagePaths);
  }

  Future<void> importDocx() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['docx'],
      );
      if (files.isEmpty) return;      final imported = <Note>[];
      final failures = <String>[];
      for (final file in files) {
        try {
          final note = await _noteFromDocx(file);
          if (note != null) {
            imported.add(note);
          } else {
            failures.add(file.name);
          }
        } catch (error) {
          debugPrint('DOCX import failed for ${file.name}: $error');
          failures.add(file.name);
        }
      }
      if (imported.isNotEmpty) {
        setState(() => notes.addAll(imported));
        await persist();
      }
      if (mounted) {
        final message = failures.isEmpty
            ? '${imported.length} فایل Word با موفقیت وارد شد'
            : '${imported.length} فایل وارد شد؛ ${failures.length} فایل ناموفق بود: ${failures.take(2).join('، ')}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (error) {
      debugPrint('DOCX import selection failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ورود فایل‌ها انجام نشد: $error')),
        );
      }
    }
  }

  Future<void> createBackup() async {
    try {
      final imageData = <String, String>{};
      for (final note in notes) {
        final paths = <String>{...note.images, ..._decodeNoteBlocks(note.body)
            .where((b) => b['type'] == 'image').map((b) => b['path'] as String),
          if (note.body.startsWith(_quillNoteMarker)) ...((jsonDecode(note.body.substring(_quillNoteMarker.length)) as List)
            .whereType<Map>().map((op) => op['insert']).whereType<Map>()
            .map((insert) => insert['image']).whereType<String>().where((path) => !path.startsWith('http')))};
        for (final path in paths) {
          final file = File(path);
          if (await file.exists()) imageData[path] = base64Encode(await file.readAsBytes());
        }
      }
      final backup = jsonEncode({
        'format': 'persian_notebook_backup', 'version': 1,
        'createdAt': DateTime.now().toIso8601String(),
        'notes': notes.map((n) => n.toJson()).toList(),
        'folders': folders.map((f) => f.toJson()).toList(),
        'pinnedNoteIds': pinnedNoteIds.toList(),
        'pinnedFolderIds': pinnedFolderIds.toList(),
        'themes': themes.map((t) => t.toJson()).toList(),
        'textColorPalette': textColorPalette,
        'images': imageData,
      });
      await FilePicker.saveFile(fileName: 'notebook_backup.json',
          bytes: Uint8List.fromList(utf8.encode(backup)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ساخت نسخه پشتیبان ناموفق بود: $e')));
    }
  }

  Future<void> restoreBackup() async {
    try {
      final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        title: const Text('بازیابی نسخه پشتیبان؟'),
        content: const Text('یادداشت‌ها، پوشه‌ها و تم‌های فعلی با اطلاعات فایل پشتیبان جایگزین می‌شوند.'),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ادامه'))],
      ));
      if (confirmed != true) return;
      final file = await FilePicker.pickFile(type: FileType.custom,
          allowedExtensions: ['json']);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (data['format'] != 'persian_notebook_backup' || data['version'] != 1) {
        throw const FormatException('فرمت فایل پشتیبان معتبر نیست');
      }
      final dir = await getApplicationDocumentsDirectory();
      final imageDir = Directory('${dir.path}/notebook_images');
      if (!await imageDir.exists()) await imageDir.create(recursive: true);
      final restoredPaths = <String, String>{};
      final images = Map<String, dynamic>.from(data['images'] ?? {});
      for (final entry in images.entries) {
        final oldPath = entry.key;
        final extension = oldPath.contains('.') ? oldPath.substring(oldPath.lastIndexOf('.')) : '.jpg';
        final newPath = '${imageDir.path}/restored_${DateTime.now().microsecondsSinceEpoch}_${restoredPaths.length}$extension';
        await File(newPath).writeAsBytes(base64Decode(entry.value as String));
        restoredPaths[oldPath] = newPath;
      }
      final restoredNotes = (data['notes'] as List).map((raw) {
        final n = Note.fromJson(Map<String, dynamic>.from(raw));
        var body = n.body;
        if (n.body.startsWith('__quill_note_v1__')) {
          final delta = (jsonDecode(n.body.substring('__quill_note_v1__'.length)) as List).map((rawOp) {
            final op = Map<String, dynamic>.from(rawOp as Map);
            if (op['insert'] is Map) {
              final insert = Map<String, dynamic>.from(op['insert'] as Map);
              final image = insert['image'];
              if (image is String && restoredPaths.containsKey(image)) {
                op['insert'] = {...insert, 'image': restoredPaths[image]};
              }
            }
            return op;
          }).toList();
          body = '__quill_note_v1__${jsonEncode(delta)}';
        } else if (n.body.startsWith('__rich_note_v1__')) {
          final blocks = _decodeNoteBlocks(n.body).map((block) {
            if (block['type'] == 'image' && restoredPaths.containsKey(block['path'])) {
              return {...block, 'path': restoredPaths[block['path']]};
            }
            return block;
          }).toList();
          body = '__rich_note_v1__${jsonEncode(blocks)}';
        }
        return Note(n.id, n.title, body, n.updated,
          n.images.map((path) => restoredPaths[path] ?? path).toList(),
          n.themeColor, n.themeTextColor, n.themeFontFamily, n.folderId);
      }).toList();
      setState(() {
        notes..clear()..addAll(restoredNotes);
        folders..clear()..addAll((data['folders'] as List? ?? []).map((e) => NoteFolder.fromJson(Map<String, dynamic>.from(e))));
        themes..clear()..addAll((data['themes'] as List? ?? []).map((e) => NoteTheme.fromJson(Map<String, dynamic>.from(e))));
        if (themes.isEmpty) themes.addAll(defaultThemes);
        selectedFolderId = null;
        showUnfiledOnly = true;
        showPinnedOnly = false;
        pinnedNoteIds..clear()..addAll(List<String>.from(data['pinnedNoteIds'] ?? const []));
        pinnedFolderIds..clear()..addAll(List<String>.from(data['pinnedFolderIds'] ?? const []));
        textColorPalette..clear()..addAll(List<int>.from(data['textColorPalette'] ?? const []));
      });
      await persist(); await persistFolders(); await persistThemes();
      await persistPinnedNotes(); await persistPinnedFolders();
      await repository.saveTextColorPalette(textColorPalette);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نسخه پشتیبان با موفقیت بازیابی شد')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('بازیابی نسخه پشتیبان ناموفق بود: $e')));
    }
  }

  Future<void> playNoteAudio(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فایل ویس پیدا نشد.')),
        );
      }
      return;
    }
    try {
      if (currentlyPlayingAudio == path && noteAudioPlayer.state == PlayerState.playing) {
        await noteAudioPlayer.pause();
        if (mounted) setState(() => currentlyPlayingAudio = null);
        return;
      }
      await noteAudioPlayer.stop();
      if (!mounted) return;
      setState(() => currentlyPlayingAudio = path);
      await noteAudioPlayer.play(DeviceFileSource(path));
    } catch (error) {
      if (mounted) {
        setState(() => currentlyPlayingAudio = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('پخش ویس ناموفق بود: $error')),
        );
      }
    }
  }

  Future<void> changeNoteTheme(Note note) async {
    if (themes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('هنوز تمی برای انتخاب وجود ندارد.')),
        );
      }
      return;
    }

    final selectedTheme = await showDialog<NoteTheme>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('انتخاب تم یادداشت'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: themes.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final theme = themes[index];
                final isSelected = note.themeColor == theme.backgroundColor &&
                    note.themeTextColor == theme.textColor &&
                    note.themeFontFamily == theme.fontFamily;
                return Material(
                  color: Color(theme.backgroundColor),
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Color(theme.textColor).withValues(alpha: .18),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    leading: CircleAvatar(
                      backgroundColor: Color(theme.textColor),
                      child: Icon(Icons.text_fields, color: Color(theme.backgroundColor)),
                    ),
                    title: Text(
                      theme.name,
                      style: TextStyle(
                        color: Color(theme.textColor),
                        fontFamily: theme.fontFamily,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'پیش‌نمایش متن یادداشت',
                      style: TextStyle(
                        color: Color(theme.textColor).withValues(alpha: .75),
                        fontFamily: theme.fontFamily,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle, color: Color(theme.textColor))
                        : null,
                    onTap: () => Navigator.pop(dialogContext, theme),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('انصراف'),
            ),
          ],
        ),
      ),
    );

    if (selectedTheme == null || !mounted) return;
    final index = notes.indexWhere((item) => item.id == note.id);
    if (index < 0) return;
    final current = notes[index];
    setState(() {
      notes[index] = Note(
        current.id,
        current.title,
        current.body,
        DateTime.now(),
        List<String>.of(current.images),
        selectedTheme.backgroundColor,
        selectedTheme.textColor,
        selectedTheme.fontFamily,
        current.folderId,
        List<String>.of(current.audios),
      );
      noteBackgroundColors.remove(current.id);
      if (featuredNote?.id == current.id) featuredNote = notes[index];
    });
    await persist();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم «${selectedTheme.name}» برای این یادداشت اعمال شد.')),
      );
    }
  }

  void showNoteMenu(Note note) {
    showModalBottomSheet<void>(context: context, builder: (sheetContext) =>
      Directionality(textDirection: TextDirection.rtl, child: SafeArea(child: Wrap(children: [
        ListTile(leading: Icon(pinnedNoteIds.contains(note.id) ? Icons.push_pin : Icons.push_pin_outlined),
          title: Text(pinnedNoteIds.contains(note.id) ? 'برداشتن سنجاق یادداشت' : 'سنجاق کردن یادداشت'),
          onTap: () { Navigator.pop(sheetContext); togglePinnedNote(note); }),
        ListTile(leading: const Icon(Icons.file_download_outlined),
          title: const Text('خروجی Word برای این یادداشت'),
          onTap: () { Navigator.pop(sheetContext); exportDocx([note]); }),
        ListTile(leading: const Icon(Icons.file_open_outlined),
          title: const Text('وارد کردن فایل Word'),
          onTap: () { Navigator.pop(sheetContext); importDocx(); }),
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Text('تغییر تم'),
          onTap: () { Navigator.pop(sheetContext); changeNoteTheme(note); },
        ),
        ListTile(leading: const Icon(Icons.drive_file_move_outline),
          title: const Text('انتقال به پوشه'),
          onTap: () { Navigator.pop(sheetContext); moveNote(note); }),
        ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red),
          title: const Text('حذف یادداشت'),
          onTap: () { Navigator.pop(sheetContext); remove(note); }),
      ]))));
  }

  String date(DateTime d) => '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  @override
  void dispose(){WidgetsBinding.instance.removeObserver(this);search.dispose();noteAudioPlayer.dispose();super.dispose();}
  @override
  Widget build(BuildContext context){
    final items=filtered;
    final visibleFolders=List<NoteFolder>.of(folders)..sort((a,b){
      final pinOrder=(pinnedFolderIds.contains(b.id)?1:0).compareTo(pinnedFolderIds.contains(a.id)?1:0);
      return pinOrder!=0?pinOrder:a.name.compareTo(b.name);
    });
    return Directionality(textDirection:TextDirection.rtl,child:Scaffold(
      appBar:AppBar(title:_selectionMode ? Text('${_selectedNoteIds.length} یادداشت انتخاب‌شده',style:const TextStyle(fontWeight:FontWeight.bold)) : null,leading:_selectionMode?IconButton(tooltip:'لغو انتخاب',onPressed:_clearSelection,icon:const Icon(Icons.close)):null,actions:_selectionMode?[IconButton(tooltip:'انتخاب همه',onPressed:_selectAllVisibleNotes,icon:const Icon(Icons.select_all)),IconButton(tooltip:'تغییر تم گروهی',onPressed:_changeSelectedNotesTheme,icon:const Icon(Icons.palette_outlined)),IconButton(tooltip:'انتقال گروهی',onPressed:_moveSelectedNotes,icon:const Icon(Icons.drive_file_move_outline)),IconButton(tooltip:'خروجی گروهی DOCX',onPressed:_exportSelectedNotes,icon:const Icon(Icons.archive_outlined)),IconButton(tooltip:'حذف گروهی',onPressed:_deleteSelectedNotes,icon:const Icon(Icons.delete_outline,color:Colors.red))]:[PopupMenuButton<String>(tooltip:'گزینه‌های بیشتر',onSelected:(value){if(value=='theme_random')_applyThemeToAllNotes(randomize:true);if(value=='theme_choose')_applyThemeToAllNotes(randomize:false);if(value=='import')importDocx();if(value=='export')exportDocx(notes);if(value=='backup')createBackup();if(value=='restore')restoreBackup();},itemBuilder:(context)=>const [PopupMenuItem(value:'theme_random',child:ListTile(leading:Icon(Icons.shuffle_rounded),title:Text('تم تصادفی برای همه نوشته‌ها'))),PopupMenuItem(value:'theme_choose',child:ListTile(leading:Icon(Icons.palette_outlined),title:Text('انتخاب یک تم برای همه نوشته‌ها'))),PopupMenuDivider(),PopupMenuItem(value:'import',child:ListTile(leading:Icon(Icons.file_open),title:Text('ورود گروهی DOCX'))),PopupMenuItem(value:'export',child:ListTile(leading:Icon(Icons.file_download),title:Text('خروجی گروهی DOCX'))),PopupMenuDivider(),PopupMenuItem(value:'backup',child:ListTile(leading:Icon(Icons.backup_outlined),title:Text('ساخت فایل پشتیبان'))),PopupMenuItem(value:'restore',child:ListTile(leading:Icon(Icons.settings_backup_restore),title:Text('بازیابی فایل پشتیبان')))]),IconButton(tooltip:'مدیریت تم‌ها',onPressed:manageThemes,icon:const Icon(Icons.palette_outlined))]),
      floatingActionButton:FloatingActionButton.extended(onPressed:()=>edit(),icon:const Icon(Icons.edit_note_rounded),label:const Text('یادداشت جدید')),
      body:SafeArea(child:Column(children:[
        if(!loading && featuredNote != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: Builder(builder: (context) {
              const background = Color(0xFF17191C);
              const foreground = Color(0xFFE5E7EA);
              const accent = Color(0xFF454B52);
              return Material(
                color: background,
                borderRadius: BorderRadius.circular(22),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => edit(note: featuredNote),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 15, 18, 17),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [background, const Color(0xFF30343A)],
                      ),
                      border: Border.all(color: foreground.withValues(alpha: .12)),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.auto_awesome_rounded, size: 14, color: foreground.withValues(alpha: .85)),
                                ],
                              ),
                            ),
                            const Spacer(),
                            Icon(Icons.format_quote_rounded, size: 25, color: foreground.withValues(alpha: .22)),
                          ],
                        ),
                        const SizedBox(height: 13),
                        Text(
                          featuredNote!.title.isEmpty ? 'بدون عنوان' : featuredNote!.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.start,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            height: 1.45,
                            color: foreground,
                            fontFamily: appInterfaceFontFamily.value,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 34,
                            height: 3,
                            decoration: BoxDecoration(
                              color: foreground.withValues(alpha: .25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        Padding(padding:const EdgeInsets.fromLTRB(20,8,20,18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[
            IconButton(
              tooltip:'جستجو',
              onPressed:(){
                setState(() {
                  isSearchExpanded=!isSearchExpanded;
                  if (!isSearchExpanded) search.clear();
                });
              },
              icon:const Icon(Icons.search),
            ),
            if(isSearchExpanded)
              Expanded(child:TextField(
                controller:search,
                autofocus:true,
                decoration:InputDecoration(
                  hintText:'جستجو',
                  filled:true,
                  fillColor:Colors.white,
                  border:OutlineInputBorder(borderRadius:BorderRadius.circular(16),borderSide:BorderSide.none),
                ),
              )),
          ]),
          const SizedBox(height:8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _folderFilterChip(
                    label: 'همه',
                    selected: showUnfiledOnly && !showPinnedOnly,
                    onTap: () => setState(() { selectedFolderId = null; showUnfiledOnly = true; showPinnedOnly = false; }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _folderFilterChip(
                    label: 'سنجاق‌شده‌ها',
                    selected: showPinnedOnly,
                    onTap: () => setState(() { selectedFolderId = null; showUnfiledOnly = false; showPinnedOnly = true; }),
                    icon: Icons.push_pin_rounded,
                  ),
                ),
                ...visibleFolders.map((folder) => Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _folderFilterChip(
                      label: folder.name,
                      selected: selectedFolderId == folder.id && !showPinnedOnly,
                      onTap: () => setState(() { selectedFolderId = folder.id; showUnfiledOnly = false; showPinnedOnly = false; }),
                      icon: pinnedFolderIds.contains(folder.id) ? Icons.push_pin_rounded : Icons.folder_outlined,
                    ),

                  ]),                )),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _folderFilterChip(
                    label: '',
                    selected: false,
                    onTap: manageFolders,
                    icon: Icons.folder_special_outlined,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height:16),

        ])),
        Expanded(child:loading?const Center(child:CircularProgressIndicator()):items.isEmpty
          ? const SizedBox.shrink()
          :ListView.separated(padding:const EdgeInsets.fromLTRB(20,0,20,100),itemCount:items.length,separatorBuilder: (_, _) => const SizedBox(height: 10),itemBuilder:(_,i){
            final n=items[i];
            final backgroundColor = _backgroundColorFor(n);
            final query = search.text.trim();
            final matchingLines = query.isEmpty ? <String>[] : _matchingLines(n, query);
            final selected = _selectedNoteIds.contains(n.id);
            return Card(elevation:selected?2:0,color:selected?Theme.of(context).colorScheme.primaryContainer:Color(backgroundColor),child:InkWell(onLongPress:()=>_toggleNoteSelection(n),onTap:()=>_selectionMode?_toggleNoteSelection(n):edit(note: n, searchQuery: query.isEmpty ? null : query),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Row(children:[if(_selectionMode)Checkbox(value:selected,onChanged:(_)=>_toggleNoteSelection(n)),if(pinnedNoteIds.contains(n.id))const Padding(padding:EdgeInsets.only(left:6),child:Icon(Icons.push_pin_rounded,size:17)),Expanded(child:Text(n.title.isEmpty?'بدون عنوان':n.title,style:TextStyle(fontWeight:FontWeight.bold,fontSize:16,color:Color(n.themeTextColor),fontFamily:appInterfaceFontFamily.value))),if(!_selectionMode)IconButton(tooltip:'گزینه‌های یادداشت',onPressed:()=>showNoteMenu(n),icon:const Icon(Icons.more_vert))]),
              if(query.isNotEmpty && matchingLines.isNotEmpty) ...matchingLines.take(6).map((line)=>Padding(padding:const EdgeInsets.only(top:6),child:_searchHighlightedText(line,query,textColor:Color(n.themeTextColor),fontFamily:appInterfaceFontFamily.value))),
              if(query.isNotEmpty && matchingLines.isEmpty && n.title.toLowerCase().contains(query.toLowerCase()))_searchHighlightedText('عنوان: ${n.title}',query,textColor:Color(n.themeTextColor),fontFamily:appInterfaceFontFamily.value),
              if(query.isEmpty && _notePlainText(n.body).isNotEmpty)Text(_notePlainText(n.body),maxLines:3,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:16,color:Color(n.themeTextColor),fontFamily:appInterfaceFontFamily.value)),
              if(n.images.isNotEmpty)Padding(padding:const EdgeInsets.only(top:8),child:Text('${n.images.length} تصویر پیوست شده',style:TextStyle(color:Color(n.themeTextColor).withValues(alpha: .7),fontSize:12,fontFamily:appInterfaceFontFamily.value))),
              if(n.audios.isNotEmpty)Padding(
                padding:const EdgeInsets.only(top:8),
                child:Wrap(
                  spacing:6,
                  runSpacing:4,
                  children:[
                    for(var audioIndex=0;audioIndex<n.audios.length;audioIndex++)
                      ActionChip(
                        avatar:Icon(
                          currentlyPlayingAudio==n.audios[audioIndex]
                              ? Icons.volume_up_rounded
                              : Icons.play_arrow_rounded,
                          size:18,
                          color:Color(n.themeTextColor),
                        ),
                        label:Text('پخش ویس ${audioIndex+1}',style:TextStyle(color:Color(n.themeTextColor),fontFamily:appInterfaceFontFamily.value)),
                        onPressed:()=>playNoteAudio(n.audios[audioIndex]),
                        backgroundColor:Color(backgroundColor).withValues(alpha: .75),
                      ),
                  ],
                ),
              ),
              const SizedBox(height:8),Text(date(n.updated),style:TextStyle(fontSize:11,color:Color(n.themeTextColor).withValues(alpha: .65),fontFamily:appInterfaceFontFamily.value)),
            ]))));
          })),
      ])),
    ));
  }
}

class FolderManagerDialog extends StatefulWidget {
  final List<NoteFolder> initialFolders;
  final Future<void> Function(List<NoteFolder>, Set<String>) onSave;
  final void Function(NoteFolder) onSelect;
  final Set<String> initialPinnedFolderIds;
  final Future<void> Function(NoteFolder) onTogglePin;
  const FolderManagerDialog({super.key, required this.initialFolders, required this.onSave, required this.onSelect, required this.initialPinnedFolderIds, required this.onTogglePin});
  @override
  State<FolderManagerDialog> createState() => _FolderManagerDialogState();
}

class _FolderManagerDialogState extends State<FolderManagerDialog> {
  late List<NoteFolder> folders;
  final Set<String> deletedIds = {};
  late final Set<String> pinnedFolderIds;
  final ScrollController _folderScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    folders = List.of(widget.initialFolders);
    pinnedFolderIds = Set<String>.of(widget.initialPinnedFolderIds);
  }

  @override
  void dispose() {
    _folderScrollController.dispose();
    super.dispose();
  }

  Future<String?> _askName({String title = 'نام پوشه', String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title),
          content: TextField(controller: controller, autofocus: true, maxLength: 30,
            decoration: const InputDecoration(hintText: 'نام پوشه')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('ذخیره')),
          ],
        ),
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  Future<void> _create() async {
    final name = await _askName(title: 'ایجاد پوشه');
    if (name == null) return;
    setState(() => folders.add(NoteFolder(DateTime.now().microsecondsSinceEpoch.toString(), name)));
    await widget.onSave(folders, deletedIds);
  }

  Future<void> _rename(NoteFolder folder) async {
    final name = await _askName(title: 'تغییر نام پوشه', initial: folder.name);
    if (name == null) return;
    setState(() {
      final index = folders.indexWhere((f) => f.id == folder.id);
      if (index >= 0) folders[index] = NoteFolder(folder.id, name);
    });
    await widget.onSave(folders, deletedIds);
  }

  Future<void> _delete(NoteFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
        title: const Text('حذف پوشه'),
        content: Text('پوشه «${folder.name}» حذف شود؟ یادداشت‌های آن به بخش بدون پوشه منتقل می‌شوند.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      )),
    );
    if (confirmed != true) return;
    setState(() {
      folders.removeWhere((f) => f.id == folder.id);
      deletedIds.add(folder.id);
    });
    await widget.onSave(folders, deletedIds);
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مدیریت پوشه‌ها'),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          actions: [IconButton(tooltip: 'ایجاد پوشه', onPressed: _create, icon: const Icon(Icons.create_new_folder_outlined))],
        ),
        body: folders.isEmpty
          ? const Center(child: Text('هنوز پوشه‌ای ایجاد نشده است.'))
          : Scrollbar(
              controller: _folderScrollController,
              thumbVisibility: folders.length > 5,
              interactive: true,
              child: ListView.separated(
                controller: _folderScrollController,
                primary: false,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 16, 24, 96),
                itemCount: folders.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final folder = folders[index];
                return ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(folder.name),
                  onTap: () { widget.onSelect(folder); Navigator.pop(context); },
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'pin') {
                        setState(() {
                          if (!pinnedFolderIds.add(folder.id)) pinnedFolderIds.remove(folder.id);
                        });
                        widget.onTogglePin(folder);
                      }
                      if (value == 'rename') _rename(folder);
                      if (value == 'delete') _delete(folder);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'pin',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(pinnedFolderIds.contains(folder.id) ? Icons.push_pin : Icons.push_pin_outlined),
                          title: Text(pinnedFolderIds.contains(folder.id) ? 'برداشتن سنجاق' : 'سنجاق کردن پوشه'),
                        ),
                      ),
                      const PopupMenuItem(value: 'rename', child: Text('تغییر نام')),
                      const PopupMenuItem(value: 'delete', child: Text('حذف پوشه')),
                    ],
                  ),
                );
                },
              ),
            ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _create,
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('پوشه جدید'),
        ),
      ),
    ),
  );
}

class EditorPage extends StatefulWidget {
  final Note? note;
  final String? searchQuery;
  final Future<void> Function(Note note) onAutoSave;
  final List<NoteTheme> themes;
  final List<String> customFonts;
  final List<String> previousTitles;
  final List<Note> existingNotes;
  final NoteTheme initialTheme;
  final String? initialFolderId;
  final int? backgroundColorOverride;
  const EditorPage({super.key,this.note,this.searchQuery,required this.themes,required this.customFonts,required this.previousTitles,required this.existingNotes,required this.initialTheme,required this.onAutoSave, this.initialFolderId, this.backgroundColorOverride});
  @override
  State<EditorPage> createState()=>_EditorPageState();
}

class _EditorPageState extends State<EditorPage> with WidgetsBindingObserver {
  late final TextEditingController title;
  late final quill.QuillController controller;
  late final String draftId;
  Timer? _autoSaveTimer;
  final AudioRecorder recorder = AudioRecorder();
  final AudioPlayer audioPlayer = AudioPlayer();
  final List<String> audioPaths = [];
  bool isRecording = false;
  String? currentlyPlayingEditorAudio;
  List<int> _searchPositions = [];
  int _searchPositionIndex = 0;
  Note? _appendTarget;
  double editorLineSpacing = 1.0;
  double editorPageMargin = 14.0;
  late int themeColor, themeTextColor;
  late String themeFontFamily;
  String? folderId;
  static const marker = '__quill_note_v1__';
  static const builtInToolbarFonts = ['sans-serif', 'Estedad'];
  Map<String, String> get toolbarFontFamilies => {
    for (final family in {...builtInToolbarFonts, ...widget.customFonts, themeFontFamily})
      'نمونه یک فونت · $family': family,
  };

  double get _availableScreenWidth {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return 360;
    final view = views.first;
    return view.physicalSize.width / view.devicePixelRatio;
  }

  quill.Document _loadDocument(String? body, List<String> legacyImages) {
    if (body != null && body.startsWith(marker)) {
      try {
        final rawDelta = jsonDecode(body.substring(marker.length)) as List;
        final screenWidth = _availableScreenWidth;
        final normalizedDelta = rawDelta.map((rawOp) {
          final op = Map<String, dynamic>.from(rawOp as Map);
          final insert = op['insert'];
          if (insert is Map && insert['image'] is String) {
            final attributes = Map<String, dynamic>.from(
              (op['attributes'] as Map?) ?? const <String, dynamic>{},
            );
            // flutter_quill_extensions reads image sizing from the CSS-like
            // "style" attribute. A numeric "width" attribute is ignored.
            // Set width only so the source aspect ratio determines the height.
            attributes['style'] = 'width: ${screenWidth}px;';
            op['attributes'] = attributes;
          }
          return op;
        }).toList();
        return quill.Document.fromJson(normalizedDelta);
      } catch (_) {}
    }
    final old = _decodeNoteBlocks(body ?? '');
    final ops = <Map<String, dynamic>>[];
    for (final block in old) {
      if (block['type'] == 'image' && block['path'] is String) {
        ops.add({'insert': {'image': block['path']}});
        ops.add({'insert': '\n'});
      } else {
        final text = block['text'] as String? ?? '';
        if (text.isNotEmpty) ops.add({'insert': text});
        ops.add({'insert': '\n'});
      }
    }
    if (!(body?.startsWith('__rich_note_v1__') ?? false)) {
      for (final path in legacyImages) {
        ops.add({'insert': {'image': path}});
        ops.add({'insert': '\n'});
      }
    }
    if (ops.isEmpty) ops.add({'insert': '\n'});
    return quill.Document.fromJson(ops);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    draftId = widget.note?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    title = TextEditingController(text: widget.note?.title ?? '');
    final doc = _loadDocument(widget.note?.body, widget.note?.images ?? const []);
    audioPlayer.onPlayerComplete.listen((_) { if (mounted) setState(() => currentlyPlayingEditorAudio = null); });
    controller = quill.QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _loadGlobalEditorSettings();
    if (widget.note == null) {
      controller.formatSelection(quill.Attribute.fromKeyValue('size', '20'));
    }
    _rebuildSearchPositions();
    if (widget.searchQuery != null && widget.searchQuery!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _searchPositions.isNotEmpty) _jumpToSearchPosition(0);
      });
    }
    title.addListener(_scheduleAutoSave);
    controller.addListener(_scheduleAutoSave);
    themeColor = widget.backgroundColorOverride ?? widget.note?.themeColor ?? widget.initialTheme.backgroundColor;
    themeTextColor = widget.note?.themeTextColor ?? widget.initialTheme.textColor;
    themeFontFamily = widget.note?.themeFontFamily ?? widget.initialTheme.fontFamily;
    folderId = widget.note?.folderId ?? widget.initialFolderId;
    audioPaths.addAll(widget.note?.audios ?? const []);
  }

  void _rebuildSearchPositions() {
    final query = widget.searchQuery?.trim() ?? '';
    _searchPositions = [];
    _searchPositionIndex = 0;
    if (query.isEmpty) return;
    final plain = controller.document.toPlainText();
    final lower = plain.toLowerCase();
    final target = query.toLowerCase();
    var offset = 0;
    while (offset <= lower.length - target.length) {
      final found = lower.indexOf(target, offset);
      if (found < 0) break;
      _searchPositions.add(found);
      offset = found + target.length;
    }
  }


  void _jumpToSearchPosition(int index) {
    if (_searchPositions.isEmpty || widget.searchQuery == null) return;
    final bounded = index.clamp(0, _searchPositions.length - 1).toInt();
    _searchPositionIndex = bounded;
    final start = _searchPositions[bounded];
    final end = (start + widget.searchQuery!.trim().length).clamp(start, controller.document.length - 1).toInt();
    controller.updateSelection(TextSelection(baseOffset: start, extentOffset: end), quill.ChangeSource.local);
    if (mounted) setState(() {});
  }


  void _moveSearchOccurrence(int delta) {
    if (_searchPositions.isEmpty) return;
    final next = (_searchPositionIndex + delta).clamp(0, _searchPositions.length - 1).toInt();
    _jumpToSearchPosition(next);
  }


  Future<void> selectEditorTheme() async {
    final selected = await showDialog<NoteTheme>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('انتخاب تم یادداشت'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: widget.themes.map((theme) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(theme.backgroundColor),
                  child: Icon(Icons.text_fields, color: Color(theme.textColor)),
                ),
                title: Text(theme.name),
                selected: theme.backgroundColor == themeColor &&
                    theme.textColor == themeTextColor &&
                    theme.fontFamily == themeFontFamily,
                onTap: () => Navigator.pop(dialogContext, theme),
              )).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('انصراف'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      themeColor = selected.backgroundColor;
      themeTextColor = selected.textColor;
      themeFontFamily = selected.fontFamily;
    });
  }

  Future<void> addImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/notebook_images');
    if (!await folder.exists()) await folder.create(recursive: true);
    final ext = picked.path.contains('.') ? picked.path.substring(picked.path.lastIndexOf('.')) : '.jpg';
    final originalPath = '${folder.path}/${DateTime.now().microsecondsSinceEpoch}$ext';
    await File(picked.path).copy(originalPath);
    if (!mounted) return;

    // Open the drawing canvas immediately after choosing a photo. The user can
    // save an annotated copy or insert the untouched original.
    final selectedPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => DrawingPage(imagePath: originalPath)),
    );
    if (!mounted || selectedPath == null) return;
    final index = controller.selection.extentOffset.clamp(0, controller.document.length - 1);
    // flutter_quill_extensions reads image dimensions from its CSS-like
    // "style" attribute. Use the full logical screen width and leave height
    // unset so the image keeps its original aspect ratio.
    final imageWidth = MediaQuery.sizeOf(context).width;
    final imageDelta = delta.Delta()
      ..retain(index)
      ..insert(
        {'image': selectedPath},
        {'style': 'width: ${imageWidth}px;'},
      )
      ..insert('\n');
    controller.document.compose(imageDelta, quill.ChangeSource.local);
    controller.updateSelection(
      TextSelection.collapsed(offset: index + 2),
      quill.ChangeSource.local,
    );
  }

  void insertHorizontalRule() {
    final selection = controller.selection;
    final index = selection.start.clamp(0, controller.document.length - 1).toInt();
    final selectedLength = selection.end - selection.start;
    final change = delta.Delta()
      ..retain(index)
      ..delete(selectedLength)
      ..insert('\n')
      ..insert({'horizontalRule': true})
      ..insert('\n');
    controller.document.compose(change, quill.ChangeSource.local);
    controller.updateSelection(
      TextSelection.collapsed(offset: index + 3),
      quill.ChangeSource.local,
    );
  }

  Future<void> toggleRecording() async {
    if(isRecording){
      final path=await recorder.stop();
      if(path!=null&&mounted){setState(()=>audioPaths.add(path));_scheduleAutoSave();}
      if(mounted)setState(()=>isRecording=false);
      return;
    }
    if(!await recorder.hasPermission()){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('برای ضبط صدا، اجازه دسترسی به میکروفون را فعال کن.')));
      return;
    }
    final dir=await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/notebook_audio');
    if(!await folder.exists())await folder.create(recursive:true);
    final path = '${folder.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await recorder.start(const RecordConfig(encoder:AudioEncoder.aacLc),path:path);
    if(mounted)setState(()=>isRecording=true);
  }

  Future<void> playAudio(String path) async {
    try {
      if (!await File(path).exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('فایل ویس پیدا نشد.')),
          );
        }
        return;
      }
      if (currentlyPlayingEditorAudio == path && audioPlayer.state == PlayerState.playing) {
        await audioPlayer.pause();
        if (mounted) setState(() => currentlyPlayingEditorAudio = null);
        return;
      }
      await audioPlayer.stop();
      if (!mounted) return;
      setState(() => currentlyPlayingEditorAudio = path);
      await audioPlayer.play(DeviceFileSource(path), mode: PlayerMode.mediaPlayer);
    } catch (error) {
      if (mounted) {
        setState(() => currentlyPlayingEditorAudio = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('پخش ویس ناموفق بود: $error')),
        );
      }
    }
  }

  Future<void> setNumericFontSize() async {
    final input=TextEditingController(text:'20');
    final value=await showDialog<double>(context:context,builder:(ctx)=>Directionality(textDirection:TextDirection.rtl,child:AlertDialog(
      title:const Text('اندازه متن'),
      content:TextField(controller:input,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'اندازه بر حسب پوینت',hintText:'مثلاً 20')),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('انصراف')),FilledButton(onPressed:(){final n=double.tryParse(input.text.trim());if(n!=null&&n>=6&&n<=42)Navigator.pop(ctx,n);},child:const Text('اعمال'))],
    )));
    input.dispose();
    if(value!=null){controller.formatSelection(quill.Attribute.fromKeyValue('size',value.toString()));}
  }

  Future<void> _choosePreviousTitle() async {
    final searchController = TextEditingController();
    final titles = widget.previousTitles
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final selectedTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (dialogContext, refreshDialog) {
            final query = searchController.text.trim().toLowerCase();
            final matches = titles.where((value) => value.toLowerCase().contains(query)).toList();
            return AlertDialog(
              title: const Text('انتخاب عنوان قبلی'),
              content: SizedBox(
                width: double.maxFinite,
                height: MediaQuery.sizeOf(dialogContext).height * .55,
                child: Column(children: [
                  TextField(
                    controller: searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'جستجوی عنوان‌ها',
                    ),
                    onChanged: (_) => refreshDialog(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: matches.isEmpty
                        ? const Center(child: Text('عنوانی پیدا نشد.'))
                        : ListView.builder(
                            itemCount: matches.length,
                            itemBuilder: (context, index) => ListTile(
                              dense: true,
                              title: Text(matches[index], maxLines: 2, overflow: TextOverflow.ellipsis),
                              onTap: () => Navigator.pop(dialogContext, matches[index]),
                            ),
                          ),
                  ),
                ]),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
              ],
            );
          },
        ),
      ),
    );
    searchController.dispose();
    if (selectedTitle != null && mounted) {
      final matchingNotes = widget.existingNotes
          .where((note) => note.title.trim() == selectedTitle.trim())
          .toList();
      if (matchingNotes.length > 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('چند یادداشت با این عنوان وجود دارد؛ برای جلوگیری از تغییر یادداشت اشتباه، ذخیره انجام نشد.')),
        );
        return;
      }
      if (matchingNotes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('یادداشت انتخاب‌شده پیدا نشد. فهرست را به‌روزرسانی کن و دوباره تلاش کن.')),
        );
        return;
      }

      // Keep the original note as the append base. Autosave can then rebuild
      // the same merged result without appending the draft repeatedly.
      setState(() => _appendTarget = matchingNotes.single);
      title.value = TextEditingValue(
        text: selectedTitle,
        selection: TextSelection.collapsed(offset: selectedTitle.length),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('متن جدید در انتهای یادداشت «$selectedTitle» ذخیره می‌شود.')),
      );
    }
  }

  Note? _buildNote() {
    final delta = controller.document.toDelta().toJson();
    final plain = controller.document.toPlainText().trim();
    final hasContent = delta.any((op) => op['insert'] is Map);
    if (_appendTarget != null) {
      // Do not alter the selected note merely because its title was selected.
      // A real text, image, or audio addition is required before saving.
      if (plain.isEmpty && !hasContent && audioPaths.isEmpty) return null;

      final target = _appendTarget!;
      final oldDocument = _loadDocument(target.body, target.images);
      final mergedDelta = oldDocument.toDelta().toJson()
          .map((op) => Map<String, dynamic>.from(op))
          .toList();
      final appendedDelta = delta
          .map((op) => Map<String, dynamic>.from(op))
          .toList();

      // Quill documents always end in a newline. Remove only the draft's
      // terminal newline, then append the exact separator as its own line.
      if (appendedDelta.isNotEmpty) {
        final lastInsert = appendedDelta.last['insert'];
        if (lastInsert is String && lastInsert.endsWith('\n')) {
          final shortened = lastInsert.substring(0, lastInsert.length - 1);
          if (shortened.isEmpty) {
            appendedDelta.removeLast();
          } else {
            appendedDelta.last['insert'] = shortened;
          }
        }
      }
      mergedDelta.addAll(appendedDelta);
      mergedDelta.add({'insert': '\n-------------------------------------------------------------------\n'});

      final newImagePaths = <String>[];
      for (final op in delta) {
        if (op['insert'] is Map) {
          final image = (op['insert'] as Map)['image'];
          if (image is String && !image.startsWith('http')) newImagePaths.add(image);
        }
      }
      final allImages = <String>{...target.images, ...newImagePaths}.toList();
      final allAudios = <String>{...target.audios, ...audioPaths}.toList();
      return Note(
        target.id,
        target.title,
        marker + jsonEncode(mergedDelta),
        DateTime.now(),
        allImages,
        target.themeColor,
        target.themeTextColor,
        target.themeFontFamily,
        target.folderId,
        allAudios,
      );
    }

    if (widget.note == null && title.text.trim().isEmpty && plain.isEmpty && !hasContent && audioPaths.isEmpty) return null;
    final imagePaths = <String>[];
    for (final op in delta) {
      if (op['insert'] is Map) {
        final image = (op['insert'] as Map)['image'];
        if (image is String && !image.startsWith('http')) imagePaths.add(image);
      }
    }
    return Note(
      draftId, title.text.trim(), marker + jsonEncode(delta), DateTime.now(), imagePaths,
      widget.note?.themeColor ?? themeColor, themeTextColor, themeFontFamily, folderId, List.of(audioPaths),
    );
  }

  Future<void> _loadGlobalEditorSettings() async {
    final repository = NotebookRepository();
    final values = await Future.wait<double>([
      repository.loadEditorLineSpacing(),
      repository.loadEditorPageMargin(),
    ]);
    if (!mounted) return;
    setState(() {
      editorLineSpacing = values[0].clamp(0.8, 2.0).toDouble();
      editorPageMargin = values[1].clamp(0.0, 48.0).toDouble();
    });
    _applyGlobalLineSpacing();
  }

  void _applyGlobalLineSpacing() {
    final documentLength = controller.document.length;
    if (documentLength <= 1) return;
    controller.formatText(
      0,
      documentLength,
      quill.Attribute.fromKeyValue('line-height', editorLineSpacing),
    );
  }

  Future<void> _showLineSpacingSettings() async {
    var value = editorLineSpacing;
    final selected = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refreshDialog) => AlertDialog(
          title: const Text('فاصله بین خطوط'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ضریب فاصله: ${value.toStringAsFixed(2)}'),
              Slider(
                value: value,
                min: 0.8,
                max: 2.0,
                divisions: 12,
                label: value.toStringAsFixed(2),
                onChanged: (next) => refreshDialog(() => value = next),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, value), child: const Text('اعمال')),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => editorLineSpacing = selected);
    _applyGlobalLineSpacing();
    await NotebookRepository().saveEditorLineSpacing(selected);
    _scheduleAutoSave();
  }

  Future<void> _showPageMarginSettings() async {
    var value = editorPageMargin;
    final selected = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refreshDialog) => AlertDialog(
          title: const Text('فاصله متن از حاشیه صفحه'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('فاصله از هر طرف: ${value.round()} پیکسل'),
              Slider(
                value: value,
                min: 0,
                max: 48,
                divisions: 24,
                label: '${value.round()}',
                onChanged: (next) => refreshDialog(() => value = next),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, value), child: const Text('اعمال')),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => editorPageMargin = selected);
    await NotebookRepository().saveEditorPageMargin(selected);
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 500), _persistDraft);
  }

  Future<void> _persistDraft() async {
    _autoSaveTimer?.cancel();    final draft = _buildNote();
    if (draft != null) await widget.onAutoSave(draft);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _persistDraft();
    }
  }

  Future<void> save() async {
    _autoSaveTimer?.cancel();
    final note = _buildNote();
    if (note == null) { Navigator.pop(context); return; }
    await widget.onAutoSave(note);
    if (mounted) Navigator.pop(context, note);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _persistDraft();
    WidgetsBinding.instance.removeObserver(this);
    title.removeListener(_scheduleAutoSave);
    controller.removeListener(_scheduleAutoSave);
    title.dispose();
    recorder.dispose();
    audioPlayer.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('یادداشت'), actions: [
        if (widget.searchQuery != null && _searchPositions.isNotEmpty) ...[
          IconButton(tooltip: 'نتیجه قبلی', onPressed: _searchPositionIndex > 0 ? () => _moveSearchOccurrence(-1) : null, icon: const Icon(Icons.keyboard_arrow_up)),
          Center(child: Text('${_searchPositionIndex + 1} / ${_searchPositions.length}')),
          IconButton(tooltip: 'نتیجه بعدی', onPressed: _searchPositionIndex < _searchPositions.length - 1 ? () => _moveSearchOccurrence(1) : null, icon: const Icon(Icons.keyboard_arrow_down)),
        ],
        TextButton.icon(onPressed: save, icon: const Icon(Icons.check), label: const Text('ذخیره')),
      ]),
      backgroundColor: Color(themeColor),
      body: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: title,
                  readOnly: _appendTarget != null,
                  autofocus: false,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(themeTextColor), fontFamily: themeFontFamily),
                  decoration: const InputDecoration(hintText: 'عنوان یادداشت', border: InputBorder.none),
                ),
              ),
              IconButton(
                tooltip: 'انتخاب از عنوان‌های قبلی',
                onPressed: widget.note != null || widget.previousTitles.isEmpty ? null : _choosePreviousTitle,
                icon: const Icon(Icons.add_circle_outline),
                color: Color(themeTextColor),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: quill.QuillEditor.basic(
              controller: controller,
              config: quill.QuillEditorConfig(
                padding: EdgeInsets.all(editorPageMargin),
                placeholder: 'متن یادداشتت را اینجا بنویس...',
                embedBuilders: [
                  ...FlutterQuillEmbeds.editorBuilders(
                    imageEmbedConfig: QuillEditorImageEmbedConfig(
                      imageProviderBuilder: (context, imageUrl) {
                        final local = File(imageUrl);
                        return local.existsSync() ? FileImage(local) : null;
                      },
                    ),
                  ),
                  const HorizontalRuleEmbedBuilder(),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          if (audioPaths.isNotEmpty)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < audioPaths.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: InputChip(
                        avatar: Icon(
                          currentlyPlayingEditorAudio == audioPaths[i]
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_fill,
                        ),
                        label: Text('پخش ویس ${i + 1}'),
                        onPressed: () => playAudio(audioPaths[i]),
                        onDeleted: () => setState(() {
                          if (currentlyPlayingEditorAudio == audioPaths[i]) {
                            audioPlayer.stop();
                            currentlyPlayingEditorAudio = null;
                          }
                          audioPaths.removeAt(i);
                          _scheduleAutoSave();
                        }),
                      ),
                    ),
                ],
              ),
            ),
          quill.QuillSimpleToolbar(
            controller: controller,
            config: quill.QuillSimpleToolbarConfig(
              buttonOptions: quill.QuillSimpleToolbarButtonOptions(
                fontFamily: quill.QuillToolbarFontFamilyButtonOptions(items: toolbarFontFamilies),
                fontSize: quill.QuillToolbarFontSizeButtonOptions(items: {for (var size = 6; size <= 42; size++) '$size': '$size'}),
              ),
              multiRowsDisplay: false,
              embedButtons: const [],
              customButtons: [
                quill.QuillToolbarCustomButtonOptions(
                  icon: const Icon(Icons.format_line_spacing),
                  tooltip: 'فاصله بین خطوط',
                  onPressed: _showLineSpacingSettings,
                ),
                quill.QuillToolbarCustomButtonOptions(
                  icon: const Icon(Icons.padding_outlined),
                  tooltip: 'فاصله از حاشیه صفحه',
                  onPressed: _showPageMarginSettings,
                ),
                quill.QuillToolbarCustomButtonOptions(
                  icon: const Icon(Icons.undo),
                  tooltip: 'واگرد',
                  onPressed: () => controller.undo(),
                ),
                quill.QuillToolbarCustomButtonOptions(
                  icon: const Icon(Icons.redo),
                  tooltip: 'انجام دوباره',
                  onPressed: () => controller.redo(),
                ),
                quill.QuillToolbarCustomButtonOptions(
                  icon: const Icon(Icons.format_align_right),
                  tooltip: 'راست‌چین',
                  onPressed: () => controller.formatSelection(quill.Attribute.fromKeyValue('align', 'right')),
                ),
                quill.QuillToolbarCustomButtonOptions(
                  icon: const Icon(Icons.format_align_center),
                  tooltip: 'وسط‌چین',
                  onPressed: () => controller.formatSelection(quill.Attribute.fromKeyValue('align', 'center')),
                ),
                quill.QuillToolbarCustomButtonOptions(
                  icon: const Icon(Icons.format_align_left),
                  tooltip: 'چپ‌چین',
                  onPressed: () => controller.formatSelection(quill.Attribute.fromKeyValue('align', 'left')),
                ),
                quill.QuillToolbarCustomButtonOptions(
                  icon: const Icon(Icons.horizontal_rule),
                  tooltip: 'درج خط افقی',
                  onPressed: insertHorizontalRule,
                ),
                quill.QuillToolbarCustomButtonOptions(
                  icon: const Icon(Icons.palette_outlined),
                  tooltip: 'انتخاب تم',
                  onPressed: selectEditorTheme,
                ),
                quill.QuillToolbarCustomButtonOptions(
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  tooltip: 'افزودن تصویر',
                  onPressed: addImage,
                ),
                quill.QuillToolbarCustomButtonOptions(
                  icon: Icon(
                    isRecording ? Icons.stop_circle_outlined : Icons.mic_none,
                    color: isRecording ? Colors.red : null,
                  ),
                  tooltip: isRecording ? 'پایان ضبط ویس' : 'اضافه کردن ویس',
                  onPressed: toggleRecording,
                ),
              ],
              // Whitelist only the requested toolbar controls. Every other
              // built-in Quill action is explicitly disabled so new/default
              // package buttons cannot leak into the editor toolbar.
              showDividers: false,
              showFontFamily: true,
              showFontSize: true,
              showBoldButton: false,
              showItalicButton: false,
              showSmallButton: false,
              showUnderLineButton: false,
              showLineHeightButton: false,
              showStrikeThrough: false,
              showInlineCode: false,
              showColorButton: true,
              showBackgroundColorButton: true,
              showClearFormat: false,
              showAlignmentButtons: false,
              showLeftAlignment: false,
              showCenterAlignment: false,
              showRightAlignment: false,
              showJustifyAlignment: false,
              showHeaderStyle: false,
              showListNumbers: true,
              showListBullets: false,
              showListCheck: false,
              showCodeBlock: false,
              showQuote: false,
              showIndent: false,
              showLink: false,
              showUndo: false,
              showRedo: false,
              showDirection: false,
              showSearchButton: false,
              showSubscript: false,
              showSuperscript: false,
            ),
          ),
        ]),
      ),
  );
}



class HorizontalRuleEmbedBuilder extends quill.EmbedBuilder {
  const HorizontalRuleEmbedBuilder();

  @override
  String get key => 'horizontalRule';

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Divider(
        thickness: 1.2,
        color: Theme.of(context).dividerColor,
        height: 1.2,
      ),
    );
  }

  @override
  String toPlainText(quill.Embed node) => '\n';
}

class Stroke{final List<Offset> points;final Color color;final double width;const Stroke(this.points,this.color,this.width);}
class DrawingPage extends StatefulWidget{
  final String imagePath;
  const DrawingPage({super.key,required this.imagePath});
  @override
  State<DrawingPage> createState()=>_DrawingPageState();
}
class _DrawingPageState extends State<DrawingPage>{
  final boundaryKey=GlobalKey();
  final strokes=<Stroke>[];
  List<Offset> active=[];
  Color color=Colors.red;
  double width=5;
  Future<void> save()async{
    try{
      final boundary=boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image=await boundary.toImage(pixelRatio:2);
      final data=await image.toByteData(format:ui.ImageByteFormat.png);
      if(data==null)return;
      final dir=await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/notebook_images');
      if(!await folder.exists())await folder.create(recursive:true);
      final file = File('${folder.path}/drawing_${DateTime.now().microsecondsSinceEpoch}.png');
      await file.writeAsBytes(data.buffer.asUint8List());
      if(mounted)Navigator.pop(context,file.path);
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('ذخیره تصویر انجام نشد. دوباره تلاش کن.')));}
  }
  @override
  Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:const Text('نقاشی روی عکس'),actions:[
      IconButton(onPressed:strokes.isEmpty?null:()=>setState(()=>strokes.removeLast()),tooltip:'بازگشت یک مرحله',icon:const Icon(Icons.undo)),
      IconButton(onPressed:()=>setState(()=>strokes.clear()),tooltip:'پاک کردن نقاشی',icon:const Icon(Icons.delete_sweep_outlined)),
      TextButton(onPressed:()=>Navigator.pop(context,widget.imagePath),child:const Text('بدون نقاشی')),
      TextButton.icon(onPressed:save,icon:const Icon(Icons.check),label:const Text('ذخیره')),
    ]),
    body:Column(children:[
      Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),child:Row(children:[
        for(final c in [Colors.red,Colors.blue,Colors.green,Colors.yellow,Colors.black,Colors.white])
          GestureDetector(onTap:()=>setState(()=>color=c),child:Container(margin:const EdgeInsets.symmetric(horizontal:5),width:27,height:27,decoration:BoxDecoration(color:c,shape:BoxShape.circle,border:Border.all(color:color==c?Colors.deepPurple:Colors.grey,width:color==c?3:1)))),
        const Spacer(),const Text('ضخامت'),SizedBox(width:100,child:Slider(value:width,min:2,max:16,onChanged:(v)=>setState(()=>width=v))),
      ])),
      Expanded(child:Center(child:RepaintBoundary(key:boundaryKey,child:GestureDetector(
        onPanStart:(d)=>setState(()=>active=[d.localPosition]),
        onPanUpdate:(d)=>setState(()=>active.add(d.localPosition)),
        onPanEnd:(_) => setState(() { if(active.isNotEmpty) strokes.add(Stroke(List.of(active),color,width)); active=[]; }),
        child:Stack(fit:StackFit.expand,children:[
          Image.file(File(widget.imagePath),fit:BoxFit.contain),
          CustomPaint(painter:DrawingPainter(strokes,active,color,width),size:Size.infinite),
        ]),
      )))),
      const Padding(padding:EdgeInsets.all(10),child:Text('با انگشت روی عکس نقاشی کن و ذخیره را بزن.')),
    ]),
  ));
}
class DrawingPainter extends CustomPainter{
  final List<Stroke> strokes;final List<Offset> active;final Color color;final double width;
  DrawingPainter(this.strokes,this.active,this.color,this.width);
  void draw(Canvas canvas,List<Offset> points,Color c,double w){
    if(points.isEmpty)return;
    final p=Paint()..color=c..strokeWidth=w..strokeCap=StrokeCap.round..strokeJoin=StrokeJoin.round..style=PaintingStyle.stroke;
    if(points.length==1){canvas.drawCircle(points.first,w/2,Paint()..color=c);return;}
    final path=Path()..moveTo(points.first.dx,points.first.dy);
    for(final point in points.skip(1)){path.lineTo(point.dx,point.dy);}
    canvas.drawPath(path,p);
  }
  @override
  void paint(Canvas canvas,Size size){for(final s in strokes){draw(canvas,s.points,s.color,s.width);}draw(canvas,active,color,width);}
  @override
  bool shouldRepaint(covariant DrawingPainter old)=>true;
}
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

final ValueNotifier<String> appInterfaceFontFamily = ValueNotifier<String>('sans-serif');
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
    debugShowCheckedModeBanner: false, title: 'دفترچه اشتباهات ترید',
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
  bool loading=true;
  Note? featuredNote;
  final customFonts=<String, String>{};
  final randomThemeNames=<String>{};
  final pinnedNoteIds=<String>{};
  final pinnedFolderIds=<String>{};
  final textColorPalette=<int>[];
  bool showPinnedOnly=false;
  final noteBackgroundColors=<String, int>{};
  static const defaultThemes=[NoteTheme('یاسی',0xFFEDE7F6),NoteTheme('آبی',0xFFE3F2FD),NoteTheme('سبز',0xFFE8F5E9),NoteTheme('صورتی',0xFFFCE4EC),NoteTheme('هلویی',0xFFFFEAD5)];

  @override
  void initState(){super.initState();WidgetsBinding.instance.addObserver(this);search.addListener(()=>setState((){}));noteAudioPlayer.onPlayerComplete.listen((_){if(mounted)setState(()=>currentlyPlayingAudio=null);});load();}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !loading) {
      setState(() {
        _randomizeNoteBackgrounds();
        featuredNote = _randomNote(notes, excludeId: featuredNote?.id);
      });
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
      appInterfaceFontFamily.value = customFonts.containsKey(loadedAppFontFamily) ? loadedAppFontFamily : 'sans-serif';
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
    setState((){folders.add(folder);selectedFolderId=folder.id;});
    await persistFolders();
  }
  Future<void> moveNote(Note note) async {
    final destination=await showDialog<String?>(context:context,builder:(c)=>Directionality(textDirection:TextDirection.rtl,child:AlertDialog(
      title:const Text('انتقال یادداشت به پوشه'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        ListTile(leading:const Icon(Icons.inbox_outlined),title:const Text('بدون پوشه'),onTap:()=>Navigator.pop(c,'')),
        ...folders.map((folder)=>ListTile(leading:const Icon(Icons.folder_outlined),title:Text(folder.name),onTap:()=>Navigator.pop(c,folder.id))),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('انصراف'))],
    )));
    if(destination==null)return;
    final id=destination.isEmpty?null:destination;
    setState((){final i=notes.indexWhere((n)=>n.id==note.id);if(i>=0){final n=notes[i];notes[i]=Note(n.id,n.title,n.body,n.updated,List.of(n.images),n.themeColor,n.themeTextColor,n.themeFontFamily,id,List.of(n.audios));}});
    await persist();
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
        textColorPalette..clear()..addAll(result.textColorPalette);
        appInterfaceFontFamily.value = result.appFontFamily;
        appThemeName.value = result.appThemeName;
      });
      await persistThemes();
      await repository.saveRandomThemeNames(randomThemeNames.toList());
      await repository.saveTextColorPalette(textColorPalette);
      await repository.saveAppInterfaceFontFamily(result.appFontFamily);
      await repository.saveAppTheme(result.appThemeName);
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
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? scheme.primary.withValues(alpha: .55) : scheme.outlineVariant.withValues(alpha: .55),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
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
    final list=notes.where((n)=>(!showPinnedOnly||pinnedNoteIds.contains(n.id))&&(selectedFolderId==null||n.folderId==selectedFolderId)&&(n.title.toLowerCase().contains(q)||_notePlainText(n.body).toLowerCase().contains(q))).toList();
    list.sort((a,b){
      final pinOrder=(pinnedNoteIds.contains(b.id)?1:0).compareTo(pinnedNoteIds.contains(a.id)?1:0);
      return pinOrder!=0?pinOrder:b.updated.compareTo(a.updated);
    });
    return list;
  }
  Future<void> edit([Note? note]) async {
    final availableThemes = themes.where((theme) => randomThemeNames.contains(theme.name)).toList();
    final themePool = availableThemes.isEmpty ? (themes.isEmpty ? defaultThemes : themes) : availableThemes;
    final selected=note==null?themePool[Random().nextInt(themePool.length)]:NoteTheme('فعلی',note.themeColor,note.themeTextColor,note.themeFontFamily);
    const builtInFonts = ['sans-serif'];
    final availableFonts = {...builtInFonts, ...customFonts.keys}.toList();
    final selectedFont = note == null
        ? availableFonts[Random().nextInt(availableFonts.length)]
        : selected.fontFamily;
    final initialTheme = NoteTheme(selected.name, selected.backgroundColor, selected.textColor, selectedFont);
    final result=await Navigator.push<Note>(context,MaterialPageRoute(builder:(_)=>EditorPage(note:note,themes:themes,customFonts:customFonts.keys.toList(),initialTheme:initialTheme,initialFolderId:note?.folderId??selectedFolderId,backgroundColorOverride:note == null ? null : _backgroundColorFor(note),onAutoSave:(draft) async { if(!mounted)return; setState(() { final i=notes.indexWhere((n)=>n.id==draft.id); if(i<0){notes.add(draft);}else{notes[i]=draft;} }); await persist(); })));
    if(result==null){_refreshFeaturedNote();return;}
    setState(() { final i=notes.indexWhere((n)=>n.id==result.id); if(i<0){notes.add(result);}else{notes[i]=result;} if(featuredNote?.id==result.id)featuredNote=result; });
    await persist();
    _refreshFeaturedNote();
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
    // Only treat the first paragraph as the note title when the DOCX explicitly
    // marks it as Title/Subtitle. Ordinary first paragraphs are document content
    // and must never be silently discarded during import.
    final firstParagraph = paragraphs.isEmpty ? null : paragraphs.first;
    final firstStyle = firstParagraph?.children
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'pPr')
        .firstOrNull
        ?.descendants.whereType<XmlElement>()
        .where((e) => e.name.local == 'pStyle')
        .firstOrNull
        ?.attributes.where((a) => a.name.local == 'val')
        .map((a) => a.value).firstOrNull ?? '';
    final hasTitleParagraph = firstStyle.toLowerCase() == 'title' ||
        firstStyle.toLowerCase() == 'subtitle';
    final importedTitle = hasTitleParagraph
        ? firstParagraph!.descendants.whereType<XmlElement>()
            .where((e) => e.name.local == 't')
            .map((e) => e.innerText).join().trim()
        : '';
    for (final paragraph in paragraphs.skip(hasTitleParagraph ? 1 : 0)) {
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
      if (files.isEmpty) return;
      final imported = <Note>[];
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
      appBar:AppBar(title:const Text('دفترچه اشتباهات',style:TextStyle(fontWeight:FontWeight.bold)),actions:[PopupMenuButton<String>(tooltip:'ورود و خروجی فایل‌ها',onSelected:(value){if(value=='import')importDocx();if(value=='export')exportDocx(notes);if(value=='backup')createBackup();if(value=='restore')restoreBackup();},itemBuilder:(context)=>const [PopupMenuItem(value:'import',child:ListTile(leading:Icon(Icons.file_open),title:Text('ورود گروهی DOCX'))),PopupMenuItem(value:'export',child:ListTile(leading:Icon(Icons.file_download),title:Text('خروجی گروهی DOCX'))),PopupMenuDivider(),PopupMenuItem(value:'backup',child:ListTile(leading:Icon(Icons.backup_outlined),title:Text('ساخت فایل پشتیبان'))),PopupMenuItem(value:'restore',child:ListTile(leading:Icon(Icons.settings_backup_restore),title:Text('بازیابی فایل پشتیبان')))]),IconButton(tooltip:'ایجاد پوشه',onPressed:createFolder,icon:const Icon(Icons.create_new_folder_outlined)),IconButton(tooltip:'مدیریت تم‌ها',onPressed:manageThemes,icon:const Icon(Icons.palette_outlined)),IconButton(onPressed:()=>edit(),icon:const Icon(Icons.add_rounded))]),
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
                  onTap: () => edit(featuredNote),
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
                            fontFamily: featuredNote!.themeFontFamily,
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
          TextField(controller:search,decoration:InputDecoration(hintText:'جستجو در یادداشت‌ها...',prefixIcon:const Icon(Icons.search),suffixIcon:search.text.isEmpty?null:IconButton(onPressed:search.clear,icon:const Icon(Icons.close)),filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(16),borderSide:BorderSide.none))),
          const SizedBox(height:16),
          const Text('پوشه‌ها',style:TextStyle(fontWeight:FontWeight.bold)),
          const SizedBox(height:10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _folderFilterChip(
                    label: 'همه',
                    selected: selectedFolderId == null,
                    onTap: () => setState(() { selectedFolderId = null; showPinnedOnly = false; }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _folderFilterChip(
                    label: 'سنجاق‌شده‌ها',
                    selected: showPinnedOnly,
                    onTap: () => setState(() { selectedFolderId = null; showPinnedOnly = true; }),
                    icon: Icons.push_pin_rounded,
                  ),
                ),
                ...visibleFolders.map((folder) => Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _folderFilterChip(
                      label: folder.name,
                      selected: selectedFolderId == folder.id && !showPinnedOnly,
                      onTap: () => setState(() { selectedFolderId = folder.id; showPinnedOnly = false; }),
                      icon: pinnedFolderIds.contains(folder.id) ? Icons.push_pin_rounded : Icons.folder_outlined,
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'گزینه‌های پوشه ${folder.name}',
                      onSelected: (value) { if (value == 'pin') togglePinnedFolder(folder); },
                      itemBuilder: (_) => [PopupMenuItem(
                        value: 'pin',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(pinnedFolderIds.contains(folder.id) ? Icons.push_pin : Icons.push_pin_outlined),
                          title: Text(pinnedFolderIds.contains(folder.id) ? 'برداشتن سنجاق پوشه' : 'سنجاق کردن پوشه'),
                        ),
                      )],
                    ),
                  ]),                )),              ],
            ),
          ),
          const SizedBox(height:16),

        ])),
        Expanded(child:loading?const Center(child:CircularProgressIndicator()):items.isEmpty
          ?Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[const Icon(Icons.menu_book_rounded,size:64,color:Color(0xFF9DA3AA)),const SizedBox(height:12),Text(search.text.isEmpty?(selectedFolderId==null?'دفترچه‌ات هنوز خالی است':'این پوشه هنوز خالی است'):'یادداشتی پیدا نشد',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:8),Text(search.text.isEmpty?'اولین یادداشتت را بنویس.':'عبارت دیگری را جستجو کن.'),if(search.text.isEmpty)...[const SizedBox(height:14),FilledButton(onPressed:()=>edit(),child:const Text('نوشتن اولین یادداشت'))]]))
          :ListView.separated(padding:const EdgeInsets.fromLTRB(20,0,20,100),itemCount:items.length,separatorBuilder: (_, _) => const SizedBox(height: 10),itemBuilder:(_,i){
            final n=items[i];
            final backgroundColor = _backgroundColorFor(n);
            return Card(elevation:0,color:Color(backgroundColor),child:InkWell(onTap:()=>edit(n),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Row(children:[if(pinnedNoteIds.contains(n.id))const Padding(padding:EdgeInsets.only(left:6),child:Icon(Icons.push_pin_rounded,size:17)),Expanded(child:Text(n.title.isEmpty?'بدون عنوان':n.title,style:TextStyle(fontWeight:FontWeight.bold,fontSize:16,color:Color(n.themeTextColor),fontFamily:n.themeFontFamily))),IconButton(tooltip:'گزینه‌های یادداشت',onPressed:()=>showNoteMenu(n),icon:const Icon(Icons.more_vert))]),
              if(_notePlainText(n.body).isNotEmpty)Text(_notePlainText(n.body),maxLines:3,overflow:TextOverflow.ellipsis,style:TextStyle(color:Color(n.themeTextColor),fontFamily:n.themeFontFamily)),
              if(n.images.isNotEmpty)Padding(padding:const EdgeInsets.only(top:8),child:Text('${n.images.length} تصویر پیوست شده',style:TextStyle(color:Color(n.themeTextColor).withValues(alpha: .7),fontSize:12,fontFamily:n.themeFontFamily))),
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
                        label:Text('پخش ویس ${audioIndex+1}',style:TextStyle(color:Color(n.themeTextColor),fontFamily:n.themeFontFamily)),
                        onPressed:()=>playNoteAudio(n.audios[audioIndex]),
                        backgroundColor:Color(backgroundColor).withValues(alpha: .75),
                      ),
                  ],
                ),
              ),
              const SizedBox(height:8),Text(date(n.updated),style:TextStyle(fontSize:11,color:Color(n.themeTextColor).withValues(alpha: .65),fontFamily:n.themeFontFamily)),
            ]))));
          })),
      ])),
    ));
  }
}

class EditorPage extends StatefulWidget {
  final Note? note;
  final Future<void> Function(Note note) onAutoSave;
  final List<NoteTheme> themes;
  final List<String> customFonts;
  final NoteTheme initialTheme;
  final String? initialFolderId;
  final int? backgroundColorOverride;
  const EditorPage({super.key,this.note,required this.themes,required this.customFonts,required this.initialTheme,required this.onAutoSave, this.initialFolderId, this.backgroundColorOverride});
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
  late int themeColor, themeTextColor;
  late String themeFontFamily;
  String? folderId;
  static const marker = '__quill_note_v1__';
  static const builtInToolbarFonts = ['sans-serif'];
  Map<String, String> get toolbarFontFamilies => {
    for (final family in {...builtInToolbarFonts, ...widget.customFonts, themeFontFamily})
      'نمونه یک فونت · $family': family,
  };

  quill.Document _loadDocument(String? body, List<String> legacyImages) {
    if (body != null && body.startsWith(marker)) {
      try { return quill.Document.fromJson(jsonDecode(body.substring(marker.length)) as List); } catch (_) {}
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
    if (widget.note == null) {
      controller.formatSelection(quill.Attribute.fromKeyValue('size', '20'));
    }
    title.addListener(_scheduleAutoSave);
    controller.addListener(_scheduleAutoSave);
    themeColor = widget.backgroundColorOverride ?? widget.note?.themeColor ?? widget.initialTheme.backgroundColor;
    themeTextColor = widget.note?.themeTextColor ?? widget.initialTheme.textColor;
    themeFontFamily = widget.note?.themeFontFamily ?? widget.initialTheme.fontFamily;
    folderId = widget.note?.folderId ?? widget.initialFolderId;
    audioPaths.addAll(widget.note?.audios ?? const []);
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
    // Set the Quill image width attribute directly. The image embed builder
    // reads this attribute and constrains the displayed image to the editor's
    // available width; its height remains automatic to preserve aspect ratio.
    final imageWidth = MediaQuery.sizeOf(context).width - 32;
    final imageDelta = delta.Delta()
      ..retain(index)
      ..insert(
        {'image': selectedPath},
        {'width': imageWidth},
      )
      ..insert('\n');
    controller.document.compose(imageDelta, quill.ChangeSource.local);
    controller.updateSelection(
      TextSelection.collapsed(offset: index + 2),
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

  Note? _buildNote() {
    final delta = controller.document.toDelta().toJson();
    final plain = controller.document.toPlainText().trim();
    final hasContent = delta.any((op) => op['insert'] is Map);
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

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 500), _persistDraft);
  }

  Future<void> _persistDraft() async {
    _autoSaveTimer?.cancel();
    final draft = _buildNote();
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
        TextButton.icon(onPressed: save, icon: const Icon(Icons.check), label: const Text('ذخیره')),
      ]),
      backgroundColor: Color(themeColor),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(
            controller: title, autofocus: false,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(themeTextColor), fontFamily: themeFontFamily),
            decoration: const InputDecoration(hintText: 'عنوان یادداشت', border: InputBorder.none),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: quill.QuillEditor.basic(
              controller: controller,
              config: quill.QuillEditorConfig(
                padding: const EdgeInsets.symmetric(vertical: 14),
                placeholder: 'متن یادداشتت را اینجا بنویس...',
                embedBuilders: FlutterQuillEmbeds.editorBuilders(
                  imageEmbedConfig: QuillEditorImageEmbedConfig(
                    imageProviderBuilder: (context, imageUrl) {
                      final local = File(imageUrl);
                      return local.existsSync() ? FileImage(local) : null;
                    },
                  ),
                ),
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
              embedButtons: FlutterQuillEmbeds.toolbarButtons(),
              customButtons: [
                quill.QuillToolbarCustomButtonOptions(
                  icon: const Icon(Icons.format_size),
                  tooltip: 'اندازه عددی متن',
                  onPressed: setNumericFontSize,
                ),
                quill.QuillToolbarCustomButtonOptions(
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  tooltip: 'افزودن عکس و نقاشی روی آن',
                  onPressed: addImage,
                ),
                quill.QuillToolbarCustomButtonOptions(
                  icon: Icon(
                    isRecording ? Icons.stop_circle_outlined : Icons.mic_none,
                    color: isRecording ? Colors.red : null,
                  ),
                  tooltip: isRecording ? 'پایان ضبط ویس' : 'شروع ضبط ویس',
                  onPressed: toggleRecording,
                ),
              ],
              showFontFamily: true,
              showFontSize: true,
              showBoldButton: true,
              showItalicButton: true,
              showUnderLineButton: true,
              showStrikeThrough: true,
              showColorButton: true,
              showBackgroundColorButton: true,
              showHeaderStyle: true,
              showListNumbers: true,
              showListBullets: true,
              showAlignmentButtons: true,
              showQuote: true,
              showCodeBlock: true,
              showClearFormat: true,
            ),
          ),
        ]),
      ),
    ),
  );
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
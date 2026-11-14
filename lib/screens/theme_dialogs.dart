import 'package:material_ui/material_ui.dart';
import '../models/note.dart';

class ThemeManagerResult {
  final List<NoteTheme> themes;
  final List<String> randomThemeNames;
  const ThemeManagerResult(this.themes, this.randomThemeNames);
}

class ThemeManagerDialog extends StatefulWidget {
  final List<NoteTheme> initialThemes;
  final List<String> customFonts;
  final List<String> initialRandomThemeNames;
  final Future<List<String>> Function()? onAddCustomFont;
  const ThemeManagerDialog({super.key, required this.initialThemes, this.customFonts = const [], this.initialRandomThemeNames = const [], this.onAddCustomFont});
  @override
  State<ThemeManagerDialog> createState() => _ThemeManagerDialogState();
}
class _ThemeManagerDialogState extends State<ThemeManagerDialog> {
  late List<NoteTheme> items;
  late List<String> availableFonts;
  late Set<String> randomThemeNames;
  bool addingFont = false;
  @override
  void initState() { super.initState(); items = List.of(widget.initialThemes); availableFonts = List.of(widget.customFonts); randomThemeNames = widget.initialRandomThemeNames.isEmpty ? items.map((e) => e.name).toSet() : widget.initialRandomThemeNames.toSet(); }
  Future<void> addFont() async {
    if (widget.onAddCustomFont == null || addingFont) return;
    setState(() => addingFont = true);
    try {
      final updated = await widget.onAddCustomFont!();
      if (mounted) setState(() => availableFonts = List.of(updated));
    } finally {
      if (mounted) setState(() => addingFont = false);
    }
  }
  Future<void> editTheme([NoteTheme? old]) async {
    final result = await showDialog<NoteTheme>(context: context, builder: (_) => ThemeEditorDialog(theme: old, customFonts: availableFonts));
    if (result == null) return;
    setState(() {
      if (old == null) { items.add(result); }
      else { final index = items.indexOf(old); if (index >= 0) items[index] = result; }
    });
  }
  Future<void> deleteTheme(NoteTheme theme) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف تم؟'),
        content: Text('تم «${theme.name}» حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed == true) setState(() => items.remove(theme));
  }
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('مدیریت تم‌ها'),
        content: SizedBox(
          width: 420,
          child: items.isEmpty
              ? const Text('هنوز تمی نساخته‌ای.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    const Padding(padding: EdgeInsets.fromLTRB(8, 8, 8, 4), child: Text('برای انتخاب تصادفی هنگام ساخت یادداشت، تم‌های دلخواهت را علامت بزن.')),
                    ...items.map((theme) => Card(
                      color: Color(theme.backgroundColor),
                      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => editTheme(theme),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: Color(theme.backgroundColor),
                                child: Icon(Icons.text_fields, size: 19, color: Color(theme.textColor)),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      theme.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.right,
                                      style: TextStyle(color: Color(theme.textColor), fontFamily: theme.fontFamily, fontWeight: FontWeight.w600, fontSize: 14),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'پیش‌نمایش رنگ و فونت',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.right,
                                      style: TextStyle(color: Color(theme.textColor).withValues(alpha: .72), fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              Checkbox(
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                value: randomThemeNames.contains(theme.name),
                                onChanged: (value) => setState(() {
                                  if (value == true) {
                                    randomThemeNames.add(theme.name);
                                  } else {
                                    randomThemeNames.remove(theme.name);
                                  }
                                }),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                                padding: EdgeInsets.zero,
                                tooltip: 'ویرایش',
                                onPressed: () => editTheme(theme),
                                icon: const Icon(Icons.edit_outlined, size: 19),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                                padding: EdgeInsets.zero,
                                tooltip: 'حذف',
                                onPressed: () {
                                  setState(() => randomThemeNames.remove(theme.name));
                                  deleteTheme(theme);
                                },
                                icon: const Icon(Icons.delete_outline, size: 19),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )),
                  ],
                ),
        ),
        actions: [
          TextButton.icon(
            onPressed: addingFont ? null : addFont,
            icon: addingFont
                ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2))
                : const Icon(Icons.upload_file_outlined),
            label: Text(addingFont ? 'در حال افزودن...' : 'افزودن فونت'),
          ),
          TextButton.icon(onPressed: () => editTheme(), icon: const Icon(Icons.add), label: const Text('ساخت تم')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, ThemeManagerResult(items, randomThemeNames.toList())), child: const Text('ذخیره')),
        ],
      ),
    );
  }
}

class ThemeEditorDialog extends StatefulWidget{
  final NoteTheme? theme;
  final List<String> customFonts;
  const ThemeEditorDialog({super.key,this.theme,this.customFonts=const []});
  @override
  State<ThemeEditorDialog> createState()=>_ThemeEditorDialogState();
}
class _ThemeEditorDialogState extends State<ThemeEditorDialog>{
  late final TextEditingController name,font;
  late int background,textColor;
  static const commonFonts=['sans-serif','serif','monospace','sans-serif-condensed','sans-serif-light','sans-serif-medium','cursive'];
  @override
  void initState(){
    super.initState();
    final t=widget.theme;
    name=TextEditingController(text:t?.name??'');
    font=TextEditingController(text:t?.fontFamily??'sans-serif');
    background=t?.backgroundColor??0xFFEDE7F6;
    textColor=t?.textColor??0xFF16131C;
  }
  @override
  void dispose(){name.dispose();font.dispose();super.dispose();}
  bool editingBackground = true;

  Widget _colorControls() {
    final current = HSVColor.fromColor(Color(editingBackground ? background : textColor));
    void update(HSVColor next) {
      setState(() {
        if (editingBackground) {
          background = next.toColor().toARGB32();
        } else {
          textColor = next.toColor().toARGB32();
        }
      });
    }
    return Column(
      children: [
        Slider(
          value: current.hue,
          min: 0,
          max: 360,
          onChanged: (value) => update(current.withHue(value)),
        ),
        Slider(
          value: current.saturation,
          min: 0,
          max: 1,
          onChanged: (value) => update(current.withSaturation(value)),
        ),
        Slider(
          value: current.value,
          min: 0,
          max: 1,
          onChanged: (value) => update(current.withValue(value)),
        ),
      ],
    );
  }

  Widget _colorPreview(int color, bool isBackground) {
    final selected = editingBackground == isBackground;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => editingBackground = isBackground),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: Color(color),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Theme.of(context).colorScheme.primary : Colors.black26,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? Icon(Icons.check, color: Color(color).computeLuminance() > .5 ? Colors.black : Colors.white)
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:AlertDialog(
    title:Text(widget.theme==null?'ساخت تم جدید':'ویرایش تم'),
    content:SingleChildScrollView(child:SizedBox(width:420,child:Column(
      mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        TextField(controller:name,maxLength:24,decoration:const InputDecoration(labelText:'نام دلخواه تم',hintText:'مثلاً شب آرام')),
        const SizedBox(height:12),
        Row(
          children: [
            _colorPreview(background, true),
            const SizedBox(width: 12),
            _colorPreview(textColor, false),
          ],
        ),
        const SizedBox(height: 12),
        _colorControls(),
        const SizedBox(height:16),const Text('۳. فونت دلخواه'),
        TextField(controller:font,onChanged:(_)=>setState((){}),decoration:const InputDecoration(labelText:'نام فونت دستگاه یا فونت برنامه',hintText:'مثلاً sans-serif')),
        const Text('برای نمایش دقیق، فونت باید روی دستگاه موجود یا به برنامه اضافه شده باشد.',style:TextStyle(fontSize:11,color:Colors.black54)),
        const SizedBox(height:6),
        Wrap(spacing:6,children:[...commonFonts,...widget.customFonts].map((f)=>ActionChip(label:Text(f,style:TextStyle(fontFamily:f,fontSize:11)),onPressed:()=>setState(()=>font.text=f))).toList()),
        const SizedBox(height:16),const Text('پیش‌نمایش'),
        Container(width:double.infinity,padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:Color(background),borderRadius:BorderRadius.circular(12)),child:Text('یادداشت نمونه؛ این متن با فونت و رنگ انتخابی نمایش داده می‌شود.',style:TextStyle(color:Color(textColor),fontFamily:font.text.trim().isEmpty?'sans-serif':font.text.trim(),fontSize:16))),
      ],
    ))),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(context),child:const Text('انصراف')),
      FilledButton(onPressed:()=>Navigator.pop(context,NoteTheme(name.text.trim().isEmpty?'تم بدون نام':name.text.trim(),background,textColor,font.text.trim().isEmpty?'sans-serif':font.text.trim())),child:const Text('ذخیره تم')),
    ],
  ));
}


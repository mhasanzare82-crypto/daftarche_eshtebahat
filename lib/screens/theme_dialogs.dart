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
  @override State<ThemeManagerDialog> createState() => _ThemeManagerDialogState();
}

class _ThemeManagerDialogState extends State<ThemeManagerDialog> {
  late List<NoteTheme> palette;
  late List<String> fonts;
  double hue = 265, saturation = .28, brightness = .94;
  bool addingFonts = false;
  static const builtInFonts = ['sans-serif','serif','monospace','sans-serif-condensed','sans-serif-light','sans-serif-medium','cursive'];
  @override void initState() { super.initState(); palette = [...widget.initialThemes]; fonts = {...builtInFonts, ...widget.customFonts}.toList(); }
  Color get selectedColor => HSVColor.fromAHSV(1, hue, saturation, brightness).toColor();
  Color readableText(Color c) => c.computeLuminance() > .42 ? const Color(0xFF211D27) : Colors.white;
  Future<void> addFonts() async {
    if (widget.onAddCustomFont == null || addingFonts) return;
    setState(() => addingFonts = true);
    try { final updated = await widget.onAddCustomFont!(); if (mounted) setState(() => fonts = {...builtInFonts, ...updated}.toList()); }
    finally { if (mounted) setState(() => addingFonts = false); }
  }
  void addSelectedColor() {
    final color = selectedColor; final value = color.toARGB32();
    if (palette.any((item) => item.backgroundColor == value)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('این رنگ قبلاً اضافه شده است.'))); return; }
    setState(() => palette.add(NoteTheme('رنگ ${palette.length + 1}', value, readableText(color).toARGB32(), 'sans-serif')));
  }
  @override Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
    child: SizedBox(width: 520, height: MediaQuery.sizeOf(context).height * .86, child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(20,16,12,12), child: Row(children: [const Expanded(child: Text('مدیریت تم‌ها', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))), IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))])),
      const Divider(height: 1),
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        _sectionTitle('۱. افزودن فونت‌ها', Icons.font_download_outlined),
        const SizedBox(height: 6),
        const Text('چند فایل فونت TTF یا OTF را هم‌زمان انتخاب کن؛ همه به فهرست فونت‌های قابل استفاده اضافه می‌شوند.', style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: addingFonts ? null : addFonts, icon: addingFonts ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.upload_file_outlined), label: Text(addingFonts ? 'در حال افزودن فونت‌ها...' : 'انتخاب گروهی فونت‌ها'))),
        const SizedBox(height: 8),
        Wrap(spacing: 7, runSpacing: 7, children: fonts.map((family) => Chip(avatar: const Icon(Icons.text_fields,size:16), label: Text(family, style: TextStyle(fontFamily: family,fontSize:11)))).toList()),
        const SizedBox(height: 24), const Divider(), const SizedBox(height: 12),
        _sectionTitle('۲. انتخاب رنگ پس‌زمینه', Icons.palette_outlined),
        const SizedBox(height: 8),
        const Text('سه اسلایدر را تنظیم کن. سپس روی کادر پیش‌نمایش بزن تا رنگ به پالت رنگ‌های برنامه اضافه شود.', style: TextStyle(fontSize: 12,color:Colors.black54)),
        const SizedBox(height: 12),
        _sliderRow('ته‌رنگ', hue, 0, 360, (v) => setState(() => hue=v), hue.round().toString()),
        _sliderRow('اشباع', saturation, 0, 1, (v) => setState(() => saturation=v), '${(saturation*100).round()}٪'),
        _sliderRow('روشنایی', brightness, 0, 1, (v) => setState(() => brightness=v), '${(brightness*100).round()}٪'),
        const SizedBox(height: 10),
        Material(color:selectedColor,borderRadius:BorderRadius.circular(14),child:InkWell(borderRadius:BorderRadius.circular(14),onTap:addSelectedColor,child:SizedBox(height:76,child:Center(child:Row(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.add_circle_outline,color:readableText(selectedColor),size:22),const SizedBox(width:8),Text('افزودن این رنگ به پالت',style:TextStyle(color:readableText(selectedColor),fontWeight:FontWeight.bold))]))))),
        const SizedBox(height: 18),
        Row(children:[Expanded(child:Text('رنگ‌های قابل انتخاب (${palette.length})',style:const TextStyle(fontWeight:FontWeight.w600))),TextButton.icon(onPressed:palette.isEmpty?null:()=>setState(palette.clear),icon:const Icon(Icons.delete_sweep_outlined,size:18),label:const Text('پاک‌کردن پالت'))]),
        if (palette.isEmpty) const Padding(padding:EdgeInsets.symmetric(vertical:16),child:Text('هنوز رنگی اضافه نشده؛ از کادر بالا رنگ دلخواهت را اضافه کن.',textAlign:TextAlign.center))
        else Wrap(spacing:9,runSpacing:9,children:List.generate(palette.length,(index){final item=palette[index];return Tooltip(message:item.name,child:GestureDetector(onLongPress:()=>setState(()=>palette.removeAt(index)),child:Container(width:46,height:46,decoration:BoxDecoration(color:Color(item.backgroundColor),borderRadius:BorderRadius.circular(12),border:Border.all(color:Colors.black26)),child:Icon(Icons.check,color:Color(item.textColor),size:19))));})),
        const SizedBox(height: 8), const Text('برای حذف یک رنگ، انگشتت را روی آن نگه دار.',style:TextStyle(fontSize:11,color:Colors.black54)),
      ])),
      const Divider(height:1),
      Padding(padding:const EdgeInsets.fromLTRB(16,10,16,12),child:Row(children:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('انصراف')),const Spacer(),FilledButton.icon(onPressed:(){final names=palette.map((item)=>item.name).toList();Navigator.pop(context,ThemeManagerResult([...palette],names));},icon:const Icon(Icons.save_outlined),label:const Text('ذخیره تنظیمات'))])),
    ])),
  ));
  Widget _sectionTitle(String title, IconData icon) => Row(children:[Icon(icon,size:20,color:Theme.of(context).colorScheme.primary),const SizedBox(width:8),Text(title,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:15))]);
  Widget _sliderRow(String label,double value,double min,double max,ValueChanged<double> onChanged,String valueText)=>Row(children:[SizedBox(width:62,child:Text(label,style:const TextStyle(fontSize:12))),Expanded(child:Slider(value:value,min:min,max:max,onChanged:onChanged)),SizedBox(width:42,child:Text(valueText,textAlign:TextAlign.left,style:const TextStyle(fontSize:11)))]);
}
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';
import '../widgets/home_widget_sync.dart';

/// Selection, color, and typography settings for the Android Daily Reminder widget.
class DailyWidgetSettingsScreen extends StatefulWidget {
  final List<Note> notes;
  const DailyWidgetSettingsScreen({super.key, required this.notes});
  @override
  State<DailyWidgetSettingsScreen> createState() => _DailyWidgetSettingsScreenState();
}
class _DailyWidgetSettingsScreenState extends State<DailyWidgetSettingsScreen> {
  static const _idsKey='daily_widget_selected_note_ids', _bgKey='daily_widget_background_color',
    _fgKey='daily_widget_text_color', _sizeKey='daily_widget_font_size', _styleKey='daily_widget_font_style';
  Set<String> selected={};
  Color background=const Color(0xFF202329), foreground=const Color(0xFFF4F4F5);
  double size=16;
  String style='normal';
  bool loading=true;
  @override void initState(){super.initState();_load();}
  Future<void> _load() async {
    final p=await SharedPreferences.getInstance(); if(!mounted)return;
    setState((){selected=(p.getStringList(_idsKey)??[]).toSet(); background=Color(p.getInt(_bgKey)??background.value);
      foreground=Color(p.getInt(_fgKey)??foreground.value); size=(p.getDouble(_sizeKey)??p.getInt(_sizeKey)?.toDouble()??16).clamp(12,28).toDouble();
      style=p.getString(_styleKey)??'normal'; loading=false;});
  }
  Future<void> _save() async {
    final p=await SharedPreferences.getInstance(); await p.setStringList(_idsKey,selected.toList());
    await p.setInt(_bgKey,background.value); await p.setInt(_fgKey,foreground.value);
    await p.setDouble(_sizeKey,size); await p.setString(_styleKey,style); await HomeWidgetSync.refresh();
  }
  static Future<bool> toggleNote(Note note) async {
    final p=await SharedPreferences.getInstance(); final ids=(p.getStringList(_idsKey)??[]).toSet();
    final remove=ids.remove(note.id); if(!remove)ids.add(note.id);
    await p.setStringList(_idsKey,ids.toList()); await HomeWidgetSync.refresh(); return !remove;
  }
  String _plain(String body){
    const q='__quill_note_v1__', legacy='__rich_note_v1__';
    try{
      if(body.startsWith(q)){final ops=jsonDecode(body.substring(q.length)) as List; return ops.map((o)=>o is Map&&o['insert'] is String?o['insert'] as String:'').join();}
      final source=body.startsWith(legacy)?body.substring(legacy.length):body;
      if(source.trimLeft().startsWith('[')){final blocks=jsonDecode(source) as List; return blocks.whereType<Map>().where((b)=>b['type']=='text').map((b)=>b['text']?.toString()??'').join('\n');}
    }catch(_){}
    return body;
  }
  List<String> _parts(Note n) {
    final body = _plain(n.body);
    final separator = RegExp(r'(?m)^[ \t]*-{20,}[ \t]*$');
    final chunks = body.split(separator);
    final lines = body.trimRight().split('\n');
    final begins = lines.isNotEmpty && RegExp(r'^[ \t]*-{20,}[ \t]*$').hasMatch(lines.first);
    final ends = lines.isNotEmpty && RegExp(r'^[ \t]*-{20,}[ \t]*$').hasMatch(lines.last);
    if (!begins && chunks.isNotEmpty) chunks.removeAt(0);
    if (!ends && chunks.isNotEmpty) chunks.removeLast();
    return chunks.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }
  Widget _rgbSlider(String label,Color c,bool isBg,int channel){
    final v=channel==0?c.red:channel==1?c.green:c.blue;
    return ListTile(dense:true,title:Text(label),subtitle:Slider(min:0,max:255,divisions:255,value:v.toDouble(),onChanged:(x){
      final r=channel==0?x.round():c.red,g=channel==1?x.round():c.green,b=channel==2?x.round():c.blue;
      setState(()=>isBg?background=Color.fromARGB(255,r,g,b):foreground=Color.fromARGB(255,r,g,b));
    },onChangeEnd:(_)=>_save()));
  }
  Widget _colorSection(String title,Color c,bool bg)=>ExpansionTile(title:title,subtitle:Container(height:22,width:22,decoration:BoxDecoration(color:c,shape:BoxShape.circle)),
    children:[_rgbSlider('قرمز',c,bg,0),_rgbSlider('سبز',c,bg,1),_rgbSlider('آبی',c,bg,2)]);
  TextStyle get _sample=>TextStyle(color:foreground,fontSize:size,fontWeight:style.contains('bold')?FontWeight.bold:FontWeight.normal,fontStyle:style.contains('italic')?FontStyle.italic:FontStyle.normal);
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:const Text('یادآوری‌های روزانه')),
    body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(14),children:[
      Card(color:background,child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('نمونه یادآوری',style:_sample.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:8),
        Text('متن بخش انتخاب‌شده از یادداشت در اینجا نمایش داده می‌شود.',style:_sample),Align(alignment:Alignment.centerLeft,child:Text('بعدی  ›',style:_sample.copyWith(fontSize:12)))
      ]))),
      const SizedBox(height:10),Text('یادداشت‌های قابل نمایش',style:Theme.of(context).textTheme.titleMedium),
      const Text('فقط یادداشت‌هایی که انتخاب می‌کنی وارد گردش ویجت می‌شوند.'),
      ...widget.notes.map((n)=>CheckboxListTile(value:selected.contains(n.id),title:Text(n.title.isEmpty?'بدون عنوان':n.title),subtitle:Text('${_parts(n).length} بخش'),onChanged:(v)async{
        setState(()=>v==true?selected.add(n.id):selected.remove(n.id));await _save();
      })),
      const Divider(),Text('تنظیمات رنگ و فونت',style:Theme.of(context).textTheme.titleMedium),
      _colorSection('رنگ پس‌زمینه',background,true),_colorSection('رنگ متن',foreground,false),
      ListTile(title:const Text('اندازه فونت'),subtitle:Slider(min:12,max:28,divisions:16,value:size,onChanged:(v)=>setState(()=>size=v),onChangeEnd:(_)=>_save())),
      ListTile(title:const Text('سبک فونت'),subtitle:DropdownButton<String>(value:style,isExpanded:true,items:const[
        DropdownMenuItem(value:'normal',child:Text('معمولی')),DropdownMenuItem(value:'bold',child:Text('ضخیم')),
        DropdownMenuItem(value:'italic',child:Text('مورب')),DropdownMenuItem(value:'bold_italic',child:Text('ضخیم و مورب'))],
        onChanged:(v){if(v!=null){setState(()=>style=v);_save();}})),
      FilledButton.icon(onPressed:_save,icon:const Icon(Icons.save),label:const Text('ذخیره و اعمال تنظیمات'))
    ]))));
}
)).map((s)=>s.trim()).where((s)=>s.isNotEmpty).toList();
  Widget _rgbSlider(String label,Color c,bool isBg,int channel){
    final v=channel==0?c.red:channel==1?c.green:c.blue;
    return ListTile(dense:true,title:Text(label),subtitle:Slider(min:0,max:255,divisions:255,value:v.toDouble(),onChanged:(x){
      final r=channel==0?x.round():c.red,g=channel==1?x.round():c.green,b=channel==2?x.round():c.blue;
      setState(()=>isBg?background=Color.fromARGB(255,r,g,b):foreground=Color.fromARGB(255,r,g,b));
    },onChangeEnd:(_)=>_save()));
  }
  Widget _colorSection(String title,Color c,bool bg)=>ExpansionTile(title:title,subtitle:Container(height:22,width:22,decoration:BoxDecoration(color:c,shape:BoxShape.circle)),
    children:[_rgbSlider('قرمز',c,bg,0),_rgbSlider('سبز',c,bg,1),_rgbSlider('آبی',c,bg,2)]);
  TextStyle get _sample=>TextStyle(color:foreground,fontSize:size,fontWeight:style.contains('bold')?FontWeight.bold:FontWeight.normal,fontStyle:style.contains('italic')?FontStyle.italic:FontStyle.normal);
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:const Text('یادآوری‌های روزانه')),
    body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(14),children:[
      Card(color:background,child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('نمونه یادآوری',style:_sample.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:8),
        Text('متن بخش انتخاب‌شده از یادداشت در اینجا نمایش داده می‌شود.',style:_sample),Align(alignment:Alignment.centerLeft,child:Text('بعدی  ›',style:_sample.copyWith(fontSize:12)))
      ]))),
      const SizedBox(height:10),Text('یادداشت‌های قابل نمایش',style:Theme.of(context).textTheme.titleMedium),
      const Text('فقط یادداشت‌هایی که انتخاب می‌کنی وارد گردش ویجت می‌شوند.'),
      ...widget.notes.map((n)=>CheckboxListTile(value:selected.contains(n.id),title:Text(n.title.isEmpty?'بدون عنوان':n.title),subtitle:Text('${_parts(n).length} بخش'),onChanged:(v)async{
        setState(()=>v==true?selected.add(n.id):selected.remove(n.id));await _save();
      })),
      const Divider(),Text('تنظیمات رنگ و فونت',style:Theme.of(context).textTheme.titleMedium),
      _colorSection('رنگ پس‌زمینه',background,true),_colorSection('رنگ متن',foreground,false),
      ListTile(title:const Text('اندازه فونت'),subtitle:Slider(min:12,max:28,divisions:16,value:size,onChanged:(v)=>setState(()=>size=v),onChangeEnd:(_)=>_save())),
      ListTile(title:const Text('سبک فونت'),subtitle:DropdownButton<String>(value:style,isExpanded:true,items:const[
        DropdownMenuItem(value:'normal',child:Text('معمولی')),DropdownMenuItem(value:'bold',child:Text('ضخیم')),
        DropdownMenuItem(value:'italic',child:Text('مورب')),DropdownMenuItem(value:'bold_italic',child:Text('ضخیم و مورب'))],
        onChanged:(v){if(v!=null){setState(()=>style=v);_save();}})),
      FilledButton.icon(onPressed:_save,icon:const Icon(Icons.save),label:const Text('ذخیره و اعمال تنظیمات'))
    ]))));
}
);
    final chunks = body.split(separator);
    final lines = body.trimRight().split('\\n');
    final begins = lines.isNotEmpty && RegExp(r'^[ \\t]*-{20,}[ \\t]*
  Widget _rgbSlider(String label,Color c,bool isBg,int channel){
    final v=channel==0?c.red:channel==1?c.green:c.blue;
    return ListTile(dense:true,title:Text(label),subtitle:Slider(min:0,max:255,divisions:255,value:v.toDouble(),onChanged:(x){
      final r=channel==0?x.round():c.red,g=channel==1?x.round():c.green,b=channel==2?x.round():c.blue;
      setState(()=>isBg?background=Color.fromARGB(255,r,g,b):foreground=Color.fromARGB(255,r,g,b));
    },onChangeEnd:(_)=>_save()));
  }
  Widget _colorSection(String title,Color c,bool bg)=>ExpansionTile(title:title,subtitle:Container(height:22,width:22,decoration:BoxDecoration(color:c,shape:BoxShape.circle)),
    children:[_rgbSlider('قرمز',c,bg,0),_rgbSlider('سبز',c,bg,1),_rgbSlider('آبی',c,bg,2)]);
  TextStyle get _sample=>TextStyle(color:foreground,fontSize:size,fontWeight:style.contains('bold')?FontWeight.bold:FontWeight.normal,fontStyle:style.contains('italic')?FontStyle.italic:FontStyle.normal);
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:const Text('یادآوری‌های روزانه')),
    body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(14),children:[
      Card(color:background,child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('نمونه یادآوری',style:_sample.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:8),
        Text('متن بخش انتخاب‌شده از یادداشت در اینجا نمایش داده می‌شود.',style:_sample),Align(alignment:Alignment.centerLeft,child:Text('بعدی  ›',style:_sample.copyWith(fontSize:12)))
      ]))),
      const SizedBox(height:10),Text('یادداشت‌های قابل نمایش',style:Theme.of(context).textTheme.titleMedium),
      const Text('فقط یادداشت‌هایی که انتخاب می‌کنی وارد گردش ویجت می‌شوند.'),
      ...widget.notes.map((n)=>CheckboxListTile(value:selected.contains(n.id),title:Text(n.title.isEmpty?'بدون عنوان':n.title),subtitle:Text('${_parts(n).length} بخش'),onChanged:(v)async{
        setState(()=>v==true?selected.add(n.id):selected.remove(n.id));await _save();
      })),
      const Divider(),Text('تنظیمات رنگ و فونت',style:Theme.of(context).textTheme.titleMedium),
      _colorSection('رنگ پس‌زمینه',background,true),_colorSection('رنگ متن',foreground,false),
      ListTile(title:const Text('اندازه فونت'),subtitle:Slider(min:12,max:28,divisions:16,value:size,onChanged:(v)=>setState(()=>size=v),onChangeEnd:(_)=>_save())),
      ListTile(title:const Text('سبک فونت'),subtitle:DropdownButton<String>(value:style,isExpanded:true,items:const[
        DropdownMenuItem(value:'normal',child:Text('معمولی')),DropdownMenuItem(value:'bold',child:Text('ضخیم')),
        DropdownMenuItem(value:'italic',child:Text('مورب')),DropdownMenuItem(value:'bold_italic',child:Text('ضخیم و مورب'))],
        onChanged:(v){if(v!=null){setState(()=>style=v);_save();}})),
      FilledButton.icon(onPressed:_save,icon:const Icon(Icons.save),label:const Text('ذخیره و اعمال تنظیمات'))
    ]))));
}
)).map((s)=>s.trim()).where((s)=>s.isNotEmpty).toList();
  Widget _rgbSlider(String label,Color c,bool isBg,int channel){
    final v=channel==0?c.red:channel==1?c.green:c.blue;
    return ListTile(dense:true,title:Text(label),subtitle:Slider(min:0,max:255,divisions:255,value:v.toDouble(),onChanged:(x){
      final r=channel==0?x.round():c.red,g=channel==1?x.round():c.green,b=channel==2?x.round():c.blue;
      setState(()=>isBg?background=Color.fromARGB(255,r,g,b):foreground=Color.fromARGB(255,r,g,b));
    },onChangeEnd:(_)=>_save()));
  }
  Widget _colorSection(String title,Color c,bool bg)=>ExpansionTile(title:title,subtitle:Container(height:22,width:22,decoration:BoxDecoration(color:c,shape:BoxShape.circle)),
    children:[_rgbSlider('قرمز',c,bg,0),_rgbSlider('سبز',c,bg,1),_rgbSlider('آبی',c,bg,2)]);
  TextStyle get _sample=>TextStyle(color:foreground,fontSize:size,fontWeight:style.contains('bold')?FontWeight.bold:FontWeight.normal,fontStyle:style.contains('italic')?FontStyle.italic:FontStyle.normal);
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:const Text('یادآوری‌های روزانه')),
    body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(14),children:[
      Card(color:background,child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('نمونه یادآوری',style:_sample.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:8),
        Text('متن بخش انتخاب‌شده از یادداشت در اینجا نمایش داده می‌شود.',style:_sample),Align(alignment:Alignment.centerLeft,child:Text('بعدی  ›',style:_sample.copyWith(fontSize:12)))
      ]))),
      const SizedBox(height:10),Text('یادداشت‌های قابل نمایش',style:Theme.of(context).textTheme.titleMedium),
      const Text('فقط یادداشت‌هایی که انتخاب می‌کنی وارد گردش ویجت می‌شوند.'),
      ...widget.notes.map((n)=>CheckboxListTile(value:selected.contains(n.id),title:Text(n.title.isEmpty?'بدون عنوان':n.title),subtitle:Text('${_parts(n).length} بخش'),onChanged:(v)async{
        setState(()=>v==true?selected.add(n.id):selected.remove(n.id));await _save();
      })),
      const Divider(),Text('تنظیمات رنگ و فونت',style:Theme.of(context).textTheme.titleMedium),
      _colorSection('رنگ پس‌زمینه',background,true),_colorSection('رنگ متن',foreground,false),
      ListTile(title:const Text('اندازه فونت'),subtitle:Slider(min:12,max:28,divisions:16,value:size,onChanged:(v)=>setState(()=>size=v),onChangeEnd:(_)=>_save())),
      ListTile(title:const Text('سبک فونت'),subtitle:DropdownButton<String>(value:style,isExpanded:true,items:const[
        DropdownMenuItem(value:'normal',child:Text('معمولی')),DropdownMenuItem(value:'bold',child:Text('ضخیم')),
        DropdownMenuItem(value:'italic',child:Text('مورب')),DropdownMenuItem(value:'bold_italic',child:Text('ضخیم و مورب'))],
        onChanged:(v){if(v!=null){setState(()=>style=v);_save();}})),
      FilledButton.icon(onPressed:_save,icon:const Icon(Icons.save),label:const Text('ذخیره و اعمال تنظیمات'))
    ]))));
}
).hasMatch(lines.first);
    final ends = lines.isNotEmpty && RegExp(r'^[ \\t]*-{20,}[ \\t]*
  Widget _rgbSlider(String label,Color c,bool isBg,int channel){
    final v=channel==0?c.red:channel==1?c.green:c.blue;
    return ListTile(dense:true,title:Text(label),subtitle:Slider(min:0,max:255,divisions:255,value:v.toDouble(),onChanged:(x){
      final r=channel==0?x.round():c.red,g=channel==1?x.round():c.green,b=channel==2?x.round():c.blue;
      setState(()=>isBg?background=Color.fromARGB(255,r,g,b):foreground=Color.fromARGB(255,r,g,b));
    },onChangeEnd:(_)=>_save()));
  }
  Widget _colorSection(String title,Color c,bool bg)=>ExpansionTile(title:title,subtitle:Container(height:22,width:22,decoration:BoxDecoration(color:c,shape:BoxShape.circle)),
    children:[_rgbSlider('قرمز',c,bg,0),_rgbSlider('سبز',c,bg,1),_rgbSlider('آبی',c,bg,2)]);
  TextStyle get _sample=>TextStyle(color:foreground,fontSize:size,fontWeight:style.contains('bold')?FontWeight.bold:FontWeight.normal,fontStyle:style.contains('italic')?FontStyle.italic:FontStyle.normal);
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:const Text('یادآوری‌های روزانه')),
    body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(14),children:[
      Card(color:background,child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('نمونه یادآوری',style:_sample.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:8),
        Text('متن بخش انتخاب‌شده از یادداشت در اینجا نمایش داده می‌شود.',style:_sample),Align(alignment:Alignment.centerLeft,child:Text('بعدی  ›',style:_sample.copyWith(fontSize:12)))
      ]))),
      const SizedBox(height:10),Text('یادداشت‌های قابل نمایش',style:Theme.of(context).textTheme.titleMedium),
      const Text('فقط یادداشت‌هایی که انتخاب می‌کنی وارد گردش ویجت می‌شوند.'),
      ...widget.notes.map((n)=>CheckboxListTile(value:selected.contains(n.id),title:Text(n.title.isEmpty?'بدون عنوان':n.title),subtitle:Text('${_parts(n).length} بخش'),onChanged:(v)async{
        setState(()=>v==true?selected.add(n.id):selected.remove(n.id));await _save();
      })),
      const Divider(),Text('تنظیمات رنگ و فونت',style:Theme.of(context).textTheme.titleMedium),
      _colorSection('رنگ پس‌زمینه',background,true),_colorSection('رنگ متن',foreground,false),
      ListTile(title:const Text('اندازه فونت'),subtitle:Slider(min:12,max:28,divisions:16,value:size,onChanged:(v)=>setState(()=>size=v),onChangeEnd:(_)=>_save())),
      ListTile(title:const Text('سبک فونت'),subtitle:DropdownButton<String>(value:style,isExpanded:true,items:const[
        DropdownMenuItem(value:'normal',child:Text('معمولی')),DropdownMenuItem(value:'bold',child:Text('ضخیم')),
        DropdownMenuItem(value:'italic',child:Text('مورب')),DropdownMenuItem(value:'bold_italic',child:Text('ضخیم و مورب'))],
        onChanged:(v){if(v!=null){setState(()=>style=v);_save();}})),
      FilledButton.icon(onPressed:_save,icon:const Icon(Icons.save),label:const Text('ذخیره و اعمال تنظیمات'))
    ]))));
}
)).map((s)=>s.trim()).where((s)=>s.isNotEmpty).toList();
  Widget _rgbSlider(String label,Color c,bool isBg,int channel){
    final v=channel==0?c.red:channel==1?c.green:c.blue;
    return ListTile(dense:true,title:Text(label),subtitle:Slider(min:0,max:255,divisions:255,value:v.toDouble(),onChanged:(x){
      final r=channel==0?x.round():c.red,g=channel==1?x.round():c.green,b=channel==2?x.round():c.blue;
      setState(()=>isBg?background=Color.fromARGB(255,r,g,b):foreground=Color.fromARGB(255,r,g,b));
    },onChangeEnd:(_)=>_save()));
  }
  Widget _colorSection(String title,Color c,bool bg)=>ExpansionTile(title:title,subtitle:Container(height:22,width:22,decoration:BoxDecoration(color:c,shape:BoxShape.circle)),
    children:[_rgbSlider('قرمز',c,bg,0),_rgbSlider('سبز',c,bg,1),_rgbSlider('آبی',c,bg,2)]);
  TextStyle get _sample=>TextStyle(color:foreground,fontSize:size,fontWeight:style.contains('bold')?FontWeight.bold:FontWeight.normal,fontStyle:style.contains('italic')?FontStyle.italic:FontStyle.normal);
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:const Text('یادآوری‌های روزانه')),
    body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(14),children:[
      Card(color:background,child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('نمونه یادآوری',style:_sample.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:8),
        Text('متن بخش انتخاب‌شده از یادداشت در اینجا نمایش داده می‌شود.',style:_sample),Align(alignment:Alignment.centerLeft,child:Text('بعدی  ›',style:_sample.copyWith(fontSize:12)))
      ]))),
      const SizedBox(height:10),Text('یادداشت‌های قابل نمایش',style:Theme.of(context).textTheme.titleMedium),
      const Text('فقط یادداشت‌هایی که انتخاب می‌کنی وارد گردش ویجت می‌شوند.'),
      ...widget.notes.map((n)=>CheckboxListTile(value:selected.contains(n.id),title:Text(n.title.isEmpty?'بدون عنوان':n.title),subtitle:Text('${_parts(n).length} بخش'),onChanged:(v)async{
        setState(()=>v==true?selected.add(n.id):selected.remove(n.id));await _save();
      })),
      const Divider(),Text('تنظیمات رنگ و فونت',style:Theme.of(context).textTheme.titleMedium),
      _colorSection('رنگ پس‌زمینه',background,true),_colorSection('رنگ متن',foreground,false),
      ListTile(title:const Text('اندازه فونت'),subtitle:Slider(min:12,max:28,divisions:16,value:size,onChanged:(v)=>setState(()=>size=v),onChangeEnd:(_)=>_save())),
      ListTile(title:const Text('سبک فونت'),subtitle:DropdownButton<String>(value:style,isExpanded:true,items:const[
        DropdownMenuItem(value:'normal',child:Text('معمولی')),DropdownMenuItem(value:'bold',child:Text('ضخیم')),
        DropdownMenuItem(value:'italic',child:Text('مورب')),DropdownMenuItem(value:'bold_italic',child:Text('ضخیم و مورب'))],
        onChanged:(v){if(v!=null){setState(()=>style=v);_save();}})),
      FilledButton.icon(onPressed:_save,icon:const Icon(Icons.save),label:const Text('ذخیره و اعمال تنظیمات'))
    ]))));
}
).hasMatch(lines.last);
    if (!begins && chunks.isNotEmpty) chunks.removeAt(0);
    if (!ends && chunks.isNotEmpty) chunks.removeLast();
    return chunks.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }
  Widget _rgbSlider(String label,Color c,bool isBg,int channel){
    final v=channel==0?c.red:channel==1?c.green:c.blue;
    return ListTile(dense:true,title:Text(label),subtitle:Slider(min:0,max:255,divisions:255,value:v.toDouble(),onChanged:(x){
      final r=channel==0?x.round():c.red,g=channel==1?x.round():c.green,b=channel==2?x.round():c.blue;
      setState(()=>isBg?background=Color.fromARGB(255,r,g,b):foreground=Color.fromARGB(255,r,g,b));
    },onChangeEnd:(_)=>_save()));
  }
  Widget _colorSection(String title,Color c,bool bg)=>ExpansionTile(title:title,subtitle:Container(height:22,width:22,decoration:BoxDecoration(color:c,shape:BoxShape.circle)),
    children:[_rgbSlider('قرمز',c,bg,0),_rgbSlider('سبز',c,bg,1),_rgbSlider('آبی',c,bg,2)]);
  TextStyle get _sample=>TextStyle(color:foreground,fontSize:size,fontWeight:style.contains('bold')?FontWeight.bold:FontWeight.normal,fontStyle:style.contains('italic')?FontStyle.italic:FontStyle.normal);
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:const Text('یادآوری‌های روزانه')),
    body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(14),children:[
      Card(color:background,child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('نمونه یادآوری',style:_sample.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:8),
        Text('متن بخش انتخاب‌شده از یادداشت در اینجا نمایش داده می‌شود.',style:_sample),Align(alignment:Alignment.centerLeft,child:Text('بعدی  ›',style:_sample.copyWith(fontSize:12)))
      ]))),
      const SizedBox(height:10),Text('یادداشت‌های قابل نمایش',style:Theme.of(context).textTheme.titleMedium),
      const Text('فقط یادداشت‌هایی که انتخاب می‌کنی وارد گردش ویجت می‌شوند.'),
      ...widget.notes.map((n)=>CheckboxListTile(value:selected.contains(n.id),title:Text(n.title.isEmpty?'بدون عنوان':n.title),subtitle:Text('${_parts(n).length} بخش'),onChanged:(v)async{
        setState(()=>v==true?selected.add(n.id):selected.remove(n.id));await _save();
      })),
      const Divider(),Text('تنظیمات رنگ و فونت',style:Theme.of(context).textTheme.titleMedium),
      _colorSection('رنگ پس‌زمینه',background,true),_colorSection('رنگ متن',foreground,false),
      ListTile(title:const Text('اندازه فونت'),subtitle:Slider(min:12,max:28,divisions:16,value:size,onChanged:(v)=>setState(()=>size=v),onChangeEnd:(_)=>_save())),
      ListTile(title:const Text('سبک فونت'),subtitle:DropdownButton<String>(value:style,isExpanded:true,items:const[
        DropdownMenuItem(value:'normal',child:Text('معمولی')),DropdownMenuItem(value:'bold',child:Text('ضخیم')),
        DropdownMenuItem(value:'italic',child:Text('مورب')),DropdownMenuItem(value:'bold_italic',child:Text('ضخیم و مورب'))],
        onChanged:(v){if(v!=null){setState(()=>style=v);_save();}})),
      FilledButton.icon(onPressed:_save,icon:const Icon(Icons.save),label:const Text('ذخیره و اعمال تنظیمات'))
    ]))));
}
)).map((s)=>s.trim()).where((s)=>s.isNotEmpty).toList();
  Widget _rgbSlider(String label,Color c,bool isBg,int channel){
    final v=channel==0?c.red:channel==1?c.green:c.blue;
    return ListTile(dense:true,title:Text(label),subtitle:Slider(min:0,max:255,divisions:255,value:v.toDouble(),onChanged:(x){
      final r=channel==0?x.round():c.red,g=channel==1?x.round():c.green,b=channel==2?x.round():c.blue;
      setState(()=>isBg?background=Color.fromARGB(255,r,g,b):foreground=Color.fromARGB(255,r,g,b));
    },onChangeEnd:(_)=>_save()));
  }
  Widget _colorSection(String title,Color c,bool bg)=>ExpansionTile(title:title,subtitle:Container(height:22,width:22,decoration:BoxDecoration(color:c,shape:BoxShape.circle)),
    children:[_rgbSlider('قرمز',c,bg,0),_rgbSlider('سبز',c,bg,1),_rgbSlider('آبی',c,bg,2)]);
  TextStyle get _sample=>TextStyle(color:foreground,fontSize:size,fontWeight:style.contains('bold')?FontWeight.bold:FontWeight.normal,fontStyle:style.contains('italic')?FontStyle.italic:FontStyle.normal);
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:const Text('یادآوری‌های روزانه')),
    body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(14),children:[
      Card(color:background,child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('نمونه یادآوری',style:_sample.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:8),
        Text('متن بخش انتخاب‌شده از یادداشت در اینجا نمایش داده می‌شود.',style:_sample),Align(alignment:Alignment.centerLeft,child:Text('بعدی  ›',style:_sample.copyWith(fontSize:12)))
      ]))),
      const SizedBox(height:10),Text('یادداشت‌های قابل نمایش',style:Theme.of(context).textTheme.titleMedium),
      const Text('فقط یادداشت‌هایی که انتخاب می‌کنی وارد گردش ویجت می‌شوند.'),
      ...widget.notes.map((n)=>CheckboxListTile(value:selected.contains(n.id),title:Text(n.title.isEmpty?'بدون عنوان':n.title),subtitle:Text('${_parts(n).length} بخش'),onChanged:(v)async{
        setState(()=>v==true?selected.add(n.id):selected.remove(n.id));await _save();
      })),
      const Divider(),Text('تنظیمات رنگ و فونت',style:Theme.of(context).textTheme.titleMedium),
      _colorSection('رنگ پس‌زمینه',background,true),_colorSection('رنگ متن',foreground,false),
      ListTile(title:const Text('اندازه فونت'),subtitle:Slider(min:12,max:28,divisions:16,value:size,onChanged:(v)=>setState(()=>size=v),onChangeEnd:(_)=>_save())),
      ListTile(title:const Text('سبک فونت'),subtitle:DropdownButton<String>(value:style,isExpanded:true,items:const[
        DropdownMenuItem(value:'normal',child:Text('معمولی')),DropdownMenuItem(value:'bold',child:Text('ضخیم')),
        DropdownMenuItem(value:'italic',child:Text('مورب')),DropdownMenuItem(value:'bold_italic',child:Text('ضخیم و مورب'))],
        onChanged:(v){if(v!=null){setState(()=>style=v);_save();}})),
      FilledButton.icon(onPressed:_save,icon:const Icon(Icons.save),label:const Text('ذخیره و اعمال تنظیمات'))
    ]))));
}

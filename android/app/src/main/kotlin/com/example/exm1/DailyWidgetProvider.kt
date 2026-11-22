package com.example.exm1
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Typeface
import android.widget.RemoteViews
import org.json.JSONArray

class DailyWidgetProvider:AppWidgetProvider(){
 override fun onUpdate(context:Context,manager:AppWidgetManager,ids:IntArray){advance(context)}
 override fun onReceive(context:Context,intent:Intent){super.onReceive(context,intent);if(intent.action==NEXT_ACTION)advance(context)}
 companion object{
  private const val NEXT_ACTION="com.mhasanzare82.daftarcheeshtebahat.DAILY_WIDGET_NEXT"
  private const val PREF="FlutterSharedPreferences"
  private const val NOTES="flutter.notebook_notes"
  private const val SELECTED="flutter.daily_widget_selected_note_ids"
  private const val INDEX="flutter.daily_widget_current_segment"
  private const val BG="flutter.daily_widget_background_color"
  private const val FG="flutter.daily_widget_text_color"
  private const val SIZE="flutter.daily_widget_font_size"
  private const val STYLE="flutter.daily_widget_font_style"
  fun refreshAll(c:Context)=advance(c)
  private fun advance(c:Context){
   val p=c.getSharedPreferences(PREF,Context.MODE_PRIVATE);val list=items(p.getString(NOTES,"[]"),p.getString(SELECTED,"[]"))
   val old=p.getInt(INDEX,-1);val next=if(list.isEmpty())0 else (old+1)%list.size
   p.edit().putInt(INDEX,next).apply();render(c,next)
  }
  private data class Entry(val title:String,val body:String)
  private fun render(c:Context,index:Int){
   val p=c.getSharedPreferences(PREF,Context.MODE_PRIVATE);val data=items(p.getString(NOTES,"[]"),p.getString(SELECTED,"[]"));val e=data.getOrNull(index)
   val manager=AppWidgetManager.getInstance(c);val ids=manager.getAppWidgetIds(ComponentName(c,DailyWidgetProvider::class.java));if(ids.isEmpty())return
   val v=RemoteViews(c.packageName,R.layout.daily_widget)
   val bg=p.getInt(BG,0xFF202329.toInt());val fg=p.getInt(FG,0xFFF4F4F5.toInt());val sz=p.getFloat(SIZE,16f).coerceIn(12f,28f)
   val font=when(p.getString(STYLE,"normal")){"bold"->Typeface.BOLD;"italic"->Typeface.ITALIC;"bold_italic"->Typeface.BOLD_ITALIC;else->Typeface.NORMAL}
   v.setInt(R.id.daily_widget_root,"setBackgroundColor",bg);v.setTextColor(R.id.daily_widget_title,fg);v.setTextColor(R.id.daily_widget_body,fg);v.setTextColor(R.id.daily_widget_next,fg)
   v.setTextViewText(R.id.daily_widget_title,e?.title?: "یادآوری‌های روزانه")
   v.setTextViewText(R.id.daily_widget_body,e?.body?: "از تنظیمات ویجت، یادداشت‌هایی را انتخاب کن.")
   v.setFloat(R.id.daily_widget_body,"setTextSize",sz);v.setInt(R.id.daily_widget_title,"setTypeface",Typeface.BOLD);v.setInt(R.id.daily_widget_body,"setTypeface",font)
   val launch=c.packageManager.getLaunchIntentForPackage(c.packageName)?:Intent(c,MainActivity::class.java);launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
   val open=PendingIntent.getActivity(c,5100,launch,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE);v.setOnClickPendingIntent(R.id.daily_widget_root,open)
   val next=Intent(c,DailyWidgetProvider::class.java).setAction(NEXT_ACTION)
   val nextPending=PendingIntent.getBroadcast(c,5101,next,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE);v.setOnClickPendingIntent(R.id.daily_widget_next,nextPending)
   ids.forEach{manager.updateAppWidget(it,v)}
  }
  private fun items(rawNotes:String?,rawIds:String?):List<Entry>{
   val ns=try{JSONArray(rawNotes?: "[]")}catch(_:Exception){JSONArray()};val ss=try{JSONArray(rawIds?: "[]")}catch(_:Exception){JSONArray()}
   val ids=(0 until ss.length()).map{ss.optString(it)}.toSet();val result=mutableListOf<Entry>()
   for(i in 0 until ns.length()){val n=ns.optJSONObject(i)?:continue;if(n.optString("id") !in ids)continue
    val title=n.optString("title").ifBlank{"بدون عنوان"};val body=plain(n.optString("body"))
    val separator=Regex("(?m)^[ \\t]*-{20,}[ \\t]*$")
    val chunks=body.split(separator).toMutableList()
    val lines=body.trimEnd().split('\\n')
    val begins=lines.firstOrNull()?.let{Regex("^[ \\t]*-{20,}[ \\t]*$").matches(it)}?:false
    val ends=lines.lastOrNull()?.let{Regex("^[ \\t]*-{20,}[ \\t]*$").matches(it)}?:false
    if(!begins&&chunks.isNotEmpty())chunks.removeAt(0)
    if(!ends&&chunks.isNotEmpty())chunks.removeAt(chunks.lastIndex)
    chunks.map{it.trim()}.filter{it.isNotEmpty()}.forEach{result.add(Entry(title,it))}
   }
   return result
  }
  private fun plain(body:String):String{
   val q="__quill_note_v1__";val legacy="__rich_note_v1__"
   return try{when{
    body.startsWith(q)->{val a=JSONArray(body.removePrefix(q));buildString{for(i in 0 until a.length()){val ins=a.optJSONObject(i)?.opt("insert");if(ins is String)append(ins)}}}
    body.startsWith(legacy)->{val a=JSONArray(body.removePrefix(legacy));buildString{for(i in 0 until a.length()){val b=a.optJSONObject(i)?:continue;if(b.optString("type")=="text")append(b.optString("text")).append(' ')}}}
    body.trimStart().startsWith("[")-> {val a=JSONArray(body);buildString{for(i in 0 until a.length()){val b=a.optJSONObject(i)?:continue;if(b.optString("type")=="text")append(b.optString("text")).append(' ')}}}
    else->body
   }}catch(_:Exception){body.removePrefix(q).removePrefix(legacy)}
  }
 }
}

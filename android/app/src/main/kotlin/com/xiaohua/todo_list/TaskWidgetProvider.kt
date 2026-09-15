package com.xiaohua.todo_list

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import java.time.LocalDate

abstract class TaskWidgetProvider : AppWidgetProvider() {
    abstract val kind: String

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { updateWidget(context, appWidgetManager, it, kind) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        updateWidget(context, appWidgetManager, appWidgetId, kind)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        preferences.edit().apply {
            appWidgetIds.forEach { remove(expandedKey(it)) }
        }.apply()
    }

    companion object {
        const val PREFERENCES = "todo_task_widgets"

        fun expandedKey(appWidgetId: Int) = "expanded_task_$appWidgetId"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            listOf(
                ComponentName(context, NowTaskWidgetProvider::class.java) to WidgetContract.KIND_NOW,
                ComponentName(context, WeekTaskWidgetProvider::class.java) to WidgetContract.KIND_WEEK,
            ).forEach { (component, kind) ->
                manager.getAppWidgetIds(component).forEach { id ->
                    manager.notifyAppWidgetViewDataChanged(id, R.id.widget_list)
                    updateWidget(context, manager, id, kind)
                }
            }
        }

        fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            appWidgetId: Int,
            kind: String,
        ) {
            val views = RemoteViews(context.packageName, R.layout.task_widget)
            val ready = WidgetTaskStore(context).isReady()
            views.setTextViewText(
                R.id.widget_title,
                if (kind == WidgetContract.KIND_NOW) "现在" else "本周",
            )
            if (kind == WidgetContract.KIND_WEEK) {
                val today = LocalDate.now()
                val start = today.minusDays((today.dayOfWeek.value - 1).toLong())
                val end = start.plusDays(6)
                views.setViewVisibility(R.id.widget_subtitle, View.VISIBLE)
                views.setTextViewText(
                    R.id.widget_subtitle,
                    "${start.monthValue}月${start.dayOfMonth}日—${end.monthValue}月${end.dayOfMonth}日",
                )
            } else {
                views.setViewVisibility(R.id.widget_subtitle, View.GONE)
            }

            val serviceIntent = Intent(context, TaskWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                putExtra(WidgetContract.EXTRA_KIND, kind)
                data = Uri.parse("todo-widget://collection/$kind/$appWidgetId")
            }
            views.setRemoteAdapter(R.id.widget_list, serviceIntent)
            views.setEmptyView(R.id.widget_list, R.id.widget_empty)
            views.setTextViewText(
                R.id.widget_empty,
                if (ready) "暂无任务" else "先打开一次应用完成初始化",
            )

            val templateIntent = Intent(context, WidgetActionReceiver::class.java)
            val template = PendingIntent.getBroadcast(
                context,
                appWidgetId,
                templateIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            )
            views.setPendingIntentTemplate(R.id.widget_list, template)

            val addIntent = Intent(context, WidgetQuickTaskActivity::class.java).apply {
                putExtra(WidgetContract.EXTRA_MODE, WidgetContract.MODE_ADD)
                putExtra(WidgetContract.EXTRA_KIND, kind)
                putExtra(WidgetContract.EXTRA_WIDGET_ID, appWidgetId)
            }
            views.setOnClickPendingIntent(
                R.id.widget_add,
                PendingIntent.getActivity(
                    context,
                    10_000 + appWidgetId,
                    addIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )

            val openApp = Intent(context, MainActivity::class.java)
            views.setOnClickPendingIntent(
                R.id.widget_header,
                PendingIntent.getActivity(
                    context,
                    20_000 + appWidgetId,
                    openApp,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            manager.updateAppWidget(appWidgetId, views)
        }
    }
}

class NowTaskWidgetProvider : TaskWidgetProvider() {
    override val kind = WidgetContract.KIND_NOW
}

class WeekTaskWidgetProvider : TaskWidgetProvider() {
    override val kind = WidgetContract.KIND_WEEK
}

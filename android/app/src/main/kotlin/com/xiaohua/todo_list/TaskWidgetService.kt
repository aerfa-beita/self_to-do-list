package com.xiaohua.todo_list

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import java.time.LocalDate

private sealed interface WidgetEntry {
    data class Day(val label: String) : WidgetEntry
    data class Task(val task: WidgetTask) : WidgetEntry
}

class TaskWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsService.RemoteViewsFactory =
        Factory(applicationContext, intent)

    private class Factory(
        private val context: Context,
        intent: Intent,
    ) : RemoteViewsService.RemoteViewsFactory {
        private val kind = intent.getStringExtra(WidgetContract.EXTRA_KIND) ?: WidgetContract.KIND_NOW
        private val appWidgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        )
        private var entries = emptyList<WidgetEntry>()

        override fun onCreate() = Unit

        override fun onDataSetChanged() {
            val preferences = context.getSharedPreferences(
                TaskWidgetProvider.PREFERENCES,
                Context.MODE_PRIVATE,
            )
            val expanded = preferences.getLong(TaskWidgetProvider.expandedKey(appWidgetId), -1L)
                .takeIf { it >= 0 }
            val store = WidgetTaskStore(context)
            val tasks = if (kind == WidgetContract.KIND_WEEK) {
                store.weekTasks(expanded)
            } else {
                store.nowTasks(expanded)
            }
            entries = if (kind == WidgetContract.KIND_WEEK) weekEntries(tasks) else tasks.map {
                WidgetEntry.Task(it)
            }
        }

        private fun weekEntries(tasks: List<WidgetTask>): List<WidgetEntry> {
            val result = mutableListOf<WidgetEntry>()
            var lastDate: String? = null
            tasks.forEach { task ->
                val date = task.dueDate?.take(10) ?: return@forEach
                if (date != lastDate) {
                    result += WidgetEntry.Day(dayLabel(date))
                    lastDate = date
                }
                result += WidgetEntry.Task(task)
            }
            return result
        }

        private fun dayLabel(value: String): String {
            val date = LocalDate.parse(value)
            val names = arrayOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")
            val weekday = names[date.dayOfWeek.value - 1]
            return if (date == LocalDate.now()) "今天 · $weekday" else weekday
        }

        override fun onDestroy() {
            entries = emptyList()
        }

        override fun getCount(): Int = entries.size

        override fun getViewAt(position: Int): RemoteViews? {
            if (position !in entries.indices) return null
            return when (val entry = entries[position]) {
                is WidgetEntry.Day -> RemoteViews(context.packageName, R.layout.widget_day_item).apply {
                    setTextViewText(R.id.widget_day_title, entry.label)
                }
                is WidgetEntry.Task -> taskView(entry.task)
            }
        }

        private fun taskView(task: WidgetTask): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_task_item)
            views.setTextViewText(R.id.widget_task_title, task.title)
            views.setImageViewResource(
                R.id.widget_task_check,
                if (task.completed) R.drawable.ic_widget_check_done else R.drawable.ic_widget_check_empty,
            )
            views.setTextViewText(
                R.id.widget_task_progress,
                if (task.total > 0) "${task.done}/${task.total}" else "",
            )
            views.setViewVisibility(
                R.id.widget_task_expand,
                if (task.total > 0) View.VISIBLE else View.INVISIBLE,
            )
            val expanded = task.subTasks.isNotEmpty()
            views.setImageViewResource(
                R.id.widget_task_expand,
                if (expanded) R.drawable.ic_expand_less else R.drawable.ic_expand_more,
            )
            views.removeAllViews(R.id.widget_subtask_container)
            views.setViewVisibility(
                R.id.widget_subtask_container,
                if (expanded) View.VISIBLE else View.GONE,
            )
            task.subTasks.forEach { subTask ->
                val child = RemoteViews(context.packageName, R.layout.widget_subtask_item)
                child.setTextViewText(R.id.widget_subtask_title, subTask.title)
                child.setImageViewResource(
                    R.id.widget_subtask_check,
                    if (subTask.isDone) R.drawable.ic_widget_check_done else R.drawable.ic_widget_check_empty,
                )
                child.setOnClickFillInIntent(
                    R.id.widget_subtask_check,
                    actionIntent(WidgetContract.ACTION_TOGGLE_SUBTASK).apply {
                        putExtra(WidgetContract.EXTRA_SUBTASK_ID, subTask.id)
                    },
                )
                views.addView(R.id.widget_subtask_container, child)
            }
            views.setOnClickFillInIntent(
                R.id.widget_task_check,
                actionIntent(WidgetContract.ACTION_TOGGLE_TASK).apply {
                    putExtra(WidgetContract.EXTRA_TASK_ID, task.id)
                },
            )
            views.setOnClickFillInIntent(
                R.id.widget_task_expand,
                actionIntent(WidgetContract.ACTION_TOGGLE_EXPANDED).apply {
                    putExtra(WidgetContract.EXTRA_TASK_ID, task.id)
                },
            )
            views.setOnClickFillInIntent(
                R.id.widget_task_menu,
                actionIntent(WidgetContract.ACTION_OPEN_MENU).apply {
                    putExtra(WidgetContract.EXTRA_TASK_ID, task.id)
                },
            )
            return views
        }

        private fun actionIntent(actionName: String) = Intent().apply {
            action = actionName
            putExtra(WidgetContract.EXTRA_KIND, kind)
            putExtra(WidgetContract.EXTRA_WIDGET_ID, appWidgetId)
        }

        override fun getLoadingView(): RemoteViews? = null
        override fun getViewTypeCount(): Int = 2
        override fun getItemId(position: Int): Long = when (val entry = entries[position]) {
            is WidgetEntry.Day -> -position.toLong() - 1
            is WidgetEntry.Task -> entry.task.id
        }
        override fun hasStableIds(): Boolean = true
    }
}

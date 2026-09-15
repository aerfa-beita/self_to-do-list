package com.xiaohua.todo_list

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.widget.Toast

class WidgetActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val store = WidgetTaskStore(context)
        val widgetId = intent.getIntExtra(WidgetContract.EXTRA_WIDGET_ID, -1)
        val taskId = intent.getLongExtra(WidgetContract.EXTRA_TASK_ID, -1L)
        val success = when (intent.action) {
            WidgetContract.ACTION_TOGGLE_TASK -> taskId >= 0 && store.toggleTask(taskId)
            WidgetContract.ACTION_TOGGLE_SUBTASK -> {
                val subTaskId = intent.getLongExtra(WidgetContract.EXTRA_SUBTASK_ID, -1L)
                subTaskId >= 0 && store.toggleSubTask(subTaskId)
            }
            WidgetContract.ACTION_TOGGLE_EXPANDED -> {
                if (widgetId < 0 || taskId < 0) {
                    false
                } else {
                    val preferences = context.getSharedPreferences(
                        TaskWidgetProvider.PREFERENCES,
                        Context.MODE_PRIVATE,
                    )
                    val key = TaskWidgetProvider.expandedKey(widgetId)
                    val next = if (preferences.getLong(key, -1L) == taskId) -1L else taskId
                    preferences.edit().putLong(key, next).apply()
                    true
                }
            }
            WidgetContract.ACTION_OPEN_MENU -> {
                if (taskId < 0) {
                    false
                } else {
                    context.startActivity(
                        Intent(context, WidgetQuickTaskActivity::class.java).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            putExtra(WidgetContract.EXTRA_MODE, WidgetContract.MODE_MENU)
                            putExtra(WidgetContract.EXTRA_TASK_ID, taskId)
                            putExtra(
                                WidgetContract.EXTRA_KIND,
                                intent.getStringExtra(WidgetContract.EXTRA_KIND),
                            )
                        },
                    )
                    true
                }
            }
            else -> false
        }
        if (!success) Toast.makeText(context, "操作失败，请打开应用重试", Toast.LENGTH_SHORT).show()
        TaskWidgetProvider.updateAll(context)
    }
}

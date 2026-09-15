package com.xiaohua.todo_list

object WidgetContract {
    const val KIND_NOW = "now"
    const val KIND_WEEK = "week"
    const val EXTRA_KIND = "widget_kind"
    const val EXTRA_TASK_ID = "task_id"
    const val EXTRA_SUBTASK_ID = "subtask_id"
    const val EXTRA_WIDGET_ID = "app_widget_id"

    const val ACTION_TOGGLE_TASK = "com.xiaohua.todo_list.widget.TOGGLE_TASK"
    const val ACTION_TOGGLE_SUBTASK = "com.xiaohua.todo_list.widget.TOGGLE_SUBTASK"
    const val ACTION_TOGGLE_EXPANDED = "com.xiaohua.todo_list.widget.TOGGLE_EXPANDED"
    const val ACTION_OPEN_MENU = "com.xiaohua.todo_list.widget.OPEN_MENU"

    const val MODE_ADD = "add"
    const val MODE_MENU = "menu"
    const val EXTRA_MODE = "mode"
}

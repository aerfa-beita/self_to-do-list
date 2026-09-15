package com.xiaohua.todo_list

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.text.InputType
import android.view.WindowManager
import android.widget.EditText
import android.widget.Toast

class WidgetQuickTaskActivity : Activity() {
    private val store by lazy { WidgetTaskStore(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        if (!store.isReady()) {
            Toast.makeText(this, "先打开一次应用完成初始化", Toast.LENGTH_SHORT).show()
            startActivity(Intent(this, MainActivity::class.java))
            finish()
            return
        }
        when (intent.getStringExtra(WidgetContract.EXTRA_MODE)) {
            WidgetContract.MODE_MENU -> showMenu()
            else -> showAdd()
        }
    }

    private fun showAdd() {
        val kind = intent.getStringExtra(WidgetContract.EXTRA_KIND) ?: WidgetContract.KIND_NOW
        val target = if (kind == WidgetContract.KIND_WEEK) "今天" else "现在"
        showTitleDialog(
            title = "添加到「$target」",
            initialValue = "",
            positiveLabel = "添加",
        ) { value ->
            finishWithResult(store.insertTask(value, kind), "已添加到$target")
        }
    }

    private fun showMenu() {
        val taskId = intent.getLongExtra(WidgetContract.EXTRA_TASK_ID, -1L)
        if (taskId < 0) {
            finish()
            return
        }
        val taskTitle = store.taskTitle(taskId) ?: run {
            finish()
            return
        }
        AlertDialog.Builder(this)
            .setTitle(taskTitle)
            .setItems(arrayOf("编辑", "移到：现在", "移到：接下来", "移到：稍后", "删除")) { _, which ->
                when (which) {
                    0 -> showTitleDialog("编辑任务", taskTitle, "保存") { value ->
                        finishWithResult(store.renameTask(taskId, value), "已保存")
                    }
                    1 -> finishWithResult(store.moveTask(taskId, "plan_now"), "已移到现在")
                    2 -> finishWithResult(store.moveTask(taskId, "plan_next"), "已移到接下来")
                    3 -> finishWithResult(store.moveTask(taskId, "plan_later"), "已移到稍后")
                    4 -> confirmDelete(taskId, taskTitle)
                }
            }
            .setNegativeButton("取消") { _, _ -> finish() }
            .setOnCancelListener { finish() }
            .show()
    }

    private fun showTitleDialog(
        title: String,
        initialValue: String,
        positiveLabel: String,
        onSubmit: (String) -> Unit,
    ) {
        val input = EditText(this).apply {
            setText(initialValue)
            setSelection(text.length)
            hint = "任务名称"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            setSingleLine(true)
            setPadding(48, 24, 48, 24)
        }
        val dialog = AlertDialog.Builder(this)
            .setTitle(title)
            .setView(input)
            .setNegativeButton("取消") { _, _ -> finish() }
            .setPositiveButton(positiveLabel, null)
            .setOnCancelListener { finish() }
            .create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val value = input.text.toString().trim()
                if (value.isNotEmpty()) onSubmit(value)
            }
            input.requestFocus()
            window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE)
        }
        dialog.show()
    }

    private fun confirmDelete(taskId: Long, title: String) {
        AlertDialog.Builder(this)
            .setTitle("删除任务")
            .setMessage("确定删除「$title」？任务仍可在最近删除中恢复。")
            .setNegativeButton("取消") { _, _ -> finish() }
            .setPositiveButton("删除") { _, _ ->
                finishWithResult(store.softDeleteTask(taskId), "已移到最近删除")
            }
            .setOnCancelListener { finish() }
            .show()
    }

    private fun finishWithResult(success: Boolean, message: String) {
        Toast.makeText(
            this,
            if (success) message else "操作失败，请打开应用重试",
            Toast.LENGTH_SHORT,
        ).show()
        TaskWidgetProvider.updateAll(this)
        finish()
    }
}

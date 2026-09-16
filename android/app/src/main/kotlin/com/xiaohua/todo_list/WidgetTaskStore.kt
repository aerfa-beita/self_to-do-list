package com.xiaohua.todo_list

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import java.io.File
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.UUID

data class WidgetSubTask(
    val id: Long,
    val title: String,
    val isDone: Boolean,
)

data class WidgetTask(
    val id: Long,
    val title: String,
    val mode: String,
    val dueDate: String?,
    val completed: Boolean,
    val total: Int,
    val done: Int,
    val subTasks: List<WidgetSubTask> = emptyList(),
)

class WidgetTaskStore(private val context: Context) {
    private val databaseFile: File
        get() = context.getDatabasePath("todo_list.db")

    fun isReady(): Boolean = databaseFile.exists()

    private fun <T> withDatabase(block: (SQLiteDatabase) -> T): T? {
        if (!databaseFile.exists()) return null
        val database = SQLiteDatabase.openDatabase(
            databaseFile.path,
            null,
            SQLiteDatabase.OPEN_READWRITE,
        )
        return try {
            block(database)
        } finally {
            database.close()
        }
    }

    fun nowTasks(expandedTaskId: Long?): List<WidgetTask> =
        queryTasks(
            "t.deleted_at IS NULL AND t.completed_at IS NULL " +
                "AND t.companion_stashed_at IS NULL AND t.task_mode IN (?, ?)",
            arrayOf("plan_now", "flow"),
            expandedTaskId,
        )

    fun weekTasks(expandedTaskId: Long?): List<WidgetTask> {
        val today = LocalDate.now()
        val start = today.minusDays((today.dayOfWeek.value - 1).toLong())
        val end = start.plusDays(7)
        return queryTasks(
            "t.deleted_at IS NULL AND t.completed_at IS NULL " +
                "AND t.companion_stashed_at IS NULL AND substr(t.due_date, 1, 10) >= ? " +
                "AND substr(t.due_date, 1, 10) < ?",
            arrayOf(start.toString(), end.toString()),
            expandedTaskId,
            "substr(t.due_date, 1, 10) ASC, t.week_sort_order ASC, t.id ASC",
        )
    }

    private fun queryTasks(
        where: String,
        args: Array<String>,
        expandedTaskId: Long?,
        orderBy: String = "t.sort_order ASC, t.id ASC",
    ): List<WidgetTask> = withDatabase { database ->
        val tasks = mutableListOf<WidgetTask>()
        val actualOrder = if (orderBy.contains("week_sort_order") && !hasWeekOrder(database)) {
            orderBy.replace("week_sort_order", "sort_order")
        } else orderBy
        database.rawQuery(
            """
            SELECT t.id, t.title, t.task_mode, t.due_date, t.completed_at,
              (SELECT COUNT(*) FROM subtasks s
                WHERE s.task_id = t.id AND s.deleted_at IS NULL) AS total,
              (SELECT COALESCE(SUM(s.is_done), 0) FROM subtasks s
                WHERE s.task_id = t.id AND s.deleted_at IS NULL) AS done
            FROM tasks t
            WHERE $where
            ORDER BY $actualOrder
            """.trimIndent(),
            args,
        ).use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getLong(0)
                tasks += WidgetTask(
                    id = id,
                    title = cursor.getString(1),
                    mode = cursor.getString(2) ?: "normal",
                    dueDate = if (cursor.isNull(3)) null else cursor.getString(3),
                    completed = !cursor.isNull(4),
                    total = cursor.getInt(5),
                    done = cursor.getInt(6),
                    subTasks = if (expandedTaskId == id) rootSubTasks(database, id) else emptyList(),
                )
            }
        }
        tasks
    } ?: emptyList()

    private fun hasTaskColumn(database: SQLiteDatabase, column: String): Boolean =
        database.rawQuery("PRAGMA table_info(tasks)", null).use { cursor ->
            val nameColumn = cursor.getColumnIndex("name")
            while (cursor.moveToNext()) {
                if (cursor.getString(nameColumn) == column) return@use true
            }
            false
        }

    private fun hasWeekOrder(database: SQLiteDatabase): Boolean =
        hasTaskColumn(database, "week_sort_order")

    private fun scopeForKind(kind: String): String =
        if (kind == WidgetContract.KIND_WEEK) "week" else "stage"

    private fun rootSubTasks(database: SQLiteDatabase, taskId: Long): List<WidgetSubTask> {
        val result = mutableListOf<WidgetSubTask>()
        database.query(
            "subtasks",
            arrayOf("id", "title", "is_done"),
            "task_id = ? AND parent_id IS NULL AND deleted_at IS NULL",
            arrayOf(taskId.toString()),
            null,
            null,
            "sort_order ASC, id ASC",
        ).use { cursor ->
            while (cursor.moveToNext()) {
                result += WidgetSubTask(
                    id = cursor.getLong(0),
                    title = cursor.getString(1),
                    isDone = cursor.getInt(2) == 1,
                )
            }
        }
        return result
    }

    fun taskTitle(taskId: Long): String? = withDatabase { database ->
        database.query(
            "tasks",
            arrayOf("title"),
            "id = ?",
            arrayOf(taskId.toString()),
            null,
            null,
            null,
            "1",
        ).use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
    }

    fun insertTask(title: String, kind: String): Boolean = withDatabase { database ->
        val now = nowText()
        val values = ContentValues().apply {
            put("title", title.trim())
            put("note", "")
            put("category", "默认")
            put("created_at", now)
            putNull("completed_at")
            if (hasTaskColumn(database, "completed_scope")) putNull("completed_scope")
            putNull("deleted_at")
            if (hasTaskColumn(database, "deleted_scope")) putNull("deleted_scope")
            if (kind == WidgetContract.KIND_WEEK) {
                put("due_date", "${LocalDate.now()}T00:00:00.000")
                put("task_mode", "normal")
            } else {
                putNull("due_date")
                put("task_mode", "plan_now")
            }
            putNull("reminder_time")
            putNull("repeat_type")
            val order = nextSortOrder(database)
            put("sort_order", order)
            if (hasWeekOrder(database)) put("week_sort_order", order)
            put("effort_points", 2)
            putNull("companion_stashed_at")
            put("sync_id", UUID.randomUUID().toString())
            put("updated_at", now)
            put("revision", 1)
        }
        database.insertOrThrow("tasks", null, values)
        true
    } ?: false

    fun toggleTask(taskId: Long, kind: String): Boolean = withDatabase { database ->
        val now = nowText()
        val scopeAssignment = if (hasTaskColumn(database, "completed_scope")) {
            ", completed_scope = CASE WHEN completed_at IS NULL THEN ? ELSE NULL END"
        } else ""
        val args = if (scopeAssignment.isEmpty()) {
            arrayOf<Any?>(now, now, taskId)
        } else {
            arrayOf<Any?>(now, scopeForKind(kind), now, taskId)
        }
        database.execSQL(
            """
            UPDATE tasks
            SET completed_at = CASE WHEN completed_at IS NULL THEN ? ELSE NULL END,
                ${if (scopeAssignment.isEmpty()) "" else "completed_scope = CASE WHEN completed_at IS NULL THEN ? ELSE NULL END,"}
                updated_at = ?, revision = revision + 1
            WHERE id = ? AND deleted_at IS NULL
            """.trimIndent(),
            args,
        )
        true
    } ?: false

    fun toggleSubTask(subTaskId: Long, kind: String): Boolean = withDatabase { database ->
        database.beginTransaction()
        try {
            val taskId = database.rawQuery(
                "SELECT task_id FROM subtasks WHERE id = ? AND deleted_at IS NULL",
                arrayOf(subTaskId.toString()),
            ).use { cursor -> if (cursor.moveToFirst()) cursor.getLong(0) else null }
                ?: return@withDatabase false
            val now = nowText()
            database.execSQL(
                """
                UPDATE subtasks
                SET is_done = CASE is_done WHEN 1 THEN 0 ELSE 1 END,
                    updated_at = ?, revision = revision + 1
                WHERE id = ?
                """.trimIndent(),
                arrayOf<Any?>(now, subTaskId),
            )
            val progress = database.rawQuery(
                """
                SELECT COUNT(*), COALESCE(SUM(is_done), 0)
                FROM subtasks WHERE task_id = ? AND deleted_at IS NULL
                """.trimIndent(),
                arrayOf(taskId.toString()),
            ).use { cursor ->
                cursor.moveToFirst()
                cursor.getInt(0) to cursor.getInt(1)
            }
            val completedAt = if (progress.first > 0 && progress.first == progress.second) now else null
            if (hasTaskColumn(database, "completed_scope")) {
                database.execSQL(
                    "UPDATE tasks SET completed_at = ?, completed_scope = ?, updated_at = ?, revision = revision + 1 WHERE id = ?",
                    arrayOf<Any?>(completedAt, if (completedAt == null) null else scopeForKind(kind), now, taskId),
                )
            } else {
                database.execSQL(
                    "UPDATE tasks SET completed_at = ?, updated_at = ?, revision = revision + 1 WHERE id = ?",
                    arrayOf<Any?>(completedAt, now, taskId),
                )
            }
            database.setTransactionSuccessful()
            true
        } finally {
            database.endTransaction()
        }
    } ?: false

    fun renameTask(taskId: Long, title: String): Boolean = updateTask(
        taskId,
        "title = ?",
        arrayOf(title.trim()),
    )

    fun moveTask(taskId: Long, mode: String): Boolean = updateTask(
        taskId,
        "task_mode = ?",
        arrayOf(mode),
    )

    fun softDeleteTask(taskId: Long, kind: String): Boolean = withDatabase { database ->
        val now = nowText()
        if (hasTaskColumn(database, "deleted_scope")) {
            database.execSQL(
                "UPDATE tasks SET deleted_at = ?, deleted_scope = ?, updated_at = ?, revision = revision + 1 WHERE id = ?",
                arrayOf<Any?>(now, scopeForKind(kind), now, taskId),
            )
        } else {
            database.execSQL(
                "UPDATE tasks SET deleted_at = ?, updated_at = ?, revision = revision + 1 WHERE id = ?",
                arrayOf<Any?>(now, now, taskId),
            )
        }
        true
    } ?: false

    private fun updateTask(taskId: Long, assignment: String, args: Array<String>): Boolean =
        withDatabase { database ->
            val now = nowText()
            val values = args.toMutableList<Any?>().apply {
                add(now)
                add(taskId)
            }.toTypedArray()
            database.execSQL(
                "UPDATE tasks SET $assignment, updated_at = ?, revision = revision + 1 WHERE id = ?",
                values,
            )
            true
        } ?: false

    private fun nextSortOrder(database: SQLiteDatabase): Int = database.rawQuery(
        "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM tasks",
        null,
    ).use { cursor -> cursor.moveToFirst(); cursor.getInt(0) }

    private fun nowText(): String = LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME)
}

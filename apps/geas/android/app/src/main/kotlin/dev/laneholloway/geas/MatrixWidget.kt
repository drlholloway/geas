package dev.laneholloway.geas

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider as GlanceColor
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.actionStartActivity
import java.util.Calendar
import java.util.TimeZone
import org.json.JSONObject

/**
 * The Eisenhower matrix on the home screen: four quadrants with their open
 * tasks, drawn from the snapshot the app saves (lib/state/home_widget.dart).
 * Due-date colors and labels are worked out here, against today, so they
 * stay right on days the app isn't opened.
 *
 * A quadrant's title opens the Matrix, a task opens it in the app, and a
 * checkbox finishes it: the task disappears at once and the app's Dart code
 * finishes and syncs it in the background.
 */
class MatrixWidgetReceiver : HomeWidgetGlanceWidgetReceiver<MatrixWidget>() {
  override val glanceAppWidget = MatrixWidget()
}

class MatrixWidget : GlanceAppWidget() {
  override val stateDefinition = HomeWidgetGlanceStateDefinition()
  override val sizeMode = SizeMode.Exact

  override suspend fun provideGlance(context: Context, id: GlanceId) {
    provideContent {
      val prefs = currentState<HomeWidgetGlanceState>().preferences
      Content(context, Snapshot.read(prefs), Pending.read(prefs))
    }
  }
}

/** Finishes the task in [taskId]: hides it now, then asks Dart to do it. */
class CompleteTaskAction : ActionCallback {
  override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
    val id = parameters[taskId] ?: return
    Pending.add(HomeWidgetPlugin.getData(context), id)
    MatrixWidget().updateAll(context)
    HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("geas://done/$id")).send()
  }

  companion object {
    val taskId = ActionParameters.Key<String>("task")
  }
}

// The app's colors (its theme seeded with 0xFF2E6F6A), light and dark.
private fun color(day: Long, night: Long) = ColorProvider(Color(day), Color(night))

private val surface = color(0xFFF4FBF9, 0xFF0E1514)
private val box = color(0xFFE9EFED, 0xFF1A2120)
private val onSurface = color(0xFF161D1C, 0xFFDDE4E2)
private val muted = color(0xFF3F4947, 0xFFBEC9C7)
private val overdue = color(0xFFBA1A1A, 0xFFFFB4AB)
private val approaching = color(0xFFB56A00, 0xFFFFB74D)

private fun priorityColor(priority: String) = when (priority) {
  "high" -> color(0xFFD64545, 0xFFD64545)
  "medium" -> color(0xFFE0A030, 0xFFE0A030)
  "low" -> color(0xFF4A84D6, 0xFF4A84D6)
  else -> color(0xFF6F7977, 0xFF899391)
}

private data class WidgetTask(val id: String, val title: String, val day: Int?, val at: Long?)

private data class Quadrant(
  val title: String,
  val priority: String,
  val count: Int,
  val tasks: List<WidgetTask>,
)

private data class Snapshot(val warnDays: Int, val quadrants: List<Quadrant>) {
  companion object {
    /** The snapshot the app saved, or null before it has saved one. */
    fun read(prefs: SharedPreferences): Snapshot? {
      val text = prefs.getString("matrix", null) ?: return null
      return try {
        val json = JSONObject(text)
        val quadrants = json.getJSONArray("quadrants")
        Snapshot(
          json.optInt("warn_days", 2),
          (0 until quadrants.length()).map { i ->
            val q = quadrants.getJSONObject(i)
            val tasks = q.getJSONArray("tasks")
            Quadrant(
              q.getString("title"),
              q.getString("priority"),
              q.getInt("count"),
              (0 until tasks.length()).map { j ->
                val t = tasks.getJSONObject(j)
                WidgetTask(
                  t.getString("id"),
                  t.getString("title"),
                  if (t.has("day")) epochDay(t.getString("day")) else null,
                  if (t.has("at")) t.getLong("at") else null,
                )
              },
            )
          },
        )
      } catch (e: Exception) {
        null
      }
    }
  }
}

/**
 * Tasks ticked off here that the app hasn't finished yet, kept hidden. An
 * entry lapses after a couple of minutes, in case finishing it failed.
 */
private object Pending {
  private const val KEY = "pending_done"
  private const val LAPSE_MS = 2 * 60 * 1000L

  fun read(prefs: SharedPreferences): Set<String> {
    val json = JSONObject(prefs.getString(KEY, null) ?: "{}")
    val now = System.currentTimeMillis()
    return json.keys().asSequence().filter { now - json.getLong(it) < LAPSE_MS }.toSet()
  }

  fun add(prefs: SharedPreferences, id: String) {
    val json = JSONObject(prefs.getString(KEY, null) ?: "{}")
    val now = System.currentTimeMillis()
    for (key in json.keys().asSequence().toList()) {
      if (now - json.getLong(key) >= LAPSE_MS) json.remove(key)
    }
    json.put(id, now)
    prefs.edit().putString(KEY, json.toString()).apply()
  }
}

// Dates as days since 1970-01-01, without java.time (API 26+).

/** "2026-11-08" as an epoch day. */
private fun epochDay(text: String): Int {
  val (y, m, d) = text.split("-").map { it.toInt() }
  return epochDay(y, m, d)
}

/** Howard Hinnant's days_from_civil. */
private fun epochDay(year: Int, month: Int, day: Int): Int {
  val y = if (month <= 2) year - 1 else year
  val era = (if (y >= 0) y else y - 399) / 400
  val yoe = y - era * 400
  val mp = (month + 9) % 12
  val doy = (153 * mp + 2) / 5 + day - 1
  val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  return era * 146097 + doe - 719468
}

private fun epochDay(calendar: Calendar) = epochDay(
  calendar.get(Calendar.YEAR),
  calendar.get(Calendar.MONTH) + 1,
  calendar.get(Calendar.DAY_OF_MONTH),
)

private val months =
  listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
private val weekdays = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")

/** As the app's dueLabel: Today, Tomorrow, a weekday, or a date; plus the time. */
private fun dueLabel(task: WidgetTask, today: Int, now: Calendar): String {
  val day = task.day ?: return ""
  val label = when (val ahead = day - today) {
    0 -> "Today"
    1 -> "Tomorrow"
    -1 -> "Yesterday"
    in 2..6 -> weekdays[Math.floorMod(day + 3, 7)] // 1970-01-01 was a Thursday
    else -> {
      // Midnight UTC of that day, read in UTC, has that date's fields.
      val date = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
      date.timeInMillis = day * 86_400_000L
      val text = "${months[date.get(Calendar.MONTH)]} ${date.get(Calendar.DAY_OF_MONTH)}"
      if (date.get(Calendar.YEAR) == now.get(Calendar.YEAR)) text
      else "$text, ${date.get(Calendar.YEAR)}"
    }
  }
  val at = task.at ?: return label
  val time = Calendar.getInstance().apply { timeInMillis = at }
  return "%s %02d:%02d".format(label, time.get(Calendar.HOUR_OF_DAY), time.get(Calendar.MINUTE))
}

private enum class Warning { NONE, APPROACHING, OVERDUE }

/** As the app's dueWarning, for an open task. */
private fun warning(task: WidgetTask, today: Int, nowMs: Long, warnDays: Int): Warning {
  val day = task.day ?: return Warning.NONE
  val late = if (task.at != null) task.at < nowMs else day < today
  return when {
    late -> Warning.OVERDUE
    day <= today + warnDays -> Warning.APPROACHING
    else -> Warning.NONE
  }
}

@Composable
private fun Content(context: Context, snapshot: Snapshot?, pending: Set<String>) {
  val openMatrix = actionStartActivity<MainActivity>(context, Uri.parse("geas://matrix"))
  val frame = GlanceModifier.fillMaxSize()
    .appWidgetBackground()
    .background(surface)
    .cornerRadius(20.dp)
    .padding(6.dp)
  if (snapshot == null || snapshot.quadrants.size != 4) {
    Box(frame.clickable(openMatrix), contentAlignment = Alignment.Center) {
      Text(
        "Open Geas to fill in the matrix.",
        style = TextStyle(color = muted, fontSize = 14.sp),
      )
    }
    return
  }
  val now = Calendar.getInstance()
  val today = epochDay(now)
  Column(frame) {
    for (row in 0..1) {
      if (row == 1) Spacer(GlanceModifier.height(6.dp))
      Row(GlanceModifier.fillMaxWidth().defaultWeight()) {
        for (col in 0..1) {
          if (col == 1) Spacer(GlanceModifier.width(6.dp))
          QuadrantBox(
            context,
            snapshot.quadrants[row * 2 + col],
            pending,
            today,
            now,
            snapshot.warnDays,
            GlanceModifier.defaultWeight().fillMaxHeight(),
          )
        }
      }
    }
  }
}

@Composable
private fun QuadrantBox(
  context: Context,
  quadrant: Quadrant,
  pending: Set<String>,
  today: Int,
  now: Calendar,
  warnDays: Int,
  modifier: GlanceModifier,
) {
  val tint = priorityColor(quadrant.priority)
  val tasks = quadrant.tasks.filter { it.id !in pending }
  val count = quadrant.count - (quadrant.tasks.size - tasks.size)
  Column(modifier.background(box).cornerRadius(14.dp).padding(start = 8.dp, top = 6.dp, end = 4.dp)) {
    Row(
      GlanceModifier.fillMaxWidth()
        .padding(bottom = 2.dp)
        .clickable(actionStartActivity<MainActivity>(context, Uri.parse("geas://matrix"))),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Image(
        ImageProvider(R.drawable.widget_flag),
        contentDescription = null,
        modifier = GlanceModifier.size(14.dp),
        colorFilter = ColorFilter.tint(tint),
      )
      Spacer(GlanceModifier.width(4.dp))
      Text(
        quadrant.title,
        maxLines = 1,
        modifier = GlanceModifier.defaultWeight(),
        style = TextStyle(color = tint, fontSize = 14.sp, fontWeight = FontWeight.Bold),
      )
      Text(
        "$count",
        modifier = GlanceModifier.padding(end = 4.dp),
        style = TextStyle(color = muted, fontSize = 12.sp),
      )
    }
    if (tasks.isEmpty()) {
      Box(GlanceModifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text("Nothing here.", style = TextStyle(color = muted, fontSize = 12.sp))
      }
    } else {
      LazyColumn(GlanceModifier.fillMaxSize()) {
        items(tasks, itemId = { it.id.hashCode().toLong() }) { task ->
          TaskRow(context, task, tint, warning(task, today, now.timeInMillis, warnDays), dueLabel(task, today, now))
        }
      }
    }
  }
}

@Composable
private fun TaskRow(
  context: Context,
  task: WidgetTask,
  tint: GlanceColor,
  warning: Warning,
  due: String,
) {
  val titleColor = when (warning) {
    Warning.OVERDUE -> overdue
    Warning.APPROACHING -> approaching
    Warning.NONE -> onSurface
  }
  Row(GlanceModifier.fillMaxWidth().padding(vertical = 2.dp)) {
    Box(
      GlanceModifier.size(32.dp).clickable(
        actionRunCallback<CompleteTaskAction>(
          actionParametersOf(CompleteTaskAction.taskId to task.id),
        ),
      ),
      contentAlignment = Alignment.Center,
    ) {
      Image(
        ImageProvider(R.drawable.widget_check_box),
        contentDescription = "Done: ${task.title}",
        modifier = GlanceModifier.size(20.dp),
        colorFilter = ColorFilter.tint(tint),
      )
    }
    Column(
      GlanceModifier.defaultWeight()
        .padding(start = 2.dp, top = 6.dp, end = 4.dp)
        .clickable(
          actionStartActivity<MainActivity>(context, Uri.parse("geas://task/${Uri.encode(task.id)}")),
        ),
    ) {
      Text(
        task.title,
        maxLines = 2,
        style = TextStyle(
          color = titleColor,
          fontSize = 13.sp,
          fontWeight = if (warning == Warning.APPROACHING) FontWeight.Bold else FontWeight.Normal,
        ),
      )
      if (due.isNotEmpty()) {
        Text(
          due,
          maxLines = 1,
          style = TextStyle(
            color = if (warning == Warning.NONE) muted else titleColor,
            fontSize = 11.sp,
          ),
        )
      }
    }
  }
}

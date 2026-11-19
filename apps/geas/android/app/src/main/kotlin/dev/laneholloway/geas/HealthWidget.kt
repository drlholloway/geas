package dev.laneholloway.geas

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
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
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.actionStartActivity
import java.util.Calendar
import org.json.JSONObject

/**
 * Health on the home screen: each medication and sensor with when it was
 * last logged and when it's next due, drawn from the snapshot the app saves
 * (lib/state/home_widget.dart). Times are shown by the clock ("Today
 * 08:05"), and whether one is overdue is worked out here, against now, so
 * both stay right while the app is closed.
 *
 * A row's button logs it now: the row says so at once, and the app's Dart
 * code logs and syncs it in the background. For a couple of minutes after,
 * the button reads Undo and takes that log back, in case the tap was a
 * slip. The title, or a row, opens Health in the app.
 */
class HealthWidgetReceiver : HomeWidgetGlanceWidgetReceiver<HealthWidget>() {
  override val glanceAppWidget = HealthWidget()
}

class HealthWidget : GlanceAppWidget() {
  override val stateDefinition = HomeWidgetGlanceStateDefinition()
  override val sizeMode = SizeMode.Exact

  override suspend fun provideGlance(context: Context, id: GlanceId) {
    provideContent {
      val prefs = currentState<HomeWidgetGlanceState>().preferences
      HealthContent(context, readTrackers(prefs), PendingLogs.read(prefs))
    }
  }
}

/** Logs the tracker in [trackerId] now: shows it, then asks Dart to do it. */
class LogTrackerAction : ActionCallback {
  override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
    val id = parameters[trackerId] ?: return
    PendingLogs.add(HomeWidgetPlugin.getData(context), id)
    HealthWidget().updateAll(context)
    HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("geas://log/${Uri.encode(id)}")).send()
  }

  companion object {
    val trackerId = ActionParameters.Key<String>("tracker")
  }
}

/**
 * Takes back the log of the tracker in [trackerId] made here a moment ago.
 * If that moment has passed, as when an old drawing of the widget still
 * shows Undo, it only redraws, so the button reads Take again.
 */
class UndoLogAction : ActionCallback {
  override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
    val id = parameters[LogTrackerAction.trackerId] ?: return
    val prefs = HomeWidgetPlugin.getData(context)
    val recent = id in PendingLogs.read(prefs)
    PendingLogs.remove(prefs, id)
    HealthWidget().updateAll(context)
    if (recent) {
      HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("geas://unlog/${Uri.encode(id)}")).send()
    }
  }
}

// The app's colors (its theme seeded with 0xFF2E6F6A), light and dark.
private fun color(day: Long, night: Long) = ColorProvider(Color(day), Color(night))

private val surface = color(0xFFF4FBF9, 0xFF0E1514)
private val box = color(0xFFE9EFED, 0xFF1A2120)
private val onSurface = color(0xFF161D1C, 0xFFDDE4E2)
private val muted = color(0xFF3F4947, 0xFFBEC9C7)
private val primary = color(0xFF006A65, 0xFF80D5CE)
private val button = color(0xFFCCE8E4, 0xFF324B48)
private val onButton = color(0xFF051F1D, 0xFFCCE8E4)
private val late = color(0xFFB56A00, 0xFFFFB74D)

private data class WidgetTracker(
  val id: String,
  val name: String,
  /** "Take" and "Taken", or "Replace" and "Replaced". */
  val action: String,
  val done: String,
  /** When it was last logged and is next due, in epoch milliseconds. */
  val last: Long?,
  val due: Long?,
)

/** The trackers the app saved, or null before it has saved any. */
private fun readTrackers(prefs: SharedPreferences): List<WidgetTracker>? {
  val text = prefs.getString("health", null) ?: return null
  return try {
    val trackers = JSONObject(text).getJSONArray("trackers")
    (0 until trackers.length()).map { i ->
      val t = trackers.getJSONObject(i)
      WidgetTracker(
        t.getString("id"),
        t.getString("name"),
        t.getString("action"),
        t.getString("done"),
        if (t.has("last")) t.getLong("last") else null,
        if (t.has("due")) t.getLong("due") else null,
      )
    }
  } catch (e: Exception) {
    null
  }
}

/**
 * Trackers logged here that the app hasn't caught up with yet, with when.
 * An entry lapses after a couple of minutes: by then the app's snapshot has
 * it, or logging it failed.
 */
private object PendingLogs {
  private const val KEY = "pending_log"
  private const val LAPSE_MS = 2 * 60 * 1000L

  fun read(prefs: SharedPreferences): Map<String, Long> {
    val json = JSONObject(prefs.getString(KEY, null) ?: "{}")
    val now = System.currentTimeMillis()
    return json.keys().asSequence()
      .filter { now - json.getLong(it) < LAPSE_MS }
      .associateWith { json.getLong(it) }
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

  fun remove(prefs: SharedPreferences, id: String) {
    val json = JSONObject(prefs.getString(KEY, null) ?: "{}")
    json.remove(id)
    prefs.edit().putString(KEY, json.toString()).apply()
  }
}

private val weekdays = listOf("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")

private val months =
  listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")

/**
 * "Today 20:05", "Yesterday 09:05", "Sat 09:05" within a week either way,
 * else "Nov 8 09:05". A clock time, not "3 h ago", so it can't go stale
 * between redraws.
 */
private fun whenLabel(at: Long, now: Calendar): String {
  val time = Calendar.getInstance().apply { timeInMillis = at }
  fun day(c: Calendar): Long {
    val midnight = (c.clone() as Calendar).apply {
      set(Calendar.HOUR_OF_DAY, 12)
      set(Calendar.MINUTE, 0)
      set(Calendar.SECOND, 0)
      set(Calendar.MILLISECOND, 0)
    }
    // Noon to noon, so a daylight-saving hour doesn't shift the count.
    return Math.round(midnight.timeInMillis / 86_400_000.0)
  }
  val label = when (val ahead = (day(time) - day(now)).toInt()) {
    0 -> "Today"
    1 -> "Tomorrow"
    -1 -> "Yesterday"
    in -6..6 -> weekdays[time.get(Calendar.DAY_OF_WEEK) - 1]
    else -> "${months[time.get(Calendar.MONTH)]} ${time.get(Calendar.DAY_OF_MONTH)}"
  }
  return "%s %02d:%02d".format(label, time.get(Calendar.HOUR_OF_DAY), time.get(Calendar.MINUTE))
}

@Composable
private fun HealthContent(
  context: Context,
  trackers: List<WidgetTracker>?,
  pending: Map<String, Long>,
) {
  val openHealth = actionStartActivity<MainActivity>(context, Uri.parse("geas://health"))
  val frame = GlanceModifier.fillMaxSize()
    .appWidgetBackground()
    .background(surface)
    .cornerRadius(20.dp)
    .padding(8.dp)
  if (trackers.isNullOrEmpty()) {
    Box(frame.clickable(openHealth), contentAlignment = Alignment.Center) {
      Text(
        if (trackers == null) "Open Geas to fill in Health."
        else "Nothing tracked yet. Add a medication or sensor in Geas.",
        style = TextStyle(color = muted, fontSize = 14.sp),
      )
    }
    return
  }
  val now = Calendar.getInstance()
  Column(frame) {
    Text(
      "Health",
      modifier = GlanceModifier.fillMaxWidth().padding(start = 6.dp, bottom = 4.dp).clickable(openHealth),
      style = TextStyle(color = primary, fontSize = 14.sp, fontWeight = FontWeight.Bold),
    )
    LazyColumn(GlanceModifier.fillMaxSize()) {
      items(trackers, itemId = { it.id.hashCode().toLong() }) { tracker ->
        Column {
          TrackerRow(context, tracker, pending[tracker.id], now)
          Spacer(GlanceModifier.height(6.dp))
        }
      }
    }
  }
}

@Composable
private fun TrackerRow(context: Context, tracker: WidgetTracker, pendingAt: Long?, now: Calendar) {
  val nowMs = now.timeInMillis
  // Logged here a moment ago, and the app's snapshot doesn't show it yet.
  // The app keeps times to the second, so compare whole seconds.
  val justLogged = pendingAt != null &&
    (tracker.last == null || tracker.last / 1000 < pendingAt / 1000)
  val last = if (justLogged) pendingAt else tracker.last
  val lastLine =
    if (last == null) "Nothing logged yet" else "${tracker.done} ${whenLabel(last, now)}"
  // The due time the app worked out is for the log before this one.
  val due = if (justLogged) null else tracker.due
  val overdue = due != null && due < nowMs
  Row(
    GlanceModifier.fillMaxWidth().background(box).cornerRadius(14.dp).padding(start = 10.dp, top = 6.dp, end = 6.dp, bottom = 6.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Column(
      GlanceModifier.defaultWeight().clickable(
        actionStartActivity<MainActivity>(context, Uri.parse("geas://health")),
      ),
    ) {
      Text(
        tracker.name,
        maxLines = 1,
        style = TextStyle(color = onSurface, fontSize = 14.sp, fontWeight = FontWeight.Medium),
      )
      Text(lastLine, maxLines = 1, style = TextStyle(color = muted, fontSize = 12.sp))
      if (due != null) {
        Text(
          (if (overdue) "Due since " else "Next due ") + whenLabel(due, now),
          maxLines = 1,
          style = TextStyle(
            color = if (overdue) late else muted,
            fontSize = 12.sp,
            fontWeight = if (overdue) FontWeight.Bold else FontWeight.Normal,
          ),
        )
      }
    }
    Spacer(GlanceModifier.width(6.dp))
    Box(
      GlanceModifier.background(button).cornerRadius(16.dp)
        .padding(horizontal = 14.dp, vertical = 8.dp)
        .clickable(
          // Logged from here in the last couple of minutes: offer to take
          // it back instead of logging it twice.
          if (pendingAt != null) {
            actionRunCallback<UndoLogAction>(
              actionParametersOf(LogTrackerAction.trackerId to tracker.id),
            )
          } else {
            actionRunCallback<LogTrackerAction>(
              actionParametersOf(LogTrackerAction.trackerId to tracker.id),
            )
          },
        ),
      contentAlignment = Alignment.Center,
    ) {
      Text(
        if (pendingAt != null) "Undo" else tracker.action,
        style = TextStyle(color = onButton, fontSize = 13.sp, fontWeight = FontWeight.Medium),
      )
    }
  }
}

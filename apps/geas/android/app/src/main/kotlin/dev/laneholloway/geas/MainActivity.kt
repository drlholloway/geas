package dev.laneholloway.geas

import android.content.Intent
import android.os.Bundle
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    // Recreated after Android reclaimed the app, or opened from recents:
    // the widget link that first launched it was followed then, so don't
    // open that task again.
    val replayed = savedInstanceState != null ||
      intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0
    if (replayed && intent.action == HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION) {
      intent = Intent(intent).setAction(Intent.ACTION_MAIN).setData(null)
    }
    super.onCreate(savedInstanceState)
  }
}

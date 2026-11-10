# Glance creates the home-screen widget's actions (MatrixWidget.kt) by
# reflection, so R8 must keep their no-argument constructors.
-keep class * implements androidx.glance.appwidget.action.ActionCallback {
    <init>();
}

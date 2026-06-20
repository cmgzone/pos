# Keep Flutter's generated Android plugin bootstrap available for the engine.
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Keep plugin implementations intact when they are discovered through Flutter or
# Android framework entry points instead of direct Java/Kotlin references.
-keep class * implements io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keep class * implements io.flutter.plugin.common.PluginRegistry$PluginRegistrantCallback { *; }

# MainActivity hosts the app's custom MethodChannel for device notifications.
-keep class com.example.pos_app.MainActivity { *; }

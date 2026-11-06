# FreeScanner R8 rules (release builds).
#
# STATUS: minification is currently DISABLED — see `shrink=false` in
# android/gradle.properties and `isMinifyEnabled = false` in
# android/app/build.gradle.kts. Flutter >= 3.47 shrinks release builds by
# default and the shrunk build crashed at launch (R8 incorrectly stripping
# plugin classes — flutter/flutter#154580). The rules below only take effect
# when shrinking is deliberately re-enabled; keep them in sync with the
# plugin set in pubspec.yaml and test a release install before shipping.

# 1) google_mlkit_text_recognition references the optional script recognizers
#    (chinese / devanagari / japanese / korean) that this app intentionally
#    does NOT bundle — only the Latin recognizer (and Tesseract for Bengali)
#    is used. Tell R8 they are expected to be absent.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# 2) tesseract4android (bundled AAR) talks to native code through JNI —
#    keep the Java <-> C++ bridge intact, including every native method name.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}
-keep class com.googlecode.tesseract.** { *; }
-keep class com.googlecode.leptonica.** { *; }
-keep class cz.adaptech.tesseract4android.** { *; }
-dontwarn com.googlecode.**
-dontwarn cz.adaptech.**

# 3) Vendored flutter_tesseract_ocr plugin (no consumer rules of its own).
-keep class io.paratoner.flutter_tesseract_ocr.** { *; }

# 4) Flutter plugin registration. R8 has incorrectly stripped plugin classes
#    in the past (flutter/flutter#154580) — belt-and-braces on top of the
#    SDK's own rule (which still allows shrinking).
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-if class * implements io.flutter.embedding.engine.plugins.FlutterPlugin
-keep class <1>
-keep class io.flutter.embedding.engine.** { *; }
-dontwarn io.flutter.plugin.**

# 5) Google Mobile Ads / Google Sign-In / ML Kit — their AARs ship consumer
#    rules, these are belt-and-braces so a stripped consumer file can never
#    break the release build again.
-keep class io.flutter.plugins.googlemobileads.** { *; }
-keep class com.google.android.gms.ads.** { *; }
-keep class io.flutter.plugins.google_sign_in.** { *; }
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.android.gms.**


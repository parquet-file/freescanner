# FreeScanner R8 rules (release builds).
#
# 1) google_mlkit_text_recognition references the optional script recognizers
#    (chinese / devanagari / japanese / korean) that this app intentionally
#    does NOT bundle — only the Latin recognizer (and Tesseract for Bengali)
#    is used. Tell R8 they are expected to be absent.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# 2) tesseract4android (bundled AAR) talks to native code through JNI —
#    keep the Java ↔ C++ bridge intact.
-keep class com.googlecode.tesseract.** { *; }
-keep class com.googlecode.leptonica.** { *; }
-keep class cz.adaptech.tesseract4android.** { *; }
-dontwarn com.googlecode.**
-dontwarn cz.adaptech.**

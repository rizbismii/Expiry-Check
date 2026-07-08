# The google_mlkit_text_recognition plugin references all script recognizers,
# but this app only bundles the Latin model. Silence R8 about the others.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

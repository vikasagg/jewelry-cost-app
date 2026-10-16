# ML Kit text recognition: only the Latin model is bundled. The plugin
# references the other script recognisers as compileOnly, so tell R8 they
# may be absent.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

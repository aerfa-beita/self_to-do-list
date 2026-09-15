# ── flutter_local_notifications R8 规则 ──
# v18 及以下依赖 Gson 泛型签名（TypeToken），R8 混淆会删掉它，
# 导致 release 包 zonedSchedule 抛 "Missing type parameter"（v19+ 已内置，无需此文件）。
# 规则来源：插件官方 example/android/app/proguard-rules.pro

# Gson 靠类文件中的泛型签名工作，R8 默认会移除，需保留
-keepattributes Signature

# 保留 Gson @Expose / @SerializedName 注解
-keepattributes *Annotation*

# 保留 TypeToken 与子类的泛型签名（R8 3.0+ 需要）
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# TypeAdapter / 工厂 / 序列化器接口信息不可剥离（供 @JsonAdapter 使用）
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# 保留 @SerializedName 字段，防止数据成员被置空
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# 若报 Attribute Signature requires InnerClasses，需要保留 InnerClasses 属性
-keepattributes InnerClasses

-dontwarn sun.misc.**

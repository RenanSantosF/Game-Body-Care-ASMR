@tool
extends EditorPlugin
## Inclui o plugin Android (plugin_src -> bin/gg_native-release.aar) na exportação com Gradle.

const ADMOB_APP_ID := "ca-app-pub-4311255826061303~6572763650"

var _export: GGNativeExport

func _enter_tree() -> void:
	_export = GGNativeExport.new()
	add_export_plugin(_export)

func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null

class GGNativeExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "GGNative"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["gg_native/bin/gg_native-release.aar"])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray([
			"com.google.android.gms:play-services-ads:23.6.0",
			"com.google.android.ump:user-messaging-platform:3.1.0",
			"androidx.core:core:1.13.1",
		])

	func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return '<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="%s"/>' % ADMOB_APP_ID

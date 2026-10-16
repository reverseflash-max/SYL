package com.example.syl_mobile

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "syl/instagram").setMethodCallHandler { call, result ->
            if (call.method != "shareToStory") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            if (path == null) {
                result.error("no_path", "No picture to share", null)
                return@setMethodCallHandler
            }
            try {
                result.success(shareToStory(File(path)))
            } catch (e: Exception) {
                result.error("failed", e.message, null)
            }
        }
    }

    /**
     * Opens Instagram's Story editor with [file] already in it. Returns true,
     * or false when Instagram isn't installed (or can't take it).
     */
    private fun shareToStory(file: File): Boolean {
        val uri = FileProvider.getUriForFile(this, "$packageName.syl_share", file)
        grantUriPermission(INSTAGRAM, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        val tries = listOf(
            // What Android's own share menu uses for Instagram's "Stories" target.
            Intent(Intent.ACTION_SEND).apply {
                setClassName(INSTAGRAM, "com.instagram.share.handleractivity.StoryShareHandlerActivity")
                type = "image/png"
                putExtra(Intent.EXTRA_STREAM, uri)
            },
            // Instagram's published "add to story" intent.
            Intent("com.instagram.share.ADD_TO_STORY").apply {
                setPackage(INSTAGRAM)
                setDataAndType(uri, "image/png")
                putExtra("source_application", packageName)
            },
        )
        for (intent in tries) {
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            if (intent.resolveActivity(packageManager) == null) continue
            try {
                startActivity(intent)
                return true
            } catch (e: Exception) {
                // Instagram changed or closed this way in; try the next.
            }
        }
        return false
    }

    private companion object {
        const val INSTAGRAM = "com.instagram.android"
    }
}

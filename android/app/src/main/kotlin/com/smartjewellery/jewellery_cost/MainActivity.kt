package com.smartjewellery.jewellery_cost

import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "damiyaas/whatsapp")
            .setMethodCallHandler { call, result ->
                if (call.method != "sendFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                sendFile(
                    call.argument<ByteArray>("bytes")!!,
                    call.argument<String>("name")!!,
                    call.argument<String>("phone")!!,
                    call.argument<String>("text"),
                    result,
                )
            }
    }

    /**
     * Opens the WhatsApp chat for [phone] (digits with country code) with
     * the file attached. Answers "done" once the user comes back to the
     * app, or "notInstalled" when neither WhatsApp nor WhatsApp Business
     * is on the phone.
     */
    private fun sendFile(
        bytes: ByteArray,
        name: String,
        phone: String,
        text: String?,
        result: MethodChannel.Result,
    ) {
        val dir = File(cacheDir, "bills").apply { mkdirs() }
        val file = File(dir, name).apply { writeBytes(bytes) }
        val uri = FileProvider.getUriForFile(this, "$packageName.bills", file)
        pending?.success("done")
        pending = null
        for (pkg in listOf("com.whatsapp", "com.whatsapp.w4b")) {
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "application/pdf"
                setPackage(pkg)
                putExtra(Intent.EXTRA_STREAM, uri)
                if (text != null) putExtra(Intent.EXTRA_TEXT, text)
                putExtra("jid", "$phone@s.whatsapp.net")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            try {
                pending = result
                startActivityForResult(intent, SEND_REQUEST)
                return
            } catch (e: ActivityNotFoundException) {
                pending = null
            }
        }
        result.success("notInstalled")
    }

    @Deprecated("Needed for the WhatsApp round trip")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SEND_REQUEST) {
            pending?.success("done")
            pending = null
        }
    }

    private companion object {
        const val SEND_REQUEST = 4721
    }
}

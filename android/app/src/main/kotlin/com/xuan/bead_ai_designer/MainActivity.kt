package com.xuan.bead_ai_designer

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private var backupResult: MethodChannel.Result? = null
    private val backupRequestCode = 2607
    private var documentSaveResult: MethodChannel.Result? = null
    private var documentSaveBytes: ByteArray? = null
    private val documentSaveRequestCode = 2608

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.xuan.bead_ai_designer/media"
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "saveImage" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                            ?: throw IllegalArgumentException("图片数据为空")
                        val requestedName = call.argument<String>("name") ?: "bead_grid.png"
                        val safeName = requestedName.replace(Regex("[\\\\/:*?\"<>|]"), "_")
                        result.success(saveImage(bytes, safeName))
                    }
                    "saveDocument" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                            ?: throw IllegalArgumentException("文件数据为空")
                        val requestedName = call.argument<String>("name") ?: "AI生成文件.txt"
                        val safeName = requestedName.replace(Regex("[\\\\/:*?\"<>|]"), "_")
                        val mimeType = call.argument<String>("mimeType") ?: documentMimeType(safeName)
                        result.success(saveDocument(bytes, safeName, mimeType))
                    }
                    "saveDocumentAs" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                            ?: throw IllegalArgumentException("文件数据为空")
                        val requestedName = call.argument<String>("name") ?: "AI生成文件.txt"
                        val safeName = requestedName.replace(Regex("[\\\\/:*?\"<>|]"), "_")
                        val mimeType = call.argument<String>("mimeType") ?: documentMimeType(safeName)
                        openDocumentSavePicker(result, bytes, safeName, mimeType)
                    }
                    "pickBackup" -> openBackupPicker(result)
                    "readBundledOriginal" -> {
                        val path = call.argument<String>("path")
                            ?: throw IllegalArgumentException("原图路径为空")
                        result.success(readBundledOriginal(path))
                    }
                    "openExternalUrl" -> {
                        val value = call.argument<String>("url")
                            ?: throw IllegalArgumentException("链接为空")
                        result.success(openExternalUrl(value))
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("SAVE_FAILED", error.message, null)
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.xuan.bead_ai_designer/secure_settings"
        ).setMethodCallHandler { call, result ->
            try {
                if (call.method == "clearAll") {
                    securePreferences().edit().clear().commit()
                    result.success(null)
                    return@setMethodCallHandler
                }
                val key = call.argument<String>("key")
                    ?: throw IllegalArgumentException("安全设置键为空")
                when (call.method) {
                    "read" -> result.success(readSecureSetting(key))
                    "write" -> {
                        val value = call.argument<String>("value")
                            ?: throw IllegalArgumentException("安全设置值为空")
                        writeSecureSetting(key, value)
                        result.success(null)
                    }
                    "delete" -> {
                        securePreferences().edit().remove(key).apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("SECURE_SETTINGS_FAILED", error.message, null)
            }
        }
    }

    private fun securePreferences() = getSharedPreferences("secure_settings", MODE_PRIVATE)

    private fun secureKey(): SecretKey {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            throw IllegalStateException("Android 6.0 以下系统不支持安全密钥存储")
        }
        val alias = "bead_ai_secure_settings_v1"
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(alias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore"
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build()
        )
        return generator.generateKey()
    }

    private fun writeSecureSetting(key: String, value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secureKey())
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val payload = ByteArray(1 + cipher.iv.size + encrypted.size)
        payload[0] = cipher.iv.size.toByte()
        cipher.iv.copyInto(payload, 1)
        encrypted.copyInto(payload, 1 + cipher.iv.size)
        securePreferences().edit()
            .putString(key, Base64.encodeToString(payload, Base64.NO_WRAP))
            .apply()
    }

    private fun readSecureSetting(key: String): String? {
        val encoded = securePreferences().getString(key, null) ?: return null
        return try {
            val payload = Base64.decode(encoded, Base64.NO_WRAP)
            val ivLength = payload[0].toInt() and 0xFF
            if (ivLength <= 0 || payload.size <= 1 + ivLength) return null
            val iv = payload.copyOfRange(1, 1 + ivLength)
            val encrypted = payload.copyOfRange(1 + ivLength, payload.size)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, secureKey(), GCMParameterSpec(128, iv))
            String(cipher.doFinal(encrypted), Charsets.UTF_8)
        } catch (error: Exception) {
            securePreferences().edit().remove(key).apply()
            null
        }
    }

    private fun openBackupPicker(result: MethodChannel.Result) {
        if (backupResult != null) {
            result.error("PICK_IN_PROGRESS", "已有文件选择窗口正在打开", null)
            return
        }
        backupResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/octet-stream", "application/gzip", "*/*"))
        }
        startActivityForResult(intent, backupRequestCode)
    }

    private fun openDocumentSavePicker(
        result: MethodChannel.Result,
        bytes: ByteArray,
        name: String,
        mimeType: String
    ) {
        if (documentSaveResult != null) {
            result.error("SAVE_IN_PROGRESS", "已有保存位置选择窗口正在打开", null)
            return
        }
        documentSaveResult = result
        documentSaveBytes = bytes
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, name)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, documentSaveRequestCode)
        } catch (error: Exception) {
            documentSaveResult = null
            documentSaveBytes = null
            throw error
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == backupRequestCode) {
            val pending = backupResult ?: return
            backupResult = null
            if (resultCode != RESULT_OK || data?.data == null) {
                pending.success(null)
                return
            }
            try {
                val bytes = contentResolver.openInputStream(data.data!!)?.use { it.readBytes() }
                    ?: throw IllegalStateException("无法读取备份文件")
                pending.success(bytes)
            } catch (error: Exception) {
                pending.error("IMPORT_FAILED", error.message, null)
            }
            return
        }
        if (requestCode == documentSaveRequestCode) {
            val pending = documentSaveResult ?: return
            val bytes = documentSaveBytes
            documentSaveResult = null
            documentSaveBytes = null
            if (resultCode != RESULT_OK || data?.data == null) {
                pending.success(null)
                return
            }
            try {
                val uri = data.data!!
                contentResolver.openOutputStream(uri, "w")?.use { stream ->
                    stream.write(bytes ?: throw IllegalStateException("待保存文件数据已丢失"))
                    stream.flush()
                } ?: throw IllegalStateException("无法写入所选文件")
                pending.success(uri.toString())
            } catch (error: Exception) {
                pending.error("SAVE_FAILED", error.message, null)
            }
        }
    }

    private fun saveImage(bytes: ByteArray, name: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, name)
                put(
                    MediaStore.Images.Media.MIME_TYPE,
                    imageMimeType(name)
                )
                put(
                    MediaStore.Images.Media.RELATIVE_PATH,
                    Environment.DIRECTORY_PICTURES + "/拼豆AI"
                )
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("无法创建相册文件")
            try {
                resolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("无法写入相册文件")
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                return uri.toString()
            } catch (error: Exception) {
                resolver.delete(uri, null, null)
                throw error
            }
        }

        val pictures = getExternalFilesDir(Environment.DIRECTORY_PICTURES)
            ?: throw IllegalStateException("本机存储不可用")
        val directory = File(pictures, "拼豆AI").apply { mkdirs() }
        return File(directory, name).apply { writeBytes(bytes) }.absolutePath
    }

    private fun imageMimeType(name: String): String = when {
        name.endsWith(".jpg", ignoreCase = true) || name.endsWith(".jpeg", ignoreCase = true) -> "image/jpeg"
        name.endsWith(".webp", ignoreCase = true) -> "image/webp"
        name.endsWith(".gif", ignoreCase = true) -> "image/gif"
        name.endsWith(".bmp", ignoreCase = true) -> "image/bmp"
        name.endsWith(".tif", ignoreCase = true) || name.endsWith(".tiff", ignoreCase = true) -> "image/tiff"
        name.endsWith(".heic", ignoreCase = true) || name.endsWith(".heif", ignoreCase = true) -> "image/heic"
        name.endsWith(".avif", ignoreCase = true) -> "image/avif"
        else -> "image/png"
    }

    private fun saveDocument(bytes: ByteArray, name: String, mimeType: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(
                    MediaStore.Downloads.RELATIVE_PATH,
                    Environment.DIRECTORY_DOWNLOADS + "/拼豆AI"
                )
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("无法创建下载文件")
            try {
                resolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("无法写入下载文件")
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                return uri.toString()
            } catch (error: Exception) {
                resolver.delete(uri, null, null)
                throw error
            }
        }

        val downloads = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: throw IllegalStateException("本机存储不可用")
        val directory = File(downloads, "拼豆AI").apply { mkdirs() }
        return File(directory, name).apply { writeBytes(bytes) }.absolutePath
    }

    private fun documentMimeType(name: String): String = when {
        name.endsWith(".html", true) || name.endsWith(".htm", true) -> "text/html"
        name.endsWith(".txt", true) || name.endsWith(".md", true) -> "text/plain"
        name.endsWith(".csv", true) -> "text/csv"
        name.endsWith(".json", true) -> "application/json"
        name.endsWith(".xml", true) -> "application/xml"
        name.endsWith(".pdf", true) -> "application/pdf"
        name.endsWith(".docx", true) -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        name.endsWith(".xlsx", true) -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        name.endsWith(".pptx", true) -> "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        name.endsWith(".zip", true) -> "application/zip"
        else -> "application/octet-stream"
    }

    private fun readBundledOriginal(relativePath: String): ByteArray {
        val normalized = relativePath.replace('\\', '/').trimStart('/')
        if (normalized.isBlank() || normalized.split('/').any { it.isBlank() || it == "." || it == ".." }) {
            throw IllegalArgumentException("原图路径不安全")
        }
        return assets.open("pindou_originals/$normalized").use { it.readBytes() }
    }

    private fun openExternalUrl(value: String): Boolean {
        val uri = Uri.parse(value)
        if (uri.scheme !in setOf("http", "https", "mqqwpa", "weixin")) {
            throw IllegalArgumentException("不支持的链接类型")
        }
        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
        }
        if (intent.resolveActivity(packageManager) == null) return false
        startActivity(intent)
        return true
    }
}

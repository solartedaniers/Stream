package com.example.stream

import android.content.ContentValues
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val storageChannelName = "download_manager/storage"
    private val publishFileMethod = "publishFileToDownloads"
    private val sourcePathArgument = "sourcePath"
    private val fileNameArgument = "fileName"
    private val copyBufferSize = 65536

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            storageChannelName
        ).setMethodCallHandler { call, result ->
            if (call.method != publishFileMethod) {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val sourcePath = call.argument<String>(sourcePathArgument)
            val fileName = call.argument<String>(fileNameArgument)
            if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
                result.error("INVALID_ARGUMENTS", "Missing file arguments", null)
                return@setMethodCallHandler
            }

            try {
                val publishedReference = publishFileToDownloads(sourcePath, fileName)
                result.success(publishedReference)
            } catch (error: Exception) {
                result.error("PUBLISH_FAILED", error.message, null)
            }
        }
    }

    private fun publishFileToDownloads(sourcePath: String, fileName: String): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            publishWithMediaStore(sourcePath, fileName)
        } else {
            publishWithPublicDirectory(sourcePath, fileName)
        }
    }

    private fun publishWithMediaStore(sourcePath: String, fileName: String): String {
        val sourceFile = File(sourcePath)
        val resolver = applicationContext.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, resolveMimeType(fileName))
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Could not create Downloads entry")

        resolver.openOutputStream(uri)?.use { outputStream ->
            FileInputStream(sourceFile).use { inputStream ->
                inputStream.copyTo(outputStream, copyBufferSize)
            }
        } ?: throw IllegalStateException("Could not open Downloads output stream")

        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return uri.toString()
    }

    private fun publishWithPublicDirectory(sourcePath: String, fileName: String): String {
        val sourceFile = File(sourcePath)
        val downloadsDirectory = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS
        )
        if (!downloadsDirectory.exists()) {
            downloadsDirectory.mkdirs()
        }

        val outputFile = File(downloadsDirectory, fileName)
        FileInputStream(sourceFile).use { inputStream ->
            FileOutputStream(outputFile).use { outputStream ->
                inputStream.copyTo(outputStream, copyBufferSize)
            }
        }

        MediaScannerConnection.scanFile(
            applicationContext,
            arrayOf(outputFile.absolutePath),
            arrayOf(resolveMimeType(fileName)),
            null
        )
        return outputFile.absolutePath
    }

    private fun resolveMimeType(fileName: String): String {
        val extension = fileName.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: "application/octet-stream"
    }
}

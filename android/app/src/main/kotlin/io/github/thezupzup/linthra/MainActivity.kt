package io.github.thezupzup.linthra

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.media.audiofx.Visualizer
import android.net.Uri
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.hypot

class MainActivity : AudioServiceActivity() {
    private val displayRefreshRate by lazy { DisplayRefreshRate(this) }
    private val launcherIconChannel by lazy { LauncherIconChannel(applicationContext) }
    private val shareChannel by lazy { ShareChannel(this) }
    private val networkStatusChannel by lazy { NetworkStatusChannel(applicationContext) }
    private val installHistoryChannel by lazy { InstallHistoryChannel(applicationContext) }
    private val audioCapabilitiesChannel by lazy { AudioCapabilitiesChannel() }
    private val safDocumentScanner by lazy { SafDocumentScanner(applicationContext) }
    private val androidMediaLibraryChannel by lazy { AndroidMediaLibraryChannel(this) }
    private val localNetworkPermissionChannel by lazy { LocalNetworkPermissionChannel(this) }
    private val androidUserCaChannel by lazy { AndroidUserCaChannel() }

    private var visualizer: Visualizer? = null
    @Volatile private var latestBands: DoubleArray = DoubleArray(32)
    private var askedAudioPermission = false

    override fun onResume() {
        super.onResume()
        displayRefreshRate.onResume()
    }

    override fun onPause() {
        displayRefreshRate.onPause()
        super.onPause()
    }

    override fun onDestroy() {
        stopCavaVisualizer()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, SAF_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFolderTree" -> startFolderPick(result)
                "listAudioDocuments" -> {
                    val treeUri = call.argument<String>("treeUri")
                    if (treeUri == null) result.error("bad_args", "treeUri is required", null)
                    else safDocumentScanner.listAudioDocuments(treeUri, result)
                }
                "cancelScan" -> {
                    safDocumentScanner.cancelScan()
                    result.success(null)
                }
                "hasPersistedPermission" -> {
                    val treeUri = call.argument<String>("treeUri")
                    if (treeUri == null) result.error("bad_args", "treeUri is required", null)
                    else result.success(safDocumentScanner.hasPersistedPermission(treeUri))
                }
                "readSidecarText" -> {
                    val uri = call.argument<String>("uri")
                    val extension = call.argument<String>("extension")
                    if (uri == null || extension == null) result.error("bad_args", "uri and extension are required", null)
                    else result.success(safDocumentScanner.readSidecarText(uri, extension))
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, CAVA_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    startCavaVisualizer()
                    result.success(visualizer != null)
                }
                "stop" -> {
                    stopCavaVisualizer()
                    result.success(null)
                }
                "getBands" -> result.success(latestBands.toList())
                else -> result.notImplemented()
            }
        }

        androidMediaLibraryChannel.configure(messenger)
        localNetworkPermissionChannel.configure(messenger)
        androidUserCaChannel.configure(messenger)
        networkStatusChannel.configure(messenger)
        installHistoryChannel.configure(messenger)
        audioCapabilitiesChannel.configure(messenger)

        MethodChannel(messenger, LauncherIconChannel.CHANNEL).setMethodCallHandler { call, result ->
            launcherIconChannel.handle(call, result)
        }
        MethodChannel(messenger, ShareChannel.CHANNEL).setMethodCallHandler { call, result ->
            shareChannel.handle(call, result)
        }
    }

    private fun startCavaVisualizer() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        ) {
            if (!askedAudioPermission) {
                askedAudioPermission = true
                requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_CODE_RECORD_AUDIO)
            }
            return
        }
        if (visualizer != null) return
        try {
            val vis = Visualizer(0)
            vis.captureSize = Visualizer.getCaptureSizeRange()[1]
            vis.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                override fun onWaveFormDataCapture(v: Visualizer?, waveform: ByteArray?, samplingRate: Int) {}
                override fun onFftDataCapture(v: Visualizer?, fft: ByteArray?, samplingRate: Int) {
                    if (fft == null || fft.size < 4) return
                    val bins = fft.size / 2
                    val maxBin = minOf(bins, 64)
                    val out = DoubleArray(32)
                    for (b in 0 until 32) {
                        val idx = (b * maxBin) / 32
                        val r = fft[idx * 2].toDouble()
                        val im = fft[idx * 2 + 1].toDouble()
                        val mag = hypot(r, im)
                        val boost = 1.0 + (b / 32.0) * 1.4
                        out[b] = ((mag / 64.0) * boost).coerceIn(0.0, 1.0)
                    }
                    latestBands = out
                }
            }, Visualizer.getMaxCaptureRate() / 2, false, true)
            vis.enabled = true
            visualizer = vis
        } catch (_: Exception) {
            visualizer = null
        }
    }

    private fun stopCavaVisualizer() {
        try {
            visualizer?.enabled = false
            visualizer?.release()
        } catch (_: Exception) {}
        visualizer = null
        latestBands = DoubleArray(32)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode == REQUEST_CODE_RECORD_AUDIO) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                startCavaVisualizer()
            }
            return
        }
        if (androidMediaLibraryChannel.onRequestPermissionsResult(requestCode, grantResults)) return
        if (localNetworkPermissionChannel.onRequestPermissionsResult(requestCode)) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    private fun startFolderPick(result: MethodChannel.Result) {
        if (pendingFolderPickResult != null) {
            result.error("pick_in_progress", "A folder pick is already in progress.", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        try {
            pendingFolderPickResult = result
            startActivityForResult(intent, REQUEST_CODE_PICK_FOLDER)
        } catch (e: ActivityNotFoundException) {
            pendingFolderPickResult = null
            result.error("no_picker", "No folder chooser is available.", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_CODE_PICK_FOLDER) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val treeUri: Uri? = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (treeUri != null) {
            try {
                contentResolver.takePersistableUriPermission(treeUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (_: SecurityException) {}
        }
        val result = pendingFolderPickResult
        pendingFolderPickResult = null
        result?.success(treeUri?.toString())
    }

    companion object {
        private var pendingFolderPickResult: MethodChannel.Result? = null
        private const val SAF_CHANNEL = "io.github.thezupzup.linthra/saf"
        private const val CAVA_CHANNEL = "io.github.thezupzup.linthra/cava_visualizer"
        private const val REQUEST_CODE_PICK_FOLDER = 0x5AF0
        private const val REQUEST_CODE_RECORD_AUDIO = 0x5AF1
    }
}

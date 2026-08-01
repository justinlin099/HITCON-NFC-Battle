package org.hitcon.nfcbattle

import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.IntentFilter
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.os.Build
import android.os.PatternMatcher
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingNfcUid: String? = null
    private var pendingWasNfcIntent = false
    private var tagMaintenanceMode = false
    private var activityResumed = false
    private val nfcAdapter: NfcAdapter? by lazy {
        NfcAdapter.getDefaultAdapter(this)
    }

    override fun onResume() {
        super.onResume()
        activityResumed = true
        if (!tagMaintenanceMode) {
            enableNfcForegroundDispatch()
        }
    }

    override fun onPause() {
        activityResumed = false
        disableNfcForegroundDispatch()
        super.onPause()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        captureLaunchIntent(intent)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hitcon_nfc_battle/nfc_intent",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "takeNfcLaunch" -> {
                    result.success(
                        mapOf(
                            "uid" to (pendingNfcUid ?: ""),
                            "isNfcIntent" to pendingWasNfcIntent,
                            "hasEvidence" to true,
                        ),
                    )
                    pendingNfcUid = null
                    pendingWasNfcIntent = false
                }
                "takeNfcUid" -> {
                    result.success(pendingNfcUid)
                    pendingNfcUid = null
                    pendingWasNfcIntent = false
                }
                "setTagMaintenanceMode" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    tagMaintenanceMode = enabled
                    if (enabled) {
                        disableNfcForegroundDispatch()
                    } else if (activityResumed) {
                        enableNfcForegroundDispatch()
                    }
                    Log.d("HitconNfcIntent", "tagMaintenanceMode=$enabled")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hitcon_nfc_battle/app_actions",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openEmailApp" -> result.success(openEmailApp())
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        captureLaunchIntent(intent)
        super.onNewIntent(intent)
        setIntent(intent)
    }

    private fun captureLaunchIntent(intent: Intent?) {
        val uid = extractNfcUid(intent)
        pendingWasNfcIntent = isNfcIntent(intent)
        pendingNfcUid = if (pendingWasNfcIntent) uid else null
        Log.d(
            "HitconNfcIntent",
            "action=${intent?.action} extras=${intent?.extras?.keySet()} " +
                "nfc=$pendingWasNfcIntent uid=${pendingNfcUid ?: "<none>"}",
        )
    }

    private fun isNfcIntent(intent: Intent?): Boolean {
        if (intent == null) {
            return false
        }
        val hasNfcPayload =
            intent.hasExtra(NfcAdapter.EXTRA_TAG) ||
                intent.hasExtra(NfcAdapter.EXTRA_ID) ||
                intent.hasExtra(NfcAdapter.EXTRA_NDEF_MESSAGES)
        return hasNfcPayload || when (intent.action) {
            NfcAdapter.ACTION_NDEF_DISCOVERED,
            NfcAdapter.ACTION_TAG_DISCOVERED,
            NfcAdapter.ACTION_TECH_DISCOVERED -> true
            else -> false
        }
    }

    private fun enableNfcForegroundDispatch() {
        val adapter = nfcAdapter ?: return
        if (!adapter.isEnabled) {
            return
        }

        val pendingIntentFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE
            } else {
                0
            }
        val dispatchIntent = Intent(this, javaClass).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            dispatchIntent,
            pendingIntentFlags,
        )
        val filters = arrayOf(
            buildNfcUrlFilter(NfcAdapter.ACTION_NDEF_DISCOVERED),
            buildNfcUrlFilter(Intent.ACTION_VIEW),
        )

        try {
            adapter.enableForegroundDispatch(this, pendingIntent, filters, null)
        } catch (error: IllegalStateException) {
            Log.w("HitconNfcIntent", "Unable to enable foreground dispatch", error)
        }
    }

    private fun disableNfcForegroundDispatch() {
        val adapter = nfcAdapter ?: return
        try {
            adapter.disableForegroundDispatch(this)
        } catch (error: IllegalStateException) {
            Log.w("HitconNfcIntent", "Unable to disable foreground dispatch", error)
        }
    }

    private fun buildNfcUrlFilter(action: String): IntentFilter {
        return IntentFilter(action).apply {
            addCategory(Intent.CATEGORY_DEFAULT)
            addCategory(Intent.CATEGORY_BROWSABLE)
            addDataScheme("https")
            addDataAuthority("game.hitcon2026.online", null)
            addDataPath("/b", PatternMatcher.PATTERN_PREFIX)
        }
    }

    private fun openEmailApp(): Boolean {
        val emailIntent = Intent.makeMainSelectorActivity(
            Intent.ACTION_MAIN,
            Intent.CATEGORY_APP_EMAIL,
        )
        return try {
            startActivity(emailIntent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    @Suppress("DEPRECATION")
    private fun extractNfcUid(intent: Intent?): String? {
        if (intent == null) {
            return null
        }
        val tag = intent.getParcelableExtra(NfcAdapter.EXTRA_TAG) as? Tag
        val identifier = tag?.id ?: intent.getByteArrayExtra(NfcAdapter.EXTRA_ID)
        return identifier?.toUidString()
    }

    private fun ByteArray.toUidString(): String {
        return joinToString(":") { byte -> "%02X".format(byte.toInt() and 0xFF) }
    }
}

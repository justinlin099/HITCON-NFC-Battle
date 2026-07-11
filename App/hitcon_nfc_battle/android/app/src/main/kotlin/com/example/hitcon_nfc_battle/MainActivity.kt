package com.example.hitcon_nfc_battle

import android.content.Intent
import android.content.ActivityNotFoundException
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingNfcUid: String? = null
    private var pendingWasNfcIntent = false

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

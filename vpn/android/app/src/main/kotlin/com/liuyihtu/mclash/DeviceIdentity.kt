package com.liuyihtu.mclash

import android.content.Context
import android.os.Build
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.UUID

internal data class DeviceRegistration(
    val json: String,
    val fingerprint: String,
    val installationId: String,
    val createdAtEpochSeconds: Long,
)

internal object DeviceIdentity {
    private const val KEY_ALIAS = "mclash_device_binding_v1"
    private const val PREFS_NAME = "mclash_device_binding"
    private const val PREF_INSTALLATION_ID = "installation_id_v1"
    private const val PREF_CREATED_AT = "created_at_epoch_seconds_v1"
    private const val PREF_NONCE = "registration_nonce_v1"
    private const val FORMAT = "mclash-device-registration"
    private const val CANONICALIZATION = "MCLASH-DEVICE-REGISTRATION-V1"

    fun createRegistration(context: Context): DeviceRegistration {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val installationId = prefs.getString(PREF_INSTALLATION_ID, null)
            ?: UUID.randomUUID().toString().also {
                prefs.edit().putString(PREF_INSTALLATION_ID, it).apply()
            }
        val createdAt = prefs.getLong(PREF_CREATED_AT, 0L).takeIf { it > 0L }
            ?: (System.currentTimeMillis() / 1000L).also {
                prefs.edit().putLong(PREF_CREATED_AT, it).apply()
            }
        val nonce = prefs.getString(PREF_NONCE, null)
            ?: randomNonce().also { prefs.edit().putString(PREF_NONCE, it).apply() }
        val keyPair = loadOrGenerateKeyPair()
        val publicKeyBytes = keyPair.public.encoded
        val fingerprint = sha256Hex(publicKeyBytes)
        val androidId = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ANDROID_ID,
        ).orEmpty()

        val payload = linkedMapOf(
            "version" to "1",
            "packageName" to context.packageName,
            "installationId" to installationId,
            "keyAlias" to KEY_ALIAS,
            "publicKeyAlgorithm" to keyPair.public.algorithm,
            "publicKeyDerBase64" to Base64.encodeToString(publicKeyBytes, Base64.NO_WRAP),
            "publicKeyFingerprintSha256" to fingerprint,
            "androidIdHashSha256" to sha256Hex(
                (context.packageName + ":" + androidId).toByteArray(StandardCharsets.UTF_8),
            ),
            "createdAtEpochSeconds" to createdAt.toString(),
            "manufacturer" to Build.MANUFACTURER.orEmpty(),
            "model" to Build.MODEL.orEmpty(),
            "sdkInt" to Build.VERSION.SDK_INT.toString(),
            "nonce" to nonce,
        )
        val canonical = buildCanonicalPayload(payload)
        val signature = Signature.getInstance("SHA256withECDSA").run {
            initSign(keyPair.private)
            update(canonical.toByteArray(StandardCharsets.UTF_8))
            sign()
        }
        val payloadJson = JSONObject().apply {
            payload.forEach { (key, value) ->
                if (key in setOf("version", "createdAtEpochSeconds", "sdkInt")) {
                    put(key, value.toLong())
                } else {
                    put(key, value)
                }
            }
        }
        val root = JSONObject().apply {
            put("format", FORMAT)
            put("version", 1)
            put("payload", payloadJson)
            put(
                "proof",
                JSONObject().apply {
                    put("algorithm", "SHA256withECDSA")
                    put("canonicalization", CANONICALIZATION)
                    put(
                        "canonicalPayloadBase64",
                        Base64.encodeToString(
                            canonical.toByteArray(StandardCharsets.UTF_8),
                            Base64.NO_WRAP,
                        ),
                    )
                    put("signatureBase64", Base64.encodeToString(signature, Base64.NO_WRAP))
                },
            )
        }
        return DeviceRegistration(
            json = root.toString(2),
            fingerprint = fingerprint,
            installationId = installationId,
            createdAtEpochSeconds = createdAt,
        )
    }

    private fun loadOrGenerateKeyPair(): KeyPair {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val privateKey = keyStore.getKey(KEY_ALIAS, null) as? java.security.PrivateKey
        val publicKey = keyStore.getCertificate(KEY_ALIAS)?.publicKey
        if (privateKey != null && publicKey != null) return KeyPair(publicKey, privateKey)

        val generator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_EC,
            "AndroidKeyStore",
        )
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
        )
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setUserAuthenticationRequired(false)
            .build()
        generator.initialize(spec)
        return generator.generateKeyPair()
    }

    private fun buildCanonicalPayload(values: LinkedHashMap<String, String>): String =
        buildString {
            append(CANONICALIZATION).append('\n')
            values.forEach { (key, value) ->
                require(!value.contains('\n') && !value.contains('\r'))
                append(key).append('=').append(value).append('\n')
            }
        }

    private fun randomNonce(): String {
        val bytes = ByteArray(32)
        java.security.SecureRandom().nextBytes(bytes)
        return Base64.encodeToString(bytes, Base64.NO_WRAP or Base64.URL_SAFE)
    }

    private fun sha256Hex(data: ByteArray): String =
        MessageDigest.getInstance("SHA-256")
            .digest(data)
            .joinToString("") { "%02x".format(it) }
}

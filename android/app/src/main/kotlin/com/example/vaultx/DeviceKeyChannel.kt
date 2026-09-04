package com.example.vaultx

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Protects the vault's device key with a hardware-backed Android Keystore key
 * that cannot be used without a fresh biometric authentication.
 *
 * This exists to replace VaultX v3's approach, which stored the user's raw PIN
 * in secure storage so that biometric unlock could re-derive the vault key.
 * That made "the key is never persisted" untrue: anyone who extracted the
 * keystore entry recovered the PIN and therefore the whole vault.
 *
 * Here the PIN is never stored. Instead:
 *
 *  1. Dart generates a random 32-byte device key and hands it over once.
 *  2. It is encrypted under a Keystore AES-256-GCM key created with
 *     `setUserAuthenticationRequired(true)` and a zero validity window, so
 *     *every* use demands a new authentication.
 *  3. Only the wrapped blob is stored. Recovering the device key requires a
 *     live biometric match, enforced by the TEE rather than by app code.
 *
 * The authentication is bound to the cipher through `BiometricPrompt`'s
 * `CryptoObject`. A patched app that skips the prompt still cannot use the key,
 * because the keystore refuses the operation without an authenticated session.
 * v3 treated the biometric result as a boolean and then read the PIN, which a
 * hooked build could simply force to `true`.
 */
class DeviceKeyChannel(private val activity: FragmentActivity) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "vaultx/device_key"

        private const val ALIAS = "vaultx.device_key.v4"
        private const val KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val TAG_BITS = 128
        private const val DEVICE_KEY_BYTES = 32
        private const val AUTHENTICATORS = BiometricManager.Authenticators.BIOMETRIC_STRONG
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(isSupported())
            "hasKey" -> result.success(loadKey() != null)
            "enrol" -> enrol(result)
            "unwrap" -> unwrap(call, result)
            "destroy" -> destroy(result)
            else -> result.notImplemented()
        }
    }

    /** True when the device has usable strong biometrics enrolled. */
    private fun isSupported(): Boolean =
        BiometricManager.from(activity).canAuthenticate(AUTHENTICATORS) ==
            BiometricManager.BIOMETRIC_SUCCESS

    /**
     * Creates the keystore key, generates a fresh device key, and returns it
     * alongside its wrapped form. The caller stores the wrapped blob and adds
     * the raw key to the vault keyring, then discards the raw key.
     */
    private fun enrol(result: MethodChannel.Result) {
        if (!isSupported()) {
            result.error("unsupported", "No strong biometric is enrolled.", null)
            return
        }
        val deviceKey = ByteArray(DEVICE_KEY_BYTES).also { SecureRandom().nextBytes(it) }
        try {
            deleteKey() // never silently reuse an older key
            val cipher = Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.ENCRYPT_MODE, createKey())
            }
            authenticate(
                cipher = cipher,
                title = "Enable biometric unlock",
                onSuccess = { authenticated ->
                    try {
                        val wrapped = authenticated.doFinal(deviceKey)
                        result.success(
                            mapOf(
                                "deviceKey" to encode(deviceKey),
                                "wrapped" to encode(wrapped),
                                "iv" to encode(authenticated.iv)
                            )
                        )
                    } catch (e: Exception) {
                        result.error("wrap_failed", e.message, null)
                    } finally {
                        deviceKey.fill(0)
                    }
                },
                onError = { code, message ->
                    deviceKey.fill(0)
                    result.error(code, message, null)
                }
            )
        } catch (e: Exception) {
            deviceKey.fill(0)
            result.error("enrol_failed", e.message, null)
        }
    }

    /** Recovers the device key after a successful biometric authentication. */
    private fun unwrap(call: MethodCall, result: MethodChannel.Result) {
        val wrapped = decodeArg(call, "wrapped", result) ?: return
        val iv = decodeArg(call, "iv", result) ?: return

        val key = loadKey()
        if (key == null) {
            result.error("no_key", "Biometric unlock is not enrolled.", null)
            return
        }
        try {
            val cipher = Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, iv))
            }
            authenticate(
                cipher = cipher,
                title = "Unlock VaultX",
                onSuccess = { authenticated ->
                    try {
                        result.success(mapOf("deviceKey" to encode(authenticated.doFinal(wrapped))))
                    } catch (e: Exception) {
                        result.error("unwrap_failed", e.message, null)
                    }
                },
                onError = { code, message -> result.error(code, message, null) }
            )
        } catch (e: KeyPermanentlyInvalidatedException) {
            // Fires when the user adds or removes a fingerprint. The wrapped key
            // is unrecoverable by design; the app must fall back to the PIN and
            // re-enrol rather than pretend biometrics still work.
            deleteKey()
            result.error("key_invalidated", "Biometric enrolment changed.", null)
        } catch (e: Exception) {
            result.error("unwrap_failed", e.message, null)
        }
    }

    private fun destroy(result: MethodChannel.Result) {
        try {
            deleteKey()
            result.success(true)
        } catch (e: Exception) {
            result.error("destroy_failed", e.message, null)
        }
    }

    // ------------------------------------------------------------- internals

    private fun createKey(): SecretKey {
        val spec = KeyGenParameterSpec.Builder(
            ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            // Invalidate the key if biometrics are re-enrolled, so an attacker
            // who adds their own fingerprint cannot inherit access.
            .setInvalidatedByBiometricEnrollment(true)
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    // 0 = authenticate for every single use, no grace window.
                    setUserAuthenticationParameters(
                        0,
                        KeyProperties.AUTH_BIOMETRIC_STRONG
                    )
                } else {
                    @Suppress("DEPRECATION")
                    setUserAuthenticationValidityDurationSeconds(-1)
                }
            }

        // Prefer a discrete security chip when the device has one.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                val generator = KeyGenerator.getInstance(
                    KeyProperties.KEY_ALGORITHM_AES,
                    KEYSTORE
                )
                generator.init(spec.setIsStrongBoxBacked(true).build())
                return generator.generateKey()
            } catch (_: Exception) {
                // No StrongBox on this device; fall through to the TEE.
            }
        }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(spec.setIsStrongBoxBacked(false).build())
        return generator.generateKey()
    }

    private fun loadKey(): SecretKey? = try {
        KeyStore.getInstance(KEYSTORE).apply { load(null) }
            .getKey(ALIAS, null) as? SecretKey
    } catch (_: Exception) {
        null
    }

    private fun deleteKey() {
        try {
            KeyStore.getInstance(KEYSTORE).apply { load(null) }.deleteEntry(ALIAS)
        } catch (_: Exception) {
            // Nothing enrolled; that is the desired end state anyway.
        }
    }

    private fun authenticate(
        cipher: Cipher,
        title: String,
        onSuccess: (Cipher) -> Unit,
        onError: (String, String) -> Unit
    ) {
        // BiometricPrompt can deliver an error after a success in rare races;
        // this guard keeps the MethodChannel result single-use.
        var settled = false

        val prompt = BiometricPrompt(
            activity,
            ContextCompat.getMainExecutor(activity),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    result: BiometricPrompt.AuthenticationResult
                ) {
                    if (settled) return
                    settled = true
                    val authenticated = result.cryptoObject?.cipher
                    if (authenticated == null) {
                        onError("no_cipher", "Authentication returned no cipher.")
                    } else {
                        onSuccess(authenticated)
                    }
                }

                override fun onAuthenticationError(code: Int, message: CharSequence) {
                    if (settled) return
                    settled = true
                    val name = when (code) {
                        BiometricPrompt.ERROR_USER_CANCELED,
                        BiometricPrompt.ERROR_NEGATIVE_BUTTON -> "cancelled"
                        BiometricPrompt.ERROR_LOCKOUT,
                        BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> "lockout"
                        else -> "auth_error"
                    }
                    onError(name, message.toString())
                }
            }
        )

        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle("Your vault key is released only after a biometric match.")
            .setNegativeButtonText("Use PIN")
            .setAllowedAuthenticators(AUTHENTICATORS)
            .setConfirmationRequired(false)
            .build()

        prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }

    private fun decodeArg(
        call: MethodCall,
        name: String,
        result: MethodChannel.Result
    ): ByteArray? {
        val raw = call.argument<String>(name)
        if (raw == null) {
            result.error("bad_args", "Missing \"$name\".", null)
            return null
        }
        return try {
            Base64.decode(raw, Base64.NO_WRAP)
        } catch (e: IllegalArgumentException) {
            result.error("bad_args", "\"$name\" is not valid base64.", null)
            null
        }
    }

    private fun encode(bytes: ByteArray): String = Base64.encodeToString(bytes, Base64.NO_WRAP)
}

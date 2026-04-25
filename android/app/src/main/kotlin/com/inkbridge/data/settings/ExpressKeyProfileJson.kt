package com.inkbridge.data.settings

import com.inkbridge.domain.model.ExpressKey
import com.inkbridge.domain.model.ExpressKeyAction
import com.inkbridge.domain.model.ExpressKeyProfile
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * Hand-rolled JSON encoder/decoder for [ExpressKeyProfile] using `org.json`
 * (Android built-in — no extra dependency).
 *
 * Wire format (one profile):
 * ```
 * {
 *   "id":   "uuid",
 *   "name": "Default",
 *   "keys": [
 *     { "id": 1, "label": "Ctrl",
 *       "action": { "type": "hold",     "keyCode": 0,    "modifiers": 2 } },
 *     { "id": 2, "label": "Undo",
 *       "action": { "type": "shortcut", "keyCode": 0x06, "modifiers": 1 } },
 *     ...
 *   ]
 * }
 * ```
 *
 * The list of profiles is stored as a top-level JSONArray under a single
 * SharedPreferences key.
 */
internal object ExpressKeyProfileJson {

    private const val K_ID = "id"
    private const val K_NAME = "name"
    private const val K_KEYS = "keys"
    private const val K_LABEL = "label"
    private const val K_ACTION = "action"
    private const val K_TYPE = "type"
    private const val K_KEYCODE = "keyCode"
    private const val K_MODIFIERS = "modifiers"
    private const val TYPE_SHORTCUT = "shortcut"
    private const val TYPE_HOLD = "hold"

    fun encodeProfiles(profiles: List<ExpressKeyProfile>): String {
        val array = JSONArray()
        profiles.forEach { array.put(encodeProfile(it)) }
        return array.toString()
    }

    fun decodeProfiles(json: String?): List<ExpressKeyProfile> {
        if (json.isNullOrBlank()) return emptyList()
        return try {
            val array = JSONArray(json)
            (0 until array.length()).map { decodeProfile(array.getJSONObject(it)) }
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private fun encodeProfile(profile: ExpressKeyProfile): JSONObject {
        val obj = JSONObject()
        obj.put(K_ID, profile.id)
        obj.put(K_NAME, profile.name)
        val keys = JSONArray()
        profile.keys.forEach { keys.put(encodeKey(it)) }
        obj.put(K_KEYS, keys)
        return obj
    }

    private fun decodeProfile(obj: JSONObject): ExpressKeyProfile {
        val id = obj.optString(K_ID, UUID.randomUUID().toString())
        val name = obj.optString(K_NAME, "Unnamed")
        val keysArr = obj.getJSONArray(K_KEYS)
        val keys = (0 until keysArr.length()).map { decodeKey(keysArr.getJSONObject(it)) }
        return ExpressKeyProfile(id = id, name = name, keys = keys)
    }

    private fun encodeKey(key: ExpressKey): JSONObject {
        val obj = JSONObject()
        obj.put(K_ID, key.id)
        obj.put(K_LABEL, key.label)
        obj.put(K_ACTION, encodeAction(key.action))
        return obj
    }

    private fun decodeKey(obj: JSONObject): ExpressKey {
        val id = obj.getInt(K_ID)
        val label = obj.optString(K_LABEL, "")
        val action = decodeAction(obj.getJSONObject(K_ACTION))
        return ExpressKey(id = id, label = label, action = action)
    }

    private fun encodeAction(action: ExpressKeyAction): JSONObject {
        val obj = JSONObject()
        return when (action) {
            is ExpressKeyAction.Shortcut -> {
                obj.put(K_TYPE, TYPE_SHORTCUT)
                obj.put(K_KEYCODE, action.keyCode.toInt())
                obj.put(K_MODIFIERS, action.modifiers.toInt())
                obj
            }
            is ExpressKeyAction.ModifierHold -> {
                obj.put(K_TYPE, TYPE_HOLD)
                obj.put(K_KEYCODE, action.keyCode.toInt())
                obj.put(K_MODIFIERS, action.modifiers.toInt())
                obj
            }
        }
    }

    private fun decodeAction(obj: JSONObject): ExpressKeyAction {
        val keyCode = obj.optInt(K_KEYCODE, 0).toUByte()
        val modifiers = obj.optInt(K_MODIFIERS, 0).toUByte()
        return when (obj.optString(K_TYPE, TYPE_SHORTCUT)) {
            TYPE_HOLD -> ExpressKeyAction.ModifierHold(keyCode = keyCode, modifiers = modifiers)
            else      -> ExpressKeyAction.Shortcut(keyCode = keyCode, modifiers = modifiers)
        }
    }
}

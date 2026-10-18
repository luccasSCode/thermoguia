package br.com.thermoguia.thermoguia

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Copiado por tool/setup_platforms.dart. Troca o ícone do app ligando um dos
// activity-alias do AndroidManifest (Padrão, Escuro ou Tingido).
class MainActivity : FlutterActivity() {
    private val aliases = mapOf(
        "padrao" to "LauncherPadrao",
        "escuro" to "LauncherEscuro",
        "tingido" to "LauncherTingido",
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "thermoguia/app_icon").setMethodCallHandler { call, result ->
            when (call.method) {
                "get" -> result.success(current())
                "set" -> {
                    val name = call.argument<String>("name")
                    if (name == null || name !in aliases) {
                        result.error("invalid", "Ícone desconhecido: $name", null)
                    } else {
                        select(name)
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun component(alias: String) = ComponentName(packageName, "$packageName.$alias")

    private fun isEnabled(key: String, alias: String): Boolean =
        when (packageManager.getComponentEnabledSetting(component(alias))) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> false
            else -> key == "padrao" // estado do manifesto
        }

    private fun current(): String = aliases.entries.firstOrNull { isEnabled(it.key, it.value) }?.key ?: "padrao"

    private fun select(name: String) {
        // Liga o novo antes de desligar os outros: o app nunca fica sem ícone.
        packageManager.setComponentEnabledSetting(
            component(aliases.getValue(name)),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        for ((key, alias) in aliases) {
            if (key == name) continue
            packageManager.setComponentEnabledSetting(
                component(alias),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
    }
}

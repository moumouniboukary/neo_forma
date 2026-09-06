package bf.neoforma.neoforma

import android.os.Bundle
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        val splash = installSplashScreen()
        // Quitte le blanc natif dès que Flutter peut peindre la marque.
        splash.setKeepOnScreenCondition { false }
        splash.setOnExitAnimationListener { provider -> provider.remove() }
        super.onCreate(savedInstanceState)
        // Ne pas laisser le splash / immersif masquer heure & batterie.
        WindowCompat.setDecorFitsSystemWindows(window, true)
        window.decorView.post {
            WindowCompat.getInsetsController(window, window.decorView).apply {
                isAppearanceLightStatusBars = true
                isAppearanceLightNavigationBars = true
                show(androidx.core.view.WindowInsetsCompat.Type.systemBars())
            }
        }
    }
}

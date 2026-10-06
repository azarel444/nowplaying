# Now Playing: build steps

1. Install Flutter and the Android SDK (or skip this and use Codemagic, see below).
2. Create the base project so Flutter generates the Gradle files and icons:

       flutter create --org com.conjure --project-name now_playing now_playing

3. Copy everything from this zip into that new `now_playing` folder, overwriting:
   - `pubspec.yaml`
   - `lib/` (replace the whole folder)
   - `android/app/src/main/AndroidManifest.xml`
   - `android/app/src/main/kotlin/com/conjure/now_playing/` (MainActivity.kt, MediaListenerService.kt, BootReceiver.kt)
   - `android/app/src/main/res/mipmap-*` (the app icon)

4. If the build complains about minSdk, open `android/app/build.gradle`
   (or `build.gradle.kts`) and set `minSdk` to 21.

5. Build:

       flutter pub get
       flutter build apk --release

   Many older head units are 32-bit ARM. If the APK won't install or crashes
   on launch, rebuild with:

       flutter build apk --release --target-platform android-arm

   The APK is at `build/app/outputs/flutter-apk/app-release.apk`.

6. Sideload it onto the head unit, open it, tap "Open settings", and turn on
   notification access for Now Playing. Start music in any player.

## Using it
- Tap the screen: controls appear for 5 seconds (theme switch, settings, previous, play/pause, next). A small label shows "live audio" or "simulated" so you can tell which visualizer is running.
- Themes (the first button cycles them): Focused, Side by Side, VHS.
- Settings (gear button): visualizer on/off, sensitivity, ring or bars, bar count, accent colors, VHS strength, background drift and beat pulse, particles, performance mode, night mode, burn-in protection.
- Seek: drag the progress bar in the controls. Tap the album cover to open the player app.
- Online features (settings, need internet): missing album art lookup (iTunes Search) and synced lyrics (LRCLIB). Both fail quietly when offline.
- Launch options (settings): open at boot, open when music starts. Newer Android may also need "Display over other apps" allowed; some head units have their own auto-start manager that must allow the app.
- Swipe left/right: next / previous track.
- The theme you pick is remembered.

## Codemagic (no local install)
Push the finished project folder to GitHub, connect the repo in Codemagic,
choose Flutter App, Android, and build the release APK.

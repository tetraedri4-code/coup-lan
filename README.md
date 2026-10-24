# Coup LAN

The Coup card game for 2–6 players on Android and iOS. One phone hosts the
game and the others join over the same Wi-Fi network (or the host's mobile
hotspot). No internet connection, accounts or servers are needed.

## Build and install

1. Install Flutter (3.24 or newer): https://docs.flutter.dev/get-started/install
   - Android: Android Studio + Android SDK.
   - iOS: a Mac with Xcode, and an Apple ID for signing.
2. In this folder, generate the Android/iOS projects and add network permissions:

   ```
   ./setup.sh
   ```

   (Windows: run `flutter create . --org com.example --project-name coup_lan --platforms android`,
   then add `<uses-permission android:name="android.permission.INTERNET"/>` above
   `<application` in `android/app/src/main/AndroidManifest.xml`.)
3. Plug in a phone and run `flutter run --release`, or build installers:
   - Android: `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`
     (send this file to friends to install).
   - iOS: `open ios/Runner.xcworkspace`, pick your team under *Signing & Capabilities*,
     then run on each iPhone. Sharing with others needs TestFlight or the iPhones
     connected to your Mac.
4. Optional: `flutter test` runs the rules tests.

## Playing

1. Everyone joins the same Wi-Fi, or connects to the host phone's hotspot.
2. Host: enter a name → **Host a game**. The lobby shows the host's IP address.
3. Others: enter a name → tap the room under **Games nearby**, or type the
   host's IP under **Join by IP address**.
4. The host taps **Start game** once 2–6 players are in.

During the game, when someone claims a character or blocks, every other player
who can respond sees **Challenge / Block / Allow** buttons; the action resolves
once everyone has allowed it. The log in the middle shows what happened.

If a player's app disconnects, they reconnect automatically; after an app restart
they can rejoin a running game by joining again with the same name.
Disconnected players are treated as "Allow" in response windows.

## Notes and limitations

- **iPhones and auto-discovery:** iOS blocks UDP broadcast for apps without a
  special Apple entitlement, so on iPhones "Games nearby" may stay empty. Joining
  by IP address always works. iOS asks for *Local Network* permission on first use —
  tap Allow.
- **Keep the host's app open.** If the host switches apps or locks the screen
  for long, the OS pauses the game server. Other players' apps reconnect when the
  host comes back.
- Some guest/office Wi-Fi networks block devices from talking to each other. Use
  a phone hotspot in that case.
- Ports: TCP 4040 (game), UDP 4041 (discovery).

## Rules implemented

Income, Foreign Aid (blocked by Duke), Coup (7 coins, forced at 10+),
Tax (Duke), Assassinate (Assassin, 3 coins, blocked by Contessa),
Steal (Captain, blocked by Captain or Ambassador), Exchange (Ambassador).
Challenges on actions and on blocks; a winning claimant shuffles the revealed
card back and draws a new one; the target can still block after a failed
challenge. Assassination coins are spent when blocked and refunded when the
Assassin claim is successfully challenged. In 2-player games the first player
starts with 1 coin.

## Code layout

```
lib/game/models.dart    roles, actions, phases
lib/game/engine.dart    rules engine (runs only on the host)
lib/net/server.dart     WebSocket game server + UDP announcement, inside the host app
lib/net/client.dart     connection used by every player (host connects to itself)
lib/net/discovery.dart  finds hosted games on the network
lib/ui/                 home, lobby and game table screens
test/engine_test.dart   rules tests
```

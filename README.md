# Heart Dance

Mini-iPhone-App: misst den Puls über **AirPods Pro 3** und sagt dir über die AirPods
**„Schneller“**, wenn du unter deinem Zielbereich liegst, und **„Langsamer“**, wenn du darüber liegst.
Im Zielbereich bleibt es still.

## Voraussetzungen

- Mac mit **Xcode 26** oder neuer
- iPhone mit **iOS 26** oder neuer (iPhone SE 2. oder 3. Generation)
- AirPods Pro 3 (Pulssensor)
- Apple-ID (ein kostenloser Account reicht für dein eigenes Gerät)

## Aufs iPhone bringen

1. Repo klonen und `HeartDance.xcodeproj` in Xcode öffnen.
2. Target **HeartDance** → *Signing & Capabilities*:
   - Unter *Team* deine Apple-ID wählen.
   - Dasselbe für das Target **HeartDanceLiveActivity**.
   - Bundle Identifier: App `de.moien.HeartDance`, Erweiterung `de.moien.HeartDance.LiveActivity`
     (die Erweiterung muss immer mit dem Identifier der App beginnen).
3. iPhone per Kabel anschließen und oben als Ziel auswählen. Auf dem iPhone den
   **Entwicklermodus** aktivieren (Einstellungen → Datenschutz & Sicherheit).
4. ▶︎ (Run) drücken.
5. Beim ersten Start auf dem iPhone: Einstellungen → Allgemein → VPN & Geräteverwaltung →
   deinem Entwicklerzertifikat vertrauen.

> Mit einem kostenlosen Apple-Account läuft die App nach **7 Tagen** ab. Dann einfach
> erneut aus Xcode starten. Mit einem bezahlten Developer-Account (99 €/Jahr) hält sie ein Jahr.

## Benutzung

1. AirPods Pro 3 einsetzen.
2. Zielbereich einstellen (z. B. 120–130 bpm) und wählen, wie oft höchstens eine Ansage kommt.
3. **Start** tippen und den Health-Zugriff erlauben.
4. Die App startet ein Training („Cardio Dance“) und bekommt dabei live den Puls.
   Beim **Stopp** wird das Training in Health gespeichert.

## Aufbau

| Datei | Aufgabe |
|---|---|
| `HeartDance/HeartRateMonitor.swift` | Startet die HealthKit-Workout-Session (`HKWorkoutSession`, ab iOS 26 auf dem iPhone) und liefert den Puls live |
| `HeartDance/VoiceCoach.swift` | Sprachansage „Schneller“ / „Langsamer“, stellt Musik dabei kurz leiser |
| `HeartDance/ContentView.swift` | Oberfläche: Puls, Zielbereich, Start/Stopp |
| `HeartDance/LiveActivityController.swift` | Startet/aktualisiert die Live-Aktivität auf dem Sperrbildschirm |
| `HeartDanceLiveActivity/` | Widget-Erweiterung: Aussehen der Live-Aktivität |
| `Shared/` | Daten, die App und Erweiterung gemeinsam nutzen |
| `Config/Info.plist` | Health-Texte und Hintergrundmodi |
| `Config/HeartDance.entitlements` | HealthKit-Berechtigung |

# Slap Me 👋

MacBook kasana vur, ses çıkar.

Slap Me, MacBook'un yerleşik mikrofonunu kullanarak kasaya yapılan fiziksel darbeleri algılayan bir macOS uygulamasıdır. Vuruşu algıladığında istediğin sesi çalar.

---

## Nasıl Çalışır?

- `AVAudioEngine` ile mikrofonu sürekli dinler
- Her ses buffer'ını analiz eder: RMS, attack/decay süresi, frekans içeriği, süreklilik skoru
- Anlık darbe sesini (kasa vuruşu) konuşma ve çevre sesinden ayırt eder
- Vuruş algılandığında seçili sesi çalar

---

## Özellikler

- Otomatik başlar — uygulama açılınca dinlemeye başlar
- Kendi sesini kaydet ve vuruşa ata
- Birden fazla ses kaydedip aralarında geçiş yap
- Hassasiyet ayarları (eşik, attack süresi, gürültü tabanı vb.)

---

## Çalıştırma

**Gereksinimler:** Flutter SDK ≥ 3.10, macOS, Xcode

```bash
cd mac_tap_detector/example
flutter pub get
flutter run
```

Uygulama ilk açılışta mikrofon izni isteyecek — izin ver.

---

## Proje Yapısı

```
slap_me/
└── mac_tap_detector/         # Flutter plugin
    ├── lib/
    │   └── mac_tap_detector.dart   # Dart API
    ├── macos/
    │   └── Classes/
    │       └── MacTapDetectorPlugin.swift  # Native Swift
    └── example/
        └── lib/
            └── main.dart           # Uygulama UI
```

---

## Plugin API (Hızlı Başlangıç)

```dart
// İzin iste
await MacTapDetector.requestMicrophonePermission();

// Dinlemeye başla
await MacTapDetector.startListening();

// Vuruşları dinle
MacTapDetector.events.listen((event) {
  print('Vuruş! amp=${event.amplitude}');
});

// Ses kaydet
await MacTapDetector.startRecording('benim_sesim');
await MacTapDetector.stopRecording();

// Ses çal
await MacTapDetector.playSound('/path/to/sound.m4a');
```

Detaylı API dokümantasyonu için [`mac_tap_detector/README.md`](mac_tap_detector/README.md) dosyasına bak.

---

## Lisans

MIT

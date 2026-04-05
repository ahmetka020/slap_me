import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mac_tap_detector/mac_tap_detector.dart';

void main() => runApp(const TapDetectorApp());

class TapDetectorApp extends StatelessWidget {
  const TapDetectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Slap Me',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6B00),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFFFF8F0),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A1A3E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFFFF6B00),
          foregroundColor: Colors.white,
        ),
      ),
      home: const HomePage(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Shared detection config
// ─────────────────────────────────────────────────────────────

class DetectorConfig {
  double threshold                = 0.01;
  double cooldownMs               = 200;
  double baselineMultiplier       = 1.8;
  double minimumAbsoluteThreshold = 0.005;
  double attackMsMax              = 50;
  double minPeakToBaselineRatio   = 1.2;
  double decayMsMax               = 300;
  double minHighFreqRatio         = 0.0;
  double maxSpeechContinuityScore = 0.30;
  bool   adaptiveNoiseFloor       = true;
  bool   continuityRejection      = true;
  bool   debugLogs                = false;

  TapDetectorConfig toPluginConfig() => TapDetectorConfig(
    threshold: threshold,
    cooldownMs: cooldownMs.toInt(),
    enableDebugLogs: debugLogs,
    adaptiveNoiseFloorEnabled: adaptiveNoiseFloor,
    baselineMultiplier: baselineMultiplier,
    minimumAbsoluteThreshold: minimumAbsoluteThreshold,
    attackMsMax: attackMsMax.toInt(),
    minPeakToBaselineRatio: minPeakToBaselineRatio,
    decayMsMax: decayMsMax.toInt(),
    minHighFreqRatio: minHighFreqRatio,
    maxSpeechContinuityScore: maxSpeechContinuityScore,
    continuityRejectionEnabled: continuityRejection,
  );
}

// ─────────────────────────────────────────────────────────────
// Home Page
// ─────────────────────────────────────────────────────────────

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {

  final DetectorConfig _cfg = DetectorConfig();

  bool _isListening  = false;
  bool _isRecording  = false;
  bool _tapFlash     = false;

  String?       _selectedPath;
  List<String>  _soundFiles = [];

  StreamSubscription<TapDetectionEvent>? _tapSub;
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulseAnim;

  // ── Lifecycle ──────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut),
    );
    _init();
  }

  @override
  void dispose() {
    _tapSub?.cancel();
    MacTapDetector.stopListening();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final status = await MacTapDetector.requestMicrophonePermission();
    if (status == MicrophonePermissionStatus.granted) {
      await _startListening();
    }
    await _refreshSounds();
  }

  // ── Tap detection ──────────────────────────────────────────

  Future<void> _startListening() async {
    try {
      await MacTapDetector.startListening(_cfg.toPluginConfig());
      _tapSub = MacTapDetector.events.listen(_onTap, onError: (_) {});
      if (mounted) setState(() => _isListening = true);
    } catch (_) {}
  }

  Future<void> _stopListening() async {
    await _tapSub?.cancel();
    _tapSub = null;
    await MacTapDetector.stopListening();
    if (mounted) setState(() => _isListening = false);
  }

  void _onTap(TapDetectionEvent _) {
    // Play selected sound
    if (_selectedPath != null) {
      MacTapDetector.playSound(_selectedPath!);
    }
    // Visual flash + pulse
    _pulseCtrl.forward(from: 0).then((_) => _pulseCtrl.reverse());
    setState(() => _tapFlash = true);
    Future.delayed(const Duration(milliseconds: 350),
        () { if (mounted) setState(() => _tapFlash = false); });
  }

  // ── Recording ──────────────────────────────────────────────

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _beginRecording();
    }
  }

  Future<void> _beginRecording() async {
    // Release mic before recording
    await _stopListening();

    final now  = DateTime.now();
    final name = 'rec_${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';

    await MacTapDetector.startRecording(name);
    if (mounted) setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    await MacTapDetector.stopRecording();
    if (mounted) setState(() => _isRecording = false);
    await _refreshSounds();
    await _startListening();
  }

  // ── Sound management ───────────────────────────────────────

  Future<void> _refreshSounds() async {
    final files = await MacTapDetector.getSoundFiles();
    if (!mounted) return;
    setState(() {
      _soundFiles = files;
      if (_selectedPath != null && !files.contains(_selectedPath)) {
        _selectedPath = null;
      }
    });
  }

  Future<void> _deleteSound(String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sesi sil?'),
        content: Text('"${_soundName(path)}" kalıcı olarak silinecek.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await MacTapDetector.deleteSound(path);
    if (mounted && _selectedPath == path) setState(() => _selectedPath = null);
    await _refreshSounds();
  }

  Future<void> _onConfigChanged() async {
    if (_isListening) await MacTapDetector.updateConfig(_cfg.toPluginConfig());
  }

  // ── Colors ─────────────────────────────────────────────────
  static const _orange  = Color(0xFFFF6B00);
  static const _yellow  = Color(0xFFFFD700);
  static const _navy    = Color(0xFF1A1A3E);
  static const _cream   = Color(0xFFFFF8F0);
  static const _red     = Color(0xFFFF2D2D);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      body: Column(
        children: [
          _header(),
          _tapHero(),
          _soundsSection(),
        ],
      ),
      floatingActionButton: _recordFab(),
    );
  }

  // ── Header ─────────────────────────────────────────────────

  Widget _header() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFF6B00), Color(0xFFFF9500)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          // Logo
          SvgPicture.asset(
            'assets/images/logo.svg',
            height: 52,
            colorFilter: const ColorFilter.mode(
              Colors.white,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 10),
          // Title
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SLAP ME',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  height: 1,
                ),
              ),
              Text(
                'Vur, ses çıkar!',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Status + settings
          _StatusChip(isListening: _isListening, isRecording: _isRecording),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.settings_rounded, color: Colors.white70),
            tooltip: 'Ayarlar',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    SettingsPage(cfg: _cfg, onChanged: _onConfigChanged),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tap hero area ──────────────────────────────────────────

  Widget _tapHero() {
    return Container(
      height: 200,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFF9500), Color(0xFFFFF8F0)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(
        child: ScaleTransition(
          scale: _pulseAnim,
          child: GestureDetector(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Starburst glow
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: _tapFlash ? 160 : 0,
                  height: _tapFlash ? 160 : 0,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _yellow.withValues(alpha: _tapFlash ? 0.35 : 0),
                  ),
                ),
                // Main button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _tapFlash ? _yellow : Colors.white,
                    border: Border.all(
                      color: _tapFlash ? _orange : _orange.withValues(alpha: 0.4),
                      width: 4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _orange.withValues(alpha: _tapFlash ? 0.6 : 0.2),
                        blurRadius: _tapFlash ? 40 : 12,
                        spreadRadius: _tapFlash ? 8 : 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 120),
                      style: TextStyle(
                        fontSize: _tapFlash ? 26 : 20,
                        fontWeight: FontWeight.w900,
                        color: _tapFlash ? _navy : _orange,
                        letterSpacing: 1.5,
                      ),
                      child: Text(_tapFlash ? 'SLAP!' : 'TAP'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Sounds section ─────────────────────────────────────────

  Widget _soundsSection() {
    return Expanded(
      child: Column(
        children: [
          // Section header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _navy,
            ),
            child: Row(
              children: [
                const Icon(Icons.library_music_rounded,
                    color: _yellow, size: 16),
                const SizedBox(width: 8),
                const Text(
                  'SESLER',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),
                if (_selectedPath != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _yellow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      '● AKTİF',
                      style: TextStyle(
                        color: _navy,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // List
          Expanded(child: _soundList()),
        ],
      ),
    );
  }

  Widget _soundList() {
    if (_soundFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🎤', style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text(
              'Henüz ses yok',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _navy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Aşağıdaki butona bas ve sesini kaydet!',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96, top: 4),
      itemCount: _soundFiles.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, indent: 68, color: Colors.grey.shade200),
      itemBuilder: (_, i) {
        final path     = _soundFiles[i];
        final selected = path == _selectedPath;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          color: selected
              ? _orange.withValues(alpha: 0.08)
              : Colors.transparent,
          child: ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: selected ? _orange : _navy.withValues(alpha: 0.07),
                border: selected
                    ? Border.all(color: _yellow, width: 2)
                    : null,
              ),
              child: Icon(
                selected
                    ? Icons.check_rounded
                    : Icons.music_note_rounded,
                color: selected ? Colors.white : _orange,
                size: 22,
              ),
            ),
            title: Text(
              _soundName(path),
              style: TextStyle(
                fontWeight:
                    selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? _orange : _navy,
                fontSize: 14,
              ),
            ),
            subtitle: selected
                ? const Text(
                    '💥 Vuruşta çalar',
                    style: TextStyle(
                      fontSize: 11,
                      color: _orange,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
            onTap: () =>
                setState(() => _selectedPath = selected ? null : path),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _iconBtn(
                  icon: Icons.play_circle_rounded,
                  color: _orange,
                  tooltip: 'Önizle',
                  onTap: () => MacTapDetector.playSound(path),
                ),
                _iconBtn(
                  icon: Icons.delete_rounded,
                  color: _red,
                  tooltip: 'Sil',
                  onTap: () => _deleteSound(path),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }

  // ── Record FAB ─────────────────────────────────────────────

  Widget _recordFab() {
    return FloatingActionButton.extended(
      onPressed: _toggleRecording,
      backgroundColor: _isRecording ? _red : _navy,
      foregroundColor: _isRecording ? Colors.white : _yellow,
      elevation: 6,
      icon: Icon(
          _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
          size: 22),
      label: Text(
        _isRecording ? 'DURDUR' : 'SES KAYDET',
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Status chip widget
// ─────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final bool isListening;
  final bool isRecording;

  const _StatusChip(
      {required this.isListening, required this.isRecording});

  @override
  Widget build(BuildContext context) {
    if (isRecording) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fiber_manual_record, size: 10, color: Colors.white),
            SizedBox(width: 5),
            Text('KAYIT',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1)),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isListening
            ? Colors.white.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isListening
              ? Colors.white.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isListening ? Icons.mic_rounded : Icons.mic_off_rounded,
            size: 12,
            color: isListening ? Colors.white : Colors.white54,
          ),
          const SizedBox(width: 5),
          Text(
            isListening ? 'Dinliyor' : 'Pasif',
            style: TextStyle(
              fontSize: 11,
              color: isListening ? Colors.white : Colors.white54,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Settings Page
// ─────────────────────────────────────────────────────────────

class SettingsPage extends StatefulWidget {
  final DetectorConfig cfg;
  final Future<void> Function() onChanged;

  const SettingsPage(
      {super.key, required this.cfg, required this.onChanged});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  DetectorConfig get c => widget.cfg;

  void _change(VoidCallback fn) {
    setState(fn);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
        backgroundColor: const Color(0xFF1A1A3E),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Eşikler'),
          _slider('Min mutlak eşik', c.minimumAbsoluteThreshold, 0.001, 0.1,
              (v) => _change(() => c.minimumAbsoluteThreshold = v)),
          _slider('Baseline çarpanı', c.baselineMultiplier, 1.0, 8.0,
              (v) => _change(() => c.baselineMultiplier = v)),
          _slider('Min peak/baseline oranı', c.minPeakToBaselineRatio, 1.0, 8.0,
              (v) => _change(() => c.minPeakToBaselineRatio = v)),
          const Divider(height: 24),
          _section('Zamanlama'),
          _slider('Max attack (ms)', c.attackMsMax, 5, 60,
              (v) => _change(() => c.attackMsMax = v)),
          _slider('Max decay (ms)', c.decayMsMax, 20, 300,
              (v) => _change(() => c.decayMsMax = v)),
          _slider('Bekleme süresi (ms)', c.cooldownMs, 50, 1000,
              (v) => _change(() => c.cooldownMs = v)),
          const Divider(height: 24),
          _section('Konuşma Filtresi'),
          _slider('Max konuşma skoru', c.maxSpeechContinuityScore, 0.1, 1.0,
              (v) => _change(() => c.maxSpeechContinuityScore = v)),
          const Divider(height: 24),
          _section('Seçenekler'),
          SwitchListTile(
            title: const Text('Adaptif gürültü tabanı'),
            subtitle: const Text('Ortam sesine göre eşiği otomatik ayarlar'),
            value: c.adaptiveNoiseFloor,
            onChanged: (v) => _change(() => c.adaptiveNoiseFloor = v),
          ),
          SwitchListTile(
            title: const Text('Konuşma reddetme'),
            subtitle: const Text('Sürekli sesleri (konuşma, yazma) filtreler'),
            value: c.continuityRejection,
            onChanged: (v) => _change(() => c.continuityRejection = v),
          ),
          SwitchListTile(
            title: const Text('Debug logları (konsol)'),
            value: c.debugLogs,
            onChanged: (v) => _change(() => c.debugLogs = v),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                c.minimumAbsoluteThreshold = 0.005;
                c.baselineMultiplier = 1.8;
                c.minPeakToBaselineRatio = 1.2;
                c.attackMsMax = 50;
                c.decayMsMax = 300;
                c.cooldownMs = 200;
                c.minHighFreqRatio = 0.0;
                c.maxSpeechContinuityScore = 0.30;
                c.adaptiveNoiseFloor = true;
                c.continuityRejection = true;
                c.debugLogs = false;
              });
              widget.onChanged();
            },
            icon: const Icon(Icons.restore),
            label: const Text('Varsayılanlara sıfırla'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        color: Color(0xFFFF6B00),
        letterSpacing: 1.5,
      ),
    ),
  );

  Widget _slider(String label, double value, double min, double max,
      void Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            Text(
              value.toStringAsFixed(3),
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

String _soundName(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

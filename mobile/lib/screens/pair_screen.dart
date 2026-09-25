import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../link.dart';
import '../theme.dart';
import '../widgets/deck_key.dart';
import 'scan_screen.dart';

/// First run: point the phone at the QR in Dacx on the PC, or type the
/// address and 6-digit code from its Connection card.
class PairScreen extends StatefulWidget {
  const PairScreen({super.key});

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  late final DeckLink _link = LinkScope.read(context);
  late final _address = TextEditingController(text: _link.lastAddress ?? '');
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _connect(PcAddress pc) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await _link.pair(pc);
    if (!mounted) return;
    if (err != null) HapticFeedback.heavyImpact();
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  void _manual() {
    final pc = PcAddress.fromInput(_address.text, _code.text);
    if (pc == null) {
      setState(() => _error = "Enter your PC's address and the 6-digit code.");
      return;
    }
    _connect(pc);
  }

  Future<void> _scan() async {
    final pc = await Navigator.of(context).push<PcAddress>(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (pc == null || !mounted) return;
    _address.text = pc.label;
    _code.text = pc.code;
    await _connect(pc);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth > box.maxHeight && box.maxWidth > 560;
          final intro = _intro(wide);
          final form = _form();
          if (wide) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(children: [
                Expanded(child: Center(child: intro)),
                const SizedBox(width: 40),
                Expanded(child: Center(child: SingleChildScrollView(child: form))),
              ]),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(children: [intro, const SizedBox(height: 36), form]),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _intro(bool wide) {
    final notice = _link.notice;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('DACX', style: capsLabel(color: Deck.text, size: 34).copyWith(letterSpacing: 12)),
        Container(
          width: 9,
          height: 9,
          margin: const EdgeInsets.only(top: 4),
          decoration: const BoxDecoration(color: Deck.accent, shape: BoxShape.circle),
        ),
      ]),
      const SizedBox(height: 10),
      const Text(
        'Your phone, as a Stream Deck for your PC.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Deck.muted, fontSize: 15),
      ),
      if (notice != null) ...[
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Deck.warn.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Deck.warn.withValues(alpha: 0.3)),
          ),
          child: Text(notice, textAlign: TextAlign.center, style: const TextStyle(color: Deck.warn, fontSize: 13)),
        ),
      ],
      SizedBox(height: wide ? 28 : 32),
      SizedBox.square(
        dimension: wide ? 150 : 132,
        child: DeckKey(
          glow: Deck.accent,
          lit: true,
          onTap: _busy ? null : _scan,
          lcd: const BoxDecoration(
            gradient: RadialGradient(radius: 0.9, colors: [Color(0x406D28D9), Deck.lcd]),
          ),
          child: const KeyFace(
            icon: Icon(Icons.qr_code_scanner_rounded, size: 46, color: Deck.text),
            label: 'SCAN QR',
          ),
        ),
      ),
    ]);
  }

  Widget _form() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        const Expanded(child: Divider(color: Color(0xFF1F1F27))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('OR TYPE IT IN', style: capsLabel(size: 10)),
        ),
        const Expanded(child: Divider(color: Color(0xFF1F1F27))),
      ]),
      const SizedBox(height: 22),
      Text('PC ADDRESS', style: capsLabel(size: 10)),
      const SizedBox(height: 8),
      TextField(
        controller: _address,
        enabled: !_busy,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
        autocorrect: false,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        decoration: _field('192.168.1.11'),
      ),
      const SizedBox(height: 18),
      Text('PAIRING CODE', style: capsLabel(size: 10)),
      const SizedBox(height: 8),
      TextField(
        controller: _code,
        enabled: !_busy,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: 14,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        decoration: _field('••••••').copyWith(counterText: ''),
        onChanged: (v) {
          if (v.length == 6 && _address.text.trim().isNotEmpty) _manual();
        },
        onSubmitted: (_) => _manual(),
      ),
      const SizedBox(height: 22),
      _ConnectButton(busy: _busy, onTap: _manual),
      AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: _error == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Deck.danger, height: 1.4)),
              ),
      ),
      const SizedBox(height: 22),
      const Text(
        'Open Dacx on your PC. The address, code and QR are on its Connection card. '
        'Both devices need to be on the same WiFi.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Deck.muted, fontSize: 12.5, height: 1.5),
      ),
    ]);
  }

  InputDecoration _field(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Deck.faint),
        filled: true,
        fillColor: Deck.body,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1F1F27)),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF16161B)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Deck.accent, width: 1.4),
        ),
      );
}

class _ConnectButton extends StatelessWidget {
  const _ConnectButton({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(colors: [Deck.accentDeep, Deck.accent]),
          boxShadow: [BoxShadow(color: Deck.accent.withValues(alpha: busy ? 0.1 : 0.3), blurRadius: 24)],
        ),
        child: busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Text('Connect', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

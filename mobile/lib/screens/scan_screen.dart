import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../link.dart';
import '../theme.dart';
import '../widgets/deck_key.dart';

/// Reads the dacx:// QR from the desktop's Connection card and returns the
/// PC's address to whoever pushed this screen.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _camera = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  bool _foreign = false;

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final pc = PcAddress.fromQr(code.rawValue ?? '');
      if (pc != null) {
        _done = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(pc);
        return;
      }
    }
    if (!_foreign) setState(() => _foreign = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        MobileScanner(
          controller: _camera,
          onDetect: _onDetect,
          errorBuilder: (context, error) => _CameraProblem(error: error),
        ),
        const IgnorePointer(child: CustomPaint(painter: _Viewfinder())),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const BackKey(),
              const Spacer(),
              Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    _foreign
                        ? "That QR isn't from Dacx. Use the one on the Connection card."
                        : 'Point at the QR code in Dacx on your PC',
                    key: ValueKey(_foreign),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _foreign ? Deck.warn : Deck.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      shadows: const [Shadow(blurRadius: 8)],
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Dims everything but a rounded square in the middle, with violet corners.
class _Viewfinder extends CustomPainter {
  const _Viewfinder();

  @override
  void paint(Canvas canvas, Size size) {
    final side = min(size.width, size.height) * 0.62;
    final hole = RRect.fromRectAndRadius(
      Rect.fromCenter(center: size.center(Offset.zero), width: side, height: side),
      const Radius.circular(24),
    );
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(hole)),
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );

    final r = hole.outerRect;
    final arm = side * 0.14;
    final p = Paint()
      ..color = Deck.accent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final (corner, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(corner.dx, corner.dy + dy * arm)
          ..lineTo(corner.dx, corner.dy + dy * 18)
          ..quadraticBezierTo(corner.dx, corner.dy, corner.dx + dx * 18, corner.dy)
          ..lineTo(corner.dx + dx * arm, corner.dy),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_Viewfinder old) => false;
}

class _CameraProblem extends StatelessWidget {
  const _CameraProblem({required this.error});
  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Deck.bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography_rounded, color: Deck.muted, size: 40),
            const SizedBox(height: 16),
            Text(
              denied
                  ? 'Camera access is off. Allow it in Settings, or go back and type the code in.'
                  : "The camera couldn't start. Go back and type the code in instead.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Deck.muted, height: 1.5),
            ),
          ]),
        ),
      ),
    );
  }
}

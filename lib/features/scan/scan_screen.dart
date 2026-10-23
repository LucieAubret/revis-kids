import 'package:flutter/material.dart';

import '../quest/quest_flow_screen.dart';
import 'photo_capture_view.dart';

/// Capture de la feuille de devoir (appareil photo ou, à défaut, un fichier).
class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner mon devoir'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: PhotoCaptureView(
          emptyHint: 'Pose ta feuille bien à plat, avec assez de lumière.',
          confirmLabel: 'Lancer ma quête',
          onConfirm: (bytes, mime) {
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => QuestFlowScreen(photo: bytes, mimeType: mime),
            ));
          },
        ),
      ),
    );
  }
}

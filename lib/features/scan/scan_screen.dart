import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../quest/quest_flow_screen.dart';

/// Capture de la feuille de devoir (appareil photo ou, à défaut, un fichier).
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key, this.picker});

  /// Injectable pour les tests.
  final ImagePicker? picker;

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  late final ImagePicker _picker = widget.picker ?? ImagePicker();
  Uint8List? _photo;
  String _mime = 'image/jpeg';
  String? _message;

  bool get _cameraAvailable {
    if (kIsWeb) return true;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
  }

  Future<void> _capture(ImageSource source) async {
    setState(() => _message = null);
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 2000,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photo = bytes;
        _mime = file.mimeType ?? 'image/jpeg';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _message =
          "Je n'arrive pas à ouvrir la caméra. Choisis plutôt une photo "
          'enregistrée sur cet appareil.');
    }
  }

  void _startQuest() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => QuestFlowScreen(photo: _photo!, mimeType: _mime),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner mon devoir'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: scheme.primary, width: 2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _photo == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.description_outlined,
                                    size: 72, color: scheme.primary),
                                const SizedBox(height: 12),
                                Text(
                                  'Pose ta feuille bien à plat, '
                                  'avec assez de lumière.',
                                  style: text.titleMedium,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            )
                          : Image.memory(_photo!, fit: BoxFit.contain),
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(_message!, style: TextStyle(color: scheme.error)),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      if (_cameraAvailable)
                        FilledButton.icon(
                          onPressed: () => _capture(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_rounded),
                          label: Text(_photo == null
                              ? 'Prendre en photo'
                              : 'Reprendre la photo'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => _capture(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_rounded),
                        label: const Text('Choisir une photo'),
                      ),
                    ],
                  ),
                  if (_photo != null) ...[
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _startQuest,
                      child: const Text('Lancer ma quête'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

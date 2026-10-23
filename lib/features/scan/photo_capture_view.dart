
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

typedef PickedPhoto = ({Uint8List bytes, String mimeType});

/// Prend une photo (caméra ou fichier). Remplaçable dans les tests.
typedef PhotoPicker = Future<PickedPhoto?> Function({required bool camera});

Future<PickedPhoto?> _defaultPicker({required bool camera}) async {
  final file = await ImagePicker().pickImage(
    source: camera ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 2000,
    imageQuality: 85,
  );
  if (file == null) return null;
  return (bytes: await file.readAsBytes(), mimeType: file.mimeType ?? 'image/jpeg');
}

final photoPickerProvider = Provider<PhotoPicker>((ref) => _defaultPicker);

bool get cameraAvailable {
  if (kIsWeb) return true;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };
}

/// Zone de prise de vue : aperçu, boutons photo / fichier et bouton de
/// validation. Utilisée pour le devoir et pour la réponse manuscrite.
class PhotoCaptureView extends ConsumerStatefulWidget {
  const PhotoCaptureView({
    super.key,
    required this.emptyHint,
    required this.confirmLabel,
    required this.onConfirm,
    this.header,
  });

  final String emptyHint;
  final String confirmLabel;
  final void Function(Uint8List bytes, String mimeType) onConfirm;
  final Widget? header;

  @override
  ConsumerState<PhotoCaptureView> createState() => _PhotoCaptureViewState();
}

class _PhotoCaptureViewState extends ConsumerState<PhotoCaptureView> {
  PickedPhoto? _photo;
  String? _message;

  Future<void> _capture({required bool camera}) async {
    setState(() => _message = null);
    try {
      final photo = await ref.read(photoPickerProvider)(camera: camera);
      if (photo == null || !mounted) return;
      setState(() => _photo = photo);
    } catch (_) {
      if (!mounted) return;
      setState(() => _message =
          "Je n'arrive pas à ouvrir la caméra. Choisis plutôt une photo "
          'enregistrée sur cet appareil.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.header != null) ...[
                widget.header!,
                const SizedBox(height: 16),
              ],
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
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                widget.emptyHint,
                                style: text.titleMedium,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : Image.memory(
                          _photo!.bytes,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                "Cette photo n'est pas lisible. Choisis-en une autre.",
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
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
                  if (cameraAvailable)
                    FilledButton.icon(
                      onPressed: () => _capture(camera: true),
                      icon: const Icon(Icons.camera_alt_rounded),
                      label: Text(
                          _photo == null ? 'Prendre en photo' : 'Reprendre la photo'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _capture(camera: false),
                    icon: const Icon(Icons.photo_library_rounded),
                    label: const Text('Choisir une photo'),
                  ),
                ],
              ),
              if (_photo != null) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => widget.onConfirm(_photo!.bytes, _photo!.mimeType),
                  child: Text(widget.confirmLabel),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/prompt.dart';
import '../../data/ai_settings.dart';
import '../quest/quest_flow_screen.dart';
import 'photo_capture_view.dart';

/// Capture de la feuille de devoir (appareil photo ou, à défaut, un fichier),
/// avec une précision pour dire de quel exercice il s'agit.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ai = ref.watch(aiSettingsProvider);
    final notReady = ai.hasValue && !ai.value!.hasKey;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner mon devoir'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: PhotoCaptureView(
          emptyHint: 'Pose ta feuille bien à plat, avec assez de lumière.',
          confirmLabel: 'Lancer la recherche',
          header: notReady ? const _NotReadyBanner() : null,
          footer: TextField(
            controller: _note,
            maxLength: kNoteMaxLength,
            maxLines: 2,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: "De quel exercice s'agit-il ?",
              hintText: 'Exemple : exercice 3 page 45, les fractions',
              prefixIcon: Icon(Icons.edit_note_rounded),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          onConfirm: (bytes, mime) {
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => QuestFlowScreen(
                photo: bytes,
                mimeType: mime,
                note: _note.text,
              ),
            ));
          },
        ),
      ),
    );
  }
}

/// Prévient avant le scan que le moteur IA n'est pas configuré, au lieu de
/// laisser l'enfant découvrir l'erreur après sa photo.
class _NotReadyBanner extends StatelessWidget {
  const _NotReadyBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFC107), width: 2),
      ),
      child: Row(
        children: [
          Icon(Icons.info_rounded, color: scheme.primary),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "La recherche n'est pas encore prête. Demande à un parent de saisir "
              'la clé dans Espace parent, puis Moteur IA.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

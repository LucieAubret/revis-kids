import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/pin_repository.dart';
import 'parent_dashboard.dart';
import 'pin_pad.dart';

const _maxFailures = 5;
const _lockDuration = Duration(seconds: 30);

/// Porte d'entrée de l'espace Parent : création du PIN au premier usage,
/// puis saisie du PIN à chaque ouverture.
class ParentGate extends ConsumerStatefulWidget {
  const ParentGate({super.key});

  @override
  ConsumerState<ParentGate> createState() => _ParentGateState();
}

enum _Step { enter, create, confirm }

class _ParentGateState extends ConsumerState<ParentGate> {
  bool _unlocked = false;
  _Step? _step;
  String? _firstEntry;
  String? _error;
  int _failures = 0;
  DateTime? _lockedUntil;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _locked =>
      _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

  void _lock() {
    _lockedUntil = DateTime.now().add(_lockDuration);
    _failures = 0;
    _timer?.cancel();
    _timer = Timer(_lockDuration, () {
      if (mounted) setState(() => _error = null);
    });
  }

  Future<void> _onPin(String pin, PinRepository repo) async {
    switch (_step!) {
      case _Step.create:
        setState(() {
          _firstEntry = pin;
          _error = null;
          _step = _Step.confirm;
        });
      case _Step.confirm:
        if (pin == _firstEntry) {
          await repo.setPin(pin);
          if (mounted) setState(() => _unlocked = true);
        } else {
          setState(() {
            _firstEntry = null;
            _step = _Step.create;
            _error = 'Les deux codes sont différents. Recommencez.';
          });
        }
      case _Step.enter:
        if (_locked) return;
        if (repo.verify(pin)) {
          setState(() => _unlocked = true);
        } else {
          _failures++;
          setState(() {
            if (_failures >= _maxFailures) {
              _lock();
              _error = 'Trop d\'essais. Réessayez dans 30 secondes.';
            } else {
              _error = 'Code incorrect.';
            }
          });
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) {
      return ParentDashboard(onLock: () => Navigator.of(context).pop());
    }
    final repo = ref.watch(pinRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Espace parent'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: repo.when(
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => const Text("Impossible d'ouvrir l'espace parent."),
              data: (r) {
                _step ??= r.hasPin ? _Step.enter : _Step.create;
                final (title, subtitle) = switch (_step!) {
                  _Step.enter => ('Code parent', 'Saisissez votre code à 4 chiffres.'),
                  _Step.create => (
                      'Créez votre code parent',
                      'Choisissez 4 chiffres que votre enfant ne connaît pas.',
                    ),
                  _Step.confirm => ('Confirmez votre code', 'Saisissez-le une seconde fois.'),
                };
                return PinPad(
                  title: title,
                  subtitle: subtitle,
                  error: _error,
                  enabled: !_locked,
                  onCompleted: (pin) => _onPin(pin, r),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

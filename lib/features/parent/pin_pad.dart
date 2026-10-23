import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pavé numérique à 4 chiffres, utilisable à la souris, au toucher et au clavier.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.title,
    required this.onCompleted,
    this.subtitle,
    this.error,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final String? error;
  final bool enabled;
  final ValueChanged<String> onCompleted;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _digits = '';

  void _add(String d) {
    if (!widget.enabled || _digits.length >= 4) return;
    setState(() => _digits += d);
    if (_digits.length == 4) {
      final pin = _digits;
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        setState(() => _digits = '');
        widget.onCompleted(pin);
      });
    }
  }

  void _back() {
    if (_digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ch = event.character;
    if (ch != null && RegExp(r'^\d$').hasMatch(ch)) {
      _add(ch);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _back();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.title,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 8),
            Text(widget.subtitle!, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 4; i++)
                Container(
                  key: ValueKey('pin-dot-$i'),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _digits.length ? scheme.primary : Colors.transparent,
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 36,
            child: widget.error == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      widget.error!,
                      style: TextStyle(color: scheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['', '0', '<'],
          ])
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final k in row)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: SizedBox(
                      width: 72,
                      height: 60,
                      child: k.isEmpty
                          ? null
                          : FilledButton.tonal(
                              onPressed: widget.enabled
                                  ? () => k == '<' ? _back() : _add(k)
                                  : null,
                              child: k == '<'
                                  ? const Icon(Icons.backspace_outlined)
                                  : Text(
                                      k,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

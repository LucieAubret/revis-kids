import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/quest_theme.dart';
import 'features/home/home_screen.dart';

void main() {
  runApp(const ProviderScope(child: ReviskidsApp()));
}

class ReviskidsApp extends ConsumerWidget {
  const ReviskidsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(questThemeProvider);
    return MaterialApp(
      title: 'Revis · CM1',
      debugShowCheckedModeBanner: false,
      theme: theme.toThemeData(),
      home: const HomeScreen(),
    );
  }
}

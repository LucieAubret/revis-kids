import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revis_kids/core/quest_theme.dart';
import 'package:revis_kids/main.dart';

void main() {
  testWidgets("l'accueil propose le scan, les trois univers et les raccourcis", (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ReviskidsApp()));

    expect(find.text('Scanner mon devoir'), findsOneWidget);
    expect(find.text('Lancer la recherche'), findsOneWidget);
    expect(find.text('Histoire de France'), findsOneWidget);
    expect(find.text('Danse classique'), findsOneWidget);
    expect(find.text('Aventures'), findsOneWidget);
    expect(find.text('Mes exercices'), findsOneWidget);
    expect(find.text('Dictée magique'), findsOneWidget);
  });

  testWidgets("toucher un univers le choisit et ouvre sa page de missions", (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ReviskidsApp()));

    await tester.ensureVisible(find.text('Danse classique'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Danse classique'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReviskidsApp)),
    );
    expect(container.read(questThemeProvider), QuestTheme.danse);
    expect(find.text('Tes missions'), findsOneWidget);
  });
}

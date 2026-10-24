import 'dart:convert';
import 'dart:typed_data';

import '../core/quest_theme.dart';

/// Exercice de démonstration : énoncé scolaire neutre et défi à écrire.
class DemoExercise {
  const DemoExercise(this.enonce, this.defi);

  final String enonce;
  final String defi;
}

/// De vrais exercices de CM1 pour les notions mises en avant dans les univers
/// et quelques notions très courantes. Les autres notions reçoivent un exercice
/// générique (voir [genericDemoExercise]).
const demoExercises = <String, DemoExercise>{
  // Histoire
  'HI.T1.01': DemoExercise(
    'Explique à quoi sert un château fort au Moyen Âge.',
    'Le seigneur te demande de présenter son château à un visiteur. Écris deux '
        'fonctions d\'un château (par exemple, se protéger), une phrase pour chacune.',
  ),
  'HI.T1.02': DemoExercise(
    'Décris la vie des paysans au Moyen Âge.',
    'Un marchand te demande ce que fait un paysan au fil de l\'année. Cite deux '
        'travaux de paysan et un devoir envers le seigneur ou l\'Église.',
  ),
  'HI.T2.01': DemoExercise(
    'Situe François Ier, Henri IV et Louis XIV et caractérise-les.',
    'Place François Ier, Henri IV et Louis XIV dans l\'ordre de leurs règnes, puis '
        'écris pour chacun un fait qui le caractérise.',
  ),
  'HI.T2.02': DemoExercise(
    'Nomme les trois ordres de la société d\'Ancien Régime.',
    'Sous Louis XIV, la société est divisée en trois ordres. Écris leurs noms et '
        'donne un exemple de personne pour chacun.',
  ),
  'HI.T3.01': DemoExercise(
    'Cite des inventions qui ont permis les grandes explorations.',
    'Pour traverser l\'océan, les navigateurs avaient besoin d\'outils. Cite deux '
        'inventions qui les ont aidés et explique à quoi sert l\'une d\'elles.',
  ),
  'HI.T4.02': DemoExercise(
    'Cite deux événements de 1789 et un droit de la Déclaration.',
    'En 1789, plusieurs événements changent la France. Écris deux événements de '
        'cette année avec leur date, puis un droit énoncé dans la Déclaration.',
  ),
  // Français
  'FR.VOC.01': DemoExercise(
    'Retrouve le sens du mot « pont-levis » grâce au contexte.',
    'Tu lis : « Le chevalier franchit le pont-levis. » Explique comment retrouver '
        'le sens de « pont-levis » avec la phrase, puis donne ta définition.',
  ),
  'FR.ECR.03': DemoExercise(
    'Écris un court récit de quatre à cinq phrases.',
    'Écris un petit récit de 4 à 5 phrases : un jeune écuyer découvre un secret '
        'dans la bibliothèque du château. Relis-toi pour vérifier les accords.',
  ),
  'FR.ORT.02': DemoExercise(
    'Mets ce groupe de mots au pluriel et fais tous les accords.',
    'Écris cette phrase au pluriel : « La danseuse élégante porte un joli '
        'costume brillant. »',
  ),
  'FR.ORT.03': DemoExercise(
    'Accorde le verbe avec son sujet.',
    'Recopie en conjuguant au présent : « Les spectateurs (applaudir) quand la '
        'danseuse (saluer). »',
  ),
  'FR.VOC.02': DemoExercise(
    'Trouve un synonyme et un contraire.',
    'Trouve un synonyme et un contraire du mot « gracieux » pour décrire un '
        'mouvement de danse.',
  ),
  'FR.CON.04': DemoExercise(
    'Conjugue des verbes aux temps étudiés.',
    'Écris le verbe « danser » au futur avec « nous », puis le verbe « aller » à '
        'l\'imparfait avec « elle ».',
  ),
  'FR.CON.01': DemoExercise(
    'Mets la phrase au passé composé.',
    'Mets au passé composé : « Nous mangeons une pomme dans le jardin. »',
  ),
  'FR.GRA.01': DemoExercise(
    'Transforme une phrase déclarative en phrase interrogative.',
    'Transforme en phrase interrogative de deux façons différentes : « Tu viens '
        'à la fête. »',
  ),
  'FR.GRA.02': DemoExercise(
    'Repère le sujet et le verbe d\'une phrase.',
    'Dans la phrase « Dans le jardin, les enfants jouent. », écris le groupe '
        'sujet et le verbe conjugué.',
  ),
  'FR.LEC.03': DemoExercise(
    'Comprends un court texte et réponds aux questions.',
    'Lis ce début de journal : « Jour 3. La tempête a cessé, mais la carte a '
        'disparu. » Qui écrit ? Que s\'est-il passé ? Réponds en deux phrases.',
  ),
  // Mathématiques
  'MA.FRA.03': DemoExercise(
    'Additionne deux fractions de même dénominateur.',
    'Calcule : 3/8 + 2/8. Écris ton calcul, puis le résultat.',
  ),
  'MA.FRA.04': DemoExercise(
    'Calcule une fraction d\'une quantité.',
    'Sur scène, 20 danseuses : les trois quarts portent un tutu rose. Combien de '
        'danseuses portent un tutu rose ?',
  ),
  'MA.ENT.01': DemoExercise(
    'Écris un grand nombre en chiffres.',
    'Écris en chiffres : trois cent douze mille quatre cent cinq.',
  ),
  'MA.DEC.02': DemoExercise(
    'Compare deux nombres décimaux.',
    'Compare 4,5 et 4,25 avec le signe < ou >, puis explique ton choix en une phrase.',
  ),
  'MA.CAL.03': DemoExercise(
    'Calcule mentalement en utilisant une procédure.',
    'Calcule 35 × 5 de tête, puis écris la méthode que tu as utilisée.',
  ),
  'MA.GRA.01': DemoExercise(
    'Convertis et calcule avec des longueurs.',
    'L\'île est à 3 km 250 m de la plage. Écris cette distance en mètres, puis '
        'calcule ce qu\'il reste à parcourir après 1 km 500 m.',
  ),
  'MA.GRA.06': DemoExercise(
    'Calcule une heure de fin à partir d\'une durée.',
    'Le spectacle commence à 18 h 45 et dure 1 h 30. À quelle heure se termine-t-il ?',
  ),
  'MA.GEO.03': DemoExercise(
    'Reconnais des figures à partir de leurs propriétés.',
    'Pour dessiner le plan du château, donne le nom d\'un quadrilatère qui a 4 côtés '
        'égaux et 4 angles droits, puis celui d\'un triangle qui a 2 côtés égaux.',
  ),
  'MA.GEO.05': DemoExercise(
    'Complète une figure pour qu\'elle soit symétrique.',
    'Sur ton cahier quadrillé, trace une droite verticale, dessine une demi-figure '
        '(par exemple une moitié de papillon) à gauche, puis complète-la pour '
        'qu\'elle soit symétrique.',
  ),
  'MA.GEO.07': DemoExercise(
    'Décris un déplacement avec un vocabulaire précis.',
    'Sur le quadrillage, écris le programme de déplacement pour aller du bateau '
        '(case A1) au coffre (case D3) avec « avancer », « tourner à droite » et '
        '« tourner à gauche ».',
  ),
  // Géographie, sciences, anglais
  'GE.T2.02': DemoExercise(
    'Nomme des aires régionales du monde.',
    'Nomme trois continents ou régions du monde et écris un pays de chacun.',
  ),
  'GE.T3.01': DemoExercise(
    'Associe un moyen de transport à son lieu d\'arrivée.',
    'Associe chaque transport à son lieu : bateau, avion, train ; port, aéroport, '
        'gare. Écris une phrase pour chaque association.',
  ),
  'SC.VIV.03': DemoExercise(
    'Représente une chaîne alimentaire.',
    'Sur l\'île, des lapins mangent de l\'herbe et des renards mangent des lapins. '
        'Écris la chaîne alimentaire avec des flèches.',
  ),
  'SC.MAT.04': DemoExercise(
    'Prévois la taille d\'une ombre.',
    'Un projecteur éclaire un danseur. Si le danseur se rapproche du projecteur, '
        'son ombre sur le mur devient-elle plus grande ou plus petite ? Explique.',
  ),
  'EN.CE.01': DemoExercise(
    'Comprends un court message en anglais.',
    'Lis ce message : « The treasure is under the big palm tree. » Écris en '
        'français où se trouve le trésor.',
  ),
};

/// Exercice de repli pour une notion sans exercice rédigé : il reprend le
/// premier objectif du programme. Il est signalé comme générique.
DemoExercise genericDemoExercise(String titre, String objectif) => DemoExercise(
      'Montre que tu maîtrises : $titre.',
      'Exercice de démonstration générique. Notion : « $titre ». Objectif : '
          '$objectif. Écris sur ton cahier un exemple qui montre ce que tu as compris.',
    );

/// Deux phrases d'ambiance pour mettre l'exercice en scène dans un univers.
String demoScenario(QuestTheme theme) => switch (theme) {
      QuestTheme.histoire =>
        "Le château s'éveille : le seigneur te confie une nouvelle mission. "
            "Les gardes comptent sur toi pour la mener à bien.",
      QuestTheme.danse =>
        "Dans les coulisses du théâtre, le rideau est encore baissé. "
            "La directrice du spectacle te confie une mission avant l'ouverture.",
      QuestTheme.aventures =>
        "Le bateau accoste sur une île inconnue. "
            "La carte du capitaine te réserve une épreuve avant le trésor.",
    };

/// Dictées d'exemple, une par univers (environ 50 mots, niveau CM1).
const demoDictees = <QuestTheme, (String, String)>{
  QuestTheme.histoire: (
    'Le château fort',
    "Au Moyen Âge, les paysans travaillent dans les champs du seigneur. Les "
        "chevaliers défendent le château avec leurs lourdes armures, et les "
        "villageois viennent se réfugier derrière les hauts remparts. Chaque "
        "soir, les cloches de l'église sonnent pour annoncer la fin du travail.",
  ),
  QuestTheme.danse: (
    'Le spectacle de danse',
    "Les petites danseuses répètent leur spectacle depuis plusieurs semaines. "
        "Elles portent de jolis tutus blancs et des chaussons roses. Leur professeur "
        "corrige chaque mouvement avec patience et douceur. Ce soir, le rideau rouge "
        "s'ouvrira et toute la salle applaudira les artistes.",
  ),
  QuestTheme.aventures: (
    "L'île mystérieuse",
    "Les explorateurs ont navigué pendant trois jours avant d'apercevoir l'île "
        "mystérieuse. Ils ont déplié la vieille carte, puis ils ont suivi le "
        "sentier bordé de palmiers. Un grand coffre les attendait au pied d'une "
        "falaise.",
  ),
};

/// Mot-clés de la description de l'élève vers une notion du programme.
const demoKeywords = <(String, String)>[
  (r'fraction', 'MA.FRA.03'),
  (r'd[ée]cimal|virgule', 'MA.DEC.02'),
  (r'nombre|chiffre', 'MA.ENT.01'),
  (r'calcul|mental|multipl', 'MA.CAL.03'),
  (r'sym[ée]tr', 'MA.GEO.05'),
  (r'figure|triangle|carr[ée]|rectangle', 'MA.GEO.03'),
  (r'heure|dur[ée]e', 'MA.GRA.06'),
  (r'distance|longueur|m[èe]tre|mesure', 'MA.GRA.01'),
  (r'accord|pluriel', 'FR.ORT.02'),
  (r'conjug|futur|imparfait|pass[ée] compos', 'FR.CON.04'),
  (r'synonyme|contraire|vocabulaire', 'FR.VOC.02'),
  (r'ch[âa]teau|moyen|seigneur|chevalier', 'HI.T1.01'),
  (r'roi|louis|versailles', 'HI.T2.01'),
  (r'1789|r[ée]volution', 'HI.T4.02'),
  (r'continent|carte|monde', 'GE.T2.02'),
  (r'anglais|english', 'EN.CE.01'),
  (r'cha[îi]ne alimentaire|animaux|plante', 'SC.VIV.03'),
  (r'ombre|lumi[èe]re', 'SC.MAT.04'),
];

/// Petite image blanche : en démo, elle remplace la photo (l'IA simulée ne
/// lit de toute façon pas les photos).
final Uint8List kDemoSamplePhoto = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

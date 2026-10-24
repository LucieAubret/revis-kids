import 'quest_theme.dart';

/// Une mission proposée dans un univers : une notion du programme CM1 et
/// l'accroche qui la met en scène.
class UniverseMission {
  const UniverseMission(this.competenceId, this.hook);

  final String competenceId;
  final String hook;
}

/// Présentation d'un univers : histoire d'introduction et missions choisies
/// dans le programme (français, maths, histoire, géographie, sciences, anglais).
class UniverseInfo {
  const UniverseInfo({required this.pitch, required this.missions});

  final String pitch;
  final List<UniverseMission> missions;
}

const universes = <QuestTheme, UniverseInfo>{
  QuestTheme.histoire: UniverseInfo(
    pitch: "Tu entres au service d'un château du Moyen Âge. De mission en mission, "
        "tu remontes le temps jusqu'à la Révolution, et tu travailles ton français "
        "avec les mots et les histoires de l'époque.",
    missions: [
      UniverseMission('HI.T1.01', 'Visite le château et rencontre le seigneur'),
      UniverseMission('HI.T1.02', 'Une journée au village : paysans, marché et église'),
      UniverseMission('HI.T2.01', 'À la cour des rois : François Ier, Henri IV, Louis XIV'),
      UniverseMission('HI.T2.02', 'Les secrets de Versailles et la société d\'ordres'),
      UniverseMission('HI.T3.01', 'Embarque avec les grands explorateurs'),
      UniverseMission('HI.T4.02', '1789 : le grand bouleversement'),
      UniverseMission('MA.GEO.03', 'Dessine les plans du château : les figures géométriques'),
      UniverseMission('FR.VOC.01', 'Enrichis ton vocabulaire avec les mots d\'autrefois'),
      UniverseMission('FR.ECR.03', 'Écris la chronique d\'un chevalier'),
    ],
  ),
  QuestTheme.danse: UniverseInfo(
    pitch: "Bienvenue dans les coulisses d'un grand théâtre : répétitions, costumes, "
        "lever de rideau. Tu travailles l'orthographe, les mots justes, les fractions "
        "et la symétrie, au rythme du spectacle.",
    missions: [
      UniverseMission('FR.ORT.02', 'Des danseuses élégantes : les accords dans le groupe nominal'),
      UniverseMission('FR.ORT.03', 'Qui danse ? Accorde le sujet et le verbe'),
      UniverseMission('FR.VOC.02', 'Synonymes et contraires pour décrire la scène'),
      UniverseMission('FR.CON.04', 'Conjugue au présent, à l\'imparfait et au futur'),
      UniverseMission('MA.GEO.05', 'Le miroir de la salle de danse : la symétrie'),
      UniverseMission('MA.FRA.04', 'Partage les rangs du ballet : les fractions'),
      UniverseMission('MA.GRA.06', 'Les horaires du spectacle : durées et heures'),
      UniverseMission('SC.MAT.04', 'Les jeux de lumière : ombres et projecteurs'),
    ],
  ),
  QuestTheme.aventures: UniverseInfo(
    pitch: "Cartes, îles et expéditions : tu pars à la recherche d'un trésor. Pour "
        "avancer, il faut te repérer, mesurer les distances, observer la nature et "
        "lire les indices, même en anglais.",
    missions: [
      UniverseMission('GE.T2.02', 'Repère les continents sur le planisphère'),
      UniverseMission('MA.GEO.07', 'Suis la carte au trésor : repérage et déplacements'),
      UniverseMission('MA.GRA.01', 'Mesure la distance jusqu\'à l\'île'),
      UniverseMission('GE.T3.01', 'Comment voyage-t-on autour du monde ?'),
      UniverseMission('SC.VIV.03', 'Les êtres vivants de l\'île et leurs repas'),
      UniverseMission('FR.LEC.03', 'Lis le journal de bord du capitaine'),
      UniverseMission('EN.CE.01', 'Déchiffre un message en anglais'),
    ],
  ),
};

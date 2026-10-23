import 'package:flutter/material.dart';

/// Un matériau est gagné en réussissant des défis d'une matière.
class GameMaterial {
  const GameMaterial({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.matiereId,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final String matiereId;
}

const materials = <GameMaterial>[
  GameMaterial(
    id: 'bois',
    label: 'Bois',
    icon: Icons.forest_rounded,
    color: Color(0xFF9A6B3F),
    matiereId: 'francais',
  ),
  GameMaterial(
    id: 'pierre',
    label: 'Pierre',
    icon: Icons.landscape_rounded,
    color: Color(0xFF7D8794),
    matiereId: 'mathematiques',
  ),
  GameMaterial(
    id: 'brique',
    label: 'Brique',
    icon: Icons.view_module_rounded,
    color: Color(0xFFC4583A),
    matiereId: 'histoire',
  ),
  GameMaterial(
    id: 'verre',
    label: 'Verre',
    icon: Icons.diamond_rounded,
    color: Color(0xFF3CA7D9),
    matiereId: 'geographie',
  ),
  GameMaterial(
    id: 'corde',
    label: 'Corde',
    icon: Icons.anchor_rounded,
    color: Color(0xFFC9A24B),
    matiereId: 'anglais',
  ),
  GameMaterial(
    id: 'metal',
    label: 'Métal',
    icon: Icons.settings_rounded,
    color: Color(0xFF5E6C84),
    matiereId: 'sciences',
  ),
];

GameMaterial materialById(String id) => materials.firstWhere((m) => m.id == id);

GameMaterial materialForMatiere(String matiereId) =>
    materials.firstWhere((m) => m.matiereId == matiereId);

/// Un bâtiment du village, lié à une matière. Il progresse sur 3 niveaux :
/// il faut des matériaux ET avoir réellement maîtrisé des notions.
class Building {
  const Building({
    required this.id,
    required this.name,
    required this.matiereId,
    required this.icon,
    required this.color,
    required this.description,
  });

  final String id;
  final String name;
  final String matiereId;
  final IconData icon;
  final Color color;
  final String description;

  GameMaterial get material => materialForMatiere(matiereId);
}

/// Matériaux nécessaires pour atteindre le niveau 1, 2 puis 3.
const List<int> kBuildingCosts = [5, 10, 20];

/// Compétences « acquises » de la matière exigées pour atteindre le niveau 1, 2, 3.
const List<int> kBuildingMastery = [0, 1, 3];

const int kBuildingMaxLevel = 3;

const buildings = <Building>[
  Building(
    id: 'bibliotheque',
    name: 'Bibliothèque',
    matiereId: 'francais',
    icon: Icons.local_library_rounded,
    color: Color(0xFFB26B3A),
    description: 'Le royaume des mots et des histoires.',
  ),
  Building(
    id: 'tour_horloge',
    name: "Tour de l'horloge",
    matiereId: 'mathematiques',
    icon: Icons.schedule_rounded,
    color: Color(0xFF6B7FD7),
    description: 'Chiffres, formes et calculs malins.',
  ),
  Building(
    id: 'chateau',
    name: 'Château',
    matiereId: 'histoire',
    icon: Icons.castle_rounded,
    color: Color(0xFFD9542B),
    description: 'Rois, reines et grands événements.',
  ),
  Building(
    id: 'observatoire',
    name: 'Observatoire',
    matiereId: 'geographie',
    icon: Icons.travel_explore_rounded,
    color: Color(0xFF2EA6A0),
    description: 'Cartes, pays et paysages du monde.',
  ),
  Building(
    id: 'port',
    name: 'Port',
    matiereId: 'anglais',
    icon: Icons.sailing_rounded,
    color: Color(0xFF3C8DD9),
    description: 'Des bateaux pour voyager en anglais.',
  ),
  Building(
    id: 'laboratoire',
    name: 'Laboratoire',
    matiereId: 'sciences',
    icon: Icons.science_rounded,
    color: Color(0xFF8E5CD0),
    description: 'Expériences, nature et inventions.',
  ),
];

Building buildingById(String id) => buildings.firstWhere((b) => b.id == id);

enum ShopKind { avatar, decor }

class ShopItem {
  const ShopItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.icon,
    required this.price,
  });

  final String id;
  final String name;
  final ShopKind kind;
  final IconData icon;
  final int price;
}

const shopItems = <ShopItem>[
  // Avatars : les deux premiers sont offerts.
  ShopItem(id: 'av_explorateur', name: 'Explorateur', kind: ShopKind.avatar, icon: Icons.face_rounded, price: 0),
  ShopItem(id: 'av_chat', name: 'Chat malin', kind: ShopKind.avatar, icon: Icons.pets_rounded, price: 0),
  ShopItem(id: 'av_robot', name: 'Robot', kind: ShopKind.avatar, icon: Icons.smart_toy_rounded, price: 15),
  ShopItem(id: 'av_fusee', name: 'Fusée', kind: ShopKind.avatar, icon: Icons.rocket_launch_rounded, price: 25),
  ShopItem(id: 'av_chevalier', name: 'Chevalier', kind: ShopKind.avatar, icon: Icons.shield_rounded, price: 30),
  ShopItem(id: 'av_etoile', name: 'Étoile filante', kind: ShopKind.avatar, icon: Icons.auto_awesome_rounded, price: 40),
  // Décors du village.
  ShopItem(id: 'dc_drapeau', name: 'Drapeau', kind: ShopKind.decor, icon: Icons.flag_rounded, price: 8),
  ShopItem(id: 'dc_arbre', name: 'Grand arbre', kind: ShopKind.decor, icon: Icons.park_rounded, price: 10),
  ShopItem(id: 'dc_fleurs', name: 'Jardin fleuri', kind: ShopKind.decor, icon: Icons.local_florist_rounded, price: 15),
  ShopItem(id: 'dc_fontaine', name: 'Fontaine', kind: ShopKind.decor, icon: Icons.water_drop_rounded, price: 20),
  ShopItem(id: 'dc_montgolfiere', name: 'Montgolfière', kind: ShopKind.decor, icon: Icons.air_rounded, price: 30),
];

ShopItem shopItemById(String id) => shopItems.firstWhere((i) => i.id == id);

const defaultAvatarId = 'av_explorateur';

/// Couleurs de fond de l'avatar : toutes gratuites.
const avatarColors = <Color>[
  Color(0xFFFF8A4C),
  Color(0xFFFF7FBF),
  Color(0xFF3CCB8B),
  Color(0xFF5BA8F5),
  Color(0xFF9B7BFF),
  Color(0xFFFFC94A),
];

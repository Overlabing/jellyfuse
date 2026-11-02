# Décisions produit — 2026-11-02 (validées par Antonin)

Plans ui-plan.md + data-plan.md validés tels quels (« seems good je valide »), recos retenues :
- Identité : wordmark jellyfuse, accent violet #8A6CFF → rose #FF5C8A. Icône app à dessiner.
- Navigation : TabView natif tvOS (Accueil, Films, Séries, Recherche, Réglages).
- Ma liste = favoris Jellyfin. PIN de profil local gardé en v1. tvOS 17 minimum.
- Langues v1 : fr + en. Bibliothèques mixtes/perso : masquées en v1.
- Data : progress 10 s + événements immédiats ; mutations offline = rollback + bandeau ;
  persistance disque Accueil seul ; snapshots par profil ; staleness hérités du RN puis mesurés ;
  DirectPlay étendu (mpeg2video, vp8) ; seuils de reprise lus du serveur.

## 2026-11-02 (suite) — multi-plateforme dès la v1 tvOS
Antonin : structurer dès maintenant pour iOS/iPad/macOS, zéro migration plus tard.
- Couche données/LibraryKit : platform-neutre (Foundation seulement), variations par
  paramètre injecté (device profile, stockage), jamais par #if os disséminé.
- DesignSystem : tokens platform-neutres ; métriques de layout tvOS dans une couche
  séparée (injectable) ; API tvOS-only isolées dans des modifiers dédiés.
- Targets SPM déclarés tvOS 17 + iOS 17 + macOS 14 partout où une dépendance ne
  l'empêche pas ; la contrainte Libmpv (binaire tvOS-only aujourd'hui) reste confinée
  à PlayerCore — les futures slices iOS/macOS s'ajoutent à la release MPVKit sans
  toucher au code.
- Seule l'UI finale (Apps/) est par-plateforme, et c'est voulu (UI focus ≠ UI tactile).

## 2026-11-02 (soir) — périmètre et Accueil
- **Pas de musique dans Jellyfuse** (verbatim Antonin). Les bibliothèques musique
  (CollectionType music/musicvideos), livres et photos sont exclues partout :
  shelves, recherche, vues. Jellyfuse = vidéo (movies, tvshows ; mixed masqué v1).
- « Ajouts récents » : UNE shelf par bibliothèque Jellyfin vidéo (ex. « Films — ajouts
  récents », « Séries — ajouts récents »), chacune avec un « Voir tout » en fin de
  rangée ouvrant la grille de la bibliothèque triée par date d'ajout.

## 2026-11-02 — fiche détail : header à la hauteur de la version RN
Antonin : les détails de la fiche film RN ne doivent pas se perdre au reboot —
**header avec image de présentation (backdrop) et TITRE EN IMAGE** (ImageType `Logo`
de Jellyfin, le logo du film/de la série), fallback texte seulement si le serveur n'a
pas de logo. À spécifier dans le lot fiche détail (3.2/3.3) ; la référence visuelle
est l'écran détail de l'app RN (`~/projects/jellyfuse`, features/detail).

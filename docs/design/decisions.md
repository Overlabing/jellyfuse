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

## Métadonnées dans la langue du device — impossible côté Jellyfin (2026-11-02)

Souhait d'Antonin : titres/synopsis dans la langue du device. Vérifié : l'API Jellyfin
n'a pas de langue de métadonnées par requête ni par utilisateur — c'est un réglage par
bibliothèque (preferredMetadataLanguage), demande communautaire ouverte depuis des années.
Décision : l'UI de Jellyfuse suit la langue du device (déjà fait) ; pour les métadonnées,
régler la langue des bibliothèques côté serveur. Pas de contournement applicatif.

## Localisation fr + en — String Catalogs (lot 3.8)

- Un `Localizable.xcstrings` par module qui a des chaînes : l'app (`Apps/Jellyfuse`) et les packages
  `DesignSystem`, `HomePresentation`, `PlaybackEngine` (`PlayerPresentation`, `SettingsKit`, `LibraryKit`,
  `PlayerCore` n'ont aucune chaîne utilisateur). Langue source `fr` (clé = texte français), `en` traduit,
  entrées `fr` explicites pour que `fr.lproj` existe dans chaque bundle.
- Packages : `defaultLocalization: "fr"` dans `Package.swift` ; toute chaîne y est résolue avec
  `bundle: .module` (`String(localized: "…", bundle: .module)`, `Text("…", bundle: .module)`). Un `String(localized:)`
  sans bundle lirait le catalogue de l'app et afficherait le français brut.
- Pas de `project.yml` à toucher : xcodegen embarque le `.xcstrings` de l'app comme ressource, SwiftPM ceux des packages.
- Extraction : le build app n'émet pas les `.stringsdata` par défaut ; pour vérifier qu'aucune clé ne manque,
  `xcodebuild … SWIFT_EMIT_LOC_STRINGS=YES build` puis comparer les `*.stringsdata` aux catalogues.
- Tests : les attentes dépendent de la langue (`tr(fr:en:)` dans `Tests/*/LocalizationSupport.swift`) ;
  lancer `xcodebuild test … -testLanguage fr` ET `-testLanguage en`. Un test par module vérifie que chaque clé a sa traduction.
- Une langue autre que fr/en retombe sur le français (région de développement).
- Ajouter une chaîne : l'écrire en français dans le code, puis ajouter sa traduction `en` dans le catalogue du module.

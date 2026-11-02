# Backlog — nice to have

Demandes validées par Antonin mais non prioritaires. Chaque entrée dit d'où elle vient
et une piste d'implémentation pour ne pas re-réfléchir de zéro.

## Lecteur

- **Sous-titres remontés au-dessus de la seekbar quand l'OSD est visible** (Antonin,
  2026-11-02, « pas prio, nice to have »). Aujourd'hui l'OSD recouvre les sous-titres en
  bas d'écran. Piste : à l'ouverture/fermeture de l'OSD, ajuster la propriété mpv
  `sub-pos` (0–150, 100 = bas) ou `sub-margin-y` via `MpvPlayer.setProperty`, avec une
  valeur calée sur la hauteur de l'OSD ; revenir à la valeur d'origine à la fermeture.
  Comportement du lecteur système/Netflix.

## Accueil

- **Billboard dynamique** (Antonin, 2026-11-02) : le hero de l'Accueil doit refléter la
  carte focusée dans « À suivre » (et idéalement les autres shelves), à la Netflix :
  backdrop + logo + boutons qui changent au fil de la navigation, avec un léger debounce
  (~300 ms) pour ne pas recharger à chaque cran. Toucher HomeView/Billboard +
  @FocusState remonté des cartes.

## Bibliothèques

- **Bibliothèque « Collections » (boxsets)** (Antonin, 2026-11-02) : FAIT au lot 3.5.
  L'allowlist `Library.videoLibraries` inclut `boxsets` (jamais de shelf d'accueil :
  `Library.showsOnHome`). Rangée « Collections » en tête de l'onglet Films (masquée quand un
  filtre ou un saut de lettre est actif, limitée à une page de 120) ; une carte ouvre une
  grille paginée de ses films/séries (tri année croissant), les items ouvrent leur fiche.
  Reste : un « Voir tout » des collections au-delà de 120, une fiche collection avec synopsis.

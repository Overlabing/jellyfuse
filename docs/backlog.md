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

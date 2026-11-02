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

- **Bibliothèque « Collections » (boxsets)** (Antonin, 2026-11-02) : les /UserViews sont
  fetchées dynamiquement mais filtrées par une allowlist movies/tvshows
  (Library.videoLibraries) — les collections Jellyfin sont exclues de la v1. Lot à part :
  étendre l'allowlist à boxsets + shelf dédiée + fiche collection (une collection s'ouvre
  sur ses films, pattern proche de la fiche série sans saisons).

## App / système

- **Top Shelf dynamique** (Antonin, 2026-11-02, validé — à lancer après la vague 3.5-3.7) :
  l'icône Jellyfuse en première rangée du dock doit afficher les posters des médias « À
  reprendre » (resume + next up) au lieu de l'image statique. Implémentation : extension
  TV Top Shelf (TVTopShelfContentProvider, TVTopShelfSectionedContent ou carousel),
  cible xcodegen dédiée + App Group pour partager la session (token Keychain partagé
  access group), fetch resume/nextUp avec les URLs d'images Jellyfin, deep links
  jellyfuse://detail/{id} et jellyfuse://play/{id} (le scheme était prévu dans le plan
  RN) à router dans JellyfuseApp.onOpenURL. Attention signing : entitlements App Group
  sur les DEUX cibles, team 39TMVBW2CY.

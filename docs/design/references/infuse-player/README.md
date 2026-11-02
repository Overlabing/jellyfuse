# Référence : lecteur Infuse (captures Apple TV d'Antonin, 2026-11-02)

Captures 4K prises sur l'Apple TV du salon (Lupin S2E1, HEVC 1080p, Dolby Atmos),
compressées pour le repo. Référence validée par Antonin pour le polish du lecteur
Jellyfuse (lots 3.4x) — « c'est Infuse ».

## Ce qu'on retient par écran

**osd-transport.jpg** — l'OSD de transport :
- hint « Balayez vers le bas pour plus d'informations » centré en HAUT quand l'OSD est visible ;
- bloc bas-gauche : « S2 · E1 - Chapter 1 » en petit AU-DESSUS du titre « Lupin » en gros ;
- barre fine pleine largeur, position courante à gauche SOUS la barre, restant à droite ;
- rangée d'icônes d'accès rapide bas-droite (info, sous-titres, stats, réglages, PiP).

**panel-info.jpg** — onglet Info :
- pilules d'onglets centrées en haut : Info · Vidéo · Audio · Sous-titres (pas d'onglet
  Chapitres séparé : les chapitres sont une ligne de l'onglet Vidéo) ;
- carte translucide (regularMaterial) ancrée en haut ;
- contenu : mini-poster + « Lupin - S2 · E1 - Chapter 1 » + synopsis + LIGNE TECHNIQUE :
  `52 min · 2023 · 611 MB · HEVC (1080p) · Dolby Atmos 5.1 · 0,9 Mbps · 25 fps · genres · FR-12`.

**panel-video.jpg** — onglet Vidéo : deux colonnes OPTIONS (Affichage, Ratio, Décalage
vertical, Chapitres → 35:50, Vitesse, Upscaling IA, Mode ambiant, Stats HUD).

**panel-audio.jpg** — onglet Audio : colonne PISTES (« ✓ Français - Dolby Atmos 5.1
(Par défaut) ») + colonne OPTIONS (Haut-parleur/AirPlay, Dolby Atmos, Délai…).

**panel-subtitles.jpg** — onglet Sous-titres : PISTES (Aucun / ✓ Anglais (Forcés, Par
défaut) / Plus…) + OPTIONS de style (Police, Taille, Couleur, Épaisseur, Contour,
Arrière-plan, Opacité, Alignement vertical).

## Deltas vs notre 3.4b — arbitrages d'Antonin (2026-11-02)
- Icônes d'accès rapide sur l'OSD : **NON, refusé** (« les icônes rapides en bas je n'en veux pas »).
- Glisser vers le bas pour ouvrir le panneau : **OUI** (déjà implémenté chez nous) ; le hint
  texte « Balayez vers le bas pour plus d'informations » : OUI, validé et implémenté sur l'OSD.
- Chapitres : onglet séparé chez nous vs ligne de l'onglet Vidéo chez Infuse — à arbitrer.
- Ligne technique de l'onglet Infos (codec/bitrate/taille/fps) : à ajouter (proposé, pas encore arbitré).
- Layout pistes+options en 2 colonnes : à arbitrer.

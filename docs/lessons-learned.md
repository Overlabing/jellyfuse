# Lessons learned — joueur mpv sur plateformes Apple (hérité de jellyfuse/fusion)

Destination : `docs/lessons-learned.md` du nouveau repo. Source : 6 mois de jellyfuse
(RN) + fork `OverGlass/mpv` (gelé, patches archivés dans `patches.tgz` de la release
`apple/v0.41.0-jf.9-dby1`). Rien ici n'est du code à porter — ce sont les règles et
pièges à ne pas redécouvrir.

## Options mpv qui comptent
- `hwdec=videotoolbox-copy` — le `videotoolbox` nu a eu des bugs de justesse couleur
  (commit Rust `51fec4ba`). Si un jour on repasse en zero-copy, re-valider les couleurs
  sur contenu 10-bit BT.2020.
- `vo=gpu-next` + `gpu-api=vulkan` + `gpu-context=moltenvk` : la seule voie qualité
  (libplacebo : scaling, dithering, tone-mapping HDR). libplacebo n'a PAS de backend
  Metal natif ; MoltenVK est incontournable.
- `cache=yes`, `demuxer-max-bytes=50MiB`, `demuxer-max-back-bytes=25MiB` — défauts
  streaming sains.
- `keep-open=yes` sinon EOF détruit le vo pendant qu'on affiche l'écran « épisode suivant ».
- Trickplay/chapitres/skip-intro = overlays JS/Swift pilotés par `time-pos` observé —
  ne jamais compter sur l'OSD mpv.

## Sous-titres
- **Mapping sid group-aware** : les sous-titres externes sont toujours `sub-add`és ;
  l'ordre réel des sid = pistes embarquées d'abord, externes ensuite — quel que soit
  l'ordre côté Jellyfin. Réimplémenter `computeSubtitleSid` + tests unitaires.
- **Strings canoniques du device profile** : Jellyfin normalise les codecs sous-titres
  (`NormalizeSubtitleCodec`) : c'est `pgs`, PAS `PGSSUB` ; une string fausse tue le
  DirectPlay **silencieusement** (aucun TranscodeReason).
- libass exige la stack freetype/fribidi/harfbuzz/libunibreak — MPVKit l'embarque.

## Audio / session (iOS surtout, à revalider tvOS)
- `ao_coreaudio` historique : qualifiait mal Now Playing ; upstream a `ao_avfoundation`
  (AVSampleBufferAudioRenderer) — MPVKit ne compile pas `-Davfoundation` par défaut :
  si besoin, c'est un flag de build à demander/ajouter, pas un fork.
- Piège iOS : `ao_audiounit` posait `.mixWithOthers` en douce sur l'AVAudioSession ;
  il fallait ré-appliquer la catégorie après chaque changement `audio-params`.
  Sur tvOS : vérifier le comportement équivalent au spike.
- Passthrough bitstream (TrueHD/Atmos) impossible via les AO mpv sur Apple : tout
  décode en PCM multicanal. Limite assumée, documentée utilisateur.

## Lecture / Jellyfin
- Resolver : DirectPlay large (tout ce que ffmpeg lit), DirectStream pour remux
  container, Transcode en dernier recours ; prévoir le fallback transcode **AV1 4K**
  (pas de hw decode sur A15 — dav1d logiciel à mesurer).
- Reporter : chaque report porte `MediaSourceId`, `PlayMethod`, `CanSeek` ;
  start/progress(~10s)/stopped ; queue persistante drainée à la reconnexion.
- Mutations cache : patch optimiste local toujours (offline-correct), invalidation
  seulement sur succès ; répliquer les règles serveur en local plutôt qu'invalider.
- Sélections audio/sous-titres mémorisées : règles server+local du PR jellyfuse #24
  (sync bidirectionnelle, priorité locale).
- Bugs jamais résolus dans l'ancienne app, à traiter nativement : bouton skip-intro,
  autoplay épisode suivant, langue de sous-titres préférée non auto-sélectionnée au load.

## Rendu — pièges MoltenVK/Metal (dossier zero-copy, pertinent seulement au volet iOS/PiP)
- IOSurface importée en VkImage : OPTIMAL + DEVICE_LOCAL uniquement (3 pièges mortels :
  Private sans mémoire liée rejeté iOS 17+ ; LINEAR+HOST_VISIBLE contourne l'IOSurface ;
  bind HOST_VISIBLE crash dans flushToDevice).
- Compression AGX : un render target BGRA8 IOSurface-backed avec
  `allowGPUOptimizedContents=YES` (défaut) sort compressé — illisible par AVSBDL,
  invisible à un IOSurfaceLock CPU. 
- CVMetalTextureCache contourné nécessaire sur iOS 17+ (patch 0022 archivé).
- hwdec_vt_pl + PL_HANDLE_IOSURFACE + patchs MoltenVK (heuristique plan P010, storage
  mode Shared) : archivés, base d'une éventuelle contribution upstream.
- Double-teardown : sous Fabric, `tearDown` pouvait s'exécuter deux fois (JS detach +
  onDropView) → UAF. En UIKit pur le problème disparaît, mais garder l'idempotence du
  teardown par principe (guard `didTearDown`).

## AirPlay (acquis de la branche feat/airplay)
- Les récepteurs AirPlay acceptent du **HTTP en clair** (pas d'exigence HTTPS) ; le
  FigPeerError venait d'un master.m3u8 manquant + absence de HEAD.
- Il faut appeler `player.play()` après `readyToPlay`.
- Rig de vérif : Mac en récepteur AirPlay + Wireshark.
- Le fork avait activé les muxers hls/mp4/mov de ffmpeg pour servir l'AirPlay — si on
  refait de l'AirPlay re-mux local, MPVKit compile-t-il ces muxers ? À vérifier le jour venu.

## Licence / App Store
- GPL interdit App Store même app gratuite+FOSS (code tiers). Stack LGPL : mpv
  `-Dgpl=false`, ffmpeg sans `--enable-gpl`, PAS de libpostproc, pas de smb.
- CI : gate qui échoue si un produit `-GPL` ou un symbole libpostproc entre dans le build.
- FOSS (MIT) satisfait le re-link LGPL §6 de fait ; écran Licences obligatoire.

## Checklist parité codecs (gate de release)
H.264 8-bit, HEVC 8/10-bit (hwdec), HEVC HDR10 + HLG (tone-mapping et/ou EDR), AV1
(dav1d sw — mesurer 1080p/4K), VP9, MPEG2/4 ; audio AAC/AC3/EAC3/DTS/TrueHD/FLAC/Opus
(PCM multicanal) ; subs SRT/ASS (libass)/PGS/VobSub ; containers mkv/mp4/ts/avi ;
pistes multiples + externes. Pertes assumées (déjà actées) : AVS3, Dolby Vision p5
(différé), SMB/BluRay/Lua/uchardet.
